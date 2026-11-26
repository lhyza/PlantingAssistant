/// AI 数据导入：同时支持
///   - zip 包（data.json + images/），PC 端 AI 生成
///   - 纯 JSON 文件，手机端 AI 生成（图片后补，不显示「!」）
///
/// 流程：previewAiData() 只解析并给出计划 → AiPreviewPage 让用户确认 →
/// applyAiPlan() 逐条写入。App 全程不联网。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/images.dart';
import '../core/util.dart';
import 'models.dart';
import 'repo.dart';

/// 一条的处置方式
enum AiAction { add, update, merge, skip }

class AiPlanItem {
  AiPlanItem({
    required this.name,
    required this.action,
    required this.reason,
    required this.map,
    this.existingName,
    this.imageBytes,
    this.imageExt = 'jpg',
  });

  final String name;
  AiAction action;
  String reason;
  final Map<String, dynamic> map;
  final String? existingName;
  final Uint8List? imageBytes;
  final String imageExt;

  /// 预览页的勾选状态；skip 不可选
  bool selected = true;
}

class AiImportPlan {
  AiImportPlan({
    required this.fileName,
    required this.kind,
    required this.cropId,
    required this.cropName,
    this.error,
  });

  final String fileName;
  final String kind;
  final String cropId;
  final String cropName;
  final String? error;
  final List<AiPlanItem> items = [];
  final List<String> warnings = [];

  bool get ok => error == null;

  int countOf(AiAction a) => items.where((i) => i.action == a).length;

  int get addCount => countOf(AiAction.add);
  int get updateCount => countOf(AiAction.update);
  int get mergeCount => countOf(AiAction.merge);
  int get skipCount => countOf(AiAction.skip);

  /// 可导入（勾选且不是跳过）
  int get importable =>
      items.where((i) => i.action != AiAction.skip && i.selected).length;

  String get kindLabel => kind == 'pest' ? '病虫害' : '品种';
}

class AiImportResult {
  AiImportResult({
    this.added = 0,
    this.updated = 0,
    this.merged = 0,
    this.skipped = 0,
    this.failed = 0,
    this.images = 0,
    this.pending = 0,
    this.error,
    this.kind = '',
    this.cropName = '',
  });

  int added;
  int updated;
  int merged;
  int skipped;
  int failed;
  int images;

  /// 带图待裁剪的条数（列表上会显示「!」），只有 zip 有图时才可能 > 0
  int pending;
  String? error;
  String kind;
  String cropName;

  bool get ok => error == null;
}

const String _kBadJson =
    'JSON 解析失败：可能是复制不完整、被截断，或里面混了中文标点（，／“”）';

