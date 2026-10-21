import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/database.dart';
import '../models/scrape_job.dart';
import '../models/scrape_exclusion_policy.dart';
import '../models/scrape_source_settings.dart';
import '../models/work_scrape_options.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_verification.dart';
import 'scrape_event_sanitizer.dart';
import 'scrape_run_observer.dart';
import 'scrape_job_repository.dart';
import 'scrape_rules_repository.dart';
import 'scrape/scrape_models.dart';
import 'works_scrape_service.dart';
import 'works_scrape_session_factory.dart';

class ScrapeJobProgressAccumulator {
  ScrapeJobProgressAccumulator({
    this.discoveredCount = 0,
    this.processedCount = 0,
    this.savedCount = 0,
    this.excludedCount = 0,
    this.failedCount = 0,
    this.reviewCount = 0,
    this.rawDiscoveredCount = 0,
    this.duplicateCount = 0,
    this.detailCompletedCount = 0,
    this.detailTotalCount = 0,
    this.supplementalEvidenceCompletedCount = 0,
    this.supplementalEvidenceTotalCount = 0,
  });

  int discoveredCount;
  int processedCount;
  int savedCount;
  int excludedCount;
  int failedCount;
  int reviewCount;
  int rawDiscoveredCount;
  int duplicateCount;
  int detailCompletedCount;
  int detailTotalCount;
  int supplementalEvidenceCompletedCount;
  int supplementalEvidenceTotalCount;
  final _outcomes = <String, ScrapeWorkOutcomeState>{};
  int _excludedBaseline = 0;
  bool _hasOutcome = false;

  void seed(ScrapeJob job) {
    discoveredCount = math.max(discoveredCount, job.discoveredCount);
    processedCount = math.max(processedCount, job.processedCount);
    savedCount = math.max(savedCount, job.savedCount);
    excludedCount = math.max(excludedCount, job.excludedCount);
    failedCount = math.max(failedCount, job.failedCount);
    reviewCount = math.max(reviewCount, job.reviewCount);
    rawDiscoveredCount = math.max(rawDiscoveredCount, job.rawDiscoveredCount);
    duplicateCount = math.max(duplicateCount, job.duplicateCount);
    detailCompletedCount = math.max(
      detailCompletedCount,
      job.detailCompletedCount,
    );
    detailTotalCount = math.max(detailTotalCount, job.detailTotalCount);
    supplementalEvidenceCompletedCount = math.max(
      supplementalEvidenceCompletedCount,
      job.supplementalEvidenceCompletedCount,
    );
    supplementalEvidenceTotalCount = math.max(
      supplementalEvidenceTotalCount,
      job.supplementalEvidenceTotalCount,
    );
  }

  void seedItems(Iterable<ScrapeJobItem> items) {
    if (_outcomes.isNotEmpty) return;
    for (final item in items) {
      final outcome = switch (item.state) {
        ScrapeJobItemState.succeeded => ScrapeWorkOutcomeState.saved,
        ScrapeJobItemState.review => ScrapeWorkOutcomeState.review,
        ScrapeJobItemState.excluded => ScrapeWorkOutcomeState.excluded,
        ScrapeJobItemState.failed => ScrapeWorkOutcomeState.failed,
        _ => null,
      };
      if (outcome != null) _outcomes[item.canonicalCode] = outcome;
    }
    _hasOutcome = _outcomes.isNotEmpty;
    if (_hasOutcome) {
      _excludedBaseline = math.max(
        0,
        excludedCount - _count(ScrapeWorkOutcomeState.excluded),
      );
      _recountOutcomes();
    }
  }

  void recordOutcome(String code, ScrapeWorkOutcomeState outcome) {
    if (outcome == ScrapeWorkOutcomeState.cancelled) return;
    if (!_hasOutcome) {
      _excludedBaseline = math.max(_excludedBaseline, excludedCount);
    }
    _outcomes[code] = outcome;
    _hasOutcome = true;
    _recountOutcomes();
  }

