---
name: project
description: "Project dossier & ship — 三模式：spec（開工：把 Context/Goal/AC/Constraints 寫入 STATUS.md dossier）、log（收尾：同步 dossier 與受影響文檔、依 Conventional Commits 提交，再依 repo 的 branch-protection 流程 push 或開 PR；為舊 /uap 的超集與繼任者）、transfer（移交：檢查 dossier 完整度、產出移交指南）。Use when starting a non-trivial work item (spec), finalizing or submitting reviewed changes (log), or handing a project to a new owner (transfer) — triggers 「uap」「ship」「提交」「送 PR」「update and push」「推上去」「開工寫 spec」「移交專案」「交接給同事」. Branches first whenever committing on the default branch (or a detached HEAD); never pushes to the default branch directly and never merges without an explicit user instruction."
user-invocable: true
disable-model-invocation: true
argument-hint: "[spec|log|transfer] [repo|.] [module...]"
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# Project — Dossier 維護與 Ship

以 repo 內的 STATUS.md（dossier）為專案單一事實來源，覆蓋工作項的三個時點：開工（spec）、收尾送出（log）、移交（transfer）。dossier 章節語意與生命週期見 `references/dossier.md`；git 為唯一跨主機媒介——machine-local 狀態（handoff/memory）不跨機，跨機要延續的內容一律進 repo。

## 模式分派

`$ARGUMENTS` 第一個 token 分派模式，其餘 token 傳給該模式：

- `spec` → Spec 模式（開工）
- `log` → Log 模式（收尾+ship）
- `transfer` → Transfer 模式（移交）
- **其他或無引數 → 預設 Log 模式**，整串引數依 Log 模式的引數規則解讀（與舊 `/uap [repo|.] [module...]` 肌肉記憶相容）。
- spec / transfer 模式的 repo token 解讀沿用 Log 模式 Step 0「引數前處理」的判定規則；無 repo token → pwd 所在 repo。

---

## Spec 模式（/project spec）

開工儀式：把要做的事從「願望」變成「可執行的工作合約」。

1. 無 STATUS.md → 從模板 `~/.dotfiles/claude/templates/STATUS-template.md` 建立，與使用者確認「專案一句話定位」。已存在但非 dossier（撞名的領域產物；判準＝`ship-state.sh <repo>` 輸出的簽章不符 `dossier-flag:` 行，命名互斥規則見 `references/dossier.md`）→ 停下告知，不覆寫。
2. 與使用者釐清後，把工作項寫入「進行中」章節的 spec 區：
   - **Context**（為什麼做）／**Goal**（做到什麼程度算完成）／**Acceptance Criteria**（怎麼驗證）／**Constraints**（不能碰什麼）
   - 模糊處直接問、不猜——spec 寫得越清楚，後續 agent 的工作越像執行合約而非猜意圖。
3. 本模式只寫 spec、不動 code、不 commit；spec 隨後續工作由 Log 模式一起送出。

---

## Log 模式（/project log，= 舊 /uap 超集）

把（通常已通過 review 的）變更收尾送出：偵測狀態 → 依 repo 流程定路徑（**branch 先決，先於 commit**）→ 同步 dossier 與必要文檔 → adaptive 提交 → 依 protection 走 PR 或直接 push。支援跨 repo。銜接 `/deep-review` 結尾（feature branch + 乾淨 commit + 未 push）。

**Violating the letter of the rules below is violating their spirit.** Do not rationalize around them.

開始前**複製這份 checklist 進回應**並逐項勾選：

```
Project Log 進度：
- [ ] Step 0：多 repo 偵測（單 repo 跳過）
- [ ] Step 1：逐 repo 狀態 + 流程偵測（default branch / 變更集 / protection / ship 路徑 / branch-first）
- [ ] Step 2：同步 dossier（STATUS.md）與受影響文檔
- [ ] Step 3：adaptive 提交（未 commit→code+docs 同 commit；已 commit→獨立 docs commit）
- [ ] Step 4：印 ship 摘要 → 等使用者確認（無確認 → STOP）
- [ ] Step 5：依路徑送出（PR 或直接 push）；輸出 PR URL / push 結果
```

