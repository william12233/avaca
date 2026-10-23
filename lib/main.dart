import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config.dart';
import 'core/database.dart';
import 'core/keyboard_dismiss_navigator_observer.dart';
import 'controllers/software_update_controller.dart';
import 'services/update_cache_service.dart';
import 'services/update_startup_marker.dart';
import 'services/scrape_job_coordinator.dart';
import 'views/add_view.dart';
import 'views/data_health_view.dart';
import 'views/detail_view.dart';
import 'views/home_view.dart';
import 'views/settings_view.dart';
import 'views/software_update_view.dart';
import 'views/works_view.dart';
import 'views/scrape_job_detail_view.dart';
import 'views/scrape_jobs_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  await db.init();
  await markWindowsStartupSuccess();

  runApp(AvacaApp(db: db, enableAutomaticUpdateCheck: true));
}

class AvacaApp extends StatefulWidget {
  const AvacaApp({
    super.key,
    required this.db,
    this.softwareUpdateController,
    this.enableAutomaticUpdateCheck = false,
  });

  final AppDatabase db;
  final SoftwareUpdateController? softwareUpdateController;
  final bool enableAutomaticUpdateCheck;

  @override
  State<AvacaApp> createState() => _AvacaAppState();
}

class _AvacaAppState extends State<AvacaApp> {
  final KeyboardDismissNavigatorObserver _keyboardObserver =
      KeyboardDismissNavigatorObserver();
  ThemeMode _themeMode = ThemeMode.system;
  bool _isPureBlack = false;
  Map<String, Color>? _customColors;
  Locale? _locale;
  bool _ready = false;
  late final SoftwareUpdateController _softwareUpdateController;
  late final bool _ownsSoftwareUpdateController;
  late final ScrapeJobCoordinator _scrapeJobCoordinator;
  final UpdateCacheService _updateCacheService = UpdateCacheService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _automaticUpdateStarted = false;

  @override
  void initState() {
    super.initState();
    _ownsSoftwareUpdateController = widget.softwareUpdateController == null;
    _softwareUpdateController =
        widget.softwareUpdateController ??
        SoftwareUpdateController.forApp(db: widget.db);
    _scrapeJobCoordinator = ScrapeJobCoordinator(db: widget.db);
    unawaited(
      _scrapeJobCoordinator.initialize().catchError((Object error) {
        debugPrint('Scrape job coordinator initialization failed: $error');
      }),
    );
    unawaited(_restoreThemeState());
  }

  @override
  void dispose() {
    if (_ownsSoftwareUpdateController) _softwareUpdateController.dispose();
    _scrapeJobCoordinator.rulesRepository.close();
    _scrapeJobCoordinator.dispose();
    super.dispose();
  }

  // 啟動時讀取上次儲存的主題與語言設定。
  Future<void> _restoreThemeState() async {
    var modeString = 'system';
    var pureBlack = false;
    var localeString = 'system';
    String? rawCustom;
    try {
      final prefs = await SharedPreferences.getInstance();
      modeString = prefs.getString('theme_mode') ?? 'system';
      pureBlack = prefs.getBool('pure_black') ?? false;
      localeString = prefs.getString('app_locale') ?? 'system';
      rawCustom = await widget.db.getSetting('custom_theme');
    } on Object catch (error) {
      debugPrint('Theme state restore failed: $error');
    }

    Map<String, Color>? customColors;

    if (rawCustom != null) {
      try {
        final decoded = jsonDecode(rawCustom);
        if (decoded is Map) {
          customColors = <String, Color>{};
          for (final entry in decoded.entries) {
            if (entry.key is String && entry.value is int) {
              customColors[entry.key as String] = Color(entry.value as int);
            }
          }
        }
      } on FormatException {
        customColors = null;
      }
    }

    if (!mounted) return;
    setState(() {
      _themeMode = _themeModeFromString(modeString);
      _isPureBlack = pureBlack;
      _customColors = modeString == 'custom' ? customColors : null;
      _locale = _localeFromString(localeString);
      _ready = true;
    });

    if (widget.enableAutomaticUpdateCheck) {
      unawaited(_initializeAndCheckForUpdates());
    }
  }

  Future<void> _initializeAndCheckForUpdates() async {
    await _softwareUpdateController.initialize();
    final current = _softwareUpdateController.currentVersion;
    if (current != null) {
      try {
        await _updateCacheService.clearAfterVersionChange(current.version);
      } catch (_) {
        // Cache eviction is best-effort and must not block startup updates.
      }
    }
    if (!mounted || !_softwareUpdateController.autoCheckUpdates) return;
    if (_automaticUpdateStarted) return;
    _automaticUpdateStarted = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final result = await _softwareUpdateController.check(automatic: true);
      if (!mounted || !result.hasUpdate) return;
      final overlayContext = _navigatorKey.currentState?.overlay?.context;
      if (overlayContext == null || !overlayContext.mounted) return;
      await showSoftwareUpdateDialog(
        overlayContext,
        _softwareUpdateController,
        result,
        automatic: true,
      );
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
      navigatorKey: _navigatorKey,
      locale: _locale,
      themeMode: _themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [_keyboardObserver],
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
      'zh_CN' => const Locale('zh', 'CN'),
      'ja_JP' => const Locale('ja', 'JP'),
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
      snackbarBackground:
          customColors['snackbarBackground'] ?? fallback.snackbarBackground,
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
          scrapeJobCoordinator: _scrapeJobCoordinator,
          softwareUpdateController: _softwareUpdateController,
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

    if (name.startsWith('/works/')) {
      final id = int.tryParse(name.split('/').last);

      if (id != null) {
        return _page(
          WorksView(
            db: widget.db,
            actressId: id,
            scrapeJobCoordinator: _scrapeJobCoordinator,
          ),
        );
      }
    }

    if (name == '/scrape-jobs') {
      return _page(
        ScrapeJobsView(db: widget.db, coordinator: _scrapeJobCoordinator),
      );
    }

    if (name.startsWith('/scrape-job/')) {
      final id = name.substring('/scrape-job/'.length);
      if (id.isNotEmpty) {
        return _page(
          ScrapeJobDetailView(
            db: widget.db,
            coordinator: _scrapeJobCoordinator,
            jobId: id,
          ),
        );
      }
    }

    if (name == '/data-health') {
      return _page(DataHealthView(db: widget.db));
    }

    return _page(HomeView(db: widget.db));
  }

  MaterialPageRoute<void> _page(Widget child) {
    return MaterialPageRoute(builder: (_) => child);
  }
}
