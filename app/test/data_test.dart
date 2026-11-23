import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;
import 'package:planting/data/models.dart';
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

Future<Batch> makeBatch(String name) async {
  final crop = (await Repo.instance.defaultCrop())!;
  final b = Batch(
    id: 'test_batch_1',
    crop: crop.id,
    name: name,
    variety: '红颜',
    plantDate: '2026-10-01',
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

  test('导出文件：schemaVersion 4 且带 pots / potIndex / groupId', () async {
    final b = await makeBatch('导出测试');
    b.potCount = 2;
    await Repo.instance.saveBatch(b);
    final file = await Transfer.instance.buildFile('garden');
    expect(file['schemaVersion'], 4);
    expect((file['pots'] as List).length, greaterThanOrEqualTo(2));
    expect((file['batches'] as List).first, contains('photoMode'));
    final pestFile = await Transfer.instance.buildFile('pest');
    expect(pestFile['schemaVersion'], 4);
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

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });
}
