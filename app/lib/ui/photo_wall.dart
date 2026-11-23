import 'dart:io';

import 'package:flutter/material.dart';

import '../core/images.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'common.dart';

/// 拍照记录图片墙：一页看所有照片（或筛某一盆），上滑连续浏览。
class PhotoWallPage extends StatefulWidget {
  const PhotoWallPage({
    super.key,
    required this.batchId,
    this.photoMode = 'batch',
    this.potCount = 1,
    this.title = '拍照记录',
  });

  final String batchId;
  final String photoMode;
  final int potCount;
  final String title;

  @override
  State<PhotoWallPage> createState() => _PhotoWallPageState();
}

class _PhotoWallPageState extends State<PhotoWallPage> {
  static const _page = 30;
  final List<GardenRecord> items = [];
  int? pot; // null = 所有
  bool loading = true;
  bool more = true;

  bool get byPot => widget.photoMode == 'pot' && widget.potCount > 1;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      items.clear();
      more = true;
      setState(() => loading = true);
    }
    final rows = await Repo.instance.records(
      batchId: widget.batchId,
      photo: true,
      limit: _page,
      offset: items.length,
    );
    final filtered = pot == null
        ? rows
        : rows.where((e) => e.potIndex == pot).toList();
    if (!mounted) return;
    setState(() {
      items.addAll(filtered);
      loading = false;
      more = rows.length == _page;
    });
  }

  Future<void> _delete(GardenRecord r) async {
    final ok = await confirm(
      context,
      '删除这张照片？',
      body: '照片文件也会一起删掉，不能恢复。',
      ok: '删除',
      danger: true,
    );
    if (!ok) return;
    await Repo.instance.deleteRecord(r.id);
    if (!mounted) return;
    setState(() => items.removeWhere((e) => e.id == r.id));
    toast(context, '已删除');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (byPot)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                children: [
                  _chip('所有', pot == null, () {
                    setState(() => pot = null);
                    _load(reset: true);
                  }),
                  for (var i = 1; i <= widget.potCount; i++)
                    _chip('盆$i', pot == i, () {
                      setState(() => pot = i);
                      _load(reset: true);
                    }),
                ],
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: kRed))
                : items.isEmpty
                ? const EmptyHint(text: '还没有照片，点「拍照」记录一下长势')
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (more &&
                          n.metrics.pixels >
                              n.metrics.maxScrollExtent - 320) {
                        more = false;
                        _load();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                      itemCount: items.length + (more ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final r = items[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _PhotoCard(
                            record: r,
                            showPot: byPot,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PhotoViewerPage(
                                  record: r,
                                  showPot: byPot,
                                  onDelete: () => _delete(r),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, bool on, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: on ? kRedBg : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? const Color(0xFFF6C9CF) : kLine),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? kRedDeep : kInk2,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.record,
    required this.showPot,
    this.onTap,
  });

  final GardenRecord record;
  final bool showPot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final path = r.images.isEmpty ? null : Images.pathOf(r.images.first);
    final ratio = (r.imgW > 0 && r.imgH > 0) ? r.imgW / r.imgH : 4 / 3;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: cardDeco(color: Colors.white),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (path != null)
              AspectRatio(
                aspectRatio: ratio,
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              )
            else
              const AspectRatio(
                aspectRatio: 4 / 3,
                child: Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: kInk3, size: 30),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              child: Row(
                children: [
                  if (showPot && r.potIndex > 0) ...[
                    Pill('盆${r.potIndex}', bg: kGreenBg, fg: kGreen),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      r.notes.isEmpty ? r.date : '${r.date} · ${r.notes}',
                      style: tSub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: kInk3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏看图：支持双指放大，右上角删除。
class PhotoViewerPage extends StatelessWidget {
  const PhotoViewerPage({
    super.key,
    required this.record,
    this.showPot = false,
    this.onDelete,
  });

  final GardenRecord record;
  final bool showPot;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final path = r.images.isEmpty ? null : Images.pathOf(r.images.first);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          showPot && r.potIndex > 0 ? '盆${r.potIndex}' : r.date,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (onDelete != null)
            IconButton(
              tooltip: '删除',
              onPressed: () async {
                await onDelete!();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: path == null
                ? const Center(
                    child: Text('图片文件丢失', style: TextStyle(color: Colors.white70)),
                  )
                : InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.file(File(path), fit: BoxFit.contain),
                    ),
                  ),
          ),
          if (r.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Text(
                r.notes,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
