import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/repo.dart';
import '../data/transfer.dart';
import 'common.dart';

const _kKinds = [
  'garden',
  'variety',
  'pest',
  'soil',
  'fertilizer',
  'medicine',
  'stage',
];
const _kKindEmoji = {
  'garden': '🌱',
  'variety': '🍓',
  'pest': '🐛',
  'soil': '🪴',
  'fertilizer': '🌾',
  'medicine': '🧴',
  'stage': '🌿',
};

class DataPage extends StatefulWidget {
  const DataPage({super.key});
  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  final Map<String, Map<String, dynamic>?> metas = {};
  final Map<String, int> counts = {};
  List<FileSystemEntity> snapshots = [];
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = <String, Map<String, dynamic>?>{};
    final c = <String, int>{};
    for (final k in _kKinds) {
      m[k] = await Repo.instance.meta(k);
      c[k] = await _countOf(k);
    }
    final dir = await Repo.instance.exportPath();
    final d = Directory('$dir/backup');
    final snaps = d.existsSync()
        ? d.listSync().whereType<Directory>().toList()
        : <FileSystemEntity>[];
    snaps.sort((a, b) => b.path.compareTo(a.path));
    if (mounted) {
      setState(() {
        metas
          ..clear()
          ..addAll(m);
        counts
          ..clear()
          ..addAll(c);
        snapshots = snaps;
        loading = false;
      });
    }
  }

  Future<int> _countOf(String kind) async {
    switch (kind) {
      case 'garden':
        return Repo.instance.count('batches');
      case 'variety':
        return Repo.instance.count('varieties');
      case 'pest':
        return Repo.instance.count('pests');
      case 'soil':
        return Repo.instance.count('soils');
      case 'stage':
        return Repo.instance.count('stages');
    }
    return 0;
  }

  Future<void> _export(String kind) async {
    setState(() => busy = true);
    try {
      final data = await Transfer.instance.buildFile(kind);
      final path = await Transfer.instance.writeFile(kind, data);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: '${kKindNames[kind]} · ${data['count'] ?? ''} 条',
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) toast(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _exportAll() async {
    setState(() => busy = true);
    try {
      final files = <XFile>[];
      for (final k in _kKinds) {
        final data = await Transfer.instance.buildFile(k);
        final path = await Transfer.instance.writeFile(k, data);
        files.add(XFile(path));
      }
      await SharePlus.instance.share(
        ShareParams(files: files, text: '种植数据全量导出（5 个文件）'),
      );
      await _load();
    } catch (e) {
      if (mounted) toast(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _backup() async {
    setState(() => busy = true);
    try {
      final dir = await Repo.instance.exportPath();
      final stamp = nowStamp()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 12);
      final target = Directory('$dir/backup/$stamp');
      await target.create(recursive: true);
      for (final k in _kKinds) {
        final data = await Transfer.instance.buildFile(k);
        final f = File('${target.path}/strawberry-$k.json');
        await f.writeAsString(_pretty(data));
      }
      if (mounted) toast(context, '已备份到本机：$stamp');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '备份失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _pretty(Map<String, dynamic> m) =>
      const JsonEncoder.withIndent('  ').convert(m);

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked.isEmpty) return;
    final p = picked.first;
    final path = p.path;
    if (path == null) {
      if (mounted) toast(context, '无法读取该文件');
      return;
    }
    setState(() => busy = true);
    try {
      var plan = await Transfer.instance.analyze(path, p.name);
      if (!plan.ok) {
        if (mounted) toast(context, plan.error ?? '文件格式不对');
        return;
      }
      plan = await Transfer.instance.diff(plan);
      if (!mounted) return;
      final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ImportPreviewPage(plan: plan)),
      );
      if (done == true) {
        await _load();
        if (mounted) toast(context, '导入完成');
      }
    } catch (e) {
      if (mounted) toast(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
        actions: [
          IconButton(
            tooltip: '导入文件',
            icon: const Icon(Icons.file_download_outlined, size: 21),
            onPressed: busy ? null : _import,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF2F8F4), Color(0xFFEAF4EE)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD9EADD)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '数据只存在这台手机上',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '卸载 App 或换手机前，一定要先导出备份。导入时按「编号 + 更新时间」逐条比较：新的覆盖、旧的跳过、没有的补上。',
                        style: tSub.copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionTitle('配置文件', count: 5),
                const SizedBox(height: 8),
                for (final k in _kKinds) _fileCard(k),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : _exportAll,
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: const Text('全部导出'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : _backup,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('本机快照'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SectionTitle('本机快照', count: snapshots.length),
                const SizedBox(height: 8),
                if (snapshots.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    alignment: Alignment.center,
                    decoration: cardDeco(color: const Color(0xFFFDFCFA)),
                    child: Text('还没有快照 · 点上面「本机快照」备份一份', style: tSub),
                  )
                else
                  for (final s in snapshots.take(5))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      decoration: cardDeco(),
                      child: Row(
                        children: [
                          const Icon(Icons.history, size: 17, color: kInk3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.path.split(RegExp(r'[\\/]')).last,
                              style: tBody,
                            ),
                          ),
                          Text('5 个文件', style: tTiny),
                        ],
                      ),
                    ),
                const SizedBox(height: 10),
                Text('提示：快照保存在本机 App 目录里，换机请用「全部导出」分享出去。', style: tTiny),
              ],
            ),
    );
  }

  Widget _fileCard(String kind) {
    final meta = metas[kind];
    final id = (meta?['libraryId'] as String?) ?? '未初始化';
    final updated = (meta?['updatedAt'] as String?) ?? '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(13, 12, 6, 12),
      decoration: cardDeco(),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kRedBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              _kKindEmoji[kind] ?? '📄',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      kKindNames[kind] ?? kind,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Pill('${counts[kind] ?? 0} 条'),
                  ],
                ),
                const SizedBox(height: 3),
                Text('$id · 更新 ${dayText(updated)}', style: tTiny),
              ],
            ),
          ),
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.share_outlined, size: 19, color: kInk2),
            onPressed: busy ? null : () => _export(kind),
          ),
        ],
      ),
    );
  }
}

