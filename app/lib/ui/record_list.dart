import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'common.dart';
import 'image_tile.dart';

/// 某批次的操作记录 / 拍照记录全量列表，每页 30 条，滚动到底自动加载。
class RecordListPage extends StatefulWidget {
  const RecordListPage({
    super.key,
    required this.batchId,
    required this.photo,
    this.title = '',
  });
  final String batchId;
  final bool photo;
  final String title;

  @override
  State<RecordListPage> createState() => _RecordListPageState();
}

class _RecordListPageState extends State<RecordListPage> {
  static const _page = 30;
  final List<GardenRecord> items = [];
  bool loading = true;
  bool more = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty
            ? (widget.photo ? '拍照记录' : '操作记录')
            : widget.title),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : items.isEmpty
          ? const EmptyHint(text: '还没有记录')
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (more && n.metrics.pixels > n.metrics.maxScrollExtent - 240) {
                  more = false;
                  _load();
                }
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                itemCount: items.length + (more ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= items.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
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
    this.photo = false,
  });
  final List<GardenRecord> items;
  final int index;
  final bool photo;

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  late int i = widget.index;

  @override
  Widget build(BuildContext context) {
    final r = widget.items[i];
    final hasPrev = i > 0;
    final hasNext = i < widget.items.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.photo ? '拍照记录' : '操作记录'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text('${i + 1}/${widget.items.length}', style: tSub),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Row(
            children: [
              Pill(
                r.type,
                bg: kindBgOf(r.type),
                fg: kindFgOf(r.type),
              ),
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
          if (r.images.isNotEmpty) ...[
            for (final img in r.images)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: LocalImage(ref: img, height: 240, width: double.infinity),
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
                      Text(
                        [p.dosage, p.method]
                            .where((x) => x.isNotEmpty)
                            .join(' · '),
                        style: tSub,
                      ),
                    ],
                  ),
                ),
              ),
          ] else if (r.productName.isNotEmpty) ...[
            const SectionTitle('产品'),
            Text(
              [r.productName, r.dosage, r.method]
                  .where((x) => x.isNotEmpty)
                  .join(' · '),
              style: tBody,
            ),
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
                        onPressed: hasPrev
                            ? () => setState(() => i -= 1)
                            : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: const Text('上一条'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: hasNext
                            ? () => setState(() => i += 1)
                            : null,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: const Text('下一条'),
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
              child: LocalImage(ref: r.images.first, width: 56, height: 56, radius: 10),
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
                if (r.products.isNotEmpty)
                  Text(
                    r.products
                        .map(
                          (e) => [e.name, e.dosage, e.method]
                              .where((x) => x.isNotEmpty)
                              .join(' '),
                        )
                        .where((e) => e.isNotEmpty)
                        .join(' ＋ '),
                    style: tSub,
                  )
                else if (r.productName.isNotEmpty)
                  Text(
                    [r.productName, r.dosage, r.method]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: tSub,
                  ),
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
