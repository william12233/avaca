import 'dart:async';
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

  test('ordered sources use one complete record and honor priority', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_avbase_merge_test_',
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
    await database.addActress(name: '測試女優');
    final actressId =
        (await (await database.database).query('actresses')).single['id']
            as int;

    final service = WorksScrapeService(
      db: database,
      sources: {
        ScrapeSourceId.javbus: _FakeScrapeSource(
          id: ScrapeSourceId.javbus,
          title: 'JavBus 標題',
          studio: null,
          durationMinutes: 10,
          performerCount: 1,
        ),
        ScrapeSourceId.avbase: _FakeScrapeSource(
          id: ScrapeSourceId.avbase,
          title: 'AvBase 標題',
          studio: 'AvBase 補上的片商',
          series: 'AvBase 系列',
          durationMinutes: 20,
          performerCount: 3,
          aliases: const ['測試女優', '別名 A'],
        ),
      },
      workImageDownloader: _FakeWorkImageDownloader(),
      imageDirectory: directory.path,
      javBusDetailDelay: Duration.zero,
    );
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
    expect(result.saved, 1);
    expect(result.failed, 0);
    expect(
      progress.any(
        (item) =>
            item.phase == WorksScrapePhase.fetchingDetails &&
            item.source == ScrapeSourceId.javbus &&
            item.sourceProgress[ScrapeSourceId.javbus]?.current == 1,
      ),
      isTrue,
      reason: 'JavBus detail progress must leave 0 after its request ends.',
    );
    expect(result.worksSources, [ScrapeSourceId.javbus, ScrapeSourceId.avbase]);
    expect(await database.getWorkCountForActress(actressId), 1);
    final work = (await database.getWorksForActress(actressId)).single;
    expect(work['code'], 'ABC-123');
    expect(work['title'], 'JavBus 標題');
    expect(work['studio'], isNull);
    expect(work['series'], isNull);
    expect(work['duration_minutes'], 10);

    // Reversing priority chooses AvBase as one complete record. Lower
    // priority JavBus data does not fill or override it.
    final repeatedResult = await service.scrape(
      actressId: actressId,
      actressName: '測試女優',
      options: const WorkScrapeOptions(syncDetails: false),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
        worksSources: [ScrapeSourceId.avbase, ScrapeSourceId.javbus],
      ),
    );
    expect(repeatedResult.saved, 1);
    expect(repeatedResult.excluded, 0);

    final anotherRepeatedResult = await service.scrape(
      actressId: actressId,
      actressName: '測試女優',
      options: const WorkScrapeOptions(syncDetails: false),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
        worksSources: [ScrapeSourceId.avbase, ScrapeSourceId.javbus],
      ),
    );
    expect(anotherRepeatedResult.saved, 1);
    expect(anotherRepeatedResult.excluded, 0);

    await database.replaceActressAliases(
      actressId: actressId,
      aliases: const ['舊別名'],
    );
    final aliasResult = await service.scrape(
      actressId: actressId,
      actressName: '測試女優',
      options: const WorkScrapeOptions(syncDetails: false, scrapeAliases: true),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
        worksSources: [ScrapeSourceId.javbus],
      ),
    );
    expect(aliasResult.saved, 1);
    expect(await database.getActressAliases(actressId), ['別名 A', '舊別名']);
    service.close();
  });

  test('falls back to the next source as one complete record', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_source_fallback_test_',
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
    await database.addActress(name: '測試女優');
    final actressId =
        (await (await database.database).query('actresses')).single['id']
            as int;
    final javbus = _FakeScrapeSource(
      id: ScrapeSourceId.javbus,
      title: '高順位但失敗',
      studio: null,
      durationMinutes: 10,
      performerCount: 1,
      failDetails: true,
    );
    final avbase = _FakeScrapeSource(
      id: ScrapeSourceId.avbase,
      title: 'AvBase 完整記錄',
      studio: 'AvBase 片商',
      series: 'AvBase 系列',
      durationMinutes: 20,
      performerCount: 1,
    );
    final service = WorksScrapeService(
      db: database,
      sources: {ScrapeSourceId.javbus: javbus, ScrapeSourceId.avbase: avbase},
      workImageDownloader: _FakeWorkImageDownloader(),
      imageDirectory: directory.path,
      javBusDetailDelay: Duration.zero,
    );
    addTearDown(service.close);

    final result = await service.scrape(
      actressId: actressId,
      actressName: '測試女優',
      options: const WorkScrapeOptions(syncDetails: false),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
        worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
      ),
    );

    expect(result.saved, 1);
    expect(result.partialSuccess, isTrue);
    expect(javbus.detailRequests, 1);
    expect(avbase.detailRequests, 1);
    final work = (await database.getWorksForActress(actressId)).single;
    expect(work['title'], 'AvBase 完整記錄');
    expect(work['studio'], 'AvBase 片商');
    expect(work['series'], 'AvBase 系列');
  });

  test('waits for enabled catalog union before resolving details', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_list_barrier_test_',
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
    await database.addActress(name: '測試女優');
    final actressId =
        (await (await database.database).query('actresses')).single['id']
            as int;
    final gate = Completer<void>();
    final started = Completer<void>();
    final javbus = _FakeScrapeSource(
      id: ScrapeSourceId.javbus,
      title: 'JavBus',
      studio: null,
      durationMinutes: 10,
      performerCount: 1,
    );
    final avbase = _FakeScrapeSource(
      id: ScrapeSourceId.avbase,
      title: 'AvBase',
      studio: null,
      durationMinutes: 10,
      performerCount: 1,
      worksGate: gate,
      worksStarted: started,
    );
    final service = WorksScrapeService(
      db: database,
      sources: {ScrapeSourceId.javbus: javbus, ScrapeSourceId.avbase: avbase},
      workImageDownloader: _FakeWorkImageDownloader(),
      imageDirectory: directory.path,
      javBusDetailDelay: Duration.zero,
    );
    addTearDown(service.close);

    final scrape = service.scrape(
      actressId: actressId,
      actressName: '測試女優',
      options: const WorkScrapeOptions(syncDetails: false),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
        worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
      ),
    );
    await started.future;
    await Future<void>.delayed(Duration.zero);
    expect(javbus.detailRequests, 0);
    expect(avbase.detailRequests, 0);
    gate.complete();
    expect((await scrape).saved, 1);
    expect(javbus.detailRequests, 1);
  });

  test(
    'stores a special edition suffix when no ordinary edition exists',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_special_only_test_',
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
      await database.addActress(name: '測試女優');
      final actressId =
          (await (await database.database).query('actresses')).single['id']
              as int;
      final source = _FakeScrapeSource(
        id: ScrapeSourceId.javbus,
        code: 'START-276V',
        title: '只有典藏版',
        studio: null,
        durationMinutes: 10,
        performerCount: 1,
      );
      final service = WorksScrapeService(
        db: database,
        sources: {ScrapeSourceId.javbus: source},
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
        javBusDetailDelay: Duration.zero,
      );
      addTearDown(service.close);
      final result = await service.scrape(
        actressId: actressId,
        actressName: '測試女優',
        options: const WorkScrapeOptions(syncDetails: false),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
        ),
      );
      expect(result.saved, 1);
      expect(
        (await database.getWorksForActress(actressId)).single['code'],
        'START-276',
      );
    },
  );
}

