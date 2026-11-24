import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/reminder_group.dart';
import '../data/repo.dart';
import '../data/update_controller.dart';
import 'app_state.dart';
import 'batch_detail.dart';
import 'record_list.dart';
import 'reminder_sheet.dart';
import 'update_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final Repo repo = Repo.instance;
  List<Crop> crops = [];
  List<Batch> batches = [];
  List<ReminderGroup> groups = [];
  List<GardenRecord> recent = [];
  Map<String, String> batchNames = {};
  Map<String, StageSnapshot> snaps = {};
  String cropId = '';
  String stripBatchId = '';
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

  void _onTick() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final cs = await repo.cropsForBrowse();
    final def = await repo.defaultCrop();
    final sel = cropId.isEmpty ? (def?.id ?? '') : cropId;
    final bs = sel.isEmpty ? <Batch>[] : await repo.batches(cropId: sel);
    // 提醒跨作物共享，批次名要从全部批次里查，否则其它作物的提醒会显示成「批次」
    final all = await repo.batches();
    final rs = await repo.reminders();
    final rq = await repo.recordsSince(15, limit: 60);
    final map = <String, StageSnapshot>{};
    for (final b in bs) {
      map[b.id] = await repo.snapshot(b);
    }
    if (!mounted) return;
    setState(() {
      crops = cs;
      cropId = sel;
      batches = bs;
      batchNames = {for (final b in all) b.id: b.name};
      groups = groupReminders(rs);
      recent = rq;
      snaps = map;
      loading = false;
    });
  }

  Crop? get crop {
    for (final c in crops) {
      if (c.id == cropId) return c;
    }
    return null;
  }

  List<ReminderGroup> get overdue => groups
      .where(
        (g) => g.dueAt.isNotEmpty && g.dueAt.compareTo(todayStr()) < 0,
      )
      .toList();

  List<ReminderGroup> get dueToday =>
      groups.where((g) => g.dueAt == todayStr()).toList();

  List<ReminderGroup> get soon => groups.where((g) {
    final d = g.dueAt;
    if (d.isEmpty || d.compareTo(todayStr()) <= 0) return false;
    final dt = parseDay(d);
    return dt != null && dt.difference(DateTime.now()).inDays <= 3;
  }).toList();

  Widget _updateBanner() {
    final c = UpdateController.instance;
    final v = c.info?.version ?? '';
    final ready = c.readyToInstall;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UpdatePage()),
        );
        if (mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: kAmberBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kAmber.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Text('✨', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready ? '更新已下载，点这里安装' : '有新版本 $v 可以更新',
                    style: tBody.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ready ? '安装包已校验通过（版本 $v）' : '点这里查看更新内容并安装',
                    style: tTiny,
                  ),
                ],
              ),
            ),
            if (!ready)
              TextButton(
                onPressed: () async {
                  await c.markSeen();
                  if (mounted) setState(() {});
                },
                child: const Text('忽略'),
              ),
          ],
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kRed,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今天',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(prettyDate(now), style: tSub),
                  ],
                ),
                const Spacer(),
                if (overdue.isNotEmpty || dueToday.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: kRedBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '待办 ${overdue.length + dueToday.length}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: kRedDeep,
                      ),
                    ),
                  ),
              ],
            ),
            if (UpdateController.instance.unseen ||
                UpdateController.instance.readyToInstall) ...[
              const SizedBox(height: 12),
              _updateBanner(),
            ],
            const SizedBox(height: 14),
            if (crops.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: crops.map((c) {
                    final on = c.id == cropId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            cropId = c.id;
                            stripBatchId = '';
                          });
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: on
                                ? colorOf(c.color).withValues(alpha: 0.10)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: on ? colorOf(c.color) : kLine,
                              width: on ? 1.4 : 1,
                            ),
                          ),
                          child: Text(
                            '${c.emoji} ${c.name}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: on
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: on ? colorOf(c.color) : kInk2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 16),
            _stageStrip(),
            const SizedBox(height: 6),
            if (overdue.isNotEmpty) ...[
              SectionTitle('已逾期', count: overdue.length),
              ...overdue.map((r) => _reminderCard(r, overdue: true)),
            ],
            SectionTitle('今天要做', count: dueToday.length),
            if (dueToday.isEmpty)
              EmptyHint(
                text: overdue.isEmpty
                    ? '今天没有安排，去记录点什么都行 🌿'
                    : '今天的做完了，还有逾期的在上面',
              )
            else
              ...dueToday.map((r) => _reminderCard(r)),
            if (soon.isNotEmpty) ...[
              SectionTitle('接下来几天', count: soon.length),
              ...soon.take(5).map((r) => _reminderCard(r, dim: true)),
            ],
            SectionTitle(
              '近 15 天操作',
              count: recent.length,
              trailing: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RecordListPage(
                      photo: false,
                      mergeOps: true,
                      title: '全部操作记录',
                    ),
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: kInk2,
                ),
                child: const Text('全部记录 ›', style: TextStyle(fontSize: 12)),
              ),
            ),
            if (recent.isEmpty)
              const EmptyHint(text: '最近 15 天还没有记录，点右下角「记一笔」')
            else
              ..._recentTiles(),
          ],
        ),
      ),
    );
  }

  /// 顶部阶段条当前展示的批次：先看用户点选，再看有没有当天/逾期提醒，
  /// 最后回落到本季开始日最新的一批（幼苗期最需要盯）。
  Batch? get _stripBatch {
    if (batches.isEmpty) return null;
    for (final b in batches) {
      if (b.id == stripBatchId) return b;
    }
    final urgent = <String>{};
    for (final g in [...overdue, ...dueToday]) {
      for (final r in g.items) {
        urgent.add(r.batchId);
      }
    }
    for (final b in batches) {
      if (urgent.contains(b.id)) return b;
    }
    var best = batches.first;
    var bestD = repo.batchBaseDate(best);
    for (final b in batches.skip(1)) {
      final d = repo.batchBaseDate(b);
      if (d.isAfter(bestD)) {
        best = b;
        bestD = d;
      }
    }
    return best;
  }

  Widget _stageStrip() {
    final b = _stripBatch;
    if (b == null) return const SizedBox.shrink();
    final s = snaps[b.id];
    final stage = s?.stage;
    final seasonName = (crop?.seasonCount ?? 1) > 1 && b.season > 0
        ? crop!.effSeasons[b.season - 1].name
        : '';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BatchDetailPage(batchId: b.id)),
        );
        _load();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kGreen.withValues(alpha: 0.10), kGreenBg],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGreen.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(crop?.emoji ?? '🌿', style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    b.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5E8A78),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (stage != null)
                  Pill(
                    '第 ${s!.dayInStage}/${stage.days} 天',
                    bg: Colors.white,
                    fg: kGreen,
                    border: kGreen.withValues(alpha: 0.25),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    stage == null
                        ? '还没有配置阶段'
                        : (seasonName.isEmpty
                              ? stage.name
                              : '$seasonName · ${stage.name}'),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: kGreen,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (stage != null && stage.operationTips.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                stage.operationTips.split('\n').first,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF3F6355),
                  height: 1.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: stage == null
                    ? 0
                    : (s!.dayInStage / stage.days).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.7),
                valueColor: const AlwaysStoppedAnimation(kGreen),
              ),
            ),
            if (batches.length > 1) ...[
              const SizedBox(height: 9),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final x in batches)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: GestureDetector(
                          onTap: () => setState(() => stripBatchId = x.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: x.id == b.id
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: x.id == b.id
                                    ? kGreen.withValues(alpha: 0.55)
                                    : kGreen.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              '${x.name}  ${snaps[x.id]?.stage?.name ?? '未配阶段'}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: x.id == b.id
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: x.id == b.id
                                    ? kGreen
                                    : const Color(0xFF5E8A78),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _batchCard(Batch b) {
    final s = snaps[b.id];
    final stage = s?.stage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BatchDetailPage(batchId: b.id)),
          );
          _load();
        },
        child: Container(
          decoration: cardDeco(),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 74,
                decoration: BoxDecoration(
                  color: colorOf(b.color),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              b.name,
                              style: tTitle,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (b.stuntedSince != null) ...[
                            const SizedBox(width: 6),
                            const Pill('僵苗', bg: kAmberBg, fg: kAmber),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${b.variety.isEmpty ? '未填品种' : b.variety} · ${b.location.isEmpty ? '未填位置' : b.location}',
                        style: tSub,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Pill(
                            '${s?.dayInCycle ?? 0} 天',
                            bg: const Color(0xFFF5F3F0),
                            fg: kInk2,
                          ),
                          const SizedBox(width: 6),
                          Pill(
                            '${b.potCount} ${snaps.isEmpty ? '盆' : '盆'}',
                            bg: const Color(0xFFF5F3F0),
                            fg: kInk2,
                          ),
                          const SizedBox(width: 6),
                          if (stage != null)
                            Flexible(
                              child: Pill(stage.name, bg: kGreenBg, fg: kGreen),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.chevron_right, size: 18, color: kInk3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _recentTiles() {
    final map = <String, List<GardenRecord>>{};
    final order = <String>[];
    for (final r in recent) {
      final key = r.opId.isEmpty ? 'one:${r.id}' : r.opId;
      if (!map.containsKey(key)) {
        map[key] = [];
        order.add(key);
      }
      map[key]!.add(r);
    }
    return [
      for (final k in order.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecordDetailPage(
                  items: map[k]!,
                  index: 0,
                  batchNames: batchNames,
                ),
              ),
            ),
            child: OpRecordTile(
              records: map[k]!,
              batchNames: batchNames,
            ),
          ),
        ),
    ];
  }

  Widget _othersRow() {
    final others = crops.where((c) => c.id != cropId).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        children: others
            .map(
              (c) => ActionChip(
                backgroundColor: Colors.white,
                side: const BorderSide(color: kLine),
                avatar: Text(c.emoji),
                label: Text(c.name, style: tSub),
                onPressed: () {
                  setState(() {
                    cropId = c.id;
                    stripBatchId = '';
                  });
                  _load();
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _reminderCard(
    ReminderGroup g, {
    bool overdue = false,
    bool dim = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openReminderSheet(
          context,
          g,
          batchName: batchName,
          onChanged: _load,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: cardDeco(
            border: overdue ? kRed.withValues(alpha: 0.3) : null,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kindBg(g.kind),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    kindEmoji(g.kind),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: dim ? kInk2 : kInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      g.isGroup
                          ? '${g.items.length} 个批次 · ${g.kind}${g.intervalDays > 1 ? ' · 每 ${g.intervalDays} 天' : ''}'
                          : '${batchName(g.head.batchId)} · ${g.kind}${g.intervalDays > 1 ? ' · 每 ${g.intervalDays} 天' : ''}',
                      style: tSub,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (overdue)
                const Pill('已逾期', bg: kRedBg, fg: kRedDeep)
              else if (g.dueAt == todayStr())
                const Pill('今天', bg: kAmberBg, fg: kAmber)
              else
                Pill(
                  relDay(g.dueDate ?? DateTime.now()),
                  bg: const Color(0xFFF5F3F0),
                  fg: kInk2,
                ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '完成',
                icon: const Icon(
                  Icons.check_circle_outline,
                  color: kGreen,
                  size: 22,
                ),
                onPressed: () => openReminderSheet(
                  context,
                  g,
                  batchName: batchName,
                  onChanged: _load,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String batchName(String id) {
    final n = batchNames[id];
    if (n != null && n.isNotEmpty) return n;
    for (final b in batches) {
      if (b.id == id) return b.name;
    }
    return '未命名批次';
  }
}

Color kindBg(String kind) {
  switch (kind) {
    case '施肥':
      return kGreenBg;
    case '施药':
      return kBlueBg;
    case '浇水':
      return const Color(0xFFE6F4FB);
    default:
      return const Color(0xFFF5F3F0);
  }
}

Color kindFg(String kind) {
  switch (kind) {
    case '施肥':
      return kGreen;
    case '施药':
      return kBlue;
    case '浇水':
      return const Color(0xFF1284B8);
    default:
      return kInk2;
  }
}

String kindEmoji(String kind) {
  switch (kind) {
    case '施肥':
      return '🌾';
    case '施药':
      return '🧴';
    case '浇水':
      return '💧';
    default:
      return '📝';
  }
}
