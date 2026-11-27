import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../core/ui_prefs.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'common.dart';
import 'image_tile.dart';

/// 某批次的操作记录 / 拍照记录全量列表，每页 30 条，滚动到底自动加载。
class RecordListPage extends StatefulWidget {
  const RecordListPage({
    super.key,
    this.batchId,
    required this.photo,
    this.title = '',
    this.mergeOps = false,
  });
  final String? batchId;
  final bool photo;
  final String title;

  /// true = 不按批次过滤，而是把同一次「记一笔」写出的多条记录合成一行
  final bool mergeOps;

  @override
  State<RecordListPage> createState() => _RecordListPageState();
}

class _RecordListPageState extends State<RecordListPage> {
  static const _page = 30;
  final List<GardenRecord> items = [];
  final List<List<GardenRecord>> groups = [];
  final Set<String> _seenOps = {};
  Map<String, String> batchNames = {};
  bool loading = true;
  bool more = true;
  int total = 0;

  @override
  void initState() {
    super.initState();
    refreshTick.addListener(_onTick);
    _init();
  }

  @override
  void dispose() {
    refreshTick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() => _reload();

  Future<void> _reload() async {
    items.clear();
    groups.clear();
    _seenOps.clear();
    more = true;
    if (mounted) setState(() {});
    await _init();
  }

  Future<void> _init() async {
    batchNames = await Repo.instance.batchNames();
    total = await Repo.instance.recordCount(photo: widget.photo);
    await _loadMore();
  }

  /// 取下一页（30 条）。合并模式下按 opId 把整组补齐，避免一次操作被分页切开。
  Future<void> _loadMore() async {
    if (widget.mergeOps) {
      final rows = await Repo.instance.records(
        photo: widget.photo,
        limit: _page,
        offset: items.length,
      );
      items.addAll(rows);
      final added = <List<GardenRecord>>[];
      for (final r in rows) {
        final key = r.opId.isEmpty ? 'one:${r.id}' : r.opId;
        if (!_seenOps.add(key)) continue;
        final full = r.opId.isEmpty
            ? <GardenRecord>[r]
            : await Repo.instance.recordsByOp(r.opId);
        added.add(full.isEmpty ? <GardenRecord>[r] : full);
      }
      if (!mounted) return;
      setState(() {
        groups.addAll(added);
        loading = false;
        more = rows.length == _page;
      });
      return;
    }
    final rows = await Repo.instance.records(
      batchId: widget.batchId,
      photo: widget.photo,
      limit: _page,
      offset: items.length,
    );
    if (!mounted) return;
    setState(() {
      items.addAll(rows);
      loading = false;
      more = rows.length == _page;
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (more && n.metrics.pixels > n.metrics.maxScrollExtent - 240) {
      more = false;
      _loadMore();
    }
    return false;
  }

  Widget get _footerTrailing => more
      ? const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      : const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: Text('没有更多了', style: tTiny)),
        );

  @override
  Widget build(BuildContext context) {
    final count = total > 0 ? '共 $total 条' : '';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title.isEmpty
              ? (widget.photo ? '拍照记录' : '操作记录')
              : widget.title,
        ),
        actions: [
          if (count.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: Text(count, style: tTiny)),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : widget.mergeOps
          ? (groups.isEmpty
                ? const EmptyHint(text: '还没有记录')
                : NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      itemCount: groups.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i >= groups.length) return _footerTrailing;
                        final g = groups[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RecordDetailPage(
                                  items: g,
                                  index: i,
                                  groups: groups,
                                  photo: widget.photo,
                                  batchNames: batchNames,
                                ),
                              ),
                            ),
                            child: OpRecordTile(
                              records: g,
                              batchNames: batchNames,
                            ),
                          ),
                        );
                      },
                    ),
                  ))
          : items.isEmpty
          ? const EmptyHint(text: '还没有记录')
          : NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                itemCount: items.length + 1,
                itemBuilder: (ctx, i) {
                  if (i >= items.length) return _footerTrailing;
                  final r = items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecordDetailPage(
                            items: items,
                            index: i,
                            photo: widget.photo,
                            batchNames: batchNames,
                          ),
                        ),
                      ),
                      child: RecordTile(record: r),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// 单条记录详情：底部有上一条 / 下一条。
class RecordDetailPage extends StatefulWidget {
  const RecordDetailPage({
    super.key,
    required this.items,
    required this.index,
    this.groups,
    this.photo = false,
    this.batchNames = const {},
  });

  /// 当前要显示的那一组记录（同一批次内通常只有 1 条；
  /// 合并模式下是同一次操作里的多条）。
  final List<GardenRecord> items;

