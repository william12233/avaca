import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../components/adaptive_page_layout.dart';
import '../components/javbus_verification_dialog.dart';
import '../controllers/data_transfer_controller.dart';
import '../controllers/prefix_route_file_transfer.dart';
import '../controllers/settings_controller.dart';
import '../controllers/software_update_controller.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../models/data_transfer_models.dart';
import '../models/scrape_exclusion_policy.dart';
import '../models/scrape_source_settings.dart';
import '../models/work_scrape_options.dart';
import '../services/data_transfer_service.dart';
import '../services/scrape_job_coordinator.dart';
import '../services/avbase/avbase_client.dart';
import '../services/avbase/avbase_transport.dart';
import '../services/avwiki/avwiki_client.dart';
import '../services/avwiki/avwiki_transport.dart';
import '../services/javbus/javbus_client.dart';
import '../services/javbus/javbus_verification.dart';
import '../services/javbus/prefix_route_repository.dart';
import '../services/minnano/minnano_client.dart';
import '../services/minnano/minnano_transport.dart';
import '../services/scrape/scrape_source_registry.dart';
import 'software_update_view.dart';
import 'prefix_route_rules_view.dart';
import 'data_health_view.dart';
import 'scrape_jobs_view.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);
typedef ScrapeSourceConnectionTester =
    Future<void> Function(ScrapeSourceId source);

enum _ScrapeSourceConnectionStatus {
  notTested,
  testing,
  connected,
  failed,
  verificationRequired,
}

Future<bool> _launchExternalUrl(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _SettingsInteractionTheme extends StatelessWidget {
  const _SettingsInteractionTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final overlayColor = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.focused)) {
        return base.colorScheme.primary.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return base.colorScheme.primary.withValues(alpha: 0.08);
      }
      return null;
    });

    return Theme(
      data: base.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        textButtonTheme: TextButtonThemeData(
          style:
              base.textButtonTheme.style?.copyWith(
                overlayColor: overlayColor,
              ) ??
              ButtonStyle(overlayColor: overlayColor),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style:
              base.filledButtonTheme.style?.copyWith(
                overlayColor: overlayColor,
              ) ??
              ButtonStyle(overlayColor: overlayColor),
        ),
        iconButtonTheme: IconButtonThemeData(
          style:
              base.iconButtonTheme.style?.copyWith(
                overlayColor: overlayColor,
              ) ??
              ButtonStyle(overlayColor: overlayColor),
        ),
        radioTheme: base.radioTheme.copyWith(overlayColor: overlayColor),
        switchTheme: base.switchTheme.copyWith(overlayColor: overlayColor),
      ),
      child: child,
    );
  }
}

