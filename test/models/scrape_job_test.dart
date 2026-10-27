import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/models/scrape_job.dart';
import 'package:avaca/models/scrape_source_settings.dart';

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

  test('legacy removed source rows migrate to AV-Wiki', () {
    final progress = ScrapeJobSourceProgress.fromRow({
      'job_id': 'job-legacy',
      'source': 'minnanoAv',
      'phase': 'fetching_details',
      'current_value': 1,
      'total_value': 2,
      'total_known': 1,
    });
    expect(progress.source, ScrapeSourceId.avwiki);

    final event = ScrapeJobEvent.fromRow({
      'job_id': 'job-legacy',
      'source': 'minnanoAv',
      'severity': 'info',
      'stage': 'fetching_details',
      'message': 'legacy source event',
      'created_at': '2026-08-23T12:30:00Z',
    });
    expect(event.source, ScrapeSourceId.avwiki);
  });
}
