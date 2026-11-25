import 'dart:async';
import 'dart:convert';

import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_providers.dart';
import 'controllers/data_transfer_controller.dart';
import 'controllers/settings_controller.dart';
import 'controllers/software_update_controller.dart';
import 'core/app_appearance.dart';
import 'core/app_motion.dart';
import 'core/config.dart';
import 'core/database.dart';
import 'core/keyboard_dismiss_navigator_observer.dart';
import 'core/platform_adapter.dart';
import 'core/resource_policy.dart';
import 'services/scrape_background_controller.dart';
import 'services/scrape_job_coordinator.dart';
import 'services/update_cache_service.dart';
import 'services/update_startup_marker.dart';
import 'views/add_view.dart';
import 'views/data_health_view.dart';
import 'views/detail_view.dart';
import 'views/home_view.dart';
import 'views/scrape_job_detail_view.dart';
import 'views/scrape_jobs_view.dart';
import 'views/settings_view.dart';
import 'views/software_update_view.dart';
import 'views/works_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = ResourcePolicy.imageCacheEntries;
  imageCache.maximumSizeBytes = ResourcePolicy.imageCacheBytes;

  final db = AppDatabase();
  await db.init();
  await markWindowsStartupSuccess();

  runApp(AvacaApp(db: db, enableAutomaticUpdateCheck: true));
}

class AvacaApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (softwareUpdateController != null)
          softwareUpdateControllerProvider.overrideWithValue(
            softwareUpdateController!,
          ),
      ],
      child: _AvacaAppContent(
        db: db,
        softwareUpdateController: softwareUpdateController,
        enableAutomaticUpdateCheck: enableAutomaticUpdateCheck,
      ),
    );
  }
}

class _AvacaAppContent extends ConsumerStatefulWidget {
  const _AvacaAppContent({
    required this.db,
    required this.softwareUpdateController,
    required this.enableAutomaticUpdateCheck,
  });

  final AppDatabase db;
  final SoftwareUpdateController? softwareUpdateController;
  final bool enableAutomaticUpdateCheck;

  @override
  ConsumerState<_AvacaAppContent> createState() => _AvacaAppState();
}

class _AvacaAppState extends ConsumerState<_AvacaAppContent> {
  final KeyboardDismissNavigatorObserver _keyboardObserver =
      KeyboardDismissNavigatorObserver();
  ThemeMode _themeMode = ThemeMode.system;
  bool _isPureBlack = false;
  Map<String, Color>? _customColors;
  AppAppearance _appearance = defaultAppearance;
  Locale? _locale;
  bool _ready = false;
  late final SoftwareUpdateController _softwareUpdateController;
  late final SettingsController _settingsController;
  late final DataTransferController _dataTransferController;
  late final ScrapeJobCoordinator _scrapeJobCoordinator;
  late final ScrapeBackgroundController _scrapeBackgroundController;
  late final UpdateCacheService _updateCacheService;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _automaticUpdateStarted = false;
  String? _pendingScrapeNotificationJobId;
  String? _lastScrapeNotificationJobId;
  DateTime? _lastScrapeNotificationTapAt;

  @override
  void initState() {
    super.initState();
    _softwareUpdateController =
        widget.softwareUpdateController ??
        ref.read(softwareUpdateControllerProvider);
    _settingsController = ref.read(settingsControllerProvider);
    _settingsController.addListener(_syncAppearance);
    _dataTransferController = ref.read(dataTransferControllerProvider);
    _scrapeJobCoordinator = ref.read(scrapeJobCoordinatorProvider);
    _scrapeBackgroundController = ScrapeBackgroundController(
      coordinator: _scrapeJobCoordinator,
      onNotificationTap: _handleScrapeNotificationTap,
    );
    _updateCacheService = ref.read(updateCacheServiceProvider);
    unawaited(_initializeScrapeCoordinator());
    unawaited(_restoreThemeState());
  }

  Future<void> _initializeScrapeCoordinator() async {
    var initialized = false;
    try {
      await _scrapeJobCoordinator.initialize();
      initialized = true;
    } on Object catch (error) {
      debugPrint('Scrape job coordinator initialization failed: $error');
    }
    if (mounted && initialized && PlatformAdapter.isAndroid) {
      _scrapeBackgroundController.attach();
    }
  }

