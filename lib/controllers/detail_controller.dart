import 'dart:io';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:avaca/l10n/app_localizations.dart';
import '../components/app_snackbar.dart';
import '../components/image_cropper.dart';
import '../core/database.dart';

class DetailController extends ChangeNotifier {
  DetailController({
    required this.db,
    required this.actressId,
  });

  final AppDatabase db;
  final int actressId;

  bool isEditing = false;
  Map<String, Object?> actressData = _buildFallbackActressData();
  List<String> currentAttrs = [];

  // 初始化頁面資料，並同步目前的分類屬性。
  Future<void> init() async {
    actressData = await _loadActressData();
    currentAttrs = _parseAttrs(
      actressData['main_type']?.toString() ?? '',
    );
    notifyListeners();
  }

  // 保留舊流程需要的入口，目前 Flutter 版本不需要保存 cropper 實例。
  void setCropper(Object? cropper) {
    // Flutter 版本不需要保存 cropper 實例。
  }

  // Flutter 版面尺寸由 widget tree 自行重建處理。
  void windowResized(Object? event) {
    // Flutter cropper 會在畫面重建時重新計算尺寸。
  }

  Map<String, Object?> getActressData() {
    return Map.unmodifiable(actressData);
  }

  List<String> getCurrentAttrs() {
    return List.unmodifiable(currentAttrs);
  }

  List<String> getAttrOptions(BuildContext context) {
    return [
      AppLocalizations.of(context).attrCensored,
      AppLocalizations.of(context).attrUncensored,
      AppLocalizations.of(context).attrWestern,
      AppLocalizations.of(context).attrFc2,
      AppLocalizations.of(context).attrDomestic,
    ];
  }

  // 開啟刪除確認視窗的狀態資料。
  Map<String, bool> openDeleteDialog() {
    return {
      'open': true,
    };
  }

  // 關閉刪除確認視窗的狀態資料。
  Map<String, bool> closeDeleteDialog() {
    return {
      'open': false,
    };
  }

  // 刪除照片檔案與資料庫資料，成功後回到首頁。
  Future<void> executeDelete(BuildContext context) async {
    _deleteImageFile();

    final success = await db.deleteActress(actressId);

    if (!context.mounted) {
      return;
    }

    if (success) {
      AppSnackBar.showSuccess(
        context,
        AppLocalizations.of(context).dataDeleted,
      );

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/',
        (route) => false,
      );
      return;
    }

