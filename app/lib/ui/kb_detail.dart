import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../core/images.dart';
import 'common.dart';
import 'image_crop.dart';
import 'image_tile.dart';

// ---------------------------------------------------------------- 品种

class VarietyDetailPage extends StatefulWidget {
  const VarietyDetailPage({super.key, required this.varietyId});
  final String varietyId;
  @override
  State<VarietyDetailPage> createState() => _VarietyDetailPageState();
}

class _VarietyDetailPageState extends State<VarietyDetailPage> {
  Variety? v;
  String cropImage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await Repo.instance.varietyById(widget.varietyId);
    final ci = x == null ? '' : await defaultImageFor(x.crop);
    if (mounted) {
      setState(() {
        v = x;
        cropImage = ci;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (v == null)
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kRed)),
      );
    final x = v!;
    return Scaffold(
      appBar: AppBar(
        title: Text(x.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      VarietyEditPage(varietyId: x.id, cropId: x.crop),
                ),
              );
              await _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          HeroImage(ref: x.image, cropRef: cropImage),
          Row(
            children: [
              if (x.category.isNotEmpty)
                Pill(x.category, bg: kRedBg, fg: kRedDeep),
              const SizedBox(width: 6),
              if (x.incomplete) const Pill('资料待完善', bg: kAmberBg, fg: kAmber),
            ],
          ),
          const SizedBox(height: 10),
          _stars(x),
          _section('特点', x.characteristics),
          _section('适宜种植', x.suitable),
          _section('栽培要点', x.care),
          _kv('口感', x.taste),
          _kv('甜度', x.sweetness),
          _kv('果型', x.fruitSize),
          _kv('耐热', x.heatResistance),
          _kv('产量', x.yieldText),
          _kv('来源', x.source),
          const SizedBox(height: 10),
          Text('编号 ${x.code} · 更新 ${x.updatedAt}', style: tTiny),
        ],
      ),
    );
  }

  Widget _stars(Variety x) {
    Widget row(String label, int n) => Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        children: [
          Text('$label ', style: tSub),
          Text(
            '★' * n + '☆' * (5 - n),
            style: const TextStyle(fontSize: 12, color: kAmber),
          ),
        ],
      ),
    );
    return Wrap(
      children: [
        row('甜度', x.sweetnessStar),
        row('果个', x.sizeStar),
        row('耐热', x.heatStar),
      ],
    );
  }

  Widget _section(String title, String body) {
    if (body.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(body, style: tBody),
        ],
      ),
    );
  }

  Widget _kv(String k, String vv) {
    if (vv.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Text(k, style: tSub)),
          Expanded(child: Text(vv, style: tBody)),
        ],
      ),
    );
  }
}

class VarietyEditPage extends StatefulWidget {
  const VarietyEditPage({super.key, this.varietyId, this.cropId = ''});
  final String? varietyId;
  final String cropId;
  @override
  State<VarietyEditPage> createState() => _VarietyEditPageState();
}

