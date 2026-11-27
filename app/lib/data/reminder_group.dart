import 'models.dart';

/// 把「同一次创建的多个批次提醒」合并成一条展示用的分组。
///
/// 单批次创建的提醒 `groupId` 为空，每个都是一组独立的。
class ReminderGroup {
  ReminderGroup(this.items);

  final List<Reminder> items;

  Reminder get head => items.first;

  String get title => head.title;
  String get kind => head.kind;
  int get intervalDays => head.intervalDays;
  bool get isOneTime => head.isOneTime;
  String get notes => head.notes;
  bool get isGroup => items.length > 1;

  /// 组内最紧急的到期日（最早的那个）
  String get dueAt {
    var v = '';
    for (final r in items) {
      if (r.nextDueAt.isEmpty) continue;
      if (v.isEmpty || r.nextDueAt.compareTo(v) < 0) v = r.nextDueAt;
    }
    return v;
  }

  DateTime? get dueDate => parseDue(dueAt);

  static DateTime? parseDue(String s) {
    if (s.isEmpty) return null;
    final parts = s.split('-');
    if (parts.length != 3) return null;
    return DateTime(
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
  }

  /// 组内已逾期的条数
  int overdueCount(String today) =>
      items.where((r) => r.nextDueAt.compareTo(today) < 0).length;

  /// 组内有几条今天到期
  int todayCount(String today) =>
      items.where((r) => r.nextDueAt == today).length;
}

/// 保持原有顺序（按 nextDueAt 升序）合并分组
List<ReminderGroup> groupReminders(List<Reminder> rs) {
  final byGroup = <String, ReminderGroup>{};
  final singles = <ReminderGroup>[];
  for (final r in rs) {
    if (r.groupId.isEmpty) {
      singles.add(ReminderGroup([r]));
      continue;
    }
    final g = byGroup[r.groupId];
    if (g == null) {
      byGroup[r.groupId] = ReminderGroup([r]);
    } else {
      g.items.add(r);
    }
  }
  final all = [...singles, ...byGroup.values];
  all.sort((a, b) {
    final x = a.dueAt.isEmpty ? '9999-12-31' : a.dueAt;
    final y = b.dueAt.isEmpty ? '9999-12-31' : b.dueAt;
    return x.compareTo(y);
  });
  return all;
}

/// 角标口径：已逾期 + 今天到期的提醒「组」数（同 groupId 只算 1）。
int dueReminderGroupCount(Iterable<Reminder> all, String today) {
  final due = all.where(
    (r) => r.nextDueAt.isNotEmpty && r.nextDueAt.compareTo(today) <= 0,
  );
  return groupReminders(due.toList()).length;
}
