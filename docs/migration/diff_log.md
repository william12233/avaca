# AVACA Flet to Flutter Migration Log

## Purpose

This file is a **migration record**, not the runtime platform-difference manager.

Runtime platform differences must be centralized in:

- `lib/core/platform_adapter.dart`

This file only records:

- Which old Flet file was converted to which Flutter file
- What behavior was preserved
- What differences were required
- Which files were deferred
- Important migration decisions

## Runtime Platform Difference Policy

Any code that depends on platform differences should not be scattered across controllers, views, or components.

Platform-specific logic should be centralized in:

- `lib/core/platform_adapter.dart`

Examples:

- Windows / Linux SQLite FFI initialization
- Windows / macOS / Linux / Android / iOS app data paths
- Future platform-specific permission handling
- Future desktop/mobile file behavior differences

## Migration Policy

- 不救火式開發
- 不跳步
- 不重設架構
- Flutter 結構 1:1 對齊舊 Flet 結構
- 每次只轉一個檔案或一個功能
- 先說舊檔案做了什麼，再寫 Flutter 對應實作
- 不跳過 controller / core
- 裁切器依舊檔行為重做，不使用 `image_cropper` plugin

## Project Paths

- New Flutter project: `D:\william\APP\avaca`
- Old Flet project: reference only
- Old Flutter project: reference only

## Current Migration Status

### Done

- `core/config.py` -> `lib/core/config.dart`
- `core/database.py` -> `lib/core/database.dart`
- Runtime platform differences centralized -> `lib/core/platform_adapter.dart`
- `components/app_snackbar.py` -> `lib/components/app_snackbar.dart`
- `components/image_cropper.py` -> `lib/components/image_cropper.dart`
- `components/actress_card.py` -> `lib/components/actress_card.dart`
- `controllers/home_controller.py` -> `lib/controllers/home_controller.dart`
- `controllers/add_controller.py` -> `lib/controllers/add_controller.dart`

### Deferred

- `core/cloud_storage.py` -> `lib/core/cloud_storage.dart`

### Pending

- `controllers/detail_controller.py` -> `lib/controllers/detail_controller.dart`
- `controllers/settings_controller.py` -> `lib/controllers/settings_controller.dart`
- `views/home_view.py` -> `lib/views/home_view.dart`
- `views/add_view.py` -> `lib/views/add_view.dart`
- `views/detail_view.py` -> `lib/views/detail_view.dart`
- `views/settings_view.py` -> `lib/views/settings_view.dart`
- `main.py` -> `lib/main.dart`

---

## core/config.py -> lib/core/config.dart

Status: Converted

### Old responsibility

`core/config.py` defined global app colors and Flet themes.

It contained:

- `App_Colors`
- `AppTheme.BLACK`
- `AppTheme.DARK`
- `AppTheme.LIGHT`

The file only handled app-wide color and theme configuration. It did not contain database logic, routing, controller logic, or page UI.

### Flutter responsibility

`lib/core/config.dart` defines:

- `AppColors`
- `AppTheme.black`
- `AppTheme.dark`
- `AppTheme.light`

Flutter uses `ThemeData` and `ColorScheme` instead of Flet `ft.Theme` and `ft.ColorScheme`.

### Preserved behavior

- Light theme preserved.
- Dark theme preserved.
- Pure black OLED/AMOLED theme preserved.
- Original color hex values preserved.
- This file remains a core/global configuration file.

### Required differences

- `App_Colors` was renamed to `AppColors` to follow Dart naming conventions.
- `AppTheme.BLACK`, `AppTheme.DARK`, and `AppTheme.LIGHT` became `AppTheme.black`, `AppTheme.dark`, and `AppTheme.light`.
- Flet theme objects were replaced with Flutter `ThemeData`.

---

## core/database.py -> lib/core/database.dart

Status: Converted

### Old responsibility

`core/database.py` defined `AppDatabase`.

It handled:

- App data directory resolution
- `images` directory creation
- SQLite database file creation
- `actresses` table creation
- Schema migration through `PRAGMA table_info`
- Actress list query
- Actress detail query
- Add actress
- Update actress
- Delete actress

