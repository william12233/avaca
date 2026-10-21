import 'dart:io';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:avaca/l10n/app_localizations.dart';
import '../components/app_snackbar.dart';
import '../components/image_cropper.dart';
import '../core/database.dart';

final class DetailActressData {
  DetailActressData({
    required this.name,
    required this.imgPath,
    required this.mainType,
    required this.memo,
    required this.height,
    required this.weight,
    required this.bwh,
    required this.cup,
    required this.birthDate,
    List<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases);

  const DetailActressData.empty()
    : name = '',
      imgPath = '',
      mainType = '',
      memo = '',
      height = '',
      weight = '',
      bwh = '',
      cup = '',
      birthDate = null,
      aliases = const [];

  factory DetailActressData.fromRow(Map<String, Object?> row) {
    String text(String key) => row[key]?.toString() ?? '';
    final rawAliases = row['aliases'];
    final aliases = rawAliases is Iterable
        ? rawAliases
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return DetailActressData(
      name: text('name'),
      imgPath: text('img_path'),
      mainType: text('main_type'),
      memo: text('memo'),
      height: text('height'),
      weight: text('weight'),
      bwh: text('bwh'),
      cup: text('cup'),
      birthDate: row['birth_date']?.toString(),
      aliases: aliases,
    );
  }

  final String name;
  final String imgPath;
  final String mainType;
  final String memo;
  final String height;
  final String weight;
  final String bwh;
  final String cup;
  final String? birthDate;
  final List<String> aliases;

  DetailActressData copyWith({String? imgPath, List<String>? aliases}) {
    return DetailActressData(
      name: name,
      imgPath: imgPath ?? this.imgPath,
      mainType: mainType,
      memo: memo,
      height: height,
      weight: weight,
      bwh: bwh,
      cup: cup,
      birthDate: birthDate,
      aliases: aliases ?? this.aliases,
    );
  }
}

final class DetailFormData {
  DetailFormData({
    required this.name,
    required this.imgPath,
    required this.mainType,
    required List<String> selectedAttrs,
    required this.memo,
    required this.height,
    required this.weight,
    required this.bwh,
    required this.cup,
    required this.birthDate,
  }) : selectedAttrs = List.unmodifiable(selectedAttrs);

  const DetailFormData.empty()
    : name = '',
      imgPath = '',
      mainType = '',
      selectedAttrs = const [],
      memo = '',
      height = '',
      weight = '',
      bwh = '',
      cup = '',
      birthDate = null;

  final String name;
  final String imgPath;
  final String mainType;
  final List<String> selectedAttrs;
  final String memo;
  final String height;
  final String weight;
  final String bwh;
  final String cup;
  final String? birthDate;
}

final class DetailEditState {
  DetailEditState({
    required this.isEditing,
    required this.name,
    required List<String> currentAttrs,
  }) : currentAttrs = List.unmodifiable(currentAttrs);

  final bool isEditing;
  final String name;
  final List<String> currentAttrs;
}

class DetailController extends ChangeNotifier {
  DetailController({required this.db, required this.actressId});

  final AppDatabase db;
  final int actressId;

  bool isEditing = false;
  int workCount = 0;
  DetailActressData actressData = const DetailActressData.empty();
  List<String> currentAttrs = [];
  List<String> actressAliases = const [];
  DetailActressData? _editActressSnapshot;
  List<String>? _editAttrsSnapshot;
  bool _disposed = false;

  // 初始化頁面資料，並同步目前的分類屬性。
  Future<void> init() async {
    actressData = await _loadActressData();
    currentAttrs = _parseAttrs(actressData.mainType);
    await refreshWorkCount(notify: false);
    actressAliases = actressData.aliases;
    _notifyIfActive();
  }

  Future<void> refresh() async {
    if (isEditing) {
      return;
    }
    actressData = await _loadActressData();
    currentAttrs = _parseAttrs(actressData.mainType);
    actressAliases = actressData.aliases;
    await refreshWorkCount(notify: false);
    _notifyIfActive();
  }

  List<String> getCurrentAliases() => List.unmodifiable(actressAliases);

  List<String> get aliases => getCurrentAliases();