  void apply(WorksScrapeProgress progress) {
    if (progress.phase != WorksScrapePhase.collectingSources) {
      discoveredCount = math.max(discoveredCount, progress.total);
    }
    final sourceDiscovered = progress.worksSources.fold<int>(
      0,
      (total, source) =>
          total + (progress.sourceProgress[source]?.discovered ?? 0),
    );
    rawDiscoveredCount = math.max(
      rawDiscoveredCount,
      math.max(progress.rawDiscovered, sourceDiscovered),
    );
    duplicateCount = math.max(duplicateCount, progress.duplicateCount);
    detailCompletedCount = math.max(
      detailCompletedCount,
      progress.detailCompleted,
    );
    detailTotalCount = math.max(detailTotalCount, progress.detailTotal);
    supplementalEvidenceCompletedCount = math.max(
      supplementalEvidenceCompletedCount,
      progress.supplementalEvidenceCompleted,
    );
    supplementalEvidenceTotalCount = math.max(
      supplementalEvidenceTotalCount,
      progress.supplementalEvidenceTotal,
    );
    if (!_hasOutcome) {
      savedCount = math.max(savedCount, progress.saved);
      reviewCount = math.max(reviewCount, progress.review);
      excludedCount = math.max(excludedCount, progress.excluded);
      failedCount = math.max(failedCount, progress.failed);
    } else {
      _excludedBaseline = math.max(
        _excludedBaseline,
        progress.excluded - _count(ScrapeWorkOutcomeState.excluded),
      );
      _recountOutcomes();
    }
    processedCount = math.max(
      processedCount,
      savedCount + excludedCount + failedCount,
    );
  }

  int _count(ScrapeWorkOutcomeState state) =>
      _outcomes.values.where((outcome) => outcome == state).length;

  void _recountOutcomes() {
    savedCount =
        _count(ScrapeWorkOutcomeState.saved) +
        _count(ScrapeWorkOutcomeState.review);
    reviewCount = _count(ScrapeWorkOutcomeState.review);
    excludedCount = _excludedBaseline + _count(ScrapeWorkOutcomeState.excluded);
    failedCount = _count(ScrapeWorkOutcomeState.failed);
    processedCount = math.max(
      processedCount,
      savedCount + excludedCount + failedCount,
    );
  }
}

class ScrapeJobWriteFence {
  ScrapeJobWriteFence({
    required Future<void> Function(Future<void> Function()) enqueue,
    required Future<void> Function() drain,
  }) : _enqueue = enqueue,
       _drain = drain;

  final Future<void> Function(Future<void> Function()) _enqueue;
  final Future<void> Function() _drain;
  bool _accepting = true;

  void stopAccepting() => _accepting = false;

  Future<void> enqueue(Future<void> Function() operation) {
    if (!_accepting) return Future<void>.value();
    return _enqueue(operation);
  }

  Future<void> drain() => _drain();
}

class ScrapeJobTerminalCounters {
  const ScrapeJobTerminalCounters({
    required this.processed,
    required this.saved,
    required this.review,
    required this.excluded,
    required this.failed,
    required this.imageFailures,
    required this.cancelled,
  });

  factory ScrapeJobTerminalCounters.fromResult(WorksScrapeResult result) {
    return ScrapeJobTerminalCounters(
      processed: result.saved + result.excluded + result.failed,
      saved: result.saved,
      review: result.review,
      excluded: result.excluded,
      failed: result.failed,
      imageFailures: result.imageFailures.length,
      cancelled: result.cancelled,
    );
  }

  final int processed;
  final int saved;
  final int review;
  final int excluded;
  final int failed;
  final int imageFailures;
  final bool cancelled;
}

ScrapeJobState resolveScrapeJobFinalState({
  required bool pauseRequested,
  required bool cancelRequested,
  required bool resultCancelled,
  required bool partialSuccess,
}) {
  if (pauseRequested) return ScrapeJobState.paused;
  if (cancelRequested || resultCancelled) return ScrapeJobState.cancelled;
  if (partialSuccess) return ScrapeJobState.partial;
  return ScrapeJobState.succeeded;
}

String? buildScrapeJobResultDiagnostic(WorksScrapeResult result) {
  final lines = <String>[];
  for (final entry in result.sourceResults.entries) {
    final sourceResult = entry.value;
    final hasSourceWarning =
        sourceResult.error != null ||
        (sourceResult.state != ScrapeSourceRunState.success &&
            sourceResult.state != ScrapeSourceRunState.zeroResults);
    if (!hasSourceWarning) continue;
    final reason = sourceResult.error == null
        ? sourceResult.state.name
        : ScrapeEventSanitizer.message(
            sourceResult.error,
            fallback: sourceResult.state.name,
          );
    lines.add('來源 ${entry.key.storageValue}：$reason');
  }
  for (final failure in result.failedWorks) {
    final reason = failure.error == null
        ? failure.reason.name
        : ScrapeEventSanitizer.message(
            failure.error,
            fallback: failure.reason.name,
          );
    lines.add('作品 ${failure.code}：$reason');
  }
  for (final imageFailure in result.imageFailures) {
    lines.add(scrapeJobImageFailureMessage(imageFailure));
  }
  if (lines.isEmpty && result.partialSuccess) {
    lines.add('部分來源或作品有警告，請查看事件紀錄');
  }
  if (lines.isEmpty) return null;
  final limited = lines.take(12).toList(growable: true);
  if (lines.length > limited.length) {
    limited.add('其餘 ${lines.length - limited.length} 筆診斷請查看事件紀錄');
  }
  return limited.map((line) => ScrapeEventSanitizer.message(line)).join('\n');
}

