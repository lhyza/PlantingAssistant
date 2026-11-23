import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图片文件统一存在 <documents>/images/ 下，数据库里只存相对路径 `images/xxx.jpg`。
/// 这样导出 JSON 时可以把图片转 base64 带出去。
class Images {
  Images._();

  static String _base = '';

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _base = p.join(dir.path, 'images');
    final d = Directory(_base);
    if (!await d.exists()) await d.create(recursive: true);
  }

  /// 相对路径 → 绝对路径；文件不存在返回 null
  static String? pathOf(String ref) {
    final r = ref.trim();
    if (r.isEmpty) return null;
    if (r.startsWith('data:')) return null;
    final abs = p.isAbsolute(r)
        ? r
        : p.join(_base, r.replaceFirst(RegExp(r'^images/'), ''));
    return File(abs).existsSync() ? abs : null;
  }

  static bool exists(String ref) => pathOf(ref) != null;

  static Future<String> save(Uint8List bytes, {String ext = 'jpg'}) async {
    if (_base.isEmpty) await init();
    final name =
        'img_${newStamp()}_${(DateTime.now().microsecondsSinceEpoch % 997)}.$ext';
    final f = File(p.join(_base, name));
    await f.writeAsBytes(bytes, flush: true);
    return 'images/$name';
  }

  /// 存为文件并返回相对路径；失败返回空串
  static Future<String> saveDataUri(String uri) async {
    try {
      final comma = uri.indexOf(',');
      if (comma < 0) return '';
      final head = uri.substring(5, comma);
      final data = base64.decode(uri.substring(comma + 1));
      final ext = head.contains('png') ? 'png' : 'jpg';
      return save(Uint8List.fromList(data), ext: ext);
    } catch (_) {
      return '';
    }
  }

  /// 相对路径 → data URI（导出用）；文件不存在返回 null
  static Future<String?> dataUri(String ref) async {
    final path = pathOf(ref);
    if (path == null) return null;
    try {
      final bytes = await File(path).readAsBytes();
      final ext = path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      return 'data:image/$ext;base64,${base64.encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String ref) async {
    final path = pathOf(ref);
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  static String newStamp() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${(DateTime.now().microsecond % 1000).toString().padLeft(3, '0')}';
}
