import 'package:flutter/material.dart';

/// 使用者可選擇的主題模式。
///
/// OLED 純黑不是獨立的 ThemeMode，而是在解析色票後套用的背景覆蓋規則。
enum AppThemeMode {
  system,
  light,
  dark,
  custom,
}

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

  AppPalette copyWith({
    Brightness? brightness,
    Color? surface,
    Color? surfaceContainer,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? primary,
    Color? onPrimary,
    Color? outline,
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
/// oledBlack 只會在最後解析結果為深色時影響背景色票。
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

    if (!options.oledBlack) {
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
      navigationBarTheme: _navigationBarTheme(palette),
    );
  }

  static AppBarTheme _appBarTheme(AppPalette palette) {
    return AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    );
  }

  static CardThemeData _cardTheme(AppPalette palette) {
    return CardThemeData(
      color: palette.surfaceContainer,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  static TextTheme _textTheme(AppPalette palette) {
    return TextTheme(
      bodyLarge: TextStyle(color: palette.onSurface),
      bodyMedium: TextStyle(color: palette.onSurface),
      bodySmall: TextStyle(color: palette.onSurfaceVariant),
      titleLarge: TextStyle(color: palette.onSurface),
      titleMedium: TextStyle(color: palette.onSurface),
      titleSmall: TextStyle(color: palette.onSurface),
      labelLarge: TextStyle(color: palette.onSurface),
      labelMedium: TextStyle(color: palette.onSurfaceVariant),
      labelSmall: TextStyle(color: palette.onSurfaceVariant),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(AppPalette palette) {
    return InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceContainer,
      labelStyle: TextStyle(color: palette.onSurfaceVariant),
      hintStyle: TextStyle(color: palette.onSurfaceVariant),
      helperStyle: TextStyle(color: palette.onSurfaceVariant),
      prefixIconColor: palette.onSurfaceVariant,
      suffixIconColor: palette.onSurfaceVariant,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: palette.primary,
          width: 2,
        ),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(AppPalette palette) {
    return TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(palette.primary),
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme(AppPalette palette) {
    return FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(palette.primary),
        foregroundColor: WidgetStatePropertyAll(palette.onPrimary),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(AppPalette palette) {
    return ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(palette.primary),
        foregroundColor: WidgetStatePropertyAll(palette.onPrimary),
        elevation: const WidgetStatePropertyAll(0),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(AppPalette palette) {
    return OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(palette.primary),
        side: WidgetStatePropertyAll(
          BorderSide(color: palette.outline),
        ),
      ),
    );
  }

  static IconThemeData _iconTheme(AppPalette palette) {
    return IconThemeData(
      color: palette.onSurface,
    );
  }

  static DividerThemeData _dividerTheme(AppPalette palette) {
    return DividerThemeData(
      color: palette.outline,
      thickness: 1,
      space: 1,
    );
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
      titleTextStyle: TextStyle(color: palette.onSurface),
      subtitleTextStyle: TextStyle(color: palette.onSurfaceVariant),
    );
  }

  static DialogThemeData _dialogTheme(AppPalette palette) {
    return DialogThemeData(
      backgroundColor: palette.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: palette.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        color: palette.onSurface,
        fontSize: 16,
      ),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(AppPalette palette) {
    return BottomSheetThemeData(
      backgroundColor: palette.surfaceContainer,
      surfaceTintColor: Colors.transparent,
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
          return TextStyle(color: palette.primary);
        }

        return TextStyle(color: palette.onSurfaceVariant);
      }),
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