import 'package:flutter/foundation.dart';

import '../core/database.dart';
import '../models/scrape_source_settings.dart';
import '../models/work_scrape_options.dart';
import '../services/actress_discovery/actress_discovery_models.dart';
import '../services/actress_discovery/actress_discovery_service.dart';
import '../services/actress_import_service.dart';
import '../services/scrape_job_coordinator.dart';

final class ActressDiscoveryController extends ChangeNotifier {
  ActressDiscoveryController({
    required this.db,
    required this.service,
    required this.importService,
    required this.scrapeJobCoordinator,
  }) {
    final sources = service.availableSources;
    if (sources.isNotEmpty) selectedSource = sources.first.id;
  }

  final AppDatabase db;
  final ActressDiscoveryService service;
  final ActressImportService importService;
  final ScrapeJobCoordinator scrapeJobCoordinator;

  ScrapeSourceId? selectedSource;
  List<ActressDiscoveryTag> tags = const [];
  ActressDiscoveryTag? selectedTag;
  ActressDiscoverySnapshot? snapshot;
  String query = '';
  bool isLoading = false;
  bool isImporting = false;
  Object? error;
  ActressImportBatchResult? lastImport;
  final Set<String> selectedKeys = <String>{};

  List<ActressDiscoverySourceOption> get sources => service.availableSources;

  ActressDiscoverySourceOption? get selectedSourceOption {
    final source = selectedSource;
    if (source == null) return null;
    for (final option in sources) {
      if (option.id == source) return option;
    }
    return null;
  }

  bool get isSearch => snapshot?.isSearch ?? query.trim().isNotEmpty;

  List<ActressDiscoveryItem> get visibleItems =>
      snapshot?.items ?? const <ActressDiscoveryItem>[];

  int get selectableCount =>
      visibleItems.where((item) => !item.alreadyCollected).length;

  int get selectedCount => selectedKeys.length;

  bool get canLoadNext => snapshot?.hasNext == true && !isSearch;

  bool isSelected(ActressDiscoveryItem item) => selectedKeys.contains(item.key);

  Future<void> load({bool refresh = false}) async {
    final sourceId = selectedSource;
    if (sourceId == null) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      tags = await service.loadTags(sourceId, refresh: refresh);
      selectedTag = _preferredTag(tags);
      query = '';
      selectedKeys.clear();
      if (selectedTag != null) {
        snapshot = await service.loadTag(
          sourceId,
          selectedTag!,
          refresh: refresh,
        );
      } else {
        snapshot = null;
      }
    } on Object catch (caught) {
      error = caught;
      snapshot = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectTag(ActressDiscoveryTag tag) async {
    final sourceId = selectedSource;
    if (sourceId == null || isLoading) return;
    selectedTag = tag;
    query = '';
    selectedKeys.clear();
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      snapshot = await service.loadTag(sourceId, tag);
    } on Object catch (caught) {
      error = caught;
      snapshot = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextPage() async {
    final sourceId = selectedSource;
    final tag = selectedTag;
    final current = snapshot;
    if (sourceId == null || tag == null || current == null || !canLoadNext) {
      return;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final next = await service.loadTag(sourceId, tag, page: current.page + 1);
      final keys = current.items.map((item) => item.key).toSet();
      final combined = [
        ...current.items,
        ...next.items.where((item) => keys.add(item.key)),
      ];
      snapshot = next.copyWith(items: combined);
    } on Object catch (caught) {
      error = caught;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> search(String value, {bool refresh = false}) async {
    final sourceId = selectedSource;
    final trimmed = value.trim();
    if (sourceId == null) return;
    if (trimmed.isEmpty) {
      await load(refresh: refresh);
      return;
    }
    isLoading = true;
    error = null;
    query = trimmed;
    selectedKeys.clear();
    notifyListeners();
    try {
      snapshot = await service.search(sourceId, trimmed, refresh: refresh);
    } on Object catch (caught) {
      error = caught;
      snapshot = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshCurrent() async {
    if (isSearch && query.trim().isNotEmpty) {
      await search(query, refresh: true);
    } else {
      await load(refresh: true);
    }
  }

  Future<void> selectSource(ScrapeSourceId source) async {
    if (selectedSource == source) return;
    selectedSource = source;
    tags = const [];
    selectedTag = null;
    snapshot = null;
    query = '';
    selectedKeys.clear();
    error = null;
    notifyListeners();
    await load();
  }

  void toggleSelection(ActressDiscoveryItem item) {
    if (item.alreadyCollected) return;
    if (!selectedKeys.add(item.key)) selectedKeys.remove(item.key);
    notifyListeners();
  }

  void selectAllVisible() {
    for (final item in visibleItems) {
      if (!item.alreadyCollected) selectedKeys.add(item.key);
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedKeys.clear();
    notifyListeners();
  }

  Future<ActressImportBatchResult?> importSelected() async {
    final selected = visibleItems
        .where((item) => selectedKeys.contains(item.key))
        .where((item) => !item.alreadyCollected)
        .toList(growable: false);
    final sourceId = selectedSource;
    if (selected.isEmpty || sourceId == null) return null;

    isImporting = true;
    error = null;
    notifyListeners();
    try {
      final settings = await _sourceSettings();
      final result = await importService.importItems(
        items: selected,
        detailsSource: settings.actressDetailsSource,
      );
      lastImport = result;
      selectedKeys.clear();
      if (snapshot != null) {
        snapshot = isSearch
            ? await service.search(sourceId, query)
            : await service.loadTag(sourceId, selectedTag!);
      }
      return result;
    } on Object catch (caught) {
      error = caught;
      return null;
    } finally {
      isImporting = false;
      notifyListeners();
    }
  }

  Future<int> enqueueWorks(ActressImportBatchResult result) async {
    final settings = await _sourceSettings();
    final options = WorkScrapeOptions.decode(
      await db.getSetting('works_scrape_options'),
    );
    final actresses = result.results
        .where(
          (item) =>
              item.actressId != null &&
              (item.status == ActressImportStatus.added ||
                  item.status == ActressImportStatus.addedIncomplete),
        )
        .map(
          (item) => (actressId: item.actressId!, actressName: item.item.name),
        );
    final jobs = await scrapeJobCoordinator.enqueueBatch(
      actresses: actresses,
      options: options,
      sourceSettings: settings,
    );
    return jobs.length;
  }

  ActressDiscoveryTag? _preferredTag(List<ActressDiscoveryTag> values) {
    for (final tag in values) {
      if (tag.isDefault) return tag;
    }
    return values.isEmpty ? null : values.first;
  }

  Future<ScrapeSourceSettings> _sourceSettings() async {
    return ScrapeSourceSettings.decode(
      await db.getSetting(scrapeSourceSettingsKey),
    );
  }
}
