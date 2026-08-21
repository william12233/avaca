import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:avaca/services/scrape/scrape_image_downloader.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_source.dart';
import 'package:avaca/services/scrape/work_code_canonicalizer.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group(
    'legacy multi-source scraper behavior',
    () {
      sqfliteFfiInit();

      test(
        'aggregate mode merges by canonical code and keeps source failures partial',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_multi_source_service_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '小湊よつ葉');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;

          final minnano = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1996-05-29',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'start－489',
                title: 'Minnano title',
                detailUri: Uri.parse('https://www.minnano-av.com/av489.html'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-002',
                title: 'Minnano only',
                detailUri: Uri.parse('https://www.minnano-av.com/av2.html'),
              ),
            ],
            detailsByCode: {
              'START-489': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'START-489',
                title: 'Minnano title',
                studio: 'Minnano studio',
                performerCount: 1,
              ),
              'M-002': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-002',
                title: 'Minnano only',
                performerCount: 1,
              ),
            },
          );
          final javbus = _FakeScrapeSource(
            id: ScrapeSourceId.javbus,
            detailBirthDate: '1900-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'START-489',
                title: 'JavBus title',
                detailUri: Uri.parse('https://www.javbus.com/START-489'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'J-003',
                title: 'JavBus only',
                detailUri: Uri.parse('https://www.javbus.com/J-003'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'BAD-004',
                title: 'Broken',
                detailUri: Uri.parse('https://www.javbus.com/BAD-004'),
              ),
            ],
            detailsByCode: {
              'START-489': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'START-489',
                title: 'JavBus title',
                durationMinutes: 120,
                performerCount: 2,
              ),
              'J-003': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'J-003',
                title: 'JavBus only',
                performerCount: 1,
              ),
            },
            failingCodes: {'BAD-004'},
          );
          final service = WorksScrapeService(
            db: database,
            sources: {
              ScrapeSourceId.minnanoAv: minnano,
              ScrapeSourceId.javbus: javbus,
            },
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final result = await service.scrape(
            actressId: actressId,
            actressName: '小湊よつ葉',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(),
          );

          final works = await database.getWorksForActress(actressId);
          expect(result.saved, 3);
          expect(result.failed, 1);
          expect(result.failedWorks, hasLength(1));
          expect(result.failedWorks.single.code, 'BAD-004');
          expect(result.partialSuccess, isTrue);
          expect(
            result.sourceResults.keys,
            containsAll([ScrapeSourceId.minnanoAv, ScrapeSourceId.javbus]),
          );
          expect(
            works.map((row) => row['code']),
            unorderedEquals(['START-489', 'M-002', 'J-003']),
          );
          final merged = works.firstWhere((row) => row['code'] == 'START-489');
          expect(merged['studio'], 'Minnano studio');
          expect(merged['duration_minutes'], 120);
          expect(
            (await database.getActressById(actressId))?['birth_date'],
            '1996-05-29',
          );

          minnano.detailRequests.clear();
          javbus.detailRequests.clear();
          await service.scrape(
            actressId: actressId,
            actressName: '小湊よつ葉',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.javbus,
            ),
          );
          expect(minnano.detailRequests, isEmpty);
          expect(javbus.detailRequests, isNotEmpty);
        },
      );

      test(
        'does not reuse separatorless alias equivalence as cross-source identity',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_separatorless_canonical_dedup_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '河北彩花');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;

          final minnano = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'SIVR00303',
                title: 'SIVR alias',
                detailUri: Uri.parse('https://www.minnano-av.com/sivr303.html'),
              ),
            ],
            detailsByCode: {
              'SIVR-303': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'SIVR00303',
                title: 'SIVR alias detail',
                performerCount: 1,
              ),
            },
          );
          final javbus = _FakeScrapeSource(
            id: ScrapeSourceId.javbus,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'SIVR-303',
                title: 'SIVR canonical',
                detailUri: Uri.parse('https://www.javbus.com/SIVR-303'),
              ),
            ],
            detailsByCode: {
              'SIVR-303': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'SIVR-303',
                title: 'SIVR canonical detail',
                performerCount: 1,
              ),
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {
              ScrapeSourceId.minnanoAv: minnano,
              ScrapeSourceId.javbus: javbus,
            },
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final progress = <WorksScrapeProgress>[];
          final result = await service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(),
            onProgress: progress.add,
          );

          final works = await database.getWorksForActress(actressId);
          expect(result.saved, 2);
          expect(result.excluded, 0);
          expect(result.failed, 0);
          expect(result.failedWorks, isEmpty);
          expect(works, hasLength(2));
          expect(
            works.map((row) => row['code']),
            unorderedEquals(['SIVR-00303', 'SIVR-303']),
          );
          expect(minnano.detailRequests, ['SIVR-303']);
          expect(javbus.detailRequests, ['SIVR-303']);

          final fetching = progress
              .where((item) => item.phase == WorksScrapePhase.fetchingDetails)
              .toList();
          final saving = progress
              .where((item) => item.phase == WorksScrapePhase.savingWorks)
              .toList();
          expect(fetching, isNotEmpty);
          expect(fetching, everyElement(isA<WorksScrapeProgress>()));
          expect(fetching.map((item) => item.total), everyElement(1));
          expect(fetching.where((item) => item.current == 1), isNotEmpty);
          expect(saving, isNotEmpty);
          expect(saving.last.total, 2);
          expect(saving.last.current, 2);
        },
      );

      test(
        'emits final-code image progress before image variants finish',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_canonical_image_progress_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '河北彩花');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          final source = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875',
                detailUri: Uri.parse('https://www.minnano-av.com/ssis875.html'),
              ),
            ],
            detailsByCode: {
              'SSIS-875': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875 detail',
                performerCount: 1,
              ),
            },
          );
          final imageDownloader = _BlockingWorkImageDownloader();
          final service = WorksScrapeService(
            db: database,
            sources: {ScrapeSourceId.minnanoAv: source},
            workImageDownloader: imageDownloader,
            imageDirectory: directory.path,
          );
          final progress = <WorksScrapeProgress>[];
          final scrape = service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.minnanoAv,
            ),
            onProgress: progress.add,
          );

          await imageDownloader.firstImageStarted.future;
          final savingBeforeImages = progress
              .where((item) => item.phase == WorksScrapePhase.savingWorks)
              .last;
          expect(savingBeforeImages.current, 0);
          expect(savingBeforeImages.total, 1);
          final imageProgress = progress
              .where((item) => item.phase == WorksScrapePhase.downloadingImages)
              .last;
          expect(imageProgress.workCode, 'SSIS-875');
          expect(imageProgress.current, 0);
          expect(imageProgress.totalKnown, isTrue);
          expect(
            imageProgress.sourceProgress[ScrapeSourceId.minnanoAv]?.current,
            0,
          );
          expect(
            imageProgress.sourceProgress[ScrapeSourceId.minnanoAv]?.total,
            1,
          );

          imageDownloader.releaseFirstImage();
          final result = await scrape;
          expect(result.saved, 1);
          expect(result.failed, 0);
          final savingAfterImages = progress
              .where((item) => item.phase == WorksScrapePhase.savingWorks)
              .last;
          expect(savingAfterImages.current, 1);
          expect(savingAfterImages.total, 1);
        },
      );

      test(
        'reports the current work while a detail request is pending',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_detail_progress_current_work_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '河北彩花');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          final detailStarted = Completer<void>();
          final releaseDetail = Completer<void>();
          final source = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875',
                detailUri: Uri.parse('https://www.minnano-av.com/ssis875.html'),
              ),
            ],
            detailsByCode: {
              'SSIS-875': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875 detail',
                performerCount: 1,
              ),
            },
            beforeDetail: (_) async {
              if (!detailStarted.isCompleted) {
                detailStarted.complete();
              }
              await releaseDetail.future;
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {ScrapeSourceId.minnanoAv: source},
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );
          final progress = <WorksScrapeProgress>[];
          final scrape = service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.minnanoAv,
            ),
            onProgress: progress.add,
          );

          await detailStarted.future;
          final fetching = progress
              .where((item) => item.phase == WorksScrapePhase.fetchingDetails)
              .last;
          expect(fetching.current, 0);
          expect(fetching.total, 1);
          expect(fetching.workCode, isNull);

          releaseDetail.complete();
          final result = await scrape;
          expect(result.saved, 1);
          expect(result.failed, 0);
        },
      );

      test(
        'deduplicates same-source unknown-code titles before detail fetch',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_unknown_work_identity_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '河北彩花');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          final source = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: '',
                title: '同名未知作品',
                detailUri: Uri.parse(
                  'https://www.minnano-av.com/unknown-a.html',
                ),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: '',
                title: '同名未知作品',
                detailUri: Uri.parse(
                  'https://www.minnano-av.com/unknown-b.html',
                ),
              ),
            ],
            detailsByCode: const {},
          );
          final service = WorksScrapeService(
            db: database,
            sources: {ScrapeSourceId.minnanoAv: source},
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );
          final progress = <WorksScrapeProgress>[];
          final result = await service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.minnanoAv,
            ),
            onProgress: progress.add,
          );

          expect(result.saved, 0);
          expect(result.failed, 1);
          expect(result.failedWorks, hasLength(1));
          expect(result.imageFailures, isEmpty);
          expect(
            progress
                .where((item) => item.phase == WorksScrapePhase.savingWorks)
                .last
                .total,
            1,
          );
        },
      );

      test(
        'keeps image failures separate and unique from work failures',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_canonical_image_failure_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '河北彩花');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          final source = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875',
                detailUri: Uri.parse('https://www.minnano-av.com/ssis875.html'),
              ),
            ],
            detailsByCode: {
              'SSIS-875': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875 detail',
                performerCount: 1,
              ),
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {ScrapeSourceId.minnanoAv: source},
            workImageDownloader: _FailingWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final result = await service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.minnanoAv,
            ),
          );

          expect(result.saved, 1);
          expect(result.failed, 0);
          expect(result.failedWorks, isEmpty);
          expect(result.imageFailures, hasLength(1));
          expect(result.imageFailures.single.code, 'SSIS-875');
          expect(
            result.imageFailures.single.variants,
            containsAll([WorkImageVariant.card, WorkImageVariant.detail]),
          );
        },
      );

      test('keeps detail code when it differs from the summary code', () async {
        final directory = await Directory.systemTemp.createTemp(
          'avaca_multi_source_code_guard_test_',
        );
        final database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await database.close();
          await directory.delete(recursive: true);
        });
        await database.init();
        await database.addActress(name: '河北彩花');
        final actressId =
            (await (await database.database).query('actresses')).single['id']
                as int;

        final summary = ScrapeWorkSummary(
          source: ScrapeSourceId.minnanoAv,
          code: 'start－489',
          title: 'Summary title',
          detailUri: Uri.parse('https://www.minnano-av.com/av489.html'),
        );
        final minnano = _FakeScrapeSource(
          id: ScrapeSourceId.minnanoAv,
          detailBirthDate: '1999-01-01',
          works: [summary],
          detailsByCode: {
            'START-489': const ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: 'OTHER-999',
              title: 'Wrong detail title',
              studio: 'Wrong studio must not be merged',
              performerCount: 1,
            ),
          },
        );
        final javbus = _FakeScrapeSource(
          id: ScrapeSourceId.javbus,
          detailBirthDate: '1999-01-01',
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.javbus,
              code: 'START-489',
              title: summary.title,
              detailUri: Uri.parse('https://www.javbus.com/START-489'),
            ),
          ],
          detailsByCode: {
            'START-489': const ScrapeWorkDetails(
              source: ScrapeSourceId.javbus,
              code: 'START-489',
              title: 'Verified detail title',
              durationMinutes: 90,
              performerCount: 1,
            ),
          },
        );
        final service = WorksScrapeService(
          db: database,
          sources: {
            ScrapeSourceId.minnanoAv: minnano,
            ScrapeSourceId.javbus: javbus,
          },
          workImageDownloader: _FakeWorkImageDownloader(),
          imageDirectory: directory.path,
        );

        final result = await service.scrape(
          actressId: actressId,
          actressName: '河北彩花',
          options: const WorkScrapeOptions(),
          sourceSettings: const ScrapeSourceSettings(),
        );

        final works = await database.getWorksForActress(actressId);
        expect(result.saved, 2);
        expect(result.failed, 0);
        expect(result.partialSuccess, isFalse);
        expect(works, hasLength(2));
        expect(
          works.map((row) => row['code']),
          unorderedEquals(['OTHER-999', 'START-489']),
        );
        expect(
          works.firstWhere((row) => row['code'] == 'OTHER-999')['studio'],
          'Wrong studio must not be merged',
        );
        expect(
          works.firstWhere(
            (row) => row['code'] == 'START-489',
          )['duration_minutes'],
          90,
        );
      });

      test('does not merge old database aliases into a new scrape', () async {
        final directory = await Directory.systemTemp.createTemp(
          'avaca_start_alias_dedup_test_',
        );
        final database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await database.close();
          await directory.delete(recursive: true);
        });
        await database.init();
        await database.addActress(name: '小湊よつ葉');
        final actressId =
            (await (await database.database).query('actresses')).single['id']
                as int;
        await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: '1START00408', title: 'legacy alias'),
        );
        await database.upsertActressWork(
          actressId: actressId,
          work: const Work(code: 'START-408', title: 'legacy canonical'),
        );

        final source = _FakeScrapeSource(
          id: ScrapeSourceId.minnanoAv,
          detailBirthDate: '1996-05-29',
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: '1start00408',
              title: 'START 408 alias',
              detailUri: Uri.parse('https://www.minnano-av.com/av408-a.html'),
            ),
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: 'START-408',
              title: 'START 408 canonical',
              detailUri: Uri.parse('https://www.minnano-av.com/av408-b.html'),
            ),
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: '1start00427',
              title: 'START 427 alias',
              detailUri: Uri.parse('https://www.minnano-av.com/av427-a.html'),
            ),
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: 'START-427',
              title: 'START 427 canonical',
              detailUri: Uri.parse('https://www.minnano-av.com/av427-b.html'),
            ),
          ],
          detailsByCode: {
            'START-408': ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: '1start00408',
              title: 'START 408',
              performerCount: 1,
              imageUris: [
                Uri.parse(
                  'https://www.minnano-av.com/p_package/2605/195939.jpg',
                ),
              ],
            ),
            'START-427': const ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: 'START-427',
              title: 'START 427',
              performerCount: 1,
            ),
          },
        );
        final uriDownloader = _RecordingScrapeImageUriDownloader();
        final service = WorksScrapeService(
          db: database,
          sources: {ScrapeSourceId.minnanoAv: source},
          workImageDownloader: _FakeWorkImageDownloader(),
          imageUriDownloader: uriDownloader,
          imageDirectory: directory.path,
        );

        final result = await service.scrape(
          actressId: actressId,
          actressName: '小湊よつ葉',
          options: const WorkScrapeOptions(),
          sourceSettings: const ScrapeSourceSettings(
            actressDetailsSource: ScrapeSourceId.minnanoAv,
            worksSource: WorksSourceSelection.minnanoAv,
          ),
        );

        final works = await database.getWorksForActress(actressId);
        expect(result.saved, 2);
        expect(works, hasLength(3));
        expect(
          works.map((row) => row['code']),
          unorderedEquals(['1START00408', 'START-408', 'START-427']),
        );
        expect(
          works.where((row) => row['code'] == '1START00408'),
          hasLength(1),
        );
        expect(source.detailRequests, [
          'START-408',
          'START-408',
          'START-427',
          'START-427',
        ]);
        expect(uriDownloader.requested, isEmpty);
      });

      test(
        'starts all source pipelines and detail queues concurrently while each source stays sequential',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_multi_source_overlap_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '小湊よつ葉');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;

          final minnanoCollectionStarted = Completer<void>();
          final releaseMinnanoCollection = Completer<void>();
          final javbusCollectionStarted = Completer<void>();
          final minnanoDetailStarted = Completer<void>();
          final releaseMinnanoDetail = Completer<void>();
          final javbusDetailStarted = Completer<void>();
          final releaseJavbusDetail = Completer<void>();

          final minnano = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1996-05-29',
            beforeSearch: () async {
              if (!minnanoCollectionStarted.isCompleted) {
                minnanoCollectionStarted.complete();
              }
              await releaseMinnanoCollection.future;
            },
            beforeDetail: (code) async {
              if (code == 'M-001') {
                if (!minnanoDetailStarted.isCompleted) {
                  minnanoDetailStarted.complete();
                }
                await releaseMinnanoDetail.future;
              }
            },
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-001',
                title: 'Minnano 1',
                detailUri: Uri.parse('https://www.minnano-av.com/m1.html'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-002',
                title: 'Minnano 2',
                detailUri: Uri.parse('https://www.minnano-av.com/m2.html'),
              ),
            ],
            detailsByCode: {
              'M-001': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-001',
                title: 'Minnano 1',
                performerCount: 1,
              ),
              'M-002': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-002',
                title: 'Minnano 2',
                performerCount: 1,
              ),
            },
          );
          final javbus = _FakeScrapeSource(
            id: ScrapeSourceId.javbus,
            detailBirthDate: '1996-05-29',
            beforeSearch: () async {
              if (!javbusCollectionStarted.isCompleted) {
                javbusCollectionStarted.complete();
              }
            },
            beforeDetail: (code) async {
              if (code == 'J-001') {
                if (!javbusDetailStarted.isCompleted) {
                  javbusDetailStarted.complete();
                }
                await releaseJavbusDetail.future;
              }
            },
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'J-001',
                title: 'JavBus 1',
                detailUri: Uri.parse('https://www.javbus.com/J-001'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'J-002',
                title: 'JavBus 2',
                detailUri: Uri.parse('https://www.javbus.com/J-002'),
              ),
            ],
            detailsByCode: {
              'J-001': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'J-001',
                title: 'JavBus 1',
                performerCount: 1,
              ),
              'J-002': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'J-002',
                title: 'JavBus 2',
                performerCount: 1,
              ),
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {
              ScrapeSourceId.minnanoAv: minnano,
              ScrapeSourceId.javbus: javbus,
            },
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final scrape = service.scrape(
            actressId: actressId,
            actressName: '小湊よつ葉',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(),
          );

          await minnanoCollectionStarted.future;
          await javbusCollectionStarted.future;
          expect(minnanoCollectionStarted.isCompleted, isTrue);
          expect(javbusCollectionStarted.isCompleted, isTrue);

          // JavBus detail must start while Minnano is still blocked in collection.
          await javbusDetailStarted.future;
          expect(releaseMinnanoCollection.isCompleted, isFalse);
          expect(javbus.detailRequests, ['J-001']);
          releaseMinnanoCollection.complete();

          await minnanoDetailStarted.future;
          expect(minnano.detailRequests, ['M-001']);
          expect(javbus.detailRequests, ['J-001']);
          releaseMinnanoDetail.complete();
          releaseJavbusDetail.complete();

          final result = await scrape;
          expect(result.saved, 4);
          expect(minnano.detailRequests, ['M-001', 'M-002']);
          expect(javbus.detailRequests, ['J-001', 'J-002']);
        },
      );

      test(
        'does not use numeric-leading aliases as ordinary cross-source identity',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_generic_alias_dedup_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '小湊よつ葉');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          await database.upsertActressWork(
            actressId: actressId,
            work: const Work(code: '1STZY00017', title: 'legacy alias'),
          );
          await database.upsertActressWork(
            actressId: actressId,
            work: const Work(code: 'STZY-017', title: 'legacy canonical'),
          );

          final minnano = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1996-05-29',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: '1stzy00017',
                title: 'STZY alias',
                detailUri: Uri.parse('https://www.minnano-av.com/stzy017.html'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: '3DSVR-1947',
                title: 'DSVR alias',
                detailUri: Uri.parse(
                  'https://www.minnano-av.com/dsvr1947.html',
                ),
              ),
            ],
            detailsByCode: {
              'STZY-017': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: '1stzy00017',
                title: 'STZY 017',
                performerCount: 1,
              ),
              'DSVR-1947': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: '3DSVR-1947',
                title: 'DSVR 1947',
                performerCount: 1,
              ),
            },
          );
          final javbus = _FakeScrapeSource(
            id: ScrapeSourceId.javbus,
            detailBirthDate: '1996-05-29',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'STZY-017',
                title: 'STZY canonical',
                detailUri: Uri.parse('https://www.javbus.com/STZY-017'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'DSVR-1947',
                title: 'DSVR canonical',
                detailUri: Uri.parse('https://www.javbus.com/DSVR-1947'),
              ),
            ],
            detailsByCode: {
              'STZY-017': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'STZY-017',
                title: 'STZY 017 JavBus',
                durationMinutes: 90,
                performerCount: 1,
              ),
              'DSVR-1947': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'DSVR-1947',
                title: 'DSVR 1947 JavBus',
                durationMinutes: 120,
                performerCount: 1,
              ),
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {
              ScrapeSourceId.minnanoAv: minnano,
              ScrapeSourceId.javbus: javbus,
            },
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final result = await service.scrape(
            actressId: actressId,
            actressName: '小湊よつ葉',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(),
          );

          final works = await database.getWorksForActress(actressId);
          expect(result.saved, 4);
          expect(result.failed, 0);
          expect(works, hasLength(4));
          expect(
            works.map((row) => row['code']),
            unorderedEquals([
              '1STZY00017',
              '3DSVR-1947',
              'STZY-017',
              'DSVR-1947',
            ]),
          );
          expect(minnano.detailRequests, ['STZY-017', 'DSVR-1947']);
          expect(javbus.detailRequests, ['STZY-017', 'DSVR-1947']);
          expect(
            (await (await database.database).query('actress_works')).length,
            4,
          );
        },
      );

      test('same-source title dedupe prefers the ordinary edition', () async {
        final directory = await Directory.systemTemp.createTemp(
          'avaca_special_edition_title_test_',
        );
        final database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await database.close();
          await directory.delete(recursive: true);
        });
        await database.init();
        await database.addActress(name: '河北彩花');
        final actressId =
            (await (await database.database).query('actresses')).single['id']
                as int;

        final source = _FakeScrapeSource(
          id: ScrapeSourceId.minnanoAv,
          detailBirthDate: '1999-01-01',
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: 'SP-001',
              title: '【特典版】同一作品',
              detailUri: Uri.parse('https://www.minnano-av.com/sp001.html'),
            ),
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: 'ORD-001',
              title: '同一作品',
              detailUri: Uri.parse('https://www.minnano-av.com/ord001.html'),
            ),
          ],
          detailsByCode: {
            'SP-001': const ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: 'SP-001',
              title: '【特典版】同一作品',
              performerCount: 1,
            ),
            'ORD-001': const ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: 'ORD-001',
              title: '同一作品',
              performerCount: 1,
            ),
          },
        );
        final service = WorksScrapeService(
          db: database,
          sources: {ScrapeSourceId.minnanoAv: source},
          workImageDownloader: _FakeWorkImageDownloader(),
          imageDirectory: directory.path,
        );

        final result = await service.scrape(
          actressId: actressId,
          actressName: '河北彩花',
          options: const WorkScrapeOptions(syncDetails: false),
          sourceSettings: const ScrapeSourceSettings(
            actressDetailsSource: ScrapeSourceId.minnanoAv,
            worksSource: WorksSourceSelection.minnanoAv,
          ),
        );

        expect(result.saved, 1);
        expect(source.detailRequests, ['ORD-001']);
        expect(
          (await database.getWorksForActress(actressId)).single['code'],
          'ORD-001',
        );
      });

      test('Rebecca title merge chooses the shortest detail code', () async {
        final directory = await Directory.systemTemp.createTemp(
          'avaca_rebecca_title_merge_test_',
        );
        final database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await database.close();
          await directory.delete(recursive: true);
        });
        await database.init();
        await database.addActress(name: '河北彩花');
        final actressId =
            (await (await database.database).query('actresses')).single['id']
                as int;
        const title = 'Ui 太陽に照らされて';
        final minnanoUri = 'https://www.minnano-av.com/rebd975.html';
        final javbusUri = 'https://www.javbus.com/REBD-975';
        final minnano = _FakeScrapeSource(
          id: ScrapeSourceId.minnanoAv,
          detailBirthDate: '1999-01-01',
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: 'H_346REBD00975',
              title: title,
              detailUri: Uri.parse(minnanoUri),
            ),
          ],
          detailsByUri: {
            minnanoUri: const ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: 'H_346REBD00975',
              title: title,
              publisher: 'Rebecca',
              studio: 'Minnano metadata',
              performerCount: 1,
            ),
          },
          detailsByCode: const {},
        );
        final javbus = _FakeScrapeSource(
          id: ScrapeSourceId.javbus,
          detailBirthDate: '1999-01-01',
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.javbus,
              code: 'REBD-975',
              title: title,
              detailUri: Uri.parse(javbusUri),
            ),
          ],
          detailsByUri: {
            javbusUri: const ScrapeWorkDetails(
              source: ScrapeSourceId.javbus,
              code: 'REBD-975',
              title: title,
              publisher: 'Rebecca',
              durationMinutes: 120,
              performerCount: 1,
            ),
          },
          detailsByCode: const {},
        );
        final imageDownloader = _RecordingWorkImageDownloader();
        final service = WorksScrapeService(
          db: database,
          sources: {
            ScrapeSourceId.minnanoAv: minnano,
            ScrapeSourceId.javbus: javbus,
          },
          workImageDownloader: imageDownloader,
          imageDirectory: directory.path,
        );

        final result = await service.scrape(
          actressId: actressId,
          actressName: '河北彩花',
          options: const WorkScrapeOptions(syncDetails: false),
          sourceSettings: const ScrapeSourceSettings(),
        );

        final works = await database.getWorksForActress(actressId);
        expect(result.saved, 1);
        expect(works, hasLength(1));
        expect(works.single['code'], 'REBD-975');
        expect(works.single['studio'], 'Minnano metadata');
        expect(works.single['duration_minutes'], 120);
        expect(imageDownloader.requestedCodes, ['REBD-975', 'REBD-975']);
        expect(minnano.detailUris, [minnanoUri]);
        expect(javbus.detailUris, [javbusUri]);
      });

      test('same title with non-Rebecca publishers stays separate', () async {
        final directory = await Directory.systemTemp.createTemp(
          'avaca_non_rebecca_title_test_',
        );
        final database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await database.close();
          await directory.delete(recursive: true);
        });
        await database.init();
        await database.addActress(name: '河北彩花');
        final actressId =
            (await (await database.database).query('actresses')).single['id']
                as int;
        const title = '同名但非 Rebecca';
        final minnanoUri = 'https://www.minnano-av.com/non-rebecca-a.html';
        final javbusUri = 'https://www.javbus.com/NON-REBECCA-B';
        final minnano = _FakeScrapeSource(
          id: ScrapeSourceId.minnanoAv,
          detailBirthDate: '1999-01-01',
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.minnanoAv,
              code: 'NON-A',
              title: title,
              detailUri: Uri.parse(minnanoUri),
            ),
          ],
          detailsByUri: {
            minnanoUri: const ScrapeWorkDetails(
              source: ScrapeSourceId.minnanoAv,
              code: 'NON-A',
              title: title,
              publisher: 'Other label',
              performerCount: 1,
            ),
          },
          detailsByCode: const {},
        );
        final javbus = _FakeScrapeSource(
          id: ScrapeSourceId.javbus,
          detailBirthDate: '1999-01-01',
          works: [
            ScrapeWorkSummary(
              source: ScrapeSourceId.javbus,
              code: 'NON-B',
              title: title,
              detailUri: Uri.parse(javbusUri),
            ),
          ],
          detailsByUri: {
            javbusUri: const ScrapeWorkDetails(
              source: ScrapeSourceId.javbus,
              code: 'NON-B',
              title: title,
              publisher: 'Other label',
              performerCount: 1,
            ),
          },
          detailsByCode: const {},
        );
        final service = WorksScrapeService(
          db: database,
          sources: {
            ScrapeSourceId.minnanoAv: minnano,
            ScrapeSourceId.javbus: javbus,
          },
          workImageDownloader: _FakeWorkImageDownloader(),
          imageDirectory: directory.path,
        );

        final result = await service.scrape(
          actressId: actressId,
          actressName: '河北彩花',
          options: const WorkScrapeOptions(syncDetails: false),
          sourceSettings: const ScrapeSourceSettings(),
        );

        expect(result.saved, 2);
        expect(
          (await database.getWorksForActress(
            actressId,
          )).map((row) => row['code']),
          unorderedEquals(['NON-A', 'NON-B']),
        );
      });

      test(
        'cancellation stops overlapping pipelines before save or image work',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_overlap_cancellation_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '河北彩花');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          final token = WorksScrapeCancellationToken();
          final minnanoCollectionStarted = Completer<void>();
          final releaseMinnanoCollection = Completer<void>();
          final javbusDetailStarted = Completer<void>();

          final minnano = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1999-01-01',
            beforeSearch: () async {
              if (!minnanoCollectionStarted.isCompleted) {
                minnanoCollectionStarted.complete();
              }
              await releaseMinnanoCollection.future;
            },
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-001',
                title: 'Minnano pending',
                detailUri: Uri.parse('https://www.minnano-av.com/m001.html'),
              ),
            ],
            detailsByCode: {
              'M-001': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'M-001',
                title: 'Minnano pending',
                performerCount: 1,
              ),
            },
          );
          final javbus = _FakeScrapeSource(
            id: ScrapeSourceId.javbus,
            detailBirthDate: '1999-01-01',
            beforeDetail: (_) async {
              if (!javbusDetailStarted.isCompleted) {
                javbusDetailStarted.complete();
              }
              token.cancel();
            },
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'J-001',
                title: 'JavBus cancels',
                detailUri: Uri.parse('https://www.javbus.com/J-001'),
              ),
            ],
            detailsByCode: {
              'J-001': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'J-001',
                title: 'JavBus cancels',
                performerCount: 1,
              ),
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {
              ScrapeSourceId.minnanoAv: minnano,
              ScrapeSourceId.javbus: javbus,
            },
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final scrape = service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(syncDetails: false),
            cancellationToken: token,
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.javbus,
            ),
          );
          await minnanoCollectionStarted.future;
          await javbusDetailStarted.future;
          expect(minnano.detailRequests, isEmpty);
          releaseMinnanoCollection.complete();

          final result = await scrape;
          expect(result.cancelled, isTrue);
          expect(await database.getWorksForActress(actressId), isEmpty);
        },
      );

      test(
        'merge priority is independent of source completion order',
        () async {
          Future<Map<String, Object?>> runScenario({
            required Duration minnanoDelay,
            required Duration javbusDelay,
          }) async {
            final directory = await Directory.systemTemp.createTemp(
              'avaca_completion_order_test_',
            );
            final database = AppDatabase.forTesting(
              baseDir: directory.path,
              databaseFactory: databaseFactoryFfi,
            );
            try {
              await database.init();
              await database.addActress(name: '小湊よつ葉');
              final actressId =
                  (await (await database.database).query(
                        'actresses',
                      )).single['id']
                      as int;
              final minnano = _FakeScrapeSource(
                id: ScrapeSourceId.minnanoAv,
                detailBirthDate: '1996-05-29',
                beforeDetail: (_) => Future<void>.delayed(minnanoDelay),
                works: [
                  ScrapeWorkSummary(
                    source: ScrapeSourceId.minnanoAv,
                    code: 'START-408',
                    title: 'Minnano summary',
                    detailUri: Uri.parse(
                      'https://www.minnano-av.com/start408.html',
                    ),
                  ),
                ],
                detailsByCode: {
                  'START-408': const ScrapeWorkDetails(
                    source: ScrapeSourceId.minnanoAv,
                    code: 'START-408',
                    title: 'Minnano title',
                    studio: 'Minnano studio',
                    performerCount: 1,
                  ),
                },
              );
              final javbus = _FakeScrapeSource(
                id: ScrapeSourceId.javbus,
                detailBirthDate: '1996-05-29',
                beforeDetail: (_) => Future<void>.delayed(javbusDelay),
                works: [
                  ScrapeWorkSummary(
                    source: ScrapeSourceId.javbus,
                    code: 'start-408',
                    title: 'JavBus summary',
                    detailUri: Uri.parse('https://www.javbus.com/START-408'),
                  ),
                ],
                detailsByCode: {
                  'START-408': const ScrapeWorkDetails(
                    source: ScrapeSourceId.javbus,
                    code: 'START-408',
                    title: 'JavBus title',
                    durationMinutes: 120,
                    performerCount: 2,
                  ),
                },
              );
              final service = WorksScrapeService(
                db: database,
                sources: {
                  ScrapeSourceId.minnanoAv: minnano,
                  ScrapeSourceId.javbus: javbus,
                },
                workImageDownloader: _FakeWorkImageDownloader(),
                imageDirectory: directory.path,
              );
              final result = await service.scrape(
                actressId: actressId,
                actressName: '小湊よつ葉',
                options: const WorkScrapeOptions(syncDetails: false),
                sourceSettings: const ScrapeSourceSettings(),
              );
              expect(result.saved, 1);
              return (await database.getWorksForActress(actressId)).single;
            } finally {
              await database.close();
              await directory.delete(recursive: true);
            }
          }

          final minnanoSlow = await runScenario(
            minnanoDelay: const Duration(milliseconds: 30),
            javbusDelay: Duration.zero,
          );
          final javbusSlow = await runScenario(
            minnanoDelay: Duration.zero,
            javbusDelay: const Duration(milliseconds: 30),
          );

          expect(minnanoSlow['code'], 'START-408');
          expect(javbusSlow['code'], 'START-408');
          expect(minnanoSlow['title'], 'Minnano title');
          expect(javbusSlow['title'], 'Minnano title');
          expect(minnanoSlow['studio'], 'Minnano studio');
          expect(javbusSlow['studio'], 'Minnano studio');
          expect(minnanoSlow['duration_minutes'], 120);
          expect(javbusSlow['duration_minutes'], 120);
        },
      );

      test(
        'cancellation before commit does not persist collected details',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_cancel_before_commit_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '小湊よつ葉');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          final token = WorksScrapeCancellationToken();
          final source = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1996-05-29',
            beforeDetail: (_) async => token.cancel(),
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'START-408',
                title: 'Cancelled work',
                detailUri: Uri.parse(
                  'https://www.minnano-av.com/start408.html',
                ),
              ),
            ],
            detailsByCode: {
              'START-408': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'START-408',
                title: 'Cancelled work',
                performerCount: 1,
              ),
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {ScrapeSourceId.minnanoAv: source},
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final result = await service.scrape(
            actressId: actressId,
            actressName: '小湊よつ葉',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.minnanoAv,
            ),
            cancellationToken: token,
          );

          expect(result.cancelled, isTrue);
          expect(await database.getWorksForActress(actressId), isEmpty);
        },
      );

      test(
        'cancellation during actress image sync does not persist the image',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_cancel_actress_sync_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '小湊よつ葉');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;
          final token = WorksScrapeCancellationToken();
          final source = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1996-05-29',
            detailAvatarUrl: Uri.parse(
              'https://www.minnano-av.com/p_actress_125_125/avatar.jpg',
            ),
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'START-408',
                title: 'Cancelled actress sync',
                detailUri: Uri.parse(
                  'https://www.minnano-av.com/start408.html',
                ),
              ),
            ],
            detailsByCode: {
              'START-408': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'START-408',
                title: 'Cancelled actress sync',
                performerCount: 1,
              ),
            },
          );
          final service = WorksScrapeService(
            db: database,
            sources: {ScrapeSourceId.minnanoAv: source},
            actressImageDownloader: _CancellingActressImageDownloader(token),
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );

          final result = await service.scrape(
            actressId: actressId,
            actressName: '小湊よつ葉',
            options: const WorkScrapeOptions(replaceActressImage: true),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.minnanoAv,
            ),
            cancellationToken: token,
          );

          expect(result.cancelled, isTrue);
          expect(result.saved, 0);
          expect(await database.getWorksForActress(actressId), isEmpty);
          final actressDirectory = Directory('${directory.path}/actresses');
          final files = actressDirectory.existsSync()
              ? actressDirectory.listSync().whereType<File>()
              : const <File>[];
          expect(files, isEmpty);
        },
      );

      test('details-only source cannot mask a failed works source', () async {
        final directory = await Directory.systemTemp.createTemp(
          'avaca_multi_source_failure_state_test_',
        );
        final database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await database.close();
          await directory.delete(recursive: true);
        });
        await database.init();
        await database.addActress(name: '河北彩花');
        final actressId =
            (await (await database.database).query('actresses')).single['id']
                as int;

        final minnano = _FakeScrapeSource(
          id: ScrapeSourceId.minnanoAv,
          detailBirthDate: '1999-01-01',
          works: const [],
          detailsByCode: const {},
        );
        final javbus = _FakeScrapeSource(
          id: ScrapeSourceId.javbus,
          detailBirthDate: '1999-01-01',
          works: const [],
          detailsByCode: const {},
          failWorks: true,
        );
        final service = WorksScrapeService(
          db: database,
          sources: {
            ScrapeSourceId.minnanoAv: minnano,
            ScrapeSourceId.javbus: javbus,
          },
          workImageDownloader: _FakeWorkImageDownloader(),
          imageDirectory: directory.path,
        );

        expect(
          () => service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.minnanoAv,
              worksSource: WorksSourceSelection.javbus,
            ),
          ),
          throwsA(isA<WorksScrapeException>()),
        );
      });
      test(
        'merges safe code forms and hides a matched source detail failure',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'avaca_new_identity_merge_test_',
          );
          final database = AppDatabase.forTesting(
            baseDir: directory.path,
            databaseFactory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await database.close();
            await directory.delete(recursive: true);
          });
          await database.init();
          await database.addActress(name: '河北彩花');
          final actressId =
              (await (await database.database).query('actresses')).single['id']
                  as int;

          final minnano = _FakeScrapeSource(
            id: ScrapeSourceId.minnanoAv,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875',
                releaseDate: '2026-01-01',
                detailUri: Uri.parse('https://www.minnano-av.com/ssis875.html'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.minnanoAv,
                code: null,
                title: '新人河北彩花作品',
                releaseDate: '2026-02-01',
                detailUri: Uri.parse('https://www.minnano-av.com/no-code.html'),
              ),
            ],
            detailsByCode: {
              'SSIS-875': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: 'SSIS875',
                title: 'SSIS 875',
                releaseDate: '2026-01-01',
                publisher: 'SODSTAR',
                performerCount: 1,
              ),
              '': const ScrapeWorkDetails(
                source: ScrapeSourceId.minnanoAv,
                code: '',
                title: '新人河北彩花作品',
                releaseDate: '2026-02-01',
                publisher: 'SODSTAR',
                performerCount: 1,
              ),
            },
          );
          final javbus = _FakeScrapeSource(
            id: ScrapeSourceId.javbus,
            detailBirthDate: '1999-01-01',
            works: [
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'SSIS-875',
                title: 'SSIS 875',
                releaseDate: '2026-01-01',
                detailUri: Uri.parse('https://www.javbus.com/SSIS-875'),
              ),
              ScrapeWorkSummary(
                source: ScrapeSourceId.javbus,
                code: 'SSNI-190',
                title: '新人河北彩花作品',
                releaseDate: '2026-02-01',
                detailUri: Uri.parse('https://www.javbus.com/SSNI-190'),
              ),
            ],
            detailsByCode: {
              'SSNI-190': const ScrapeWorkDetails(
                source: ScrapeSourceId.javbus,
                code: 'SSNI-190',
                title: '新人河北彩花作品',
                releaseDate: '2026-02-01',
                publisher: 'SODSTAR',
                performerCount: 1,
              ),
            },
            failingCodes: {'SSIS-875'},
          );
          final service = WorksScrapeService(
            db: database,
            sources: {
              ScrapeSourceId.minnanoAv: minnano,
              ScrapeSourceId.javbus: javbus,
            },
            workImageDownloader: _FakeWorkImageDownloader(),
            imageDirectory: directory.path,
          );
          final progress = <WorksScrapeProgress>[];

          final result = await service.scrape(
            actressId: actressId,
            actressName: '河北彩花',
            options: const WorkScrapeOptions(syncDetails: false),
            sourceSettings: const ScrapeSourceSettings(),
            onProgress: progress.add,
          );

          expect(result.saved, 2);
          expect(result.failed, 0);
          expect(result.failedWorks, isEmpty);
          expect(
            (await database.getWorksForActress(
              actressId,
            )).map((row) => row['code']),
            unorderedEquals(['SSIS-875', 'SSNI-190']),
          );
          expect(
            result.sourceResults[ScrapeSourceId.javbus]?.state,
            ScrapeSourceRunState.partial,
          );
          expect(
            result.sourceResults[ScrapeSourceId.javbus]?.error.toString(),
            contains('www.javbus.com/SSIS-875'),
          );
          final sourceSnapshot = progress.lastWhere(
            (item) => item.sourceProgress.length == 2,
          );
          expect(
            sourceSnapshot.sourceProgress.keys,
            containsAll([ScrapeSourceId.minnanoAv, ScrapeSourceId.javbus]),
          );
          expect(
            sourceSnapshot.sourceProgress.values,
            everyElement(isA<WorksScrapeSourceProgress>()),
          );
        },
      );
    },
    skip:
        'Superseded by JavBus-only works scraping and exact code/URI identity.',
  );

  test(
    'new scraper collapses V T VT editions and fetches the ordinary page',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_special_edition_code_test_',
      );
      final database = AppDatabase.forTesting(
        baseDir: directory.path,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      await database.init();
      await database.addActress(name: '小湊よつ葉');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;
      final specialUri = Uri.parse('https://www.javbus.com/START-053-VT');
      final ordinaryUri = Uri.parse('https://www.javbus.com/START-053');
      final source = _FakeScrapeSource(
        id: ScrapeSourceId.javbus,
        detailBirthDate: '1997-01-01',
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'START-053-VT',
            title: '特典版',
            detailUri: specialUri,
          ),
          ScrapeWorkSummary(
            source: ScrapeSourceId.javbus,
            code: 'START-053',
            title: '一般版',
            detailUri: ordinaryUri,
          ),
        ],
        detailsByCode: const {},
        detailsByUri: {
          specialUri.toString(): const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'START-053-VT',
            rawCode: 'START-053-VT',
            title: '特典版',
            performerCount: 1,
          ),
          ordinaryUri.toString(): const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'START-053',
            rawCode: 'START-053',
            title: '一般版',
            performerCount: 1,
          ),
        },
      );
      final service = WorksScrapeService(
        db: database,
        sources: {ScrapeSourceId.javbus: source},
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(syncDetails: false),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
          worksSource: WorksSourceSelection.javbus,
        ),
      );

      expect(result.saved, 1);
      expect(source.detailUris, [ordinaryUri.toString()]);
      expect(
        (await database.getWorksForActress(actressId)).single['code'],
        'START-053',
      );
      expect(
        (await database.getWorksForActress(actressId)).single['title'],
        '一般版',
      );
    },
  );
}

