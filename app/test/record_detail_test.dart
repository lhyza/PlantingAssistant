import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:planting/core/theme.dart';
import 'package:planting/data/models.dart';
import 'package:planting/ui/record_list.dart';

GardenRecord rec(
  String id,
  String batchId,
  String title, {
  String opId = 'op1',
  List<String> skipped = const [],
}) =>
    GardenRecord(
      id: id,
      batchId: batchId,
      type: '施药',
      date: '2026-11-24',
      title: title,
      opId: opId,
      opSkipped: skipped,
      products: [
        RecordProduct(name: '苯醚甲环唑', dosage: '1:1500', method: '喷雾'),
      ],
    );

Widget wrap(Widget child) =>
    MaterialApp(theme: buildTheme(), home: child);

void main() {
  const names = {'b1': '阳台花架', 'b2': '露台大盆'};

  testWidgets('合并模式：上一条/下一条在“不同操作”之间切换', (tester) async {
    final groups = [
      [rec('r1', 'b1', '第一次用药', skipped: ['b2'])],
      [rec('r2', 'b2', '第二次用药', opId: 'op2')],
    ];
    await tester.pumpWidget(wrap(RecordDetailPage(
      items: groups[0],
      index: 0,
      groups: groups,
      batchNames: names,
    )));
    await tester.pump();

    expect(find.text('第 1/2 次操作'), findsOneWidget);
    expect(find.text('第一次用药'), findsOneWidget);
    expect(find.text('下一次'), findsOneWidget);

    await tester.tap(find.text('下一次'));
    await tester.pump();
    await tester.pump();

    expect(find.text('第 2/2 次操作'), findsOneWidget);
    expect(find.text('第二次用药'), findsOneWidget);
    expect(find.text('第一次用药'), findsNothing);

    await tester.tap(find.text('上一次'));
    await tester.pump();
    await tester.pump();
    expect(find.text('第一次用药'), findsOneWidget);
  });

  testWidgets('单条模式：仍按记录条数切换', (tester) async {
    final items = [rec('r1', 'b1', '记录一'), rec('r2', 'b2', '记录二')];
    await tester.pumpWidget(wrap(RecordDetailPage(
      items: items,
      index: 0,
      batchNames: names,
    )));
    await tester.pump();

    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('下一条'), findsOneWidget);
    await tester.tap(find.text('下一条'));
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('记录二'), findsOneWidget);
  });
}
