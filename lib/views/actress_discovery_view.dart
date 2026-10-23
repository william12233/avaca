import 'package:flutter/material.dart';

import '../controllers/actress_discovery_controller.dart';
import '../core/database.dart';
import '../l10n/app_localizations.dart';
import '../models/scrape_source_settings.dart';
import '../services/actress_discovery/actress_discovery_models.dart';
import '../services/actress_discovery/actress_discovery_service.dart';
import '../services/actress_import_service.dart';
import '../services/scrape_job_coordinator.dart';

/// Source-native actress ranking/search picker.
class ActressDiscoveryView extends StatefulWidget {
  const ActressDiscoveryView({
    super.key,
    required this.db,
    required this.discoveryService,
    required this.importService,
    required this.scrapeJobCoordinator,
  });

  final AppDatabase db;
  final ActressDiscoveryService discoveryService;
  final ActressImportService importService;
  final ScrapeJobCoordinator scrapeJobCoordinator;

  @override
  State<ActressDiscoveryView> createState() => _ActressDiscoveryViewState();
}

class _ActressDiscoveryViewState extends State<ActressDiscoveryView> {
  late final ActressDiscoveryController controller;
  late final TextEditingController searchController;
  final FocusNode searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    controller = ActressDiscoveryController(
      db: widget.db,
      service: widget.discoveryService,
      importService: widget.importService,
      scrapeJobCoordinator: widget.scrapeJobCoordinator,
    )..addListener(_onControllerChanged);
    searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.load();
    });
  }

  @override
  void dispose() {
    controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _submitSearch() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await controller.search(searchController.text);
  }

  Future<void> _importSelected() async {
    final result = await controller.importSelected();
    if (!mounted) return;
    if (result == null) {
      final error = controller.error;
      if (error != null) {
        _showMessage(AppLocalizations.of(context).loadFailed('$error'));
      }
      return;
    }

    final shouldScrape = await _showImportSummary(result);
    if (!mounted || !shouldScrape || result.addedCount == 0) return;
    try {
      final jobs = await controller.enqueueWorks(result);
      if (!mounted) return;
      _showMessage(
        AppLocalizations.of(context).actressDiscoveryBatchQueued(jobs),
      );
      await Navigator.of(context).pushNamed('/scrape-jobs');
    } on Object catch (error) {
      if (mounted) {
        _showMessage(AppLocalizations.of(context).loadFailed('$error'));
      }
    }
  }

  Future<bool> _showImportSummary(ActressImportBatchResult result) async {
    final l10n = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.collectionAdded),
          content: Text(
            '${l10n.actressDiscoveryImportSummary(result.addedCount, result.skippedCount, result.incompleteCount, result.failedCount)}\n\n'
            '${l10n.actressDiscoveryImportQuestion}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.of(context).done),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.actressDiscoveryBatchScrape),
            ),
          ],
        );
      },
    );
    return answer ?? false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.actressDiscoveryTitle),
        actions: [
          IconButton(
            tooltip: l10n.reload,
            onPressed: controller.isLoading
                ? null
                : () {
                    controller.refreshCurrent();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(context),
          if (controller.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildResults(context)),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final source = controller.selectedSource;
    final sourceItems = controller.sources
        .map(
          (option) =>
              DropdownMenuItem(value: option.id, child: Text(option.label)),
        )
        .toList(growable: false);
    final publishers = controller.publisherOptions;
    final publisherItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '',
        child: Text(AppLocalizations.of(context).actressDiscoveryAllPublishers),
      ),
      ...publishers.map(
        (publisher) =>
            DropdownMenuItem(value: publisher, child: Text(publisher)),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Text(AppLocalizations.of(context).actressDiscoverySource),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<ScrapeSourceId>(
                  isExpanded: true,
                  value: source,
                  items: sourceItems,
                  onChanged: controller.isLoading || source == null
                      ? null
                      : (value) {
                          if (value != null) {
                            searchController.clear();
                            controller.selectSource(value);
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: controller.selectedPublisher,
                  items: publisherItems,
                  onChanged: publishers.isEmpty
                      ? null
                      : (value) => controller.selectPublisher(value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: searchController,
            focusNode: searchFocusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submitSearch(),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).actressDiscoverySearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: controller.isLoading
                    ? null
                    : () {
                        _submitSearch();
                      },
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (controller.isSearch)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.isLoading
                    ? null
                    : () {
                        searchController.clear();
                        controller.load();
                      },
                icon: const Icon(Icons.leaderboard_outlined),
                label: Text(
                  AppLocalizations.of(context).actressDiscoveryBackToRanking,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final error = controller.error;
    if (error != null && controller.snapshot == null && !controller.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 42),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context).loadFailed('$error')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  controller.load();
                },
                child: Text(AppLocalizations.of(context).reload),
              ),
            ],
          ),
        ),
      );
    }

    if (controller.isLoading && controller.snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = controller.visibleItems;
    if (items.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noData));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 284,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildCandidateCard(items[index]),
    );
  }

  Widget _buildCandidateCard(ActressDiscoveryItem item) {
    final selected = controller.isSelected(item);
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: item.alreadyCollected
          ? colors.surfaceContainerHighest.withValues(alpha: .55)
          : colors.surfaceContainerHighest,
      child: InkWell(
        onTap: item.alreadyCollected
            ? null
            : () => controller.toggleSelection(item),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildCandidateImage(item)),
                  const SizedBox(height: 7),
                  if (item.rank != null)
                    Text(
                      '#${item.rank}',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    item.publishers.isEmpty
                        ? AppLocalizations.of(
                            context,
                          ).actressDiscoveryPublisherUnavailable
                        : item.publishers.take(2).join('、'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (item.alreadyCollected)
              Positioned(
                top: 8,
                left: 8,
                child: _buildBadge(
                  AppLocalizations.of(context).actressDiscoveryCollected,
                  colors.tertiary,
                ),
              )
            else
              Positioned(
                top: 2,
                right: 2,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => controller.toggleSelection(item),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidateImage(ActressDiscoveryItem item) {
    final uri = item.imageUri;
    if (uri == null || !_isSafeMinnanoImage(uri)) {
      return _imagePlaceholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imagePlaceholder(),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Center(child: Icon(Icons.image_not_supported, size: 42)),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color:
                ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                ? Colors.white
                : Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget? _buildBottomBar(BuildContext context) {
    if (controller.snapshot == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            TextButton(
              onPressed: controller.selectableCount == 0
                  ? null
                  : controller.selectAllVisible,
              child: Text(
                AppLocalizations.of(context).actressDiscoverySelectAll,
              ),
            ),
            TextButton(
              onPressed: controller.selectedCount == 0
                  ? null
                  : controller.clearSelection,
              child: Text(AppLocalizations.of(context).clear),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: controller.selectedCount == 0 || controller.isImporting
                  ? null
                  : _importSelected,
              icon: controller.isImporting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bookmark_add_outlined),
              label: Text(
                AppLocalizations.of(
                  context,
                ).actressDiscoverySelectedCount(controller.selectedCount),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSafeMinnanoImage(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'www.minnano-av.com' &&
        port == 443 &&
        uri.path.startsWith('/p_actress_125_125/');
  }
}
