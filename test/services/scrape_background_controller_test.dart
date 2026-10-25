import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_job.dart';
import 'package:avaca/services/scrape_background_controller.dart';
import 'package:avaca/services/scrape_job_coordinator.dart';
import 'package:avaca/services/scrape_job_repository.dart';

void main() {
  sqfliteFfiInit();

  test('uses indeterminate progress when a phase has no known total', () {
    final progress = scrapeNotificationProgressFor(
      _job(
        phase: ScrapeJobPhase.collectingSources,
        detailCompletedCount: 4,
        detailTotalCount: 0,
      ),
    );

    expect(progress.percent, isNull);
    expect(progress.indeterminate, isTrue);
  });

  test('maps detail progress to a bounded percentage', () {
    expect(
      scrapeNotificationProgressFor(
        _job(
          phase: ScrapeJobPhase.fetchingDetails,
          detailCompletedCount: 3,
          detailTotalCount: 8,
        ),
      ).percent,
      37,
    );
    expect(
      scrapeNotificationProgressFor(
        _job(
          phase: ScrapeJobPhase.resolvingWorks,
          detailCompletedCount: 20,
          detailTotalCount: 8,
        ),
      ).percent,
      100,
    );
  });

  test('maps saving progress from processed works', () {
    expect(
      scrapeNotificationProgressFor(
        _job(
          phase: ScrapeJobPhase.savingWorks,
          discoveredCount: 4,
          processedCount: 2,
        ),
      ).percent,
      50,
    );
  });

  test('starts and stops the foreground host with the job lifecycle', () async {
    final fixture = await _JobFixture.create();
    try {
      final host = _FakeScrapeBackgroundHost();
      final controller = ScrapeBackgroundController(
        coordinator: fixture.coordinator,
        host: host,
      );

      await controller.synchronize();
      expect(host.started, hasLength(1));
      expect(host.started.single.jobId, fixture.job.id);
      expect(host.permissionRequestCount, 1);

      await fixture.repository.updateJob(
        fixture.job.id,
        state: ScrapeJobState.succeeded,
        phase: ScrapeJobPhase.completed,
      );
      await controller.synchronize();

      expect(host.stopCount, 1);
      controller.dispose();
    } finally {
      await fixture.dispose();
    }
  });

  test(
    'shows one attention notification when verification is required',
    () async {
      final fixture = await _JobFixture.create();
      try {
        final host = _FakeScrapeBackgroundHost();
        final controller = ScrapeBackgroundController(
          coordinator: fixture.coordinator,
          host: host,
        );

        await fixture.repository.updateJob(
          fixture.job.id,
          state: ScrapeJobState.waitingForVerification,
        );
        await controller.synchronize();
        await controller.synchronize();

        expect(host.verificationNotifications, hasLength(1));
        expect(host.verificationNotifications.single.jobId, fixture.job.id);
        expect(host.stopCount, 0);
        controller.dispose();
      } finally {
        await fixture.dispose();
      }
    },
  );
}

class _FakeScrapeBackgroundHost implements ScrapeBackgroundHost {
  final started = <ScrapeNotificationPayload>[];
  final updates = <ScrapeNotificationPayload>[];
  final verificationNotifications = <ScrapeNotificationPayload>[];
  int permissionRequestCount = 0;
  int stopCount = 0;

  @override
  Stream<String> get notificationTaps => const Stream<String>.empty();

  @override
  Future<void> requestNotificationPermission() async {
    permissionRequestCount++;
  }

  @override
  Future<void> start(ScrapeNotificationPayload payload) async {
    started.add(payload);
  }

  @override
  Future<void> update(ScrapeNotificationPayload payload) async {
    updates.add(payload);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> showVerificationNotification(
    ScrapeNotificationPayload payload,
  ) async {
    verificationNotifications.add(payload);
  }

  @override
  Future<String?> consumePendingJobId() async => null;

  @override
  Future<void> dispose() async {}
}

class _JobFixture {
  _JobFixture({
    required this.directory,
    required this.db,
    required this.repository,
    required this.coordinator,
    required this.job,
  });

  final Directory directory;
  final AppDatabase db;
  final ScrapeJobRepository repository;
  final ScrapeJobCoordinator coordinator;
  final ScrapeJob job;

  static Future<_JobFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca-background-job-test-',
    );
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    await db.init();
    await db.addActress(name: 'Test Actress');
    final actressId =
        (await (await db.database).query(
              'actresses',
              columns: const ['id'],
              where: 'name = ?',
              whereArgs: const ['Test Actress'],
            )).single['id']
            as int;
    final repository = ScrapeJobRepository(db: db);
    final job = await repository.create(
      actressId: actressId,
      actressName: 'Test Actress',
      optionsSnapshot: '{}',
      sourceSettingsSnapshot: '{}',
      rulesVersionSnapshot: 'test',
      rulesSnapshot: '{}',
    );
    return _JobFixture(
      directory: directory,
      db: db,
      repository: repository,
      coordinator: ScrapeJobCoordinator(db: db),
      job: job,
    );
  }

  Future<void> dispose() async {
    coordinator.dispose();
    await db.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

ScrapeJob _job({
  required ScrapeJobPhase phase,
  int discoveredCount = 0,
  int processedCount = 0,
  int detailCompletedCount = 0,
  int detailTotalCount = 0,
}) {
  return ScrapeJob(
    id: 'job-1',
    actressId: 1,
    actressNameSnapshot: 'Test Actress',
    state: ScrapeJobState.running,
    phase: phase,
    optionsSnapshot: '{}',
    sourceSettingsSnapshot: '{}',
    rulesVersionSnapshot: 'test',
    rulesSnapshot: '{}',
    discoveredCount: discoveredCount,
    processedCount: processedCount,
    detailCompletedCount: detailCompletedCount,
    detailTotalCount: detailTotalCount,
  );
}