class _VarietyEditPageState extends State<VarietyEditPage> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _char = TextEditingController();
  final _suitable = TextEditingController();
  final _care = TextEditingController();
  final _taste = TextEditingController();
  final _sweet = TextEditingController();
  final _fruit = TextEditingController();
  final _heat = TextEditingController();
  final _yield = TextEditingController();
  Variety? origin;
  String image = '';
  String cropImage = '';
  int sweetStar = 0, sizeStar = 0, heatStar = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.varietyId != null) {
      origin = await Repo.instance.varietyById(widget.varietyId!);
      final o = origin;
      if (o != null) {
        _name.text = o.name;
        _category.text = o.category;
        _char.text = o.characteristics;
        _suitable.text = o.suitable;
        _care.text = o.care;
        _taste.text = o.taste;
        _sweet.text = o.sweetness;
        _fruit.text = o.fruitSize;
        _heat.text = o.heatResistance;
        _yield.text = o.yieldText;
        sweetStar = o.sweetnessStar;
        sizeStar = o.sizeStar;
        heatStar = o.heatStar;
        image = o.image;
        cropImage = await defaultImageFor(o.crop);
      }
    }
    if (widget.varietyId == null)
      cropImage = await defaultImageFor(widget.cropId);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, '品种名不能空');
      return;
    }
    final v =
        origin ??
        Variety(
          id: newId('var'),
          crop: widget.cropId.isEmpty ? 'crop_strawberry' : widget.cropId,
          sortOrder: 500,
        );
    v.name = _name.text.trim();
    v.category = _category.text.trim();
    v.characteristics = _char.text.trim();
    v.suitable = _suitable.text.trim();
    v.care = _care.text.trim();
    v.taste = _taste.text.trim();
    v.sweetness = _sweet.text.trim();
    v.fruitSize = _fruit.text.trim();
    v.heatResistance = _heat.text.trim();
    v.yieldText = _yield.text.trim();
    v.sweetnessStar = sweetStar;
    v.sizeStar = sizeStar;
    v.heatStar = heatStar;
    v.image = image;
    v.imgPending = false;
    v.incomplete = v.characteristics.isEmpty && v.care.isEmpty;
    if (widget.cropId.isNotEmpty) v.crop = widget.cropId;
    await Repo.instance.saveVariety(v);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.varietyId == null ? '新增品种' : '编辑品种'),
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
                const FormLabel('图片'),
                ImageField(
                  ref: image,
                  cropRef: cropImage,
                  onChanged: (v) => setState(() => image = v),
                  hint: '不选的话，列表里用这个作物的默认图',
                ),
                const SizedBox(height: 6),
                const FormLabel('品种名', required: true),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: '红颜 / 章姬'),
                ),
                const FormLabel('分类'),
                TextField(
                  controller: _category,
                  decoration: const InputDecoration(hintText: '红草莓 / 白草莓'),
                ),
                const FormLabel('特点'),
                AutoField(controller: _char, hint: '果型、口感、长势…'),
                const FormLabel('适宜种植'),
                AutoField(
                  controller: _suitable,
                  hint: '适合什么环境、什么地区',
                  minLines: 2,
                ),
                const FormLabel('栽培要点'),
                AutoField(controller: _care, hint: '水肥、温度、注意事项', minLines: 3),
                const FormLabel('口感'),
                TextField(controller: _taste),
                const FormLabel('甜度'),
                TextField(
                  controller: _sweet,
                  decoration: const InputDecoration(hintText: '比如 高 / 14%'),
                ),
                _starPicker(
                  '甜度星级',
                  sweetStar,
                  (v) => setState(() => sweetStar = v),
                ),
                const FormLabel('果型'),
                TextField(controller: _fruit),
                const FormLabel('耐热性'),
                TextField(controller: _heat),
                _starPicker(
                  '耐热星级',
                  heatStar,
                  (v) => setState(() => heatStar = v),
                ),
                const FormLabel('产量'),
                TextField(controller: _yield),
                const SizedBox(height: 22),
                FilledButton(onPressed: _save, child: const Text('保存')),
              ],
            ),
    );
  }

  Widget _starPicker(String label, int value, ValueChanged<int> onPick) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text(label, style: tSub),
          const SizedBox(width: 10),
          ...List.generate(5, (i) {
            return IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onPick(i + 1 == value ? 0 : i + 1),
              icon: Icon(
                i < value ? Icons.star : Icons.star_border,
                size: 20,
                color: kAmber,
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 病虫害

class PestDetailPage extends StatefulWidget {
  const PestDetailPage({super.key, required this.pestId});
  final String pestId;
  @override
  State<PestDetailPage> createState() => _PestDetailPageState();
}

class _PestDetailPageState extends State<PestDetailPage> {
  Pest? p;
  String cropImage = '';
  List<Crop> crops = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await Repo.instance.pestById(widget.pestId);
    final ci = x == null ? '' : await defaultImageFor(x.crop);
    final cs = await Repo.instance.crops();
    if (mounted) {
      setState(() {
        p = x;
        cropImage = ci;
        crops = cs;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (p == null)
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kRed)),
      );
    final x = p!;
    return Scaffold(
      appBar: AppBar(
        title: Text(x.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PestEditPage(pestId: x.id, cropId: x.crop),
                ),
              );
              await _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          HeroImage(ref: x.image, cropRef: cropImage),
          Row(
            children: [
              if (x.category.isNotEmpty)
                Pill(x.category, bg: kRedBg, fg: kRedDeep),
              const SizedBox(width: 6),
              Pill(
                x.crops.isEmpty
                    ? '通用'
                    : '影响 ${x.cropsText({for (final c in crops) c.id: c.name})}',
                bg: kBlueBg,
                fg: kBlue,
              ),
              if (x.incomplete) ...[
                const SizedBox(width: 6),
                const Pill('资料待完善', bg: kAmberBg, fg: kAmber),
              ],
            ],
          ),
          _block('症状', x.symptoms),
          _block('发生原因', x.cause),
          _block('防治方法', x.treatment),
          _block('日常预防', x.prevention),
          const SizedBox(height: 10),
          Text('更新 ${x.updatedAt}', style: tTiny),
        ],
      ),
    );
  }

  Widget _block(String t, String b) {
    if (b.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: cardDeco(color: const Color(0xFFFDFCFA)),
            child: Text(b, style: tBody),
          ),
        ],
      ),
    );
  }
}