### Flutter responsibility

`lib/core/database.dart` defines `AppDatabase`.

It now focuses only on:

- SQLite initialization
- Database file usage
- `images` directory usage
- Schema creation
- Migration
- CRUD

Runtime platform differences were moved out to:

- `lib/core/platform_adapter.dart`

### Preserved behavior

- Database file remains `avaca.db`.
- Image directory remains `images`.
- Table remains `actresses`.
- `name` remains `TEXT NOT NULL UNIQUE`.
- `modified_at` remains updated on insert and update.
- Existing migration columns are preserved:
  - `main_type`
  - `tags`
  - `memo`
  - `height`
  - `weight`
  - `bwh`
  - `cup`
  - `modified_at`
- Search, filter, and sort behavior are preserved.

### Required differences

- Database initialization is asynchronous in Flutter.
  - Old Flet/Python: `db = AppDatabase()`
  - New Flutter/Dart: `final db = AppDatabase(); await db.init();`
- Python `sqlite3` was replaced with Flutter SQLite packages.
- Python snake_case methods were converted to Dart lowerCamelCase:
  - `get_all_actresses` -> `getAllActresses`
  - `get_actress_by_id` -> `getActressById`
  - `add_actress` -> `addActress`
  - `update_actress` -> `updateActress`
  - `delete_actress` -> `deleteActress`
- Return values remain map-based to avoid adding a new model layer at this stage.

---

## Runtime platform differences -> lib/core/platform_adapter.dart

Status: Added

### Reason

The original Python database layer handled platform-specific storage paths directly inside `core/database.py`.

In Flutter, platform-specific decisions must not be scattered through database, controllers, views, or components.

### Flutter responsibility

`lib/core/platform_adapter.dart` centralizes runtime platform differences.

It handles:

- Platform detection
- Desktop/mobile grouping
- SQLite FFI setup for platforms that require it
- App data directory resolution

### Centralized platform behavior

- Windows:
  - App data path: `%LOCALAPPDATA%\AVACA`
  - SQLite uses `sqflite_common_ffi`
- macOS:
  - App data path: `~/Library/Application Support/AVACA`
- Linux:
  - App data path: `~/.local/share/AVACA`
  - SQLite uses `sqflite_common_ffi`
- Android / iOS:
  - App document directory + `avaca_data`

### Policy going forward

Any future platform-specific logic should be added to `platform_adapter.dart` first, instead of being scattered into controllers, views, components, or database code.

---

## core/cloud_storage.py -> lib/core/cloud_storage.dart

Status: Deferred

### Reason

Cloud storage is optional in the old project scope.

The current migration priority is to stabilize the local app flow first:

- Local SQLite database
- Local image storage
- Add / edit / delete actress data
- Search / filter / sort
- Custom image cropper integration
- Settings

### Migration decision

This file is intentionally deferred.

It is not deleted from the migration plan and should not be considered unsupported.

It will be converted after the local-only app flow is stable.

### Required future handling

When this file is resumed, the Flutter version should preserve the old responsibility:

- Cloud upload / download if implemented in old Flet project
- Optional sync behavior
- Failure isolation from local database operations
- No forced dependency on cloud storage for local CRUD

### Current Flutter status

No `lib/core/cloud_storage.dart` is created at this stage.

This prevents introducing placeholder logic that could hide missing cloud behavior.

---

## components/app_snackbar.py -> lib/components/app_snackbar.dart

Status: Converted

### Old responsibility

`components/app_snackbar.py` defined `AppSnackBar`.

It handled global notification display through Flet `SnackBar`.

It provided:

- `show_success`
- `show_error`
- `show_info`

It also contained a shared `_show` method and `_calculate_width` helper.

### Flutter responsibility

`lib/components/app_snackbar.dart` defines `AppSnackBar`.

It handles global notification display through Flutter `ScaffoldMessenger` and `SnackBar`.

It provides:

- `showSuccess`
- `showError`
- `showInfo`

### Preserved behavior

