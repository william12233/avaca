import '../../models/scrape_source_settings.dart';

/// A candidate actress exposed by a discovery source.
final class ActressDiscoveryItem {
  const ActressDiscoveryItem({
    required this.source,
    required this.name,
    required this.uri,
    this.rank,
    this.imageUri,
    this.publishers = const [],
    this.alreadyCollected = false,
  });

  final ScrapeSourceId source;
  final String name;
  final Uri uri;
  final int? rank;
  final Uri? imageUri;
  final List<String> publishers;
  final bool alreadyCollected;

  String get key => '${source.storageValue}|$uri';

  ActressDiscoveryItem copyWith({
    int? rank,
    Uri? imageUri,
    List<String>? publishers,
    bool? alreadyCollected,
  }) {
    return ActressDiscoveryItem(
      source: source,
      name: name,
      uri: uri,
      rank: rank ?? this.rank,
      imageUri: imageUri ?? this.imageUri,
      publishers: publishers ?? this.publishers,
      alreadyCollected: alreadyCollected ?? this.alreadyCollected,
    );
  }
}

/// The immutable result cached for one source or one network search query.
final class ActressDiscoverySnapshot {
  const ActressDiscoverySnapshot({
    required this.source,
    required this.items,
    required this.fetchedAt,
    this.query,
    this.isSearch = false,
  });

  final ScrapeSourceId source;
  final List<ActressDiscoveryItem> items;
  final DateTime fetchedAt;
  final String? query;
  final bool isSearch;

  List<String> get publisherOptions {
    final values = <String>{};
    for (final item in items) {
      values.addAll(
        item.publishers
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final result = values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List.unmodifiable(result);
  }

  ActressDiscoverySnapshot copyWith({List<ActressDiscoveryItem>? items}) {
    return ActressDiscoverySnapshot(
      source: source,
      items: items ?? this.items,
      fetchedAt: fetchedAt,
      query: query,
      isSearch: isSearch,
    );
  }
}
