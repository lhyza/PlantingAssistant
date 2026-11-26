import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'package:planting/app.dart';
import 'package:planting/core/theme.dart';
import 'package:planting/core/ui_prefs.dart';
import 'package:planting/core/util.dart';
import 'package:planting/data/models.dart';
import 'package:planting/data/repo.dart';
import 'package:planting/ui/record_list.dart';

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

Future<void> _flush(WidgetTester tester, [int rounds = 10]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// 今天页「近 15 天操作」的入口要按「操作」翻页：
/// 同一次操作涉及多个批次时，不该在批次之间打转。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_today');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    final repo = Repo.instance;
    final crop = (await repo.defaultCrop())!;
    final today = dateOnly(DateTime.now());
    String d(int daysAgo) => fmtDay(today.subtract(Duration(days: daysAgo)));

    await repo.saveBatch(Batch(
      id: 'tb1',
      crop: crop.id,
      name: '阳台花架',
      variety: '隋珠',
      plantDate: d(50),
      potCount: 4,
      color: '#E8354D',
      sortOrder: 1,
    ));
    await repo.saveBatch(Batch(
      id: 'tb2',
      crop: crop.id,
      name: '露台大盆',
      variety: '红颜',
      plantDate: d(52),
      potCount: 6,
      color: '#2A9D8F',
      sortOrder: 2,
    ));

    // 第一次操作：打了阳台花架，露台大盆没打（未施）
    await repo.saveRecord(GardenRecord(
      id: 'tr1',
      batchId: 'tb1',
      type: '施药',
      date: d(0),
      title: '白粉病预防',
      products: [
        RecordProduct(name: '苯醚甲环唑', dosage: '1:1500', method: '喷雾'),
      ],
      opId: 'top1',
      opSkipped: const ['tb2'],
      notes: '重点喷叶背',
    ));
    // 第二次操作：单独给露台大盆施肥
    await repo.saveRecord(GardenRecord(
      id: 'tr2',
      batchId: 'tb2',
      type: '施肥',
      date: d(3),
      title: '高磷促花肥',
      products: [
        RecordProduct(name: '磷酸二氢钾', dosage: '1:1000', method: '灌根'),
      ],
      opId: 'top2',
    ));

    // 一条提醒涉及两个批次（同 groupId）→ 今天页只应出现一张卡，且列出两个批次名
    for (final b in ['tb1', 'tb2']) {
      await repo.saveReminder(Reminder(
        id: 'trm_$b',
        batchId: b,
        kind: '施肥',
        title: '促花肥（提醒）',
        intervalDays: 7,
        nextDueAt: d(0),
        active: true,
        groupId: 'trg1',
        notes: '花前用一次',
      ));
    }
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {
      // Windows 上数据库句柄可能还没释放，临时目录留给系统清理
    }
  });

  testWidgets('今天页近 15 天操作：点进去按「操作」翻页，而不是按批次', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlantingApp());
    await _flush(tester, 12);

    // 今天页第一行操作 = 最近的一次
    // 注意：'白粉病预防' 同时也是提醒标题，这里按组件定位记录行
    expect(find.byType(OpRecordTile), findsWidgets);

    await tester.tap(find.byType(OpRecordTile).first);
    await _flush(tester, 6);

    expect(find.text('第 1/2 次操作'), findsOneWidget);
    expect(find.text('下一次'), findsOneWidget);
    // 第一条操作时「上一次」应为禁用态
    final prev = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '上一次'),
    );
    expect(prev.onPressed, isNull);

    await tester.tap(find.text('下一次'));
    await _flush(tester, 4);

    expect(find.text('第 2/2 次操作'), findsOneWidget);
    // 详情页标题是 22sp 的那一个（今天页的列表项仍压在下层路由里，所以用 findsWidgets）
    expect(find.text('高磷促花肥'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == '高磷促花肥' && w.style?.fontSize == 22,
      ),
      findsOneWidget,
    );
  });

  testWidgets('操作记录：产品 → 备注 → 施用 → 未施，各按配置着色', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlantingApp());
    await _flush(tester, 12);

    // 四种文本都在同一条记录里
    final product = find.textContaining('苯醚甲环唑');
    final notes = find.text('重点喷叶背');
    final applied = find.text('施用：阳台花架');
    final skipped = find.text('未施：露台大盆');
    expect(product, findsWidgets);
    expect(notes, findsOneWidget);
    expect(applied, findsOneWidget);
    expect(skipped, findsOneWidget);

    // 顺序：产品 → 备注 → 施用 → 未施
    final yProduct = tester.getTopLeft(product.first).dy;
    final yNotes = tester.getTopLeft(notes).dy;
    final yApplied = tester.getTopLeft(applied).dy;
    final ySkipped = tester.getTopLeft(skipped).dy;
    expect(yProduct, lessThan(yNotes));
    expect(yNotes, lessThan(yApplied));
    expect(yApplied, lessThan(ySkipped));

    // 默认配色：施用深橙、未施橙，两者不同
    final appliedText = tester.widget<Text>(applied);
    final skippedText = tester.widget<Text>(skipped);
    expect(appliedText.style?.color, kDefaultAppliedColor);
    expect(skippedText.style?.color, kDefaultSkippedColor);
    expect(kDefaultAppliedColor.toARGB32(), isNot(kDefaultSkippedColor.toARGB32()));

    // 详情页把它叫「本次忽略」
    await tester.tap(find.byType(OpRecordTile).first);
    await _flush(tester, 6);
    expect(find.text('本次忽略'), findsOneWidget);
    expect(find.textContaining('露台大盆'), findsWidgets);

  });

  testWidgets('我的 → 显示设置：颜色与未施范围', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlantingApp());
    await _flush(tester, 12);

    await tester.tap(find.text('我的').last);
    await _flush(tester, 10);
    expect(find.text('显示设置'), findsOneWidget);

    await tester.tap(find.text('显示设置'));
    await _flush(tester, 8);
    expect(find.text('施用批次名称'), findsOneWidget);
    expect(find.text('未施批次名称'), findsOneWidget);
    // 两个默认色不同，且页面显示了当前色值
    expect(find.textContaining('#C2410C'), findsOneWidget);
    expect(find.textContaining('#E0862B'), findsOneWidget);
    // 新的「记录偏好」段
    expect(find.text('未施范围'), findsOneWidget);
    expect(find.text('算上其它作物'), findsOneWidget);
  });

  testWidgets('记录详情可删除整次操作，且删除前要确认', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlantingApp());
    await _flush(tester, 12);
    expect(find.byType(OpRecordTile), findsNWidgets(2));

    await tester.tap(find.byType(OpRecordTile).first);
    await _flush(tester, 6);
    expect(find.text('第 1/2 次操作'), findsOneWidget);

    // 点删除 → 先弹确认框，正文要写清涉及哪个批次、共几条
    await tester.tap(find.byTooltip('删除这次操作'));
    await _flush(tester, 4);
    expect(find.text('删除这次操作？'), findsOneWidget);
    expect(find.textContaining('阳台花架'), findsWidgets);
    expect(find.textContaining('共 1 条记录'), findsOneWidget);

    // 取消：什么都不删，仍停在详情页
    await tester.tap(find.text('取消'));
    await _flush(tester, 10);
    expect(find.text('删除这次操作？'), findsNothing);
    expect(find.text('第 1/2 次操作'), findsOneWidget);

    // 确认删除：整次操作（同 opId 的多条）一起消失，另一组保留
    await tester.tap(find.byTooltip('删除这次操作'));
    await _flush(tester, 6);
    await tester.tap(find.text('删除'));
    await _flush(tester, 8);

    expect(find.text('删除这次操作？'), findsNothing);
    final left = (await tester.runAsync(() => Repo.instance.records()))!;
    expect(left.any((e) => e.opId == 'top1'), isFalse);
    expect(left.any((e) => e.opId == 'top2'), isTrue);

    // bump() 会触发其它页（批次列表等）重新查库，等它们跑完再结束用例
    await _flush(tester, 25);
  });

  testWidgets('今天页「全部」也用单批次阶段条，chips 可切换', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlantingApp());
    await _flush(tester, 12);

    // chips 首位是「全部」
    expect(find.text('全部'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await _flush(tester, 10);

    // v1.9.1：全部模式与单品种同款——一次显示一个批次的阶段条
    expect(find.text('全部作物'), findsNothing);
    expect(find.text('阳台花架'), findsWidgets);
    expect(find.textContaining('第 '), findsWidgets);
    // 两个批次都出现在 chips 里，可以一个个点
    expect(find.textContaining('露台大盆'), findsWidgets);

    await tester.tap(find.textContaining('露台大盆').last);
    await _flush(tester, 6);
    expect(find.text('阳台花架'), findsWidgets);
  });

  testWidgets('多批次提醒在今天页只有一张卡，并列出涉及的批次', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(child: PlantingApp()),
    );
    await _flush(tester, 14);

    // 两个批次只渲染一张卡：标题只出现一次
    expect(find.text('促花肥（提醒）'), findsOneWidget);
    // 第二行：类型 · 每 N 天 · 备注
    expect(find.textContaining('施肥 · 每 7 天 · 花前用一次'), findsOneWidget);
    // 第三行：批次：全部涉及批次
    expect(find.text('批次：阳台花架、露台大盆'), findsOneWidget);
  });

}
