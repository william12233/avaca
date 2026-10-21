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
    'does not call the secondary source for confident primary evidence',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final primary = _EscalationSource(
        id: ScrapeSourceId.javbus,
        works: [_summary(ScrapeSourceId.javbus, 'NEW-001')],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'NEW-001',
          title: '新作',
          provenanceFacts: ScrapeWorkProvenanceFacts(
            explicitOriginalProduction: true,
          ),
        ),
      );
      final secondary = _EscalationSource(
        id: ScrapeSourceId.avbase,
        works: [_summary(ScrapeSourceId.avbase, 'NEW-001')],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.avbase,
          code: 'NEW-001',
          title: 'secondary should not be requested',
        ),
      );

      final result = await fixture
          .service(sources: {primary.id: primary, secondary.id: secondary})
          .scrape(
            actressId: fixture.actressId,
            actressName: '测试女优',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.javbus,
              worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
            ),
          );

      expect(result.saved, 1);
      expect(primary.worksCalls, 1);
      expect(primary.detailCalls, 1);
      expect(secondary.worksCalls, 1);
      expect(secondary.detailCalls, 0);
    },
  );

  test(
    'escalates only the unresolved work for secondary provenance evidence',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final primary = _EscalationSource(
        id: ScrapeSourceId.javbus,
        works: [
          _summary(ScrapeSourceId.javbus, 'NEW-002'),
          _summary(ScrapeSourceId.javbus, 'UNKNOWN-002'),
        ],
        detailsByCode: {
          'NEW-002': const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'NEW-002',
            title: '新作',
            provenanceFacts: ScrapeWorkProvenanceFacts(
              explicitOriginalProduction: true,
            ),
          ),
          'UNKNOWN-002': const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'UNKNOWN-002',
            title: '100人8時間2枚組',
          ),
        },
      );
      final secondary = _EscalationSource(
        id: ScrapeSourceId.avbase,
        works: [
          _summary(ScrapeSourceId.avbase, 'NEW-002'),
          _summary(ScrapeSourceId.avbase, 'UNKNOWN-002'),
        ],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.avbase,
          code: 'UNKNOWN-002',
          title: '作品集',
          provenanceFacts: ScrapeWorkProvenanceFacts(
            includedWorks: ['OLD-001'],
          ),
        ),
      );

      final result = await fixture
          .service(sources: {primary.id: primary, secondary.id: secondary})
          .scrape(
            actressId: fixture.actressId,
            actressName: '测试女优',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.javbus,
              worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
            ),
          );

      expect(result.saved, 1);
      expect(result.excluded, 1);
      expect(
        primary.detailRequests,
        unorderedEquals(['NEW-002', 'UNKNOWN-002']),
      );
      expect(secondary.worksCalls, 1);
      expect(secondary.detailRequests, ['UNKNOWN-002']);
    },
  );

  test(
    'uses exact-code secondary lookup after the enabled catalog union',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final primary = _EscalationSource(
        id: ScrapeSourceId.javbus,
        works: [_summary(ScrapeSourceId.javbus, 'UNKNOWN-003')],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'UNKNOWN-003',
          title: '100人8時間2枚組',
        ),
      );
      final secondary = _DirectEscalationSource(
        id: ScrapeSourceId.avbase,
        works: const [],
        detailsByCode: const {
          'UNKNOWN-003': ScrapeWorkDetails(
            source: ScrapeSourceId.avbase,
            code: 'UNKNOWN-003',
            title: '作品集',
            provenanceFacts: ScrapeWorkProvenanceFacts(
              includedWorks: ['OLD-003'],
            ),
          ),
        },
      );
      final progress = <WorksScrapeProgress>[];

      final result = await fixture
          .service(sources: {primary.id: primary, secondary.id: secondary})
          .scrape(
            actressId: fixture.actressId,
            actressName: '测试女优',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.javbus,
              worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
            ),
            onProgress: progress.add,
          );

      expect(result.saved, 0);
      expect(result.excluded, 1);
      expect(secondary.worksCalls, 1);
      expect(secondary.detailCalls, 0);
      expect(secondary.directRequests, ['UNKNOWN-003']);
      expect(
        progress.lastWhere((item) => item.supplementalEvidenceTotal > 0),
        isA<WorksScrapeProgress>(),
      );
      final supplemental = progress.lastWhere(
        (item) => item.supplementalEvidenceTotal > 0,
      );
      expect(supplemental.supplementalEvidenceTotal, 1);
      expect(supplemental.supplementalEvidenceCompleted, 1);
      expect(supplemental.detailTotal, 1);
    },
  );

  test(
    'keeps standalone bonus-only material without secondary detail escalation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final primary = _EscalationSource(
        id: ScrapeSourceId.javbus,
        works: [_summary(ScrapeSourceId.javbus, 'BONUS-001')],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'BONUS-001',
          title: '全編撮り下ろしの特典映像',
        ),
      );
      final secondary = _EscalationSource(
        id: ScrapeSourceId.avbase,
        works: [_summary(ScrapeSourceId.avbase, 'BONUS-001')],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.avbase,
          code: 'BONUS-001',
          title: '全編撮り下ろし新作',
        ),
      );

      final result = await fixture
          .service(sources: {primary.id: primary, secondary.id: secondary})
          .scrape(
            actressId: fixture.actressId,
            actressName: '测试女优',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.javbus,
              worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
            ),
          );

      expect(result.saved, 1);
      expect(result.excluded, 0);
      expect(primary.detailCalls, 1);
      expect(secondary.worksCalls, 1);
      expect(secondary.detailRequests, isEmpty);
    },
  );

  test(
    'does not escalate a confident director-cut premium repackage',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const title = '未公開映像収録のプレミアムエディション！ディレクターズカット版 新人NO.1STYLE 河北彩花 AVデビュー';
      final primary = _EscalationSource(
        id: ScrapeSourceId.javbus,
        works: [_summary(ScrapeSourceId.javbus, 'REEDIT-001')],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'REEDIT-001',
          title: title,
        ),
      );
      final secondary = _EscalationSource(
        id: ScrapeSourceId.avbase,
        works: [_summary(ScrapeSourceId.avbase, 'REEDIT-001')],
        details: const ScrapeWorkDetails(
          source: ScrapeSourceId.avbase,
          code: 'REEDIT-001',
          title: 'secondary should not be requested',
        ),
      );

      final result = await fixture
          .service(sources: {primary.id: primary, secondary.id: secondary})
          .scrape(
            actressId: fixture.actressId,
            actressName: '测试女优',
            options: const WorkScrapeOptions(),
            sourceSettings: const ScrapeSourceSettings(
              actressDetailsSource: ScrapeSourceId.javbus,
              worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
            ),
          );

      expect(result.saved, 0);
      expect(result.excluded, 1);
      expect(primary.detailCalls, 1);
      expect(secondary.worksCalls, 1);
      expect(secondary.detailCalls, 0);
    },
  );

  test('does not escalate a whole-production original surface', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final primary = _EscalationSource(
      id: ScrapeSourceId.javbus,
      works: [_summary(ScrapeSourceId.javbus, 'WHOLE-001')],
      details: const ScrapeWorkDetails(
        source: ScrapeSourceId.javbus,
        code: 'WHOLE-001',
        title: '全編撮り下ろし新作',
      ),
    );
    final secondary = _EscalationSource(
      id: ScrapeSourceId.avbase,
      works: [_summary(ScrapeSourceId.avbase, 'WHOLE-001')],
      details: const ScrapeWorkDetails(
        source: ScrapeSourceId.avbase,
        code: 'WHOLE-001',
        title: 'secondary should not be requested',
      ),
    );

    final result = await fixture
        .service(sources: {primary.id: primary, secondary.id: secondary})
        .scrape(
          actressId: fixture.actressId,
          actressName: '测试女优',
          options: const WorkScrapeOptions(),
          sourceSettings: const ScrapeSourceSettings(
            actressDetailsSource: ScrapeSourceId.javbus,
            worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
          ),
        );

    expect(result.saved, 1);
    expect(primary.detailCalls, 1);
    expect(secondary.worksCalls, 1);
    expect(secondary.detailCalls, 0);
  });

  test('does not escalate a mixed derived surface', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final primary = _EscalationSource(
      id: ScrapeSourceId.javbus,
      works: [_summary(ScrapeSourceId.javbus, 'MIXED-001')],
      details: const ScrapeWorkDetails(
        source: ScrapeSourceId.javbus,
        code: 'MIXED-001',
        title: 'BEST11人・全編撮り下ろしの特典映像',
      ),
    );
    final secondary = _EscalationSource(
      id: ScrapeSourceId.avbase,
      works: [_summary(ScrapeSourceId.avbase, 'MIXED-001')],
      details: const ScrapeWorkDetails(
        source: ScrapeSourceId.avbase,
        code: 'MIXED-001',
        title: 'secondary should not be requested',
      ),
    );

    final result = await fixture
        .service(sources: {primary.id: primary, secondary.id: secondary})
        .scrape(
          actressId: fixture.actressId,
          actressName: '测试女优',
          options: const WorkScrapeOptions(),
          sourceSettings: const ScrapeSourceSettings(
            actressDetailsSource: ScrapeSourceId.javbus,
            worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
          ),
        );

    expect(result.saved, 0);
    expect(result.excluded, 1);
    expect(primary.detailCalls, 1);
    expect(secondary.worksCalls, 1);
    expect(secondary.detailCalls, 0);
  });
}

