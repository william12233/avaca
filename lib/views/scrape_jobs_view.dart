import 'dart:async';

import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../models/scrape_job.dart';
import '../services/scrape_job_coordinator.dart';
import 'scrape_job_detail_view.dart';

class ScrapeJobsView extends StatefulWidget {
  const ScrapeJobsView({
    super.key,
    required this.db,
    required this.coordinator,
  });

  final AppDatabase db;
  final ScrapeJobCoordinator coordinator;

  @override
  State<ScrapeJobsView> createState() => _ScrapeJobsViewState();
}

class _ScrapeJobsViewState extends State<ScrapeJobsView> {
  List<ScrapeJob> _jobs = const <ScrapeJob>[];
  final Set<String> _selectedJobIds = <String>{};
  Object? _loadError;
  bool _loading = true;
  bool _deleting = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _loadGeneration++;
    widget.coordinator.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    if (_jobs.isEmpty && !_loading) {
      setState(() => _loading = true);
    }
    unawaited(_loadLatest(generation));
  }

  Future<void> _loadLatest(int generation) async {
    try {
      final jobs = await widget.coordinator.listJobs();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _jobs = jobs;
        _selectedJobIds.retainAll(jobs.map((job) => job.id));
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selecting = _selectedJobIds.isNotEmpty;
    return PopScope(
      canPop: !selecting && !_deleting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selecting && !_deleting) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: AlignedAppBarBackButton(
            enabled: !_deleting,
            onPressed: selecting ? _clearSelection : null,
          ),
          title: Text(
            selecting
                ? l10n.scrapeJobsSelectedCount(_selectedJobIds.length)
                : l10n.scrapeJobsTitle,
          ),
          actions: [
            if (selecting)
              IconButton(
                key: const ValueKey('scrape-jobs-delete-selected'),
                tooltip: l10n.scrapeJobsDelete,
                onPressed: _deleting ? null : _deleteSelected,
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: AdaptivePageLayout(
          compactBuilder: (context, tokens) => _buildBody(context, tokens),
          expandedBuilder: (context, tokens) => _buildBody(context, tokens),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLayoutTokens tokens) {
    if (_loading && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_jobs.isEmpty) {
      if (_loadError != null) {
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
      return Center(child: Text(AppLocalizations.of(context).scrapeJobsEmpty));
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: tokens.sectionGap * 2),
      itemCount: _jobs.length,
      separatorBuilder: (_, _) => SizedBox(height: tokens.sectionGap),
      itemBuilder: (context, index) {
        final job = _jobs[index];
        final l10n = AppLocalizations.of(context);
        final selected = _selectedJobIds.contains(job.id);
        final colorScheme = Theme.of(context).colorScheme;
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: selected
                ? BorderSide(color: colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: ListTile(
            leading: _stateIcon(job.state),
            title: Text(job.actressNameSnapshot),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_stateLabel(context, job.state)} · '
                  '${_progressLabel(l10n, job)}',
                ),
                if (job.lastError != null)
                  Text(
                    job.lastError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            trailing: _selectedJobIds.isNotEmpty
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleSelection(job.id),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () {
              if (_selectedJobIds.isNotEmpty) {
                _toggleSelection(job.id);
                return;
              }
              unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ScrapeJobDetailView(
                      db: widget.db,
                      coordinator: widget.coordinator,
                      jobId: job.id,
                    ),
                  ),
                ),
              );
            },
            onLongPress: () => _toggleSelection(job.id),
          ),
        );
      },
    );
  }

  void _toggleSelection(String jobId) {
    if (_deleting) return;
    setState(() {
      if (!_selectedJobIds.add(jobId)) {
        _selectedJobIds.remove(jobId);
      }
    });
  }

  void _clearSelection() {
    if (_deleting || _selectedJobIds.isEmpty) return;
    setState(_selectedJobIds.clear);
  }

  Future<void> _deleteSelected() async {
    final selectedIds = _selectedJobIds.toList(growable: false);
    if (selectedIds.isEmpty) {
      return;
    }
    final selectedJobs = _jobs
        .where((job) => _selectedJobIds.contains(job.id))
        .toList(growable: false);
    if (selectedJobs.any((job) => job.isActive)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).scrapeJobsDeleteActive),
          ),
        );
      return;
    }

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.scrapeJobsDeleteTitle),
        content: Text(l10n.scrapeJobsDeleteMessage(selectedIds.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.scrapeJobsDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _deleting = true);
    try {
      await widget.coordinator.deleteJobs(selectedIds);
      if (!mounted) return;
      setState(() {
        _selectedJobIds.clear();
        _deleting = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.scrapeJobsDeleted(selectedIds.length))),
        );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${l10n.scrapeJobsDeleteFailed}: $error')),
        );
    }
  }

  Icon _stateIcon(ScrapeJobState state) {
    return Icon(switch (state) {
      ScrapeJobState.succeeded => Icons.check_circle_outline,
      ScrapeJobState.partial => Icons.warning_amber_outlined,
      ScrapeJobState.failed => Icons.error_outline,
      ScrapeJobState.cancelled => Icons.cancel_outlined,
      ScrapeJobState.paused => Icons.pause_circle_outline,
      ScrapeJobState.waitingForVerification => Icons.verified_user_outlined,
      _ => Icons.sync_outlined,
    });
  }

  String _progressLabel(AppLocalizations l10n, ScrapeJob job) {
    final collection = l10n.scrapeJobCandidateSummary(
      job.discoveredCount,
      job.duplicateCount,
    );
    final supplemental = job.supplementalEvidenceTotalCount > 0
        ? l10n.scrapeJobSupplementalEvidence(
            job.supplementalEvidenceCompletedCount,
            job.supplementalEvidenceTotalCount,
          )
        : null;
    return switch (job.phase) {
      ScrapeJobPhase.collectingSources => collection,
      ScrapeJobPhase.fetchingDetails || ScrapeJobPhase.resolvingWorks =>
        '$collection · ${l10n.scrapeJobDetailProgress(job.detailCompletedCount, job.detailTotalCount)}'
            '${supplemental == null ? '' : ' · $supplemental'}',
      _ => l10n.scrapeJobOutcomeSummary(
        job.processedCount,
        job.discoveredCount,
        job.savedCount - job.reviewCount < 0
            ? 0
            : job.savedCount - job.reviewCount,
        job.reviewCount,
        job.excludedCount,
        job.failedCount,
      ),
    };
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
}
