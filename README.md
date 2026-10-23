# AVACA

AVACA 1.1.0 是一個以本地資料為主的女優與作品收藏 App；本版本新增女優
熱門排行與發行商篩選收藏流程，不包含播放器、遠端 Server 或配對流程。

## Windows portable 版

Windows portable release 會包含完整的 Flutter 執行檔 bundle，以及
`avaca_update.exe` 原生更新 helper。從 AVACA「設定 → 其他 → 軟體更新」
按「立即更新」即可自動下載、驗證並替換 portable 程式檔，不需要安裝版。

更新 helper 會在替換程式前停止 AVACA，失敗時復原原本的程式 bundle，成功
後重新啟動 App。AVACA Windows 版的資料庫、圖片與設定位於：

    %LOCALAPPDATA%\AVACA

更新器不會刪除、搬移或覆寫這個資料夾，也不要求重新匯出或匯入收藏資料。
更新前會驗證 GitHub Release 提供的 SHA-256，並檢查 ZIP 路徑、版本與必要檔案。

## Release artifacts

完整的 Release 命名、Android versionCode 與 portable 內容規則請看
[`docs/release.md`](docs/release.md)。推送符合 `vX.Y.Z` 的 tag 後，GitHub
Actions 會驗證 tag 與 `pubspec.yaml` 版本一致，並且只建立以下四個固定命名
的上傳資產：

- `avaca-X.Y.Z-arm64-v8a.apk`
- `avaca-X.Y.Z-arm64-v8a.apk.sha256`
- `avaca-X.Y.Z.zip`
- `avaca-X.Y.Z.zip.sha256`
