import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../core/app_motion.dart';
import '../core/shapes.dart';
import 'app_glass_surface.dart';

/// Retains Material card layout and ink feedback while painting glass behind it.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.margin,
    this.color,
    this.elevation,
    this.shape,
    this.clipBehavior,
    required this.child,
  });

  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? elevation;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    if (surfaces.glass == 0) {
      return Card(
        margin: margin,
        color: color,
        elevation: elevation,
        shape: shape,
        clipBehavior: clipBehavior,
        child: child,
      );
    }

    final theme = CardTheme.of(context);
    final resolvedShape = shape ?? theme.shape;
    final radius = _radiusOf(
      context,
      resolvedShape,
      AppShapeTokens.defaultCardRadius,
    );
    final selectionSide =
        resolvedShape is OutlinedBorder && resolvedShape.side.width > 1
        ? resolvedShape.side
        : BorderSide.none;
    final fill =
        color ?? theme.color ?? Theme.of(context).colorScheme.surfaceContainer;
    return Padding(
      padding: margin ?? theme.margin ?? const EdgeInsets.all(4),
      child: AppGlassSurface(
        color: fill,
        borderRadius: radius,
        grouped: true,
        child: Card(
          margin: EdgeInsets.zero,
          color: surfaces.clearForGlass(fill),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: selectionSide,
          ),
          clipBehavior: clipBehavior,
          child: child,
        ),
      ),
    );
  }
}

/// Glass counterpart for surfaces whose standard layout is a Container.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    this.padding,
    this.width,
    this.height,
    this.decoration,
    required this.child,
  });

  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final BoxDecoration? decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final fill = decoration?.color;
    final radius = decoration?.borderRadius?.resolve(
      Directionality.of(context),
    );
    if (surfaces.glass == 0 || fill == null || radius == null) {
      return Container(
        padding: padding,
        width: width,
        height: height,
        decoration: decoration,
        child: child,
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: AppGlassSurface(
        color: fill,
        borderRadius: radius,
        grouped: true,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

BorderRadius _radiusOf(
  BuildContext context,
  ShapeBorder? shape,
  double fallback,
) => shape is RoundedRectangleBorder
    ? shape.borderRadius.resolve(Directionality.of(context))
    : BorderRadius.circular(fallback);

class AppSurfaceMaterial extends StatelessWidget {
  const AppSurfaceMaterial({
    super.key,
    required this.color,
    required this.borderRadius,
    required this.child,
  });

  final Color color;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final material = Material(
      color: surfaces.clearForGlass(color),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return surfaces.glass == 0
        ? material
        : AppGlassSurface(
            color: color,
            borderRadius: borderRadius,
            grouped: true,
            child: material,
          );
  }
}

/// Reuses the SDK's title, content, actions, sizing, and scrolling layout.
Widget appAlertDialog(
  BuildContext context, {
  Key? key,
  Widget? title,
  Widget? content,
  List<Widget>? actions,
  ShapeBorder? shape,
  bool scrollable = false,
  BoxConstraints? constraints,
  EdgeInsetsGeometry? titlePadding,
  EdgeInsetsGeometry? contentPadding,
  EdgeInsetsGeometry? actionsPadding,
  EdgeInsets? insetPadding,
}) {
  final alert = AlertDialog(
    key: key,
    title: title,
    content: content,
    actions: actions,
    shape: shape,
    scrollable: scrollable,
    constraints: constraints,
    titlePadding: titlePadding,
    contentPadding: contentPadding,
    actionsPadding: actionsPadding,
    insetPadding: insetPadding,
  );
  if (AppSurfaces.of(context).glass == 0) return alert;
  final layout = alert.build(context);
  // Flutter stable builds the laid-out alert as a Dialog. The fallback
  // keeps the stock alert functional if the surrounding layout ever changes.
  return layout is Dialog ? appGlassDialog(context, layout, key: key) : alert;
}

Widget appGlassDialog(BuildContext context, Dialog layout, {Key? key}) {
  final surfaces = AppSurfaces.of(context);
  if (surfaces.glass == 0) return layout;
  final theme = DialogTheme.of(context);
  final shape = layout.shape ?? theme.shape;
  final radius = _radiusOf(context, shape, AppShapeTokens.dialogRadius);
  final fill =
      layout.backgroundColor ??
      theme.backgroundColor ??
      Theme.of(context).colorScheme.surfaceContainer;
  return Dialog(
    key: key ?? layout.key,
    backgroundColor: surfaces.clearForGlass(fill),
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: radius),
    surfaceTintColor: Colors.transparent,
    insetAnimationDuration: layout.insetAnimationDuration,
    insetAnimationCurve: layout.insetAnimationCurve,
    insetPadding: layout.insetPadding,
    clipBehavior: Clip.none,
    alignment: layout.alignment,
    constraints: layout.constraints,
    semanticsRole: layout.semanticsRole,
    child: AppGlassSurface(
      color: fill,
      borderRadius: radius,
      child: layout.child ?? const SizedBox.shrink(),
    ),
  );
}

Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
}) {
  final glass = AppSurfaces.of(context).glass > 0;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: !glass && showDragHandle,
    backgroundColor: glass ? Colors.transparent : null,
    elevation: glass ? 0 : null,
    sheetAnimationStyle: AppMotion.instantIfReduced(context),
    builder: glass
        ? (context) {
            final scheme = Theme.of(context).colorScheme;
            return AppGlassSurface(
              color: scheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppShapeTokens.dialogRadius),
              ),
              child: showDragHandle
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          button: true,
                          label: MaterialLocalizations.of(
                            context,
                          ).modalBarrierDismissLabel,
                          child: InkWell(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 12,
                              ),
                              child: Container(
                                width: 32,
                                height: 4,
                                decoration: ShapeDecoration(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.55,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Flexible(child: builder(context)),
                      ],
                    )
                  : builder(context),
            );
          }
        : builder,
  );
}
