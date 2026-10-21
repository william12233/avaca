import '../../models/scrape_source_settings.dart';
import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import 'avwiki_client.dart';
import 'avwiki_models.dart';

final class AvWikiScrapeSource
    implements
        ScrapeSource,
        ScrapeSourceDiagnosticsProvider,
        ScrapeSourceWorkCodeLookup {
  AvWikiScrapeSource(this.client);

  final AvWikiClient client;
  ScrapeSourceRunDiagnostic? _lastRunDiagnostic;

  @override
  ScrapeSourceRunDiagnostic? get lastRunDiagnostic => _lastRunDiagnostic;

  @override
  void resetRunDiagnostic() => _lastRunDiagnostic = null;

  @override
  ScrapeSourceId get id => ScrapeSourceId.avwiki;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) {
    return client.searchActresses(name);
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    final page = await client.fetchActressPage(actress.uri);
    return ScrapeActressPage(
      source: id,
      details: page.details,
      aliases: page.aliases,
      works: page.works.map(_summary).toList(growable: false),
      pageCount: page.pageCount,
    );
  }

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
    void Function(ScrapeCollectionProgress progress)? onProgress,
  }) async {
    final firstPageModel = AvWikiActressPage(
      details: firstPage.details,
      aliases: firstPage.aliases,
      works: firstPage.works
          .map(
            (work) => AvWikiWorkSummary(
              code: work.code,
              rawCode: work.rawCode,
              title: work.title,
              detailUri: work.detailUri,
              releaseDate: work.releaseDate,
              externalIdentity: work.externalIdentity,
              catalogEvidence: work.catalogEvidence,
            ),
          )
          .toList(growable: false),
      pageCount: firstPage.pageCount,
    );
    final collection = await client.fetchAllActressWorks(
      actress.uri,
      firstPage: firstPageModel,
      isCancelled: isCancelled,
      onProgress: (currentPage, totalPages, discovered) => onProgress?.call(
        ScrapeCollectionProgress(
          currentPage: currentPage,
          totalPages: totalPages,
          discovered: discovered,
        ),
      ),
    );
    if (collection.issues.isNotEmpty) {
      final firstIssue = collection.issues.first;
      _lastRunDiagnostic = ScrapeSourceRunDiagnostic(
        state: collection.works.isNotEmpty
            ? ScrapeSourceRunState.partial
            : _stateForIssue(firstIssue.kind),
        error: firstIssue,
      );
    }
    return collection.works.map(_summary).toList(growable: false);
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final details = await client.fetchWorkDetails(work.detailUri);
    return _mapDetails(details);
  }

  @override
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(
    String canonicalCode,
  ) async {
    try {
      return _mapDetails(await client.fetchWorkDetailsByCode(canonicalCode));
    } on AvWikiRequestException catch (error) {
      if (error.kind == AvWikiFailureKind.notFound) return null;
      rethrow;
    }
  }

  @override
  bool acceptsImageUri(Uri uri) => false;

  @override
  void close() => client.close();

  ScrapeWorkDetails _mapDetails(AvWikiWorkDetails details) {
    final catalogEvidence = details.catalogEvidence.isEmpty
        ? [
            ScrapeCatalogWorkEvidence.fromDetails(
              source: id,
              code: details.code,
              title: details.title,
              manufacturer: details.studio,
              label: details.publisher,
              series: details.series,
              description: details.description,
              provenanceFacts: details.provenanceFacts,
            ),
          ]
        : details.catalogEvidence;
    return ScrapeWorkDetails(
      source: id,
      code: details.code,
      rawCode: details.rawCode ?? details.code,
      title: details.title,
      releaseDate: details.releaseDate,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performerCount: details.performerCount,
      performers: details.performers,
      description: details.description,
      genres: details.genres,
      provenanceFacts: details.provenanceFacts,
      coPerformance: details.provenanceFacts.coPerformance,
      externalIdentity: details.externalIdentity,
      imageUris: const [],
      originalImageEvidenceUris: const [],
      catalogEvidence: catalogEvidence,
    );
  }

  ScrapeWorkSummary _summary(AvWikiWorkSummary work) {
    return ScrapeWorkSummary(
      source: id,
      code: work.code,
      rawCode: work.rawCode ?? work.code,
      title: work.title,
      detailUri: work.detailUri,
      releaseDate: work.releaseDate,
      externalIdentity: work.externalIdentity,
      catalogEvidence: work.catalogEvidence,
    );
  }

  ScrapeSourceRunState _stateForIssue(AvWikiFailureKind kind) {
    return switch (kind) {
      AvWikiFailureKind.blocked => ScrapeSourceRunState.blocked,
      AvWikiFailureKind.rateLimited => ScrapeSourceRunState.rateLimited,
      AvWikiFailureKind.timeout => ScrapeSourceRunState.timedOut,
      AvWikiFailureKind.cancelled => ScrapeSourceRunState.cancelled,
      AvWikiFailureKind.transport ||
      AvWikiFailureKind.transientTransport ||
      AvWikiFailureKind.notFound ||
      AvWikiFailureKind.parserInvalid => ScrapeSourceRunState.failed,
    };
  }
}