**輕量判準（fast path）**——以下**全部**成立時，儀式面從簡：免貼上方 checklist；Step 2 快速核對（確認 dossier 無需新增即可一句帶過）；Step 4 摘要縮為 3 行精簡版：

- 單一 repo；
- 變更集 ≤3 檔、或純 docs/chore 文檔性變更；
- 本次無關鍵決策／死路／技術債要記入 dossier。

**Light path relaxes ceremony only, NEVER Critical.** Branch-first, never-push-default, the Step 4 confirmation gate, and Unknown=protected all apply unchanged — "it's just a small change" is never a reason to skip a guardrail.

**詢問收斂（單一 gate）**：除 Step 4 硬 gate 與 agent 無法自行安全決定的情境（身分分離、fork、push 失敗、spec 撞名）外，其餘待決事項（squash 建議、STATUS.md 建立/過期、是否開 PR）一律彙整進 Step 4 摘要的「附註」**一次問**，不逐項中斷流程。

### Critical — Guardrails

These are hard constraints. Read them before touching git.

- **NEVER push without explicit user confirmation.** Always show the Step 4 ship summary first and wait for an affirmative reply. No confirmation → STOP.
- **NEVER push to the default / protected branch directly.** On a protected default branch, open a PR instead. Sole exception: `ship-state.sh` prints `verdict: BOOTSTRAP` — it measured zero branches on the remote, so no default branch exists yet. That exemption covers **exactly one push** (creating the baseline) and expires the moment the baseline exists. Only the script grants it; never carry it over from memory or from an earlier turn's authorization.
- **NEVER merge the PR.** Opening a PR ≠ merging it. Merge only on an explicit user instruction.
- **Branch FIRST, before any commit.** If changes must be committed while `HEAD` is the default branch (or detached), create a feature branch **before** committing — not at push time. This is unconditional: do it regardless of protection state (see Step 1, item 5), even when protection is confirmed off.
- **Unknown protection = protected.** If `gh` is missing or the protection query fails, treat the default branch as protected (PR path). Do not assume it is open.

#### Rationalization table — STOP if you hear yourself say these

| Excuse | Reality |
|--------|---------|
| "User said push, so push to main." | "push" means push the *feature branch*. A protected default branch needs a PR. |
| "The PR is open now, might as well merge it." | Opening ≠ merging. Merge only on an explicit, separate instruction. |
| "Docs are already committed on main, just push them." | You should have branched first. Move the commit to a feature branch; never push to protected main. |
| "Can't detect protection, so it's probably fine to push to main." | Unknown protection → treat as protected. Branch + PR, or stop and ask. |
| "Branching now is extra work; commit here first, move later." | Branch-first is one command and prevents an awkward main commit. Do it before the commit, every time. |
| "It's just a docs commit, the protection won't mind." | Protection does not care what the commit is. Same rules. |
| "Working tree is clean — nothing to ship, exit." | Docs may still lag behind already-shipped code. Check session memory for shipped work (docs-only mode, Step 1 item 2) before exiting. |

#### Red Flags — STOP and re-read Critical

- About to run `git push origin <default-branch>` or `git push` while on the default branch.
- About to run `gh pr merge` / any merge **without an explicit user merge instruction** (with one, follow `references/ship-paths.md`「Merge 最後一哩」).
- About to `git commit` while `HEAD == default branch` **or detached HEAD** without having branched.
- About to push without having shown the Step 4 summary and received confirmation.

### Step 0：範圍鎖定

#### 引數前處理（repo 鎖定）

模式 token（若有）之後的第一個 token 若是 **repo 指定**，直接鎖定該 repo、**跳過下方多 repo 偵測互動**；其餘 token 當 module 過濾（Step 2 用）。判定該 token：

```
~/.claude/skills/project/scripts/ship-state.sh resolve <token>
```

照 verdict 走（**the script IS the path/realpath/toplevel logic — do not re-derive it**）：

- `resolve: REPO <root>` → 鎖定該 repo。
- `resolve: MODULE` → 當 module 過濾，不鎖定（`docs/plans` 這類子路徑 scope 落在這裡）。
- `resolve: UNKNOWN` → 比對 session 記憶中的 repo 根 basename（如 `krepo`、`dotfiles`）——命中即鎖定該 repo；不命中 → 該 token 也當 module，走下方多 repo 偵測。（basename 比對需要 session 記憶，故留在 model 端。）

