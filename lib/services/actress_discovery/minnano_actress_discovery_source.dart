import '../../models/scrape_source_settings.dart';
import '../minnano/minnano_client.dart';
import '../minnano/minnano_models.dart';
import 'actress_discovery_models.dart';
import 'actress_discovery_source.dart';

final class MinnanoActressDiscoverySource implements ActressDiscoverySource {
  MinnanoActressDiscoverySource({required this.client});

  final MinnanoClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.minnanoAv;

  @override
  String get displayName => 'Minnano AV';

  @override
  bool get supportsTags => true;

  @override
  bool get supportsSearch => true;

  @override
  bool acceptsImageUri(Uri uri) => client.acceptsImageUri(uri);

  @override
  Future<List<ActressDiscoveryTag>> fetchTags() async {
    final tags = await client.fetchActressTags();
    return tags
        .map(
          (tag) => ActressDiscoveryTag(
            key: tag.key,
            label: tag.label,
            uri: tag.uri,
            count: tag.count,
            isDefault: false,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ActressDiscoverySnapshot> fetchTag(
    ActressDiscoveryTag tag, {
    int page = 1,
  }) async {
    final uri = tag.uri;
    if (uri == null) {
      throw ArgumentError('Minnano tag is missing its source URI.');
    }
    final result = await client.fetchActressList(uri, page: page);
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
    final results = await client.searchActresses(query);
    return ActressDiscoverySnapshot(
      source: id,
      query: query.trim(),
      isSearch: true,
      items: results
          .map(
            (result) => ActressDiscoveryItem(
              source: id,
              name: result.name,
              uri: result.uri,
              imageUri: result.imageUri,
            ),
          )
          .toList(growable: false),
      fetchedAt: DateTime.now(),
    );
  }

  ActressDiscoveryItem _item(MinnanoActressListItem item) {
    return ActressDiscoveryItem(
      source: id,
      name: item.name,
      uri: item.uri,
      imageUri: item.imageUri,
      tags: item.tags,
    );
  }

  @override
  void close() => client.close();
}
