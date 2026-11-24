import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'common.dart';
import 'kb_detail.dart';

class CropListPage extends StatefulWidget {
  const CropListPage({super.key});
  @override
  State<CropListPage> createState() => _CropListPageState();
}

class _CropListPageState extends State<CropListPage> {
  List<Crop> crops = [];
  Map<String, int> batchCounts = {};
  Map<String, int> stageCounts = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cs = await Repo.instance.crops(includeDisabled: true);
    final bc = <String, int>{};
    final sc = <String, int>{};
    for (final c in cs) {
      bc[c.id] = (await Repo.instance.batches(cropId: c.id)).length;
      sc[c.id] = (await Repo.instance.stages(c.id)).length;
    }
    if (mounted) {
      setState(() {
        crops = cs;
        batchCounts = bc;
        stageCounts = sc;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作物管理'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CropEditPage()),
              );
              await _load();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新增'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
              itemCount: crops.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                if (i == crops.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '想加蓝莓、番茄、辣椒？点右上「新增」填个名字就行，阶段和提醒自己配。葡萄/树莓这类一年多季的，把「一年几季」设成 2 或 3。',
                      style: tTiny,
                    ),
                  );
                }
                final c = crops[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CropEditPage(cropId: c.id),
                      ),
                    );
                    await _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: cardDeco(),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorOf(c.color).withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            c.emoji,
                            style: const TextStyle(fontSize: 20),
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
                                    c.name,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (c.isDefault) ...[
                                    const SizedBox(width: 6),
                                    const Pill('默认', bg: kRedBg, fg: kRedDeep),
                                  ],
                                  if (!c.enabled) ...[
                                    const SizedBox(width: 6),
                                    const Pill(
                                      '已停用',
                                      bg: Color(0xFFF1EFEA),
                                      fg: kInk3,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${c.isPerennial ? '多年生' : '一年生'}'
                                '${c.seasonCount > 1 ? ' · ${c.seasonCount} 季' : ''}'
                                ' · 计「${c.unit}」 · ${stageCounts[c.id] ?? 0} 个阶段'
                                ' · ${batchCounts[c.id] ?? 0} 个批次',
                                style: tSub,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: kInk3),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class CropEditPage extends StatefulWidget {
  const CropEditPage({super.key, this.cropId});
  final String? cropId;
  @override
  State<CropEditPage> createState() => _CropEditPageState();
}

class _CropEditPageState extends State<CropEditPage> {
  String image = '';
  final _name = TextEditingController();
  final _emoji = TextEditingController(text: '🌱');
  final _cycle = TextEditingController(text: '03-01');
  final _unit = TextEditingController(text: '盆');
  Crop? origin;
  bool perennial = false;
  bool enabled = true;
  int seasonCount = 1;
  final List<_SeasonEdit> seasons = [];
  bool seasonsTouched = false;
  String color = kColors[4];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.cropId != null) {
      origin = await Repo.instance.cropById(widget.cropId!);
      final o = origin;
      if (o != null) {
        _name.text = o.name;
        _emoji.text = o.emoji;
        _cycle.text = o.cycleStart;
        _unit.text = o.unit;
        perennial = o.isPerennial;
        enabled = o.enabled;
        final eff = o.effSeasons;
        seasonCount = o.seasonCount;
        seasons
          ..clear()
          ..addAll(eff.map((e) => _SeasonEdit(e.idx, e.name, e.start)));
        image = o.image;
        if (o.color.isNotEmpty) color = o.color;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, '作物名不能空');
      return;
    }
    final c = origin ?? Crop(id: newId('crop'), name: '', sortOrder: 900);
    c.name = _name.text.trim();
    c.emoji = _emoji.text.trim().isEmpty ? '🌱' : _emoji.text.trim();
    c.lifeCycle = perennial ? 'perennial' : 'annual';
    c.cycleStart = perennial ? _cycle.text.trim() : '';
    if (perennial && seasonCount > 1) {
      c.seasons = [
        for (var i = 0; i < seasonCount; i++)
          CropSeason(
            idx: i + 1,
            name: (i < seasons.length ? seasons[i].name.text.trim() : ''),
            start: (i < seasons.length ? seasons[i].start.text.trim() : ''),
          ),
      ];
    } else {
      c.seasons = [];
    }
    c.unit = _unit.text.trim().isEmpty ? '盆' : _unit.text.trim();
    c.color = color;
    c.enabled = enabled;
    c.image = image;
    await Repo.instance.saveCrop(c);
    if (mounted) Navigator.pop(context);
  }

  void _syncSeasons() {
    while (seasons.length < seasonCount) {
      final i = seasons.length + 1;
      final last = seasons.isEmpty
          ? ''
          : seasons.last.start.text.trim();
      seasons.add(_SeasonEdit(i, '$i 季', last));
    }
    while (seasons.length > seasonCount) {
      seasons.removeLast();
    }
  }

  Widget _seasonRow(int i) {
    final row = seasons[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${i + 1}', style: tSub),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: row.name,
              decoration: InputDecoration(
                hintText: i == 0 ? '夏果季' : '秋果季',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: TextField(
              controller: row.start,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: '03-01',
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _remove() async {
    final c = origin;
    if (c == null) return;
    if (c.isDefault) {
      toast(context, '默认作物不能删');
      return;
    }
    final ok = await confirm(
      context,
      '删除「${c.name}」？',
      body: '这个作物下的批次会变成「未分类」，不会删数据。',
      danger: true,
    );
    if (!ok) return;
    await Repo.instance.softDeleteCrop(c.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = origin?.isDefault ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cropId == null ? '新增作物' : '编辑作物'),
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
                const FormLabel('默认图'),
                ImageField(
                  ref: image,
                  onChanged: (v) => setState(() => image = v),
                  hint: '这个作物的品种/病虫害没单独设图时，列表和详情就用它',
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FormLabel('名称', required: true),
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(hintText: '草莓'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FormLabel('图标'),
                          TextField(
                            controller: _emoji,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const FormLabel('生命周期'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('一年生')),
                    ButtonSegment(value: true, label: Text('多年生')),
                  ],
                  selected: {perennial},
                  onSelectionChanged: isDefault
                      ? null
                      : (s) => setState(() => perennial = s.first),
                ),
                if (perennial) ...[
                  const FormLabel('一年几季'),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 季')),
                      ButtonSegment(value: 2, label: Text('2 季')),
                      ButtonSegment(value: 3, label: Text('3 季')),
                    ],
                    selected: {seasonCount},
                    onSelectionChanged: isDefault
                        ? null
                        : (v) => setState(() {
                            seasonCount = v.first;
                            _syncSeasons();
                          }),
                  ),
                  if (seasonCount == 1) ...[
                    const FormLabel('每年萌芽/开始日'),
                    TextField(
                      controller: _cycle,
                      decoration: const InputDecoration(
                        hintText: 'MM-DD，如 03-01',
                      ),
                    ),
                    Text(
                      '多年生作物按「今年这个日期」开始新一轮，休眠期后可点「开启新一季」重置。',
                      style: tTiny,
                    ),
                  ] else ...[
                    FormLabel('每季名称与起始日（共 $seasonCount 季）', required: true),
                    for (var i = 0; i < seasonCount; i++) _seasonRow(i),
                    const SizedBox(height: 4),
                    Text(
                      '日期格式 MM-DD；每年到这一天算「本季第 1 天」。不同地区季数不同时，建议直接建两个作物（如「葡萄（北方单季）」「葡萄（广西双季）」）。',
                      style: tTiny,
                    ),
                  ],
                ],
                const FormLabel('计数单位'),
                TextField(
                  controller: _unit,
                  decoration: const InputDecoration(hintText: '盆 / 株 / 棵'),
                ),
                const FormLabel('颜色'),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in kColors)
                        GestureDetector(
                          onTap: () => setState(() => color = c),
                          child: Container(
                            width: 30,
                            height: 30,
                            margin: const EdgeInsets.only(right: 10, top: 4),
                            decoration: BoxDecoration(
                              color: colorOf(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == c ? kInk : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  activeThumbColor: kRed,
                  title: const Text('启用', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '停用后新增批次时不显示，已有批次不受影响',
                    style: TextStyle(fontSize: 12, color: kInk3),
                  ),
                  onChanged: isDefault
                      ? null
                      : (v) => setState(() => enabled = v),
                ),
                const SizedBox(height: 18),
                if (origin != null && !isDefault)
                  OutlinedButton.icon(
                    onPressed: _remove,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除这个作物'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRed,
                      side: const BorderSide(color: Color(0xFFF6C9CF)),
                      minimumSize: const Size(double.infinity, 46),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SeasonEdit {
  _SeasonEdit(int idx, String name, String start)
    : _idx = idx,
      name = TextEditingController(text: name),
      start = TextEditingController(text: start);

  final int _idx;
  final TextEditingController name;
  final TextEditingController start;
}