class ImportPreviewPage extends StatefulWidget {
  const ImportPreviewPage({super.key, required this.plan});
  final ImportPlan plan;
  @override
  State<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends State<ImportPreviewPage> {
  late final Set<String> selected = widget.plan.diffs
      .where((d) => d.action != 'skip')
      .map(_key)
      .toSet();
  bool applying = false;

  static String _key(ImportDiff d) => '${d.action}|${d.name}';

  Future<void> _apply() async {
    setState(() => applying = true);
    try {
      await Transfer.instance.apply(widget.plan, selected: selected);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => applying = false);
        toast(context, '写入失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final importable = p.diffs.where((d) => d.action != 'skip').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('导入预览')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fileName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${kKindNames[p.kind] ?? p.kind} · 文件更新 ${dayText(p.fileUpdatedAt)}',
                  style: tSub,
                ),
                if (p.idMismatch) ...[
                  const SizedBox(height: 6),
                  Text(
                    '注意：文件里的库编号与你本机不同，按「另一个来源」处理，重名可能产生重复条目。',
                    style: TextStyle(fontSize: 12, color: kAmber, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('新增', p.add, kGreen),
              _stat('更新', p.update, kBlue),
              _stat('跳过', p.skip, kInk3),
              _stat('删除', p.remove, kRed),
            ],
          ),
          const SizedBox(height: 18),
          SectionTitle('逐条对比', count: p.diffs.length),
          const SizedBox(height: 8),
          if (p.diffs.isEmpty) const EmptyHint(text: '文件里没有条目'),
          for (final d in p.diffs)
            Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              decoration: cardDeco(),
              child: Row(
                children: [
                  if (d.action == 'skip')
                    const SizedBox(
                      width: 44,
                      child: Text(
                        '跳过',
                        style: TextStyle(fontSize: 12, color: kInk3),
                      ),
                    )
                  else
                    SizedBox(
                      width: 44,
                      child: Checkbox(
                        value: selected.contains(_key(d)),
                        activeColor: kRed,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) {
                          setState(() {
                            final k = _key(d);
                            if (v == true) {
                              selected.add(k);
                            } else {
                              selected.remove(k);
                            }
                          });
                        },
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (d.detail.isNotEmpty) Text(d.detail, style: tTiny),
                      ],
                    ),
                  ),
                  Text(
                    switch (d.action) {
                      'add' => '新增',
                      'update' => '更新',
                      'delete' => '删除',
                      _ => '跳过',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: switch (d.action) {
                        'add' => kGreen,
                        'update' => kBlue,
                        'delete' => kRed,
                        _ => kInk3,
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          10 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: kLine)),
        ),
        child: FilledButton(
          onPressed: applying || importable.isEmpty
              ? null
              : () async {
                  final ok = await confirm(
                    context,
                    '确认导入 ${selected.length} 条？',
                    body: '导入前会自动存一份快照，出问题可在「本机快照」里找回。',
                  );
                  if (ok) await _apply();
                },
          child: Text(applying ? '写入中…' : '确认导入 ${selected.length} 条'),
        ),
      ),
    );
  }

  Widget _stat(String label, int n, Color c) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$n',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: tTiny),
        ],
      ),
    );
  }
}