鎖定單一 repo 後 → 直接進 Step 1（不問多 repo 清單）。

#### 多 Repo 偵測（無 repo 引數時）

依本 session 記憶列出所有涉及變更的 repo（**不掃 `~/Projects/`**）：

1. 回憶 session 中改過檔案的所有 repo 根目錄 + pwd 所在 repo。
2. **單一呼叫**確認全部 repo 狀態：`~/.claude/skills/project/scripts/ship-state.sh <repo1> <repo2> ...`（default branch 偵測、三點/兩點變更集、upstream 邊界、protection 判定全在腳本內）。Step 1 直接沿用同一份輸出，**不重跑**。
3. 展示清單等使用者確認（ok / 只看 X / 還有 Y）：
   ```
   本次涉及 2 個 repo：
     1. krepo（領先 default 2 commit）
     2. pilot-api（3 檔未提交）
   一起 ship？或需要調整？
   ```
4. context 被壓縮 → 以 pwd 的 repo 為底讓使用者補充；使用者指定的 repo 即使無變更也納入。
5. 全部 repo 既無領先 default 的 commit 又無 working tree 變更 → **勿直接結束**：先逐 repo 依 Step 1 第 2 項的 **docs-only mode** 判定（session 有已 ship 變更的 repo 仍納入，跑文檔同步）。git 無變更**且** session 記憶亦無已 ship 工作 → 才告知並結束。
6. **單一 repo → 跳過此步，直接 Step 1。**

### Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）

> **remote 假設**：下文一律以 `origin` 書寫，代表「canonical remote」的 stand-in。**非 origin repo**：把下文所有 `origin` 讀作你解析出的 remote（`git -C <repo> remote`；有 `origin` 用之、否則取第一個）；無任何 remote → 停下告知使用者。**fork 工作流**（push 目標 = writable fork、PR/protection 查詢目標 = upstream，兩者為不同 remote）**本 skill 不自動分辨**——遇 fork 場景在 Step 4 摘要明列兩個 remote、由使用者確認，**不擅自對 fork 開 PR、不對唯讀 upstream push**。**host 假設**：本 skill 假設 GitHub.com（`gh` 走 authenticated default host、compare URL 用 `github.com`）；GitHub Enterprise / 自架站台需設 `GH_HOST` 並以 `host/owner/repo` 形式綁 `-R`，**不在本 skill 自動處理範圍**（SSH alias 如 `git@github-work:` 仍指向 github.com，照常適用）。

對每個 repo：

1. **狀態偵測（單一來源）**：沿用 Step 0 的 `ship-state.sh` 輸出（單 repo 鎖定時在此直跑一次）——每 repo 印出 `branch` / `remotes`（多 remote 附 fork 提示）/ `default` / `files-vs-default`（三點，branch 自身帶來的檔）/ `commits-ahead`（兩點，領先 default 的 commit）/ `working-tree`（porcelain 含 untracked）/ `misplaced`（誤 commit 在本地 default 的警示，附 `branch-first-cmd:` 供第 5 項照抄）/ `dossier`（STATUS.md 衛生訊號，Step 2 用）/ `protection` / `ship-path` / `branch-first`。**Do not re-run the underlying git/gh commands one by one — the script IS the detection.**
2. **變更集**（= 此 branch **相對 default 的變更**，即 PR 將含的內容；**不等於「未 push」**——已 push 到 feature branch upstream 的 commit 仍落在此範圍，push 狀態由 Step 5 處理且 push 為冪等）：取腳本的 `files-vs-default` + `working-tree` 合併為完整**檔案**清單（Step 2 判模組、Step 4 列變更檔都靠它；`commits-ahead` 只有主旨、無檔名，deep-review 交接的「clean tree + 只剩 branch commit」情境靠 `files-vs-default` 列檔）。無變更（腳本印 `changes: NONE`）→ 跳過此 repo，**除非符合下述 docs-only mode**。
   **Docs-only mode**：repo git 無變更（tree clean、無領先 default 的 commit），但 session 記憶中有本 session **已 ship**（已 merge／已 push）的變更 → 不跳過。變更集改由那批 commit 重建檔案清單：逐 commit `git -C <repo> show --name-only <sha>`（已 merge 進 default 者用 default 上的對應 commit）。後續步驟照常：Step 2 據此同步文檔、Step 3 只會產生 `docs:` commit、branch-first／protection／Step 4 確認全部適用；Step 2 掃完確認文檔皆已同步 → 該 repo 無事可做，如實回報。**A clean tree does not mean "nothing to ship" — "code shipped, docs lagging" is the common case this mode exists for.**
