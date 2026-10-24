import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The two composition classes used by the adaptive UI.
///
/// The class is derived from the available width. It intentionally does not
/// encode an operating system, device name, or physical device category.
enum AppLayoutClass { compact, expanded }

/// The measured geometry for an item grid.
///
/// The grid is intentionally allowed to use a narrower rail than the page.
/// That keeps sparse collections centred and prevents a wide monitor from
/// turning small cards into a left-aligned island in a huge empty grid.
@immutable
class AppGridGeometry {
  const AppGridGeometry({
    required this.columns,
    required this.itemWidth,
    required this.railWidth,
  });

  final int columns;
  final double itemWidth;
  final double railWidth;
}

/// Semantic layout values shared by the primary views.
@immutable
class AppLayoutTokens {
  const AppLayoutTokens({
    required this.layoutClass,
    required this.pagePadding,
    required this.contentMaxWidth,
    required this.sectionGap,
    required this.gridGap,
    required this.gridPadding,
    required this.cardRadius,
    required this.controlHeight,
    required this.minimumInteractiveSize,
    required this.contentColumnGap,
    required this.formMaxWidth,
    required this.detailImageMaxSize,
    required this.homeCardMinWidth,
    required this.homeCardMaxWidth,
    required this.homeMaxUsefulColumns,
    required this.workCardMinWidth,
    required this.workCardMaxWidth,
    required this.workMaxUsefulColumns,
    required this.workCardSmallMinWidth,
    required this.workCardSmallMaxWidth,
    required this.workSmallMaxUsefulColumns,
    required this.detailPaneMinWidth,
    required this.detailMiddleMinWidth,
    required this.detailBodyMinWidth,
    required this.settingsShortContentMaxWidth,
  });

  final AppLayoutClass layoutClass;
  final EdgeInsets pagePadding;
  final double contentMaxWidth;
  final double sectionGap;
  final double gridGap;
  final EdgeInsets gridPadding;
  /// Radius of the outer card/panel. Framed children should match this value.
  ///
  /// Keep the responsive values documented in `docs/ui-guidelines.md`.
  final double cardRadius;
  final double controlHeight;
  final double minimumInteractiveSize;
  final double contentColumnGap;
  final double formMaxWidth;
  final double detailImageMaxSize;
  final double homeCardMinWidth;
  final double homeCardMaxWidth;
  final int homeMaxUsefulColumns;
  final double workCardMinWidth;
  final double workCardMaxWidth;
  final int workMaxUsefulColumns;
  final double workCardSmallMinWidth;
  final double workCardSmallMaxWidth;
  final int workSmallMaxUsefulColumns;
  final double detailPaneMinWidth;
  final double detailMiddleMinWidth;
  final double detailBodyMinWidth;
  final double settingsShortContentMaxWidth;

  bool get isCompact => layoutClass == AppLayoutClass.compact;

  bool get isExpanded => layoutClass == AppLayoutClass.expanded;

  /// Calculates a stable grid column count from available space.
  int columnsForWidth(
    double width, {
    required double minItemWidth,
    int minColumns = 1,
    int maxColumns = 9,
  }) {
    final availableWidth = math.max(0, width - gridPadding.horizontal);
    final count = ((availableWidth + gridGap) / (minItemWidth + gridGap))
        .floor();
    return count.clamp(minColumns, maxColumns).toInt();
  }

