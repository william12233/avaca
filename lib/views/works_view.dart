import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../components/app_snackbar.dart';
import '../components/javbus_verification_dialog.dart';
import '../controllers/works_controller.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../models/scrape_source_settings.dart';
import '../models/work_scrape_options.dart';
import '../models/work_storage.dart';
import '../services/avbase/avbase_client.dart';
import '../services/avbase/avbase_scrape_source.dart';
import '../services/avbase/avbase_transport.dart';
import '../services/avwiki/avwiki_client.dart';
import '../services/avwiki/avwiki_scrape_source.dart';
import '../services/avwiki/avwiki_transport.dart';
import '../services/javbus/javbus_client.dart';
import '../services/javbus/javbus_scrape_source.dart';
import '../services/javbus/javbus_verification.dart';
import '../services/javbus/work_image_downloader.dart';
import '../services/javbus/work_image_policy.dart';
import '../services/minnano/minnano_client.dart';
import '../services/minnano/minnano_scrape_source.dart';
import '../services/minnano/minnano_transport.dart';
import '../services/scrape/scrape_image_downloader.dart';
import '../services/scrape/scrape_models.dart';
import '../services/scrape/scrape_source.dart';
import '../services/scrape/scrape_source_registry.dart';
import '../services/scrape_job_coordinator.dart';
import '../services/works_scrape_service.dart';
import '../controllers/settings_controller.dart';
import 'work_detail_view.dart';

typedef WorksScrapeExecutor =
    Future<WorksScrapeResult> Function(
      WorkScrapeOptions options,
      WorksScrapeCancellationToken token,
      void Function(WorksScrapeProgress progress) onProgress,
    );

enum _WorksMenuAction {
  search,
  scrape,
  jobs,
  filterStored,
  filterNotStored,
  filterAll,
}

class WorksView extends StatefulWidget {
  const WorksView({
    super.key,
    required this.db,
    required this.actressId,
    this.scrapeExecutor,
    this.scrapeJobCoordinator,
  });

  final AppDatabase db;
  final int actressId;
  final WorksScrapeExecutor? scrapeExecutor;
  final ScrapeJobCoordinator? scrapeJobCoordinator;

  @override
  State<WorksView> createState() => _WorksViewState();
}

class _WorksViewState extends State<WorksView> {
  late final WorksController controller;

  late final Future<void> initFuture;

  final selectedWorkIds = <int>{};
  final searchTextController = TextEditingController();
  final searchFocusNode = FocusNode();

  var deletionBusy = false;
  var searchOpen = false;
  Timer? _scrapeReloadTimer;
  int _lastWorkDataRevision = 0;
  late final SettingsController settingsController;

