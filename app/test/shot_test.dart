import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'package:planting/app.dart';
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

Future<void> _flush(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _loadFonts() async {
  final f = File(r'C:\Windows\Fonts\simhei.ttf');
  if (!f.existsSync()) return;
  final bytes = await f.readAsBytes();
  // 测试环境没有系统字体，且工具栏/按钮的样式是裸 TextStyle（不继承主题的
  // fontFamilyFallback），所以把常见默认族名都注册一遍，截图才不会是方框。
  const families = [
    'Roboto',
    'Noto Sans CJK SC',
    'Microsoft YaHei',
    'Noto Sans SC',
    '.SF UI Text',
    'Segoe UI',
    'Arial',
    'Helvetica',
    'sans-serif',
  ];
  for (final family in families) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }
}

Future<void> _shot(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    await File(path).writeAsBytes(data.buffer.asUint8List());
  });
  await tester.pump();
}


/// 造一点演示数据，让截图里能看到阶段条、批次卡与记录行。
/// 只写进测试用的临时数据库，不影响正式 App 的首次启动状态。
Future<void> _seedDemo() async {
  final repo = Repo.instance;
  final crop = (await repo.defaultCrop())!;
  final today = dateOnly(DateTime.now());
  String d(int daysAgo) => fmtDay(today.subtract(Duration(days: daysAgo)));

  await repo.saveBatch(Batch(
    id: 'demo_b1',
    crop: crop.id,
    name: '阳台花架',
    variety: '隋珠',
    plantDate: d(50),
    location: '南阳台',
    potCount: 4,
    color: '#E8354D',
    sortOrder: 1,
  ));
  await repo.saveBatch(Batch(
    id: 'demo_b2',
    crop: crop.id,
    name: '露台大盆',
    variety: '红颜',
    plantDate: d(52),
    location: '露台',
    potCount: 6,
    color: '#2A9D8F',
    sortOrder: 2,
  ));

  await repo.saveRecord(GardenRecord(
    id: 'demo_r1',
    batchId: 'demo_b1',
    type: '施药',
    date: d(0),
    title: '白粉病预防',
    products: [
      RecordProduct(name: '苯醚甲环唑', dosage: '1:1500', method: '喷雾（叶背）'),
      RecordProduct(name: '吡唑醚菌酯', dosage: '1:2000', method: '喷雾'),
    ],
    opId: 'demo_op1',
    opSkipped: ['demo_b2'],
    notes: '重点喷叶背',
  ));
  await repo.saveRecord(GardenRecord(
    id: 'demo_r2',
    batchId: 'demo_b2',
    type: '施肥',
    date: d(3),
    title: '高磷促花肥',
    products: [
      RecordProduct(name: '磷酸二氢钾', dosage: '1:1000', method: '灌根'),
    ],
    notes: '浇透',
  ));

  await repo.saveReminder(Reminder(
    id: 'demo_m1',
    batchId: 'demo_b2',
    kind: '施药',
    title: '白粉病预防',
    intervalDays: 10,
    nextDueAt: d(2),
  ));
  await repo.saveReminder(Reminder(
    id: 'demo_m2',
    batchId: 'demo_b1',
    kind: '施肥',
    title: '高磷促花肥',
    intervalDays: 7,
    nextDueAt: d(0),
  ));

  // 阶段提醒（templateId 非空）+ 同一次为两个批次创建 → 面板里合并成一行
  await repo.saveReminder(Reminder(
    id: 'demo_m3',
    batchId: 'demo_b1',
    kind: '施药',
    title: '白粉病预防',
    intervalDays: 5,
    nextDueAt: d(1),
    templateId: 'sr_strawberry_05_a#1',
    notes: '重点喷叶背',
  ));
  await repo.saveReminder(Reminder(
    id: 'demo_m4',
    batchId: 'demo_b2',
    kind: '施药',
    title: '白粉病预防',
    intervalDays: 5,
    nextDueAt: d(1),
    templateId: 'sr_strawberry_05_a#1',
    groupId: 'demo_g1',
    notes: '重点喷叶背',
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_shot');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await Repo.instance.crops();
    await _seedDemo();
    await _loadFonts();
  });

  testWidgets('导出今天页截图', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // 390x844 @3x
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(key: Key('shot'), child: PlantingApp()),
    );
    await _flush(tester, 10);
    await tester.pump(const Duration(milliseconds: 400));

    await _shot(tester, '../docs/images/app-real-today.png');
    await _flush(tester);
  });

  testWidgets('导出批次列表与我的页截图', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(key: Key('shot'), child: PlantingApp()),
    );
    await _flush(tester, 10);

    await tester.tap(find.text('批次').last);
    await _flush(tester, 6);
    await _shot(tester, '../docs/images/app-real-batches.png');

    // 底部导航「提醒」进提醒面板
    await tester.tap(find.text('提醒').last);
    await _flush(tester, 8);
    await _shot(tester, '../docs/images/app-real-reminder-panel.png');
    await _flush(tester, 4);

    await tester.tap(find.text('我的').last);
    await _flush(tester, 6);
    await _shot(tester, '../docs/images/app-real-me.png');
    await _flush(tester);
  });

  testWidgets('导出版本更新页截图', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(key: Key('shot'), child: PlantingApp()),
    );
    await _flush(tester, 10);

    await tester.tap(find.text('我的').last);
    await _flush(tester, 6);
    await tester.tap(find.text('版本更新').last);
    await _flush(tester, 10);
    await _shot(tester, '../docs/images/app-real-update.png');
    await _flush(tester);
  });

  testWidgets('导出记录详情截图（今天页按操作翻页）', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(key: Key('shot'), child: PlantingApp()),
    );
    await _flush(tester, 10);

    // 记录行可能在首屏之外（提醒卡较高），先往下滚到出现为止
    final list = find.byType(ListView).first;
    for (var i = 0; i < 8 && find.byType(OpRecordTile).evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -280));
      await _flush(tester, 3);
    }
    expect(find.byType(OpRecordTile), findsWidgets);
    await tester.ensureVisible(find.byType(OpRecordTile).first);
    await _flush(tester, 3);
    // 「白粉病预防」同时是提醒标题，这里精确点「近 15 天操作」里的记录行
    await tester.tap(find.byType(OpRecordTile).first);
    await _flush(tester, 8);
    await _shot(tester, '../docs/images/app-real-record-detail.png');
    await _flush(tester);
  });
}
