import 'dart:convert';

import '../models/scrape_source_settings.dart';

enum ScrapeJobState {
  queued,
  running,
  paused,
  waitingForVerification,
  succeeded,
  partial,
  failed,
  cancelled,
}

enum ScrapeJobPhase {
  queued,
  collectingSources,
  syncingActress,
  fetchingDetails,
  resolvingWorks,
  savingWorks,
  downloadingImages,
  completed,
}

enum ScrapeJobItemState {
  queued,
  running,
  succeeded,
  review,
  excluded,
  failed,
  cancelled,
}

enum ScrapeJobEventSeverity { info, warning, error }

extension ScrapeJobStateCodec on ScrapeJobState {
  String get storageValue => switch (this) {
    ScrapeJobState.queued => 'queued',
    ScrapeJobState.running => 'running',
    ScrapeJobState.paused => 'paused',
    ScrapeJobState.waitingForVerification => 'waiting_for_verification',
    ScrapeJobState.succeeded => 'succeeded',
    ScrapeJobState.partial => 'partial',
    ScrapeJobState.failed => 'failed',
    ScrapeJobState.cancelled => 'cancelled',
  };

  static ScrapeJobState parse(Object? value) {
    return switch (value?.toString()) {
      'running' => ScrapeJobState.running,
      'paused' => ScrapeJobState.paused,
      'waiting_for_verification' => ScrapeJobState.waitingForVerification,
      'succeeded' => ScrapeJobState.succeeded,
      'partial' => ScrapeJobState.partial,
      'failed' => ScrapeJobState.failed,
      'cancelled' => ScrapeJobState.cancelled,
      _ => ScrapeJobState.queued,
    };
  }
}

extension ScrapeJobPhaseCodec on ScrapeJobPhase {
  String get storageValue => switch (this) {
    ScrapeJobPhase.queued => 'queued',
    ScrapeJobPhase.collectingSources => 'collecting_sources',
    ScrapeJobPhase.syncingActress => 'syncing_actress',
    ScrapeJobPhase.fetchingDetails => 'fetching_details',
    ScrapeJobPhase.resolvingWorks => 'resolving_works',
    ScrapeJobPhase.savingWorks => 'saving_works',
    ScrapeJobPhase.downloadingImages => 'downloading_images',
    ScrapeJobPhase.completed => 'completed',
  };

  static ScrapeJobPhase parse(Object? value) {
    return switch (value?.toString()) {
      'collecting_sources' => ScrapeJobPhase.collectingSources,
      'syncing_actress' => ScrapeJobPhase.syncingActress,
      'fetching_details' => ScrapeJobPhase.fetchingDetails,
      'resolving_works' => ScrapeJobPhase.resolvingWorks,
      'saving_works' => ScrapeJobPhase.savingWorks,
      'downloading_images' => ScrapeJobPhase.downloadingImages,
      'completed' => ScrapeJobPhase.completed,
      _ => ScrapeJobPhase.queued,
    };
  }
}

extension ScrapeJobItemStateCodec on ScrapeJobItemState {
  String get storageValue => switch (this) {
    ScrapeJobItemState.queued => 'queued',
    ScrapeJobItemState.running => 'running',
    ScrapeJobItemState.succeeded => 'succeeded',
    ScrapeJobItemState.review => 'review',
    ScrapeJobItemState.excluded => 'excluded',
    ScrapeJobItemState.failed => 'failed',
    ScrapeJobItemState.cancelled => 'cancelled',
  };

  static ScrapeJobItemState parse(Object? value) {
    return switch (value?.toString()) {
      'running' => ScrapeJobItemState.running,
      'succeeded' => ScrapeJobItemState.succeeded,
      'review' => ScrapeJobItemState.review,
      'excluded' => ScrapeJobItemState.excluded,
      'failed' => ScrapeJobItemState.failed,
      'cancelled' => ScrapeJobItemState.cancelled,
      _ => ScrapeJobItemState.queued,
    };
  }
}

