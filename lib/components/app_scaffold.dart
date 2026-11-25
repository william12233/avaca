import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import 'app_glass_surface.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.scrollUnderGlassToolbar = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor;

  /// The body adds the Scaffold's top media padding to its scrollable content.
  final bool scrollUnderGlassToolbar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaces.of(context);
    final base = backgroundColor ?? theme.scaffoldBackgroundColor;
    final toolbar = appBar;
    return Scaffold(
      appBar: toolbar == null
          ? null
          : PreferredSize(
              preferredSize: toolbar.preferredSize,
              child: AppGlassSurface(color: base, child: toolbar),
            ),
      extendBodyBehindAppBar:
          toolbar != null && scrollUnderGlassToolbar && surfaces.glass > 0,
      body: body == null ? null : BackdropGroup(child: body!),
      backgroundColor: backgroundColor,
    );
  }
}