class _SettingsTapFeedback extends StatefulWidget {
  const _SettingsTapFeedback({required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<_SettingsTapFeedback> createState() => _SettingsTapFeedbackState();
}

class _SettingsTapFeedbackState extends State<_SettingsTapFeedback> {
  static const double _dotSize = 12;
  static const Duration _fadeDuration = Duration(milliseconds: 120);

  Timer? _removalTimer;
  Offset? _position;
  bool _visible = false;

  @override
  void dispose() {
    _removalTimer?.cancel();
    super.dispose();
  }

  void _show(PointerDownEvent event) {
    _removalTimer?.cancel();
    setState(() {
      _position = event.localPosition;
      _visible = true;
    });
  }

  void _hide(PointerEvent event) {
    if (_position == null) return;

    setState(() => _visible = false);
    _removalTimer?.cancel();
    _removalTimer = Timer(_fadeDuration, () {
      if (!mounted) return;
      setState(() => _position = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;

    return Listener(
      onPointerDown: _show,
      onPointerUp: _hide,
      onPointerCancel: _hide,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          widget.child,
          if (position != null)
            Positioned(
              left: position.dx - (_dotSize / 2),
              top: position.dy - (_dotSize / 2),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: _fadeDuration,
                  curve: Curves.easeOut,
                  child: SizedBox.square(
                    dimension: _dotSize,
                    child: DecoratedBox(
                      key: ValueKey('settings-feedback-dot-${widget.id}'),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.28),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.db,
    required this.onThemeChanged,
    required this.onLocaleChanged,
    this.transferController,
    this.softwareUpdateController,
    this.prefixRouteFilePicker,
    this.externalUrlLauncher = _launchExternalUrl,
    this.scrapeSourceConnectionTester,
    this.scrapeJobCoordinator,
  });

  final AppDatabase db;
  final void Function(
    ThemeMode themeMode,
    bool isPureBlack,
    Map<String, Color>? customColors,
  )
  onThemeChanged;
  final void Function(Locale? locale) onLocaleChanged;
  final DataTransferController? transferController;
  final SoftwareUpdateController? softwareUpdateController;
  final PrefixRouteFilePicker? prefixRouteFilePicker;
  final ExternalUrlLauncher externalUrlLauncher;
  final ScrapeSourceConnectionTester? scrapeSourceConnectionTester;
  final ScrapeJobCoordinator? scrapeJobCoordinator;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const double _settingsCardRadius = 12;
  static final Uri _githubUri = Uri.parse(
    'https://github.com/william12233/avaca',
  );
  static final Uri _issuesUri = Uri.parse(
    'https://github.com/william12233/avaca/issues',
  );
  static const AnimationStyle _expansionAnimationStyle = AnimationStyle(
    duration: Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  late final SettingsController controller;
  late final DataTransferController dataTransferController;
  late final bool _ownsDataTransferController;
  late final SoftwareUpdateController updateController;
  late final bool _ownsSoftwareUpdateController;

  @override
  void initState() {
    super.initState();
    controller = SettingsController(db: widget.db);
    _ownsDataTransferController = widget.transferController == null;
    dataTransferController =
        widget.transferController ??
        DataTransferController(service: DataTransferService(db: widget.db));
    _ownsSoftwareUpdateController = widget.softwareUpdateController == null;
    updateController =
        widget.softwareUpdateController ??
        SoftwareUpdateController.forApp(db: widget.db);
    // 載入目前儲存的外觀設定
    controller.loadFromPrefs();
    controller.loadCustomTheme();
    // 監聽設定變更並同步更新畫面
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    if (_ownsDataTransferController) dataTransferController.dispose();
    if (_ownsSoftwareUpdateController) updateController.dispose();
    super.dispose();
  }

  // 將 controller 的外觀與語言狀態同步給外層，並重建目前畫面
  void _onControllerChanged() {
    if (!mounted) return;
    widget.onThemeChanged(
      controller.themeMode,
      controller.isPureBlack,
      controller.isCustomTheme ? controller.customColors : null,
    );
    widget.onLocaleChanged(controller.appLocale);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsInteractionTheme(
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).settings),
          leading: _SettingsTapFeedback(
            id: 'settings-back',
            child: AlignedAppBarBackButton(
              expandToToolbar: true,
              verticalOffset: 0,
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        body: AdaptivePageLayout(
          padding: EdgeInsets.zero,
          compactBuilder: (context, tokens) => _buildSettingsCategories(tokens),
          expandedBuilder: (context, tokens) =>
              _buildSettingsCategories(tokens),
        ),
      ),
    );
  }

  Widget _buildSettingsCategories(AppLayoutTokens tokens) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tokens.isCompact
              ? double.infinity
              : tokens.settingsShortContentMaxWidth,
        ),
        child: ListView(
          padding: tokens.pagePadding,
          children: [
            _categoryCard(
              tokens: tokens,
              feedbackId: 'category-theme-colors',
              icon: Icons.palette_outlined,
              title: AppLocalizations.of(context).themeAndColors,
              onTap: () => _openCategory(
                titleBuilder: (context) =>
                    AppLocalizations.of(context).themeAndColors,
                bodyBuilder: _buildThemeAndColors,
              ),
            ),
            const SizedBox(height: 8),
            _categoryCard(
              tokens: tokens,
              feedbackId: 'category-interface',
              icon: Icons.language,
              title: AppLocalizations.of(context).interfaceSettings,
              onTap: () => _openCategory(
                titleBuilder: (context) =>
                    AppLocalizations.of(context).interfaceSettings,
                bodyBuilder: _buildInterfaceSettings,
              ),
            ),
            const SizedBox(height: 8),
            _categoryCard(
              tokens: tokens,
              feedbackId: 'category-scrape',
              icon: Icons.manage_search_outlined,
              title: AppLocalizations.of(context).scrapeSettings,
              onTap: () => _openCategory(
                titleBuilder: (context) =>
                    AppLocalizations.of(context).scrapeSettings,
                bodyBuilder: _buildScrapeSettings,
              ),
            ),
            const SizedBox(height: 8),
            _categoryCard(
              tokens: tokens,
              feedbackId: 'category-data-transfer',
              icon: Icons.import_export,
              title: AppLocalizations.of(context).settingsDataTransferTitle,
              onTap: () => _openCategory(
                titleBuilder: (context) =>
                    AppLocalizations.of(context).settingsDataTransferTitle,
                bodyBuilder: _buildDataTransferSettings,
              ),
            ),
            const SizedBox(height: 8),
            _categoryCard(
              tokens: tokens,
              feedbackId: 'category-data-health',
              icon: Icons.monitor_heart_outlined,
              title: AppLocalizations.of(context).settingsDataHealthTitle,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => DataHealthView(db: widget.db),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _categoryCard(
              tokens: tokens,
              feedbackId: 'category-other',
              icon: Icons.more_horiz,
              title: AppLocalizations.of(context).otherSettings,
              onTap: () => _openCategory(
                titleBuilder: (context) =>
                    AppLocalizations.of(context).otherSettings,
                bodyBuilder: _buildOtherSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard({
    required AppLayoutTokens tokens,
    required String feedbackId,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return _SettingsTapFeedback(
      id: feedbackId,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: _settingsCardShape(),
        child: ListTile(leading: Icon(icon), title: Text(title), onTap: onTap),
      ),
    );
  }

  RoundedRectangleBorder _settingsCardShape({
    double radius = _settingsCardRadius,
  }) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  }

  RoundedRectangleBorder _outlinedCardShape(
    BuildContext context, {
    double radius = _settingsCardRadius,
  }) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(width: 1, color: Theme.of(context).colorScheme.outline),
    );
  }

  Future<void> _openCategory({
    required String Function(BuildContext context) titleBuilder,
    required Widget Function(BuildContext context) bodyBuilder,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SettingsCategoryPage(
          controller: controller,
          titleBuilder: titleBuilder,
          bodyBuilder: bodyBuilder,
        ),
      ),
    );
  }

  Widget _buildThemeAndColors(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [_themeModeSelector(context)],
    );
  }

  Widget _buildInterfaceSettings(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _languageSelector(context),
        const SizedBox(height: 12),
        _worksPageSizeSelector(context),
      ],
    );
  }

  Widget _buildDataTransferSettings(BuildContext context) {
    return ListenableBuilder(
      listenable: dataTransferController,
      builder: (context, _) {
        final localizations = AppLocalizations.of(context);
        final isBusy = dataTransferController.isBusy;
        final progressText = switch (dataTransferController.phase) {
          DataTransferPhase.preparing => localizations.dataTransferPreparing,
          DataTransferPhase.reviewingDuplicates =>
            localizations.dataTransferDuplicateProgress,
          DataTransferPhase.writing => localizations.dataTransferWriting,
          _ => null,
        };
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Text(
              localizations.settingsDataTransferSubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _settingsActionCard(
              context: context,
              feedbackId: 'data-transfer-export',
              icon: Icons.file_upload_outlined,
              title: localizations.dataTransferExportTitle,
              subtitle: isBusy && progressText != null
                  ? progressText
                  : localizations.dataTransferExportSubtitle,
              enabled: !isBusy,
              trailing: isBusy ? const _TransferProgressIndicator() : null,
              onTap: _exportData,
            ),
            const SizedBox(height: 8),
            _settingsActionCard(
              context: context,
              feedbackId: 'data-transfer-import',
              icon: Icons.file_download_outlined,
              title: localizations.dataTransferImportTitle,
              subtitle: isBusy && progressText != null
                  ? progressText
                  : localizations.dataTransferImportSubtitle,
              enabled: !isBusy,
              trailing: isBusy ? const _TransferProgressIndicator() : null,
              onTap: _importData,
            ),
          ],
        );
      },
    );
  }

  Widget _buildOtherSettings(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _settingsExpansionCard(
          context: context,
          feedbackId: 'other-software-update',
          icon: Icons.system_update_alt_outlined,
          title: localizations.softwareUpdate,
          subtitle: localizations.softwareUpdateDescription,
          child: SoftwareUpdateView(
            controller: updateController,
            shrinkWrap: true,
          ),
        ),
        const SizedBox(height: 8),
        _settingsExpansionCard(
          context: context,
          feedbackId: 'other-scrape-jobs',
          icon: Icons.queue_play_next_outlined,
          title: localizations.settingsScrapeJobsTitle,
          subtitle: localizations.settingsScrapeJobsSubtitle,
          child: widget.scrapeJobCoordinator == null
              ? Text(localizations.scrapeJobsEmpty)
              : ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: Text(localizations.scrapeJobsTitle),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ScrapeJobsView(
                        db: widget.db,
                        coordinator: widget.scrapeJobCoordinator!,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        _settingsExpansionCard(
          context: context,
          feedbackId: 'other-prefix-route-rules',
          icon: Icons.route_outlined,
          title: localizations.prefixRouteRulesTitle,
          subtitle: localizations.prefixRouteRulesSubtitle,
          child: _buildPrefixRouteRulesSettings(context, shrinkWrap: true),
        ),
        const SizedBox(height: 8),
        _settingsExpansionCard(
          context: context,
          feedbackId: 'other-about',
          icon: Icons.info_outline,
          title: localizations.about,
          subtitle: null,
          child: _buildAboutSettingsEmbedded(context),
        ),
      ],
    );
  }

  Widget _buildScrapeSettings(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _settingsExpansionCard(
          context: context,
          feedbackId: 'scrape-sources',
          icon: Icons.source_outlined,
          title: localizations.scrapeSources,
          subtitle: null,
          child: _buildScrapeSourcesSettings(context, shrinkWrap: true),
        ),
        const SizedBox(height: 12),
        _ScrapePreferencesSettingsBody(database: widget.db),
      ],
    );
  }

  Widget _buildScrapeSourcesSettings(
    BuildContext context, {
    bool shrinkWrap = false,
  }) {
    return _ScrapeSourcesSettingsBody(
      database: widget.db,
      connectionTester:
          widget.scrapeSourceConnectionTester ?? _checkScrapeSourceConnection,
      shrinkWrap: shrinkWrap,
    );
  }

  Widget _buildPrefixRouteRulesSettings(
    BuildContext context, {
    bool shrinkWrap = false,
  }) {
    return PrefixRouteRulesBody(
      database: widget.db,
      repository: PrefixRouteRepository.forDatabase(widget.db),
      filePicker: widget.prefixRouteFilePicker,
      shrinkWrap: shrinkWrap,
    );
  }

  Future<void> _checkScrapeSourceConnection(ScrapeSourceId source) async {
    switch (source) {
      case ScrapeSourceId.javbus:
        String? initialCookies;
        try {
          initialCookies = await widget.db.getSetting('javbus_cookies');
        } catch (_) {
          initialCookies = null;
        }

        final transport = HttpJavBusTransport(
          initialCookieHeader: initialCookies,
          verificationHandler: _showJavBusVerification,
        );
        final client = JavBusClient(transport: transport);
        try {
          await client.checkConnection();
        } finally {
          if (transport.cookieHeader.isNotEmpty) {
            try {
              await widget.db.setSetting(
                'javbus_cookies',
                transport.cookieHeader,
              );
            } catch (_) {
              // Cookie 儲存失敗不應遮蔽原始連線結果。
            }
          }
          client.close();
        }
      case ScrapeSourceId.minnanoAv:
        final client = MinnanoClient(transport: HttpMinnanoTransport());
        try {
          await client.checkConnection();
        } finally {
          client.close();
        }
      case ScrapeSourceId.avbase:
        final client = AvBaseClient(transport: HttpAvBaseTransport());
        try {
          await client.checkConnection();
        } finally {
          client.close();
        }
      case ScrapeSourceId.avwiki:
        final client = AvWikiClient(transport: HttpAvWikiTransport());
        try {
          await client.checkConnection();
        } finally {
          client.close();
        }
    }
  }

  Future<Map<String, String>?> _showJavBusVerification(
    JavBusVerificationChallenge challenge,
  ) {
    if (!mounted) {
      return Future.value(null);
    }

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => JavBusVerificationDialog(challenge: challenge),
    );
  }

