import 'dart:io';

import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/avwiki/avwiki_client.dart';
import 'package:avaca/services/avwiki/avwiki_html_parser.dart';
import 'package:avaca/services/avwiki/avwiki_models.dart';
import 'package:avaca/services/avwiki/avwiki_scrape_source.dart';
import 'package:avaca/services/avwiki/avwiki_transport.dart';
import 'package:avaca/services/http_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final parser = AvWikiHtmlParser();

  test('parses exact actress search, paginated catalog, and dedupe fields', () {
    final searchUri = Uri.parse(
      'https://av-wiki.net/?s=%E6%B2%B3%E5%8C%97%E5%BD%A9%E8%8A%B1',
    );
    final search = parser.parseActressSearchResults(
      _fixture('search.html'),
      pageUri: searchUri,
      query: '河北彩花',
    );
    expect(search, hasLength(1));
    expect(search.single.source, ScrapeSourceId.avwiki);
    expect(
      search.single.uri.toString(),
      'https://av-wiki.net/av-actress/kawakita-saika/',
    );

    final page = parser.parseActressPage(
      _fixture('actress_page.html'),
      pageUri: search.single.uri,
    );
    expect(page.details.name, '河北彩花');
    expect(page.aliases, contains('河北彩伽'));
    expect(page.pageCount, 8);
    expect(page.works.map((work) => work.code), ['SNOS-371', 'SNOS-320']);
    expect(
      page.works.first.externalIdentity?.platformIds['fanza'],
      'snos00371',
    );
    expect(
      page.works.first.catalogEvidence.single.source,
      ScrapeSourceId.avwiki,
    );
    expect(page.works.first.catalogEvidence.single.manufacturer, 'エスワン');
    expect(page.works.first.catalogEvidence.single.label, 'SNOS');
  });

  test('retains series and tags in archive catalog evidence', () {
    final summary = parser.parseSearchWorkSummary(
      html
          .parse('''
      <article class="archive-list">
        <header class="archive-header">
          <h2 class="archive-header-title"><a href="/title-001/">作品標題</a></h2>
          <ul class="post-meta">
            <li class="actress-name"><a href="/av-actress/test/">女優</a></li>
            <li><a href="/maker/s1">S1 NO.1 STYLE</a></li>
            <li>TITLE-001</li>
          </ul>
        </header>
        <a href="/series/test-series">測試系列</a>
        <a rel="tag" href="/tags/best">BEST</a>
        <div class="read-more"><a href="/title-001/">続きを読む</a></div>
      </article>
      ''')
          .querySelector('article')!,
      Uri.parse('https://av-wiki.net/'),
    );

    expect(summary, isNotNull);
    expect(summary!.catalogEvidence.single.manufacturer, 'S1 NO.1 STYLE');
    expect(summary.catalogEvidence.single.series, '測試系列');
    expect(summary.catalogEvidence.single.tags, ['BEST']);
  });

  test(
    'parses typed work identity and keeps compilation evidence separate',
    () {
      final normal = parser.parseWorkPage(
        _fixture('work_normal.html'),
        pageUri: Uri.parse('https://av-wiki.net/snos-371/'),
      );
      expect(normal.code, 'SNOS-371');
      expect(normal.studio, 'エスワン ナンバーワンスタイル');
      expect(normal.publisher, 'S1 NO.1 STYLE');
      expect(normal.releaseDate, '2026-08-21');
      expect(normal.externalIdentity?.platformIds['fanza'], 'snos00371');
      expect(normal.provenanceFacts.containsPriorWorks, isNull);

      final platformIds = parser.parseWorkPage(
        _fixture('work_platform_ids.html'),
        pageUri: Uri.parse('https://av-wiki.net/start-164/'),
      );
      expect(platformIds.code, 'START-164');
      expect(platformIds.externalIdentity?.makerCode, 'START-164');
      expect(platformIds.externalIdentity?.platformIds, {
        'mgs': '107START-164',
        'fanza': '1start00164',
        'sokmil': 'start164',
        'duga': 'start164',
      });

      final compilation = parser.parseWorkPage(
        _fixture('work_compilation.html'),
        pageUri: Uri.parse('https://av-wiki.net/best-001/'),
      );
      expect(compilation.code, 'BEST-001');
      expect(compilation.provenanceFacts.includedWorks, contains('SNOS-371'));
      expect(compilation.provenanceFacts.containsPriorWorks, isTrue);
    },
  );

  test(
    'client validates direct and exact-search lookup, pagination, and health',
    () async {
      final transport = _FixtureTransport({
        '/': _fixture('search.html'),
        '/?s=%E6%B2%B3%E5%8C%97%E5%BD%A9%E8%8A%B1': _fixture('search.html'),
        '/av-actress/kawakita-saika/': _fixture('actress_page.html'),
        '/av-actress/kawakita-saika/page/2/': _fixture('actress_page_2.html'),
        '/snos-371/': _fixture('work_normal.html'),
        '/?s=SNOS-371': _fixture('actress_page.html'),
      });
      final client = AvWikiClient(
        transport: transport,
        requestDelay: Duration.zero,
      );
      addTearDown(client.close);

      await client.checkConnection();
      final actresses = await client.searchActresses('河北彩花');
      final page = await client.fetchActressPage(actresses.single.uri);
      final collection = await client.fetchAllActressWorks(
        actresses.single.uri,
        firstPage: page,
      );
      expect(collection.works, hasLength(3));
      expect(collection.works.map((work) => work.detailUri.path), [
        '/snos-371/',
        '/snos-320/',
        '/sivr-326/',
      ]);
      expect(collection.issues, hasLength(6));

      final limitedClient = AvWikiClient(
        transport: transport,
        maxPages: 1,
        requestDelay: Duration.zero,
      );
      addTearDown(limitedClient.close);
      expect(
        () => limitedClient.fetchAllActressWorks(
          actresses.single.uri,
          firstPage: page,
        ),
        throwsA(isA<AvWikiPageLimitException>()),
      );

      final details = await client.fetchWorkDetailsByCode('SNOS-371');
      expect(details.code, 'SNOS-371');
      expect(
        transport.requested.where((uri) => uri.path == '/snos-371/'),
        isNotEmpty,
      );

      final bridgeClient = AvWikiClient(
        transport: _FixtureTransport({
          '/1start00164/': _fixture('search_empty.html'),
          '/?s=1start00164': _fixture('search_bridge.html'),
          '/start-164/': _fixture('work_platform_ids.html'),
        }),
        requestDelay: Duration.zero,
      );
      addTearDown(bridgeClient.close);
      final bridged = await bridgeClient.fetchWorkDetailsByCode('1start00164');
      expect(bridged.code, 'START-164');

      final emptyClient = AvWikiClient(
        transport: _FixtureTransport({
          '/?s=missing': _fixture('search_empty.html'),
        }),
        requestDelay: Duration.zero,
      );
      addTearDown(emptyClient.close);
      expect(await emptyClient.searchActresses('missing'), isEmpty);

      final malformedClient = AvWikiClient(
        transport: _FixtureTransport({
          '/malformed/': _fixture('work_malformed.html'),
        }),
        requestDelay: Duration.zero,
      );
      addTearDown(malformedClient.close);
      expect(
        () => malformedClient.fetchWorkDetails(
          Uri.parse('https://av-wiki.net/malformed/'),
        ),
        throwsA(
          isA<AvWikiRequestException>().having(
            (error) => error.kind,
            'kind',
            AvWikiFailureKind.parserInvalid,
          ),
        ),
      );

      final wrongCodeClient = AvWikiClient(
        transport: _FixtureTransport({
          '/snos-371/': _fixture('work_wrong_code.html'),
          '/?s=SNOS-371': _fixture('search.html'),
        }),
        requestDelay: Duration.zero,
      );
      addTearDown(wrongCodeClient.close);
      expect(
        () => wrongCodeClient.fetchWorkDetailsByCode('SNOS-371'),
        throwsA(
          isA<AvWikiRequestException>().having(
            (error) => error.kind,
            'kind',
            AvWikiFailureKind.notFound,
          ),
        ),
      );

      final cancelled = await client.fetchAllActressWorks(
        actresses.single.uri,
        firstPage: page,
        isCancelled: () => true,
      );
      expect(cancelled.works, isEmpty);
      expect(
        AvWikiScrapeSource(
          client,
        ).acceptsImageUri(Uri.parse('https://av-wiki.net/image.jpg')),
        isFalse,
      );

      expect(
        () => AvWikiClient(
          transport: transport,
          baseUri: Uri.parse('http://av-wiki.net/'),
        ),
        throwsA(isA<UnsafeHttpUriException>()),
      );
      expect(
        () =>
            client.fetchActressPage(Uri.parse('https://evil.example/actress/')),
        throwsA(isA<UnsafeHttpUriException>()),
      );
    },
  );
}

String _fixture(String name) =>
    File('test/fixtures/avwiki/$name').readAsStringSync();

final class _FixtureTransport implements AvWikiTransport {
  _FixtureTransport(this.pages);

  final Map<String, String> pages;
  final requested = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri);
    final key = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    final page = pages[key];
    if (page == null) {
      throw AvWikiRequestException(uri, 404, kind: AvWikiFailureKind.notFound);
    }
    return page;
  }
}
