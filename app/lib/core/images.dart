import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
  /// 图标用途的小图：等比缩进 size×size 方框（透明底），存成 PNG。
  /// 作物图标只有十几到几十像素，没必要留原图。
  static Future<String> saveScaled(Uint8List bytes, {int size = 128}) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final long = src.width > src.height ? src.width : src.height;
      final scale = size / long;
      final w = src.width * scale;
      final h = src.height * scale;
      canvas.drawImageRect(
        src,
        ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        ui.Rect.fromLTWH((size - w) / 2, (size - h) / 2, w, h),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final out = await recorder.endRecording().toImage(size, size);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      src.dispose();
      out.dispose();
      if (data == null) return '';
      return save(data.buffer.asUint8List(), ext: 'png');
    } catch (_) {
      return '';
    }
  }

  /// 把已存的文件压到 size，成功后删掉原文件；失败保留原文件并返回空串
  static Future<String> shrinkTo(String ref, {int size = 128}) async {
    final path = pathOf(ref);
    if (path == null) return '';
    try {
      final bytes = await File(path).readAsBytes();
      final out = await saveScaled(bytes, size: size);
      if (out.isEmpty) return '';
      if (out != ref) await remove(ref);
      return out;
    } catch (_) {
      return '';
    }
  }

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
