import 'package:flutter/material.dart';

class AppMotion extends InheritedWidget {
  const AppMotion({
    required this.systemReduced,
    required super.child,
    super.key,
  });

  static const themeDuration = Duration(milliseconds: 200);
  static const expansion = AnimationStyle(
    duration: Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  final bool systemReduced;

  static bool systemReducedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppMotion>()?.systemReduced ??
      MediaQuery.disableAnimationsOf(context);

  static bool enabledOf(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, Duration normal) =>
      enabledOf(context) ? normal : Duration.zero;

  static AnimationStyle expansionOf(BuildContext context) =>
      enabledOf(context) ? expansion : AnimationStyle.noAnimation;

  static AnimationStyle? instantIfReduced(BuildContext context) =>
      enabledOf(context) ? null : AnimationStyle.noAnimation;

  static final instantPageTransitions = PageTransitionsTheme(
    builders: {
      for (final platform in TargetPlatform.values)
        platform: const _InstantPageTransition(),
    },
  );

  @override
  bool updateShouldNotify(AppMotion oldWidget) =>
      systemReduced != oldWidget.systemReduced;
}

class _InstantPageTransition extends PageTransitionsBuilder {
  const _InstantPageTransition();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
