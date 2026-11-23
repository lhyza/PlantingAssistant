import 'package:flutter_test/flutter_test.dart';
import 'package:planting/core/util.dart';

void main() {
  test('daysBetween 跨月跨年都按自然日算', () {
    expect(daysBetween(DateTime(2026, 10, 1), DateTime(2026, 10, 1)), 0);
    expect(daysBetween(DateTime(2026, 10, 1), DateTime(2026, 10, 31)), 30);
    expect(daysBetween(DateTime(2026, 12, 20), DateTime(2027, 1, 5)), 16);
    expect(daysBetween(DateTime(2027, 1, 5), DateTime(2026, 12, 20)), -16);
  });

  test('非法类型归一到「其他」', () {
    expect(normKind('施肥'), '施肥');
    expect(normKind('浇水'), '浇水');
    expect(normKind('乱写'), '其他');
    expect(normRecordType('打药'), '其他');
  });
}
