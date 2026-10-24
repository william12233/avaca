import 'dart:async';

import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../controllers/software_update_controller.dart';
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
            if (controller.status == UpdateStatus.checking ||
                controller.status == UpdateStatus.downloading ||
                controller.status == UpdateStatus.verifying ||
                controller.status == UpdateStatus.handingOff) ...[
              const SizedBox(height: 12),
              _StatusMessage(controller: controller),
            ],
            if (controller.status == UpdateStatus.failed ||
                controller.status == UpdateStatus.unavailable ||
                controller.status == UpdateStatus.notSupported) ...[
              const SizedBox(height: 12),
              _StatusMessage(controller: controller),
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
  BuildContext context,
  SoftwareUpdateController controller,
  SoftwareUpdateResult result, {
  bool automatic = false,
}) async {
  final localizations = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final liveResult = controller.currentResult ?? result;
          final canUpdate =
              liveResult.hasUpdate &&
              liveResult.asset != null &&
              !controller.isBusy;
          return AlertDialog(
            title: Text(_dialogTitle(localizations, liveResult.status)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (liveResult.release != null) ...[
                  Text(
                    '${localizations.currentVersion}: '
                    '${liveResult.current.version}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${localizations.latestVersion}: '
                    '${liveResult.release!.version}',
                  ),
                  const SizedBox(height: 8),
                ],
                if (controller.isBusy)
                  _StatusMessage(controller: controller)
                else
                  Text(_dialogMessage(localizations, liveResult)),
                if (canUpdate) ...[
                  const SizedBox(height: 8),
                  Text(
                    localizations.updateDataPreserved,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: controller.isBusy
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(localizations.updateLater),
              ),
              if (canUpdate)
                FilledButton(
                  key: const ValueKey('software-update-now'),
                  onPressed: () => unawaited(
                    _startUpdate(context, dialogContext, controller),
                  ),
                  child: Text(localizations.updateNow),
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
  if (!pageContext.mounted || installResult?.started == true) {
    if (installResult?.started == true && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
    return;
  }
  if (!dialogContext.mounted) return;
  Navigator.pop(dialogContext);
  await _showInstallFailure(
    pageContext,
    controller,
    installResult?.requiresUserAction == true,
  );
}

String _dialogTitle(AppLocalizations localizations, UpdateStatus status) {
  return switch (status) {
    UpdateStatus.updateAvailable => localizations.updateAvailable,
    UpdateStatus.upToDate => localizations.upToDate,
    UpdateStatus.unavailable => localizations.updateUnavailable,
    UpdateStatus.notSupported => localizations.updateNotSupported,
    _ => localizations.updateCheckFailed,
  };
}

String _dialogMessage(
  AppLocalizations localizations,
  SoftwareUpdateResult result,
) {
  return switch (result.status) {
    UpdateStatus.updateAvailable => localizations.updateAvailable,
    UpdateStatus.upToDate => localizations.upToDate,
    UpdateStatus.unavailable => localizations.updateUnavailable,
    UpdateStatus.notSupported => localizations.updateNotSupported,
    _ => switch (result.error?.reason) {
      UpdateFailureReason.integrity => localizations.updateIntegrityFailed,
      UpdateFailureReason.assetUnavailable => localizations.updateUnavailable,
      UpdateFailureReason.notSupported => localizations.updateNotSupported,
      _ => localizations.updateCheckFailed,
    },
  };
}

Future<void> _showInstallFailure(
  BuildContext context,
  SoftwareUpdateController controller,
  bool requiresUserAction,
) {
  final localizations = AppLocalizations.of(context);
  final message = requiresUserAction
      ? localizations.updateInstallPermissionRequired
      : localizations.updateInstallerFailed;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(localizations.updateCheckFailed),
      content: Text(message),
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

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.controller});

  final SoftwareUpdateController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final message = switch (controller.status) {
      UpdateStatus.downloading => localizations.downloadingUpdate,
      UpdateStatus.checking => localizations.checkingForUpdates,
      UpdateStatus.verifying => localizations.verifyingUpdate,
      UpdateStatus.handingOff => localizations.installingUpdate,
      UpdateStatus.unavailable => localizations.updateUnavailable,
      UpdateStatus.notSupported => localizations.updateNotSupported,
      _ => localizations.updateCheckFailed,
    };
    final progress = controller.downloadProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (progress != null &&
            (controller.status == UpdateStatus.downloading ||
                controller.status == UpdateStatus.verifying)) ...[
          const SizedBox(height: 8),
          Text(_progressLabel(localizations, progress)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress.fraction),
        ],
      ],
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
