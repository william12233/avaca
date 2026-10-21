import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../core/database.dart';
import '../models/data_transfer_manifest.dart';
import '../models/data_transfer_models.dart';
import 'javbus/work_image_policy.dart';

typedef DataTransferDuplicateResolver =
    Future<DataTransferDuplicateResolution?> Function(
      DataTransferDuplicateCandidate candidate,
    );

typedef DataTransferProgressCallback =
    void Function(DataTransferProgress progress);

class DataTransferExport {
  const DataTransferExport({required this.bytes, required this.summary});

  final Uint8List bytes;
  final DataTransferSummary summary;
}

/// A file-backed export used by platform pickers that can copy a path.
/// Keeping the archive on disk avoids retaining every image and the encoded
/// ZIP in Dart heap at the same time.
class DataTransferFileExport {
  const DataTransferFileExport({required this.file, required this.summary});

  final File file;
  final DataTransferSummary summary;
}

class DataTransferService {
  DataTransferService({required this.db});

  final AppDatabase db;
  static const _workImagePolicy = WorkImagePolicy();

  Future<DataTransferExport> buildExport({
    DataTransferProgressCallback? onProgress,
  }) async {
    final exported = await buildExportFile(onProgress: onProgress);
    try {
      final bytes = await exported.file.readAsBytes();
      if (bytes.length > DataTransferLimits.maxArchiveBytes) {
        throw const DataTransferException(
          'archive_too_large',
          'The portable archive exceeds the supported size.',
        );
      }
      return DataTransferExport(
        bytes: Uint8List.fromList(bytes),
        summary: exported.summary,
      );
    } finally {
      if (await exported.file.exists()) {
        await exported.file.delete();
      }
    }
  }

  /// Builds the archive directly on disk so callers can hand it to a native
  /// save dialog without materializing the complete ZIP in memory.
  Future<DataTransferFileExport> buildExportFile({
    DataTransferProgressCallback? onProgress,
  }) async {
    await db.database;
    final directory = Directory(path.join(db.baseDir, '.exports'));
    await directory.create(recursive: true);
    final outputFile = File(
      path.join(
        directory.path,
        'avaca-export-${DateTime.now().microsecondsSinceEpoch}.zip',
      ),
    );
    try {
      return await _buildExportFile(
        outputFile: outputFile,
        onProgress: onProgress,
      );
    } catch (_) {
      if (await outputFile.exists()) await outputFile.delete();
      rethrow;
    }
  }

