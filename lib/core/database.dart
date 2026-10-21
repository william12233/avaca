import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/scraped_actress_details.dart';
import '../models/scrape_job.dart';
import '../models/work.dart';
import '../models/work_storage.dart';
import 'platform_adapter.dart';

typedef ManagedFileDelete = Future<void> Function(File file);
typedef DeleteTransactionCommittedCallback = Future<void> Function();
typedef ManagedImageCanonicalPathResolver = String Function(String path);

class ManagedImageStats {
  const ManagedImageStats({required this.fileCount, required this.totalBytes});

  final int fileCount;
  final int totalBytes;

  Map<String, int> toJson() => {
    'file_count': fileCount,
    'total_bytes': totalBytes,
  };
}

class ManagedFileCleanupReport {
  const ManagedFileCleanupReport({
    this.deleted = const [],
    this.missing = const [],
    this.deferred = const [],
    this.rejected = const [],
    this.emptyDirectoriesRemoved = const [],
    this.records = const [],
    this.deletedCount = 0,
    this.deletedBytes = 0,
    this.missingCount = 0,
    this.deferredCount = 0,
    this.rejectedCount = 0,
  });

  final List<String> deleted;
  final List<String> missing;
  final List<String> deferred;
  final List<String> rejected;
  final List<String> emptyDirectoriesRemoved;
  final List<ManagedFileCleanupRecord> records;
  final int deletedCount;
  final int deletedBytes;
  final int missingCount;
  final int deferredCount;
  final int rejectedCount;

  Map<String, Object?> toJson() => {
    'deleted': deleted,
    'missing': missing,
    'deferred': deferred,
    'rejected': rejected,
    'empty_directories_removed': emptyDirectoriesRemoved,
    'deleted_count': deletedCount,
    'deleted_bytes': deletedBytes,
    'missing_count': missingCount,
    'deferred_count': deferredCount,
    'rejected_count': rejectedCount,
    'records': records.map((record) => record.toJson()).toList(),
  };
}

class ManagedFileCleanupRecord {
  const ManagedFileCleanupRecord({
    required this.kind,
    required this.databaseStoredPath,
    required this.normalizedPath,
    required this.resolvedAbsolutePath,
    required this.managedRoot,
    required this.existsBefore,
    required this.databaseReferenceCount,
    required this.classifyResult,
    required this.deleteResult,
    required this.rejectionReason,
    required this.existsAfter,
    required this.bytesBefore,
  });

  final String kind;
  final String databaseStoredPath;
  final String? normalizedPath;
  final String? resolvedAbsolutePath;
  final String managedRoot;
  final bool existsBefore;
  final int databaseReferenceCount;
  final String classifyResult;
  final String deleteResult;
  final String? rejectionReason;
  final bool existsAfter;
  final int bytesBefore;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'database_stored_path': databaseStoredPath,
    'normalized_path': normalizedPath,
    'resolved_absolute_path': resolvedAbsolutePath,
    'managed_root': managedRoot,
    'exists_before': existsBefore,
    'database_reference_count': databaseReferenceCount,
    'classify_result': classifyResult,
    'delete_result': deleteResult,
    'rejection_reason': rejectionReason,
    'exists_after': existsAfter,
    'bytes_before': bytesBefore,
  };
}

class ActressDeletionSnapshotWork {
  const ActressDeletionSnapshotWork({
    required this.workId,
    required this.cardImagePath,
    required this.detailImagePath,
    required this.actressReferenceCount,
  });

  final int workId;
  final String? cardImagePath;
  final String? detailImagePath;
  final int actressReferenceCount;

  Map<String, Object?> toJson() => {
    'work_id': workId,
    'card_image_path': cardImagePath,
    'detail_image_path': detailImagePath,
    'actress_reference_count': actressReferenceCount,
  };
}

class DatabaseMaintenanceReport {
  const DatabaseMaintenanceReport({
    required this.walCheckpointAttempted,
    required this.vacuumAttempted,
    required this.vacuumCompleted,
  });

  final bool walCheckpointAttempted;
  final bool vacuumAttempted;
  final bool vacuumCompleted;

  Map<String, bool> toJson() => {
    'wal_checkpoint_attempted': walCheckpointAttempted,
    'vacuum_attempted': vacuumAttempted,
    'vacuum_completed': vacuumCompleted,
  };
}

class ActressDeletionReport {
  const ActressDeletionReport({
    required this.databaseCommitted,
    required this.beforeTableCounts,
    required this.afterTableCounts,
    required this.beforeManagedImageStats,
    required this.afterManagedImageStats,
    required this.fileCleanup,
    required this.maintenance,
    required this.cacheEvictionPaths,
    this.actressId,
    this.actressImagePath,
    this.managedRoot = '',
    this.targetActressWorkCount = 0,
    this.snapshotWorks = const [],
    this.uiWorkIds = const [],
    this.deletedActressRows = 0,
    this.deletedActressWorkRows = 0,
    this.orphanWorkIds = const [],
    this.deletedWorkRows = 0,
    this.remainingActressCount = 0,
    this.remainingWorkCount = 0,
    this.remainingActressWorkCount = 0,
    this.pendingFileDeletionsBefore = const [],
    this.pendingFileDeletionsAfter = const [],
  });

  final bool databaseCommitted;
  final Map<String, int> beforeTableCounts;
  final Map<String, int> afterTableCounts;
  final ManagedImageStats beforeManagedImageStats;
  final ManagedImageStats afterManagedImageStats;
  final ManagedFileCleanupReport fileCleanup;
  final DatabaseMaintenanceReport maintenance;
  final List<String> cacheEvictionPaths;
  final int? actressId;
  final String? actressImagePath;
  final String managedRoot;
  final int targetActressWorkCount;
  final List<ActressDeletionSnapshotWork> snapshotWorks;
  final List<int> uiWorkIds;
  final int deletedActressRows;
  final int deletedActressWorkRows;
  final List<int> orphanWorkIds;
  final int deletedWorkRows;
  final int remainingActressCount;
  final int remainingWorkCount;
  final int remainingActressWorkCount;
  final List<String> pendingFileDeletionsBefore;
  final List<String> pendingFileDeletionsAfter;

  int get snapshotWorkCount => snapshotWorks.length;
  List<ManagedFileCleanupRecord> get fileRecords => fileCleanup.records;

  int get deletedBytes => fileCleanup.deletedBytes;

  Map<String, Object?> toJson() => {
    'database_committed': databaseCommitted,
    'actress_id': actressId,
    'actress_img_path': actressImagePath,
    'tables': {'before': beforeTableCounts, 'after': afterTableCounts},
    'database_before': {
      'actress_count': beforeTableCounts['actresses'] ?? 0,
      'work_count': beforeTableCounts['works'] ?? 0,
      'actress_work_count': beforeTableCounts['actress_works'] ?? 0,
      'target_actress_work_count': targetActressWorkCount,
    },
    'snapshot_work_count': snapshotWorkCount,
    'snapshot_works': snapshotWorks.map((work) => work.toJson()).toList(),
    'ui_work_ids': uiWorkIds,
    'transaction': {
      'deleted_actress_rows': deletedActressRows,
      'deleted_actress_work_rows': deletedActressWorkRows,
      'orphan_work_ids': orphanWorkIds,
      'deleted_work_rows': deletedWorkRows,
      'remaining_actress_count': remainingActressCount,
      'remaining_work_count': remainingWorkCount,
      'remaining_actress_work_count': remainingActressWorkCount,
      'database_committed': databaseCommitted,
    },
    'managed_images': {
      'managed_root': managedRoot,
      'before': beforeManagedImageStats.toJson(),
      'after': afterManagedImageStats.toJson(),
      'files_before': beforeManagedImageStats.fileCount,
      'bytes_before': beforeManagedImageStats.totalBytes,
      'deleted_count': fileCleanup.deletedCount,
      'deleted_bytes': deletedBytes,
      'missing_count': fileCleanup.missingCount,
      'deferred_count': fileCleanup.deferredCount,
      'rejected_count': fileCleanup.rejectedCount,
      'files_after': afterManagedImageStats.fileCount,
      'bytes_after': afterManagedImageStats.totalBytes,
    },
    'files': fileRecords.map((record) => record.toJson()).toList(),
    'pending_file_deletions': {
      'before': pendingFileDeletionsBefore,
      'after': pendingFileDeletionsAfter,
    },
    'file_cleanup': fileCleanup.toJson(),
    'maintenance': maintenance.toJson(),
  };
}

/// Auditable result of deleting works globally from the local database.
///
/// A work is shared by zero or more actresses through [actress_works].  The
/// deletion operation removes the selected work rows and every relation in a
/// single transaction, then performs managed-image cleanup after commit.
class WorkDeletionReport {
  const WorkDeletionReport({
    required this.databaseCommitted,
    required this.requestedWorkIds,
    required this.deletedWorkIds,
    required this.deletedWorkRows,
    required this.deletedActressWorkRows,
    required this.fileCleanup,
    required this.cacheEvictionPaths,
    required this.pendingFileDeletionsBefore,
    required this.pendingFileDeletionsAfter,
  });

  final bool databaseCommitted;
  final List<int> requestedWorkIds;
  final List<int> deletedWorkIds;
  final int deletedWorkRows;
  final int deletedActressWorkRows;
  final ManagedFileCleanupReport fileCleanup;
  final List<String> cacheEvictionPaths;
  final List<String> pendingFileDeletionsBefore;
  final List<String> pendingFileDeletionsAfter;

  Map<String, Object?> toJson() => {
    'database_committed': databaseCommitted,
    'requested_work_ids': requestedWorkIds,
    'deleted_work_ids': deletedWorkIds,
    'deleted_work_rows': deletedWorkRows,
    'deleted_actress_work_rows': deletedActressWorkRows,
    'cache_eviction_paths': cacheEvictionPaths,
    'pending_file_deletions': {
      'before': pendingFileDeletionsBefore,
      'after': pendingFileDeletionsAfter,
    },
    'file_cleanup': fileCleanup.toJson(),
  };
}

class AppDatabase {
  static const int _sqliteBindBatchSize = 500;

  AppDatabase()
    : _baseDirOverride = null,
      _databaseFactoryOverride = null,
      _deleteFileOverride = null,
      _afterDeleteTransactionCommitted = null,
      _managedImageCanonicalPathResolver = null;

  AppDatabase.forTesting({
    required String baseDir,
    required DatabaseFactory databaseFactory,
    ManagedFileDelete? deleteFile,
    DeleteTransactionCommittedCallback? afterDeleteTransactionCommitted,
    ManagedImageCanonicalPathResolver? managedImageCanonicalPathResolver,
  }) : _baseDirOverride = baseDir,
       _databaseFactoryOverride = databaseFactory,
       _deleteFileOverride = deleteFile,
       _afterDeleteTransactionCommitted = afterDeleteTransactionCommitted,
       _managedImageCanonicalPathResolver = managedImageCanonicalPathResolver;

  static const String appName = 'AVACA';
  static const String databaseFileName = 'avaca.db';