3. **branch protection**：取腳本的 `protection:` verdict（classic + ruleset 都查過）——`PROTECTED` / `OPEN` / `UNKNOWN → treat as PROTECTED`。**Never reinterpret the script's UNKNOWN as "probably open" — Unknown = protected, the script already says so.** verdict 附 `viewerPermission=READ`（classic `Not Found`）→ 身分分離情境，後續處置（`git push --dry-run` 探權限、Step 4 摘要點明、不自行硬推）見 `references/ship-paths.md`。
4. **決定 ship 路徑**：腳本印 `verdict: BOOTSTRAP`（全新空 repo，遠端零 branch）→ 走 **bootstrap 路徑**（`references/ship-paths.md`「Bootstrap」）：branch-first 與 protection 判定在此皆不適用（沒有 default 可保護），Step 4 摘要須標明「此 push 將決定遠端 default branch」。其餘 `verdict: STOP` 一律停下照訊息處理，**不得**自行當成 bootstrap。否則取腳本的 `ship-path:`——protected（或未知）→ **PR 路徑**（推 feature branch + 必開 PR）；確定無保護 → **仍預設 PR 路徑**（跨 repo 單一形狀，省掉每輪「這個 repo 要不要 PR」的判斷，並留下審查紀錄與可回溯 diff）。**"No protection" is not a reason to skip the PR** —— 只有使用者明說「不用 PR / 只推 branch」才退為直接 push 該 feature branch（escape hatch，不主動勸退）。**兩條路徑都推 feature branch、都不直推 default**（branch-first 無條件）——「直接 push」指**省去開 PR 的步驟、直接 push 該 branch**，不是直推 default。把變更合進 default branch 一律是**使用者**的事（agent 不 merge、不直推 default）。
5. **Branch-first（無條件，依全域「if on default branch, branch first」）**：目標——**到 Step 5 送出前，當前 branch 一定不是 default branch（也不是 detached HEAD）**，**不論 protection**。已在 feature branch（如 deep-review 結尾）→ 跳過。否則執行：

   ```
   ~/.claude/skills/project/scripts/branch-first.sh <repo> <type>/<slug>
   ```

   （ship-state 有印 `branch-first-cmd:` 時整行照抄、填上 type/slug；type 取自變更語意 feat/fix/docs…，slug kebab-case。）情況 A（default/detached 上無誤 commit → `switch -c`，working-tree 變更與 detached commit 跟隨）與情況 B（誤 commit 在本地 default → 救援序列 + porcelain 前後快照驗證）由腳本自動判定；任何 ambiguous（分岔、branch 撞名、無 remote）→ `verdict: STOP` 交回處理，零 mutation。在 default branch 上務必 **commit 之前**先跑。**Do not hand-type the rescue sequence — the script IS the mutation path**（手動 fallback 僅供除錯，見 `references/ship-paths.md`）。
   > 做完此步，**Step 5 一律推 feature branch，絕不直推 default branch**——即使確定無保護（branch-first 無條件，「無保護→直接 push」推的也是 feature branch，不是 default）。
6. **Squash 提醒**：branch 上若有連續 `fix:`/`refactor:`（review 迭代痕跡）→ 列入 Step 4 摘要附註提醒可先 squash，**不在此單獨停下**（deep-review 正常已 squash，通常無需；已 push 的 commit squash 後 push 需 `--force-with-lease`）。

### Step 2：同步 dossier（STATUS.md）與受影響文檔

由**完整變更集**（已 commit + 未 commit）識別涉及模組，更新文檔（防禦原則：**先讀、只改相關段落、無需更新就跳過，不硬塞**）：

