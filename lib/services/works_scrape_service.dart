import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../core/database.dart';
import '../models/scrape_source_settings.dart';
import '../models/scraped_actress_details.dart';
import '../models/work.dart';
import '../models/work_scrape_options.dart';
import 'avbase/avbase_models.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_scrape_source.dart';
import 'javbus/prefix_exclusion.dart';
import 'javbus/javbus_verification.dart';
import 'javbus/prefix_route_repository.dart';
import 'javbus/work_image_downloader.dart';
import 'javbus/work_image_policy.dart';
import 'safe_image.dart';
import 'scrape/scrape_image_downloader.dart';
import 'scrape/scrape_models.dart';
import 'scrape/scrape_source.dart';
import 'scrape/scrape_source_registry.dart';
import 'scrape/work_identity.dart';

abstract interface class ActressImageDownloader {
  Future<String> download(Uri uri, String targetPath);
}

class HttpActressImageDownloader implements ActressImageDownloader {
  HttpActressImageDownloader({
    BinaryTransport? transport,
    JavBusBinarySession? authenticatedTransport,
  }) : assert(transport == null || authenticatedTransport == null),
       _authenticatedTransport = authenticatedTransport,
       _transport = authenticatedTransport == null
           ? transport ??
                 HttpBinaryTransport(
                   allowedHosts: const {'www.javbus.com'},
                   maxBytes: 5 * 1024 * 1024,
                 )
           : null;

  final BinaryTransport? _transport;
  final JavBusBinarySession? _authenticatedTransport;

