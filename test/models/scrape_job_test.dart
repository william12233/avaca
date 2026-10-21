import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/models/scrape_job.dart';

void main() {
  test('job row round trip keeps stable lifecycle values', () {
    final now = DateTime.utc(2026, 8, 23, 12, 30);
    final job = ScrapeJob(
      id: 'job-1',
      actressId: 7,
      actressNameSnapshot: 'Example',
      state: ScrapeJobState.waitingForVerification,
      phase: ScrapeJobPhase.fetchingDetails,
      optionsSnapshot: '{"fillMissingOnly":true}',
      sourceSettingsSnapshot: '{"worksSource":"javbus"}',
      rulesVersionSnapshot: 'rules-3',
      rulesSnapshot: '{"schemaVersion":1}',
      retryTargetCodes: const ['ABC-123'],
      discoveredCount: 4,
      processedCount: 2,
      savedCount: 1,
      failedCount: 1,
      createdAt: now,
      updatedAt: now,
    );

    final decoded = ScrapeJob.fromRow(job.toRow());

    expect(decoded.id, job.id);
    expect(decoded.state, ScrapeJobState.waitingForVerification);
    expect(decoded.phase, ScrapeJobPhase.fetchingDetails);
    expect(decoded.retryTargetCodes, ['ABC-123']);
    expect(decoded.savedCount, 1);
  });

  test('terminal states are not active', () {
    expect(
      ScrapeJob(
        id: 'job-2',
        actressId: 1,
        actressNameSnapshot: 'A',
        state: ScrapeJobState.failed,
        phase: ScrapeJobPhase.completed,
        optionsSnapshot: '{}',
        sourceSettingsSnapshot: '{}',
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
      ).isActive,
      isFalse,
    );
  });
}
