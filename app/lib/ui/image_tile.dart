import 'dart:io';

import 'package:flutter/material.dart';

import '../core/images.dart';
import '../core/theme.dart';

/// 本地图片；没有图时用 [fallbackRef]，再没有就显示占位块。
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
