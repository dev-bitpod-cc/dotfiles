---
name: uap
description: "Ship reviewed changes — 同步受影響文檔（CLAUDE.md/STATUS.md/docs）、依 Conventional Commits 一致提交，再依該 repo 的 branch-protection 流程 push 或開 PR。Use after code review when finalizing or submitting changes, or when the user says 「uap」「ship」「提交」「送 PR」「update and push」「推上去」. Branches first whenever committing on the default branch (or a detached HEAD); never pushes to the default branch directly and never merges PRs."
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
- **Branch FIRST, before any commit.** If changes must be committed while `HEAD` is the default branch (or detached), create a feature branch **before** committing — not at push time. This is unconditional: do it regardless of protection state (see Step 1, item 5), even when protection is confirmed off.
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
- About to `git commit` while `HEAD == default branch` **or detached HEAD** without having branched.
- About to push without having shown the Step 4 summary and received confirmation.

---

## Step 0：範圍鎖定

### 引數前處理（repo 鎖定）

`$ARGUMENTS` 第一個 token 若是 **repo 指定**，直接鎖定該 repo、**跳過下方多 repo 偵測互動**；其餘 token 當 module 過濾（Step 2 用）。判定第一個 token 是否為 repo：

- `.` → pwd 所在的 git repo 根（`git rev-parse --show-toplevel`）。
- **解析得到 git repo 根**的路徑（`git -C <token> rev-parse --show-toplevel` 成功，且 `realpath <token>` == 該 toplevel 輸出——**兩端都正規化後比對，勿裸字串比對**：`--show-toplevel` 回傳已解 symlink 的絕對路徑，token 可能是相對路徑/含 symlink，直接比字串會 false-negative；相等即指向 repo 根、非子目錄）→ 該 repo。**僅含 `/` 不足以判定 repo**——`docs/plans`、`knowledge-commander/`、`src/foo` 這類 module/子路徑 scope 同樣含 `/`，會解析到所屬 repo 根（≠ token 本身）→ 不鎖定，續當 module。
- 否則比對 session 記憶中的 repo 根 basename（如 `krepo`、`dotfiles`）→ 命中即該 repo。
- 都不命中 → 第一個 token 也當 module，走下方多 repo 偵測。

鎖定單一 repo 後 → 直接進 Step 1（不問多 repo 清單）。

### 多 Repo 偵測（無 repo 引數時）

依本 session 記憶列出所有涉及變更的 repo（**不掃 `~/Projects/`**）：

1. 回憶 session 中改過檔案的所有 repo 根目錄 + pwd 所在 repo。
2. 每個 repo 跑 `git -C <repo> status --porcelain` 與 `git -C <repo> log --oneline origin/<default>..HEAD 2>/dev/null` 確認狀態（`<default>` = origin 預設分支、`origin` 為 canonical remote 的 stand-in（無 `origin` 取第一個 remote），同 Step 1 remote 假設；**勿用 `@{upstream}`**——未設 upstream 的 feature branch 會 error 被 `2>/dev/null` 靜默吞掉，把 deep-review 交接的 clean-tree feature branch 誤判為「無變更」而漏掉）。
3. 展示清單等使用者確認（ok / 只看 X / 還有 Y）：
   ```
   本次涉及 2 個 repo：
     1. krepo（領先 default 2 commit）
     2. pilot-api（3 檔未提交）
   一起 ship？或需要調整？
   ```
4. context 被壓縮 → 以 pwd 的 repo 為底讓使用者補充；使用者指定的 repo 即使無變更也納入。
5. 全部 repo 既無領先 default 的 commit 又無 working tree 變更 → 告知並結束。
6. **單一 repo → 跳過此步，直接 Step 1。**

## Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）

> **remote 假設**：下文一律以 `origin` 書寫，代表「canonical remote」的 stand-in。**非 origin repo**：把下文所有 `origin` 讀作你解析出的 remote（`git -C <repo> remote`；有 `origin` 用之、否則取第一個）；無任何 remote → 停下告知使用者。**fork 工作流**（push 目標 = writable fork、PR/protection 查詢目標 = upstream，兩者為不同 remote）**本 skill 不自動分辨**——遇 fork 場景在 Step 4 摘要明列兩個 remote、由使用者確認，**不擅自對 fork 開 PR、不對唯讀 upstream push**。**host 假設**：本 skill 假設 GitHub.com（`gh` 走 authenticated default host、compare URL 用 `github.com`）；GitHub Enterprise / 自架站台需設 `GH_HOST` 並以 `host/owner/repo` 形式綁 `-R`，**不在本 skill 自動處理範圍**（SSH alias 如 `git@github-work:` 仍指向 github.com，照常適用）。

