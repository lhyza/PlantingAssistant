import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:planting/app.dart';
import 'package:planting/data/repo.dart';

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

/// 让 sqflite ffi 的真实异步在测试里跑完（fake_async 下 DB 调用会一直 pending）
Future<void> _flush(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_ui_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await Repo.instance.crops();
  });

  testWidgets('首屏可渲染且底部 5 个 Tab 都在', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlantingApp());
    await _flush(tester);

    expect(find.text('今天'), findsWidgets);
    expect(find.text('批次'), findsWidgets);
    expect(find.text('提醒'), findsWidgets);
    expect(find.text('知识'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _flush(tester);
  });

  testWidgets('切到「我的」再进「关于」不崩', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PlantingApp());
    await _flush(tester);

    await tester.tap(find.text('我的').last);
    await _flush(tester);

    final about = find.text('关于');
    expect(about, findsWidgets);
    // v1.8.4 起「管理」组多了颜色设置，关于可能被底部导航遮住，先滚到可见
    await tester.ensureVisible(about.last);
    await _flush(tester, 2);
    await tester.tap(about.last);
    await _flush(tester);

    expect(find.text('种植助手'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _flush(tester);
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });
}
