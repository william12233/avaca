import 'package:avaca/components/app_snackbar.dart';
import 'package:avaca/core/config.dart';
import 'package:avaca/core/shapes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _longMessage =
    'The export is complete. Some images were skipped because they were unavailable.';

void main() {
  testWidgets('uses the palette surface for every message type', (
    tester,
  ) async {
    await _pumpSnackBarHarness(tester, AppPalettes.light);

    for (final type in ['success', 'error', 'info']) {
      await _show(tester, type);
      final surface = tester.widget<Material>(_surface);
      expect(surface.color, AppPalettes.light.snackbarBackground);
      expect(surface.elevation, 0);
      expect(
        _messageColor(tester, '$type message'),
        AppPalettes.light.onSurface,
      );
      final shape = surface.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(AppShapeTokens.defaultCardRadius),
      );
      expect(shape.side.width, 1);
      expect(shape.side.color.a, greaterThan(0));
    }
  });

  testWidgets('keeps the dark and OLED surfaces legible', (tester) async {
    final oled = AppOledPaletteOverride.apply(AppPalettes.dark);
    for (final palette in [AppPalettes.dark, oled]) {
      await _pumpSnackBarHarness(tester, palette);
      await _show(tester, 'success');

      expect(tester.widget<Material>(_surface).color, Colors.black);
      expect(_messageColor(tester, 'success message'), palette.onSurface);
    }
  });

  testWidgets('keeps the custom background and corrects low contrast text', (
    tester,
  ) async {
    const background = Color(0xFF203040);
    await _pumpSnackBarHarness(
      tester,
      AppPalettes.light.copyWith(snackbarBackground: background),
    );
    await _show(tester, 'error');

    expect(tester.widget<Material>(_surface).color, background);
    expect(_messageColor(tester, 'error message'), Colors.white);
  });

  testWidgets('updates the visible notification when the theme changes', (
    tester,
  ) async {
    await _pumpSnackBarHarness(tester, AppPalettes.light);
    await _show(tester, 'success');
    await _pumpSnackBarHarness(tester, AppPalettes.dark);
    await tester.pumpAndSettle();

    expect(tester.widget<Material>(_surface).color, Colors.black);
    expect(
      _messageColor(tester, 'success message'),
      AppPalettes.dark.onSurface,
    );
  });

  testWidgets('fits the text and centers above the navigation bar', (
    tester,
  ) async {
    await _pumpSnackBarHarness(
      tester,
      AppPalettes.light,
      bottomNavigationBar: const SizedBox(height: 64),
    );
    await _show(tester, 'short');

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final shortBounds = tester.getRect(_surface);
    final shortText = tester.getRect(find.text('ok'));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(shortText.left - shortBounds.left, 16);
    expect(shortText.top - shortBounds.top, 10);
    expect(shortBounds.width, lessThan(100));
    final scaffold = tester.getRect(find.byType(Scaffold));
    expect(shortBounds.center.dx, scaffold.center.dx);
    expect(shortBounds.bottom, scaffold.bottom - 64 - 16);

    await _show(tester, 'long');
    expect(tester.getSize(_surface).width, 400);
  });

  testWidgets('wraps scaled text above the keyboard on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpSnackBarHarness(tester, AppPalettes.light);
    await _show(tester, 'long');

    final bounds = tester.getRect(_surface);
    expect(bounds.left, 16);
    expect(bounds.right, 304);
    expect(bounds.top, greaterThan(0));
    expect(bounds.bottom, 640 - 260 - 16);
    expect(tester.getSize(find.text(_longMessage)).height, greaterThan(56));
    expect(tester.takeException(), isNull);
  });

  testWidgets('floats above the bottom safe area', (tester) async {
    final bottom = 24 * tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(bottom: bottom);
    tester.view.viewPadding = FakeViewPadding(bottom: bottom);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await _pumpSnackBarHarness(tester, AppPalettes.light);
    await _show(tester, 'short');

    final scaffold = tester.getRect(find.byType(Scaffold));
    expect(tester.getRect(_surface).bottom, scaffold.bottom - 24 - 16);
  });

  testWidgets(
    'announces and times out the newest message after rapid updates',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpSnackBarHarness(tester, AppPalettes.light);
      await _show(tester, 'success');
      await tester.tap(find.byKey(const Key('show-error')));
      await tester.tap(find.byKey(const Key('show-info')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('success message'), findsNothing);
      expect(find.text('error message'), findsNothing);
      expect(find.bySemanticsLabel('info message'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.duration, const Duration(seconds: 3));
      final ancestors = find.ancestor(
        of: find.text('info message'),
        matching: find.byType(Semantics),
      );
      expect(
        tester
            .widgetList<Semantics>(ancestors)
            .any((widget) => widget.properties.liveRegion == true),
        isTrue,
      );
      semantics.dispose();

      await tester.pump(const Duration(milliseconds: 2999));
      expect(find.text('info message'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}

Finder get _surface =>
    find.descendant(of: find.byType(SnackBar), matching: find.byType(Material));

Color? _messageColor(WidgetTester tester, String message) {
  return DefaultTextStyle.of(tester.element(find.text(message))).style.color;
}

Future<void> _show(WidgetTester tester, String type) async {
  await tester.tap(find.byKey(Key('show-$type')));
  await tester.pumpAndSettle();
}

Future<void> _pumpSnackBarHarness(
  WidgetTester tester,
  AppPalette palette, {
  Widget? bottomNavigationBar,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromPalette(palette),
      home: Scaffold(
        bottomNavigationBar: bottomNavigationBar,
        body: Builder(
          builder: (context) => Column(
            children: [
              ElevatedButton(
                key: const Key('show-success'),
                onPressed: () =>
                    AppSnackBar.showSuccess(context, 'success message'),
                child: const Text('success'),
              ),
              ElevatedButton(
                key: const Key('show-error'),
                onPressed: () =>
                    AppSnackBar.showError(context, 'error message'),
                child: const Text('error'),
              ),
              ElevatedButton(
                key: const Key('show-info'),
                onPressed: () => AppSnackBar.showInfo(context, 'info message'),
                child: const Text('info'),
              ),
              ElevatedButton(
                key: const Key('show-short'),
                onPressed: () => AppSnackBar.showInfo(context, 'ok'),
                child: const Text('short'),
              ),
              ElevatedButton(
                key: const Key('show-long'),
                onPressed: () => AppSnackBar.showInfo(context, _longMessage),
                child: const Text('long'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
