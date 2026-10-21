import 'dart:io';

import 'package:flutter/material.dart';

import '../components/aligned_app_bar_back_button.dart';
import '../components/app_snackbar.dart';
import '../components/adaptive_page_layout.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../l10n/app_localizations.dart';
import '../models/work_storage.dart';

class WorkDetailView extends StatefulWidget {
  const WorkDetailView({
    super.key,
    required this.db,
    required this.workId,
    this.currentActressId,
  });

  final AppDatabase db;
  final int workId;
  final int? currentActressId;

  @override
  State<WorkDetailView> createState() => _WorkDetailViewState();
}

class _WorkDetailViewState extends State<WorkDetailView> {
  late final Future<Map<String, Object?>?> workFuture;
  WorkStorageRecord? _storageRecord;

  @override
  void initState() {
    super.initState();
    workFuture = widget.db.getWorkById(
      widget.workId,
      currentActressId: widget.currentActressId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>?>(
      future: workFuture,
      builder: (context, snapshot) {
        final work = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            leading: Navigator.canPop(context)
                ? const AlignedAppBarBackButton()
                : null,
            title: Text(work?['code']?.toString() ?? ''),
            actions: [if (work != null) _buildStorageAction(work)],
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.waiting => const Center(
              child: CircularProgressIndicator(),
            ),
            _ when snapshot.hasError => Center(
              child: Text(AppLocalizations.of(context).loadFailedGeneric),
            ),
            _ when work == null => Center(
              child: Text(AppLocalizations.of(context).dataNotFound),
            ),
            _ => _buildContent(work),
          },
        );
      },
    );
  }

  Widget _buildStorageAction(Map<String, Object?> work) {
    final l10n = AppLocalizations.of(context);
    final record = _storageRecord ?? WorkStorageRecord.fromDatabase(work);
    final statusLabel = record.isStored
        ? record.compactLabel
        : l10n.workStorageNotSaved;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: record.isStored
            ? l10n.workStorageSaved
            : l10n.workStorageNotSaved,
        child: TextButton(
          key: const Key('work-storage-action'),
          onPressed: () => _editWorkStorage(record),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                record.isStored ? Icons.bookmark : Icons.bookmark_border,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editWorkStorage(WorkStorageRecord initial) async {
    final updated = await showDialog<WorkStorageRecord>(
      context: context,
      builder: (context) => _WorkStorageDialog(initial: initial),
    );
    if (updated == null || !mounted) {
      return;
    }

    try {
      await widget.db.updateWorkStorage(workId: widget.workId, record: updated);
      if (!mounted) {
        return;
      }
      setState(() => _storageRecord = updated);
      AppSnackBar.showSuccess(
        context,
        AppLocalizations.of(context).workStorageUpdated,
      );
    } catch (_) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context).workStorageUpdateFailed,
        );
      }
    }
  }

  Widget _buildContent(Map<String, Object?> work) {
    return AdaptivePageLayout(
      padding: EdgeInsets.zero,
      compactBuilder: (context, tokens) => _buildCompactContent(work, tokens),
      expandedBuilder: (context, tokens) => _buildExpandedContent(work, tokens),
    );
  }

  Widget _buildCompactContent(
    Map<String, Object?> work,
    AppLayoutTokens tokens,
  ) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        tokens.pagePadding.left,
        tokens.pagePadding.top,
        tokens.pagePadding.right,
        tokens.pagePadding.bottom * 2,
      ),
      children: [
        _buildMedia(work['detail_image_path']?.toString() ?? ''),
        SizedBox(height: tokens.sectionGap),
        _buildMetadata(work, tokens),
      ],
    );
  }

  Widget _buildExpandedContent(
    Map<String, Object?> work,
    AppLayoutTokens tokens,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final splitRequired =
            360 +
            tokens.contentColumnGap +
            tokens.detailPaneMinWidth * textScale;
        if (constraints.maxWidth < splitRequired) {
          return _buildCompactContent(work, tokens);
        }

        final mediaWidth = (constraints.maxWidth * 0.45)
            .clamp(360.0, 520.0)
            .toDouble();
        return SingleChildScrollView(
          padding: EdgeInsets.all(tokens.pagePadding.left),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: mediaWidth,
                child: _buildMedia(work['detail_image_path']?.toString() ?? ''),
              ),
              SizedBox(width: tokens.contentColumnGap),
              Expanded(child: _buildMetadata(work, tokens)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMedia(String imagePath) {
    return ClipRRect(
      key: const Key('work-detail-image'),
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(aspectRatio: 1.48, child: _detailImage(imagePath)),
    );
  }

  Widget _buildMetadata(Map<String, Object?> work, AppLayoutTokens tokens) {
    final l10n = AppLocalizations.of(context);
    final title = work['title']?.toString() ?? '';
    final duration = work['duration_minutes'];
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.cardRadius + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: tokens.sectionGap / 2),
            _value(work['code']?.toString()),
            _value(work['release_date']?.toString()),
            if (duration is int) _value(l10n.durationMinutes(duration)),
            _labeledValue(l10n.studio, work['studio']?.toString()),
            _labeledValue(l10n.publisher, work['publisher']?.toString()),
            _labeledValue(l10n.series, work['series']?.toString()),
            _buildRelatedActresses(work),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedActresses(Map<String, Object?> work) {
    final raw = work['related_performers'];
    if (raw is! List) {
      return const SizedBox.shrink();
    }
    final performers = raw
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .where((performer) {
          final actressId = performer['actress_id'];
          return widget.currentActressId == null ||
              actressId != widget.currentActressId;
        })
        .toList(growable: false);
    if (performers.isEmpty ||
        (widget.currentActressId == null && performers.length < 2)) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('related-actresses-section'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.relatedActresses),
          const SizedBox(height: 2),
          Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              for (final performer in performers)
                _relatedActressButton(performer),
            ],
          ),
        ],
      ),
    );
  }

  Widget _relatedActressButton(Map<String, Object?> performer) {
    final name = performer['name']?.toString().trim() ?? '';
    final actressId = performer['actress_id'];
    if (name.isEmpty) {
      return const SizedBox.shrink();
    }
    if (actressId is int) {
      return TextButton(
        key: ValueKey('related-actress-$actressId'),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(name),
        onPressed: () => Navigator.of(context).pushNamed('/detail/$actressId'),
      );
    }
    return TextButton(
      key: ValueKey('related-actress-$name'),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: null,
      child: Text(name),
    );
  }

  Widget _detailImage(String path) {
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 48,
        ),
      ),
    );
  }

  Widget _value(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(value),
    );
  }

  Widget _labeledValue(String label, String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label：$value'),
    );
  }
}

