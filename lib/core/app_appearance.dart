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
  const AppSurfaces({this.glass = 0});

  factory AppSurfaces.forTheme(AppVisualTheme theme) => switch (theme) {
    AppVisualTheme.standard => const AppSurfaces(),
    AppVisualTheme.frostedGlass => const AppSurfaces(glass: 1),
  };

  final double glass;

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>() ?? const AppSurfaces();

  Color clearForGlass(Color base) =>
      base.withValues(alpha: base.a * (1 - glass));

  @override
  AppSurfaces copyWith({double? glass}) =>
      AppSurfaces(glass: glass ?? this.glass);

  @override
  AppSurfaces lerp(AppSurfaces? other, double t) => other == null
      ? this
      : AppSurfaces(glass: lerpDouble(glass, other.glass, t)!);

  @override
  bool operator ==(Object other) =>
      other is AppSurfaces && glass == other.glass;

  @override
  int get hashCode => glass.hashCode;
}