  @override
  Future<String> download(Uri uri, String targetPath) async {
    final response =
        await (_authenticatedTransport?.getBinary(uri) ?? _transport!.get(uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorksScrapeException('Actress image request failed: $uri');
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    if (!isSafeDecodableImage(bytes)) {
      throw WorksScrapeException('Actress image is invalid: $uri');
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void close() {
    final transport = _transport;
    if (transport is HttpBinaryTransport) {
      transport.close();
    }
  }
}

enum ActressImageSyncStatus {
  notRequested,
  replaced,
  unavailable,
  downloadFailed,
  databaseFailed,
}

class WorksScrapeCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

enum WorksScrapePhase {
  collectingSources,
  syncingActress,
  fetchingDetails,
  resolvingWorks,
  savingWorks,
  downloadingImages,
  completed,
}

enum WorksScrapeFailureStage { fetchingDetails, resolvingWorks, savingWorks }

enum WorksScrapeFailureReason {
  detailsUnavailable,
  detailCodeMismatch,
  invalidCode,
  performerCountUnavailable,
  databaseSaveFailed,
}

final class WorksScrapeFailure {
  const WorksScrapeFailure({
    required this.code,
    required this.stage,
    required this.reason,
    this.source,
    this.error,
  });

  final String code;
  final WorksScrapeFailureStage stage;
  final WorksScrapeFailureReason reason;
  final ScrapeSourceId? source;
  final Object? error;
}

final class WorksScrapeImageFailure {
  const WorksScrapeImageFailure({required this.code, required this.variants});

  final String code;
  final List<WorkImageVariant> variants;
}

final class WorksScrapeSourceProgress {
  const WorksScrapeSourceProgress({
    required this.phase,
    required this.current,
    required this.total,
    this.totalKnown = false,
    this.workCode,
  });

  final WorksScrapePhase phase;
  final int current;
  final int total;
  final bool totalKnown;
  final String? workCode;

  bool get hasKnownTotal => totalKnown;
}

class WorksScrapeProgress {
  const WorksScrapeProgress({
    required this.current,
    required this.total,
    required this.saved,
    required this.excluded,
    required this.failed,
    this.totalKnown = false,
    this.phase = WorksScrapePhase.savingWorks,
    this.source,
    this.workCode,
    this.sourceProgress = const {},
    this.detailsSource,
    this.worksSources = const [],
  });

  final WorksScrapePhase phase;
  final int current;
  final int total;
  final int saved;
  final int excluded;
  final int failed;
  final bool totalKnown;
  final ScrapeSourceId? source;
  final String? workCode;
  final Map<ScrapeSourceId, WorksScrapeSourceProgress> sourceProgress;

  bool get hasKnownTotal => totalKnown;

  /// The source currently responsible for actress profile synchronization.
  ///
  /// This is presentation metadata. It keeps a details-only source from being
  /// rendered as a work source when the same source run result has no works.
  final ScrapeSourceId? detailsSource;

  /// Sources that participate in the aggregate work pipeline.
  ///
  /// The list is intentionally source-oriented so adding another works source
  /// only adds another row to the dialog.
  final List<ScrapeSourceId> worksSources;
}

class WorksScrapeResult {
  const WorksScrapeResult({
    required this.saved,
    required this.excluded,
    required this.failed,
    required this.cancelled,
    this.actressImageStatus = ActressImageSyncStatus.notRequested,
    this.partialSuccess = false,
    this.sourceResults = const {},
    this.failedWorks = const [],
    this.imageFailures = const [],
    this.detailsSource,
    this.worksSources = const [],
  });

  final int saved;
  final int excluded;
  final int failed;
  final bool cancelled;
  final ActressImageSyncStatus actressImageStatus;
  final bool partialSuccess;
  final Map<ScrapeSourceId, ScrapeSourceRunResult> sourceResults;
  final List<WorksScrapeFailure> failedWorks;
  final List<WorksScrapeImageFailure> imageFailures;

  /// The source that supplied actress details, separate from work sources.
  final ScrapeSourceId? detailsSource;

  /// Work sources whose results were merged into the aggregate counters.
  final List<ScrapeSourceId> worksSources;
}

class WorksScrapeException implements Exception {
  const WorksScrapeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WorksScrapeService {
  WorksScrapeService({
    required this.db,
    JavBusClient? client,
    Map<ScrapeSourceId, ScrapeSource>? sources,
    WorkImageDownloader? workImageDownloader,
    ActressImageDownloader? actressImageDownloader,
    this.imageUriDownloader,
    String? imageDirectory,
    this.javBusDetailDelay = const Duration(milliseconds: 600),
    this.imageDownloadConcurrency = 2,
  }) : client = client,
       sources = sources ?? _legacySources(client),
       workImageDownloader =
           workImageDownloader ??
           WorkImageDownloader(
             routeRepository: PrefixRouteRepository.forDatabase(db),
           ),
       actressImageDownloader =
           actressImageDownloader ?? HttpActressImageDownloader(),
       imageDirectory = imageDirectory ?? path.join(db.imgDir, 'scraped'),
       assert(imageDownloadConcurrency > 0);

  final AppDatabase db;
  final JavBusClient? client;
  final Map<ScrapeSourceId, ScrapeSource> sources;
  final WorkImageDownloader workImageDownloader;
  final ActressImageDownloader actressImageDownloader;
  final ScrapeImageUriDownloader? imageUriDownloader;
  final String imageDirectory;
  final Duration javBusDetailDelay;
  final int imageDownloadConcurrency;
  final Map<ScrapeSourceId, WorksScrapeSourceProgress> _sourceProgress = {};
  ScrapeSourceId? _detailsSource;
  List<ScrapeSourceId> _worksSources = const [];

  static Map<ScrapeSourceId, ScrapeSource> _legacySources(
    JavBusClient? client,
  ) {
    if (client == null) {
      throw ArgumentError('Either client or sources must be supplied.');
    }
    return {ScrapeSourceId.javbus: JavBusScrapeSource(client)};
  }

  void close() {
    final closed = <ScrapeSource>{};
    for (final source in sources.values) {
      if (closed.add(source)) {
        source.close();
      }
    }
    workImageDownloader.close();
    final imageDownloader = imageUriDownloader;
    imageDownloader?.close();
    final downloader = actressImageDownloader;
    if (downloader is HttpActressImageDownloader) {
      downloader.close();
    }
  }

  Future<WorksScrapeResult> scrape({
    required int actressId,
    required String actressName,
    List<String> aliases = const [],
    required WorkScrapeOptions options,
    ScrapeSourceSettings? sourceSettings,
    WorksScrapeCancellationToken? cancellationToken,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) async {
    _sourceProgress.clear();
    _detailsSource = null;
    _worksSources = const [];
    final name = actressName.trim();
    if (name.isEmpty) {
      throw const WorksScrapeException('Actress name is empty.');
    }
    _notify(
      onProgress,
      0,
      0,
      0,
      0,
      0,
      phase: WorksScrapePhase.collectingSources,
    );
    final settings = sourceSettings ?? const ScrapeSourceSettings();
    final queries = _queries(name, aliases);
    final requestedWorkIds = ScrapeSourceRegistry.resolveWorksSources(
      settings.worksSource,
    );
    _detailsSource = settings.actressDetailsSource;
    _worksSources = List.unmodifiable(requestedWorkIds);
    final sourceResults = <ScrapeSourceId, ScrapeSourceRunResult>{};
    final collectedById = <ScrapeSourceId, _CollectedSource>{};
    final collectionFutures =
        <ScrapeSourceId, Future<_SourceCollectionOutcome>>{};
    final sourceIdsToCollect = <ScrapeSourceId>[
      ...requestedWorkIds,
      if (!requestedWorkIds.contains(settings.actressDetailsSource))
        settings.actressDetailsSource,
    ];

    // Start every source collection immediately.  Each works source then
    // chains its own detail queue from this future, so one site's details can
    // start while another site is still traversing its works pages.
    for (final sourceId in sourceIdsToCollect) {
      _notify(
        onProgress,
        0,
        0,
        0,
        0,
        0,
        phase: WorksScrapePhase.collectingSources,
        source: sourceId,
      );
      final source = sources[sourceId];
      collectionFutures[sourceId] = source == null
          ? Future.value(
              _SourceCollectionOutcome(
                result: ScrapeSourceRunResult(
                  source: sourceId,
                  state: ScrapeSourceRunState.unavailable,
                  error: 'Source is not configured.',
                ),
              ),
            )
          : _collectSourceSafely(
              source: source,
              queries: queries,
              cancellationToken: cancellationToken,
              includeWorks: requestedWorkIds.contains(sourceId),
            );
    }

    void recordCollectionOutcome(
      ScrapeSourceId sourceId,
      _SourceCollectionOutcome outcome,
    ) {
      final collected = outcome.collected;
      if (collected != null) {
        collectedById[sourceId] = collected;
      }
      if (requestedWorkIds.contains(sourceId) ||
          sourceId == settings.actressDetailsSource) {
        sourceResults[sourceId] = outcome.result;
      }
    }

    final exclusions = PrefixExclusion(options.excludedPrefixes);
    final streamImagesWhileFetching =
        requestedWorkIds.isNotEmpty &&
        requestedWorkIds.every((source) => source == ScrapeSourceId.javbus);
    final imageQueue = _BoundedAsyncQueue(
      maxConcurrent: imageDownloadConcurrency,
    );
    final sourcePipelines = <Future<_SourcePipelineOutcome>>[
      for (final sourceId in requestedWorkIds)
        _runSourcePipeline(
          sourceId: sourceId,
          source: sources[sourceId],
          collectionFuture: collectionFutures[sourceId]!,
          exclusions: exclusions,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
          streamImageSaves: streamImagesWhileFetching,
          actressId: actressId,
          options: options,
          imageQueue: imageQueue,
        ),
    ];

    // Actress metadata synchronization may await its own collection, but all
    // works source pipelines above are already running and are not blocked by
    // this optional profile sync.
    final detailsSourceId = settings.actressDetailsSource;
    final detailsSource = sources[detailsSourceId];
    final detailsCollectionFuture = collectionFutures[detailsSourceId];
    final detailsOutcome = detailsCollectionFuture == null
        ? null
        : await detailsCollectionFuture;
    if (detailsOutcome != null) {
      recordCollectionOutcome(detailsSourceId, detailsOutcome);
    }
    final detailsCollection = detailsOutcome?.collected;
    ActressImageSyncStatus actressImageStatus = options.replaceActressImage
        ? ActressImageSyncStatus.unavailable
        : ActressImageSyncStatus.notRequested;
    if (detailsSource != null &&
        detailsCollection != null &&
        detailsCollection.pages.isNotEmpty) {
      _notify(
        onProgress,
        0,
        0,
        0,
        0,
        0,
        phase: WorksScrapePhase.syncingActress,
        source: detailsSourceId,
      );
      if (_isCancelled(cancellationToken)) {
        return WorksScrapeResult(
          saved: 0,
          excluded: 0,
          failed: 0,
          cancelled: true,
          sourceResults: Map.unmodifiable(sourceResults),
          detailsSource: _detailsSource,
          worksSources: _worksSources,
        );
      }
      final details = _mergeActressPages(
        detailsCollection.pages.values.toList(growable: false),
        source: detailsSource,
      );
      actressImageStatus = await _syncActress(
        actressId: actressId,
        details: details,
        source: detailsSource,
        options: options,
        cancellationToken: cancellationToken,
      );
      if (_isCancelled(cancellationToken)) {
        return WorksScrapeResult(
          saved: 0,
          excluded: 0,
          failed: 0,
          cancelled: true,
          actressImageStatus: actressImageStatus,
          sourceResults: Map.unmodifiable(sourceResults),
          detailsSource: _detailsSource,
          worksSources: _worksSources,
        );
      }
    }

    final pipelineResults = await Future.wait(sourcePipelines);
    for (final pipeline in pipelineResults) {
      recordCollectionOutcome(
        pipeline.sourceId,
        _SourceCollectionOutcome(
          collected: pipeline.collected,
          result: pipeline.result,
        ),
      );
    }

    if (_isCancelled(cancellationToken) && !streamImagesWhileFetching) {
      return WorksScrapeResult(
        saved: 0,
        excluded: pipelineResults.fold(
          0,
          (total, pipeline) => total + pipeline.preExcluded,
        ),
        failed: 0,
        cancelled: true,
        actressImageStatus: actressImageStatus,
        sourceResults: Map.unmodifiable(sourceResults),
        detailsSource: _detailsSource,
        worksSources: _worksSources,
      );
    }

    final successfulWorkSources = pipelineResults
        .where(
          (pipeline) =>
              requestedWorkIds.contains(pipeline.sourceId) &&
              pipeline.collected?.result.succeeded == true,
        )
        .toList(growable: false);
    if (successfulWorkSources.isEmpty) {
      final lastError = sourceResults.values
          .map((result) => result.error)
          .whereType<Object>()
          .lastOrNull;
      throw WorksScrapeException(
        _hasExactMatch(sourceResults.values)
            ? 'Actress works could not be fetched: $name'
                  '${lastError == null ? '' : ' ($lastError)'}'
            : 'Exact actress was not found: $name',
      );
    }

    if (streamImagesWhileFetching) {
      final streamedOutcomes = await Future.wait(
        pipelineResults.expand((pipeline) => pipeline.streamingSaves),
      );
      return _finishStreamingScrape(
        streamedOutcomes: streamedOutcomes,
        pipelineResults: pipelineResults,
        preExcluded: pipelineResults.fold(
          0,
          (total, pipeline) => total + pipeline.preExcluded,
        ),
        actressImageStatus: actressImageStatus,
        sourceResults: sourceResults,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );
    }

    final fetched = pipelineResults
        .expand((pipeline) => pipeline.fetched)
        .toList(growable: false);
    final failedCandidates = pipelineResults
        .expand((pipeline) => pipeline.failedCandidates)
        .toList(growable: false);
    final preExcluded = pipelineResults.fold(
      0,
      (total, pipeline) => total + pipeline.preExcluded,
    );
    final resolvedGroups = _resolveAcrossSources(fetched, failedCandidates);
    if (_isCancelled(cancellationToken)) {
      return WorksScrapeResult(
        saved: 0,
        excluded: preExcluded,
        failed: 0,
        cancelled: true,
        actressImageStatus: actressImageStatus,
        partialSuccess: true,
        sourceResults: Map.unmodifiable(sourceResults),
        detailsSource: _detailsSource,
        worksSources: _worksSources,
      );
    }

    _notify(
      onProgress,
      0,
      resolvedGroups.length,
      0,
      preExcluded,
      0,
      phase: WorksScrapePhase.resolvingWorks,
      totalKnown: true,
    );
    for (final group in resolvedGroups) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      _notify(
        onProgress,
        0,
        resolvedGroups.length,
        0,
        preExcluded,
        0,
        phase: WorksScrapePhase.resolvingWorks,
        source: group.sourceId,
        totalKnown: true,
        updateSourceProgress: false,
      );
    }
    final outcomes = <String, _CanonicalWorkOutcome>{};

    void recordOutcome({
      required String identityKey,
      required String code,
      required _CanonicalWorkStatus status,
      WorksScrapeFailure? failure,
      Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
    }) {
      final existing = outcomes[identityKey];
      if (existing == null) {
        outcomes[identityKey] = _CanonicalWorkOutcome(
          code: code,
          status: status,
          failure: failure,
          imageFailures: imageFailures,
        );
        return;
      }
      existing.imageFailures.addAll(imageFailures);
      if (status == _CanonicalWorkStatus.saved ||
          existing.status == _CanonicalWorkStatus.excluded) {
        existing.status = status;
        existing.failure = failure;
      }
    }

    int savedCount() => outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.saved)
        .length;

    int excludedCount() =>
        preExcluded +
        outcomes.values
            .where((outcome) => outcome.status == _CanonicalWorkStatus.excluded)
            .length;

    int failedCount() => outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.failed)
        .length;

    _notify(
      onProgress,
      0,
      resolvedGroups.length,
      savedCount(),
      excludedCount(),
      failedCount(),
      phase: WorksScrapePhase.savingWorks,
      totalKnown: true,
    );
    final sourceTotals = <ScrapeSourceId, int>{};
    for (final resolved in resolvedGroups) {
      sourceTotals.update(
        resolved.sourceId,
        (total) => total + 1,
        ifAbsent: () => 1,
      );
    }
    int sourceTotalFor(ScrapeSourceId sourceId) {
      final existing = _sourceProgress[sourceId];
      if (existing != null && existing.hasKnownTotal) {
        return existing.total;
      }
      return sourceTotals[sourceId] ?? 0;
    }

    final sourceCurrents = <ScrapeSourceId, int>{};
    var savingCurrent = 0;
    for (final resolved in resolvedGroups) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      final currentForSource = sourceCurrents[resolved.sourceId] ?? 0;
      final totalForSource = sourceTotalFor(resolved.sourceId);
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        savedCount(),
        excludedCount(),
        failedCount(),
        phase: WorksScrapePhase.savingWorks,
        source: resolved.sourceId,
        totalKnown: true,
        sourceCurrent: currentForSource,
        sourceTotal: totalForSource,
        sourceTotalKnown: true,
      );
      final code = preferredScrapeWorkCode([resolved.code]);
      if (code == null) {
        final failureCode = resolved.code.isEmpty ? '未知番號：來源候選' : resolved.code;
        recordOutcome(
          identityKey: resolved.identityKey,
          code: failureCode,
          status: _CanonicalWorkStatus.failed,
          failure: WorksScrapeFailure(
            code: failureCode,
            stage: WorksScrapeFailureStage.resolvingWorks,
            reason: WorksScrapeFailureReason.invalidCode,
            source: resolved.sourceId,
          ),
        );
      } else if (resolved.details.isEmpty) {
        recordOutcome(
          identityKey: resolved.identityKey,
          code: code,
          status: _CanonicalWorkStatus.failed,
          failure: WorksScrapeFailure(
            code: code,
            stage: WorksScrapeFailureStage.fetchingDetails,
            reason:
                resolved.failureReason ??
                WorksScrapeFailureReason.detailsUnavailable,
            source: resolved.sourceId,
            error: resolved.failureError,
          ),
        );
      } else if (exclusions.matches(code)) {
        recordOutcome(
          identityKey: resolved.identityKey,
          code: code,
          status: _CanonicalWorkStatus.excluded,
        );
      } else {
        final merged = _mergeWorkDetails(resolved.details, code);
        final maxActressCount = options.maxActressCount;
        final performerCount = merged.performerCount;
        if (maxActressCount != null &&
            (performerCount == null || performerCount <= 0)) {
          recordOutcome(
            identityKey: resolved.identityKey,
            code: code,
            status: _CanonicalWorkStatus.failed,
            failure: WorksScrapeFailure(
              code: code,
              stage: WorksScrapeFailureStage.resolvingWorks,
              reason: WorksScrapeFailureReason.performerCountUnavailable,
              source: resolved.sourceId,
            ),
          );
        } else if (maxActressCount != null &&
            performerCount! > maxActressCount) {
          recordOutcome(
            identityKey: resolved.identityKey,
            code: code,
            status: _CanonicalWorkStatus.excluded,
          );
        } else {
          try {
            final savedWork = await _saveWork(
              actressId: actressId,
              details: merged,
              missingOnly: options.fillMissingOnly,
              cancellationToken: cancellationToken,
              onImageDownload: (imageCode, _) {
                _notify(
                  onProgress,
                  savingCurrent,
                  resolvedGroups.length,
                  savedCount(),
                  excludedCount(),
                  failedCount(),
                  phase: WorksScrapePhase.downloadingImages,
                  source: resolved.sourceId,
                  workCode: imageCode,
                  totalKnown: true,
                  updateSourceProgress: false,
                );
              },
            );
            recordOutcome(
              identityKey: resolved.identityKey,
              code: code,
              status: _CanonicalWorkStatus.saved,
              imageFailures: savedWork.failedVariants,
            );
          } on _ScrapeCancelled {
            break;
          } catch (_) {
            recordOutcome(
              identityKey: resolved.identityKey,
              code: code,
              status: _CanonicalWorkStatus.failed,
              failure: WorksScrapeFailure(
                code: code,
                stage: WorksScrapeFailureStage.savingWorks,
                reason: WorksScrapeFailureReason.databaseSaveFailed,
                source: resolved.sourceId,
              ),
            );
          }
        }
      }
      final nextSourceCurrent = currentForSource + 1;
      sourceCurrents[resolved.sourceId] = nextSourceCurrent;
      savingCurrent++;
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        savedCount(),
        excludedCount(),
        failedCount(),
        phase: WorksScrapePhase.savingWorks,
        source: resolved.sourceId,
        totalKnown: true,
        sourceCurrent: nextSourceCurrent,
        sourceTotal: totalForSource,
        sourceTotalKnown: true,
      );
    }

    final saved = savedCount();
    final excluded = excludedCount();
    final failed = failedCount();
    final failedWorks = outcomes.values
        .where((outcome) => outcome.status == _CanonicalWorkStatus.failed)
        .map((outcome) => outcome.failure)
        .whereType<WorksScrapeFailure>()
        .toList(growable: false);
    final imageFailures = outcomes.values
        .where((outcome) => outcome.imageFailures.isNotEmpty)
        .map(
          (outcome) => WorksScrapeImageFailure(
            code: outcome.code,
            variants: List.unmodifiable(outcome.imageFailures),
          ),
        )
        .toList(growable: false);
    final cancelled = _isCancelled(cancellationToken);
    final partial =
        sourceResults.values.any(
          (result) =>
              result.state == ScrapeSourceRunState.failed ||
              result.state == ScrapeSourceRunState.unavailable ||
              result.state == ScrapeSourceRunState.cancelled,
        ) ||
        failed > 0 ||
        imageFailures.isNotEmpty ||
        resolvedGroups.any((group) => group.hadSourceFailure);
    if (!cancelled) {
      _notify(
        onProgress,
        savingCurrent,
        resolvedGroups.length,
        saved,
        excluded,
        failed,
        phase: WorksScrapePhase.completed,
        totalKnown: true,
      );
    }
    return WorksScrapeResult(
      saved: saved,
      excluded: excluded,
      failed: failed,
      cancelled: cancelled,
      actressImageStatus: actressImageStatus,
      partialSuccess: partial,
      sourceResults: Map.unmodifiable(sourceResults),
      failedWorks: List.unmodifiable(failedWorks),
      imageFailures: List.unmodifiable(imageFailures),
      detailsSource: _detailsSource,
      worksSources: _worksSources,
    );
  }