  /// Measures a useful, item-count-aware rail for a grid.
  AppGridGeometry gridGeometry({
    required double availableWidth,
    required double minItemWidth,
    required double maxItemWidth,
    required int itemCount,
    required int maxUsefulColumns,
    int minColumns = 1,
  }) {
    if (itemCount <= 0 || availableWidth <= 0) {
      return const AppGridGeometry(columns: 1, itemWidth: 0, railWidth: 0);
    }

    final innerWidth = math.max(0, availableWidth - gridPadding.horizontal);
    final widthColumns = math.max(
      1,
      ((innerWidth + gridGap) / (minItemWidth + gridGap)).floor(),
    );
    final columnLimit = math.min(
      math.min(widthColumns, maxUsefulColumns),
      itemCount,
    );
    final columns = math.max(minColumns, columnLimit);
    final measuredItemWidth = (innerWidth - gridGap * (columns - 1)) / columns;
    final safeMinimumWidth = math.min(minItemWidth, innerWidth);
    final itemWidth = measuredItemWidth
        .clamp(safeMinimumWidth, maxItemWidth)
        .toDouble();
    final railWidth = itemWidth * columns + gridGap * (columns - 1);

    return AppGridGeometry(
      columns: columns,
      itemWidth: itemWidth,
      railWidth: railWidth,
    );
  }

  double detailIntermediateRequiredRail(double textScale) {
    return detailImageMaxSize +
        contentColumnGap +
        detailPaneMinWidth * textScale;
  }

  double detailWideRequiredRail(double textScale) {
    return detailImageMaxSize +
        detailMiddleMinWidth * textScale +
        detailBodyMinWidth * textScale +
        contentColumnGap * 2;
  }

  bool canUseWideDetail(double railWidth, double textScale) {
    return railWidth >= detailWideRequiredRail(textScale);
  }

  bool canUseIntermediateDetail(double railWidth, double textScale) {
    return railWidth >= detailIntermediateRequiredRail(textScale);
  }
}

/// The single source of truth for adaptive layout measurement and tokens.
class AppLayoutPolicy {
  AppLayoutPolicy._();

  /// The first width at which the expanded composition is allowed.
  static const double expandedBreakpoint = 672;

  static const double _contentMaxWidth = 1440;

  static const AppLayoutTokens _compactTokens = AppLayoutTokens(
    layoutClass: AppLayoutClass.compact,
    pagePadding: EdgeInsets.all(16),
    contentMaxWidth: _contentMaxWidth,
    sectionGap: 16,
    gridGap: 10,
    gridPadding: EdgeInsets.all(10),
    cardRadius: 12,
    controlHeight: 48,
    minimumInteractiveSize: 48,
    contentColumnGap: 16,
    formMaxWidth: 360,
    detailImageMaxSize: 220,
    homeCardMinWidth: 120,
    homeCardMaxWidth: 180,
    homeMaxUsefulColumns: 3,
    workCardMinWidth: 128,
    workCardMaxWidth: 220,
    workMaxUsefulColumns: 4,
    workCardSmallMinWidth: 96,
    workCardSmallMaxWidth: 220,
    workSmallMaxUsefulColumns: 4,
    detailPaneMinWidth: 360,
    detailMiddleMinWidth: 360,
    detailBodyMinWidth: 360,
    settingsShortContentMaxWidth: 360,
  );

  static const AppLayoutTokens _expandedTokens = AppLayoutTokens(
    layoutClass: AppLayoutClass.expanded,
    pagePadding: EdgeInsets.all(24),
    contentMaxWidth: _contentMaxWidth,
    sectionGap: 24,
    gridGap: 10,
    gridPadding: EdgeInsets.all(10),
    cardRadius: 16,
    controlHeight: 48,
    minimumInteractiveSize: 48,
    contentColumnGap: 24,
    formMaxWidth: 640,
    detailImageMaxSize: 260,
    homeCardMinWidth: 112,
    homeCardMaxWidth: 220,
    homeMaxUsefulColumns: 4,
    workCardMinWidth: 160,
    workCardMaxWidth: 240,
    workMaxUsefulColumns: 4,
    workCardSmallMinWidth: 128,
    workCardSmallMaxWidth: 192,
    workSmallMaxUsefulColumns: 6,
    detailPaneMinWidth: 360,
    detailMiddleMinWidth: 360,
    detailBodyMinWidth: 360,
    settingsShortContentMaxWidth: 640,
  );

  /// Resolves tokens from constraints, not from platform or device identity.
  static AppLayoutTokens resolve(BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.biggest.width;
    return width < expandedBreakpoint ? _compactTokens : _expandedTokens;
  }
}