final class _FakeScrapeSource implements ScrapeSource {
  _FakeScrapeSource({
    required this.id,
    required this.detailBirthDate,
    required this.works,
    required this.detailsByCode,
    this.detailsByUri = const {},
    this.failingCodes = const {},
    this.failWorks = false,
    this.beforeSearch,
    this.beforeDetail,
    this.detailAvatarUrl,
  });

  @override
  final ScrapeSourceId id;
  final String detailBirthDate;
  final List<ScrapeWorkSummary> works;
  final Map<String, ScrapeWorkDetails> detailsByCode;
  final Map<String, ScrapeWorkDetails> detailsByUri;
  final Set<String> failingCodes;
  final bool failWorks;
  final Future<void> Function()? beforeSearch;
  final Future<void> Function(String code)? beforeDetail;
  final Uri? detailAvatarUrl;
  final detailRequests = <String>[];
  final detailUris = <String>[];

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    await beforeSearch?.call();
    return [
      ScrapeActressSearchResult(
        source: id,
        name: name,
        uri: Uri.parse(
          id == ScrapeSourceId.minnanoAv
              ? 'https://www.minnano-av.com/actress618082.html'
              : 'https://www.javbus.com/star/618082',
        ),
      ),
    ];
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    return ScrapeActressPage(
      source: id,
      details: ScrapedActressDetails(
        name: '小湊よつ葉',
        birthDate: detailBirthDate,
        avatarUrl: detailAvatarUrl,
      ),
      works: works,
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
  }) async {
    if (failWorks) {
      throw StateError('simulated works traversal failure');
    }
    return firstPage.works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final code = canonicalizeWorkCode(work.code) ?? '';
    detailRequests.add(code);
    detailUris.add(work.detailUri.toString());
    await beforeDetail?.call(code);
    if (failingCodes.contains(code)) {
      throw StateError('simulated failure');
    }
    final details =
        detailsByUri[work.detailUri.toString()] ?? detailsByCode[code];
    if (details == null) {
      throw StateError('missing fake details');
    }
    return details;
  }

  @override
  bool acceptsImageUri(Uri uri) =>
      uri.host == 'www.minnano-av.com' || uri.host == 'www.javbus.com';

  @override
  void close() {}
}

