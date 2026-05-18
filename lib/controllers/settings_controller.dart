import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.db,
  });

  final AppDatabase db;

  static const String _themeModeKey = 'theme_mode';
  static const String _pureBlackKey = 'pure_black';
  static const String _customThemeKey = 'custom_theme';
  static const String _localeKey = 'app_locale';

  ThemeMode themeMode = ThemeMode.system;
  bool isPureBlack = false;

  String _themeModeString = 'system';
  String _localeString = 'system';

  String get themeModeString => _themeModeString;
  String get localeString => _localeString;

  bool get isCustomTheme => _themeModeString == 'custom';

  Locale? get appLocale => _localeFromString(_localeString);

  /// 提供 UI 使用的主題選項（分層用）
  List<String> getThemeModeOptions() {
    return ['system', 'light', 'dark', 'custom'];
  }

  /// 提供 UI 使用的語言選項（分層用）
  List<String> getLocaleOptions() {
    return ['system', 'zh_TW', 'en'];
  }

  Map<String, Color> customColors = {
    'surface': Colors.black,
    'surfaceContainer': const Color(0xFF121212),
    'onSurface': Colors.white,
    'onSurfaceVariant': Colors.grey,
    'primary': Colors.blueGrey,
    'onPrimary': Colors.black,
    'outline': Colors.grey,
  };

  // 讀取儲存在裝置中的外觀設定，並同步到目前狀態。
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final mode = prefs.getString(_themeModeKey) ?? 'system';
    final pure = prefs.getBool(_pureBlackKey) ?? false;
    final locale = prefs.getString(_localeKey) ?? 'system';

    _themeModeString = mode;
    themeMode = _themeModeFromString(mode);
    isPureBlack = pure;
    _localeString = locale;

    notifyListeners();
  }

  // 提供設定頁目前需要顯示的外觀與語言狀態。
  Map<String, Object> getAppearanceState() {
    return {
      'theme_mode': _themeModeString,
      'is_pure_black': isPureBlack,
      'locale': _localeString,
    };
  }

  // 更新主題模式，並將選擇結果寫入裝置儲存。
  Future<void> themeModeChanged(String mode) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_themeModeKey, mode);

    _themeModeString = mode;
    themeMode = _themeModeFromString(mode);

    notifyListeners();
  }

  // 更新語言，並將選擇結果寫入裝置儲存。
  Future<void> languageChanged(String locale) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_localeKey, locale);

    _localeString = locale;

    notifyListeners();
  }

  // 更新純黑模式，並將選擇結果寫入裝置儲存。
  Future<void> pureBlackChanged(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_pureBlackKey, value);

    isPureBlack = value;

    notifyListeners();
  }

  // 從資料庫讀取自訂主題色，並合併到預設色表。
  Future<void> loadCustomTheme() async {
    final raw = await db.getSetting(_customThemeKey);

    if (raw == null) return;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final merged = Map<String, Color>.from(customColors);

    for (final entry in decoded.entries) {
      merged[entry.key] = Color(entry.value as int);
    }

    customColors = merged;

    notifyListeners();
  }

  // 將目前的自訂主題色寫入資料庫。
  Future<void> saveCustomTheme() async {
    final encoded = jsonEncode(
      customColors.map((key, value) => MapEntry(key, value.toARGB32())),
    );

    await db.setSetting(_customThemeKey, encoded);

    notifyListeners();
  }

  // 將儲存用字串轉成 Flutter 使用的主題模式。
  ThemeMode _themeModeFromString(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'custom' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  // 將儲存用字串轉成 Flutter 使用的 Locale。
  Locale? _localeFromString(String value) {
    return switch (value) {
      'zh_TW' => const Locale('zh', 'TW'),
      'en' => const Locale('en'),
      _ => null,
    };
  }
}