  Future<bool> saveAliases(Iterable<String> aliases) async {
    try {
      await db.replaceActressAliases(actressId: actressId, aliases: aliases);
      actressAliases = (await db.getActressAliases(
        actressId,
      )).toList(growable: false);
      actressData = actressData.copyWith(aliases: actressAliases);
      _notifyIfActive();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshWorkCount({bool notify = true}) async {
    try {
      workCount = await db.getWorkCountForActress(actressId);
    } catch (_) {
      workCount = 0;
    }
    if (notify) {
      _notifyIfActive();
    }
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

  // 刪除資料與相關圖片，成功後回到首頁。
  Future<void> executeDelete(BuildContext context) async {
    final report = await db.deleteActressWithReport(actressId);

    if (report.databaseCommitted) {
      for (final imagePath in report.cacheEvictionPaths) {
        await FileImage(File(imagePath)).evict();
      }
      actressData = const DetailActressData.empty();
      currentAttrs = [];
      workCount = 0;
      _notifyIfActive();
    }

    if (!context.mounted) {
      return;
    }

    if (report.databaseCommitted) {
      AppSnackBar.showSuccess(context, _deletionSummary(report));

      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }

    AppSnackBar.showError(context, AppLocalizations.of(context).deleteFailed);
  }

  String _deletionSummary(ActressDeletionReport report) {
    final cleanup = report.fileCleanup;
    if (cleanup.rejectedCount > 0 || cleanup.deferredCount > 0) {
      return '資料已刪除；圖片：成功 ${cleanup.deletedCount}、拒絕 '
          '${cleanup.rejectedCount}、待重試 ${cleanup.deferredCount}';
    }
    return '已刪除 ${cleanup.deletedCount} 個圖片檔，共釋放 '
        '${(report.deletedBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
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

    await processPickedImage(context: context, pickedPath: pickedPath);
  }

  // 建立暫存輸出路徑，並開啟圖片裁切流程。
  Future<void> processPickedImage({
    required BuildContext context,
    required String pickedPath,
  }) async {
    final tempFileName =
        'actress_${actressId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final tempPath = path.join(db.imgDir, tempFileName);

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
  void onCropDone(String newImgPath) {
    actressData = actressData.copyWith(imgPath: newImgPath);
    _notifyIfActive();
  }

  // 移除目前照片路徑。
  void deletePhoto() {
    actressData = actressData.copyWith(imgPath: '');
    _notifyIfActive();
  }

  // 切換編輯狀態；離開編輯狀態時同步表單並寫入資料庫。
  Future<DetailEditState> toggleEditMode(
    BuildContext context,
    DetailFormData formData,
  ) async {
    if (!isEditing) {
      _editActressSnapshot = actressData;
      _editAttrsSnapshot = List<String>.from(currentAttrs);
      isEditing = true;
    } else if (await saveToDb(context, formData)) {
      currentAttrs = List<String>.from(formData.selectedAttrs);
      _syncActressData(formData);
      isEditing = false;
      _clearEditSnapshot();
    }

    _notifyIfActive();

    return DetailEditState(
      isEditing: isEditing,
      name: formData.name,
      currentAttrs: currentAttrs,
    );
  }

  // 放棄尚未儲存的編輯，只恢復檢視狀態。
  void cancelEditMode() {
    if (!isEditing) return;

    final actressSnapshot = _editActressSnapshot;
    final attrsSnapshot = _editAttrsSnapshot;
    if (actressSnapshot != null) {
      actressData = actressSnapshot;
    }
    if (attrsSnapshot != null) {
      currentAttrs = List<String>.from(attrsSnapshot);
    }
    isEditing = false;
    _clearEditSnapshot();
    _notifyIfActive();
  }

  void _clearEditSnapshot() {
    _editActressSnapshot = null;
    _editAttrsSnapshot = null;
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // 將表單資料寫入資料庫，並依結果顯示提示訊息。
  Future<bool> saveToDb(BuildContext context, DetailFormData formData) async {
    bool success;
    try {
      success = await db.updateActress(
        actressId: actressId,
        name: formData.name,
        imgPath: actressData.imgPath,
        mainType: formData.mainType,
        memo: formData.memo,
        height: formData.height,
        weight: formData.weight,
        bwh: formData.bwh,
        cup: formData.cup,
        birthDate: formData.birthDate,
      );
    } on Object {
      success = false;
    }

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
  Future<DetailActressData> _loadActressData() async {
    final dbData = await db.getActressById(actressId);

    if (dbData != null) {
      return DetailActressData.fromRow(dbData);
    }

    return const DetailActressData.empty();
  }

  // 將逗號分隔的分類文字轉成清單。
  List<String> _parseAttrs(String mainType) {
    return mainType
        .split(',')
        .map((attr) => attr.trim())
        .where((attr) => attr.isNotEmpty)
        .toList();
  }

  // 將表單資料同步回本地狀態。
  void _syncActressData(DetailFormData formData) {
    actressData = DetailActressData(
      name: formData.name,
      imgPath: formData.imgPath,
      mainType: formData.mainType,
      memo: formData.memo,
      height: formData.height,
      weight: formData.weight,
      bwh: formData.bwh,
      cup: formData.cup,
      birthDate: formData.birthDate,
      aliases: actressAliases,
    );
  }
}