  late final String baseDir;
  late final String imgDir;
  late final String dbPath;

  final String? _baseDirOverride;
  final DatabaseFactory? _databaseFactoryOverride;
  final ManagedFileDelete? _deleteFileOverride;
  final DeleteTransactionCommittedCallback? _afterDeleteTransactionCommitted;
  final ManagedImageCanonicalPathResolver? _managedImageCanonicalPathResolver;
  Database? _database;
  bool _initialized = false;
  Future<void> _managedImageLifecycleTail = Future.value();
  static final Object _managedImageLifecycleZoneKey = Object();

  // 讓圖片檔寫入與資料庫參照成為一個不可交錯的生命週期。
  Future<T> runManagedImageLifecycle<T>(Future<T> Function() operation) async {
    final owner = Zone.current[_managedImageLifecycleZoneKey];
    if (owner is _ManagedImageLifecycleOwner &&
        identical(owner.database, this) &&
        owner.acceptingNestedOperations) {
      return owner.runNested(operation);
    }
    final previous = _managedImageLifecycleTail;
    final completed = Completer<void>();
    _managedImageLifecycleTail = completed.future;
    await previous;
    final lifecycleOwner = _ManagedImageLifecycleOwner(this);
    try {
      return await runZoned(
        operation,
        zoneValues: {_managedImageLifecycleZoneKey: lifecycleOwner},
      );
    } finally {
      await lifecycleOwner.close();
      completed.complete();
    }
  }

  // 初始化資料庫路徑、圖片資料夾與 SQLite 連線。
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    if (_databaseFactoryOverride == null) {
      PlatformAdapter.configureSqliteFactory();
    }

    baseDir =
        _baseDirOverride ??
        await PlatformAdapter.resolveAppBaseDir(appName: appName);

    imgDir = path.join(baseDir, 'images');
    dbPath = path.join(baseDir, databaseFileName);

    await Directory(imgDir).create(recursive: true);

