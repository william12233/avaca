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

  List<ActressDiscoverySourceOption> get availableSources {
    return registry.sources
        .where(
          (source) => source.supportsRanking && source.supportsPublisherFilter,
        )
        .map(
          (source) => ActressDiscoverySourceOption(
            id: source.id,
            label: source.displayName,
          ),
        )
        .toList(growable: false);
  }

  Future<ActressDiscoverySnapshot> loadRanking(
    ScrapeSourceId sourceId, {
    bool refresh = false,
  }) async {
    final source = _source(sourceId);
    if (!refresh) {
      final cached = cache.rankingFor(sourceId);
      if (cached != null) return _markCollected(cached);
    } else {
      cache.clearRanking(sourceId);
    }
    final snapshot = await source.fetchRanking();
    cache.storeRanking(snapshot);
    return _markCollected(snapshot);
  }

  Future<ActressDiscoverySnapshot> search(
    ScrapeSourceId sourceId,
    String query, {
    bool refresh = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return loadRanking(sourceId, refresh: refresh);
    final source = _source(sourceId);
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

  Future<ActressDiscoverySnapshot> refreshRanking(ScrapeSourceId sourceId) =>
      loadRanking(sourceId, refresh: true);

  Future<ActressDiscoverySnapshot> refreshSearch(
    ScrapeSourceId sourceId,
    String query,
  ) => search(sourceId, query, refresh: true);

  ActressDiscoverySource _source(ScrapeSourceId id) {
    final source = registry.byId(id);
    if (source == null ||
        !source.supportsRanking ||
        !source.supportsPublisherFilter) {
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
  const ActressDiscoverySourceOption({required this.id, required this.label});

  final ScrapeSourceId id;
  final String label;
}
