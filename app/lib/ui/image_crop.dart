import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/images.dart';
import '../core/theme.dart';

/// 裁剪结果：图片相对路径 + 像素宽高（显示时按原始比例铺满，不再裁切）。
class CroppedPhoto {
  CroppedPhoto(this.ref, this.width, this.height);
  final String ref;
  final int width;
  final int height;
}

/// 从相册选图 → 裁剪（默认自由比例）→ 存本地。
Future<CroppedPhoto?> pickAndCropPhoto(
  BuildContext context, {
  double? aspect,
}) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 92,
  );
  if (picked == null) return null;
  return _cropBytes(context, await picked.readAsBytes(), aspect: aspect);
}

/// 调起相机拍一张 → 直接进裁剪页（用户确认：一步到位）。
Future<CroppedPhoto?> captureAndCropPhoto(BuildContext context) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 92,
  );
  if (picked == null) return null;
  return _cropBytes(context, await picked.readAsBytes());
}

Future<CroppedPhoto?> _cropBytes(
  BuildContext context,
  Uint8List bytes, {
  double? aspect,
}) async {
  if (!context.mounted) return null;
  final res = await Navigator.push<_CropResult>(
    context,
    MaterialPageRoute(
      builder: (_) => ImageCropperPage(bytes: bytes, initialAspect: aspect),
    ),
  );
  if (res == null) return null;
  final ref = await Images.save(res.bytes, ext: 'png');
  if (ref.isEmpty) return null;
  return CroppedPhoto(ref, res.width, res.height);
}

/// 对已有图片重新裁剪（AI 导入的图需要用户确认）：返回新的相对路径，并删掉旧文件。
Future<CroppedPhoto?> cropExistingPhoto(BuildContext context, String ref) async {
  final path = Images.pathOf(ref);
  if (path == null) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  final res = await _cropBytes(context, await file.readAsBytes());
  if (res == null) return null;
  await Images.remove(ref); // 裁好了就不留旧图
  return res;
}

/// 旧接口：只关心路径（知识库/作物默认图用）。
/// [aspect] 为裁剪页的初始比例；知识库与默认图都按 16:9 存（详情页封面是 16:9）。
Future<String> pickAndCropImage(BuildContext context, {double? aspect}) async {
  final p = await pickAndCropPhoto(context, aspect: aspect);
  return p?.ref ?? '';
}