ScrapeWorkSummary _summary(ScrapeSourceId source, String code) {
  return ScrapeWorkSummary(
    source: source,
    code: code,
    title: code,
    detailUri: Uri.parse('https://example.test/$code'),
  );
}

final class _Fixture {
  _Fixture(this.database, this.actressId, this.directory);

  final AppDatabase database;
  final int actressId;
  final Directory directory;

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_provenance_escalation_test_',
    );
    final database = AppDatabase.forTesting(
      baseDir: directory.path,
      databaseFactory: databaseFactoryFfi,
    );
    await database.init();
    await database.addActress(name: '测试女优');
    final rows = await (await database.database).query('actresses');
    return _Fixture(database, rows.single['id'] as int, directory);
  }

  WorksScrapeService service({
    required Map<ScrapeSourceId, ScrapeSource> sources,
  }) {
    return WorksScrapeService(
      db: database,
      sources: sources,
      workImageDownloader: _NoopWorkImageDownloader(),
      imageDirectory: directory.path,
    );
  }

  Future<void> dispose() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}

class _EscalationSource implements ScrapeSource {
  _EscalationSource({
    required this.id,
    required this.works,
    ScrapeWorkDetails? details,
    this.detailsByCode = const {},
  }) : details = details ?? detailsByCode.values.first;

