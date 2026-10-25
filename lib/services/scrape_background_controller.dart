import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/platform_adapter.dart';
import '../l10n/app_localizations.dart';
import '../models/scrape_job.dart';
import 'scrape_job_coordinator.dart';

/// The progress representation used by the Android notification.
///
/// A job does not always know its total work count. In those phases the
/// notification intentionally uses an indeterminate progress bar instead of
/// presenting a misleading percentage.
class ScrapeNotificationProgress {
  const ScrapeNotificationProgress({this.percent});

  final int? percent;

  bool get indeterminate => percent == null;
}

ScrapeNotificationProgress scrapeNotificationProgressFor(ScrapeJob job) {
  final percent = switch (job.phase) {
    ScrapeJobPhase.fetchingDetails ||
    ScrapeJobPhase.resolvingWorks => _scrapeNotificationPercent(
      current: job.detailCompletedCount,
      total: job.detailTotalCount,
    ),
    ScrapeJobPhase.savingWorks => _scrapeNotificationPercent(
      current: job.processedCount,
      total: job.discoveredCount,
    ),
    _ => null,
  };
  return ScrapeNotificationProgress(percent: percent);
}

int? _scrapeNotificationPercent({required int current, required int total}) {
  if (total <= 0) return null;
  final safeCurrent = math.min(math.max(current, 0), total);
  return math.min(100, safeCurrent * 100 ~/ total);
}

class ScrapeNotificationPayload {
  const ScrapeNotificationPayload({
    required this.jobId,
    required this.title,
    required this.body,
    required this.progress,
  });

  final String jobId;
  final String title;
  final String body;
  final ScrapeNotificationProgress progress;

  Map<String, Object?> toArguments() => {
    'jobId': jobId,
    'title': title,
    'body': body,
    'progress': progress.percent ?? 0,
    'indeterminate': progress.indeterminate,
  };

  @override
  bool operator ==(Object other) {
    return other is ScrapeNotificationPayload &&
        other.jobId == jobId &&
        other.title == title &&
        other.body == body &&
        other.progress.percent == progress.percent;
  }

  @override
  int get hashCode => Object.hash(jobId, title, body, progress.percent);
}

abstract interface class ScrapeBackgroundHost {
  Stream<String> get notificationTaps;

  Future<void> requestNotificationPermission();

  Future<void> start(ScrapeNotificationPayload payload);

  Future<void> update(ScrapeNotificationPayload payload);

  Future<void> stop();

  Future<void> showVerificationNotification(ScrapeNotificationPayload payload);

  Future<String?> consumePendingJobId();

  Future<void> dispose();
}

