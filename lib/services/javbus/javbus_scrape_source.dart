import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import '../../models/scrape_source_settings.dart';
import 'javbus_client.dart';
import 'javbus_models.dart';

final class JavBusScrapeSource
    implements
        ScrapeSource,
        ScrapeSourceDiagnosticsProvider,
        ScrapeSourceWorkCodeLookup {
  JavBusScrapeSource(this.client);

  final JavBusClient client;
  ScrapeSourceRunDiagnostic? _lastRunDiagnostic;

  @override
  ScrapeSourceRunDiagnostic? get lastRunDiagnostic => _lastRunDiagnostic;

  @override
  void resetRunDiagnostic() {
    _lastRunDiagnostic = null;
  }

  @override
  ScrapeSourceId get id => ScrapeSourceId.javbus;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    final results = await client.searchActresses(name);
    return results
        .map(
          (result) => ScrapeActressSearchResult(
            source: id,
            name: result.name,
            uri: result.uri,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async {
    final page = await client.fetchActressPage(actress.uri);
    return ScrapeActressPage(
      source: id,
      details: page.details,
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
    final firstJavBusPage = JavBusActressPage(
      details: firstPage.details,
      works: firstPage.works
          .map(
            (work) => JavBusWorkSummary(
              code: work.code ?? '',
              rawCode: work.rawCode ?? work.code ?? '',
              title: work.title,
              detailUri: work.detailUri,
              releaseDate: work.releaseDate,
              catalogEvidence: work.catalogEvidence,
            ),
          )
          .toList(growable: false),
      pageCount: firstPage.pageCount,
    );
    final works = await client.fetchAllActressWorks(
      actress.uri,
      firstPage: firstJavBusPage,
      isCancelled: isCancelled,
      onProgress: (currentPage, totalPages, discovered) => onProgress?.call(
        ScrapeCollectionProgress(
          currentPage: currentPage,
          totalPages: totalPages,
          discovered: discovered,
        ),
      ),
    );
    final issues = client.lastWorkCollectionIssues;
    if (issues.isNotEmpty) {
      final firstIssue = issues.first;
      _lastRunDiagnostic = ScrapeSourceRunDiagnostic(
        state: works.isNotEmpty
            ? ScrapeSourceRunState.partial
            : _stateForIssue(firstIssue.kind),
        error: firstIssue,
      );
    }
    return works.map(_summary).toList(growable: false);
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
    } on JavBusRequestException catch (error) {
      if (error.kind == JavBusFailureKind.notFound) return null;
      rethrow;
    }
  }

  @override
  bool acceptsImageUri(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    final imagePath = uri.path.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'www.javbus.com' &&
        port == 443 &&
        imagePath.startsWith('/pics/actress/') &&
        !imagePath.endsWith('/nowprinting.gif');
  }

  @override
  void close() {
    client.close();
  }

  ScrapeWorkDetails _mapDetails(JavBusWorkDetails details) {
    final catalogEvidence = details.catalogEvidence.isEmpty
        ? [
            ScrapeCatalogWorkEvidence.fromDetails(
              source: id,
              code: details.rawCode ?? details.code,
              title: details.title,
              manufacturer: details.studio,
              label: details.publisher,
              series: details.series,
              provenanceFacts: details.provenanceFacts,
            ),
          ]
        : details.catalogEvidence;
    return ScrapeWorkDetails(
      source: id,
      code: details.rawCode ?? details.code,
      rawCode: details.rawCode ?? details.code,
      title: details.title,
      releaseDate: details.releaseDate,
      durationMinutes: details.durationMinutes,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performers: details.performers,
      description: details.provenanceFacts.description,
      includedWorks: details.provenanceFacts.includedWorks,
      parentWorks: details.provenanceFacts.parentWorks,
      genres: details.provenanceFacts.genres,
      provenanceFacts: details.provenanceFacts,
      coPerformance: details.provenanceFacts.coPerformance,
      performerCount: details.actressUris.length,
      originalImageEvidenceUris: details.originalImageEvidenceUris,
      catalogEvidence: catalogEvidence,
    );
  }

  ScrapeWorkSummary _summary(JavBusWorkSummary work) {
    return ScrapeWorkSummary(
      source: id,
      code: work.rawCode ?? work.code,
      title: work.title,
      detailUri: work.detailUri,
      releaseDate: work.releaseDate,
      catalogEvidence: work.catalogEvidence,
    );
  }

  ScrapeSourceRunState _stateForIssue(JavBusPageIssueKind kind) {
    return switch (kind) {
      JavBusPageIssueKind.verificationRequired =>
        ScrapeSourceRunState.verificationRequired,
      JavBusPageIssueKind.blocked => ScrapeSourceRunState.blocked,
      JavBusPageIssueKind.rateLimited => ScrapeSourceRunState.rateLimited,
      JavBusPageIssueKind.timeout => ScrapeSourceRunState.timedOut,
      JavBusPageIssueKind.cancelled => ScrapeSourceRunState.cancelled,
      JavBusPageIssueKind.notFound ||
      JavBusPageIssueKind.transport ||
      JavBusPageIssueKind.parserInvalid => ScrapeSourceRunState.failed,
    };
  }
}