  @override
  void initState() {
    super.initState();

    controller = WorksController(db: widget.db, actressId: widget.actressId);

    settingsController = SettingsController(db: widget.db);

    initFuture = controller.init();

    settingsController.loadFromPrefs();

    controller.addListener(_handleControllerChanged);

    settingsController.addListener(_handleSettingsChanged);

    final coordinator = widget.scrapeJobCoordinator;
    if (coordinator != null) {
      _lastWorkDataRevision = coordinator.workDataRevision;
      coordinator.addListener(_handleScrapeJobChanged);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);

    settingsController.removeListener(_handleSettingsChanged);

    _scrapeReloadTimer?.cancel();
    widget.scrapeJobCoordinator?.removeListener(_handleScrapeJobChanged);

    settingsController.dispose();

    searchTextController.dispose();
    searchFocusNode.dispose();

    controller.dispose();

    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleScrapeJobChanged() {
    final coordinator = widget.scrapeJobCoordinator;
    if (!mounted || coordinator == null) return;
    final revision = coordinator.workDataRevision;
    if (revision <= _lastWorkDataRevision) return;
    _lastWorkDataRevision = revision;
    _scrapeReloadTimer ??= Timer(const Duration(milliseconds: 120), () {
      _scrapeReloadTimer = null;
      if (mounted) unawaited(controller.reloadWorks());
    });
  }

  bool get isSelecting => selectedWorkIds.isNotEmpty;

  void _clearSelection() {
    if (selectedWorkIds.isEmpty || !mounted) {
      return;
    }

    setState(selectedWorkIds.clear);
  }

  void _handleBack() {
    if (isSelecting) {
      _clearSelection();

      return;
    }

    if (searchOpen) {
      _closeSearch();

      return;
    }

    Navigator.of(context).pop();
  }

  void _openSearch() {
    if (searchOpen || !mounted) {
      return;
    }

    setState(() => searchOpen = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && searchOpen) {
        searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    if (!searchOpen) {
      return;
    }

    searchFocusNode.unfocus();
    searchTextController.clear();
    controller.changeSearch('');

    if (mounted) {
      setState(() => searchOpen = false);
    }
  }

  void _toggleSelection(Map<String, Object?> work) {
    if (deletionBusy) {
      return;
    }

    final workId = work['id'];

    if (workId is! int) {
      return;
    }

    setState(() {
      if (!selectedWorkIds.add(workId)) {
        selectedWorkIds.remove(workId);
      }
    });
  }

  Future<void> _openDeleteConfirmation() async {
    if (deletionBusy || selectedWorkIds.isEmpty) {
      return;
    }

    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) => AlertDialog(
        key: const Key('works-delete-confirm'),

        title: Text(l10n.deleteWorksTitle),

        content: Text(l10n.deleteWorksWarning),

        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),

            child: Text(l10n.cancel),
          ),

          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),

            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,

              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),

            child: Text(l10n.confirmDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteSelectedWorks();
    }
  }

  Future<void> _deleteSelectedWorks() async {
    if (deletionBusy || selectedWorkIds.isEmpty) {
      return;
    }

    final requested = selectedWorkIds.toList(growable: false);

    setState(() => deletionBusy = true);

    WorkDeletionReport? report;

    Object? error;

    try {
      report = await widget.db.deleteWorksWithReport(requested);

      if (report.databaseCommitted) {
        for (final imagePath in report.cacheEvictionPaths) {
          await FileImage(File(imagePath)).evict();
        }

        await controller.reloadWorks();
      }
    } catch (caught) {
      error = caught;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      deletionBusy = false;

      if (report?.databaseCommitted == true) {
        selectedWorkIds.clear();
      }
    });

    final failed = error != null || report?.databaseCommitted != true;

    final message = failed
        ? AppLocalizations.of(context).deleteFailed
        : AppLocalizations.of(context).worksDeleted(report!.deletedWorkRows);

    if (failed) {
      AppSnackBar.showError(context, message);
    } else {
      AppSnackBar.showSuccess(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: initFuture,

      builder: (context, snapshot) {
        return PopScope(
          canPop: !isSelecting && !searchOpen && !deletionBusy,

          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && isSelecting) {
              _clearSelection();
            } else if (!didPop && searchOpen) {
              _closeSearch();
            }
          },

          child: Scaffold(
            appBar: AppBar(
              leading: AlignedAppBarBackButton(onPressed: _handleBack),

              title: Text(_buildTitle(context)),

              actions: [
                if (isSelecting)
                  IconButton(
                    key: const Key('works-delete-action'),

                    tooltip: AppLocalizations.of(context).deleteWorks,

                    onPressed: deletionBusy ? null : _openDeleteConfirmation,

                    icon: const Icon(Icons.delete_outline),
                  )
                else
                  _buildOverflowMenu(),
              ],
            ),

            body: AdaptivePageLayout(
              padding: EdgeInsets.zero,
              compactBuilder: (context, tokens) =>
                  _buildWorksContent(context, tokens),
              expandedBuilder: (context, tokens) =>
                  _buildWorksContent(context, tokens),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverflowMenu() {
    final l10n = AppLocalizations.of(context);
    final enabled = controller.status == WorksLoadStatus.loaded;

    return PopupMenuButton<_WorksMenuAction>(
      key: const Key('works-overflow-menu'),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _WorksMenuAction.search:
            _openSearch();
          case _WorksMenuAction.scrape:
            _openScrapeSettings();
          case _WorksMenuAction.jobs:
            Navigator.of(context).pushNamed('/scrape-jobs');
          case _WorksMenuAction.filterStored:
            controller.changeStorageFilter(WorkStorageFilter.stored);
          case _WorksMenuAction.filterNotStored:
            controller.changeStorageFilter(WorkStorageFilter.notStored);
          case _WorksMenuAction.filterAll:
            controller.changeStorageFilter(WorkStorageFilter.all);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-search-menu-item'),
          value: _WorksMenuAction.search,
          enabled: enabled,
          child: Row(
            children: [
              const Icon(Icons.search),
              const SizedBox(width: 12),
              Text(l10n.searchWorks),
            ],
          ),
        ),
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-scrape-menu-item'),
          value: _WorksMenuAction.scrape,
          enabled: enabled,
          child: Row(
            children: [
              const Icon(Icons.manage_search),
              const SizedBox(width: 12),
              Text(l10n.scrapeWorks),
            ],
          ),
        ),
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-scrape-jobs-menu-item'),
          value: _WorksMenuAction.jobs,
          child: Row(
            children: [
              const Icon(Icons.queue_play_next_outlined),
              const SizedBox(width: 12),
              Text(l10n.scrapeJobsTitle),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-filter-stored-menu-item'),
          value: _WorksMenuAction.filterStored,
          enabled: enabled,
          child: _buildStorageFilterMenuRow(
            l10n.workStorageFilterStored,
            WorkStorageFilter.stored,
            Icons.bookmark,
          ),
        ),
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-filter-not-stored-menu-item'),
          value: _WorksMenuAction.filterNotStored,
          enabled: enabled,
          child: _buildStorageFilterMenuRow(
            l10n.workStorageFilterNotStored,
            WorkStorageFilter.notStored,
            Icons.bookmark_border,
          ),
        ),
        PopupMenuItem<_WorksMenuAction>(
          key: const Key('works-filter-all-menu-item'),
          value: _WorksMenuAction.filterAll,
          enabled: enabled,
          child: _buildStorageFilterMenuRow(
            l10n.workStorageFilterAll,
            WorkStorageFilter.all,
            Icons.video_library_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildStorageFilterMenuRow(
    String label,
    WorkStorageFilter filter,
    IconData icon,
  ) {
    final selected = controller.storageFilter == filter;
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (selected) const Icon(Icons.check, size: 18),
      ],
    );
  }

  Widget _buildWorksContent(BuildContext context, AppLayoutTokens tokens) {
    return Column(
      children: [
        _buildSearchBar(tokens),
        Expanded(child: _buildBody(context, tokens)),
      ],
    );
  }

  Widget _buildSearchBar(AppLayoutTokens tokens) {
    final isOpen = searchOpen;
    final l10n = AppLocalizations.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.decelerate,
      height: isOpen ? 55 : 0,
      margin: EdgeInsets.only(
        left: tokens.gridPadding.left + 5,
        right: tokens.gridPadding.right + 5,
        top: isOpen ? tokens.gridGap : 0,
        bottom: isOpen ? tokens.gridGap : 0,
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: searchFocusNode.requestFocus,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.search),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('works-search-field'),
                    controller: searchTextController,
                    focusNode: searchFocusNode,
                    decoration: InputDecoration(
                      hintText: l10n.workCodeSearchHint,
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                    onChanged: controller.changeSearch,
                  ),
                ),
                IconButton(
                  key: const Key('works-search-close'),
                  tooltip: l10n.close,
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildTitle(BuildContext context) {
    if (controller.status == WorksLoadStatus.loaded &&
        controller.actressName.isNotEmpty) {
      return AppLocalizations.of(
        context,
      ).actressWorksTitle(controller.actressName);
    }

    return AppLocalizations.of(context).works;
  }

  Widget _buildBody(BuildContext context, AppLayoutTokens tokens) {
    return switch (controller.status) {
      WorksLoadStatus.loading => const Center(
        child: CircularProgressIndicator(),
      ),

      WorksLoadStatus.error => Center(
        child: Text(AppLocalizations.of(context).loadFailedGeneric),
      ),

      WorksLoadStatus.notFound => Center(
        child: Text(AppLocalizations.of(context).dataNotFound),
      ),

      WorksLoadStatus.loaded => _buildLoadedBody(context, tokens),
    };
  }

  Widget _buildLoadedBody(BuildContext context, AppLayoutTokens tokens) {
    if (controller.works.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noWorks));
    }

    final visibleWorks = controller.visibleWorks;

    if (visibleWorks.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noMatchingWorks));
    }

    return _buildWorksGrid(tokens, visibleWorks);
  }

  Widget _buildWorksGrid(
    AppLayoutTokens tokens,
    List<Map<String, Object?>> works,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = settingsController.worksPageSize == WorksPageSize.small;

        final geometry = tokens.gridGeometry(
          availableWidth: constraints.maxWidth,

          minItemWidth: isSmall
              ? tokens.workCardSmallMinWidth
              : tokens.workCardMinWidth,

          maxItemWidth: isSmall
              ? tokens.workCardSmallMaxWidth
              : tokens.workCardMaxWidth,

          itemCount: works.length,

          // Works cards should use the available width naturally. The
          // generic geometry still protects other grids with their own
          // maxUsefulColumns values, but a fixed 4/6 cap leaves artificial
          // rails on wide Works pages when there are enough items.
          maxUsefulColumns: works.length,
        );

        return Align(
          alignment: Alignment.topCenter,

          child: SizedBox(
            width: geometry.railWidth,

            height: constraints.maxHeight,

            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                0,

                tokens.sectionGap,

                0,

                tokens.sectionGap * 1.5,
              ),

              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: geometry.columns,

                crossAxisSpacing: tokens.gridGap,

                mainAxisSpacing: tokens.sectionGap,

                childAspectRatio: 0.54,
              ),

              itemCount: works.length,

              itemBuilder: (context, index) {
                final work = works[index];

                final workId = work['id'];

                final selected =
                    workId is int && selectedWorkIds.contains(workId);

                return KeyedSubtree(
                  key: selected ? Key('work-card-selected-$workId') : null,

                  child: _WorkCard(
                    key: Key('work-card-$workId'),

                    work: work,

                    selected: selected,

                    onTap: () {
                      if (isSelecting) {
                        _toggleSelection(work);
                      } else {
                        _openWorkDetail(work);
                      }
                    },

                    onLongPress: () => _toggleSelection(work),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openWorkDetail(Map<String, Object?> work) async {
    final workId = work['id'];

    if (workId is! int) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailView(
          db: widget.db,
          workId: workId,
          currentActressId: widget.actressId,
        ),
      ),
    );

    if (mounted) {
      await controller.reloadWorks();
    }
  }

  Future<void> _openScrapeSettings() async {
    WorkScrapeOptions options;

    try {
      options = WorkScrapeOptions.decode(
        await widget.db.getSetting('works_scrape_options'),
      );
    } catch (_) {
      options = const WorkScrapeOptions();
    }

    if (!mounted) {
      return;
    }

    final coordinator = widget.scrapeJobCoordinator;
    if (coordinator != null) {
      ScrapeSourceSettings sourceSettings;
      try {
        sourceSettings = ScrapeSourceSettings.decode(
          await widget.db.getSetting(scrapeSourceSettingsKey),
        );
      } catch (_) {
        sourceSettings = const ScrapeSourceSettings();
      }
      final job = await coordinator.enqueue(
        actressId: widget.actressId,
        actressName: controller.actressName,
        options: options,
        sourceSettings: sourceSettings,
      );
      if (!mounted) return;
      await Navigator.of(context).pushNamed('/scrape-job/${job.id}');
      await controller.reloadWorks();
      return;
    }

    await _runScrape(options);
  }

  Future<void> _runScrape(WorkScrapeOptions options) async {
    final token = WorksScrapeCancellationToken();

    final progress = ValueNotifier<WorksScrapeProgress?>(null);

    final executor = widget.scrapeExecutor ?? _defaultScrapeExecutor;

    NavigatorState? progressNavigator;

    Route<void>? progressRoute;

    final dialog = showDialog<void>(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        progressNavigator = Navigator.of(dialogContext);

        progressRoute = ModalRoute.of(dialogContext);

        return PopScope(
          canPop: false,

          child: _ScrapeProgressDialog(
            progress: progress,

            actressName: controller.actressName,

            onCancel: token.cancel,
          ),
        );
      },
    );

    await WidgetsBinding.instance.endOfFrame;

    WorksScrapeResult? result;

    Object? scrapeError;

    try {
      result = await executor(
        options,

        token,

        (value) => progress.value = value,
      );

      await controller.reloadWorks();
    } catch (error) {
      scrapeError = error;
    } finally {
      final route = progressRoute;

      if (route != null && route.isActive) {
        progressNavigator?.removeRoute(route);
      }

      await dialog;

      progress.dispose();
    }

    if (!mounted) {
      return;
    }

    final l10n = AppLocalizations.of(context);

    final completedResult = result;

    if (scrapeError != null || completedResult == null) {
      await _showScrapeResultDialog(l10n.scrapeFailed);

      return;
    }

    final cancelled = completedResult.cancelled;

    final notices = <String>[];
    if (!cancelled) {
      switch (completedResult.actressImageStatus) {
        case ActressImageSyncStatus.unavailable:
          notices.add(l10n.scrapeAvatarUnavailable);
        case ActressImageSyncStatus.downloadFailed:
        case ActressImageSyncStatus.databaseFailed:
          notices.add(l10n.scrapeAvatarFailed);
        case ActressImageSyncStatus.notRequested:
        case ActressImageSyncStatus.replaced:
          break;
      }
    }

    final hasNoChanges =
        !cancelled &&
        completedResult.saved == 0 &&
        completedResult.excluded == 0 &&
        completedResult.failed == 0 &&
        completedResult.imageFailures.isEmpty;
    if (hasNoChanges) {
      notices.add(l10n.scrapeZeroResults);
    } else if (completedResult.partialSuccess && !cancelled) {
      notices.add(l10n.scrapePartial);
    }

    await _showScrapeResultDialog(
      notices.isEmpty ? null : notices.join(' '),
      result: completedResult,
    );
  }

  Future<void> _showScrapeResultDialog(
    String? notice, {
    WorksScrapeResult? result,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: _ScrapeResultDialog(notice: notice, result: result),
      ),
    );
  }

  Future<WorksScrapeResult> _defaultScrapeExecutor(
    WorkScrapeOptions options,
    WorksScrapeCancellationToken token,
    void Function(WorksScrapeProgress progress) onProgress,
  ) async {
    ScrapeSourceSettings sourceSettings;
    try {
      sourceSettings = ScrapeSourceSettings.decode(
        await widget.db.getSetting(scrapeSourceSettingsKey),
      );
    } catch (_) {
      sourceSettings = const ScrapeSourceSettings();
    }

    final requestedSourceIds = <ScrapeSourceId>{
      sourceSettings.actressDetailsSource,
      ...ScrapeSourceRegistry.resolveWorksSources(sourceSettings.worksSources),
    };
    if (options.scrapeAliases) {
      requestedSourceIds.add(sourceSettings.aliasSource);
    }
    final configuredSources = <ScrapeSourceId, ScrapeSource>{};
    HttpJavBusTransport? javBusTransport;
    HttpMinnanoTransport? minnanoTransport;
    MinnanoClient? minnanoClient;
    HttpBinaryTransport? minnanoAvatarTransport;
    HttpAvBaseTransport? avbaseTransport;
    AvBaseClient? avbaseClient;
    HttpBinaryTransport? avbaseAvatarTransport;
    HttpScrapeImageUriDownloader? imageUriDownloader;

    if (requestedSourceIds.contains(ScrapeSourceId.javbus)) {
      String? initialCookies;
      try {
        initialCookies = await widget.db.getSetting('javbus_cookies');
      } catch (_) {
        initialCookies = null;
      }
      javBusTransport = HttpJavBusTransport(
        initialCookieHeader: initialCookies,
        verificationHandler: _showJavBusVerification,
      );
      configuredSources[ScrapeSourceId.javbus] = JavBusScrapeSource(
        JavBusClient(transport: javBusTransport),
      );
    }
    if (requestedSourceIds.contains(ScrapeSourceId.minnanoAv)) {
      minnanoTransport = HttpMinnanoTransport();
      minnanoClient = MinnanoClient(transport: minnanoTransport);
      configuredSources[ScrapeSourceId.minnanoAv] = MinnanoScrapeSource(
        minnanoClient,
      );
      minnanoAvatarTransport = HttpBinaryTransport(
        allowedHosts: const {'www.minnano-av.com'},
        maxBytes: 5 * 1024 * 1024,
      );
      imageUriDownloader = HttpScrapeImageUriDownloader(
        isAllowed: minnanoClient.acceptsImageUri,
        transport: HttpBinaryTransport(
          allowedHosts: const {'www.minnano-av.com'},
          maxBytes: 15 * 1024 * 1024,
        ),
      );
    }
    if (requestedSourceIds.contains(ScrapeSourceId.avbase)) {
      avbaseTransport = HttpAvBaseTransport();
      avbaseClient = AvBaseClient(transport: avbaseTransport);
      configuredSources[ScrapeSourceId.avbase] = AvBaseScrapeSource(
        avbaseClient,
      );
      avbaseAvatarTransport = HttpBinaryTransport(
        allowedHosts: const {'pics.dmm.co.jp'},
        maxBytes: 5 * 1024 * 1024,
      );
    }
    if (requestedSourceIds.contains(ScrapeSourceId.avwiki)) {
      final transport = HttpAvWikiTransport();
      final client = AvWikiClient(transport: transport);
      configuredSources[ScrapeSourceId.avwiki] = AvWikiScrapeSource(client);
    }

    final detailsImageDownloader =
        switch (sourceSettings.actressDetailsSource) {
          ScrapeSourceId.minnanoAv => HttpActressImageDownloader(
            transport: minnanoAvatarTransport,
          ),
          ScrapeSourceId.avbase => HttpActressImageDownloader(
            transport: avbaseAvatarTransport,
          ),
          ScrapeSourceId.javbus => HttpActressImageDownloader(
            authenticatedTransport: javBusTransport,
          ),
          ScrapeSourceId.avwiki => HttpActressImageDownloader(
            transport: HttpBinaryTransport(
              allowedHosts: const {'av-wiki.net', 'www.av-wiki.net'},
              maxBytes: 5 * 1024 * 1024,
            ),
          ),
        };
    final service = WorksScrapeService(
      db: widget.db,
      sources: configuredSources,
      actressImageDownloader: detailsImageDownloader,
      imageUriDownloader: imageUriDownloader,
    );

    try {
      return await service.scrape(
        actressId: widget.actressId,

        actressName: controller.actressName,

        aliases: controller.actressAliases,
        options: options,
        sourceSettings: sourceSettings,
        cancellationToken: token,
        onProgress: onProgress,
      );
    } finally {
      if (javBusTransport != null && javBusTransport.cookieHeader.isNotEmpty) {
        try {
          await widget.db.setSetting(
            'javbus_cookies',
            javBusTransport.cookieHeader,
          );
        } catch (_) {
          // Cookie 儲存失敗不應遮蔽原始刮削結果。
        }
      }

      service.close();
    }
  }

  Future<Map<String, String>?> _showJavBusVerification(
    JavBusVerificationChallenge challenge,
  ) {
    if (!mounted) {
      return Future.value(null);
    }

    return showDialog<Map<String, String>>(
      context: context,

      barrierDismissible: false,

      builder: (context) => JavBusVerificationDialog(challenge: challenge),
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    super.key,
    required this.work,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<String, Object?> work;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final title = work['title']?.toString() ?? '';
    final code = work['code']?.toString() ?? '';
    final releaseDate = work['release_date']?.toString() ?? '';
    final imagePath = work['card_image_path']?.toString() ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(
                    child: _LocalWorkImage(
                      path: imagePath,
                      icon: Icons.movie_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colorScheme.primary),
              ),
              const SizedBox(height: 4),
              Text(
                releaseDate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.primary, width: 2),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: colorScheme.primary,
                      child: Icon(
                        Icons.check,
                        size: 15,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LocalWorkImage extends StatelessWidget {
  const _LocalWorkImage({required this.path, required this.icon});

  final String path;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, color: colorScheme.onSurfaceVariant, size: 36),
      ),
    );
  }
}

