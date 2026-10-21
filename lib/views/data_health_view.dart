import 'package:flutter/material.dart';

import '../components/adaptive_page_layout.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../models/data_health.dart';
import '../services/data_health_service.dart';

class DataHealthView extends StatefulWidget {
  const DataHealthView({super.key, required this.db});

  final AppDatabase db;

  @override
  State<DataHealthView> createState() => _DataHealthViewState();
}

class _DataHealthViewState extends State<DataHealthView> {
  late final DataHealthService _service;
  late Future<DataHealthSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _service = DataHealthService(db: widget.db);
    _future = _service.load();
  }

  void _refresh() => setState(() => _future = _service.load());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AlignedAppBarBackButton(),
        title: Text(l10n.dataHealthTitle),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.dataHealthRefresh,
          ),
        ],
      ),
      body: AdaptivePageLayout(
        compactBuilder: (context, tokens) => _buildBody(context, tokens),
        expandedBuilder: (context, tokens) => _buildBody(context, tokens),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLayoutTokens tokens) {
    return FutureBuilder<DataHealthSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _loadError(context, tokens);
        }
        final health = snapshot.data;
        if (health == null) {
          return Center(
            child: Text(AppLocalizations.of(context).loadFailedGeneric),
          );
        }
        final l10n = AppLocalizations.of(context);
        return ListView(
          padding: EdgeInsets.only(bottom: tokens.sectionGap * 2),
          children: [
            Text(
              l10n.dataHealthSubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (health.warnings.isNotEmpty) ...[
              SizedBox(height: tokens.sectionGap),
              _warningCard(context, health.warnings),
            ],
            SizedBox(height: tokens.sectionGap),
            _metricGrid(context, tokens, [
              _Metric(l10n.dataHealthActresses, health.actressCount),
              _Metric(l10n.dataHealthWorks, health.workCount),
              _Metric(l10n.dataHealthStored, health.storedWorkCount),
              _Metric(l10n.dataHealthNotStored, health.notStoredWorkCount),
            ]),
            SizedBox(height: tokens.sectionGap),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  _healthTile(
                    l10n.dataHealthMetadataIssues,
                    health.metadataIssueCount,
                  ),
                  _healthTile(
                    l10n.dataHealthMissingImages,
                    health.missingCardImageCount +
                        health.missingDetailImageCount,
                  ),
                  _healthTile(
                    l10n.dataHealthMissingProvenance,
                    health.missingProvenanceCount,
                  ),
                  _healthTile(
                    l10n.dataHealthPendingDeletions,
                    health.pendingDeletionCount,
                  ),
                ],
              ),
            ),
            SizedBox(height: tokens.sectionGap),
            _mapSection(context, l10n.dataHealthJobStates, health.jobCounts),
            SizedBox(height: tokens.sectionGap),
            _mapSection(
              context,
              l10n.dataHealthSourceErrors,
              health.sourceErrorCounts,
            ),
          ],
        );
      },
    );
  }

  Widget _loadError(BuildContext context, AppLayoutTokens tokens) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Card(
        margin: EdgeInsets.all(tokens.sectionGap),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.loadFailedGeneric),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.dataHealthRefresh),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _warningCard(BuildContext context, List<String> warnings) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined, color: colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                warnings
                    .map(
                      (warning) => l10n.dataHealthSectionUnavailable(
                        _warningLabel(context, warning),
                      ),
                    )
                    .join('\n'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _warningLabel(BuildContext context, String warning) {
    final l10n = AppLocalizations.of(context);
    return switch (warning) {
      'actresses' => l10n.dataHealthActresses,
      'works' => l10n.dataHealthWorks,
      'storedWorks' => l10n.dataHealthStored,
      'pendingDeletions' => l10n.dataHealthPendingDeletions,
      'metadata' => l10n.dataHealthMetadataIssues,
      'images' => l10n.dataHealthMissingImages,
      'provenance' => l10n.dataHealthMissingProvenance,
      'jobStates' => l10n.dataHealthJobStates,
      'sourceErrors' => l10n.dataHealthSourceErrors,
      _ => warning,
    };
  }

  Widget _metricGrid(
    BuildContext context,
    AppLayoutTokens tokens,
    List<_Metric> metrics,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: tokens.gridGap,
          mainAxisSpacing: tokens.gridGap,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          children: metrics
              .map(
                (metric) => Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(metric.label),
                        const SizedBox(height: 4),
                        Text(
                          '${metric.value}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _healthTile(String label, int value) =>
      ListTile(dense: true, title: Text(label), trailing: Text('$value'));

  Widget _mapSection(
    BuildContext context,
    String title,
    Map<String, int> values,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: Text(title),
        children: values.isEmpty
            ? [const ListTile(title: Text('—'))]
            : values.entries
                  .map(
                    (entry) => ListTile(
                      dense: true,
                      title: Text(entry.key),
                      trailing: Text('${entry.value}'),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final int value;
}
