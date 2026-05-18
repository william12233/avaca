import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:avaca/l10n/app_localizations.dart';
import '../components/app_snackbar.dart';
import '../components/image_cropper.dart';
import '../core/database.dart';

class AddController extends ChangeNotifier {
  AddController({
    required this.db,
  }) {
    tempImgPath = path.join(
      db.imgDir,
      'temp_crop.jpg',
    );
  }

  final AppDatabase db;
  String? selectedImagePath;
  late final String tempImgPath;

  Map<String, Object> _imageState = _buildImageState(
    previewSrc: '',
    hasImage: false,
  );

  Map<String, Object> get imageState => Map.unmodifiable(_imageState);

  // 保留外部呼叫入口，目前 Flutter 版本不需要保存裁切器實例。
  void setCropper(Object? cropper) {}

  // 保留外部呼叫入口，目前尺寸由 Flutter 版面系統自行處理。
  void windowResized(Object? event) {}

  // 選擇圖片，成功後開啟裁切流程。
  Future<void> pickImage(BuildContext context) async {
    final result = await file_picker.FilePicker.pickFiles(
      allowMultiple: false,
      type: file_picker.FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );

    if (!context.mounted) {
      return;
    }

    if (result == null || result.files.isEmpty) {
      return;
    }

    final pickedPath = result.files.first.path;

    if (pickedPath == null || pickedPath.isEmpty) {
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context).imageReadFailedUnsupportedFormat,
      );
      return;
    }

    final success = await ImageCropper.open(
      context: context,
      sourceImagePath: pickedPath,
      outputImagePath: tempImgPath,
      onCropDone: onCropSuccess,
    );

    if (!context.mounted) {
      return;
    }

    if (!success) {
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context).imageReadFailedUnsupportedFormat,
      );
    }
  }

  // 裁切成功後，更新目前圖片路徑與預覽狀態。
  Map<String, Object> onCropSuccess(String croppedPath) {
    selectedImagePath = croppedPath;

    final previewSrc = _buildBase64ImageSrc(croppedPath);

    _imageState = _buildImageState(
      previewSrc: previewSrc,
      hasImage: true,
    );

    notifyListeners();

    return imageState;
  }

  // 移除目前選擇的圖片與暫存檔案。
  Map<String, Object> removeImage() {
    selectedImagePath = null;
    _removeTempImage();

    _imageState = _buildImageState(
      previewSrc: '',
      hasImage: false,
    );

    notifyListeners();

    return imageState;
  }

  // 儲存新增資料，成功後回到首頁。
  Future<void> saveActress(
    BuildContext context,
    String nameValue,
  ) async {
    final name = _normalizeName(nameValue);

    if (name.isEmpty) {
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context).enterName,
      );
      return;
    }

    final finalImgPath = _buildFinalImagePath(name);

    final success = await db.addActress(
      name: name,
      imgPath: finalImgPath,
    );

    if (!context.mounted) {
      return;
    }

    if (success) {
      _moveSelectedImageToFinalPath(finalImgPath);

      AppSnackBar.showSuccess(
        context,
        AppLocalizations.of(context).collectionAdded,
      );

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/',
        (route) => false,
      );
      return;
    }

    AppSnackBar.showError(
      context,
      AppLocalizations.of(context).alreadyInCollection,
    );
  }

  // 清除暫存圖片後返回首頁。
  Future<void> goBack(BuildContext context) async {
    _removeTempImage();

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }

  String _normalizeName(String nameValue) {
    if (nameValue.isEmpty) {
      return '';
    }

    return nameValue.trim();
  }

  String _buildSafeName(String name) {
    const invalidChars = '<>:"/\\?*';

    return name
        .split('')
        .where((char) => !invalidChars.contains(char))
        .join();
  }

  String? _buildFinalImagePath(String name) {
    if (selectedImagePath == null) {
      return null;
    }

    final safeName = _buildSafeName(name);

    return path.join(
      db.imgDir,
      '$safeName.jpg',
    );
  }

  void _moveSelectedImageToFinalPath(String? finalImgPath) {
    final currentSelectedPath = selectedImagePath;

    if (currentSelectedPath == null || finalImgPath == null) {
      return;
    }

    final selectedFile = File(currentSelectedPath);
    final finalFile = File(finalImgPath);

    if (!selectedFile.existsSync()) {
      return;
    }

    if (finalFile.existsSync()) {
      finalFile.deleteSync();
    }

    finalFile.parent.createSync(recursive: true);

    try {
      selectedFile.renameSync(finalImgPath);
    } on FileSystemException {
      selectedFile.copySync(finalImgPath);
      selectedFile.deleteSync();
    }

    selectedImagePath = finalImgPath;
  }

  void _removeTempImage() {
    final tempFile = File(tempImgPath);

    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
  }

  String _buildBase64ImageSrc(String imagePath) {
    final imageBytes = File(imagePath).readAsBytesSync();
    final encodedImg = base64Encode(imageBytes);

    return 'data:image/jpeg;base64,$encodedImg';
  }

  static Map<String, Object> _buildImageState({
    required String previewSrc,
    required bool hasImage,
  }) {
    return {
      'preview_src': previewSrc,
      'preview_visible': hasImage,
      'placeholder_visible': !hasImage,
      'delete_button_visible': hasImage,
    };
  }
}