class _ScrapeProgressDialog extends StatelessWidget {
  const _ScrapeProgressDialog({
    required this.progress,
    required this.actressName,
    required this.onCancel,
  });

  final ValueListenable<WorksScrapeProgress?> progress;
  final String actressName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final padding = _scrapeProgressDialogPadding(context);
    final viewportSize = MediaQuery.sizeOf(context);
    final dialogWidth = (viewportSize.width - padding * 2)
        .clamp(240.0, 640.0)
        .toDouble();
    final contentWidth = dialogWidth - padding * 2;
    return AlertDialog(
      key: const Key('scrape-progress-dialog'),
      insetPadding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_scrapeDialogRadius),
      ),
      titlePadding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
      title: _ScrapeDialogHeading(
        title: l10n.scrapeSyncingTitle,
        subtitle: actressName.trim().isEmpty ? null : actressName.trim(),
        compact: true,
      ),
      contentPadding: EdgeInsets.fromLTRB(padding, 8, padding, 0),
      content: SizedBox(
        width: contentWidth,
        child: _ScrapeDialogViewport(
          shrinkWrap: true,
          child: ValueListenableBuilder<WorksScrapeProgress?>(
            valueListenable: progress,
            builder: (context, value, child) {
              return _ScrapeProgressContent(value: value);
            },
          ),
        ),
      ),
      actionsPadding: EdgeInsets.fromLTRB(padding, 4, padding, 8),
      actions: [TextButton(onPressed: onCancel, child: Text(l10n.stopScrape))],
    );
  }
}

