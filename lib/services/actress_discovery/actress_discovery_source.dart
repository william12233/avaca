import '../../models/scrape_source_settings.dart';
import 'actress_discovery_models.dart';

/// A source is listed in discovery only when it can provide both a
/// source-native ranking and publisher metadata without crawling individual
/// work detail pages.
abstract interface class ActressDiscoverySource {
  ScrapeSourceId get id;

  String get displayName;

  bool get supportsRanking;

  bool get supportsPublisherFilter;

  Future<ActressDiscoverySnapshot> fetchRanking();

  Future<ActressDiscoverySnapshot> search(String query);

  void close();
}
