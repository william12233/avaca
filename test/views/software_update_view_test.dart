import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:avaca/controllers/software_update_controller.dart';
import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/software_update_models.dart';
import 'package:avaca/services/app_version_provider.dart';
import 'package:avaca/services/software_update_installer.dart';
import 'package:avaca/services/software_update_service.dart';
import 'package:avaca/views/settings_view.dart';

class _FakeDatabase extends AppDatabase {
  final Map<String, String> settings = {};

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }
}

class _FakeVersionProvider implements AppVersionProvider {
  @override
  Future<AppVersionInfo> load() async => const AppVersionInfo(
    version: '0.8.1',
    buildNumber: '2026',
    platform: SoftwareUpdatePlatform.android,
    architecture: 'arm64-v8a',
  );
}

class _FakeInstaller implements SoftwareUpdateInstaller {
  bool called = false;

  @override
  Future<SoftwareInstallResult> install(DownloadedUpdate update) async {
    called = true;
    return const SoftwareInstallResult(started: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'system',
      'pure_black': false,
      'app_locale': 'en',
    });
  });

  testWidgets('Other contains Software update with the requested controls', (
    tester,
  ) async {
    final controller = await _buildController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_SettingsHarness(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Other'), findsOneWidget);
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(find.text('Software update'), findsOneWidget);
    expect(find.text('Scrape sources'), findsNothing);

    await tester.tap(find.text('Software update'));
    await tester.pumpAndSettle();

    expect(find.text('Current version'), findsOneWidget);
    expect(find.text('0.8.1'), findsOneWidget);
    expect(find.text('0.8.1+2026'), findsNothing);
    expect(find.text('Latest version'), findsOneWidget);
    expect(find.text('Check for updates automatically'), findsOneWidget);
    expect(find.byKey(const ValueKey('software-update-check')), findsOneWidget);
  });

  testWidgets(
    'manual check opens a dialog whose Update now action starts install',
    (tester) async {
      final installer = _FakeInstaller();
      final controller = await _buildController(installer: installer);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_SettingsHarness(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Software update'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('software-update-check')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Update available'), findsNWidgets(2));
      expect(find.text('Current version: 0.8.1'), findsOneWidget);
      expect(find.text('Current version: 0.8.1+2026'), findsNothing);
      expect(find.byKey(const ValueKey('software-update-now')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('software-update-now')));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20 && !installer.called; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(
        installer.called,
        isTrue,
        reason: 'status=${controller.status}, error=${controller.error}',
      );
    },
  );
}

Future<SoftwareUpdateController> _buildController({
  _FakeInstaller? installer,
}) async {
  final release = const SoftwareRelease(
    tagName: 'v0.8.2',
    version: SemanticVersion(0, 8, 2),
    assets: <ReleaseAsset>[],
  );
  final asset = ReleaseAsset(
    name: 'avaca-0.8.2-arm64-v8a.apk',
    downloadUrl: Uri.parse('https://github.com/william12233/avaca/update.apk'),
    size: 1,
    digest: 'sha256:${sha256.convert([0])}',
  );
  final download = DownloadedUpdate(
    file: File('update.apk'),
    stagingDirectory: Directory.current,
    release: release,
    asset: asset,
  );
  final client = MockClient((request) async {
    if (request.url.path.endsWith('.apk')) {
      return http.Response.bytes([0], 200);
    }
    return http.Response(
      jsonEncode({
        'tag_name': 'v0.8.2',
        'draft': false,
        'prerelease': false,
        'assets': [
          {
            'name': 'avaca-0.8.2-arm64-v8a.apk',
            'browser_download_url':
                'https://github.com/william12233/avaca/releases/download/v0.8.2/avaca-0.8.2-arm64-v8a.apk',
            'size': 1,
            'digest': 'sha256:${sha256.convert([0])}',
          },
        ],
      }),
      200,
    );
  });
  final service = SoftwareUpdateService(
    client: client,
    versionProvider: _FakeVersionProvider(),
    platformOverride: SoftwareUpdatePlatform.android,
    architectureOverride: 'arm64-v8a',
    downloadOverride: (result, {onProgress}) async {
      onProgress?.call(1, 1);
      return download;
    },
  );
  final controller = SoftwareUpdateController(
    service: service,
    installer: installer ?? _FakeInstaller(),
  );
  await controller.initialize();
  return controller;
}

class _SettingsHarness extends StatefulWidget {
  const _SettingsHarness({required this.controller});

  final SoftwareUpdateController controller;

  @override
  State<_SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<_SettingsHarness> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale = const Locale('en');
  final _database = _FakeDatabase();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.fromPalette(AppPalettes.light),
      darkTheme: AppTheme.fromPalette(AppPalettes.dark),
      themeMode: _themeMode,
      home: SettingsView(
        db: _database,
        softwareUpdateController: widget.controller,
        onThemeChanged: (themeMode, _, _) {
          if (_themeMode != themeMode) setState(() => _themeMode = themeMode);
        },
        onLocaleChanged: (locale) {
          if (_locale != locale) setState(() => _locale = locale);
        },
      ),
    );
  }
}