  List<String> _queries(String name, List<String> aliases) {
    final queries = <String>[name];
    final seen = <String>{name.toLowerCase()};
    for (final alias in aliases) {
      final normalized = alias.trim();
      if (normalized.isNotEmpty && seen.add(normalized.toLowerCase())) {
        queries.add(normalized);
      }
    }
    return queries;
  }

  Future<_CollectedSource> _collectSource({
    required ScrapeSource source,
    required List<String> queries,
    required WorksScrapeCancellationToken? cancellationToken,
    required bool includeWorks,
  }) async {
    final diagnostics = source is ScrapeSourceDiagnosticsProvider
        ? source as ScrapeSourceDiagnosticsProvider
        : null;
    diagnostics?.resetRunDiagnostic();
    final pages = <String, ScrapeActressPage>{};
    final matches = <String, ScrapeActressSearchResult>{};
    final completedUris = <String>{};
    final summaries = <ScrapeWorkSummary>[];
    Object? lastError;
    Object? lastSearchError;
    var matched = false;
    var traversed = false;
    for (final query in queries) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      List<ScrapeActressSearchResult> results;
      try {
        results = await source.searchActresses(query);
      } catch (error) {
        // A single name/alias search can legitimately fail while a later
        // alias still finds the exact actress. Do not turn that superseded
        // query failure into a partial source result.
        lastSearchError = error;
        continue;
      }
      if (_isCancelled(cancellationToken)) {
        break;
      }
      final queryKey = query.trim().toLowerCase();
      for (final actress in results.where(
        (result) => result.name.trim().toLowerCase() == queryKey,
      )) {
        if (_isCancelled(cancellationToken)) {
          break;
        }
        matched = true;
        final uriKey = actress.uri.toString();
        if (completedUris.contains(uriKey)) {
          continue;
        }
        matches[uriKey] = actress;
        try {
          final page = await source.fetchActressPage(actress);
          if (_isCancelled(cancellationToken)) {
            break;
          }
          pages[uriKey] = page;
          if (!includeWorks) {
            traversed = true;
            completedUris.add(uriKey);
            continue;
          }
          try {
            final sourceWorks = await source.fetchActressWorks(
              actress,
              firstPage: page,
              isCancelled: () => _isCancelled(cancellationToken),
            );
            if (_isCancelled(cancellationToken)) {
              break;
            }
            summaries.addAll(sourceWorks);
            traversed = true;
            completedUris.add(uriKey);
          } catch (error) {
            lastError = error;
          }
        } catch (error) {
          lastError = error;
        }
      }
    }
    if (!matched && lastError == null) {
      lastError = lastSearchError;
    }
    final sourceDiagnostic = diagnostics?.lastRunDiagnostic;
    final state = _isCancelled(cancellationToken)
        ? ScrapeSourceRunState.cancelled
        : sourceDiagnostic?.state ??
              (traversed
                  ? (summaries.isEmpty
                        ? ScrapeSourceRunState.zeroResults
                        : lastError == null
                        ? ScrapeSourceRunState.success
                        : ScrapeSourceRunState.partial)
                  : matched
                  ? _sourceStateForError(lastError)
                  : ScrapeSourceRunState.unavailable);
    return _CollectedSource(
      source: source,
      pages: pages,
      summaries: summaries,
      result: ScrapeSourceRunResult(
        source: source.id,
        state: state,
        discovered: summaries.length,
        error: sourceDiagnostic?.error ?? lastError,
      ),
    );
  }

  Future<_SourceCollectionOutcome> _collectSourceSafely({
    required ScrapeSource source,
    required List<String> queries,
    required WorksScrapeCancellationToken? cancellationToken,
    required bool includeWorks,
  }) async {
    try {
      final collected = await _collectSource(
        source: source,
        queries: queries,
        cancellationToken: cancellationToken,
        includeWorks: includeWorks,
      );
      return _SourceCollectionOutcome(
        collected: collected,
        result: collected.result,
      );
    } catch (error) {
      return _SourceCollectionOutcome(
        result: ScrapeSourceRunResult(
          source: source.id,
          state: _isCancelled(cancellationToken)
              ? ScrapeSourceRunState.cancelled
              : _sourceStateForError(error),
          error: error,
        ),
      );
    }
  }

  ScrapeSourceRunState _sourceStateForError(Object? error) {
    if (error is JavBusVerificationRequiredException) {
      return ScrapeSourceRunState.verificationRequired;
    }
    if (error is JavBusVerificationCancelledException) {
      return ScrapeSourceRunState.cancelled;
    }
    if (error is JavBusRequestException) {
      return switch (error.kind) {
        JavBusFailureKind.verificationRequired =>
          ScrapeSourceRunState.verificationRequired,
        JavBusFailureKind.blocked => ScrapeSourceRunState.blocked,
        JavBusFailureKind.rateLimited => ScrapeSourceRunState.rateLimited,
        JavBusFailureKind.timeout => ScrapeSourceRunState.timedOut,
        JavBusFailureKind.cancelled => ScrapeSourceRunState.cancelled,
        JavBusFailureKind.notFound ||
        JavBusFailureKind.parserInvalid ||
        JavBusFailureKind.transport ||
        JavBusFailureKind.transientTransport => ScrapeSourceRunState.failed,
      };
    }
    if (error is AvBaseRequestException) {
      return switch (error.kind) {
        AvBaseFailureKind.blocked => ScrapeSourceRunState.blocked,
        AvBaseFailureKind.rateLimited => ScrapeSourceRunState.rateLimited,
        AvBaseFailureKind.timeout => ScrapeSourceRunState.timedOut,
        AvBaseFailureKind.cancelled => ScrapeSourceRunState.cancelled,
        AvBaseFailureKind.notFound ||
        AvBaseFailureKind.parserInvalid ||
        AvBaseFailureKind.transport ||
        AvBaseFailureKind.transientTransport => ScrapeSourceRunState.failed,
      };
    }
    return ScrapeSourceRunState.failed;
  }

  Future<_SourcePipelineOutcome> _runSourcePipeline({
    required ScrapeSourceId sourceId,
    required ScrapeSource? source,
    required Future<_SourceCollectionOutcome> collectionFuture,
    required PrefixExclusion exclusions,
    required WorksScrapeCancellationToken? cancellationToken,
    required bool streamImageSaves,
    required int actressId,
    required WorkScrapeOptions options,
    required _BoundedAsyncQueue imageQueue,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) async {
    final collectionOutcome = await collectionFuture;
    final collected = collectionOutcome.collected;
    if (source == null ||
        collected == null ||
        !collectionOutcome.result.succeeded) {
      return _SourcePipelineOutcome(
        sourceId: sourceId,
        collected: collected,
        result: collectionOutcome.result,
      );
    }

    final selection = _selectWorkCandidates(collected, exclusions);
    _notify(
      onProgress,
      0,
      selection.candidates.length,
      0,
      selection.preExcluded,
      0,
      phase: WorksScrapePhase.fetchingDetails,
      source: sourceId,
      totalKnown: false,
      sourceCurrent: 0,
      sourceTotal: selection.candidates.length,
      sourceTotalKnown: true,
    );

    var detailCurrent = 0;
    void notifyDetailProgress({
      _WorkCandidate? candidate,
      bool completed = false,
    }) {
      if (completed && detailCurrent < selection.candidates.length) {
        detailCurrent++;
      }
      _notify(
        onProgress,
        0,
        selection.candidates.length,
        0,
        selection.preExcluded,
        0,
        phase: WorksScrapePhase.fetchingDetails,
        source: sourceId,
        workCode: candidate?.summary.code,
        totalKnown: false,
        updateSourceProgress: completed,
        sourceCurrent: detailCurrent,
        sourceTotal: selection.candidates.length,
        sourceTotalKnown: true,
      );
    }

    var streamingCurrent = 0;
    var streamingSaved = 0;
    var streamingExcluded = 0;
    var streamingFailed = 0;

    void notifyStreamingProgress({
      String? workCode,
      bool updateSourceProgress = true,
    }) {
      _notify(
        onProgress,
        streamingCurrent,
        selection.candidates.length,
        streamingSaved,
        selection.preExcluded + streamingExcluded,
        streamingFailed,
        phase: WorksScrapePhase.downloadingImages,
        source: sourceId,
        workCode: workCode,
        totalKnown: true,
        updateSourceProgress: updateSourceProgress,
        sourceCurrent: streamingCurrent,
        sourceTotal: selection.candidates.length,
        sourceTotalKnown: true,
      );
    }

    void recordStreamingOutcome(_StreamingWorkOutcome outcome) {
      streamingCurrent++;
      switch (outcome.status) {
        case _CanonicalWorkStatus.saved:
          streamingSaved++;
        case _CanonicalWorkStatus.excluded:
          streamingExcluded++;
        case _CanonicalWorkStatus.failed:
          streamingFailed++;
      }
      notifyStreamingProgress(workCode: outcome.code);
    }

    Future<_StreamingWorkOutcome> observeStreamingOutcome(
      Future<_StreamingWorkOutcome> future,
    ) async {
      final outcome = await future;
      recordStreamingOutcome(outcome);
      return outcome;
    }

    final streamingSaves = <Future<_StreamingWorkOutcome>>[];
    void enqueueImageSave(_FetchedWorkDetail fetched) {
      if (!streamImageSaves) {
        return;
      }
      streamingSaves.add(
        observeStreamingOutcome(
          _enqueueStreamingWork(
            fetched: fetched,
            actressId: actressId,
            options: options,
            exclusions: exclusions,
            cancellationToken: cancellationToken,
            imageQueue: imageQueue,
            onImageDownload: (code) => notifyStreamingProgress(
              workCode: code,
              updateSourceProgress: true,
            ),
          ),
        ),
      );
    }

    final detailResult = await _fetchDetailsForSourceSafely(
      source: source,
      candidates: selection.candidates,
      cancellationToken: cancellationToken,
      onAttemptStart: (candidate) => notifyDetailProgress(candidate: candidate),
      onAttemptComplete: (candidate) =>
          notifyDetailProgress(candidate: candidate, completed: true),
      onDetailsFetched: enqueueImageSave,
    );
    final sourceResolution = _resolveSourceDetails(detailResult);
    final sourceErrors = <String>[
      if (collectionOutcome.result.error != null)
        collectionOutcome.result.error.toString(),
      if (sourceResolution.failedCandidates.isNotEmpty)
        _formatDetailFailures(sourceResolution.failedCandidates),
    ];
    final sourceResult = sourceResolution.failedCandidates.isEmpty
        ? collectionOutcome.result
        : ScrapeSourceRunResult(
            source: sourceId,
            state: ScrapeSourceRunState.partial,
            discovered: collectionOutcome.result.discovered,
            error: sourceErrors.join('; '),
          );
    if (streamImageSaves) {
      for (final failure in sourceResolution.failedCandidates) {
        streamingSaves.add(
          observeStreamingOutcome(Future.value(_streamingFailure(failure))),
        );
      }
    }
    return _SourcePipelineOutcome(
      sourceId: sourceId,
      collected: collected,
      result: sourceResult,
      fetched: sourceResolution.fetched,
      failedCandidates: sourceResolution.failedCandidates,
      preExcluded: selection.preExcluded,
      streamingSaves: List.unmodifiable(streamingSaves),
    );
  }

  Future<_StreamingWorkOutcome> _enqueueStreamingWork({
    required _FetchedWorkDetail fetched,
    required int actressId,
    required WorkScrapeOptions options,
    required PrefixExclusion exclusions,
    required WorksScrapeCancellationToken? cancellationToken,
    required _BoundedAsyncQueue imageQueue,
    void Function(String code)? onImageDownload,
  }) {
    final details = fetched.details;
    final code = preferredScrapeWorkCode([details.code]);
    final identityKey = code == null
        ? 'stream:${fetched.sourceId.storageValue}:${fetched.candidate.summary.detailUri}'
        : 'stream:${fetched.sourceId.storageValue}:${code.toLowerCase()}';
    if (code == null) {
      return Future.value(
        _StreamingWorkOutcome.failed(
          identityKey: identityKey,
          code: details.code.isEmpty ? '未知番號' : details.code,
          failure: WorksScrapeFailure(
            code: details.code.isEmpty ? '未知番號' : details.code,
            stage: WorksScrapeFailureStage.resolvingWorks,
            reason: WorksScrapeFailureReason.invalidCode,
            source: fetched.sourceId,
          ),
        ),
      );
    }
    if (exclusions.matches(code)) {
      return Future.value(
        _StreamingWorkOutcome.excluded(identityKey: identityKey, code: code),
      );
    }
    final performerCount = details.performerCount;
    final maxActressCount = options.maxActressCount;
    if (maxActressCount != null &&
        (performerCount == null || performerCount <= 0)) {
      return Future.value(
        _StreamingWorkOutcome.failed(
          identityKey: identityKey,
          code: code,
          failure: WorksScrapeFailure(
            code: code,
            stage: WorksScrapeFailureStage.resolvingWorks,
            reason: WorksScrapeFailureReason.performerCountUnavailable,
            source: fetched.sourceId,
          ),
        ),
      );
    }
    if (maxActressCount != null && performerCount! > maxActressCount) {
      return Future.value(
        _StreamingWorkOutcome.excluded(identityKey: identityKey, code: code),
      );
    }

    return imageQueue.add<_StreamingWorkOutcome>(() async {
      if (_isCancelled(cancellationToken)) {
        return _StreamingWorkOutcome.cancelled(
          identityKey: identityKey,
          code: code,
        );
      }
      try {
        final saved = await _saveWork(
          actressId: actressId,
          details: details,
          missingOnly: options.fillMissingOnly,
          cancellationToken: cancellationToken,
          onImageDownload: (imageCode, _) {
            onImageDownload?.call(imageCode);
          },
        );
        return _StreamingWorkOutcome.saved(
          identityKey: identityKey,
          code: code,
          imageFailures: saved.failedVariants,
        );
      } on _ScrapeCancelled {
        return _StreamingWorkOutcome.cancelled(
          identityKey: identityKey,
          code: code,
        );
      } catch (error) {
        return _StreamingWorkOutcome.failed(
          identityKey: identityKey,
          code: code,
          failure: WorksScrapeFailure(
            code: code,
            stage: WorksScrapeFailureStage.savingWorks,
            reason: WorksScrapeFailureReason.databaseSaveFailed,
            source: fetched.sourceId,
            error: error,
          ),
        );
      }
    });
  }

  _StreamingWorkOutcome _streamingFailure(_FailedWorkCandidate failure) {
    final rawCode = failure.candidate.summary.code?.trim() ?? '';
    final code = rawCode.isEmpty
        ? '未知番號'
        : preferredScrapeWorkCode([rawCode]) ?? rawCode;
    final identityKey =
        'failed:${failure.candidate.source.id.storageValue}:${failure.candidate.summary.detailUri}';
    return _StreamingWorkOutcome.failed(
      identityKey: identityKey,
      code: code,
      failure: WorksScrapeFailure(
        code: code,
        stage: WorksScrapeFailureStage.fetchingDetails,
        reason: failure.reason,
        source: failure.candidate.source.id,
        error: failure.error,
      ),
    );
  }

  WorksScrapeResult _finishStreamingScrape({
    required List<_StreamingWorkOutcome> streamedOutcomes,
    required List<_SourcePipelineOutcome> pipelineResults,
    required int preExcluded,
    required ActressImageSyncStatus actressImageStatus,
    required Map<ScrapeSourceId, ScrapeSourceRunResult> sourceResults,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(WorksScrapeProgress progress)? onProgress,
  }) {
    final cancelled =
        _isCancelled(cancellationToken) ||
        streamedOutcomes.any((outcome) => outcome.cancelled);
    if (cancelled) {
      return WorksScrapeResult(
        saved: 0,
        excluded: preExcluded,
        failed: 0,
        cancelled: true,
        actressImageStatus: actressImageStatus,
        partialSuccess: true,
        sourceResults: Map.unmodifiable(sourceResults),
        detailsSource: _detailsSource,
        worksSources: _worksSources,
      );
    }
    final saved = streamedOutcomes
        .where((outcome) => outcome.status == _CanonicalWorkStatus.saved)
        .length;
    final excluded =
        preExcluded +
        streamedOutcomes
            .where((outcome) => outcome.status == _CanonicalWorkStatus.excluded)
            .length;
    final failedOutcomes = streamedOutcomes
        .where((outcome) => outcome.status == _CanonicalWorkStatus.failed)
        .toList(growable: false);
    final imageFailures = streamedOutcomes
        .where((outcome) => outcome.imageFailures.isNotEmpty)
        .map(
          (outcome) => WorksScrapeImageFailure(
            code: outcome.code,
            variants: List.unmodifiable(outcome.imageFailures),
          ),
        )
        .toList(growable: false);
    final partial =
        sourceResults.values.any(
          (result) =>
              result.state == ScrapeSourceRunState.failed ||
              result.state == ScrapeSourceRunState.unavailable ||
              result.state == ScrapeSourceRunState.cancelled,
        ) ||
        failedOutcomes.isNotEmpty ||
        imageFailures.isNotEmpty ||
        pipelineResults.any(
          (pipeline) => pipeline.result.state == ScrapeSourceRunState.partial,
        );
    _notify(
      onProgress,
      streamedOutcomes.length,
      streamedOutcomes.length,
      saved,
      excluded,
      failedOutcomes.length,
      phase: WorksScrapePhase.completed,
      totalKnown: true,
    );
    return WorksScrapeResult(
      saved: saved,
      excluded: excluded,
      failed: failedOutcomes.length,
      cancelled: false,
      actressImageStatus: actressImageStatus,
      partialSuccess: partial,
      sourceResults: Map.unmodifiable(sourceResults),
      failedWorks: List.unmodifiable(
        failedOutcomes
            .map((outcome) => outcome.failure)
            .whereType<WorksScrapeFailure>(),
      ),
      imageFailures: List.unmodifiable(imageFailures),
      detailsSource: _detailsSource,
      worksSources: _worksSources,
    );
  }

  String _formatDetailFailures(List<_FailedWorkCandidate> failures) {
    return failures
        .map((failure) {
          final uri = failure.candidate.summary.detailUri.toString();
          final error = failure.error;
          return error == null ? uri : '$uri ($error)';
        })
        .join('; ');
  }

  _SourceCandidateSelection _selectWorkCandidates(
    _CollectedSource collected,
    PrefixExclusion exclusions,
  ) {
    final selected = <_WorkCandidate>[];
    final selectedKeys = <String, int>{};
    var preExcluded = 0;

    for (final summary in collected.summaries) {
      final summaryCode = summary.code?.trim() ?? '';
      if (summaryCode.isNotEmpty && exclusions.matches(summaryCode)) {
        preExcluded++;
        continue;
      }
      final candidate = _WorkCandidate(
        source: collected.source,
        summary: summary,
      );
      // Only collapse an exact transport duplicate. Title similarity is not
      // a work identity and must never remove a different edition.
      final normalizedCode = preferredScrapeWorkCode([summaryCode]);
      final key = normalizedCode == null || normalizedCode.isEmpty
          ? 'uri:${summary.detailUri}'
          : 'code:${normalizedCode.toLowerCase()}';
      final existingIndex = selectedKeys[key];
      if (existingIndex == null) {
        selectedKeys[key] = selected.length;
        selected.add(candidate);
      } else if (scrapeWorkCodeIsSpecialEdition(
            selected[existingIndex].summary.code ??
                selected[existingIndex].summary.rawCode,
          ) &&
          !scrapeWorkCodeIsSpecialEdition(summaryCode)) {
        // The special edition shares the base identity, but the ordinary
        // edition is the one that should supply the detail page.
        selected[existingIndex] = candidate;
      }
    }
    return _SourceCandidateSelection(
      candidates: List.unmodifiable(selected),
      preExcluded: preExcluded,
    );
  }

  _SourceDetailResolution _resolveSourceDetails(_DetailQueueResult result) {
    return _SourceDetailResolution(
      fetched: result.fetched,
      failedCandidates: result.failedCandidates,
    );
  }

  Future<_DetailQueueResult> _fetchDetailsForSourceSafely({
    required ScrapeSource source,
    required List<_WorkCandidate> candidates,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(_WorkCandidate candidate)? onAttemptStart,
    void Function(_WorkCandidate candidate)? onAttemptComplete,
    void Function(_FetchedWorkDetail detail)? onDetailsFetched,
  }) async {
    try {
      return await _fetchDetailsForSource(
        source: source,
        candidates: candidates,
        cancellationToken: cancellationToken,
        onAttemptStart: onAttemptStart,
        onAttemptComplete: onAttemptComplete,
        onDetailsFetched: onDetailsFetched,
      );
    } catch (error) {
      final failed = <_FailedWorkCandidate>[];
      for (final candidate in candidates) {
        onAttemptStart?.call(candidate);
        failed.add(
          _FailedWorkCandidate(
            candidate: candidate,
            reason: WorksScrapeFailureReason.detailsUnavailable,
            error: error,
          ),
        );
        onAttemptComplete?.call(candidate);
      }
      return _DetailQueueResult(failedCandidates: failed);
    }
  }

  Future<_DetailQueueResult> _fetchDetailsForSource({
    required ScrapeSource source,
    required List<_WorkCandidate> candidates,
    required WorksScrapeCancellationToken? cancellationToken,
    void Function(_WorkCandidate candidate)? onAttemptStart,
    void Function(_WorkCandidate candidate)? onAttemptComplete,
    void Function(_FetchedWorkDetail detail)? onDetailsFetched,
  }) async {
    final fetched = <_FetchedWorkDetail>[];
    final failedCandidates = <_FailedWorkCandidate>[];
    final fetchedKeys = <String>{};
    var detailRequestsStarted = 0;
    for (final candidate in candidates) {
      if (_isCancelled(cancellationToken)) {
        break;
      }
      onAttemptStart?.call(candidate);
      if ((source.id == ScrapeSourceId.javbus ||
              source.id == ScrapeSourceId.avbase) &&
          detailRequestsStarted > 0 &&
          javBusDetailDelay > Duration.zero) {
        await Future<void>.delayed(javBusDetailDelay);
      }
      detailRequestsStarted++;
      ScrapeWorkDetails? details;
      Object? lastError;
      try {
        try {
          details = await source.fetchWorkDetails(candidate.summary);
        } catch (error) {
          lastError = error;
        }
        final scrapedDetails = details;
        if (scrapedDetails == null) {
          failedCandidates.add(
            _FailedWorkCandidate(
              candidate: candidate,
              reason: WorksScrapeFailureReason.detailsUnavailable,
              error: lastError,
            ),
          );
        } else {
          final code = preferredScrapeWorkCode([scrapedDetails.code]);
          final fetchedDetail = _FetchedWorkDetail(
            candidate: candidate,
            sourceId: source.id,
            details: _withScrapeCode(
              scrapedDetails,
              code ?? '',
              fallbackTitle: candidate.summary.title,
              fallbackReleaseDate: candidate.summary.releaseDate,
            ),
          );
          if (fetchedKeys.add(_fetchedDetailKey(fetchedDetail))) {
            fetched.add(fetchedDetail);
            onDetailsFetched?.call(fetchedDetail);
          }
        }
      } finally {
        onAttemptComplete?.call(candidate);
      }
    }
    return _DetailQueueResult(
      fetched: fetched,
      failedCandidates: failedCandidates,
    );
  }

  String _fetchedDetailKey(_FetchedWorkDetail detail) {
    final code = preferredScrapeWorkCode([detail.details.code]);
    return code == null || code.isEmpty
        ? 'uri:${detail.candidate.summary.detailUri}'
        : 'code:${code.toLowerCase()}';
  }

  List<_ResolvedWorkGroup> _resolveAcrossSources(
    List<_FetchedWorkDetail> fetched,
    List<_FailedWorkCandidate> failedCandidates,
  ) {
    final groups = <String, _ResolvedWorkGroup>{};

    int sourcePriority(ScrapeSourceId source) {
      final priority = ScrapeSourceRegistry.worksPriority.indexOf(source);
      return priority < 0
          ? ScrapeSourceRegistry.worksPriority.length
          : priority;
    }

    String canonicalCode(String? rawCode) {
      return preferredScrapeWorkCode([rawCode])?.trim() ?? '';
    }

    int compareSourceAndCode(
      ScrapeSourceId leftSource,
      String leftCode,
      Uri leftUri,
      ScrapeSourceId rightSource,
      String rightCode,
      Uri rightUri,
    ) {
      final sourceComparison = sourcePriority(
        leftSource,
      ).compareTo(sourcePriority(rightSource));
      if (sourceComparison != 0) {
        return sourceComparison;
      }
      final codeComparison = leftCode.toLowerCase().compareTo(
        rightCode.toLowerCase(),
      );
      if (codeComparison != 0) {
        return codeComparison;
      }
      return leftUri.toString().compareTo(rightUri.toString());
    }

    final sortedFetched = [...fetched]
      ..sort(
        (left, right) => compareSourceAndCode(
          left.sourceId,
          canonicalCode(left.details.code),
          left.candidate.summary.detailUri,
          right.sourceId,
          canonicalCode(right.details.code),
          right.candidate.summary.detailUri,
        ),
      );
    for (final detail in sortedFetched) {
      final code = canonicalCode(detail.details.code);
      final sourceUri = detail.candidate.summary.detailUri.toString();
      final identityKey = code.isEmpty
          ? 'resolved:${detail.sourceId.storageValue}:$sourceUri'
          : 'resolved:${code.toLowerCase()}';
      final group = groups.putIfAbsent(
        identityKey,
        () => _ResolvedWorkGroup(
          code: code,
          details: <ScrapeWorkDetails>[],
          identityKey: identityKey,
          hadSourceFailure: false,
          sourceId: detail.sourceId,
        ),
      );
      group.details.add(detail.details);
      if (sourcePriority(detail.sourceId) < sourcePriority(group.sourceId)) {
        group.sourceId = detail.sourceId;
      }
    }

    final sortedFailures = [...failedCandidates]
      ..sort(
        (left, right) => compareSourceAndCode(
          left.candidate.source.id,
          canonicalCode(left.candidate.summary.code),
          left.candidate.summary.detailUri,
          right.candidate.source.id,
          canonicalCode(right.candidate.summary.code),
          right.candidate.summary.detailUri,
        ),
      );
    for (final failed in sortedFailures) {
      final rawCode = failed.candidate.summary.code?.trim() ?? '';
      final code = canonicalCode(rawCode);
      final identityKey = code.isEmpty
          ? 'failed:${failed.candidate.source.id.storageValue}:${failed.candidate.summary.detailUri}'
          : 'resolved:${code.toLowerCase()}';
      final group = groups.putIfAbsent(
        identityKey,
        () => _ResolvedWorkGroup(
          code: code,
          details: <ScrapeWorkDetails>[],
          identityKey: identityKey,
          hadSourceFailure: true,
          sourceId: failed.candidate.source.id,
          failureReason: failed.reason,
          failureError: failed.error,
        ),
      );
      group.hadSourceFailure = true;
      if (sourcePriority(failed.candidate.source.id) <
          sourcePriority(group.sourceId)) {
        group.sourceId = failed.candidate.source.id;
        group.failureReason = failed.reason;
        group.failureError = failed.error;
      } else if (group.failureReason == null) {
        group.failureReason = failed.reason;
        group.failureError = failed.error;
      }
    }

    for (final group in groups.values) {
      group.details.sort((left, right) {
        final leftSpecial = scrapeWorkCodeIsSpecialEdition(
          left.rawCode ?? left.code,
        );
        final rightSpecial = scrapeWorkCodeIsSpecialEdition(
          right.rawCode ?? right.code,
        );
        if (leftSpecial != rightSpecial) {
          return leftSpecial ? 1 : -1;
        }
        final sourceComparison = sourcePriority(
          left.source,
        ).compareTo(sourcePriority(right.source));
        if (sourceComparison != 0) {
          return sourceComparison;
        }
        return (left.rawCode ?? left.code).compareTo(
          right.rawCode ?? right.code,
        );
      });
    }
    final resolved = groups.values.toList()
      ..sort((left, right) {
        final sourceComparison = sourcePriority(
          left.sourceId,
        ).compareTo(sourcePriority(right.sourceId));
        if (sourceComparison != 0) {
          return sourceComparison;
        }
        return left.identityKey.compareTo(right.identityKey);
      });
    return List.unmodifiable(resolved);
  }

  ScrapedActressDetails _mergeActressPages(
    List<ScrapeActressPage> pages, {
    required ScrapeSource source,
  }) {
    String? firstValue(String? Function(ScrapedActressDetails) select) {
      for (final page in pages) {
        final value = select(page.details)?.trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    Uri? avatarUrl;
    for (final page in pages) {
      final candidate = page.details.avatarUrl;
      if (candidate != null && source.acceptsImageUri(candidate)) {
        avatarUrl = candidate;
        break;
      }
    }
    return ScrapedActressDetails(
      name: firstValue((details) => details.name),
      avatarUrl: avatarUrl,
      birthDate: firstValue((details) => details.birthDate),
      height: firstValue((details) => details.height),
      cup: firstValue((details) => details.cup),
      bust: firstValue((details) => details.bust),
      waist: firstValue((details) => details.waist),
      hip: firstValue((details) => details.hip),
    );
  }

  Future<ActressImageSyncStatus> _syncActress({
    required int actressId,
    required ScrapedActressDetails details,
    required ScrapeSource source,
    required WorkScrapeOptions options,
    required WorksScrapeCancellationToken? cancellationToken,
  }) async {
    return db.runManagedImageLifecycle(
      () => _syncActressUnlocked(
        actressId: actressId,
        details: details,
        source: source,
        options: options,
        cancellationToken: cancellationToken,
      ),
    );
  }

  Future<ActressImageSyncStatus> _syncActressUnlocked({
    required int actressId,
    required ScrapedActressDetails details,
    required ScrapeSource source,
    required WorkScrapeOptions options,
    required WorksScrapeCancellationToken? cancellationToken,
  }) async {
    String? imagePath;
    String? previousImagePath;
    var imageStatus = options.replaceActressImage
        ? ActressImageSyncStatus.unavailable
        : ActressImageSyncStatus.notRequested;
    final avatar = details.avatarUrl;
    if (options.replaceActressImage &&
        avatar != null &&
        source.acceptsImageUri(avatar)) {
      try {
        if (_isCancelled(cancellationToken)) {
          return imageStatus;
        }
        previousImagePath = (await db.getActressById(
          actressId,
        ))?['img_path']?.toString();
        if (_isCancelled(cancellationToken)) {
          return imageStatus;
        }
        final version = DateTime.now().microsecondsSinceEpoch;
        imagePath = await actressImageDownloader.download(
          avatar,
          path.join(
            imageDirectory,
            'actresses',
            'actress_${actressId}_$version.jpg',
          ),
        );
        imageStatus = ActressImageSyncStatus.replaced;
      } catch (_) {
        imagePath = null;
        imageStatus = ActressImageSyncStatus.downloadFailed;
      }
    }

    if (_isCancelled(cancellationToken)) {
      if (imagePath != null) {
        await _deleteManagedActressImage(imagePath);
      }
      return imageStatus;
    }

    if (!options.syncDetails && imagePath == null) {
      return imageStatus;
    }

    final syncDetails = ScrapedActressDetails(
      // The local canonical name is authoritative; scraped alias pages must
      // never rename the actress record.
      name: null,
      imagePath: imagePath,
      birthDate: options.syncDetails ? details.birthDate : null,
      height: options.syncDetails ? details.height : null,
      cup: options.syncDetails ? details.cup : null,
      bust: options.syncDetails ? details.bust : null,
      waist: options.syncDetails ? details.waist : null,
      hip: options.syncDetails ? details.hip : null,
    );
    if (_isCancelled(cancellationToken)) {
      if (imagePath != null) {
        await _deleteManagedActressImage(imagePath);
      }
      return imageStatus;
    }
    final updated = await db.syncActressDetails(
      actressId: actressId,
      details: syncDetails,
      missingOnly: options.fillMissingOnly,
      replaceImage: options.replaceActressImage,
    );
    if (!updated && imagePath != null) {
      final file = File(imagePath);
      if (file.existsSync()) {
        await file.delete();
      }
      return ActressImageSyncStatus.databaseFailed;
    } else if (updated && imagePath != null) {
      await _deletePreviousManagedAvatar(previousImagePath, imagePath);
    }
    return imageStatus;
  }

  Future<void> _deleteManagedActressImage(String imagePath) async {
    final managedDirectory = path.normalize(
      path.absolute(path.join(imageDirectory, 'actresses')),
    );
    final image = path.normalize(path.absolute(imagePath));
    if (!path.isWithin(managedDirectory, image)) {
      return;
    }
    final file = File(image);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> _deletePreviousManagedAvatar(
    String? previousPath,
    String newPath,
  ) async {
    if (previousPath == null || previousPath.trim().isEmpty) {
      return;
    }
    final managedDirectory = path.normalize(
      path.absolute(path.join(imageDirectory, 'actresses')),
    );
    final previous = path.normalize(path.absolute(previousPath));
    final replacement = path.normalize(path.absolute(newPath));
    if (previous == replacement || !path.isWithin(managedDirectory, previous)) {
      return;
    }
    final file = File(previous);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<_WorkImageSaveResult> _saveWork({
    required int actressId,
    required ScrapeWorkDetails details,
    required bool missingOnly,
    WorksScrapeCancellationToken? cancellationToken,
    void Function(String code, WorkImageVariant variant)? onImageDownload,
  }) async {
    return _saveWorkUnlocked(
      actressId: actressId,
      details: details,
      missingOnly: missingOnly,
      cancellationToken: cancellationToken,
      onImageDownload: onImageDownload,
    );
  }

  Future<_WorkImageSaveResult> _saveWorkUnlocked({
    required int actressId,
    required ScrapeWorkDetails details,
    required bool missingOnly,
    WorksScrapeCancellationToken? cancellationToken,
    void Function(String code, WorkImageVariant variant)? onImageDownload,
  }) async {
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final code = preferredScrapeWorkCode([details.code]);
    if (code == null) {
      throw ArgumentError('Work code must not be empty.');
    }
    if (details.code != code) {
      details = _withScrapeCode(
        details,
        code,
        fallbackTitle: details.title,
        fallbackReleaseDate: details.releaseDate,
      );
    }
    final performerSource = details.source == ScrapeSourceId.javbus
        ? details.source.storageValue
        : null;
    final performers = performerSource == null ? null : details.performers;
    final prepared = await db.runManagedImageLifecycle(() async {
      final workId = await db.upsertActressWork(
        actressId: actressId,
        work: details.toWork(),
        missingOnly: missingOnly,
        performerSource: performerSource,
        performers: performers,
      );
      final current = await db.getWorkById(workId);
      return _PreparedWorkImage(
        details: details,
        currentCard: current?['card_image_path']?.toString() ?? '',
        currentDetail: current?['detail_image_path']?.toString() ?? '',
      );
    });
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final imageResults = await Future.wait<_WorkImageResult>([
      _downloadWorkImage(
        details: prepared.details,
        variant: WorkImageVariant.card,
        targetPath: path.join(
          imageDirectory,
          'works',
          workImageDownloader.fileNameFor(
            code: prepared.details.code,
            variant: WorkImageVariant.card,
          ),
        ),
        currentPath: prepared.currentCard,
        missingOnly: missingOnly,
        onImageDownload: onImageDownload,
      ),
      _downloadWorkImage(
        details: prepared.details,
        variant: WorkImageVariant.detail,
        targetPath: path.join(
          imageDirectory,
          'works',
          workImageDownloader.fileNameFor(
            code: prepared.details.code,
            variant: WorkImageVariant.detail,
          ),
        ),
        currentPath: prepared.currentDetail,
        missingOnly: missingOnly,
        onImageDownload: onImageDownload,
      ),
    ]);
    if (_isCancelled(cancellationToken)) {
      throw const _ScrapeCancelled();
    }
    final cardPath = imageResults[0];
    final detailPath = imageResults[1];
    final work = prepared.details.toWork(
      cardImagePath: cardPath.path,
      detailImagePath: detailPath.path,
    );
    await db.runManagedImageLifecycle(
      () => db.upsertActressWork(
        actressId: actressId,
        work: work,
        missingOnly: missingOnly,
        performerSource: performerSource,
        performers: performers,
      ),
    );
    return _WorkImageSaveResult(
      failedVariants: {
        if (cardPath.failed) WorkImageVariant.card,
        if (detailPath.failed) WorkImageVariant.detail,
      },
    );
  }

  Future<_WorkImageResult> _downloadWorkImage({
    required ScrapeWorkDetails details,
    required WorkImageVariant variant,
    required String targetPath,
    required String currentPath,
    required bool missingOnly,
    void Function(String code, WorkImageVariant variant)? onImageDownload,
  }) async {
    if (missingOnly &&
        currentPath.isNotEmpty &&
        File(currentPath).existsSync()) {
      return _WorkImageResult(path: currentPath);
    }
    onImageDownload?.call(details.code, variant);
    // Work images must come only from the explicit WorkImagePolicy hosts
    // (DMM/MGStage).  Source pages such as JavBus and Minnano AV are metadata
    // and avatar sources only; never use their jacket/gallery URI as a work
    // image or as a fallback here.
    try {
      await workImageDownloader.downloadToFile(
        code: details.code,
        studio: details.studio,
        publisher: details.publisher,
        originalImageEvidenceUris: details.originalImageEvidenceUris,
        variant: variant,
        targetPath: targetPath,
      );
      return _WorkImageResult(path: targetPath);
    } catch (_) {
      return _WorkImageResult(
        path: currentPath.isEmpty ? null : currentPath,
        failed: true,
      );
    }
  }

  ScrapeWorkDetails _withScrapeCode(
    ScrapeWorkDetails details,
    String code, {
    required String fallbackTitle,
    required String? fallbackReleaseDate,
  }) {
    return ScrapeWorkDetails(
      source: details.source,
      code: code,
      rawCode: details.rawCode ?? details.code,
      title: details.title.trim().isEmpty ? fallbackTitle : details.title,
      releaseDate: details.releaseDate ?? fallbackReleaseDate,
      durationMinutes: details.durationMinutes,
      studio: details.studio,
      publisher: details.publisher,
      series: details.series,
      performerCount: details.performerCount,
      performers: details.performers,
      imageUris: details.imageUris,
      originalImageEvidenceUris: details.originalImageEvidenceUris,
    );
  }

  ScrapeWorkDetails _mergeWorkDetails(
    List<ScrapeWorkDetails> details,
    String code,
  ) {
    String? firstText(String? Function(ScrapeWorkDetails) select) {
      for (final item in details) {
        final value = select(item)?.trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    int? firstInt(int? Function(ScrapeWorkDetails) select) {
      for (final item in details) {
        final value = select(item);
        if (value != null && value > 0) {
          return value;
        }
      }
      return null;
    }

    int? performerCount;
    for (final item in details) {
      final value = item.performerCount;
      if (value != null && (performerCount == null || value > performerCount)) {
        performerCount = value;
      }
    }
    List<WorkPerformer>? performers;
    final performerKeys = <String>{};
    for (final item in details) {
      final sourcePerformers = item.performers;
      if (sourcePerformers == null) {
        continue;
      }
      performers ??= <WorkPerformer>[];
      for (final performer in sourcePerformers) {
        final name = performer.name.trim();
        final key = name.toLowerCase();
        if (name.isNotEmpty && performerKeys.add(key)) {
          performers.add(performer);
        }
      }
    }
    final imageUris = <Uri>[];
    final imageKeys = <String>{};
    final evidenceUris = <Uri>[];
    final evidenceKeys = <String>{};
    for (final item in details) {
      for (final uri in item.imageUris) {
        if (imageKeys.add(uri.toString())) {
          imageUris.add(uri);
        }
      }
      for (final uri in item.originalImageEvidenceUris) {
        if (evidenceKeys.add(uri.toString())) {
          evidenceUris.add(uri);
        }
      }
    }
    return ScrapeWorkDetails(
      source: details.first.source,
      code: code,
      rawCode: firstText((item) => item.rawCode ?? item.code),
      title: firstText((item) => item.title) ?? code,
      releaseDate: firstText((item) => item.releaseDate),
      durationMinutes: firstInt((item) => item.durationMinutes),
      studio: firstText((item) => item.studio),
      publisher: firstText((item) => item.publisher),
      series: firstText((item) => item.series),
      performerCount: performerCount,
      performers: performers == null ? null : List.unmodifiable(performers),
      imageUris: List.unmodifiable(imageUris),
      originalImageEvidenceUris: List.unmodifiable(evidenceUris),
    );
  }

  bool _hasExactMatch(Iterable<ScrapeSourceRunResult> results) {
    return results.any(
      (result) =>
          result.error != null ||
          result.state == ScrapeSourceRunState.failed ||
          result.state == ScrapeSourceRunState.zeroResults,
    );
  }

  bool _isCancelled(WorksScrapeCancellationToken? token) =>
      token?.isCancelled ?? false;

  void _notify(
    void Function(WorksScrapeProgress progress)? callback,
    int current,
    int total,
    int saved,
    int excluded,
    int failed, {
    WorksScrapePhase phase = WorksScrapePhase.savingWorks,
    ScrapeSourceId? source,
    String? workCode,
    bool totalKnown = false,
    bool updateSourceProgress = true,
    int? sourceCurrent,
    int? sourceTotal,
    bool? sourceTotalKnown,
  }) {
    if (source != null) {
      final previous = _sourceProgress[source];
      final effectiveSourceTotal = sourceTotal ?? previous?.total ?? total;
      final effectiveSourceTotalKnown =
          sourceTotalKnown ?? previous?.totalKnown ?? totalKnown;
      final effectiveSourceCurrent = updateSourceProgress
          ? sourceCurrent ?? current
          : previous?.current ?? sourceCurrent ?? current;
      _sourceProgress[source] = WorksScrapeSourceProgress(
        phase: phase,
        current: effectiveSourceCurrent,
        total: effectiveSourceTotal,
        totalKnown: effectiveSourceTotalKnown,
        workCode: workCode,
      );
    }
    callback?.call(
      WorksScrapeProgress(
        phase: phase,
        current: current,
        total: total,
        saved: saved,
        excluded: excluded,
        failed: failed,
        totalKnown: totalKnown,
        source: source,
        workCode: workCode,
        sourceProgress: Map.unmodifiable(_sourceProgress),
        detailsSource: _detailsSource,
        worksSources: _worksSources,
      ),
    );
  }
}

final class _CollectedSource {
  const _CollectedSource({
    required this.source,
    required this.pages,
    required this.summaries,
    required this.result,
  });

  final ScrapeSource source;
  final Map<String, ScrapeActressPage> pages;
  final List<ScrapeWorkSummary> summaries;
  final ScrapeSourceRunResult result;
}

final class _SourceCollectionOutcome {
  const _SourceCollectionOutcome({this.collected, required this.result});

  final _CollectedSource? collected;
  final ScrapeSourceRunResult result;
}

final class _WorkCandidate {
  const _WorkCandidate({required this.source, required this.summary});

  final ScrapeSource source;
  final ScrapeWorkSummary summary;
}

final class _SourcePipelineOutcome {
  const _SourcePipelineOutcome({
    required this.sourceId,
    required this.result,
    this.collected,
    this.fetched = const [],
    this.failedCandidates = const [],
    this.preExcluded = 0,
    this.streamingSaves = const [],
  });

  final ScrapeSourceId sourceId;
  final _CollectedSource? collected;
  final ScrapeSourceRunResult result;
  final List<_FetchedWorkDetail> fetched;
  final List<_FailedWorkCandidate> failedCandidates;
  final int preExcluded;
  final List<Future<_StreamingWorkOutcome>> streamingSaves;
}

final class _SourceCandidateSelection {
  const _SourceCandidateSelection({
    required this.candidates,
    required this.preExcluded,
  });

  final List<_WorkCandidate> candidates;
  final int preExcluded;
}

final class _SourceDetailResolution {
  const _SourceDetailResolution({
    required this.fetched,
    required this.failedCandidates,
  });

  final List<_FetchedWorkDetail> fetched;
  final List<_FailedWorkCandidate> failedCandidates;
}

final class _FetchedWorkDetail {
  const _FetchedWorkDetail({
    required this.candidate,
    required this.sourceId,
    required this.details,
  });

  final _WorkCandidate candidate;
  final ScrapeSourceId sourceId;
  final ScrapeWorkDetails details;
}

final class _FailedWorkCandidate {
  const _FailedWorkCandidate({
    required this.candidate,
    required this.reason,
    this.error,
  });

  final _WorkCandidate candidate;
  final WorksScrapeFailureReason reason;
  final Object? error;
}

final class _DetailQueueResult {
  const _DetailQueueResult({
    this.fetched = const [],
    this.failedCandidates = const [],
  });

  final List<_FetchedWorkDetail> fetched;
  final List<_FailedWorkCandidate> failedCandidates;
}

final class _ResolvedWorkGroup {
  _ResolvedWorkGroup({
    required this.code,
    required this.details,
    required this.identityKey,
    required this.hadSourceFailure,
    required this.sourceId,
    this.failureReason,
    this.failureError,
  });

  final String code;
  final List<ScrapeWorkDetails> details;
  final String identityKey;
  ScrapeSourceId sourceId;
  bool hadSourceFailure;
  WorksScrapeFailureReason? failureReason;
  Object? failureError;
}

enum _CanonicalWorkStatus { saved, excluded, failed }

final class _CanonicalWorkOutcome {
  _CanonicalWorkOutcome({
    required this.code,
    required this.status,
    this.failure,
    Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
  }) : imageFailures = {...imageFailures};

  final String code;
  _CanonicalWorkStatus status;
  WorksScrapeFailure? failure;
  final Set<WorkImageVariant> imageFailures;
}

final class _WorkImageResult {
  const _WorkImageResult({this.path, this.failed = false});

  final String? path;
  final bool failed;
}

final class _PreparedWorkImage {
  const _PreparedWorkImage({
    required this.details,
    required this.currentCard,
    required this.currentDetail,
  });

  final ScrapeWorkDetails details;
  final String currentCard;
  final String currentDetail;
}

final class _WorkImageSaveResult {
  const _WorkImageSaveResult({required this.failedVariants});

  final Set<WorkImageVariant> failedVariants;
}

final class _StreamingWorkOutcome {
  const _StreamingWorkOutcome._({
    required this.identityKey,
    required this.code,
    required this.status,
    this.failure,
    this.imageFailures = const <WorkImageVariant>{},
    this.cancelled = false,
  });

  factory _StreamingWorkOutcome.saved({
    required String identityKey,
    required String code,
    Set<WorkImageVariant> imageFailures = const <WorkImageVariant>{},
  }) => _StreamingWorkOutcome._(
    identityKey: identityKey,
    code: code,
    status: _CanonicalWorkStatus.saved,
    imageFailures: imageFailures,
  );

  factory _StreamingWorkOutcome.excluded({
    required String identityKey,
    required String code,
  }) => _StreamingWorkOutcome._(
    identityKey: identityKey,
    code: code,
    status: _CanonicalWorkStatus.excluded,
  );

  factory _StreamingWorkOutcome.failed({
    required String identityKey,
    required String code,
    required WorksScrapeFailure failure,
  }) => _StreamingWorkOutcome._(
    identityKey: identityKey,
    code: code,
    status: _CanonicalWorkStatus.failed,
    failure: failure,
  );

  factory _StreamingWorkOutcome.cancelled({
    required String identityKey,
    required String code,
  }) => _StreamingWorkOutcome._(
    identityKey: identityKey,
    code: code,
    status: _CanonicalWorkStatus.failed,
    cancelled: true,
  );

  final String identityKey;
  final String code;
  final _CanonicalWorkStatus status;
  final WorksScrapeFailure? failure;
  final Set<WorkImageVariant> imageFailures;
  final bool cancelled;
}

final class _BoundedAsyncQueue {
  _BoundedAsyncQueue({required this.maxConcurrent}) : assert(maxConcurrent > 0);

  final int maxConcurrent;
  final Queue<Future<void> Function()> _pending = Queue();
  Completer<void>? _idleCompleter;
  int _active = 0;

  Future<T> add<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _pending.add(() async {
      try {
        completer.complete(await task());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _drain();
    return completer.future;
  }

  Future<void> waitForIdle() async {
    if (_active == 0 && _pending.isEmpty) {
      return;
    }
    final completer = _idleCompleter ??= Completer<void>();
    await completer.future;
  }

  void _drain() {
    while (_active < maxConcurrent && _pending.isNotEmpty) {
      final task = _pending.removeFirst();
      _active++;
      unawaited(
        task().whenComplete(() {
          _active--;
          if (_active == 0 && _pending.isEmpty) {
            final idle = _idleCompleter;
            _idleCompleter = null;
            idle?.complete();
          } else {
            _drain();
          }
        }),
      );
    }
  }
}

class _ScrapeCancelled implements Exception {
  const _ScrapeCancelled();
}
