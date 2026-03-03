更新專案文件並推送至 remote。

## 步驟

1. **前置檢查**
   - `git diff --name-only` + `git log --oneline -5` 確認本次 session 有變更
   - 若無變更，告知使用者並結束

2. **偵測變更範圍**
   - 根據變更檔案路徑，識別涉及的模組
   - 掃描專案中所有 `**/CLAUDE.md`，判斷哪些屬於受影響模組
   - 若 `$ARGUMENTS` 有指定模組名，則限縮範圍

3. **更新文件**
   - 更新涉及模組的 CLAUDE.md（僅更新受影響的，不動其他的）
   - 更新 STATUS.md（如檔案存在且有里程碑變動）
   - 更新相關 docs/plans/*.md（如檔案存在）
   - 所有文件的 `updated` 日期欄位更新為今天（格式：YYYY-MM-DD）

4. **提交並推送**
   - `git add` 僅加入文件類檔案（CLAUDE.md、STATUS.md、docs/）
   - commit message：`docs: 更新專案文件（涉及模組列表）`
   - 顯示本次 commit 的檔案清單摘要，然後 push
