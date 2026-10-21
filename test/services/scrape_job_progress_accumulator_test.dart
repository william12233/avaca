import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/models/scrape_job.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/scrape_job_coordinator.dart';
import 'package:avaca/services/scrape_run_observer.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/works_scrape_service.dart';

void main() {
  test('progress remains monotonic when a phase reports from zero again', () {
    final accumulator = ScrapeJobProgressAccumulator();

    accumulator.apply(
      const WorksScrapeProgress(
        current: 0,
        total: 12,
        saved: 0,
        excluded: 0,
        failed: 0,
      ),
    );
    accumulator.apply(
      const WorksScrapeProgress(
        current: 4,
        total: 12,
        saved: 3,
        excluded: 1,
        failed: 0,
      ),
    );
    accumulator.apply(
      const WorksScrapeProgress(
        current: 0,
        total: 0,
        saved: 0,
        excluded: 0,
        failed: 0,
      ),
    );

    expect(accumulator.discoveredCount, 12);
    expect(accumulator.processedCount, 4);
    expect(accumulator.savedCount, 3);
    expect(accumulator.excludedCount, 1);
    expect(accumulator.failedCount, 0);
  });

  test('seeding keeps persisted progress before the next live event', () {
    final accumulator = ScrapeJobProgressAccumulator();
    accumulator.seed(
      ScrapeJob(
        id: 'job-1',
        actressId: 1,
        actressNameSnapshot: 'Test',
        state: ScrapeJobState.running,
        phase: ScrapeJobPhase.savingWorks,
        optionsSnapshot: '{}',
        sourceSettingsSnapshot: '{}',
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
        discoveredCount: 10,
        processedCount: 7,
        savedCount: 6,
        excludedCount: 1,
      ),
    );

    accumulator.apply(
      const WorksScrapeProgress(
        current: 0,
        total: 10,
        saved: 0,
        excluded: 0,
        failed: 0,
      ),
    );

    expect(accumulator.processedCount, 7);
    expect(accumulator.savedCount, 6);
    expect(accumulator.excludedCount, 1);
  });

  test('keeps canonical detail totals separate from supplemental evidence', () {
    final accumulator = ScrapeJobProgressAccumulator();
    accumulator.apply(
      const WorksScrapeProgress(
        current: 179,
        total: 179,
        saved: 0,
        excluded: 0,
        failed: 0,
        detailCompleted: 179,
        detailTotal: 179,
        supplementalEvidenceTotal: 69,
      ),
    );
    accumulator.apply(
      const WorksScrapeProgress(
        current: 179,
        total: 179,
        saved: 12,
        excluded: 0,
        failed: 0,
        detailCompleted: 179,
        detailTotal: 179,
        supplementalEvidenceCompleted: 42,
        supplementalEvidenceTotal: 69,
        review: 3,
      ),
    );

    expect(accumulator.discoveredCount, 179);
    expect(accumulator.detailCompletedCount, 179);
    expect(accumulator.detailTotalCount, 179);
    expect(accumulator.supplementalEvidenceCompletedCount, 42);
    expect(accumulator.supplementalEvidenceTotalCount, 69);
    expect(accumulator.savedCount, 12);
    expect(accumulator.reviewCount, 3);
  });

  test(
    'per-work outcomes prevent a reset progress snapshot from inflating counts',
    () {
      final accumulator = ScrapeJobProgressAccumulator();
      accumulator.apply(
        const WorksScrapeProgress(
          current: 0,
          total: 3,
          saved: 0,
          excluded: 1,
          failed: 0,
        ),
      );
      accumulator.recordOutcome('WORK-001', ScrapeWorkOutcomeState.saved);
      accumulator.apply(
        const WorksScrapeProgress(
          current: 0,
          total: 0,
          saved: 0,
          excluded: 0,
          failed: 0,
        ),
      );
      accumulator.recordOutcome('WORK-002', ScrapeWorkOutcomeState.failed);

      expect(accumulator.processedCount, 3);
      expect(accumulator.savedCount, 1);
      expect(accumulator.excludedCount, 1);
      expect(accumulator.failedCount, 1);
    },
  );

  test(
    'per-work outcomes are idempotent and cancelled work is not counted',
    () {
      final accumulator = ScrapeJobProgressAccumulator();

      accumulator.recordOutcome('WORK-001', ScrapeWorkOutcomeState.saved);
      accumulator.recordOutcome('WORK-001', ScrapeWorkOutcomeState.saved);
      accumulator.recordOutcome('WORK-001', ScrapeWorkOutcomeState.cancelled);
      accumulator.recordOutcome('WORK-002', ScrapeWorkOutcomeState.cancelled);
      accumulator.recordOutcome('WORK-002', ScrapeWorkOutcomeState.failed);
      accumulator.recordOutcome('WORK-002', ScrapeWorkOutcomeState.failed);

      expect(accumulator.processedCount, 2);
      expect(accumulator.savedCount, 1);
      expect(accumulator.excludedCount, 0);
      expect(accumulator.failedCount, 1);
    },
  );

  test(
    'write fence drains accepted events and rejects late observer events',
    () async {
      final trace = <String>[];
      final gate = Completer<void>();
      var tail = Future<void>.value();

      Future<void> enqueue(Future<void> Function() operation) {
        final next = tail.then((_) => operation());
        tail = next.catchError((_) {});
        return next;
      }

      final fence = ScrapeJobWriteFence(enqueue: enqueue, drain: () => tail);
      fence.enqueue(() async {
        trace.add('accepted-start');
        await gate.future;
        trace.add('accepted-end');
      });
      fence.stopAccepting();
      await fence.enqueue(() async => trace.add('late-event'));
      final terminal = fence.drain().then((_) => trace.add('terminal-write'));

      expect(trace, ['accepted-start']);
      gate.complete();
      await terminal;
      expect(trace, ['accepted-start', 'accepted-end', 'terminal-write']);
    },
  );

  test('terminal counters use the final scrape result as authority', () {
    final counters = ScrapeJobTerminalCounters.fromResult(
      const WorksScrapeResult(
        saved: 4,
        review: 1,
        excluded: 2,
        failed: 1,
        cancelled: false,
      ),
    );

    expect(counters.processed, 7);
    expect(counters.saved, 4);
    expect(counters.review, 1);
    expect(counters.excluded, 2);
    expect(counters.failed, 1);
    expect(counters.imageFailures, 0);
    expect(counters.cancelled, isFalse);
  });

  test('terminal cancellation remains authoritative over partial success', () {
    final counters = ScrapeJobTerminalCounters.fromResult(
      const WorksScrapeResult(
        saved: 2,
        excluded: 1,
        failed: 0,
        cancelled: true,
        partialSuccess: true,
      ),
    );

    expect(counters.cancelled, isTrue);
    expect(
      resolveScrapeJobFinalState(
        pauseRequested: false,
        cancelRequested: false,
        resultCancelled: counters.cancelled,
        partialSuccess: true,
      ),
      ScrapeJobState.cancelled,
    );
  });

  test(
    'partial diagnostic keeps failure reason and removes sensitive transport data',
    () {
      final diagnostic = buildScrapeJobResultDiagnostic(
        WorksScrapeResult(
          saved: 2,
          excluded: 0,
          failed: 1,
          cancelled: false,
          partialSuccess: true,
          sourceResults: const {
            ScrapeSourceId.javbus: ScrapeSourceRunResult(
              source: ScrapeSourceId.javbus,
              state: ScrapeSourceRunState.partial,
              error:
                  'Authorization: Bearer secret-token https://example.test/a?q=1',
            ),
          },
          failedWorks: const [
            WorksScrapeFailure(
              code: 'BAD-001',
              stage: WorksScrapeFailureStage.resolvingWorks,
              reason: WorksScrapeFailureReason.invalidCode,
            ),
          ],
        ),
      );

      expect(diagnostic, isNotNull);
      expect(diagnostic, contains('BAD-001'));
      expect(diagnostic, contains('invalidCode'));
      expect(diagnostic, isNot(contains('secret-token')));
      expect(diagnostic, isNot(contains('?q=')));
    },
  );

  test('partial diagnostics are bounded with a visible overflow marker', () {
    final diagnostic = buildScrapeJobResultDiagnostic(
      WorksScrapeResult(
        saved: 0,
        excluded: 0,
        failed: 20,
        cancelled: false,
        partialSuccess: true,
        failedWorks: List<WorksScrapeFailure>.generate(
          20,
          (index) => WorksScrapeFailure(
            code: 'BAD-${index + 1}',
            stage: WorksScrapeFailureStage.resolvingWorks,
            reason: WorksScrapeFailureReason.invalidCode,
          ),
        ),
      ),
    );

    final lines = diagnostic!.split('\n');
    expect(lines.length, 13);
    expect(lines.last, contains('其餘 8 筆診斷'));
  });
}
