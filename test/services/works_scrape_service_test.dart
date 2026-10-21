import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/javbus/javbus_client.dart';
import 'package:avaca/services/javbus/javbus_models.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:avaca/services/scrape_run_observer.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'authenticated avatar downloader accepts a valid 125x125 image',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_authenticated_avatar_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final session = _FakeJavBusBinarySession(
        BinaryResponse(
          statusCode: 200,
          bodyBytes: image.encodeJpg(image.Image(width: 125, height: 125)),
        ),
      );
      final target = '${directory.path}${Platform.pathSeparator}avatar.jpg';

      final result =
          await HttpActressImageDownloader(
            authenticatedTransport: session,
          ).download(
            Uri.parse('https://www.javbus.com/pics/actress/zh5_a.jpg'),
            target,
          );

      expect(session.requested.single.path, '/pics/actress/zh5_a.jpg');
      expect(result, target);
      expect(File(target).existsSync(), isTrue);
    },
  );

  test(
    'scrapes exact actress and keeps prefix-like codes by default',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_service_test_',
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
      await database.addActress(name: '涼森れむ');
      final sqlite = await database.database;
      final actressId = (await sqlite.query('actresses')).single['id'] as int;
      final oldAvatar = File(
        '${directory.path}${Platform.pathSeparator}actresses'
        '${Platform.pathSeparator}actress_${actressId}_old.jpg',
      );
      await oldAvatar.parent.create(recursive: true);
      await oldAvatar.writeAsBytes([9]);
      await sqlite.update(
        'actresses',
        {'img_path': oldAvatar.path},
        where: 'id = ?',
        whereArgs: [actressId],
      );
      final client = _FakeJavBusClient();
      final workImages = _FakeWorkImageDownloader();
      final actressImages = _FakeActressImageDownloader();
      final observer = _RecordingScrapeObserver();
      final service = WorksScrapeService(
        db: database,
        client: client,
        workImageDownloader: workImages,
        actressImageDownloader: actressImages,
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '涼森れむ',
        options: const WorkScrapeOptions(replaceActressImage: true),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
        ),
        observer: observer,
      );

      expect(client.detailRequests, ['ABF-367', 'FC2-PPV_123-999']);
      expect(workImages.targetPaths.map(path.basename), [
        'abf00367ps.jpg',
        'abf00367pl.jpg',
        'fc2_ppv_123_999ps.jpg',
        'fc2_ppv_123_999pl.jpg',
      ]);
      expect(await database.getWorkCountForActress(actressId), 2);
      final works = await database.getWorksForActress(actressId);
      final ordinary = works.singleWhere((work) => work['code'] == 'ABF-367');
      expect(ordinary['studio'], 'プレステージ');
      expect(File(ordinary['card_image_path']! as String).existsSync(), isTrue);
      expect(
        File(ordinary['detail_image_path']! as String).existsSync(),
        isTrue,
      );
      final relatedPerformers =
          ((await database.getWorkById(
                    ordinary['id']! as int,
                  ))!['related_performers']!
                  as List)
              .cast<Map<String, Object?>>();
      expect(
        relatedPerformers.map((performer) => performer['name']),
        unorderedEquals(['追加女優', '涼森れむ']),
      );
      expect(
        (await database.getActressById(actressId))?['img_path'],
        isNotEmpty,
      );
      expect(oldAvatar.existsSync(), isFalse);
      expect(result.saved, 2);
      expect(result.excluded, 0);
      expect(result.actressImageStatus, ActressImageSyncStatus.replaced);
      expect(
        observer.outcomes,
        contains(const (code: 'ABF-367', state: ScrapeWorkOutcomeState.saved)),
      );
    },
  );

  test('reports image work separately after all details are ready', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_javbus_image_overlap_test_',
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
    await database.addActress(name: '涼森?��?');
    final actressId =
        (await (await database.database).query('actresses')).single['id']
            as int;
    final images = _OverlapWorkImageDownloader();
    final client = _OverlapJavBusClient();
    final progress = <WorksScrapeProgress>[];
    final service = WorksScrapeService(
      db: database,
      client: client,
      workImageDownloader: images,
      imageDirectory: directory.path,
      javBusDetailDelay: Duration.zero,
    );

    final scrape = service.scrape(
      actressId: actressId,
      actressName: '涼森?��?',
      options: const WorkScrapeOptions(syncDetails: false),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
      ),
      onProgress: progress.add,
    );

    await images.firstDownloadStarted.future;
    expect(client.detailRequests, ['OVR-001', 'OVR-002']);
    final firstImageProgress = progress.firstWhere(
      (item) => item.phase == WorksScrapePhase.downloadingImages,
    );
    expect(firstImageProgress.current, 0);
    expect(firstImageProgress.total, 2);
    expect(firstImageProgress.totalKnown, isTrue);
    expect(
      firstImageProgress.sourceProgress[ScrapeSourceId.javbus]?.current,
      0,
    );
    expect(firstImageProgress.sourceProgress[ScrapeSourceId.javbus]?.total, 2);

    images.releaseFirstDownload();
    final result = await scrape;
    expect(result.saved, 2);
    expect(result.failed, 0);
    expect(images.maxActive, greaterThan(1));
    final imageProgress = progress
        .where((item) => item.phase == WorksScrapePhase.downloadingImages)
        .map((item) => item.current)
        .toList();
    expect(imageProgress, containsAll(<int>[0, 1]));
    expect(imageProgress, isNot(contains(2)));
  });

  test('missing-only mode keeps existing downloaded image files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_scrape_missing_only_test_',
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
    await database.addActress(name: '涼森れむ');
    final sqlite = await database.database;
    final actressId = (await sqlite.query('actresses')).single['id'] as int;
    final card = File('${directory.path}/existing-card.jpg');
    final detail = File('${directory.path}/existing-detail.jpg');
    await card.writeAsBytes([7]);
    await detail.writeAsBytes([8]);
    await database.upsertActressWork(
      actressId: actressId,
      work: Work(
        code: 'ABF-367',
        title: '已儲存標題',
        cardImagePath: card.path,
        detailImagePath: detail.path,
      ),
    );
    final workImages = _FakeWorkImageDownloader();
    final service = WorksScrapeService(
      db: database,
      client: _FakeJavBusClient(),
      workImageDownloader: workImages,
      actressImageDownloader: _FakeActressImageDownloader(),
      imageDirectory: directory.path,
    );

    await service.scrape(
      actressId: actressId,
      actressName: '涼森れむ',
      options: const WorkScrapeOptions(
        syncDetails: false,
        fillMissingOnly: true,
      ),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.javbus,
      ),
    );

    expect(workImages.downloads, [
      WorkImageVariant.card,
      WorkImageVariant.detail,
    ]);
    expect(workImages.targetPaths.map(path.basename), [
      'fc2_ppv_123_999ps.jpg',
      'fc2_ppv_123_999pl.jpg',
    ]);
    expect(await card.readAsBytes(), [7]);
    expect(await detail.readAsBytes(), [8]);
    final work = (await database.getWorksForActress(
      actressId,
    )).singleWhere((row) => row['code'] == 'ABF-367');
    expect(work['title'], '已儲存標題');
    expect(work['duration_minutes'], 135);
  });

  test(
    'does not scrape a different actress when no exact name matches',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_exact_name_test_',
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

      final service = WorksScrapeService(
        db: database,
        client: _NoExactMatchJavBusClient(),
        imageDirectory: directory.path,
      );

      await expectLater(
        service.scrape(
          actressId: 1,
          actressName: '涼森れむ',
          options: const WorkScrapeOptions(),
          sourceSettings: const ScrapeSourceSettings(
            actressDetailsSource: ScrapeSourceId.javbus,
          ),
        ),
        throwsA(isA<WorksScrapeException>()),
      );
    },
  );

  test(
    'merges exact-name pages and does not filter by performer count',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_merge_test_',
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
      final sqlite = await database.database;
      final actressId = (await sqlite.query('actresses')).single['id'] as int;
      final client = _MergedJavBusClient();
      final actressImages = _RecordingActressImageDownloader();
      final service = WorksScrapeService(
        db: database,
        client: client,
        workImageDownloader: _FakeWorkImageDownloader(),
        actressImageDownloader: actressImages,
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '小湊よつ葉',
        options: const WorkScrapeOptions(replaceActressImage: true),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
        ),
      );

      expect(client.actressPageRequests, [
        'https://www.javbus.com/star/zen',
        'https://www.javbus.com/star/zh5',
      ]);
      expect(client.detailRequests, [
        'ONE-001',
        'MANY-003',
        'UNKNOWN-001',
        'TWO-002',
      ]);
      expect(
        (await database.getWorksForActress(
          actressId,
        )).map((row) => row['code']),
        unorderedEquals(['ONE-001', 'TWO-002', 'MANY-003', 'UNKNOWN-001']),
      );
      expect(
        actressImages.requested.single.toString(),
        'https://www.javbus.com/pics/actress/zh5_a.jpg',
      );
      expect(result.saved, 4);
      expect(result.excluded, 0);
      expect(result.failed, 0);
      expect(result.failedWorks, isEmpty);
      expect(result.actressImageStatus, ActressImageSyncStatus.replaced);
    },
  );

  test(
    'scrapes canonical name then normalized aliases with tolerant exact matching',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_aliases_test_',
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
      await database.addActress(name: '涼森れむ');
      final sqlite = await database.database;
      final actressId = (await sqlite.query('actresses')).single['id'] as int;
      final client = _AliasAwareJavBusClient();
      final service = WorksScrapeService(
        db: database,
        client: client,
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '涼森れむ',
        aliases: const ['  Remu  ', 'Remu', 'missing', 'Broken', '涼森れむ'],
        options: const WorkScrapeOptions(fillMissingOnly: false),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
        ),
      );

      expect(client.searchRequests, ['涼森れむ', 'Remu', 'missing', 'Broken']);
      expect(client.actressPageRequests, [
        'https://www.javbus.com/star/canonical',
        'https://www.javbus.com/star/remu',
        'https://www.javbus.com/star/broken',
      ]);
      expect(
        client.detailRequests,
        containsAll(['DUP-001', 'CAN-002', 'ALIAS-003']),
      );
      expect(
        client.detailRequests.where((code) => code == 'DUP-001'),
        hasLength(1),
      );
      expect(result.saved, 3);
      expect(result.failed, 0);
      expect((await database.getActressById(actressId))?['name'], '涼森れむ');
      expect(
        (await database.getWorksForActress(
          actressId,
        )).map((row) => row['code']),
        unorderedEquals(['DUP-001', 'CAN-002', 'ALIAS-003']),
      );
    },
  );

  test(
    'retries a shared actress URI through an alias after page failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_alias_retry_test_',
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
      await database.addActress(name: '涼森れむ');
      final sqlite = await database.database;
      final actressId = (await sqlite.query('actresses')).single['id'] as int;
      final client = _RetrySharedUriJavBusClient();
      final service = WorksScrapeService(
        db: database,
        client: client,
        workImageDownloader: _FakeWorkImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '涼森れむ',
        aliases: const ['Remu'],
        options: const WorkScrapeOptions(),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
        ),
      );

      expect(client.pageRequests, 2);
      expect(result.saved, 2);
      expect(
        (await database.getWorksForActress(
          actressId,
        )).singleWhere((row) => row['code'] == 'ABF-367')['code'],
        'ABF-367',
      );
    },
  );

  test(
    'reports avatar download failure and keeps the previous image',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca_scrape_avatar_failure_test_',
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
      await database.addActress(name: '涼森れむ');
      final sqlite = await database.database;
      final actressId = (await sqlite.query('actresses')).single['id'] as int;
      const previousPath = 'C:\\existing\\remu.jpg';
      await sqlite.update(
        'actresses',
        {'img_path': previousPath},
        where: 'id = ?',
        whereArgs: [actressId],
      );
      final service = WorksScrapeService(
        db: database,
        client: _FakeJavBusClient(),
        workImageDownloader: _FakeWorkImageDownloader(),
        actressImageDownloader: _ThrowingActressImageDownloader(),
        imageDirectory: directory.path,
      );

      final result = await service.scrape(
        actressId: actressId,
        actressName: '涼森れむ',
        options: const WorkScrapeOptions(replaceActressImage: true),
        sourceSettings: const ScrapeSourceSettings(
          actressDetailsSource: ScrapeSourceId.javbus,
        ),
      );

      expect(
        (await database.getActressById(actressId))?['img_path'],
        previousPath,
      );
      expect(result.actressImageStatus, ActressImageSyncStatus.downloadFailed);
    },
  );
}