  /// 合并模式（今天页「近 15 天」/「全部记录」）下，按「一次操作」分好组的全量列表。
  ///
  /// 有值时上一条/下一条在**不同操作之间**切换，而不是在一次操作的多个批次之间打转
  /// ——后者每次翻页标题/产品/备注都不变，看起来像没反应。
  final List<List<GardenRecord>>? groups;
  final int index;
  final bool photo;
  final Map<String, String> batchNames;

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  /// groups 非空时表示第几次「操作」；否则是第几条「记录」。
  late int i = widget.index;
  Map<String, String> names = {};
  List<GardenRecord> siblings = [];

  List<List<GardenRecord>>? get _groups => widget.groups;

  /// 当前这次的完整一组记录（合并模式下同一次操作的多条；否则就是这一条）。
  List<GardenRecord> get _cur =>
      _groups != null ? _groups![i] : <GardenRecord>[widget.items[i]];

  GardenRecord get _head => _cur.first;

  int get _total => _groups?.length ?? widget.items.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    names = widget.batchNames.isEmpty
        ? await Repo.instance.batchNames()
        : widget.batchNames;
    final r = _head;
    if (_groups != null) {
      siblings = _cur;
    } else if (r.opId.isNotEmpty) {
      siblings = await Repo.instance.recordsByOp(r.opId);
    } else {
      siblings = [];
    }
    if (mounted) setState(() {});
  }

  String _name(String id) => names[id] ?? '未命名批次';

  Widget _batchInfo(GardenRecord r) {
    final applied = siblings.isEmpty
        ? <String>[r.batchId].where((e) => e.isNotEmpty).toList()
        : siblings.map((e) => e.batchId).toList();
    final skipped = r.opSkipped;
    if (applied.isEmpty && skipped.isEmpty) return const SizedBox.shrink();
    final singleApplied = applied.length == 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (singleApplied)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('所属批次', style: tSub),
                  )
                else
                  Pill('施用 ${applied.length}', bg: kGreenBg, fg: kGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    applied.map(_name).join('、'),
                    style: tBody.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            ValueListenableBuilder<bool>(
              valueListenable: showSkippedRecords,
              builder: (_, show, __) => !show || skipped.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Pill('本次忽略', bg: kAmberBg, fg: kAmber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              skipped.map(_name).join('、'),
                              style: tBody.copyWith(color: kAmber),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _go(int d) {
    setState(() => i += d);
    _load();
  }

  Future<void> _delete() async {
    final head = _head;
    final recs = _cur;
    final batchNamesOf = <String>[];
    for (final r in recs) {
      final n = names[r.batchId] ?? '';
      if (n.isNotEmpty && !batchNamesOf.contains(n)) batchNamesOf.add(n);
    }
    final body = [
      '${head.date} · ${head.type}',
      if (batchNamesOf.isNotEmpty) batchNamesOf.join('、'),
      '共 ${recs.length} 条记录，删除后今天页和记录列表都不再显示，图片也会一起清掉。',
    ].join('\n');
    final ok = await confirm(
      context,
      '删除这次操作？',
      body: body,
      ok: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    final int n;
    if (head.opId.isEmpty) {
      await Repo.instance.deleteRecord(head.id);
      n = 1;
    } else {
      n = await Repo.instance.deleteOp(head.opId);
    }
    if (!mounted) return;
    bump();
    toast(context, '已删除这次操作，共 $n 条记录');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = _head;
    final hasPrev = i > 0;
    final hasNext = i < _total - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.photo ? '拍照记录' : '操作记录'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                _groups == null ? '${i + 1}/$_total' : '第 ${i + 1}/$_total 次操作',
                style: tSub,
              ),
            ),
          ),
          IconButton(
            tooltip: '删除这次操作',
            icon: const Icon(Icons.delete_outline, color: kRedDeep),
            onPressed: _delete,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Row(
            children: [
              Pill(r.type, bg: kindBgOf(r.type), fg: kindFgOf(r.type)),
              const Spacer(),
              Text(r.date, style: tSub),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r.title.isEmpty ? r.type : r.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _batchInfo(r),
          if (r.images.isNotEmpty) ...[
            for (final img in r.images)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: LocalImage(
                    ref: img,
                    height: 240,
                    width: double.infinity,
                  ),
                ),
              ),
            const SizedBox(height: 4),
          ],
          if (r.products.isNotEmpty) ...[
            const SectionTitle('产品'),
            for (final p in r.products)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: cardDeco(),
                  child: Row(
                    children: [
                      Expanded(child: Text(p.name, style: tBody)),
                      Text(p.dosage, style: tSub),
                    ],
                  ),
                ),
              ),
          ] else if (r.productName.isNotEmpty) ...[
            const SectionTitle('产品'),
            Text(
              [r.productName, r.dosage].where((x) => x.isNotEmpty).join(' · '),
              style: tBody,
            ),
          ],
          if (r.effMethod.isNotEmpty) ...[
            const SectionTitle('施用方式'),
            Text(r.effMethod, style: tBody),
          ],
          if (r.notes.isNotEmpty) ...[
            const SectionTitle('备注'),
            Text(r.notes, style: tBody),
          ],
        ],
      ),
      bottomNavigationBar: (hasPrev || hasNext)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: hasPrev ? () => _go(-1) : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: Text(_groups == null ? '上一条' : '上一次'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: hasNext ? () => _go(1) : null,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: Text(_groups == null ? '下一条' : '下一次'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// 操作记录列表里「产品 用量 ＋ … · 本次施用方式」的文案。
/// 施用方式整条记录只出现一次。
String productSummary(GardenRecord r) {
  final m = r.effMethod;
  final base = r.products.isNotEmpty
      ? r.products
            .map((p) => [p.name, p.dosage].where((x) => x.isNotEmpty).join(' '))
            .where((e) => e.isNotEmpty)
            .join(' ＋ ')
      : [r.productName, r.dosage].where((x) => x.isNotEmpty).join(' ');
  if (base.isEmpty) return m;
  return m.isEmpty ? base : '$base · $m';
}

/// 列表里复用的记录卡片（操作记录与批次详情共用）。
class RecordTile extends StatelessWidget {
  const RecordTile({super.key, required this.record, this.showBatch = false});
  final GardenRecord record;
  final bool showBatch;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final photo = r.type == '拍照';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: cardDeco(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo && r.images.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LocalImage(
                ref: r.images.first,
                width: 56,
                height: 56,
                radius: 10,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: kindBgOf(r.type),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                r.type,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: kindFgOf(r.type),
                ),
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.title.isEmpty ? r.type : r.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(r.date, style: tTiny),
                  ],
                ),
                if (r.products.isNotEmpty || r.productName.isNotEmpty)
                  Text(productSummary(r), style: tSub),
                if (r.notes.isNotEmpty)
                  Text(
                    r.notes,
                    style: tSub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: kInk3),
        ],
      ),
    );
  }
}

