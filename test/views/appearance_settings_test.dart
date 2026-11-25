import 'dart:ui' as ui;

import 'package:avaca/components/actress_card.dart';
import 'package:avaca/core/app_appearance.dart';
import 'package:avaca/core/app_motion.dart';
import 'package:avaca/core/config.dart';
import 'package:avaca/components/app_glass_surface.dart';
import 'package:avaca/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/ui_test_harness.dart';

const _glass = ValueKey('appearance-theme-frostedGlass');
const _standard = ValueKey('appearance-theme-standard');
const _themeTile = PageStorageKey('visual-theme');
const _appearanceTile = PageStorageKey('theme-mode');
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
    expect(oled.scaffoldBackgroundColor, Colors.black);
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
    expect(custom.extension<AppSurfaces>()!.glass, 1);
    expect(custom.cardTheme.color, palette.surfaceContainer);
  });

  testWidgets('glass blurs painted content only within the panel', (
    tester,
  ) async {
    const boundary = ValueKey('glass-render-proof');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: 280,
              height: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Row(
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: Colors.black,
                          child: SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: Colors.white,
                          child: SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                  const Positioned(
                    top: 72,
                    left: 30,
                    right: 30,
                    bottom: 28,
                    child: AppGlassSurface(
                      color: Colors.transparent,
                      surfaces: AppSurfaces(glass: 1),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final pixels = await _capture(tester, find.byKey(boundary));
    final rgba = pixels.$1;
    int red(int x, int y) => rgba[(y * pixels.$2 + x) * 4];
    expect(red(142, 50) - red(137, 50), greaterThan(220));
    expect(red(142, 119) - red(137, 119), lessThan(80));
    expect(red(137, 119) - red(105, 119), greaterThan(24));
    expect(red(173, 119) - red(142, 119), greaterThan(24));
  });

  testWidgets(
    'glass blurs the scrolling gallery over the original page color',
    (tester) async {
      tester.view.physicalSize = const Size(320, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'light',
        'visual_theme': 'frostedGlass',
        'motion_enabled': false,
      });
      await tester.pumpWidget(AvacaApp(db: GoldenFixtureDatabase()));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final context = tester.element(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        AppPalettes.light.surface,
      );
      expect(scaffold.extendBodyBehindAppBar, isTrue);
      final toolbarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      final firstCard = find.byType(ActressCard).first;
      expect(tester.getTopLeft(firstCard).dy, greaterThan(toolbarBottom));

      await tester.drag(find.byType(GridView), const Offset(0, -56));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(firstCard).dy, lessThan(toolbarBottom));
    },
  );

  testWidgets('two separate expanders and a theme that applies and persists', (
    tester,
  ) async {
    final database = GoldenFixtureDatabase();
    await tester.pumpWidget(AvacaApp(db: database));
    await tester.pumpAndSettle();
    await _openAppearance(tester);

    expect(find.byKey(_themeTile), findsOneWidget);
    expect(find.byKey(_appearanceTile), findsOneWidget);
    expect(find.byKey(_motionSwitch), findsOneWidget);
    expect(find.byKey(_standard), findsNothing);
    expect(find.text('Custom Palette'), findsNothing);

    await tester.tap(find.byKey(_themeTile));
    await _advance(tester);
    expect(find.byKey(_standard), findsOneWidget);
    expect(find.text('Custom Palette'), findsNothing);
    await tester.tap(find.byKey(_appearanceTile));
    await _advance(tester);
    expect(find.text('Custom Palette'), findsOneWidget);
    expect(find.byKey(_standard), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    await tester.tap(find.byKey(_appearanceTile));
    await _advance(tester);

    expect(_surfaces(tester).glass, 0);
    await tester.tap(find.byKey(_glass));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_surfaces(tester).glass, allOf(greaterThan(0), lessThan(1)));
    await _advance(tester);
    expect(_surfaces(tester).glass, 1);
    expect(
      Theme.of(tester.element(find.byType(AppBar).last)).appBarTheme.shape,
      isNull,
    );
    expect(
      tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .where((f) => f.enabled)
          .length,
      greaterThan(2),
    );

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
    await tester.tap(find.byKey(_themeTile));
    await _advance(tester);
    await tester.tap(find.byKey(_standard));
    await _advance(tester);
    expect(_surfaces(tester).glass, 0);
  });

  testWidgets(
    'motion preview plays, pauses in background, and switches to stills',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final database = GoldenFixtureDatabase();
      await tester.pumpWidget(AvacaApp(db: database));
      await tester.pumpAndSettle();
      await _openAppearance(tester);

      final sample = find.byKey(_motionSample);
      final boundary = find.descendant(
        of: sample,
        matching: find.byType(RepaintBoundary),
      );
      final before = await _frameHash(tester, boundary);
      final size = tester.getSize(sample);
      await tester.pump(const Duration(milliseconds: 700));
      expect(await _frameHash(tester, boundary), isNot(before));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final paused = await _frameHash(tester, boundary);
      await tester.pump(const Duration(seconds: 1));
      expect(await _frameHash(tester, boundary), paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.tap(find.byKey(_motionSwitch));
      await tester.pumpAndSettle();
      expect(tester.getSize(sample), size);
      expect(AppMotion.enabledOf(tester.element(sample)), isFalse);
      expect(_currentRoute(tester).reverseTransitionDuration, Duration.zero);
      expect(
        tester
            .widget<ExpansionTile>(find.byKey(_appearanceTile))
            .expansionAnimationStyle,
        AnimationStyle.noAnimation,
      );
      expect(
        tester.widget<Semantics>(sample).properties.label,
        startsWith('Still preview'),
      );
      final still = await _frameHash(tester, boundary);
      await tester.pump(const Duration(seconds: 1));
      expect(await _frameHash(tester, boundary), still);
      expect(find.text('Toggle preview'), findsNothing);

      await tester.tap(find.byKey(_motionSwitch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.widget<Semantics>(sample).properties.label,
        startsWith('Motion preview'),
      );
      expect(await _frameHash(tester, boundary), isNot(still));

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
    },
  );

  testWidgets('system reduction and keyboard on a narrow scaled viewport', (
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
    expect(
      tester.widget<Semantics>(find.byKey(_motionSample)).properties.label,
      startsWith('Still preview'),
    );
    await tester.tap(find.byKey(_themeTile));
    await tester.pumpAndSettle();
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

Future<(Uint8List, int)> _capture(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return (rgba.buffer.asUint8List(), image.width);
    } finally {
      image.dispose();
    }
  }))!;
}

Future<int> _frameHash(WidgetTester tester, Finder finder) async =>
    Object.hashAll((await _capture(tester, finder)).$1);

Future<void> _openAppearance(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Theme & Appearance'));
  await _advance(tester);
}

Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

AppSurfaces _surfaces(WidgetTester tester) =>
    AppSurfaces.of(tester.element(find.byType(AppBar).last));

ModalRoute<dynamic> _currentRoute(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byKey(_motionSample)))!;
