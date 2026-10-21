import 'dart:async';

import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/works_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WorksFeatureDatabase extends AppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': '涼森れむ',
      'img_path': '',
      'main_type': '有碼',
      'memo': '',
      'height': '160',
      'weight': '',
      'bwh': '87-58-85',
      'cup': 'F',
      'birth_date': '1997-12-03',
    };
  }

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    return const [
      {
        'id': 1,
        'code': 'ABF-367',
        'title': '第一部測試作品',
        'release_date': '2026-07-17',
        'duration_minutes': 135,
        'studio': 'プレステージ',
        'publisher': 'ABSOLUTELYFANTASIA',
        'series': '「顔」で、ヌく。',
        'card_image_path': '',
        'detail_image_path': '',
      },
      {
        'id': 2,
        'code': 'SONE-833',
        'title': '第二部測試作品',
        'release_date': '2026-06-20',
        'duration_minutes': 120,
        'studio': '測試製作商',
        'publisher': '測試發行商',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      },
      {
        'id': 3,
        'code': 'START-196',
        'title': '第三部測試作品',
        'release_date': '2026-05-01',
        'duration_minutes': null,
        'studio': '',
        'publisher': '',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      },
      {
        'id': 4,
        'code': 'SONE409',
        'title': '第四部測試作品',
        'release_date': '2026-04-12',
        'duration_minutes': 110,
        'studio': '',
        'publisher': '',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      },
    ];
  }

  @override
  Future<Map<String, Object?>?> getWorkById(
    int workId, {
    int? currentActressId,
  }) async {
    final rows = await getWorksForActress(7);
    for (final row in rows) {
      if (row['id'] == workId) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<int> getWorkCountForActress(int actressId) async => 178;

  @override
  Future<String?> getSetting(String key) async => null;

  @override
  Future<void> setSetting(String key, String value) async {}
}

class _WideWorksFeatureDatabase extends _WorksFeatureDatabase {
  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    final works = [...await super.getWorksForActress(actressId)];
    for (var id = 5; id <= 12; id++) {
      works.add({
        'id': id,
        'code': 'WIDE-$id',
        'title': '寬螢幕測試作品 $id',
        'release_date': '2026-01-${id.toString().padLeft(2, '0')}',
        'duration_minutes': 120,
        'studio': '測試製作商',
        'publisher': '測試發行商',
        'series': '',
        'card_image_path': '',
        'detail_image_path': '',
      });
    }
    return works;
  }
}

class _ConfiguredWorksFeatureDatabase extends _WorksFeatureDatabase {
  _ConfiguredWorksFeatureDatabase(this.options);

  final WorkScrapeOptions options;

  @override
  Future<String?> getSetting(String key) async {
    if (key == 'works_scrape_options') return options.encode();
    return super.getSetting(key);
  }
}