/// 一次「记一笔」写了多个批次时，多条记录合成一行展示（施用 / 未施）。
class OpRecordTile extends StatelessWidget {
  const OpRecordTile({
    super.key,
    required this.records,
    required this.batchNames,
  });

  final List<GardenRecord> records;
  final Map<String, String> batchNames;

  String _name(String id) => batchNames[id] ?? '未命名批次';

  @override
  Widget build(BuildContext context) {
    final r = records.first;
    final multi = records.length > 1 || r.opSkipped.isNotEmpty;
    final applied = records.map((e) => _name(e.batchId)).toList();
    final skipped = r.opSkipped.map(_name).toList();
    return ListenableBuilder(
      listenable: Listenable.merge([
        appliedNameColor,
        skippedNameColor,
        showSkippedRecords,
      ]),
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: cardDeco(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: kindBgOf(r.type),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                r.type,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: kindFgOf(r.type),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.title.isEmpty ? r.type : r.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(r.date, style: tTiny),
                    ],
                  ),
                  if (r.products.isNotEmpty || r.productName.isNotEmpty)
                    Text(
                      productSummary(r),
                      style: tSub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (r.notes.isNotEmpty)
                    Text(
                      r.notes,
                      style: tSub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (applied.isNotEmpty)
                    Text(
                      '${multi ? '施用：' : ''}${applied.join('、')}',
                      style: tSub.copyWith(color: appliedNameColor.value),
                    ),
                  if (showSkippedRecords.value && skipped.isNotEmpty)
                    Text(
                      '未施：${skipped.join('、')}',
                      style: tSub.copyWith(color: skippedNameColor.value),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: kInk3),
          ],
        ),
      ),
    );
  }
}

Color kindBgOf(String type) => switch (type) {
  '施肥' => kGreenBg,
  '施药' => kBlueBg,
  '浇水' => const Color(0xFFE8F3FC),
  '拍照' => const Color(0xFFF1EFEC),
  _ => const Color(0xFFF3F2F0),
};

Color kindFgOf(String type) => switch (type) {
  '施肥' => kGreen,
  '施药' => kBlue,
  '浇水' => const Color(0xFF2A7CB8),
  '拍照' => kInk2,
  _ => kInk2,
};
