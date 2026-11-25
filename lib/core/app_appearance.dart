import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

enum AppVisualTheme { standard, frostedGlass }

typedef AppAppearance = ({AppVisualTheme visualTheme, bool motionEnabled});

const AppAppearance defaultAppearance = (
  visualTheme: AppVisualTheme.standard,
  motionEnabled: true,
);

@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({this.glass = 0, this.tint = 0});

  factory AppSurfaces.forTheme(
    AppVisualTheme theme, {
    required bool pureBlack,
  }) {
    return switch (theme) {
      AppVisualTheme.standard => const AppSurfaces(),
      AppVisualTheme.frostedGlass => AppSurfaces(
        glass: 1,
        tint: pureBlack ? 0 : 1,
      ),
    };
  }

  final double glass;
  final double tint;

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>() ?? const AppSurfaces();

  BoxDecoration backdrop(ColorScheme scheme, {Color? background}) {
    final dark = scheme.brightness == Brightness.dark;
    final base = Color.alphaBlend(
      background ?? scheme.surface,
      dark ? const Color(0xFF121212) : Colors.white,
    );
    return BoxDecoration(
      color: base,
      gradient: tint == 0
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0, 0.53, 1],
              colors: [
                Color.alphaBlend(
                  (dark ? const Color(0xFF226279) : const Color(0xFF8ED4DB))
                      .withValues(alpha: tint * 0.34),
                  base,
                ),
                base,
                Color.alphaBlend(
                  (dark ? const Color(0xFF3A4D84) : const Color(0xFFA4B7F1))
                      .withValues(alpha: tint * 0.27),
                  base,
                ),
              ],
            ),
    );
  }

  Color panel(Color base) =>
      base.withValues(alpha: base.a * (1 - glass * 0.36));

  Color toolbar(Color base) =>
      base.withValues(alpha: base.a * (1 - glass * 0.42));

  BorderSide edge(ColorScheme scheme) => glass == 0
      ? BorderSide.none
      : BorderSide(
          color: scheme.outline.withValues(
            alpha: scheme.outline.a * glass * 0.75,
          ),
        );

  @override
  AppSurfaces copyWith({double? glass, double? tint}) =>
      AppSurfaces(glass: glass ?? this.glass, tint: tint ?? this.tint);

  @override
  AppSurfaces lerp(AppSurfaces? other, double t) => other == null
      ? this
      : AppSurfaces(
          glass: lerpDouble(glass, other.glass, t)!,
          tint: lerpDouble(tint, other.tint, t)!,
        );

  @override
  bool operator ==(Object other) =>
      other is AppSurfaces && glass == other.glass && tint == other.tint;

  @override
  int get hashCode => Object.hash(glass, tint);
}
