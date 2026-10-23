import '../../models/scrape_source_settings.dart';
import '../minnano/minnano_client.dart';
import 'actress_discovery_models.dart';
import 'actress_discovery_source.dart';

/// Minnano's ranking page exposes the source-native order.  Its actress
/// profile list also exposes the maker/label for each listed work, so the
/// publisher selector can be populated without requesting work detail pages.
final class MinnanoActressDiscoverySource implements ActressDiscoverySource {
  MinnanoActressDiscoverySource({required this.client});

  final MinnanoClient client;

  @override
  ScrapeSourceId get id => ScrapeSourceId.minnanoAv;

  @override
  String get displayName => 'Minnano AV';

  @override
  bool get supportsRanking => true;

  @override
  bool get supportsPublisherFilter => true;

  @override
  Future<ActressDiscoverySnapshot> fetchRanking() async {
    final ranking = await client.fetchActressRanking();
    final items = ranking
        .map(
          (item) => ActressDiscoveryItem(
            source: id,
            name: item.name,
            uri: item.uri,
            rank: item.rank,
            imageUri: item.imageUri,
          ),
        )
        .toList(growable: false);
    return _snapshot(await _enrich(items));
  }

  @override
  Future<ActressDiscoverySnapshot> search(String query) async {
    final matches = await client.searchActresses(query);
    final items = matches
        .map(
          (match) => ActressDiscoveryItem(
            source: id,
            name: match.name,
            uri: match.uri,
          ),
        )
        .toList(growable: false);
    return _snapshot(await _enrich(items), query: query.trim(), isSearch: true);
  }

  @override
  void close() => client.close();

  ActressDiscoverySnapshot _snapshot(
    List<ActressDiscoveryItem> items, {
    String? query,
    bool isSearch = false,
  }) {
    return ActressDiscoverySnapshot(
      source: id,
      items: List.unmodifiable(items),
      fetchedAt: DateTime.now(),
      query: query,
      isSearch: isSearch,
    );
  }

  Future<List<ActressDiscoveryItem>> _enrich(
    List<ActressDiscoveryItem> items,
  ) async {
    if (items.isEmpty) return const [];
    final enriched = List<ActressDiscoveryItem?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= items.length) return;
        final item = items[index];
        try {
          final page = await client.fetchActressPage(item.uri);
          final publishers = <String>{};
          for (final work in page.works) {
            final publisher = work.publisher?.trim();
            if (publisher != null && publisher.isNotEmpty) {
              publishers.add(publisher);
            }
          }
          enriched[index] = item.copyWith(
            imageUri: item.imageUri ?? page.details.avatarUrl,
            publishers: publishers.toList(growable: false),
          );
        } on Object {
          // A single profile may be blocked or malformed.  Keep the ranking
          // card usable and let the publisher list remain partial.
          enriched[index] = item;
        }
      }
    }

    final workers = <Future<void>>[];
    final count = items.length < 4 ? items.length : 4;
    for (var index = 0; index < count; index++) {
      workers.add(worker());
    }
    await Future.wait(workers);
    return enriched.cast<ActressDiscoveryItem>();
  }
}
