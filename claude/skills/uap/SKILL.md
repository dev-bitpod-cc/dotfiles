---
description: "更新專案文件並推送至 remote — 自動偵測變更範圍，更新相關 CLAUDE.md / STATUS.md / docs，然後 commit + push"
user-invocable: true
disable-model-invocation: true
argument-hint: "[module...]"
allowed-tools: Bash, Read, Glob, Grep, Edit
---

# Update And Push

更新專案文件並推送至 remote。

## 步驟

1. **前置檢查**
   - 偵測未 push 的變更：`git diff --name-only @{upstream}...HEAD`（fallback：無 upstream 時用 `origin/main`）
   - 偵測 working tree 變更：`git diff --name-only HEAD`
   - 合併兩者為完整變更檔案清單
   - `git log --oneline @{upstream}..HEAD` 列出所有未 push 的 commit
   - 若兩者皆為空（無未 push commit 且無 working tree 變更），告知使用者並結束

2. **偵測變更範圍**
   - 根據完整變更檔案清單（已 commit + 未 commit），識別涉及的模組
   - 掃描專案中所有 `**/CLAUDE.md`，判斷哪些屬於受影響模組
   - 若 `$ARGUMENTS` 有指定模組名，則限縮範圍

3. **更新文件**
   - 更新涉及模組的 CLAUDE.md（僅更新受影響的，不動其他的）
   - 更新 STATUS.md（如檔案存在且有里程碑變動）
   - 更新相關 docs/plans/*.md（如檔案存在）
   - 所有文件的 `updated` 日期欄位更新為今天（格式：YYYY-MM-DD）

4. **提交並推送**
   - 若有文件需更新：`git add` 僅加入文件類檔案（CLAUDE.md、STATUS.md、docs/），commit message：`docs: 更新專案文件（涉及模組列表）`
   - 若無文件需更新：跳過 commit，直接進入 push
   - push 前顯示完整摘要（未 push commit 數量 + 變更檔案清單），等待使用者確認
   - push 失敗處理：remote 有新 commit → 提示 `git pull --rebase`；無 upstream → 提示 `git push -u origin <branch>`
