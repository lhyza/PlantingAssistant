import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'package:planting/core/util.dart';
import 'package:planting/data/models.dart';
import 'package:planting/data/repo.dart';
import 'package:planting/data/transfer.dart';
import 'package:planting/ui/reminder_history.dart';

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

/// 提醒历史：一次完成=一条、批次快照、可删除、导出带 schemaVersion 6
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_history');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);

    final repo = Repo.instance;
    final crop = (await repo.defaultCrop())!;
    final today = dateOnly(DateTime.now());
    String d(int plus) => fmtDay(today.add(Duration(days: plus)));

    for (final b in [
      ('hb1', '阳台花架', 4, 1),
      ('hb2', '露台大盆', 6, 2),
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
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('全部完成一组含 2 个批次：只写 1 条历史，批次是快照', () async {
    final repo = Repo.instance;
    final today = dateOnly(DateTime.now());

    final a = Reminder(
      id: 'hr_a',
      batchId: 'hb1',
      kind: '施药',
      title: '白粉病预防',
      intervalDays: 7,
      nextDueAt: fmtDay(today),
      notes: '叶背要打透',
      groupId: 'hg1',
    );
    final b = Reminder(
      id: 'hr_b',
      batchId: 'hb2',
      kind: '施药',
      title: '白粉病预防',
      intervalDays: 7,
      nextDueAt: fmtDay(today),
      notes: '叶背要打透',
      groupId: 'hg1',
    );
    await repo.saveReminder(a);
    await repo.saveReminder(b);

    for (final r in [a, b]) {
      await repo.completeReminder(r, doneAt: today);
    }
    await repo.logReminderDone(
      items: [a, b],
      done: today,
      nextDueAt: a.nextDueAt,
    );

    final logs = await repo.reminderLogs();
    expect(logs.length, 1);
    expect(logs.first.batchNames, '阳台花架、露台大盆');
    expect(logs.first.notes, '叶背要打透');
    expect(logs.first.nextDueAt, fmtDay(today.add(const Duration(days: 7))));
  });

  test('只完成其中一条：再写一条历史，只有 1 个批次', () async {
    final repo = Repo.instance;
    final today = dateOnly(DateTime.now());
    final a = (await repo.reminder('hr_a'))!;
    await repo.completeReminder(a, doneAt: today);
    await repo.logReminderDone(
      items: [a],
      done: today,
      nextDueAt: a.nextDueAt,
    );

    final logs = await repo.reminderLogs();
    expect(logs.length, 2);
    // 两条互不合并：一条两批次、一条单批次
    expect(logs.where((e) => e.batchNames.contains('、')).length, 1);
    expect(logs.where((e) => e.batchNames == '阳台花架').length, 1);
  });

  test('一次性提醒完成：nextDueAt 为空，页面不显示下次日期', () async {
    final repo = Repo.instance;
    final today = dateOnly(DateTime.now());
    final one = Reminder(
      id: 'hr_one',
      batchId: 'hb1',
      kind: '其他',
      title: '换盆',
      intervalDays: 0,
      nextDueAt: fmtDay(today),
      isOneTime: true,
      notes: '换成 20cm 盆',
    );
    await repo.saveReminder(one);
    await repo.completeReminder(one, doneAt: today);
    await repo.logReminderDone(
      items: [one],
      done: today,
      nextDueAt: one.isOneTime ? '' : one.nextDueAt,
    );

    final logs = await repo.reminderLogs();
    final log = logs.firstWhere((e) => e.title == '换盆');
    expect(log.nextDueAt, isEmpty);
    expect(log.isOneTime, isTrue);
  });

  testWidgets('历史页：备注跟在标题后、批次单独一行；可删除', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: ReminderHistoryPage()),
    );
    await _flush(tester, 12);

    expect(find.text('白粉病预防'), findsWidgets);
    expect(find.textContaining('备注：叶背要打透'), findsWidgets);
    expect(find.text('批次：阳台花架、露台大盆'), findsOneWidget);
    expect(find.textContaining('下次'), findsNothing);

    final before = await tester.runAsync(
      () => Repo.instance.reminderLogCount(),
    );
    expect(before, 3);

    // 删除第一条（最上面那条是今天的「换盆」或「白粉病预防」，都行）
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await _flush(tester, 6);
    expect(find.text('删除这条历史？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await _flush(tester, 10);

    final after = await tester.runAsync(
      () => Repo.instance.reminderLogCount(),
    );
    expect(after, 2);
    // 提醒本身不受影响
    final r = await tester.runAsync(() => Repo.instance.reminder('hr_a'));
    expect(r, isNotNull);
  });

  test('导出：garden 文件带 reminderLogs，schemaVersion 为 6', () async {
    final repo = Repo.instance;
    final file = await repo.exportPath();
    expect(file, isNotEmpty);

    final data = await Transfer.instance.buildFile('garden');
    expect(data['schemaVersion'], 6);
    expect((data['reminderLogs'] as List).length, 2);
  });
}