extension ScrapeJobEventSeverityCodec on ScrapeJobEventSeverity {
  String get storageValue => switch (this) {
    ScrapeJobEventSeverity.info => 'info',
    ScrapeJobEventSeverity.warning => 'warning',
    ScrapeJobEventSeverity.error => 'error',
  };

  static ScrapeJobEventSeverity parse(Object? value) {
    return switch (value?.toString()) {
      'warning' => ScrapeJobEventSeverity.warning,
      'error' => ScrapeJobEventSeverity.error,
      _ => ScrapeJobEventSeverity.info,
    };
  }
}

class ScrapeJob {
  const ScrapeJob({
    required this.id,
    required this.actressId,
    required this.actressNameSnapshot,
    required this.state,
    required this.phase,
    required this.optionsSnapshot,
    required this.sourceSettingsSnapshot,
    required this.rulesVersionSnapshot,
    required this.rulesSnapshot,
    this.discoveredCount = 0,
    this.rawDiscoveredCount = 0,
    this.duplicateCount = 0,
    this.detailCompletedCount = 0,
    this.detailTotalCount = 0,
    this.processedCount = 0,
    this.savedCount = 0,
    this.excludedCount = 0,
    this.failedCount = 0,
    this.reviewCount = 0,
    this.supplementalEvidenceCompletedCount = 0,
    this.supplementalEvidenceTotalCount = 0,
    this.imageFailureCount = 0,
    this.attemptCount = 0,
    this.retryTargetCodes = const [],
    this.createdAt,
    this.startedAt,
    this.updatedAt,
    this.finishedAt,
    this.lastError,
  });

  final String id;
  final int actressId;
  final String actressNameSnapshot;
  final ScrapeJobState state;
  final ScrapeJobPhase phase;
  final String optionsSnapshot;
  final String sourceSettingsSnapshot;
  final String rulesVersionSnapshot;
  final String rulesSnapshot;
  final int discoveredCount;
  final int rawDiscoveredCount;
  final int duplicateCount;
  final int detailCompletedCount;
  final int detailTotalCount;
  final int processedCount;
  final int savedCount;
  final int excludedCount;
  final int failedCount;
  final int reviewCount;
  final int supplementalEvidenceCompletedCount;
  final int supplementalEvidenceTotalCount;
  final int imageFailureCount;
  final int attemptCount;
  final List<String> retryTargetCodes;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;
  final String? lastError;

  bool get isActive => switch (state) {
    ScrapeJobState.queued ||
    ScrapeJobState.running ||
    ScrapeJobState.paused ||
    ScrapeJobState.waitingForVerification => true,
    _ => false,
  };

  Map<String, Object?> toRow() => {
    'id': id,
    'actress_id': actressId,
    'actress_name_snapshot': actressNameSnapshot,
    'state': state.storageValue,
    'phase': phase.storageValue,
    'options_snapshot': optionsSnapshot,
    'source_settings_snapshot': sourceSettingsSnapshot,
    'rules_version_snapshot': rulesVersionSnapshot,
    'rules_snapshot': rulesSnapshot,
    'retry_target_codes': jsonEncode(retryTargetCodes),
    'discovered_count': discoveredCount,
    'raw_discovered_count': rawDiscoveredCount,
    'duplicate_count': duplicateCount,
    'detail_completed_count': detailCompletedCount,
    'detail_total_count': detailTotalCount,
    'processed_count': processedCount,
    'saved_count': savedCount,
    'excluded_count': excludedCount,
    'failed_count': failedCount,
    'review_count': reviewCount,
    'supplemental_evidence_completed_count': supplementalEvidenceCompletedCount,
    'supplemental_evidence_total_count': supplementalEvidenceTotalCount,
    'image_failure_count': imageFailureCount,
    'attempt_count': attemptCount,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'started_at': startedAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'finished_at': finishedAt?.toUtc().toIso8601String(),
    'last_error': lastError,
  };