  Future<DataTransferFileExport> _buildExportFile({
    required File outputFile,
    DataTransferProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const DataTransferProgress(phase: DataTransferPhase.preparing),
    );

    final database = await db.database;
    final actressRows = await database.query(
      'actresses',
      columns: const [
        'id',
        'name',
        'img_path',
        'birth_date',
        'main_type',
        'tags',
        'memo',
        'height',
        'weight',
        'bwh',
        'cup',
      ],
      orderBy: 'name COLLATE NOCASE ASC, name ASC, id ASC',
    );
    final aliasRows = await database.query(
      'actress_aliases',
      columns: const ['actress_id', 'alias'],
      orderBy: 'actress_id ASC, alias COLLATE NOCASE ASC',
    );
    final aliasesByActress = <int, List<String>>{};
    for (final row in aliasRows) {
      final actressId = _asInt(row['actress_id']);
      final alias = row['alias']?.toString();
      if (actressId != null && alias != null && alias.trim().isNotEmpty) {
        (aliasesByActress[actressId] ??= <String>[]).add(alias);
      }
    }

    final workRows = await database.query(
      'works',
      columns: const [
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
        'created_at',
        'modified_at',
      ],
      orderBy: 'code COLLATE NOCASE ASC, code ASC, id ASC',
    );
    final provenanceRows = await database.query(
      'work_field_provenance',
      columns: const [
        'work_id',
        'field',
        'source',
        'source_uri',
        'observed_at',
      ],
      orderBy: 'work_id ASC, field ASC',
    );
    final provenanceByWork = <int, List<DataTransferProvenance>>{};
    for (final row in provenanceRows) {
      final workId = _asInt(row['work_id']);
      final field = row['field']?.toString().trim() ?? '';
      final source = row['source']?.toString().trim() ?? '';
      if (workId == null || field.isEmpty || source.isEmpty) continue;
      (provenanceByWork[workId] ??= <DataTransferProvenance>[]).add(
        DataTransferProvenance(
          field: field,
          source: source,
          sourceUri: _asNullableString(row['source_uri']),
          observedAt: _asNullableString(row['observed_at']),
        ),
      );
    }
    final relationRows = await database.query(
      'actress_works',
      columns: const ['actress_id', 'work_id'],
      orderBy: 'actress_id ASC, work_id ASC',
    );

    final imageBySource = <String, _ExportImage>{};
    var skippedImages = 0;

    Future<String?> collectImage(
      String? storedPath, {
      String? preferredArchiveFileName,
    }) async {
      final file = await db.resolveManagedImageForTransfer(storedPath);
      if (file == null) {
        if (storedPath?.trim().isNotEmpty ?? false) skippedImages++;
        return null;
      }
      final sourceKey = _imageKey(file.path);
      final preferredFileName = preferredArchiveFileName == null
          ? null
          : '${path.basenameWithoutExtension(preferredArchiveFileName)}'
                '${_supportedExtension(file.path)}';
      final existing = imageBySource[sourceKey];
      if (existing == null) {
        final size = await file.length();
        if (size > DataTransferLimits.maxSingleEntryBytes) {
          throw const DataTransferException(
            'archive_too_large',
            'A referenced image exceeds the portable archive limit.',
          );
        }
        imageBySource[sourceKey] = _ExportImage(
          sourceKey: sourceKey,
          file: file,
          size: size,
          extension: _supportedExtension(file.path),
          sha256: await _sha256File(file),
          preferredFileName: preferredFileName,
        );
      } else if (existing.preferredFileName == null &&
          preferredFileName != null) {
        existing.preferredFileName = preferredFileName;
      }
      return sourceKey;
    }

    final actressDrafts = <_ExportActressDraft>[];
    for (final row in actressRows) {
      final id = _asInt(row['id']);
      final name = row['name']?.toString().trim() ?? '';
      if (id == null || name.isEmpty) continue;
      actressDrafts.add(
        _ExportActressDraft(
          sourceId: id,
          name: name,
          avatarSourceKey: await collectImage(row['img_path']?.toString()),
          birthDate: _asNullableString(row['birth_date']),
          mainType: _asNullableString(row['main_type']),
          tags: _asNullableString(row['tags']),
          memo: _asNullableString(row['memo']),
          height: _asNullableString(row['height']),
          weight: _asNullableString(row['weight']),
          bwh: _asNullableString(row['bwh']),
          cup: _asNullableString(row['cup']),
          aliases: List.unmodifiable(aliasesByActress[id] ?? const []),
        ),
      );
    }

    final workDrafts = <_ExportWorkDraft>[];
    for (final row in workRows) {
      final id = _asInt(row['id']);
      final code = row['code']?.toString().trim() ?? '';
      final title = row['title']?.toString().trim() ?? '';
      if (id == null || code.isEmpty || title.isEmpty) continue;
      final duration = _asInt(row['duration_minutes']);
      if (duration != null && duration < 0) {
        throw const DataTransferException(
          'invalid_data',
          'A work contains a negative duration.',
        );
      }
      workDrafts.add(
        _ExportWorkDraft(
          sourceId: id,
          code: code,
          title: title,
          releaseDate: _asNullableString(row['release_date']),
          durationMinutes: duration,
          studio: _asNullableString(row['studio']),
          publisher: _asNullableString(row['publisher']),
          series: _asNullableString(row['series']),
          cardSourceKey: await collectImage(
            row['card_image_path']?.toString(),
            preferredArchiveFileName: _workImagePolicy.fileNameFor(
              code: code,
              variant: WorkImageVariant.card,
            ),
          ),
          detailSourceKey: await collectImage(
            row['detail_image_path']?.toString(),
            preferredArchiveFileName: _workImagePolicy.fileNameFor(
              code: code,
              variant: WorkImageVariant.detail,
            ),
          ),
          isStored: row['is_stored'] is num && row['is_stored'] != 0,
          storageQuality: _asNullableString(row['storage_quality']),
          storageFrameRate: _asInt(row['storage_frame_rate']),
          createdAt: _asNullableString(row['created_at']),
          modifiedAt: _asNullableString(row['modified_at']),
          provenance: List.unmodifiable(provenanceByWork[id] ?? const []),
        ),
      );
    }

    final sortedActresses = [...actressDrafts]
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.sourceId.compareTo(b.sourceId);
      });
    final sortedWorks = [...workDrafts]
      ..sort((a, b) {
        final byCode = a.code.toLowerCase().compareTo(b.code.toLowerCase());
        return byCode != 0 ? byCode : a.sourceId.compareTo(b.sourceId);
      });

    final actressIds = <int, String>{};
    final exportedActresses = <DataTransferActress>[];
    for (var index = 0; index < sortedActresses.length; index++) {
      final draft = sortedActresses[index];
      final archiveId = 'a${(index + 1).toString().padLeft(6, '0')}';
      actressIds[draft.sourceId] = archiveId;
      exportedActresses.add(
        DataTransferActress(
          id: archiveId,
          name: draft.name,
          avatarAssetId: draft.avatarSourceKey,
          birthDate: draft.birthDate,
          mainType: draft.mainType,
          tags: draft.tags,
          memo: draft.memo,
          height: draft.height,
          weight: draft.weight,
          bwh: draft.bwh,
          cup: draft.cup,
          aliases: [...draft.aliases]
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        ),
      );
    }

    final workIds = <int, String>{};
    final exportedWorks = <DataTransferWork>[];
    for (var index = 0; index < sortedWorks.length; index++) {
      final draft = sortedWorks[index];
      final archiveId = 'w${(index + 1).toString().padLeft(6, '0')}';
      workIds[draft.sourceId] = archiveId;
      exportedWorks.add(
        DataTransferWork(
          id: archiveId,
          code: draft.code,
          title: draft.title,
          releaseDate: draft.releaseDate,
          durationMinutes: draft.durationMinutes,
          studio: draft.studio,
          publisher: draft.publisher,
          series: draft.series,
          cardImageAssetId: draft.cardSourceKey,
          detailImageAssetId: draft.detailSourceKey,
          createdAt: draft.createdAt,
          modifiedAt: draft.modifiedAt,
          isStored: draft.isStored,
          storageQuality: draft.storageQuality,
          storageFrameRate: draft.storageFrameRate,
          provenance: draft.provenance,
        ),
      );
    }

    final sortedAssets = imageBySource.values.toList()
      ..sort((a, b) => a.sourceKey.compareTo(b.sourceKey));
    final assetIds = <String, String>{};
    final exportedAssets = <DataTransferAsset>[];
    final usedArchiveFileNames = <String>{};
    for (var index = 0; index < sortedAssets.length; index++) {
      final image = sortedAssets[index];
      final archiveId = 'asset${(index + 1).toString().padLeft(6, '0')}';
      assetIds[image.sourceKey] = archiveId;
      var archiveFileName =
          image.preferredFileName ?? '$archiveId${image.extension}';
      if (!usedArchiveFileNames.add(archiveFileName.toLowerCase())) {
        archiveFileName = '$archiveId${image.extension}';
        var collision = 1;
        while (!usedArchiveFileNames.add(archiveFileName.toLowerCase())) {
          archiveFileName = '$archiveId-$collision${image.extension}';
          collision++;
        }
      }
      image.archivePath = 'assets/$archiveFileName';
      exportedAssets.add(
        DataTransferAsset(
          id: archiveId,
          path: image.archivePath!,
          size: image.size,
          sha256: image.sha256,
        ),
      );
    }

    final manifest = DataTransferManifest(
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      actresses: exportedActresses
          .map(
            (item) => DataTransferActress(
              id: item.id,
              name: item.name,
              avatarAssetId: item.avatarAssetId == null
                  ? null
                  : assetIds[item.avatarAssetId!],
              birthDate: item.birthDate,
              mainType: item.mainType,
              tags: item.tags,
              memo: item.memo,
              height: item.height,
              weight: item.weight,
              bwh: item.bwh,
              cup: item.cup,
              aliases: item.aliases,
            ),
          )
          .toList(growable: false),
      works: exportedWorks
          .map(
            (item) => DataTransferWork(
              id: item.id,
              code: item.code,
              title: item.title,
              releaseDate: item.releaseDate,
              durationMinutes: item.durationMinutes,
              studio: item.studio,
              publisher: item.publisher,
              series: item.series,
              cardImageAssetId: item.cardImageAssetId == null
                  ? null
                  : assetIds[item.cardImageAssetId!],
              detailImageAssetId: item.detailImageAssetId == null
                  ? null
                  : assetIds[item.detailImageAssetId!],
              createdAt: item.createdAt,
              modifiedAt: item.modifiedAt,
              isStored: item.isStored,
              storageQuality: item.storageQuality,
              storageFrameRate: item.storageFrameRate,
              provenance: item.provenance,
            ),
          )
          .toList(growable: false),
      relations: relationRows
          .map((row) {
            final actressId = actressIds[_asInt(row['actress_id'])];
            final workId = workIds[_asInt(row['work_id'])];
            if (actressId == null || workId == null) return null;
            return DataTransferRelation(actressId: actressId, workId: workId);
          })
          .whereType<DataTransferRelation>()
          .toList(growable: false),
      assets: exportedAssets,
    );

    final manifestBytes = Uint8List.fromList(utf8.encode(manifest.encode()));
    if (manifestBytes.length > DataTransferLimits.maxManifestBytes) {
      throw const DataTransferException(
        'archive_too_large',
        'The manifest exceeds the portable archive limit.',
      );
    }
    var totalBytes = manifestBytes.length;
    for (final image in sortedAssets) {
      totalBytes += image.size;
      if (totalBytes > DataTransferLimits.maxTotalUncompressedBytes) {
        throw const DataTransferException(
          'archive_too_large',
          'The library exceeds the portable archive limit.',
        );
      }
    }

    onProgress?.call(
      DataTransferProgress(
        phase: DataTransferPhase.writing,
        completed: 0,
        total: sortedAssets.length,
      ),
    );
    final encoder = ZipFileEncoder();
    encoder.create(outputFile.path);
    var encoderClosed = false;
    try {
      encoder.addArchiveFile(ArchiveFile.bytes('manifest.json', manifestBytes));
      for (var index = 0; index < sortedAssets.length; index++) {
        final image = sortedAssets[index];
        if (await image.file.length() != image.size) {
          throw const DataTransferException(
            'file_changed',
            'A referenced image changed while the archive was being built.',
          );
        }
        await encoder.addFile(image.file, image.archivePath!);
        onProgress?.call(
          DataTransferProgress(
            phase: DataTransferPhase.writing,
            completed: index + 1,
            total: sortedAssets.length,
          ),
        );
      }
      await encoder.close();
      encoderClosed = true;
    } finally {
      if (!encoderClosed) {
        try {
          await encoder.close();
        } catch (_) {
          // Preserve the original archive-building error.
        }
      }
    }
    if (await outputFile.length() > DataTransferLimits.maxArchiveBytes) {
      throw const DataTransferException(
        'archive_too_large',
        'The portable archive exceeds the supported size.',
      );
    }
    return DataTransferFileExport(
      file: outputFile,
      summary: DataTransferSummary(
        actresses: exportedActresses.length,
        works: exportedWorks.length,
        images: exportedAssets.length,
        skippedImages: skippedImages,
      ),
    );
  }

  Future<String> _sha256File(File file) async {
    final sink = _DataTransferDigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.value.toString();
  }

  Future<DataTransferOperationResult> importArchive({
    required Uint8List bytes,
    DataTransferDuplicateResolver? resolveDuplicate,
    DataTransferProgressCallback? onProgress,
  }) async {
    try {
      if (bytes.length > DataTransferLimits.maxArchiveBytes) {
        throw const DataTransferException(
          'archive_too_large',
          'The selected ZIP exceeds the supported size.',
        );
      }
      onProgress?.call(
        const DataTransferProgress(phase: DataTransferPhase.preparing),
      );
      final prepared = await _prepareImport(bytes);
      final resolutions = <String, DataTransferDuplicateResolution>{};
      for (final candidate in prepared.duplicates) {
        onProgress?.call(
          const DataTransferProgress(
            phase: DataTransferPhase.reviewingDuplicates,
          ),
        );
        if (resolveDuplicate == null) {
          throw const DataTransferException(
            'duplicate_requires_choice',
            'Duplicate actresses require an explicit choice.',
          );
        }
        final resolution = await resolveDuplicate(candidate);
        if (resolution == null) {
          throw const DataTransferCancelled();
        }
        resolutions[candidate.imported.id] = resolution;
      }

      final operationId =
          'transfer-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      final directory = Directory(
        path.join(db.imgDir, '.imports', operationId),
      );
      await directory.create(recursive: true);
      final localAssetPaths = <String, String>{};
      final preferredImportFileNames = <String, String>{};
      for (final work in prepared.manifest.works) {
        final code = work.code.trim();
        final cardAssetId = work.cardImageAssetId;
        if (cardAssetId != null) {
          preferredImportFileNames.putIfAbsent(
            cardAssetId,
            () => _workImagePolicy.fileNameFor(
              code: code,
              variant: WorkImageVariant.card,
            ),
          );
        }
        final detailAssetId = work.detailImageAssetId;
        if (detailAssetId != null) {
          preferredImportFileNames.putIfAbsent(
            detailAssetId,
            () => _workImagePolicy.fileNameFor(
              code: code,
              variant: WorkImageVariant.detail,
            ),
          );
        }
      }
      final stagedFileNames = <String>{};
      var committed = false;
      try {
        onProgress?.call(
          DataTransferProgress(
            phase: DataTransferPhase.writing,
            completed: 0,
            total: prepared.manifest.assets.length,
          ),
        );
        for (var index = 0; index < prepared.manifest.assets.length; index++) {
          final asset = prepared.manifest.assets[index];
          final extension = _supportedExtension(asset.path);
          final preferredFileName = preferredImportFileNames[asset.id];
          var stagedFileName = preferredFileName == null
              ? path.basename(asset.path)
              : '${path.basenameWithoutExtension(preferredFileName)}$extension';
          if (!stagedFileNames.add(stagedFileName.toLowerCase())) {
            stagedFileName = 'asset-$index$extension';
            var collision = 1;
            while (!stagedFileNames.add(stagedFileName.toLowerCase())) {
              stagedFileName = 'asset-$index-$collision$extension';
              collision++;
            }
          }
          final target = File(path.join(directory.path, stagedFileName));
          await target.writeAsBytes(
            prepared.assetBytes[asset.id]!,
            flush: true,
          );
          localAssetPaths[asset.id] = target.path;
          onProgress?.call(
            DataTransferProgress(
              phase: DataTransferPhase.writing,
              completed: index + 1,
              total: prepared.manifest.assets.length,
            ),
          );
        }

        await db.runDataTransferTransaction((transaction) async {
          await _commitImport(
            transaction,
            prepared,
            localAssetPaths,
            resolutions,
          );
        });
        committed = true;
        await _cleanupUnreferencedImportAssets(directory, localAssetPaths);
        await db.flushDataTransferFileDeletions();
      } catch (_) {
        if (!committed && await directory.exists()) {
          await directory.delete(recursive: true);
        }
        rethrow;
      }

      return DataTransferOperationResult(
        cancelled: false,
        summary: DataTransferSummary(
          actresses: prepared.manifest.actresses.length,
          works: prepared.manifest.works.length,
          images: prepared.manifest.assets.length,
          duplicatesResolved: resolutions.length,
        ),
      );
    } on DataTransferCancelled {
      return const DataTransferOperationResult(cancelled: true);
    } on DataTransferException catch (error) {
      return DataTransferOperationResult(cancelled: false, error: error);
    } on FormatException catch (error) {
      return DataTransferOperationResult(
        cancelled: false,
        error: DataTransferException('invalid_archive', error.message),
      );
    } on Object catch (error) {
      return DataTransferOperationResult(
        cancelled: false,
        error: DataTransferException('transfer_failed', error.toString()),
      );
    }
  }

  Future<_PreparedImport> _prepareImport(Uint8List bytes) async {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes, verify: true);
    final headers = decoder.directory.fileHeaders;
    if (headers.length > DataTransferLimits.maxEntries) {
      throw const DataTransferException(
        'archive_too_large',
        'The ZIP contains too many entries.',
      );
    }

    final headerNames = <String>{};
    var totalHeaderBytes = 0;
    for (final header in headers) {
      final rawName = header.filename;
      final isDirectory = rawName.endsWith('/');
      final name = _validateArchivePath(
        isDirectory ? rawName.substring(0, rawName.length - 1) : rawName,
      );
      if (!headerNames.add(name)) {
        throw const DataTransferException(
          'unsafe_archive',
          'The ZIP contains duplicate entries.',
        );
      }
      if (header.uncompressedSize > DataTransferLimits.maxSingleEntryBytes) {
        throw const DataTransferException(
          'archive_too_large',
          'A ZIP entry exceeds the supported size.',
        );
      }
      totalHeaderBytes += header.uncompressedSize;
      if (totalHeaderBytes > DataTransferLimits.maxTotalUncompressedBytes) {
        throw const DataTransferException(
          'archive_too_large',
          'The ZIP expands beyond the supported size.',
        );
      }
      if (header.uncompressedSize > 0 &&
          (header.compressedSize <= 0 ||
              header.uncompressedSize >
                  header.compressedSize *
                      DataTransferLimits.maxCompressionRatio)) {
        throw const DataTransferException(
          'unsafe_archive',
          'The ZIP compression ratio is unsafe.',
        );
      }
    }

    final entries = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (entry.isDirectory) {
        _validateArchivePath(
          entry.name.endsWith('/')
              ? entry.name.substring(0, entry.name.length - 1)
              : entry.name,
        );
        continue;
      }
      final name = _validateArchivePath(entry.name);
      if (!entries.containsKey(name)) {
        entries[name] = entry;
      } else {
        throw const DataTransferException(
          'unsafe_archive',
          'The ZIP contains duplicate entries.',
        );
      }
      if (entry.isSymbolicLink) {
        throw const DataTransferException(
          'unsafe_archive',
          'Symbolic links are not supported in portable archives.',
        );
      }
      if (entry.isFile && entry.size > DataTransferLimits.maxSingleEntryBytes) {
        throw const DataTransferException(
          'archive_too_large',
          'A ZIP entry exceeds the supported size.',
        );
      }
    }

    final manifestEntry = entries['manifest.json'];
    if (manifestEntry == null || !manifestEntry.isFile) {
      throw const DataTransferException(
        'invalid_archive',
        'The ZIP does not contain manifest.json.',
      );
    }
    if (manifestEntry.size > DataTransferLimits.maxManifestBytes) {
      throw const DataTransferException(
        'archive_too_large',
        'The manifest exceeds the supported size.',
      );
    }
    final manifestBytes = manifestEntry.readBytes();
    if (manifestBytes == null) {
      throw const DataTransferException(
        'corrupt_archive',
        'The manifest could not be read.',
      );
    }

    final manifest = DataTransferManifest.fromJson(
      jsonDecode(utf8.decode(manifestBytes, allowMalformed: false)),
    );
    final assetByPath = <String, DataTransferAsset>{};
    for (final asset in manifest.assets) {
      final safePath = _validateArchivePath(asset.path);
      if (!safePath.startsWith('assets/')) {
        throw const DataTransferException(
          'unsafe_archive',
          'Asset paths must remain under assets/.',
        );
      }
      if (assetByPath.containsKey(safePath)) {
        throw const DataTransferException(
          'unsafe_archive',
          'The manifest contains duplicate asset paths.',
        );
      }
      assetByPath[safePath] = asset;
    }

    final assetBytes = <String, Uint8List>{};
    var totalBytes = manifestBytes.length;
    for (final asset in manifest.assets) {
      final entry = entries[asset.path];
      if (entry == null || !entry.isFile) {
        throw const DataTransferException(
          'invalid_archive',
          'A manifest asset is missing from the ZIP.',
        );
      }
      final payload = entry.readBytes();
      if (payload == null || payload.length != asset.size) {
        throw const DataTransferException(
          'corrupt_archive',
          'An asset size does not match its manifest.',
        );
      }
      totalBytes += payload.length;
      if (totalBytes > DataTransferLimits.maxTotalUncompressedBytes) {
        throw const DataTransferException(
          'archive_too_large',
          'The ZIP expands beyond the supported size.',
        );
      }
      if (sha256.convert(payload).toString() != asset.sha256) {
        throw const DataTransferException(
          'corrupt_archive',
          'An asset checksum does not match its manifest.',
        );
      }
      assetBytes[asset.id] = Uint8List.fromList(payload);
    }

    for (final entry in entries.values) {
      if (entry.isDirectory || entry.name == 'manifest.json') continue;
      if (!assetByPath.containsKey(entry.name)) {
        throw const DataTransferException(
          'invalid_archive',
          'The ZIP contains an unexpected regular file.',
        );
      }
    }

    final database = await db.database;
    final existingRows = await database.query(
      'actresses',
      columns: const ['id', 'name', 'img_path'],
    );
    final workCountRows = await database.rawQuery(
      'SELECT actress_id, COUNT(*) AS count FROM actress_works GROUP BY actress_id',
    );
    final workCounts = <int, int>{};
    for (final row in workCountRows) {
      final id = _asInt(row['actress_id']);
      if (id != null) workCounts[id] = _asInt(row['count']) ?? 0;
    }
    final importedWorkCounts = <String, int>{};
    for (final relation in manifest.relations) {
      importedWorkCounts[relation.actressId] =
          (importedWorkCounts[relation.actressId] ?? 0) + 1;
    }

    final existingByName = <String, Map<String, Object?>>{};
    for (final row in existingRows) {
      final name = row['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        existingByName[_nameKey(name)] = row;
      }
    }
    final duplicates = <DataTransferDuplicateCandidate>[];
    for (final actress in manifest.actresses) {
      final existing = existingByName[_nameKey(actress.name)];
      if (existing == null) continue;
      final existingId = _asInt(existing['id']);
      if (existingId == null) continue;
      duplicates.add(
        DataTransferDuplicateCandidate(
          imported: actress,
          existingActressId: existingId,
          existingName: existing['name']?.toString() ?? actress.name,
          existingImagePath: existing['img_path']?.toString(),
          existingWorkCount: workCounts[existingId] ?? 0,
          importedWorkCount: importedWorkCounts[actress.id] ?? 0,
          importedAvatarBytes: actress.avatarAssetId == null
              ? null
              : assetBytes[actress.avatarAssetId!],
        ),
      );
    }

    return _PreparedImport(
      manifest: manifest,
      assetBytes: assetBytes,
      duplicates: List.unmodifiable(duplicates),
    );
  }

  Future<void> _commitImport(
    DatabaseExecutor transaction,
    _PreparedImport prepared,
    Map<String, String> localAssetPaths,
    Map<String, DataTransferDuplicateResolution> resolutions,
  ) async {
    final existingRows = await transaction.query(
      'actresses',
      columns: const [
        'id',
        'name',
        'img_path',
        'birth_date',
        'main_type',
        'tags',
        'memo',
        'height',
        'weight',
        'bwh',
        'cup',
      ],
    );
    final existingByName = <String, Map<String, Object?>>{};
    for (final row in existingRows) {
      final name = row['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        existingByName[_nameKey(name)] = row;
      }
    }

    final actressIds = <String, int>{};
    for (final actress in prepared.manifest.actresses) {
      final existing = existingByName[_nameKey(actress.name)];
      final resolution = resolutions[actress.id];
      final importedImage = _assetPath(localAssetPaths, actress.avatarAssetId);
      if (existing == null) {
        final id = await transaction.insert('actresses', {
          'name': actress.name.trim(),
          'img_path': importedImage,
          'birth_date': actress.birthDate,
          'main_type': actress.mainType ?? '',
          'tags': actress.tags ?? '',
          'memo': actress.memo ?? '',
          'height': actress.height ?? '',
          'weight': actress.weight ?? '',
          'bwh': actress.bwh ?? '',
          'cup': actress.cup ?? '',
          'modified_at': DateTime.now().toUtc().toIso8601String(),
        });
        actressIds[actress.id] = id;
        await _mergeAliases(transaction, id, actress.aliases, actress.name);
        continue;
      }

      final existingId = _asInt(existing['id']);
      if (existingId == null) {
        throw const DataTransferException(
          'invalid_data',
          'An existing actress row has no numeric id.',
        );
      }
      actressIds[actress.id] = existingId;
      final useImported =
          resolution == DataTransferDuplicateResolution.useImported;
      var finalName = existing['name']?.toString() ?? actress.name;
      var finalImage = existing['img_path']?.toString();
      if (useImported) {
        finalName = actress.name.trim();
        finalImage = importedImage ?? finalImage;
        finalName = await _ensureUniqueImportedName(
          transaction,
          finalName,
          existingId,
        );
        await transaction.update(
          'actresses',
          {
            'name': finalName,
            'img_path': finalImage,
            'birth_date': actress.birthDate,
            'main_type': actress.mainType ?? '',
            'tags': actress.tags ?? '',
            'memo': actress.memo ?? '',
            'height': actress.height ?? '',
            'weight': actress.weight ?? '',
            'bwh': actress.bwh ?? '',
            'cup': actress.cup ?? '',
            'modified_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );
      }
      if (importedImage != null &&
          useImported &&
          existing['img_path']?.toString().trim().isNotEmpty == true &&
          existing['img_path']?.toString() != importedImage) {
        await _queueOldImage(transaction, existing['img_path']?.toString());
      }
      await _mergeAliases(transaction, existingId, actress.aliases, finalName);
    }

    final workIds = <String, int>{};
    for (final work in prepared.manifest.works) {
      final code = work.code.trim().toUpperCase();
      final title = work.title.trim();
      if (code.isEmpty || title.isEmpty) {
        throw const DataTransferException(
          'invalid_data',
          'A work code and title are required.',
        );
      }
      final existing = await transaction.query(
        'works',
        columns: const [
          'id',
          'title',
          'release_date',
          'duration_minutes',
          'studio',
          'publisher',
          'series',
          'card_image_path',
          'detail_image_path',
        ],
        where: 'code = ? COLLATE NOCASE',
        whereArgs: [code],
        limit: 1,
      );
      final cardImage = _assetPath(localAssetPaths, work.cardImageAssetId);
      final detailImage = _assetPath(localAssetPaths, work.detailImageAssetId);
      if (existing.isEmpty) {
        final id = await transaction.insert('works', {
          'code': code,
          'title': title,
          'release_date': work.releaseDate,
          'duration_minutes': work.durationMinutes,
          'studio': work.studio,
          'publisher': work.publisher,
          'series': work.series,
          'card_image_path': cardImage,
          'detail_image_path': detailImage,
          'is_stored': work.isStored ? 1 : 0,
          'storage_quality': work.storageQuality,
          'storage_frame_rate': work.storageFrameRate,
          if (work.createdAt != null) 'created_at': work.createdAt,
          if (work.modifiedAt != null) 'modified_at': work.modifiedAt,
        });
        workIds[work.id] = id;
        await _importProvenance(
          transaction,
          workId: id,
          work: work,
          existing: null,
        );
        continue;
      }

      final row = existing.single;
      final id = _asInt(row['id']);
      if (id == null) {
        throw const DataTransferException(
          'invalid_data',
          'An existing work row has no numeric id.',
        );
      }
      workIds[work.id] = id;
      final oldCard = row['card_image_path']?.toString();
      final oldDetail = row['detail_image_path']?.toString();
      await transaction.rawUpdate(
        '''
        UPDATE works
        SET title = ?,
            release_date = COALESCE(?, release_date),
            duration_minutes = COALESCE(?, duration_minutes),
            studio = COALESCE(?, studio),
            publisher = COALESCE(?, publisher),
            series = COALESCE(?, series),
            card_image_path = COALESCE(?, card_image_path),
            detail_image_path = COALESCE(?, detail_image_path),
            is_stored = CASE WHEN is_stored = 1 OR ? = 1 THEN 1 ELSE 0 END,
            storage_quality = CASE
              WHEN is_stored = 0 AND ? = 1 THEN COALESCE(?, storage_quality)
              ELSE storage_quality
            END,
            storage_frame_rate = CASE
              WHEN is_stored = 0 AND ? = 1 THEN COALESCE(?, storage_frame_rate)
              ELSE storage_frame_rate
            END,
            modified_at = CURRENT_TIMESTAMP
        WHERE id = ?
        ''',
        [
          title,
          work.releaseDate,
          work.durationMinutes,
          work.studio,
          work.publisher,
          work.series,
          cardImage,
          detailImage,
          work.isStored ? 1 : 0,
          work.isStored ? 1 : 0,
          work.storageQuality,
          work.isStored ? 1 : 0,
          work.storageFrameRate,
          id,
        ],
      );
      if (cardImage != null && oldCard != null && oldCard != cardImage) {
        await _queueOldImage(transaction, oldCard);
      }
      if (detailImage != null &&
          oldDetail != null &&
          oldDetail != detailImage) {
        await _queueOldImage(transaction, oldDetail);
      }
      await _importProvenance(
        transaction,
        workId: id,
        work: work,
        existing: row,
      );
    }

    for (final relation in prepared.manifest.relations) {
      final actressId = actressIds[relation.actressId];
      final workId = workIds[relation.workId];
      if (actressId == null || workId == null) {
        throw const DataTransferException(
          'invalid_data',
          'A relation points to a missing imported record.',
        );
      }
      await transaction.insert('actress_works', {
        'actress_id': actressId,
        'work_id': workId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _importProvenance(
    DatabaseExecutor transaction, {
    required int workId,
    required DataTransferWork work,
    required Map<String, Object?>? existing,
  }) async {
    final incoming = <String, Object?>{
      'title': work.title,
      'release_date': work.releaseDate,
      'duration_minutes': work.durationMinutes,
      'studio': work.studio,
      'publisher': work.publisher,
      'series': work.series,
    };
    for (final item in work.provenance) {
      final incomingValue = incoming[item.field];
      if (incomingValue == null || incomingValue.toString().trim().isEmpty) {
        continue;
      }
      final existingValue = existing?[item.field];
      final wins =
          item.field == 'title' ||
          existing == null ||
          existingValue == null ||
          existingValue.toString().trim().isEmpty;
      if (!wins) continue;
      await transaction.insert('work_field_provenance', {
        'work_id': workId,
        'field': item.field,
        'source': item.source,
        'source_uri': item.sourceUri,
        'observed_at': item.observedAt,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _cleanupUnreferencedImportAssets(
    Directory directory,
    Map<String, String> stagedPaths,
  ) async {
    if (stagedPaths.isEmpty) return;
    final database = await db.database;
    final rows = await database.rawQuery('''
      SELECT img_path AS image_path FROM actresses WHERE img_path IS NOT NULL
      UNION ALL
      SELECT card_image_path AS image_path FROM works
      WHERE card_image_path IS NOT NULL
      UNION ALL
      SELECT detail_image_path AS image_path FROM works
      WHERE detail_image_path IS NOT NULL
    ''');
    final referenced = <String>{};
    for (final row in rows) {
      final storedPath = row['image_path']?.toString();
      if (storedPath == null || storedPath.trim().isEmpty) continue;
      final file = await db.resolveManagedImageForTransfer(storedPath);
      if (file != null) referenced.add(_imageKey(file.path));
    }

    for (final stagedPath in stagedPaths.values) {
      if (referenced.contains(_imageKey(stagedPath))) continue;
      final file = File(stagedPath);
      if (await file.exists()) await file.delete();
    }
    if (await directory.exists() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }

  Future<String> _ensureUniqueImportedName(
    DatabaseExecutor transaction,
    String name,
    int currentId,
  ) async {
    final rows = await transaction.query(
      'actresses',
      columns: const ['id'],
      where: 'name = ? COLLATE NOCASE AND id != ?',
      whereArgs: [name, currentId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const DataTransferException(
        'actor_name_conflict',
        'Imported actress details conflict with another actress.',
      );
    }
    return name;
  }

  Future<void> _mergeAliases(
    DatabaseExecutor transaction,
    int actressId,
    Iterable<String> imported,
    String canonicalName,
  ) async {
    final existingRows = await transaction.query(
      'actress_aliases',
      columns: const ['alias'],
      where: 'actress_id = ?',
      whereArgs: [actressId],
    );
    final aliases = <String>{};
    for (final row in existingRows) {
      final alias = row['alias']?.toString().trim();
      if (alias != null && alias.isNotEmpty) aliases.add(alias);
    }
    aliases.addAll(imported.map((value) => value.trim()));
    final canonicalKey = canonicalName.trim().toLowerCase();
    for (final alias in aliases) {
      if (alias.isEmpty || alias.toLowerCase() == canonicalKey) continue;
      await transaction.insert('actress_aliases', {
        'actress_id': actressId,
        'alias': alias,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await transaction.rawDelete(
      'DELETE FROM actress_aliases WHERE actress_id = ? AND alias = ? COLLATE NOCASE',
      [actressId, canonicalName.trim()],
    );
  }

  Future<void> _queueOldImage(
    DatabaseExecutor transaction,
    String? oldPath,
  ) async {
    final value = oldPath?.trim();
    if (value == null || value.isEmpty) return;
    await transaction.insert('pending_file_deletions', {
      'path': value,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}

class _PreparedImport {
  const _PreparedImport({
    required this.manifest,
    required this.assetBytes,
    required this.duplicates,
  });

  final DataTransferManifest manifest;
  final Map<String, Uint8List> assetBytes;
  final List<DataTransferDuplicateCandidate> duplicates;
}

class _ExportActressDraft {
  const _ExportActressDraft({
    required this.sourceId,
    required this.name,
    required this.avatarSourceKey,
    required this.birthDate,
    required this.mainType,
    required this.tags,
    required this.memo,
    required this.height,
    required this.weight,
    required this.bwh,
    required this.cup,
    required this.aliases,
  });

  final int sourceId;
  final String name;
  final String? avatarSourceKey;
  final String? birthDate;
  final String? mainType;
  final String? tags;
  final String? memo;
  final String? height;
  final String? weight;
  final String? bwh;
  final String? cup;
  final List<String> aliases;
}

class _ExportWorkDraft {
  const _ExportWorkDraft({
    required this.sourceId,
    required this.code,
    required this.title,
    required this.releaseDate,
    required this.durationMinutes,
    required this.studio,
    required this.publisher,
    required this.series,
    required this.cardSourceKey,
    required this.detailSourceKey,
    required this.isStored,
    required this.storageQuality,
    required this.storageFrameRate,
    required this.createdAt,
    required this.modifiedAt,
    required this.provenance,
  });

  final int sourceId;
  final String code;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final String? cardSourceKey;
  final String? detailSourceKey;
  final bool isStored;
  final String? storageQuality;
  final int? storageFrameRate;
  final String? createdAt;
  final String? modifiedAt;
  final List<DataTransferProvenance> provenance;
}

class _ExportImage {
  _ExportImage({
    required this.sourceKey,
    required this.file,
    required this.size,
    required this.extension,
    required this.sha256,
    this.preferredFileName,
  });

  final String sourceKey;
  final File file;
  final int size;
  final String extension;
  final String sha256;
  String? preferredFileName;
  String? archivePath;
}

class _DataTransferDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest!;

  @override
  void add(Digest value) {
    _digest = value;
  }

  @override
  void close() {}
}

String _validateArchivePath(String value) {
  if (value.isEmpty ||
      value.contains('\\') ||
      value.contains('\u0000') ||
      value.startsWith('/') ||
      value.startsWith('//') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    throw const DataTransferException(
      'unsafe_archive',
      'The ZIP contains an unsafe path.',
    );
  }
  final segments = value.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw const DataTransferException(
      'unsafe_archive',
      'The ZIP contains a traversal path.',
    );
  }
  return value;
}

String _supportedExtension(String value) {
  final extension = path.extension(value).toLowerCase();
  const supported = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
  if (!supported.contains(extension)) {
    throw const DataTransferException(
      'unsupported_image',
      'The archive contains an unsupported image type.',
    );
  }
  return extension;
}

String? _assetPath(Map<String, String> paths, String? assetId) {
  if (assetId == null) return null;
  return paths[assetId];
}

String _imageKey(String value) {
  var normalized = path.normalize(value);
  if (Platform.isAndroid) {
    // Android can expose the same app-private directory as either
    // /data/user/0/<package> or /data/data/<package>. The database image
    // validator canonicalizes to the latter, while staged files retain the
    // former spelling. Normalize both before deciding whether an imported
    // file is still referenced.
    const userDataPrefix = '/data/user/0/';
    final slashPath = normalized.replaceAll('\\', '/');
    if (slashPath.startsWith(userDataPrefix)) {
      normalized = path.normalize(
        '/data/data/${slashPath.substring(userDataPrefix.length)}',
      );
    }
  }
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

String _nameKey(String value) => value.trim().toLowerCase();

int? _asInt(Object? value) => value is num ? value.toInt() : null;

String? _asNullableString(Object? value) => value?.toString();
