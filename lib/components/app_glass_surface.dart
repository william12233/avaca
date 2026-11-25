import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_appearance.dart';

class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.color,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.surfaces,
    this.grouped = false,
  });

  final Color color;
  final Widget child;
  final BorderRadius borderRadius;
  final AppSurfaces? surfaces;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final glass = (surfaces ?? AppSurfaces.of(context)).glass;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sigma = 14 * glass;
    final filter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    final fill = ColoredBox(
      color: color.withValues(alpha: color.a * glass * (dark ? 0.45 : 0.43)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.36, 0.72, 1],
            colors: [
              Colors.white.withValues(alpha: glass * (dark ? 0.19 : 0.66)),
              Colors.white.withValues(alpha: glass * (dark ? 0.04 : 0.12)),
              Colors.transparent,
              (dark ? Colors.black : Colors.white).withValues(
                alpha: glass * 0.15,
              ),
            ],
          ),
        ),
        child: CustomPaint(
          foregroundPainter: glass > 0 && borderRadius != BorderRadius.zero
              ? _GlassRim(
                  borderRadius,
                  reflection: glass * (dark ? 0.34 : 0.85),
                  edgeShade: (dark ? Colors.white : Colors.black).withValues(
                    alpha: glass * (dark ? 0.10 : 0.15),
                  ),
                )
              : null,
          child: child,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: glass > 0 ? Clip.antiAlias : Clip.none,
      child: grouped
          ? BackdropFilter.grouped(
              enabled: glass > 0,
              filter: filter,
              child: fill,
            )
          : BackdropFilter(enabled: glass > 0, filter: filter, child: fill),
    );
  }
}

class _GlassRim extends CustomPainter {
  const _GlassRim(
    this.radius, {
    required this.reflection,
    required this.edgeShade,
  });

  final BorderRadius radius;
  final double reflection;
  final Color edgeShade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, 0.38, 0.70, 1],
        colors: [
          Colors.white.withValues(alpha: reflection),
          Colors.white.withValues(alpha: reflection * 0.52),
          Colors.transparent,
          edgeShade,
        ],
      ).createShader(bounds);
    canvas.drawRRect(radius.toRRect(bounds).deflate(0.75), stroke);
  }

  @override
  bool shouldRepaint(_GlassRim oldDelegate) =>
      radius != oldDelegate.radius ||
      reflection != oldDelegate.reflection ||
      edgeShade != oldDelegate.edgeShade;
}