  Future<void> _restoreThemeState() async {
    String? rawCustom;
    try {
      await _settingsController.loadFromPrefs();
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
      _themeMode = _settingsController.themeMode;
      _isPureBlack = _settingsController.isPureBlack;
      _customColors = _settingsController.isCustomTheme ? customColors : null;
      _locale = _settingsController.appLocale;
      _appearance = _settingsController.appearance;
      _ready = true;
    });
    _scrapeBackgroundController.setLocale(_locale);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingScrapeNotification();
    });

    if (widget.enableAutomaticUpdateCheck) {
      unawaited(_initializeAndCheckForUpdates());
    }
  }

  void _syncAppearance() {
    final appearance = _settingsController.appearance;
    if (_ready && appearance != _appearance) {
      setState(() => _appearance = appearance);
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
    final systemReducedMotion = MediaQuery.disableAnimationsOf(context);
    final motionEnabled = _appearance.motionEnabled && !systemReducedMotion;

    final lightTheme = _buildThemeData(
      mode: useCustomTheme ? AppThemeMode.custom : AppThemeMode.light,
      brightness: Brightness.light,
      oledBlack: false,
      fallbackPalette: AppPalettes.light,
      motionEnabled: motionEnabled,
    );

    final darkTheme = _buildThemeData(
      mode: useCustomTheme ? AppThemeMode.custom : AppThemeMode.dark,
      brightness: Brightness.dark,
      oledBlack: _isPureBlack,
      fallbackPalette: AppPalettes.dark,
      motionEnabled: motionEnabled,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      locale: _locale,
      themeMode: _appearance.visualTheme == AppVisualTheme.frostedGlass
          ? ThemeMode.dark
          : _themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeAnimationStyle: motionEnabled
          ? const AnimationStyle(
              duration: AppMotion.themeDuration,
              curve: Curves.easeOutCubic,
            )
          : AnimationStyle.noAnimation,
      builder: (context, child) {
        final viewport = MediaQuery.of(context);
        return AppMotion(
          systemReduced: systemReducedMotion,
          child: MediaQuery(
            data: viewport.copyWith(disableAnimations: !motionEnabled),
            child: child!,
          ),
        );
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [_keyboardObserver],
      onGenerateRoute: _onGenerateRoute,
    );
  }

  ThemeData _buildThemeData({
    required AppThemeMode mode,
    required Brightness brightness,
    required bool oledBlack,
    required AppPalette fallbackPalette,
    required bool motionEnabled,
  }) {
    final colors = _customColors;
    final theme = AppTheme.fromOptions(
      options: AppThemeOptions(
        mode: mode,
        oledBlack: oledBlack,
        customPalette: colors == null
            ? null
            : AppPalettes.custom(colors, base: fallbackPalette),
      ),
      systemBrightness: brightness,
      visualTheme: _appearance.visualTheme,
    );
    return motionEnabled
        ? theme
        : theme.copyWith(
            pageTransitionsTheme: AppMotion.instantPageTransitions,
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
          transferController: _dataTransferController,
          softwareUpdateController: _softwareUpdateController,
          settingsController: _settingsController,
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
            _scrapeBackgroundController.setLocale(locale);
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

  void _handleScrapeNotificationTap(String jobId) {
    final normalized = jobId.trim();
    if (normalized.isEmpty) return;
    final now = DateTime.now();
    if (_lastScrapeNotificationJobId == normalized &&
        _lastScrapeNotificationTapAt != null &&
        now.difference(_lastScrapeNotificationTapAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastScrapeNotificationJobId = normalized;
    _lastScrapeNotificationTapAt = now;
    _pendingScrapeNotificationJobId = normalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingScrapeNotification();
    });
  }

  void _openPendingScrapeNotification() {
    if (!mounted || !_ready) return;
    final jobId = _pendingScrapeNotificationJobId;
    final navigator = _navigatorKey.currentState;
    if (jobId == null) return;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPendingScrapeNotification();
      });
      return;
    }
    _pendingScrapeNotificationJobId = null;
    unawaited(navigator.pushNamed('/scrape-job/$jobId'));
  }

  @override
  void dispose() {
    _settingsController.removeListener(_syncAppearance);
    _scrapeBackgroundController.dispose();
    super.dispose();
  }
}