    AppSnackBar.showError(
      context,
      AppLocalizations.of(context).deleteFailed,
    );
  }

  // 選擇新照片後交給裁切流程處理。
  Future<void> changePhoto(BuildContext context) async {
    final result = await file_picker.FilePicker.pickFiles(
      allowMultiple: false,
      type: file_picker.FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
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

    await processPickedImage(
      context: context,
      pickedPath: pickedPath,
    );
  }

  // 建立暫存輸出路徑，並開啟圖片裁切流程。
  Future<void> processPickedImage({
    required BuildContext context,
    required String pickedPath,
  }) async {
    final tempFileName =
        'actress_${actressId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final tempPath = path.join(
      db.imgDir,
      tempFileName,
    );

    final success = await ImageCropper.open(
      context: context,
      sourceImagePath: pickedPath,
      outputImagePath: tempPath,
      onCropDone: onCropDone,
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

  // 裁切完成後更新目前照片路徑。
  Map<String, Object> onCropDone(String newImgPath) {
    actressData['img_path'] = newImgPath;
    notifyListeners();

    return _buildImageState(newImgPath);
  }

  // 裁切完成後更新照片狀態，並提示使用者仍需儲存。
  Map<String, Object> notifyCropDone(
    BuildContext context,
    String newImgPath,
  ) {
    final state = onCropDone(newImgPath);

    AppSnackBar.showSuccess(
      context,
      AppLocalizations.of(context).photoCroppedRememberSave,
    );

    return state;
  }

  // 移除目前照片路徑。
  Map<String, Object> deletePhoto() {
    actressData['img_path'] = '';
    notifyListeners();

    return _buildImageState('');
  }

  // 切換編輯狀態；離開編輯狀態時同步表單並寫入資料庫。
  Future<Map<String, Object?>> toggleEditMode(
    BuildContext context,
    Map<String, Object?> formData,
  ) async {
    isEditing = !isEditing;

    if (!isEditing) {
      final selectedAttrs = formData['selected_attrs'];

      if (selectedAttrs is List) {
        currentAttrs = selectedAttrs.map((value) => value.toString()).toList();
      } else {
        currentAttrs = [];
      }

      _syncActressData(formData);
      await saveToDb(context, formData);
    }

    notifyListeners();

    return {
      'is_editing': isEditing,
      'name': formData['name']?.toString() ?? '',
      'current_attrs': currentAttrs,
    };
  }

  // 將表單資料寫入資料庫，並依結果顯示提示訊息。
  Future<bool> saveToDb(
    BuildContext context,
    Map<String, Object?> formData,
  ) async {
    final success = await db.updateActress(
      actressId: actressId,
      name: formData['name']?.toString() ?? '',
      imgPath: actressData['img_path']?.toString() ?? '',
      mainType: formData['main_type']?.toString() ?? '',
      memo: formData['memo']?.toString() ?? '',
      height: formData['height']?.toString() ?? '',
      weight: formData['weight']?.toString() ?? '',
      bwh: formData['bwh']?.toString() ?? '',
      cup: formData['cup']?.toString() ?? '',
    );

    if (!context.mounted) {
      return success;
    }

    if (success) {
      AppSnackBar.showSuccess(
        context,
        AppLocalizations.of(context).detailSaved,
      );
      return true;
    }

    AppSnackBar.showError(
      context,
      AppLocalizations.of(context).saveFailedDuplicateName,
    );
    return false;
  }

  // 從資料庫讀取詳細資料，找不到資料時使用預設資料。
  Future<Map<String, Object?>> _loadActressData() async {
    final dbData = await db.getActressById(actressId);

    if (dbData != null) {
      return Map<String, Object?>.from(dbData);
    }

    return _buildFallbackActressData();
  }

  // 將逗號分隔的分類文字轉成清單。
  List<String> _parseAttrs(String mainType) {
    return mainType
        .split(',')
        .map((attr) => attr.trim())
        .where((attr) => attr.isNotEmpty)
        .toList();
  }

  // 嘗試刪除目前照片檔案；刪除失敗時只輸出除錯訊息。
  void _deleteImageFile() {
    final imgPath = actressData['img_path']?.toString();

    if (imgPath == null || imgPath.isEmpty) {
      return;
    }

    final imageFile = File(imgPath);

    if (!imageFile.existsSync()) {
      return;
    }

    try {
      imageFile.deleteSync();
    } catch (error) {
      debugPrint('照片刪除失敗: $error');
    }
  }

  // 產生圖片狀態資料。
  Map<String, Object> _buildImageState(String imgPath) {
    return {
      'img_path': imgPath,
      'has_image': imgPath.isNotEmpty,
    };
  }

  // 將表單資料同步回本地狀態。
  void _syncActressData(Map<String, Object?> formData) {
    actressData['name'] = formData['name']?.toString() ?? '';
    actressData['img_path'] = formData['img_path']?.toString() ?? '';
    actressData['main_type'] = formData['main_type']?.toString() ?? '';
    actressData['memo'] = formData['memo']?.toString() ?? '';
    actressData['height'] = formData['height']?.toString() ?? '';
    actressData['weight'] = formData['weight']?.toString() ?? '';
    actressData['bwh'] = formData['bwh']?.toString() ?? '';
    actressData['cup'] = formData['cup']?.toString() ?? '';
  }

  // 建立找不到資料時使用的預設詳細資料。
  static Map<String, Object?> _buildFallbackActressData() {
    return {
      'name': '',
      'img_path': null,
      'main_type': '',
      'memo': '',
      'height': '',
      'weight': '',
      'bwh': '',
      'cup': '',
    };
  }
}