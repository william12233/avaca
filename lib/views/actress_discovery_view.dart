import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../controllers/actress_discovery_controller.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../services/actress_discovery/actress_discovery_models.dart';
import '../services/actress_discovery/actress_discovery_service.dart';
import '../services/actress_import_service.dart';
import '../services/scrape_job_coordinator.dart';

/// Source-native actress list picker. The route keeps the historical name for
/// compatibility, while the visible product name is 女優榜.
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
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.collectionAdded),
        content: Text(
          '${l10n.actressDiscoveryImportSummary(result.addedCount, result.skippedCount, result.incompleteCount, result.failedCount)}\n\n'
          '${l10n.actressDiscoveryImportQuestion}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.done),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actressDiscoveryBatchScrape),
          ),
        ],
      ),
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
        leading: const AlignedAppBarBackButton(),
        title: Text(l10n.actressDiscoveryTitle),
        actions: [
          IconButton(
            tooltip: l10n.reload,
            onPressed: controller.isLoading ? null : controller.refreshCurrent,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AdaptivePageLayout(
        padding: EdgeInsets.zero,
        compactBuilder: _buildContent,
        expandedBuilder: _buildContent,
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildContent(BuildContext context, AppLayoutTokens tokens) {
    return Column(
      children: [
        _buildFilters(context, tokens),
        if (controller.isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _buildResults(context, tokens)),
      ],
    );
  }

  Widget _buildFilters(BuildContext context, AppLayoutTokens tokens) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.fromLTRB(
        tokens.gridPadding.left,
        tokens.gridGap,
        tokens.gridPadding.right,
        tokens.gridGap / 2,
      ),
      elevation: 0,
      color: colors.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSourceChips(context),
            if (controller.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildTagChips(context),
            ] else if (controller.selectedSourceOption?.supportsSearch ==
                    true &&
                controller.snapshot == null &&
                controller.error == null) ...[
              const SizedBox(height: 6),
              Text(
                '此來源沒有穩定的女優標籤頁，請直接搜尋。',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
              decoration: InputDecoration(
                hintText: l10n.actressDiscoverySearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: l10n.search,
                  onPressed: controller.isLoading ? null : _submitSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
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
                  icon: const Icon(Icons.list_alt_outlined),
                  label: Text(l10n.actressDiscoveryBackToRanking),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceChips(BuildContext context) {
    final selected = controller.selectedSource;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in controller.sources)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option.label),
                selected: option.id == selected,
                onSelected: controller.isLoading
                    ? null
                    : (_) {
                        searchController.clear();
                        controller.selectSource(option.id);
                      },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTagChips(BuildContext context) {
    final selected = controller.selectedTag?.key;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: controller.tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final tag = controller.tags[index];
          final label = tag.count == null
              ? tag.label
              : '${tag.label} ${tag.count}';
          return ChoiceChip(
            label: Text(label),
            selected: tag.key == selected,
            onSelected: controller.isLoading
                ? null
                : (_) => controller.selectTag(tag),
          );
        },
      ),
    );
  }

  Widget _buildResults(BuildContext context, AppLayoutTokens tokens) {
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
              Text(
                AppLocalizations.of(context).loadFailed('$error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.load,
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
      return Center(
        child: Text(
          controller.selectedSourceOption?.supportsSearch == true
              ? '輸入女優名稱開始搜尋'
              : AppLocalizations.of(context).noData,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
              tokens.gridPadding.left,
              tokens.gridGap / 2,
              tokens.gridPadding.right,
              tokens.gridGap,
            ),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 242,
              crossAxisSpacing: tokens.gridGap,
              mainAxisSpacing: tokens.gridGap,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildCandidateCard(items[index]),
          ),
        ),
        if (controller.canLoadNext)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.gridGap),
            child: OutlinedButton.icon(
              onPressed: controller.isLoading ? null : controller.loadNextPage,
              icon: const Icon(Icons.expand_more),
              label: const Text('載入更多'),
            ),
          ),
      ],
    );
  }

  Widget _buildCandidateCard(ActressDiscoveryItem item) {
    final selected = controller.isSelected(item);
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: item.alreadyCollected
            ? colors.surfaceContainerHighest.withValues(alpha: .55)
            : colors.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(width: 1, color: colors.outline),
        ),
        child: InkWell(
          onTap: item.alreadyCollected
              ? null
              : () => controller.toggleSelection(item),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildCandidateImage(item)),
                    const SizedBox(height: 5),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (item.tags.isNotEmpty)
                      Text(
                        item.tags.take(2).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
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
                  top: 0,
                  right: 0,
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => controller.toggleSelection(item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateImage(ActressDiscoveryItem item) {
    final uri = item.imageUri;
    final source = widget.discoveryService.registry.byId(item.source);
    if (uri == null || source == null || !source.acceptsImageUri(uri)) {
      return _imagePlaceholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _imagePlaceholder(),
      ),
    );
  }

  Widget _imagePlaceholder() {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported,
          size: 40,
          color: colors.onSurface,
        ),
      ),
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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      child: SafeArea(
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
                onPressed:
                    controller.selectedCount == 0 || controller.isImporting
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
      ),
    );
  }
}