class _NeverTransport implements JavBusTransport {
  @override
  Future<String> get(Uri uri) {
    throw StateError('Unexpected live request: $uri');
  }
}

class _RecordingScrapeObserver extends ScrapeRunObserver {
  final outcomes = <({String code, ScrapeWorkOutcomeState state})>[];

  @override
  void onWorkOutcome({
    required String code,
    required ScrapeSourceId source,
    required ScrapeWorkOutcomeState outcome,
    Object? error,
    String? reason,
    Iterable<String> imageFailureVariants = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    outcomes.add((code: code, state: outcome));
  }
}

class _FakeJavBusBinarySession implements JavBusBinarySession {
  _FakeJavBusBinarySession(this.response);

  final BinaryResponse response;
  final requested = <Uri>[];

  @override
  Future<BinaryResponse> getBinary(Uri uri) async {
    requested.add(uri);
    return response;
  }
}

class _FakeJavBusClient extends JavBusClient {
  _FakeJavBusClient() : super(transport: _NeverTransport());

  List<String> detailRequests = [];

  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    return [
      JavBusActressSearchResult(
        name: '涼森れむ',
        uri: Uri.parse('https://www.javbus.com/star/uly'),
      ),
    ];
  }

  @override
  Future<JavBusActressPage> fetchActressPage(Uri uri) async {
    return JavBusActressPage(
      details: ScrapedActressDetails(
        name: '涼森れむ',
        avatarUrl: Uri.parse('https://www.javbus.com/pics/actress/uly_a.jpg'),
        birthDate: '1997-12-03',
        height: '160',
        cup: 'F',
        bust: '87',
        waist: '58',
        hip: '85',
      ),
      works: const [],
      pageCount: 1,
    );
  }

