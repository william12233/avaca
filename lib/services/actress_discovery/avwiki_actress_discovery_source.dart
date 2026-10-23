import '../../models/scrape_source_settings.dart';
import '../avwiki/avwiki_client.dart';
import '../scrape/scrape_models.dart';
import 'actress_discovery_models.dart';
import 'actress_discovery_source.dart';

/// AV-Wiki currently has a stable actress search endpoint but no stable
/// public actress index. It is therefore exposed as search-only rather than
/// inventing a fake category page.
final class AvWikiActressDiscoverySource implements ActressDiscoverySource {
  AvWikiActressDiscoverySource({required this.client});

  final AvWikiClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.avwiki;

  @override
  String get displayName => 'AV-Wiki';

  @override
  bool get supportsTags => false;

  @override
  bool get supportsSearch => true;

  @override
  bool acceptsImageUri(Uri uri) => false;

  @override
  Future<List<ActressDiscoveryTag>> fetchTags() async => const [];

  @override
  Future<ActressDiscoverySnapshot> fetchTag(
    ActressDiscoveryTag tag, {
    int page = 1,
  }) {
    throw StateError('AV-Wiki does not expose a stable actress directory.');
  }

  @override
  Future<ActressDiscoverySnapshot> search(String query) async {
    final result = await client.searchActresses(query);
    return ActressDiscoverySnapshot(
      source: id,
      query: query.trim(),
      isSearch: true,
      items: result.map(_item).toList(growable: false),
      fetchedAt: DateTime.now(),
    );
  }

  ActressDiscoveryItem _item(ScrapeActressSearchResult item) =>
      ActressDiscoveryItem(source: id, name: item.name, uri: item.uri);

  @override
  void close() => client.close();
}
