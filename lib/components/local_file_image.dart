import 'dart:io';

import 'package:flutter/material.dart';

/// Displays a managed local image without decoding it at its source size.
///
/// The decode dimensions are derived from the laid-out logical size and the
/// current device pixel ratio. Missing or corrupt files use the same
/// placeholder as an empty path, and no synchronous filesystem probe is made
/// during widget build.
class LocalFileImage extends StatelessWidget {
  const LocalFileImage({
    super.key,
    required this.path,
    required this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String? path;
  final Widget placeholder;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final value = path?.trim();
    if (value == null || value.isEmpty) return placeholder;

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth =
            width ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : null);
        final logicalHeight =
            height ??
            (constraints.hasBoundedHeight ? constraints.maxHeight : null);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return Image.file(
          File(value),
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          cacheWidth: _decodeDimension(logicalWidth, dpr),
          cacheHeight: _decodeDimension(logicalHeight, dpr),
          errorBuilder: (context, error, stackTrace) => placeholder,
        );
      },
    );
  }

  int? _decodeDimension(double? logicalSize, double dpr) {
    if (logicalSize == null || !logicalSize.isFinite || logicalSize <= 0) {
      return null;
    }
    final pixels = (logicalSize * dpr).ceil();
    return pixels > 0 ? pixels : null;
  }
}
