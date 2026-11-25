import 'package:avaca/components/app_appearance_controls.dart';
import 'package:avaca/core/app_appearance.dart';
import 'package:avaca/core/app_motion.dart';
import 'package:avaca/core/config.dart';
import 'package:avaca/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/ui_test_harness.dart';

const _glass = ValueKey('appearance-theme-frostedGlass');
const _standard = ValueKey('appearance-theme-standard');
const _motionSwitch = ValueKey('appearance-motion');
const _motionSample = ValueKey('appearance-motion-sample');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'app_locale': 'en'}));

  test('frosted glass respects the custom palette and the OLED override', () {
    final oled = AppTheme.fromOptions(
      options: const AppThemeOptions(mode: AppThemeMode.dark, oledBlack: true),
      systemBrightness: Brightness.dark,
      visualTheme: AppVisualTheme.frostedGlass,
    );
    final oledSurfaces = oled.extension<AppSurfaces>()!;
    expect(oledSurfaces.glass, 1);
    expect(oledSurfaces.backdrop(oled.colorScheme).color, Colors.black);
    expect(oledSurfaces.backdrop(oled.colorScheme).gradient, isNull);
    expect(oled.cardTheme.color, const Color(0xFF121212));

    final palette = AppPalettes.dark.copyWith(
      surface: const Color(0xFF18132C),
      primary: const Color(0xFFDBC7FF),
    );
    final custom = AppTheme.fromOptions(
      options: AppThemeOptions(
        mode: AppThemeMode.custom,
        oledBlack: true,
        customPalette: palette,
      ),
      systemBrightness: Brightness.dark,
      visualTheme: AppVisualTheme.frostedGlass,
    );
    expect(custom.colorScheme.surface, palette.surface);
    expect(custom.colorScheme.primary, palette.primary);
    expect(custom.extension<AppSurfaces>()!.tint, 1);
    expect(custom.cardTheme.color, palette.surfaceContainer);
  });

  testWidgets('visual theme applies across routes and restores after restart', (
    tester,
  ) async {
    final database = GoldenFixtureDatabase();
    await tester.pumpWidget(AvacaApp(db: database));
    await tester.pumpAndSettle();
    await _openAppearance(tester);

    expect(_surfaces(tester).glass, 0);
    expect(find.byKey(_standard), findsOneWidget);
    await tester.tap(find.byKey(_glass));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_surfaces(tester).glass, allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(_surfaces(tester).glass, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_surfaces(tester).glass, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(AvacaApp(db: database));
    await tester.pumpAndSettle();
    expect(_surfaces(tester).glass, 1);
    await _openAppearance(tester);
    await tester.tap(find.byKey(_standard));
    await tester.pumpAndSettle();
    expect(_surfaces(tester).glass, 0);
  });

  testWidgets('motion switch previews both behaviors and skips route motion', (
    tester,
  ) async {
    final database = GoldenFixtureDatabase();
    await tester.pumpWidget(AvacaApp(db: database));
    await tester.pumpAndSettle();
    await _openAppearance(tester);

    final sample = find.byKey(_motionSample);
    final previewToggle = find.text('Toggle preview');
    final collapsed = tester.getSize(sample).height;
    await tester.tap(previewToggle);
    await tester.pump();
    expect(tester.getSize(sample).height, collapsed);
    await tester.pump(const Duration(milliseconds: 60));
    final expanding = tester.getSize(sample).height;
    expect(expanding, greaterThan(collapsed));

    await tester.tap(find.byKey(_motionSwitch));
    await tester.pump();
    expect(tester.getSize(sample).height, collapsed);
    expect(AppMotion.enabledOf(tester.element(sample)), isFalse);
    expect(_currentRoute(tester).reverseTransitionDuration, Duration.zero);
    expect(
      tester
          .widget<ExpansionTile>(find.byKey(const PageStorageKey('theme-mode')))
          .expansionAnimationStyle,
      AnimationStyle.noAnimation,
    );

    await tester.tap(previewToggle);
    await tester.pump();
    final expanded = tester.getSize(sample).height;
    expect(expanded, greaterThan(expanding));
    await tester.tap(find.byKey(_motionSwitch));
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(sample).height, expanded);
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.getSize(sample).height,
      inExclusiveRange(collapsed, expanded),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(sample).height, collapsed);
    expect(AppMotion.enabledOf(tester.element(sample)), isTrue);

    await tester.tap(find.byKey(_motionSwitch));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(AvacaApp(db: database));
    await tester.pumpAndSettle();
    await _openAppearance(tester);
    expect(
      tester.widget<SwitchListTile>(find.byKey(_motionSwitch)).value,
      isFalse,
    );
    expect(_currentRoute(tester).transitionDuration, Duration.zero);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter & Sort'));
    await tester.pump();
    final sheet = tester.element(find.byType(BottomSheet));
    expect(ModalRoute.of(sheet)?.transitionDuration, Duration.zero);
  });

  testWidgets('system reduction overrides motion on a narrow scaled viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(AvacaApp(db: GoldenFixtureDatabase()));
    await tester.pumpAndSettle();
    await _openAppearance(tester);

    expect(find.text('Your system is set to reduce motion'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byKey(_motionSwitch)).value,
      isTrue,
    );
    expect(_currentRoute(tester).transitionDuration, Duration.zero);
    final sample = find.byKey(_motionSample);
    final toggle = find.text('Toggle preview');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    final collapsed = tester.getSize(sample).height;
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.getSize(sample).height, greaterThan(collapsed));

    final card = tester.element(find.byKey(_glass));
    for (var count = 0; count < 10; count++) {
      final focused = FocusManager.instance.primaryFocus?.context as Element?;
      var withinCard = false;
      focused?.visitAncestorElements((ancestor) {
        withinCard = ancestor == card;
        return !withinCard;
      });
      if (withinCard) break;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_surfaces(tester).glass, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openAppearance(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Appearance'));
  await tester.pumpAndSettle();
}

AppSurfaces _surfaces(WidgetTester tester) =>
    AppSurfaces.of(tester.element(find.byType(AppBar).last));

ModalRoute<dynamic> _currentRoute(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(AppAppearanceControls)))!;