/// 解析文件，生成导入计划（不写库）。自动识别 zip 与纯 JSON。
Future<AiImportPlan> previewAiData({
  required Uint8List bytes,
  required String cropId,
  String? expectedKind,
  String? fileName,
}) async {
  final crops = await Repo.instance.crops();
  var cropName = '';
  for (final c in crops) {
    if (c.id == cropId) cropName = c.name;
  }

  final plan = AiImportPlan(
    fileName: fileName ?? '',
    kind: '',
    cropId: cropId,
    cropName: cropName,
  );

  Map<String, dynamic> root;
  final imgMap = <String, Uint8List>{};

  if (_isZip(bytes)) {
    Archive arc;
    try {
      arc = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return _fail(plan, '压缩包解不开，可能已损坏');
    }
    ArchiveFile? jsonFile;
    for (final f in arc.files) {
      final n = f.name.replaceAll('\\\\', '/');
      if (n == 'data.json' || n.endsWith('/data.json')) {
        jsonFile = f;
        break;
      }
    }
    if (jsonFile == null) {
      return _fail(plan, '压缩包里没有找到 data.json');
    }
    try {
      root = _asRoot(jsonDecode(utf8.decode(jsonFile.content as List<int>)));
    } catch (_) {
      return _fail(plan, _kBadJson);
    }
    for (final f in arc.files) {
      final n = f.name.replaceAll('\\\\', '/');
      if (n.startsWith('images/') && !n.endsWith('/') && f.size > 0) {
        imgMap[n.substring('images/'.length)] = f.content as Uint8List;
      }
    }
  } else {
    final text = _cleanJsonText(bytes);
    if (text == null) return _fail(plan, '这个文件里没有找到 JSON 内容');
    try {
      root = _asRoot(jsonDecode(text));
    } catch (_) {
      final repaired = text.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
      try {
        root = _asRoot(jsonDecode(repaired));
      } catch (_) {
        return _fail(plan, _kBadJson);
      }
    }
  }

  final kind = (root['kind'] ?? expectedKind ?? '').toString().trim();
  if (kind != 'variety' && kind != 'pest') {
    return _fail(plan, '识别不出这是品种还是病虫害（缺 kind），请从对应页面点「导入」');
  }

  final fmt = (root['format'] ?? '').toString().trim();
  if (fmt == 'planting.data') {
    return _fail(plan, '这是「数据管理」导出的库文件，请到「数据管理 → 导入」里导入');
  }
  if (fmt.isNotEmpty && fmt != 'planting.ai') {
    return _fail(plan, 'format 是「$fmt」，不是 AI 数据包，可能选错了文件');
  }
  if (fmt.isEmpty) plan.warnings.add('文件里没有声明 format，已按 AI 数据包处理');

  final rawItems = (root['items'] as List?) ?? const [];
  if (rawItems.isEmpty) return _fail(plan, '这个数据包里没有任何条目');

  // 作物：数据包里写了就按它，否则用当前顶部作物
  var targetCrop = cropId;
  final rawCrop = (root['crop'] ?? '').toString().trim();
  if (rawCrop.isNotEmpty) {
    for (final c in crops) {
      if (rawCrop == c.id || rawCrop == c.name) targetCrop = c.id;
    }
  }
  var targetCropName = plan.cropName;
  for (final c in crops) {
    if (c.id == targetCrop) targetCropName = c.name;
  }

  final typed = AiImportPlan(
    fileName: plan.fileName,
    kind: kind,
    cropId: targetCrop,
    cropName: targetCropName,
  )..warnings.addAll(plan.warnings);

  final existing = kind == 'pest'
      ? <({String id, String name, bool common})>[
          for (final p in await Repo.instance.pests(targetCrop))
            (id: p.id, name: p.name, common: p.crop == '通用'),
        ]
      : <({String id, String name, bool common})>[
          for (final v in await Repo.instance.varieties(targetCrop))
            (id: v.id, name: v.name, common: false),
        ];

  for (final raw in rawItems) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final name = _s(m['name']);
    if (name.isEmpty) {
      typed.items.add(AiPlanItem(
        name: '（未命名）',
        action: AiAction.skip,
        reason: '没有名称，跳过',
        map: m,
      ));
      continue;
    }

    Uint8List? imageBytes;
    var imageExt = 'jpg';
    final imgRel = _s(m['image']);
    if (imgRel.isNotEmpty && !imgRel.startsWith('http')) {
      final key = imgRel.startsWith('images/')
          ? imgRel.substring('images/'.length)
          : imgRel;
      imageBytes = imgMap[key];
      if (imageBytes != null) imageExt = _extOf(key);
    }

    // 精确同名优先，其次别名归一
    ({String id, String name, bool common})? hit;
    for (final e in existing) {
      if (e.name == name) {
        hit = e;
        break;
      }
    }
    var merged = false;
    if (hit == null) {
      for (final e in existing) {
        if (_aliasHit(name, e.name)) {
          hit = e;
          merged = true;
          break;
        }
      }
    }

    if (hit == null) {
      typed.items.add(AiPlanItem(
        name: name,
        action: AiAction.add,
        reason: '新增',
        map: m,
        imageBytes: imageBytes,
        imageExt: imageExt,
      ));
      continue;
    }

    // 通用条目：按约定跳过（不覆盖跨作物知识）
    if (hit.common && targetCrop != '通用') {
      typed.items.add(AiPlanItem(
        name: name,
        action: AiAction.skip,
        reason: '内置「${hit.name}」是通用条目，按设置跳过；要改它请直接在条目里编辑',
        map: m,
        existingName: hit.name,
      ));
      continue;
    }

    typed.items.add(AiPlanItem(
      name: name,
      action: merged ? AiAction.merge : AiAction.update,
      reason: merged ? '疑似同名，合并到「${hit.name}」' : '更新已有条目',
      map: m,
      existingName: hit.name,
      imageBytes: imageBytes,
      imageExt: imageExt,
    ));
  }

  return typed;
}