class _DeletingWorksFeatureDatabase extends _WorksFeatureDatabase {
  final deletedWorkIds = <int>[];

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    final works = await super.getWorksForActress(actressId);
    return works
        .where((work) => !deletedWorkIds.contains(work['id']))
        .toList(growable: false);
  }

  @override
  Future<WorkDeletionReport> deleteWorksWithReport(
    Iterable<int> workIds,
  ) async {
    final requested = workIds.toList(growable: false);
    deletedWorkIds.addAll(requested);
    return WorkDeletionReport(
      databaseCommitted: true,
      requestedWorkIds: requested,
      deletedWorkIds: requested,
      deletedWorkRows: requested.length,
      deletedActressWorkRows: requested.length,
      fileCleanup: const ManagedFileCleanupReport(),
      cacheEvictionPaths: const [],
      pendingFileDeletionsBefore: const [],
      pendingFileDeletionsAfter: const [],
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('works page renders a three-column screenshot-style grid', (
    tester,
  ) async {
    await _pumpWorks(tester);

    expect(find.byKey(const Key('work-card-1')), findsOneWidget);

    expect(find.byKey(const Key('work-card-2')), findsOneWidget);

    expect(find.byKey(const Key('work-card-3')), findsOneWidget);

    expect(find.text('第一部測試作品'), findsOneWidget);

    expect(find.text('ABF-367'), findsOneWidget);

    expect(find.text('2026-07-17'), findsOneWidget);

    final first = tester.getRect(find.byKey(const Key('work-card-1')));

    final second = tester.getRect(find.byKey(const Key('work-card-2')));

    final third = tester.getRect(find.byKey(const Key('work-card-3')));

    expect(first.top, closeTo(second.top, 0.01));

    expect(second.top, closeTo(third.top, 0.01));

    expect(first.right, lessThan(second.left));

    expect(second.right, lessThan(third.left));

    expect(tester.takeException(), isNull);
  });

  testWidgets('works overflow menu contains search and scrape actions', (
    tester,
  ) async {
    await _pumpWorks(tester);

    expect(find.byKey(const Key('works-overflow-menu')), findsOneWidget);
    expect(find.byKey(const Key('works-scrape-action')), findsNothing);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('works-search-menu-item')), findsOneWidget);
    expect(find.byKey(const Key('works-scrape-menu-item')), findsOneWidget);
    expect(
      find.byKey(const Key('works-filter-stored-menu-item')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('works-filter-not-stored-menu-item')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('works-filter-all-menu-item')), findsOneWidget);

    await tester.tap(find.byKey(const Key('works-search-menu-item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('works-search-field')), findsOneWidget);
    expect(find.byKey(const Key('works-search-close')), findsOneWidget);
    expect(find.byKey(const Key('works-search-clear')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('works overflow menu filters saved and unsaved works', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('works-filter-stored-menu-item')));
    await tester.pumpAndSettle();
    expect(find.text('找不到符合的作品'), findsOneWidget);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('works-filter-all-menu-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
  });

  testWidgets('work code search ignores case and separators', (tester) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('works-search-menu-item')));
    await tester.pumpAndSettle();

    final searchField = find.byKey(const Key('works-search-field'));

    for (final query in ['SONE-409', 'sone-409', 'SONE409', 'sone409']) {
      await tester.enterText(searchField, query);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('work-card-4')), findsOneWidget);
      expect(find.byKey(const Key('work-card-1')), findsNothing);
      expect(find.byKey(const Key('work-card-2')), findsNothing);
      expect(find.byKey(const Key('work-card-3')), findsNothing);
    }

    expect(find.byKey(const Key('works-search-close')), findsOneWidget);
    expect(find.byKey(const Key('works-search-clear')), findsNothing);

    await tester.enterText(searchField, 'not-a-real-code');
    await tester.pumpAndSettle();

    expect(find.text('找不到符合的作品'), findsOneWidget);
    expect(find.byKey(const Key('work-card-4')), findsNothing);

    await tester.enterText(searchField, '中文');
    await tester.pumpAndSettle();

    expect(find.text('找不到符合的作品'), findsOneWidget);
    expect(find.byKey(const Key('work-card-4')), findsNothing);

    await tester.tap(find.byKey(const Key('works-search-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('works-search-field')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
    expect(find.byKey(const Key('work-card-4')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back closes work search before leaving the page', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('works-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('works-search-menu-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('works-search-field')),
      'SONE409',
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(WorksView), findsOneWidget);
    expect(
      find.byKey(const Key('works-search-field')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large works page size keeps two cards in the first row', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'works_page_size': 'large'});
    await _pumpWorks(tester);

    final first = tester.getRect(find.byKey(const Key('work-card-1')));
    final second = tester.getRect(find.byKey(const Key('work-card-2')));
    final third = tester.getRect(find.byKey(const Key('work-card-3')));
    expect(first.top, closeTo(second.top, 0.01));
    expect(third.top, greaterThan(second.top));
  });

  testWidgets('small works cards stay safe under narrow text scaling', (
    tester,
  ) async {
    await _pumpWorks(
      tester,
      size: const Size(320, 480),
      textScaler: const TextScaler.linear(1.25),
    );

    expect(find.byKey(const Key('work-card-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small works cards shrink in the expanded landscape layout', (
    tester,
  ) async {
    await _pumpWorks(tester, size: const Size(1440, 900));
    final smallWidth = tester
        .getRect(find.byKey(const Key('work-card-1')))
        .width;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    SharedPreferences.setMockInitialValues({'works_page_size': 'large'});
    await _pumpWorks(tester, size: const Size(1440, 900));
    final largeWidth = tester
        .getRect(find.byKey(const Key('work-card-1')))
        .width;

    expect(smallWidth, lessThan(largeWidth));
    expect(smallWidth, lessThanOrEqualTo(192));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide Works grid uses remaining width beyond the old cap', (
    tester,
  ) async {
    final database = _WideWorksFeatureDatabase();

    await _pumpWorks(tester, database: database, size: const Size(1440, 900));

    final smallFirst = tester.getRect(find.byKey(const Key('work-card-1')));
    final smallSeventh = tester.getRect(find.byKey(const Key('work-card-7')));
    final smallGrid = tester.getRect(find.byType(GridView).first);

    expect(smallSeventh.top, closeTo(smallFirst.top, 0.01));
    expect(smallGrid.width, greaterThan(1300));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    SharedPreferences.setMockInitialValues({'works_page_size': 'large'});
    await _pumpWorks(tester, database: database, size: const Size(1440, 900));

    final largeFirst = tester.getRect(find.byKey(const Key('work-card-1')));
    final largeFifth = tester.getRect(find.byKey(const Key('work-card-5')));
    final largeGrid = tester.getRect(find.byType(GridView).first);

    expect(largeFifth.top, closeTo(largeFirst.top, 0.01));
    expect(largeGrid.width, closeTo(smallGrid.width, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press enters multi-select and tap toggles work cards', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.longPress(find.byKey(const Key('work-card-1')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-card-selected-1')), findsOneWidget);

    expect(find.byKey(const Key('works-delete-action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('work-card-2')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-card-selected-1')), findsOneWidget);

    expect(find.byKey(const Key('work-card-selected-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('work-card-1')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-card-selected-1')), findsNothing);

    expect(find.byKey(const Key('work-card-selected-2')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'system back clears work selection and delete confirms global removal',

    (tester) async {
      await _pumpWorks(tester);

      await tester.longPress(find.byKey(const Key('work-card-1')));

      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();

      await tester.pumpAndSettle();

      expect(find.byType(WorksView), findsOneWidget);

      expect(find.byKey(const Key('work-card-selected-1')), findsNothing);

      expect(find.byKey(const Key('works-delete-action')), findsNothing);

      await tester.longPress(find.byKey(const Key('work-card-1')));

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('works-delete-action')));

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('works-delete-confirm')), findsOneWidget);

      expect(find.textContaining('其他女優'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('confirming selected work deletion reloads and exits selection', (
    tester,
  ) async {
    final database = _DeletingWorksFeatureDatabase();

    await _pumpWorks(tester, database: database);

    await tester.longPress(find.byKey(const Key('work-card-1')));

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('works-delete-action')));

    await tester.pumpAndSettle();

    await tester.tap(find.text('確定刪除'));

    await tester.pumpAndSettle();

    expect(database.deletedWorkIds, [1]);

    expect(find.byKey(const Key('work-card-1')), findsNothing);

    expect(find.byKey(const Key('work-card-2')), findsOneWidget);

    expect(find.byKey(const Key('works-delete-action')), findsNothing);

    expect(find.byKey(const Key('works-overflow-menu')), findsOneWidget);

    expect(find.text('已刪除 1 部作品'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('scrape action starts with persisted global preferences', (
    tester,
  ) async {
    const persisted = WorkScrapeOptions(
      syncDetails: false,
      fillMissingOnly: false,
      scrapeAliases: true,
      autoExcludeDerivedWorks: false,
      exactDenies: [ScrapeExactDenyRule(code: 'MANUAL-001')],
    );
    WorkScrapeOptions? received;
    await _pumpWorks(
      tester,
      database: _ConfiguredWorksFeatureDatabase(persisted),
      scrapeExecutor: (options, token, onProgress) async {
        received = options;
        return const WorksScrapeResult(
          saved: 1,
          excluded: 0,
          failed: 0,
          cancelled: false,
        );
      },
    );

    await _openWorksScrapeSettings(tester);
    await tester.pumpAndSettle();

    expect(received?.syncDetails, isFalse);
    expect(received?.fillMissingOnly, isFalse);
    expect(received?.scrapeAliases, isTrue);
    expect(received?.autoExcludeDerivedWorks, isFalse);
    expect(received?.exactDenies.single.normalizedCode, 'MANUAL-001');
    expect(find.byKey(const Key('scrape-result-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scrape-result-done')));
    await tester.pumpAndSettle();
  });
  testWidgets('avatar failure is visible while the scrape still completes', (
    tester,
  ) async {
    await _pumpWorks(
      tester,

      scrapeExecutor: (options, token, onProgress) async =>
          const WorksScrapeResult(
            saved: 1,

            excluded: 0,

            failed: 0,

            cancelled: false,

            actressImageStatus: ActressImageSyncStatus.downloadFailed,
          ),
    );

    await _openWorksScrapeSettings(tester);

    await tester.pumpAndSettle();

    expect(find.textContaining('女優頭像替換失敗，已保留原頭像'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scrape-result-done')));

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a work opens details with the downloaded large image', (
    tester,
  ) async {
    await _pumpWorks(tester);

    await tester.tap(find.byKey(const Key('work-card-1')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('work-detail-image')), findsOneWidget);

    expect(find.text('第一部測試作品'), findsOneWidget);

    expect(find.text('135 分鐘'), findsOneWidget);

    expect(find.textContaining('プレステージ'), findsOneWidget);

    expect(find.textContaining('ABSOLUTELYFANTASIA'), findsOneWidget);

    expect(find.textContaining('「顔」で、ヌく。'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('system back cannot dismiss the active scrape dialog', (
    tester,
  ) async {
    final result = Completer<WorksScrapeResult>();

    await _pumpWorks(
      tester,

      scrapeExecutor: (options, token, onProgress) async {
        onProgress(
          const WorksScrapeProgress(
            phase: WorksScrapePhase.fetchingDetails,
            current: 0,
            total: 1,
            saved: 0,
            excluded: 0,
            failed: 0,
            source: ScrapeSourceId.javbus,
            worksSources: [ScrapeSourceId.javbus],
            sourceProgress: {
              ScrapeSourceId.javbus: WorksScrapeSourceProgress(
                phase: WorksScrapePhase.fetchingDetails,
                current: 0,
                total: 1,
                totalKnown: true,
              ),
            },
          ),
        );
        return result.future;
      },
    );

    await _openWorksScrapeSettings(tester);

    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('scrape-progress-circular')), findsOneWidget);

    await tester.binding.handlePopRoute();

    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('scrape-progress-circular')), findsOneWidget);

    expect(find.byType(WorksView), findsOneWidget);

    result.complete(
      const WorksScrapeResult(
        saved: 0,

        excluded: 0,

        failed: 0,

        cancelled: false,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(WorksView), findsOneWidget);

    expect(find.byKey(const Key('scrape-result-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scrape-result-done')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scrape-result-dialog')), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('completed scrape result requires explicit Done dismissal', (
    tester,
  ) async {
    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) async =>
          const WorksScrapeResult(
            saved: 1,
            excluded: 0,
            failed: 0,
            cancelled: false,
          ),
    );

    await _openWorksScrapeSettings(tester);

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scrape-result-dialog')), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));

    await tester.pump();

    expect(find.byKey(const Key('scrape-result-dialog')), findsOneWidget);

    await tester.binding.handlePopRoute();

    await tester.pump();

    expect(find.byKey(const Key('scrape-result-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scrape-result-done')));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scrape-result-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrape progress keeps phase rows stable and uses circular progress',
    (tester) async {
      final result = Completer<WorksScrapeResult>();
      final allowDetailProgress = Completer<void>();
      final allowImageProgress = Completer<void>();
      var executorStarted = false;

      await _pumpWorks(
        tester,
        scrapeExecutor: (options, token, onProgress) async {
          executorStarted = true;
          onProgress(
            const WorksScrapeProgress(
              phase: WorksScrapePhase.collectingSources,
              current: 0,
              total: 0,
              saved: 0,
              excluded: 0,
              failed: 0,
              source: ScrapeSourceId.javbus,
              worksSources: [ScrapeSourceId.javbus],
            ),
          );
          await allowDetailProgress.future;
          onProgress(
            const WorksScrapeProgress(
              phase: WorksScrapePhase.fetchingDetails,
              current: 0,
              total: 1,
              saved: 0,
              excluded: 0,
              failed: 0,
              source: ScrapeSourceId.javbus,
              workCode: 'SHOULD-NOT-BE-SHOWN',
              totalKnown: true,
              worksSources: [ScrapeSourceId.javbus],
              sourceProgress: {
                ScrapeSourceId.javbus: WorksScrapeSourceProgress(
                  phase: WorksScrapePhase.fetchingDetails,
                  current: 0,
                  total: 1,
                  totalKnown: true,
                ),
              },
            ),
          );
          await allowImageProgress.future;
          onProgress(
            const WorksScrapeProgress(
              phase: WorksScrapePhase.downloadingImages,
              current: 0,
              total: 1,
              saved: 0,
              excluded: 0,
              failed: 0,
              source: ScrapeSourceId.javbus,
              workCode: 'REBD-975',
              totalKnown: true,
              worksSources: [ScrapeSourceId.javbus],
              sourceProgress: {
                ScrapeSourceId.javbus: WorksScrapeSourceProgress(
                  phase: WorksScrapePhase.downloadingImages,
                  current: 0,
                  total: 1,
                  totalKnown: true,
                  workCode: 'REBD-975',
                ),
              },
            ),
          );
          return result.future;
        },
      );

      await _openWorksScrapeSettings(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(executorStarted, isTrue);
      expect(find.byKey(const Key('scrape-progress-operation')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const Key('scrape-progress-count')), findsNothing);
      expect(find.byKey(const Key('scrape-progress-summary')), findsOneWidget);
      expect(find.text('已儲存 0 排除 0 失敗 0'), findsOneWidget);

      allowDetailProgress.complete();
      await tester.pump();
      expect(find.byKey(const Key('scrape-progress-operation')), findsNothing);
      expect(find.text('SHOULD-NOT-BE-SHOWN'), findsNothing);
      expect(find.byKey(const Key('scrape-progress-count')), findsOneWidget);
      expect(find.byKey(const Key('scrape-progress-circular')), findsOneWidget);

      allowImageProgress.complete();
      await tester.pump();
      expect(
        find.byKey(const Key('scrape-progress-current-work')),
        findsOneWidget,
      );
      expect(find.textContaining('REBD-975'), findsOneWidget);
      expect(
        find.byKey(const Key('scrape-progress-download-circular')),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);

      result.complete(
        const WorksScrapeResult(
          saved: 0,
          excluded: 0,
          failed: 0,
          cancelled: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scrape-result-done')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('shows numeric progress per source without work names', (
    tester,
  ) async {
    final result = Completer<WorksScrapeResult>();
    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) async {
        const payload = WorksScrapeProgress(
          phase: WorksScrapePhase.fetchingDetails,
          current: 3,
          total: 10,
          saved: 0,
          excluded: 0,
          failed: 0,
          source: ScrapeSourceId.javbus,
          worksSources: [ScrapeSourceId.minnanoAv, ScrapeSourceId.javbus],
          sourceProgress: {
            ScrapeSourceId.minnanoAv: WorksScrapeSourceProgress(
              phase: WorksScrapePhase.fetchingDetails,
              current: 3,
              total: 10,
              totalKnown: true,
              workCode: 'MINNANO-TITLE-MUST-NOT-SHOW',
            ),
            ScrapeSourceId.javbus: WorksScrapeSourceProgress(
              phase: WorksScrapePhase.fetchingDetails,
              current: 4,
              total: 10,
              totalKnown: true,
              workCode: 'JAVBUS-TITLE-MUST-NOT-SHOW',
            ),
          },
        );
        expect(payload.sourceProgress, hasLength(2));
        onProgress(payload);
        return result.future;
      },
    );

    await _openWorksScrapeSettings(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.byKey(const Key('scrape-progress-sources')), findsOneWidget);
    expect(find.text('Minnano AV'), findsOneWidget);
    expect(find.text('JavBus'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('4 / 10'), findsOneWidget);
    expect(find.byKey(const Key('scrape-progress-count')), findsOneWidget);
    expect(find.byKey(const Key('scrape-progress-circular')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('MINNANO-TITLE-MUST-NOT-SHOW'), findsNothing);
    expect(find.text('JAVBUS-TITLE-MUST-NOT-SHOW'), findsNothing);

    result.complete(
      const WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scrape-result-done')));
    await tester.pumpAndSettle();
  });

  testWidgets('unknown totals use an indeterminate circular indicator', (
    tester,
  ) async {
    final result = Completer<WorksScrapeResult>();
    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) async {
        onProgress(
          const WorksScrapeProgress(
            phase: WorksScrapePhase.fetchingDetails,
            current: 0,
            total: 0,
            saved: 0,
            excluded: 0,
            failed: 0,
            source: ScrapeSourceId.javbus,
            worksSources: [ScrapeSourceId.javbus],
            sourceProgress: {
              ScrapeSourceId.javbus: WorksScrapeSourceProgress(
                phase: WorksScrapePhase.fetchingDetails,
                current: 0,
                total: 0,
                totalKnown: false,
              ),
            },
          ),
        );
        return result.future;
      },
    );

    await _openWorksScrapeSettings(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byKey(const Key('scrape-progress-circular')),
    );
    expect(indicator.value, isNull);
    expect(find.byKey(const Key('scrape-progress-count')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    result.complete(
      const WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scrape-result-done')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'scrape dialog bounds stay stable when the current work changes',
    (tester) async {
      final result = Completer<WorksScrapeResult>();
      late void Function(WorksScrapeProgress progress) emitProgress;
      await _pumpWorks(
        tester,
        size: const Size(320, 480),
        textScaler: TextScaler.linear(1.3),
        scrapeExecutor: (options, token, onProgress) async {
          emitProgress = onProgress;
          onProgress(
            const WorksScrapeProgress(
              phase: WorksScrapePhase.fetchingDetails,
              current: 0,
              total: 3,
              saved: 0,
              excluded: 0,
              failed: 0,
              totalKnown: true,
              source: ScrapeSourceId.javbus,
              worksSources: [ScrapeSourceId.javbus],
              sourceProgress: {
                ScrapeSourceId.javbus: WorksScrapeSourceProgress(
                  phase: WorksScrapePhase.fetchingDetails,
                  current: 0,
                  total: 3,
                  totalKnown: true,
                ),
              },
            ),
          );
          return result.future;
        },
      );

      await _openWorksScrapeSettings(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      final dialogKey = find.byKey(const Key('scrape-progress-dialog'));
      final sourcesKey = find.byKey(const Key('scrape-progress-sources'));
      final initialDialogRect = tester.getRect(dialogKey);
      final initialSourcesRect = tester.getRect(sourcesKey);

      emitProgress(
        const WorksScrapeProgress(
          phase: WorksScrapePhase.downloadingImages,
          current: 1,
          total: 3,
          saved: 1,
          excluded: 0,
          failed: 0,
          totalKnown: true,
          source: ScrapeSourceId.javbus,
          workCode: 'LONG-CURRENT-WORK-CODE-THAT-CHANGES',
          worksSources: [ScrapeSourceId.javbus],
          sourceProgress: {
            ScrapeSourceId.javbus: WorksScrapeSourceProgress(
              phase: WorksScrapePhase.downloadingImages,
              current: 1,
              total: 3,
              totalKnown: true,
              workCode: 'LONG-CURRENT-WORK-CODE-THAT-CHANGES',
            ),
          },
        ),
      );
      await tester.pump();

      expect(tester.getRect(dialogKey), initialDialogRect);
      expect(tester.getRect(sourcesKey), initialSourcesRect);
      expect(
        find.byKey(const Key('scrape-progress-download-circular')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scrape-progress-current-work')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      result.complete(
        const WorksScrapeResult(
          saved: 1,
          excluded: 0,
          failed: 0,
          cancelled: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scrape-result-done')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('scrape progress dialog sizes to content on phone viewport', (
    tester,
  ) async {
    final result = Completer<WorksScrapeResult>();
    await _pumpWorks(
      tester,
      size: const Size(390, 844),
      scrapeExecutor: (options, token, onProgress) async {
        onProgress(
          const WorksScrapeProgress(
            phase: WorksScrapePhase.fetchingDetails,
            current: 0,
            total: 1,
            saved: 0,
            excluded: 0,
            failed: 0,
            totalKnown: true,
            source: ScrapeSourceId.javbus,
            worksSources: [ScrapeSourceId.javbus],
            sourceProgress: {
              ScrapeSourceId.javbus: WorksScrapeSourceProgress(
                phase: WorksScrapePhase.fetchingDetails,
                current: 0,
                total: 1,
                totalKnown: true,
              ),
            },
          ),
        );
        return result.future;
      },
    );

    await _openWorksScrapeSettings(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final progressViewport = tester.getRect(
      find.byType(SingleChildScrollView).last,
    );
    expect(progressViewport.height, lessThan(400));

    result.complete(
      const WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 0,
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scrape-result-done')));
    await tester.pumpAndSettle();
  });

  testWidgets('scrape result lists unique failed works and image issues', (
    tester,
  ) async {
    await _pumpWorks(
      tester,
      scrapeExecutor: (options, token, onProgress) async {
        return const WorksScrapeResult(
          saved: 1,
          excluded: 2,
          failed: 1,
          cancelled: false,
          failedWorks: [
            WorksScrapeFailure(
              code: 'SIVR-303',
              stage: WorksScrapeFailureStage.fetchingDetails,
              reason: WorksScrapeFailureReason.detailsUnavailable,
            ),
          ],
          imageFailures: [
            WorksScrapeImageFailure(
              code: 'SSIS-875',
              variants: [WorkImageVariant.card, WorkImageVariant.detail],
            ),
          ],
        );
      },
    );

    await _openWorksScrapeSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('失敗作品（1）'), findsOneWidget);
    expect(find.textContaining('SIVR-303'), findsOneWidget);
    expect(find.text('圖片下載失敗（1）'), findsOneWidget);
    expect(find.textContaining('SSIS-875'), findsOneWidget);
    expect(find.textContaining('SIVR00303'), findsNothing);
    expect(find.text('所有來源都無法取得作品詳情'), findsOneWidget);
    expect(find.byKey(const Key('scrape-result-scroll')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scrape-result-done')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'scrape result keeps actress details separate from work sources',
    (tester) async {
      await _pumpWorks(
        tester,
        scrapeExecutor: (options, token, onProgress) async {
          return const WorksScrapeResult(
            saved: 2,
            excluded: 1,
            failed: 0,
            cancelled: false,
            detailsSource: ScrapeSourceId.minnanoAv,
            worksSources: [ScrapeSourceId.javbus],
            sourceResults: {
              ScrapeSourceId.minnanoAv: ScrapeSourceRunResult(
                source: ScrapeSourceId.minnanoAv,
                state: ScrapeSourceRunState.zeroResults,
              ),
              ScrapeSourceId.javbus: ScrapeSourceRunResult(
                source: ScrapeSourceId.javbus,
                state: ScrapeSourceRunState.success,
                discovered: 3,
              ),
            },
          );
        },
      );

      await _openWorksScrapeSettings(tester);
      await tester.pumpAndSettle();

      expect(find.text('詳細資料'), findsOneWidget);
      expect(find.text('作品'), findsOneWidget);
      expect(find.text('下載'), findsOneWidget);
      expect(find.text('Minnano AV'), findsOneWidget);
      expect(find.text('JavBus'), findsOneWidget);
      expect(find.text('完成，無新增作品'), findsNothing);
      expect(find.textContaining('已儲存'), findsOneWidget);
      expect(find.textContaining('排除'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scrape-result-done')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'detail page shows the local work count inside the works button',

    (tester) async {
      await tester.pumpWidget(
        _localizedApp(
          home: DetailView(db: _WorksFeatureDatabase(), actressId: 7),
        ),
      );

      await tester.pumpAndSettle();

      final button = tester.getRect(
        find.byKey(const Key('detail-works-button')),
      );

      final count = tester.getRect(find.byKey(const Key('detail-works-count')));

      expect(find.text('178'), findsOneWidget);

      expect(count.left, greaterThan(button.left));
      expect(count.right, lessThanOrEqualTo(button.right));
      expect(button.height, 52);
      expect(button.width, greaterThan(120));

      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpWorks(
  WidgetTester tester, {
  AppDatabase? database,
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
  Future<WorksScrapeResult> Function(
    WorkScrapeOptions options,
    WorksScrapeCancellationToken token,
    void Function(WorksScrapeProgress progress) onProgress,
  )?
  scrapeExecutor,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    _localizedApp(
      textScaler: textScaler,
      home: WorksView(
        db: database ?? _WorksFeatureDatabase(),
        actressId: 7,
        scrapeExecutor: scrapeExecutor,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openWorksScrapeSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('works-overflow-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('works-scrape-menu-item')));
  await tester.pump();
}

Widget _localizedApp({
  required Widget home,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: home,
  );
}
