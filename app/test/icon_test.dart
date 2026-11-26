import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:planting/data/models.dart';
import 'package:planting/ui/app_state.dart';
import 'package:planting/ui/image_crop.dart';
import 'package:planting/core/theme.dart';
import 'package:planting/ui/image_tile.dart';

Crop _crop({String emoji = '🍅', String iconImage = ''}) => Crop(
  id: 'crop_tomato',
  name: '番茄',
  emoji: emoji,
  image: '',
  iconImage: iconImage,
);


/// 1×1 透明 PNG（测试用最小合法图片）
final Uint8List kBmp1x1Png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('没有自定义小图时 cropLabel 显示 emoji', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: cropLabel(_crop()))),
      ),
    );
    expect(find.text('🍅'), findsOneWidget);
    expect(find.text('番茄'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('有自定义小图时 cropLabel 显示图片，不再显示 emoji', (tester) async {
    // 建一个真的 1×1 PNG 放到临时目录，让 Image.file 有东西可读
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('planting_icon'),
    );
    final file = File('${dir!.path}/icon.png');
    final png = kBmp1x1Png;
    await tester.runAsync(() => file.writeAsBytes(png));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: cropLabel(_crop(iconImage: file.path))),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('🍅'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('番茄'), findsOneWidget);
  });

  testWidgets('裁剪页可以预选 16:9，并给出 16:9 档位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageCropperPage(
          bytes: kBmp1x1Png,
          initialAspect: 16 / 9,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('16:9'), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);
    expect(find.text('自由'), findsOneWidget);
    // 预选了比例后提示语应是「把想要的部分放到框里」
    expect(find.textContaining('放到框里'), findsOneWidget);
  });

  test('bump() 会让 refreshTick 自增（页面据此重新读库）', () {
    final before = refreshTick.value;
    bump();
    expect(refreshTick.value, before + 1);
  });

  testWidgets('SectionTitle 支持左侧图标（批次页分组标题用）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionTitle(
            '树莓',
            count: 2,
            leading: Icon(Icons.eco, size: 16),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.eco), findsOneWidget);
    expect(find.text('树莓'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

}
