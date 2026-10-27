import 'package:avaca/components/app_help_tooltip.dart';
import 'package:avaca/core/config.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the explanation after a tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromPalette(AppPalettes.light),
        home: const Scaffold(
          body: Center(child: AppHelpTooltip(message: 'Help text')),
        ),
      ),
    );

    final help = find.byTooltip('Help text');
    expect(help, findsOneWidget);

    await tester.tap(help);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Help text'), findsOneWidget);
  });

  testWidgets('shows the explanation while a mouse hovers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromPalette(AppPalettes.light),
        home: const Scaffold(
          body: Center(child: AppHelpTooltip(message: 'Hover help')),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(
      location: tester.getCenter(find.byTooltip('Hover help')),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Hover help'), findsOneWidget);
  });

  testWidgets('places the help affordance after a flexible title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromPalette(AppPalettes.light),
        home: const Scaffold(
          body: SizedBox(
            width: 240,
            child: AppHelpTitleRow(
              title: Text('Setting'),
              message: 'Setting help',
            ),
          ),
        ),
      ),
    );

    final row = tester.widget<Row>(find.byType(Row));
    expect(row.children, hasLength(3));
    expect(row.children.first, isA<Expanded>());
    expect(row.children[1], isA<SizedBox>());
    expect((row.children[1] as SizedBox).width, AppHelpTitleRow.gap);
    expect(row.children.last, isA<AppHelpTooltip>());
  });
}
