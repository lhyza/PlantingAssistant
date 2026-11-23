import 'dart:math';
import 'dart:ui' show Color;

import 'package:intl/intl.dart';

final DateFormat dayFmt = DateFormat('yyyy-MM-dd');
final DateFormat dayShort = DateFormat('MM-dd');
final DateFormat stampFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

/// 本地时间 ISO 字符串（用于 updated_at 比较与展示）
String nowStamp() => stampFmt.format(DateTime.now());

String todayStr() => dayFmt.format(DateTime.now());

DateTime? parseDay(String? s) {
  if (s == null || s.isEmpty) return null;
  final d = DateTime.tryParse(s.length <= 10 ? '${s}T00:00:00' : s);
  return d;
}

String fmtDay(DateTime? d) => d == null ? '' : dayFmt.format(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysBetween(DateTime a, DateTime b) =>
    dateOnly(b).difference(dateOnly(a)).inDays;

String relDay(DateTime due) {
  final diff = daysBetween(DateTime.now(), due);
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff == -1) return '昨天';
  if (diff < 0) return '已逾期 ${-diff} 天';
  return '$diff 天后';
}

const List<String> kColors = [
  '#D9534F',
  '#D96A9A',
  '#E0862B',
  '#C9A227',
  '#3E9B6B',
  '#2A9D8F',
  '#4A7FC0',
  '#8A63D2',
  '#A9744F',
  '#647A8E',
];

const List<String> kRecordTypes = ['施肥', '施药', '浇水', '拍照', '其他'];
const List<String> kReminderKinds = ['施肥', '施药', '浇水', '其他'];

String normRecordType(String? v) => kRecordTypes.contains(v) ? v! : '其他';

String normKind(String? v) => kReminderKinds.contains(v) ? v! : '其他';

Color colorOf(String? hex) {
  final h = (hex ?? '#4A7FC0').replaceAll('#', '');
  final v = int.tryParse(h, radix: 16) ?? 0x4A7FC0;
  return Color(0xFF000000 | v);
}

final Random _rnd = Random.secure();

/// 简易 ULID 风格 id：时间前缀 + 随机，保证离线不撞
String newId(String prefix) {
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = List.generate(
    8,
    (_) => _rnd.nextInt(36).toRadixString(36),
  ).join();
  return '${prefix}_$ts$rand';
}

String prettyDate(DateTime d) {
  const w = ['一', '二', '三', '四', '五', '六', '日'];
  return '${d.month}月${d.day}日 星期${w[d.weekday - 1]}';
}