  @override
  Future<List<JavBusWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    bool Function()? isCancelled,
    JavBusActressPage? firstPage,
    void Function(int currentPage, int totalPages, int discovered)? onProgress,
  }) async {
    return [
      JavBusWorkSummary(
        code: 'ABF-367',
        title: '新標題',
        releaseDate: '2026-07-17',
        detailUri: Uri.parse('https://www.javbus.com/ABF-367'),
      ),
      JavBusWorkSummary(
        code: 'FC2-PPV_123-999',
        title: '排除作品',
        detailUri: Uri.parse('https://www.javbus.com/FC2-PPV_123-999'),
      ),
    ];
  }

  @override
  Future<JavBusWorkDetails> fetchWorkDetails(Uri uri) async {
    final code = uri.pathSegments.last;
    detailRequests.add(code);
    return JavBusWorkDetails(
      code: code,
      title: '新標題',
      releaseDate: '2026-07-17',
      durationMinutes: 135,
      studio: 'プレステージ',
      publisher: 'ABSOLUTELYFANTASIA',
      series: '系列',
      performers: code == 'ABF-367'
          ? [
              WorkPerformer(
                name: '追加女優',
                sourceUri: Uri.parse('https://www.javbus.com/star/other'),
              ),
              const WorkPerformer(name: '涼森れむ'),
            ]
          : null,
    );
  }
}

