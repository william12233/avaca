import 'dart:async';

import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../components/javbus_verification_dialog.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../models/scrape_job.dart';
import '../models/scrape_source_settings.dart';
import '../services/javbus/javbus_verification.dart';
import '../services/scrape_job_coordinator.dart';

enum _ScrapeJobItemFilter {
  all,
  review,
  keep,
  exclude,
  failed;

  bool matches(ScrapeJobItemState state) => switch (this) {
    _ScrapeJobItemFilter.all => true,
    _ScrapeJobItemFilter.review => state == ScrapeJobItemState.review,
    _ScrapeJobItemFilter.keep => state == ScrapeJobItemState.succeeded,
    _ScrapeJobItemFilter.exclude => state == ScrapeJobItemState.excluded,
    _ScrapeJobItemFilter.failed => state == ScrapeJobItemState.failed,
  };
}

class ScrapeJobDetailView extends StatefulWidget {
  const ScrapeJobDetailView({
    super.key,
    required this.db,
    required this.coordinator,
    required this.jobId,
  });

  final AppDatabase db;
  final ScrapeJobCoordinator coordinator;
  final String jobId;

  @override
  State<ScrapeJobDetailView> createState() => _ScrapeJobDetailViewState();
}

class _ScrapeJobDetailViewState extends State<ScrapeJobDetailView> {
  _JobDetailData _detail = const _JobDetailData.empty();
  bool _loading = true;
  Object? _loadError;
  bool _actionBusy = false;
  _ScrapeJobItemFilter _itemFilter = _ScrapeJobItemFilter.all;
  int _loadGeneration = 0;
  late final ScrollController _itemsScrollController;
  late final JavBusVerificationHandler? _previousVerificationHandler;
  late final JavBusVerificationHandler _installedVerificationHandler;

  @override
  void initState() {
    super.initState();
    _itemsScrollController = ScrollController();
    widget.coordinator.addListener(_handleChanged);
    _previousVerificationHandler = widget.coordinator.verificationHandler;
    _installedVerificationHandler = _showVerification;
    widget.coordinator.verificationHandler = _installedVerificationHandler;
    _reload();
  }

  @override
  void dispose() {
    _loadGeneration++;
    widget.coordinator.removeListener(_handleChanged);
    if (identical(
      widget.coordinator.verificationHandler,
      _installedVerificationHandler,
    )) {
      widget.coordinator.verificationHandler = _previousVerificationHandler;
    }
    _itemsScrollController.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    unawaited(_loadLatest(generation));
  }

