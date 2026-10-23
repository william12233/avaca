import '../../core/database.dart';
import '../../models/scrape_source_settings.dart';
import 'actress_discovery_cache.dart';
import 'actress_discovery_models.dart';
import 'actress_discovery_registry.dart';
import 'actress_discovery_source.dart';

final class ActressDiscoveryService {
  ActressDiscoveryService({
    required this.db,
    required this.registry,
    required this.cache,
  });

  final AppDatabase db;
  final ActressDiscoveryRegistry registry;
  final ActressDiscoveryCache cache;

  List<ActressDiscoverySourceOption> get availableSources => registry.sources
      .where((source) => source.supportsTags || source.supportsSearch)
      .map(
        (source) => ActressDiscoverySourceOption(
          id: source.id,
          label: source.displayName,
          supportsTags: source.supportsTags,
          supportsSearch: source.supportsSearch,
        ),
      )
      .toList(growable: false);

  Future<List<ActressDiscoveryTag>> loadTags(
    ScrapeSourceId sourceId, {
    bool refresh = false,
  }) async {
    final source = _source(sourceId);
    if (!source.supportsTags) return const [];
    if (!refresh) {
      final cached = cache.tagsFor(sourceId);
      if (cached != null) return cached;
    }
    final tags = await source.fetchTags();
    cache.storeTags(sourceId, tags);
    return tags;
  }

  Future<ActressDiscoverySnapshot> loadTag(
    ScrapeSourceId sourceId,
    ActressDiscoveryTag tag, {
    int page = 1,
    bool refresh = false,
  }) async {
    final source = _source(sourceId);
    if (!source.supportsTags) {
      throw StateError(
        'Source has no actress directory: ${source.displayName}',
      );
    }
    if (!refresh) {
      final cached = cache.listFor(sourceId, tag.key, page: page);
      if (cached != null) return _markCollected(cached);
    } else {
      cache.clearList(sourceId, tag.key, page: page);
    }
    final snapshot = await source.fetchTag(tag, page: page);
    cache.storeList(snapshot);
    return _markCollected(snapshot);
  }

  Future<ActressDiscoverySnapshot> search(
    ScrapeSourceId sourceId,
    String query, {
    bool refresh = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(query, 'query', 'Must not be empty.');
    }
    final source = _source(sourceId);
    if (!source.supportsSearch) {
      throw StateError('Source has no actress search: ${source.displayName}');
    }
    if (!refresh) {
      final cached = cache.searchFor(sourceId, trimmed);
      if (cached != null) return _markCollected(cached);
    } else {
      cache.clearSearch(sourceId, trimmed);
    }
    final snapshot = await source.search(trimmed);
    cache.storeSearch(snapshot);
    return _markCollected(snapshot);
  }

  Future<ActressDiscoverySnapshot> refreshTag(
    ScrapeSourceId sourceId,
    ActressDiscoveryTag tag, {
    int page = 1,
  }) => loadTag(sourceId, tag, page: page, refresh: true);

  // Compatibility for code from the 1.1 prototype. It now selects the first
  // native tag and never calls a ranking endpoint.
  @Deprecated('Use loadTags and loadTag.')
  Future<ActressDiscoverySnapshot> loadRanking(
    ScrapeSourceId sourceId, {
    bool refresh = false,
  }) async {
    final tags = await loadTags(sourceId, refresh: refresh);
    if (tags.isEmpty) {
      throw StateError('Source has no actress directory.');
    }
    return loadTag(sourceId, tags.first, refresh: refresh);
  }

  @Deprecated('Use refreshTag.')
  Future<ActressDiscoverySnapshot> refreshRanking(ScrapeSourceId sourceId) =>
      loadRanking(sourceId, refresh: true);

  @Deprecated('Use search.')
  Future<ActressDiscoverySnapshot> refreshSearch(
    ScrapeSourceId sourceId,
    String query,
  ) => search(sourceId, query, refresh: true);

  ActressDiscoverySource _source(ScrapeSourceId id) {
    final source = registry.byId(id);
    if (source == null || (!source.supportsTags && !source.supportsSearch)) {
      throw StateError('Discovery source is not available: ${id.storageValue}');
    }
    return source;
  }

  Future<ActressDiscoverySnapshot> _markCollected(
    ActressDiscoverySnapshot snapshot,
  ) async {
    final rows = await db.getAllActresses();
    final names = rows
        .map((row) => row['name']?.toString().trim().toLowerCase())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet();
    return snapshot.copyWith(
      items: snapshot.items
          .map(
            (item) => item.copyWith(
              alreadyCollected: names.contains(item.name.trim().toLowerCase()),
            ),
          )
          .toList(growable: false),
    );
  }
}

final class ActressDiscoverySourceOption {
  const ActressDiscoverySourceOption({
    required this.id,
    required this.label,
    required this.supportsTags,
    required this.supportsSearch,
  });

  final ScrapeSourceId id;
  final String label;
  final bool supportsTags;
  final bool supportsSearch;
}