class _OverlapJavBusClient extends _FakeJavBusClient {
  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    return [
      JavBusActressSearchResult(
        name: name,
        uri: Uri.parse('https://www.javbus.com/star/overlap'),
      ),
    ];
  }

  @override
  Future<List<JavBusWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    bool Function()? isCancelled,
    JavBusActressPage? firstPage,
    void Function(int currentPage, int totalPages, int discovered)? onProgress,
  }) async {
    return [
      JavBusWorkSummary(
        code: 'OVR-001',
        title: 'OVR-001',
        detailUri: Uri.parse('https://www.javbus.com/OVR-001'),
      ),
      JavBusWorkSummary(
        code: 'OVR-002',
        title: 'OVR-002',
        detailUri: Uri.parse('https://www.javbus.com/OVR-002'),
      ),
    ];
  }

  @override
  Future<JavBusWorkDetails> fetchWorkDetails(Uri uri) async {
    final code = uri.pathSegments.last.toUpperCase();
    detailRequests.add(code);
    return JavBusWorkDetails(
      code: code,
      title: code,
      studio: 'S1',
      publisher: 'S1',
    );
  }
}

class _OverlapWorkImageDownloader extends WorkImageDownloader {
  _OverlapWorkImageDownloader() : super(transport: _NoBinaryTransport());