- Success notification is green.
- Error notification is red.
- Info notification is blue grey.
- Text color remains white.
- Text alignment remains centered.
- SnackBar behavior remains floating.
- Duration remains 3000ms.
- Border radius remains 20.
- Padding remains left=5, top=4, right=5, bottom=6.
- Message width is still estimated by character width.
- Maximum SnackBar width remains 400.
- Only one SnackBar should be visible at a time.

### Required differences

- Flet `page.overlay` was replaced with Flutter `ScaffoldMessenger`.
- Flet `ft.SnackBar` was replaced with Flutter `SnackBar`.
- `page.update()` is not needed in Flutter.
- `show_success`, `show_error`, and `show_info` were renamed to Dart lowerCamelCase:
  - `show_success` -> `showSuccess`
  - `show_error` -> `showError`
  - `show_info` -> `showInfo`
- Flutter methods receive `BuildContext` instead of Flet `Page`.

---

## components/image_cropper.py -> lib/components/image_cropper.dart

Status: Rebuilt

### Old responsibility

`components/image_cropper.py` defined `ImageCropper`.

It handled image cropping through a Flet `AlertDialog`.

The old cropper:

- Loaded the selected image.
- Applied EXIF orientation correction.
- Displayed the image with `BoxFit.CONTAIN`.
- Displayed a square crop box above the image.
- Let the user adjust crop box size.
- Let the user adjust crop box horizontal position.
- Let the user adjust crop box vertical position.
- Cropped the original image based on slider values.
- Saved the result as JPEG with quality 95.
- Called `on_crop_done(temp_img_path)` after success.

### Flutter responsibility

`lib/components/image_cropper.dart` defines `ImageCropper`.

It provides:

- A custom Flutter `AlertDialog`
- A fixed square crop box overlay
- Three sliders:
  - `放大縮小`
  - `左右平移`
  - `上下平移`
- JPEG output through Dart image processing
- Callback after crop completion

### Preserved behavior

- The image is not the interactive subject.
- The crop box is the interaction subject.
- Crop box remains square.
- Zoom slider range remains 1 to 10.
- Horizontal slider range remains 0 to 1.
- Vertical slider range remains 0 to 1.
- Dialog content padding remains 24.
- Dialog corner radius remains 16.
- Landscape layout places image and controls side by side.
- Portrait layout places image above controls.
- Output JPEG quality remains 95.
- EXIF orientation correction is preserved.
- Crop completion still returns the cropped image path.

### Required differences

- Flet `AlertDialog` was replaced with Flutter `AlertDialog`.
- Flet `Page` was replaced with Flutter `BuildContext`.
- Python PIL was replaced with Dart `image` package.
- `file_picker_file.path` is replaced by `sourceImagePath`.
- `temp_img_path` is replaced by `outputImagePath`.
- `on_crop_done(temp_img_path)` is replaced by `onCropDone(outputImagePath)`.
- Flutter implementation is asynchronous.
- No `image_cropper` plugin is used.

---

## components/actress_card.py -> lib/components/actress_card.dart

Status: Converted

### Old responsibility

`components/actress_card.py` defined `ActressCard`.

It rendered an actress card with:

- Actress image
- Actress name
- Optional click handler

The card was used as a reusable UI component.

### Flutter responsibility

`lib/components/actress_card.dart` defines `ActressCard`.

It renders:

- A clickable card
- A square image area
- A fallback placeholder when no image is available
- A one-line actress name label

### Preserved behavior

- Card background uses `surfaceContainerHighest`.
- Card elevation remains 0.
- Card border radius remains 12.
- Card outline remains 1px.
- Card padding remains 10.
- Image area remains square.
- Image fit remains cover.
- Image border radius remains 8.
- Missing image placeholder is preserved.
- Placeholder icon remains `image_not_supported`.
- Placeholder text remains `尚無相片`.
- Actress name remains size 16.
- Actress name remains bold.
- Actress name remains single-line.
- Actress name overflow remains ellipsis.
- Actress name alignment remains centered.

### Required differences

- Flet `ft.Card` was replaced with Flutter `Card`.
- Flet `Container(on_click=...)` was replaced with Flutter `InkWell(onTap: ...)`.
- `img_path` was renamed to `imgPath`.
- `on_card_click` was renamed to `onTap`.
- Flet `ft.Image(src=...)` was replaced with Flutter `Image.file(File(...))`.
- Flutter version adds `errorBuilder` so missing or invalid image files fall back to the placeholder instead of breaking the UI.

