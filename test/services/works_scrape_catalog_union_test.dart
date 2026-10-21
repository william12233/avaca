import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_source.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'unions all enabled catalogs and saves each canonical work once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_catalog_union_test_',
      );
      final database = AppDatabase.forTesting(
        baseDir: directory.path,
        databaseFactory: databaseFactoryFfi,
      );
      await database.init();
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      await database.addActress(name: '測試女優');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;

      final primaryCodes = List<String>.generate(
        100,
        (index) => 'UNION-${(index + 1).toString().padLeft(3, '0')}',
      );
      final secondaryCodes = List<String>.generate(
        20,
        (index) => 'UNION-${(index + 91).toString().padLeft(3, '0')}',
      );
      final primary = _UnionSource(ScrapeSourceId.javbus, primaryCodes);
      final secondary = _UnionSource(ScrapeSourceId.avbase, secondaryCodes);
      final service = WorksScrapeService(
        db: database,
        sources: {primary.id: primary, secondary.id: secondary},
        workImageDownloader: _NoopWorkImageDownloader(),
        imageDirectory: directory.path,
        javBusDetailDelay: Duration.zero,
      );
      addTearDown(service.close);
      final progress = <WorksScrapeProgress>[];

      final result = await service.scrape(
        actressId: actressId,
        actressName: '測試女優',
        options: const WorkScrapeOptions(syncDetails: false),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
          worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
        ),
        onProgress: progress.add,
      );

      expect(result.saved, 110);
      expect(result.excluded, 0);
      expect(result.failed, 0);
      expect(primary.worksCalls, 1);
      expect(secondary.worksCalls, 1);
      expect(primary.detailCalls, 100);
      expect(secondary.detailCalls, 10);
      expect(await database.getWorkCountForActress(actressId), 110);
      expect(progress.any((item) => item.rawDiscovered == 120), isTrue);
      expect(progress.any((item) => item.duplicateCount == 10), isTrue);
    },
  );

  test('keeps a usable catalog when another enabled source fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_catalog_partial_test_',
    );
    final database = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    await database.init();
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    await database.addActress(name: '部分來源女優');
    final actressId =
        (await (await database.database).query('actresses')).single['id']
            as int;

    final failed = _UnionSource(ScrapeSourceId.javbus, const [
      'PARTIAL-001',
    ], failSearch: true);
    final usable = _UnionSource(ScrapeSourceId.avbase, const [
      'PARTIAL-001',
      'PARTIAL-002',
    ]);
    final service = WorksScrapeService(
      db: database,
      sources: {failed.id: failed, usable.id: usable},
      workImageDownloader: _NoopWorkImageDownloader(),
      imageDirectory: directory.path,
      javBusDetailDelay: Duration.zero,
    );
    addTearDown(service.close);

    final result = await service.scrape(
      actressId: actressId,
      actressName: '部分來源女優',
      options: const WorkScrapeOptions(syncDetails: false),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
        worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
      ),
    );

    expect(result.saved, 2);
    expect(result.partialSuccess, isTrue);
    expect(
      result.sourceResults[ScrapeSourceId.javbus]?.state,
      ScrapeSourceRunState.failed,
    );
    expect(
      result.sourceResults[ScrapeSourceId.avbase]?.state,
      ScrapeSourceRunState.success,
    );
    expect(await database.getWorkCountForActress(actressId), 2);
  });
}

final class _UnionSource implements ScrapeSource {
  _UnionSource(this.id, List<String> codes, {this.failSearch = false})
    : summaries = [
        for (final code in codes)
          ScrapeWorkSummary(
            source: id,
            code: code,
            title: code,
            detailUri: Uri.parse(
              'https://example.test/${id.storageValue}/works/$code',
            ),
          ),
      ];

  @override
  final ScrapeSourceId id;
  final List<ScrapeWorkSummary> summaries;
  final bool failSearch;
  var worksCalls = 0;
  var detailCalls = 0;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    if (failSearch) throw StateError('Synthetic source failure.');
    return [
      ScrapeActressSearchResult(
        source: id,
        name: name,
        uri: Uri.parse('https://example.test/${id.storageValue}/actress'),
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
      works: summaries,
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
    void Function(ScrapeCollectionProgress progress)? onProgress,
  }) async {
    worksCalls++;
    onProgress?.call(
      ScrapeCollectionProgress(
        currentPage: 1,
        totalPages: 1,
        discovered: summaries.length,
      ),
    );
    return firstPage.works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    detailCalls++;
    final code = work.code!;
    return ScrapeWorkDetails(source: id, code: code, title: '$id $code');
  }

  @override
  bool acceptsImageUri(Uri uri) => false;

  @override
  void close() {}
}

final class _NoopWorkImageDownloader extends WorkImageDownloader {
  _NoopWorkImageDownloader() : super(transport: _NoBinaryTransport());

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
