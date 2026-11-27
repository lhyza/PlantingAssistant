import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/reminder_group.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'common.dart';
import 'reminder_edit.dart';
import 'reminder_history.dart';
import 'reminder_sheet.dart';
import 'today.dart' show kindBg, kindFg;

/// 提醒面板（v2.0.0）
///
/// 两个区块：自定义提醒 / 近 15 天阶段提醒。
/// 窗口 = 到期日 ≤ 今天 + 15，且包含全部已逾期；两类用同一套三行样式。
class ReminderPanelPage extends StatefulWidget {
  const ReminderPanelPage({super.key});

  @override
  State<ReminderPanelPage> createState() => _ReminderPanelPageState();
}

class _ReminderPanelPageState extends State<ReminderPanelPage> {
  final Repo repo = Repo.instance;

  List<ReminderGroup> custom = [];
  List<ReminderGroup> stage = [];
  Map<String, String> batchNames = {};

  bool loading = true;

  @override
  void initState() {
    super.initState();
    refreshTick.addListener(_onTick);
    _load();
  }

  @override
  void dispose() {
    refreshTick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() => _load();

  String _batchName(String id) {
    final n = batchNames[id] ?? '';
    return n.isEmpty ? '已删除批次' : n;
  }

  /// 组内全部批次名，用「、」连接
  String _batchText(ReminderGroup g) {
    final seen = <String>[];
    for (final r in g.items) {
      final n = _batchName(r.batchId);
      if (!seen.contains(n)) seen.add(n);
    }
    return seen.join('、');
  }

  Future<void> _load() async {
    final all = await repo.reminders();
    final names = await repo.batchNames();
    final limit = fmtDay(DateTime.now().add(const Duration(days: 15)));

    // 窗口：到期日 ≤ 今天+15（逾期不限下限，自然全部命中）
    final rows = all
        .where(
          (r) => r.nextDueAt.isNotEmpty && r.nextDueAt.compareTo(limit) <= 0,
        )
        .toList();

    final groups = groupReminders(rows);
    final mine = <ReminderGroup>[];
    final staged = <ReminderGroup>[];
    for (final g in groups) {
      if (g.head.templateId.isEmpty) {
        mine.add(g);
      } else {
        staged.add(g);
      }
    }

    if (!mounted) return;
    setState(() {
      batchNames = names;
      custom = _sorted(mine);
      stage = _sorted(staged);
      loading = false;
    });
    reminderBadge.value = dueReminderGroupCount(all, todayStr());
  }

  /// 已逾期 → 今天 → 未来；同状态内按到期日、标题
  List<ReminderGroup> _sorted(List<ReminderGroup> list) {
    final today = todayStr();
    final copy = [...list];
    copy.sort((a, b) {
      final ka = _rank(a, today);
      final kb = _rank(b, today);
      if (ka != kb) return ka.compareTo(kb);
      final c = a.dueAt.compareTo(b.dueAt);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });
    return copy;
  }

  int _rank(ReminderGroup g, String today) {
    final d = g.dueAt;
    if (d.isEmpty) return 3;
    if (d.compareTo(today) < 0) return 0;
    if (d == today) return 1;
    return 2;
  }

  /// 状态文案：已逾期 N 天 / 今天 / N 天后
  /// （不用 relDay，它会给出「昨天」，与「已逾期 2 天」口径不一致）
  String _statusText(ReminderGroup g) {
    final due = g.dueDate;
    if (due == null) return '未设置';
    final n = daysBetween(dateOnly(DateTime.now()), dateOnly(due));
    if (n < 0) return '已逾期 ${-n} 天';
    if (n == 0) return '今天';
    return '$n 天后';
  }

  Color _statusColor(ReminderGroup g, String today) {
    final d = g.dueAt;
    if (d.isEmpty) return kInk3;
    if (d.compareTo(today) < 0) return kRedDeep;
    if (d == today) return kAmber;
    return kInk3;
  }

  String _cycleText(ReminderGroup g) {
    if (g.isOneTime) return '只做一次';
    if (g.intervalDays <= 1) return '每天';
    return '每 ${g.intervalDays} 天';
  }

  /// 第二行：循环 · 下次 MM-DD[ · 备注]
  String _line2(ReminderGroup g) {
    final parts = <String>[_cycleText(g)];
    final due = g.dueDate;
    if (due != null) parts.add('下次 ${dayFmt.format(due)}');
    final notes = g.notes.trim();
    if (notes.isNotEmpty) parts.add(notes);
    return parts.join(' · ');
  }

  /// 顶部「＋ 新建」：进提醒编辑页（按作物分组多选批次），保存后回来刷新
  Future<void> _newReminder() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ReminderEditPage()),
    );
    if (!mounted) return;
    await _load();
    await refreshReminderBadge();
    if (saved == true) {
      toast(context, '已添加提醒');
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = todayStr();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kRed,
        onRefresh: _load,
        child: loading
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 80),
                  Center(child: CircularProgressIndicator(color: kRed)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '提醒',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('逾期和近期要做的，都在这', style: tSub),
                        ],
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _newReminder,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionTitle('自定义提醒', count: custom.length),
                  if (custom.isEmpty)
                    const EmptyHint(text: '还没有自定义提醒，点右上角「新建」加一条')
                  else
                    for (final g in custom) _card(g, today),
                  const SizedBox(height: 14),
                  SectionTitle(
                    '近 15 天提醒',
                    count: stage.length,
                    trailing: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReminderHistoryPage(),
                        ),
                      ),
                      child: const Text('历史 ›'),
                    ),
                  ),
                  if (stage.isEmpty)
                    const EmptyHint(text: '给批次点「生成阶段提醒」后，这里会自动出现')
                  else
                    for (final g in stage) _card(g, today),
                ],
              ),
      ),
    );
  }

  Widget _card(ReminderGroup g, String today) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardDeco(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await openReminderSheet(
              context,
              g,
              batchName: _batchName,
              onChanged: _load,
            );
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第 1 行：徽章 + 标题 + 状态
                Row(
                  children: [
                    Pill(g.kind, bg: kindBg(g.kind), fg: kindFg(g.kind)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        g.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusText(g),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(g, today),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 第 2 行：循环 · 下次 · 备注
                Text(
                  _line2(g),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tSub,
                ),
                const SizedBox(height: 4),
                // 第 3 行：批次
                Text(
                  '批次：${_batchText(g)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tTiny,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部导航「提醒」图标上的角标数字（0 表示不显示）
final ValueNotifier<int> reminderBadge = ValueNotifier<int>(0);

/// 重新算一次角标，供 Shell 在刷新时调用
Future<void> refreshReminderBadge() async {
  final n = await reminderBadgeCount();
  if (reminderBadge.value != n) reminderBadge.value = n;
}

/// 全部批次里「已逾期 + 今天」的提醒组数
Future<int> reminderBadgeCount() async {
  final list = await Repo.instance.reminders();
  return dueReminderGroupCount(list, todayStr());
}