對每個 repo：

1. **default branch**：`git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null`（取 basename）；失敗則依序試 `main`、`master`。
2. **變更集**（= 此 branch **相對 default 的變更**，即 PR 將含的內容；**不等於「未 push」**——已 push 到 feature branch upstream 的 commit 仍落在此範圍，push 狀態由 Step 5 處理且 push 為冪等）：branch 帶來的**檔案**（`git -C <repo> diff --name-only origin/<default>...HEAD`，**三點**——以 merge-base 計，只列 branch 自切出後自身帶來的變更；用兩點 `..` 會在上游前進後混入他人檔。commit 主旨另用 `git -C <repo> log --oneline origin/<default>..HEAD`，**兩點**——列「在 HEAD、不在 origin/<default>」的 commit；`log` 只有主旨、無檔名，deep-review 交接的「clean tree + 只剩 branch commit」情境下必須靠 `diff --name-only` 才列得出檔）+ working-tree **含 untracked**（`git -C <repo> status --porcelain`——`git diff --name-only HEAD` 會漏掉新增的 untracked 檔，與 Step 0 一致用 porcelain）。合併為完整**檔案**清單（Step 2 判模組、Step 4 列變更檔都靠它）。無變更 → 跳過此 repo。
3. **branch protection**（classic + ruleset 都查；細節見 `references/ship-paths.md`）：
   - `gh api repos/<owner>/<repo>/branches/<default>/protection`（classic）+ `gh api repos/<owner>/<repo>/rules/branches/<default>`（ruleset）。**`<owner>/<repo>/<default>` 用偵測到的實際值代入**——`gh api` 只替換 `{owner}`/`{repo}`/`{branch}`、**不認 `{default}`**，且多 repo 時 `{owner}/{repo}` 會依 cwd 解析到錯 repo。完整可執行版見 `references/ship-paths.md`。
   - classic 回 200 **或** ruleset 非空 → **protected**。
   - classic 回 404「Branch not protected」**且** ruleset = `[]` → **確定無保護**。
   - 其他錯誤（403 / 網路 / 無 gh，無法分辨）→ **未知 → 視為 protected**（Unknown = protected）。
4. **決定 ship 路徑**：protected（或未知）→ **PR 路徑**（推 feature branch + 必開 PR）；確定無保護 → **直接 push 路徑**（推 feature branch，PR 可選）。**兩條路徑都推 feature branch、都不直推 default**（branch-first 無條件）——「直接 push」指**省去開 PR 的步驟、直接 push 該 branch**，不是直推 default。把變更合進 default branch 一律是**使用者**的事（agent 不 merge、不直推 default）。
5. **Branch-first（無條件，依全域「if on default branch, branch first」）**：目標——**到 Step 5 送出前，當前 branch 一定不是 default branch（也不是 detached HEAD）**，**不論 protection**。已在 feature branch（如 deep-review 結尾）→ 跳過。否則依狀態二擇一：
   - **當前在 default branch 或 detached HEAD，變更尚未 commit，或已 commit 在 detached HEAD 上**（情況 A）→ `git -C <repo> switch -c <type>/<slug>`（type 取自變更語意 feat/fix/docs…，slug kebab-case）：working-tree 變更跟著切過去，**detached HEAD 上已有的 commit 也一併被新 branch 接走**（不需情況 B 的 ref 重置——detached HEAD 不移動任何 branch ref）。在 default branch 上時務必**commit 之前**先做。
   - **變更已誤 commit 在本地 default branch**（且未 push，**無論是否還有未 commit 變更**）（情況 B）→ `git -C <repo> branch <feature>` 保住 commit → `git -C <repo> switch <feature>` → `git -C <repo> branch -f <default> origin/<default>` 把本地 default 退回 remote。**不 checkout default、不 `reset --hard`**——mixed state（部分已 commit、部分還在 working tree）下切回 default 再 hard reset 會永久銷毀未 commit 變更。完整序列見 `references/ship-paths.md` 情況 B。
   > 做完此步，**Step 5 一律推 feature branch，絕不直推 default branch**——即使確定無保護（branch-first 無條件，「無保護→直接 push」推的也是 feature branch，不是 default）。
6. **Squash 提醒**：branch 上若有連續 `fix:`/`refactor:`（review 迭代痕跡）→ 提醒使用者考慮先 squash 再繼續（deep-review 正常已 squash，通常無需；已 push 的 commit squash 後 push 需 `--force-with-lease`）。

