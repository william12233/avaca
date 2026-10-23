import '../../models/scrape_source_settings.dart';
import 'actress_discovery_models.dart';

/// App-session-only cache for source-native actress data.
final class ActressDiscoveryCache {
  final Map<String, ActressDiscoverySnapshot> _lists = {};
  final Map<String, ActressDiscoverySnapshot> _searches = {};
  final Map<ScrapeSourceId, List<ActressDiscoveryTag>> _tags = {};

  List<ActressDiscoveryTag>? tagsFor(ScrapeSourceId source) => _tags[source];

  void storeTags(ScrapeSourceId source, List<ActressDiscoveryTag> tags) {
    _tags[source] = List.unmodifiable(tags);
  }

  ActressDiscoverySnapshot? listFor(
    ScrapeSourceId source,
    String tagKey, {
    int page = 1,
  }) => _lists[_listKey(source, tagKey, page)];

  void storeList(ActressDiscoverySnapshot snapshot) {
    final tagKey = snapshot.tag?.key ?? 'default';
    _lists[_listKey(snapshot.source, tagKey, snapshot.page)] = snapshot;
  }

  void clearList(ScrapeSourceId source, String tagKey, {int page = 1}) {
    _lists.remove(_listKey(source, tagKey, page));
  }

  ActressDiscoverySnapshot? searchFor(ScrapeSourceId source, String query) =>
      _searches[_searchKey(source, query)];

  void storeSearch(ActressDiscoverySnapshot snapshot) {
    final query = snapshot.query?.trim();
    if (query == null || query.isEmpty) return;
    _searches[_searchKey(snapshot.source, query)] = snapshot;
  }

  void clearSearch(ScrapeSourceId source, String query) {
    _searches.remove(_searchKey(source, query));
  }

  // Legacy aliases keep consumers of the 1.1 cache source-compatible.
  @Deprecated('Use listFor.')
  ActressDiscoverySnapshot? rankingFor(ScrapeSourceId source) =>
      listFor(source, 'default');

  @Deprecated('Use storeList.')
  void storeRanking(ActressDiscoverySnapshot snapshot) => storeList(snapshot);

  @Deprecated('Use clearList.')
  void clearRanking(ScrapeSourceId source) => clearList(source, 'default');

  void clearAll() {
    _lists.clear();
    _searches.clear();
    _tags.clear();
  }

  String _listKey(ScrapeSourceId source, String tagKey, int page) =>
      '${source.storageValue}|tag:${tagKey.trim().toLowerCase()}|page:$page';

  String _searchKey(ScrapeSourceId source, String query) =>
      '${source.storageValue}|search:${query.trim().toLowerCase()}';
}
