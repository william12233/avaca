# GitHub 同步與分支工作規則

本規則適用於本專案每一次實作、修改或修復任務，也適用於同一 Cloud 任務中的每一個新的實作回合。GitHub 遠端目標分支上已提交的程式碼是工作基準；Cloud 工作區不是獨立的真實來源。不得在已知工作區落後於目標分支時，直接以舊程式碼繼續實作。

## 每一回合開始前的同步閘門

在讀取或修改應用程式碼前，必須重新完成以下流程；不得依賴前一回合、另一個 Cloud 工作區或先前對話中的檢查結果：

1. 先在專案根目錄讀取目前狀態與分支關係，至少檢查：

   ```sh
   git status --short --branch
   git rev-parse HEAD
   git branch --show-current
   git symbolic-ref --short -q HEAD
   git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
   git branch -vv
   git remote -v
   ```

   需要辨識目前 HEAD、目前分支或 detached HEAD、upstream、所有相關 remote，以及本次任務真正的目標分支（例如目前分支的 upstream 或未合併 PR 的 head/base 關係）。不得因慣例擅自假設目標一定是 `main`；遠端預設分支只能在實際查證後作為資訊，不能取代任務目標分支的判定。

2. 執行遠端更新：

   ```sh
   git fetch origin --prune
   ```

   若目標分支未被現有 fetch refspec 取得，必須在不改寫工作成果的前提下補取該分支，並記錄實際比較的 remote ref。

3. 比較本地 HEAD、目標分支的遠端追蹤 ref，以及必要時的遠端預設分支。至少確認提交關係與是否分歧，例如：

   ```sh
   git rev-list --left-right --count HEAD...refs/remotes/origin/<target>
   git merge-base --is-ancestor HEAD refs/remotes/origin/<target>
   git merge-base --is-ancestor refs/remotes/origin/<target> HEAD
   ```

   明確分類為相同、工作區落後、工作區超前或分歧；遠端追蹤 ref 不存在、目標不明或比較結果不可信時，視為無法安全同步，不得繼續以猜測的版本實作。

4. 只有在工作區乾淨、目前位於正確的追蹤分支，且同步可以 fast-forward 時，才使用：

   ```sh
   git pull --ff-only
   ```

   若已經與目標分支相同，確認為 no-op 即可。若目前分支沒有 upstream，不能自行把它綁到 `main` 或其他分支；在目標已明確且確認不會覆蓋本地成果時，才可使用對應的明確 remote ref 進行 fast-forward。同步完成後記錄開始實作時的 commit。

## 無法直接 fast-forward 時的安全處理

- 有未提交或已 staged 的變更時，先保護現有工作並檢查 `git diff` 與 `git diff --cached`；不得直接 pull、覆蓋、丟棄或混入不屬於本任務的成果。可依實際分支關係建立非破壞性的 checkpoint、暫存或隔離分支；若仍無法安全整合，停止可能基於舊版的實作並明確回報阻礙。
- detached HEAD 時，先保護目前成果並確認真正目標分支；未完成安全分支定位前不得開始實作，也不得直接 checkout 覆蓋工作區。
- 工作區與目標分支分歧、同步會產生衝突，或存在未合併 PR 時，先辨識 PR 的 head 與 base 以及各自的提交關係，再選擇不遺失成果的整合方式。衝突、目標不明或需要改寫既有成果時，停止並回報，不得假設可以安全繼續。
- 工作區超前但沒有落後時，可在確認目標與任務範圍後繼續；必須清楚記錄本地超前提交，不能把它誤報成遠端已包含。
- 不同 Cloud 工作區不會自動同步；每個工作區、每個新回合都必須自行 fetch 和比較。

## 實作、驗證與推送

同步閘門成功且沒有衝突後，才開始本次任務。完成後執行與變更相稱的測試、lint、分析或其他驗證，並確認 `git status` 與 diff 只包含本任務的變更。

只有在使用者已授權推送、且實際確認具有該 remote 的推送權限時，才可推送。推送時使用已確認的目標分支，不得使用 force push；完成後必須用遠端實際 ref（例如 `git ls-remote origin refs/heads/<target>`）核對遠端提交與本地 HEAD 一致。推送功能分支或 PR head 不代表 `main` 已更新，回報時必須明確寫出實際推送的分支與提交。

## 禁止事項

除非使用者明確授權，不得為了同步而執行以下破壞性操作：

- `git reset --hard`
- 強制推送（包括 `--force` 或 `--force-with-lease`）
- 隨意刪除分支
- 清除、覆蓋或丟棄未提交修改
- 任何會改寫或隱藏既有成果、但尚未確認安全的 rebase、checkout 或清理操作

同步成功且沒有衝突時直接繼續任務，不必每次再次詢問使用者；只有遇到上述安全阻礙、目標分支不明、權限不足或需要額外授權時才停止。

## 最終回報

最終回報保持精簡，至少列出：實際使用的分支與目標分支、同步後（開始實作時）的起始 commit、實作與驗證結果、以及實際推送結果（未推送時明確寫明原因）。
