import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'batch_detail.dart';
import 'batch_edit.dart';
import 'common.dart';
import 'today.dart' show kindFg;

class BatchListPage extends StatefulWidget {
  const BatchListPage({super.key});
  @override
  State<BatchListPage> createState() => _BatchListPageState();
}

class _BatchListPageState extends State<BatchListPage> {
  final Repo repo = Repo.instance;
  List<Crop> crops = [];
  List<Batch> batches = [];
  Map<String, StageSnapshot> snaps = {};
  Map<String, int> openReminders = {};
  Map<String, int> potDead = {};
  Map<String, int> potStunt = {};
  String cropId = '';

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

  Future<void> _load() async {
    final cs = await repo.cropsForBrowse();
    final all = await repo.batches();
    final map = <String, StageSnapshot>{};
    final rems = <String, int>{};
    final dead = <String, int>{};
    final stunt = <String, int>{};
    for (final b in all) {
      map[b.id] = await repo.snapshot(b);
      final list = await repo.reminders(batchId: b.id);
      rems[b.id] = list.length;
      final ps = await repo.potStats(b.id);
      dead[b.id] = ps.dead;
      stunt[b.id] = ps.stunted;
    }
    if (!mounted) return;
    setState(() {
      crops = cs;
      batches = all;
      snaps = map;
      openReminders = rems;
      potDead = dead;
      potStunt = stunt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = batches
        .where((b) => cropId.isEmpty || b.crop == cropId)
        .toList();
    final groups = <String, List<Batch>>{};
    for (final b in shown) {
      groups.putIfAbsent(b.crop, () => []).add(b);
    }
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kRed,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '批次',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('按花架、窗台或区域管理', style: tSub),
                  ],
                ),
                const Spacer(),
                if (batches.length > 1)
                  IconButton(
                    tooltip: '合并批次',
                    onPressed: _mergeDialog,
                    icon: const Icon(Icons.merge_outlined),
                  ),
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BatchEditPage()),
                    );
                    _load();
                  },
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
            if (crops.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('全部', '全部', cropId.isEmpty, () {
                      setState(() => cropId = '');
                    }),
                    ...crops.map(
                      (c) => _chip(
                        '${c.emoji} ${c.name}',
                        c.id,
                        cropId == c.id,
                        () {
                          setState(() => cropId = c.id);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyHint(text: '还没有批次。点「新建」建一个，比如「阳台花架 12 盆」'),
              ),
            for (final entry in groups.entries) ...[
              SectionTitle(
                _cropName(entry.key),
                count: entry.value.length,
                trailing: Text(
                  '${entry.value.fold<int>(0, (a, b) => a + b.potCount)} ${_unit(entry.key)}',
                  style: tTiny,
                ),
              ),
              ...entry.value.map((b) => _batchCard(b)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String id, bool on, VoidCallback tap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: on ? kRedBg : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? kRed : kLine, width: on ? 1.4 : 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? kRedDeep : kInk2,
            ),
          ),
        ),
      ),
    );
  }

  String _cropName(String id) {
    for (final c in crops) {
      if (c.id == id) return '${c.emoji} ${c.name}';
    }
    return '未分类';
  }

  String _unit(String id) {
    for (final c in crops) {
      if (c.id == id) return c.unit;
    }
    return '盆';
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
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorOf(b.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b.name,
                      style: tTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, size: 20, color: kInk3),
                    onSelected: (v) async {
                      if (v == 'edit') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BatchEditPage(batchId: b.id),
                          ),
                        );
                        _load();
                      } else if (v == 'delete') {
                        final ok = await confirm(
                          context,
                          '删除批次？',
                          body: '批次下的记录和提醒会一起删除，无法撤销。',
                        );
                        if (ok) {
                          await repo.softDeleteBatch(b.id);
                          _load();
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑批次')),
                      PopupMenuItem(value: 'delete', child: Text('删除批次')),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${b.variety.isEmpty ? '未填品种' : b.variety} · ${b.location.isEmpty ? '未填位置' : b.location}'
                      '${b.status.isEmpty ? '' : ' · ${b.status}'}',
                      style: tSub,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(
                          '${s?.dayInCycle ?? 0} 天',
                          bg: const Color(0xFFF5F3F0),
                          fg: kInk2,
                        ),
                        Pill(
                          '${b.potCount} ${_unit(b.crop)}',
                          bg: const Color(0xFFF5F3F0),
                          fg: kInk2,
                        ),
                        if (stage != null)
                          Pill(stage.name, bg: kGreenBg, fg: kGreen),
                        if ((openReminders[b.id] ?? 0) > 0)
                          Pill(
                            '${openReminders[b.id]} 条待办',
                            bg: kAmberBg,
                            fg: kAmber,
                          ),
                        if ((potDead[b.id] ?? 0) > 0)
                          Pill(
                            '已死亡 ${potDead[b.id]} 盆',
                            bg: kRedBg,
                            fg: kRedDeep,
                          ),
                        if ((potStunt[b.id] ?? 0) > 0)
                          Pill(
                            '僵苗 ${potStunt[b.id]} 盆',
                            bg: kAmberBg,
                            fg: kAmber,
                          ),
                        if (b.stuntedSince != null)
                          const Pill('进度暂停', bg: kAmberBg, fg: kAmber),
                      ],
                    ),
                    if (b.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        b.notes,
                        style: tSub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mergeDialog() async {
    var target = batches.first.id;
    final picked = <String>{};
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx2).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '合并批次',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('把几个批次并成一个：苗数相加，记录和提醒都会转过去。', style: tSub),
                const SizedBox(height: 12),
                const Text(
                  '合并到',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kInk2,
                  ),
                ),
                const SizedBox(height: 6),
                ...batches.map(
                  (b) => RadioListTile<String>(
                    value: b.id,
                    groupValue: target,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: kRed,
                    title: Text(b.name, style: tBody),
                    onChanged: (v) => setSheet(() => target = v!),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '要合并进来的批次',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kInk2,
                  ),
                ),
                const SizedBox(height: 6),
                ...batches
                    .where((b) => b.id != target)
                    .map(
                      (b) => CheckboxListTile(
                        value: picked.contains(b.id),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: kRed,
                        title: Text(b.name, style: tBody),
                        subtitle: Text(
                          '${b.potCount} ${_unit(b.crop)}',
                          style: tTiny,
                        ),
                        onChanged: (v) => setSheet(
                          () => v == true
                              ? picked.add(b.id)
                              : picked.remove(b.id),
                        ),
                      ),
                    ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: picked.isEmpty
                        ? null
                        : () async {
                            Navigator.pop(ctx2);
                            await repo.mergeBatches(picked.toList(), target);
                            bump();
                            _load();
                            if (mounted)
                              toast(context, '已合并 ${picked.length} 个批次');
                          },
                    child: const Text('确认合并'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