  factory ScrapeJob.fromRow(Map<String, Object?> row) {
    return ScrapeJob(
      id: row['id']?.toString() ?? '',
      actressId: _int(row['actress_id']),
      actressNameSnapshot: row['actress_name_snapshot']?.toString() ?? '',
      state: ScrapeJobStateCodec.parse(row['state']),
      phase: ScrapeJobPhaseCodec.parse(row['phase']),
      optionsSnapshot: row['options_snapshot']?.toString() ?? '{}',
      sourceSettingsSnapshot:
          row['source_settings_snapshot']?.toString() ?? '{}',
      rulesVersionSnapshot:
          row['rules_version_snapshot']?.toString() ?? 'builtin-1',
      rulesSnapshot: row['rules_snapshot']?.toString() ?? '{}',
      retryTargetCodes: _strings(row['retry_target_codes']),
      discoveredCount: _int(row['discovered_count']),
      rawDiscoveredCount: _int(row['raw_discovered_count']),
      duplicateCount: _int(row['duplicate_count']),
      detailCompletedCount: _int(row['detail_completed_count']),
      detailTotalCount: _int(row['detail_total_count']),
      processedCount: _int(row['processed_count']),
      savedCount: _int(row['saved_count']),
      excludedCount: _int(row['excluded_count']),
      failedCount: _int(row['failed_count']),
      reviewCount: _int(row['review_count']),
      supplementalEvidenceCompletedCount: _int(
        row['supplemental_evidence_completed_count'],
      ),
      supplementalEvidenceTotalCount: _int(
        row['supplemental_evidence_total_count'],
      ),
      imageFailureCount: _int(row['image_failure_count']),
      attemptCount: _int(row['attempt_count']),
      createdAt: _date(row['created_at']),
      startedAt: _date(row['started_at']),
      updatedAt: _date(row['updated_at']),
      finishedAt: _date(row['finished_at']),
      lastError: row['last_error']?.toString(),
    );
  }
}

