import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/images.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'batch_edit.dart';
import 'common.dart';
import 'image_crop.dart';
import 'image_tile.dart';

/// 底部快速记一笔：先选类型，再勾一批批次（可多选，按作物分组）
Future<void> quickRecord(BuildContext context) async {
  final batches = await Repo.instance.batches();
  final crops = await Repo.instance.crops();
  if (!context.mounted) return;
  if (batches.isEmpty) {
    final go = await confirm(
      context,
      '还没有批次',
      body: '先建一个批次，再记这一笔。',
      ok: '去新建',
      danger: false,
    );
    if (go && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BatchEditPage()),
      );
    }
    return;
  }

  final groups = <String, List<Batch>>{};
  for (final b in batches) {
    groups.putIfAbsent(b.crop, () => []).add(b);
  }
  final orderedCrops = crops.where((c) => groups.containsKey(c.id)).toList();

  String type = '施肥';
  final picked = <String>{batches.first.id};

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setSheet) {
        final pickedCount = picked.length;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx2).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx2).size.height * 0.82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '记一笔',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text('已选 $pickedCount', style: tSub),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx2),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('今天做了什么？可以一次给好几个批次记账', style: tSub),
                const SizedBox(height: 10),
                Row(
                  children: kRecordTypes.map((t) {
                    final on = t == type;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setSheet(() => type = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              color: on ? kRedBg : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: on ? kRed : kLine,
                                width: on ? 1.4 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  kindEmojiOf(t),
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: on ? kRedDeep : kInk2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      '哪些批次',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kInk2,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setSheet(() {
                        picked.clear();
                        for (final b in batches) {
                          picked.add(b.id);
                        }
                      }),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: kInk2,
                      ),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setSheet(picked.clear),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: kInk3,
                      ),
                      child: const Text('清空'),
                    ),
                  ],
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in orderedCrops) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 2),
                          child: Row(
                            children: [
                              Text(
                                '${c.emoji} ${c.name}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: kInk2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('${groups[c.id]!.length} 个批次', style: tTiny),
                            ],
                          ),
                        ),
                        ...groups[c.id]!.map((b) {
                          final on = picked.contains(b.id);
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setSheet(
                              () => on ? picked.remove(b.id) : picked.add(b.id),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: on,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    activeColor: kRed,
                                    onChanged: (v) => setSheet(
                                      () => v == true
                                          ? picked.add(b.id)
                                          : picked.remove(b.id),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(b.name, style: tBody),
                                        Text(
                                          '${b.variety} · ${b.potCount} ${c.unit}',
                                          style: tTiny,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: picked.isEmpty
                        ? null
                        : () async {
                            final ids = [...picked];
                            Navigator.pop(ctx2);
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RecordEditPage(batchIds: ids, type: type),
                              ),
                            );
                          },
                    child: Text(
                      picked.isEmpty ? '选一个批次' : '下一步（$pickedCount 个批次）',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

String kindEmojiOf(String t) {
  switch (t) {
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

class RecordEditPage extends StatefulWidget {
  const RecordEditPage({
    super.key,
    required this.batchIds,
    this.type = '施肥',
    this.recordId,
  });
  final List<String> batchIds;
  final String type;
  final String? recordId;
  @override
  State<RecordEditPage> createState() => _RecordEditPageState();
}

class _RecordEditPageState extends State<RecordEditPage> {
  final Repo repo = Repo.instance;
  final _title = TextEditingController();
  final _notes = TextEditingController();
  late String type = widget.type;
  String date = todayStr();
  final Map<String, String> stageIds = {};
  List<Batch> batchList = [];
  final List<_PRow> rows = [_PRow()];
  List<String> photos = [];
  GardenRecord? origin;
  bool loading = true;

  int imgW = 0;
  int imgH = 0;
  List<Pot> pots = [];
  Map<int, GardenRecord> latestPhotos = {};
  Map<int, int> photoCounts = {};
  int potSel = 0;

  bool get _byPot =>
      _isPhoto && batchList.length == 1 && batchList.first.photoMode == 'pot';

  String get _names =>
      batchList.isEmpty ? '' : batchList.map((b) => b.name).join('、');

  bool get _showProducts => type == '施肥' || type == '施药';
  bool get _isPhoto => type == '拍照';
  bool get _canSave => !_isPhoto || photos.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    batchList = [];
    for (final id in widget.batchIds) {
      final b = await repo.batch(id);
      if (b != null) {
        batchList.add(b);
        final snap = await repo.snapshot(b);
        stageIds[b.id] = snap?.stage?.id ?? '';
      }
    }
    if (_isPhoto && widget.batchIds.length == 1) {
      final b = batchList.isEmpty ? null : batchList.first;
      if (b != null) {
        pots = await repo.pots(b.id);
        latestPhotos = await repo.latestPhotoByPot(b.id);
        photoCounts = await repo.photoCountByPot(b.id);
        if (b.photoMode == 'pot' && pots.isNotEmpty) {
          final firstAlive = pots.where((e) => !e.dead).toList();
          potSel = (firstAlive.isNotEmpty ? firstAlive.first : pots.first).idx;
        }
      }
    }
    if (widget.recordId != null) {
      final all = await repo.records(
        batchId: widget.batchIds.first,
        limit: 500,
      );
      for (final r in all) {
        if (r.id == widget.recordId) origin = r;
      }
      if (origin != null) {
        type = origin!.type;
        date = origin!.date;
        _title.text = origin!.title;
        _notes.text = origin!.notes;
        stageIds[widget.batchIds.first] = origin!.stageId;
        photos = [...origin!.images];
        imgW = origin!.imgW;
        imgH = origin!.imgH;
        potSel = origin!.potIndex;
        if (origin!.type != '拍照') {
          final list = origin!.products.isNotEmpty
              ? origin!.products
              : (origin!.productName.isNotEmpty
                    ? [
                        RecordProduct(
                          name: origin!.productName,
                          dosage: origin!.dosage,
                          method: origin!.method.isEmpty
                              ? '灌根'
                              : origin!.method,
                        ),
                      ]
                    : <RecordProduct>[]);
          if (list.isNotEmpty) {
            rows
              ..clear()
              ..addAll(list.map((e) => _PRow(e, true)));
          }
        }
      }
    } else {
      _title.text = _defaultTitle(type);
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  String _defaultTitle(String t) {
    switch (t) {
      case '施肥':
        return '施肥';
      case '施药':
        return '打药';
      case '浇水':
        return '浇水';
      case '拍照':
        return '拍照记录';
      default:
        return '观察记录';
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim().isEmpty
        ? _defaultTitle(type)
        : _title.text.trim();
    final items = rows
        .map(
          (e) => RecordProduct(
            name: e.data.name.trim(),
            dosage: e.data.dosage.trim(),
            method: e.data.method,
          ),
        )
        .where((e) => e.name.isNotEmpty || e.dosage.isNotEmpty)
        .toList();

    if (widget.recordId != null && origin != null) {
      final r = origin!;
      _fill(r, title, items);
      r.stageId = stageIds[r.batchId] ?? r.stageId;
      await repo.saveRecord(r);
      bump();
      if (!mounted) return;
      Navigator.pop(context, r);
      return;
    }

    final targets = batchList.isEmpty
        ? widget.batchIds
        : batchList.map((b) => b.id).toList();
    GardenRecord? last;
    for (final id in targets) {
      final r = GardenRecord(id: newId('rec'), batchId: id);
      _fill(r, title, items);
      r.stageId = stageIds[id] ?? '';
      await repo.saveRecord(r);
      last = r;
    }
    bump();
    if (!mounted) return;
    Navigator.pop(context, last);
  }

  void _fill(GardenRecord r, String title, List<RecordProduct> items) {
    r.type = normRecordType(type);
    r.date = _isPhoto ? todayStr() : date;
    r.title = _isPhoto ? '拍照记录' : title;
    r.products = _isPhoto ? const [] : items;
    r.productName = (_isPhoto || items.isEmpty) ? '' : items.first.name;
    r.dosage = (_isPhoto || items.isEmpty) ? '' : items.first.dosage;
    r.method = (_isPhoto || items.isEmpty) ? '' : items.first.method;
    r.potIndex = _byPot ? potSel : 0;
    r.imgW = imgW;
    r.imgH = imgH;
    if (photos.isNotEmpty) r.images = [...photos];
    r.notes = _notes.text.trim();
  }

  Future<void> _pickMaterial(_PRow row) async {
    final cropIds = batchList.map((b) => b.crop).toSet();
    bool allowed(Supply m) =>
        !cropIds.any((c) => m.blockedFor(c));
    final fers = (await repo.materials('fertilizer'))
        .where(allowed)
        .toList();
    final meds = (await repo.materials('medicine')).where(allowed).toList();
    if (!mounted) return;
    if (fers.isEmpty && meds.isEmpty) {
      final go = await confirm(
        context,
        '库还是空的',
        body: '在「知识库 → 肥料 / 药品」里先记下常用的，之后这里就能直接选。',
        ok: '知道了',
        danger: false,
      );
      if (go) return;
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '从库中选择',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group in [('肥料', fers), ('药品', meds)])
                    if (group.$2.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Text(
                          group.$1,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: kInk2,
                          ),
                        ),
                      ),
                      ...group.$2.map(
                        (m) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(m.name, style: tBody),
                          subtitle: Text(
                            [
                              if (m.ratio.isNotEmpty) '兑水 ${m.ratio}',
                              m.method,
                            ].join(' · '),
                            style: tTiny,
                          ),
                          onTap: () {
                            row.data.name = m.name;
                            row.data.dosage = m.ratio;
                            row.data.method = m.method;
                            row.name.text = m.name;
                            row.dosage.text = m.ratio;
                            if (Supply.kMethods.contains(m.method)) {
                              row.data.method = m.method;
                            }
                            Navigator.pop(ctx);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productRow(int i) {
    final row = rows[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '产品 ${i + 1}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: kInk2,
                ),
              ),
              const Spacer(),
              if (rows.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    rows.removeAt(i).dispose();
                  }),
                  child: const Icon(Icons.close, size: 17, color: kInk3),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.name,
                  decoration: InputDecoration(
                    hintText: type == '施肥' ? '花多多 2 号' : '代森锰锌',
                    isDense: true,
                  ),
                  onChanged: (v) => row.data.name = v,
                ),
              ),
              IconButton(
                tooltip: '从知识库选择',
                onPressed: () => _pickMaterial(row),
                icon: const Icon(Icons.list_alt, size: 20, color: kRed),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.dosage,
                  decoration: const InputDecoration(
                    hintText: '用量 / 兑水比例',
                    isDense: true,
                  ),
                  onChanged: (v) => row.data.dosage = v,
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: Supply.kMethods.contains(row.data.method)
                    ? row.data.method
                    : Supply.kMethods.first,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 13, color: kInk),
                items: Supply.kMethods
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(
                  () => row.data.method = v ?? row.data.method,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _ensurePots() async {
    if (pots.isNotEmpty || batchList.length != 1) return;
    final b = batchList.first;
    final ps = await Repo.instance.pots(b.id);
    final latest = await Repo.instance.latestPhotoByPot(b.id);
    final counts = await Repo.instance.photoCountByPot(b.id);
    if (!mounted) return;
    setState(() {
      pots = ps;
      latestPhotos = latest;
      photoCounts = counts;
      if (b.photoMode == 'pot' && potSel == 0) {
        final aliveOnes = ps.where((e) => !e.dead).toList();
        if (aliveOnes.isNotEmpty) potSel = aliveOnes.first.idx;
      }
    });
  }

  Future<void> _pickPhoto() async {
    final p = await captureAndCropPhoto(context);
    if (p == null) return;
    if (!mounted) return;
    setState(() {
      photos = [p.ref];
      imgW = p.width;
      imgH = p.height;
    });
  }

  Widget _potPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text('这是哪一盆？', style: tSub),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in pots)
              GestureDetector(
                onTap: p.dead
                    ? () => toast(context, '盆${p.idx} 已标记死亡，不能再拍')
                    : () => setState(() => potSel = p.idx),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: p.dead
                        ? const Color(0xFFF3F2F0)
                        : (photoCounts.containsKey(p.idx)
                              ? kGreenBg
                              : kRedBg),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: potSel == p.idx
                          ? kInk
                          : (p.dead
                                ? kLine
                                : (photoCounts.containsKey(p.idx)
                                      ? kGreenBg
                                      : const Color(0xFFF6C9CF))),
                      width: potSel == p.idx ? 1.6 : 1,
                    ),
                  ),
                  child: Text(
                    p.dead ? '盆${p.idx}·死亡' : '盆${p.idx}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: p.dead
                          ? kInk3
                          : (photoCounts.containsKey(p.idx) ? kGreen : kRedDeep),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('绿色=拍过，红色=还没拍', style: tTiny),
        if (potSel > 0 && latestPhotos.containsKey(potSel)) ...[
          const SizedBox(height: 14),
          Text('首张', style: tSub),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LocalImage(
              ref: latestPhotos[potSel]!.images.isEmpty
                  ? ''
                  : latestPhotos[potSel]!.images.first,
              width: double.infinity,
              height: 150,
              fit: BoxFit.cover,
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _photoBox() {
    if (photos.isEmpty) {
      return GestureDetector(
        onTap: _pickPhoto,
        child: Container(
          height: 190,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLine),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_camera_outlined, size: 34, color: kInk3),
              SizedBox(height: 8),
              Text('点这里拍照', style: tSub),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: LocalImage(ref: photos.first, width: double.infinity, height: 210),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _pickPhoto,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重新拍'),
          style: TextButton.styleFrom(foregroundColor: kRed),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recordId == null ? '记一笔' : '编辑记录'),
        actions: [
          TextButton(
            onPressed: loading ? null : _save,
            child: const Text(
              '保存',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(_names, style: tSub)),
                    if (widget.recordId == null && batchList.length > 1)
                      Pill('${batchList.length} 个批次', bg: kRedBg, fg: kRedDeep),
                  ],
                ),
                const FormLabel('类型'),
                ChoiceRow(
                  options: kRecordTypes,
                  value: type,
                  onChanged: (v) async {
                    setState(() {
                      type = v;
                      if (_title.text == _defaultTitle(type) ||
                          _title.text.isEmpty ||
                          true) {
                        _title.text = _defaultTitle(v);
                      }
                    });
                    if (v == '拍照') await _ensurePots();
                  },
                ),
                if (_isPhoto) ...[
                  if (_byPot) _potPicker(),
                  const FormLabel('照片', required: true),
                  _photoBox(),
                ] else ...[
                  const FormLabel('日期'),
                  PickTile(
                    label: '',
                    value: date,
                    onTap: () async {
                      final d = await pickDate(
                        context,
                        parseDay(date) ?? DateTime.now(),
                      );
                      if (d != null) setState(() => date = fmtDay(d));
                    },
                  ),
                  const FormLabel('标题'),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(hintText: '做了什么'),
                  ),
                  if (_showProducts) ...[
                    const FormLabel('产品'),
                    ...List.generate(rows.length, _productRow),
                    TextButton.icon(
                      onPressed: () => setState(() => rows.add(_PRow())),
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('添加一项（复配）'),
                      style: TextButton.styleFrom(
                        foregroundColor: kRed,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
                const FormLabel('备注'),
                AutoField(controller: _notes, hint: '植株反应、天气、下次注意…'),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(
                    widget.recordId == null && batchList.length > 1
                        ? '保存 ${batchList.length} 条记录'
                        : '保存记录',
                  ),
                ),
              ],
            ),
    );
  }
}

/// 一个产品行：控制器与数据分开，选库回填时控制器也要一起更新。
class _PRow {
  _PRow([RecordProduct? data, bool clone = false])
    : data = data == null
          ? RecordProduct()
          : (clone
                ? RecordProduct(
                    name: data.name,
                    dosage: data.dosage,
                    method: data.method,
                  )
                : data) {
    name = TextEditingController(text: this.data.name);
    dosage = TextEditingController(text: this.data.dosage);
  }

  RecordProduct data;
  late final TextEditingController name;
  late final TextEditingController dosage;

  void dispose() {
    name.dispose();
    dosage.dispose();
  }
}
