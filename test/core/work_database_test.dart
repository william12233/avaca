import 'dart:async';
import 'dart:io';

import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/models/work_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('work persistence', () {
    late _DatabaseFixture fixture;
    late AppDatabase database;
    late int actressId;

    setUp(() async {
      fixture = await _DatabaseFixture.create();
      database = fixture.openAppDatabase();
      await database.init();
      await database.addActress(name: '涼森れむ');
      final sqlite = await database.database;
      actressId =
          (await sqlite.query(
                'actresses',
                columns: ['id'],
                where: 'name = ?',
                whereArgs: ['涼森れむ'],
              )).single['id']
              as int;
    });

    tearDown(() => fixture.dispose());

    test('creates work tables and round-trips rows for an actress', () async {
      final workId = await database.upsertActressWork(
        actressId: actressId,
        work: const Work(
          code: 'ABF-183',
          title: '作品標題',
          releaseDate: '2024-07-16',
          durationMinutes: 120,
          studio: 'プレステージ',
          publisher: 'ABS',
          series: '系列',
          cardImagePath: 'images/abf-183-card.jpg',
          detailImagePath: 'images/abf-183-detail.jpg',
        ),
      );

      expect(await database.getWorkCountForActress(actressId), 1);
      expect(await database.getWorksForActress(actressId), [
        {
          'id': workId,
          'code': 'ABF-183',
          'title': '作品標題',
          'release_date': '2024-07-16',
          'duration_minutes': 120,
          'studio': 'プレステージ',
          'publisher': 'ABS',
          'series': '系列',
          'card_image_path': 'images/abf-183-card.jpg',
          'detail_image_path': 'images/abf-183-detail.jpg',
          'is_stored': 0,
          'storage_quality': null,
          'storage_frame_rate': null,
        },
      ]);
      expect(
        await database.getWorkById(workId),
        containsPair('code', 'ABF-183'),
      );
    });

    test(
      'persists the work storage record with quality and frame rate',
      () async {
        final workId = await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'STORE-001', title: '儲存測試作品'),
        );

        await database.updateWorkStorage(
          workId: workId,
          record: const WorkStorageRecord(
            isStored: true,
            quality: '2K',
            frameRate: 30,
          ),
        );

        final row = await database.getWorkById(workId);
        expect(row?['is_stored'], 1);
        expect(row?['storage_quality'], '2K');
        expect(row?['storage_frame_rate'], 30);
      },
    );

    test(
      'stores source-scoped performers and resolves canonical names and aliases',
      () async {
        await database.addActress(name: '谷村凪咲');
        await database.addActress(name: '另一位女優');
        final sqlite = await database.database;
        final rows = await sqlite.query(
          'actresses',
          columns: ['id', 'name'],
          orderBy: 'id ASC',
        );
        final canonicalId =
            rows.singleWhere((row) => row['name'] == '谷村凪咲')['id'] as int;
        final aliasOwnerId =
            rows.singleWhere((row) => row['name'] == '另一位女優')['id'] as int;
        await database.replaceActressAliases(
          actressId: aliasOwnerId,
          aliases: const ['谷村別名', '重名'],
        );
        await database.replaceActressAliases(
          actressId: actressId,
          aliases: const ['重名'],
        );

        final workId = await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'MULTI-001', title: '多人作品'),
          performerSource: 'javbus',
          performers: [
            WorkPerformer(
              name: '涼森れむ',
              sourceUri: Uri.parse('https://www.javbus.com/star/remu'),
            ),
            WorkPerformer(
              name: '谷村凪咲',
              sourceUri: Uri.parse('https://www.javbus.com/star/tanimura'),
            ),
            WorkPerformer(
              name: '谷村別名',
              sourceUri: Uri.parse('https://www.javbus.com/star/alias'),
            ),
            const WorkPerformer(name: '重名'),
            const WorkPerformer(name: '重名'),
          ],
        );
        await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'MULTI-001', title: '多人作品'),
          performerSource: 'other',
          performers: const [WorkPerformer(name: '其他來源演員')],
        );

        final first = await database.getWorkById(workId);
        final performers = (first?['related_performers']! as List)
            .cast<Map<String, Object?>>();
        expect(performers, hasLength(5));
        expect(
          performers.map((performer) => performer['name']),
          containsAll(['涼森れむ', '谷村凪咲', '谷村別名', '重名', '其他來源演員']),
        );
        expect(
          performers.singleWhere(
            (performer) => performer['name'] == '涼森れむ',
          )['actress_id'],
          actressId,
        );
        expect(
          performers.singleWhere(
            (performer) => performer['name'] == '谷村凪咲',
          )['actress_id'],
          canonicalId,
        );
        expect(
          performers.singleWhere(
            (performer) => performer['name'] == '谷村別名',
          )['actress_id'],
          aliasOwnerId,
        );
        expect(
          performers.singleWhere(
            (performer) => performer['name'] == '重名',
          )['actress_id'],
          isNull,
        );
        expect(
          performers.singleWhere(
            (performer) => performer['name'] == '其他來源演員',
          )['source'],
          'other',
        );

        await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'MULTI-001', title: '多人作品'),
          performerSource: 'javbus',
          performers: const [],
        );
        final afterClear = await database.getWorkById(workId);
        final remaining = (afterClear?['related_performers']! as List)
            .cast<Map<String, Object?>>();
        expect(remaining, hasLength(1));
        expect(remaining.single['name'], '其他來源演員');

        await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'MULTI-001', title: '多人作品'),
          performerSource: 'other',
          performers: null,
        );
        expect(
          ((await database.getWorkById(workId))!['related_performers']! as List)
              .cast<Map<String, Object?>>(),
          hasLength(1),
        );

        await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'MULTI-001', title: '多人作品'),
          performerSource: 'javbus',
          performers: const [
            WorkPerformer(name: '涼森れむ'),
            WorkPerformer(name: '重名'),
            WorkPerformer(name: '谷村凪咲'),
          ],
        );
        final currentActressView = await database.getWorkById(
          workId,
          currentActressId: actressId,
        );
        final currentActressPerformers =
            (currentActressView?['related_performers']! as List)
                .cast<Map<String, Object?>>();
        expect(
          currentActressPerformers.map((performer) => performer['name']),
          containsAll(['谷村凪咲', '其他來源演員']),
        );
        expect(
          currentActressPerformers.map((performer) => performer['name']),
          isNot(contains('涼森れむ')),
        );
        expect(
          currentActressPerformers.map((performer) => performer['name']),
          isNot(contains('重名')),
        );
      },
    );

    test(
      'deduplicates codes and actress links without case sensitivity',
      () async {
        final firstId = await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'ABF-183', title: 'first'),
        );
        final secondId = await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'abf-183', title: 'second'),
        );

        expect(secondId, firstId);
        expect(await database.getWorkCountForActress(actressId), 1);
        expect((await database.getWorkById(firstId))?['title'], 'second');
      },
    );

    test(
      'missing-only upsert fills blanks and preserves existing values',
      () async {
        final workId = await database.upsertActressWork(
          actressId: actressId,
          work: const Work(
            code: 'SONE-833',
            title: 'original',
            studio: 'existing studio',
          ),
        );

        await database.upsertActressWork(
          actressId: actressId,
          missingOnly: true,
          work: const Work(
            code: 'sone-833',
            title: 'replacement',
            studio: '',
            series: 'new series',
          ),
        );

        final row = await database.getWorkById(workId);
        expect(row?['title'], 'original');
        expect(row?['studio'], 'existing studio');
        expect(row?['series'], 'new series');
      },
    );

    test(
      'normal upsert never clears stored values with empty source data',
      () async {
        final workId = await database.upsertActressWork(
          actressId: actressId,
          work: const Work(
            code: 'SONE-833',
            title: 'original',
            series: 'existing series',
          ),
        );

        await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'SONE-833', title: 'replacement', series: ''),
        );

        final row = await database.getWorkById(workId);
        expect(row?['title'], 'replacement');
        expect(row?['series'], 'existing series');
      },
    );

    test('stores normalized actress aliases per actress', () async {
      await database.addActress(name: '另一位女優');
      final sqlite = await database.database;
      final otherActressId =
          (await sqlite.query(
                'actresses',
                columns: ['id'],
                where: 'name = ?',
                whereArgs: ['另一位女優'],
              )).single['id']
              as int;

      await database.replaceActressAliases(
        actressId: actressId,
        aliases: const ['  Remu  ', 'Remu', '涼森れむ', ''],
      );
      await database.replaceActressAliases(
        actressId: otherActressId,
        aliases: const ['Remu'],
      );

      expect(
        (await sqlite.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'actress_aliases'",
        )),
        hasLength(1),
      );
      expect(await database.getActressAliases(actressId), ['Remu']);
      expect(await database.getActressAliases(otherActressId), ['Remu']);

      await database.replaceActressAliases(
        actressId: actressId,
        aliases: const ['新別名'],
      );
      expect(await database.getActressAliases(actressId), ['新別名']);
      expect(await database.getActressAliases(otherActressId), ['Remu']);
    });

    test(
      'canonical rename removes the matching alias and actress delete cascades',
      () async {
        await database.replaceActressAliases(
          actressId: actressId,
          aliases: const ['舊別名', '新主藝名'],
        );

        expect(
          await database.updateActress(actressId: actressId, name: '新主藝名'),
          isTrue,
        );
        expect(await database.getActressAliases(actressId), ['舊別名']);

        expect(await database.deleteActress(actressId), isTrue);
        final sqlite = await database.database;
        expect(
          await sqlite.query(
            'actress_aliases',
            where: 'actress_id = ?',
            whereArgs: [actressId],
          ),
          isEmpty,
        );
      },
    );

    test('empty or unknown work deletion is a non-committed no-op', () async {
      final empty = await database.deleteWorksWithReport(const []);
      final unknown = await database.deleteWorksWithReport(const [999999]);

      expect(empty.databaseCommitted, isFalse);
      expect(empty.deletedWorkRows, 0);
      expect(unknown.databaseCommitted, isFalse);
      expect(unknown.deletedWorkIds, isEmpty);
      expect(await database.getActressById(actressId), isNotNull);
    });

    test('deletes selections larger than one SQLite bind batch', () async {
      final sqlite = await database.database;
      final batch = sqlite.batch();
      for (var index = 0; index < 501; index++) {
        batch.insert('works', {
          'code': 'BATCH-$index',
          'title': 'Batch work $index',
        });
      }
      await batch.commit(noResult: true);
      final workIds = (await sqlite.query(
        'works',
        columns: ['id'],
      )).map((row) => row['id'] as int).toList(growable: false);
      final relationBatch = sqlite.batch();
      for (final workId in workIds) {
        relationBatch.insert('actress_works', {
          'actress_id': actressId,
          'work_id': workId,
        });
      }
      await relationBatch.commit(noResult: true);

      final report = await database.deleteWorksWithReport(workIds);

      expect(report.databaseCommitted, isTrue);
      expect(report.deletedWorkRows, 501);
      expect(report.deletedActressWorkRows, 501);
      expect(await sqlite.query('works'), isEmpty);
      expect(await sqlite.query('actress_works'), isEmpty);
    });

    test(
      'deletes selected works globally and preserves files still referenced by another work',
      () async {
        await database.addActress(name: '共同演出女優');
        final sqlite = await database.database;
        final otherActressId =
            (await sqlite.query(
                  'actresses',
                  columns: ['id'],
                  where: 'name = ?',
                  whereArgs: ['共同演出女優'],
                )).single['id']
                as int;
        final sharedCard = File(
          path.join(database.imgDir, 'works', 'shared-card.jpg'),
        );
        final sharedDetail = File(
          path.join(database.imgDir, 'works', 'shared-detail.jpg'),
        );
        final onlyCard = File(
          path.join(database.imgDir, 'works', 'only-card.jpg'),
        );
        final onlyDetail = File(
          path.join(database.imgDir, 'works', 'only-detail.jpg'),
        );
        await sharedCard.parent.create(recursive: true);
        await sharedCard.writeAsString('shared card');
        await sharedDetail.writeAsString('shared detail');
        await onlyCard.writeAsString('only card');
        await onlyDetail.writeAsString('only detail');

        final selectedShared = await database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'GLOBAL-SHARED',
            title: '共同作品',
            cardImagePath: sharedCard.path,
            detailImagePath: sharedDetail.path,
          ),
        );
        await database.upsertActressWork(
          actressId: otherActressId,
          work: Work(
            code: 'GLOBAL-SHARED',
            title: '共同作品',
            cardImagePath: sharedCard.path,
            detailImagePath: sharedDetail.path,
          ),
        );
        final selectedOnly = await database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'GLOBAL-ONLY',
            title: '單一作品',
            cardImagePath: onlyCard.path,
            detailImagePath: onlyDetail.path,
          ),
        );
        final retained = await database.upsertActressWork(
          actressId: otherActressId,
          work: Work(
            code: 'GLOBAL-RETAINED',
            title: '保留作品',
            cardImagePath: sharedCard.path,
            detailImagePath: sharedDetail.path,
          ),
        );

        final report = await database.deleteWorksWithReport([
          selectedShared,
          selectedOnly,
        ]);

        expect(report.databaseCommitted, isTrue);
        expect(report.requestedWorkIds, [selectedShared, selectedOnly]);
        expect(
          report.deletedWorkIds,
          containsAll([selectedShared, selectedOnly]),
        );
        expect(report.deletedWorkRows, 2);
        expect(report.deletedActressWorkRows, 3);
        expect(await database.getWorkById(selectedShared), isNull);
        expect(await database.getWorkById(selectedOnly), isNull);
        expect(await database.getWorkById(retained), isNotNull);
        expect(await database.getWorksForActress(actressId), isEmpty);
        expect(
          (await database.getWorksForActress(otherActressId)).single['code'],
          'GLOBAL-RETAINED',
        );
        expect(onlyCard.existsSync(), isFalse);
        expect(onlyDetail.existsSync(), isFalse);
        expect(sharedCard.existsSync(), isTrue);
        expect(sharedDetail.existsSync(), isTrue);
        expect(report.fileCleanup.deleted, contains(onlyCard.path));
        expect(report.fileCleanup.deleted, contains(onlyDetail.path));
        expect(report.fileCleanup.deleted, isNot(contains(sharedCard.path)));
        expect(report.fileCleanup.deleted, isNot(contains(sharedDetail.path)));
      },
    );

    test(
      'scraped actress sync never changes weight and gates image replacement',
      () async {
        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {
            'img_path': 'old.jpg',
            'height': '',
            'weight': '48',
            'bwh': 'B80 / W55 / H82',
            'cup': 'C',
          },
          where: 'id = ?',
          whereArgs: [actressId],
        );

        await database.syncActressDetails(
          actressId: actressId,
          missingOnly: true,
          details: const ScrapedActressDetails(
            name: '新名稱',
            imagePath: 'new.jpg',
            birthDate: '1997-12-03',
            height: '160',
            cup: 'D',
            bust: '87',
            waist: '58',
            hip: '85',
          ),
        );

        var actress = await database.getActressById(actressId);
        expect(actress?['name'], '涼森れむ');
        expect(actress?['img_path'], 'old.jpg');
        expect(actress?['height'], '160');
        expect(actress?['weight'], '48');
        expect(actress?['bwh'], 'B80 / W55 / H82');
        expect(actress?['cup'], 'C');
        expect(actress?['birth_date'], '1997-12-03');

        await database.syncActressDetails(
          actressId: actressId,
          missingOnly: true,
          replaceImage: true,
          details: const ScrapedActressDetails(imagePath: 'new.jpg'),
        );
        actress = await database.getActressById(actressId);
        expect(actress?['img_path'], 'new.jpg');
        expect(actress?['weight'], '48');
      },
    );

    test(
      'standalone work upsert does not create an actress relation',
      () async {
        final workId = await database.upsertWork(
          const Work(code: 'ABF-200', title: 'standalone'),
        );

        expect(await database.getWorkById(workId), isNotNull);
        expect(await database.getWorkCountForActress(actressId), 0);
      },
    );

    test(
      'normal actress sync updates provided fields but not weight',
      () async {
        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {'weight': '48', 'img_path': 'old.jpg'},
          where: 'id = ?',
          whereArgs: [actressId],
        );

        expect(
          await database.syncActressDetails(
            actressId: actressId,
            details: const ScrapedActressDetails(
              name: '涼森れむ（更新）',
              imagePath: 'ignored.jpg',
              height: '161',
              cup: 'E',
              bust: '88',
              waist: '59',
              hip: '86',
            ),
          ),
          isTrue,
        );

        final actress = await database.getActressById(actressId);
        expect(actress?['name'], '涼森れむ（更新）');
        expect(actress?['img_path'], 'old.jpg');
        expect(actress?['height'], '161');
        expect(actress?['weight'], '48');
        expect(actress?['bwh'], 'B88 / W59 / H86');
        expect(actress?['cup'], 'E');
      },
    );

    test(
      'invalid scraped birthday does not discard other profile fields',
      () async {
        expect(
          await database.syncActressDetails(
            actressId: actressId,
            details: const ScrapedActressDetails(
              birthDate: '未知',
              height: '162',
              cup: 'F',
            ),
          ),
          isTrue,
        );

        final actress = await database.getActressById(actressId);
        expect(actress?['birth_date'], isNull);
        expect(actress?['height'], '162');
        expect(actress?['cup'], 'F');
      },
    );

    test(
      'deleting an actress removes its image and unshared work data',
      () async {
        final actressImage = File(
          '${database.imgDir}${Platform.pathSeparator}actress.jpg',
        );
        final cardImage = File(
          path.join(database.imgDir, 'works', 'sone-900-card.jpg'),
        );
        final detailImage = File(
          path.join(database.imgDir, 'works', 'sone-900-detail.jpg'),
        );
        await cardImage.parent.create(recursive: true);
        await actressImage.writeAsString('actress');
        await cardImage.writeAsString('card');
        await detailImage.writeAsString('detail');

        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {'img_path': actressImage.path},
          where: 'id = ?',
          whereArgs: [actressId],
        );
        final workId = await database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'SONE-900',
            title: 'unshared',
            cardImagePath: cardImage.path,
            detailImagePath: detailImage.path,
          ),
        );

        final beforeTables = await _tableCounts(sqlite);
        final beforeImages = await _managedImageStats(
          Directory(database.imgDir),
        );
        final report = await database.deleteActressWithReport(actressId);

        expect(report.databaseCommitted, isTrue);
        expect(report.beforeTableCounts, beforeTables);
        expect(
          report.beforeManagedImageStats.fileCount,
          beforeImages.fileCount,
        );
        expect(
          report.beforeManagedImageStats.totalBytes,
          beforeImages.totalBytes,
        );
        expect(report.afterTableCounts, {
          'actresses': 0,
          'works': 0,
          'actress_works': 0,
          'pending_file_deletions': 0,
        });
        expect(report.afterManagedImageStats.fileCount, 0);
        expect(report.afterManagedImageStats.totalBytes, 0);
        expect(report.fileCleanup.deletedCount, 3);
        expect(report.deletedBytes, beforeImages.totalBytes);
        expect(report.fileCleanup.rejectedCount, 0);
        expect(report.fileCleanup.deferredCount, 0);
        expect(
          report.fileCleanup.deleted,
          containsAll([actressImage.path, cardImage.path, detailImage.path]),
        );
        expect(await database.getActressById(actressId), isNull);
        expect(await sqlite.query('actress_works'), isEmpty);
        expect(await database.getWorkById(workId), isNull);
        expect(actressImage.existsSync(), isFalse);
        expect(cardImage.existsSync(), isFalse);
        expect(detailImage.existsSync(), isFalse);
        expect(
          Directory(path.join(database.imgDir, 'works')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'deletion report snapshots the actual Android managed root before rows are removed',
      () async {
        await database.close();
        final documentsDirectory = Directory(
          path.join(fixture.directory.path, 'application-documents'),
        );
        database = fixture.openAppDatabase(
          baseDir: path.join(documentsDirectory.path, 'avaca_data'),
        );
        await database.init();
        await database.addActress(name: 'diagnostic actress');
        final sqlite = await database.database;
        final diagnosticActressId =
            (await sqlite.query(
                  'actresses',
                  columns: ['id'],
                  where: 'name = ?',
                  whereArgs: ['diagnostic actress'],
                )).single['id']
                as int;
        final avatar = File(
          path.join(
            database.imgDir,
            'scraped',
            'actresses',
            'diagnostic-avatar.jpg',
          ),
        );
        final card = File(
          path.join(database.imgDir, 'scraped', 'works', 'diagnostic-card.jpg'),
        );
        final detail = File(
          path.join(
            database.imgDir,
            'scraped',
            'works',
            'diagnostic-detail.jpg',
          ),
        );
        await avatar.parent.create(recursive: true);
        await card.parent.create(recursive: true);
        await avatar.writeAsString('avatar');
        await card.writeAsString('card');
        await detail.writeAsString('detail');
        await sqlite.update(
          'actresses',
          {'img_path': avatar.path},
          where: 'id = ?',
          whereArgs: [diagnosticActressId],
        );
        final workId = await database.upsertActressWork(
          actressId: diagnosticActressId,
          work: Work(
            code: 'DIAGNOSTIC-900',
            title: 'diagnostic work',
            cardImagePath: card.path,
            detailImagePath: detail.path,
          ),
        );

        final report = await database.deleteActressWithReport(
          diagnosticActressId,
        );

        expect(report.databaseCommitted, isTrue);
        expect(report.actressId, diagnosticActressId);
        expect(report.managedRoot, database.imgDir);
        expect(report.targetActressWorkCount, 1);
        expect(report.snapshotWorks, hasLength(1));
        expect(report.snapshotWorks.single.workId, workId);
        expect(report.snapshotWorks.single.cardImagePath, card.path);
        expect(report.snapshotWorks.single.detailImagePath, detail.path);
        expect(report.snapshotWorks.single.actressReferenceCount, 1);
        expect(report.deletedActressRows, 1);
        expect(report.deletedActressWorkRows, 1);
        expect(report.orphanWorkIds, [workId]);
        expect(report.deletedWorkRows, 1);
        expect(report.remainingActressCount, 0);
        expect(report.remainingWorkCount, 0);
        expect(report.remainingActressWorkCount, 0);
        expect(report.pendingFileDeletionsBefore, isEmpty);
        expect(report.pendingFileDeletionsAfter, isEmpty);
        expect(report.fileRecords, hasLength(3));
        expect(
          report.fileRecords.map((entry) => entry.databaseStoredPath),
          containsAll([avatar.path, card.path, detail.path]),
        );
        expect(
          report.fileRecords.every(
            (entry) =>
                entry.managedRoot == database.imgDir &&
                entry.deleteResult == 'deleted' &&
                entry.existsBefore &&
                !entry.existsAfter,
          ),
          isTrue,
        );
        expect(report.toJson()['snapshot_work_count'], 1);
      },
    );

    test(
      'deletes supported JavBus managed-image path formats under Android documents',
      () async {
        await database.close();
        final documentsDirectory = Directory(
          path.join(fixture.directory.path, 'application-documents'),
        );
        database = fixture.openAppDatabase(
          baseDir: path.join(documentsDirectory.path, 'avaca_data'),
        );
        await database.init();
        await database.addActress(name: 'path format actress');
        final sqlite = await database.database;
        final pathFormatActressId =
            (await sqlite.query(
                  'actresses',
                  columns: ['id'],
                  where: 'name = ?',
                  whereArgs: ['path format actress'],
                )).single['id']
                as int;
        final scrapedWorksDirectory = Directory(
          path.join(database.imgDir, 'scraped', 'works'),
        );
        final avatar = File(
          path.join(database.imgDir, 'scraped', 'actresses', 'avatar.jpg'),
        );
        final uriCard = File(
          path.join(scrapedWorksDirectory.path, 'uri-card.jpg'),
        );
        final documentsDetail = File(
          path.join(scrapedWorksDirectory.path, 'documents-detail.jpg'),
        );
        final managedRootCard = File(
          path.join(scrapedWorksDirectory.path, 'managed-root-card.jpg'),
        );
        final scrapedRelativeDetail = File(
          path.join(scrapedWorksDirectory.path, 'scraped-relative-detail.jpg'),
        );
        final legacyWorksCard = File(
          path.join(database.imgDir, 'works', 'legacy-card.jpg'),
        );
        await avatar.parent.create(recursive: true);
        await scrapedWorksDirectory.create(recursive: true);
        await legacyWorksCard.parent.create(recursive: true);
        await avatar.writeAsString('avatar');
        await uriCard.writeAsString('uri-card');
        await documentsDetail.writeAsString('documents-detail');
        await managedRootCard.writeAsString('managed-root-card');
        await scrapedRelativeDetail.writeAsString('scraped-relative-detail');
        await legacyWorksCard.writeAsString('legacy-card');
        await sqlite.update(
          'actresses',
          {'img_path': avatar.path},
          where: 'id = ?',
          whereArgs: [pathFormatActressId],
        );
        await database.upsertActressWork(
          actressId: pathFormatActressId,
          work: Work(
            code: 'PATH-FORMAT-URI',
            title: 'uri and documents relative',
            cardImagePath: uriCard.uri.toString(),
            detailImagePath: path.relative(
              documentsDetail.path,
              from: documentsDirectory.path,
            ),
          ),
        );
        await database.upsertActressWork(
          actressId: pathFormatActressId,
          work: Work(
            code: 'PATH-FORMAT-RELATIVE',
            title: 'managed and scraped relative',
            cardImagePath: path.relative(
              managedRootCard.path,
              from: database.imgDir,
            ),
            detailImagePath: path.relative(
              scrapedRelativeDetail.path,
              from: path.join(database.imgDir, 'scraped'),
            ),
          ),
        );
        await database.upsertActressWork(
          actressId: pathFormatActressId,
          work: const Work(
            code: 'PATH-FORMAT-LEGACY',
            title: 'legacy works root',
            cardImagePath: '/works/legacy-card.jpg',
          ),
        );

        final report = await database.deleteActressWithReport(
          pathFormatActressId,
        );

        expect(report.databaseCommitted, isTrue);
        expect(report.snapshotWorkCount, 3);
        expect(report.orphanWorkIds, hasLength(3));
        expect(report.fileCleanup.rejected, isEmpty);
        expect(report.fileCleanup.deferred, isEmpty);
        expect(
          report.fileRecords.every(
            (entry) => entry.deleteResult == 'deleted' && !entry.existsAfter,
          ),
          isTrue,
        );
        expect(
          [
            avatar.existsSync(),
            uriCard.existsSync(),
            documentsDetail.existsSync(),
            managedRootCard.existsSync(),
            scrapedRelativeDetail.existsSync(),
            legacyWorksCard.existsSync(),
          ],
          [false, false, false, false, false, false],
        );
        expect(await _tableCounts(sqlite), {
          'actresses': 0,
          'works': 0,
          'actress_works': 0,
          'pending_file_deletions': 0,
        });
        await database.close();
        database = fixture.openAppDatabase(
          baseDir: path.join(documentsDirectory.path, 'avaca_data'),
        );
        await database.init();
        expect(await _tableCounts(await database.database), {
          'actresses': 0,
          'works': 0,
          'actress_works': 0,
          'pending_file_deletions': 0,
        });
      },
    );

    test(
      'deletes an Android private-data alias without resolving the stored path twice',
      () async {
        const androidManagedRoot =
            '/data/data/com.avaca.avaca/app_flutter/avaca_data/images';
        const androidStoredPath =
            '/data/user/0/com.avaca.avaca/app_flutter/avaca_data/images/'
            'scraped/works/test-card.jpg';
        final mappedImage = File(
          path.join(database.imgDir, 'scraped', 'works', 'test-card.jpg'),
        );
        await mappedImage.parent.create(recursive: true);
        await mappedImage.writeAsString('Android alias image');

        await database.close();
        var storedPathResolutionCount = 0;
        database = fixture.openAppDatabase(
          managedImageCanonicalPathResolver: (candidate) {
            if (candidate == androidStoredPath) {
              storedPathResolutionCount++;
              return mappedImage.path;
            }
            return candidate;
          },
        );
        await database.init();
        await database.addActress(name: 'Android alias actress');
        final sqlite = await database.database;
        final aliasActressId =
            (await sqlite.query(
                  'actresses',
                  columns: ['id'],
                  where: 'name = ?',
                  whereArgs: ['Android alias actress'],
                )).single['id']
                as int;
        await database.upsertActressWork(
          actressId: aliasActressId,
          work: const Work(
            code: 'ANDROID-ALIAS-900',
            title: 'Android private-data alias',
            cardImagePath: androidStoredPath,
          ),
        );

        final report = await database.deleteActressWithReport(aliasActressId);

        expect(report.databaseCommitted, isTrue);
        expect(report.managedRoot, database.imgDir);
        expect(androidManagedRoot, contains('/data/data/'));
        expect(storedPathResolutionCount, 1);
        expect(report.fileCleanup.deleted, [mappedImage.path]);
        expect(report.fileCleanup.rejected, isEmpty);
        expect(report.fileRecords.single.classifyResult, 'valid');
        expect(report.fileRecords.single.deleteResult, 'deleted');
        expect(mappedImage.existsSync(), isFalse);
      },
    );

    test(
      'rejects a managed-root prefix collision without deleting the file',
      () async {
        final collisionRoot = Directory('${database.imgDir}2');
        final collisionImage = File(
          path.join(collisionRoot.path, 'scraped', 'works', 'collision.jpg'),
        );
        await collisionImage.parent.create(recursive: true);
        await collisionImage.writeAsString('outside managed root');
        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {'img_path': collisionImage.path},
          where: 'id = ?',
          whereArgs: [actressId],
        );

        final report = await database.deleteActressWithReport(actressId);

        expect(report.databaseCommitted, isTrue);
        expect(report.fileCleanup.rejected, contains(collisionImage.path));
        expect(collisionImage.existsSync(), isTrue);
        expect(await _pendingPaths(sqlite), isEmpty);
      },
    );

    test('deleting an actress preserves shared work data and images', () async {
      final actressImage = File(
        '${database.imgDir}${Platform.pathSeparator}actress-shared.jpg',
      );
      final cardImage = File(
        '${database.imgDir}${Platform.pathSeparator}shared-card.jpg',
      );
      final detailImage = File(
        '${database.imgDir}${Platform.pathSeparator}shared-detail.jpg',
      );
      await actressImage.writeAsString('actress');
      await cardImage.writeAsString('card');
      await detailImage.writeAsString('detail');

      final sqlite = await database.database;
      await sqlite.update(
        'actresses',
        {'img_path': actressImage.path},
        where: 'id = ?',
        whereArgs: [actressId],
      );
      await database.addActress(name: 'shared actress');
      final sharedActressId =
          (await sqlite.query(
                'actresses',
                columns: ['id'],
                where: 'name = ?',
                whereArgs: ['shared actress'],
              )).single['id']
              as int;
      final work = Work(
        code: 'SONE-901',
        title: 'shared',
        cardImagePath: cardImage.path,
        detailImagePath: detailImage.path,
      );
      final workId = await database.upsertActressWork(
        actressId: actressId,
        work: work,
      );
      await database.upsertActressWork(actressId: sharedActressId, work: work);

      final report = await database.deleteActressWithReport(actressId);

      expect(report.databaseCommitted, isTrue);
      expect(await database.getActressById(actressId), isNull);
      expect(await database.getWorkById(workId), isNotNull);
      expect(await database.getWorkCountForActress(sharedActressId), 1);
      expect(cardImage.existsSync(), isTrue);
      expect(detailImage.existsSync(), isTrue);
      expect(actressImage.existsSync(), isFalse);
    });

    test(
      'deleting an orphan work preserves an image path still referenced by another work',
      () async {
        final sharedCard = File(
          path.join(database.imgDir, 'works', 'shared-physical-card.jpg'),
        );
        final orphanDetail = File(
          path.join(database.imgDir, 'works', 'orphan-detail.jpg'),
        );
        final retainedDetail = File(
          path.join(database.imgDir, 'works', 'retained-detail.jpg'),
        );
        await sharedCard.parent.create(recursive: true);
        await sharedCard.writeAsString('shared-card');
        await orphanDetail.writeAsString('orphan-detail');
        await retainedDetail.writeAsString('retained-detail');

        final sqlite = await database.database;
        await database.addActress(name: 'image path owner');
        final secondActressId =
            (await sqlite.query(
                  'actresses',
                  columns: ['id'],
                  where: 'name = ?',
                  whereArgs: ['image path owner'],
                )).single['id']
                as int;
        final orphanWorkId = await database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'PATH-ORPHAN',
            title: 'orphan',
            cardImagePath: sharedCard.path,
            detailImagePath: orphanDetail.path,
          ),
        );
        final retainedWorkId = await database.upsertActressWork(
          actressId: secondActressId,
          work: Work(
            code: 'PATH-RETAINED',
            title: 'retained',
            cardImagePath: sharedCard.path,
            detailImagePath: retainedDetail.path,
          ),
        );

        final report = await database.deleteActressWithReport(actressId);

        expect(report.databaseCommitted, isTrue);
        expect(await database.getWorkById(orphanWorkId), isNull);
        expect(await database.getWorkById(retainedWorkId), isNotNull);
        expect(sharedCard.existsSync(), isTrue);
        expect(orphanDetail.existsSync(), isFalse);
        expect(retainedDetail.existsSync(), isTrue);
        expect(report.fileCleanup.rejected, contains(sharedCard.path));
      },
    );

    test(
      'missing managed images are successful cleanup and leave no queue garbage',
      () async {
        final missingCard = File(
          path.join(database.imgDir, 'works', 'missing-card.jpg'),
        );
        final sqlite = await database.database;
        await database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'MISSING-900',
            title: 'missing image',
            cardImagePath: missingCard.path,
          ),
        );

        final report = await database.deleteActressWithReport(actressId);

        expect(report.databaseCommitted, isTrue);
        expect(report.fileCleanup.missing, contains(missingCard.path));
        expect(await _pendingPaths(sqlite), isEmpty);
        expect(await database.getActressById(actressId), isNull);
        expect(await database.getWorksForActress(actressId), isEmpty);
      },
    );

    test(
      'a transaction failure leaves database rows, managed files, and queue unchanged',
      () async {
        final actressImage = File(
          path.join(database.imgDir, 'transaction-avatar.jpg'),
        );
        final cardImage = File(
          path.join(database.imgDir, 'works', 'transaction-card.jpg'),
        );
        await cardImage.parent.create(recursive: true);
        await actressImage.writeAsString('avatar');
        await cardImage.writeAsString('card');
        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {'img_path': actressImage.path},
          where: 'id = ?',
          whereArgs: [actressId],
        );
        final workId = await database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'TXN-900',
            title: 'transaction failure',
            cardImagePath: cardImage.path,
          ),
        );
        await sqlite.execute('''
          CREATE TRIGGER fail_actress_work_delete
          BEFORE DELETE ON actress_works
          BEGIN
            SELECT RAISE(ABORT, 'simulated transaction failure');
          END
        ''');

        final report = await database.deleteActressWithReport(actressId);

        expect(report.databaseCommitted, isFalse);
        expect(await database.getActressById(actressId), isNotNull);
        expect(await database.getWorkById(workId), isNotNull);
        expect(await sqlite.query('actress_works'), hasLength(1));
        expect(actressImage.existsSync(), isTrue);
        expect(cardImage.existsSync(), isTrue);
        expect(await _pendingPaths(sqlite), isEmpty);
      },
    );

    test('startup retry removes duplicate canonical queue records', () async {
      final image = File(path.join(database.imgDir, 'duplicate-queued.jpg'));
      final duplicatePath =
          '${database.imgDir}${Platform.pathSeparator}.${Platform.pathSeparator}duplicate-queued.jpg';
      await image.writeAsString('duplicate queue');
      final sqlite = await database.database;
      await sqlite.insert('pending_file_deletions', {'path': image.path});
      await sqlite.insert('pending_file_deletions', {'path': duplicatePath});

      await database.close();
      database = fixture.openAppDatabase();
      await database.init();

      expect(image.existsSync(), isFalse);
      expect(await _pendingPaths(await database.database), isEmpty);
    });

    test(
      'pending retry validates an Android alias once and preserves an external file',
      () async {
        const androidStoredPath =
            '/data/user/0/com.avaca.avaca/app_flutter/avaca_data/images/'
            'scraped/works/pending-card.jpg';
        final managedImage = File(
          path.join(database.imgDir, 'scraped', 'works', 'pending-card.jpg'),
        );
        final externalImage = File(
          path.join(fixture.directory.path, 'pending-external.jpg'),
        );
        await managedImage.parent.create(recursive: true);
        await managedImage.writeAsString('pending managed image');
        await externalImage.writeAsString('pending external image');
        final sqlite = await database.database;
        await sqlite.insert('pending_file_deletions', {
          'path': androidStoredPath,
        });
        await sqlite.insert('pending_file_deletions', {
          'path': externalImage.path,
        });

        await database.close();
        var storedPathResolutionCount = 0;
        database = fixture.openAppDatabase(
          managedImageCanonicalPathResolver: (candidate) {
            if (candidate == androidStoredPath) {
              storedPathResolutionCount++;
              return managedImage.path;
            }
            return candidate;
          },
        );
        await database.init();

        expect(storedPathResolutionCount, 1);
        expect(managedImage.existsSync(), isFalse);
        expect(externalImage.existsSync(), isTrue);
        expect(await _pendingPaths(await database.database), isEmpty);
      },
    );

    test(
      'a failed file delete is deferred and startup retry clears its queue entry',
      () async {
        final actressImage = File(
          path.join(database.imgDir, 'retry-avatar.jpg'),
        );
        await actressImage.writeAsString('retry-avatar');
        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {'img_path': actressImage.path},
          where: 'id = ?',
          whereArgs: [actressId],
        );

        await database.close();
        database = fixture.openAppDatabase(
          deleteFile: (_) => Future<void>.error(
            FileSystemException('simulated delete failure'),
          ),
        );
        await database.init();

        final report = await database.deleteActressWithReport(actressId);

        expect(report.databaseCommitted, isTrue);
        expect(report.fileCleanup.deferred, contains(actressImage.path));
        expect(await _pendingPaths(await database.database), [
          actressImage.path,
        ]);
        expect(actressImage.existsSync(), isTrue);

        await database.close();
        database = fixture.openAppDatabase();
        await database.init();

        expect(actressImage.existsSync(), isFalse);
        expect(await _pendingPaths(await database.database), isEmpty);
        expect(await database.getActressById(actressId), isNull);
        final restartedController = DetailController(
          db: database,
          actressId: actressId,
        );
        await restartedController.init();
        expect(restartedController.workCount, 0);
      },
    );

    test(
      'a committed delete recovers queued image cleanup after a simulated interruption',
      () async {
        final actressImage = File(
          path.join(database.imgDir, 'interrupt-avatar.jpg'),
        );
        await actressImage.writeAsString('interrupt-avatar');
        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {'img_path': actressImage.path},
          where: 'id = ?',
          whereArgs: [actressId],
        );

        await database.close();
        database = fixture.openAppDatabase(
          afterDeleteTransactionCommitted: () async {
            throw const _SimulatedProcessInterruption();
          },
        );
        await database.init();

        await expectLater(
          database.deleteActressWithReport(actressId),
          throwsA(isA<_SimulatedProcessInterruption>()),
        );

        final interruptedSqlite = await database.database;
        expect(await database.getActressById(actressId), isNull);
        expect(await _pendingPaths(interruptedSqlite), [actressImage.path]);
        expect(actressImage.existsSync(), isTrue);

        await database.close();
        database = fixture.openAppDatabase();
        await database.init();

        expect(actressImage.existsSync(), isFalse);
        expect(await _pendingPaths(await database.database), isEmpty);
      },
    );

    test(
      'an image outside the managed root is rejected, retained, and removed from the queue',
      () async {
        final externalImage = File(
          path.join(fixture.directory.path, 'external-avatar.jpg'),
        );
        await externalImage.writeAsString('external');
        final sqlite = await database.database;
        await sqlite.update(
          'actresses',
          {'img_path': externalImage.path},
          where: 'id = ?',
          whereArgs: [actressId],
        );

        final report = await database.deleteActressWithReport(actressId);

        expect(report.databaseCommitted, isTrue);
        expect(report.fileCleanup.rejected, contains(externalImage.path));
        expect(report.fileRecords.single.existsBefore, isTrue);
        expect(
          report.fileRecords.single.bytesBefore,
          externalImage.lengthSync(),
        );
        expect(externalImage.existsSync(), isTrue);
        expect(await _pendingPaths(sqlite), isEmpty);
      },
    );

    test(
      'deleting an actress preserves untracked files and conditionally compacts the database',
      () async {
        final scrapedDirectory = Directory(
          '${database.imgDir}${Platform.pathSeparator}scraped',
        );
        await scrapedDirectory.create(recursive: true);
        final staleImage = File(
          '${scrapedDirectory.path}${Platform.pathSeparator}stale.jpg',
        );
        final retainedImage = File(
          '${scrapedDirectory.path}${Platform.pathSeparator}retained.jpg',
        );
        final nonScrapedImage = File(
          '${database.imgDir}${Platform.pathSeparator}not-scraped.jpg',
        );
        await staleImage.writeAsString('stale');
        await retainedImage.writeAsString('retained');
        await nonScrapedImage.writeAsString('do not delete');

        final sqlite = await database.database;
        await database.addActress(name: 'retained actress');
        final retainedActressId =
            (await sqlite.query(
                  'actresses',
                  columns: ['id'],
                  where: 'name = ?',
                  whereArgs: ['retained actress'],
                )).single['id']
                as int;
        await sqlite.update(
          'actresses',
          {'img_path': retainedImage.path},
          where: 'id = ?',
          whereArgs: [retainedActressId],
        );

        await database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'VACUUM-900',
            title: List<String>.filled(300000, 'x').join(),
          ),
        );
        final beforePageCount =
            (await sqlite.rawQuery('PRAGMA page_count')).single.values.single
                as int;

        expect(await database.deleteActress(actressId), isTrue);

        final afterPageCount =
            (await sqlite.rawQuery('PRAGMA page_count')).single.values.single
                as int;
        expect(
          [staleImage.existsSync(), afterPageCount < beforePageCount],
          [true, true],
        );
        expect(retainedImage.existsSync(), isTrue);
        expect(nonScrapedImage.existsSync(), isTrue);
      },
    );

    test(
      'deleting waits for a prepared scraped image to receive its DB reference',
      () async {
        await database.addActress(name: 'surviving actress');
        final sqlite = await database.database;
        final survivingActressId =
            (await sqlite.query(
                  'actresses',
                  columns: ['id'],
                  where: 'name = ?',
                  whereArgs: ['surviving actress'],
                )).single['id']
                as int;
        final image = File(
          '${database.imgDir}${Platform.pathSeparator}scraped'
          '${Platform.pathSeparator}surviving.jpg',
        );
        final prepared = Completer<void>();
        final allowReferenceWrite = Completer<void>();

        final lifecycle = database.runManagedImageLifecycle(() async {
          await image.parent.create(recursive: true);
          await image.writeAsString('surviving');
          prepared.complete();
          await allowReferenceWrite.future;
          await sqlite.update(
            'actresses',
            {'img_path': image.path},
            where: 'id = ?',
            whereArgs: [survivingActressId],
          );
        });
        await prepared.future;

        final deletion = database.deleteActress(actressId);
        var deletionCompleted = false;
        deletion.then((_) => deletionCompleted = true);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(deletionCompleted, isFalse);

        allowReferenceWrite.complete();
        await lifecycle;
        expect(await deletion, isTrue);
        expect(image.existsSync(), isTrue);
        expect(
          (await database.getActressById(survivingActressId))?['img_path'],
          image.path,
        );
      },
    );

    test(
      'public image-reference writers wait for an active lifecycle',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final lifecycle = database.runManagedImageLifecycle(() async {
          started.complete();
          await release.future;
        });
        await started.future;

        final synced = database.syncActressDetails(
          actressId: actressId,
          details: ScrapedActressDetails(
            imagePath: path.join(database.imgDir, 'scraped', 'synced.jpg'),
          ),
          replaceImage: true,
        );
        final updated = database.updateActress(
          actressId: actressId,
          name: '涼森れむ',
          imgPath: path.join(database.imgDir, 'scraped', 'updated.jpg'),
        );
        final upserted = database.upsertActressWork(
          actressId: actressId,
          work: Work(
            code: 'LOCK-900',
            title: 'locked work',
            cardImagePath: path.join(database.imgDir, 'scraped', 'card.jpg'),
          ),
        );
        final added = database.addActress(
          name: 'lifecycle image actress',
          imgPath: path.join(database.imgDir, 'scraped', 'added.jpg'),
        );
        var completed = 0;
        synced.then((_) => completed++);
        updated.then((_) => completed++);
        upserted.then((_) => completed++);
        added.then((_) => completed++);

        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(completed, 0);

        release.complete();
        await Future.wait([synced, updated, upserted, added]);
        await lifecycle;
      },
    );

    test('nested managed image lifecycle operations complete', () async {
      final value = await database
          .runManagedImageLifecycle(
            () => database.runManagedImageLifecycle(() async => 'complete'),
          )
          .timeout(const Duration(milliseconds: 100));

      expect(value, 'complete');
    });

    test(
      'detached lifecycle descendants rejoin the queue after outer exit',
      () async {
        final detachedCreated = Completer<void>();
        final releaseDetached = Completer<void>();
        final detachedCompleted = Completer<void>();
        Future<void>? detached;
        final outer = database.runManagedImageLifecycle(() async {
          detached = () async {
            await releaseDetached.future;
            await database.runManagedImageLifecycle(() async {
              detachedCompleted.complete();
            });
          }();
          detachedCreated.complete();
        });
        await detachedCreated.future;
        await outer;

        final secondStarted = Completer<void>();
        final releaseSecond = Completer<void>();
        final second = database.runManagedImageLifecycle(() async {
          secondStarted.complete();
          await releaseSecond.future;
        });
        await secondStarted.future;

        releaseDetached.complete();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(detachedCompleted.isCompleted, isFalse);

        releaseSecond.complete();
        await second;
        await detached;
        expect(detachedCompleted.isCompleted, isTrue);
      },
    );
  });
}