class PestEditPage extends StatefulWidget {
  const PestEditPage({super.key, this.pestId, this.cropId = '通用'});
  final String? pestId;
  final String cropId;
  @override
  State<PestEditPage> createState() => _PestEditPageState();
}

class _PestEditPageState extends State<PestEditPage> {
  final _name = TextEditingController();
  final _category = TextEditingController(text: '病害');
  final _symptoms = TextEditingController();
  final _cause = TextEditingController();
  final _treatment = TextEditingController();
  final _prevention = TextEditingController();
  Pest? origin;
  String image = '';
  String cropImage = '';
  bool loading = true;
  List<Crop> crops = const [];
  Set<String> cropSel = {};
  bool common = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.pestId != null) {
      origin = await Repo.instance.pestById(widget.pestId!);
      final o = origin;
      if (o != null) {
        _name.text = o.name;
        _category.text = o.category;
        _symptoms.text = o.symptoms;
        _cause.text = o.cause;
        _treatment.text = o.treatment;
        _prevention.text = o.prevention;
        image = o.image;
        cropImage = await defaultImageFor(o.crop);
        common = o.crop == '通用' || o.crops.isEmpty;
        if (!common) cropSel = {...o.crops};
        if (common) cropSel = {};
      }
    }
    crops = await Repo.instance.crops();
    if (widget.pestId == null) {
      cropImage = await defaultImageFor(widget.cropId);
      // 默认绑定当前顶部选中的作物
      final cur = crops.where((c) => c.id == widget.cropId).firstOrNull;
      if (cur != null) {
        common = false;
        cropSel = {cur.id};
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, '名字不能空');
      return;
    }
    final p =
        origin ?? Pest(id: newId('pest'), crop: widget.cropId, sortOrder: 500);
    p.name = _name.text.trim();
    p.category = _category.text.trim();
    p.symptoms = _symptoms.text.trim();
    p.cause = _cause.text.trim();
    p.treatment = _treatment.text.trim();
    p.prevention = _prevention.text.trim();
    p.image = image;
    p.imgPending = false;
    p.crops = common ? const [] : cropSel.toList();
    p.crop = common || cropSel.isEmpty ? '通用' : cropSel.first;
    p.incomplete = p.symptoms.isEmpty && p.treatment.isEmpty;
    await Repo.instance.savePest(p);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pestId == null ? '新增病虫害' : '编辑病虫害'),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
        children: [
          const FormLabel('图片'),
          ImageField(
            ref: image,
            cropRef: cropImage,
            onChanged: (v) => setState(() => image = v),
            hint: '不选的话，列表里用默认图',
          ),
          const SizedBox(height: 6),
          const FormLabel('名称', required: true),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '白粉病 / 红蜘蛛'),
          ),
          const FormLabel('分类'),
          TextField(
            controller: _category,
            decoration: const InputDecoration(hintText: '病害 / 虫害'),
          ),
          const FormLabel('影响作物'),
          ChoiceRow(
            options: const ['通用', '指定作物'],
            value: common ? '通用' : '指定作物',
            onChanged: (v) => setState(() {
              common = v == '通用';
              if (common) cropSel = {};
            }),
          ),
          if (!common) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: crops.map((c) {
                final on = cropSel.contains(c.id);
                final col = colorOf(c.color);
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() {
                    if (on) {
                      cropSel.remove(c.id);
                    } else {
                      cropSel.add(c.id);
                    }
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: on ? col.withValues(alpha: .12) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: on ? col.withValues(alpha: .45) : kLine,
                      ),
                    ),
                    child: Text(
                      '${c.emoji} ${c.name}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? col : kInk2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            const Text('一种病害影响多类作物时，可以全部选上', style: tTiny),
          ],
          const FormLabel('症状'),
          AutoField(controller: _symptoms),
          const FormLabel('发生原因'),
          AutoField(controller: _cause, minLines: 2),
          const FormLabel('防治方法'),
          AutoField(controller: _treatment, minLines: 3),
          const FormLabel('日常预防'),
          AutoField(controller: _prevention, minLines: 2),
          const SizedBox(height: 22),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 土肥

class SoilDetailPage extends StatefulWidget {
  const SoilDetailPage({super.key, required this.soilId});
  final String soilId;
  @override
  State<SoilDetailPage> createState() => _SoilDetailPageState();
}

class _SoilDetailPageState extends State<SoilDetailPage> {
  Soil? s;
  String cropImage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await Repo.instance.soilById(widget.soilId);
    final ci = x == null ? '' : await defaultImageFor(x.crop);
    if (mounted) {
      setState(() {
        s = x;
        cropImage = ci;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (s == null)
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kRed)),
      );
    final x = s!;
    return Scaffold(
      appBar: AppBar(
        title: Text(x.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SoilEditPage(soilId: x.id, cropId: x.crop),
                ),
              );
              await _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          HeroImage(ref: x.image, cropRef: cropImage),
          Row(
            children: [
              if (x.category.isNotEmpty)
                Pill(x.category, bg: kGreenBg, fg: kGreen),
              const SizedBox(width: 6),
              if (x.crop == '通用') const Pill('通用', bg: kBlueBg, fg: kBlue),
            ],
          ),
          _block('简介', x.description),
          _block('配料', x.ingredients),
          _block('做法', x.method),
          _block('要点', x.tips),
          const SizedBox(height: 10),
          Text('更新 ${x.updatedAt}', style: tTiny),
        ],
      ),
    );
  }

  Widget _block(String t, String b) {
    if (b.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: cardDeco(color: const Color(0xFFFDFCFA)),
            child: Text(b, style: tBody),
          ),
        ],
      ),
    );
  }
}

