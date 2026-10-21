import 'dart:async';

import 'package:avaca/components/javbus_verification_dialog.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/scrape_job.dart';
import 'package:avaca/services/javbus/javbus_verification.dart';
import 'package:avaca/services/scrape_job_coordinator.dart';
import 'package:avaca/services/scrape_job_repository.dart';
import 'package:avaca/views/scrape_job_detail_view.dart';
import 'package:avaca/views/scrape_jobs_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows partial diagnostic and keeps a large checkpoint list scrollable',
    (tester) async {
      final db = AppDatabase();
      final job = ScrapeJob(
        id: 'ui-test-job',
        actressId: 1,
        actressNameSnapshot: '測試女優',
        state: ScrapeJobState.partial,
        phase: ScrapeJobPhase.completed,
        optionsSnapshot: '{}',
        sourceSettingsSnapshot: '{}',
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
        discoveredCount: 179,
        rawDiscoveredCount: 251,
        duplicateCount: 67,
        detailCompletedCount: 179,
        detailTotalCount: 179,
        processedCount: 31,
        savedCount: 30,
        reviewCount: 3,
        failedCount: 1,
        supplementalEvidenceCompletedCount: 42,
        supplementalEvidenceTotalCount: 69,
        lastError: '來源 javbus：partial\n作品 BAD-001：detailsUnavailable',
      );
      final now = DateTime.now().toUtc();
      final items = List<ScrapeJobItem>.generate(31, (index) {
        final failed = index == 30;
        final review = index == 29;
        return ScrapeJobItem(
          id: index + 1,
          jobId: job.id,
          canonicalCode: failed
              ? 'BAD-001'
              : review
              ? 'REVIEW-030'
              : 'OK-${index + 1}',
          state: failed
              ? ScrapeJobItemState.failed
              : review
              ? ScrapeJobItemState.review
              : ScrapeJobItemState.succeeded,
          stage: ScrapeJobPhase.completed,
          lastError: failed
              ? 'detailsUnavailable'
              : review
              ? 'review_evidence · 已檢查來源：JavBus、AV-Wiki'
              : null,
          createdAt: now,
          updatedAt: now,
        );
      });

      final repository = _FakeScrapeJobRepository(
        db: db,
        job: job,
        items: items,
      );
      final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ScrapeJobDetailView(
            db: db,
            coordinator: coordinator,
            jobId: job.id,
          ),
        ),
      );
      await tester.pump();
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(const Key('scrape-job-diagnostic')), findsOneWidget);
      expect(find.textContaining('BAD-001'), findsWidgets);
      expect(find.textContaining('候選作品 179'), findsOneWidget);
      expect(find.textContaining('補充證據 42/69'), findsOneWidget);
      expect(find.textContaining('待檢視 3'), findsOneWidget);
      expect(find.textContaining('取得 251'), findsNothing);
      expect(find.byKey(const Key('scrape-job-items-list')), findsOneWidget);
      final viewport = tester.getSize(
        find.byKey(const Key('scrape-job-items-viewport')),
      );
      expect(viewport.height, lessThanOrEqualTo(480));
      await tester.tap(
        find.byKey(const ValueKey('scrape-job-item-filter-review')),
      );
      await tester.pump();
      expect(find.text('REVIEW-030'), findsOneWidget);
      expect(find.textContaining('已檢查來源：JavBus'), findsOneWidget);
      expect(find.text('OK-1'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('scrape-job-item-filter-all')),
      );
    },
  );

  testWidgets('detail view ignores an out-of-order stale read', (tester) async {
    final db = AppDatabase();
    final staleRead = Completer<ScrapeJob?>();
    final oldJob = _job(id: 'old-job', name: '舊女優');
    final currentJob = _job(id: 'current-job', name: '新女優');
    final repository = _FakeScrapeJobRepository(
      db: db,
      job: currentJob,
      getResponses: [staleRead.future, Future.value(currentJob)],
    );
    final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      _testApp(
        ScrapeJobDetailView(
          db: db,
          coordinator: coordinator,
          jobId: currentJob.id,
        ),
      ),
    );
    await tester.pump();
    coordinator.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    staleRead.complete(oldJob);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    expect(find.text('舊女優'), findsNothing);
  });

  testWidgets('installs a user-visible JavBus verification handler', (
    tester,
  ) async {
    final db = AppDatabase();
    final job = _job(id: 'verification-job', name: '驗證女優');
    final repository = _FakeScrapeJobRepository(db: db, job: job);
    final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      _testApp(
        ScrapeJobDetailView(db: db, coordinator: coordinator, jobId: job.id),
      ),
    );
    await tester.pump();

    final challenge = JavBusVerificationChallenge(
      submitUri: Uri.parse('https://www.javbus.com/verify'),
      hiddenFields: const {},
      submitFields: const {'submit': 'question'},
      questions: [
        JavBusVerificationQuestion(
          name: 'answer',
          prompt: 'Do you agree?',
          options: [
            JavBusVerificationOption(value: 'yes', label: 'Yes'),
            JavBusVerificationOption(value: 'no', label: 'No'),
          ],
        ),
      ],
    );

    final handler = coordinator.verificationHandler;
    expect(handler, isNotNull);
    final pending = handler!(challenge);
    await tester.pump();
    expect(find.byType(JavBusVerificationDialog), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.tap(find.text('送出驗證'));
    await tester.pumpAndSettle();

    expect(await pending, {'answer': 'yes'});
  });

  testWidgets('jobs view ignores an out-of-order stale read', (tester) async {
    final db = AppDatabase();
    final staleRead = Completer<List<ScrapeJob>>();
    final oldJob = _job(id: 'old-job', name: '舊女優');
    final currentJob = _job(id: 'current-job', name: '新女優');
    final repository = _FakeScrapeJobRepository(
      db: db,
      job: currentJob,
      listResponses: [
        staleRead.future,
        Future.value([currentJob]),
      ],
    );
    final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      _testApp(ScrapeJobsView(db: db, coordinator: coordinator)),
    );
    await tester.pump();
    coordinator.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    staleRead.complete([oldJob]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('新女優'), findsOneWidget);
    expect(find.text('舊女優'), findsNothing);
  });

  testWidgets('long press selects a job and exposes the delete action', (
    tester,
  ) async {
    final db = AppDatabase();
    final job = _job(
      id: 'terminal-job',
      name: '可刪除女優',
      state: ScrapeJobState.succeeded,
    );
    final repository = _FakeScrapeJobRepository(db: db, job: job);
    final coordinator = ScrapeJobCoordinator(db: db, repository: repository);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      _testApp(ScrapeJobsView(db: db, coordinator: coordinator)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.longPress(find.text('可刪除女優'));
    await tester.pump();

    expect(find.text('已選取 1 項'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scrape-jobs-delete-selected')),
      findsOneWidget,
    );
    final card = tester.widget<Card>(
      find.ancestor(of: find.text('可刪除女優'), matching: find.byType(Card)),
    );
    final shape = card.shape! as RoundedRectangleBorder;
    expect(card.clipBehavior, Clip.antiAlias);
    expect(shape.borderRadius, BorderRadius.circular(12));
    expect(shape.side.width, 2);
    expect(
      shape.side.color,
      Theme.of(tester.element(find.byType(Card))).colorScheme.primary,
    );
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('可刪除女優'), matching: find.byType(ListTile)),
    );
    expect(tile.selected, isFalse);
    expect(tile.selectedTileColor, isNull);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('可刪除女優'), findsOneWidget);
    expect(find.text('已選取 1 項'), findsNothing);

    await tester.longPress(find.text('可刪除女優'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(find.text('可刪除女優'), findsOneWidget);
    expect(find.text('已選取 1 項'), findsNothing);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

ScrapeJob _job({
  required String id,
  required String name,
  ScrapeJobState state = ScrapeJobState.running,
}) {
  return ScrapeJob(
    id: id,
    actressId: 1,
    actressNameSnapshot: name,
    state: state,
    phase: switch (state) {
      ScrapeJobState.succeeded ||
      ScrapeJobState.partial ||
      ScrapeJobState.failed ||
      ScrapeJobState.cancelled => ScrapeJobPhase.completed,
      _ => ScrapeJobPhase.savingWorks,
    },
    optionsSnapshot: '{}',
    sourceSettingsSnapshot: '{}',
    rulesVersionSnapshot: 'builtin-1',
    rulesSnapshot: '{}',
  );
}

class _FakeScrapeJobRepository extends ScrapeJobRepository {
  _FakeScrapeJobRepository({
    required super.db,
    required this.job,
    this.items = const [],
    List<Future<ScrapeJob?>> getResponses = const [],
    List<Future<List<ScrapeJob>>> listResponses = const [],
  }) : getResponses = List<Future<ScrapeJob?>>.of(getResponses),
       listResponses = List<Future<List<ScrapeJob>>>.of(listResponses);

  final ScrapeJob job;
  final List<ScrapeJobItem> items;
  final List<Future<ScrapeJob?>> getResponses;
  final List<Future<List<ScrapeJob>>> listResponses;

  @override
  Future<ScrapeJob?> get(String id) async {
    if (getResponses.isNotEmpty) return getResponses.removeAt(0);
    return id == job.id ? job : null;
  }

  @override
  Future<List<ScrapeJob>> list({int? actressId, int limit = 100}) async {
    if (listResponses.isNotEmpty) return listResponses.removeAt(0);
    return [job];
  }

  @override
  Future<List<ScrapeJobItem>> listItems(String jobId) async =>
      jobId == job.id ? items : const [];

  @override
  Future<List<ScrapeJobEvent>> listEvents(
    String jobId, {
    int limit = 200,
  }) async => const [];

  @override
  Future<List<ScrapeJobSourceProgress>> listSourceProgress(
    String jobId,
  ) async => const [];
}