  final firstDownloadStarted = Completer<void>();
  final _release = Completer<void>();
  var _blocked = false;
  var active = 0;
  var maxActive = 0;

  void releaseFirstDownload() {
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
    active++;
    if (active > maxActive) {
      maxActive = active;
    }
    try {
      if (!_blocked) {
        _blocked = true;
        firstDownloadStarted.complete();
        await _release.future;
      }
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      return DownloadedWorkImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        sourceUri: Uri.parse('https://example.test/$code.jpg'),
      );
    } finally {
      active--;
    }
  }
}

class _RetrySharedUriJavBusClient extends _FakeJavBusClient {
  int pageRequests = 0;

  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    return [
      JavBusActressSearchResult(
        name: name,
        uri: Uri.parse('https://www.javbus.com/star/shared'),
      ),
    ];
  }

  @override
  Future<JavBusActressPage> fetchActressPage(Uri uri) {
    pageRequests++;
    if (pageRequests == 1) {
      throw const WorksScrapeException('simulated transient page failure');
    }
    return super.fetchActressPage(uri);
  }
}

class _MergedJavBusClient extends JavBusClient {
  _MergedJavBusClient() : super(transport: _NeverTransport());

  final actressPageRequests = <String>[];
  final detailRequests = <String>[];

  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    return [
      JavBusActressSearchResult(
        name: '小湊よつ葉',
        uri: Uri.parse('https://www.javbus.com/star/zen'),
      ),
      JavBusActressSearchResult(
        name: '小湊よつ葉',
        uri: Uri.parse('https://www.javbus.com/star/zh5'),
      ),
    ];
  }

  @override
  Future<JavBusActressPage> fetchActressPage(Uri uri) async {
    actressPageRequests.add(uri.toString());
    final validAvatar = uri.pathSegments.last == 'zh5';
    return JavBusActressPage(
      details: ScrapedActressDetails(
        name: '小湊よつ葉',
        avatarUrl: validAvatar
            ? Uri.parse('https://www.javbus.com/pics/actress/zh5_a.jpg')
            : null,
      ),
      works: const [],
      pageCount: 1,
    );
  }

  @override
  Future<List<JavBusWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    bool Function()? isCancelled,
    JavBusActressPage? firstPage,
    void Function(int currentPage, int totalPages, int discovered)? onProgress,
  }) async {
    final second = actressUri.pathSegments.last == 'zh5';
    return (second
            ? ['many-003', 'TWO-002']
            : ['ONE-001', 'MANY-003', 'UNKNOWN-001'])
        .map(
          (code) => JavBusWorkSummary(
            code: code,
            title: code,
            detailUri: Uri.parse('https://www.javbus.com/$code'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<JavBusWorkDetails> fetchWorkDetails(Uri uri) async {
    final code = uri.pathSegments.last.toUpperCase();
    detailRequests.add(code);
    final actressCount = switch (code) {
      'ONE-001' => 1,
      'TWO-002' => 2,
      'MANY-003' => 3,
      _ => 0,
    };
    return JavBusWorkDetails(
      code: code,
      title: code,
      actressUris: List.generate(
        actressCount,
        (index) => Uri.parse('https://www.javbus.com/star/$index'),
      ),
    );
  }
}

class _AliasAwareJavBusClient extends JavBusClient {
  _AliasAwareJavBusClient() : super(transport: _NeverTransport());

  final searchRequests = <String>[];
  final actressPageRequests = <String>[];
  final detailRequests = <String>[];

  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    searchRequests.add(name);
    return switch (name) {
      '涼森れむ' => [
        JavBusActressSearchResult(
          name: '涼森れむ',
          uri: Uri.parse('https://www.javbus.com/star/canonical'),
        ),
        JavBusActressSearchResult(
          name: '涼森れむ',
          uri: Uri.parse('https://www.javbus.com/star/canonical'),
        ),
      ],
      'Remu' => [
        JavBusActressSearchResult(
          name: 'remu',
          uri: Uri.parse('https://www.javbus.com/star/remu'),
        ),
        JavBusActressSearchResult(
          name: 'REMU',
          uri: Uri.parse('https://www.javbus.com/star/remu'),
        ),
      ],
      'Broken' => [
        JavBusActressSearchResult(
          name: 'Broken',
          uri: Uri.parse('https://www.javbus.com/star/broken'),
        ),
      ],
      _ => [
        JavBusActressSearchResult(
          name: 'not an exact match',
          uri: Uri.parse('https://www.javbus.com/star/missing'),
        ),
      ],
    };
  }

  @override
  Future<JavBusActressPage> fetchActressPage(Uri uri) async {
    actressPageRequests.add(uri.toString());
    if (uri.pathSegments.last == 'broken') {
      throw const WorksScrapeException('simulated alias page failure');
    }
    final canonical = uri.pathSegments.last == 'canonical';
    return JavBusActressPage(
      details: ScrapedActressDetails(name: canonical ? null : 'Remu'),
      works: const [],
      pageCount: 1,
    );
  }

  @override
  Future<List<JavBusWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    bool Function()? isCancelled,
    JavBusActressPage? firstPage,
    void Function(int currentPage, int totalPages, int discovered)? onProgress,
  }) async {
    final canonical = actressUri.pathSegments.last == 'canonical';
    return (canonical ? ['DUP-001', 'CAN-002'] : ['dup-001', 'ALIAS-003'])
        .map(
          (code) => JavBusWorkSummary(
            code: code,
            title: code,
            detailUri: Uri.parse('https://www.javbus.com/$code'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<JavBusWorkDetails> fetchWorkDetails(Uri uri) async {
    final code = uri.pathSegments.last.toUpperCase();
    detailRequests.add(code);
    return JavBusWorkDetails(code: code, title: code);
  }
}

class _NoExactMatchJavBusClient extends _FakeJavBusClient {
  @override
  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    return [
      JavBusActressSearchResult(
        name: '別の女優',
        uri: Uri.parse('https://www.javbus.com/star/not-remu'),
      ),
    ];
  }

  @override
  Future<JavBusActressPage> fetchActressPage(Uri uri) {
    throw StateError('A non-exact actress must never be scraped.');
  }
}

class _NoBinaryTransport implements BinaryTransport {
  @override
  Future<BinaryResponse> get(Uri uri) {
    throw StateError('Unexpected binary request: $uri');
  }
}

class _FakeWorkImageDownloader extends WorkImageDownloader {
  _FakeWorkImageDownloader() : super(transport: _NoBinaryTransport());

  final downloads = <WorkImageVariant>[];
  final targetPaths = <String>[];

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
    downloads.add(variant);
    targetPaths.add(targetPath);
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    return DownloadedWorkImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      sourceUri: Uri.parse('https://example.test/$code.jpg'),
    );
  }
}

class _FakeActressImageDownloader implements ActressImageDownloader {
  @override
  Future<String> download(Uri uri, String targetPath) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([4, 5, 6]);
    return file.path;
  }
}

class _RecordingActressImageDownloader implements ActressImageDownloader {
  final requested = <Uri>[];

  @override
  Future<String> download(Uri uri, String targetPath) async {
    requested.add(uri);
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([4, 5, 6]);
    return file.path;
  }
}

class _ThrowingActressImageDownloader implements ActressImageDownloader {
  @override
  Future<String> download(Uri uri, String targetPath) {
    throw const WorksScrapeException('Actress image request failed.');
  }
}