/// 执行计划（只写勾选的、非 skip 的条目）。逐条写入，失败的那条会被计数。
Future<AiImportResult> applyAiPlan(AiImportPlan plan) async {
  final res = AiImportResult(
    kind: plan.kind,
    cropName: plan.cropName,
    skipped: plan.skipCount,
  );
  final cropIdsByName = <String, String>{};
  for (final c in await Repo.instance.crops(includeDisabled: true)) {
    cropIdsByName[c.name] = c.id;
  }

  for (final it in plan.items) {
    if (it.action == AiAction.skip || !it.selected) {
      if (it.action != AiAction.skip) res.skipped++;
      continue;
    }
    try {
      var imageRef = '';
      if (it.imageBytes != null) {
        imageRef = await Images.save(it.imageBytes!, ext: it.imageExt);
        res.images++;
      }
      final m = it.map;
      if (plan.kind == 'variety') {
        Variety? v;
        if (it.existingName != null) {
          for (final x in await Repo.instance.varieties(plan.cropId)) {
            if (x.name == it.existingName) v = x;
          }
        }
        v ??= Variety(id: newId('var'), crop: plan.cropId);
        v.name = it.existingName ?? it.name;
        v.category = _s(m['category']);
        v.characteristics = _s(m['characteristics']);
        v.suitable = _s(m['suitable']);
        v.care = _s(m['care']);
        v.yieldText = _s(m['yield'] ?? m['yieldText']);
        v.taste = _s(m['taste']);
        v.sweetness = _s(m['sweetness']);
        v.sweetnessStar = _star(m['sweetnessStar']);
        v.fruitSize = _s(m['fruitSize']);
        v.sizeStar = _star(m['sizeStar']);
        v.heatResistance = _s(m['heatResistance']);
        v.heatStar = _star(m['heatStar']);
        if (imageRef.isNotEmpty) {
          v.image = imageRef;
          v.imgPending = true;
          res.pending++;
        }
        v.source = 'ai';
        v.incomplete = v.characteristics.isEmpty && v.care.isEmpty;
        if (it.action == AiAction.add) v.sortOrder = 600;
        await Repo.instance.saveVariety(v);
        _bump(res, it.action);
      } else {
        Pest? p;
        if (it.existingName != null) {
          for (final x in await Repo.instance.pests(plan.cropId)) {
            if (x.name == it.existingName) p = x;
          }
        }
        p ??= Pest(id: newId('pest'), sortOrder: 600);
        p.name = it.existingName ?? it.name;
        final cat = _s(m['category']);
        p.category = cat.isEmpty ? '病害' : cat;
        p.symptoms = _s(m['symptoms']);
        p.cause = _s(m['cause']);
        p.treatment = _s(m['treatment']);
        p.prevention = _s(m['prevention']);
        if (imageRef.isNotEmpty) {
          p.image = imageRef;
          p.imgPending = true;
          res.pending++;
        }
        if (it.action == AiAction.add) {
          p.crop = plan.cropId;
          p.crops = _cropListOf(m['crops'], plan.cropId, cropIdsByName);
        }
        p.source = 'ai';
        p.incomplete = p.symptoms.isEmpty && p.treatment.isEmpty;
        await Repo.instance.savePest(p);
        _bump(res, it.action);
      }
    } catch (_) {
      res.failed++;
    }
  }
  // 外部数据可能带全角括号，统一成「喷雾(叶背)」
  await Repo.instance.normalizeMethodNames();
  return res;
}