class _ScrapeProgressContent extends StatelessWidget {
  const _ScrapeProgressContent({required this.value});

  final WorksScrapeProgress? value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phase = value?.phase ?? WorksScrapePhase.collectingSources;
    final sourceProgress =
        value?.sourceProgress ??
        const <ScrapeSourceId, WorksScrapeSourceProgress>{};
    final detailsSource = value?.detailsSource;
    final inferredWorkSources = sourceProgress.keys
        .where((source) => source != detailsSource)
        .toList(growable: false);
    final worksSources = value?.worksSources.isNotEmpty == true
        ? value!.worksSources
        : inferredWorkSources.isNotEmpty
        ? inferredWorkSources
        : value?.source != null && value!.source != detailsSource
        ? [value!.source!]
        : const <ScrapeSourceId>[];
    final workCode = value?.workCode?.trim();

    final detailsBody = detailsSource == null
        ? _ScrapeEmptyState(text: l10n.scrapeStatusWaiting)
        : _ScrapeSourceRow(
            label: _scrapeSourceLabel(l10n, detailsSource),
            status: _scrapeDetailsProgressStatus(
              l10n,
              value,
              detailsSource,
              sourceProgress[detailsSource],
            ),
            compact: true,
          );

    final worksBody = Column(
      key: const Key('scrape-progress-sources'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (worksSources.isEmpty)
          _ScrapeEmptyState(text: l10n.scrapeStatusWaiting)
        else
          for (final source in worksSources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ScrapeSourceProgressRow(
                source: source,
                value: value,
                progress: sourceProgress[source],
                isActive: value?.source == source,
              ),
            ),
        _ScrapeSummary(
          key: const Key('scrape-progress-summary'),
          saved: value?.saved ?? 0,
          excluded: value?.excluded ?? 0,
          failed: value?.failed ?? 0,
          compact: true,
        ),
      ],
    );

