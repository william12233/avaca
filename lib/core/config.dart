import 'package:flutter/material.dart';

import 'shapes.dart';

/// 使用者可選擇的主題模式。
///
/// OLED 純黑不是獨立的 ThemeMode，而是在解析色票後套用的背景覆蓋規則。
enum AppThemeMode { system, light, dark, custom }

/// App 內部使用的用途導向色票。
///
/// 這裡的名稱代表 UI 用途，不代表具體顏色名稱。
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.surface,
    required this.surfaceContainer,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.onPrimary,
    required this.outline,
    this.snackbarBackground = Colors.black,
  });

  /// 色票偏向淺色或深色。
  final Brightness brightness;

  /// 畫面背景，例如 Scaffold、AppBar 或整體底色。
  final Color surface;

  /// 卡片與區塊背景，例如 Card、搜尋列、設定列或容器。
  final Color surfaceContainer;

  /// 主要文字與主要 icon 顏色。
  final Color onSurface;

  /// 次要文字、提示文字、補充說明與弱化 icon 顏色。
  final Color onSurfaceVariant;

  /// 主要強調色，例如主要按鈕、選取狀態、focus 狀態與重要操作入口。
  final Color primary;

  /// primary 背景上的文字與 icon 顏色。
  final Color onPrimary;

  /// 邊框與分隔線顏色。
  final Color outline;

  /// 暫時性通知（SnackBar）的背景色。
  ///
  /// 預設值保留給舊版自訂色票資料；內建淺色與深色色票會明確設定為
  /// 白色與黑色。
  final Color snackbarBackground;

  AppPalette copyWith({
    Brightness? brightness,
    Color? surface,
    Color? surfaceContainer,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? primary,
    Color? onPrimary,
    Color? outline,
    Color? snackbarBackground,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      surface: surface ?? this.surface,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      outline: outline ?? this.outline,
      snackbarBackground: snackbarBackground ?? this.snackbarBackground,
    );
  }
}

/// 預設基礎色票集合。
///
/// OLED 覆蓋不放在這裡，避免把 OLED 當成第三套主題。
class AppPalettes {
  AppPalettes._();

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    surface: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF5F5F5),
    onSurface: Color(0xFF1F1F1F),
    onSurfaceVariant: Color(0xFF6B6B6B),
    primary: Color(0xFF4A4A4A),
    onPrimary: Color(0xFFFFFFFF),
    outline: Color(0xFFBDBDBD),
    snackbarBackground: Color(0xFFFFFFFF),
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    surface: Color(0xFF121212),
    surfaceContainer: Color(0xFF1E1E1E),
    onSurface: Color(0xFFE6E6E6),
    onSurfaceVariant: Color(0xFFA0A0A0),
    primary: Color(0xFFB0B0B0),
    onPrimary: Color(0xFF121212),
    outline: Color(0xFF4A4A4A),
    snackbarBackground: Color(0xFF000000),
  );
}

/// OLED 純黑背景覆蓋規則。
///
/// 只覆蓋背景類色票，不改文字、主要強調色與邊框。
class AppOledPaletteOverride {
  AppOledPaletteOverride._();

  static AppPalette apply(AppPalette palette) {
    if (palette.brightness != Brightness.dark) {
      return palette;
    }

    return palette.copyWith(
      surface: const Color(0xFF000000),
      surfaceContainer: const Color(0xFF121212),
    );
  }
}

/// 主題設定資料。
///
/// customPalette 只在 custom 模式優先使用。
/// oledBlack 只會影響系統深色或固定深色，不會覆蓋自訂色票。
@immutable
class AppThemeOptions {
  const AppThemeOptions({
    this.mode = AppThemeMode.system,
    this.oledBlack = false,
    this.customPalette,
  });

  final AppThemeMode mode;
  final bool oledBlack;
  final AppPalette? customPalette;

  AppThemeOptions copyWith({
    AppThemeMode? mode,
    bool? oledBlack,
    AppPalette? customPalette,
  }) {
    return AppThemeOptions(
      mode: mode ?? this.mode,
      oledBlack: oledBlack ?? this.oledBlack,
      customPalette: customPalette ?? this.customPalette,
    );
  }
}

/// 將使用者設定解析成最後實際使用的色票。
class AppThemeResolver {
  AppThemeResolver._();

  static AppPalette resolve({
    required AppThemeOptions options,
    required Brightness systemBrightness,
  }) {
    final AppPalette basePalette = switch (options.mode) {
      AppThemeMode.system => _paletteFromSystemBrightness(systemBrightness),
      AppThemeMode.light => AppPalettes.light,
      AppThemeMode.dark => AppPalettes.dark,
      AppThemeMode.custom =>
        options.customPalette ?? _paletteFromSystemBrightness(systemBrightness),
    };

    if (!options.oledBlack || options.mode == AppThemeMode.custom) {
      return basePalette;
    }

    return AppOledPaletteOverride.apply(basePalette);
  }

