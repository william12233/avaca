import 'package:avaca/views/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_test_harness.dart';

void main() {
  testWidgets('data transfer is grouped under Data management', (tester) async {
    await pumpGoldenApp(
      tester,
      SettingsView(
        db: GoldenFixtureDatabase(),
        onThemeChanged: (_, _, _) {},
        onLocaleChanged: (_) {},
      ),
      size: const Size(360, 800),
      textScale: 1.25,
    );

    expect(find.text('資料管理'), findsOneWidget);
    expect(find.text('介面'), findsOneWidget);
    await tester.tap(find.text('資料管理'));
    await tester.pumpAndSettle();

    expect(find.text('匯出資料'), findsOneWidget);
    expect(find.text('匯入資料'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.arrow_back).last);
    await tester.pumpAndSettle();
  });
}
