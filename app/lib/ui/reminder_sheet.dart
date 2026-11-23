import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/notify.dart';
import '../data/reminder_group.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'common.dart';
import 'record_edit.dart' show kindEmojiOf;
import 'reminder_edit.dart';

/// 点提醒后弹出的信息框：关闭 / 完成 / 编辑 / 取消提醒
Future<void> openReminderSheet(
  BuildContext context,
  ReminderGroup g, {
  required String Function(String) batchName,
  VoidCallback? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _ReminderSheet(
      group: g,
      batchName: batchName,
      onChanged: onChanged,
    ),
  );
}

class _ReminderSheet extends StatelessWidget {
  const _ReminderSheet({
    required this.group,
    required this.batchName,
    this.onChanged,
  });

  final ReminderGroup group;
  final String Function(String) batchName;
  final VoidCallback? onChanged;

  String get _today => todayStr();

  bool get _overdue => group.dueAt.isNotEmpty && group.dueAt.compareTo(_today) < 0;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final names = g.items.map((r) => batchName(r.batchId)).toList();
    final cycle = g.isOneTime
        ? '只做一次'
        : (g.intervalDays <= 1 ? '每天' : '每 ${g.intervalDays} 天');
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6E1DB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    g.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Row(
              children: [
                Pill(
                  '${kindEmojiOf(g.kind)} ${g.kind}',
                  bg: const Color(0xFFF5F3F0),
                  fg: kInk2,
                ),
                const SizedBox(width: 6),
                Pill(cycle),
                if (g.isGroup) ...[
                  const SizedBox(width: 6),
                  Pill('${g.items.length} 个批次', bg: kBlueBg, fg: kBlue),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _row(
              '下次到期',
              g.dueAt.isEmpty ? '—' : g.dueAt,
              valueColor: _overdue ? kRedDeep : null,
              trailing: _overdue
                  ? Pill('已逾期 ${_daysLate()} 天', bg: kRedBg, fg: kRedDeep)
                  : (g.dueAt == _today
                        ? const Pill('今天', bg: kAmberBg, fg: kAmber)
                        : null),
            ),
            _row(
              g.isGroup ? '批次（${g.items.length}）' : '批次',
              g.isGroup ? names.join('、') : (names.isEmpty ? '—' : names.first),
            ),
            if (g.notes.trim().isNotEmpty) _row('备注', g.notes.trim()),
            if (g.isGroup)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  '这是一次创建的 ${g.items.length} 条提醒：完成后各自按间隔顺延。',
                  style: tTiny,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _finish(context),
                    child: const Text('完成'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _edit(context),
                    child: const Text('编辑'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () => _cancel(context),
                child: const Text(
                  '取消提醒',
                  style: TextStyle(color: kRedDeep, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Center(
              child: Text('取消后不再提醒，记录仍会保留，可重新开启', style: tTiny),
            ),
          ],
        ),
      ),
    );
  }

  int _daysLate() {
    final d = group.dueDate;
    if (d == null) return 0;
    final n = DateTime.now().difference(d).inDays;
    return n < 0 ? 0 : n;
  }

  Widget _row(
    String label,
    String value, {
    Color? valueColor,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 74, child: Text(label, style: tSub)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: valueColor ?? kInk,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _finish(BuildContext context) async {
    final targets = group.items;
    if (targets.isEmpty) return;
    if (group.isGroup) {
      final all = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('完成提醒'),
          content: Text('这组提醒包含 ${targets.length} 个批次，要一起完成吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('只完成这一条'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '全部完成',
                style: TextStyle(fontWeight: FontWeight.w700, color: kGreen),
              ),
            ),
          ],
        ),
      );
      if (all == null) return;
      final list = all ? targets : [targets.first];
      if (context.mounted) Navigator.pop(context);
      await _finishMany(context, list);
      return;
    }
    Navigator.pop(context);
    await finishReminder(context, targets.first);
    onChanged?.call();
  }

  Future<void> _finishMany(BuildContext context, List<Reminder> list) async {
    var done = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          title: Text(
            list.length == 1 ? list.first.title : '完成 ${list.length} 条提醒',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('完成日期', style: tSub),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final d = await pickDate(ctx2, done);
                  if (d != null) setD(() => done = d);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: kLine),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    fmtDay(done),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('完成后下次到期日 = 完成日 + 各自的间隔天数。', style: tTiny),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text(
                '完成',
                style: TextStyle(fontWeight: FontWeight.w700, color: kGreen),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    for (final r in list) {
      await Repo.instance.completeReminder(r, doneAt: done);
    }
    await Notify.instance.reschedule();
    bump();
    onChanged?.call();
    if (context.mounted) {
      toast(context, list.length == 1 ? '已完成' : '已完成 ${list.length} 条');
    }
  }

  Future<void> _edit(BuildContext context) async {
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderEditPage(
          reminderId: group.head.id,
          groupId: group.isGroup ? group.head.groupId : null,
        ),
      ),
    );
    onChanged?.call();
  }

  Future<void> _cancel(BuildContext context) async {
    final ok = await confirm(
      context,
      '取消这个提醒？',
      body: group.isGroup
          ? '这组 ${group.items.length} 条提醒都会停止，数据保留，可重新开启。'
          : '取消后不再提醒，记录仍会保留，可重新开启。',
      ok: '取消提醒',
      danger: true,
    );
    if (!ok) return;
    await Repo.instance.cancelReminder(
      group.head,
      wholeGroup: group.isGroup,
    );
    await Notify.instance.reschedule();
    bump();
    onChanged?.call();
    if (context.mounted) {
      Navigator.pop(context);
      toast(context, '已取消提醒');
    }
  }
}