class SoilEditPage extends StatefulWidget {
  const SoilEditPage({super.key, this.soilId, this.cropId = '通用'});
  final String? soilId;
  final String cropId;
  @override
  State<SoilEditPage> createState() => _SoilEditPageState();
}

class _SoilEditPageState extends State<SoilEditPage> {
  final _name = TextEditingController();
  final _category = TextEditingController(text: '配土');
  final _desc = TextEditingController();
  final _ingredients = TextEditingController();
  final _method = TextEditingController();
  final _tips = TextEditingController();
  Soil? origin;
  String image = '';
  String cropImage = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.soilId != null) {
      origin = await Repo.instance.soilById(widget.soilId!);
      final o = origin;
      if (o != null) {
        _name.text = o.name;
        _category.text = o.category;
        _desc.text = o.description;
        _ingredients.text = o.ingredients;
        _method.text = o.method;
        _tips.text = o.tips;
        image = o.image;
        cropImage = await defaultImageFor(o.crop);
      }
    }
    if (widget.soilId == null) cropImage = await defaultImageFor(widget.cropId);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, '名字不能空');
      return;
    }
    final s =
        origin ?? Soil(id: newId('soil'), crop: widget.cropId, sortOrder: 500);
    s.name = _name.text.trim();
    s.category = _category.text.trim();
    s.description = _desc.text.trim();
    s.ingredients = _ingredients.text.trim();
    s.method = _method.text.trim();
    s.tips = _tips.text.trim();
    s.image = image;
    s.incomplete = s.ingredients.isEmpty && s.method.isEmpty;
    await Repo.instance.saveSoil(s);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.soilId == null ? '新增土肥' : '编辑土肥'),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
        children: [
          const FormLabel('图片'),
          ImageField(
            ref: image,
            cropRef: cropImage,
            onChanged: (v) => setState(() => image = v),
            hint: '不选的话，列表里用默认图',
          ),
          const SizedBox(height: 6),
          const FormLabel('名称', required: true),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '草莓专用配土'),
          ),
          const FormLabel('分类'),
          TextField(
            controller: _category,
            decoration: const InputDecoration(hintText: '配土 / 堆肥 / 液肥'),
          ),
          const FormLabel('简介'),
          AutoField(controller: _desc, minLines: 2),
          const FormLabel('配料'),
          AutoField(controller: _ingredients),
          const FormLabel('做法'),
          AutoField(controller: _method),
          const FormLabel('要点'),
          AutoField(controller: _tips, minLines: 2),
          const SizedBox(height: 22),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 图片