## Step 2：同步受影響文檔

由**完整變更集**（已 commit + 未 commit）識別涉及模組，更新文檔（防禦原則：**先讀、只改相關段落、無需更新就跳過，不硬塞**）：

- 涉及模組的 `**/CLAUDE.md`（只動受影響的）。
- `STATUS.md`（存在且有里程碑變動時）。
- 相關 `docs/plans/*.md`（存在時）。
- 所有更動文檔頂部的 `updated` 日期改為今天（YYYY-MM-DD）。
- `$ARGUMENTS` 中（repo token 之後的）module 名 → 限縮文檔掃描範圍。

## Step 3：Adaptive 提交

依 reviewed code 的狀態決定文檔如何「一起提交」。**前提：送出前所有 reviewed code 都必須已 commit**——working tree 不留未 commit 的 code，否則 Step 5 會送出不完整變更集。

- **code 未 commit**（review 在 working tree）：`git add` 程式 + 文檔 → 一個或多個語意 commit（Conventional Commits），code 與其文檔**同 commit**。
- **code 已 commit**（如 deep-review 已 squash）：文檔另起 `docs: …` commit，**同 branch**（同 PR 一起出）。**不 amend、不重寫已 review 的 commit。**
- **mixed state**（部分 code 已 commit、部分仍在 working tree——如 Step 1 情況 B 搬移後又改了東西）：**先**把 working-tree 的 code 補成語意 commit（與已 commit 的同 branch），**不可只補 `docs:` commit 就送出、把未 commit 的 code 留在 working tree**；code 全部 commit 後再依「code 已 commit」處理文檔。
- 無文檔需更新且 code 已 commit → 本步不產生 commit。

commit message 用 Conventional Commits，附環境指定的 `Co-Authored-By` trailer（以 runtime system prompt 的 Git 區塊為權威，**勿在 skill 寫死 model 名稱/版本**——它每次升 model 就漂移）。

## Step 4：Ship 摘要 → 確認（critical-op gate）

push **之前**，逐 repo 印摘要等使用者確認（plan → validate → execute）：

```
Ship 摘要：
  krepo  路徑=PR（main 受保護）
    feature branch: feat/mops-announce-backfill
    branch commit（相對 default，= PR 內容）: 2 feat + 1 docs（push 為冪等，已 push 則 no-op）
    變更檔: src/..., scripts/..., CLAUDE.md
    PR: feat/... → main（將開，不 merge）
確認送出？
```

**無確認 → STOP。** 這是硬 gate（見 Critical）。

## Step 5：依路徑送出

確認後逐 repo 執行（完整指令序列見 `references/ship-paths.md`）：

- **PR 路徑**：`git -C <repo> push -u origin <feature-branch>` → 偵測既有 PR（`gh pr view`，多 repo 須 `-R <owner/repo>` 綁定）：有則指向、無則 `gh pr create`（同樣 `-R` 綁定；title/body 由 commits 組；deep-review 的「第三方審查資訊」若有一併放進 body）。完整綁定指令見 `references/ship-paths.md`。輸出 PR URL。**不 push default branch、不 merge。**
- **直接 push 路徑**（確定無保護）：push **當前 branch**（branch-first 無條件，故此處一定是 feature branch、非 default）：`git -C <repo> push -u origin <feature-branch>`（**顯式 remote + branch**，不用裸 `git push`——裸 push 受 `push.default` / `remote.pushDefault` / 非預期 upstream 影響，可能推到錯 remote 或多推 ref；`origin` 為 stand-in）。在 feature branch 時可**附帶提示**是否開 PR（不強制；尊重「無保護→直接 push」）。
- 多 repo：逐 repo 送出，最後彙總（各 repo 的 PR URL / push 結果）。
- push 失敗處理（`rejected` / 無 upstream / gh 未登入）→ 見 `references/ship-paths.md`「push 失敗處理」（單一來源）。

---

## 設計備忘

- 本 skill 是 **ship 階段**，不自己跑 review。大變更未審查 → 建議使用者先 `/deep-review`，但不強制。
- 與 `/deep-review` 銜接：deep-review 結尾 = feature branch + 乾淨 commit + 未 push → 本 skill 多走 Step 2（docs）+ Step 4/5（ship）。
- 詳細 git/gh 指令與邊界 → `references/ship-paths.md`；紀律驗收情境 → `references/pressure-tests.md`。
