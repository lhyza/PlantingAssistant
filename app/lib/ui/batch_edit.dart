import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'common.dart';

class BatchEditPage extends StatefulWidget {
  const BatchEditPage({super.key, this.batchId});
  final String? batchId;
  @override
  State<BatchEditPage> createState() => _BatchEditPageState();
}

class _BatchEditPageState extends State<BatchEditPage> {
  final Repo repo = Repo.instance;
  final _name = TextEditingController();
  final _variety = TextEditingController();
  final _location = TextEditingController();
  final _pots = TextEditingController(text: '1');
  String photoMode = 'batch';
  final _notes = TextEditingController();
  final _status = TextEditingController(text: '进行中');

  List<Crop> crops = [];
  List<Variety> varieties = [];
  List<Stage> stages = [];
  String stageId = '';
  bool stageTouched = false;
  final _elapsed = TextEditingController(text: '0');
  String cropId = '';
  String color = '#D9534F';
  String plantDate = todayStr();
  String cycleStart = '03-01';
  int season = 0;
  bool loading = true;
  bool customVariety = false;

  Batch? origin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    crops = await repo.cropsForBrowse();
    final def = await repo.defaultCrop();
    if (widget.batchId != null) {
      origin = await repo.batch(widget.batchId!);
    }
    cropId = origin?.crop ?? def?.id ?? '';
    if (origin != null) {
      _name.text = origin!.name;
      _variety.text = origin!.variety;
      _location.text = origin!.location;
      _pots.text = '${origin!.potCount}';
      photoMode = origin!.photoMode;
      _notes.text = origin!.notes;
      _status.text = origin!.status;
      color = origin!.color;
      plantDate = origin!.plantDate.isEmpty ? todayStr() : origin!.plantDate;
      cycleStart = origin!.cycleStartDate.isEmpty
          ? _defaultCycle()
          : origin!.cycleStartDate;
      season = origin!.season;
    } else {
      cycleStart = _defaultCycle();
    }
    varieties = cropId.isEmpty ? [] : await repo.varieties(cropId);
    final n = crop?.seasonCount ?? 1;
    if (season >= n) season = 0;
    if (n > 1) {
      final st = crop!.seasons[season].start;
      if (st.isNotEmpty) cycleStart = st;
    }
    stages = cropId.isEmpty
        ? []
        : await repo.stages(cropId, season: n > 1 ? season : null);
    if (stages.isNotEmpty) {
      if (origin != null) {
        final snap = await repo.snapshot(origin!);
        final st = snap?.stage;
        if (st != null) {
          stageId = st.id;
          _elapsed.text = '${((snap?.dayInStage ?? 1) - 1).clamp(0, 999)}';
        } else {
          stageId = stages.first.id;
        }
      } else {
        stageId = stages.first.id;
      }
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  String _defaultCycle() {
    for (final c in crops) {
      if (c.id == cropId && c.cycleStart.isNotEmpty) return c.cycleStart;
    }
    return '03-01';
  }

  Crop? get crop {
    for (final c in crops) {
      if (c.id == cropId) return c;
    }
    return null;
  }

  bool get perennial => crop?.isPerennial ?? false;

  Future<void> _pickCrop(String id) async {
    setState(() {
      cropId = id;
      season = 0;
      cycleStart = _defaultCycle();
      customVariety = false;
    });
    varieties = await repo.varieties(id);
    setState(() {});
  }

  Stage? get curStage {
    for (final s in stages) {
      if (s.id == stageId) return s;
    }
    return stages.isEmpty ? null : stages.first;
  }

  DateTime? _baseDate() {
    if (perennial) {
      final parts = cycleStart.split('-');
      if (parts.length != 2) return null;
      final m = int.tryParse(parts[0]);
      final d = int.tryParse(parts[1]);
      if (m == null || d == null) return null;
      final now = DateTime.now();
      var base = DateTime(now.year, m, d);
      if (base.isAfter(now)) base = DateTime(now.year - 1, m, d);
      return dateOnly(base);
    }
    return parseDay(plantDate);
  }

  Future<void> _pickSeason(int i) async {
    final c = crop;
    if (c == null) return;
    setState(() {
      season = i;
      final st = c.seasons[i].start;
      if (st.isNotEmpty) cycleStart = st;
      loading = true;
    });
    stages = await repo.stages(c.id, season: i);
    setState(() {
      stageId = stages.isEmpty ? '' : stages.first.id;
      _elapsed.text = '0';
      stageTouched = false;
      loading = false;
    });
  }

  Future<void> _pickStage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            const Text(
              '现在处于哪个阶段？',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('不确定就选第一个，之后 App 会按日期自动往后推', style: tTiny),
            const SizedBox(height: 10),
            ...stages.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  decoration: cardDeco(
                    color: s.id == stageId ? kRedBg : Colors.white,
                    border: s.id == stageId ? const Color(0xFFF6C9CF) : kLine,
                  ),
                  child: ListTile(
                    onTap: () => Navigator.pop(ctx, s.id),
                    title: Text(
                      s.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '第 ${s.startDay} ~ ${s.endDay} 天 · 共 ${s.days} 天',
                      style: tTiny,
                    ),
                    trailing: s.id == stageId
                        ? const Icon(Icons.check_circle, color: kRed, size: 20)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        stageId = picked;
        stageTouched = true;
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, '给这批起个名字吧');
      return;
    }
    final vName = _variety.text.trim();
    var vid = '';
    if (vName.isNotEmpty) {
      final v = await repo.ensureVariety(cropId, vName);
      vid = v.id;
    }
    final b = origin ?? Batch(id: newId('bat'), crop: cropId);
    b.crop = cropId;
    b.name = name;
    b.variety = vName;
    b.varietyId = vid;
    b.plantDate = perennial ? '' : plantDate;
    b.cycleStartDate = perennial ? cycleStart : '';
    b.season = (crop?.seasonCount ?? 1) > 1 ? season : 0;
    b.location = _location.text.trim();
    b.potCount = int.tryParse(_pots.text.trim()) ?? 1;
    b.photoMode = photoMode;
    b.notes = _notes.text.trim();
    b.status = _status.text.trim().isEmpty ? '进行中' : _status.text.trim();
    b.color = color;
    if (stages.isNotEmpty) {
      final st = curStage;
      if (st != null) {
        if (widget.batchId == null && !stageTouched) {
          b.growthOffsetDays = 0;
        } else {
          final base = _baseDate();
          if (base != null) {
            final elapsed = (int.tryParse(_elapsed.text.trim()) ?? 0).clamp(
              0,
              st.days - 1,
            );
            final days = daysBetween(base, DateTime.now()) + 1;
            b.growthOffsetDays = days - (st.startDay + elapsed);
          }
        }
      }
    }
    if (b.sortOrder == 0)
      b.sortOrder = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000;
    await repo.saveBatch(b);
    bump();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.batchId == null ? '新建批次' : '编辑批次'),
        actions: [
          TextButton(
            onPressed: _save,
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
                const FormLabel('种什么', required: true),
                ChoiceRow(
                  options: crops.map((c) => '${c.emoji} ${c.name}').toList(),
                  value: crop == null ? '' : '${crop!.emoji} ${crop!.name}',
                  onChanged: (v) {
                    final c = crops.firstWhere(
                      (e) => '${e.emoji} ${e.name}' == v,
                    );
                    _pickCrop(c.id);
                  },
                ),
                const FormLabel('批次名称', required: true),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: '比如：阳台花架 / 露台大盆'),
                ),
                const FormLabel('品种'),
                TextField(
                  controller: _variety,
                  onChanged: (v) {
                    final hit = varieties.any((e) => e.name == v);
                    if (customVariety == hit)
                      setState(() => customVariety = !hit);
                  },
                  decoration: InputDecoration(
                    hintText: '输入或从下面选，不会的新品种会自动加进品种库',
                    suffixIcon: PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      onSelected: (v) {
                        _variety.text = v;
                        setState(
                          () => customVariety = !varieties.any(
                            (e) => e.name == v,
                          ),
                        );
                      },
                      itemBuilder: (_) => [
                        if (varieties.isEmpty)
                          const PopupMenuItem(
                            enabled: false,
                            child: Text('暂无品种，直接输入即可'),
                          ),
                        ...varieties.map(
                          (v) => PopupMenuItem(
                            value: v.name,
                            child: Row(
                              children: [
                                Text(v.name, style: tBody),
                                if (v.incomplete) ...[
                                  const SizedBox(width: 6),
                                  const Pill('待完善', bg: kAmberBg, fg: kAmber),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (customVariety) ...[
                  const SizedBox(height: 6),
                  Text(
                    '保存后会在品种库里新建「${_variety.text.trim()}」，资料可以之后慢慢补。',
                    style: tTiny.copyWith(color: kAmber),
                  ),
                ],
                if ((crop?.seasonCount ?? 1) > 1 && crop != null) ...[
                  const FormLabel('这一批是本年第几季', required: true),
                  Builder(
                    builder: (ctx) {
                      final c = crop!;
                      final labels = [
                        for (final s in c.seasons) '${s.name} ${s.start}',
                      ];
                      return ChoiceRow(
                        options: labels,
                        value: labels[season],
                        onChanged: (v) => _pickSeason(labels.indexOf(v)),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '每季单独一条生长链：阶段按本季起始日推算，季与季之间各算各的。',
                    style: tTiny,
                  ),
                ],
                if (perennial) ...[
                  FormLabel(
                    '本年度萌芽/开始日（${crop?.name ?? ''}是多年生）',
                    required: true,
                  ),
                  PickTile(
                    label: '',
                    value: '$cycleStart（每年 3 月左右可在这里改）',
                    onTap: () async {
                      final now = DateTime.now();
                      final d = await pickDate(
                        context,
                        DateTime(
                          now.year,
                          int.parse(cycleStart.split('-')[0]),
                          int.parse(cycleStart.split('-')[1]),
                        ),
                      );
                      if (d != null) {
                        setState(
                          () => cycleStart =
                              '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Text('多年生作物按「本年度第几天」推算阶段，跨年后点一次「开启新一年」即可重新开始。', style: tTiny),
                ] else ...[
                  FormLabel('定植日期', required: true),
                  PickTile(
                    label: '',
                    value: plantDate,
                    onTap: () async {
                      final d = await pickDate(
                        context,
                        parseDay(plantDate) ?? DateTime.now(),
                      );
                      if (d != null) setState(() => plantDate = fmtDay(d));
                    },
                  ),
                ],
                if (stages.isNotEmpty) ...[
                  const FormLabel('当前阶段'),
                  PickTile(
                    label: '',
                    value: curStage == null
                        ? '未设置'
                        : '${curStage!.name}（第 ${curStage!.startDay} ~ ${curStage!.endDay} 天）',
                    hint: '默认第一阶段，已经养了一段时间就在这改',
                    onTap: _pickStage,
                  ),
                  const SizedBox(height: 10),
                  FormLabel('这一阶段已经过了几天'),
                  TextField(
                    controller: _elapsed,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => stageTouched = true),
                    decoration: const InputDecoration(
                      hintText: '0',
                      suffixText: '天',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '新装 App 时苗往往已经长了一段时间：把「当前阶段」和「已过几天」调对，提醒就会从今天开始正确往后推。',
                    style: tTiny,
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FormLabel('数量'),
                          TextField(
                            controller: _pots,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              suffixText: crop?.unit ?? '盆',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FormLabel('状态'),
                          TextField(
                            controller: _status,
                            decoration: const InputDecoration(hintText: '进行中'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const FormLabel('拍照模式'),
                ChoiceRow(
                  options: const ['按批次', '按盆'],
                  value: photoMode == 'pot' ? '按盆' : '按批次',
                  onChanged: (v) => setState(
                    () => photoMode = v == '按盆' ? 'pot' : 'batch',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    photoMode == 'pot'
                        ? '拍照时会让你选这是第几盆，方便逐盆看长势'
                        : '整批一起拍，不区分盆号（想逐盆记录就切到「按盆」）',
                    style: tTiny,
                  ),
                ),
                const FormLabel('摆放位置'),
                TextField(
                  controller: _location,
                  decoration: const InputDecoration(hintText: '南阳台 / 花架第二层'),
                ),
                const FormLabel('颜色标记'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kColors.map((c) {
                    final on = c == color;
                    return GestureDetector(
                      onTap: () => setState(() => color = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: colorOf(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: on ? kInk : Colors.white,
                            width: on ? 2.5 : 1,
                          ),
                        ),
                        child: on
                            ? const Icon(
                                Icons.check,
                                size: 15,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const FormLabel('备注'),
                AutoField(controller: _notes, hint: '苗从哪来、用的什么土、特殊注意事项…'),
                const SizedBox(height: 22),
                FilledButton(onPressed: _save, child: const Text('保存批次')),
                const SizedBox(height: 8),
                Text(
                  '数据只保存在这台手机里，记得偶尔去「我的 → 数据管理」导出一份备份。',
                  style: tTiny,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}
