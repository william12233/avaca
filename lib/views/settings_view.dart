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
    return DropdownButtonFormField<String>(
      initialValue: controller.getAppearanceState()['theme_mode'] as String,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).themeMode,
      ),
      items: controller.getThemeModeOptions().map((value) {
        return DropdownMenuItem(
          value: value,
          child: Text(_themeModeLabel(value)),
        );
      }).toList(),
      onChanged: (value) async {
        if (value == null) return;
        await controller.themeModeChanged(value);
      },
    );
  }

  // 語言選擇區塊
  Widget _languageSelector() {
    return DropdownButtonFormField<String>(
      initialValue: controller.getAppearanceState()['locale'] as String,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).language,
      ),
      items: controller.getLocaleOptions().map((value) {
        return DropdownMenuItem(
          value: value,
          child: Text(_localeLabel(value)),
        );
      }).toList(),
      onChanged: (value) async {
        if (value == null) return;
        await controller.languageChanged(value);
      },
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