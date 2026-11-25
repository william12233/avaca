import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/settings_controller.dart';
import '../core/app_appearance.dart';
import '../core/app_motion.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import 'app_snackbar.dart';

class AppAppearanceControls extends StatefulWidget {
  const AppAppearanceControls({
    required this.controller,
    required this.tokens,
    super.key,
  });

  final SettingsController controller;
  final AppLayoutTokens tokens;

  @override
  State<AppAppearanceControls> createState() => _AppAppearanceControlsState();
}

class _AppAppearanceControlsState extends State<AppAppearanceControls> {
  bool _previewExpanded = false;
  bool _saving = false;

  void _togglePreview() {
    setState(() => _previewExpanded = !_previewExpanded);
  }

  Future<void> _save(
    Future<bool> Function() change, {
    bool? motionEnabled,
  }) async {
    if (_saving) return;
    _saving = true;
    var saved = false;
    try {
      saved = await change();
    } on Exception catch (error) {
      debugPrint('Appearance preference save failed: $error');
    } finally {
      _saving = false;
    }
    if (!mounted) return;
    if (!saved) {
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context).appearanceSaveFailed,
      );
    } else if (motionEnabled != null) {
      if (motionEnabled && !AppMotion.systemReducedOf(context)) {
        // Mount the animated preview before giving it a new target.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _togglePreview();
        });
      } else {
        _togglePreview();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaces = AppSurfaces.of(context);
    final controller = widget.controller;
    final appearance = controller.appearance;
    final systemReduced = AppMotion.systemReducedOf(context);
    final animate = appearance.motionEnabled && !systemReduced;
    final pureBlack =
        scheme.brightness == Brightness.dark &&
        controller.isPureBlack &&
        !controller.isCustomTheme;
    final radius = BorderRadius.circular(widget.tokens.cardRadius);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.visualTheme, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final visualTheme in AppVisualTheme.values) ...[
              if (visualTheme != AppVisualTheme.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: _ThemePreviewCard(
                  visualTheme: visualTheme,
                  label: visualTheme == AppVisualTheme.standard
                      ? l10n.visualThemeStandard
                      : l10n.visualThemeFrostedGlass,
                  selected: visualTheme == appearance.visualTheme,
                  animate: animate,
                  pureBlack: pureBlack,
                  radius: radius,
                  onTap: () {
                    if (visualTheme != appearance.visualTheme) {
                      _save(() => controller.visualThemeChanged(visualTheme));
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          color: surfaces.panel(scheme.surfaceContainerHighest),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: surfaces.edge(scheme),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const ValueKey('appearance-motion'),
                minTileHeight: widget.tokens.controlHeight,
                title: Text(l10n.motionEffects),
                subtitle: systemReduced
                    ? Text(l10n.motionEffectsSystemReduced)
                    : null,
                value: appearance.motionEnabled,
                onChanged: (enabled) => _save(
                  () => controller.motionEnabledChanged(enabled),
                  motionEnabled: enabled,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: _MotionPreview(
                  expanded: _previewExpanded,
                  animate: animate,
                  radius: radius,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton.icon(
                    onPressed: _togglePreview,
                    icon: const Icon(Icons.swap_vert),
                    label: Text(l10n.motionPreviewToggle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    required this.visualTheme,
    required this.label,
    required this.selected,
    required this.animate,
    required this.pureBlack,
    required this.radius,
    required this.onTap,
  });

  final AppVisualTheme visualTheme;
  final String label;
  final bool selected;
  final bool animate;
  final bool pureBlack;
  final BorderRadius radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sample = AppSurfaces.forTheme(visualTheme, pureBlack: pureBlack);
    final outline = selected ? scheme.primary : scheme.outline;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: AnimatedContainer(
        key: ValueKey(animate),
        duration: animate ? AppMotion.themeDuration : Duration.zero,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerHighest : scheme.surface,
          borderRadius: radius,
          border: Border.all(color: outline, width: 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('appearance-theme-${visualTheme.name}'),
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: radius,
                      child: SizedBox(
                        height: 80,
                        child: DecoratedBox(
                          decoration: sample.backdrop(scheme),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 24,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                alignment: AlignmentDirectional.centerStart,
                                decoration: BoxDecoration(
                                  color: sample.toolbar(
                                    scheme.surfaceContainerHighest,
                                  ),
                                  border: Border(bottom: sample.edge(scheme)),
                                ),
                                child: Text(
                                  AppLocalizations.of(context).appTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (
                                        var index = 0;
                                        index < 2;
                                        index++
                                      ) ...[
                                        if (index > 0) const SizedBox(width: 4),
                                        Expanded(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: sample.panel(
                                                scheme.surfaceContainerHighest,
                                              ),
                                              borderRadius: radius,
                                              border: Border.fromBorderSide(
                                                sample.edge(scheme),
                                              ),
                                            ),
                                            child: Icon(
                                              index == 0
                                                  ? Icons.tune
                                                  : Icons.palette_outlined,
                                              size: 15,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: outline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(label)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MotionPreview extends StatelessWidget {
  const _MotionPreview({
    required this.expanded,
    required this.animate,
    required this.radius,
  });

  final bool expanded;
  final bool animate;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final target = expanded ? 1.0 : 0.0;
    final curve = expanded
        ? AppMotion.expansion.curve!
        : AppMotion.expansion.reverseCurve!;

    Widget sample(double progress) => DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        border: Border.all(color: scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.interfaceSettings)),
                Transform.rotate(
                  angle: math.pi * progress,
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
            if (progress > 0)
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: progress,
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.check, size: 16, color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l10n.followSystem)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      label: expanded
          ? l10n.motionPreviewExpanded
          : l10n.motionPreviewCollapsed,
      key: const ValueKey('appearance-motion-sample'),
      child: ExcludeSemantics(
        child: animate
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: target, end: target),
                duration: AppMotion.expansion.duration!,
                curve: curve,
                builder: (_, progress, _) => sample(progress),
              )
            : sample(target),
      ),
    );
  }
}
