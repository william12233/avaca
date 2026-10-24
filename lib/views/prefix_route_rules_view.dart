import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../components/app_help_tooltip.dart';
import '../controllers/prefix_route_file_transfer.dart';
import '../core/database.dart';
import '../core/layout.dart';
import '../core/shapes.dart';
import '../l10n/app_localizations.dart';
import '../services/javbus/prefix_route_repository.dart';
import '../services/javbus/work_image_route_models.dart';
import '../services/javbus/work_image_route_resolver.dart';

class PrefixRouteRulesBody extends StatefulWidget {
  const PrefixRouteRulesBody({
    super.key,
    required this.database,
    this.repository,
    this.filePicker,
    this.shrinkWrap = false,
  });

  final AppDatabase database;
  final PrefixRouteRepository? repository;
  final PrefixRouteFilePicker? filePicker;
  final bool shrinkWrap;

  @override
  State<PrefixRouteRulesBody> createState() => _PrefixRouteRulesBodyState();
}

class _PrefixRouteRulesBodyState extends State<PrefixRouteRulesBody> {
  late final PrefixRouteRepository _repository;
  late final PrefixRouteFilePicker _filePicker;
  late final TextEditingController _searchController;
  final _rulesScrollController = ScrollController();
  List<WorkImagePrefixRouteRule> _rules = const [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? PrefixRouteRepository.forDatabase(widget.database);
    _filePicker = widget.filePicker ?? const PlatformPrefixRouteFilePicker();
    _searchController = TextEditingController()..addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _rulesScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await _repository.ensureLoaded();
      if (!mounted) return;
      final loadError = _repository.isReady
          ? null
          : _repository.loadError ??
                AppLocalizations.of(context).prefixRouteLoadFailed;
      setState(() {
        _rules = _repository.rules;
        _loadError = loadError;
        _isLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadError = AppLocalizations.of(context).prefixRouteLoadFailed;
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _repository.ensureLoaded();
    if (!mounted) return;
    setState(() => _rules = _repository.rules);
  }

  List<WorkImagePrefixRouteRule> get _filteredRules {
    final query = _searchController.text.trim().toUpperCase();
    if (query.isEmpty) return _rules;
    return _rules.where((rule) => rule.prefix.contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tokens = AppLayoutPolicy.resolve(
      BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width),
    );
    final inputRadius = BorderRadius.circular(AppShapeTokens.defaultCardRadius);
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredRules = _filteredRules;
    return ListView(
      key: const PageStorageKey('prefix-route-settings-scroll'),
      padding: EdgeInsets.zero,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [
        _summaryCard(context),
        const SizedBox(height: 12),
        SizedBox(
          height: tokens.controlHeight,
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: localizations.prefixRouteSearchHint,
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: localizations.clear,
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear),
                    ),
              border: OutlineInputBorder(borderRadius: inputRadius),
              enabledBorder: OutlineInputBorder(
                borderRadius: inputRadius,
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: inputRadius,
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('prefix-route-export'),
              onPressed: _export,
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, tokens.controlHeight),
              ),
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(localizations.prefixRouteExport),
            ),
            OutlinedButton.icon(
              key: const ValueKey('prefix-route-import'),
              onPressed: _import,
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, tokens.controlHeight),
              ),
              icon: const Icon(Icons.file_download_outlined),
              label: Text(localizations.prefixRouteImport),
            ),
            TextButton.icon(
              key: const ValueKey('prefix-route-clear-automatic'),
              onPressed: _clearAutomaticLearning,
              style: TextButton.styleFrom(
                minimumSize: Size(0, tokens.controlHeight),
              ),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(localizations.prefixRouteClearAutomatic),
            ),
          ],
        ),
        if (_loadError != null) ...[
          const SizedBox(height: 12),
          _messageCard(
            context,
            icon: Icons.warning_amber_outlined,
            message: _loadError!,
          ),
        ],
        const SizedBox(height: 12),
        if (filteredRules.isEmpty)
          _messageCard(
            context,
            icon: Icons.route_outlined,
            message: _rules.isEmpty
                ? localizations.prefixRouteNoRules
                : localizations.prefixRouteNoSearchResults,
          )
        else
          _rulesViewport(context, filteredRules),
      ],
    );
  }

  Widget _rulesViewport(
    BuildContext context,
    List<WorkImagePrefixRouteRule> rules,
  ) {
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.46).clamp(
      220.0,
      480.0,
    );
    return ConstrainedBox(
      key: const ValueKey('prefix-route-rules-viewport'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scrollbar(
        controller: _rulesScrollController,
        thumbVisibility: rules.length > 8,
        child: ListView.separated(
          controller: _rulesScrollController,
          primary: false,
          shrinkWrap: true,
          itemCount: rules.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _ruleCard(context, rules[index]),
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.route_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppHelpTooltip(
                        message: localizations.prefixRouteRulesSubtitle,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          localizations.prefixRouteRulesTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(localizations.prefixRouteRuleCount(_rules.length)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Widget _ruleCard(BuildContext context, WorkImagePrefixRouteRule rule) {
    final localizations = AppLocalizations.of(context);
    final family = rule.manualOverride ?? rule.preferredFamily;
    final status = _statusPresentation(context, rule.status);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        key: ValueKey('prefix-route-rule-${rule.prefix}'),
        onTap: () => _openDetail(rule),
        leading: Icon(status.$1, color: status.$2),
        title: Text(rule.prefix, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${localizations.prefixRouteBestFamily}: '
          '${family == null ? localizations.prefixRouteNotAvailable : _familyLabel(context, family)}\n'
          '${status.$3}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Future<void> _openDetail(WorkImagePrefixRouteRule rule) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PrefixRouteRuleDetailSheet(
        repository: _repository,
        initialRule: rule,
        onChanged: _refresh,
      ),
    );
    await _refresh();
  }

  Future<void> _export() async {
    final localizations = AppLocalizations.of(context);
    final includeStatistics = await _showExportMode();
    if (includeStatistics == null) return;
    try {
      final json = await _repository.exportJson(
        includeStatistics: includeStatistics,
      );
      final savedPath = await _filePicker.saveExport(
        bytes: Uint8List.fromList(utf8.encode(json)),
        fileName: 'avaca-prefix-routes.json',
        dialogTitle: localizations.prefixRouteExportDialogTitle,
      );
      if (!mounted || savedPath == null) return;
      _showMessage(localizations.prefixRouteExportSuccess);
    } on Object {
      if (mounted) _showMessage(localizations.prefixRouteOperationFailed);
    }
  }

  Future<bool?> _showExportMode() {
    final localizations = AppLocalizations.of(context);
    final tokens = AppLayoutPolicy.resolve(
      BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width),
    );
    var includeStatistics = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(localizations.prefixRouteExportDialogTitle),
          content: RadioGroup<bool>(
            groupValue: includeStatistics,
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => includeStatistics = value);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<bool>(
                  value: false,
                  minTileHeight: tokens.controlHeight,
                  title: Row(
                    children: [
                      AppHelpTooltip(
                        message:
                            localizations.prefixRouteExportRulesOnlyDescription,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(localizations.prefixRouteExportRulesOnly),
                      ),
                    ],
                  ),
                ),
                RadioListTile<bool>(
                  value: true,
                  minTileHeight: tokens.controlHeight,
                  title: Row(
                    children: [
                      AppHelpTooltip(
                        message: localizations
                            .prefixRouteExportWithStatisticsDescription,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          localizations.prefixRouteExportWithStatistics,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, includeStatistics),
              child: Text(localizations.prefixRouteExport),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import() async {
    final localizations = AppLocalizations.of(context);
    try {
      final bytes = await _filePicker.pickImport(
        dialogTitle: localizations.prefixRouteImportDialogTitle,
      );
      if (bytes == null) return;
      await _repository.ensureLoaded();
      final preview = _repository.previewImport(utf8.decode(bytes));
      final mode = await _showImportMode(preview);
      if (mode == null) return;
      final result = await _repository.importJson(
        utf8.decode(bytes),
        mode: mode,
      );
      await _refresh();
      if (!mounted) return;
      _showMessage(
        localizations.prefixRouteImportSuccess(result.importedRuleCount),
      );
    } on Object {
      if (mounted) _showMessage(localizations.prefixRouteOperationFailed);
    }
  }

  Future<PrefixRouteImportMode?> _showImportMode(
    PrefixRouteImportPreview preview,
  ) {
    final localizations = AppLocalizations.of(context);
    return showDialog<PrefixRouteImportMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.prefixRouteImportDialogTitle),
        content: Text(
          localizations.prefixRouteImportPreview(
            preview.importedRuleCount,
            preview.manualConflictCount,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(localizations.cancel),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, PrefixRouteImportMode.replace),
            child: Text(localizations.prefixRouteImportReplace),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, PrefixRouteImportMode.merge),
            child: Text(localizations.prefixRouteImportMerge),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAutomaticLearning() async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.prefixRouteClearAutomaticTitle),
        content: Text(localizations.prefixRouteClearAutomaticMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.clear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.clearAutomaticLearning();
      await _refresh();
      if (mounted) _showMessage(localizations.prefixRouteClearAutomaticSuccess);
    } on Object {
      if (mounted) _showMessage(localizations.prefixRouteOperationFailed);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  (IconData, Color, String) _statusPresentation(
    BuildContext context,
    WorkImagePrefixRouteStatus status,
  ) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return switch (status) {
      WorkImagePrefixRouteStatus.verified => (
        Icons.verified_outlined,
        colorScheme.tertiary,
        localizations.prefixRouteStatusVerified,
      ),
      WorkImagePrefixRouteStatus.hasExceptions => (
        Icons.warning_amber_outlined,
        colorScheme.error,
        localizations.prefixRouteStatusExceptions,
      ),
      WorkImagePrefixRouteStatus.pendingValidation => (
        Icons.hourglass_empty,
        colorScheme.primary,
        localizations.prefixRouteStatusPending,
      ),
      WorkImagePrefixRouteStatus.probeFailed => (
        Icons.error_outline,
        colorScheme.error,
        localizations.prefixRouteStatusProbeFailed,
      ),
    };
  }

  String _familyLabel(
    BuildContext context,
    WorkImageNormalizationFamily family,
  ) {
    final localizations = AppLocalizations.of(context);
    return switch (family) {
      WorkImageNormalizationFamily.dmmStandard =>
        localizations.prefixRouteFamilyDmmStandard,
      WorkImageNormalizationFamily.dmmLeadingOne =>
        localizations.prefixRouteFamilyDmmLeadingOne,
      WorkImageNormalizationFamily.dmmH1711 =>
        localizations.prefixRouteFamilyDmmH1711,
      WorkImageNormalizationFamily.dmmRebeccaH346 =>
        localizations.prefixRouteFamilyDmmRebeccaH346,
      WorkImageNormalizationFamily.mgstagePrestige =>
        localizations.prefixRouteFamilyMgstagePrestige,
      WorkImageNormalizationFamily.mgstageSeikyouiku =>
        localizations.prefixRouteFamilyMgstageSeikyouiku,
    };
  }
}

class _PrefixRouteRuleDetailSheet extends StatefulWidget {
  const _PrefixRouteRuleDetailSheet({
    required this.repository,
    required this.initialRule,
    required this.onChanged,
  });

  final PrefixRouteRepository repository;
  final WorkImagePrefixRouteRule initialRule;
  final Future<void> Function() onChanged;

  @override
  State<_PrefixRouteRuleDetailSheet> createState() =>
      _PrefixRouteRuleDetailSheetState();
}

class _PrefixRouteRuleDetailSheetState
    extends State<_PrefixRouteRuleDetailSheet> {
  late WorkImagePrefixRouteRule _rule;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _rule = widget.initialRule;
  }

  Future<void> _reload() async {
    await widget.repository.ensureLoaded();
    if (!mounted) return;
    final next = widget.repository.ruleFor(_rule.prefix);
    if (next == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _rule = next);
    await widget.onChanged();
  }

  Future<void> _setManual(WorkImageNormalizationFamily? family) async {
    setState(() => _isBusy = true);
    try {
      await widget.repository.setManualOverride(
        prefix: _rule.prefix,
        family: family,
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _resetLearning() async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.prefixRouteResetTitle),
        content: Text(localizations.prefixRouteResetMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.prefixRouteReset),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isBusy = true);
    try {
      await widget.repository.clearAutomaticLearningFor(_rule.prefix);
      await _reload();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _forgetRule() async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.prefixRouteForgetTitle),
        content: Text(localizations.prefixRouteForgetMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.prefixRouteForget),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isBusy = true);
    try {
      await widget.repository.forget(_rule.prefix);
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final status = _statusPresentation(context, _rule.status);
    final manual = _rule.manualOverride;
    final inputRadius = BorderRadius.circular(AppShapeTokens.dialogRadius);
    final menuRadius = BorderRadius.circular(AppShapeTokens.popupMenuRadius);
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = AppLayoutPolicy.resolve(
      BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _rule.prefix,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${localizations.prefixRouteBestFamily}: '
                '${manual == null && _rule.preferredFamily == null ? localizations.prefixRouteNotAvailable : _familyLabel(context, manual ?? _rule.preferredFamily!)}',
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(status.$1, color: status.$2, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(status.$3)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                localizations.prefixRouteCandidates,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final candidate in _rule.candidates)
                _candidateTile(context, candidate),
              const SizedBox(height: 16),
              Row(
                children: [
                  AppHelpTooltip(
                    message: manual == null
                        ? localizations.prefixRouteAutomaticDescription
                        : localizations.prefixRouteManualDescription,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      localizations.prefixRouteManualOverride,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: tokens.controlHeight,
                child: DropdownButtonFormField<WorkImageNormalizationFamily?>(
                  initialValue: manual,
                  elevation: 3,
                  dropdownColor: colorScheme.surfaceContainer,
                  borderRadius: menuRadius,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: inputRadius),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: inputRadius,
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: inputRadius,
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  items: [
                    DropdownMenuItem<WorkImageNormalizationFamily?>(
                      value: null,
                      child: Text(localizations.prefixRouteAutomatic),
                    ),
                    for (final family in workImageDefaultProbeOrder)
                      DropdownMenuItem<WorkImageNormalizationFamily?>(
                        value: family,
                        child: Text(_familyLabel(context, family)),
                      ),
                  ],
                  onChanged: _isBusy ? null : _setManual,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _resetLearning,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, tokens.controlHeight),
                ),
                icon: const Icon(Icons.restart_alt),
                label: Text(localizations.prefixRouteReset),
              ),
              TextButton.icon(
                onPressed: _isBusy ? null : _forgetRule,
                style: TextButton.styleFrom(
                  minimumSize: Size(0, tokens.controlHeight),
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(localizations.prefixRouteForget),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _candidateTile(
    BuildContext context,
    WorkImageRouteCandidate candidate,
  ) {
    final localizations = AppLocalizations.of(context);
    final status = _candidateStatus(context, candidate.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListTile(
        dense: true,
        title: Text(_familyLabel(context, candidate.family)),
        subtitle: Text(
          '${localizations.prefixRouteSuccessCount(candidate.successCount)} · '
          '${localizations.prefixRouteFailureCount(candidate.failureCount)}\n'
          '${status.$2}${_candidateTimes(context, candidate)}',
        ),
        trailing: Icon(status.$1, color: status.$3),
      ),
    );
  }

  String _candidateTimes(
    BuildContext context,
    WorkImageRouteCandidate candidate,
  ) {
    final localizations = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    String format(DateTime value) {
      final local = value.toLocal();
      return '${material.formatFullDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    }

    final lines = <String>[
      if (candidate.lastSuccessAt != null)
        localizations.prefixRouteLastSuccess(format(candidate.lastSuccessAt!)),
      if (candidate.lastFailureAt != null)
        localizations.prefixRouteLastFailure(format(candidate.lastFailureAt!)),
    ];
    return lines.isEmpty ? '' : '\n${lines.join('\n')}';
  }

  String _familyLabel(
    BuildContext context,
    WorkImageNormalizationFamily family,
  ) {
    final localizations = AppLocalizations.of(context);
    return switch (family) {
      WorkImageNormalizationFamily.dmmStandard =>
        localizations.prefixRouteFamilyDmmStandard,
      WorkImageNormalizationFamily.dmmLeadingOne =>
        localizations.prefixRouteFamilyDmmLeadingOne,
      WorkImageNormalizationFamily.dmmH1711 =>
        localizations.prefixRouteFamilyDmmH1711,
      WorkImageNormalizationFamily.dmmRebeccaH346 =>
        localizations.prefixRouteFamilyDmmRebeccaH346,
      WorkImageNormalizationFamily.mgstagePrestige =>
        localizations.prefixRouteFamilyMgstagePrestige,
      WorkImageNormalizationFamily.mgstageSeikyouiku =>
        localizations.prefixRouteFamilyMgstageSeikyouiku,
    };
  }

  (IconData, String, Color) _candidateStatus(
    BuildContext context,
    WorkImageRouteCandidateStatus status,
  ) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return switch (status) {
      WorkImageRouteCandidateStatus.untested => (
        Icons.hourglass_empty,
        localizations.prefixRouteStatusPending,
        colors.primary,
      ),
      WorkImageRouteCandidateStatus.healthy => (
        Icons.check_circle_outline,
        localizations.prefixRouteStatusVerified,
        colors.tertiary,
      ),
      WorkImageRouteCandidateStatus.degraded => (
        Icons.warning_amber_outlined,
        localizations.prefixRouteStatusExceptions,
        colors.error,
      ),
      WorkImageRouteCandidateStatus.failed => (
        Icons.error_outline,
        localizations.prefixRouteStatusProbeFailed,
        colors.error,
      ),
    };
  }

  (IconData, Color, String) _statusPresentation(
    BuildContext context,
    WorkImagePrefixRouteStatus status,
  ) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return switch (status) {
      WorkImagePrefixRouteStatus.verified => (
        Icons.verified_outlined,
        colors.tertiary,
        localizations.prefixRouteStatusVerified,
      ),
      WorkImagePrefixRouteStatus.hasExceptions => (
        Icons.warning_amber_outlined,
        colors.error,
        localizations.prefixRouteStatusExceptions,
      ),
      WorkImagePrefixRouteStatus.pendingValidation => (
        Icons.hourglass_empty,
        colors.primary,
        localizations.prefixRouteStatusPending,
      ),
      WorkImagePrefixRouteStatus.probeFailed => (
        Icons.error_outline,
        colors.error,
        localizations.prefixRouteStatusProbeFailed,
      ),
    };
  }
}
