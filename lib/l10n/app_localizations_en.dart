// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addTitle => 'Add Collection';

  @override
  String get noPhoto => 'No Photo';

  @override
  String get selectPhoto => 'Select Photo';

  @override
  String get removePhoto => 'Remove Photo';

  @override
  String get actressNameRequired => 'Actress Name (Required)';

  @override
  String get saveCard => 'Save Card';

  @override
  String get changePhoto => 'Change Photo';

  @override
  String get deletePhoto => 'Delete Photo';

  @override
  String get noAttributesSet => 'No Attributes Set';

  @override
  String get bodyInfo => 'Body Info';

  @override
  String get heightCm => 'Height (cm)';

  @override
  String get weightKg => 'Weight (kg)';

  @override
  String get cup => 'Cup';

  @override
  String get measurements => 'Measurements';

  @override
  String get privateNotes => 'Private Notes';

  @override
  String get noNotes => 'No Notes';

  @override
  String get confirmDeleteTitle => 'Confirm Delete?';

  @override
  String get deleteWarningWithPhoto =>
      'This cannot be undone. The photo file will also be deleted.';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirmDelete => 'Delete';

  @override
  String get appTitle => 'AVACA Collection Library';

  @override
  String get search => 'Search';

  @override
  String get filterAndSort => 'Filter & Sort';

  @override
  String get add => 'Add';

  @override
  String get settings => 'Settings';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get noData => 'No Data';

  @override
  String get searchNameHint => 'Enter a name to search quickly...';

  @override
  String get applySettings => 'Apply Settings';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get followSystem => 'Follow System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get customTheme => 'Custom Theme';

  @override
  String get pureBlackAmoled => 'Pure Black AMOLED';

  @override
  String get pureBlackOnlyDarkOrCustom => 'Only works with dark / custom theme';

  @override
  String get colorSurface => 'Background';

  @override
  String get colorSurfaceContainer => 'Card Background';

  @override
  String get colorOnSurface => 'Primary Text';

  @override
  String get colorOnSurfaceVariant => 'Secondary Text';

  @override
  String get colorPrimary => 'Primary Accent';

  @override
  String get colorOnPrimary => 'Text on Primary';

  @override
  String get colorOutline => 'Border / Divider';

  @override
  String adjustColorTitle(String colorLabel) {
    return 'Adjust $colorLabel';
  }

  @override
  String get apply => 'Apply';

  @override
  String get imageReadFailedUnsupportedFormat =>
      'Failed to read image. The format may not be supported.';

  @override
  String get enterName => 'Please enter a name';

  @override
  String get collectionAdded => 'Added to collection';

  @override
  String get alreadyInCollection => 'Already in collection';

  @override
  String get dataDeleted => 'Data deleted permanently';

  @override
  String get deleteFailed => 'Delete failed';

  @override
  String get photoCroppedRememberSave => 'Photo cropped. Remember to save!';

  @override
  String get detailSaved => 'Details saved';

  @override
  String get saveFailedDuplicateName =>
      'Save failed. The name may already exist.';

  @override
  String get dataNotFound => 'Data not found';

  @override
  String get attrCensored => 'Censored';

  @override
  String get attrUncensored => 'Uncensored';

  @override
  String get attrWestern => 'Western';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => 'Domestic';

  @override
  String get filterAll => 'All';

  @override
  String get imageCropLoadErrorTitle => 'Image load error';

  @override
  String get close => 'Close';

  @override
  String get imageDecodeFailed => 'Failed to decode image';

  @override
  String get cropZoom => 'Zoom';

  @override
  String get cropPanX => 'Horizontal pan';

  @override
  String get cropPanY => 'Vertical pan';

  @override
  String get confirmCrop => 'Crop';

  @override
  String get language => 'Language';

  @override
  String get traditionalChineseTaiwan => 'Traditional Chinese (Taiwan)';

  @override
  String get english => 'English';
}
