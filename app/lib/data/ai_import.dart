/// AI 数据包（zip）导入：解析 data.json + images/，写入品种库或病虫害库。
///
/// 约定见 docs/08-AI提示词设计.md：App 只读本地文件，不联网。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/images.dart';
import '../core/util.dart';
import 'models.dart';
import 'repo.dart';

class AiImportResult {
  AiImportResult({
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.images = 0,
    this.pending = 0,
    this.error,
    this.kind = '',
    this.cropName = '',
  });

  int added;
  int updated;
  int skipped;
  int images;

  /// 带图待裁剪的条数（列表上会显示「!」）
  int pending;
  String? error;
  String kind;
  String cropName;

  bool get ok => error == null;
}

/// 解析并导入。cropId 是当前顶部选中的作物，zip 里没写 crop 时用它。
Future<AiImportResult> importAiPack({
  required Uint8List bytes,
  required String cropId,
}) async {
  final res = AiImportResult();
  Archive arc;
  try {
    arc = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    res.error = '这个文件不是 zip，或者已损坏';
    return res;
  }

  ArchiveFile? jsonFile;
  for (final f in arc.files) {
    final n = f.name.replaceAll('\\', '/');
    if (n == 'data.json' || n.endsWith('/data.json')) {
      jsonFile = f;
      break;
    }
  }
  if (jsonFile == null) {
    res.error = 'zip 里没有找到 data.json';
    return res;
  }

  Map<String, dynamic> root;
  try {
    root = jsonDecode(utf8.decode(jsonFile.content as List<int>))
        as Map<String, dynamic>;
  } catch (_) {
    res.error = 'data.json 不是合法的 JSON';
    return res;
  }

  final kind = (root['kind'] ?? '').toString();
  if (kind != 'variety' && kind != 'pest') {
    res.error = 'data.json 的 kind 必须是 variety 或 pest';
    return res;
  }
  final fmt = (root['format'] ?? '').toString();
  if (fmt.isNotEmpty && fmt != 'planting.ai') {
    res.error = 'format 不是 planting.ai，可能选错了文件';
    return res;
  }
  final items = (root['items'] as List?) ?? const [];
  if (items.isEmpty) {
    res.error = '这个数据包是空的（items 里没有内容）';
    return res;
  }

  res.kind = kind;

  // zip 里写了作物就按它，否则用当前选中的作物
  var targetCrop = cropId;
  final crops = await Repo.instance.crops();
  final rawCrop = (root['crop'] ?? '').toString().trim();
  for (final c in crops) {
    if (rawCrop.isNotEmpty && (rawCrop == c.id || rawCrop == c.name)) {
      targetCrop = c.id;
      res.cropName = c.name;
    }
  }
  if (res.cropName.isEmpty) {
    for (final c in crops) {
      if (c.id == targetCrop) res.cropName = c.name;
    }
  }

  // 图片索引：images/<文件名>
  final imgMap = <String, Uint8List>{};
  for (final f in arc.files) {
    final n = f.name.replaceAll('\\', '/');
    if (n.startsWith('images/') && !n.endsWith('/') && f.size > 0) {
      imgMap[n.substring('images/'.length)] = f.content as Uint8List;
    }
  }

  for (final raw in items) {
    final m = Map<String, dynamic>.from(raw as Map);
    final name = _s(m['name']);
    if (name.isEmpty) {
      res.skipped++;
      continue;
    }

    // 图片：相对路径落盘；网络图离线版一律忽略
    var imageRef = '';
    final imgRel = _s(m['image']);
    if (imgRel.isNotEmpty && !imgRel.startsWith('http')) {
      final key = imgRel.startsWith('images/')
          ? imgRel.substring('images/'.length)
          : imgRel;
      final data = imgMap[key];
      if (data != null) {
        imageRef = await Images.save(data, ext: _extOf(key));
        res.images++;
        res.pending++;
      }
    }

    if (kind == 'variety') {
      final exists = await _findVariety(targetCrop, name);
      final v = exists ?? Variety(id: newId('var'), crop: targetCrop);
      v.name = name;
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
      }
      v.source = 'ai';
      v.incomplete = v.characteristics.isEmpty && v.care.isEmpty;
      if (exists == null) v.sortOrder = 600;
      await Repo.instance.saveVariety(v);
      exists == null ? res.added++ : res.updated++;
    } else {
      final exists = await _findPest(targetCrop, name);
      final p = exists ?? Pest(id: newId('pest'), sortOrder: 600);
      p.name = name;
      final cat = _s(m['category']);
      p.category = cat.isEmpty ? '病害' : cat;
      p.symptoms = _s(m['symptoms']);
      p.cause = _s(m['cause']);
      p.treatment = _s(m['treatment']);
      p.prevention = _s(m['prevention']);
      if (imageRef.isNotEmpty) {
        p.image = imageRef;
        p.imgPending = true;
      }
      if (exists == null) {
        p.crop = targetCrop;
        p.crops = [targetCrop];
      }
      p.source = 'ai';
      p.incomplete = p.symptoms.isEmpty && p.treatment.isEmpty;
      await Repo.instance.savePest(p);
      exists == null ? res.added++ : res.updated++;
    }
  }
  return res;
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

Future<Variety?> _findVariety(String cropId, String name) async {
  final list = await Repo.instance.varieties(cropId);
  for (final v in list) {
    if (v.name == name) return v;
  }
  return null;
}

Future<Pest?> _findPest(String cropId, String name) async {
  final list = await Repo.instance.pests(cropId);
  for (final p in list) {
    if (p.name == name) return p;
  }
  return null;
}