  @override
  final ScrapeSourceId id;
  final List<ScrapeWorkSummary> works;
  final ScrapeWorkDetails details;
  final Map<String, ScrapeWorkDetails> detailsByCode;
  var worksCalls = 0;
  final detailRequests = <String>[];

  int get detailCalls => detailRequests.length;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
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
      details: const ScrapedActressDetails(name: '测试女优'),
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
    worksCalls++;
    onProgress?.call(
      ScrapeCollectionProgress(
        currentPage: 1,
        totalPages: 1,
        discovered: works.length,
      ),
    );
    return works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final code = work.code ?? '';
    detailRequests.add(code);
    return detailsByCode[code] ?? details;
  }

  @override
  bool acceptsImageUri(Uri uri) => false;

  @override
  void close() {}
}

final class _DirectEscalationSource extends _EscalationSource
    implements ScrapeSourceWorkCodeLookup {
  _DirectEscalationSource({
    required super.id,
    required super.works,
    super.detailsByCode,
  });

  final directRequests = <String>[];

  @override
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(
    String canonicalCode,
  ) async {
    directRequests.add(canonicalCode);
    return detailsByCode[canonicalCode];
  }
}

final class _NoopWorkImageDownloader extends WorkImageDownloader {
  _NoopWorkImageDownloader() : super(transport: _NoopBinaryTransport());

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

final class _NoopBinaryTransport implements BinaryTransport {
  @override
  Future<BinaryResponse> get(Uri uri) =>
      throw StateError('unexpected binary request: $uri');
}