---

## controllers/home_controller.py -> lib/controllers/home_controller.dart

Status: Converted

### Old responsibility

`controllers/home_controller.py` defined `HomeController`.

It handled home page state and actions:

- Search keyword
- Current filter
- Current sort
- Search bar open state
- Filter sheet open/apply result
- Gallery data loading
- Navigation to detail/settings/add routes

### Flutter responsibility

`lib/controllers/home_controller.dart` defines `HomeController`.

It keeps the same home state and calls `AppDatabase.getAllActresses()` to load gallery data.

### Preserved behavior

- `current_search` default remains empty.
- `current_filter` default remains `全部`.
- `current_sort` default remains `新增時間 (新到舊)`.
- `is_search_open` default remains false.
- Closing search clears the search keyword.
- Closing search requests gallery refresh.
- Filter options remain:
  - `全部`
  - `有碼`
  - `無碼`
  - `歐美`
  - `FC2`
  - `國產`
- Gallery query still uses search keyword, filter type, and sort value.
- Detail route remains `/detail/{id}`.
- Settings route remains `/settings`.
- Add route remains `/add`.

### Required differences

- Flet `page.push_route()` was replaced with Flutter `Navigator.pushNamed()`.
- Flutter route methods receive `BuildContext`.
- Python snake_case methods were converted to Dart lowerCamelCase.
- Python dictionaries were replaced with Dart `Map`.
- Gallery data loading is asynchronous because Flutter database access is asynchronous.

---

## controllers/add_controller.py -> lib/controllers/add_controller.dart

Status: Converted

### Old responsibility

`controllers/add_controller.py` defined `AddController`.

It handled:

- Image selection
- Cropper invocation
- Temporary cropped image path
- Selected image path state
- Image preview state dictionary
- Image removal
- Name normalization
- Safe image filename generation
- Add database insert
- Moving cropped image to final image path
- Success / error snackbar
- Returning to home route

### Flutter responsibility

`lib/controllers/add_controller.dart` defines `AddController`.

It handles the same add flow using:

- `file_picker`
- `ImageCropper.open`
- `AppDatabase.addActress`
- `AppSnackBar`
- Flutter `Navigator`
- `ChangeNotifier` for future view refresh

### Verification result

The current Flutter implementation has been analyzed successfully with:

```powershell
flutter analyze
```

Result:

```text
No issues found!
```

### Preserved behavior

- Temporary image remains `temp_crop.jpg`.
- Temporary image is stored under `db.imgDir`.
- Final image is saved under `db.imgDir`.
- Final image name is based on the actress name.
- Invalid filename characters are removed.
- Empty name shows `請輸入姓名`.
- Duplicate name shows `已經在收藏庫中`.
- Successful save shows `收藏成功`.
- Successful save returns to `/`.
- Cancel / back removes the temporary image.
- Image state map keeps:
  - `preview_src`
  - `preview_visible`
  - `placeholder_visible`
  - `delete_button_visible`
- Allowed image extensions remain:
  - `png`
  - `jpg`
  - `jpeg`
  - `webp`

### Required differences

- Flet `FilePicker` was replaced with Flutter `file_picker`.
- Flet `Page` was replaced with Flutter `BuildContext`.
- Flet route push was replaced with Flutter `Navigator`.
- Python `shutil.move` was replaced with Dart `File.renameSync`, with copy/delete fallback.
- Python base64 encoding was replaced with Dart `base64Encode`.
- Python snake_case methods were converted to Dart lowerCamelCase:
  - `set_cropper` -> `setCropper`
  - `window_resized` -> `windowResized`
  - `pick_image` -> `pickImage`
  - `on_crop_success` -> `onCropSuccess`
  - `remove_image` -> `removeImage`
  - `save_actress` -> `saveActress`
  - `go_back` -> `goBack`