    final downloadActive = phase == WorksScrapePhase.downloadingImages;
    final downloadComplete =
        phase.index > WorksScrapePhase.downloadingImages.index;
    final downloadBody = _ScrapeSourceRow(
      label: l10n.scrapeImagesLabel,
      status: downloadActive
          ? l10n.scrapeStatusSyncing
          : downloadComplete
          ? l10n.scrapeStatusCompleted
          : l10n.scrapeStatusWaiting,
      detail: downloadActive && workCode != null && workCode.isNotEmpty
          ? l10n.scrapeCurrentWork(workCode)
          : null,
      detailKey: downloadActive
          ? const Key('scrape-progress-current-work')
          : null,
      indeterminateProgress: downloadActive,
      progressIndicatorKey: downloadActive
          ? const Key('scrape-progress-download-circular')
          : null,
      reserveProgressIndicator: true,
      reserveDetailSlot: true,
      compact: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ScrapeSection(
          title: l10n.scrapeDetailsSection,
          compact: true,
          child: detailsBody,
        ),
        _ScrapeSection(
          title: l10n.scrapeWorksSection,
          compact: true,
          child: worksBody,
        ),
        _ScrapeSection(
          title: l10n.scrapeDownloadSection,
          compact: true,
          child: downloadBody,
        ),
      ],
    );
  }
}

class _ScrapeResultDialog extends StatelessWidget {
  const _ScrapeResultDialog({required this.notice, this.result});

  final String? notice;
  final WorksScrapeResult? result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final padding = _scrapeDialogPadding(context);
    final currentResult = result;
    final detailsSource = currentResult == null
        ? null
        : _resultDetailsSource(currentResult);
    final worksSources = currentResult == null
        ? const <ScrapeSourceId>[]
        : _resultWorksSources(currentResult, detailsSource);

