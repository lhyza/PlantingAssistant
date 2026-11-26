import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'common.dart';
import 'today.dart' show kindBg, kindFg;

/// 提醒历史：一次「完成」动作一条，按日期倒序分组
class ReminderHistoryPage extends StatefulWidget {
  const ReminderHistoryPage({super.key});

  @override
  State<ReminderHistoryPage> createState() => _ReminderHistoryPageState();
}

class _ReminderHistoryPageState extends State<ReminderHistoryPage> {
  static const int _page = 50;

  final Repo repo = Repo.instance;
  final ScrollController _scroll = ScrollController();

  List<ReminderLog> logs = [];
  bool loading = true;
  bool more = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!more || loading) return;
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final rows = await repo.reminderLogs(limit: _page);
    if (!mounted) return;
    setState(() {
      logs = rows;
      more = rows.length == _page;
      loading = false;
    });
  }

  Future<void> _loadMore() async {
    setState(() => loading = true);
    final rows = await repo.reminderLogs(limit: _page, offset: logs.length);
    if (!mounted) return;
    setState(() {
      logs = [...logs, ...rows];
      more = rows.length == _page;
      loading = false;
    });
  }

  Future<void> _delete(ReminderLog log) async {
    final ok = await confirm(
      context,
      '删除这条历史？',
      body: '只删掉这条完成记录，提醒本身不受影响。',
      ok: '删除',
      danger: true,
    );
    if (!ok) return;
    await repo.deleteReminderLog(log.id);
    if (!mounted) return;
    setState(() => logs = logs.where((e) => e.id != log.id).toList());
    toast(context, '已删除这条历史');
  }

  @override
  Widget build(BuildContext context) {
    // 按 doneAt 分组，保持倒序
    final groups = <String, List<ReminderLog>>{};
    for (final l in logs) {
      groups.putIfAbsent(l.doneAt, () => []).add(l);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: const Text('提醒历史')),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          if (logs.isEmpty && !loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: EmptyHint(text: '还没有完成记录。在提醒上点完成后，这里会留下记录'),
            )
          else
            for (final k in keys) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                child: Text(
                  _dayTitle(k),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                  ),
                ),
              ),
              for (final l in groups[k]!) _card(l),
            ],
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (!more && logs.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('没有更多了', style: tTiny)),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _dayTitle(String day) {
    final d = parseDay(day);
    return d == null ? day : prettyDate(d);
  }

  Widget _card(ReminderLog l) {
    final bg = kindBg(l.kind);
    final fg = kindFg(l.kind);
    final note = l.notes.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: cardDeco(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Pill(l.kind, bg: bg, fg: fg),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        l.title.isEmpty ? '未命名提醒' : l.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '备注：$note',
                          style: tTiny,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '批次：${l.batchNames.isEmpty ? '未命名批次' : l.batchNames}',
                  style: tSub,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除这条历史',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 19, color: kInk3),
            onPressed: () => _delete(l),
          ),
        ],
      ),
    );
  }
}
