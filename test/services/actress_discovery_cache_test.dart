import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/actress_discovery/actress_discovery_cache.dart';
import 'package:avaca/services/actress_discovery/actress_discovery_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final item = ActressDiscoveryItem(
    source: ScrapeSourceId.minnanoAv,
    name: '測試女優',
    uri: Uri.parse('https://www.minnano-av.com/actress1.html'),
    rank: 1,
    publishers: ['測試發行商'],
  );

  test('keeps ranking and search caches in memory by source/query', () {
    final cache = ActressDiscoveryCache();
    final ranking = ActressDiscoverySnapshot(
      source: ScrapeSourceId.minnanoAv,
      items: [item],
      fetchedAt: DateTime(2026, 1, 1),
    );
    final search = ActressDiscoverySnapshot(
      source: ScrapeSourceId.minnanoAv,
      items: [item],
      fetchedAt: DateTime(2026, 1, 1),
      query: '測試',
      isSearch: true,
    );

    cache.storeRanking(ranking);
    cache.storeSearch(search);

    expect(cache.rankingFor(ScrapeSourceId.minnanoAv), same(ranking));
    expect(cache.searchFor(ScrapeSourceId.minnanoAv, ' 測試 '), same(search));

    cache.clearRanking(ScrapeSourceId.minnanoAv);
    expect(cache.rankingFor(ScrapeSourceId.minnanoAv), isNull);
    expect(cache.searchFor(ScrapeSourceId.minnanoAv, '測試'), same(search));

    cache.clearAll();
    expect(cache.searchFor(ScrapeSourceId.minnanoAv, '測試'), isNull);
  });

  test('bounds list and search entries with recent-use eviction', () {
    final cache = ActressDiscoveryCache(maxListEntries: 2, maxSearchEntries: 2);
    ActressDiscoverySnapshot snapshot({int page = 1, String? query}) {
      return ActressDiscoverySnapshot(
        source: ScrapeSourceId.minnanoAv,
        items: [item],
        fetchedAt: DateTime(2026, 1, page),
        page: page,
        query: query,
        isSearch: query != null,
      );
    }

    cache.storeList(snapshot(page: 1));
    cache.storeList(snapshot(page: 2));
    expect(
      cache.listFor(ScrapeSourceId.minnanoAv, 'default', page: 1),
      isNotNull,
    );
    cache.storeList(snapshot(page: 3));
    expect(cache.listFor(ScrapeSourceId.minnanoAv, 'default', page: 2), isNull);

    cache.storeSearch(snapshot(query: 'one'));
    cache.storeSearch(snapshot(query: 'two'));
    expect(cache.searchFor(ScrapeSourceId.minnanoAv, 'one'), isNotNull);
    cache.storeSearch(snapshot(query: 'three'));
    expect(cache.searchFor(ScrapeSourceId.minnanoAv, 'two'), isNull);
  });
}
