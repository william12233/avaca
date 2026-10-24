/// Shared shape values for surfaces that do not have responsive layout tokens.
///
/// Keep new UI aligned with `docs/ui-guidelines.md`. In particular, controls
/// inside a framed surface should use that surface's radius instead of adding
/// a new literal radius.
///
/// Responsive cards use [AppLayoutTokens.cardRadius]. These values cover
/// app-wide components such as dialogs and the default input decoration.
abstract final class AppShapeTokens {
  AppShapeTokens._();

  /// Material 3's large dialog shape, used consistently by app dialogs.
  static const double dialogRadius = 28;

  /// The base card/input shape used by pages without a responsive card token.
  static const double defaultCardRadius = 12;

  static const double inputRadius = defaultCardRadius;

  /// Menus should use the same compact surface language as cards and inputs.
  static const double popupMenuRadius = defaultCardRadius;
}
