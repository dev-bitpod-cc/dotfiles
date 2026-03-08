---
description: "更新專案文件並推送至 remote — 自動偵測變更範圍，更新相關 CLAUDE.md / STATUS.md / docs，然後 commit + push"
user-invocable: true
disable-model-invocation: true
argument-hint: "[module...]"
allowed-tools: Bash, Read, Glob, Grep, Edit
---

# Update And Push

更新專案文件並推送至 remote。支援跨 repo 操作——逐 repo 處理文件更新與 commit，最後統一推送。

## 步驟

### 0. 識別 Repo 範圍（多 Repo 偵測）

主 agent 根據本 session 的記憶，列出所有涉及變更的 repo：

1. 回憶本 session 中修改過檔案的所有 repo 根目錄
2. 加上 pwd 所在的 repo
3. 對每個 repo 執行 `git status --porcelain` 和 `git log --oneline @{upstream}..HEAD 2>/dev/null` 確認變更狀態
4. 向使用者展示清單並等待確認：

```
本次涉及 2 個 repo：
  1. rag-platform（3 檔案未提交 + 2 commit 未 push）
  2. rag-platform-deploy（5 檔案未提交）
一起處理？或需要調整？
```

5. 使用者可：確認（ok）、限縮（只推 X）、擴充（還有 Y）
6. 若 context 被壓縮導致記憶不完整，以 pwd 的 repo 為底，讓使用者補充
7. **單一 repo** → 跳過此步驟，直接進入 Step 1
8. 若所有 repo 都沒有未 push commit 且無 working tree 變更，告知使用者並結束

### 1. 前置檢查（逐 repo）

對每個 repo 依序執行：

- 偵測未 push 的變更：`git -C <repo> diff --name-only @{upstream}...HEAD`（fallback：無 upstream 時用 `origin/main`）
- 偵測 working tree 變更：`git -C <repo> diff --name-only HEAD`
- 合併兩者為完整變更檔案清單
- `git -C <repo> log --oneline @{upstream}..HEAD` 列出所有未 push 的 commit
- 若該 repo 無變更，跳過
- **Squash 提醒**：若未 push 的 commit 中有連續的 fix/refactor commit（review 迭代痕跡），提醒使用者考慮先 squash 再繼續
- **Squash 時機**：所有 repo 的前置檢查完成後，若有任何 repo 需要 squash，統一在此步驟處理完畢再進入 Step 2。避免 docs commit 蓋在未 squash 的 commit 上面

### 2. 偵測變更範圍（逐 repo）

- 根據完整變更檔案清單（已 commit + 未 commit），識別涉及的模組
- 掃描該 repo 中所有 `**/CLAUDE.md`，判斷哪些屬於受影響模組
- 若 `$ARGUMENTS` 有指定模組名，則限縮範圍

### 3. 更新文件（逐 repo）

- 更新涉及模組的 CLAUDE.md（僅更新受影響的，不動其他的）
- 更新 STATUS.md（如檔案存在且有里程碑變動）
- 更新相關 docs/plans/*.md（如檔案存在）
- 所有文件的 `updated` 日期欄位更新為今天（格式：YYYY-MM-DD）

### 4. 提交（逐 repo）

- 若有文件需更新：`git -C <repo> add` 僅加入文件類檔案（CLAUDE.md、STATUS.md、docs/），commit message：`docs: 更新專案文件（涉及模組列表）`
- 若無文件需更新：跳過 commit

### 5. 統一推送

處理完所有 repo 後，統一顯示摘要並推送：

```
推送摘要：
  rag-platform
    - 3 commits 待推送
    - 變更：src/env.ts, src/config/registry.ts, CLAUDE.md
  rag-platform-deploy
    - 2 commits 待推送
    - 變更：scripts/configure.sh, scripts/init.sh, CLAUDE.md

確認推送？
```

- 使用者確認後，逐 repo 執行 `git -C <repo> push`
- push 失敗處理：remote 有新 commit → 提示 `git pull --rebase`；無 upstream → 提示 `git push -u origin <branch>`