final class _RecordingScrapeImageUriDownloader
    implements ScrapeImageUriDownloader {
  final requested = <Uri>[];

  @override
  Future<String> download({
    required Uri uri,
    required String targetPath,
  }) async {
    requested.add(uri);
    return targetPath;
  }

  @override
  void close() {}
}

final class _CancellingActressImageDownloader
    implements ActressImageDownloader {
  _CancellingActressImageDownloader(this.token);

  final WorksScrapeCancellationToken token;

  @override
  Future<String> download(Uri uri, String targetPath) async {
    token.cancel();
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return file.path;
  }
}

class _FakeWorkImageDownloader extends WorkImageDownloader {
  _FakeWorkImageDownloader() : super(transport: _NoBinaryTransport());

  @override
  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> originalImageEvidenceUris = const [],
    WorkImageRouteResolution? route,
    required WorkImageVariant variant,
    required String targetPath,
  }) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return DownloadedWorkImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      sourceUri: Uri.parse('https://example.test/$code.jpg'),
    );
  }
}

final class _RecordingWorkImageDownloader extends _FakeWorkImageDownloader {
  final requestedCodes = <String>[];

  @override
  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> originalImageEvidenceUris = const [],
    WorkImageRouteResolution? route,
    required WorkImageVariant variant,
    required String targetPath,
  }) {
    requestedCodes.add(code);
    return super.downloadToFile(
      code: code,
      studio: studio,
      publisher: publisher,
      originalImageEvidenceUris: originalImageEvidenceUris,
      route: route,
      variant: variant,
      targetPath: targetPath,
    );
  }
}

final class _BlockingWorkImageDownloader extends WorkImageDownloader {
  _BlockingWorkImageDownloader() : super(transport: _NoBinaryTransport());

  final firstImageStarted = Completer<void>();
  final _release = Completer<void>();
  var _blocked = false;

  void releaseFirstImage() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> originalImageEvidenceUris = const [],
    WorkImageRouteResolution? route,
    required WorkImageVariant variant,
    required String targetPath,
  }) async {
    if (!_blocked) {
      _blocked = true;
      firstImageStarted.complete();
      await _release.future;
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return DownloadedWorkImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      sourceUri: Uri.parse('https://example.test/$code.jpg'),
    );
  }
}

final class _FailingWorkImageDownloader extends WorkImageDownloader {
  _FailingWorkImageDownloader() : super(transport: _NoBinaryTransport());

  @override
  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> originalImageEvidenceUris = const [],
    WorkImageRouteResolution? route,
    required WorkImageVariant variant,
    required String targetPath,
  }) {
    throw StateError('simulated image failure');
  }
}

final class _NoBinaryTransport implements BinaryTransport {
  @override
  Future<BinaryResponse> get(Uri uri) =>
      throw StateError('unexpected binary request: $uri');
}