/// 取某个作物的默认图（病虫害/土肥的「通用」条目用默认作物的图）
Future<String> defaultImageFor(String crop) async {
  final c = crop == '通用'
      ? await Repo.instance.defaultCrop()
      : await Repo.instance.cropById(crop);
  return c?.image ?? '';
}

/// 详情页顶部的图，没有图就用该作物的默认图，再没有就灰底占位
class HeroImage extends StatelessWidget {
  const HeroImage({super.key, required this.ref, this.cropRef = ''});
  final String ref;
  final String cropRef;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: LocalImage(
          ref: ref,
          fallbackRef: cropRef,
          radius: 16,
          iconSize: 34,
        ),
      ),
    );
  }
}

/// 编辑页选图/换图/删图
class ImageField extends StatelessWidget {
  const ImageField({
    super.key,
    required this.ref,
    this.cropRef = '',
    required this.onChanged,
    this.hint = '',
  });
  final String ref;
  final String cropRef;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalImage(
          ref: ref,
          fallbackRef: cropRef,
          width: 88,
          height: 88,
          radius: 14,
          iconSize: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await pickAndCropImage(context);
                      if (saved.isNotEmpty) onChanged(saved);
                    },
                    icon: const Icon(Icons.photo_library_outlined, size: 17),
                    label: Text(ref.isEmpty ? '选图片' : '换一张'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (ref.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => onChanged(''),
                      style: TextButton.styleFrom(
                        foregroundColor: kInk3,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('删除'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(hint.isEmpty ? '从相册选一张，拖动裁出想要的部分' : hint, style: tTiny),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 肥料 / 药品

class MaterialDetailPage extends StatefulWidget {
  const MaterialDetailPage({super.key, required this.materialId});
  final String materialId;
  @override
  State<MaterialDetailPage> createState() => _MaterialDetailPageState();
}

class _MaterialDetailPageState extends State<MaterialDetailPage> {
  Supply? m;
  List<Crop> crops = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await Repo.instance.materialById(widget.materialId);
    final cs = await Repo.instance.crops(includeDisabled: true);
    if (mounted) {
      setState(() {
        m = x;
        crops = cs;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = m;
    return Scaffold(
      appBar: AppBar(
        title: Text(x == null ? '' : (x.kind == 'fertilizer' ? '肥料' : '药品')),
        actions: [
          if (x != null)
            TextButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MaterialEditPage(materialId: x.id, kind: x.kind),
                  ),
                );
                _load();
              },
              child: const Text(
                '编辑',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: x == null
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                HeroImage(ref: x.image, cropRef: ''),
                Text(
                  x.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    if (x.ratio.isNotEmpty)
                      Pill('兑水 ${x.ratio}', bg: kBlueBg, fg: kBlue),
                    Pill(x.method, bg: kGreenBg, fg: kGreen),
                    if (x.scope == 'disabled' && x.disabledCrops.isNotEmpty)
                      Pill(_scopeText(x.disabledCrops, crops),
                          bg: kAmberBg, fg: kAmber)
                    else
                      const Pill('通用', bg: kGreenBg, fg: kGreen),
                  ],
                ),
                const SizedBox(height: 14),
                if (x.notes.isNotEmpty) ...[
                  const SectionTitle('备注'),
                  Text(x.notes, style: tBody),
                ],
              ],
            ),
    );
  }
}

class MaterialEditPage extends StatefulWidget {
  const MaterialEditPage({
    super.key,
    this.materialId,
    this.kind = 'fertilizer',
  });
  final String? materialId;
  final String kind;
  @override
  State<MaterialEditPage> createState() => _MaterialEditPageState();
}

class _MaterialEditPageState extends State<MaterialEditPage> {
  final _name = TextEditingController();
  final _ratio = TextEditingController();
  final _notes = TextEditingController();
  Supply? origin;
  String image = '';
  String method = '灌根';
  String scope = 'common';
  final Set<String> disabledCrops = {};
  List<Crop> crops = [];
  bool loading = true;

  static const _ratios = [
    '1:500',
    '1:800',
    '1:1000',
    '1:1500',
    '1:2000',
    '1:3000',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.materialId != null) {
      origin = await Repo.instance.materialById(widget.materialId!);
      final o = origin;
      if (o != null) {
        _name.text = o.name;
        _ratio.text = o.ratio;
        _notes.text = o.notes;
        image = o.image;
        method = o.method.isEmpty ? '灌根' : o.method;
        scope = o.scope;
        disabledCrops
          ..clear()
          ..addAll(o.disabledCrops);
      }
    }
    final cs = await Repo.instance.crops(includeDisabled: true);
    crops = cs;
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, '名称不能空');
      return;
    }
    final m = origin ?? Supply(id: newId('mat'), kind: widget.kind);
    m.name = _name.text.trim();
    m.ratio = _ratio.text.trim();
    m.method = method;
    m.notes = _notes.text.trim();
    m.image = image;
    if (scope == 'disabled' && disabledCrops.isEmpty) {
      toast(context, '选了「禁用」，至少要勾一个作物');
      return;
    }
    m.scope = scope;
    m.disabledCrops = scope == 'disabled' ? [...disabledCrops] : [];
    await Repo.instance.saveMaterial(m);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final m = origin;
    if (m == null) return;
    final ok = await confirm(
      context,
      '删除「${m.name}」？',
      body: '已经记在农事记录里的不受影响。',
      danger: true,
    );
    if (!ok) return;
    await Repo.instance.softDelete('materials', m.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fer = widget.kind == 'fertilizer';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.materialId == null
              ? (fer ? '新增肥料' : '新增药品')
              : (fer ? '编辑肥料' : '编辑药品'),
        ),
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
                const FormLabel('图片'),
                ImageField(
                  ref: image,
                  onChanged: (v) => setState(() => image = v),
                  hint: '可选，拍一下包装袋也很方便',
                ),
                const SizedBox(height: 4),
                const FormLabel('名称', required: true),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    hintText: fer ? '花多多 2 号' : '代森锰锌',
                  ),
                ),
                const FormLabel('兑水比例'),
                TextField(
                  controller: _ratio,
                  decoration: const InputDecoration(hintText: '1:1000'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ratios.map((r) {
                    final on = _ratio.text.trim() == r;
                    return GestureDetector(
                      onTap: () => setState(() => _ratio.text = r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: on ? kRedBg : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: on ? kRed : kLine),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: on ? kRedDeep : kInk2,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const FormLabel('方式'),
                ChoiceRow(
                  options: Supply.kMethods,
                  value: method,
                  onChanged: (v) => setState(() => method = v),
                  compact: true,
                ),
                const FormLabel('适用范围'),
                ChoiceRow(
                  options: const ['通用', '禁用'],
                  value: scope == 'disabled' ? '禁用' : '通用',
                  onChanged: (v) => setState(() {
                    scope = v == '禁用' ? 'disabled' : 'common';
                  }),
                  compact: true,
                ),
                if (scope == 'disabled') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: crops.map((c) {
                      final on = disabledCrops.contains(c.id);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (on) {
                            disabledCrops.remove(c.id);
                          } else {
                            disabledCrops.add(c.id);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: on ? kRedBg : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: on ? kRed : kLine),
                          ),
                          child: Text(
                            '${c.emoji} ${c.name}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: on ? kRedDeep : kInk2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '勾选的作物在「记一笔」选产品时不会出现',
                    style: tTiny,
                  ),
                ],
                const FormLabel('备注'),
                AutoField(controller: _notes, hint: '用法、注意事项、买自哪里…'),
                const SizedBox(height: 22),
                FilledButton(onPressed: _save, child: const Text('保存')),
                if (origin != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _remove,
                    style: TextButton.styleFrom(foregroundColor: kRedDeep),
                    child: const Text('删除这条'),
                  ),
                ],
              ],
            ),
    );
  }
}

String _scopeText(List<String> ids, List<Crop> crops) {
  final names = ids.map((id) {
    for (final c in crops) {
      if (c.id == id) return c.name;
    }
    return id;
  }).join('、');
  return '禁用：$names';
}
