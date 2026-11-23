import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/ai_import.dart';
import '../data/ai_prompt.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'ai_template_page.dart';
import 'common.dart';
import 'image_crop.dart';
import 'image_tile.dart';
import 'kb_detail.dart';
import 'stage_manage.dart';

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});
  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage>
    with SingleTickerProviderStateMixin {
  final Repo repo = Repo.instance;
  late final TabController _tab = TabController(length: 5, vsync: this);
  List<Crop> crops = [];
  String cropId = '';
  List<Variety> varieties = [];
  List<Pest> pests = [];
  List<Soil> soils = [];
  List<Supply> fertilizers = [];
  List<Supply> medicines = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final cs = await repo.crops();
    final def = await repo.defaultCrop();
    final sel = cropId.isEmpty ? (def?.id ?? '') : cropId;
    final vs = sel.isEmpty ? <Variety>[] : await repo.varieties(sel);
    final ps = sel.isEmpty ? <Pest>[] : await repo.pests(sel);
    final ss = sel.isEmpty ? <Soil>[] : await repo.soils(sel);
    final fers = await repo.materials('fertilizer');
    final meds = await repo.materials('medicine');
    if (!mounted) return;
    setState(() {
      crops = cs;
      cropId = sel;
      varieties = vs;
      pests = ps;
      soils = ss;
      fertilizers = fers;
      medicines = meds;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                const Text(
                  '知识库',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '生产阶段管理',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StageListPage()),
                  ),
                  icon: const Icon(Icons.timeline, size: 21),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: crops.map((c) {
                    final on = c.id == cropId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => cropId = c.id);
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: on
                                ? colorOf(c.color).withValues(alpha: 0.1)
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
                              fontSize: 12.5,
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
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tab,
            labelColor: kRedDeep,
            unselectedLabelColor: kInk2,
            indicatorColor: kRed,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: '品种'),
              Tab(text: '病虫害'),
              Tab(text: '肥料'),
              Tab(text: '药品'),
              Tab(text: '土肥'),
            ],
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: kRed))
                : TabBarView(
                    controller: _tab,
                    children: [
                      _varietyList(),
                      _pestList(),
                      _materialList(fertilizers, 'fertilizer'),
                      _materialList(medicines, 'medicine'),
                      _soilList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _varietyList() {
    return _list(
      count: varieties.length,
      label: '个品种',
      empty: '还没有品种，点右上角加一个',
      onAdd: () => _openEdit(0, null),
      onAi: () => _openAi('variety'),
      onImport: () => _importAi('variety'),
      children: varieties.map((v) {
        return _card(
          title: v.name,
          badge: v.category,
          image: v.image,
          cropImage: _cropImage,
          pending: v.imgPending,
          onImageTap: v.image.isEmpty ? null : () => _cropImageOf(
            v.image,
            (ref) async {
              v.image = ref;
              v.imgPending = false;
              await Repo.instance.saveVariety(v);
              _load();
            },
          ),
          tags: [
            if (v.sweetness.isNotEmpty) '甜度 ${v.sweetness}',
            if (v.fruitSize.isNotEmpty) v.fruitSize,
            if (v.heatResistance.isNotEmpty) '耐热 ${v.heatResistance}',
          ],
          note: v.characteristics,
          incomplete: v.incomplete,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VarietyDetailPage(varietyId: v.id),
              ),
            );
            _load();
          },
        );
      }).toList(),
    );
  }

  Widget _pestList() {
    return _list(
      count: pests.length,
      label: '条',
      empty: '还没有病虫害资料',
      onAdd: () => _openEdit(1, null),
      onAi: () => _openAi('pest'),
      onImport: () => _importAi('pest'),
      children: pests.map((p) {
        return _card(
          title: p.name,
          badge: p.category,
          image: p.image,
          cropImage: _cropImage,
          pending: p.imgPending,
          onImageTap: p.image.isEmpty ? null : () => _cropImageOf(
            p.image,
            (ref) async {
              p.image = ref;
              p.imgPending = false;
              await Repo.instance.savePest(p);
              _load();
            },
          ),
          tags: [p.crops.isEmpty ? '通用' : '影响 ${p.cropsText(crops.map((c) => c.name).toList())}'],
          note: p.symptoms,
          incomplete: p.incomplete,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PestDetailPage(pestId: p.id)),
            );
            _load();
          },
        );
      }).toList(),
    );
  }

  Widget _soilList() {
    return _list(
      count: soils.length,
      label: '条',
      empty: '还没有配土/用肥资料',
      onAdd: () => _openEdit(4, null),
      children: soils.map((s) {
        return _card(
          title: s.name,
          badge: s.category,
          image: s.image,
          cropImage: _cropImage,
          tags: [if (s.crop == '通用') '通用'],
          note: s.description,
          incomplete: s.incomplete,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SoilDetailPage(soilId: s.id)),
            );
            _load();
          },
        );
      }).toList(),
    );
  }

  Widget _materialList(List<Supply> list, String kind) {
    final fer = kind == 'fertilizer';
    return _list(
      count: list.length,
      label: '条',
      empty: fer ? '还没有肥料，点右上角把你常用的肥记下来' : '还没有药品，点右上角把常用药记下来',
      onAdd: () => _openEdit(fer ? 2 : 3, null, kind: kind),
      children: list.map((m) {
        return _card(
          title: m.name,
          badge: '',
          image: m.image,
          cropImage: '',
          tags: [],
          tags2: [
            if (m.method.isNotEmpty) m.method,
            if (m.ratio.isNotEmpty) '兑水 ${m.ratio}',
            _scopeLabel(m),
          ],
          note: m.notes,
          incomplete: m.incomplete,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MaterialDetailPage(materialId: m.id),
              ),
            );
            _load();
          },
        );
      }).toList(),
    );
  }

  String _scopeLabel(Supply m) {
    if (m.scope != 'disabled' || m.disabledCrops.isEmpty) return '通用';
    final names = m.disabledCrops
        .map((id) {
          for (final c in crops) {
            if (c.id == id) return c.name;
          }
          return id;
        })
        .join('、');
    return '禁用：$names';
  }

  String get _cropImage {
    for (final c in crops) {
      if (c.id == cropId) return c.image;
    }
    return '';
  }

  Future<void> _cropImageOf(
    String ref,
    Future<void> Function(String) onDone,
  ) async {
    final res = await cropExistingPhoto(context, ref);
    if (res == null) return;
    await onDone(res.ref);
    if (mounted) toast(context, '已换成裁剪后的图');
  }

  void _openAi(String kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiTemplatePage(cropId: cropId, kind: kind),
      ),
    ).then((_) => _load());
  }

  Future<void> _importAi(String kind) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (picked == null || picked.isEmpty) return;
    final bytes = await picked.first.readAsBytes();
    final res = await importAiPack(bytes: bytes, cropId: cropId);
    if (!mounted) return;
    if (!res.ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入失败'),
          content: SingleChildScrollView(
            child: Text('${res.error}\n\n${kAiPackHint}'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${aiKindName(res.kind)} · ${res.cropName}'),
            const SizedBox(height: 8),
            Text('新增 ${res.added} 条，更新 ${res.updated} 条'),
            if (res.images > 0)
              Text('保存了 ${res.images} 张图片，带「!」的点缩略图可以裁剪'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好')),
        ],
      ),
    );
    _load();
  }

  void _openEdit(int tab, String? id, {String kind = 'fertilizer'}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => switch (tab) {
          0 => VarietyEditPage(varietyId: id, cropId: cropId),
          1 => PestEditPage(pestId: id, cropId: cropId),
          2 => MaterialEditPage(materialId: id, kind: 'fertilizer'),
          3 => MaterialEditPage(materialId: id, kind: 'medicine'),
          _ => SoilEditPage(soilId: id, cropId: cropId),
        },
      ),
    ).then((_) => _load());
  }

  Widget _list({
    required int count,
    required String label,
    required String empty,
    required VoidCallback onAdd,
    VoidCallback? onAi,
    VoidCallback? onImport,
    required List<Widget> children,
  }) {
    final toolStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        Row(
          children: [
            Text('共 $count $label', style: tSub),
            const Spacer(),
            if (onAi != null)
              TextButton.icon(
                onPressed: onAi,
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('AI模板', style: TextStyle(fontSize: 12.5)),
                style: toolStyle.copyWith(foregroundColor: const WidgetStatePropertyAll(kGreen)),
              ),
            if (onImport != null)
              TextButton(
                onPressed: onImport,
                style: toolStyle.copyWith(
                  foregroundColor: const WidgetStatePropertyAll(kInk2),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.file_download_outlined, size: 15),
                    SizedBox(width: 2),
                    Text('导入', style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            if (onAi != null || onImport != null) const SizedBox(width: 2),
            TextButton(
              onPressed: onAdd,
              style: toolStyle.copyWith(
                foregroundColor: const WidgetStatePropertyAll(kRed),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16),
                  SizedBox(width: 1),
                  Text(
                    '新增',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (children.isEmpty) EmptyHint(text: empty),
        ...children,
      ],
    );
  }

  Widget _card({
    required String title,
    required String badge,
    String image = '',
    String cropImage = '',
    required List<String> tags,
    List<String> tags2 = const [],
    bool pending = false,
    VoidCallback? onImageTap,
    required String note,
    required bool incomplete,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          decoration: cardDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：标题靠左，分类/状态角标跟在后面，箭头贴右
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: tTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Pill(badge, bg: kGreenBg, fg: kGreen),
                  ],
                  if (incomplete) ...[
                    const SizedBox(width: 4),
                    const Pill('待完善', bg: kAmberBg, fg: kAmber),
                  ],
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 17, color: kInk3),
                ],
              ),
              const SizedBox(height: 9),
              // 第二行起：左边缩略图占方块，右边是摘要与描述
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: onImageTap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        LocalImage(
                          ref: image,
                          fallbackRef: cropImage,
                          width: 54,
                          height: 54,
                          radius: 12,
                          iconSize: 20,
                        ),
                        if (pending)
                          Positioned(
                            right: -3,
                            bottom: -3,
                            child: Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: kAmber,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Text(
                                '!',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.1,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tags.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: tags.map((t) => Pill(t)).toList(),
                          ),
                        if (tags2.isNotEmpty) ...[
                          if (tags.isNotEmpty) const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: tags2.map((t) => Pill(t)).toList(),
                          ),
                        ],
                        if (note.isNotEmpty) ...[
                          if (tags.isNotEmpty) const SizedBox(height: 6),
                          Text(
                            note,
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
            ],
          ),
        ),
      ),
    );
  }
}
