import '../../models/scrape_source_settings.dart';
import '../avbase/avbase_client.dart';
import '../scrape/scrape_models.dart';
import 'actress_discovery_models.dart';
import 'actress_discovery_source.dart';

final class AvBaseActressDiscoverySource implements ActressDiscoverySource {
  AvBaseActressDiscoverySource({required this.client});

  final AvBaseClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.avbase;

  @override
  String get displayName => 'AvBase';

  @override
  bool get supportsTags => true;

  @override
  bool get supportsSearch => true;

  @override
  bool acceptsImageUri(Uri uri) => client.acceptsImageUri(uri);

  @override
  Future<List<ActressDiscoveryTag>> fetchTags() async => [
    ActressDiscoveryTag(
      key: 'recent',
      label: '新着女優',
      uri: Uri.parse('https://www.avbase.net/talents/recent'),
      isDefault: true,
    ),
  ];

  @override
  Future<ActressDiscoverySnapshot> fetchTag(
    ActressDiscoveryTag tag, {
    int page = 1,
  }) async {
    final uri = tag.uri;
    if (uri == null) throw ArgumentError('AvBase list URI is missing.');
    final result = await client.fetchActressDirectory(uri, page: page);
    return ActressDiscoverySnapshot(
      source: id,
      tag: tag,
      page: result.page,
      hasNext: result.hasNext,
      items: result.items.map(_item).toList(growable: false),
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
      items: result.map(_item).toList(growable: false),
      fetchedAt: DateTime.now(),
    );
  }

  ActressDiscoveryItem _item(ScrapeActressSearchResult item) =>
      ActressDiscoveryItem(
        source: id,
        name: item.name,
        uri: item.uri,
        imageUri: item.imageUri,
      );

  @override
  void close() => client.close();
}
