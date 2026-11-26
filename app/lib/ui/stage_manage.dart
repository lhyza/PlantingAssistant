import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'common.dart';
import 'image_tile.dart';
import 'crop_manage.dart';
import 'today.dart';

class StageListPage extends StatefulWidget {
  const StageListPage({super.key, this.cropId});
  final String? cropId;
  @override
  State<StageListPage> createState() => _StageListPageState();
}

class _StageListPageState extends State<StageListPage> {
  List<Crop> crops = [];
  String cropId = 'crop_strawberry';
  List<Stage> allStages = [];
  List<Stage> stages = [];
  Map<String, int> counts = {};
  int season = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.cropId != null) cropId = widget.cropId!;
    _loadCrops();
  }

  Future<void> _loadCrops() async {
    final cs = await Repo.instance.crops();
    if (cs.isNotEmpty && !cs.any((c) => c.id == cropId)) cropId = cs.first.id;
    setState(() {
      crops = cs;
    });
    await _loadStages();
  }

  Future<void> _loadStages() async {
    final ss = await Repo.instance.stages(cropId);
    final m = <String, int>{};
    for (final s in ss) {
      m[s.id] = await Repo.instance.stageReminderCount(s.id);
    }
    // 作物换季了/季被删了 → 回到第 1 季
    final crop = crops.where((c) => c.id == cropId).firstOrNull;
    final n = crop?.seasonCount ?? 1;
    if (season >= n) season = 0;
    final list = n <= 1
        ? ss
        : ss.where((e) => e.season == season).toList();
    if (mounted) {
      setState(() {
        allStages = ss;
        stages = list;
        counts = m;
        loading = false;
      });
    }
  }

  Future<void> _copyFromPrev(Crop crop) async {
    if (season <= 0) {
      toast(context, '第 1 季没有上一季可复制');
      return;
    }
    final ok = await confirm(
      context,
      '从「${crop.seasons[season - 1].name}」复制阶段？',
      body: '会把上一季的阶段和提醒模板整套复制过来，已在目标季的阶段不会被覆盖。',
      ok: '复制',
    );
    if (!ok) return;
    final r = await Repo.instance.copySeasonStages(cropId, season - 1, season);
    await _loadStages();
    if (!mounted) return;
    if (r.copied == 0) {
      toast(context, '这套阶段已经在当前季了，没有复制');
    } else if (r.skipped > 0) {
      toast(context, '已复制 ${r.copied} 个阶段，跳过 ${r.skipped} 个同名阶段');
    } else {
      toast(context, '已复制 ${r.copied} 个阶段');
    }
  }

  @override
  Widget build(BuildContext context) {
    final crop = crops.where((c) => c.id == cropId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('生产阶段管理'),
        actions: [
          IconButton(
            tooltip: '作物管理',
            icon: const Icon(Icons.eco_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CropListPage()),
              );
              await _loadCrops();
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (crops.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        for (final c in crops)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: cropLabel(c, size: 15),
                              selected: c.id == cropId,
                              onSelected: (_) {
                                setState(() {
                                  cropId = c.id;
                                  season = 0;
                                  loading = true;
                                });
                                _loadStages();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                if ((crop?.seasonCount ?? 1) > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var i = 0; i < crop!.seasons.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(
                                        '${crop.seasons[i].name} '
                                        '${crop.seasons[i].start}',
                                      ),
                                      selected: season == i,
                                      onSelected: (_) {
                                        setState(() => season = i);
                                        _loadStages();
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (season > 0)
                          TextButton.icon(
                            onPressed: () => _copyFromPrev(crop!),
                            icon: const Icon(Icons.copy_all_outlined, size: 15),
                            label: const Text(
                              '从上一季复制',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (crop != null)
                              CropIcon(
                                iconRef: crop!.iconImage,
                                emoji: crop!.emoji,
                                size: 17,
                                fontSize: 14,
                              ),
                            if (crop != null) const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${crop?.name ?? ''}'
                                '${(crop?.seasonCount ?? 1) > 1 ? ' · ${crop!.seasons[season].name}' : ''}'
                                ' · ${stages.length} 个阶段',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final crop = crops
                              .where((c) => c.id == cropId)
                              .firstOrNull;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StageEditPage(
                                cropId: cropId,
                                cropUnit: crop?.unit ?? '盆',
                                season: season,
                              ),
                            ),
                          );
                          await _loadStages();
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新增阶段'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: stages.isEmpty
                      ? const EmptyHint(text: '这个作物还没有阶段，点右上「新增阶段」开始配置')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                          itemCount: stages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final s = stages[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final crop = crops
                                    .where((c) => c.id == cropId)
                                    .firstOrNull;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StageEditPage(
                                      stageId: s.id,
                                      cropId: cropId,
                                      cropUnit: crop?.unit ?? '盆',
                                      season: s.season,
                                    ),
                                  ),
                                );
                                await _loadStages();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(13),
                                decoration: cardDeco(),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: colorOf(s.color),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.name,
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '第 ${s.startDay}~${s.endDay} 天 · 共 ${s.days} 天 · ${counts[s.id] ?? 0} 条提醒',
                                            style: tSub,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: kInk3,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class StageEditPage extends StatefulWidget {
  const StageEditPage({
    super.key,
    this.stageId,
    required this.cropId,
    this.cropUnit = '盆',
    this.season = 0,
  });
  final String? stageId;
  final String cropId;
  final String cropUnit;
  final int season;
  @override
  State<StageEditPage> createState() => _StageEditPageState();
}

class _StageEditPageState extends State<StageEditPage> {
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _fert = TextEditingController();
  final _pest = TextEditingController();
  final _tips = TextEditingController();
  Stage? origin;
  String color = kColors.first;
  List<StageReminder> templates = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.stageId != null) {
      origin = await Repo.instance.stageById(widget.stageId!);
      final o = origin;
      if (o != null) {
        _name.text = o.name;
        _start.text = '${o.startDay}';
        _end.text = '${o.endDay}';
        _fert.text = o.fertilizerPlan;
        _pest.text = o.pestControl;
        _tips.text = o.operationTips;
        color = o.color.isEmpty ? kColors.first : o.color;
      }
      final t = await Repo.instance.stageReminders(widget.stageId!);
      if (mounted) setState(() => templates = t);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, '阶段名不能空');
      return;
    }
    final s =
        origin ??
        Stage(
          id: newId('stage'),
          crop: widget.cropId,
          sortOrder: 500,
          startDay: 0,
          endDay: 0,
          name: '',
        );
    s.name = _name.text.trim();
    s.startDay = int.tryParse(_start.text.trim()) ?? 0;
    s.endDay = int.tryParse(_end.text.trim()) ?? s.startDay;
    if (s.endDay < s.startDay) s.endDay = s.startDay;
    s.fertilizerPlan = _fert.text.trim();
    s.pestControl = _pest.text.trim();
    s.operationTips = _tips.text.trim();
    s.color = color;
    s.season = origin?.season ?? widget.season;
    await Repo.instance.saveStage(s);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final o = origin;
    if (o == null) return;
    final ok = await confirm(
      context,
      '删除「${o.name}」？',
      body: '这个阶段和它的 ${templates.length} 条提醒模板都会被删掉；'
          '已经生成过的提醒和记录不受影响。',
      ok: '删除',
      danger: true,
    );
    if (!ok) return;
    await Repo.instance.deleteStage(o.id);
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, '已删除阶段');
  }

  Future<void> _editTemplate([StageReminder? t]) async {
    if (origin == null) {
      toast(context, '先保存阶段，再配提醒');
      return;
    }
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _TemplateSheet(stageId: origin!.id, template: t),
    );
    if (r == true) {
      final list = await Repo.instance.stageReminders(origin!.id);
      if (mounted) setState(() => templates = list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stageId == null ? '新增阶段' : '阶段设置'),
        actions: [
          if (widget.stageId != null)
            IconButton(
              tooltip: '删除阶段',
              onPressed: loading ? null : _delete,
              icon: const Icon(Icons.delete_outline, color: kRedDeep),
            ),
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
                const FormLabel('阶段名称', required: true),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: '催花/花芽分化期'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FormLabel('开始（第几天）'),
                          TextField(
                            controller: _start,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FormLabel('结束（第几天）'),
                          TextField(
                            controller: _end,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('提示：一年生作物从定植日算起；多年生作物从本年度萌芽日算起。', style: tTiny),
                const FormLabel('标记色'),
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
                const FormLabel('施肥方案'),
                AutoField(controller: _fert, hint: '这个阶段怎么施肥', minLines: 2),
                const FormLabel('病虫害预防'),
                AutoField(controller: _pest, hint: '重点防什么、怎么防', minLines: 2),
                const FormLabel('操作要点'),
                AutoField(controller: _tips, hint: '温度、水分、整枝等要点', minLines: 3),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '阶段提醒',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _editTemplate(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('新增提醒'),
                    ),
                  ],
                ),
                Text('进入这个阶段时，App 会按这些模板自动生成提醒。', style: tTiny),
                const SizedBox(height: 8),
                if (templates.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    alignment: Alignment.center,
                    decoration: cardDeco(color: const Color(0xFFFDFCFA)),
                    child: Text('还没有提醒模板', style: tSub),
                  )
                else
                  for (final t in templates)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: cardDeco(),
                      child: Row(
                        children: [
                          Pill(t.kind, bg: kindBg(t.kind), fg: kindFg(t.kind)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '阶段第 ${t.startOffset} 天起 · 每 ${t.intervalDays} 天 × ${t.repeatCount}${t.enabled ? '' : ' · 已停用'}',
                                  style: tSub,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: kInk3,
                            ),
                            onPressed: () => _editTemplate(t),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                              color: kInk3,
                            ),
                            onPressed: () async {
                              final ok = await confirm(
                                context,
                                '删除这条提醒模板？',
                                body: t.title,
                                danger: true,
                              );
                              if (!ok) return;
                              await Repo.instance.softDelete(
                                'stage_reminders',
                                t.id,
                              );
                              final list = await Repo.instance.stageReminders(
                                origin!.id,
                              );
                              if (mounted) setState(() => templates = list);
                            },
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 22),
                FilledButton(onPressed: _save, child: const Text('保存阶段')),
              ],
            ),
    );
  }
}

