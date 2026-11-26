import 'dart:io';

import 'package:flutter/material.dart';

import '../data/models.dart';

import '../core/images.dart';
import '../core/theme.dart';

/// 本地图片；没有图时用 [fallbackRef]，再没有就显示占位块。
/// 作物图标：有自定义小图显示图片，否则回落到 emoji。
/// 用在 chips、阶段条标题、作物列表这些「图标很小」的地方。
class CropIcon extends StatelessWidget {
  const CropIcon({
    super.key,
    required this.iconRef,
    required this.emoji,
    this.size = 18,
    this.fontSize = 13,
    this.radius = 5,
  });

  final String iconRef;
  final String emoji;
  final double size;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = Images.pathOf(iconRef);
    if (path == null) {
      return Text(emoji, style: TextStyle(fontSize: fontSize, height: 1.1));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Text(emoji, style: TextStyle(fontSize: fontSize, height: 1.1)),
      ),
    );
  }
}

class LocalImage extends StatelessWidget {
  const LocalImage({
    super.key,
    required this.ref,
    this.fallbackRef = '',
    this.width,
    this.height,
    this.radius = 12,
    this.fit = BoxFit.cover,
    this.iconSize = 22,
  });

  final String ref;
  final String fallbackRef;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final use = Images.exists(ref)
        ? ref
        : (Images.exists(fallbackRef) ? fallbackRef : '');
    final path = Images.pathOf(use);
    final placeholder = _Placeholder(iconSize: iconSize);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: path == null
            ? placeholder
            : Image.file(
                File(path),
                fit: fit,
                width: width,
                height: height,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.iconSize = 22});
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGreenBg,
      alignment: Alignment.center,
      child: Icon(
        Icons.local_florist_outlined,
        size: iconSize,
        color: kGreen.withValues(alpha: 0.45),
      ),
    );
  }
}

/// 作物「图标 + 名字」(v2.0.4)：有自定义小图用图，否则 emoji。
/// 全 App 需要显示「作物图标 + 名字」的地方都走这里，避免各处只写 emoji。
Widget cropLabel(
  Crop c, {
  double size = 17,
  double fontSize = 12.5,
  TextStyle? style,
  String? text,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CropIcon(iconRef: c.iconImage, emoji: c.emoji, size: size, fontSize: fontSize),
      const SizedBox(width: 4),
      Text(text ?? c.name, style: style ?? TextStyle(fontSize: fontSize)),
    ],
  );
}
