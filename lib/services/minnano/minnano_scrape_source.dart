import '../../models/scrape_source_settings.dart';
import '../scrape/scrape_models.dart';
import '../scrape/scrape_source.dart';
import 'minnano_client.dart';
import 'minnano_models.dart';

final class MinnanoScrapeSource implements ScrapeSource {
  MinnanoScrapeSource(this.client);

  final MinnanoClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.minnanoAv;

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
    final firstMinnanoPage = MinnanoActressPage(
      details: firstPage.details,
      aliases: firstPage.aliases,
      works: firstPage.works
          .map(
            (work) => MinnanoWorkSummary(
              code: work.code,
              title: work.title,
              detailUri: work.detailUri,
              releaseDate: work.releaseDate,
            ),
          )
          .toList(growable: false),
      pageCount: firstPage.pageCount,
    );
    final works = await client.fetchAllActressWorks(
      actress.uri,
      firstPage: firstMinnanoPage,
      isCancelled: isCancelled,
    );
    return works.map(_summary).toList(growable: false);
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final details = await client.fetchWorkDetails(work.detailUri);
    return ScrapeWorkDetails(
      source: id,
      code: details.code ?? '',
      rawCode: details.code,
      title: details.title,
      releaseDate: details.releaseDate,
      studio: details.studio,
      publisher: details.publisher,
      performerCount: details.performerCount,
      imageUris: details.imageUris,
    );
  }

  @override
  bool acceptsImageUri(Uri uri) => client.acceptsImageUri(uri);

  @override
  void close() => client.close();

  ScrapeWorkSummary _summary(MinnanoWorkSummary work) {
    return ScrapeWorkSummary(
      source: id,
      code: work.code,
      title: work.title,
      detailUri: work.detailUri,
      releaseDate: work.releaseDate,
    );
  }
}
