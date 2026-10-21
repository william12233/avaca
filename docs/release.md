# AVACA Release 發布規則

AVACA 1.0.0 起維持單一的本地收藏產品。發布流程參考 Wynime：推送一個
與版本一致的 tag，GitHub Actions 建置 Android 與 Windows 兩個平台，產生
版本化資產後直接建立正式 GitHub Release。播放器、遠端 Server、配對與
額外產品不再進入發布流程。

實際流程由 [`.github/workflows/release.yml`](../.github/workflows/release.yml)
執行；任何版本或資產不一致都必須使 workflow 失敗。

## 版本與 Tag

- Release Tag 必須是 `vX.Y.Z`，例如 `v1.0.0`。
- Tag 去掉 `v` 後必須等於 `pubspec.yaml` 的版本主體。
- `pubspec.yaml` 的 `+build` 值就是 Android `versionCode`，每次正式版必須遞增。
- 只發布正式版，不使用 draft 或 prerelease。

## GitHub Release 資產

Release 必須且只能由下列四個 workflow 資產組成；`X.Y.Z` 取自 tag：

| 平台 | 資產 | SHA-256 sidecar |
| --- | --- | --- |
| Android ARM64 | `avaca-X.Y.Z-arm64-v8a.apk` | `avaca-X.Y.Z-arm64-v8a.apk.sha256` |
| Windows x64 portable | `avaca-X.Y.Z.zip` | `avaca-X.Y.Z.zip.sha256` |

命名固定使用小寫 `avaca`、完整三段 SemVer 與版本化檔名；不得上傳
`app-release.apk`、未帶版本的 ZIP 或其他替代資產。GitHub 自動產生的 source
archive 不屬於 workflow 資產清單。

## Windows portable 內容

`avaca-X.Y.Z.zip` 解壓後必須包含完整 Flutter bundle、`avaca.exe`、
`avaca_update.exe` 與內容為 `X.Y.Z` 的 `version.txt`。更新器會先驗證
GitHub Release 的 SHA-256 與 ZIP 內容，再替換程式；收藏資料仍保存在
`%LOCALAPPDATA%\AVACA`，不會被更新覆寫。

## 發布方式

1. 更新 `pubspec.yaml` 的版本與遞增 build number。
2. 建立並推送對應的 `vX.Y.Z` tag。
3. 由 `release.yml` 建置兩個平台、產生 checksum 並發布 GitHub Release。
4. 以 workflow 的資產清單與 checksum 驗證結果作為發布完成條件；不要手動補檔或改名。
