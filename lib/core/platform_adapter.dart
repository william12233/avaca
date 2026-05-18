import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 集中處理 Flutter 在不同平台上的差異。
///
/// 這個類別只負責平台相關的判斷、初始化與路徑解析，
/// 不放入任何業務邏輯。
class PlatformAdapter {
  PlatformAdapter._();

  // 平台判斷

  /// 目前平台是否為 Windows。
  static bool get isWindows => Platform.isWindows;

  /// 目前平台是否為 macOS。
  static bool get isMacOS => Platform.isMacOS;

  /// 目前平台是否為 Linux。
  static bool get isLinux => Platform.isLinux;

  /// 目前平台是否為 Android。
  static bool get isAndroid => Platform.isAndroid;

  /// 目前平台是否為 iOS。
  static bool get isIOS => Platform.isIOS;

  /// 目前平台是否屬於桌面平台。
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  /// 目前平台是否屬於行動平台。
  static bool get isMobile => isAndroid || isIOS;

  // SQLite 設定

  /// 目前平台是否需要使用 FFI 版本的 SQLite。
  ///
  /// 目前只套用在 Windows 與 Linux。
  /// macOS 維持原本 sqflite 的行為，避免造成不必要的平台差異。
  static bool get usesFfiSqlite => isWindows || isLinux;

  /// 初始化目前平台需要的 SQLite factory。
  static void configureSqliteFactory() {
    if (!usesFfiSqlite) {
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // App 資料目錄

  /// 解析目前平台的 App 資料根目錄。
  ///
  /// 桌面平台會優先使用各平台慣用的資料目錄。
  /// 行動平台則使用 app documents directory 底下的 avaca_data。
  static Future<String> resolveAppBaseDir({
    required String appName,
  }) async {
    if (isWindows) {
      return _resolveWindowsAppBaseDir(appName);
    }

    if (isMacOS) {
      return _resolveMacOSAppBaseDir(appName);
    }

    if (isLinux) {
      return _resolveLinuxAppBaseDir(appName);
    }

    return _resolveMobileAppBaseDir();
  }

  /// 解析 Windows 的 App 資料根目錄。
  static Future<String> _resolveWindowsAppBaseDir(String appName) async {
    final localAppData = Platform.environment['LOCALAPPDATA'];

    if (localAppData != null && localAppData.isNotEmpty) {
      return path.join(localAppData, appName);
    }

    final supportDir = await getApplicationSupportDirectory();
    return path.join(supportDir.path, appName);
  }

  /// 解析 macOS 的 App 資料根目錄。
  static Future<String> _resolveMacOSAppBaseDir(String appName) async {
    final home = Platform.environment['HOME'];

    if (home != null && home.isNotEmpty) {
      return path.join(home, 'Library', 'Application Support', appName);
    }

    final supportDir = await getApplicationSupportDirectory();
    return path.join(supportDir.path, appName);
  }

  /// 解析 Linux 的 App 資料根目錄。
  static Future<String> _resolveLinuxAppBaseDir(String appName) async {
    final home = Platform.environment['HOME'];

    if (home != null && home.isNotEmpty) {
      return path.join(home, '.local', 'share', appName);
    }

    final supportDir = await getApplicationSupportDirectory();
    return path.join(supportDir.path, appName);
  }

  /// 解析行動平台的 App 資料根目錄。
  static Future<String> _resolveMobileAppBaseDir() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return path.join(documentsDir.path, 'avaca_data');
  }
}