- **STATUS.md（dossier；章節語意見 `references/dossier.md`）**：
  - 本次工作的**關鍵決策（附理由）／死路／新增技術債** → 寫入對應章節。若工作過程已依全域規則**事件當下就地記錄**，本步為**核對補漏**而非重建；未記錄的部分此刻 session 記憶還在，是最後時機。只記 git 推不出來的（為什麼、放棄了什麼、還欠什麼），進度細節留給 commit。
  - 里程碑達成 → 「進行中」項收斂或移入「已完成」；「下一步」隨進度改寫（跨主機接續的交接點就在這裡）。
  - 衛生檢查（總量治理）：偵測訊號取 Step 1 同一份腳本輸出的 `dossier:` / `dossier-flag:` 行——**門檻常數單一來源在 ship-state.sh**（references 若提及數字僅為說明性引用、以腳本為準）；章節語意與收斂規則見 `references/dossier.md`。逐 flag 處置：「進行中」含 ✅ → 當場移入里程碑；全檔過長或規範外章節（Session Log）→ 當次收斂（蒸餾＋歸檔 docs/archive/）並列入 Step 4 附註告知；過期 → 列入 Step 4 附註提醒、本次重點補齊；簽章不符（撞名領域產物）→ 停下告知，勿當 dossier 改。
  - `dossier: NONE` 且 repo 非 trivial（有持續開發跡象）→ 列入 Step 4 摘要附註**建議**從 `~/.dotfiles/claude/templates/STATUS-template.md` 建立，經同意才建、不硬塞（不提前單獨詢問）。
- 涉及模組的 `**/CLAUDE.md`（只動受影響的）。
- 相關 `docs/plans/*.md`（存在時）。
- 所有更動文檔頂部的 `updated` 日期改為今天（YYYY-MM-DD；STATUS.md 的對應欄位名為「更新日期」）。
- `$ARGUMENTS` 中（mode 與 repo token 之後的）module 名 → 限縮文檔掃描範圍。

### Step 3：Adaptive 提交

依 reviewed code 的狀態決定文檔如何「一起提交」。**前提：送出前所有 reviewed code 都必須已 commit**——working tree 不留未 commit 的 code，否則 Step 5 會送出不完整變更集。

- **code 未 commit**（review 在 working tree）：`git add` 程式 + 文檔 → 一個或多個語意 commit（Conventional Commits），code 與其文檔**同 commit**。
- **code 已 commit**（如 deep-review 已 squash）：文檔另起 `docs: …` commit，**同 branch**（同 PR 一起出）。**不 amend、不重寫已 review 的 commit。**
- **mixed state**（部分 code 已 commit、部分仍在 working tree——如 Step 1 情況 B 搬移後又改了東西）：**先**把 working-tree 的 code 補成語意 commit（與已 commit 的同 branch），**不可只補 `docs:` commit 就送出、把未 commit 的 code 留在 working tree**；code 全部 commit 後再依「code 已 commit」處理文檔。
- 無文檔需更新且 code 已 commit → 本步不產生 commit。

commit message 用 Conventional Commits，附環境指定的 `Co-Authored-By` trailer（以 runtime system prompt 的 Git 區塊為權威，**勿在 skill 寫死 model 名稱/版本**——它每次升 model 就漂移）。

### Step 4：Ship 摘要 → 確認（critical-op gate）

push **之前**，逐 repo 印摘要等使用者確認（plan → validate → execute）：

```
Ship 摘要：
  krepo  路徑=PR（main 受保護）
    feature branch: feat/mops-announce-backfill
    branch commit（相對 default，= PR 內容）: 2 feat + 1 docs（push 為冪等，已 push 則 no-op）
    變更檔: src/..., scripts/..., STATUS.md
    PR: feat/... → main（將開，不 merge）
    附註: branch 有 3 個 fix: commit，要先 squash 嗎？／此 repo 無 STATUS.md，要一併建立嗎？
確認送出？
```

「附註」列詢問收斂來的待決事項（squash／STATUS.md 建立／過期／是否開 PR），無則省略。輕量路徑摘要縮為 3 行（路徑＋branch＋變更檔），確認語意不變。

**無確認 → STOP。** 這是硬 gate（見 Critical）。

### Step 5：依路徑送出

確認後逐 repo 執行（完整指令序列見 `references/ship-paths.md`）：

