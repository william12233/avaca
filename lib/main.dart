import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config.dart';
import 'core/database.dart';
import 'views/add_view.dart';
import 'views/detail_view.dart';
import 'views/home_view.dart';
import 'views/settings_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  await db.init();

  runApp(AvacaApp(db: db));
}

class AvacaApp extends StatefulWidget {
  const AvacaApp({
    super.key,
    required this.db,
  });

  final AppDatabase db;

  @override
  State<AvacaApp> createState() => _AvacaAppState();
}

class _AvacaAppState extends State<AvacaApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isPureBlack = false;
  Map<String, Color>? _customColors;
  Locale? _locale;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restoreThemeState();
  }

  // 啟動時讀取上次儲存的主題與語言設定。
  Future<void> _restoreThemeState() async {
    final prefs = await SharedPreferences.getInstance();
    final modeString = prefs.getString('theme_mode') ?? 'system';
    final pureBlack = prefs.getBool('pure_black') ?? false;
    final localeString = prefs.getString('app_locale') ?? 'system';

    final rawCustom = await widget.db.getSetting('custom_theme');

    Map<String, Color>? customColors;

    if (rawCustom != null) {
      final decoded = jsonDecode(rawCustom) as Map<String, dynamic>;

      customColors = decoded.map(
        (key, value) => MapEntry(key, Color(value as int)),
      );
    }

    setState(() {
      _themeMode = _themeModeFromString(modeString);
      _isPureBlack = pureBlack;
      _customColors = modeString == 'custom' ? customColors : null;
      _locale = _localeFromString(localeString);
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox.shrink();
    }

    final useCustomTheme = _customColors != null;

    final lightTheme = _buildThemeData(
      mode: useCustomTheme ? AppThemeMode.custom : AppThemeMode.light,
      brightness: Brightness.light,
      oledBlack: false,
      fallbackPalette: AppPalettes.light,
    );

    final darkTheme = _buildThemeData(
      mode: useCustomTheme ? AppThemeMode.custom : AppThemeMode.dark,
      brightness: Brightness.dark,
      oledBlack: _isPureBlack,
      fallbackPalette: AppPalettes.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      themeMode: _themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: _onGenerateRoute,
    );
  }

  // 將儲存的文字設定轉回 Flutter 使用的主題模式。
  ThemeMode _themeModeFromString(String modeString) {
    return switch (modeString) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'custom' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  // 將儲存的語言設定轉回 Flutter 使用的 Locale。
  Locale? _localeFromString(String localeString) {
    return switch (localeString) {
      'zh_TW' => const Locale('zh', 'TW'),
      'en' => const Locale('en'),
      _ => null,
    };
  }

  // 依照目前主題狀態建立亮色或暗色 ThemeData。
  ThemeData _buildThemeData({
    required AppThemeMode mode,
    required Brightness brightness,
    required bool oledBlack,
    required AppPalette fallbackPalette,
  }) {
    return AppTheme.fromOptions(
      options: AppThemeOptions(
        mode: mode,
        oledBlack: oledBlack,
        customPalette: _buildCustomPalette(
          customColors: _customColors,
          fallback: fallbackPalette,
          brightness: brightness,
        ),
      ),
      systemBrightness: brightness,
    );
  }

  // 將自訂色票補齊成 AppPalette，缺少的顏色會沿用預設色票。
  AppPalette? _buildCustomPalette({
    required Map<String, Color>? customColors,
    required AppPalette fallback,
    required Brightness brightness,
  }) {
    if (customColors == null) {
      return null;
    }

    return AppPalette(
      brightness: brightness,
      surface: customColors['surface'] ?? fallback.surface,
      surfaceContainer:
          customColors['surfaceContainer'] ?? fallback.surfaceContainer,
      onSurface: customColors['onSurface'] ?? fallback.onSurface,
      onSurfaceVariant:
          customColors['onSurfaceVariant'] ?? fallback.onSurfaceVariant,
      primary: customColors['primary'] ?? fallback.primary,
      onPrimary: customColors['onPrimary'] ?? fallback.onPrimary,
      outline: customColors['outline'] ?? fallback.outline,
    );
  }

  Route<void> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';

    if (name == '/') {
      return _page(HomeView(db: widget.db));
    }

    if (name == '/add') {
      return _page(AddView(db: widget.db));
    }

    if (name == '/settings') {
      return _page(
        SettingsView(
          db: widget.db,
          onThemeChanged: (mode, pureBlack, custom) {
            setState(() {
              _themeMode = mode;
              _isPureBlack = pureBlack;
              _customColors = custom;
            });
          },
          onLocaleChanged: (locale) {
            setState(() {
              _locale = locale;
            });
          },
        ),
      );
    }

    if (name.startsWith('/detail/')) {
      final id = int.tryParse(name.split('/').last);

      if (id != null) {
        return _page(DetailView(db: widget.db, actressId: id));
      }
    }

    return _page(HomeView(db: widget.db));
  }

  MaterialPageRoute<void> _page(Widget child) {
    return MaterialPageRoute(builder: (_) => child);
  }
}