import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_motion.dart';

class AppSnackBar {
  AppSnackBar._();

  static const _maxWidth = 400.0;
  static const _duration = Duration(seconds: 3);
  static const _contentPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  );

  static double _calculateWidth(
    BuildContext context,
    MediaQueryData viewport,
    String message,
    TextStyle textStyle,
    EdgeInsets insetPadding,
  ) {
    final measurementStyle = MediaQuery.boldTextOf(context)
        ? textStyle.merge(const TextStyle(fontWeight: FontWeight.bold))
        : textStyle;
    final textPainter = TextPainter(
      text: TextSpan(text: message, style: measurementStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();

    final contentWidth =
        textPainter.width.ceilToDouble() + _contentPadding.horizontal;
    textPainter.dispose();

    // Flutter applies the horizontal SafeArea inside its centered SnackBar.
    final availableWidth =
        viewport.size.width -
        insetPadding.horizontal -
        2 * viewport.padding.horizontal;
    return math.min(contentWidth, availableWidth.clamp(0.0, _maxWidth));
  }

  static void _show(BuildContext context, String message) {
    final theme = Theme.of(context);
    final snackBarTheme = SnackBarTheme.of(context);
    final textStyle =
        snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium!.copyWith(
          color: theme.colorScheme.onInverseSurface,
        );
    final messenger = ScaffoldMessenger.of(context);
    final width = _calculateWidth(
      context,
      MediaQuery.of(messenger.context),
      message,
      textStyle,
      snackBarTheme.insetPadding ?? const EdgeInsets.all(16),
    );

    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          behavior: SnackBarBehavior.floating,
          duration: _duration,
          width: width,
          padding: _contentPadding,
        ),
        snackBarAnimationStyle: AppMotion.instantIfReduced(context),
      );
  }

  // 顯示成功提示。
  static void showSuccess(BuildContext context, String message) {
    _show(context, message);
  }

  // 顯示錯誤提示。
  static void showError(BuildContext context, String message) {
    _show(context, message);
  }

  // 顯示一般提示。
  static void showInfo(BuildContext context, String message) {
    _show(context, message);
  }
}
