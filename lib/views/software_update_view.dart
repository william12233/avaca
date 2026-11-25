import 'dart:async';

import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../components/app_glass_components.dart';
import '../controllers/software_update_controller.dart';
import '../core/app_motion.dart';
import '../core/layout.dart';
import '../models/software_update_models.dart';

class SoftwareUpdateView extends StatefulWidget {
  const SoftwareUpdateView({
    super.key,
    required this.controller,
    this.shrinkWrap = false,
  });

  final SoftwareUpdateController controller;
  final bool shrinkWrap;

  @override
  State<SoftwareUpdateView> createState() => _SoftwareUpdateViewState();
}

class _SoftwareUpdateViewState extends State<SoftwareUpdateView> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.currentVersion == null) {
      unawaited(widget.controller.initialize());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final localizations = AppLocalizations.of(context);
        final controller = widget.controller;
        final failure = controller.status == UpdateStatus.failed
            ? _failureDescription(localizations, controller.error)
            : null;
        final current = controller.currentVersion?.version ?? '—';
        final latest = controller.latestRelease?.version.toString() ?? '—';
        final tokens = AppLayoutPolicy.resolve(
          BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width),
        );

        return ListView(
          key: const PageStorageKey('software-update-settings-scroll'),
          padding: EdgeInsets.zero,
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          children: [
            _VersionRow(label: localizations.currentVersion, value: current),
            const SizedBox(height: 8),
            _VersionRow(label: localizations.latestVersion, value: latest),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              minTileHeight: tokens.controlHeight,
              minVerticalPadding: 0,
              title: Text(localizations.autoCheckUpdates),
              value: controller.autoCheckUpdates,
              onChanged: controller.isBusy
                  ? null
                  : controller.setAutoCheckUpdates,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('software-update-check'),
                onPressed: controller.isBusy ? null : _checkForUpdates,
                style: TextButton.styleFrom(
                  minimumSize: Size(0, tokens.controlHeight),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(localizations.checkForUpdates),
              ),
            ),
            if ((ModalRoute.isCurrentOf(context) ?? true) &&
                (controller.isBusy ||
                    controller.status == UpdateStatus.failed ||
                    controller.status == UpdateStatus.unavailable ||
                    controller.status == UpdateStatus.notSupported)) ...[
              const SizedBox(height: 12),
              Text(
                _statusTitle(
                  localizations,
                  controller.status,
                  failure: failure,
                ),
              ),
              if (controller.status == UpdateStatus.downloading) ...[
                const SizedBox(height: 8),
                _DownloadProgressView(progress: controller.downloadProgress),
              ],
              if (failure != null) ...[
                const SizedBox(height: 8),
                Text(failure),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdates() async {
    final result = await widget.controller.check();
    if (!mounted) return;
    await showSoftwareUpdateDialog(context, widget.controller, result);
  }
}

Future<void> showSoftwareUpdateDialog(
  BuildContext hostContext,
  SoftwareUpdateController controller,
  SoftwareUpdateResult result, {
  bool automatic = false,
}) async {
  await showDialog<void>(
    context: hostContext,
    animationStyle: AppMotion.instantIfReduced(hostContext),
    builder: (dialogContext) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final l10n = AppLocalizations.of(context);
          final liveResult = controller.currentResult ?? result;
          final status = controller.status == UpdateStatus.idle
              ? liveResult.status
              : controller.status;
          final canUpdate =
              status == UpdateStatus.updateAvailable &&
              liveResult.asset != null;
          final failure = status == UpdateStatus.failed
              ? _failureDescription(l10n, controller.error ?? liveResult.error)
              : null;
          final release = liveResult.release;
          final content = switch (status) {
            UpdateStatus.downloading => _DownloadProgressView(
              progress: controller.downloadProgress,
            ),
            UpdateStatus.updateAvailable ||
            UpdateStatus.upToDate ||
            UpdateStatus.unavailable when release != null => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                _VersionRow(
                  label: l10n.currentVersion,
                  value: liveResult.current.version,
                ),
                _VersionRow(
                  label: l10n.latestVersion,
                  value: release.version.toString(),
                ),
                if (canUpdate)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.updateDataPreserved,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            _ when failure != null => Text(failure),
            _ => null,
          };
          return appAlertDialog(
            context,
            scrollable: true,
            title: Text(_statusTitle(l10n, status, failure: failure)),
            content: content,
            actions: [
              TextButton(
                onPressed: controller.isBusy
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(l10n.updateLater),
              ),
              if (canUpdate)
                FilledButton(
                  key: const ValueKey('software-update-now'),
                  onPressed: () => unawaited(
                    _startUpdate(hostContext, dialogContext, controller),
                  ),
                  child: Text(l10n.updateNow),
                ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _startUpdate(
  BuildContext pageContext,
  BuildContext dialogContext,
  SoftwareUpdateController controller,
) async {
  final installResult = await controller.update();
  if (!dialogContext.mounted) return;
  if (installResult?.started == true) {
    Navigator.pop(dialogContext);
  } else if (pageContext.mounted && installResult?.requiresUserAction == true) {
    Navigator.pop(dialogContext);
    await _showInstallPermission(pageContext);
  }
}

String _statusTitle(
  AppLocalizations l10n,
  UpdateStatus status, {
  String? failure,
}) => switch (status) {
  UpdateStatus.updateAvailable => l10n.updateAvailable,
  UpdateStatus.upToDate => l10n.upToDate,
  UpdateStatus.unavailable => l10n.updateUnavailable,
  UpdateStatus.notSupported => l10n.updateNotSupported,
  UpdateStatus.checking => l10n.checkingForUpdates,
  UpdateStatus.downloading => l10n.downloadingUpdate,
  UpdateStatus.verifying => l10n.verifyingUpdate,
  UpdateStatus.handingOff => l10n.installingUpdate,
  UpdateStatus.failed when failure != null => l10n.updateFailed,
  _ => l10n.updateCheckFailed,
};

String? _failureDescription(
  AppLocalizations l10n,
  SoftwareUpdateException? error,
) => switch (error?.reason) {
  UpdateFailureReason.download => l10n.updateDownloadFailed,
  UpdateFailureReason.integrity => l10n.updateIntegrityFailed,
  UpdateFailureReason.assetUnavailable => l10n.updateUnavailable,
  UpdateFailureReason.installer => l10n.updateInstallerFailed,
  _ => null,
};

Future<void> _showInstallPermission(BuildContext context) {
  final localizations = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    animationStyle: AppMotion.instantIfReduced(context),
    builder: (dialogContext) => appAlertDialog(
      dialogContext,
      title: Text(localizations.updateFailed),
      content: Text(localizations.updateInstallPermissionRequired),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(localizations.updateLater),
        ),
      ],
    ),
  );
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _DownloadProgressView extends StatelessWidget {
  const _DownloadProgressView({required this.progress});

  final DownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = progress ?? const DownloadProgress(receivedBytes: 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(_progressLabel(l10n, value)),
        _DownloadProgressIndicator(progress: value, localizations: l10n),
      ],
    );
  }
}

class _DownloadProgressIndicator extends StatelessWidget {
  const _DownloadProgressIndicator({
    required this.progress,
    required this.localizations,
  });

  final DownloadProgress progress;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fraction = progress.fraction;

    LinearProgressIndicator indicator(double? value) {
      return LinearProgressIndicator(
        key: const ValueKey('software-update-progress-indicator'),
        value: value,
        minHeight: 6,
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        semanticsLabel: localizations.updateProgressIndicator,
      );
    }

    if (fraction == null) {
      return TickerMode(
        enabled: AppMotion.enabledOf(context),
        child: indicator(null),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: fraction),
      duration: AppMotion.duration(context, const Duration(milliseconds: 120)),
      curve: Curves.linear,
      builder: (context, value, child) => indicator(value),
    );
  }
}

String _progressLabel(
  AppLocalizations localizations,
  DownloadProgress progress,
) {
  final received = _formatBytes(progress.receivedBytes);
  final total = progress.totalBytes;
  if (total == null || total <= 0) {
    return localizations.updateDownloadProgressUnknownTotal(received);
  }
  return localizations.updateDownloadProgress(
    progress.percentage ?? 0,
    received,
    _formatBytes(total),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  final mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(1)} MB';
  return '${(mib / 1024).toStringAsFixed(1)} GB';
}
