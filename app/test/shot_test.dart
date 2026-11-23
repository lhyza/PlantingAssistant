import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  for (final family in ['Roboto', 'Noto Sans CJK SC', 'Microsoft YaHei']) {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_shot');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await Repo.instance.crops();
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

    await tester.tap(find.text('我的').last);
    await _flush(tester, 6);
    await _shot(tester, '../docs/images/app-real-me.png');
    await _flush(tester);
  });
}