class _WorkStorageDialog extends StatefulWidget {
  const _WorkStorageDialog({required this.initial});

  final WorkStorageRecord initial;

  @override
  State<_WorkStorageDialog> createState() => _WorkStorageDialogState();
}

class _WorkStorageDialogState extends State<_WorkStorageDialog> {
  late bool isStored;
  late String quality;
  late int frameRate;

  @override
  void initState() {
    super.initState();
    isStored = widget.initial.isStored;
    quality = widget.initial.quality;
    frameRate = widget.initial.frameRate;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('work-storage-dialog'),
      title: Text(l10n.workStorageTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              key: const Key('work-storage-saved-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.workStorageSaved),
              value: isStored,
              onChanged: (value) => setState(() => isStored = value),
            ),
            const SizedBox(height: 8),
            Text(l10n.workStorageQuality),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final value in WorkStorageRecord.qualities)
                  ChoiceChip(
                    key: Key('work-storage-quality-$value'),
                    label: Text(value),
                    selected: quality == value,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(vertical: -2),
                    onSelected: (_) => setState(() => quality = value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.workStorageFrameRate),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final value in WorkStorageRecord.frameRates)
                  ChoiceChip(
                    key: Key('work-storage-frame-rate-$value'),
                    label: Text('$value'),
                    selected: frameRate == value,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(vertical: -2),
                    onSelected: (_) => setState(() => frameRate = value),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('work-storage-save'),
          onPressed: () => Navigator.of(context).pop(
            WorkStorageRecord(
              isStored: isStored,
              quality: quality,
              frameRate: frameRate,
            ),
          ),
          child: Text(l10n.workStorageSave),
        ),
      ],
    );
  }
}
