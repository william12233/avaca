import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/data_transfer_manifest.dart';
import '../models/data_transfer_models.dart';
import '../services/data_transfer_service.dart';

abstract interface class DataTransferPicker {
  Future<Uint8List?> pickImport();

  Future<String?> saveExport({
    required Uint8List bytes,
    required String fileName,
  });
}

abstract interface class DataTransferExportPathPicker {
  bool get supportsFilePaths;

  Future<String?> chooseExportPath({required String fileName});
}

abstract interface class DataTransferImportPathPicker {
  bool get supportsFilePaths;

  Future<String?> chooseImportPath();
}

class PlatformDataTransferPicker
    implements
        DataTransferPicker,
        DataTransferExportPathPicker,
        DataTransferImportPathPicker {
  const PlatformDataTransferPicker();

  @override
  bool get supportsFilePaths => !Platform.isAndroid && !Platform.isIOS;

  @override
  Future<String?> chooseImportPath() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
      withReadStream: false,
    );
    return result?.files.single.path;
  }

  @override
  Future<String?> chooseExportPath({required String fileName}) {
    return FilePicker.saveFile(
      dialogTitle: 'Export AVACA data',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
  }

  @override
  Future<Uint8List?> pickImport() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      // Android's file_picker implementation already caches the selected
      // document to a private file path. Requesting `withData` as well loads
      // the entire ZIP into native memory before Dart reads it again, which
      // can kill the app as soon as a real library archive is selected.
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final filePath = file.path;
    if (filePath != null && filePath.isNotEmpty) {
      final bytes = await File(filePath).readAsBytes();
      return _bounded(bytes);
    }
    if (file.bytes != null) return _bounded(file.bytes!);
    final stream = file.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in stream) {
        length += chunk.length;
        if (length > DataTransferLimits.maxArchiveBytes) {
          throw const DataTransferException(
            'archive_too_large',
            'The selected ZIP exceeds the supported size.',
          );
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
    throw const DataTransferException(
      'file_unreadable',
      'The selected file could not be read.',
    );
  }

  @override
  Future<String?> saveExport({
    required Uint8List bytes,
    required String fileName,
  }) {
    return FilePicker.saveFile(
      dialogTitle: 'Export AVACA data',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: bytes,
    );
  }

  Uint8List _bounded(Uint8List bytes) {
    if (bytes.length > DataTransferLimits.maxArchiveBytes) {
      throw const DataTransferException(
        'archive_too_large',
        'The selected ZIP exceeds the supported size.',
      );
    }
    return bytes;
  }
}

class DataTransferController extends ChangeNotifier {
  DataTransferController({
    required DataTransferService service,
    DataTransferPicker? picker,
  }) : _service = service,
       _picker = picker ?? const PlatformDataTransferPicker();

  final DataTransferService _service;
  final DataTransferPicker _picker;

  DataTransferPhase phase = DataTransferPhase.idle;
  DataTransferProgress? progress;
  bool _busy = false;

  bool get isBusy => _busy;

  Future<DataTransferOperationResult> exportData() async {
    if (_busy) return _busyResult();
    _busy = true;
    _setProgress(
      const DataTransferProgress(phase: DataTransferPhase.preparing),
    );
    try {
      final fileName = _suggestedFileName();
      final pathPicker = _picker is DataTransferExportPathPicker
          ? _picker as DataTransferExportPathPicker
          : null;
      if (pathPicker?.supportsFilePaths == true) {
        final savedPath = await pathPicker!.chooseExportPath(
          fileName: fileName,
        );
        if (savedPath == null) {
          return _finish(const DataTransferOperationResult(cancelled: true));
        }
        final export = await _service.buildExport(
          onProgress: _setProgress,
          outputPath: savedPath,
        );
        return _finish(
          DataTransferOperationResult(
            cancelled: false,
            summary: DataTransferSummary(
              actresses: export.summary.actresses,
              works: export.summary.works,
              images: export.summary.images,
              skippedImages: export.summary.skippedImages,
              destinationPath: savedPath,
            ),
          ),
        );
      }
      final export = await _service.buildExport(onProgress: _setProgress);
      final savedPath = await _picker.saveExport(
        bytes: export.bytes,
        fileName: fileName,
      );
      if (savedPath == null) {
        return _finish(const DataTransferOperationResult(cancelled: true));
      }
      return _finish(
        DataTransferOperationResult(
          cancelled: false,
          summary: DataTransferSummary(
            actresses: export.summary.actresses,
            works: export.summary.works,
            images: export.summary.images,
            skippedImages: export.summary.skippedImages,
            destinationPath: savedPath,
          ),
        ),
      );
    } on DataTransferException catch (error) {
      return _finish(
        DataTransferOperationResult(cancelled: false, error: error),
      );
    } on Object catch (error) {
      return _finish(
        DataTransferOperationResult(
          cancelled: false,
          error: DataTransferException('export_failed', error.toString()),
        ),
      );
    }
  }

  Future<DataTransferOperationResult> importData({
    required DataTransferDuplicateResolver? resolveDuplicate,
  }) async {
    if (_busy) return _busyResult();
    _busy = true;
    _setProgress(
      const DataTransferProgress(phase: DataTransferPhase.preparing),
    );
    try {
      final pathPicker = _picker is DataTransferImportPathPicker
          ? _picker as DataTransferImportPathPicker
          : null;
      if (pathPicker?.supportsFilePaths == true) {
        final selectedPath = await pathPicker!.chooseImportPath();
        if (selectedPath == null) {
          return _finish(const DataTransferOperationResult(cancelled: true));
        }
        final result = await _service.importArchiveFile(
          file: File(selectedPath),
          resolveDuplicate: resolveDuplicate,
          onProgress: _setProgress,
        );
        return _finish(result);
      }
      final bytes = await _picker.pickImport();
      if (bytes == null) {
        return _finish(const DataTransferOperationResult(cancelled: true));
      }
      final result = await _service.importArchive(
        bytes: bytes,
        resolveDuplicate: resolveDuplicate,
        onProgress: _setProgress,
      );
      return _finish(result);
    } on DataTransferException catch (error) {
      return _finish(
        DataTransferOperationResult(cancelled: false, error: error),
      );
    } on Object catch (error) {
      return _finish(
        DataTransferOperationResult(
          cancelled: false,
          error: DataTransferException('import_failed', error.toString()),
        ),
      );
    }
  }

  void _setProgress(DataTransferProgress value) {
    phase = value.phase;
    progress = value;
    notifyListeners();
  }

  DataTransferOperationResult _finish(DataTransferOperationResult result) {
    phase = result.error == null
        ? (result.cancelled
              ? DataTransferPhase.idle
              : DataTransferPhase.success)
        : DataTransferPhase.error;
    progress = null;
    _busy = false;
    notifyListeners();
    return result;
  }

  DataTransferOperationResult _busyResult() {
    return const DataTransferOperationResult(
      cancelled: false,
      error: DataTransferException(
        'busy',
        'Another data transfer is already in progress.',
      ),
    );
  }

  String _suggestedFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'avaca-export-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }
}