- **PR 路徑**：`git -C <repo> push -u origin <feature-branch>` → 偵測既有 PR（`gh pr view`，多 repo 須 `-R <owner/repo>` 綁定）：有則指向、無則 `gh pr create`（同樣 `-R` 綁定；title/body 由 commits 組；deep-review 的「第三方審查資訊」若有一併放進 body）。完整綁定指令見 `references/ship-paths.md`。輸出 PR URL，並附一句提示：「說『merge』即可由我接手最後一哩（squash-merge + 清 branch + 同步本地 default）」——序列見 `references/ship-paths.md`「Merge 最後一哩」。**不 push default branch；未獲明說 merge 前不 merge。**
- **直接 push 路徑**（escape hatch：確定無保護**且**使用者明說不用 PR）：push **當前 branch**（branch-first 無條件，故此處一定是 feature branch、非 default）：`git -C <repo> push -u origin <feature-branch>`（**顯式 remote + branch**，不用裸 `git push`——裸 push 受 `push.default` / `remote.pushDefault` / 非預期 upstream 影響，可能推到錯 remote 或多推 ref；`origin` 為 stand-in）。**本路徑不是無保護 repo 的預設**——預設仍是 PR（見 Step 1 第 4 項），走到這裡代表使用者已明說不用 PR，故不再回頭勸開 PR。
- **Bootstrap 路徑**（`verdict: BOOTSTRAP`）：照抄腳本的 `bootstrap-cmd:`（推本地 default 建立 baseline），完成後**重跑 `ship-state.sh` 確認 BOOTSTRAP 已消失**——此後回到正常路徑，後續 commit 一律 feature branch。
- 多 repo：逐 repo 送出，最後彙總（各 repo 的 PR URL / push 結果）。
- push 失敗處理（`rejected` / 無 upstream / gh 未登入）→ 見 `references/ship-paths.md`「push 失敗處理」（單一來源）。

---

## Transfer 模式（/project transfer）

移交專案給新 owner 前的完整度檢查與移交包產出。**本模式不 push、不 merge、不改 repo 權限**——那些是移交雙方拍板後的人工動作。

1. **Dossier 完整度檢查**：讀 STATUS.md 逐節評估（判準見 `references/dossier.md`）：
   - 關鍵決策是否附理由、死路是否記錄、技術債/已知缺口是否誠實反映
   - 「進行中」是否反映現況（過期 → 先補齊再移交；接手者最需要的就是「為什麼這樣設計、哪些路不通」）
   - 缺漏列成清單與使用者確認，逐項補齊
2. **Credentials 盤點**：檢查 `.env.example` 覆蓋度、掃描無硬編碼 secrets。**Credentials NEVER go into git** — 交付走 gitignored 檔（如 `tmp/transfer-credentials.md`）+ 私訊/密碼管理器。
3. **產出移交指南**：從 `~/.dotfiles/claude/templates/transfer-guide-template.md` 建 `<repo>/docs/transfer.md`，依 repo 實況填寫；待決策表（D1–D6）留給移交雙方拍板，不代填。
4. 移交拍板後在 STATUS.md「關鍵決策」記一筆：「YYYY-MM-DD owner 移交 A → B」。

---

## 設計備忘

- 本 skill 是 **ship / dossier 階段**，不自己跑 review。大變更未審查 → 建議使用者先 `/deep-review`，但不強制。
- 與 `/deep-review` 銜接：deep-review 結尾 = feature branch + 乾淨 commit + 未 push → Log 模式多走 Step 2（dossier+docs）+ Step 4/5（ship）。
- 典型流程：`/project spec`（開工）→ 實作 → `/deep-review` → `/project log`（ship）→ `/handoff`（同主機延續）或 STATUS.md 下一步（跨主機延續）→ `/ready4quit`。
- 歷史：Log 模式的前身是 `/uap`（2026-07 併入本 skill，防護內容原文搬遷）。本 skill 為 `disable-model-invocation`（description 不進 model context，無語意觸發）——「uap」「ship」等字面由全域 CLAUDE.md 技能載入指標路由（建議使用者執行 `/project log`）；slash 相容形式為裸 `/project`（預設 log 模式）。
- 詳細 git/gh 指令與邊界 → `references/ship-paths.md`；紀律驗收情境 → `references/pressure-tests.md`；dossier 規範 → `references/dossier.md`。