class _TemplateSheet extends StatefulWidget {
  const _TemplateSheet({required this.stageId, this.template});
  final String stageId;
  final StageReminder? template;
  @override
  State<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends State<_TemplateSheet> {
  late final _title = TextEditingController(text: widget.template?.title ?? '');
  late final _offset = TextEditingController(
    text: '${widget.template?.startOffset ?? 1}',
  );
  late final _interval = TextEditingController(
    text: '${widget.template?.intervalDays ?? 7}',
  );
  late final _repeat = TextEditingController(
    text: '${widget.template?.repeatCount ?? 1}',
  );
  late final _notes = TextEditingController(text: widget.template?.notes ?? '');
  late String kind = widget.template?.kind ?? '施肥';
  late bool enabled = widget.template?.enabled ?? true;

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      toast(context, '提醒标题不能空');
      return;
    }
    final t =
        widget.template ??
        StageReminder(id: newId('sr'), stageId: widget.stageId, sortOrder: 500);
    t.kind = kind;
    t.title = _title.text.trim();
    t.startOffset = int.tryParse(_offset.text.trim()) ?? 1;
    t.intervalDays = (int.tryParse(_interval.text.trim()) ?? 7).clamp(1, 365);
    t.repeatCount = (int.tryParse(_repeat.text.trim()) ?? 1).clamp(1, 50);
    t.notes = _notes.text.trim();
    t.enabled = enabled;
    await Repo.instance.saveStageReminder(t);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.template == null ? '新增提醒模板' : '编辑提醒模板',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const FormLabel('类型'),
            ChoiceRow(
              options: kReminderKinds,
              value: kind,
              colors: {for (final k in kReminderKinds) k: kindFg(k)},
              onChanged: (v) => setState(() => kind = v),
            ),
            const FormLabel('标题', required: true),
            TextField(
              controller: _title,
              decoration: const InputDecoration(hintText: '高磷促花肥'),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FormLabel('阶段第几天开始'),
                      TextField(
                        controller: _offset,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FormLabel('间隔天数'),
                      TextField(
                        controller: _interval,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FormLabel('重复次数'),
                      TextField(
                        controller: _repeat,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const FormLabel('备注'),
            AutoField(controller: _notes, hint: '用量、注意事项', minLines: 2),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              activeThumbColor: kRed,
              title: const Text('启用', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '停用后不会自动生成',
                style: TextStyle(fontSize: 12, color: kInk3),
              ),
              onChanged: (v) => setState(() => enabled = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ),
    );
  }
}
