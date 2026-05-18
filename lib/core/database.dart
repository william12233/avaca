import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'platform_adapter.dart';

class AppDatabase {
  AppDatabase();

  static const String appName = 'AVACA';
  static const String databaseFileName = 'avaca.db';

  late final String baseDir;
  late final String imgDir;
  late final String dbPath;

  Database? _database;
  bool _initialized = false;

  // 初始化資料庫路徑、圖片資料夾與 SQLite 連線。
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    PlatformAdapter.configureSqliteFactory();

    baseDir = await PlatformAdapter.resolveAppBaseDir(
      appName: appName,
    );

    imgDir = path.join(baseDir, 'images');
    dbPath = path.join(baseDir, databaseFileName);

    await Directory(imgDir).create(recursive: true);

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createBaseTable(db);
        await _createSettingsTable(db);
      },
      onOpen: (db) async {
        await _migrateActressesTable(db);
        await _createSettingsTable(db);
      },
    );

    _initialized = true;
  }

  // 取得目前可用的資料庫連線，尚未初始化時會先完成初始化。
  Future<Database> get database async {
    if (!_initialized || _database == null) {
      await init();
    }

    return _database!;
  }

  // 關閉資料庫連線並重置初始化狀態。
  Future<void> close() async {
    final db = _database;

    if (db != null) {
      await db.close();
    }

    _database = null;
    _initialized = false;
  }

  // 建立收藏資料的基礎資料表。
  Future<void> _createBaseTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS actresses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        img_path TEXT,
        modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  // 確保收藏資料表存在，並補齊舊資料庫可能缺少的欄位。
  Future<void> _migrateActressesTable(Database db) async {
    await _createBaseTable(db);

    final columns = await _getTableColumns(db, 'actresses');

    if (!columns.contains('main_type')) {
      await db.execute(
        "ALTER TABLE actresses ADD COLUMN main_type TEXT DEFAULT ''",
      );
    }

    if (!columns.contains('tags')) {
      await db.execute(
        "ALTER TABLE actresses ADD COLUMN tags TEXT DEFAULT ''",
      );
    }

    if (!columns.contains('memo')) {
      await db.execute(
        "ALTER TABLE actresses ADD COLUMN memo TEXT DEFAULT ''",
      );
    }

    if (!columns.contains('height')) {
      await db.execute(
        "ALTER TABLE actresses ADD COLUMN height TEXT DEFAULT ''",
      );
    }

    if (!columns.contains('weight')) {
      await db.execute(
        "ALTER TABLE actresses ADD COLUMN weight TEXT DEFAULT ''",
      );
    }

    if (!columns.contains('bwh')) {
      await db.execute(
        "ALTER TABLE actresses ADD COLUMN bwh TEXT DEFAULT ''",
      );
    }

    if (!columns.contains('cup')) {
      await db.execute(
        "ALTER TABLE actresses ADD COLUMN cup TEXT DEFAULT ''",
      );
    }

    if (!columns.contains('modified_at')) {
      await db.execute(
        'ALTER TABLE actresses ADD COLUMN modified_at TIMESTAMP DEFAULT NULL',
      );
      await db.execute(
        'UPDATE actresses SET modified_at = CURRENT_TIMESTAMP WHERE modified_at IS NULL',
      );
    }
  }

  // 讀取指定資料表目前擁有的欄位名稱。
  Future<Set<String>> _getTableColumns(Database db, String tableName) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');

    return tableInfo
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();
  }

  // 依搜尋、分類與排序條件取得收藏列表。
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    final db = await database;
    final whereClauses = <String>['1=1'];
    final params = <Object?>[];

    if (searchKeyword.isNotEmpty) {
      whereClauses.add('name LIKE ?');
      params.add('%$searchKeyword%');
    }

    if (filterType != '全部') {
      whereClauses.add('main_type LIKE ?');
      params.add('%$filterType%');
    }

    final orderBy = switch (sortBy) {
      '新增時間 (新到舊)' => 'id DESC',
      '新增時間 (舊到新)' => 'id ASC',
      '修改時間 (新到舊)' => 'modified_at DESC',
      '修改時間 (舊到新)' => 'modified_at ASC',
      '名稱 (A-Z)' => 'name ASC',
      '名稱 (Z-A)' => 'name DESC',
      _ => 'id DESC',
    };

    final rows = await db.rawQuery(
      '''
      SELECT id, name, img_path
      FROM actresses
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY $orderBy
      ''',
      params,
    );

    return rows
        .map(
          (row) => {
            'id': row['id'],
            'name': row['name'],
            'img_path': row['img_path'],
          },
        )
        .toList();
  }

  // 依 id 取得單筆收藏的詳細資料。
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    final db = await database;

    final rows = await db.rawQuery(
      '''
      SELECT id, name, img_path, main_type, memo, height, weight, bwh, cup
      FROM actresses
      WHERE id = ?
      ''',
      [actressId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;

    return {
      'id': row['id'],
      'name': row['name'],
      'img_path': row['img_path'],
      'main_type': row['main_type'],
      'memo': row['memo'],
      'height': row['height'],
      'weight': row['weight'],
      'bwh': row['bwh'],
      'cup': row['cup'],
    };
  }

  // 新增一筆收藏資料，若資料庫拒絕寫入則回傳失敗。
  Future<bool> addActress({
    required String name,
    String? imgPath,
    String mainType = '',
    String tags = '',
    String memo = '',
  }) async {
    try {
      final db = await database;

      await db.rawInsert(
        '''
        INSERT INTO actresses (name, img_path, main_type, tags, memo, modified_at)
        VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        [name, imgPath, mainType, tags, memo],
      );

      return true;
    } on DatabaseException {
      return false;
    }
  }

  // 更新指定收藏資料，並同步刷新修改時間。
  Future<bool> updateActress({
    required int actressId,
    required String name,
    String imgPath = '',
    String mainType = '',
    String memo = '',
    String height = '',
    String weight = '',
    String bwh = '',
    String cup = '',
  }) async {
    try {
      final db = await database;

      await db.rawUpdate(
        '''
        UPDATE actresses
        SET name = ?,
            img_path = ?,
            main_type = ?,
            memo = ?,
            height = ?,
            weight = ?,
            bwh = ?,
            cup = ?,
            modified_at = CURRENT_TIMESTAMP
        WHERE id = ?
        ''',
        [
          name,
          imgPath,
          mainType,
          memo,
          height,
          weight,
          bwh,
          cup,
          actressId,
        ],
      );

      return true;
    } on DatabaseException {
      return false;
    }
  }

  // 刪除指定收藏資料，失敗時保留原本的錯誤輸出行為。
  Future<bool> deleteActress(int actressId) async {
    try {
      final db = await database;

      await db.rawDelete(
        'DELETE FROM actresses WHERE id = ?',
        [actressId],
      );

      return true;
    } on DatabaseException catch (error) {
      stderr.writeln('刪除失敗: $error');
      return false;
    }
  }

  // 建立設定資料表。
  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  // 寫入或覆蓋指定設定值。
  Future<void> setSetting(String key, String value) async {
    final db = await database;

    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 讀取指定設定值，不存在時回傳 null。
  Future<String?> getSetting(String key) async {
    final db = await database;

    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first['value'] as String?;
  }

  // 移除指定設定值。
  Future<void> removeSetting(String key) async {
    final db = await database;

    await db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}