    final body = <Widget>[
      if (notice != null && notice!.trim().isNotEmpty)
        Text(
          notice!,
          key: const Key('scrape-result-message'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      if (currentResult != null) ...[
        _ScrapeSection(
          title: l10n.scrapeDetailsSection,
          child: detailsSource == null
              ? _ScrapeEmptyState(text: l10n.scrapeStatusUnavailable)
              : _ScrapeResultDetailsBody(
                  source: detailsSource,
                  result: currentResult,
                ),
        ),
        _ScrapeSection(
          title: l10n.scrapeWorksSection,
          titleKey: const Key('scrape-source-results-title'),
          child: _ScrapeResultWorksBody(
            sources: worksSources,
            result: currentResult,
          ),
        ),
        _ScrapeSection(
          title: l10n.scrapeDownloadSection,
          child: _ScrapeResultDownloadBody(result: currentResult),
        ),
      ],
    ];
    if (body.isEmpty) {
      body.add(
        Text(l10n.scrapeFailed, key: const Key('scrape-result-message')),
      );
    }

    return AlertDialog(
      key: const Key('scrape-result-dialog'),
      insetPadding: EdgeInsets.symmetric(horizontal: padding, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_scrapeDialogRadius),
      ),
      titlePadding: EdgeInsets.fromLTRB(padding, 24, padding, 0),
      title: _ScrapeDialogHeading(
        title: _scrapeResultTitle(l10n, currentResult),
      ),
      contentPadding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
      content: _ScrapeDialogViewport(
        key: const Key('scrape-result-scroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: body,
        ),
      ),
      actionsPadding: EdgeInsets.fromLTRB(padding, 8, padding, 16),
      actions: [
        FilledButton(
          key: const Key('scrape-result-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}

class _ScrapeResultDetailsBody extends StatelessWidget {
  const _ScrapeResultDetailsBody({required this.source, required this.result});

  final ScrapeSourceId source;
  final WorksScrapeResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sourceResult = result.sourceResults[source];
    final imageNotice = switch (result.actressImageStatus) {
      ActressImageSyncStatus.unavailable => l10n.scrapeAvatarUnavailable,
      ActressImageSyncStatus.downloadFailed ||
      ActressImageSyncStatus.databaseFailed => l10n.scrapeAvatarFailed,
      ActressImageSyncStatus.notRequested ||
      ActressImageSyncStatus.replaced => null,
    };
    return _ScrapeSourceRow(
      label: _scrapeSourceLabel(l10n, source),
      status: sourceResult == null
          ? result.cancelled
                ? l10n.scrapeStatusCancelled
                : l10n.scrapeStatusUnavailable
          : _scrapeSourceStateLabel(
              l10n,
              sourceResult.state,
              isDetailsSource: true,
            ),
      detail: imageNotice,
    );
  }
}

class _ScrapeResultWorksBody extends StatelessWidget {
  const _ScrapeResultWorksBody({required this.sources, required this.result});

  final List<ScrapeSourceId> sources;
  final WorksScrapeResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <Widget>[];
    for (final source in sources) {
      final sourceResult = result.sourceResults[source];
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ScrapeSourceRow(
            label: _scrapeSourceLabel(l10n, source),
            status: sourceResult == null
                ? result.cancelled
                      ? l10n.scrapeStatusCancelled
                      : l10n.scrapeStatusUnavailable
                : _scrapeSourceStateLabel(l10n, sourceResult.state),
            detail: sourceResult?.error?.toString(),
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(_ScrapeEmptyState(text: l10n.scrapeStatusUnavailable));
    }
    rows.add(
      _ScrapeSummary(
        saved: result.saved,
        excluded: result.excluded,
        failed: result.failed,
      ),
    );
    if (result.failedWorks.isNotEmpty) {
      rows.add(const SizedBox(height: 16));
      rows.add(
        Text(
          l10n.scrapeFailedWorksTitle(result.failedWorks.length),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      );
      rows.add(const SizedBox(height: 8));
      rows.add(
        _ScrapeFailureList(
          children: [
            for (final failure in result.failedWorks)
              _ScrapeFailureRow(
                code: failure.code,
                reason: _scrapeFailureReasonLabel(l10n, failure.reason),
                error: failure.error,
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _ScrapeResultDownloadBody extends StatelessWidget {
  const _ScrapeResultDownloadBody({required this.result});

  final WorksScrapeResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failures = result.imageFailures;
    final status = result.cancelled
        ? l10n.scrapeStatusCancelled
        : failures.isEmpty
        ? l10n.scrapeStatusCompleted
        : l10n.scrapeStatusPartial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScrapeSourceRow(
          label: l10n.scrapeImagesLabel,
          status: status,
          detail: failures.isEmpty
              ? null
              : l10n.scrapeImageFailuresTitle(failures.length),
        ),
        if (failures.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ScrapeFailureList(
            children: [
              for (final failure in failures)
                _ScrapeFailureRow(
                  code: failure.code,
                  reason: _scrapeImageFailureLabel(l10n, failure.variants),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ScrapeDialogHeading extends StatelessWidget {
  const _ScrapeDialogHeading({
    required this.title,
    this.subtitle,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          SizedBox(height: compact ? 2 : 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ScrapeDialogViewport extends StatelessWidget {
  const _ScrapeDialogViewport({
    required this.child,
    this.shrinkWrap = false,
    super.key,
  });

  final Widget child;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final scrollable = SingleChildScrollView(child: child);
    if (shrinkWrap) {
      return scrollable;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 640,
        maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      ),
      child: scrollable,
    );
  }
}

class _ScrapeSection extends StatelessWidget {
  const _ScrapeSection({
    required this.title,
    required this.child,
    this.titleKey,
    this.compact = false,
  });

  final String title;
  final Widget child;
  final Key? titleKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tokens = AppLayoutPolicy.resolve(
      BoxConstraints.tightFor(width: width),
    );
    final sectionGap = compact ? 8.0 : tokens.sectionGap;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(
            height: sectionGap,
            color: theme.colorScheme.outline.withValues(alpha: 0.35),
          ),
          Text(
            title,
            key: titleKey,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          child,
        ],
      ),
    );
  }
}

class _ScrapeSourceProgressRow extends StatelessWidget {
  const _ScrapeSourceProgressRow({
    required this.source,
    required this.value,
    required this.progress,
    required this.isActive,
  });

  final ScrapeSourceId source;
  final WorksScrapeProgress? value;
  final WorksScrapeSourceProgress? progress;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = progress?.total ?? 0;
    final current = _scrapeSafeProgressCurrent(progress?.current ?? 0, total);
    final hasKnownTotal = progress?.hasKnownTotal ?? false;
    final hasCount = hasKnownTotal && total > 0;
    final indeterminate = isActive && !hasKnownTotal;
    return _ScrapeSourceRow(
      label: _scrapeSourceLabel(l10n, source),
      status: _scrapeWorkProgressStatus(l10n, value, progress, isActive),
      count: hasCount ? '$current / $total' : null,
      countKey: isActive && hasCount
          ? const Key('scrape-progress-count')
          : null,
      progressValue: hasCount
          ? _scrapeProgressValue(progress?.current ?? 0, total)
          : null,
      indeterminateProgress: indeterminate,
      progressIndicatorKey: isActive
          ? const Key('scrape-progress-circular')
          : null,
      reserveProgressIndicator: true,
      reserveCountSlot: true,
      compact: true,
    );
  }
}

class _ScrapeSourceRow extends StatelessWidget {
  const _ScrapeSourceRow({
    required this.label,
    required this.status,
    this.count,
    this.countKey,
    this.detail,
    this.detailKey,
    this.progressValue,
    this.indeterminateProgress = false,
    this.progressIndicatorKey,
    this.reserveProgressIndicator = false,
    this.reserveCountSlot = false,
    this.reserveDetailSlot = false,
    this.compact = false,
  });

  final String label;
  final String status;
  final String? count;
  final Key? countKey;
  final String? detail;
  final Key? detailKey;
  final double? progressValue;
  final bool indeterminateProgress;
  final Key? progressIndicatorKey;
  final bool reserveProgressIndicator;
  final bool reserveCountSlot;
  final bool reserveDetailSlot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProgressIndicator = progressValue != null || indeterminateProgress;
    final showProgressIndicator =
        hasProgressIndicator || reserveProgressIndicator;
    final showCountSlot = count != null || reserveCountSlot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: compact ? 24 : 28,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (showProgressIndicator) ...[
                        SizedBox(width: compact ? 6 : 8),
                        SizedBox(
                          width: compact ? 18 : 20,
                          height: compact ? 18 : 20,
                          child: hasProgressIndicator
                              ? CircularProgressIndicator(
                                  key: progressIndicatorKey,
                                  value: progressValue,
                                  strokeWidth: 2.5,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                      if (showCountSlot) ...[
                        SizedBox(width: compact ? 6 : 8),
                        SizedBox(
                          width: compact ? 64 : 72,
                          height: compact ? 22 : 24,
                          child: count == null
                              ? const SizedBox.shrink()
                              : Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      count!,
                                      key: countKey,
                                      maxLines: 1,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (reserveDetailSlot)
          SizedBox(
            height: compact ? 22 : 24,
            child: detail != null && detail!.trim().isNotEmpty
                ? Text(
                    detail!,
                    key: detailKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : const SizedBox.shrink(),
          )
        else if (detail != null && detail!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            detail!,
            key: detailKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ScrapeSummary extends StatelessWidget {
  const _ScrapeSummary({
    required this.saved,
    required this.excluded,
    required this.failed,
    this.compact = false,
    super.key,
  });

  final int saved;
  final int excluded;
  final int failed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary =
        '${l10n.scrapeSavedCount} $saved '
        '${l10n.scrapeExcludedCount} $excluded '
        '${l10n.scrapeFailedCount} $failed';
    return SizedBox(
      height: compact ? 24 : 28,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(summary, maxLines: 1),
      ),
    );
  }
}

class _ScrapeEmptyState extends StatelessWidget {
  const _ScrapeEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _ScrapeFailureList extends StatelessWidget {
  const _ScrapeFailureList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          children[index],
        ],
      ],
    );
  }
}

class _ScrapeFailureRow extends StatelessWidget {
  const _ScrapeFailureRow({
    required this.code,
    required this.reason,
    this.error,
  });

  final String code;
  final String reason;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(code, style: theme.textTheme.bodyMedium),
        Text(
          reason,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null)
          Text(
            error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

const _scrapeDialogRadius = 28.0;

double _scrapeDialogPadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final tokens = AppLayoutPolicy.resolve(BoxConstraints.tightFor(width: width));
  return tokens.isCompact ? 20 : 24;
}

double _scrapeProgressDialogPadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final tokens = AppLayoutPolicy.resolve(BoxConstraints.tightFor(width: width));
  return tokens.isCompact ? 16 : 20;
}

int _scrapeSafeProgressCurrent(int current, int total) {
  final nonNegative = current < 0 ? 0 : current;
  if (total <= 0) {
    return nonNegative;
  }
  return nonNegative.clamp(0, total).toInt();
}

double _scrapeProgressValue(int current, int total) {
  if (total <= 0) {
    return 0;
  }
  return _scrapeSafeProgressCurrent(current, total) / total;
}

String _scrapeResultTitle(AppLocalizations l10n, WorksScrapeResult? result) {
  if (result == null) {
    return l10n.scrapeSyncFailed;
  }
  if (result.cancelled) {
    return l10n.scrapeSyncStopped;
  }
  final hasWorkFailure = result.failed > 0;
  final hasSourceFailure = result.sourceResults.values.any(
    (source) =>
        source.state != ScrapeSourceRunState.success &&
        source.state != ScrapeSourceRunState.zeroResults,
  );
  if ((hasWorkFailure || hasSourceFailure) &&
      result.saved == 0 &&
      result.excluded == 0) {
    return l10n.scrapeSyncFailed;
  }
  final hasPartialState =
      result.partialSuccess ||
      result.imageFailures.isNotEmpty ||
      hasSourceFailure;
  return hasPartialState ? l10n.scrapeSyncPartial : l10n.scrapeSyncCompleted;
}

ScrapeSourceId? _resultDetailsSource(WorksScrapeResult result) {
  if (result.detailsSource != null) {
    return result.detailsSource;
  }
  if (result.sourceResults.containsKey(ScrapeSourceId.minnanoAv) &&
      !result.worksSources.contains(ScrapeSourceId.minnanoAv)) {
    return ScrapeSourceId.minnanoAv;
  }
  if (result.sourceResults.containsKey(ScrapeSourceId.avbase) &&
      !result.worksSources.contains(ScrapeSourceId.avbase)) {
    return ScrapeSourceId.avbase;
  }
  return null;
}

List<ScrapeSourceId> _resultWorksSources(
  WorksScrapeResult result,
  ScrapeSourceId? detailsSource,
) {
  if (result.worksSources.isNotEmpty) {
    return result.worksSources;
  }
  return result.sourceResults.keys
      .where((source) => source != detailsSource)
      .toList(growable: false);
}

String _scrapeDetailsProgressStatus(
  AppLocalizations l10n,
  WorksScrapeProgress? value,
  ScrapeSourceId source,
  WorksScrapeSourceProgress? progress,
) {
  if (value == null ||
      value.phase.index < WorksScrapePhase.syncingActress.index) {
    return l10n.scrapeStatusWaiting;
  }
  if (value.phase == WorksScrapePhase.syncingActress &&
      (value.source == source ||
          progress?.phase == WorksScrapePhase.syncingActress)) {
    return l10n.scrapeStatusSyncing;
  }
  if (value.phase.index > WorksScrapePhase.syncingActress.index) {
    return l10n.scrapeStatusCompleted;
  }
  return l10n.scrapeStatusWaiting;
}

String _scrapeWorkProgressStatus(
  AppLocalizations l10n,
  WorksScrapeProgress? value,
  WorksScrapeSourceProgress? progress,
  bool isActive,
) {
  if (value == null || progress == null) {
    return l10n.scrapeStatusWaiting;
  }
  if (value.phase == WorksScrapePhase.completed) {
    return l10n.scrapeStatusCompleted;
  }
  if (isActive) {
    return l10n.scrapeStatusSyncing;
  }
  if (value.phase.index > progress.phase.index) {
    return l10n.scrapeStatusCompleted;
  }
  return _scrapePhaseLabel(l10n, progress.phase);
}

String _scrapeSourceStateLabel(
  AppLocalizations l10n,
  ScrapeSourceRunState state, {
  bool isDetailsSource = false,
}) {
  return switch (state) {
    ScrapeSourceRunState.success => l10n.scrapeStatusCompleted,
    ScrapeSourceRunState.zeroResults =>
      isDetailsSource
          ? l10n.scrapeStatusCompleted
          : l10n.scrapeStatusNoNewWorks,
    ScrapeSourceRunState.partial => l10n.scrapeStatusPartial,
    ScrapeSourceRunState.unavailable => l10n.scrapeStatusUnavailable,
    ScrapeSourceRunState.failed => l10n.scrapeStatusFailed,
    ScrapeSourceRunState.cancelled => l10n.scrapeStatusCancelled,
    ScrapeSourceRunState.verificationRequired =>
      l10n.scrapeSourceVerificationRequired,
    ScrapeSourceRunState.blocked => l10n.scrapeStatusBlocked,
    ScrapeSourceRunState.rateLimited => l10n.scrapeStatusRateLimited,
    ScrapeSourceRunState.timedOut => l10n.scrapeStatusTimedOut,
  };
}

String _scrapePhaseLabel(AppLocalizations l10n, WorksScrapePhase phase) {
  return switch (phase) {
    WorksScrapePhase.collectingSources => l10n.scrapePhaseCollecting,
    WorksScrapePhase.syncingActress => l10n.scrapePhaseSyncingActress,
    WorksScrapePhase.fetchingDetails => l10n.scrapePhaseFetchingDetails,
    WorksScrapePhase.resolvingWorks => l10n.scrapePhaseResolvingWorks,
    WorksScrapePhase.savingWorks => l10n.scrapePhaseSavingWorks,
    WorksScrapePhase.downloadingImages => l10n.scrapePhaseSavingWorks,
    WorksScrapePhase.completed => l10n.scrapePhaseCompleted,
  };
}

String _scrapeSourceLabel(AppLocalizations l10n, ScrapeSourceId source) {
  return switch (source) {
    ScrapeSourceId.javbus => l10n.scrapeSourceJavBus,
    ScrapeSourceId.minnanoAv => l10n.scrapeSourceMinnanoAv,
    ScrapeSourceId.avbase => l10n.scrapeSourceAvBase,
    ScrapeSourceId.avwiki => l10n.scrapeSourceAvWiki,
  };
}

String _scrapeFailureReasonLabel(
  AppLocalizations l10n,
  WorksScrapeFailureReason reason,
) {
  return switch (reason) {
    WorksScrapeFailureReason.detailsUnavailable =>
      l10n.scrapeFailureDetailsUnavailable,
    WorksScrapeFailureReason.detailCodeMismatch =>
      l10n.scrapeFailureDetailCodeMismatch,
    WorksScrapeFailureReason.invalidCode => l10n.scrapeFailureInvalidCode,
    WorksScrapeFailureReason.databaseSaveFailed =>
      l10n.scrapeFailureDatabaseSave,
  };
}

String _scrapeImageFailureLabel(
  AppLocalizations l10n,
  List<WorkImageVariant> variants,
) {
  final hasCard = variants.contains(WorkImageVariant.card);
  final hasDetail = variants.contains(WorkImageVariant.detail);
  if (hasCard && hasDetail) {
    return l10n.scrapeImageFailureBoth;
  }
  if (hasCard) {
    return l10n.scrapeImageFailureCard;
  }
  return l10n.scrapeImageFailureDetail;
}