    final options = OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createBaseTable(db);
        await _createSettingsTable(db);
        await _createWorksTables(db);
        await _createOperationalTables(db);
      },
      onOpen: (db) async {
        await _migrateActressesTable(db);
        await _createSettingsTable(db);
        await _createWorksTables(db);
        await _createOperationalTables(db);
      },
    );
    final factory = _databaseFactoryOverride;
    _database = factory == null
        ? await openDatabase(
            dbPath,
            version: options.version,
            onConfigure: options.onConfigure,
            onCreate: options.onCreate,
            onOpen: options.onOpen,
          )
        : await factory.openDatabase(dbPath, options: options);

    _initialized = true;
    final startupCleanup = await _flushPendingFileDeletions(_database!);
    _writeStructuredResult(
      'pending_file_deletions_startup_retry',
      () => {'file_cleanup': startupCleanup.toJson()},
    );
  }

  // 取得目前可用的資料庫連線，尚未初始化時會先完成初始化。
  Future<Database> get database async {
    if (!_initialized || _database == null) {
      await init();
    }

    return _database!;
  }

  /// Runs a portable-data import inside the same serialized image lifecycle
  /// used by the normal CRUD flows. Callers must finish writing any referenced
  /// managed files before invoking this transaction.
  Future<T> runDataTransferTransaction<T>(
    Future<T> Function(DatabaseExecutor transaction) operation,
  ) {
    return runManagedImageLifecycle(() async {
      final db = await database;
      return db.transaction(operation);
    });
  }

  /// Resolves an existing stored image only when it is a valid managed image.
  /// Portable export code must never copy an arbitrary absolute path.
  Future<File?> resolveManagedImageForTransfer(String? imagePath) async {
    final value = imagePath?.trim();
    if (value == null || value.isEmpty) return null;
    final validated = await _validateManagedImage(value);
    return validated.exists ? validated.resolvedFile : null;
  }

  /// Flushes pending managed-file deletions after an import transaction has
  /// committed new references.
  Future<ManagedFileCleanupReport> flushDataTransferFileDeletions() async {
    final db = await database;
    return _flushPendingFileDeletions(db);
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
        birth_date TEXT,
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
      await db.execute("ALTER TABLE actresses ADD COLUMN tags TEXT DEFAULT ''");
    }

    if (!columns.contains('memo')) {
      await db.execute("ALTER TABLE actresses ADD COLUMN memo TEXT DEFAULT ''");
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
      await db.execute("ALTER TABLE actresses ADD COLUMN bwh TEXT DEFAULT ''");
    }

    if (!columns.contains('cup')) {
      await db.execute("ALTER TABLE actresses ADD COLUMN cup TEXT DEFAULT ''");
    }

    if (!columns.contains('modified_at')) {
      await db.execute(
        'ALTER TABLE actresses ADD COLUMN modified_at TIMESTAMP DEFAULT NULL',
      );
      await db.execute(
        'UPDATE actresses SET modified_at = CURRENT_TIMESTAMP WHERE modified_at IS NULL',
      );
    }

    if (!columns.contains('birth_date')) {
      await db.execute(
        'ALTER TABLE actresses ADD COLUMN birth_date TEXT DEFAULT NULL',
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

  // 建立作品資料與女優、作品多對多關聯。
  Future<void> _createWorksTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS works (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL COLLATE NOCASE UNIQUE,
        title TEXT NOT NULL,
        release_date TEXT,
        duration_minutes INTEGER,
        studio TEXT,
        publisher TEXT,
        series TEXT,
        card_image_path TEXT,
        detail_image_path TEXT,
        is_stored INTEGER NOT NULL DEFAULT 0,
        storage_quality TEXT,
        storage_frame_rate INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    final columns = await _getTableColumns(db, 'works');
    if (!columns.contains('is_stored')) {
      await db.execute(
        'ALTER TABLE works ADD COLUMN is_stored INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columns.contains('storage_quality')) {
      await db.execute('ALTER TABLE works ADD COLUMN storage_quality TEXT');
    }
    if (!columns.contains('storage_frame_rate')) {
      await db.execute(
        'ALTER TABLE works ADD COLUMN storage_frame_rate INTEGER',
      );
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS actress_works (
        actress_id INTEGER NOT NULL,
        work_id INTEGER NOT NULL,
        PRIMARY KEY (actress_id, work_id),
        FOREIGN KEY (actress_id) REFERENCES actresses(id) ON DELETE CASCADE,
        FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_performers (
        work_id INTEGER NOT NULL,
        source TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE,
        source_uri TEXT,
        PRIMARY KEY (work_id, source, name),
        FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS actress_aliases (
        actress_id INTEGER NOT NULL,
        alias TEXT NOT NULL COLLATE NOCASE,
        PRIMARY KEY (actress_id, alias),
        FOREIGN KEY (actress_id) REFERENCES actresses(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_actress_aliases_actress '
      'ON actress_aliases(actress_id, alias COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_actress_works_work '
      'ON actress_works(work_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_file_deletions (
        path TEXT PRIMARY KEY
      )
    ''');
  }

  // Operational tables are additive and idempotent so existing version-1
  // databases receive the same schema on open without rewriting user data.
  Future<void> _createOperationalTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_field_provenance (
        work_id INTEGER NOT NULL,
        field TEXT NOT NULL,
        source TEXT NOT NULL,
        source_uri TEXT,
        observed_at TEXT,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (work_id, field),
        FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_work_field_provenance_source '
      'ON work_field_provenance(source, field)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scrape_jobs (
        id TEXT PRIMARY KEY,
        actress_id INTEGER NOT NULL,
        actress_name_snapshot TEXT NOT NULL,
        state TEXT NOT NULL,
        phase TEXT NOT NULL,
        options_snapshot TEXT NOT NULL,
        source_settings_snapshot TEXT NOT NULL,
        rules_version_snapshot TEXT NOT NULL,
        rules_snapshot TEXT NOT NULL,
        retry_target_codes TEXT NOT NULL DEFAULT '[]',
        discovered_count INTEGER NOT NULL DEFAULT 0,
        raw_discovered_count INTEGER NOT NULL DEFAULT 0,
        duplicate_count INTEGER NOT NULL DEFAULT 0,
        detail_completed_count INTEGER NOT NULL DEFAULT 0,
        detail_total_count INTEGER NOT NULL DEFAULT 0,
        processed_count INTEGER NOT NULL DEFAULT 0,
        saved_count INTEGER NOT NULL DEFAULT 0,
        excluded_count INTEGER NOT NULL DEFAULT 0,
        failed_count INTEGER NOT NULL DEFAULT 0,
        review_count INTEGER NOT NULL DEFAULT 0,
        supplemental_evidence_completed_count INTEGER NOT NULL DEFAULT 0,
        supplemental_evidence_total_count INTEGER NOT NULL DEFAULT 0,
        image_failure_count INTEGER NOT NULL DEFAULT 0,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        started_at TEXT,
        updated_at TEXT NOT NULL,
        finished_at TEXT,
        last_error TEXT,
        FOREIGN KEY (actress_id) REFERENCES actresses(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scrape_jobs_actress_state '
      'ON scrape_jobs(actress_id, state, updated_at DESC)',
    );
    final scrapeJobColumns = await _getTableColumns(db, 'scrape_jobs');
    for (final column in const {
      'raw_discovered_count': 'INTEGER NOT NULL DEFAULT 0',
      'duplicate_count': 'INTEGER NOT NULL DEFAULT 0',
      'detail_completed_count': 'INTEGER NOT NULL DEFAULT 0',
      'detail_total_count': 'INTEGER NOT NULL DEFAULT 0',
      'review_count': 'INTEGER NOT NULL DEFAULT 0',
      'supplemental_evidence_completed_count': 'INTEGER NOT NULL DEFAULT 0',
      'supplemental_evidence_total_count': 'INTEGER NOT NULL DEFAULT 0',
    }.entries) {
      if (!scrapeJobColumns.contains(column.key)) {
        await db.execute(
          'ALTER TABLE scrape_jobs ADD COLUMN ${column.key} ${column.value}',
        );
      }
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scrape_jobs_state_updated '
      'ON scrape_jobs(state, updated_at DESC)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_scrape_jobs_one_active_per_actress
      ON scrape_jobs(actress_id)
      WHERE state IN ('queued', 'running', 'paused', 'waiting_for_verification')
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scrape_job_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id TEXT NOT NULL,
        canonical_code TEXT NOT NULL,
        observed_raw_code TEXT,
        state TEXT NOT NULL,
        stage TEXT,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(job_id, canonical_code),
        FOREIGN KEY (job_id) REFERENCES scrape_jobs(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scrape_job_items_job_state '
      'ON scrape_job_items(job_id, state, updated_at DESC)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scrape_job_source_progress (
        job_id TEXT NOT NULL,
        source TEXT NOT NULL,
        phase TEXT NOT NULL,
        current_value INTEGER NOT NULL DEFAULT 0,
        total_value INTEGER NOT NULL DEFAULT 0,
        total_known INTEGER NOT NULL DEFAULT 0,
        work_code TEXT,
        discovered_count INTEGER NOT NULL DEFAULT 0,
        state TEXT,
        last_error TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (job_id, source),
        FOREIGN KEY (job_id) REFERENCES scrape_jobs(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scrape_job_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_id TEXT NOT NULL,
        item_id INTEGER,
        canonical_code TEXT,
        source TEXT,
        severity TEXT NOT NULL,
        stage TEXT NOT NULL,
        message TEXT NOT NULL,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        FOREIGN KEY (job_id) REFERENCES scrape_jobs(id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES scrape_job_items(id) ON DELETE SET NULL
      )
    ''');
    final sourceProgressColumns = await _getTableColumns(
      db,
      'scrape_job_source_progress',
    );
    if (!sourceProgressColumns.contains('discovered_count')) {
      await db.execute(
        'ALTER TABLE scrape_job_source_progress '
        'ADD COLUMN discovered_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scrape_job_events_job_time '
      'ON scrape_job_events(job_id, created_at DESC, id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scrape_job_events_source_severity '
      'ON scrape_job_events(source, severity, created_at DESC)',
    );
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
      '修改時間 (新到舊)' => 'modified_at DESC, id DESC',
      '修改時間 (舊到新)' => 'modified_at ASC, id DESC',
      '年齡 (低到高)' => 'birth_date IS NULL, birth_date DESC, id DESC',
      '年齡 (高到低)' => 'birth_date IS NULL, birth_date ASC, id DESC',
      '名稱 (A-Z)' => 'name ASC',
      '名稱 (Z-A)' => 'name DESC',
      _ => 'id DESC',
    };

    final rows = await db.rawQuery('''
      SELECT id, name, img_path
      FROM actresses
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY $orderBy
      ''', params);

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
      SELECT id, name, img_path, main_type, memo, height, weight, bwh, cup,
             birth_date
      FROM actresses
      WHERE id = ?
      ''',
      [actressId],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final aliases = await getActressAliases(actressId);

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
      'birth_date': row['birth_date'],
      'aliases': aliases,
    };
  }

  /// Returns the stored aliases for an actress in deterministic NOCASE order.
  Future<List<String>> getActressAliases(int actressId) async {
    final db = await database;
    final rows = await db.query(
      'actress_aliases',
      columns: ['alias'],
      where: 'actress_id = ?',
      whereArgs: [actressId],
      orderBy: 'alias COLLATE NOCASE ASC',
    );
    return rows
        .map((row) => row['alias']?.toString())
        .whereType<String>()
        .toList(growable: false);
  }

  /// Replaces an actress's aliases after trimming, deduplicating (NOCASE), and
  /// excluding the canonical actress name.
  Future<void> replaceActressAliases({
    required int actressId,
    required Iterable<String> aliases,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final actressRows = await transaction.query(
        'actresses',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [actressId],
        limit: 1,
      );
      if (actressRows.isEmpty) {
        throw StateError('Actress $actressId does not exist.');
      }
      final canonical = actressRows.single['name']?.toString().trim() ?? '';
      final canonicalKey = canonical.toLowerCase();
      final normalized = <String>[];
      final seen = <String>{};
      for (final source in aliases) {
        final value = source.trim();
        if (value.isEmpty) {
          continue;
        }
        final key = value.toLowerCase();
        if (key == canonicalKey || !seen.add(key)) {
          continue;
        }
        normalized.add(value);
      }

      await transaction.delete(
        'actress_aliases',
        where: 'actress_id = ?',
        whereArgs: [actressId],
      );
      for (final alias in normalized) {
        await transaction.insert('actress_aliases', {
          'actress_id': actressId,
          'alias': alias,
        });
      }
    });
  }

  static const _workColumns = <String>[
    'id',
    'code',
    'title',
    'release_date',
    'duration_minutes',
    'studio',
    'publisher',
    'series',
    'card_image_path',
    'detail_image_path',
    'is_stored',
    'storage_quality',
    'storage_frame_rate',
  ];

  // 取得指定女優的本機作品，最新發行日期優先。
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT ${_workColumns.map((column) => 'w.$column').join(', ')}
      FROM works w
      INNER JOIN actress_works aw ON aw.work_id = w.id
      WHERE aw.actress_id = ?
      ORDER BY w.release_date IS NULL, w.release_date DESC, w.id DESC
      ''',
      [actressId],
    );
  }

  // 依作品 id 取得詳細資料。
  Future<Map<String, Object?>?> getWorkById(
    int workId, {
    int? currentActressId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'works',
      columns: _workColumns,
      where: 'id = ?',
      whereArgs: [workId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final work = Map<String, Object?>.from(rows.first);
    work['related_performers'] = await _getRelatedPerformers(
      db,
      workId,
      currentActressId: currentActressId,
    );
    final provenanceRows = await db.query(
      'work_field_provenance',
      columns: const [
        'field',
        'source',
        'source_uri',
        'observed_at',
        'updated_at',
      ],
      where: 'work_id = ?',
      whereArgs: [workId],
      orderBy: 'field ASC',
    );
    work['field_provenance'] = provenanceRows
        .map((row) {
          final item = WorkFieldProvenance.fromRow(row);
          return <String, Object?>{
            'field': item.field,
            'source': item.source,
            'source_uri': item.sourceUri?.toString(),
            'observed_at': item.observedAt?.toIso8601String(),
          };
        })
        .toList(growable: false);
    return work;
  }

  Future<void> updateWorkStorage({
    required int workId,
    required WorkStorageRecord record,
  }) async {
    if (!WorkStorageRecord.qualities.contains(record.quality) ||
        !WorkStorageRecord.frameRates.contains(record.frameRate)) {
      throw ArgumentError('Unsupported work storage settings.');
    }
    final db = await database;
    final updated = await db.update(
      'works',
      {
        ...record.toDatabaseMap(),
        'modified_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [workId],
    );
    if (updated == 0) {
      throw StateError('Work $workId was not found.');
    }
  }

  Future<List<Map<String, Object?>>> _getRelatedPerformers(
    DatabaseExecutor executor,
    int workId, {
    int? currentActressId,
  }) async {
    final rows = await executor.query(
      'work_performers',
      columns: ['name', 'source', 'source_uri'],
      where: 'work_id = ?',
      whereArgs: [workId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final currentActressNames = <String>{};
    if (currentActressId != null) {
      final currentRows = await executor.query(
        'actresses',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [currentActressId],
        limit: 1,
      );
      final currentName = currentRows.firstOrNull?['name']?.toString().trim();
      if (currentName != null && currentName.isNotEmpty) {
        currentActressNames.add(currentName.toLowerCase());
      }
      final aliasRows = await executor.query(
        'actress_aliases',
        columns: ['alias'],
        where: 'actress_id = ?',
        whereArgs: [currentActressId],
      );
      for (final aliasRow in aliasRows) {
        final alias = aliasRow['alias']?.toString().trim();
        if (alias != null && alias.isNotEmpty) {
          currentActressNames.add(alias.toLowerCase());
        }
      }
    }
    final performerNames = rows
        .map((row) => row['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .map((name) => name.toLowerCase())
        .where((name) => !currentActressNames.contains(name))
        .toSet();
    final canonicalIds = <String, Set<int>>{};
    final aliasIds = <String, Set<int>>{};
    if (performerNames.isNotEmpty) {
      final placeholders = List.filled(performerNames.length, '?').join(', ');
      final arguments = performerNames.toList(growable: false);
      final canonicalRows = await executor.rawQuery(
        'SELECT id, name FROM actresses '
        'WHERE lower(name) IN ($placeholders)',
        arguments,
      );
      for (final row in canonicalRows) {
        final key = row['name']!.toString().trim().toLowerCase();
        canonicalIds.putIfAbsent(key, () => <int>{}).add(row['id'] as int);
      }
      final aliasRows = await executor.rawQuery(
        'SELECT DISTINCT aa.alias, a.id FROM actress_aliases aa '
        'INNER JOIN actresses a ON a.id = aa.actress_id '
        'WHERE lower(aa.alias) IN ($placeholders)',
        arguments,
      );
      for (final row in aliasRows) {
        final key = row['alias']!.toString().trim().toLowerCase();
        aliasIds.putIfAbsent(key, () => <int>{}).add(row['id'] as int);
      }
    }

    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final name = row['name']?.toString().trim() ?? '';
      final key = name.toLowerCase();
      if (name.isEmpty || currentActressNames.contains(key)) continue;
      final canonical = canonicalIds[key] ?? const <int>{};
      final aliases = aliasIds[key] ?? const <int>{};
      final matches = canonical.isNotEmpty ? canonical : aliases;
      final actressId = matches.length == 1 ? matches.single : null;
      result.add({
        'name': name,
        'source': row['source'],
        'source_uri': row['source_uri'],
        'actress_id': actressId,
      });
    }
    return List.unmodifiable(result);
  }

  // 計算指定女優目前在本機建立關聯的作品數。
  Future<int> getWorkCountForActress(int actressId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM actress_works WHERE actress_id = ?',
      [actressId],
    );
    return (rows.single['count'] as num?)?.toInt() ?? 0;
  }

  // 新增或更新作品；missingOnly 模式僅補齊尚未儲存的欄位。
  Future<int> upsertWork(Work work, {bool missingOnly = false}) async {
    return runManagedImageLifecycle(() async {
      final db = await database;
      return db.transaction(
        (transaction) =>
            _upsertWork(transaction, work, missingOnly: missingOnly),
      );
    });
  }

  // 寫入作品並以不可重複的關聯連結至女優。
  Future<int> upsertActressWork({
    required int actressId,
    required Work work,
    bool missingOnly = false,
    String? performerSource,
    Iterable<WorkPerformer>? performers,
    Iterable<WorkFieldProvenance>? provenance,
  }) async {
    return runManagedImageLifecycle(() async {
      final db = await database;
      return db.transaction((transaction) async {
        final existingRows = await transaction.query(
          'works',
          columns: _workColumns,
          where: 'code = ? COLLATE NOCASE',
          whereArgs: [work.code.trim().toUpperCase()],
          limit: 1,
        );
        final workId = await _upsertWork(
          transaction,
          work,
          missingOnly: missingOnly,
        );
        if (provenance != null) {
          await _upsertWorkProvenance(
            transaction,
            workId: workId,
            work: work,
            missingOnly: missingOnly,
            provenance: provenance,
            existing: existingRows.firstOrNull,
          );
        }
        await transaction.insert('actress_works', {
          'actress_id': actressId,
          'work_id': workId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (performerSource != null && performers != null) {
          await _replaceWorkPerformers(
            transaction,
            workId: workId,
            source: performerSource,
            performers: performers,
          );
        }
        return workId;
      });
    });
  }

  Future<void> _upsertWorkProvenance(
    DatabaseExecutor executor, {
    required int workId,
    required Work work,
    required bool missingOnly,
    required Iterable<WorkFieldProvenance> provenance,
    required Map<String, Object?>? existing,
  }) async {
    final values = work.toDatabaseMap();
    const fields = <String>{
      'title',
      'release_date',
      'duration_minutes',
      'studio',
      'publisher',
      'series',
    };
    for (final entry in provenance) {
      if (!fields.contains(entry.field)) continue;
      final incoming = values[entry.field];
      if (incoming == null || incoming.toString().trim().isEmpty) continue;
      final previous = existing?[entry.field];
      final previousIsPresent =
          previous != null && previous.toString().trim().isNotEmpty;
      if (missingOnly && previousIsPresent) continue;
      await executor.insert(
        'work_field_provenance',
        entry.copyWith(workId: workId).toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _replaceWorkPerformers(
    DatabaseExecutor executor, {
    required int workId,
    required String source,
    required Iterable<WorkPerformer> performers,
  }) async {
    await executor.delete(
      'work_performers',
      where: 'work_id = ? AND source = ?',
      whereArgs: [workId, source],
    );
    final seen = <String>{};
    for (final performer in performers) {
      final name = performer.name.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) {
        continue;
      }
      await executor.insert('work_performers', {
        'work_id': workId,
        'source': source,
        'name': name,
        'source_uri': performer.sourceUri?.toString(),
      });
    }
  }

  /// Merge legacy work rows that are known aliases of [canonicalCode].
  ///
  /// The canonical row is retained (or the first alias is renamed when it is
  /// the only available row).  All actress relations are moved to that row;
  /// legacy image paths are queued for managed cleanup instead of being
  /// copied into the canonical work.
  Future<int> mergeWorkCodeAliases({
    required String canonicalCode,
    required Iterable<String> aliasCodes,
  }) async {
    final canonical = canonicalCode.trim().toUpperCase();
    if (canonical.isEmpty) {
      throw ArgumentError('Canonical work code must not be empty.');
    }
    final aliases = <String>{};
    for (final alias in aliasCodes) {
      final value = alias.trim();
      if (value.isEmpty || value.toUpperCase() == canonical) {
        continue;
      }
      aliases.add(value.toUpperCase());
    }
    if (aliases.isEmpty) {
      return 0;
    }

    return runManagedImageLifecycle(() async {
      final db = await database;
      final merged = await db.transaction<int>((transaction) async {
        final canonicalRows = await transaction.query(
          'works',
          columns: ['id'],
          where: 'code = ? COLLATE NOCASE',
          whereArgs: [canonical],
          limit: 1,
        );
        var canonicalId = canonicalRows.isEmpty
            ? null
            : canonicalRows.single['id'] as int;
        var count = 0;

        for (final alias in aliases) {
          final aliasRows = await transaction.query(
            'works',
            columns: ['id', 'card_image_path', 'detail_image_path'],
            where: 'code = ? COLLATE NOCASE',
            whereArgs: [alias],
            limit: 1,
          );
          if (aliasRows.isEmpty) {
            continue;
          }
          final aliasRow = aliasRows.single;
          final aliasId = aliasRow['id'] as int;
          if (canonicalId == aliasId) {
            continue;
          }

          final oldImagePaths = [
            aliasRow['card_image_path']?.toString(),
            aliasRow['detail_image_path']?.toString(),
          ].where((value) => value != null && value.trim().isNotEmpty);
          for (final oldImagePath in oldImagePaths) {
            await transaction.insert(
              'pending_file_deletions',
              {'path': oldImagePath},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }

          if (canonicalId == null) {
            await transaction.rawUpdate(
              '''
              UPDATE works
              SET code = ?, card_image_path = NULL, detail_image_path = NULL,
                  modified_at = CURRENT_TIMESTAMP
              WHERE id = ?
              ''',
              [canonical, aliasId],
            );
            canonicalId = aliasId;
            count++;
            continue;
          }

          await transaction.rawInsert(
            '''
            INSERT OR IGNORE INTO actress_works (actress_id, work_id)
            SELECT actress_id, ? FROM actress_works WHERE work_id = ?
            ''',
            [canonicalId, aliasId],
          );
          await transaction.rawInsert(
            '''
            INSERT OR IGNORE INTO work_performers
              (work_id, source, name, source_uri)
            SELECT ?, source, name, source_uri
            FROM work_performers
            WHERE work_id = ?
            ''',
            [canonicalId, aliasId],
          );
          await transaction.delete(
            'actress_works',
            where: 'work_id = ?',
            whereArgs: [aliasId],
          );
          await transaction.delete(
            'works',
            where: 'id = ?',
            whereArgs: [aliasId],
          );
          count++;
        }
        return count;
      });
      if (merged > 0) {
        await _flushPendingFileDeletions(db);
      }
      return merged;
    });
  }

  Future<int> _upsertWork(
    DatabaseExecutor executor,
    Work work, {
    required bool missingOnly,
  }) async {
    final values = work.toDatabaseMap();
    final code = values['code'] as String;
    final title = values['title'] as String;
    if (code.isEmpty || title.isEmpty) {
      throw ArgumentError('Work code and title must not be empty.');
    }

    final existing = await executor.query(
      'works',
      columns: ['id'],
      where: 'code = ? COLLATE NOCASE',
      whereArgs: [code],
      limit: 1,
    );
    if (existing.isEmpty) {
      return executor.insert('works', values);
    }

    final workId = existing.single['id'] as int;
    const updatable = <String>[
      'title',
      'release_date',
      'duration_minutes',
      'studio',
      'publisher',
      'series',
      'card_image_path',
      'detail_image_path',
    ];
    final assignments = updatable
        .map((column) {
          if (missingOnly) {
            return '$column = CASE '
                "WHEN $column IS NULL OR TRIM(CAST($column AS TEXT)) = '' "
                'THEN COALESCE(?, $column) ELSE $column END';
          }
          return '$column = COALESCE(?, $column)';
        })
        .join(', ');
    await executor.rawUpdate(
      '''
      UPDATE works
      SET $assignments, modified_at = CURRENT_TIMESTAMP
      WHERE id = ?
      ''',
      [...updatable.map((column) => values[column]), workId],
    );
    return workId;
  }

  // 合併刮削到的女優詳細資料，體重永遠不由刮削流程修改。
  Future<bool> syncActressDetails({
    required int actressId,
    required ScrapedActressDetails details,
    bool missingOnly = false,
    bool replaceImage = false,
  }) {
    return runManagedImageLifecycle(
      () => _syncActressDetails(
        actressId: actressId,
        details: details,
        missingOnly: missingOnly,
        replaceImage: replaceImage,
      ),
    );
  }

  Future<bool> _syncActressDetails({
    required int actressId,
    required ScrapedActressDetails details,
    required bool missingOnly,
    required bool replaceImage,
  }) async {
    final normalizedBirthDate = _normalizeBirthDate(details.birthDate);
    final db = await database;
    final rows = await db.query(
      'actresses',
      columns: ['name', 'img_path', 'height', 'bwh', 'cup', 'birth_date'],
      where: 'id = ?',
      whereArgs: [actressId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    final current = rows.single;

    Object? merged(String column, String? incoming) {
      final value = incoming?.trim();
      if (value == null || value.isEmpty) {
        return current[column];
      }
      if (!missingOnly) {
        return value;
      }
      final existing = current[column]?.toString().trim() ?? '';
      return existing.isEmpty ? value : current[column];
    }

    final imageValue = details.imagePath?.trim();
    final mergedName = merged('name', details.name);
    try {
      await db.transaction((transaction) async {
        await transaction.update(
          'actresses',
          {
            'name': mergedName,
            'img_path':
                replaceImage && imageValue != null && imageValue.isNotEmpty
                ? imageValue
                : current['img_path'],
            'height': merged('height', details.height),
            'bwh': merged('bwh', details.bwh),
            'cup': merged('cup', details.cup),
            'birth_date': merged(
              'birth_date',
              normalizedBirthDate.valid ? normalizedBirthDate.value : null,
            ),
            'modified_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [actressId],
        );
        final canonical = mergedName?.toString().trim() ?? '';
        if (canonical.isNotEmpty) {
          await transaction.delete(
            'actress_aliases',
            where: 'actress_id = ? AND alias = ? COLLATE NOCASE',
            whereArgs: [actressId, canonical],
          );
        }
      });
      return true;
    } on DatabaseException {
      return false;
    }
  }

  // 新增一筆收藏資料，若資料庫拒絕寫入則回傳失敗。
  Future<bool> addActress({
    required String name,
    String? imgPath,
    String mainType = '',
    String tags = '',
    String memo = '',
    String? birthDate,
  }) async {
    final normalizedBirthDate = _normalizeBirthDate(birthDate);
    if (!normalizedBirthDate.valid) {
      return false;
    }

    return runManagedImageLifecycle(
      () => _addActress(
        name: name,
        imgPath: imgPath,
        mainType: mainType,
        tags: tags,
        memo: memo,
        birthDate: normalizedBirthDate.value,
      ),
    );
  }

  Future<bool> _addActress({
    required String name,
    required String? imgPath,
    required String mainType,
    required String tags,
    required String memo,
    required String? birthDate,
  }) async {
    try {
      final db = await database;

      await db.rawInsert(
        '''
        INSERT INTO actresses (
          name, img_path, main_type, tags, memo, birth_date, modified_at
        )
        VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        [name, imgPath, mainType, tags, memo, birthDate],
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
    String? birthDate,
  }) {
    return runManagedImageLifecycle(
      () => _updateActress(
        actressId: actressId,
        name: name,
        imgPath: imgPath,
        mainType: mainType,
        memo: memo,
        height: height,
        weight: weight,
        bwh: bwh,
        cup: cup,
        birthDate: birthDate,
      ),
    );
  }

  Future<bool> _updateActress({
    required int actressId,
    required String name,
    required String imgPath,
    required String mainType,
    required String memo,
    required String height,
    required String weight,
    required String bwh,
    required String cup,
    required String? birthDate,
  }) async {
    final normalizedBirthDate = _normalizeBirthDate(birthDate);
    if (!normalizedBirthDate.valid) {
      return false;
    }

    try {
      final db = await database;

      await db.transaction((transaction) async {
        await transaction.rawUpdate(
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
              birth_date = ?,
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
            normalizedBirthDate.value,
            actressId,
          ],
        );
        await transaction.delete(
          'actress_aliases',
          where: 'actress_id = ? AND alias = ? COLLATE NOCASE',
          whereArgs: [actressId, name.trim()],
        );
      });

      return true;
    } on DatabaseException {
      return false;
    }
  }

  ({bool valid, String? value}) _normalizeBirthDate(String? birthDate) {
    final value = birthDate?.trim();
    if (value == null || value.isEmpty) {
      return (valid: true, value: null);
    }

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return (valid: false, value: null);
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year < 1900 ||
        _formatIsoDate(parsed) != value) {
      return (valid: false, value: null);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(parsed.year, parsed.month, parsed.day);
    if (date.isAfter(today)) {
      return (valid: false, value: null);
    }

    return (valid: true, value: value);
  }

  String _formatIsoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // 刪除指定收藏資料。保留布林入口供既有呼叫端使用。
  Future<bool> deleteActress(int actressId) async {
    return (await deleteActressWithReport(actressId)).databaseCommitted;
  }

  /// Deletes selected work rows globally, including every actress relation.
  ///
  /// Database rows and pending managed-file paths are committed atomically;
  /// physical files are validated and removed only after the transaction.
  Future<WorkDeletionReport> deleteWorksWithReport(
    Iterable<int> workIds,
  ) async {
    final requested = <int>[];
    final seen = <int>{};
    for (final id in workIds) {
      if (id > 0 && seen.add(id)) {
        requested.add(id);
      }
    }
    return runManagedImageLifecycle(() => _deleteWorksWithReport(requested));
  }

  Future<WorkDeletionReport> _deleteWorksWithReport(
    List<int> requestedWorkIds,
  ) async {
    final db = await database;
    final pendingBefore = await _pendingFileDeletionPaths(db);
    const noCleanup = ManagedFileCleanupReport();

    final candidates = <_FileDeletionCandidate>[];
    try {
      final rowsById = <int, Map<String, Object?>>{};
      for (
        var start = 0;
        start < requestedWorkIds.length;
        start += _sqliteBindBatchSize
      ) {
        final end = min(start + _sqliteBindBatchSize, requestedWorkIds.length);
        final batch = requestedWorkIds.sublist(start, end);
        final placeholders = List.filled(batch.length, '?').join(', ');
        final rows = await db.rawQuery('''
          SELECT id, card_image_path, detail_image_path
          FROM works
          WHERE id IN ($placeholders)
          ''', batch);
        for (final row in rows) {
          rowsById[row['id'] as int] = row;
        }
      }
      final validatedByStoredPath = <String, _ValidatedManagedImage>{};
      Future<_ValidatedManagedImage> validate(String storedPath) async {
        return validatedByStoredPath[storedPath] ??=
            await _validateManagedImage(storedPath);
      }

      for (final id in requestedWorkIds) {
        final row = rowsById[id];
        if (row == null) {
          continue;
        }
        final cardImagePath = row['card_image_path']?.toString();
        final detailImagePath = row['detail_image_path']?.toString();
        for (final image in [
          (kind: 'card', storedPath: cardImagePath),
          (kind: 'detail', storedPath: detailImagePath),
        ]) {
          final storedPath = image.storedPath;
          if (storedPath == null || storedPath.trim().isEmpty) {
            continue;
          }
          candidates.add(
            _FileDeletionCandidate(
              kind: image.kind,
              databaseStoredPath: storedPath,
              validated: await validate(storedPath),
              workId: id,
            ),
          );
        }
      }

      final outcome = await db.transaction<_WorkDeleteTransactionOutcome>((
        transaction,
      ) async {
        if (requestedWorkIds.isEmpty) {
          return const _WorkDeleteTransactionOutcome(
            deletedWorkIds: [],
            deletedActressWorkRows: 0,
            deletedWorkRows: 0,
          );
        }
        final existingIds = <int>[];
        for (
          var start = 0;
          start < requestedWorkIds.length;
          start += _sqliteBindBatchSize
        ) {
          final end = min(
            start + _sqliteBindBatchSize,
            requestedWorkIds.length,
          );
          final batch = requestedWorkIds.sublist(start, end);
          final placeholders = List.filled(batch.length, '?').join(', ');
          final existingRows = await transaction.rawQuery(
            'SELECT id FROM works WHERE id IN ($placeholders)',
            batch,
          );
          existingIds.addAll(existingRows.map((row) => row['id'] as int));
        }
        if (existingIds.isEmpty) {
          return const _WorkDeleteTransactionOutcome(
            deletedWorkIds: [],
            deletedActressWorkRows: 0,
            deletedWorkRows: 0,
          );
        }
        final existingIdSet = existingIds.toSet();
        var actressWorkRowsDeleted = 0;
        for (
          var start = 0;
          start < existingIds.length;
          start += _sqliteBindBatchSize
        ) {
          final end = min(start + _sqliteBindBatchSize, existingIds.length);
          final batch = existingIds.sublist(start, end);
          final placeholders = List.filled(batch.length, '?').join(', ');
          actressWorkRowsDeleted += await transaction.rawDelete(
            'DELETE FROM actress_works WHERE work_id IN ($placeholders)',
            batch,
          );
        }
        for (final candidate in candidates.where(
          (candidate) => existingIdSet.contains(candidate.workId),
        )) {
          await transaction.insert('pending_file_deletions', {
            'path': candidate.pendingPath,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        var workRowsDeleted = 0;
        for (
          var start = 0;
          start < existingIds.length;
          start += _sqliteBindBatchSize
        ) {
          final end = min(start + _sqliteBindBatchSize, existingIds.length);
          final batch = existingIds.sublist(start, end);
          final placeholders = List.filled(batch.length, '?').join(', ');
          workRowsDeleted += await transaction.rawDelete(
            'DELETE FROM works WHERE id IN ($placeholders)',
            batch,
          );
        }
        return _WorkDeleteTransactionOutcome(
          deletedWorkIds: requestedWorkIds
              .where(existingIdSet.contains)
              .toList(growable: false),
          deletedActressWorkRows: actressWorkRowsDeleted,
          deletedWorkRows: workRowsDeleted,
        );
      });

      if (outcome.deletedWorkRows == 0) {
        return WorkDeletionReport(
          databaseCommitted: false,
          requestedWorkIds: List.unmodifiable(requestedWorkIds),
          deletedWorkIds: const [],
          deletedWorkRows: 0,
          deletedActressWorkRows: 0,
          fileCleanup: noCleanup,
          cacheEvictionPaths: const [],
          pendingFileDeletionsBefore: pendingBefore,
          pendingFileDeletionsAfter: await _pendingFileDeletionPaths(db),
        );
      }

      await _afterDeleteTransactionCommitted?.call();
      final fileCleanup = await _flushPendingFileDeletions(
        db,
        validatedCandidates: candidates
            .where(
              (candidate) => outcome.deletedWorkIds.contains(candidate.workId),
            )
            .toList(growable: false),
      );
      final cachePaths = candidates
          .where(
            (candidate) => outcome.deletedWorkIds.contains(candidate.workId),
          )
          .map((candidate) => candidate.databaseStoredPath)
          .toSet()
          .toList(growable: false);
      final report = WorkDeletionReport(
        databaseCommitted: true,
        requestedWorkIds: List.unmodifiable(requestedWorkIds),
        deletedWorkIds: outcome.deletedWorkIds,
        deletedWorkRows: outcome.deletedWorkRows,
        deletedActressWorkRows: outcome.deletedActressWorkRows,
        fileCleanup: fileCleanup,
        cacheEvictionPaths: cachePaths,
        pendingFileDeletionsBefore: pendingBefore,
        pendingFileDeletionsAfter: await _pendingFileDeletionPaths(db),
      );
      _writeStructuredResult('works_delete', report.toJson);
      return report;
    } on DatabaseException catch (error) {
      stderr.writeln('作品刪除失敗: $error');
      return WorkDeletionReport(
        databaseCommitted: false,
        requestedWorkIds: List.unmodifiable(requestedWorkIds),
        deletedWorkIds: const [],
        deletedWorkRows: 0,
        deletedActressWorkRows: 0,
        fileCleanup: noCleanup,
        cacheEvictionPaths: const [],
        pendingFileDeletionsBefore: pendingBefore,
        pendingFileDeletionsAfter: await _pendingFileDeletionPaths(db),
      );
    }
  }

  // 回傳資料庫與實體圖片清理的可稽核結果，供 UI 清快取與驗收使用。
  Future<ActressDeletionReport> deleteActressWithReport(int actressId) {
    return runManagedImageLifecycle(() => _deleteActressWithReport(actressId));
  }

  Future<ActressDeletionReport> _deleteActressWithReport(int actressId) async {
    final db = await database;
    final beforeTableCounts = await _tableCounts(db);
    final beforeManagedImageStats = await _managedImageStats();
    final managedRoot = await _canonicalManagedImageRoot();
    final pendingFileDeletionsBefore = await _pendingFileDeletionPaths(db);
    const noMaintenance = DatabaseMaintenanceReport(
      walCheckpointAttempted: false,
      vacuumAttempted: false,
      vacuumCompleted: false,
    );
    _ActressDeletionSnapshot? snapshot;

    try {
      snapshot = await _loadActressDeletionSnapshot(db, actressId);
      final deletionSnapshot = snapshot;
      if (deletionSnapshot == null) {
        return ActressDeletionReport(
          databaseCommitted: false,
          beforeTableCounts: beforeTableCounts,
          afterTableCounts: beforeTableCounts,
          beforeManagedImageStats: beforeManagedImageStats,
          afterManagedImageStats: beforeManagedImageStats,
          fileCleanup: const ManagedFileCleanupReport(),
          maintenance: noMaintenance,
          cacheEvictionPaths: const [],
          actressId: actressId,
          managedRoot: managedRoot,
          remainingActressCount: beforeTableCounts['actresses'] ?? 0,
          remainingWorkCount: beforeTableCounts['works'] ?? 0,
          remainingActressWorkCount: beforeTableCounts['actress_works'] ?? 0,
          pendingFileDeletionsBefore: pendingFileDeletionsBefore,
          pendingFileDeletionsAfter: pendingFileDeletionsBefore,
        );
      }
      final outcome = await db.transaction<_DeleteTransactionOutcome?>((
        transaction,
      ) async {
        final current = await transaction.query(
          'actresses',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [actressId],
          limit: 1,
        );
        if (current.isEmpty) {
          return null;
        }

        final actressWorkRowsDeleted = await transaction.delete(
          'actress_works',
          where: 'actress_id = ?',
          whereArgs: [actressId],
        );

        final orphanWorkIds = await _findOrphanWorkIds(
          transaction,
          deletionSnapshot.workIds,
        );
        final selectedCandidates = deletionSnapshot.selectCandidates(
          orphanWorkIds,
        );
        for (final pendingPath
            in selectedCandidates
                .map((candidate) => candidate.pendingPath)
                .toSet()) {
          await transaction.insert('pending_file_deletions', {
            'path': pendingPath,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        var deletedWorkRows = 0;
        if (orphanWorkIds.isNotEmpty) {
          final placeholders = List.filled(
            orphanWorkIds.length,
            '?',
          ).join(', ');
          deletedWorkRows = await transaction.rawDelete(
            'DELETE FROM works WHERE id IN ($placeholders)',
            orphanWorkIds,
          );
        }

        final actressRowsDeleted = await transaction.delete(
          'actresses',
          where: 'id = ?',
          whereArgs: [actressId],
        );
        if (actressRowsDeleted != 1) {
          throw StateError('Actress $actressId disappeared during deletion.');
        }

        return _DeleteTransactionOutcome(
          orphanWorkIds: orphanWorkIds,
          actressRowsDeleted: actressRowsDeleted,
          actressWorkRowsDeleted: actressWorkRowsDeleted,
          deletedWorkRows: deletedWorkRows,
          fileCandidates: selectedCandidates,
          cacheEvictionPaths: selectedCandidates
              .map((candidate) => candidate.databaseStoredPath)
              .toSet()
              .toList(growable: false),
        );
      });
      if (outcome == null) {
        final afterTableCounts = await _tableCounts(db);
        return ActressDeletionReport(
          databaseCommitted: false,
          beforeTableCounts: beforeTableCounts,
          afterTableCounts: afterTableCounts,
          beforeManagedImageStats: beforeManagedImageStats,
          afterManagedImageStats: await _managedImageStats(),
          fileCleanup: const ManagedFileCleanupReport(),
          maintenance: noMaintenance,
          cacheEvictionPaths: const [],
          actressId: deletionSnapshot.actressId,
          actressImagePath: deletionSnapshot.actressImagePath,
          managedRoot: managedRoot,
          targetActressWorkCount: deletionSnapshot.targetActressWorkCount,
          snapshotWorks: deletionSnapshot.reportWorks,
          uiWorkIds: deletionSnapshot.uiWorkIds,
          remainingActressCount: afterTableCounts['actresses'] ?? 0,
          remainingWorkCount: afterTableCounts['works'] ?? 0,
          remainingActressWorkCount: afterTableCounts['actress_works'] ?? 0,
          pendingFileDeletionsBefore: pendingFileDeletionsBefore,
          pendingFileDeletionsAfter: await _pendingFileDeletionPaths(db),
        );
      }

      // 此測試鉤子位於 commit 之後、任何實體檔案處理之前，驗證重啟復原。
      await _afterDeleteTransactionCommitted?.call();

      final fileCleanup = await _flushPendingFileDeletions(
        db,
        validatedCandidates: outcome.fileCandidates,
      );
      final maintenance = await _compactDatabaseIfNeeded(db);
      final afterTableCounts = await _tableCounts(db);
      final report = ActressDeletionReport(
        databaseCommitted: true,
        beforeTableCounts: beforeTableCounts,
        afterTableCounts: afterTableCounts,
        beforeManagedImageStats: beforeManagedImageStats,
        afterManagedImageStats: await _managedImageStats(),
        fileCleanup: fileCleanup,
        maintenance: maintenance,
        cacheEvictionPaths: outcome.cacheEvictionPaths,
        actressId: deletionSnapshot.actressId,
        actressImagePath: deletionSnapshot.actressImagePath,
        managedRoot: managedRoot,
        targetActressWorkCount: deletionSnapshot.targetActressWorkCount,
        snapshotWorks: deletionSnapshot.reportWorks,
        uiWorkIds: deletionSnapshot.uiWorkIds,
        deletedActressRows: outcome.actressRowsDeleted,
        deletedActressWorkRows: outcome.actressWorkRowsDeleted,
        orphanWorkIds: outcome.orphanWorkIds,
        deletedWorkRows: outcome.deletedWorkRows,
        remainingActressCount: afterTableCounts['actresses'] ?? 0,
        remainingWorkCount: afterTableCounts['works'] ?? 0,
        remainingActressWorkCount: afterTableCounts['actress_works'] ?? 0,
        pendingFileDeletionsBefore: pendingFileDeletionsBefore,
        pendingFileDeletionsAfter: await _pendingFileDeletionPaths(db),
      );
      _writeStructuredResult('actress_delete', report.toJson);
      return report;
    } on DatabaseException catch (error) {
      stderr.writeln('刪除失敗: $error');
      final report = ActressDeletionReport(
        databaseCommitted: false,
        beforeTableCounts: beforeTableCounts,
        afterTableCounts: beforeTableCounts,
        beforeManagedImageStats: beforeManagedImageStats,
        afterManagedImageStats: beforeManagedImageStats,
        fileCleanup: const ManagedFileCleanupReport(),
        maintenance: noMaintenance,
        cacheEvictionPaths: const [],
        actressId: snapshot?.actressId ?? actressId,
        actressImagePath: snapshot?.actressImagePath,
        managedRoot: managedRoot,
        targetActressWorkCount: snapshot?.targetActressWorkCount ?? 0,
        snapshotWorks: snapshot?.reportWorks ?? const [],
        uiWorkIds: snapshot?.uiWorkIds ?? const [],
        remainingActressCount: beforeTableCounts['actresses'] ?? 0,
        remainingWorkCount: beforeTableCounts['works'] ?? 0,
        remainingActressWorkCount: beforeTableCounts['actress_works'] ?? 0,
        pendingFileDeletionsBefore: pendingFileDeletionsBefore,
        pendingFileDeletionsAfter: await _pendingFileDeletionPaths(db),
      );
      _writeStructuredResult('actress_delete', report.toJson);
      return report;
    }
  }

  Future<_ActressDeletionSnapshot?> _loadActressDeletionSnapshot(
    Database db,
    int actressId,
  ) async {
    final actressRows = await db.query(
      'actresses',
      columns: ['id', 'img_path'],
      where: 'id = ?',
      whereArgs: [actressId],
      limit: 1,
    );
    if (actressRows.isEmpty) {
      return null;
    }

    final targetCountRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM actress_works WHERE actress_id = ?',
      [actressId],
    );
    final targetActressWorkCount =
        (targetCountRows.single['count'] as num?)?.toInt() ?? 0;
    final uiWorkIds = (await getWorksForActress(
      actressId,
    )).map((work) => work['id'] as int).toList(growable: false);

    final workRows = await db.rawQuery(
      '''
      SELECT w.id, w.card_image_path, w.detail_image_path,
             COUNT(aw_count.actress_id) AS actress_reference_count
      FROM works w
      INNER JOIN actress_works aw ON aw.work_id = w.id
      LEFT JOIN actress_works aw_count ON aw_count.work_id = w.id
      WHERE aw.actress_id = ?
      GROUP BY w.id, w.card_image_path, w.detail_image_path
      ''',
      [actressId],
    );
    final works = workRows
        .map(
          (row) => _WorkDeletionSnapshot(
            id: row['id'] as int,
            cardImagePath: row['card_image_path']?.toString(),
            detailImagePath: row['detail_image_path']?.toString(),
            actressReferenceCount:
                (row['actress_reference_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
    final validatedByStoredPath = <String, _ValidatedManagedImage>{};
    Future<_ValidatedManagedImage> validateStoredPath(String storedPath) async {
      final existing = validatedByStoredPath[storedPath];
      if (existing != null) {
        return existing;
      }
      final validated = await _validateManagedImage(storedPath);
      validatedByStoredPath[storedPath] = validated;
      return validated;
    }

    final fileCandidates = <_FileDeletionCandidate>[];
    final actressImagePath = actressRows.single['img_path']?.toString();
    if (actressImagePath != null && actressImagePath.trim().isNotEmpty) {
      fileCandidates.add(
        _FileDeletionCandidate(
          kind: 'avatar',
          databaseStoredPath: actressImagePath,
          validated: await validateStoredPath(actressImagePath),
        ),
      );
    }
    for (final work in works) {
      for (final image in [
        (kind: 'card', storedPath: work.cardImagePath),
        (kind: 'detail', storedPath: work.detailImagePath),
      ]) {
        final storedPath = image.storedPath;
        if (storedPath == null || storedPath.trim().isEmpty) {
          continue;
        }
        fileCandidates.add(
          _FileDeletionCandidate(
            kind: image.kind,
            databaseStoredPath: storedPath,
            validated: await validateStoredPath(storedPath),
            workId: work.id,
          ),
        );
      }
    }

    return _ActressDeletionSnapshot(
      actressId: actressRows.single['id'] as int,
      actressImagePath: actressImagePath,
      works: works,
      targetActressWorkCount: targetActressWorkCount,
      uiWorkIds: uiWorkIds,
      fileCandidates: fileCandidates,
    );
  }

  Future<List<int>> _findOrphanWorkIds(
    Transaction transaction,
    List<int> relatedWorkIds,
  ) async {
    if (relatedWorkIds.isEmpty) {
      return const [];
    }
    final placeholders = List.filled(relatedWorkIds.length, '?').join(', ');
    final rows = await transaction.rawQuery('''
      SELECT w.id
      FROM works w
      WHERE w.id IN ($placeholders)
        AND NOT EXISTS (
          SELECT 1 FROM actress_works aw WHERE aw.work_id = w.id
        )
      ''', relatedWorkIds);
    return rows.map((row) => row['id'] as int).toList(growable: false);
  }

  // 僅清理由應用程式圖片目錄管理、且已不再被資料庫引用的檔案。
  Future<ManagedFileCleanupReport> _flushPendingFileDeletions(
    Database db, {
    List<_FileDeletionCandidate> validatedCandidates = const [],
  }) async {
    final deleted = <String>[];
    final missing = <String>[];
    final deferred = <String>[];
    final rejected = <String>[];
    final emptyDirectoriesRemoved = <String>[];
    final records = <ManagedFileCleanupRecord>[];
    final captureDiagnostics = _shouldCaptureDeletionDiagnostics;
    var deletedCount = 0;
    var deletedBytes = 0;
    var missingCount = 0;
    var deferredCount = 0;
    var rejectedCount = 0;
    final deletedFileKeys = <String>{};
    void recordDeleted(String pendingPath, _ValidatedManagedImage validated) {
      deletedCount++;
      if (captureDiagnostics) {
        deleted.add(pendingPath);
      }
      final canonicalFilePath = validated.canonicalFilePath;
      if (canonicalFilePath != null && deletedFileKeys.add(canonicalFilePath)) {
        deletedBytes += validated.bytes;
      }
    }

    void recordMissing(String pendingPath) {
      missingCount++;
      if (captureDiagnostics) {
        missing.add(pendingPath);
      }
    }

    void recordDeferred(String pendingPath) {
      deferredCount++;
      if (captureDiagnostics) {
        deferred.add(pendingPath);
      }
    }

    void recordRejected(String pendingPath) {
      rejectedCount++;
      if (captureDiagnostics) {
        rejected.add(pendingPath);
      }
    }

    final candidatesByPendingPath = <String, List<_FileDeletionCandidate>>{};
    for (final candidate in validatedCandidates) {
      candidatesByPendingPath
          .putIfAbsent(candidate.pendingPath, () => [])
          .add(candidate);
    }

    Future<void> appendRecords({
      required String pendingPath,
      required List<_FileDeletionCandidate> candidates,
      required String deleteResult,
      required int databaseReferenceCount,
      String? rejectionReason,
      required bool existsAfter,
    }) async {
      if (!captureDiagnostics) {
        return;
      }
      for (final candidate in candidates) {
        final before = candidate.validated;
        final existsBefore =
            before.exists || await _diagnosticPathExists(before);
        final bytesBefore = before.bytes == 0
            ? await _diagnosticPathBytes(before)
            : before.bytes;
        records.add(
          ManagedFileCleanupRecord(
            kind: candidate.kind,
            databaseStoredPath: candidate.databaseStoredPath,
            normalizedPath: before.normalizedPath,
            resolvedAbsolutePath: before.canonicalFilePath,
            managedRoot: before.canonicalRootPath,
            existsBefore: existsBefore,
            databaseReferenceCount: databaseReferenceCount,
            classifyResult: before.status.name,
            deleteResult: deleteResult,
            rejectionReason: rejectionReason ?? before.reason,
            existsAfter: existsAfter,
            bytesBefore: bytesBefore,
          ),
        );
      }
    }

    try {
      final pending = await db.query('pending_file_deletions');
      final referencedCounts = await _referencedManagedImageCounts(db);
      final processedKeys = <String>{};

      for (final row in pending) {
        final pendingPath = row['path']?.toString();
        if (pendingPath == null) {
          await _removePendingFileDeletion(db, null);
          recordRejected('<null>');
          _writeSecurityWarning('<null>', 'pending path is null');
          continue;
        }

        final candidates =
            candidatesByPendingPath[pendingPath] ??
            [
              _FileDeletionCandidate(
                kind: 'pending',
                databaseStoredPath: pendingPath,
                validated: await _validateManagedImage(pendingPath),
              ),
            ];
        final validated = candidates.first.validated;
        switch (validated.status) {
          case _ManagedImageStatus.missing:
            await _removePendingFileDeletion(db, pendingPath);
            recordMissing(pendingPath);
            await appendRecords(
              pendingPath: pendingPath,
              candidates: candidates,
              deleteResult: 'missing',
              databaseReferenceCount: 0,
              existsAfter: false,
            );
            continue;
          case _ManagedImageStatus.rejected:
            await _removePendingFileDeletion(db, pendingPath);
            recordRejected(pendingPath);
            _writeSecurityWarning(pendingPath, validated.reason);
            await appendRecords(
              pendingPath: pendingPath,
              candidates: candidates,
              deleteResult: 'rejected',
              databaseReferenceCount: 0,
              rejectionReason: validated.reason,
              existsAfter: await _diagnosticPathExists(validated),
            );
            continue;
          case _ManagedImageStatus.valid:
            final imageFile = validated.resolvedFile!;
            final fileKey = _fileKey(imageFile.path);
            final databaseReferenceCount = referencedCounts[fileKey] ?? 0;
            if (!processedKeys.add(fileKey)) {
              await _removePendingFileDeletion(db, pendingPath);
              recordRejected(pendingPath);
              await appendRecords(
                pendingPath: pendingPath,
                candidates: candidates,
                deleteResult: 'rejected',
                databaseReferenceCount: databaseReferenceCount,
                rejectionReason: 'duplicate canonical pending path',
                existsAfter: await imageFile.exists(),
              );
              continue;
            }
            if (databaseReferenceCount > 0) {
              await _removePendingFileDeletion(db, pendingPath);
              recordRejected(pendingPath);
              _writeSecurityWarning(
                pendingPath,
                'path remains referenced by another database row',
              );
              await appendRecords(
                pendingPath: pendingPath,
                candidates: candidates,
                deleteResult: 'rejected',
                databaseReferenceCount: databaseReferenceCount,
                rejectionReason:
                    'path remains referenced by another database row',
                existsAfter: await imageFile.exists(),
              );
              continue;
            }

            try {
              await _deleteManagedFile(validated);
              if (await imageFile.exists()) {
                recordDeferred(pendingPath);
                await appendRecords(
                  pendingPath: pendingPath,
                  candidates: candidates,
                  deleteResult: 'deferred',
                  databaseReferenceCount: databaseReferenceCount,
                  rejectionReason: 'delete completed without removing file',
                  existsAfter: true,
                );
                continue;
              }
              await _removePendingFileDeletion(db, pendingPath);
              recordDeleted(pendingPath, validated);
              await appendRecords(
                pendingPath: pendingPath,
                candidates: candidates,
                deleteResult: 'deleted',
                databaseReferenceCount: databaseReferenceCount,
                existsAfter: false,
              );
            } on FileSystemException catch (error) {
              if (!await imageFile.exists()) {
                await _removePendingFileDeletion(db, pendingPath);
                recordMissing(pendingPath);
                await appendRecords(
                  pendingPath: pendingPath,
                  candidates: candidates,
                  deleteResult: 'missing',
                  databaseReferenceCount: databaseReferenceCount,
                  existsAfter: false,
                );
              } else {
                recordDeferred(pendingPath);
                stderr.writeln('圖片刪除失敗，將於下次啟動重試: $error');
                await appendRecords(
                  pendingPath: pendingPath,
                  candidates: candidates,
                  deleteResult: 'deferred',
                  databaseReferenceCount: databaseReferenceCount,
                  rejectionReason: error.message,
                  existsAfter: true,
                );
              }
            }
        }
      }
      emptyDirectoriesRemoved.addAll(
        await _pruneEmptyManagedImageDirectories(),
      );
    } on DatabaseException catch (error) {
      stderr.writeln('待刪圖片清理資料庫操作失敗: $error');
    } on FileSystemException catch (error) {
      stderr.writeln('待刪圖片暫時無法驗證，將於下次啟動重試: $error');
    }

    return ManagedFileCleanupReport(
      deleted: deleted,
      missing: missing,
      deferred: deferred,
      rejected: rejected,
      emptyDirectoriesRemoved: emptyDirectoriesRemoved,
      records: records,
      deletedCount: deletedCount,
      deletedBytes: deletedBytes,
      missingCount: missingCount,
      deferredCount: deferredCount,
      rejectedCount: rejectedCount,
    );
  }

  Future<Map<String, int>> _referencedManagedImageCounts(Database db) async {
    final referencedPaths = <String>{
      ...(await db.query(
        'actresses',
        columns: ['img_path'],
      )).map((row) => row['img_path']?.toString()).whereType<String>(),
      ...(await db.query(
            'works',
            columns: ['card_image_path', 'detail_image_path'],
          ))
          .expand(
            (work) => [
              work['card_image_path']?.toString(),
              work['detail_image_path']?.toString(),
            ],
          )
          .whereType<String>(),
    }..removeWhere((value) => value.trim().isEmpty);
    final counts = <String, int>{};
    for (final referencedPath in referencedPaths) {
      final validated = await _validateManagedImage(referencedPath);
      if (validated.status == _ManagedImageStatus.valid) {
        final key = _fileKey(validated.resolvedFile!.path);
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<bool> _diagnosticPathExists(_ValidatedManagedImage validation) async {
    final candidatePath =
        validation.canonicalFilePath ?? validation.normalizedPath;
    return candidatePath != null && await File(candidatePath).exists();
  }

  Future<int> _diagnosticPathBytes(_ValidatedManagedImage validation) async {
    final candidatePath =
        validation.canonicalFilePath ?? validation.normalizedPath;
    if (candidatePath == null) {
      return 0;
    }
    try {
      return await File(candidatePath).length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _removePendingFileDeletion(Database db, String? pendingPath) {
    if (pendingPath == null) {
      return db.delete('pending_file_deletions', where: 'path IS NULL');
    }
    return db.delete(
      'pending_file_deletions',
      where: 'path = ?',
      whereArgs: [pendingPath],
    );
  }

  Future<void> _deleteManagedFile(_ValidatedManagedImage validated) {
    final file = validated.resolvedFile;
    if (file == null) {
      throw StateError('Only a validated managed image may be deleted.');
    }
    return _deleteFileOverride?.call(file) ?? file.delete();
  }

  Future<_ValidatedManagedImage> _validateManagedImage(String imagePath) async {
    final trimmed = imagePath.trim();
    final lexicalRoot = path.normalize(
      path.absolute(_normalizeAndroidPrivateDataAlias(imgDir)),
    );
    final managedRoot = await _canonicalManagedImageRoot();
    if (trimmed.isEmpty) {
      return _ValidatedManagedImage.rejected(
        originalPath: imagePath,
        reason: 'path is empty',
        normalizedPath: null,
        managedRoot: managedRoot,
      );
    }
    final candidates = _managedImagePathCandidates(trimmed);
    String? safeMissingPath;
    String? rejectedPath;
    String? rejectedReason;

    for (final candidate in candidates) {
      final lexicalPath = path.normalize(path.absolute(candidate));
      if (!_isWithinPath(lexicalRoot, lexicalPath)) {
        rejectedPath ??= lexicalPath;
        rejectedReason ??= 'path is outside image root';
        continue;
      }
      safeMissingPath ??= lexicalPath;

      final entityType = await FileSystemEntity.type(
        lexicalPath,
        followLinks: false,
      );
      if (entityType == FileSystemEntityType.notFound) {
        continue;
      }
      if (entityType != FileSystemEntityType.file) {
        rejectedPath = lexicalPath;
        rejectedReason = 'path is not a regular image file';
        continue;
      }
      if (!_isManagedImageFile(lexicalPath)) {
        rejectedPath = lexicalPath;
        rejectedReason = 'path is not a supported image file';
        continue;
      }

      final resolvedPath = path.normalize(
        _normalizeAndroidPrivateDataAlias(
          await File(lexicalPath).resolveSymbolicLinks(),
        ),
      );
      if (!_isWithinPath(managedRoot, resolvedPath)) {
        rejectedPath = lexicalPath;
        rejectedReason = 'canonical path resolves outside image root';
        continue;
      }
      final imageFile = File(resolvedPath);
      return _ValidatedManagedImage.valid(
        originalPath: imagePath,
        resolvedFile: imageFile,
        normalizedPath: lexicalPath,
        canonicalFilePath: resolvedPath,
        canonicalRootPath: managedRoot,
        exists: true,
        bytes: await imageFile.length(),
      );
    }

    if (safeMissingPath != null) {
      return _ValidatedManagedImage.missing(
        originalPath: imagePath,
        normalizedPath: safeMissingPath,
        managedRoot: managedRoot,
      );
    }
    return _ValidatedManagedImage.rejected(
      originalPath: imagePath,
      reason: rejectedReason ?? 'path cannot be resolved under image root',
      normalizedPath: rejectedPath,
      managedRoot: managedRoot,
    );
  }

  List<String> _managedImagePathCandidates(String storedPath) {
    final mappedStoredPath =
        _managedImageCanonicalPathResolver?.call(storedPath) ?? storedPath;
    final fileUri = Uri.tryParse(mappedStoredPath);
    if (fileUri != null && fileUri.scheme.toLowerCase() == 'file') {
      try {
        return [
          path.normalize(
            path.absolute(
              _normalizeAndroidPrivateDataAlias(
                fileUri.toFilePath(windows: Platform.isWindows),
              ),
            ),
          ),
        ];
      } on ArgumentError {
        return const [];
      } on UnsupportedError {
        return const [];
      }
    }

    final resolvedStoredPath = _normalizeAndroidPrivateDataAlias(
      mappedStoredPath,
    );
    final slashPath = resolvedStoredPath.replaceAll('\\', '/');
    if (slashPath == '/works' || slashPath.startsWith('/works/')) {
      final suffix = slashPath == '/works'
          ? ''
          : slashPath.substring('/works/'.length);
      return [path.normalize(path.join(imgDir, 'works', suffix))];
    }
    if (path.isAbsolute(resolvedStoredPath)) {
      return [path.normalize(path.absolute(resolvedStoredPath))];
    }

    final documentsDirectory = path.dirname(baseDir);
    final candidates = <String>[];
    void addCandidate(String candidate) {
      final normalized = path.normalize(path.absolute(candidate));
      if (!candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    if (slashPath == 'works' || slashPath.startsWith('works/')) {
      addCandidate(path.join(imgDir, 'scraped', resolvedStoredPath));
    }
    addCandidate(path.join(imgDir, resolvedStoredPath));
    addCandidate(path.join(baseDir, resolvedStoredPath));
    addCandidate(path.join(documentsDirectory, resolvedStoredPath));
    if (!slashPath.contains('/')) {
      addCandidate(path.join(imgDir, 'scraped', 'works', resolvedStoredPath));
    }
    return candidates;
  }

  String _normalizeAndroidPrivateDataAlias(String candidatePath) {
    const userDataPrefix = '/data/user/0/';
    if (candidatePath.replaceAll('\\', '/').startsWith(userDataPrefix)) {
      return '/data/data/${candidatePath.substring(userDataPrefix.length)}';
    }
    return candidatePath;
  }

  bool _isWithinPath(String root, String candidate) {
    final comparableRoot = Platform.isWindows ? root.toLowerCase() : root;
    final comparableCandidate = Platform.isWindows
        ? candidate.toLowerCase()
        : candidate;
    return path.equals(comparableRoot, comparableCandidate) ||
        path.isWithin(comparableRoot, comparableCandidate);
  }

  bool _isManagedImageFile(String filePath) {
    const supportedExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
    return supportedExtensions.contains(path.extension(filePath).toLowerCase());
  }

  Future<String> _canonicalManagedImageRoot() async {
    return path.normalize(
      _normalizeAndroidPrivateDataAlias(
        await Directory(imgDir).resolveSymbolicLinks(),
      ),
    );
  }

  Future<List<String>> _pruneEmptyManagedImageDirectories() async {
    final root = Directory(imgDir);
    if (!await root.exists()) {
      return const [];
    }
    final managedRoot = await _canonicalManagedImageRoot();
    final directories = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        directories.add(entity);
      }
    }
    directories.sort((a, b) => b.path.length.compareTo(a.path.length));

    final removed = <String>[];
    for (final directory in directories) {
      final resolvedPath = path.normalize(
        _normalizeAndroidPrivateDataAlias(
          await directory.resolveSymbolicLinks(),
        ),
      );
      if (!_isWithinPath(managedRoot, resolvedPath)) {
        _writeSecurityWarning(
          directory.path,
          'directory resolves outside image root',
        );
        continue;
      }
      try {
        if (await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
          removed.add(directory.path);
        }
      } on FileSystemException catch (error) {
        stderr.writeln('空圖片目錄清理失敗: $error');
      }
    }
    return removed;
  }

  // checkpoint 每次在 transaction 外執行；只有足夠多空頁時才進行 VACUUM。
  Future<DatabaseMaintenanceReport> _compactDatabaseIfNeeded(
    Database db,
  ) async {
    var walCheckpointAttempted = false;
    var vacuumAttempted = false;
    var vacuumCompleted = false;
    try {
      walCheckpointAttempted = true;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } on DatabaseException catch (error) {
      stderr.writeln('SQLite WAL checkpoint 失敗: $error');
    }

    try {
      final rows = await db.rawQuery('PRAGMA freelist_count');
      final freePages = (rows.single.values.single as num?)?.toInt() ?? 0;
      if (freePages >= 32) {
        vacuumAttempted = true;
        await db.execute('VACUUM');
        vacuumCompleted = true;
      }
    } on DatabaseException catch (error) {
      stderr.writeln('SQLite 壓縮失敗: $error');
    }

    return DatabaseMaintenanceReport(
      walCheckpointAttempted: walCheckpointAttempted,
      vacuumAttempted: vacuumAttempted,
      vacuumCompleted: vacuumCompleted,
    );
  }

  Future<Map<String, int>> _tableCounts(Database db) async {
    const tables = [
      'actresses',
      'works',
      'actress_works',
      'pending_file_deletions',
    ];
    final counts = <String, int>{};
    for (final table in tables) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
      counts[table] = (rows.single['count'] as num).toInt();
    }
    return counts;
  }

  Future<ManagedImageStats> _managedImageStats() async {
    final root = Directory(imgDir);
    if (!await root.exists()) {
      return const ManagedImageStats(fileCount: 0, totalBytes: 0);
    }
    var fileCount = 0;
    var totalBytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        fileCount++;
        totalBytes += await entity.length();
      }
    }
    return ManagedImageStats(fileCount: fileCount, totalBytes: totalBytes);
  }

  Future<List<String>> _pendingFileDeletionPaths(Database db) async {
    final rows = await db.query(
      'pending_file_deletions',
      columns: ['path'],
      orderBy: 'path ASC',
    );
    return rows
        .map((row) => row['path']?.toString())
        .whereType<String>()
        .toList(growable: false);
  }

  bool get _shouldCaptureDeletionDiagnostics {
    var isDebugBuild = false;
    assert(() {
      isDebugBuild = true;
      return true;
    }());
    return isDebugBuild;
  }

  void _writeStructuredResult(
    String event,
    Map<String, Object?> Function() buildResult,
  ) {
    assert(() {
      stderr.writeln(jsonEncode({'event': event, ...buildResult()}));
      return true;
    }());
  }

  void _writeSecurityWarning(String path, String? reason) {
    _writeStructuredResult(
      'managed_image_rejected',
      () => {
        'path': path,
        'reason': reason ?? 'managed image validation failed',
      },
    );
  }

  String _fileKey(String filePath) {
    final normalized = path.normalize(path.absolute(filePath));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
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

    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}

class _ManagedImageLifecycleOwner {
  _ManagedImageLifecycleOwner(this.database);

  final AppDatabase database;
  bool acceptingNestedOperations = true;
  var _nestedOperationCount = 0;
  Completer<void>? _nestedOperationsFinished;

  Future<T> runNested<T>(Future<T> Function() operation) async {
    _nestedOperationCount++;
    try {
      return await operation();
    } finally {
      _nestedOperationCount--;
      if (_nestedOperationCount == 0) {
        _nestedOperationsFinished?.complete();
      }
    }
  }

  Future<void> close() async {
    acceptingNestedOperations = false;
    if (_nestedOperationCount > 0) {
      await (_nestedOperationsFinished ??= Completer<void>()).future;
    }
  }
}

class _ActressDeletionSnapshot {
  const _ActressDeletionSnapshot({
    required this.actressId,
    required this.actressImagePath,
    required this.works,
    required this.targetActressWorkCount,
    required this.uiWorkIds,
    required this.fileCandidates,
  });

  final int actressId;
  final String? actressImagePath;
  final List<_WorkDeletionSnapshot> works;
  final int targetActressWorkCount;
  final List<int> uiWorkIds;
  final List<_FileDeletionCandidate> fileCandidates;

  List<int> get workIds => works.map((work) => work.id).toList(growable: false);

  List<ActressDeletionSnapshotWork> get reportWorks => works
      .map(
        (work) => ActressDeletionSnapshotWork(
          workId: work.id,
          cardImagePath: work.cardImagePath,
          detailImagePath: work.detailImagePath,
          actressReferenceCount: work.actressReferenceCount,
        ),
      )
      .toList(growable: false);

  List<_FileDeletionCandidate> selectCandidates(List<int> orphanWorkIds) {
    final orphanIds = orphanWorkIds.toSet();
    return fileCandidates
        .where(
          (candidate) =>
              candidate.workId == null || orphanIds.contains(candidate.workId),
        )
        .toList(growable: false);
  }
}

class _WorkDeletionSnapshot {
  const _WorkDeletionSnapshot({
    required this.id,
    required this.cardImagePath,
    required this.detailImagePath,
    required this.actressReferenceCount,
  });

  final int id;
  final String? cardImagePath;
  final String? detailImagePath;
  final int actressReferenceCount;
}

class _DeleteTransactionOutcome {
  const _DeleteTransactionOutcome({
    required this.orphanWorkIds,
    required this.actressRowsDeleted,
    required this.actressWorkRowsDeleted,
    required this.deletedWorkRows,
    required this.fileCandidates,
    required this.cacheEvictionPaths,
  });

  final List<int> orphanWorkIds;
  final int actressRowsDeleted;
  final int actressWorkRowsDeleted;
  final int deletedWorkRows;
  final List<_FileDeletionCandidate> fileCandidates;
  final List<String> cacheEvictionPaths;
}

class _WorkDeleteTransactionOutcome {
  const _WorkDeleteTransactionOutcome({
    required this.deletedWorkIds,
    required this.deletedActressWorkRows,
    required this.deletedWorkRows,
  });

  final List<int> deletedWorkIds;
  final int deletedActressWorkRows;
  final int deletedWorkRows;
}

class _FileDeletionCandidate {
  const _FileDeletionCandidate({
    required this.kind,
    required this.databaseStoredPath,
    required this.validated,
    this.workId,
  });

  final String kind;
  final String databaseStoredPath;
  final _ValidatedManagedImage validated;
  final int? workId;

  String get pendingPath => validated.pendingPath;
}

enum _ManagedImageStatus { valid, missing, rejected }

class _ValidatedManagedImage {
  const _ValidatedManagedImage._({
    required this.originalPath,
    required this.status,
    required this.resolvedFile,
    required this.reason,
    required this.normalizedPath,
    required this.canonicalFilePath,
    required this.canonicalRootPath,
    required this.exists,
    required this.bytes,
  });

  const _ValidatedManagedImage.valid({
    required String originalPath,
    required File resolvedFile,
    required String normalizedPath,
    required String canonicalFilePath,
    required String canonicalRootPath,
    required bool exists,
    required int bytes,
  }) : this._(
         originalPath: originalPath,
         status: _ManagedImageStatus.valid,
         resolvedFile: resolvedFile,
         reason: null,
         normalizedPath: normalizedPath,
         canonicalFilePath: canonicalFilePath,
         canonicalRootPath: canonicalRootPath,
         exists: exists,
         bytes: bytes,
       );

  const _ValidatedManagedImage.missing({
    required String originalPath,
    required String normalizedPath,
    required String managedRoot,
  }) : this._(
         originalPath: originalPath,
         status: _ManagedImageStatus.missing,
         resolvedFile: null,
         reason: null,
         normalizedPath: normalizedPath,
         canonicalFilePath: normalizedPath,
         canonicalRootPath: managedRoot,
         exists: false,
         bytes: 0,
       );

  const _ValidatedManagedImage.rejected({
    required String originalPath,
    required String reason,
    required String? normalizedPath,
    required String managedRoot,
  }) : this._(
         originalPath: originalPath,
         status: _ManagedImageStatus.rejected,
         resolvedFile: null,
         reason: reason,
         normalizedPath: normalizedPath,
         canonicalFilePath: null,
         canonicalRootPath: managedRoot,
         exists: false,
         bytes: 0,
       );

  final String originalPath;
  final _ManagedImageStatus status;
  final File? resolvedFile;
  final String? reason;
  final String? normalizedPath;
  final String? canonicalFilePath;
  final String canonicalRootPath;
  final bool exists;
  final int bytes;

  String get pendingPath => canonicalFilePath ?? normalizedPath ?? originalPath;
}