String scrapeJobImageFailureMessage(WorksScrapeImageFailure failure) {
  final variants = failure.variants.map((variant) => variant.name).join('、');
  return '作品 ${failure.code}：圖片下載失敗（$variants）';
}

class ScrapeJobCoordinator extends ChangeNotifier {
  ScrapeJobCoordinator({
    required this.db,
    ScrapeJobRepository? repository,
    ScrapeRulesRepository? rulesRepository,
    WorksScrapeSessionFactory? sessionFactory,
    this.verificationHandler,
  }) : repository = repository ?? ScrapeJobRepository(db: db),
       rulesRepository = rulesRepository ?? ScrapeRulesRepository(db: db),
       sessionFactory = sessionFactory ?? WorksScrapeSessionFactory(db: db);

  final AppDatabase db;
  final ScrapeJobRepository repository;
  final ScrapeRulesRepository rulesRepository;
  final WorksScrapeSessionFactory sessionFactory;
  JavBusVerificationHandler? verificationHandler;

  bool _initialized = false;
  Future<void>? _initializationFuture;
  bool _pumpRunning = false;
  bool _pumpRequested = false;
  String? _runningJobId;
  final _tokens = <String, WorksScrapeCancellationToken>{};
  final _retryingJobIds = <String>{};
  Future<void> _writeQueue = Future<void>.value();
  Timer? _notificationTimer;
  bool _disposed = false;

