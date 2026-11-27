import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/notify.dart';
import '../data/reminder_group.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'common.dart';
import 'record_edit.dart' show kindEmojiOf, RecordEditPage;
import 'reminder_edit.dart';

/// 完成提醒：一个弹窗里选完成日期、勾选批次（默认全选）。
///
/// 单条提醒显示静态批次；一组提醒默认全选，可只完成其中几条。
/// 完成后若是施肥 / 施药 / 浇水，会接着打开「记一笔」补操作记录。
Future<void> openCompleteReminder(
  BuildContext pageContext,
  ReminderGroup g, {
  required String Function(String) batchName,
  VoidCallback? onChanged,
}) async {
  final items = g.items;
  if (items.isEmpty) return;
  final selected = <String>{for (final r in items) r.id};
  var done = DateTime.now();
  final ok = await showDialog<bool>(
    context: pageContext,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setD) {
        final allOn = selected.length == items.length;
        return AlertDialog(
          title: Text(
            g.isGroup ? '完成提醒' : g.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 340,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx2).height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            g.isGroup
                                ? '要完成的批次（${selected.length}/${items.length}）'
                                : '批次',
                            style: tSub,
                          ),
                        ),
                        if (g.isGroup)
                          TextButton(
                            onPressed: () => setD(() {
                              if (allOn) {
                                selected.clear();
                              } else {
                                selected.addAll(items.map((e) => e.id));
                              }
                            }),
                            child: Text(allOn ? '全不选' : '全选'),
                          ),
                      ],
                    ),
                    if (!g.isGroup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          batchName(items.first.batchId),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      ...items.map(
                        (r) => CheckboxListTile(
                          value: selected.contains(r.id),
                          onChanged: (v) => setD(() {
                            if (v == true) {
                              selected.add(r.id);
                            } else {
                              selected.remove(r.id);
                            }
                          }),
                          title: Text(
                            batchName(r.batchId),
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: r.isOneTime
                              ? const Text('只做一次', style: tTiny)
                              : null,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      items.any((r) => r.isOneTime)
                          ? '一次性提醒完成后会结束；其余按「完成日 + 各自的间隔天数」顺延。'
                          : '完成后下次到期日 = 完成日 + 各自的间隔天数。',
                      style: tTiny,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx2, true),
              child: const Text(
                '完成',
                style: TextStyle(fontWeight: FontWeight.w700, color: kGreen),
              ),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || selected.isEmpty) return;
  final list = items.where((r) => selected.contains(r.id)).toList();

  for (final r in list) {
    await Repo.instance.completeReminder(r, doneAt: done);
  }
  // 一次「完成」只写一条历史；批次顺延日一致时才记具体日期
  final next = list
      .where((r) => !r.isOneTime)
      .map((r) => r.nextDueAt)
      .where((v) => v.isNotEmpty)
      .toSet();
  await Repo.instance.logReminderDone(
    items: list,
    done: done,
    nextDueAt: next.length == 1 ? next.first : '',
  );
  await Notify.instance.reschedule();
  bump();
  onChanged?.call();

  final isOp = const {'施肥', '施药', '浇水'}.contains(g.kind);
  if (!isOp) {
    if (pageContext.mounted) {
      toast(pageContext, list.length == 1 ? '已完成' : '已完成 ${list.length} 条');
    }
    return;
  }
  final ids = <String>[];
  for (final r in list) {
    if (!ids.contains(r.batchId)) ids.add(r.batchId);
  }
  // 批次可能已经被删掉，过滤后再进记一笔
  final alive = <String>[];
  for (final id in ids) {
    if (await Repo.instance.batch(id) != null) alive.add(id);
  }
  if (alive.isEmpty) {
    if (pageContext.mounted) {
      toast(pageContext, '批次已不存在，未生成操作记录');
    }
    return;
  }
  if (!pageContext.mounted) return;
  await Navigator.push(
    pageContext,
    MaterialPageRoute(
      builder: (_) => RecordEditPage(
        batchIds: alive,
        type: g.kind,
        date: fmtDay(done),
        title: g.title,
        fromReminder: g.title,
      ),
    ),
  );
}

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
      pageContext: context,
      batchName: batchName,
      onChanged: onChanged,
    ),
  );
}

class _ReminderSheet extends StatelessWidget {
  const _ReminderSheet({
    required this.group,
    required this.pageContext,
    required this.batchName,
    this.onChanged,
  });

  final ReminderGroup group;

  /// 打开 sheet 的页面 context，用于关闭 sheet 后弹窗 / 跳转
  final BuildContext pageContext;
  final String Function(String) batchName;
  final VoidCallback? onChanged;

  String get _today => todayStr();

  bool get _overdue =>
      group.dueAt.isNotEmpty && group.dueAt.compareTo(_today) < 0;

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
                  style: TextStyle(
                    color: kRedDeep,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Center(child: Text('取消后不再提醒，记录仍会保留，可重新开启', style: tTiny)),
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
    if (group.items.isEmpty) return;
    Navigator.pop(context);
    await openCompleteReminder(
      pageContext,
      group,
      batchName: batchName,
      onChanged: onChanged,
    );
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
    await Repo.instance.cancelReminder(group.head, wholeGroup: group.isGroup);
    await Notify.instance.reschedule();
    bump();
    onChanged?.call();
    if (context.mounted) {
      Navigator.pop(context);
      toast(context, '已取消提醒');
    }
  }
}
