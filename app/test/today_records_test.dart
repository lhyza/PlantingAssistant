import 'dart:io';

import 'package:flutter/material.dart';
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
}