  static AppPalette _paletteFromSystemBrightness(Brightness systemBrightness) {
    return systemBrightness == Brightness.dark
        ? AppPalettes.dark
        : AppPalettes.light;
  }
}

/// ThemeData 建立器。
///
/// 這裡只接收已解析完成的 AppPalette，不負責判斷主題模式。
class AppTheme {
  AppTheme._();

  static const fontFamily = 'NotoSansCjkTcVariable';
  static const minimumFontWeight = FontWeight.w400;

  static ThemeData fromOptions({
    required AppThemeOptions options,
    required Brightness systemBrightness,
  }) {
    final palette = AppThemeResolver.resolve(
      options: options,
      systemBrightness: systemBrightness,
    );

    return fromPalette(palette);
  }

  static ThemeData fromPalette(AppPalette palette) {
    final scheme = _colorSchemeFromPalette(palette);

    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.surface,
      appBarTheme: _appBarTheme(palette),
      cardTheme: _cardTheme(palette),
      textTheme: _textTheme(palette),
      inputDecorationTheme: _inputDecorationTheme(palette),
      textButtonTheme: _textButtonTheme(palette),
      filledButtonTheme: _filledButtonTheme(palette),
      elevatedButtonTheme: _elevatedButtonTheme(palette),
      outlinedButtonTheme: _outlinedButtonTheme(palette),
      iconTheme: _iconTheme(palette),
      dividerTheme: _dividerTheme(palette),
      switchTheme: _switchTheme(palette),
      checkboxTheme: _checkboxTheme(palette),
      radioTheme: _radioTheme(palette),
      listTileTheme: _listTileTheme(palette),
      dialogTheme: _dialogTheme(palette),
      bottomSheetTheme: _bottomSheetTheme(palette),
      popupMenuTheme: _popupMenuTheme(palette),
      tooltipTheme: _tooltipTheme(palette),
      navigationBarTheme: _navigationBarTheme(palette),
      snackBarTheme: _snackBarTheme(palette),
    );
  }

  static SnackBarThemeData _snackBarTheme(AppPalette palette) {
    return SnackBarThemeData(
      backgroundColor: palette.snackbarBackground,
      contentTextStyle: _appTextStyle(color: palette.onSurface),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  static AppBarTheme _appBarTheme(AppPalette palette) {
    return AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: _appTextStyle(
        color: palette.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static CardThemeData _cardTheme(AppPalette palette) {
    return CardThemeData(
      color: palette.surfaceContainer,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapeTokens.defaultCardRadius),
      ),
    );
  }

  static TextTheme _textTheme(AppPalette palette) {
    return TextTheme(
      displayLarge: _appTextStyle(color: palette.onSurface),
      displayMedium: _appTextStyle(color: palette.onSurface),
      displaySmall: _appTextStyle(color: palette.onSurface),
      headlineLarge: _appTextStyle(color: palette.onSurface),
      headlineMedium: _appTextStyle(color: palette.onSurface),
      headlineSmall: _appTextStyle(color: palette.onSurface),
      bodyLarge: _appTextStyle(color: palette.onSurface),
      bodyMedium: _appTextStyle(color: palette.onSurface),
      bodySmall: _appTextStyle(color: palette.onSurfaceVariant),
      titleLarge: _appTextStyle(color: palette.onSurface),
      titleMedium: _appTextStyle(color: palette.onSurface),
      titleSmall: _appTextStyle(color: palette.onSurface),
      labelLarge: _appTextStyle(color: palette.onSurface),
      labelMedium: _appTextStyle(color: palette.onSurfaceVariant),
      labelSmall: _appTextStyle(color: palette.onSurfaceVariant),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(AppPalette palette) {
    final inputRadius = BorderRadius.circular(AppShapeTokens.inputRadius);
    final errorColor = palette.brightness == Brightness.dark
        ? const Color(0xFFFFB4AB)
        : const Color(0xFFBA1A1A);
    return InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceContainer,
      labelStyle: _appTextStyle(color: palette.onSurfaceVariant),
      hintStyle: _appTextStyle(color: palette.onSurfaceVariant),
      helperStyle: _appTextStyle(color: palette.onSurfaceVariant),
      prefixIconColor: palette.onSurfaceVariant,
      suffixIconColor: palette.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: palette.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: palette.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: palette.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: inputRadius,
        borderSide: BorderSide(color: errorColor, width: 2),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(AppPalette palette) {
    return TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(palette.onSurfaceVariant),
        textStyle: WidgetStatePropertyAll(_appTextStyle()),
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme(AppPalette palette) {
    return FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(palette.primary),
        foregroundColor: WidgetStatePropertyAll(palette.onPrimary),
        textStyle: WidgetStatePropertyAll(_appTextStyle()),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(AppPalette palette) {
    return ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(palette.primary),
        foregroundColor: WidgetStatePropertyAll(palette.onPrimary),
        elevation: const WidgetStatePropertyAll(0),
        textStyle: WidgetStatePropertyAll(_appTextStyle()),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(AppPalette palette) {
    return OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(palette.primary),
        side: WidgetStatePropertyAll(BorderSide(color: palette.outline)),
        textStyle: WidgetStatePropertyAll(_appTextStyle()),
      ),
    );
  }

  static IconThemeData _iconTheme(AppPalette palette) {
    return IconThemeData(color: palette.onSurface);
  }

  static DividerThemeData _dividerTheme(AppPalette palette) {
    return DividerThemeData(color: palette.outline, thickness: 1, space: 1);
  }

  static SwitchThemeData _switchTheme(AppPalette palette) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return palette.primary;
        }

        return palette.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return palette.primary.withValues(alpha: 0.35);
        }

        return palette.surfaceContainer;
      }),
    );
  }

  static CheckboxThemeData _checkboxTheme(AppPalette palette) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return palette.primary;
        }

        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(palette.onPrimary),
      side: BorderSide(color: palette.outline),
    );
  }

  static RadioThemeData _radioTheme(AppPalette palette) {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return palette.primary;
        }

        return palette.onSurfaceVariant;
      }),
    );
  }

  static ListTileThemeData _listTileTheme(AppPalette palette) {
    return ListTileThemeData(
      textColor: palette.onSurface,
      iconColor: palette.onSurface,
      titleTextStyle: _appTextStyle(color: palette.onSurface),
      subtitleTextStyle: _appTextStyle(color: palette.onSurfaceVariant),
    );
  }

  static DialogThemeData _dialogTheme(AppPalette palette) {
    return DialogThemeData(
      backgroundColor: palette.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapeTokens.dialogRadius),
      ),
      titleTextStyle: _appTextStyle(
        color: palette.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      contentTextStyle: _appTextStyle(color: palette.onSurface, fontSize: 16),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(AppPalette palette) {
    return BottomSheetThemeData(
      backgroundColor: palette.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppShapeTokens.dialogRadius),
        ),
      ),
    );
  }

  static PopupMenuThemeData _popupMenuTheme(AppPalette palette) {
    return PopupMenuThemeData(
      color: palette.surfaceContainer,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapeTokens.popupMenuRadius),
      ),
    );
  }

  static TooltipThemeData _tooltipTheme(AppPalette palette) {
    return TooltipThemeData(
      triggerMode: TooltipTriggerMode.tap,
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 4),
      exitDuration: const Duration(milliseconds: 100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: palette.onSurface,
        borderRadius: BorderRadius.circular(AppShapeTokens.defaultCardRadius),
      ),
      textStyle: _appTextStyle(color: palette.surface, fontSize: 13),
    );
  }

  static NavigationBarThemeData _navigationBarTheme(AppPalette palette) {
    return NavigationBarThemeData(
      backgroundColor: palette.surface,
      indicatorColor: palette.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: palette.primary);
        }

        return IconThemeData(color: palette.onSurfaceVariant);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _appTextStyle(color: palette.primary);
        }

        return _appTextStyle(color: palette.onSurfaceVariant);
      }),
    );
  }

  static TextStyle _appTextStyle({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight ?? minimumFontWeight,
      fontFamily: fontFamily,
    );
  }

  static ColorScheme _colorSchemeFromPalette(AppPalette palette) {
    final isDark = palette.brightness == Brightness.dark;

    return ColorScheme(
      brightness: palette.brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      surface: palette.surface,
      onSurface: palette.onSurface,
      onSurfaceVariant: palette.onSurfaceVariant,
      outline: palette.outline,
      outlineVariant: palette.outline,
      secondary: palette.primary,
      onSecondary: palette.onPrimary,
      tertiary: palette.primary,
      onTertiary: palette.onPrimary,
      surfaceContainerLowest: palette.surface,
      surfaceContainerLow: palette.surfaceContainer,
      surfaceContainer: palette.surfaceContainer,
      surfaceContainerHigh: palette.surfaceContainer,
      surfaceContainerHighest: palette.surfaceContainer,
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: isDark
          ? const Color(0xFF93000A)
          : const Color(0xFFFFDAD6),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
    );
  }
}
