import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scrape_work_category.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/javbus_client.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:avaca/services/minnano/minnano_transport.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_source.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'supplements unknown category evidence with direct code lookups',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_category_evidence_lookup_test_',
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
      await database.addActress(name: '分類補查');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;

      final primary = _CategoryEvidenceSource(
        id: ScrapeSourceId.avwiki,
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.avwiki,
            code: 'AUTO-001',
            title: '分類補查作品',
            detailUri: Uri.parse('https://av-wiki.net/auto-001/'),
          ),
        ],
        detailsByCode: {
          'AUTO-001': const ScrapeWorkDetails(
            source: ScrapeSourceId.avwiki,
            code: 'AUTO-001',
            title: '分類補查作品',
          ),
        },
      );
      final evidence = _CategoryEvidenceSource(
        id: ScrapeSourceId.avbase,
        detailsByCode: {
          'AUTO-001': const ScrapeWorkDetails(
            source: ScrapeSourceId.avbase,
            code: 'AUTO-001',
            title: '分類補查作品',
            genres: ['單體'],
          ),
        },
      );
      final progress = <WorksScrapeProgress>[];
      final service = WorksScrapeService(
        db: database,
        sources: {
          ScrapeSourceId.avwiki: primary,
          ScrapeSourceId.avbase: evidence,
        },
        categoryEvidenceSources: const [ScrapeSourceId.avbase],
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '分類補查',
        options: const WorkScrapeOptions(
          syncDetails: false,
          selectedCategories: [ScrapeWorkCategory.single],
        ),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.avwiki,
          worksSources: [ScrapeSourceId.avwiki],
        ),
        onProgress: progress.add,
      );

      expect(result.saved, 1);
      expect(result.review, 0);
      expect(result.failed, 0);
      expect(result.partialSuccess, isFalse);
      expect(primary.detailRequests, ['AUTO-001']);
      expect(evidence.detailRequests, ['AUTO-001']);
      expect(evidence.searchRequests, 0);
      expect(
        progress.any(
          (item) =>
              item.supplementalEvidenceCompleted == 1 &&
              item.supplementalEvidenceTotal == 1,
        ),
        isTrue,
      );
    },
  );

  test(
    'skips JavBus verification during optional category evidence lookup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_category_evidence_verification_test_',
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
      await database.addActress(name: '分類驗證');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;

      final primary = _CategoryEvidenceSource(
        id: ScrapeSourceId.avwiki,
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.avwiki,
            code: 'VERIFY-001',
            title: '等待人工驗證',
            detailUri: Uri.parse('https://av-wiki.net/verify-001/'),
          ),
        ],
        detailsByCode: {
          'VERIFY-001': const ScrapeWorkDetails(
            source: ScrapeSourceId.avwiki,
            code: 'VERIFY-001',
            title: '等待人工驗證',
          ),
        },
      );
      final javbus = _CategoryEvidenceSource(
        id: ScrapeSourceId.javbus,
        lookupError: JavBusVerificationRequiredException(
          Uri.parse('https://www.javbus.com/verify-001'),
        ),
      );
      final service = WorksScrapeService(
        db: database,
        sources: {
          ScrapeSourceId.avwiki: primary,
          ScrapeSourceId.javbus: javbus,
        },
        categoryEvidenceSources: const [ScrapeSourceId.javbus],
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '分類驗證',
        options: const WorkScrapeOptions(
          syncDetails: false,
          selectedCategories: [ScrapeWorkCategory.single],
        ),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.avwiki,
          worksSources: [ScrapeSourceId.avwiki],
        ),
      );

      expect(result.saved, 1);
      expect(result.review, 1);
      expect(result.failed, 0);
      expect(result.partialSuccess, isFalse);
    },
  );

  test(
    'keeps a configured Minnano source failure partial after classifying 403',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_minnano_blocked_source_test_',
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
      await database.addActress(name: '來源被擋');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;

      final primary = _CategoryEvidenceSource(
        id: ScrapeSourceId.avwiki,
        works: [
          ScrapeWorkSummary(
            source: ScrapeSourceId.avwiki,
            code: 'BLOCKED-001',
            title: '仍可取得的作品',
            detailUri: Uri.parse('https://av-wiki.net/blocked-001/'),
          ),
        ],
        detailsByCode: {
          'BLOCKED-001': const ScrapeWorkDetails(
            source: ScrapeSourceId.avwiki,
            code: 'BLOCKED-001',
            title: '仍可取得的作品',
          ),
        },
      );
      final blocked = _CategoryEvidenceSource(
        id: ScrapeSourceId.minnanoAv,
        searchError: MinnanoRequestException(
          Uri.parse('https://www.minnano-av.com/search_result.php'),
          403,
          kind: MinnanoFailureKind.blocked,
        ),
      );
      final service = WorksScrapeService(
        db: database,
        sources: {
          ScrapeSourceId.avwiki: primary,
          ScrapeSourceId.minnanoAv: blocked,
        },
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '來源被擋',
        options: const WorkScrapeOptions(syncDetails: false),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.minnanoAv,
          worksSources: [ScrapeSourceId.avwiki],
        ),
      );

      expect(result.saved, 1);
      expect(result.partialSuccess, isTrue);
      expect(
        result.sourceResults[ScrapeSourceId.minnanoAv]?.state,
        ScrapeSourceRunState.blocked,
      );
    },
  );
}

final class _CategoryEvidenceSource
    implements ScrapeSource, ScrapeSourceWorkCodeLookup {
  _CategoryEvidenceSource({
    required this.id,
    this.works = const [],
    this.detailsByCode = const {},
    this.lookupError,
    this.searchError,
  });

  @override
  final ScrapeSourceId id;
  final List<ScrapeWorkSummary> works;
  final Map<String, ScrapeWorkDetails> detailsByCode;
  final Object? lookupError;
  final Object? searchError;
  final detailRequests = <String>[];
  var searchRequests = 0;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    final error = searchError;
    if (error != null) throw error;
    searchRequests++;
    return [
      ScrapeActressSearchResult(
        source: id,
        name: name,
        uri: Uri.parse('https://example.test/actress/$name'),
      ),
    ];
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    return ScrapeActressPage(
      source: id,
      details: const ScrapedActressDetails(name: '測試女優'),
      works: works,
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
    void Function(ScrapeCollectionProgress progress)? onProgress,
  }) async {
    return firstPage.works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final code = work.code ?? '';
    detailRequests.add(code);
    final details = detailsByCode[code];
    if (details == null) throw StateError('Missing details for $code.');
    return details;
  }

  @override
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(
    String canonicalCode,
  ) async {
    detailRequests.add(canonicalCode);
    final error = lookupError;
    if (error != null) throw error;
    return detailsByCode[canonicalCode];
  }

  @override
  bool acceptsImageUri(Uri uri) => false;

  @override
  void close() {}
}

final class _FakeWorkImageDownloader extends WorkImageDownloader {
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

final class _NoBinaryTransport implements BinaryTransport {
  @override
  Future<BinaryResponse> get(Uri uri) =>
      throw StateError('Unexpected binary request: $uri');
}
