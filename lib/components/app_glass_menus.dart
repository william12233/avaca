import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../core/app_motion.dart';
import '../core/shapes.dart';
import 'app_glass_surface.dart';

class AppPopupMenuButton<T> extends StatelessWidget {
  const AppPopupMenuButton({
    super.key,
    required this.icon,
    required this.onSelected,
    required this.itemBuilder,
    this.popUpAnimationStyle,
  });

  final Widget icon;
  final ValueChanged<T> onSelected;
  final PopupMenuItemBuilder<T> itemBuilder;
  final AnimationStyle? popUpAnimationStyle;

  @override
  Widget build(BuildContext context) {
    if (AppSurfaces.of(context).glass == 0) {
      return PopupMenuButton<T>(
        icon: icon,
        onSelected: onSelected,
        itemBuilder: itemBuilder,
        popUpAnimationStyle: popUpAnimationStyle,
      );
    }
    return _GlassMenu(
      alignment: AlignmentDirectional.bottomEnd,
      entries: [
        for (final entry in itemBuilder(context))
          if (entry is PopupMenuItem<T>)
            MenuItemButton(
              key: entry.key,
              onPressed: entry.enabled
                  ? () {
                      entry.onTap?.call();
                      final value = entry.value;
                      if (value != null) onSelected(value);
                    }
                  : null,
              child: entry.child,
            )
          else if (entry is PopupMenuDivider)
            const SizedBox(height: 8),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        icon: icon,
        onPressed: () => _toggleMenu(controller),
      ),
    );
  }
}

/// Both callers save a selection immediately; the standard theme uses the
/// native form field, while glass uses the same anchored menu as the toolbar.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    required this.decoration,
    this.isExpanded = false,
    this.elevation = 3,
    this.dropdownColor,
    this.borderRadius,
  });
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  final int elevation;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    if (AppSurfaces.of(context).glass == 0) {
      return DropdownButtonFormField<T>(
        initialValue: initialValue,
        items: items,
        onChanged: onChanged,
        decoration: decoration,
        isExpanded: isExpanded,
        elevation: elevation,
        dropdownColor: dropdownColor,
        borderRadius: borderRadius,
      );
    }
    final selected = items
        .where((item) => item.value == initialValue)
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) => _GlassMenu(
        alignment: AlignmentDirectional.bottomStart,
        width: constraints.maxWidth,
        entries: [
          for (final item in items)
            MenuItemButton(
              key: item.key,
              onPressed: item.enabled && onChanged != null
                  ? () => onChanged!(item.value)
                  : null,
              trailingIcon: identical(item, selected)
                  ? const Icon(Icons.check, size: 16)
                  : null,
              child: item.child,
            ),
        ],
        builder: (context, controller, _) => InkWell(
          borderRadius: BorderRadius.circular(AppShapeTokens.inputRadius),
          onTap: onChanged == null ? null : () => _toggleMenu(controller),
          child: InputDecorator(
            decoration: decoration.copyWith(
              enabled: onChanged != null,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            isFocused: controller.isOpen,
            isEmpty: selected == null,
            child: selected?.child,
          ),
        ),
      ),
    );
  }
}

void _toggleMenu(MenuController controller) {
  if (controller.isOpen) {
    controller.close();
  } else {
    controller.open();
  }
}

class _GlassMenu extends StatelessWidget {
  const _GlassMenu({
    required this.alignment,
    required this.entries,
    required this.builder,
    this.width,
  });

  final AlignmentDirectional alignment;
  final List<Widget> entries;
  final MenuAnchorChildBuilder builder;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final radius = BorderRadius.circular(AppShapeTokens.popupMenuRadius);
    return MenuAnchor(
      animated: AppMotion.enabledOf(context),
      style: MenuStyle(
        alignment: alignment,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        elevation: const WidgetStatePropertyAll(0),
        maximumSize: WidgetStatePropertyAll(
          Size(
            (viewport.width - 32).clamp(0, double.infinity),
            viewport.height * 0.67,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      builder: builder,
      menuChildren: [
        AppGlassSurface(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: radius,
          child: SizedBox(
            width: width,
            child: IntrinsicWidth(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: entries,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