class _DatabaseFixture {
  _DatabaseFixture._(this.directory);

  final Directory directory;
  AppDatabase? _database;

  static Future<_DatabaseFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_work_database_test_',
    );
    return _DatabaseFixture._(directory);
  }

  AppDatabase openAppDatabase({
    String? baseDir,
    Future<void> Function(File file)? deleteFile,
    Future<void> Function()? afterDeleteTransactionCommitted,
    ManagedImageCanonicalPathResolver? managedImageCanonicalPathResolver,
  }) {
    return _database = AppDatabase.forTesting(
      baseDir: baseDir ?? directory.path,
      databaseFactory: databaseFactoryFfi,
      deleteFile: deleteFile,
      afterDeleteTransactionCommitted: afterDeleteTransactionCommitted,
      managedImageCanonicalPathResolver: managedImageCanonicalPathResolver,
    );
  }

  Future<void> dispose() async {
    await _database?.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

class _ManagedImageStats {
  const _ManagedImageStats(this.fileCount, this.totalBytes);

  final int fileCount;
  final int totalBytes;

  @override
  bool operator ==(Object other) {
    return other is _ManagedImageStats &&
        other.fileCount == fileCount &&
        other.totalBytes == totalBytes;
  }

  @override
  int get hashCode => Object.hash(fileCount, totalBytes);

  @override
  String toString() =>
      '_ManagedImageStats($fileCount files, $totalBytes bytes)';
}

Future<Map<String, int>> _tableCounts(DatabaseExecutor database) async {
  const tables = [
    'actresses',
    'works',
    'actress_works',
    'pending_file_deletions',
  ];
  final result = <String, int>{};
  for (final table in tables) {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM $table',
    );
    result[table] = (rows.single['count'] as num).toInt();
  }
  return result;
}

Future<_ManagedImageStats> _managedImageStats(Directory root) async {
  var fileCount = 0;
  var totalBytes = 0;
  if (!await root.exists()) {
    return const _ManagedImageStats(0, 0);
  }
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      fileCount++;
      totalBytes += await entity.length();
    }
  }
  return _ManagedImageStats(fileCount, totalBytes);
}

Future<List<String>> _pendingPaths(DatabaseExecutor database) async {
  final rows = await database.query(
    'pending_file_deletions',
    columns: ['path'],
    orderBy: 'path ASC',
  );
  return rows.map((row) => row['path']! as String).toList();
}

class _SimulatedProcessInterruption implements Exception {
  const _SimulatedProcessInterruption();
}
