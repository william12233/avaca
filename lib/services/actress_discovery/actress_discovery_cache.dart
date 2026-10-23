import '../../models/scrape_source_settings.dart';
import 'actress_discovery_models.dart';

/// App-session-only cache for discovery data.
///
/// Nothing is written to SQLite or disk.  Recreating the app clears this
/// cache; a manual refresh removes only the selected source/query entry.
final class ActressDiscoveryCache {
  final Map<ScrapeSourceId, ActressDiscoverySnapshot> _rankings = {};
  final Map<String, ActressDiscoverySnapshot> _searches = {};

  ActressDiscoverySnapshot? rankingFor(ScrapeSourceId source) =>
      _rankings[source];

  void storeRanking(ActressDiscoverySnapshot snapshot) {
    _rankings[snapshot.source] = snapshot;
  }

  ActressDiscoverySnapshot? searchFor(ScrapeSourceId source, String query) =>
      _searches[_searchKey(source, query)];

  void storeSearch(ActressDiscoverySnapshot snapshot) {
    final query = snapshot.query?.trim();
    if (query == null || query.isEmpty) return;
    _searches[_searchKey(snapshot.source, query)] = snapshot;
  }

  void clearRanking(ScrapeSourceId source) {
    _rankings.remove(source);
  }

  void clearSearch(ScrapeSourceId source, String query) {
    _searches.remove(_searchKey(source, query));
  }

  void clearAll() {
    _rankings.clear();
    _searches.clear();
  }

  String _searchKey(ScrapeSourceId source, String query) =>
      '${source.storageValue}|${query.trim().toLowerCase()}';
}
