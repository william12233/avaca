import 'package:sqflite/sqflite.dart';

import '../core/database.dart';
import '../models/data_health.dart';

class DataHealthService {
  DataHealthService({required this.db});

  final AppDatabase db;

  Future<DataHealthSnapshot> load() async {
    final database = await db.database;
    final warnings = <String>[];

    void warn(String key) {
      if (!warnings.contains(key)) warnings.add(key);
    }

    Future<T> safe<T>(
      String warningKey,
      T fallback,
      Future<T> Function() operation,
    ) async {
      try {
        return await operation();
      } on Object {
        warn(warningKey);
        return fallback;
      }
    }

    final actressCount = await safe(
      'actresses',
      0,
      () => _count(database, 'actresses'),
    );
    final workCount = await safe('works', 0, () => _count(database, 'works'));
    final storedWorkCount = await safe(
      'storedWorks',
      0,
      () => _count(database, 'works', where: 'is_stored = 1'),
    );
    final pendingDeletionCount = await safe(
      'pendingDeletions',
      0,
      () => _count(database, 'pending_file_deletions'),
    );
    final missingReleaseDateCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'release_date'),
    );
    final missingStudioCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'studio'),
    );
    final missingPublisherCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'publisher'),
    );
    final missingSeriesCount = await safe(
      'metadata',
      0,
      () => _missing(database, 'series'),
    );
    final missingCardImageCount = await safe(
      'images',
      0,
      () => _missingImageReferences(database, 'card_image_path'),
    );
    final missingDetailImageCount = await safe(
      'images',
      0,
      () => _missingImageReferences(database, 'detail_image_path'),
    );
    final missingProvenanceCount = await safe('provenance', 0, () async {
      final rows = await database.rawQuery('''
          SELECT COUNT(*) AS count
          FROM works w
          WHERE NOT EXISTS (
            SELECT 1 FROM work_field_provenance p WHERE p.work_id = w.id
          )
        ''');
      return _number(rows.firstOrNull?['count']);
    });
    final jobCounts = await safe('jobStates', const <String, int>{}, () async {
      final rows = await database.rawQuery(
        'SELECT state, COUNT(*) AS count FROM scrape_jobs GROUP BY state ORDER BY state',
      );
      return _countsBy(rows, 'state');
    });
    final sourceErrorCounts = await safe(
      'sourceErrors',
      const <String, int>{},
      () async {
        final rows = await database.rawQuery('''
          SELECT COALESCE(source, 'unknown') AS source, COUNT(*) AS count
          FROM scrape_job_events
          WHERE severity IN ('warning', 'error')
            AND created_at >= datetime('now', '-7 day')
          GROUP BY source
          ORDER BY count DESC, source ASC
        ''');
        return _countsBy(rows, 'source');
      },
    );
    return DataHealthSnapshot(
      generatedAt: DateTime.now().toUtc(),
      actressCount: actressCount,
      workCount: workCount,
      storedWorkCount: storedWorkCount,
      notStoredWorkCount: (workCount - storedWorkCount).clamp(0, workCount),
      missingReleaseDateCount: missingReleaseDateCount,
      missingStudioCount: missingStudioCount,
      missingPublisherCount: missingPublisherCount,
      missingSeriesCount: missingSeriesCount,
      missingCardImageCount: missingCardImageCount,
      missingDetailImageCount: missingDetailImageCount,
      missingProvenanceCount: missingProvenanceCount,
      pendingDeletionCount: pendingDeletionCount,
      jobCounts: Map.unmodifiable(jobCounts),
      sourceErrorCounts: Map.unmodifiable(sourceErrorCounts),
      warnings: List.unmodifiable(warnings),
    );
  }

  Map<String, int> _countsBy(List<Map<String, Object?>> rows, String key) {
    final counts = <String, int>{};
    for (final row in rows) {
      counts[row[key]?.toString() ?? 'unknown'] = _number(row['count']);
    }
    return counts;
  }

  Future<int> _count(
    DatabaseExecutor database,
    String table, {
    String? where,
  }) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM $table${where == null ? '' : ' WHERE $where'}',
    );
    return _number(rows.firstOrNull?['count']);
  }

  Future<int> _missing(DatabaseExecutor database, String column) => _count(
    database,
    'works',
    where: '$column IS NULL OR TRIM(CAST($column AS TEXT)) = \'\'',
  );

  Future<int> _missingImageReferences(
    DatabaseExecutor database,
    String column,
  ) async {
    final rows = await database.query('works', columns: [column]);
    var missing = 0;
    for (final row in rows) {
      final storedPath = row[column]?.toString().trim() ?? '';
      try {
        if (storedPath.isEmpty ||
            await db.resolveManagedImageForTransfer(storedPath) == null) {
          missing++;
        }
      } on Object {
        missing++;
      }
    }
    return missing;
  }
}

int _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
