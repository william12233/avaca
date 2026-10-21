import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_job.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/services/scrape_job_repository.dart';

void main() {
  sqfliteFfiInit();

  test('operational schema is idempotent and recovers running jobs', () async {
    final directory = await Directory.systemTemp.createTemp('avaca-job-test-');
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    try {
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
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
      );
      final database = await db.database;
      await database.update(
        'scrape_jobs',
        {'state': ScrapeJobState.running.storageValue},
        where: 'id = ?',
        whereArgs: [job.id],
      );

      await db.close();
      final reopenedDb = AppDatabase.forTesting(
        baseDir: directory.path,
        databaseFactory: databaseFactoryFfi,
      );
      try {
        await reopenedDb.init();
        final reopenedRepository = ScrapeJobRepository(db: reopenedDb);
        await reopenedRepository.recoverInterruptedJobs();

        expect(
          (await reopenedRepository.get(job.id))?.state,
          ScrapeJobState.queued,
        );
      } finally {
        await reopenedDb.close();
      }
    } finally {
      await db.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test('work provenance is returned with work details', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca-provenance-test-',
    );
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    try {
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
      final workId = await db.upsertActressWork(
        actressId: actressId,
        work: const Work(code: 'ABC-1', title: 'A title'),
        provenance: const [
          WorkFieldProvenance(workId: 0, field: 'title', source: 'javbus'),
        ],
      );

      final work = await db.getWorkById(workId);
      expect(work?['field_provenance'], isNotEmpty);
    } finally {
      await db.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test('deletes terminal jobs as an all-or-nothing batch', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca-job-delete-test-',
    );
    final db = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    try {
      await db.init();
      await db.addActress(name: 'Terminal Actress');
      await db.addActress(name: 'Active Actress');
      final actressRows = await (await db.database).query(
        'actresses',
        columns: const ['id', 'name'],
      );
      final terminalActressId =
          actressRows.singleWhere(
                (row) => row['name'] == 'Terminal Actress',
              )['id']
              as int;
      final activeActressId =
          actressRows.singleWhere(
                (row) => row['name'] == 'Active Actress',
              )['id']
              as int;
      final repository = ScrapeJobRepository(db: db);
      final terminalJob = await repository.create(
        actressId: terminalActressId,
        actressName: 'Terminal Actress',
        optionsSnapshot: '{}',
        sourceSettingsSnapshot: '{}',
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
      );
      await repository.updateJob(
        terminalJob.id,
        state: ScrapeJobState.succeeded,
        phase: ScrapeJobPhase.completed,
        finishedAt: DateTime.now().toUtc(),
      );
      final activeJob = await repository.create(
        actressId: activeActressId,
        actressName: 'Active Actress',
        optionsSnapshot: '{}',
        sourceSettingsSnapshot: '{}',
        rulesVersionSnapshot: 'builtin-1',
        rulesSnapshot: '{}',
      );

      await expectLater(
        repository.deleteTerminalJobs([terminalJob.id, activeJob.id]),
        throwsStateError,
      );
      expect(await repository.get(terminalJob.id), isNotNull);
      expect(await repository.get(activeJob.id), isNotNull);

      await repository.deleteTerminalJobs([terminalJob.id]);
      expect(await repository.get(terminalJob.id), isNull);
      expect(await repository.listEvents(terminalJob.id), isEmpty);
      expect(await repository.get(activeJob.id), isNotNull);
    } finally {
      await db.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test(
    'concurrent enqueue is idempotent and FIFO selects the oldest',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca-job-fifo-test-',
      );
      final db = AppDatabase.forTesting(
        baseDir: directory.path,
        databaseFactory: databaseFactoryFfi,
      );
      try {
        await db.init();
        await db.addActress(name: 'First Actress');
        await db.addActress(name: 'Second Actress');
        final rows = await (await db.database).query(
          'actresses',
          columns: const ['id', 'name'],
        );
        final firstId =
            rows.singleWhere((row) => row['name'] == 'First Actress')['id']
                as int;
        final secondId =
            rows.singleWhere((row) => row['name'] == 'Second Actress')['id']
                as int;
        final repository = ScrapeJobRepository(db: db);
        final concurrent = await Future.wait([
          repository.create(
            actressId: firstId,
            actressName: 'First Actress',
            optionsSnapshot: '{}',
            sourceSettingsSnapshot: '{}',
            rulesVersionSnapshot: 'builtin-1',
            rulesSnapshot: '{}',
          ),
          repository.create(
            actressId: firstId,
            actressName: 'First Actress',
            optionsSnapshot: '{}',
            sourceSettingsSnapshot: '{}',
            rulesVersionSnapshot: 'builtin-1',
            rulesSnapshot: '{}',
          ),
        ]);
        expect(concurrent[0].id, concurrent[1].id);
        expect(
          (await repository.list(
            actressId: firstId,
          )).where((job) => job.isActive),
          hasLength(1),
        );
        expect(await repository.listEvents(concurrent[0].id), hasLength(1));

        await Future<void>.delayed(const Duration(milliseconds: 2));
        final second = await repository.create(
          actressId: secondId,
          actressName: 'Second Actress',
          optionsSnapshot: '{}',
          sourceSettingsSnapshot: '{}',
          rulesVersionSnapshot: 'builtin-1',
          rulesSnapshot: '{}',
        );
        expect((await repository.nextQueued())?.id, concurrent[0].id);
        await repository.updateJob(
          concurrent[0].id,
          state: ScrapeJobState.succeeded,
        );
        expect((await repository.nextQueued())?.id, second.id);
      } finally {
        await db.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );
}
