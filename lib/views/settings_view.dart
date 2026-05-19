import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../controllers/settings_controller.dart';
import '../core/database.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.db,
    required this.onThemeChanged,
    required this.onLocaleChanged,
  });

  final AppDatabase db;
  final void Function(
    ThemeMode themeMode,
    bool isPureBlack,
    Map<String, Color>? customColors,
  ) onThemeChanged;
  final void Function(Locale? locale) onLocaleChanged;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final SettingsController controller;

  @override
  void initState() {
    super.initState();
    controller = SettingsController(
      db: widget.db,
    );
    // 載入目前儲存的外觀設定
    controller.loadFromPrefs();
    controller.loadCustomTheme();
    // 監聽設定變更並同步更新畫面
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
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
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(AppLocalizations.of(context).settings),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _themeModeSelector(),
        const SizedBox(height: 8),
        _languageSelector(),
        const SizedBox(height: 8),
        _pureBlackSwitch(),
        if (controller.isCustomTheme) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _customThemeEditor(),
        ],
      ],
    );
  }

  // 主題模式選擇區塊
  Widget _themeModeSelector() {
    final current =
        controller.getAppearanceState()['theme_mode'] as String;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(AppLocalizations.of(context).themeMode),
      trailing: _popupTheme(
        child: PopupMenuButton<String>(
          initialValue: current,
          tooltip: '',
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(999),
          onSelected: (value) async {
            await controller.themeModeChanged(value);
          },
          itemBuilder: (context) {
            return controller.getThemeModeOptions().map((value) {
              return PopupMenuItem(
                value: value,
                child: Text(_themeModeLabel(value)),
              );
            }).toList();
          },
          child: _popupValueText(_themeModeLabel(current)),
        ),
      ),
    );
  }

  // 語言選擇區塊
  Widget _languageSelector() {
    final current =
        controller.getAppearanceState()['locale'] as String;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(AppLocalizations.of(context).language),
      trailing: _popupTheme(
        child: PopupMenuButton<String>(
          initialValue: current,
          tooltip: '',
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(999),
          onSelected: (value) async {
            await controller.languageChanged(value);
          },
          itemBuilder: (context) {
            return controller.getLocaleOptions().map((value) {
              return PopupMenuItem(
                value: value,
                child: Text(_localeLabel(value)),
              );
            }).toList();
          },
          child: _popupValueText(_localeLabel(current)),
        ),
      ),
    );
  }

  Widget _popupTheme({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: colorScheme.primary.withOpacity(0.08),
        highlightColor: colorScheme.primary.withOpacity(0.10),
        splashColor: colorScheme.primary.withOpacity(0.10),
        focusColor: colorScheme.primary.withOpacity(0.08),
      ),
      child: child,
    );
  }

  Widget _popupValueText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  String _themeModeLabel(String value) {
    return switch (value) {
      'system' => AppLocalizations.of(context).followSystem,
      'light' => AppLocalizations.of(context).lightTheme,
      'dark' => AppLocalizations.of(context).darkTheme,
      'custom' => AppLocalizations.of(context).customTheme,
      _ => value,
    };
  }

  String _localeLabel(String value) {
    return switch (value) {
      'system' => AppLocalizations.of(context).followSystem,
      'zh_TW' => AppLocalizations.of(context).traditionalChineseTaiwan,
      'zh_CN' => AppLocalizations.of(context).simplifiedChinese,
      'en' => AppLocalizations.of(context).english,
      _ => value,
    };
  }

  Widget _pureBlackSwitch() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(AppLocalizations.of(context).pureBlackAmoled),
      subtitle: Text(AppLocalizations.of(context).pureBlackOnlyDarkOrCustom),
      value: controller.isPureBlack,
      onChanged: controller.themeMode == ThemeMode.light
          ? null
          : (value) async {
              await controller.pureBlackChanged(value);
            },
    );
  }

  // 自訂主題顏色編輯區塊
  Widget _customThemeEditor() {
    return Column(
      children: controller.customColors.entries.map(_customColorTile).toList(),
    );
  }

  Widget _customColorTile(MapEntry<String, Color> entry) {
    return ListTile(
      title: Text(_colorLabel(entry.key)),
      trailing: _colorPreview(entry.value),
      onTap: () => _openColorPicker(entry.key),
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

  String _colorLabel(String key) {
    return switch (key) {
      'surface' => AppLocalizations.of(context).colorSurface,
      'surfaceContainer' => AppLocalizations.of(context).colorSurfaceContainer,
      'onSurface' => AppLocalizations.of(context).colorOnSurface,
      'onSurfaceVariant' =>
        AppLocalizations.of(context).colorOnSurfaceVariant,
      'primary' => AppLocalizations.of(context).colorPrimary,
      'onPrimary' => AppLocalizations.of(context).colorOnPrimary,
      'outline' => AppLocalizations.of(context).colorOutline,
      _ => key,
    };
  }

  Future<void> _openColorPicker(String key) async {
    Color temp = controller.customColors[key]!;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).adjustColorTitle(_colorLabel(key)),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: temp,
            onColorChanged: (color) => temp = color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () async {
              controller.customColors[key] = temp;
              await controller.saveCustomTheme();
              if (mounted) Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context).apply),
          ),
        ],
      ),
    );
  }
}