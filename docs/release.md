# AVACA Release 發布規則

這份文件是 AVACA 發布 GitHub Release 的命名與版本契約。
實際發布由 [`.github/workflows/release.yml`](../.github/workflows/release.yml)
執行；不符合以下規則時，workflow 必須失敗，不得發布不規則的資產。

## 版本與 Tag

- Release Tag 必須是 `vX.Y.Z`，例如 `v0.8.1`。
- Tag 的 `X.Y.Z` 必須與 `pubspec.yaml` 的版本完全一致。
- 只發布正式版，不使用 draft 或 prerelease 資產。
- Android 的 `versionName` 使用 `X.Y.Z`。
- `v0.8.0` 的歷史 APK 使用 `versionCode=30`；`v0.8.1` 使用
  `versionCode=2026`；`v0.8.2` 使用 `versionCode=2027`。從 `v0.8.1`
  開始，workflow 以 GitHub Release workflow run #6 對應 2026，之後每個
  正式 Release run 遞增 1（公式為
  `GITHUB_RUN_NUMBER + 2020`）。Android 不接受較小或重複的 `versionCode`
  作為更新。
- 同一個 Tag 重新執行 workflow 會保留同一個 `github.run_number`，只能更新同一個 GitHub Release；要發布新版本，必須使用新的 `vX.Y.Z` Tag。

## GitHub Release 資產檔名

Release 中的上傳資產必須且只能使用下列四個檔名。`X.Y.Z` 取自 Release Tag 去掉開頭的 `v`：

| 平台 | 正式資產 | SHA-256 sidecar |
| --- | --- | --- |
| Android ARM64 | `avaca-X.Y.Z-arm64-v8a.apk` | `avaca-X.Y.Z-arm64-v8a.apk.sha256` |
| Windows x64 portable | `avaca-X.Y.Z.zip` | `avaca-X.Y.Z.zip.sha256` |

例如 `v0.8.1` 必須產生：

```text
avaca-0.8.1-arm64-v8a.apk
avaca-0.8.1-arm64-v8a.apk.sha256
avaca-0.8.1.zip
avaca-0.8.1.zip.sha256
```

命名要求：

- 使用小寫 `avaca`。
- 版本使用完整三段 SemVer：`major.minor.patch`。
- 使用連字號 `-`，不使用空白、底線、日期或 `latest`。
- Android 架構固定寫成 `arm64-v8a`。
- Windows 資產固定使用 `.zip`，不加入額外架構字串。
- checksum 檔名必須是原資產檔名再加上 `.sha256`。
- 不上傳 `app-release.apk`、`avaca.zip`、未帶版本的檔案或其他替代命名。

GitHub Release 自動產生的 source code archive 不屬於上述上傳資產；本契約只管 workflow 上傳的四個檔案。

## Windows portable 內容

`avaca-X.Y.Z.zip` 解壓後必須包含完整 Windows Flutter bundle，以及：

- `avaca.exe`
- `avaca_update.exe`
- `version.txt`，內容必須是 `X.Y.Z`

Windows updater 由 `avaca_update.exe` 提供。AVACA 會先下載並驗證符合
`avaca-X.Y.Z.zip` 的正式資產，再將 ZIP 解壓到暫存資料夾；原生 helper 會等待
舊程式退出、以同目錄重新命名完成替換、驗證新程式啟動，失敗時復原原本的
portable bundle。資料庫與圖片位於 `%LOCALAPPDATA%\AVACA`，不在替換範圍內。

## 發布方式

1. 更新 `pubspec.yaml` 的 `X.Y.Z`。
2. 確認 Android 正式發布的 `versionCode` 會遞增。
3. 建立並推送對應的 `vX.Y.Z` Tag。
4. 由 `release.yml` 建立資產、checksum 並發布 GitHub Release。
5. 發布前的 workflow 檢查必須通過；不要手動改名或補上不符合規則的資產。
