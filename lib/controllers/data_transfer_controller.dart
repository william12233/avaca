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

abstract interface class DataTransferFilePicker {
  Future<String?> saveExportFile({
    required File file,
    required String fileName,
  });
}

class PlatformDataTransferPicker
    implements DataTransferPicker, DataTransferFilePicker {
  const PlatformDataTransferPicker();

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
      return _bounded(Uint8List.fromList(bytes));
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

  @override
  Future<String?> saveExportFile({
    required File file,
    required String fileName,
  }) async {
    final destination = await FilePicker.saveFile(
      dialogTitle: 'Export AVACA data',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (destination == null || destination.isEmpty) return null;
    await file.copy(destination);
    return destination;
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
    DataTransferFileExport? fileExport;
    try {
      final fileName = _suggestedFileName();
      String? savedPath;
      DataTransferSummary? summary;
      if (_picker is DataTransferFilePicker) {
        savedPath = await _saveFileBackedExport(
          _picker as DataTransferFilePicker,
          fileName,
          (value) => fileExport = value,
        );
        summary = fileExport?.summary;
      } else {
        final export = await _service.buildExport(onProgress: _setProgress);
        savedPath = await _picker.saveExport(
          bytes: export.bytes,
          fileName: fileName,
        );
        summary = export.summary;
      }
      if (savedPath == null) {
        return _finish(const DataTransferOperationResult(cancelled: true));
      }
      final exportSummary = summary!;
      return _finish(
        DataTransferOperationResult(
          cancelled: false,
          summary: DataTransferSummary(
            actresses: exportSummary.actresses,
            works: exportSummary.works,
            images: exportSummary.images,
            skippedImages: exportSummary.skippedImages,
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
    } finally {
      final file = fileExport?.file;
      if (file != null && await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<String?> _saveFileBackedExport(
    DataTransferFilePicker picker,
    String fileName,
    void Function(DataTransferFileExport value) onBuilt,
  ) async {
    final export = await _service.buildExportFile(onProgress: _setProgress);
    onBuilt(export);
    return picker.saveExportFile(file: export.file, fileName: fileName);
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