/// 预览 + 一次性应用（测试与"直接导入"用的便捷入口）
Future<AiImportResult> importAiData({
  required Uint8List bytes,
  required String cropId,
  String? expectedKind,
  String? fileName,
}) async {
  final plan = await previewAiData(
    bytes: bytes,
    cropId: cropId,
    expectedKind: expectedKind,
    fileName: fileName,
  );
  if (!plan.ok) return AiImportResult(error: plan.error);
  return applyAiPlan(plan);
}

/// 兼容旧调用：zip 包导入
Future<AiImportResult> importAiPack({
  required Uint8List bytes,
  required String cropId,
}) =>
    importAiData(bytes: bytes, cropId: cropId);

List<String> _cropListOf(
    dynamic v, String fallback, Map<String, String> idsByName) {
  if (v is List) {
    final out = <String>[];
    for (final e in v) {
      final s = _s(e);
      if (s.isNotEmpty) out.add(idsByName[s] ?? s);
    }
    if (out.isNotEmpty) return out;
  }
  return [fallback];
}

void _bump(AiImportResult r, AiAction a) {
  switch (a) {
    case AiAction.add:
      r.added++;
      break;
    case AiAction.update:
      r.updated++;
      break;
    case AiAction.merge:
      r.merged++;
      break;
    case AiAction.skip:
      break;
  }
}

AiImportPlan _fail(AiImportPlan p, String msg) => AiImportPlan(
      fileName: p.fileName,
      kind: p.kind,
      cropId: p.cropId,
      cropName: p.cropName,
      error: msg,
    )..warnings.addAll(p.warnings);

bool _isZip(Uint8List b) =>
    b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04;

/// 清洗手机端复制出来的 JSON 文本：BOM、```json 围栏、前后说明文字
String? _cleanJsonText(Uint8List bytes) {
  var s = utf8.decode(bytes, allowMalformed: true);
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  s = s.trim();
  if (s.contains('```')) {
    final i = s.indexOf('```');
    var rest = s.substring(i + 3);
    if (rest.startsWith('json') || rest.startsWith('JSON')) {
      rest = rest.substring(4);
    }
    final end = rest.indexOf('```');
    s = (end >= 0 ? rest.substring(0, end) : rest).trim();
  }
  final firstObj = s.indexOf('{');
  final firstArr = s.indexOf('[');
  var start = firstObj;
  if (start < 0 || (firstArr >= 0 && firstArr < start)) start = firstArr;
  if (start < 0) return null;
  final isArr = start == firstArr;
  final endChar = isArr ? ']' : '}';
  final end = s.lastIndexOf(endChar);
  if (end <= start) return null;
  return s.substring(start, end + 1);
}

Map<String, dynamic> _asRoot(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is List) {
    return <String, dynamic>{
      'items': v,
      'count': v.length,
    };
  }
  throw const FormatException('root');
}

/// 名字拆成"主名 + 括号里的别名"，用于疑似同名判断
List<String> _nameKeys(String n) {
  final out = <String>{n.trim()};
  final base = n.replaceAll(RegExp(r'[（(].*?[)）]'), '').trim();
  if (base.isNotEmpty) out.add(base);
  for (final m in RegExp(r'[（(]([^（）()]*)[)）]').allMatches(n)) {
    final a = (m.group(1) ?? '').trim();
    if (a.isNotEmpty) out.add(a);
  }
  out.removeWhere((e) => e.isEmpty);
  return out.toList();
}

/// 只在"主名/别名完全相等"时命中，避免「蚜虫」误吞「桃蚜」
bool _aliasHit(String a, String b) {
  final ka = _nameKeys(a);
  final kb = _nameKeys(b);
  for (final x in ka) {
    for (final y in kb) {
      if (x == y && x.length >= 2) return true;
    }
  }
  return false;
}

String _s(dynamic v) => v == null ? '' : v.toString().trim();

int _star(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt().clamp(0, 5);
  final t = v.toString().replaceAll(RegExp(r'[^0-9.]'), '');
  final d = double.tryParse(t) ?? 0;
  return d.round().clamp(0, 5);
}

String _extOf(String path) {
  final i = path.lastIndexOf('.');
  if (i < 0) return 'jpg';
  return path.substring(i + 1).toLowerCase();
}
