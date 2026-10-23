import '../../models/scrape_source_settings.dart';
import '../javdb/javdb_client.dart';
import 'actress_discovery_models.dart';
import 'actress_discovery_source.dart';

final class JavDbActressDiscoverySource implements ActressDiscoverySource {
  JavDbActressDiscoverySource({required this.client});

  final JavDbClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.javdb;

  @override
  String get displayName => 'JAVDB';

  @override
  bool get supportsTags => true;

  @override
  bool get supportsSearch => true;

  @override
  bool acceptsImageUri(Uri uri) => client.acceptsImageUri(uri);

  @override
  Future<List<ActressDiscoveryTag>> fetchTags() async {
    // Do not expose a catalog chip when the site only returned a Cloudflare
    // challenge or another blocked response.
    await client.checkConnection();
    return [
      ActressDiscoveryTag(
        key: 'actors',
        label: '女優',
        uri: Uri.parse('https://javdb.com/actors'),
        isDefault: true,
      ),
    ];
  }

  @override
  Future<ActressDiscoverySnapshot> fetchTag(
    ActressDiscoveryTag tag, {
    int page = 1,
  }) async {
    final result = await client.fetchActors(page: page);
    return ActressDiscoverySnapshot(
      source: id,
      tag: tag,
      page: result.page,
      hasNext: result.hasNext,
      items: result.items
          .map(
            (item) => ActressDiscoveryItem(
              source: id,
              name: item.name,
              uri: item.uri,
              imageUri: item.imageUri,
            ),
          )
          .toList(growable: false),
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Future<ActressDiscoverySnapshot> search(String query) async {
    final result = await client.searchActresses(query);
    return ActressDiscoverySnapshot(
      source: id,
      query: query.trim(),
      isSearch: true,
      items: result.items
          .map(
            (item) => ActressDiscoveryItem(
              source: id,
              name: item.name,
              uri: item.uri,
              imageUri: item.imageUri,
            ),
          )
          .toList(growable: false),
      fetchedAt: DateTime.now(),
    );
  }

  @override
  void close() => client.close();
}