class AndroidScrapeBackgroundHost implements ScrapeBackgroundHost {
  AndroidScrapeBackgroundHost({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.avaca.avaca/scrape_background') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get notificationTaps => _notificationTapController.stream;

  @override
  Future<void> requestNotificationPermission() async {
    await _channel.invokeMethod<void>('requestNotificationPermission');
  }

  @override
  Future<void> start(ScrapeNotificationPayload payload) async {
    await _channel.invokeMethod<void>('startForeground', payload.toArguments());
  }

  @override
  Future<void> update(ScrapeNotificationPayload payload) async {
    await _channel.invokeMethod<void>(
      'updateForeground',
      payload.toArguments(),
    );
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod<void>('stopForeground');
  }

  @override
  Future<void> showVerificationNotification(
    ScrapeNotificationPayload payload,
  ) async {
    await _channel.invokeMethod<void>(
      'showVerificationNotification',
      payload.toArguments(),
    );
  }

  @override
  Future<String?> consumePendingJobId() {
    return _channel.invokeMethod<String>('consumePendingJobId');
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'notificationTap') {
      throw MissingPluginException('Unknown scrape background method');
    }
    final jobId = call.arguments?.toString().trim();
    if (jobId != null && jobId.isNotEmpty) {
      _notificationTapController.add(jobId);
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _notificationTapController.close();
  }
}

class NoopScrapeBackgroundHost implements ScrapeBackgroundHost {
  const NoopScrapeBackgroundHost();

  @override
  Stream<String> get notificationTaps => const Stream<String>.empty();

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Future<void> start(ScrapeNotificationPayload payload) async {}

  @override
  Future<void> update(ScrapeNotificationPayload payload) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> showVerificationNotification(
    ScrapeNotificationPayload payload,
  ) async {}

  @override
  Future<String?> consumePendingJobId() async => null;

  @override
  Future<void> dispose() async {}
}

ScrapeBackgroundHost createScrapeBackgroundHost() {
  if (PlatformAdapter.isAndroid) {
    return AndroidScrapeBackgroundHost();
  }
  return const NoopScrapeBackgroundHost();
}

class ScrapeBackgroundController {
  ScrapeBackgroundController({
    required this.coordinator,
    this.host,
    this.onNotificationTap,
  }) : _host = host ?? createScrapeBackgroundHost(),
       _localizations = _localizationsFor(null);

  final ScrapeJobCoordinator coordinator;
  final ScrapeBackgroundHost? host;
  final void Function(String jobId)? onNotificationTap;

  late final ScrapeBackgroundHost _host;
  AppLocalizations _localizations;
  Timer? _syncTimer;
  StreamSubscription<String>? _notificationTapSubscription;
  ScrapeNotificationPayload? _lastPayload;
  String? _lastVerificationJobId;
  bool _foregroundActive = false;
  bool _permissionRequested = false;
  bool _attached = false;
  bool _syncInFlight = false;
  bool _syncRequested = false;
  bool _disposed = false;

  static AppLocalizations _localizationsFor(Locale? locale) {
    final candidate = locale ?? ui.PlatformDispatcher.instance.locale;
    try {
      return lookupAppLocalizations(candidate);
    } on FlutterError {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    coordinator.addListener(_handleCoordinatorChanged);
    _notificationTapSubscription = _host.notificationTaps.listen(
      _handleNotificationTap,
    );
    unawaited(_consumePendingJobId());
    unawaited(synchronize());
  }

  void setLocale(Locale? locale) {
    if (_disposed) return;
    final next = _localizationsFor(locale);
    if (next.localeName == _localizations.localeName) return;
    _localizations = next;
    if (_attached) _scheduleSync();
  }

  Future<void> synchronize() async {
    if (_disposed) return;
    if (_syncInFlight) {
      _syncRequested = true;
      return;
    }

    _syncInFlight = true;
    try {
      do {
        _syncRequested = false;
        await _synchronizeOnce();
      } while (_syncRequested && !_disposed);
    } on Object catch (error) {
      debugPrint('Scrape background synchronization failed: $error');
    } finally {
      _syncInFlight = false;
    }
  }

  void _handleCoordinatorChanged() {
    // The first start must happen as soon as a job is enqueued while the
    // activity is still visible. Subsequent progress updates can be batched.
    if (!_foregroundActive) {
      unawaited(synchronize());
      return;
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_disposed || _syncTimer != null) return;
    _syncTimer = Timer(const Duration(milliseconds: 250), () {
      _syncTimer = null;
      unawaited(synchronize());
    });
  }

  Future<void> _consumePendingJobId() async {
    try {
      final jobId = await _host.consumePendingJobId();
      if (jobId != null && jobId.trim().isNotEmpty) {
        _handleNotificationTap(jobId.trim());
      }
    } on Object catch (error) {
      debugPrint('Scrape notification intent read failed: $error');
    }
  }

  void _handleNotificationTap(String jobId) {
    onNotificationTap?.call(jobId);
  }

  Future<void> _synchronizeOnce() async {
    final jobs = await coordinator.listJobs();
    final runnable = _selectRunnableJob(jobs);
    if (runnable != null) {
      _lastVerificationJobId = null;
      final payload = _payloadFor(runnable);
      if (!_permissionRequested) {
        _permissionRequested = true;
        try {
          await _host.requestNotificationPermission();
        } on Object catch (error) {
          debugPrint('Scrape notification permission request failed: $error');
        }
      }

      if (!_foregroundActive) {
        try {
          await _host.start(payload);
          _foregroundActive = true;
          _lastPayload = payload;
        } on Object catch (error) {
          debugPrint('Scrape foreground service start failed: $error');
        }
      } else if (_lastPayload != payload) {
        try {
          await _host.update(payload);
          _lastPayload = payload;
        } on Object catch (error) {
          debugPrint('Scrape foreground notification update failed: $error');
        }
      }
      return;
    }

    await _stopForeground();

    final waiting = _firstJobWithState(
      jobs,
      ScrapeJobState.waitingForVerification,
    );
    if (waiting == null) {
      _lastVerificationJobId = null;
      return;
    }
    if (_lastVerificationJobId == waiting.id) return;

    final payload = _verificationPayloadFor(waiting);
    try {
      await _host.showVerificationNotification(payload);
      _lastVerificationJobId = waiting.id;
    } on Object catch (error) {
      debugPrint('Scrape verification notification failed: $error');
    }
  }

  Future<void> _stopForeground() async {
    if (!_foregroundActive) return;
    try {
      await _host.stop();
    } on Object catch (error) {
      debugPrint('Scrape foreground service stop failed: $error');
    } finally {
      _foregroundActive = false;
      _lastPayload = null;
    }
  }

  ScrapeJob? _selectRunnableJob(List<ScrapeJob> jobs) {
    for (final job in jobs) {
      if (job.state == ScrapeJobState.running) return job;
    }

    final queued = jobs
        .where((job) => job.state == ScrapeJobState.queued)
        .toList(growable: false);
    if (queued.isEmpty) return null;
    return queued.reduce((first, second) {
      final firstCreated =
          first.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final secondCreated =
          second.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return firstCreated.isBefore(secondCreated) ? first : second;
    });
  }

  ScrapeJob? _firstJobWithState(List<ScrapeJob> jobs, ScrapeJobState state) {
    for (final job in jobs) {
      if (job.state == state) return job;
    }
    return null;
  }

  ScrapeNotificationPayload _payloadFor(ScrapeJob job) {
    return ScrapeNotificationPayload(
      jobId: job.id,
      title: _localizations.scrapeSyncingTitle,
      body: _progressBody(job),
      progress: scrapeNotificationProgressFor(job),
    );
  }

  ScrapeNotificationPayload _verificationPayloadFor(ScrapeJob job) {
    return ScrapeNotificationPayload(
      jobId: job.id,
      title: _localizations.scrapeSourceVerificationRequired,
      body:
          '${job.actressNameSnapshot} · ${_localizations.scrapeJobStateWaiting}',
      progress: const ScrapeNotificationProgress(),
    );
  }

  String _progressBody(ScrapeJob job) {
    final name = job.actressNameSnapshot.trim();
    final phase = switch (job.phase) {
      ScrapeJobPhase.queued => _localizations.scrapeJobStateQueued,
      ScrapeJobPhase.collectingSources =>
        '${_localizations.scrapePhaseCollecting} · '
            '${_localizations.scrapeJobCandidateSummary(job.discoveredCount, job.duplicateCount)}',
      ScrapeJobPhase.syncingActress => _localizations.scrapePhaseSyncingActress,
      ScrapeJobPhase.fetchingDetails =>
        '${_localizations.scrapePhaseFetchingDetails} · '
            '${_localizations.scrapeJobDetailProgress(job.detailCompletedCount, job.detailTotalCount)}',
      ScrapeJobPhase.resolvingWorks =>
        '${_localizations.scrapePhaseResolvingWorks} · '
            '${_localizations.scrapeJobDetailProgress(job.detailCompletedCount, job.detailTotalCount)}',
      ScrapeJobPhase.savingWorks =>
        '${_localizations.scrapePhaseSavingWorks} · '
            '${_localizations.scrapeJobOutcomeSummary(job.processedCount, job.discoveredCount, math.max(0, job.savedCount - job.reviewCount), job.reviewCount, job.excludedCount, job.failedCount)}',
      ScrapeJobPhase.downloadingImages => _localizations.scrapeImagesLabel,
      ScrapeJobPhase.completed => _localizations.scrapePhaseCompleted,
    };
    return name.isEmpty ? phase : '$name · $phase';
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _syncTimer?.cancel();
    _syncTimer = null;
    if (_attached) coordinator.removeListener(_handleCoordinatorChanged);
    unawaited(_notificationTapSubscription?.cancel());
    _notificationTapSubscription = null;
    unawaited(_host.dispose());
  }
}
