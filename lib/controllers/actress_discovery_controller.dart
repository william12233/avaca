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
  ActressDiscoverySnapshot? snapshot;
  String query = '';
  String selectedPublisher = '';
  bool isLoading = false;
  bool isImporting = false;
  Object? error;
  ActressImportBatchResult? lastImport;
  final Set<String> selectedKeys = <String>{};

  List<ActressDiscoverySourceOption> get sources => service.availableSources;

  bool get isSearch => snapshot?.isSearch ?? query.trim().isNotEmpty;

  List<String> get publisherOptions => snapshot?.publisherOptions ?? const [];

  List<ActressDiscoveryItem> get visibleItems {
    final items = snapshot?.items ?? const <ActressDiscoveryItem>[];
    if (selectedPublisher.isEmpty) return items;
    return items
        .where((item) => item.publishers.contains(selectedPublisher))
        .toList(growable: false);
  }

  int get selectableCount =>
      visibleItems.where((item) => !item.alreadyCollected).length;

  int get selectedCount => selectedKeys.length;

  bool isSelected(ActressDiscoveryItem item) => selectedKeys.contains(item.key);

  Future<void> load({bool refresh = false}) async {
    final source = selectedSource;
    if (source == null) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      snapshot = await service.loadRanking(source, refresh: refresh);
      query = '';
      selectedPublisher = '';
      selectedKeys.clear();
    } on Object catch (caught) {
      error = caught;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> search(String value, {bool refresh = false}) async {
    final source = selectedSource;
    final trimmed = value.trim();
    if (source == null) return;
    if (trimmed.isEmpty) {
      await load(refresh: refresh);
      return;
    }
    isLoading = true;
    error = null;
    query = trimmed;
    notifyListeners();
    try {
      snapshot = await service.search(source, trimmed, refresh: refresh);
      selectedPublisher = '';
      selectedKeys.clear();
    } on Object catch (caught) {
      error = caught;
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
    snapshot = null;
    query = '';
    selectedPublisher = '';
    selectedKeys.clear();
    notifyListeners();
    await load();
  }

  void selectPublisher(String publisher) {
    selectedPublisher = publisher;
    selectedKeys.removeWhere(
      (key) => !visibleItems.any((item) => item.key == key),
    );
    notifyListeners();
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
    if (selected.isEmpty || selectedSource == null) return null;

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
      snapshot = snapshot == null
          ? null
          : (snapshot!.isSearch
                ? await service.search(selectedSource!, query)
                : await service.loadRanking(selectedSource!));
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

  Future<ScrapeSourceSettings> _sourceSettings() async {
    return ScrapeSourceSettings.decode(
      await db.getSetting(scrapeSourceSettingsKey),
    );
  }
}