  Widget _buildAboutSettingsEmbedded(BuildContext context) {
    return Column(children: _aboutSettingsChildren(context));
  }

  List<Widget> _aboutSettingsChildren(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return [
      _settingsActionCard(
        context: context,
        feedbackId: 'about-github',
        icon: Icons.code_outlined,
        title: localizations.github,
        subtitle: null,
        enabled: true,
        trailing: const Icon(Icons.open_in_new),
        onTap: () => unawaited(_openExternalLink(_githubUri)),
      ),
      const SizedBox(height: 8),
      _settingsActionCard(
        context: context,
        feedbackId: 'about-feedback-suggestions',
        icon: Icons.feedback_outlined,
        title: localizations.feedbackSuggestions,
        subtitle: null,
        enabled: true,
        trailing: const Icon(Icons.open_in_new),
        onTap: () => unawaited(_openExternalLink(_issuesUri)),
      ),
    ];
  }

  Future<void> _openExternalLink(Uri uri) async {
    await widget.externalUrlLauncher(uri);
  }

  Widget _settingsActionCard({
    required BuildContext context,
    required String feedbackId,
    required IconData icon,
    required String title,
    String? subtitle,
    required bool enabled,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _SettingsTapFeedback(
      id: feedbackId,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: _settingsCardShape(),
        child: ListTile(
          enabled: enabled,
          minVerticalPadding: 12,
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }

  Widget _settingsExpansionCard({
    required BuildContext context,
    required String feedbackId,
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = _settingsCardShape();
    return _SettingsTapFeedback(
      id: feedbackId,
      child: ExpansionTile(
        key: PageStorageKey(feedbackId),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        backgroundColor: colorScheme.surfaceContainerHighest,
        collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        expansionAnimationStyle: _expansionAnimationStyle,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        children: [child],
      ),
    );
  }

  Future<void> _exportData() async {
    final result = await dataTransferController.exportData();
    if (!mounted || result.cancelled) return;
    final localizations = AppLocalizations.of(context);
    final skippedImages = result.summary?.skippedImages ?? 0;
    final message = result.error != null
        ? _dataTransferErrorMessage(localizations, result.error!.code)
        : skippedImages > 0
        ? localizations.dataTransferExportSuccessWithSkippedImages(
            skippedImages,
          )
        : localizations.dataTransferExportSuccess;
    _showDataTransferMessage(message, isError: result.error != null);
  }

  Future<void> _importData() async {
    final result = await dataTransferController.importData(
      resolveDuplicate: _showDuplicateChooser,
    );
    if (!mounted || result.cancelled) return;
    final localizations = AppLocalizations.of(context);
    final message = result.error != null
        ? _dataTransferErrorMessage(localizations, result.error!.code)
        : localizations.dataTransferImportSuccess;
    _showDataTransferMessage(message, isError: result.error != null);
  }

  Future<DataTransferDuplicateResolution?> _showDuplicateChooser(
    DataTransferDuplicateCandidate candidate,
  ) async {
    DataTransferDuplicateResolution? selected;
    return showDialog<DataTransferDuplicateResolution>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final localizations = AppLocalizations.of(context);
          return AlertDialog(
            shape: _outlinedCardShape(context),
            title: Text(localizations.dataTransferDuplicateTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(localizations.dataTransferDuplicateExplanation),
                    const SizedBox(height: 16),
                    RadioGroup<DataTransferDuplicateResolution>(
                      groupValue: selected,
                      onChanged: (value) =>
                          setDialogState(() => selected = value),
                      child: Column(
                        children: [
                          _duplicateChoice(
                            context: context,
                            value: DataTransferDuplicateResolution.keepExisting,
                            title: localizations.dataTransferKeepExisting,
                            name: candidate.existingName,
                            workCount: candidate.existingWorkCount,
                            image: _existingAvatar(candidate.existingImagePath),
                          ),
                          _duplicateChoice(
                            context: context,
                            value: DataTransferDuplicateResolution.useImported,
                            title: localizations.dataTransferUseImported,
                            name: candidate.imported.name,
                            workCount: candidate.importedWorkCount,
                            image: _importedAvatar(
                              candidate.importedAvatarBytes,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(localizations.cancel),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, selected),
                child: Text(localizations.dataTransferContinue),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _duplicateChoice({
    required BuildContext context,
    required DataTransferDuplicateResolution value,
    required String title,
    required String name,
    required int workCount,
    required Widget image,
  }) {
    final localizations = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: _outlinedCardShape(context, radius: 10),
      child: RadioListTile<DataTransferDuplicateResolution>(
        value: value,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        secondary: image,
        title: Text(title),
        subtitle: Text(
          '$name\n${localizations.dataTransferWorkCount(workCount)}',
        ),
      ),
    );
  }

  Widget _existingAvatar(String? imagePath) {
    if (imagePath == null || imagePath.trim().isEmpty) {
      return const _TransferAvatarPlaceholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(imagePath),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _TransferAvatarPlaceholder(),
      ),
    );
  }

  Widget _importedAvatar(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return const _TransferAvatarPlaceholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _TransferAvatarPlaceholder(),
      ),
    );
  }

  String _dataTransferErrorMessage(
    AppLocalizations localizations,
    String code,
  ) {
    return switch (code) {
      'archive_too_large' => localizations.dataTransferArchiveTooLarge,
      'unsafe_archive' => localizations.dataTransferUnsafeArchive,
      'corrupt_archive' => localizations.dataTransferCorruptArchive,
      'file_unreadable' => localizations.dataTransferFileUnreadable,
      'actor_name_conflict' => localizations.dataTransferActorNameConflict,
      'busy' => localizations.dataTransferBusy,
      _ => localizations.dataTransferFailed,
    };
  }

  void _showDataTransferMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _themeModeSelector(BuildContext context) {
    final current = controller.themeModeString;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final shape = _settingsCardShape();

    return _SettingsTapFeedback(
      id: 'theme-mode',
      child: ExpansionTile(
        key: const PageStorageKey('theme-mode'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        backgroundColor: colorScheme.surfaceContainerHighest,
        collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        expansionAnimationStyle: _expansionAnimationStyle,
        title: Text(AppLocalizations.of(context).themeMode),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (selected) async {
              if (selected != null) {
                await controller.themeModeChanged(selected);
              }
            },
            child: Column(
              children: [
                _themeModeRadioOption(context, 'system'),
                _themeModeRadioOption(context, 'light'),
                if (isDark && !controller.isCustomTheme)
                  _expandableThemeModeOption(
                    context,
                    key: const PageStorageKey('theme-option-dark'),
                    value: 'dark',
                    child: _pureBlackSwitch(context),
                  )
                else
                  _themeModeRadioOption(context, 'dark'),
                if (controller.isCustomTheme)
                  _expandableThemeModeOption(
                    context,
                    key: const PageStorageKey('theme-option-custom'),
                    value: 'custom',
                    child: _customThemeEditor(context),
                  )
                else
                  _themeModeRadioOption(context, 'custom'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeModeRadioOption(BuildContext context, String value) {
    return RadioListTile<String>(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(_themeModeLabel(context, value)),
      value: value,
    );
  }

  Widget _expandableThemeModeOption(
    BuildContext context, {
    required Key key,
    required String value,
    required Widget child,
  }) {
    return ExpansionTile(
      key: key,
      leading: Radio<String>(value: value),
      title: Text(_themeModeLabel(context, value)),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      shape: const Border(),
      collapsedShape: const Border(),
      expansionAnimationStyle: _expansionAnimationStyle,
      children: [child],
    );
  }

  Widget _languageSelector(BuildContext context) {
    final current = controller.localeString;
    final colorScheme = Theme.of(context).colorScheme;
    final shape = _settingsCardShape();

    return _SettingsTapFeedback(
      id: 'language',
      child: ExpansionTile(
        key: const PageStorageKey('language'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        backgroundColor: colorScheme.surfaceContainerHighest,
        collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        expansionAnimationStyle: _expansionAnimationStyle,
        title: Text(AppLocalizations.of(context).language),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (selected) async {
              if (selected != null) {
                await controller.languageChanged(selected);
              }
            },
            child: Column(
              children: controller.getLocaleOptions().map((value) {
                return RadioListTile<String>(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(_localeLabel(context, value)),
                  value: value,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _worksPageSizeSelector(BuildContext context) {
    final current = controller.worksPageSize;
    final colorScheme = Theme.of(context).colorScheme;
    final shape = _settingsCardShape();

    return _SettingsTapFeedback(
      id: 'works-page-size',
      child: ExpansionTile(
        key: const PageStorageKey('works-page-size'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        backgroundColor: colorScheme.surfaceContainerHighest,
        collapsedBackgroundColor: colorScheme.surfaceContainerHighest,
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        expansionAnimationStyle: _expansionAnimationStyle,
        title: Text(AppLocalizations.of(context).worksPageSize),
        children: [
          RadioGroup<WorksPageSize>(
            groupValue: current,
            onChanged: (selected) async {
              if (selected != null) {
                await controller.worksPageSizeChanged(selected);
              }
            },
            child: Column(
              children: [
                RadioListTile<WorksPageSize>(
                  key: const PageStorageKey('works-page-size-option-small'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(AppLocalizations.of(context).worksPageSizeSmall),
                  value: WorksPageSize.small,
                ),
                RadioListTile<WorksPageSize>(
                  key: const PageStorageKey('works-page-size-option-large'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(AppLocalizations.of(context).worksPageSizeLarge),
                  value: WorksPageSize.large,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(BuildContext context, String value) {
    return switch (value) {
      'system' => AppLocalizations.of(context).followSystem,
      'light' => AppLocalizations.of(context).lightTheme,
      'dark' => AppLocalizations.of(context).darkTheme,
      'custom' => AppLocalizations.of(context).customTheme,
      _ => value,
    };
  }

  String _localeLabel(BuildContext context, String value) {
    return switch (value) {
      'system' => AppLocalizations.of(context).followSystem,
      'zh_TW' => AppLocalizations.of(context).traditionalChineseTaiwan,
      'zh_CN' => AppLocalizations.of(context).simplifiedChinese,
      'ja_JP' => AppLocalizations.of(context).japanese,
      'en' => AppLocalizations.of(context).english,
      _ => value,
    };
  }

  Widget _pureBlackSwitch(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(AppLocalizations.of(context).pureBlackAmoled),
      subtitle: Text(AppLocalizations.of(context).pureBlackOnlyDark),
      value: controller.isPureBlack,
      onChanged: (value) async {
        await controller.pureBlackChanged(value);
      },
    );
  }

  Widget _customThemeEditor(BuildContext context) {
    return Column(
      children: controller.customColors.entries
          .map((entry) => _customColorTile(context, entry))
          .toList(),
    );
  }

  Widget _customColorTile(BuildContext context, MapEntry<String, Color> entry) {
    return ListTile(
      title: Text(_colorLabel(context, entry.key)),
      trailing: _colorPreview(entry.value),
      onTap: () => _openColorPicker(context, entry.key),
    );
  }

  Widget _colorPreview(Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
      ),
    );
  }

  String _colorLabel(BuildContext context, String key) {
    return switch (key) {
      'surface' => AppLocalizations.of(context).colorSurface,
      'surfaceContainer' => AppLocalizations.of(context).colorSurfaceContainer,
      'onSurface' => AppLocalizations.of(context).colorOnSurface,
      'onSurfaceVariant' => AppLocalizations.of(context).colorOnSurfaceVariant,
      'primary' => AppLocalizations.of(context).colorPrimary,
      'onPrimary' => AppLocalizations.of(context).colorOnPrimary,
      'outline' => AppLocalizations.of(context).colorOutline,
      'snackbarBackground' => AppLocalizations.of(
        context,
      ).colorSnackbarBackground,
      _ => key,
    };
  }

  Future<void> _openColorPicker(BuildContext context, String key) async {
    Color temp = controller.customColors[key]!;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _SettingsTapFeedback(
          id: 'color-dialog',
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_settingsCardRadius),
              side: BorderSide(width: 1, color: temp),
            ),
            title: Text(
              AppLocalizations.of(
                context,
              ).adjustColorTitle(_colorLabel(context, key)),
            ),
            content: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: temp,
                onColorChanged: (color) {
                  setDialogState(() => temp = color);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context).cancel),
              ),
              FilledButton(
                onPressed: () async {
                  controller.customColors[key] = temp;
                  await controller.saveCustomTheme();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: Text(AppLocalizations.of(context).apply),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferProgressIndicator extends StatelessWidget {
  const _TransferProgressIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _ScrapeSourcesSettingsBody extends StatefulWidget {
  const _ScrapeSourcesSettingsBody({
    required this.database,
    required this.connectionTester,
    this.shrinkWrap = false,
  });

  final AppDatabase database;
  final ScrapeSourceConnectionTester connectionTester;
  final bool shrinkWrap;

  @override
  State<_ScrapeSourcesSettingsBody> createState() =>
      _ScrapeSourcesSettingsBodyState();
}

class _ScrapeSourcesSettingsBodyState
    extends State<_ScrapeSourcesSettingsBody> {
  late final Future<ScrapeSourceSettings> _settingsFuture;
  ScrapeSourceSettings? _settings;
  Future<void> _saveQueue = Future<void>.value();
  int _selectionVersion = 0;
  final _connectionStatuses = <ScrapeSourceId, _ScrapeSourceConnectionStatus>{
    for (final source in ScrapeSourceRegistry.aggregatePriority)
      source: _ScrapeSourceConnectionStatus.notTested,
  };
  bool _isTestingConnections = false;

  @override
  void initState() {
    super.initState();
    // This state is created for each category visit, so reopening the page
    // always reads the latest persisted selection instead of reusing the
    // SettingsView state's initial Future.
    _settingsFuture = _loadScrapeSourceSettings();
  }

  Future<ScrapeSourceSettings> _loadScrapeSourceSettings() async {
    return ScrapeSourceSettings.decode(
      await widget.database.getSetting(scrapeSourceSettingsKey),
    );
  }

  Future<void> _select({
    ScrapeSourceId? actressDetailsSource,
    List<ScrapeSourceId>? worksSources,
    ScrapeSourceId? aliasSource,
  }) async {
    final current = _settings;
    if (current == null) {
      return;
    }
    final next = current.copyWith(
      actressDetailsSource: actressDetailsSource,
      worksSources: worksSources,
      aliasSource: aliasSource,
    );
    final version = ++_selectionVersion;
    setState(() => _settings = next);
    final save = _saveQueue.then<void>(
      (_) => widget.database.setSetting(scrapeSourceSettingsKey, next.encode()),
    );
    _saveQueue = save.catchError((_) {});
    try {
      await save;
    } catch (_) {
      if (!mounted || version != _selectionVersion) {
        return;
      }
      final persisted = await _loadScrapeSourceSettings();
      if (!mounted || version != _selectionVersion) {
        return;
      }
      setState(() => _settings = persisted);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).scrapeSourceSaveFailed),
          ),
        );
    }
  }

  Future<void> _testConnections() async {
    if (_isTestingConnections) {
      return;
    }

    setState(() {
      _isTestingConnections = true;
      for (final source in _connectionStatuses.keys) {
        _connectionStatuses[source] = _ScrapeSourceConnectionStatus.testing;
      }
    });

    try {
      for (final source in ScrapeSourceRegistry.aggregatePriority) {
        if (!mounted) {
          return;
        }

        try {
          await widget.connectionTester(source);
          if (!mounted) {
            return;
          }
          setState(() {
            _connectionStatuses[source] =
                _ScrapeSourceConnectionStatus.connected;
          });
        } on JavBusVerificationCancelledException {
          if (!mounted) {
            return;
          }
          setState(() {
            _connectionStatuses[source] =
                _ScrapeSourceConnectionStatus.verificationRequired;
          });
        } on Object {
          if (!mounted) {
            return;
          }
          setState(() {
            _connectionStatuses[source] = _ScrapeSourceConnectionStatus.failed;
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnections = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ScrapeSourceSettings>(
      key: const PageStorageKey('scrape-source-settings-loader'),
      future: _settingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(AppLocalizations.of(context).scrapeSourceSaveFailed),
          );
        }
        _settings ??= snapshot.data ?? const ScrapeSourceSettings();
        final settings = _settings!;
        final localizations = AppLocalizations.of(context);
        return ListView(
          key: const PageStorageKey('scrape-source-settings-scroll'),
          padding: EdgeInsets.zero,
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          children: [
            _connectionStatusSelector(context),
            const SizedBox(height: 12),
            _sourceSelector<ScrapeSourceId>(
              key: const PageStorageKey('scrape-actress-source'),
              title: localizations.scrapeSourceDetailsTitle,
              value: settings.actressDetailsSource,
              options: [
                (ScrapeSourceId.minnanoAv, localizations.scrapeSourceMinnanoAv),
                (ScrapeSourceId.javbus, localizations.scrapeSourceJavBus),
                (ScrapeSourceId.avbase, localizations.scrapeSourceAvBase),
              ],
              onChanged: (value) =>
                  unawaited(_select(actressDetailsSource: value)),
            ),
            const SizedBox(height: 12),
            _worksSourceSelector(context, settings),
            const SizedBox(height: 12),
            _sourceSelector<ScrapeSourceId>(
              key: const PageStorageKey('scrape-alias-source'),
              title: localizations.scrapeSourceAliasTitle,
              value: settings.aliasSource,
              options: [
                (ScrapeSourceId.avbase, localizations.scrapeSourceAvBase),
              ],
              onChanged: (value) => unawaited(_select(aliasSource: value)),
            ),
          ],
        );
      },
    );
  }

  Widget _connectionStatusSelector(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const PageStorageKey('scrape-source-connection-status'),
        title: Text(localizations.scrapeSourceConnectionTitle),
        subtitle: Text(localizations.scrapeSourceConnectionSubtitle),
        backgroundColor: colorScheme.surfaceContainer,
        collapsedBackgroundColor: colorScheme.surfaceContainer,
        shape: const Border(),
        collapsedShape: const Border(),
        clipBehavior: Clip.antiAlias,
        children: [
          for (final source in ScrapeSourceRegistry.aggregatePriority)
            _connectionStatusTile(context, source),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('scrape-source-retest-button'),
                onPressed: _isTestingConnections ? null : _testConnections,
                icon: _isTestingConnections
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _isTestingConnections
                      ? localizations.scrapeSourceTesting
                      : localizations.scrapeSourceRetest,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionStatusTile(BuildContext context, ScrapeSourceId source) {
    final localizations = AppLocalizations.of(context);
    final status =
        _connectionStatuses[source] ?? _ScrapeSourceConnectionStatus.notTested;
    final (label, icon, color) = switch (status) {
      _ScrapeSourceConnectionStatus.notTested => (
        localizations.scrapeSourceNotTested,
        Icons.help_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      _ScrapeSourceConnectionStatus.testing => (
        localizations.scrapeSourceTesting,
        Icons.sync,
        Theme.of(context).colorScheme.primary,
      ),
      _ScrapeSourceConnectionStatus.connected => (
        localizations.scrapeSourceConnected,
        Icons.check_circle_outline,
        Theme.of(context).colorScheme.tertiary,
      ),
      _ScrapeSourceConnectionStatus.failed => (
        localizations.scrapeSourceConnectionFailed,
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
      _ScrapeSourceConnectionStatus.verificationRequired => (
        localizations.scrapeSourceVerificationRequired,
        Icons.verified_user_outlined,
        Theme.of(context).colorScheme.primary,
      ),
    };

    return ListTile(
      key: ValueKey('scrape-source-status-${source.name}'),
      title: Text(_sourceLabel(localizations, source)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  String _sourceLabel(AppLocalizations localizations, ScrapeSourceId source) {
    return switch (source) {
      ScrapeSourceId.minnanoAv => localizations.scrapeSourceMinnanoAv,
      ScrapeSourceId.javbus => localizations.scrapeSourceJavBus,
      ScrapeSourceId.avbase => localizations.scrapeSourceAvBase,
      ScrapeSourceId.avwiki => localizations.scrapeSourceAvWiki,
    };
  }

  Widget _worksSourceSelector(
    BuildContext context,
    ScrapeSourceSettings settings,
  ) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final selected = settings.worksSources;
    final unselected = ScrapeSourceRegistry.worksSources
        .where((source) => !selected.contains(source))
        .toList(growable: false);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const PageStorageKey('scrape-works-source'),
        backgroundColor: colorScheme.surfaceContainer,
        collapsedBackgroundColor: colorScheme.surfaceContainer,
        shape: const Border(),
        collapsedShape: const Border(),
        clipBehavior: Clip.antiAlias,
        title: Text(localizations.scrapeSourceWorksTitle),
        subtitle: Text(localizations.scrapeSourcePriorityHint),
        children: [
          ReorderableListView.builder(
            key: const PageStorageKey('scrape-works-source-order'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: selected.length,
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...selected];
              final source = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, source);
              unawaited(_select(worksSources: reordered));
            },
            itemBuilder: (context, index) {
              final source = selected[index];
              return CheckboxListTile(
                key: ValueKey('scrape-works-source-selected-${source.name}'),
                value: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Row(
                  children: [
                    Expanded(child: Text(_sourceLabel(localizations, source))),
                    Text('#${index + 1}'),
                  ],
                ),
                secondary: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
                onChanged: selected.length == 1
                    ? null
                    : (_) => unawaited(
                        _select(
                          worksSources: selected
                              .where((item) => item != source)
                              .toList(growable: false),
                        ),
                      ),
              );
            },
          ),
          for (final source in unselected)
            CheckboxListTile(
              key: ValueKey('scrape-works-source-available-${source.name}'),
              value: false,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(_sourceLabel(localizations, source)),
              onChanged: (_) =>
                  unawaited(_select(worksSources: [...selected, source])),
            ),
        ],
      ),
    );
  }

  Widget _sourceSelector<T>({
    required Key key,
    required String title,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: key,
        backgroundColor: colorScheme.surfaceContainer,
        collapsedBackgroundColor: colorScheme.surfaceContainer,
        shape: const Border(),
        collapsedShape: const Border(),
        clipBehavior: Clip.antiAlias,
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: value,
            onChanged: onChanged,
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<T>(
                    value: option.$1,
                    title: Text(option.$2),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrapePreferencesSettingsBody extends StatefulWidget {
  const _ScrapePreferencesSettingsBody({required this.database});

  final AppDatabase database;

  @override
  State<_ScrapePreferencesSettingsBody> createState() =>
      _ScrapePreferencesSettingsBodyState();
}

class _ScrapePreferencesSettingsBodyState
    extends State<_ScrapePreferencesSettingsBody> {
  late final Future<WorkScrapeOptions> _optionsFuture;
  final exactAllowController = TextEditingController();
  final exactDenyController = TextEditingController();
  WorkScrapeOptions? options;
  bool advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    _optionsFuture = _loadOptions();
  }

  @override
  void dispose() {
    exactAllowController.dispose();
    exactDenyController.dispose();
    super.dispose();
  }

  Future<WorkScrapeOptions> _loadOptions() async {
    try {
      final loaded = WorkScrapeOptions.decode(
        await widget.database.getSetting('works_scrape_options'),
      );
      if (mounted) setState(() => options = loaded);
      return loaded;
    } catch (_) {
      const fallback = WorkScrapeOptions();
      if (mounted) setState(() => options = fallback);
      return fallback;
    }
  }

  Future<void> _update(WorkScrapeOptions next) async {
    if (!mounted) return;
    setState(() => options = next);
    try {
      await widget.database.setSetting('works_scrape_options', next.encode());
    } catch (_) {
      // Keep the in-memory preference usable when the settings store is busy.
    }
  }

  void _addExactAllow(WorkScrapeOptions current) {
    final value = exactAllowController.text.trim().toUpperCase();
    if (value.isEmpty ||
        current.exactAllows.any((rule) => rule.normalizedCode == value)) {
      return;
    }
    exactAllowController.clear();
    unawaited(
      _update(
        current.copyWith(
          exactAllows: [
            ...current.exactAllows,
            ScrapeExactAllowRule(code: value),
          ],
        ),
      ),
    );
  }

  void _addExactDeny(WorkScrapeOptions current) {
    final value = exactDenyController.text.trim().toUpperCase();
    if (value.isEmpty ||
        current.exactDenies.any((rule) => rule.normalizedCode == value)) {
      return;
    }
    exactDenyController.clear();
    unawaited(
      _update(
        current.copyWith(
          exactDenies: [
            ...current.exactDenies,
            ScrapeExactDenyRule(code: value),
          ],
        ),
      ),
    );
  }

  Widget _ruleEditor({
    required String title,
    required String hint,
    required TextEditingController controller,
    required List<String> values,
    required VoidCallback onAdd,
    required ValueChanged<String> onDelete,
    required Key inputKey,
    required Key addKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: inputKey,
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: addKey,
              tooltip: title,
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (values.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              AppLocalizations.of(context).scrapeNoRules,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in values)
                  InputChip(
                    label: Text(value),
                    onDeleted: () => onDelete(value),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return FutureBuilder<WorkScrapeOptions>(
      future: _optionsFuture,
      builder: (context, snapshot) {
        final current = options ?? snapshot.data;
        if (current == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Card(
          key: const Key('settings-scrape-preferences'),
          margin: EdgeInsets.zero,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            key: const Key('scrape-preferences-padding'),
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<bool>(
                  key: const Key('scrape-existing-data-policy'),
                  initialValue: current.fillMissingOnly,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: localizations.scrapeExistingData,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: true,
                      child: Text(localizations.fillMissingOnly),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text(localizations.scrapeUpdateAll),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(
                        _update(current.copyWith(fillMissingOnly: value)),
                      );
                    }
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('scrape-aliases-switch'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(localizations.scrapeAliases),
                  value: current.scrapeAliases,
                  onChanged: (value) => unawaited(
                    _update(current.copyWith(scrapeAliases: value)),
                  ),
                ),
                SwitchListTile(
                  key: const Key('scrape-replace-actress-image-switch'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(localizations.replaceActressImage),
                  value: current.replaceActressImage,
                  onChanged: (value) => unawaited(
                    _update(current.copyWith(replaceActressImage: value)),
                  ),
                ),
                SwitchListTile(
                  key: const Key('scrape-auto-exclude-derived-switch'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(localizations.scrapeAutomaticDerivedFilter),
                  subtitle: Text(
                    localizations.scrapeAutomaticDerivedFilterDescription,
                  ),
                  value: current.autoExcludeDerivedWorks,
                  onChanged: (value) => unawaited(
                    _update(current.copyWith(autoExcludeDerivedWorks: value)),
                  ),
                ),
                ExpansionTile(
                  key: const Key('scrape-advanced-rules'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(localizations.scrapeAdvancedRules),
                  subtitle: Text(localizations.scrapeAdvancedRulesDescription),
                  initiallyExpanded: advancedExpanded,
                  onExpansionChanged: (value) =>
                      setState(() => advancedExpanded = value),
                  children: [
                    _ruleEditor(
                      title: localizations.scrapeExactAllows,
                      hint: localizations.scrapeRuleHint,
                      controller: exactAllowController,
                      values: [
                        for (final rule in current.exactAllows) rule.code,
                      ],
                      onAdd: () => _addExactAllow(current),
                      onDelete: (value) => unawaited(
                        _update(
                          current.copyWith(
                            exactAllows: [
                              for (final rule in current.exactAllows)
                                if (rule.code != value) rule,
                            ],
                          ),
                        ),
                      ),
                      inputKey: const Key('scrape-exact-allow-input'),
                      addKey: const Key('scrape-exact-allow-add'),
                    ),
                    const SizedBox(height: 16),
                    _ruleEditor(
                      title: localizations.scrapeExactDenies,
                      hint: localizations.scrapeRuleHint,
                      controller: exactDenyController,
                      values: [
                        for (final rule in current.exactDenies) rule.code,
                      ],
                      onAdd: () => _addExactDeny(current),
                      onDelete: (value) => unawaited(
                        _update(
                          current.copyWith(
                            exactDenies: [
                              for (final rule in current.exactDenies)
                                if (rule.code != value) rule,
                            ],
                          ),
                        ),
                      ),
                      inputKey: const Key('scrape-exact-deny-input'),
                      addKey: const Key('scrape-exact-deny-add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TransferAvatarPlaceholder extends StatelessWidget {
  const _TransferAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: const SizedBox(
        width: 64,
        height: 64,
        child: Icon(Icons.person_outline),
      ),
    );
  }
}

class _SettingsCategoryPage extends StatelessWidget {
  const _SettingsCategoryPage({
    required this.controller,
    required this.titleBuilder,
    required this.bodyBuilder,
  });

  final SettingsController controller;
  final String Function(BuildContext context) titleBuilder;
  final Widget Function(BuildContext context) bodyBuilder;

  @override
  Widget build(BuildContext context) {
    return _SettingsInteractionTheme(
      child: Scaffold(
        appBar: AppBar(
          title: Text(titleBuilder(context)),
          leading: _SettingsTapFeedback(
            id: 'category-back',
            child: AlignedAppBarBackButton(
              expandToToolbar: true,
              verticalOffset: 0,
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        body: AdaptivePageLayout(
          padding: EdgeInsets.zero,
          compactBuilder: (context, tokens) =>
              _buildCategoryBody(context, tokens),
          expandedBuilder: (context, tokens) =>
              _buildCategoryBody(context, tokens),
        ),
      ),
    );
  }

  Widget _buildCategoryBody(BuildContext context, AppLayoutTokens tokens) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tokens.isCompact
              ? double.infinity
              : tokens.settingsShortContentMaxWidth,
        ),
        child: Padding(
          padding: tokens.pagePadding,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => bodyBuilder(context),
          ),
        ),
      ),
    );
  }
}
