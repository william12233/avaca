import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:avaca/core/database.dart';
import 'package:crypto/crypto.dart';
import 'package:avaca/models/data_transfer_manifest.dart';
import 'package:avaca/models/work_storage.dart';
import 'package:avaca/models/data_transfer_models.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/services/data_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory sourceDirectory;
  late Directory targetDirectory;
  late AppDatabase source;
  late AppDatabase target;

  setUp(() async {
    sourceDirectory = await Directory.systemTemp.createTemp(
      'avaca_transfer_source_',
    );
    targetDirectory = await Directory.systemTemp.createTemp(
      'avaca_transfer_target_',
    );
    source = AppDatabase.forTesting(
      baseDir: sourceDirectory.path,
      databaseFactory: databaseFactoryFfi,
    );
    target = AppDatabase.forTesting(
      baseDir: targetDirectory.path,
      databaseFactory: databaseFactoryFfi,
    );
    await source.init();
    await target.init();
  });

  tearDown(() async {
    await source.close();
    await target.close();
    if (sourceDirectory.existsSync()) {
      await sourceDirectory.delete(recursive: true);
    }
    if (targetDirectory.existsSync()) {
      await targetDirectory.delete(recursive: true);
    }
  });

  test(
    'exported ZIP imports into a clean database with usable images',
    () async {
      final avatar = File(path.join(source.imgDir, 'avatar.jpg'));
      final card = File(path.join(source.imgDir, 'works', 'card.jpg'));
      final detail = File(path.join(source.imgDir, 'works', 'detail.jpg'));
      await card.parent.create(recursive: true);
      await avatar.writeAsBytes([1, 2, 3, 4]);
      await card.writeAsBytes([5, 6, 7]);
      await detail.writeAsBytes([8, 9]);

      await source.addActress(
        name: 'Round Trip Actor',
        imgPath: avatar.path,
        mainType: '無碼',
        tags: 'tag-a,tag-b',
        memo: 'memo',
        birthDate: '1999-01-01',
      );
      final sqlite = await source.database;
      final actressId =
          (await sqlite.query('actresses', columns: ['id'])).single['id']
              as int;
      await sqlite.update(
        'actresses',
        {'height': '160', 'weight': '48', 'bwh': '85-55-85', 'cup': 'F'},
        where: 'id = ?',
        whereArgs: [actressId],
      );
      await source.replaceActressAliases(
        actressId: actressId,
        aliases: const ['RTA', 'Round Trip'],
      );
      final workId = await source.upsertActressWork(
        actressId: actressId,
        work: Work(
          code: 'RT-001',
          title: 'Round Trip Work',
          releaseDate: '2026-01-02',
          durationMinutes: 120,
          studio: 'Studio',
          publisher: 'Publisher',
          series: 'Series',
          cardImagePath: card.path,
          detailImagePath: detail.path,
        ),
      );
      await source.updateWorkStorage(
        workId: workId,
        record: const WorkStorageRecord(
          storageOptions: {
            WorkStorageOption.cracked,
            WorkStorageOption.original,
          },
          quality: '4K',
          frameRate: 30,
        ),
      );

      final exported = await DataTransferService(db: source).buildExport();
      expect(exported.bytes, isNotEmpty);
      expect(exported.summary.actresses, 1);
      expect(exported.summary.works, 1);
      expect(exported.summary.images, 3);
      final archive = ZipDecoder().decodeBytes(exported.bytes);
      expect(
        archive.files.map((file) => file.name),
        containsAll(['assets/rt00001ps.jpg', 'assets/rt00001pl.jpg']),
      );

      final result = await DataTransferService(
        db: target,
      ).importArchive(bytes: exported.bytes);
      expect(result.succeeded, isTrue);

      final importedActors = await target.getAllActresses();
      expect(importedActors, hasLength(1));
      expect(importedActors.single['name'], 'Round Trip Actor');
      final importedId = importedActors.single['id'] as int;
      final importedDetails = await target.getActressById(importedId);
      expect(importedDetails?['birth_date'], '1999-01-01');
      expect(importedDetails?['aliases'], containsAll(['RTA', 'Round Trip']));
      expect(await target.getWorkCountForActress(importedId), 1);
      final importedWork = (await target.getWorksForActress(importedId)).single;
      expect(importedWork['code'], 'RT-001');
      expect(importedWork['is_stored'], 1);
      expect(importedWork['storage_cracked'], 1);
      expect(importedWork['storage_original'], 1);
      expect(importedWork['storage_subtitles'], 0);
      expect(importedWork['storage_quality'], '4K');
      expect(importedWork['storage_frame_rate'], 30);
      expect(
        path.basename(importedWork['card_image_path'] as String),
        'rt00001ps.jpg',
      );
      expect(
        path.basename(importedWork['detail_image_path'] as String),
        'rt00001pl.jpg',
      );
      expect(
        await File(importedActors.single['img_path'] as String).exists(),
        isTrue,
      );
      expect(
        await File(importedWork['card_image_path'] as String).exists(),
        isTrue,
      );
      expect(
        await File(importedWork['detail_image_path'] as String).exists(),
        isTrue,
      );
    },
  );

  test(
    'duplicate actor resolution keeps existing details but imports relations',
    () async {
      await source.addActress(name: 'Duplicate Actor', mainType: 'imported');
      final sourceDb = await source.database;
      final sourceActorId =
          (await sourceDb.query('actresses')).single['id'] as int;
      await source.upsertActressWork(
        actressId: sourceActorId,
        work: const Work(code: 'DUP-001', title: 'Imported Work'),
      );
      await target.addActress(name: 'duplicate actor', mainType: 'existing');

      DataTransferDuplicateCandidate? candidate;
      final exported = await DataTransferService(db: source).buildExport();
      final result = await DataTransferService(db: target).importArchive(
        bytes: exported.bytes,
        resolveDuplicate: (value) async {
          candidate = value;
          return DataTransferDuplicateResolution.keepExisting;
        },
      );

      expect(result.succeeded, isTrue);
      expect(candidate, isNotNull);
      expect(candidate!.existingWorkCount, 0);
      expect(candidate!.importedWorkCount, 1);
      final actors = await target.getAllActresses();
      expect(actors, hasLength(1));
      final targetActorId = actors.single['id'] as int;
      expect(
        (await target.getActressById(targetActorId))?['main_type'],
        'existing',
      );
      expect(await target.getWorkCountForActress(targetActorId), 1);
    },
  );

  test(
    'imports a file-backed archive without loading its assets map',
    () async {
      final assetBytes = Uint8List.fromList([1, 2, 3, 4]);
      final manifest = DataTransferManifest(
        exportedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        actresses: const [
          DataTransferActress(
            id: 'a000001',
            name: 'Streamed Actor',
            avatarAssetId: 'asset000001',
            birthDate: null,
            mainType: null,
            tags: null,
            memo: null,
            height: null,
            weight: null,
            bwh: null,
            cup: null,
            aliases: [],
          ),
        ],
        works: const [],
        relations: const [],
        assets: [
          DataTransferAsset(
            id: 'asset000001',
            path: 'assets/avatar.jpg',
            size: assetBytes.length,
            sha256: sha256.convert(assetBytes).toString(),
          ),
        ],
      );
      final bytes = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string('manifest.json', manifest.encode()))
            ..addFile(ArchiveFile.bytes('assets/avatar.jpg', assetBytes)),
        ),
      );
      final archivePath = path.join(sourceDirectory.path, 'streamed.zip');
      await File(archivePath).writeAsBytes(bytes);

      final result = await DataTransferService(
        db: target,
      ).importArchiveFile(file: File(archivePath));

      expect(result.succeeded, isTrue);
      final imported = (await target.getAllActresses()).single;
      expect(
        await File(imported['img_path'] as String).readAsBytes(),
        assetBytes,
      );
    },
  );

  test('invalid ZIP returns an error without changing the database', () async {
    final before = await (await target.database).rawQuery(
      'SELECT COUNT(*) AS count FROM actresses',
    );
    final result = await DataTransferService(
      db: target,
    ).importArchive(bytes: Uint8List.fromList([1, 2, 3, 4]));
    final after = await (await target.database).rawQuery(
      'SELECT COUNT(*) AS count FROM actresses',
    );
    expect(result.succeeded, isFalse);
    expect(result.error, isNotNull);
    expect(after.single['count'], before.single['count']);
  });

  test('ZIP traversal entries are rejected before staging files', () async {
    final manifest = DataTransferManifest(
      exportedAt: '2026-08-10T00:00:00Z',
      actresses: const [],
      works: const [],
      relations: const [],
      assets: [
        DataTransferAsset(
          id: 'asset000001',
          path: '../outside.jpg',
          size: 3,
          sha256:
              '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a2b5f6a7c5be',
        ),
      ],
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('manifest.json', utf8.encode(manifest.encode())),
      )
      ..addFile(ArchiveFile.bytes('../outside.jpg', [1, 2, 3]));

    final result = await DataTransferService(
      db: target,
    ).importArchive(bytes: Uint8List.fromList(ZipEncoder().encode(archive)));

    expect(result.succeeded, isFalse);
    expect(result.error?.code, 'unsafe_archive');
    final count = await (await target.database).rawQuery(
      'SELECT COUNT(*) AS count FROM actresses',
    );
    expect(count.single['count'], 0);
  });

  test(
    'import keeps staged images referenced by the committed database rows',
    () async {
      final avatar = File(path.join(source.imgDir, 'avatar.jpg'));
      await avatar.writeAsBytes([1, 2, 3, 4]);
      await source.addActress(name: 'Staged Image Actor', imgPath: avatar.path);

      final exported = await DataTransferService(db: source).buildExport();
      final result = await DataTransferService(
        db: target,
      ).importArchive(bytes: exported.bytes);

      expect(result.succeeded, isTrue);
      final imported = (await target.getAllActresses()).single;
      final importedPath = imported['img_path'] as String;
      expect(importedPath, contains('.imports'));
      expect(await File(importedPath).readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test('import normalizes legacy work asset names to the work code', () async {
    const payload = [1, 2, 3];
    const checksum =
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';
    final manifest = DataTransferManifest(
      exportedAt: '2026-08-10T00:00:00Z',
      actresses: const [],
      works: const [
        DataTransferWork(
          id: 'w000001',
          code: 'START-489',
          title: 'Legacy asset names',
          releaseDate: null,
          durationMinutes: null,
          studio: null,
          publisher: null,
          series: null,
          cardImageAssetId: 'asset000001',
          detailImageAssetId: 'asset000002',
          createdAt: null,
          modifiedAt: null,
        ),
      ],
      relations: const [],
      assets: const [
        DataTransferAsset(
          id: 'asset000001',
          path: 'assets/asset000001.jpg',
          size: 3,
          sha256: checksum,
        ),
        DataTransferAsset(
          id: 'asset000002',
          path: 'assets/asset000002.jpg',
          size: 3,
          sha256: checksum,
        ),
      ],
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('manifest.json', utf8.encode(manifest.encode())),
      )
      ..addFile(ArchiveFile.bytes('assets/asset000001.jpg', payload))
      ..addFile(ArchiveFile.bytes('assets/asset000002.jpg', payload));

    final result = await DataTransferService(
      db: target,
    ).importArchive(bytes: Uint8List.fromList(ZipEncoder().encode(archive)));

    expect(result.succeeded, isTrue, reason: result.error?.toString());
    final imported = (await target.database).query(
      'works',
      columns: const ['card_image_path', 'detail_image_path'],
      where: 'code = ?',
      whereArgs: ['START-489'],
    );
    final work = (await imported).single;
    expect(
      path.basename(work['card_image_path'] as String),
      'start00489ps.jpg',
    );
    expect(
      path.basename(work['detail_image_path'] as String),
      'start00489pl.jpg',
    );
  });
}
