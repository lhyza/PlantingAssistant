import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;
import 'package:planting/core/images.dart';
import 'package:planting/data/models.dart';
import 'package:planting/core/ui_prefs.dart';
import 'package:planting/core/util.dart';
import 'package:planting/data/ai_prompt.dart';
import 'package:planting/data/reminder_group.dart';
import 'package:planting/data/repo.dart';
import 'package:planting/data/transfer.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

String _batchId = '';

Future<Batch> makeBatch(String name, {String? id}) async {
  final crop = (await Repo.instance.defaultCrop())!;
  final b = Batch(
    id: id ?? 'test_batch_1',
    crop: crop.id,
    name: name,
    variety: '红颜',
    // 定植 55 天前 → 稳定落在催花/花芽分化期（9 天），提醒到期日在未来
    plantDate: fmtDay(dateOnly(DateTime.now().subtract(const Duration(days: 55)))),
    location: '阳台',
    potCount: 12,
    color: '#D9534F',
  );
  await Repo.instance.saveBatch(b);
  _batchId = b.id;
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  test('首次启动灌入 4 个作物与种子库', () async {
    final crops = await Repo.instance.crops(includeDisabled: true);
    expect(crops.map((c) => c.name), containsAll(['草莓', '柠檬', '葡萄', '无花果']));
    final strawberry = crops.firstWhere((c) => c.isDefault);
    expect(strawberry.lifeCycle, 'annual');

    final stages = await Repo.instance.stages(strawberry.id);
    expect(stages.length, 10);
    expect(stages.first.name, contains('苗前消毒'));

    final varieties = await Repo.instance.varieties(strawberry.id);
    expect(varieties.length, 20);
    final pests = await Repo.instance.pests(strawberry.id);
    expect(pests.length, 8);
  });

  test('首次启动不带任何示例批次（APK 里是干净的）', () async {
    expect(await Repo.instance.batches(), isEmpty);
    expect(await Repo.instance.records(), isEmpty);
  });

  test('批次/阶段推算/提醒生成均可用', () async {
    final b = await makeBatch('阳台花架');
    expect(b.crop, 'crop_strawberry');
    expect(b.id, _batchId);

    final snap = await Repo.instance.snapshot(b);
    expect(snap.stage!.name, isNotEmpty);
    expect(snap.dayInCycle, greaterThan(0));

    final made = await Repo.instance.generateStageReminders(b);
    expect(made, greaterThanOrEqualTo(0));
    final rs = await Repo.instance.reminders(
      batchId: b.id,
      activeOnly: false,
      includeExpired: true,
    );
    expect(rs, isNotEmpty);
  });

  test('完成提醒后循环提醒顺延、单次提醒失效', () async {
    final b = (await Repo.instance.batch(_batchId))!;
    final r = Reminder(
      id: 'test_r1',
      batchId: b.id,
      kind: '施肥',
      title: '测试施肥',
      intervalDays: 7,
      nextDueAt: '2026-11-20',
      active: true,
      isOneTime: false,
      createdAt: '2026-11-01 08:00:00',
      updatedAt: '2026-11-01 08:00:00',
    );
    await Repo.instance.saveReminder(r);
    final next = await Repo.instance.completeReminder(
      r,
      doneAt: DateTime(2026, 11, 20),
    );
    expect(next, DateTime(2026, 11, 27));
    final after = await Repo.instance.reminder('test_r1');
    expect(after != null && after.active, true);

    final once = Reminder(
      id: 'test_r2',
      batchId: b.id,
      kind: '其他',
      title: '一次性',
      intervalDays: 0,
      nextDueAt: '2026-11-20',
      active: true,
      isOneTime: true,
      createdAt: '2026-11-01 08:00:00',
      updatedAt: '2026-11-01 08:00:00',
    );
    await Repo.instance.saveReminder(once);
    await Repo.instance.completeReminder(once, doneAt: DateTime(2026, 11, 20));
    final afterOnce = await Repo.instance.reminder('test_r2');
    expect(afterOnce!.active, false);
  });

  test('肥料/药品库可增删查，记一笔可带多个产品', () async {
    final f = Supply(
      id: 'test_mat_1',
      kind: 'fertilizer',
      name: '花多多 2 号',
      ratio: '1:1000',
      method: '灌根',
    );
    await Repo.instance.saveMaterial(f);
    final m = Supply(
      id: 'test_mat_2',
      kind: 'medicine',
      name: '代森锰锌',
      ratio: '1:800',
      method: '喷雾（叶背）',
    );
    await Repo.instance.saveMaterial(m);

    final fers = await Repo.instance.materials('fertilizer');
    expect(fers.map((e) => e.name), contains('花多多 2 号'));
    final meds = await Repo.instance.materials('medicine');
    expect(meds.map((e) => e.method), contains('喷雾（叶背）'));

    final r = GardenRecord(id: 'test_rec_1', batchId: _batchId, type: '施肥');
    r.products = [
      RecordProduct(name: '花多多 2 号', dosage: '1:1000', method: '灌根'),
      RecordProduct(name: '海藻精', dosage: '1:2000', method: '灌根'),
    ];
    await Repo.instance.saveRecord(r);
    final saved = (await Repo.instance.records(batchId: _batchId))
        .firstWhere((e) => e.id == 'test_rec_1');
    expect(saved.products.length, 2);
    expect(saved.products.last.name, '海藻精');
  });

  test('自定义品种自动入库且同名复用', () async {
    final crop = (await Repo.instance.defaultCrop())!.id;
    final v1 = await Repo.instance.ensureVariety(crop, '朋友给的苗XYZ');
    final v2 = await Repo.instance.ensureVariety(crop, '朋友给的苗XYZ');
    expect(v1.id, v2.id);
  });


  test('肥料药品可禁用指定作物，记一笔里按作物过滤', () async {
    final crops = await Repo.instance.crops(includeDisabled: true);
    final st = crops.firstWhere((c) => c.isDefault);
    final lemon = crops.firstWhere((c) => c.name == '柠檬');

    final common = Supply(
      id: 'test_scope_1',
      kind: 'fertilizer',
      name: '通用肥A',
      ratio: '1:1000',
      method: '灌根',
    );
    final blocked = Supply(
      id: 'test_scope_2',
      kind: 'fertilizer',
      name: '禁用肥B',
      ratio: '1:500',
      method: '灌根',
    );
    blocked.scope = 'disabled';
    blocked.disabledCrops = [st.id];
    await Repo.instance.saveMaterial(common);
    await Repo.instance.saveMaterial(blocked);

    final forStrawberry = await Repo.instance.materials(
      'fertilizer',
      cropId: st.id,
    );
    expect(forStrawberry.map((e) => e.name), contains('通用肥A'));
    expect(forStrawberry.map((e) => e.name), isNot(contains('禁用肥B')));

    final forLemon = await Repo.instance.materials(
      'fertilizer',
      cropId: lemon.id,
    );
    expect(forLemon.map((e) => e.name), contains('禁用肥B'));
  });

  test('拍照记录单独计数，操作记录不含拍照，可分页', () async {
    if (_batchId.isEmpty) await makeBatch('拍照测试');
    final op = GardenRecord(
      id: 'test_op_for_count',
      batchId: _batchId,
      type: '浇水',
    );
    await Repo.instance.saveRecord(op);
    for (var i = 0; i < 3; i++) {
      final r = GardenRecord(
        id: 'test_photo_$i',
        batchId: _batchId,
        type: '拍照',
        title: '拍照记录',
        date: '2026-11-0${i + 1}',
      );
      r.images = ['images/p$i.jpg'];
      await Repo.instance.saveRecord(r);
    }
    final all = await Repo.instance.records(batchId: _batchId);
    final photos = await Repo.instance.records(batchId: _batchId, photo: true);
    expect(photos.length, 3);
    expect(all.any((e) => e.type == '拍照'), isFalse);

    final total = await Repo.instance.recordCount(batchId: _batchId);
    final photoTotal = await Repo.instance.recordCount(
      batchId: _batchId,
      photo: true,
    );
    expect(photoTotal, 3);
    expect(total, greaterThanOrEqualTo(1));

    final page = await Repo.instance.records(
      batchId: _batchId,
      limit: 2,
      offset: 0,
    );
    final page2 = await Repo.instance.records(
      batchId: _batchId,
      limit: 2,
      offset: 2,
    );
    expect(page.length, 2);
    expect(page2.every((e) => !page.any((p) => p.id == e.id)), isTrue);
  });


  test('盆栽：按数量生成、全部死亡才暂停进度、恢复后扣掉冻结天数', () async {
    final b = await makeBatch('盆栽测试');
    b.potCount = 3;
    await Repo.instance.saveBatch(b);

    var pots = await Repo.instance.pots(b.id);
    expect(pots.length, 3);
    expect(pots.every((e) => e.alive), isTrue);

    // 死一盆：整批仍在生长
    await Repo.instance.setPotState(pots[0], 'dead', note: '烂根');
    var reloaded = (await Repo.instance.batch(b.id))!;
    expect(reloaded.stuntedSince, isNull);
    var st = await Repo.instance.potStats(b.id);
    expect(st.dead, 1);
    expect(st.alive, 2);

    // 再死两盆：全批没有存活 → 暂停
    for (final p in pots.skip(1)) {
      await Repo.instance.setPotState(p, 'dead');
    }
    reloaded = (await Repo.instance.batch(b.id))!;
    expect(reloaded.stuntedSince, isNotNull);
    st = await Repo.instance.potStats(b.id);
    expect(st.allGone, isTrue);

    // 复活一盆：恢复生长（冻结天数累加进 growthOffsetDays）
    final again = await Repo.instance.pots(b.id);
    await Repo.instance.setPotState(again.first, 'alive');
    reloaded = (await Repo.instance.batch(b.id))!;
    expect(reloaded.stuntedSince, isNull);
    expect(reloaded.growthOffsetDays, greaterThanOrEqualTo(0));

    // 减少盆数：不重排，多出来的盆被停用
    b.potCount = 2;
    await Repo.instance.saveBatch(b);
    final left = await Repo.instance.pots(b.id);
    expect(left.map((e) => e.idx).toList(), [1, 2]);
  });

  test('拍照：按盆计数、最近一张、删除记录会清掉图片引用', () async {
    final b = await makeBatch('拍照测试');
    b.potCount = 3;
    b.photoMode = 'pot';
    await Repo.instance.saveBatch(b);

    for (var i = 0; i < 2; i++) {
      final r = GardenRecord(
        id: 'ph_${i}_1',
        batchId: b.id,
        type: '拍照',
        title: '拍照记录',
        date: '2026-11-0${i + 1}',
      );
      r.images = ['images/ph_${i}_1.png'];
      r.potIndex = 1;
      r.imgW = 1200;
      r.imgH = 900;
      await Repo.instance.saveRecord(r);
    }
    final r2 = GardenRecord(
      id: 'ph_pot2',
      batchId: b.id,
      type: '拍照',
      title: '拍照记录',
      date: '2026-11-03',
    );
    r2.images = ['images/ph_pot2.png'];
    r2.potIndex = 2;
    await Repo.instance.saveRecord(r2);

    final counts = await Repo.instance.photoCountByPot(b.id);
    expect(counts[1], 2);
    expect(counts[2], 1);

    final latest = await Repo.instance.latestPhotoByPot(b.id);
    expect(latest[1]!.id, 'ph_1_1');
    expect(latest[2]!.id, 'ph_pot2');

    final photos = await Repo.instance.records(batchId: b.id, photo: true);
    final mine = photos.where((e) => e.id.startsWith('ph_')).toList();
    expect(mine.length, 3);
    expect(mine.any((e) => e.imgW == 1200), isTrue);

    await Repo.instance.deleteRecord('ph_pot2');
    final after = await Repo.instance.records(batchId: b.id, photo: true);
    expect(after.any((e) => e.id == 'ph_pot2'), isFalse);
  });

  test('导出文件：schemaVersion 6 且带 pots / potIndex / groupId', () async {
    final b = await makeBatch('导出测试');
    b.potCount = 2;
    await Repo.instance.saveBatch(b);
    final file = await Transfer.instance.buildFile('garden');
    expect(file['schemaVersion'], 6);
    expect((file['pots'] as List).length, greaterThanOrEqualTo(2));
    expect((file['batches'] as List).first, contains('photoMode'));
    final pestFile = await Transfer.instance.buildFile('pest');
    expect(pestFile['schemaVersion'], 6);
    expect((pestFile['items'] as List).first, contains('crops'));
  });

  test('病虫害按作物过滤：通用 + 指定作物都命中', () async {
    final p1 = Pest(id: 't_pest_common', crop: '通用', name: '红蜘蛛');
    await Repo.instance.savePest(p1);
    final p2 = Pest(
      id: 't_pest_straw',
      name: '测试白粉病',
      crop: 'crop_strawberry',
      crops: const ['crop_strawberry'],
    );
    await Repo.instance.savePest(p2);

    final sb = await Repo.instance.pests('crop_strawberry');
    final names = sb.map((e) => e.name).toList();
    expect(names.contains('红蜘蛛'), isTrue);
    expect(names.contains('测试白粉病'), isTrue);

    // 柠檬只应看到通用那条
    final lemon = await Repo.instance.pests('crop_lemon');
    final lemonNames = lemon.map((e) => e.name).toList();
    expect(lemonNames.contains('红蜘蛛'), isTrue);
    expect(lemonNames.contains('测试白粉病'), isFalse);
  });

  test('多批次提醒：同 groupId 合并成一组，取消整组都停用', () async {
    final b1 = await makeBatch('提醒A');
    final b2 = await makeBatch('提醒B');
    final g = 'rg_test_1';
    final r1 = Reminder(
      id: 'r_t1',
      batchId: b1.id,
      kind: '施肥',
      title: '冲肥',
      intervalDays: 7,
      nextDueAt: '2026-11-24',
      groupId: g,
    );
    final r2 = Reminder(
      id: 'r_t2',
      batchId: b2.id,
      kind: '施肥',
      title: '冲肥',
      intervalDays: 7,
      nextDueAt: '2026-11-25',
      groupId: g,
    );
    await Repo.instance.saveReminderBatch([r1, r2]);

    final list = await Repo.instance.reminders(batchId: null);
    final groups = groupReminders(list);
    final one = groups.where((e) => e.items.any((i) => i.id == 'r_t1')).toList();
    expect(one.length, 1);
    expect(one.first.items.length, 2);
    expect(one.first.isGroup, isTrue);
    expect(fmtDay(one.first.dueDate), '2026-11-24');

    await Repo.instance.cancelReminder(r1, wholeGroup: true);
    final after = await Repo.instance.reminderGroup(g);
    expect(after.isEmpty, isTrue);
  });

  test('AI 提示词包含约定字段与上限', () {
    final t = buildAiPrompt(
      cropName: '草莓',
      kind: 'variety',
      links: ['https://example.com/a'],
    );
    expect(t.contains('planting.ai'), isTrue);
    expect(t.contains('最多整理 20 条'), isTrue);
    expect(t.contains('sweetnessStar'), isTrue);
    expect(t.contains('https://example.com/a'), isTrue);

    final p = buildAiPrompt(cropName: '柠檬', kind: 'pest', links: const []);
    expect(p.contains('"kind": "pest"'), isTrue);
    expect(p.contains('treatment'), isTrue);
  });


  // ---------------- v1.7：多季 ----------------
  test('多季作物：按季取阶段，切季改基准日', () async {
    final c = Crop(
      id: 'crop_grape2',
      name: '葡萄（测试双季）',
      emoji: '🍇',
      lifeCycle: 'perennial',
      cycleStart: '03-01',
      unit: '株',
      seasons: [
        CropSeason(idx: 1, name: '夏果季', start: '03-01'),
        CropSeason(idx: 2, name: '秋果季', start: '07-20'),
      ],
      sortOrder: 950,
    );
    await Repo.instance.saveCrop(c);

    // 第 1 季两个阶段、第 2 季一个阶段
    await Repo.instance.saveStage(
      Stage(
        id: 's_g1',
        crop: c.id,
        name: '萌芽',
        startDay: 0,
        endDay: 30,
        season: 0,
      ),
    );
    await Repo.instance.saveStage(
      Stage(
        id: 's_g2',
        crop: c.id,
        name: '开花',
        startDay: 31,
        endDay: 60,
        season: 0,
      ),
    );
    await Repo.instance.saveStage(
      Stage(
        id: 's_g3',
        crop: c.id,
        name: '秋梢',
        startDay: 0,
        endDay: 40,
        season: 1,
      ),
    );

    final s1 = await Repo.instance.stages(c.id, season: 0);
    final s2 = await Repo.instance.stages(c.id, season: 1);
    expect(s1.map((e) => e.name), ['萌芽', '开花']);
    expect(s2.map((e) => e.name), ['秋梢']);
    // 没配阶段的季 → 回落到第 1 季，避免空白
    final s3 = await Repo.instance.stages(c.id, season: 2);
    expect(s3.map((e) => e.name), ['萌芽', '开花']);

    // 选第 2 季保存批次 → 基准日自动跟着季走
    final b = Batch(
      id: 'b_season',
      crop: c.id,
      name: '秋果批',
      plantDate: '',
      cycleStartDate: '03-01',
      season: 1,
      potCount: 1,
    );
    await Repo.instance.saveBatch(b);
    final back = (await Repo.instance.batch('b_season'))!;
    expect(back.season, 1);
    expect(back.cycleStartDate, '07-20');
    final snap = await Repo.instance.snapshot(back);
    expect(snap?.stage?.name, '秋梢');

    // 从第 1 季复制到第 3 季
    final cp = await Repo.instance.copySeasonStages(c.id, 0, 2);
    expect(cp.copied, 2);
    expect(cp.skipped, 0);
    final s4 = await Repo.instance.stages(c.id, season: 2);
    expect(s4.length, 2);
    expect(s4.every((e) => e.season == 2), isTrue);

    // 再点一次「从上一季复制」→ 同名阶段全部跳过，不重复创建
    final again = await Repo.instance.copySeasonStages(c.id, 0, 2);
    expect(again.copied, 0);
    expect(again.skipped, 2);
    expect((await Repo.instance.stages(c.id, season: 2)).length, 2);

    // v1.7 的 bug 现场：编辑时把季写成 0 → 启动归一化按 id 归位
    final broken = (await Repo.instance.stageById(s4.first.id))!;
    broken.season = 0;
    await Repo.instance.saveStage(broken);
    expect((await Repo.instance.stageById(broken.id))!.season, 0);
    final fixed = await Repo.instance.normalizeStageSeasons();
    expect(fixed >= 1, isTrue);
    expect((await Repo.instance.stageById(broken.id))!.season, 2);

    // 删除阶段：软删后不再出现在列表里
    await Repo.instance.deleteStage(broken.id);
    final s5 = await Repo.instance.stages(c.id, season: 2);
    expect(s5.any((e) => e.id == broken.id), isFalse);
    expect(s5.length, 1);
  });

  // ---------------- v1.7：一次记多批次（opId / 未施） ----------------
  test('记一笔多批次：同 opId，未选的批次记成未施', () async {
    final b1 = await makeBatch('施用A', id: 'b_op_a');
    final b2 = await makeBatch('施用B', id: 'b_op_b');
    final op = 'op_test_1';
    await Repo.instance.saveRecord(
      GardenRecord(
        id: 'op_r1',
        batchId: b1.id,
        type: '施药',
        date: todayStr(),
        title: '白粉病预防',
        opId: op,
        opSkipped: [b2.id],
      ),
    );
    await Repo.instance.saveRecord(
      GardenRecord(
        id: 'op_r2',
        batchId: b2.id,
        type: '施药',
        date: todayStr(),
        title: '白粉病预防',
        opId: op,
        opSkipped: [b2.id],
      ),
    );

    final byOp = await Repo.instance.recordsByOp(op);
    expect(byOp.length, 2);
    expect(byOp.first.opSkipped, [b2.id]);

    final recent = await Repo.instance.recordsSince(7);
    final mine = recent.where((e) => e.opId == op).toList();
    expect(mine.length, 2);

    final names = await Repo.instance.batchNames();
    expect(names[b1.id], '施用A');
  });

  // ---------------- v1.8.4：施用方式半角括号 ----------------
  test('施用方式统一成半角括号，旧数据启动后自动归一（幂等）', () async {
    expect(Supply.kMethods, contains('喷雾(叶背)'));
    expect(Supply.kMethods.any((e) => e.contains('（')), isFalse);

    await Repo.instance.saveMaterial(Supply(
      id: 'mat_full',
      kind: 'medicine',
      name: '旧药',
      ratio: '1:800',
      method: '喷雾（叶背）',
      methods: ['喷雾（叶背）', '灌根'],
    ));
    final b = await makeBatch('归一', id: 'b_norm');
    await Repo.instance.saveRecord(GardenRecord(
      id: 'rec_norm',
      batchId: b.id,
      type: '施药',
      date: todayStr(),
      title: '归一测试',
      products: [
        RecordProduct(name: '旧药', dosage: '1:800', method: '喷雾（叶背）'),
      ],
    ));

    expect(await Repo.instance.normalizeMethodNames(), greaterThanOrEqualTo(2));

    final m2 = (await Repo.instance.materials('medicine'))
        .firstWhere((e) => e.id == 'mat_full');
    expect(m2.method, '喷雾(叶背)');
    expect(m2.methods, contains('喷雾(叶背)'));
    expect(m2.methods.toString(), isNot(contains('（')));

    final r2 = (await Repo.instance.records())
        .firstWhere((e) => e.id == 'rec_norm');
    expect(r2.products.first.method, '喷雾(叶背)');

    // 幂等：再跑一次没有改动
    expect(await Repo.instance.normalizeMethodNames(), 0);
  });

  test('颜色配置：十六进制解析与回退默认', () {
    expect(hexOfColor(const Color(0xFFC2410C)), '#C2410C');
    expect(hexOfColor(parseHexColor('#c2410c')!), '#C2410C');
    expect(hexOfColor(parseHexColor('E0862B')!), '#E0862B');
    expect(parseHexColor('#F08'), isNull);
    expect(parseHexColor('不是颜色'), isNull);
    expect(kDefaultAppliedColor.toARGB32(), isNot(kDefaultSkippedColor.toARGB32()));
  });

  // ---------------- v1.8.3：删除整次操作 ----------------
  test('删除整次操作：同 opId 的记录一起删，其它记录不受影响', () async {
    final b1 = await makeBatch('删除A', id: 'b_del_a');
    final b2 = await makeBatch('删除B', id: 'b_del_b');
    const op = 'op_del_1';
    for (final (i, b) in [(1, b1), (2, b2)]) {
      await Repo.instance.saveRecord(
        GardenRecord(
          id: 'del_r$i',
          batchId: b.id,
          type: '施药',
          date: todayStr(),
          title: '删除测试',
          opId: op,
        ),
      );
    }
    await Repo.instance.saveRecord(
      GardenRecord(
        id: 'del_keep',
        batchId: b1.id,
        type: '浇水',
        date: todayStr(),
        title: '保留',
        opId: 'op_del_2',
      ),
    );

    expect((await Repo.instance.recordsByOp(op)).length, 2);
    expect(await Repo.instance.deleteOp(op), 2);
    expect(await Repo.instance.recordsByOp(op), isEmpty);

    final all = await Repo.instance.records();
    expect(all.any((e) => e.id == 'del_keep'), isTrue);
    expect(all.any((e) => e.id == 'del_r1'), isFalse);
    // 再删一次不会重复计数
    expect(await Repo.instance.deleteOp(op), 0);
  });

  // ---------------- v1.7：施用方式多选 ----------------
  test('肥料可存多种施用方式，老记录只有单值时自动兼容', () async {
    final m = Supply(
      id: 'mat_multi',
      kind: 'fertilizer',
      name: '测试复合肥',
      ratio: '1:1000',
      method: '灌根',
      methods: ['灌根', '喷雾'],
    );
    await Repo.instance.saveMaterial(m);
    final back = (await Repo.instance.materialById('mat_multi'))!;
    expect(back.effMethods, ['灌根', '喷雾']);
    expect(back.methodsText, '灌根、喷雾');

    // 老数据：methods 为空 → 回落到单值 method
    final old = Supply(id: 'mat_old', kind: 'medicine', name: '老药', method: '喷雾（叶背）');
    await Repo.instance.saveMaterial(old);
    final oldBack = (await Repo.instance.materialById('mat_old'))!;
    expect(oldBack.effMethods, ['喷雾（叶背）']);
    expect(oldBack.methodsText, '喷雾（叶背）');

    // 记录里的产品也能带多方式
    final p = RecordProduct(
      name: '测试复合肥',
      dosage: '1:1000',
      method: '灌根',
      methods: ['灌根', '喷雾'],
    );
    final b = await makeBatch('方式测试');
    await Repo.instance.saveRecord(
      GardenRecord(
        id: 'rec_multi',
        batchId: b.id,
        type: '施肥',
        date: todayStr(),
        title: '冲肥',
        products: [p],
      ),
    );
    final recs = await Repo.instance.records(batchId: b.id);
    final got = recs.firstWhere((e) => e.id == 'rec_multi');
    expect(got.products.first.effMethods, ['灌根', '喷雾']);
  });

  // ---------------- v1.7：导出 schemaVersion 5（v2.0.3 起为 6） ----------------
  test('导出文件 schemaVersion 为 6，并带季与 opId', () async {
    await makeBatch('导出v5');
    final f = await Transfer.instance.buildFile('garden');
    expect(f['schemaVersion'], 6);
    final batches = (f['batches'] as List).cast<Map>();
    expect(batches.any((e) => e.containsKey('season')), isTrue);
    final records = (f['records'] as List).cast<Map>();
    expect(records.any((e) => e.containsKey('opId')), isTrue);

    final st = await Transfer.instance.buildFile('stage');
    expect(st['schemaVersion'], 6);
    final crops = (st['crops'] as List).cast<Map>();
    expect(crops.any((e) => e['seasons'] is List), isTrue);
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('未施：单批次也有快照，范围可切换，死光批次不进候选', () async {
    final repo = Repo.instance;
    final straw =
        (await repo.crops()).firstWhere((c) => c.id == 'crop_strawberry');
    final lemon = (await repo.crops()).firstWhere((c) => c.id == 'crop_lemon');
    final plant = fmtDay(
      dateOnly(DateTime.now().subtract(const Duration(days: 40))),
    );

    final a = await makeBatch('未施A', id: 'skip_a');
    await repo.saveBatch(
      Batch(
        id: 'skip_b',
        crop: straw.id,
        name: '未施B',
        variety: '红颜',
        plantDate: plant,
        potCount: 2,
        color: '#2A9D8F',
      ),
    );
    await repo.saveBatch(
      Batch(
        id: 'skip_c',
        crop: lemon.id,
        name: '柠檬C',
        variety: '尤力克',
        plantDate: plant,
        potCount: 1,
        color: '#E8B23A',
      ),
    );

    // 默认（跨作物）：别的作物也算未施
    final all = await repo.skippedForRecord(
      type: '施肥',
      targets: {a.id},
      crops: {straw.id},
      acrossCrops: true,
    );
    expect(all.contains('skip_c'), isTrue, reason: '默认跨作物');
    expect(all.contains(a.id), isFalse, reason: '目标批次不算未施');

    // 仅同作物：柠檬不再出现
    final same = await repo.skippedForRecord(
      type: '施肥',
      targets: {a.id},
      crops: {straw.id},
      acrossCrops: false,
    );
    expect(same.contains('skip_c'), isFalse);
    expect(same.contains('skip_b'), isTrue);

    // 拍照 / 其他 没有「未施」
    expect(
      await repo.skippedForRecord(type: '拍照', targets: {a.id}),
      isEmpty,
    );
    expect(
      await repo.skippedForRecord(type: '其他', targets: {a.id}),
      isEmpty,
    );

    // 整盆死光 → 不再进候选
    for (final p in await repo.pots('skip_b')) {
      await repo.setPotState(p, 'dead');
    }
    final after = await repo.skippedForRecord(
      type: '施肥',
      targets: {a.id},
      crops: {straw.id},
      acrossCrops: false,
    );
    expect(after.contains('skip_b'), isFalse, reason: '死光批次不进未施');
    expect(await repo.deadBatchIds(), contains('skip_b'));
  });

  test('作物图标：能存库、能压成小图、导出带上 iconImage', () async {
    final repo = Repo.instance;
    // 1×1 红点 PNG，够验证解码/缩放链路
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final bytes = base64Decode(png);
    final small = await Images.saveScaled(bytes, size: 128);
    expect(small, startsWith('images/'));
    expect(Images.exists(small), isTrue);
    final abs = Images.pathOf(small)!;
    // 输出是 128×128 的方图（用文件头宽高校验：PNG IHDR 第 16..24 字节）
    final head = await File(abs).readAsBytes();
    final w = (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19];
    expect(w, 128);

    final c = (await repo.cropById('crop_strawberry'))!;
    c.iconImage = small;
    await repo.saveCrop(c);
    expect((await repo.cropById('crop_strawberry'))!.iconImage, small);

    final plan = await Transfer.instance.buildFile('stage');
    final raw = (plan['crops'] as List)
        .cast<Map>()
        .firstWhere((e) => e['id'] == 'crop_strawberry');
    // 有文件 → 导出成 data URI，换手机也能带走
    expect(raw['iconImage'].toString(), startsWith('data:image/png;base64,'));
    await Images.remove(small);
  });

  test('回填：老记录补「未施」快照，且只跑一次', () async {
    final repo = Repo.instance;
    final b = await makeBatch('回填A', id: 'bf_a');
    final plant = fmtDay(
      dateOnly(DateTime.now().subtract(const Duration(days: 40))),
    );
    await repo.saveBatch(
      Batch(
        id: 'bf_b',
        crop: b.crop,
        name: '回填B',
        variety: '红颜',
        plantDate: plant,
        potCount: 2,
        color: '#8A63D2',
      ),
    );
    await repo.saveRecord(
      GardenRecord(
        id: 'bf_r1',
        batchId: 'bf_a',
        type: '施肥',
        date: todayStr(),
        title: '回填测试',
      ),
    );

    final first = await repo.backfillOpSkipped();
    expect(first, greaterThan(0));
    final got = (await repo.records(batchId: 'bf_a'))
        .firstWhere((r) => r.id == 'bf_r1');
    expect(got.opSkipped, contains('bf_b'));

    // 幂等：再跑一次没有可补的
    expect(await repo.backfillOpSkipped(), 0);
  });

  // ---------------- v2.0.5：作物不再有「默认图」 ----------------
  test('作物导出不再带 image（知识库图片只属于条目）', () async {
    final f = await Transfer.instance.buildFile('stage');
    final crops = (f['crops'] as List).cast<Map>();
    expect(crops, isNotEmpty);
    for (final c in crops) {
      expect(c.containsKey('image'), isFalse);
    }
  });

  test('导入时同时接受 planting.data（开源快照/samples 用的标识）', () async {
    final f = await Transfer.instance.buildFile('variety') as Map;
    f['format'] = 'planting.data';
    final dir = await Directory.systemTemp.createTemp('fmt_alias');
    final file = File('${dir.path}/variety.json');
    await file.writeAsString(jsonEncode(f));
    final plan = await Transfer.instance.analyze(file.path, 'variety.json');
    expect(plan.error, null);
    expect(plan.kind, 'variety');
    await dir.delete(recursive: true);
  });

}