class ScrapeJobItem {
  const ScrapeJobItem({
    required this.id,
    required this.jobId,
    required this.canonicalCode,
    required this.state,
    this.observedRawCode,
    this.stage,
    this.attemptCount = 0,
    this.lastError,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String jobId;
  final String canonicalCode;
  final ScrapeJobItemState state;
  final String? observedRawCode;
  final ScrapeJobPhase? stage;
  final int attemptCount;
  final String? lastError;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'job_id': jobId,
    'canonical_code': canonicalCode,
    'observed_raw_code': observedRawCode,
    'state': state.storageValue,
    'stage': stage?.storageValue,
    'attempt_count': attemptCount,
    'last_error': lastError,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  factory ScrapeJobItem.fromRow(Map<String, Object?> row) => ScrapeJobItem(
    id: row['id'] is num ? (row['id'] as num).toInt() : null,
    jobId: row['job_id']?.toString() ?? '',
    canonicalCode: row['canonical_code']?.toString() ?? '',
    observedRawCode: row['observed_raw_code']?.toString(),
    state: ScrapeJobItemStateCodec.parse(row['state']),
    stage: row['stage'] == null
        ? null
        : ScrapeJobPhaseCodec.parse(row['stage']),
    attemptCount: _int(row['attempt_count']),
    lastError: row['last_error']?.toString(),
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
  );
}

class ScrapeJobSourceProgress {
  const ScrapeJobSourceProgress({
    required this.jobId,
    required this.source,
    required this.phase,
    required this.current,
    required this.total,
    required this.totalKnown,
    this.workCode,
    this.discovered = 0,
    this.state,
    this.lastError,
    this.updatedAt,
  });

  final String jobId;
  final ScrapeSourceId source;
  final ScrapeJobPhase phase;
  final int current;
  final int total;
  final bool totalKnown;
  final String? workCode;
  final int discovered;
  final String? state;
  final String? lastError;
  final DateTime? updatedAt;

  Map<String, Object?> toRow() => {
    'job_id': jobId,
    'source': source.storageValue,
    'phase': phase.storageValue,
    'current_value': current,
    'total_value': total,
    'total_known': totalKnown ? 1 : 0,
    'work_code': workCode,
    'discovered_count': discovered,
    'state': state,
    'last_error': lastError,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  factory ScrapeJobSourceProgress.fromRow(Map<String, Object?> row) {
    final source = ScrapeSourceId.values.firstWhere(
      (item) => item.storageValue == row['source']?.toString(),
      orElse: () => ScrapeSourceId.javbus,
    );
    return ScrapeJobSourceProgress(
      jobId: row['job_id']?.toString() ?? '',
      source: source,
      phase: ScrapeJobPhaseCodec.parse(row['phase']),
      current: _int(row['current_value']),
      total: _int(row['total_value']),
      totalKnown: _int(row['total_known']) != 0,
      workCode: row['work_code']?.toString(),
      discovered: _int(row['discovered_count']),
      state: row['state']?.toString(),
      lastError: row['last_error']?.toString(),
      updatedAt: _date(row['updated_at']),
    );
  }
}

class ScrapeJobEvent {
  const ScrapeJobEvent({
    required this.id,
    required this.jobId,
    required this.createdAt,
    required this.severity,
    required this.stage,
    required this.message,
    this.itemId,
    this.canonicalCode,
    this.source,
    this.metadata = const {},
  });

  final int? id;
  final String jobId;
  final DateTime createdAt;
  final ScrapeJobEventSeverity severity;
  final ScrapeJobPhase stage;
  final String message;
  final int? itemId;
  final String? canonicalCode;
  final ScrapeSourceId? source;
  final Map<String, Object?> metadata;

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'job_id': jobId,
    'item_id': itemId,
    'canonical_code': canonicalCode,
    'source': source?.storageValue,
    'severity': severity.storageValue,
    'stage': stage.storageValue,
    'message': message,
    'metadata_json': jsonEncode(metadata),
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory ScrapeJobEvent.fromRow(Map<String, Object?> row) {
    final source = ScrapeSourceId.values.where(
      (item) => item.storageValue == row['source']?.toString(),
    );
    return ScrapeJobEvent(
      id: row['id'] is num ? (row['id'] as num).toInt() : null,
      jobId: row['job_id']?.toString() ?? '',
      itemId: row['item_id'] is num ? (row['item_id'] as num).toInt() : null,
      canonicalCode: row['canonical_code']?.toString(),
      source: source.isEmpty ? null : source.first,
      severity: ScrapeJobEventSeverityCodec.parse(row['severity']),
      stage: ScrapeJobPhaseCodec.parse(row['stage']),
      message: row['message']?.toString() ?? '',
      metadata: _map(row['metadata_json']),
      createdAt:
          _date(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class WorkFieldProvenance {
  const WorkFieldProvenance({
    required this.workId,
    required this.field,
    required this.source,
    this.sourceUri,
    this.observedAt,
    this.updatedAt,
  });

  final int workId;
  final String field;
  final String source;
  final Uri? sourceUri;
  final DateTime? observedAt;
  final DateTime? updatedAt;

  WorkFieldProvenance copyWith({int? workId}) => WorkFieldProvenance(
    workId: workId ?? this.workId,
    field: field,
    source: source,
    sourceUri: sourceUri,
    observedAt: observedAt,
    updatedAt: updatedAt,
  );

  Map<String, Object?> toRow() => {
    'work_id': workId,
    'field': field,
    'source': source,
    'source_uri': sourceUri?.toString(),
    'observed_at': observedAt?.toUtc().toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
  };

  factory WorkFieldProvenance.fromRow(Map<String, Object?> row) =>
      WorkFieldProvenance(
        workId: _int(row['work_id']),
        field: row['field']?.toString() ?? '',
        source: row['source']?.toString() ?? '',
        sourceUri: Uri.tryParse(row['source_uri']?.toString() ?? ''),
        observedAt: _date(row['observed_at']),
        updatedAt: _date(row['updated_at']),
      );

  Map<String, Object?> toTransferJson() => {
    'field': field,
    'source': source,
    if (sourceUri != null) 'sourceUri': sourceUri.toString(),
    if (observedAt != null) 'observedAt': observedAt!.toUtc().toIso8601String(),
  };
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

List<String> _strings(Object? value) {
  if (value is! String || value.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }
  } on FormatException {
    return const [];
  }
  return const [];
}

Map<String, Object?> _map(Object? value) {
  if (value is! String || value.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } on FormatException {
    return const {};
  }
  return const {};
}