  Future<void> initialize() {
    final inFlight = _initializationFuture;
    if (inFlight != null) return inFlight;

    final future = _initializeOnce();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initializeOnce() async {
    try {
      await repository.recoverInterruptedJobs();
      await rulesRepository.load();
      _initialized = true;
      _emitChanged();
      unawaited(
        rulesRepository.refreshIfDue().then((_) {
          if (_initialized) _scheduleChanged();
        }),
      );
      unawaited(_pump());
    } on Object {
      _initializationFuture = null;
      rethrow;
    }
  }

  Future<ScrapeJob> enqueue({
    required int actressId,
    required String actressName,
    required WorkScrapeOptions options,
    required ScrapeSourceSettings sourceSettings,
  }) async {
    await initialize();
    final policySnapshot = ScrapePolicySnapshot.current(
      rules: rulesRepository.current,
      exactAllows: options.exactAllows,
      autoExcludeDerivedWorks: options.autoExcludeDerivedWorks,
      exactDenies: options.exactDenies,
    );
    final job = await repository.create(
      actressId: actressId,
      actressName: actressName,
      optionsSnapshot: options.encode(),
      sourceSettingsSnapshot: sourceSettings.encode(),
      rulesVersionSnapshot: policySnapshot.rulesVersion,
      rulesSnapshot: policySnapshot.encode(),
    );
    _emitChanged();
    unawaited(_pump());
    return job;
  }

  Future<void> pause(String jobId) async {
    _tokens[jobId]?.pause();
    _emitChanged();
    final job = await repository.get(jobId);
    if (job == null || !job.isActive || job.state == ScrapeJobState.paused) {
      return;
    }
    await repository.updateJob(jobId, state: ScrapeJobState.paused);
    await repository.appendEvent(
      jobId,
      severity: ScrapeJobEventSeverity.info,
      stage: job.phase,
      message: '已要求暫停，會在目前安全檢查點停止',
    );
    _emitChanged();
  }

  Future<void> resume(String jobId) async {
    final job = await repository.get(jobId);
    if (job == null ||
        (job.state != ScrapeJobState.paused &&
            job.state != ScrapeJobState.waitingForVerification)) {
      return;
    }
    await repository.updateJob(
      jobId,
      state: ScrapeJobState.queued,
      phase: ScrapeJobPhase.queued,
      clearError: true,
    );
    await repository.appendEvent(
      jobId,
      severity: ScrapeJobEventSeverity.info,
      stage: ScrapeJobPhase.queued,
      message: '工作已恢復，等待執行',
    );
    _emitChanged();
    unawaited(_pump());
  }

  Future<void> cancel(String jobId) async {
    _tokens[jobId]?.cancel();
    _emitChanged();
    final job = await repository.get(jobId);
    if (job == null || !job.isActive) return;
    final now = DateTime.now().toUtc();
    await repository.updateJob(
      jobId,
      state: ScrapeJobState.cancelled,
      finishedAt: now,
      phase: ScrapeJobPhase.completed,
    );
    await repository.appendEvent(
      jobId,
      severity: ScrapeJobEventSeverity.warning,
      stage: job.phase,
      message: '工作已取消',
    );
    _emitChanged();
  }

  Future<void> retryFailed(String jobId) async {
    if (!_retryingJobIds.add(jobId)) return;
    try {
      final items = await repository.listItems(jobId);
      final retryCodes = items
          .where((item) => item.state == ScrapeJobItemState.failed)
          .map((item) => item.canonicalCode)
          .toList(growable: false);
      final job = await repository.get(jobId);
      if (job == null ||
          retryCodes.isEmpty ||
          job.state == ScrapeJobState.queued ||
          job.state == ScrapeJobState.running) {
        return;
      }
      await repository.updateJob(
        jobId,
        state: ScrapeJobState.queued,
        phase: ScrapeJobPhase.queued,
        retryTargetCodes: retryCodes,
        clearError: true,
        clearFinishedAt: true,
      );
      for (final item in items.where(
        (item) => retryCodes.contains(item.canonicalCode),
      )) {
        await repository.upsertItem(
          ScrapeJobItem(
            id: item.id,
            jobId: item.jobId,
            canonicalCode: item.canonicalCode,
            observedRawCode: item.observedRawCode,
            state: ScrapeJobItemState.queued,
            stage: ScrapeJobPhase.queued,
            attemptCount: item.attemptCount,
            createdAt: item.createdAt,
            updatedAt: DateTime.now().toUtc(),
          ),
          existingId: item.id,
        );
      }
      await repository.appendEvent(
        jobId,
        severity: ScrapeJobEventSeverity.info,
        stage: ScrapeJobPhase.queued,
        message: '只重試失敗作品',
        metadata: {'count': retryCodes.length},
      );
      _emitChanged();
      unawaited(_pump());
    } finally {
      _retryingJobIds.remove(jobId);
    }
  }

  Future<ScrapeJob?> latestForActress(int actressId) =>
      repository.findActiveForActress(actressId);

  Future<List<ScrapeJob>> listJobs() => repository.list();

  Future<void> deleteJobs(Iterable<String> ids) async {
    await initialize();
    await _drainWrites();
    await repository.deleteTerminalJobs(ids);
    _emitChanged();
  }

  Future<List<ScrapeJobEvent>> eventsFor(String jobId) =>
      repository.listEvents(jobId);

  Future<void> _pump() async {
    if (_disposed) return;
    _pumpRequested = true;
    if (_pumpRunning) return;
    _pumpRunning = true;
    try {
      while (_pumpRequested && !_disposed) {
        _pumpRequested = false;
        while (_runningJobId == null && !_disposed) {
          final next = await repository.nextQueued();
          if (next == null) break;
          _runningJobId = next.id;
          await _run(next);
          _runningJobId = null;
        }
      }
    } finally {
      _pumpRunning = false;
      if (_pumpRequested && !_disposed) {
        unawaited(_pump());
      }
    }
  }

  Future<void> _run(ScrapeJob queued) async {
    final now = DateTime.now().toUtc();
    final attempt = queued.attemptCount + 1;
    final token = WorksScrapeCancellationToken();
    _tokens[queued.id] = token;
    _JobObserver? observer;
    var workDataChanged = false;
    try {
      await repository.updateJob(
        queued.id,
        state: ScrapeJobState.running,
        phase: ScrapeJobPhase.collectingSources,
        attemptCount: attempt,
        startedAt: queued.startedAt ?? now,
        clearError: true,
      );
      _emitChanged();
      if (token.shouldStop) {
        await _persistControlState(queued.id, token);
        return;
      }
      observer = _JobObserver(
        repository,
        queued.id,
        ScrapeJobWriteFence(enqueue: _queueWrite, drain: _drainWrites),
      );
      final session = await sessionFactory.create(
        queued,
        verificationHandler: verificationHandler,
      );
      try {
        if (token.shouldStop) {
          await _persistControlState(queued.id, token);
          return;
        }
        final result = await session.service.scrape(
          actressId: queued.actressId,
          actressName: queued.actressNameSnapshot,
          aliases: await sessionFactory.aliasesFor(queued.actressId),
          options: WorkScrapeOptions.decode(queued.optionsSnapshot).copyWith(
            retryWorkCodes: queued.retryTargetCodes.isEmpty
                ? null
                : queued.retryTargetCodes,
          ),
          sourceSettings: ScrapeSourceSettings.decode(
            queued.sourceSettingsSnapshot,
          ),
          policySnapshot: session.policySnapshot,
          cancellationToken: token,
          observer: observer,
        );
        workDataChanged = true;
        for (final failure in result.failedWorks) {
          await observer.complete(
            failure.code,
            state: ScrapeJobItemState.failed,
            error: failure.error ?? failure.reason.name,
          );
        }
        for (final imageFailure in result.imageFailures) {
          await observer.complete(
            imageFailure.code,
            state: ScrapeJobItemState.succeeded,
            error: scrapeJobImageFailureMessage(imageFailure),
          );
        }
        final finalState = resolveScrapeJobFinalState(
          pauseRequested: token.isPauseRequested,
          cancelRequested: token.isCancelRequested,
          resultCancelled: result.cancelled,
          partialSuccess: result.partialSuccess,
        );
        final diagnostic = finalState == ScrapeJobState.partial
            ? buildScrapeJobResultDiagnostic(result)
            : null;
        final counters = ScrapeJobTerminalCounters.fromResult(result);
        observer.stopAccepting();
        await observer.drain();
        await _queueWrite(() async {
          await observer!.completeRemaining(
            finalState == ScrapeJobState.cancelled
                ? ScrapeJobItemState.cancelled
                : finalState == ScrapeJobState.paused
                ? ScrapeJobItemState.queued
                : ScrapeJobItemState.succeeded,
          );
          await repository.updateJob(
            queued.id,
            state: finalState,
            phase: ScrapeJobPhase.completed,
            processedCount: counters.processed,
            savedCount: counters.saved,
            reviewCount: counters.review,
            excludedCount: counters.excluded,
            failedCount: counters.failed,
            imageFailureCount: counters.imageFailures,
            finishedAt: finalState == ScrapeJobState.paused
                ? null
                : DateTime.now().toUtc(),
            retryTargetCodes: const [],
            lastError: diagnostic,
            clearError: diagnostic == null,
          );
          await repository.appendEvent(
            queued.id,
            severity: finalState == ScrapeJobState.succeeded
                ? ScrapeJobEventSeverity.info
                : ScrapeJobEventSeverity.warning,
            stage: ScrapeJobPhase.completed,
            message: _resultMessage(finalState),
            metadata: {
              'saved': result.saved,
              'review': result.review,
              'excluded': result.excluded,
              'failed': result.failed,
              'image_failures': result.imageFailures.length,
            },
          );
          if (diagnostic != null) {
            await repository.appendEvent(
              queued.id,
              severity: result.failed > 0
                  ? ScrapeJobEventSeverity.error
                  : ScrapeJobEventSeverity.warning,
              stage: ScrapeJobPhase.completed,
              message: '刮削診斷：$diagnostic',
            );
          }
        });
      } finally {
        if (session.javBusTransport?.cookieHeader.isNotEmpty == true) {
          await db.setSetting(
            'javbus_cookies',
            session.javBusTransport!.cookieHeader,
          );
        }
        session.service.close();
      }
    } on Object catch (error) {
      observer?.stopAccepting();
      await observer?.drain();
      final verificationCancelled =
          error is JavBusVerificationCancelledException;
      final waiting =
          error is JavBusVerificationRequiredException ||
          (!verificationCancelled &&
              error.toString().toLowerCase().contains('verification'));
      final state = token.isPauseRequested
          ? ScrapeJobState.paused
          : token.isCancelRequested
          ? ScrapeJobState.cancelled
          : verificationCancelled
          ? ScrapeJobState.cancelled
          : waiting
          ? ScrapeJobState.waitingForVerification
          : ScrapeJobState.failed;
      workDataChanged = ScrapeJobRepository.terminalStates.contains(state);
      final safeError = ScrapeEventSanitizer.message(error);
      await _queueWrite(() async {
        await repository.updateJob(
          queued.id,
          state: state,
          phase: state == ScrapeJobState.waitingForVerification
              ? ScrapeJobPhase.collectingSources
              : ScrapeJobPhase.completed,
          lastError: state == ScrapeJobState.paused ? null : safeError,
          clearError: state == ScrapeJobState.paused,
          finishedAt:
              state == ScrapeJobState.paused ||
                  state == ScrapeJobState.waitingForVerification
              ? null
              : DateTime.now().toUtc(),
        );
        await repository.appendEvent(
          queued.id,
          severity: state == ScrapeJobState.failed
              ? ScrapeJobEventSeverity.error
              : ScrapeJobEventSeverity.warning,
          stage: ScrapeJobPhase.completed,
          message: verificationCancelled
              ? '來源驗證已取消，刮削工作已取消'
              : waiting
              ? '需要完成來源驗證後才能繼續'
              : safeError,
        );
      });
    } finally {
      _tokens.remove(queued.id);
      _emitChanged(workDataChanged: workDataChanged);
    }
  }

  Future<void> _persistControlState(
    String jobId,
    WorksScrapeCancellationToken token,
  ) async {
    final cancelled = token.isCancelRequested;
    await repository.updateJob(
      jobId,
      state: cancelled ? ScrapeJobState.cancelled : ScrapeJobState.paused,
      phase: ScrapeJobPhase.completed,
      finishedAt: cancelled ? DateTime.now().toUtc() : null,
      clearError: !cancelled,
    );
  }

  Future<void> _queueWrite(Future<void> Function() operation) {
    final next = _writeQueue.then((_) async {
      await operation();
      _scheduleChanged();
    });
    _writeQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _drainWrites() => _writeQueue;

  void _scheduleChanged() {
    if (_disposed || _notificationTimer != null) return;
    _notificationTimer = Timer(const Duration(milliseconds: 120), () {
      _notificationTimer = null;
      _emitChanged();
    });
  }

  int _workDataRevision = 0;

  int get workDataRevision => _workDataRevision;

  void _emitChanged({bool workDataChanged = false}) {
    if (_disposed) return;
    if (workDataChanged) _workDataRevision++;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    super.dispose();
  }

  String _resultMessage(ScrapeJobState state) => switch (state) {
    ScrapeJobState.succeeded => '刮削工作完成',
    ScrapeJobState.partial => '刮削工作部分完成',
    ScrapeJobState.cancelled => '刮削工作已取消',
    ScrapeJobState.paused => '刮削工作已暫停',
    _ => '刮削工作結束',
  };
}

class _JobObserver extends ScrapeRunObserver {
  _JobObserver(this.repository, this.jobId, this.writeFence);

  final ScrapeJobRepository repository;
  final String jobId;
  final ScrapeJobWriteFence writeFence;
  final _items = <String, ScrapeJobItem>{};
  final _progress = ScrapeJobProgressAccumulator();
  bool _progressSeeded = false;
  bool _accepting = true;
  ScrapeJobPhase? _lastPhase;
  String? _lastProgressKey;

  void stopAccepting() {
    _accepting = false;
    writeFence.stopAccepting();
  }

  Future<void> drain() => writeFence.drain();

  void _enqueue(Future<void> Function() operation) {
    if (!_accepting) return;
    writeFence.enqueue(operation);
  }

  Future<void> _ensureProgressState() async {
    if (_progressSeeded) return;
    final currentJob = await repository.get(jobId);
    if (currentJob != null) _progress.seed(currentJob);
    final items = await repository.listItems(jobId);
    _progress.seedItems(items);
    for (final item in items) {
      _items[item.canonicalCode] = item;
    }
    _progressSeeded = true;
  }

  @override
  void onProgress(WorksScrapeProgress progress) {
    final sourceKey = progress.sourceProgress.entries
        .map(
          (entry) =>
              '${entry.key.storageValue}:${entry.value.phase.name}:'
              '${entry.value.current}:${entry.value.total}:'
              '${entry.value.discovered}:${entry.value.workCode ?? ''}',
        )
        .join('|');
    final progressKey =
        '${progress.phase.name}:${progress.current}:'
        '${progress.total}:${progress.saved}:${progress.excluded}:'
        '${progress.failed}:${progress.rawDiscovered}:'
        '${progress.duplicateCount}:${progress.detailCompleted}:'
        '${progress.detailTotal}:${progress.review}:'
        '${progress.supplementalEvidenceCompleted}:'
        '${progress.supplementalEvidenceTotal}:$sourceKey';
    if (_lastProgressKey == progressKey) return;
    _lastProgressKey = progressKey;
    _enqueue(() async {
      await _ensureProgressState();
      _progress.apply(progress);
      await repository.updateJob(
        jobId,
        phase: _phase(progress.phase),
        discoveredCount: _progress.discoveredCount,
        rawDiscoveredCount: _progress.rawDiscoveredCount,
        duplicateCount: _progress.duplicateCount,
        detailCompletedCount: _progress.detailCompletedCount,
        detailTotalCount: _progress.detailTotalCount,
        processedCount: _progress.processedCount,
        savedCount: _progress.savedCount,
        excludedCount: _progress.excludedCount,
        failedCount: _progress.failedCount,
        reviewCount: _progress.reviewCount,
        supplementalEvidenceCompletedCount:
            _progress.supplementalEvidenceCompletedCount,
        supplementalEvidenceTotalCount:
            _progress.supplementalEvidenceTotalCount,
      );
      for (final entry in progress.sourceProgress.entries) {
        await repository.upsertSourceProgress(
          ScrapeJobSourceProgress(
            jobId: jobId,
            source: entry.key,
            phase: _phase(entry.value.phase),
            current: entry.value.current,
            total: entry.value.total,
            totalKnown: entry.value.totalKnown,
            workCode: entry.value.workCode,
            discovered: entry.value.discovered,
          ),
        );
      }
      if (_lastPhase != _phase(progress.phase)) {
        _lastPhase = _phase(progress.phase);
        await repository.appendEvent(
          jobId,
          severity: ScrapeJobEventSeverity.info,
          stage: _lastPhase!,
          message: '刮削階段：${_lastPhase!.storageValue}',
        );
      }
      if (progress.workCode != null && progress.workCode!.trim().isNotEmpty) {
        await _setItem(
          progress.workCode!,
          state: ScrapeJobItemState.running,
          stage: _phase(progress.phase),
        );
      }
    });
  }

  @override
  void onWorkDiscovered({
    required String canonicalCode,
    String? rawCode,
    required ScrapeSourceId source,
  }) {
    _enqueue(
      () => _setItem(
        canonicalCode,
        rawCode: rawCode,
        state: ScrapeJobItemState.queued,
        stage: ScrapeJobPhase.fetchingDetails,
      ),
    );
  }

  @override
  void onWorkAttemptStarted({
    required String code,
    required ScrapeSourceId source,
  }) {
    _enqueue(
      () => _setItem(
        code,
        state: ScrapeJobItemState.running,
        stage: ScrapeJobPhase.fetchingDetails,
      ),
    );
  }

  @override
  void onWorkCompleted({
    required String code,
    required ScrapeSourceId source,
    required String state,
    Object? error,
  }) {
    if (state != 'details_ready') return;
    _enqueue(
      () => _setItem(
        code,
        state: ScrapeJobItemState.running,
        stage: ScrapeJobPhase.resolvingWorks,
      ),
    );
  }

  @override
  void onWorkOutcome({
    required String code,
    required ScrapeSourceId source,
    required ScrapeWorkOutcomeState outcome,
    Object? error,
    String? reason,
    Iterable<String> imageFailureVariants = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final imageVariants = imageFailureVariants.toList(growable: false);
    final baseDiagnostic =
        error == null && reason == null && imageVariants.isEmpty
        ? null
        : error == null
        ? reason ?? '圖片下載失敗（${imageVariants.join('、')}）'
        : ScrapeEventSanitizer.message(error);
    final checkedSources = outcome == ScrapeWorkOutcomeState.review
        ? _checkedSourceLabels(metadata['evidenceSources'])
        : const <String>[];
    final diagnostic = baseDiagnostic == null || checkedSources.isEmpty
        ? baseDiagnostic
        : '$baseDiagnostic · 已檢查來源：${checkedSources.join('、')}';
    final itemState = switch (outcome) {
      ScrapeWorkOutcomeState.saved => ScrapeJobItemState.succeeded,
      ScrapeWorkOutcomeState.review => ScrapeJobItemState.review,
      ScrapeWorkOutcomeState.excluded => ScrapeJobItemState.excluded,
      ScrapeWorkOutcomeState.failed => ScrapeJobItemState.failed,
      ScrapeWorkOutcomeState.cancelled => ScrapeJobItemState.cancelled,
    };
    _enqueue(() async {
      await _ensureProgressState();
      _progress.recordOutcome(code, outcome);
      await _setItem(
        code,
        state: itemState,
        stage: ScrapeJobPhase.completed,
        lastError: diagnostic,
      );
      await repository.updateJob(
        jobId,
        discoveredCount: _progress.discoveredCount,
        processedCount: _progress.processedCount,
        savedCount: _progress.savedCount,
        excludedCount: _progress.excludedCount,
        failedCount: _progress.failedCount,
        reviewCount: _progress.reviewCount,
      );
      if (diagnostic != null || metadata.isNotEmpty) {
        await repository.appendEvent(
          jobId,
          severity: outcome == ScrapeWorkOutcomeState.failed
              ? ScrapeJobEventSeverity.error
              : diagnostic == null
              ? ScrapeJobEventSeverity.info
              : ScrapeJobEventSeverity.warning,
          stage: ScrapeJobPhase.completed,
          canonicalCode: code,
          source: source.storageValue,
          message: diagnostic ?? '作品 provenance 分類已記錄',
          metadata: metadata,
        );
      }
    });
  }

  List<String> _checkedSourceLabels(Object? rawSources) {
    if (rawSources is! Iterable) return const [];
    return rawSources
        .map((value) => _sourceLabel(value.toString()))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _sourceLabel(String source) {
    return switch (source) {
      'javbus' => 'JavBus',
      'avbase' => 'AVBase',
      'avwiki' => 'AV-Wiki',
      'minnanoAv' => 'Minnano AV',
      _ => source,
    };
  }

  Future<void> complete(
    String code, {
    required ScrapeJobItemState state,
    Object? error,
  }) {
    if (!_accepting) return Future<void>.value();
    return writeFence.enqueue(
      () => _setItem(
        code,
        state: state,
        stage: ScrapeJobPhase.completed,
        lastError: error == null ? null : ScrapeEventSanitizer.message(error),
      ),
    );
  }

  Future<void> completeRemaining(ScrapeJobItemState state) async {
    final items = await repository.listItems(jobId);
    for (final item in items) {
      if (item.state == ScrapeJobItemState.failed ||
          item.state == ScrapeJobItemState.excluded ||
          item.state == ScrapeJobItemState.succeeded ||
          item.state == ScrapeJobItemState.review) {
        continue;
      }
      await _setItem(
        item.canonicalCode,
        state: state,
        stage: state == ScrapeJobItemState.queued
            ? ScrapeJobPhase.queued
            : ScrapeJobPhase.completed,
      );
    }
  }

  @override
  void onSourceResult(ScrapeSourceRunResult result) {
    if (result.error == null) return;
    _enqueue(
      () => repository.appendEvent(
        jobId,
        severity: ScrapeJobEventSeverity.warning,
        stage: ScrapeJobPhase.collectingSources,
        source: result.source.storageValue,
        message: ScrapeEventSanitizer.message(result.error),
      ),
    );
  }

  @override
  void onError({required String stage, Object? error, String? code}) {
    final jobStage = stage == WorksScrapePhase.fetchingDetails.name
        ? ScrapeJobPhase.fetchingDetails
        : ScrapeJobPhase.savingWorks;
    _enqueue(
      () => repository.appendEvent(
        jobId,
        severity: ScrapeJobEventSeverity.error,
        stage: jobStage,
        canonicalCode: code,
        message: ScrapeEventSanitizer.message(error),
      ),
    );
  }

  Future<void> _setItem(
    String code, {
    String? rawCode,
    required ScrapeJobItemState state,
    required ScrapeJobPhase stage,
    String? lastError,
  }) async {
    await _ensureProgressState();
    final existing = _items[code];
    final item = ScrapeJobItem(
      id: existing?.id,
      jobId: jobId,
      canonicalCode: code,
      observedRawCode: rawCode ?? existing?.observedRawCode,
      state: state,
      stage: stage,
      attemptCount:
          (existing?.attemptCount ?? 0) +
          (state == ScrapeJobItemState.running ? 1 : 0),
      lastError: lastError,
      createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final id = await repository.upsertItem(item, existingId: existing?.id);
    _items[code] = ScrapeJobItem(
      id: id,
      jobId: item.jobId,
      canonicalCode: item.canonicalCode,
      observedRawCode: item.observedRawCode,
      state: item.state,
      stage: item.stage,
      attemptCount: item.attemptCount,
      lastError: item.lastError,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
  }

  ScrapeJobPhase _phase(WorksScrapePhase phase) => switch (phase) {
    WorksScrapePhase.collectingSources => ScrapeJobPhase.collectingSources,
    WorksScrapePhase.syncingActress => ScrapeJobPhase.syncingActress,
    WorksScrapePhase.fetchingDetails => ScrapeJobPhase.fetchingDetails,
    WorksScrapePhase.resolvingWorks => ScrapeJobPhase.resolvingWorks,
    WorksScrapePhase.savingWorks => ScrapeJobPhase.savingWorks,
    WorksScrapePhase.downloadingImages => ScrapeJobPhase.downloadingImages,
    WorksScrapePhase.completed => ScrapeJobPhase.completed,
  };
}
