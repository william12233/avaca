import 'package:flutter/material.dart';

import '../core/app_appearance.dart';

/// Paints the current surface behind this page, including its toolbar.
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, this.appBar, this.body, this.backgroundColor});

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaces.of(context);
    final base = backgroundColor ?? theme.scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: surfaces.glass == 0
          ? const BoxDecoration()
          : surfaces.backdrop(theme.colorScheme, background: base),
      child: Scaffold(
        appBar: appBar,
        body: body,
        backgroundColor: surfaces.glass == 0
            ? backgroundColor
            : base.withValues(alpha: base.a * (1 - surfaces.glass)),
      ),
    );
  }
}