- Controller extends `ChangeNotifier` so the future Flutter view can react to image state changes without adding a new state management package.
- The old Flet controller stored a cropper instance through `set_cropper`; the Flutter version keeps a no-op compatibility method because the new cropper opens through `ImageCropper.open`.
- The old Flet controller called `cropper.handle_resize()` on window resize; the Flutter cropper recalculates layout through `MediaQuery` / `LayoutBuilder` during rebuild.

### File picker API difference

The Flutter version uses the current `file_picker` static API:

- Legacy Flutter API: `FilePicker.platform.pickFiles()`
- Current Flutter API: `FilePicker.pickFiles()`

This is required because newer `file_picker` versions refactored `FilePicker` to use static methods directly.

---

## Next migration target

Next file:

- `controllers/detail_controller.py` -> `lib/controllers/detail_controller.dart`
---

## controllers/detail_controller.py -> lib/controllers/detail_controller.dart

Status: Converted

### Old responsibility

`controllers/detail_controller.py` defined `DetailController`.

It handled:

- Loading actress detail data
- Fallback data when the record does not exist
- Parsing `main_type` into selected attributes
- Delete dialog state
- Deleting image file
- Deleting actress data from database
- Picking a replacement image
- Invoking the cropper
- Updating image state after crop
- Removing photo from the detail state
- Toggling edit mode
- Saving edited detail data
- Syncing form data back to local controller state

### Flutter responsibility

`lib/controllers/detail_controller.dart` defines `DetailController`.

It handles the same detail page flow using:

- `AppDatabase.getActressById`
- `AppDatabase.updateActress`
- `AppDatabase.deleteActress`
- `file_picker`
- `ImageCropper.open`
- `AppSnackBar`
- Flutter `Navigator`
- `ChangeNotifier`

### Preserved behavior

- `is_editing` default remains false.
- Missing data fallback keeps `找不到資料`.
- Attribute options remain:
  - `有碼`
  - `無碼`
  - `歐美`
  - `FC2`
  - `國產`
- Delete dialog returns `open: true` / `open: false`.
- Delete flow removes the image file first.
- Delete success message remains `資料已徹底刪除`.
- Delete failure message remains `刪除失敗`.
- Replacement photo extensions remain:
  - `png`
  - `jpg`
  - `jpeg`
- Crop result updates `img_path`.
- Delete photo clears `img_path`.
- Leaving edit mode saves form data.
- Save success message remains `詳細資料已儲存！`.
- Save failure message remains `儲存失敗，可能是姓名與他人重複`.

### Required differences

- Flet `Page` was replaced with Flutter `BuildContext`.
- Flet `page.go("/")` was replaced with Flutter `Navigator.pushNamedAndRemoveUntil("/")`.
- Flet `FilePicker` was replaced with Flutter `file_picker`.
- Flet cropper instance was replaced with `ImageCropper.open`.
- Python `os.remove` was replaced with Dart `File.deleteSync`.
- Python `time.time()` was replaced with `DateTime.now().millisecondsSinceEpoch`.
- Database operations are asynchronous in Flutter.
- Python snake_case methods were converted to Dart lowerCamelCase.
- Controller extends `ChangeNotifier` so the future detail view can react to data changes.
---

## controllers/settings_controller.py -> lib/controllers/settings_controller.dart

Status: Converted with cloud deferred

### Old responsibility

`controllers/settings_controller.py` defined `SettingsController`.

It handled:

- Appearance state
- Theme mode changes
- Pure black mode changes
- Back navigation
- Google Drive auto login check
- Google Drive login/logout UI state
- Google device-code login flow
- Google Drive backup flow

### Flutter responsibility

`lib/controllers/settings_controller.dart` defines `SettingsController`.

It currently handles:

- Appearance state
- Theme mode changes
- Pure black mode changes
- Back navigation
- Preserved Google Drive UI state method entries

Cloud operations remain deferred because `core/cloud_storage.py` is also deferred.

### Preserved behavior

- Theme mode still supports:
  - `system`
  - `light`
  - `dark`
- Pure black mode remains supported.
- `theme_mode` is still persisted.
- `pure_black` is still persisted.
- Back navigation still returns to `/`.
- Login success state text remains `狀態：✅ 已登入，可以開始備份！`.
- Logout state text remains `狀態：已登出`.
- Google login and backup method names remain represented in Flutter.