class _CropResult {
  _CropResult(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

class ImageCropperPage extends StatefulWidget {
  const ImageCropperPage({
    super.key,
    required this.bytes,
    this.initialAspect,
  });

  final Uint8List bytes;

  /// 进页面时预选的比例（null = 自由）
  final double? initialAspect;

  @override
  State<ImageCropperPage> createState() => _ImageCropperPageState();
}

class _ImageCropperPageState extends State<ImageCropperPage> {
  ui.Image? _img;
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _baseScale = 1;
  Offset _baseOffset = Offset.zero;
  Offset _baseFocal = Offset.zero;

  /// null = 自由比例（整张图）
  double? _aspect;
  Size _view = const Size(320, 320);

  @override
  void initState() {
    super.initState();
    _aspect = widget.initialAspect;
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _img = frame.image);
  }

  /// 裁剪框在屏幕上的尺寸
  Size _cropSize(ui.Image img) {
    final v = _view;
    final a = _aspect;
    if (a == null) {
      final s = math.min(v.width / img.width, v.height / img.height);
      return Size(img.width * s, img.height * s);
    }
    final w = math.min(v.width, v.height * a);
    return Size(w, w / a);
  }

  /// 让图片至少盖住裁剪框
  double _fitFor(ui.Image img) {
    final c = _cropSize(img);
    return math.max(c.width / img.width, c.height / img.height);
  }

  Offset _clamp(Offset off, double scale) {
    final img = _img;
    if (img == null) return off;
    final s = _fitFor(img) * scale;
    final c = _cropSize(img);
    final dw = img.width * s;
    final dh = img.height * s;
    final maxX = math.max(0.0, (dw - c.width) / 2);
    final maxY = math.max(0.0, (dh - c.height) / 2);
    return Offset(off.dx.clamp(-maxX, maxX), off.dy.clamp(-maxY, maxY));
  }

  Future<void> _done() async {
    final img = _img;
    if (img == null) return;
    final s = _fitFor(img) * _scale;
    final c = _cropSize(img);
    final dw = img.width * s;
    final dh = img.height * s;
    final ox = (_view.width - dw) / 2 + _offset.dx;
    final oy = (_view.height - dh) / 2 + _offset.dy;

    var ix = (0 - ox) / s + ((_view.width - c.width) / 2) / s;
    var iy = (0 - oy) / s + ((_view.height - c.height) / 2) / s;
    var iw = c.width / s;
    var ih = c.height / s;
    if (_aspect == null) {
      ix = 0;
      iy = 0;
      iw = img.width.toDouble();
      ih = img.height.toDouble();
    }
    ix = ix.clamp(0.0, math.max(0.0, img.width - iw));
    iy = iy.clamp(0.0, math.max(0.0, img.height - ih));
    iw = math.min(iw, img.width.toDouble());
    ih = math.min(ih, img.height.toDouble());

    final ratio = math.min(1.0, 1600 / math.max(iw, ih));
    final outW = math.max(1, (iw * ratio).round());
    final outH = math.max(1, (ih * ratio).round());
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(ix, iy, iw, ih),
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final pic = rec.endRecording();
    final outImage = await pic.toImage(outW, outH);
    final data = await outImage.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.pop(
      context,
      _CropResult(data!.buffer.asUint8List(), outW, outH),
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    return Scaffold(
      backgroundColor: const Color(0xFF171514),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171514),
        foregroundColor: Colors.white,
        title: const Text('调整图片'),
        actions: [
          TextButton(
            onPressed: img == null ? null : _done,
            child: const Text(
              '使用',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Text(
                _aspect == null ? '整张照片都会保存，可双指缩放微调' : '双指缩放、拖动图片，把想要的部分放到框里',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
            Expanded(
              child: img == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        _view = Size(
                          math.max(80, c.maxWidth - 40),
                          math.max(80, c.maxHeight - 16),
                        );
                        _offset = _clamp(_offset, _scale);
                        final crop = _cropSize(img);
                        return Center(
                          child: SizedBox(
                            width: _view.width,
                            height: _view.height,
                            child: GestureDetector(
                              onScaleStart: (d) {
                                _baseScale = _scale;
                                _baseOffset = _offset;
                                _baseFocal = d.focalPoint;
                              },
                              onScaleUpdate: (d) {
                                final next = (_baseScale * d.scale).clamp(
                                  1.0,
                                  8.0,
                                );
                                setState(() {
                                  _scale = next;
                                  _offset = _clamp(
                                    _baseOffset + (d.focalPoint - _baseFocal),
                                    next,
                                  );
                                });
                              },
                              child: ClipRect(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CustomPaint(
                                      painter: _CropPainter(
                                        img: img,
                                        scale: _scale,
                                        offset: _offset,
                                        fit: _fitFor(img),
                                      ),
                                    ),
                                    if (_aspect != null)
                                      Center(
                                        child: IgnorePointer(
                                          child: SizedBox(
                                            width: crop.width,
                                            height: crop.height,
                                            child: CustomPaint(
                                              painter: _GridPainter(),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  _ratioBtn('自由', null),
                  const SizedBox(width: 8),
                  _ratioBtn('1:1', 1),
                  const SizedBox(width: 8),
                  _ratioBtn('4:3', 4 / 3),
                  const SizedBox(width: 8),
                  _ratioBtn('16:9', 16 / 9),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _scale = 1;
                      _offset = Offset.zero;
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    child: const Text('重置'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: FilledButton(
                onPressed: img == null ? null : _done,
                style: FilledButton.styleFrom(
                  backgroundColor: kRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                ),
                child: const Text('使用这张'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratioBtn(String text, double? aspect) {
    final on = _aspect == aspect;
    return GestureDetector(
      onTap: () => setState(() {
        _aspect = aspect;
        _scale = 1;
        _offset = Offset.zero;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: on ? kInk : Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.img,
    required this.scale,
    required this.offset,
    required this.fit,
  });

  final ui.Image img;
  final double scale;
  final Offset offset;
  final double fit;

  @override
  void paint(Canvas canvas, Size size) {
    final s = fit * scale;
    final dw = img.width * s;
    final dh = img.height * s;
    final ox = (size.width - dw) / 2 + offset.dx;
    final oy = (size.height - dh) / 2 + offset.dy;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(ox, oy, dw, dh),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.scale != scale || old.offset != offset || old.img != img;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
