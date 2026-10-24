# AVACA UI 開發規範

這份文件是 AVACA UI 的圓角與框線單一規則。目標是讓外框和內部控制項在所有頁面、尺寸與彈窗中保持一致。

## 真正的來源

請不要在頁面裡自行建立一套圓角數值。使用以下兩個來源：

- [`lib/core/shapes.dart`](../lib/core/shapes.dart)：全域元件與非響應式頁面的形狀 token。
- [`lib/core/layout.dart`](../lib/core/layout.dart)：依可用寬度變化的版面 token。

全域 Material 預設也已在 [`lib/core/config.dart`](../lib/core/config.dart) 套用這些規則。

## 圓角規則

| 使用情境 | 應使用的 token | 目前值 |
| --- | --- | ---: |
| 一般卡片、頁面區塊、非響應式外框 | `AppShapeTokens.defaultCardRadius` | 12 |
| 一般輸入框 | `AppShapeTokens.inputRadius` | 12 |
| 下拉選單、PopupMenu | `AppShapeTokens.popupMenuRadius` | 12 |
| Dialog、BottomSheet 及其同一視覺外框內的控制項 | `AppShapeTokens.dialogRadius` | 28 |
| 會依 compact／expanded 改變大小的卡片或面板 | `tokens.cardRadius`（由 `AppLayoutPolicy.resolve` 取得） | 12／16 |

## 內外框對齊

如果元件是在某個外框裡，且兩者屬於同一個視覺框架，內部框線的圓角必須跟外框一致：

```dart
final tokens = AppLayoutPolicy.resolve(constraints);

Card(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(tokens.cardRadius),
  ),
  child: TextField(
    decoration: InputDecoration(
      // 內部控制項與外層卡片對齊
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
    ),
  ),
);
```

Dialog 也同樣處理：外框使用 `AppShapeTokens.dialogRadius`，其內若有作為該框線一部分的輸入框、按鈕或下拉選單，也使用同一個 token。不要在外框是 12 或 28 時，另外放入 6、8、10 等未命名圓角。

圖片若是外框的全出血內容，也要使用外框圓角。只有縮圖、頭像或刻意內縮的裝飾性圖片可以有不同圓角；這種例外必須在程式碼留下原因。

## 設定頁控制項規則

- 同一個設定頁的選項列、輸入框、下拉選單與操作按鈕，使用 `AppLayoutTokens.controlHeight`，目前固定為 48px。
- 動態狀態、進度、錯誤與資料摘要可以讓列高自然增加；這些不是固定說明文字。
- 靜態補充說明不要放在 `subtitle` 常駐顯示，改用 [`AppHelpTooltip`](../lib/components/app_help_tooltip.dart) 放在選項文字前。手機單擊問號顯示，桌面滑鼠移入顯示。
- 設定分類以「主題與色彩」、「介面」、「刮削設定」、「資料管理」、「系統與關於」分組；新增選項先放入對應分類，不在主頁堆疊細節。

## 新增 UI 時的檢查

1. 先判斷元件的外層視覺框架，取得對應的 shape token。
2. 將同一框架內的 border、enabled／focused border、按鈕、下拉選單與全出血圖片全部對齊該 token。
3. 搜尋新增程式碼，確認沒有未命名的 `BorderRadius.circular(數字)` 或 `radius: 數字`。
4. 若是例外，使用具語意的常數、註解原因，並以 widget test 或 golden test 固定行為。
5. 至少執行 `flutter analyze` 與受影響的 widget tests。