### Required differences

- Flet `SharedPreferences` was replaced with Flutter `shared_preferences`.
- Flet `Page` theme mutation was replaced with controller state + `notifyListeners`.
- Flet `page.go("/")` was replaced with Flutter `Navigator.pushNamedAndRemoveUntil("/")`.
- Flet `ft.Colors` and `ft.Icons` were replaced with Flutter `Colors` and `Icons`.
- `GoogleDriveSync` is not imported yet because cloud storage migration is deferred.
- Google Drive methods currently return deferred UI states instead of performing network/cloud operations.
---

## views/home_view.py -> lib/views/home_view.dart

Status: Converted

### Old responsibility

`views/home_view.py` defined `HomeView`.

It rendered the home page with:

- AppBar
- Search bar
- Filter and sort bottom sheet
- Gallery grid
- Empty gallery state
- Navigation buttons
- Actress cards

It used `HomeController` for state and actions.

### Flutter responsibility

`lib/views/home_view.dart` defines `HomeView`.

It renders the same home page using:

- `Scaffold`
- `AppBar`
- Animated search container
- `showModalBottomSheet`
- `FutureBuilder`
- `GridView.builder`
- `ActressCard`
- `HomeController`

### Preserved behavior

- App title remains `AVACA 收藏庫`.
- Search hint remains `輸入名稱快速搜尋...`.
- Search open/close behavior is preserved.
- Closing search clears the keyword.
- Search changes refresh the gallery.
- Filter options are provided by `HomeController`.
- Sort options preserve the old values.
- Apply button text remains `套用設定`.
- Empty gallery message remains `找不到符合條件的女優...`.
- Actress cards still use `name`, `img_path`, and `id`.
- Card tap still navigates to `/detail/{id}`.
- Add button navigates to `/add`.
- Settings button navigates to `/settings`.

### Required differences

- Flet `ft.View` was replaced with Flutter `StatefulWidget`.
- Flet `page.update()` was replaced with `setState`.
- Flet `BottomSheet` was replaced with `showModalBottomSheet`.
- Flet `ResponsiveRow` was replaced with `LayoutBuilder` + `GridView.builder`.
- Gallery loading uses `FutureBuilder` because Flutter database access is asynchronous.
- Flet event handlers were converted to Flutter callbacks.
- Flutter `RadioListTile(groupValue/onChanged)` was avoided because those members are deprecated in the current Flutter SDK. Sorting options are rendered with `ListTile` and radio-style icons instead.
---

## views/add_view.py -> lib/views/add_view.dart

Status: Converted

### Old responsibility

`views/add_view.py` defined `AddView`.

It rendered the add page with:

- AppBar
- Back button
- Image placeholder
- Image preview
- Pick image button
- Delete image button
- Name input
- Save button

It used `AddController` and `ImageCropper`.

### Flutter responsibility

`lib/views/add_view.dart` defines `AddView`.

It renders the same add page using:

- `Scaffold`
- `AppBar`
- `TextField`
- `Image.memory`
- `ElevatedButton`
- `IconButton`
- `AddController`

### Preserved behavior

- Route remains `/add`.
- AppBar title remains `新增收藏`.
- Name input label remains `女優姓名 (必填)`.
- Name input width remains 300.
- Name input alignment remains centered.
- Image preview remains 180x180.
- Placeholder text remains `尚無照片`.
- Pick image button text remains `選擇照片`.
- Delete image tooltip remains `移除照片`.
- Save button text remains `儲存卡片`.
- Save button width remains 200.
- Image state is still rendered from controller state:
  - `preview_src`
  - `preview_visible`
  - `placeholder_visible`
  - `delete_button_visible`

### Required differences

- Flet `ft.View` was replaced with Flutter `StatefulWidget`.
- Flet `page.update()` was replaced with `setState`.
- Flet `ft.Image(src=base64)` was replaced with Flutter `Image.memory`.
- The view no longer creates an `ImageCropper` instance directly.
- The Flutter add flow opens the cropper through `AddController.pickImage(context)`.
- `AddController` is listened to through `ChangeNotifier`.
---