final class _FakeScrapeSource implements ScrapeSource {
  _FakeScrapeSource({
    required this.id,
    required this.title,
    required this.studio,
    this.series,
    required this.durationMinutes,
    required this.performerCount,
    this.aliases = const [],
    this.code = 'ABC-123',
    this.failDetails = false,
    this.worksGate,
    this.worksStarted,
  });

  @override
  final ScrapeSourceId id;
  final String title;
  final String? studio;
  final String? series;
  final int durationMinutes;
  final int performerCount;
  final List<String> aliases;
  final String code;
  final bool failDetails;
  final Completer<void>? worksGate;
  final Completer<void>? worksStarted;
  int detailRequests = 0;

  final _actressUri = Uri.parse('https://example.test/talents/test');
  Uri get _workUri => Uri.parse('https://example.test/works/$code');

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    return [
      ScrapeActressSearchResult(source: id, name: name, uri: _actressUri),
    ];
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    return ScrapeActressPage(
      source: id,
      details: const ScrapedActressDetails(name: '測試女優'),
      aliases: aliases,
      works: [
        ScrapeWorkSummary(
          source: id,
          code: code,
          title: title,
          detailUri: _workUri,
          releaseDate: '2026-08-20',
        ),
      ],
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
    void Function(ScrapeCollectionProgress progress)? onProgress,
  }) async {
    if (worksStarted?.isCompleted == false) worksStarted!.complete();
    await worksGate?.future;
    return firstPage.works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    detailRequests++;
    if (failDetails) throw StateError('simulated detail failure');
    return ScrapeWorkDetails(
      source: id,
      code: id == ScrapeSourceId.avbase ? code.toLowerCase() : code,
      title: title,
      releaseDate: id == ScrapeSourceId.javbus ? '2026-08-20' : null,
      durationMinutes: durationMinutes,
      studio: studio,
      series: series,
      performerCount: performerCount,
    );
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
