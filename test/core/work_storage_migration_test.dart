import 'dart:io';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/work_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'clears legacy work storage when storage options are first added',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'avaca-work-storage-migration-',
      );
      AppDatabase? database;
      try {
        final legacy = await databaseFactoryFfi.openDatabase(
          path.join(directory.path, AppDatabase.databaseFileName),
        );
        await legacy.execute('''
        CREATE TABLE actresses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          img_path TEXT,
          modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
        await legacy.execute('''
        CREATE TABLE works (
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
        await legacy.insert('works', {
          'code': 'LEGACY-001',
          'title': '舊儲存紀錄',
          'is_stored': 1,
          'storage_quality': '1080',
          'storage_frame_rate': 60,
        });
        await legacy.close();

        database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        await database.init();

        final row = await database.getWorkById(1);
        expect(row?['is_stored'], 0);
        expect(row?['storage_cracked'], 0);
        expect(row?['storage_original'], 0);
        expect(row?['storage_subtitles'], 0);
        expect(row?['storage_quality'], isNull);
        expect(row?['storage_frame_rate'], isNull);

        final sqlite = await database.database;
        final columns = await sqlite.rawQuery('PRAGMA table_info(works)');
        expect(
          columns.map((column) => column['name']),
          containsAll([
            'storage_cracked',
            'storage_original',
            'storage_subtitles',
          ]),
        );

        await database.updateWorkStorage(
          workId: 1,
          record: const WorkStorageRecord(
            storageOptions: {WorkStorageOption.original},
            quality: '2K',
          ),
        );
        await database.close();
        database = AppDatabase.forTesting(
          baseDir: directory.path,
          databaseFactory: databaseFactoryFfi,
        );
        await database.init();
        final reopened = await database.getWorkById(1);
        expect(reopened?['is_stored'], 1);
        expect(reopened?['storage_original'], 1);
        expect(reopened?['storage_quality'], '2K');
      } finally {
        await database?.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