## views/detail_view.py -> lib/views/detail_view.dart

Status: Converted

### Old responsibility

`views/detail_view.py` defined `DetailView`.

It rendered the detail page with:

- AppBar title / editable name input
- Profile image / fallback avatar
- Photo edit controls
- Attribute view row
- Attribute edit row
- Body stat fields
- Memo field
- Delete confirmation dialog
- Edit/save mode rendering
- Image state rendering
- Form data collection

It used `DetailController` and `ImageCropper`.

### Flutter responsibility

`lib/views/detail_view.dart` defines `DetailView`.

It renders the same detail page using:

- `Scaffold`
- `AppBar`
- `LayoutBuilder`
- `TextField`
- `Image.file`
- `CircleAvatar`
- `FilterChip`
- `showDialog`
- `DetailController`

### Preserved behavior

- AppBar displays the actress name.
- Edit mode changes the title into an editable name field.
- Edit button changes to save behavior.
- Delete button is hidden during edit mode.
- Profile image remains 200x200 circular.
- Missing photo fallback remains a person icon.
- Edit mode shows `更換照片` and `刪除照片`.
- Attribute options remain:
  - `有碼`
  - `無碼`
  - `歐美`
  - `FC2`
  - `國產`
- Empty attribute state remains `尚未設定屬性`.
- Body card title remains `身體密碼`.
- Memo card title remains `私人筆記`.
- Stat fields remain:
  - `身高 (cm)`
  - `體重 (kg)`
  - `罩杯`
  - `三圍 (B-W-H)`
- Delete confirmation text is preserved.

### Required differences

- Flet `ft.View` was replaced with Flutter `StatefulWidget`.
- Flet `ResponsiveRow` was replaced with `LayoutBuilder`.
- Flet `AlertDialog` was replaced with Flutter `showDialog`.
- Flet `Checkbox` attribute editing was represented with Flutter `FilterChip`.
- Flet `page.update()` was replaced with `setState` and `ChangeNotifier`.
- The view no longer creates an `ImageCropper` instance directly.
- Photo change is handled through `DetailController.changePhoto(context)`.
---

## views/settings_view.py -> lib/views/settings_view.dart

Status: Converted with cloud deferred

### Old responsibility

`views/settings_view.py` defined `SettingsView`.

It rendered the settings page with:

- AppBar
- Back button
- Appearance settings section
- Theme mode dropdown
- Pure black mode switch
- Google Drive sync section
- Login button
- Logout button
- Backup button
- Cloud status rendering

It used `SettingsController`.

### Flutter responsibility

`lib/views/settings_view.dart` defines `SettingsView`.

It renders the same settings page using:

- `Scaffold`
- `AppBar`
- `DropdownButtonFormField`
- `SwitchListTile`
- `SelectableText`
- `ElevatedButton.icon`
- `SettingsController`

Cloud UI is preserved, but Google Drive functionality remains deferred because `core/cloud_storage.py` is deferred.

### Preserved behavior

- Route remains `/settings`.
- AppBar title remains `設定`.
- Appearance section title remains `外觀設定`.
- Theme label remains `選擇主題`.
- Theme options remain:
  - `跟隨系統`
  - `淺色模式`
  - `深色模式`
- Pure black title remains `純黑模式 (AMOLED)`.
- Pure black subtitle remains `在深色模式下使用純黑背景以節省手機電量`.
- Cloud section title remains `雲端同步 (Google Drive)`.
- Cloud description text is preserved.
- Initial cloud status remains `狀態：尚未登入`.
- Login button text remains `1. 登入 Google`.
- Logout button text remains `登出`.
- Backup button text remains `2. 開始備份`.
- Cloud UI state is still rendered from controller state maps.

### Required differences

- Flet `ft.View` was replaced with Flutter `StatefulWidget`.
- Flet `Dropdown` was replaced with `DropdownButtonFormField`.
- Flet `Switch` + `ListTile` was replaced with `SwitchListTile`.
- Flet `page.update()` was replaced with `setState`.
- Flet button icons were replaced with Flutter `Icons`.
- Google Drive UI is preserved, but real cloud logic is deferred until `core/cloud_storage.dart` is migrated.
