---
name: uap
description: "Ship reviewed changes — 同步受影響文檔（CLAUDE.md/STATUS.md/docs）、依 Conventional Commits 一致提交，再依該 repo 的 branch-protection 流程 push 或開 PR。Use after code review when finalizing or submitting changes, or when the user says 「uap」「ship」「提交」「送 PR」「update and push」「推上去」. Branches first on protected default branches; never pushes to the default branch directly and never merges PRs."
user-invocable: true
disable-model-invocation: true
argument-hint: "[repo|.] [module...]"
allowed-tools: Bash, Read, Glob, Grep, Edit
---

# UAP — Ship Reviewed Changes

把（通常已通過 review 的）變更收尾送出：偵測狀態 → 依 repo 流程定路徑（**branch 先決，先於 commit**）→ 同步必要文檔 → adaptive 提交 → 依 protection 走 PR 或直接 push。支援跨 repo。銜接 `/deep-review` 結尾（feature branch + 乾淨 commit + 未 push）。

**Violating the letter of the rules below is violating their spirit.** Do not rationalize around them.

開始前**複製這份 checklist 進回應**並逐項勾選：

```
UAP 進度：
- [ ] Step 0：多 repo 偵測（單 repo 跳過）
- [ ] Step 1：逐 repo 狀態 + 流程偵測（default branch / 變更集 / protection / ship 路徑 / branch-first）
- [ ] Step 2：同步受影響文檔
- [ ] Step 3：adaptive 提交（未 commit→code+docs 同 commit；已 commit→獨立 docs commit）
- [ ] Step 4：印 ship 摘要 → 等使用者確認（無確認 → STOP）
- [ ] Step 5：依路徑送出（PR 或直接 push）；輸出 PR URL / push 結果
```

## Critical — Guardrails

These are hard constraints. Read them before touching git.

- **NEVER push without explicit user confirmation.** Always show the Step 4 ship summary first and wait for an affirmative reply. No confirmation → STOP.
- **NEVER push to the default / protected branch directly.** On a protected default branch, open a PR instead.
- **NEVER merge the PR.** Opening a PR ≠ merging it. Merge only on an explicit user instruction.
- **Branch FIRST, before any commit.** If changes must be committed while `HEAD` is the default branch and the ship path is PR (or protection is on/unknown), create a feature branch **before** committing — not at push time.
- **Unknown protection = protected.** If `gh` is missing or the protection query fails, treat the default branch as protected (PR path). Do not assume it is open.

### Rationalization table — STOP if you hear yourself say these

| Excuse | Reality |
|--------|---------|
| "User said push, so push to main." | "push" means push the *feature branch*. A protected default branch needs a PR. |
| "The PR is open now, might as well merge it." | Opening ≠ merging. Merge only on an explicit, separate instruction. |
| "Docs are already committed on main, just push them." | You should have branched first. Move the commit to a feature branch; never push to protected main. |
| "Can't detect protection, so it's probably fine to push to main." | Unknown protection → treat as protected. Branch + PR, or stop and ask. |
| "Branching now is extra work; commit here first, move later." | Branch-first is one command and prevents an awkward main commit. Do it before the commit, every time. |
| "It's just a docs commit, the protection won't mind." | Protection does not care what the commit is. Same rules. |

### Red Flags — STOP and re-read Critical

- About to run `git push origin <default-branch>` or `git push` while on the default branch.
- About to run `gh pr merge` / any merge.
- About to `git commit` while `HEAD == default branch` without having branched.
- About to push without having shown the Step 4 summary and received confirmation.

---

## Step 0：範圍鎖定

### 引數前處理（repo 鎖定）

`$ARGUMENTS` 第一個 token 若是 **repo 指定**，直接鎖定該 repo、**跳過下方多 repo 偵測互動**；其餘 token 當 module 過濾（Step 2 用）。判定第一個 token 是否為 repo：

- `.` → pwd 所在的 git repo 根（`git rev-parse --show-toplevel`）。
- 含 `/` 或可解析為 git repo 的路徑 → 該 repo。
- 否則比對 session 記憶中的 repo 根 basename（如 `krepo`、`dotfiles`）→ 命中即該 repo。
- 都不命中 → 第一個 token 也當 module，走下方多 repo 偵測。

鎖定單一 repo 後 → 直接進 Step 1（不問多 repo 清單）。

### 多 Repo 偵測（無 repo 引數時）

依本 session 記憶列出所有涉及變更的 repo（**不掃 `~/Projects/`**）：

1. 回憶 session 中改過檔案的所有 repo 根目錄 + pwd 所在 repo。
2. 每個 repo 跑 `git -C <repo> status --porcelain` 與 `git -C <repo> log --oneline @{upstream}..HEAD 2>/dev/null` 確認狀態。
3. 展示清單等使用者確認（ok / 只看 X / 還有 Y）：
   ```
   本次涉及 2 個 repo：
     1. krepo（2 commit 未 push）
     2. pilot-api（3 檔未提交）
   一起 ship？或需要調整？
   ```
4. context 被壓縮 → 以 pwd 的 repo 為底讓使用者補充；使用者指定的 repo 即使無變更也納入。
5. 全部 repo 既無未 push commit 又無 working tree 變更 → 告知並結束。
6. **單一 repo → 跳過此步，直接 Step 1。**

## Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）

對每個 repo：

1. **default branch**：`git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null`（取 basename）；失敗則依序試 `main`、`master`。
2. **變更集**：已 commit 未 push（`git -C <repo> log --oneline origin/<default>..HEAD`）+ working-tree（`git -C <repo> diff --name-only HEAD`）。合併為完整清單。無變更 → 跳過此 repo。
3. **branch protection**（classic + ruleset 都查；細節見 `references/ship-paths.md`）：
   - `gh api repos/{owner}/{repo}/branches/{default}/protection`（classic）+ `gh api repos/{owner}/{repo}/rules/branches/{default}`（ruleset）。
   - classic 回 200 **或** ruleset 非空 → **protected**。
   - classic 回 404「Branch not protected」**且** ruleset = `[]` → **確定無保護**。
   - 其他錯誤（403 / 網路 / 無 gh，無法分辨）→ **未知 → 視為 protected**（Unknown = protected）。
4. **決定 ship 路徑**：protected（或未知）→ **PR 路徑**；確定無保護 → **直接 push 路徑**。
5. **Branch-first（無條件，依全域「if on default branch, branch first」）**：只要「有變更要 commit」且「當前 branch == default branch」→ **立刻開 feature branch**（**不論 protection**）：`git -C <repo> switch -c <type>/<slug>`（type 取自變更語意 feat/fix/docs…，slug kebab-case）。working-tree 變更會跟著切過去。已在 feature branch（如 deep-review 結尾）→ 跳過。
   - 若變更**已誤 commit 在本地 default branch**（且未 push）：先 `git switch -c <feature>` 保住 commit，再回 default branch `git reset --hard origin/<default>`。詳見 `references/ship-paths.md`。
6. **Squash 提醒**：未 push commit 中若有連續 `fix:`/`refactor:`（review 迭代痕跡）→ 提醒使用者考慮先 squash 再繼續（deep-review 正常已 squash，通常無需）。

## Step 2：同步受影響文檔

由**完整變更集**（已 commit + 未 commit）識別涉及模組，更新文檔（防禦原則：**先讀、只改相關段落、無需更新就跳過，不硬塞**）：

- 涉及模組的 `**/CLAUDE.md`（只動受影響的）。
- `STATUS.md`（存在且有里程碑變動時）。
- 相關 `docs/plans/*.md`（存在時）。
- 所有更動文檔頂部的 `updated` 日期改為今天（YYYY-MM-DD）。
- `$ARGUMENTS` 中（repo token 之後的）module 名 → 限縮文檔掃描範圍。

## Step 3：Adaptive 提交

依 reviewed code 的狀態決定文檔如何「一起提交」：

- **code 未 commit**（review 在 working tree）：`git add` 程式 + 文檔 → 一個或多個語意 commit（Conventional Commits），code 與其文檔**同 commit**。
- **code 已 commit**（如 deep-review 已 squash）：文檔另起 `docs: …` commit，**同 branch**（同 PR 一起出）。**不 amend、不重寫已 review 的 commit。**
- 無文檔需更新且 code 已 commit → 本步不產生 commit。

commit message 用 Conventional Commits，附 trailer：
```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

## Step 4：Ship 摘要 → 確認（critical-op gate）

push **之前**，逐 repo 印摘要等使用者確認（plan → validate → execute）：

```
Ship 摘要：
  krepo  路徑=PR（main 受保護）
    feature branch: feat/mops-announce-backfill
    待 push commit: 2 feat + 1 docs
    變更檔: src/..., scripts/..., CLAUDE.md
    PR: feat/... → main（將開，不 merge）
確認送出？
```

**無確認 → STOP。** 這是硬 gate（見 Critical）。

## Step 5：依路徑送出

確認後逐 repo 執行（完整指令序列見 `references/ship-paths.md`）：

- **PR 路徑**：`git -C <repo> push -u origin <feature-branch>` → 偵測既有 PR（`gh pr view`）：有則指向、無則 `gh pr create`（title/body 由 commits 組；deep-review 的「第三方審查資訊」若有一併放進 body）。輸出 PR URL。**不 push default branch、不 merge。**
- **直接 push 路徑**（確定無保護）：push **當前 branch**（branch-first 後通常是 feature branch）：`git -C <repo> push`（無 upstream → `-u origin <branch>`）。在 feature branch 時可**附帶提示**是否開 PR（不強制；尊重「無保護→直接 push」）。push 失敗：remote 有新 commit → 提示 `git pull --rebase` 後重試。
- 多 repo：逐 repo 送出，最後彙總（各 repo 的 PR URL / push 結果）。

---

## 設計備忘

- 本 skill 是 **ship 階段**，不自己跑 review。大變更未審查 → 建議使用者先 `/deep-review`，但不強制。
- 與 `/deep-review` 銜接：deep-review 結尾 = feature branch + 乾淨 commit + 未 push → 本 skill 多走 Step 2（docs）+ Step 4/5（ship）。
- 詳細 git/gh 指令與邊界 → `references/ship-paths.md`；紀律驗收情境 → `references/pressure-tests.md`。
