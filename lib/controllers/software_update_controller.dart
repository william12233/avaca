import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/database.dart';
import '../models/software_update_models.dart';
import '../services/software_update_installer.dart';
import '../services/software_update_preferences.dart';
import '../services/software_update_service.dart';

class SoftwareUpdateController extends ChangeNotifier {
  SoftwareUpdateController({
    required SoftwareUpdateService service,
    required SoftwareUpdateInstaller installer,
    SoftwareUpdatePreferences? preferences,
    bool disposeService = true,
  }) : _service = service,
       _installer = installer,
       _preferences = preferences ?? SoftwareUpdatePreferences(),
       _disposeService = disposeService;

  factory SoftwareUpdateController.forApp({required AppDatabase db}) {
    final service = SoftwareUpdateService();
    return SoftwareUpdateController(
      service: service,
      installer: SoftwareUpdateInstaller.forCurrentPlatform(
        onBeforeWindowsUpdate: db.close,
      ),
    );
  }

  final SoftwareUpdateService _service;
  final SoftwareUpdateInstaller _installer;
  final SoftwareUpdatePreferences _preferences;
  final bool _disposeService;

  UpdateStatus status = UpdateStatus.idle;
  AppVersionInfo? currentVersion;
  SoftwareRelease? latestRelease;
  ReleaseAsset? latestAsset;
  SoftwareUpdateException? error;
  DownloadProgress? downloadProgress;
  bool autoCheckUpdates = true;

  Future<SoftwareUpdateResult>? _checkFuture;
  Future<SoftwareInstallResult?>? _installFuture;
  SoftwareUpdateResult? _lastResult;
  Timer? _progressNotificationTimer;

  static const _progressNotificationInterval = Duration(milliseconds: 100);

  SoftwareUpdateResult? get currentResult => _lastResult;

  bool get isBusy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.verifying ||
      status == UpdateStatus.handingOff;

  Future<void> initialize() async {
    autoCheckUpdates = await _preferences.autoCheckUpdates();
    try {
      currentVersion = await _service.currentVersion();
    } catch (error) {
      this.error = SoftwareUpdateException(
        UpdateFailureReason.invalidMetadata,
        error.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> setAutoCheckUpdates(bool value) async {
    autoCheckUpdates = value;
    notifyListeners();
    await _preferences.setAutoCheckUpdates(value);
  }

  Future<SoftwareUpdateResult> check({bool automatic = false}) async {
    final existing = _checkFuture;
    if (existing != null) return existing;

    if (status == UpdateStatus.downloading ||
        status == UpdateStatus.verifying ||
        status == UpdateStatus.handingOff) {
      return _lastResult ??
          SoftwareUpdateResult(
            status: status,
            current: currentVersion ?? _fallbackVersion,
          );
    }

    final future = _performCheck();
    _checkFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_checkFuture, future)) _checkFuture = null;
    }
  }

  Future<SoftwareInstallResult?> update() async {
    final existing = _installFuture;
    if (existing != null) return existing;
    final result = _lastResult;
    if (result == null || !result.hasUpdate) return null;

    final future = _performUpdate(result);
    _installFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_installFuture, future)) _installFuture = null;
    }
  }

  @override
  void dispose() {
    _progressNotificationTimer?.cancel();
    _progressNotificationTimer = null;
    if (_disposeService) _service.dispose();
    super.dispose();
  }

  Future<SoftwareUpdateResult> _performCheck() async {
    status = UpdateStatus.checking;
    error = null;
    notifyListeners();

    try {
      final result = await _service.checkForUpdates();
      currentVersion = result.current;
      latestRelease = result.release;
      latestAsset = result.asset;
      status = result.status;
      error = result.error;
      _lastResult = result;
      notifyListeners();
      return result;
    } on SoftwareUpdateException catch (exception) {
      return _setCheckError(exception);
    } on Object catch (exception) {
      return _setCheckError(
        SoftwareUpdateException(
          UpdateFailureReason.network,
          exception.toString(),
        ),
      );
    }
  }

  Future<SoftwareUpdateResult> _setCheckError(
    SoftwareUpdateException exception,
  ) async {
    currentVersion ??= await _loadCurrentOrFallback();
    status = UpdateStatus.failed;
    error = exception;
    final result = SoftwareUpdateResult(
      status: status,
      current: currentVersion!,
      error: exception,
    );
    _lastResult = result;
    notifyListeners();
    return result;
  }

  Future<SoftwareInstallResult?> _performUpdate(
    SoftwareUpdateResult result,
  ) async {
    status = UpdateStatus.downloading;
    error = null;
    downloadProgress = DownloadProgress(
      receivedBytes: 0,
      totalBytes: result.asset?.size,
    );
    _progressNotificationTimer?.cancel();
    _progressNotificationTimer = null;
    notifyListeners();

    try {
      final downloaded = await _service.download(
        result,
        onProgress: _publishDownloadProgress,
      );
      _cancelProgressNotification();
      status = UpdateStatus.verifying;
      notifyListeners();

      status = UpdateStatus.handingOff;
      notifyListeners();
      final installResult = await _installer.install(downloaded);
      if (!installResult.started) {
        if (installResult.requiresUserAction) {
          status = UpdateStatus.idle;
          notifyListeners();
          return installResult;
        }
        throw SoftwareUpdateException(
          UpdateFailureReason.installer,
          installResult.message ?? 'The platform installer did not start.',
        );
      }
      status = UpdateStatus.idle;
      notifyListeners();
      return installResult;
    } on SoftwareUpdateException catch (exception) {
      _cancelProgressNotification();
      status = UpdateStatus.failed;
      error = exception;
      notifyListeners();
      return const SoftwareInstallResult(started: false);
    } on Object catch (exception) {
      _cancelProgressNotification();
      status = UpdateStatus.failed;
      error = SoftwareUpdateException(
        UpdateFailureReason.installer,
        exception.toString(),
      );
      notifyListeners();
      return const SoftwareInstallResult(started: false);
    }
  }

  void _publishDownloadProgress(DownloadProgress progress) {
    downloadProgress = progress;
    final isFinal =
        progress.hasTotal && progress.receivedBytes >= progress.totalBytes!;
    if (isFinal) {
      _cancelProgressNotification();
      notifyListeners();
      return;
    }

    if (_progressNotificationTimer != null) return;
    _progressNotificationTimer = Timer(_progressNotificationInterval, () {
      _progressNotificationTimer = null;
      if (status == UpdateStatus.downloading) notifyListeners();
    });
  }

  void _cancelProgressNotification() {
    _progressNotificationTimer?.cancel();
    _progressNotificationTimer = null;
  }

  Future<AppVersionInfo> _loadCurrentOrFallback() async {
    try {
      return await _service.currentVersion();
    } catch (_) {
      return _fallbackVersion;
    }
  }

  AppVersionInfo get _fallbackVersion => const AppVersionInfo(
    version: '0.0.0',
    buildNumber: '',
    platform: SoftwareUpdatePlatform.unsupported,
    architecture: 'unknown',
  );
}
