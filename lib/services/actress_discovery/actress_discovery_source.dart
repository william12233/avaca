import '../../models/scrape_source_settings.dart';
import 'actress_discovery_models.dart';

/// Contract for the source-native actress browser.
///
/// A source may expose categories, search, or both. It must never fabricate a
/// ranking when its site only has a directory or search endpoint.
abstract interface class ActressDiscoverySource {
  ScrapeSourceId get id;

  String get displayName;

  bool get supportsTags;

  bool get supportsSearch;

  /// Whether the source can safely be used as an image origin for this page.
  bool acceptsImageUri(Uri uri);

  Future<List<ActressDiscoveryTag>> fetchTags();

  Future<ActressDiscoverySnapshot> fetchTag(
    ActressDiscoveryTag tag, {
    int page = 1,
  });

  Future<ActressDiscoverySnapshot> search(String query);

  void close();
}
