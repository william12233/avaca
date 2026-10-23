import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/prefix_route_repository.dart';
import 'package:avaca/services/javbus/javbus_verification.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:avaca/views/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'system',
      'pure_black': true,
      'app_locale': 'en',
    });
  });

  testWidgets('settings root shows categories but hides their details', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('Theme & Colors'), findsOneWidget);
    expect(find.text('Interface'), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    _expectBorderlessCategoryCard(tester, 'Theme & Colors');
    _expectBorderlessCategoryCard(tester, 'Interface');
    expect(find.text('Theme Mode'), findsNothing);
    expect(find.text('Language'), findsNothing);
    expect(find.text('Pure Black AMOLED'), findsNothing);
  });

  testWidgets('settings back button aligns with the app bar title', (
    tester,
  ) async {
    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();

    final backRect = tester.getRect(find.byIcon(Icons.arrow_back));
    final titleRect = tester.getRect(find.text('Theme & Colors'));
    expect(backRect.center.dy, closeTo(titleRect.center.dy, 0.5));
  });

  testWidgets('about expands GitHub and feedback links inline', (tester) async {
    final openedUrls = <Uri>[];

    await _pumpSettings(
      tester,
      externalUrlLauncher: (uri) async {
        openedUrls.add(uri);
        return true;
      },
    );

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Other'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'About'), findsNothing);
    expect(find.text('github'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));

    await tester.tap(find.text('github'));
    await tester.pump();
    await tester.tap(find.text('Feedback'));
    await tester.pump();

    expect(openedUrls, [
      Uri.parse('https://github.com/william12233/avaca'),
      Uri.parse('https://github.com/william12233/avaca/issues'),
    ]);
  });

  testWidgets('other expands Prefix route rules inline', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();

    expect(find.text('Prefix route rules'), findsOneWidget);
    await tester.tap(find.text('Prefix route rules'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Other'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Prefix route rules'), findsNothing);
    expect(find.text('0 learned Prefix rules'), findsOneWidget);
    expect(find.byKey(const ValueKey('prefix-route-import')), findsOneWidget);
    expect(find.byKey(const ValueKey('prefix-route-export')), findsOneWidget);
    expect(
      find.text('No Prefix route rules have been learned yet.'),
      findsOneWidget,
    );
  });

  testWidgets('Prefix route detail supports a manual override', (tester) async {
    await _pumpSettings(tester);
    final database = tester
        .state<_SettingsHarnessState>(find.byType(_SettingsHarness))
        .database;
    final repository = PrefixRouteRepository.forDatabase(database);
    await repository.recordSuccess(
      prefix: 'SONE',
      family: WorkImageNormalizationFamily.dmmStandard,
    );

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefix route rules'));
    await tester.pumpAndSettle();
    final sone = find.text('SONE');
    await tester.ensureVisible(sone);
    await tester.pumpAndSettle();
    await tester.tap(sone);
    await tester.pumpAndSettle();

    expect(find.text('Known candidates'), findsOneWidget);
    expect(find.text('Manual override'), findsOneWidget);

    await tester.tap(
      find.byType(DropdownButtonFormField<WorkImageNormalizationFamily?>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('MGStage Prestige').last);
    await tester.pumpAndSettle();

    expect(
      repository.ruleFor('sone')?.manualOverride,
      WorkImageNormalizationFamily.mgstagePrestige,
    );
    expect(
      repository
          .ruleFor('sone')
          ?.candidates
          .firstWhere(
            (candidate) =>
                candidate.family == WorkImageNormalizationFamily.dmmStandard,
          )
          .successCount,
      1,
    );
  });

  testWidgets('scrape sources persist detail and supported work selections', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Scrape settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrape sources'));
    await tester.pumpAndSettle();

    expect(find.text('Actress details source'), findsOneWidget);
    expect(find.text('Works source'), findsOneWidget);
    expect(find.text('Actress aliases source'), findsOneWidget);
    _expectBorderlessExpansionTile(
      tester,
      'Actress details source',
      expectedShape: const Border(),
      expectAnimationStyle: false,
    );
    _expectBorderlessExpansionTile(
      tester,
      'Works source',
      expectedShape: const Border(),
      expectAnimationStyle: false,
    );

    await tester.tap(find.byKey(const PageStorageKey('scrape-actress-source')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(RadioListTile<ScrapeSourceId>, 'JavBus'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const PageStorageKey('scrape-works-source')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'JavBus'),
          )
          .value,
      isTrue,
    );
    final availableAvBase = find.byKey(
      const ValueKey('scrape-works-source-available-avbase'),
    );
    await tester.ensureVisible(availableAvBase);
    await tester.pumpAndSettle();
    await tester.tap(availableAvBase);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    final selectedAvBase = find.byKey(
      const ValueKey('scrape-works-source-selected-avbase'),
    );
    await tester.ensureVisible(selectedAvBase);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byIcon(Icons.drag_handle).last,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    final availableAvWiki = find.byKey(
      const ValueKey('scrape-works-source-available-avwiki'),
    );
    await tester.ensureVisible(availableAvWiki);
    await tester.pumpAndSettle();
    await tester.tap(availableAvWiki);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scrape-works-source-selected-avwiki')),
      findsOneWidget,
    );

    final database = tester
        .state<_SettingsHarnessState>(find.byType(_SettingsHarness))
        .database;
    final settings = ScrapeSourceSettings.decode(
      await database.getSetting(scrapeSourceSettingsKey),
    );
    expect(settings.actressDetailsSource, ScrapeSourceId.javbus);
    expect(settings.worksSources, [
      ScrapeSourceId.avbase,
      ScrapeSourceId.javbus,
      ScrapeSourceId.avwiki,
    ]);
    expect(settings.aliasSource, ScrapeSourceId.avbase);

    // Reopening the category must read the latest persisted pair rather than
    // restoring either source's default.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrape settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrape sources'));
    await tester.pumpAndSettle();
    if (find.widgetWithText(CheckboxListTile, 'JavBus').evaluate().isEmpty) {
      await tester.tap(find.byKey(const PageStorageKey('scrape-works-source')));
      await tester.pumpAndSettle();
    }
    expect(find.widgetWithText(CheckboxListTile, 'JavBus'), findsOneWidget);

    final reopenedSettings = ScrapeSourceSettings.decode(
      await database.getSetting(scrapeSourceSettingsKey),
    );
    expect(reopenedSettings.actressDetailsSource, ScrapeSourceId.javbus);
    expect(reopenedSettings.worksSources, [
      ScrapeSourceId.avbase,
      ScrapeSourceId.javbus,
      ScrapeSourceId.avwiki,
    ]);
    expect(reopenedSettings.aliasSource, ScrapeSourceId.avbase);
  });

  testWidgets('scrape source connections can be retested and verified', (
    tester,
  ) async {
    final testedSources = <ScrapeSourceId>[];

    await _pumpSettings(
      tester,
      scrapeSourceConnectionTester: (source) async {
        testedSources.add(source);
        if (source == ScrapeSourceId.javbus) {
          throw const JavBusVerificationCancelledException();
        }
      },
    );

    await tester.tap(find.text('Scrape settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrape sources'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const PageStorageKey('scrape-source-connection-status')),
    );
    await tester.pumpAndSettle();
    _expectBorderlessExpansionTile(
      tester,
      'Scrape source connections',
      expectedShape: const Border(),
      expectAnimationStyle: false,
    );

    expect(
      find.byKey(const ValueKey('scrape-source-status-minnanoAv')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scrape-source-status-javbus')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scrape-source-status-avbase')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('scrape-source-status-avwiki')),
      findsOneWidget,
    );
    expect(find.text('Not tested'), findsNWidgets(4));

    await tester.tap(find.byKey(const ValueKey('scrape-source-retest-button')));
    await tester.pumpAndSettle();

    expect(testedSources, [
      ScrapeSourceId.minnanoAv,
      ScrapeSourceId.javbus,
      ScrapeSourceId.avbase,
      ScrapeSourceId.avwiki,
    ]);
    expect(find.text('Connected'), findsNWidgets(3));
    expect(find.text('Verification required'), findsOneWidget);
  });

  testWidgets('global scrape preferences persist outside the Works action', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Scrape settings'));
    await tester.pumpAndSettle();

    final preferences = find.byKey(const Key('settings-scrape-preferences'));
    await tester.ensureVisible(preferences);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('scrape-existing-data-policy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('scrape-auto-exclude-derived-switch')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('scrape-auto-exclude-derived-switch')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scrape-advanced-rules')));
    await tester.pumpAndSettle();
    final denyInput = find.byKey(const Key('scrape-exact-deny-input'));
    await tester.ensureVisible(denyInput);
    await tester.enterText(denyInput, 'manual-001');
    await tester.tap(find.byKey(const Key('scrape-exact-deny-add')));
    await tester.pumpAndSettle();

    final database = tester
        .state<_SettingsHarnessState>(find.byType(_SettingsHarness))
        .database;
    final options = WorkScrapeOptions.decode(
      await database.getSetting('works_scrape_options'),
    );
    expect(options.autoExcludeDerivedWorks, isFalse);
    expect(options.exactDenies.single.normalizedCode, 'MANUAL-001');
  });

  testWidgets('scrape advanced rules only expose exact overrides', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Scrape settings'));
    await tester.pumpAndSettle();

    final padding = tester.widget<Padding>(
      find.byKey(const Key('scrape-preferences-padding')),
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(8, 7, 8, 8));

    final tileFinder = find.byKey(const Key('scrape-advanced-rules'));
    final collapsed = tester.widget<ExpansionTile>(tileFinder);
    expect(collapsed.shape, const Border());
    expect(collapsed.collapsedShape, const Border());
    expect(find.byKey(const Key('scrape-prefix-input')), findsNothing);
    expect(find.byKey(const Key('scrape-ofje-policy-dropdown')), findsNothing);

    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scrape-exact-allow-input')), findsOneWidget);
    expect(find.byKey(const Key('scrape-exact-deny-input')), findsOneWidget);
    expect(find.byKey(const Key('scrape-prefix-input')), findsNothing);
    expect(find.byKey(const Key('scrape-ofje-policy-dropdown')), findsNothing);
    expect(find.text('Compatibility prefixes'), findsNothing);
    expect(
      find.text('Enter a full work code or prefix, e.g. KCKC or KCKC-212.'),
      findsOneWidget,
    );
  });

  testWidgets('all visible settings text uses the bundled variable font', (
    tester,
  ) async {
    await _pumpSettings(tester);

    for (final element in find.byType(Text).evaluate()) {
      final text = element.widget as Text;
      final inheritedStyle = DefaultTextStyle.of(element).style;
      final effectiveStyle = inheritedStyle.merge(text.style);

      expect(
        effectiveStyle.fontFamily,
        'NotoSansCjkTcVariable',
        reason: 'Missing bundled font on "${text.data}"',
      );
      expect(
        effectiveStyle.fontWeight?.value,
        greaterThanOrEqualTo(FontWeight.w300.value),
        reason: 'Text is lighter than w300 on "${text.data}"',
      );
    }
  });

  testWidgets(
    'system dark nests AMOLED under Dark without changing the selected mode',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Theme & Colors'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Theme Mode'), findsOneWidget);
      _expectBorderlessExpansionTile(tester, 'Theme Mode');
      expect(find.text('Follow System'), findsNothing);
      expect(find.text('Dark'), findsNothing);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Follow System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Custom Theme'), findsOneWidget);
      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      expect(darkOption, findsOneWidget);
      _expectSecondaryExpansionTile(tester, darkOption);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('theme_mode'), 'system');

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsOneWidget);
      expect(preferences.getString('theme_mode'), 'system');

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsNothing);
      final darkRadio = find.descendant(
        of: darkOption,
        matching: find.byType(Radio<String>),
      );
      expect(darkRadio, findsOneWidget);

      await tester.tap(darkRadio);
      await tester.pumpAndSettle();

      expect(preferences.getString('theme_mode'), 'dark');
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    },
  );

  testWidgets(
    'system light promotes Dark from a radio option after it is selected',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const PageStorageKey('theme-option-dark')),
        findsNothing,
      );
      final darkRadio = find.widgetWithText(RadioListTile<String>, 'Dark');
      expect(darkRadio, findsOneWidget);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(darkRadio);
      await tester.pumpAndSettle();

      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      expect(darkOption, findsOneWidget);
      _expectSecondaryExpansionTile(tester, darkOption);
      expect(find.text('Pure Black AMOLED'), findsNothing);
      expect(find.byType(Divider), findsNothing);
    },
  );

  testWidgets(
    'custom mode in platform dark keeps Dark a radio and hides AMOLED',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'custom',
        'pure_black': true,
        'app_locale': 'en',
      });
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const PageStorageKey('theme-option-custom')),
        findsOneWidget,
      );
      expect(
        find.byKey(const PageStorageKey('theme-option-dark')),
        findsNothing,
      );
      expect(
        find.widgetWithText(RadioListTile<String>, 'Dark'),
        findsOneWidget,
      );
      expect(find.text('Pure Black AMOLED'), findsNothing);
    },
  );

  testWidgets('fixed dark AMOLED copy excludes custom theme', (tester) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'pure_black': true,
      'app_locale': 'en',
    });

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const PageStorageKey('theme-option-dark')));
    await tester.pumpAndSettle();

    expect(find.text('Only works with dark theme'), findsOneWidget);
    expect(find.textContaining('/ custom theme'), findsNothing);
  });

  testWidgets('selecting Custom promotes it into a collapsed color submenu', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const PageStorageKey('theme-option-custom')),
      findsNothing,
    );
    final customRadio = find.widgetWithText(
      RadioListTile<String>,
      'Custom Theme',
    );
    expect(customRadio, findsOneWidget);

    await tester.ensureVisible(customRadio);
    await tester.pumpAndSettle();
    await tester.tap(customRadio);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('theme_mode'), 'custom');
    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    expect(customOption, findsOneWidget);
    _expectSecondaryExpansionTile(tester, customOption);
    expect(find.text('Background'), findsNothing);

    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Primary Accent'), findsOneWidget);
  });

  testWidgets('interface category expands all language choices', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Interface'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Interface'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    _expectBorderlessExpansionTile(tester, 'Language');
    expect(find.text('Follow System'), findsNothing);
    expect(find.text('Traditional Chinese (Taiwan)'), findsNothing);
    expect(find.text('Simplified Chinese'), findsNothing);
    expect(find.text('Japanese'), findsNothing);
    expect(find.text('English'), findsNothing);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.text('Follow System'), findsOneWidget);
    expect(find.text('Traditional Chinese (Taiwan)'), findsOneWidget);
    expect(find.text('Simplified Chinese'), findsOneWidget);
    expect(find.text('Japanese'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('Traditional Chinese (Taiwan)'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '介面'), findsOneWidget);
    expect(find.text('語言'), findsOneWidget);
  });

  testWidgets('interface category exposes works page size choices', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Interface'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.text('Works page size'), findsOneWidget);

    await tester.tap(find.byKey(const PageStorageKey('works-page-size')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const PageStorageKey('works-page-size-option-small')),
      findsOneWidget,
    );
    expect(
      find.byKey(const PageStorageKey('works-page-size-option-large')),
      findsOneWidget,
    );
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);

    await tester.tap(
      find.byKey(const PageStorageKey('works-page-size-option-large')),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('works_page_size'), 'large');
  });

  testWidgets('AMOLED is hidden in effective light mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    expect(find.text('Pure Black AMOLED'), findsNothing);
    expect(find.byKey(const PageStorageKey('theme-option-dark')), findsNothing);
  });

  testWidgets(
    'AMOLED follows effective system darkness and preserves its preference',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsNothing);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      expect(darkOption, findsOneWidget);
      expect(find.text('Pure Black AMOLED'), findsNothing);

      await tester.tap(darkOption);
      await tester.pumpAndSettle();

      expect(find.text('Pure Black AMOLED'), findsOneWidget);
      final pureBlackSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Pure Black AMOLED'),
      );
      expect(pureBlackSwitch.value, isTrue);
    },
  );

  testWidgets('custom theme nests the complete color editor under Custom', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'custom',
      'pure_black': false,
      'app_locale': 'en',
    });

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsNothing);
    expect(find.text('Primary Accent'), findsNothing);

    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    expect(customOption, findsOneWidget);
    _expectSecondaryExpansionTile(tester, customOption);
    expect(find.text('Background'), findsNothing);
    expect(find.text('Primary Accent'), findsNothing);

    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Card Background'), findsOneWidget);
    expect(find.text('Primary Text'), findsOneWidget);
    expect(find.text('Secondary Text'), findsOneWidget);
    expect(find.text('Primary Accent'), findsOneWidget);
    expect(find.text('Text on Primary'), findsOneWidget);
    expect(find.text('Border / Divider'), findsOneWidget);
    expect(find.text('Snackbar Background'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('color dialog previews the selected color on its outline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'custom',
      'pure_black': false,
      'app_locale': 'en',
    });

    await _pumpSettings(tester);
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();
    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();
    final background = find.text('Background');
    await tester.ensureVisible(background);
    await tester.pumpAndSettle();
    await tester.tap(background);
    await tester.pumpAndSettle();

    _expectDialogOutline(tester, Colors.black);

    final colorPicker = tester.widget<ColorPicker>(find.byType(ColorPicker));
    colorPicker.onColorChanged(const Color(0xFF123456));
    await tester.pump();

    _expectDialogOutline(tester, const Color(0xFF123456));
  });

  testWidgets(
    'category press uses a transparent tile overlay and local feedback dot',
    (tester) async {
      await _pumpSettings(tester);

      final category = find.ancestor(
        of: find.text('Theme & Colors'),
        matching: find.byType(Card),
      );
      final pressPosition = tester.getCenter(category) + const Offset(80, 0);
      final gesture = await tester.startGesture(pressPosition);
      await tester.pump();

      _expectTransparentPressedOverlay(tester, category);
      final feedbackDot = find.byKey(
        const ValueKey('settings-feedback-dot-category-theme-colors'),
      );
      _expectLocalFeedbackDot(tester, feedbackDot, pressPosition);

      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 40));
      expect(feedbackDot, findsOneWidget);
      await tester.pumpAndSettle();
      expect(feedbackDot, findsNothing);
    },
  );

  testWidgets(
    'nested setting press shares the transparent local feedback behavior',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'pure_black': false,
        'app_locale': 'en',
      });

      await _pumpSettings(tester);
      await tester.tap(find.text('Theme & Colors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme Mode'));
      await tester.pumpAndSettle();

      final darkOption = find.byKey(const PageStorageKey('theme-option-dark'));
      final pressPosition =
          tester.getTopLeft(darkOption) + const Offset(180, 28);
      final gesture = await tester.startGesture(pressPosition);
      await tester.pump();

      _expectTransparentPressedOverlay(tester, darkOption);
      final feedbackDot = find.byKey(
        const ValueKey('settings-feedback-dot-theme-mode'),
      );
      _expectLocalFeedbackDot(tester, feedbackDot, pressPosition);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
      expect(feedbackDot, findsOneWidget);
      await tester.pumpAndSettle();
      expect(feedbackDot, findsNothing);
    },
  );

  testWidgets('custom settings remain scrollable on a narrow scaled viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'custom',
      'pure_black': true,
      'app_locale': 'en',
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpSettings(tester, textScaler: const TextScaler.linear(1.25));
    await tester.tap(find.text('Theme & Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme Mode'));
    await tester.pumpAndSettle();

    final customOption = find.byKey(
      const PageStorageKey('theme-option-custom'),
    );
    await tester.ensureVisible(customOption);
    await tester.pumpAndSettle();
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    final outline = find.text('Border / Divider');
    await tester.ensureVisible(outline);
    await tester.pumpAndSettle();

    expect(outline, findsOneWidget);
    expect(find.text('Pure Black AMOLED'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _expectBorderlessCategoryCard(WidgetTester tester, String label) {
  final cardFinder = find.ancestor(
    of: find.text(label),
    matching: find.byType(Card),
  );

  expect(cardFinder, findsOneWidget);

  final card = tester.widget<Card>(cardFinder);
  final shape = card.shape;

  expect(shape, isA<RoundedRectangleBorder>());

  final roundedShape = shape! as RoundedRectangleBorder;
  expect(roundedShape.borderRadius, BorderRadius.circular(12));
  expect(roundedShape.side, BorderSide.none);
}

void _expectBorderlessExpansionTile(
  WidgetTester tester,
  String label, {
  ShapeBorder? expectedShape,
  bool expectAnimationStyle = true,
}) {
  final tileFinder = find.widgetWithText(ExpansionTile, label).first;

  expect(tileFinder, findsOneWidget);

  final tile = tester.widget<ExpansionTile>(tileFinder);
  expect(tile.leading, isNull);
  expect(tile.trailing, isNull);
  expect(tile.showTrailingIcon, isTrue);
  expect(tile.clipBehavior, Clip.antiAlias);
  if (expectedShape != null) {
    expect(tile.shape, expectedShape);
    expect(tile.collapsedShape, expectedShape);
  } else {
    expect(tile.shape, isA<RoundedRectangleBorder>());
    expect(tile.collapsedShape, isA<RoundedRectangleBorder>());
    expect((tile.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(
      (tile.collapsedShape! as RoundedRectangleBorder).side,
      BorderSide.none,
    );
  }

  if (expectAnimationStyle) {
    final animationStyle = tile.expansionAnimationStyle;
    expect(animationStyle, isNotNull);
    expect(animationStyle!.duration, const Duration(milliseconds: 180));
    expect(animationStyle.curve, Curves.easeOutCubic);
    expect(animationStyle.reverseCurve, Curves.easeInCubic);
  }
}

void _expectSecondaryExpansionTile(WidgetTester tester, Finder tileFinder) {
  final tile = tester.widget<ExpansionTile>(tileFinder);

  expect(tile.leading, isA<Radio<String>>());
  expect(tile.trailing, isNull);
  expect(tile.showTrailingIcon, isTrue);
  expect(tile.shape, const Border());
  expect(tile.collapsedShape, const Border());
  expect(tile.backgroundColor, Colors.transparent);
  expect(tile.collapsedBackgroundColor, Colors.transparent);

  final animationStyle = tile.expansionAnimationStyle;
  expect(animationStyle, isNotNull);
  expect(animationStyle!.duration, const Duration(milliseconds: 180));
}

void _expectDialogOutline(WidgetTester tester, Color expectedColor) {
  final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
  final shape = dialog.shape;

  expect(shape, isA<RoundedRectangleBorder>());

  final roundedShape = shape! as RoundedRectangleBorder;
  expect(roundedShape.borderRadius, BorderRadius.circular(12));
  expect(roundedShape.side.width, 1);
  expect(roundedShape.side.color, expectedColor);
}

void _expectTransparentPressedOverlay(
  WidgetTester tester,
  Finder tappableRegion,
) {
  final inkWellFinder = find.descendant(
    of: tappableRegion,
    matching: find.byType(InkWell),
  );
  expect(inkWellFinder, findsOneWidget);

  final inkWell = tester.widget<InkWell>(inkWellFinder);
  final theme = Theme.of(tester.element(inkWellFinder));
  expect(
    inkWell.overlayColor?.resolve({WidgetState.pressed}) ??
        theme.highlightColor,
    Colors.transparent,
  );
  expect(theme.splashFactory, NoSplash.splashFactory);
  expect(theme.splashColor, Colors.transparent);
}

void _expectLocalFeedbackDot(
  WidgetTester tester,
  Finder feedbackDot,
  Offset pressPosition,
) {
  expect(feedbackDot, findsOneWidget);
  expect(tester.getCenter(feedbackDot).dx, closeTo(pressPosition.dx, 1));
  expect(tester.getCenter(feedbackDot).dy, closeTo(pressPosition.dy, 1));

  final size = tester.getSize(feedbackDot);
  expect(size.width, lessThanOrEqualTo(16));
  expect(size.height, size.width);

  final dot = tester.widget<DecoratedBox>(feedbackDot);
  final decoration = dot.decoration;
  expect(decoration, isA<BoxDecoration>());
  expect((decoration as BoxDecoration).shape, BoxShape.circle);
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  TextScaler textScaler = TextScaler.noScaling,
  ExternalUrlLauncher? externalUrlLauncher,
  ScrapeSourceConnectionTester? scrapeSourceConnectionTester,
}) async {
  await tester.pumpWidget(
    _SettingsHarness(
      textScaler: textScaler,
      externalUrlLauncher: externalUrlLauncher,
      scrapeSourceConnectionTester: scrapeSourceConnectionTester,
    ),
  );
  await tester.pumpAndSettle();
}

class _SettingsHarness extends StatefulWidget {
  const _SettingsHarness({
    this.textScaler = TextScaler.noScaling,
    this.externalUrlLauncher,
    this.scrapeSourceConnectionTester,
  });

  final TextScaler textScaler;
  final ExternalUrlLauncher? externalUrlLauncher;
  final ScrapeSourceConnectionTester? scrapeSourceConnectionTester;

  @override
  State<_SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<_SettingsHarness> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale = const Locale('en');
  final database = _FakeAppDatabase();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.fromPalette(AppPalettes.light),
      darkTheme: AppTheme.fromPalette(AppPalettes.dark),
      themeMode: _themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: widget.textScaler),
        child: child!,
      ),
      home: SettingsView(
        db: database,
        onThemeChanged: (themeMode, _, _) {
          if (_themeMode == themeMode) return;
          setState(() => _themeMode = themeMode);
        },
        onLocaleChanged: (locale) {
          if (_locale == locale) return;
          setState(() => _locale = locale);
        },
        externalUrlLauncher: widget.externalUrlLauncher ?? (_) async => true,
        scrapeSourceConnectionTester: widget.scrapeSourceConnectionTester,
      ),
    );
  }
}

class _FakeAppDatabase extends AppDatabase {
  final Map<String, String> _settings = {};

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
  }
}
