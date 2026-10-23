import '../../models/scrape_source_settings.dart';
import '../javbus/javbus_client.dart';
import '../javbus/javbus_models.dart';
import 'actress_discovery_models.dart';
import 'actress_discovery_source.dart';

final class JavBusActressDiscoverySource implements ActressDiscoverySource {
  JavBusActressDiscoverySource({required this.client});

  final JavBusClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.javbus;

  @override
  String get displayName => 'JavBus';

  @override
  bool get supportsTags => true;

  @override
  bool get supportsSearch => true;

  @override
  bool acceptsImageUri(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'www.javbus.com' &&
        port == 443 &&
        uri.path.startsWith('/pics/actress/') &&
        !uri.path.toLowerCase().contains('nowprinting');
  }

  @override
  Future<List<ActressDiscoveryTag>> fetchTags() async => [
    ActressDiscoveryTag(
      key: 'censored',
      label: '有碼女優',
      uri: Uri.parse('https://www.javbus.com/actresses'),
      isDefault: true,
    ),
    ActressDiscoveryTag(
      key: 'uncensored',
      label: '無碼女優',
      uri: Uri.parse('https://www.javbus.com/uncensored/actresses'),
    ),
  ];

  @override
  Future<ActressDiscoverySnapshot> fetchTag(
    ActressDiscoveryTag tag, {
    int page = 1,
  }) async {
    final uri = tag.uri;
    if (uri == null) throw ArgumentError('JavBus category URI is missing.');
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
      items: result
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

  ActressDiscoveryItem _item(JavBusActressSearchResult item) =>
      ActressDiscoveryItem(
        source: id,
        name: item.name,
        uri: item.uri,
        imageUri: item.imageUri,
      );

  @override
  void close() => client.close();
}
