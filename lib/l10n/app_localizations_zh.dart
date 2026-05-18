// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get addTitle => '新增收藏';

  @override
  String get noPhoto => '尚無照片';

  @override
  String get selectPhoto => '選擇照片';

  @override
  String get removePhoto => '移除照片';

  @override
  String get actressNameRequired => '女優姓名 (必填)';

  @override
  String get saveCard => '儲存卡片';

  @override
  String get changePhoto => '更換照片';

  @override
  String get deletePhoto => '刪除照片';

  @override
  String get noAttributesSet => '尚未設定屬性';

  @override
  String get bodyInfo => '身體資料';

  @override
  String get heightCm => '身高 (cm)';

  @override
  String get weightKg => '體重 (kg)';

  @override
  String get cup => '罩杯';

  @override
  String get measurements => '三圍';

  @override
  String get privateNotes => '私人筆記';

  @override
  String get noNotes => '尚無筆記';

  @override
  String get confirmDeleteTitle => '確認刪除？';

  @override
  String get deleteWarningWithPhoto => '刪除後將無法復原，連同照片檔案也會被清除。';

  @override
  String get cancel => '取消';

  @override
  String get confirmDelete => '確定刪除';

  @override
  String get appTitle => 'AVACA 收藏庫';

  @override
  String get search => '搜尋';

  @override
  String get filterAndSort => '篩選與排序';

  @override
  String get add => '新增';

  @override
  String get settings => '設定';

  @override
  String loadFailed(String error) {
    return '載入失敗：$error';
  }

  @override
  String get noData => '尚無資料';

  @override
  String get searchNameHint => '輸入名稱快速搜尋...';

  @override
  String get applySettings => '套用設定';

  @override
  String get themeMode => '主題模式';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get lightTheme => '淺色';

  @override
  String get darkTheme => '深色';

  @override
  String get customTheme => '自訂主題';

  @override
  String get pureBlackAmoled => '純黑 AMOLED';

  @override
  String get pureBlackOnlyDarkOrCustom => '僅深色 / 自訂主題有效';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => '卡片背景';

  @override
  String get colorOnSurface => '主要文字';

  @override
  String get colorOnSurfaceVariant => '次要文字';

  @override
  String get colorPrimary => '互動主色';

  @override
  String get colorOnPrimary => '主色文字';

  @override
  String get colorOutline => '邊框 / 分隔線';

  @override
  String adjustColorTitle(String colorLabel) {
    return '調整 $colorLabel';
  }

  @override
  String get apply => '套用';

  @override
  String get imageReadFailedUnsupportedFormat => '圖片讀取失敗，可能格式不支援';

  @override
  String get enterName => '請輸入姓名';

  @override
  String get collectionAdded => '收藏成功';

  @override
  String get alreadyInCollection => '已經在收藏庫中';

  @override
  String get dataDeleted => '資料已徹底刪除';

  @override
  String get deleteFailed => '刪除失敗';

  @override
  String get photoCroppedRememberSave => '照片裁切完成，請記得按下儲存！';

  @override
  String get detailSaved => '詳細資料已儲存！';

  @override
  String get saveFailedDuplicateName => '儲存失敗，可能是姓名與他人重複';

  @override
  String get dataNotFound => '找不到資料';

  @override
  String get attrCensored => '有碼';

  @override
  String get attrUncensored => '無碼';

  @override
  String get attrWestern => '歐美';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '國產';

  @override
  String get filterAll => '全部';

  @override
  String get imageCropLoadErrorTitle => '圖片讀取錯誤';

  @override
  String get close => '關閉';

  @override
  String get imageDecodeFailed => '圖片解碼失敗';

  @override
  String get cropZoom => '放大縮小';

  @override
  String get cropPanX => '左右平移';

  @override
  String get cropPanY => '上下平移';

  @override
  String get confirmCrop => '確定裁切';

  @override
  String get language => '語言';

  @override
  String get traditionalChineseTaiwan => '繁體中文（台灣）';

  @override
  String get english => '英文';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get addTitle => '新增收藏';

  @override
  String get noPhoto => '尚無照片';

  @override
  String get selectPhoto => '選擇照片';

  @override
  String get removePhoto => '移除照片';

  @override
  String get actressNameRequired => '女優姓名 (必填)';

  @override
  String get saveCard => '儲存卡片';

  @override
  String get changePhoto => '更換照片';

  @override
  String get deletePhoto => '刪除照片';

  @override
  String get noAttributesSet => '尚未設定屬性';

  @override
  String get bodyInfo => '身體資料';

  @override
  String get heightCm => '身高 (cm)';

  @override
  String get weightKg => '體重 (kg)';

  @override
  String get cup => '罩杯';

  @override
  String get measurements => '三圍';

  @override
  String get privateNotes => '私人筆記';

  @override
  String get noNotes => '尚無筆記';

  @override
  String get confirmDeleteTitle => '確認刪除？';

  @override
  String get deleteWarningWithPhoto => '刪除後將無法復原，連同照片檔案也會被清除。';

  @override
  String get cancel => '取消';

  @override
  String get confirmDelete => '確定刪除';

  @override
  String get appTitle => 'AVACA 收藏庫';

  @override
  String get search => '搜尋';

  @override
  String get filterAndSort => '篩選與排序';

  @override
  String get add => '新增';

  @override
  String get settings => '設定';

  @override
  String loadFailed(String error) {
    return '載入失敗：$error';
  }

  @override
  String get noData => '尚無資料';

  @override
  String get searchNameHint => '輸入名稱快速搜尋...';

  @override
  String get applySettings => '套用設定';

  @override
  String get themeMode => '主題模式';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get lightTheme => '淺色';

  @override
  String get darkTheme => '深色';

  @override
  String get customTheme => '自訂主題';

  @override
  String get pureBlackAmoled => '純黑 AMOLED';

  @override
  String get pureBlackOnlyDarkOrCustom => '僅深色 / 自訂主題有效';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => '卡片背景';

  @override
  String get colorOnSurface => '主要文字';

  @override
  String get colorOnSurfaceVariant => '次要文字';

  @override
  String get colorPrimary => '互動主色';

  @override
  String get colorOnPrimary => '主色文字';

  @override
  String get colorOutline => '邊框 / 分隔線';

  @override
  String adjustColorTitle(String colorLabel) {
    return '調整 $colorLabel';
  }

  @override
  String get apply => '套用';

  @override
  String get imageReadFailedUnsupportedFormat => '圖片讀取失敗，可能格式不支援';

  @override
  String get enterName => '請輸入姓名';

  @override
  String get collectionAdded => '收藏成功';

  @override
  String get alreadyInCollection => '已經在收藏庫中';

  @override
  String get dataDeleted => '資料已徹底刪除';

  @override
  String get deleteFailed => '刪除失敗';

  @override
  String get photoCroppedRememberSave => '照片裁切完成，請記得按下儲存！';

  @override
  String get detailSaved => '詳細資料已儲存！';

  @override
  String get saveFailedDuplicateName => '儲存失敗，可能是姓名與他人重複';

  @override
  String get dataNotFound => '找不到資料';

  @override
  String get attrCensored => '有碼';

  @override
  String get attrUncensored => '無碼';

  @override
  String get attrWestern => '歐美';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '國產';

  @override
  String get filterAll => '全部';

  @override
  String get imageCropLoadErrorTitle => '圖片讀取錯誤';

  @override
  String get close => '關閉';

  @override
  String get imageDecodeFailed => '圖片解碼失敗';

  @override
  String get cropZoom => '放大縮小';

  @override
  String get cropPanX => '左右平移';

  @override
  String get cropPanY => '上下平移';

  @override
  String get confirmCrop => '確定裁切';

  @override
  String get language => '語言';

  @override
  String get traditionalChineseTaiwan => '繁體中文（台灣）';

  @override
  String get english => '英文';
}
