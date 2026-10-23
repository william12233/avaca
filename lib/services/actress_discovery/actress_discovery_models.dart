import '../../models/scrape_source_settings.dart';

/// A source-native category or tag that can be used to browse actresses.
final class ActressDiscoveryTag {
  const ActressDiscoveryTag({
    required this.key,
    required this.label,
    this.uri,
    this.count,
    this.isDefault = false,
  });

  final String key;
  final String label;
  final Uri? uri;
  final int? count;
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is ActressDiscoveryTag &&
      other.key == key &&
      other.uri == uri &&
      other.label == label;

  @override
  int get hashCode => Object.hash(key, uri, label);
}

/// A candidate actress exposed by a source-native list or search result.
final class ActressDiscoveryItem {
  const ActressDiscoveryItem({
    required this.source,
    required this.name,
    required this.uri,
    this.imageUri,
    this.tags = const [],
    this.alreadyCollected = false,
    // Compatibility shims for the first discovery prototype.  The UI never
    // renders ranks and no new source populates publishers.
    @Deprecated('Source-native actress lists do not expose ranks.') this.rank,
    @Deprecated('Use tags; publisher filtering was removed.')
    this.publishers = const [],
  });

  final ScrapeSourceId source;
  final String name;
  final Uri uri;
  final Uri? imageUri;
  final List<String> tags;
  final bool alreadyCollected;

  @Deprecated('Source-native actress lists do not expose ranks.')
  final int? rank;

  @Deprecated('Use tags; publisher filtering was removed.')
  final List<String> publishers;

  String get key => '${source.storageValue}|$uri';

  ActressDiscoveryItem copyWith({
    Uri? imageUri,
    List<String>? tags,
    bool? alreadyCollected,
    int? rank,
    List<String>? publishers,
  }) {
    return ActressDiscoveryItem(
      source: source,
      name: name,
      uri: uri,
      imageUri: imageUri ?? this.imageUri,
      tags: tags ?? this.tags,
      alreadyCollected: alreadyCollected ?? this.alreadyCollected,
      rank: rank ?? this.rank,
      publishers: publishers ?? this.publishers,
    );
  }
}

/// The immutable result cached for one source tag/page or one search query.
final class ActressDiscoverySnapshot {
  const ActressDiscoverySnapshot({
    required this.source,
    required this.items,
    required this.fetchedAt,
    this.tag,
    this.query,
    this.isSearch = false,
    this.page = 1,
    this.hasNext = false,
  });

  final ScrapeSourceId source;
  final List<ActressDiscoveryItem> items;
  final DateTime fetchedAt;
  final ActressDiscoveryTag? tag;
  final String? query;
  final bool isSearch;
  final int page;
  final bool hasNext;

  /// Deprecated compatibility getter. Tags replace publisher filtering.
  @Deprecated('Use tag options from ActressDiscoveryController.')
  List<String> get publisherOptions {
    final values = <String>{};
    for (final item in items) {
      values.addAll(item.publishers);
    }
    final result = values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List.unmodifiable(result);
  }

  ActressDiscoverySnapshot copyWith({
    List<ActressDiscoveryItem>? items,
    ActressDiscoveryTag? tag,
    String? query,
    bool? isSearch,
    int? page,
    bool? hasNext,
  }) {
    return ActressDiscoverySnapshot(
      source: source,
      items: items ?? this.items,
      fetchedAt: fetchedAt,
      tag: tag ?? this.tag,
      query: query ?? this.query,
      isSearch: isSearch ?? this.isSearch,
      page: page ?? this.page,
      hasNext: hasNext ?? this.hasNext,
    );
  }
}
