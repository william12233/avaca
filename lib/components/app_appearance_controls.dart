import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../core/app_motion.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import 'app_glass_surface.dart';
import 'app_motion_preview.dart';

class AppThemeChoices extends StatelessWidget {
  const AppThemeChoices({
    super.key,
    required this.selected,
    required this.tokens,
    required this.onChanged,
  });

  final AppVisualTheme selected;
  final AppLayoutTokens tokens;
  final ValueChanged<AppVisualTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(tokens.cardRadius);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        for (final theme in AppVisualTheme.values)
          Expanded(
            child: _ThemeChoice(
              visualTheme: theme,
              label: switch (theme) {
                AppVisualTheme.standard => l10n.visualThemeStandard,
                AppVisualTheme.frostedGlass => l10n.visualThemeFrostedGlass,
              },
              selected: theme == selected,
              radius: radius,
              onTap: () {
                if (theme != selected) onChanged(theme);
              },
            ),
          ),
      ],
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.visualTheme,
    required this.label,
    required this.selected,
    required this.radius,
    required this.onTap,
  });

  final AppVisualTheme visualTheme;
  final String label;
  final bool selected;
  final BorderRadius radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sample = AppSurfaces.forTheme(visualTheme);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        shape: RoundedRectangleBorder(borderRadius: radius),
        color: selected ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
        child: InkWell(
          key: ValueKey('appearance-theme-${visualTheme.name}'),
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                ExcludeSemantics(
                  child: _ThemeThumbnail(radius: radius, surfaces: sample),
                ),
                Row(
                  spacing: 6,
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 17,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    Expanded(child: Text(label)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeThumbnail extends StatelessWidget {
  const _ThemeThumbnail({required this.radius, required this.surfaces});

  final BorderRadius radius;
  final AppSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: scheme.surface,
          child: SizedBox(
            height: (constraints.maxWidth * 0.69).clamp(96.0, 134.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 13, 6, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: [
                      for (var index = 0; index < 3; index++)
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              border: Border.all(
                                color: scheme.outline.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 30,
                  child: AppGlassSurface(
                    color: scheme.surface,
                    surfaces: surfaces,
                    child: ColoredBox(
                      color: surfaces.clearForGlass(scheme.surface),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context).appTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.search_rounded,
                              size: 12,
                              color: scheme.onSurface,
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.settings_outlined,
                              size: 12,
                              color: scheme.onSurface,
                            ),
                          ],
                        ),
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
  }
}

class AppMotionControl extends StatelessWidget {
  const AppMotionControl({
    super.key,
    required this.enabled,
    required this.tokens,
    required this.onChanged,
  });

  final bool enabled;
  final AppLayoutTokens tokens;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);
    final systemReduced = AppMotion.systemReducedOf(context);
    final radius = BorderRadius.circular(tokens.cardRadius);
    final color = scheme.surfaceContainerHighest;

    return AppGlassSurface(
      color: color,
      borderRadius: radius,
      grouped: true,
      child: Card(
        margin: EdgeInsets.zero,
        color: surfaces.clearForGlass(color),
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const ValueKey('appearance-motion'),
              minTileHeight: tokens.controlHeight,
              title: Text(l10n.motionEffects),
              subtitle: systemReduced
                  ? Text(l10n.motionEffectsSystemReduced)
                  : null,
              value: enabled,
              onChanged: onChanged,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: AppMotionPreview(
                animate: enabled && !systemReduced,
                radius: radius,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
