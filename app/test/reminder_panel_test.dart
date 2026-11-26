import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'package:planting/core/util.dart';
import 'package:planting/data/models.dart';
import 'package:planting/data/repo.dart';
import 'package:planting/ui/reminder_panel.dart';

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

/// 提醒面板：分类、合并一行、15 天窗口
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_panel');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);

    final repo = Repo.instance;
    final crop = (await repo.defaultCrop())!;
    final today = dateOnly(DateTime.now());
    String d(int plus) => fmtDay(today.add(Duration(days: plus)));

    for (final b in [
      ('pb1', '阳台花架', 4, 1),
      ('pb2', '露台大盆', 6, 2),
    ]) {
      await repo.saveBatch(Batch(
        id: b.$1,
        crop: crop.id,
        name: b.$2,
        variety: '隋珠',
        plantDate: d(-50),
        potCount: b.$3,
        color: '#E8354D',
        sortOrder: b.$4,
      ));
    }

    // 自定义提醒（templateId 为空），同一次创建的两个批次 → 应合并成一行
    await repo.saveReminder(Reminder(
      id: 'pm1',
      batchId: 'pb1',
      kind: '施肥',
      title: '高磷促花肥',
      intervalDays: 7,
      nextDueAt: d(-2),
      active: true,
      groupId: 'pg1',
      notes: '花前用一次',
    ));
    await repo.saveReminder(Reminder(
      id: 'pm2',
      batchId: 'pb2',
      kind: '施肥',
      title: '高磷促花肥',
      intervalDays: 7,
      nextDueAt: d(-2),
      active: true,
      groupId: 'pg1',
      notes: '花前用一次',
    ));

    // 阶段提醒（templateId 非空）：今天 + 边界 +15 与 +16
    await repo.saveReminder(Reminder(
      id: 'ps1',
      batchId: 'pb1',
      kind: '施药',
      title: '白粉病预防',
      intervalDays: 5,
      nextDueAt: d(0),
      active: true,
      templateId: 'sr_strawberry_05_a#1',
    ));
    await repo.saveReminder(Reminder(
      id: 'ps2',
      batchId: 'pb1',
      kind: '浇水',
      title: '边界十五天',
      intervalDays: 3,
      nextDueAt: d(15),
      active: true,
      templateId: 'sr_x#1',
    ));
    await repo.saveReminder(Reminder(
      id: 'ps3',
      batchId: 'pb1',
      kind: '浇水',
      title: '十六天不该出现',
      intervalDays: 3,
      nextDueAt: d(16),
      active: true,
      templateId: 'sr_y#1',
    ));
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('分类正确：自定义与阶段分开，合并组只一行', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReminderPanelPage())),
    );
    await _flush(tester, 12);

    expect(find.text('自定义提醒'), findsOneWidget);
    expect(find.text('近 15 天提醒'), findsOneWidget);
    // 两个批次的自定义提醒合并成一行
    expect(find.text('高磷促花肥'), findsOneWidget);
    expect(find.textContaining('阳台花架、露台大盆'), findsOneWidget);
    expect(find.textContaining('花前用一次'), findsOneWidget);
    // 阶段提醒出现在第二个区块
    expect(find.text('白粉病预防'), findsOneWidget);
    expect(find.textContaining('批次：阳台花架'), findsWidgets);
  });

  testWidgets('窗口：今天+15 在列表，今天+16 不出现', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReminderPanelPage())),
    );
    await _flush(tester, 12);

    expect(find.text('边界十五天'), findsOneWidget);
    expect(find.text('十六天不该出现'), findsNothing);
  });

  testWidgets('第一行有状态、第二行是循环+下次、第三行是批次', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReminderPanelPage())),
    );
    await _flush(tester, 12);

    expect(find.textContaining('已逾期'), findsWidgets);
    expect(find.textContaining('今天'), findsWidgets);
    expect(find.textContaining('每 7 天 · 下次'), findsOneWidget);
  });
  testWidgets('顶部「新建」能打开新建提醒页', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReminderPanelPage())),
    );
    await _flush(tester, 12);

    expect(find.text('新建'), findsOneWidget);
    await tester.tap(find.text('新建'));
    await _flush(tester, 14);

    expect(find.text('新建提醒'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });
}
