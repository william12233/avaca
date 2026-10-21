import 'dart:async';

import 'package:avaca/views/add_view.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/home_view.dart';
import 'package:avaca/views/settings_view.dart';
import 'package:avaca/views/work_detail_view.dart';
import 'package:avaca/views/works_view.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ui_test_harness.dart';

const _compactViewport = Size(390, 844);
const _expandedViewport = Size(1280, 720);

void main() {
  group('adaptive UI primary surfaces', () {
    testWidgets('Home compact golden', (tester) async {
      await pumpGoldenApp(
        tester,
        HomeView(db: GoldenFixtureDatabase()),
        size: _compactViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/home.png'),
      );
    });

    testWidgets('Home expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        HomeView(db: GoldenFixtureDatabase()),
        size: _expandedViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/expanded/home.png'),
      );
    });

    testWidgets('Add compact golden', (tester) async {
      await pumpGoldenApp(
        tester,
        AddView(db: GoldenFixtureDatabase()),
        size: _compactViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/add.png'),
      );
    });

    testWidgets('Add expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        AddView(db: GoldenFixtureDatabase()),
        size: _expandedViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/expanded/add.png'),
      );
    });

    testWidgets('Settings compact golden', (tester) async {
      await pumpGoldenApp(
        tester,
        SettingsView(
          db: GoldenFixtureDatabase(),
          onThemeChanged: (_, _, _) {},
          onLocaleChanged: (_) {},
        ),
        size: _compactViewport,
      );
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/compact/settings.png'),
      );
    });

    testWidgets('Settings expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        SettingsView(
          db: GoldenFixtureDatabase(),
          onThemeChanged: (_, _, _) {},
          onLocaleChanged: (_) {},
        ),
        size: _expandedViewport,
      );
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/expanded/settings.png'),
      );
    });

    testWidgets('Scrape settings compact golden', (tester) async {
      await pumpGoldenApp(
        tester,
        SettingsView(
          db: GoldenFixtureDatabase(),
          onThemeChanged: (_, _, _) {},
          onLocaleChanged: (_) {},
        ),
        size: _compactViewport,
      );
      await tester.tap(find.text('刮削設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scrape-advanced-rules')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/compact/scrape-settings.png'),
      );
    });

    testWidgets('Scrape settings expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        SettingsView(
          db: GoldenFixtureDatabase(),
          onThemeChanged: (_, _, _) {},
          onLocaleChanged: (_) {},
        ),
        size: _expandedViewport,
      );
      await tester.tap(find.text('刮削設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scrape-advanced-rules')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/expanded/scrape-settings.png'),
      );
    });

    testWidgets('Detail compact golden', (tester) async {
      await pumpGoldenApp(
        tester,
        DetailView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _compactViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/detail.png'),
      );
    });

    testWidgets('Detail expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        DetailView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _expandedViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/expanded/detail.png'),
      );
    });

    testWidgets('Detail edit expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        DetailView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _expandedViewport,
      );
      await tester.tap(find.byKey(const Key('detail-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-edit-menu-item')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/expanded/detail-edit.png'),
      );
    });

    testWidgets('Works compact golden', (tester) async {
      await pumpGoldenApp(
        tester,
        WorksView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _compactViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/works.png'),
      );
    });

    testWidgets('Works expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        WorksView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _expandedViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/expanded/works.png'),
      );
    });

    testWidgets('WorkDetail compact golden', (tester) async {
      await pumpGoldenApp(
        tester,
        WorkDetailView(db: GoldenFixtureDatabase(), workId: 1),
        size: _compactViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/work-detail.png'),
      );
    });

    testWidgets('WorkDetail expanded golden', (tester) async {
      await pumpGoldenApp(
        tester,
        WorkDetailView(db: GoldenFixtureDatabase(), workId: 1),
        size: _expandedViewport,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/expanded/work-detail.png'),
      );
    });
  });

  group('adaptive UI changing states', () {
    testWidgets('Home search state golden', (tester) async {
      await pumpGoldenApp(
        tester,
        HomeView(db: GoldenFixtureDatabase()),
        size: _compactViewport,
      );
      await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/home-search.png'),
      );
    });

    testWidgets('Detail edit state golden', (tester) async {
      await pumpGoldenApp(
        tester,
        DetailView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _compactViewport,
      );
      await tester.tap(find.byKey(const Key('detail-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-edit-menu-item')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/detail-edit.png'),
      );
    });

    testWidgets('Works selection state golden', (tester) async {
      await pumpGoldenApp(
        tester,
        WorksView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _compactViewport,
      );
      await tester.longPress(find.byKey(const Key('work-card-1')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/works-selection.png'),
      );
    });

    testWidgets('Works search state golden', (tester) async {
      await pumpGoldenApp(
        tester,
        WorksView(db: GoldenFixtureDatabase(), actressId: 1),
        size: _compactViewport,
      );
      await tester.tap(find.byKey(const Key('works-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('works-search-menu-item')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/compact/works-search.png'),
      );
    });

    testWidgets('Settings expanded control state golden', (tester) async {
      await pumpGoldenApp(
        tester,
        SettingsView(
          db: GoldenFixtureDatabase(),
          onThemeChanged: (_, _, _) {},
          onLocaleChanged: (_) {},
        ),
        size: _compactViewport,
      );
      await tester.tap(find.byIcon(Icons.palette_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const PageStorageKey('theme-mode')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/compact/settings-theme-expanded.png'),
      );
    });

    testWidgets('Works scrape progress overlay golden', (tester) async {
      final result = Completer<WorksScrapeResult>();
      await pumpGoldenApp(
        tester,
        WorksView(
          db: GoldenFixtureDatabase(),
          actressId: 1,
          scrapeExecutor: (options, token, onProgress) async {
            onProgress(
              const WorksScrapeProgress(
                phase: WorksScrapePhase.fetchingDetails,
                current: 1,
                total: 3,
                saved: 0,
                excluded: 0,
                failed: 0,
                totalKnown: true,
                source: ScrapeSourceId.javbus,
                detailsSource: ScrapeSourceId.javbus,
                worksSources: [ScrapeSourceId.javbus],
                sourceProgress: {
                  ScrapeSourceId.javbus: WorksScrapeSourceProgress(
                    phase: WorksScrapePhase.fetchingDetails,
                    current: 1,
                    total: 3,
                    totalKnown: true,
                  ),
                },
              ),
            );
            return result.future;
          },
        ),
        size: _compactViewport,
      );
      await tester.tap(find.byKey(const Key('works-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('works-scrape-menu-item')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(find.byKey(const Key('scrape-progress-dialog')), findsOneWidget);
      expect(find.byKey(const Key('scrape-progress-sources')), findsOneWidget);
      expect(find.byKey(const Key('scrape-progress-summary')), findsOneWidget);
      expect(find.byKey(const Key('scrape-progress-count')), findsOneWidget);
      expect(find.byKey(const Key('scrape-progress-circular')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('scrape-progress-dialog')),
        matchesGoldenFile('goldens/compact/works-scrape.png'),
      );

      result.complete(
        const WorksScrapeResult(
          saved: 0,
          excluded: 0,
          failed: 0,
          cancelled: true,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('scrape-result-dialog')),
        matchesGoldenFile('goldens/compact/works-scrape-result.png'),
      );
      await tester.tap(find.byKey(const Key('scrape-result-done')));
      await tester.pumpAndSettle();
    });
  });
}