  Future<void> _loadLatest(int generation) async {
    try {
      final detail = await _load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<_JobDetailData> _load() async {
    final job = await widget.coordinator.repository.get(widget.jobId);
    if (job == null) return const _JobDetailData.empty();
    return _JobDetailData(
      job: job,
      items: await widget.coordinator.repository.listItems(widget.jobId),
      events: await widget.coordinator.repository.listEvents(widget.jobId),
      sourceProgress: await widget.coordinator.repository.listSourceProgress(
        widget.jobId,
      ),
    );
  }

  Future<Map<String, String>?> _showVerification(
    JavBusVerificationChallenge challenge,
  ) {
    if (!mounted) return Future.value(null);
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => JavBusVerificationDialog(challenge: challenge),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AlignedAppBarBackButton(),
        title: Text(AppLocalizations.of(context).scrapeJobDetailTitle),
      ),
      body: AdaptivePageLayout(
        compactBuilder: (context, tokens) => _buildBody(context, tokens),
        expandedBuilder: (context, tokens) => _buildBody(context, tokens),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLayoutTokens tokens) {
    if (_loading && _detail.job == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _detail.job == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).reload),
            ),
          ],
        ),
      );
    }
    final detail = _detail;
    final job = detail.job;
    if (job == null) {
      return Center(child: Text(AppLocalizations.of(context).dataNotFound));
    }
    return ListView(
      padding: EdgeInsets.only(bottom: tokens.sectionGap * 2),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.actressNameSnapshot,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(_stateLabel(context, job.state)),
                const SizedBox(height: 4),
                Text(_progressSummary(context, job)),
                if (detail.sourceProgress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final progress in detail.sourceProgress)
                    Text(_sourceProgressLabel(context, progress)),
                ],
                if (job.lastError != null) ...[
                  const SizedBox(height: 12),
                  _buildDiagnostic(context, job.lastError!),
                ],
                const SizedBox(height: 16),
                _buildActions(context, job),
              ],
            ),
          ),
        ),
        SizedBox(height: tokens.sectionGap),
        _buildSection(
          context,
          AppLocalizations.of(context).scrapeJobItems,
          _buildItemsPanel(context, detail.items),
        ),
        SizedBox(height: tokens.sectionGap),
        _buildSection(
          context,
          AppLocalizations.of(context).scrapeJobEvents,
          detail.events.isEmpty
              ? Text(AppLocalizations.of(context).scrapeJobNoEvents)
              : Column(
                  children: detail.events
                      .map((event) => _eventTile(context, event))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildDiagnostic(BuildContext context, String diagnostic) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      key: const Key('scrape-job-diagnostic'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).scrapeJobDiagnostics,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(diagnostic, maxLines: 8, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsPanel(BuildContext context, List<ScrapeJobItem> items) {
    if (items.isEmpty) {
      return Text(AppLocalizations.of(context).scrapeJobNoItems);
    }

    final filteredItems = items
        .where((item) => _itemFilter.matches(item.state))
        .toList(growable: false);
    final l10n = AppLocalizations.of(context);
    final filterLabels = <_ScrapeJobItemFilter, String>{
      _ScrapeJobItemFilter.all: l10n.scrapeJobFilterAll,
      _ScrapeJobItemFilter.review: l10n.scrapeJobFilterReview,
      _ScrapeJobItemFilter.keep: l10n.scrapeJobFilterKeep,
      _ScrapeJobItemFilter.exclude: l10n.scrapeJobFilterExclude,
      _ScrapeJobItemFilter.failed: l10n.scrapeJobFilterFailed,
    };
    final filters = SingleChildScrollView(
      key: const Key('scrape-job-item-filters'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in filterLabels.entries) ...[
            ChoiceChip(
              key: ValueKey('scrape-job-item-filter-${entry.key.name}'),
              label: Text(entry.value),
              selected: _itemFilter == entry.key,
              onSelected: (_) => setState(() => _itemFilter = entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
    if (filteredItems.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          filters,
          const SizedBox(height: 8),
          Text(l10n.scrapeJobNoFilteredItems),
        ],
      );
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = (screenHeight * 0.42).clamp(180.0, 480.0).toDouble();
    final estimatedContentHeight = (filteredItems.length * 56.0 + 8)
        .clamp(56.0, maxHeight)
        .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        filters,
        const SizedBox(height: 8),
        SizedBox(
          key: const Key('scrape-job-items-viewport'),
          height: estimatedContentHeight,
          child: Scrollbar(
            controller: _itemsScrollController,
            thumbVisibility: filteredItems.length > 2,
            child: ListView.separated(
              key: const Key('scrape-job-items-list'),
              controller: _itemsScrollController,
              primary: false,
              shrinkWrap: false,
              padding: const EdgeInsets.only(right: 8),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) =>
                  _itemTile(context, filteredItems[index]),
              separatorBuilder: (_, _) => const Divider(height: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, ScrapeJob job) {
    final canPause =
        job.state == ScrapeJobState.running ||
        job.state == ScrapeJobState.queued;
    final canResume =
        job.state == ScrapeJobState.paused ||
        job.state == ScrapeJobState.waitingForVerification;
    final canCancel = job.isActive;
    final canRetry =
        job.state == ScrapeJobState.failed ||
        job.state == ScrapeJobState.partial;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canPause)
          OutlinedButton.icon(
            onPressed: _actionBusy
                ? null
                : () => _runAction(() => widget.coordinator.pause(job.id)),
            icon: const Icon(Icons.pause),
            label: Text(AppLocalizations.of(context).scrapeJobPause),
          ),
        if (canResume)
          FilledButton.icon(
            onPressed: _actionBusy
                ? null
                : () => _runAction(() => widget.coordinator.resume(job.id)),
            icon: const Icon(Icons.play_arrow),
            label: Text(AppLocalizations.of(context).scrapeJobResume),
          ),
        if (canCancel)
          TextButton.icon(
            onPressed: _actionBusy
                ? null
                : () => _runAction(() => widget.coordinator.cancel(job.id)),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(AppLocalizations.of(context).scrapeJobCancel),
          ),
        if (canRetry)
          OutlinedButton.icon(
            onPressed: _actionBusy
                ? null
                : () =>
                      _runAction(() => widget.coordinator.retryFailed(job.id)),
            icon: const Icon(Icons.replay),
            label: Text(AppLocalizations.of(context).scrapeJobRetryFailed),
          ),
      ],
    );
  }

  String _progressSummary(BuildContext context, ScrapeJob job) {
    final l10n = AppLocalizations.of(context);
    final collection = l10n.scrapeJobCandidateSummary(
      job.discoveredCount,
      job.duplicateCount,
    );
    final details = l10n.scrapeJobDetailProgress(
      job.detailCompletedCount,
      job.detailTotalCount,
    );
    final supplemental = job.supplementalEvidenceTotalCount > 0
        ? l10n.scrapeJobSupplementalEvidence(
            job.supplementalEvidenceCompletedCount,
            job.supplementalEvidenceTotalCount,
          )
        : null;
    final terminal = l10n.scrapeJobOutcomeSummary(
      job.processedCount,
      job.discoveredCount,
      job.savedCount - job.reviewCount < 0
          ? 0
          : job.savedCount - job.reviewCount,
      job.reviewCount,
      job.excludedCount,
      job.failedCount,
    );
    return switch (job.phase) {
      ScrapeJobPhase.collectingSources => collection,
      ScrapeJobPhase.fetchingDetails || ScrapeJobPhase.resolvingWorks =>
        '$collection\n$details${supplemental == null ? '' : '\n$supplemental'}',
      _ =>
        '$collection\n$details${supplemental == null ? '' : '\n$supplemental'}\n$terminal',
    };
  }

  String _sourceProgressLabel(
    BuildContext context,
    ScrapeJobSourceProgress progress,
  ) {
    final l10n = AppLocalizations.of(context);
    final source = switch (progress.source) {
      ScrapeSourceId.javbus => l10n.scrapeSourceJavBus,
      ScrapeSourceId.avbase => l10n.scrapeSourceAvBase,
      ScrapeSourceId.minnanoAv => l10n.scrapeSourceMinnanoAv,
      ScrapeSourceId.avwiki => l10n.scrapeSourceAvWiki,
    };
    final pages = progress.totalKnown
        ? '${progress.current}/${progress.total}'
        : '${progress.current}';
    return '$source · $pages · ${progress.discovered}';
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Widget _buildSection(BuildContext context, String title, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _itemTile(BuildContext context, ScrapeJobItem item) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (item.state) {
        ScrapeJobItemState.succeeded => Icons.check,
        ScrapeJobItemState.review => Icons.rate_review_outlined,
        ScrapeJobItemState.failed => Icons.error_outline,
        ScrapeJobItemState.excluded => Icons.remove_circle_outline,
        _ => Icons.sync,
      }),
      title: Text(item.canonicalCode),
      subtitle: item.lastError == null
          ? null
          : Text(item.lastError!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(_itemStateLabel(context, item.state)),
    );
  }

  Widget _eventTile(BuildContext context, ScrapeJobEvent event) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        event.severity == ScrapeJobEventSeverity.error
            ? Icons.error_outline
            : Icons.info_outline,
      ),
      title: Text(event.message),
      subtitle: Text(
        '${_phaseLabel(context, event.stage)} · ${event.createdAt.toLocal()}',
      ),
    );
  }

  String _stateLabel(BuildContext context, ScrapeJobState state) {
    final l10n = AppLocalizations.of(context);
    return switch (state) {
      ScrapeJobState.queued => l10n.scrapeJobStateQueued,
      ScrapeJobState.running => l10n.scrapeJobStateRunning,
      ScrapeJobState.paused => l10n.scrapeJobStatePaused,
      ScrapeJobState.waitingForVerification => l10n.scrapeJobStateWaiting,
      ScrapeJobState.succeeded => l10n.scrapeJobStateSucceeded,
      ScrapeJobState.partial => l10n.scrapeJobStatePartial,
      ScrapeJobState.failed => l10n.scrapeJobStateFailed,
      ScrapeJobState.cancelled => l10n.scrapeJobStateCancelled,
    };
  }

  String _itemStateLabel(BuildContext context, ScrapeJobItemState state) {
    final l10n = AppLocalizations.of(context);
    return switch (state) {
      ScrapeJobItemState.queued => l10n.scrapeJobStateQueued,
      ScrapeJobItemState.running => l10n.scrapeJobStateRunning,
      ScrapeJobItemState.succeeded => l10n.scrapeJobStateSucceeded,
      ScrapeJobItemState.review => l10n.scrapeJobStateReview,
      ScrapeJobItemState.excluded => l10n.scrapeJobStateExcluded,
      ScrapeJobItemState.failed => l10n.scrapeJobStateFailed,
      ScrapeJobItemState.cancelled => l10n.scrapeJobStateCancelled,
    };
  }

  String _phaseLabel(BuildContext context, ScrapeJobPhase phase) {
    final l10n = AppLocalizations.of(context);
    return switch (phase) {
      ScrapeJobPhase.queued => l10n.scrapeJobStateQueued,
      ScrapeJobPhase.collectingSources => l10n.scrapePhaseCollecting,
      ScrapeJobPhase.syncingActress => l10n.scrapePhaseSyncingActress,
      ScrapeJobPhase.fetchingDetails => l10n.scrapePhaseFetchingDetails,
      ScrapeJobPhase.resolvingWorks => l10n.scrapePhaseResolvingWorks,
      ScrapeJobPhase.savingWorks ||
      ScrapeJobPhase.downloadingImages => l10n.scrapePhaseSavingWorks,
      ScrapeJobPhase.completed => l10n.scrapePhaseCompleted,
    };
  }
}

class _JobDetailData {
  const _JobDetailData({
    required this.job,
    required this.items,
    required this.events,
    required this.sourceProgress,
  });
  const _JobDetailData.empty()
    : job = null,
      items = const [],
      events = const [],
      sourceProgress = const [];

  final ScrapeJob? job;
  final List<ScrapeJobItem> items;
  final List<ScrapeJobEvent> events;
  final List<ScrapeJobSourceProgress> sourceProgress;
}
