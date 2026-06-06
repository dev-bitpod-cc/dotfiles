---
name: deep-review
description: "深度 code review — 結合專案 CLAUDE.md 慣例與架構知識，對 diff 或指定模組進行多維度審查。Use when the user asks to review code, check their code, or do a deep/code review — including Chinese triggers 「審查」「深度審查」「幫我看 code」「檢查程式碼」「code review」 — or runs /deep-review. Supports autofix mode and cross-repo review."
user-invocable: true
argument-hint: "[autofix] [autocodex] [file_or_path_or_commit_range]"
allowed-tools: Bash, Read, Glob, Grep, Edit, Write, Agent
---

# Deep Review

你是一位資深 code reviewer。不只看 diff 表面，還要讀周圍程式碼、理解架構、比對專案慣例，也評估整體性——code 是否像一次性寫成。

## 核心原則

### 審查者與作者分離

**Code-quality 審查優先由 subagent（Agent 工具）執行。** 主 agent 負責 orchestration-level judgment（範圍確定、repo 選擇、context 收集、round 偵測），但不做 code-quality judgment（程式碼好壞、是否有 bug、是否符合慣例）。Subagent 擁有乾淨的 context window，不帶寫 code 時的推理脈絡，避免 confirmation bias。

跨 repo 時此原則更加重要——主 agent 同時是多個 repo 的作者，跨 repo 一致性判斷應交給 subagent，而非由身為作者的主 agent 自行判斷。

**Subagent 不可用時的降級**：若當前 permission mode 擋下 Agent 工具、或環境無 subagent 能力，主 agent **明確告知使用者「無法委派 subagent，改由主 agent 直接審查」**，再進行審查——並在報告開頭標註「⚠️ 本輪未經審查者/作者分離，主 agent 同時是作者，confirmation bias 風險升高，findings 請額外存疑」。降級是 last resort，不是預設路徑；能用 subagent 就絕不降級。

### Autofix 模式

引數包含 `autofix` 時，主 agent 自動執行 review → fix → commit 循環，直到通過或達到上限。

```
R1 review → 未通過 → 主 agent 修復 → commit「fix: R1 review fixes」
R2 review → 未通過 → 主 agent 修復 → commit「fix: R2 review fixes」
R3 review → 未通過 → 主 agent 修復 → commit「fix: R3 review fixes」
R4 review → 未通過 → 主 agent 修復 → commit「fix: R4 review fixes」
R5 review → 通過 → 結束（squash 成乾淨 commit）
          → 未通過 → 停止，輸出累積報告，交還使用者
```

**上限**：4 輪修復、5 次審查。若 R5 仍未通過，代表問題可能在架構層面，繼續自動修只會越補越亂。終止報告須包含 branch 狀態處置建議（見報告模板）。

**修復原則**：主 agent 在修復階段依照 subagent 的修復計畫執行，優先修復所有嚴重與中等問題；建議等級僅在不引入額外風險時順手處理。

**修復後驗證**：commit 前，若 repo 偵測得到測試框架（`pyproject.toml` → `uv run pytest`、`package.json` 含 test script → `bun test`），先跑測試確認修復未引入 regression。無測試框架則跳過驗證、直接 commit。

- **測試通過** → commit，進入下一輪審查。
- **測試失敗** → 表示本輪修復未完成。**留在本輪**繼續修到測試通過再 commit；**不要**帶著未 commit 的失敗修復進下一輪（那正是迭代紀律要防的累積 diff 狀態）。
- **本輪反覆修仍無法讓測試通過**（同一處修兩次以上仍紅、或測試因環境原因無法執行而擋住驗證）→ **停止**，輸出終止/blocked 報告，branch 維持在上一個測試通過的 commit；**不 commit 失敗狀態、不進下一輪**，交還使用者。

> 不變式：一輪只有在「測試通過」時才算完成並 commit；任何 review 輪次都不會帶著未 commit 的失敗修復開始。

**審查者與作者分離在 autofix 中同樣適用**——主 agent 負責修復（作者角色），subagent 負責審查（reviewer 角色），兩者不混合。

### Autocodex 模式

此模式涉及兩個審查者，全文一律以此命名：**主 agent**（Claude Code 本體，負責主 agent 審查階段與所有修復）、**Codex**（獨立第三方 reviewer）。

引數包含 `autocodex` 時，主 agent 審查通過後自動進入 Codex 第三方審查循環。`autocodex` 與 `autofix` 正交——可單獨使用或組合：

- `/deep-review autofix autocodex`：主 agent 自動審查修復 → 通過 → Codex 自動審查修復循環
- `/deep-review autocodex`：主 agent 手動審查 → 通過 → Codex 自動審查修復循環

#### Codex 審查循環流程

```
主 agent 審查通過 → 取第三方審查資訊（repo path + commit range）
  → 呼叫 codex:rescue（prompt 格式見下方）
  → 收到 findings → 主 agent 逐條驗證（true positive / false positive）
  → 全部 false positive 或無 blocking findings → 結束
  → 有 true positive → 主 agent 修復 → commit「fix: codex R{N} fixes」
  → 再呼叫 codex:rescue 審查修復部分
  → 重複直到無 blocking findings 或達上限
```

**上限**：3 輪 codex 審查、2 輪修復（**diff / baseline 模式皆維持此上限，不放寬**——放寬只會鼓勵深井追逐）。到此階段 code 已通過主 agent 完整審查，剩餘問題應快速收斂。baseline 模式 C2+ 只驗增量修復、基線 backlog 不阻擋通過，因此 2 輪修復足以收斂。若第 3 輪仍有 true positive blocking findings（指向修復本身、非基線 backlog）→ 停止，輸出 codex 終止報告交使用者。

**Codex 呼叫協議**（與 CLAUDE.md 觸發詞流程一致）：

呼叫 `codex:rescue`，**prompt 只含一行**：
```
Run your repo-review skill on <repo_path> for <commit_range>. 繁體中文.
```

**絕對不要**：寫自訂 focus points、要求跑測試、加 context files、解釋要審什麼、傳專案慣例文件。

**多 repo 時**：逐 repo 呼叫，每個 repo 獨立一次 codex:rescue。

**Findings 驗證規則**：主 agent 收到 codex findings 後，逐條讀原始碼獨立驗證。對每條判定 true positive / false positive / context-dependent。不預設 findings 正確，不預設錯誤。只有 true positive 才修復。

**Commit range 更新（依 `codex_base_mode`，見 Step 1）**：base 端永遠錨定、不隨修復「無意識前移」；**錨在哪取決於模式**。

- **Diff 模式**（base 為有界祖先：origin/main、commit range 引數、HEAD~1）：全程 `<審查起點 base hash>..HEAD`，base 固定錨在 Step 1 起點，**不要退化成 `HEAD~1..HEAD`**——否則漏審同一變更集前面的修復。若 base 已被 push（`origin/main..HEAD` 為空），C1 前先記下當時 base hash，後續沿用。

- **Baseline 模式**（base 為 repo 初始狀態 / empty-tree，或全庫 / path 稽核）：
  - **C1**：`<empty-tree 或審查起點>..HEAD`，全量稽核一次——findings 即完整交付物。
  - **C2 起**：`<上一輪 codex 審查時的 HEAD>..HEAD`，**只審本輪修復 commit**，驗證收斂、不重審基線；每輪審完更新「上次 codex HEAD」。
  - C2+ 收斂判準：finding 指向本輪修復 commit（增量 range 內新增/修改行）→ 照常驗證；指向 C1 已知類型的基線 backlog → non-blocking、不阻擋通過、不觸發再一輪修復。

> 不矛盾：anti-`HEAD~1` 防的是「diff 模式 base 滑動 → 漏審同一變更集前面 commit」；baseline C2+ 縮 range 防的是「重審不變基線 → 不收斂」。兩者不同維度——基線本體已在 C1 審過，重審只會不收斂。

**Squash**：codex 階段的 `fix: codex R{N} fixes` commit 與先前的 `fix: R{N} review fixes` commit 一起納入最終 squash。

### 迭代紀律：每輪修復後 commit

多輪 review 時，每輪修復後**必須先 commit 再進入下一輪**，最終通過後 squash 成乾淨 commit。

```
Round 1 review（未通過）
  → 修復問題 → commit「fix: R1 review fixes」
Round 2 review（未通過）
  → 修復問題 → commit「fix: R2 review fixes」
Round N review — 通過
  → squash 成一個有意義的 commit
```

**為什麼：**
- 不 commit → 每輪 subagent 都要處理完整累積 diff，context 隨輪次膨脹，大型變更會撞 context 上限
- 有 commit → working tree clean，Step 1 自動使用 `git diff <base>...HEAD` 審查完整 branch 狀態
- Round 偵測依賴 `git log`，不 commit 則無法正確偵測輪次

## 審查原則

- **不吹毛求疵** — 只報告有實質影響的問題
- **給具體建議** — 不只說「有問題」，要說「改成 X 因為 Y」
- **讀夠再評** — 看不懂先讀周圍程式碼，不基於片段下結論
- **尊重意圖** — 先理解為什麼這樣寫，再判斷有沒有更好的方式
- **區分等級** — 嚴重/中等為 blocking，建議為 non-blocking；分級時若有疑慮歸入中等而非建議
- **獨立判斷** — 每輪用全新視角看最終狀態，不錨定上一輪結論

## 執行流程

開始前，主 agent **複製以下 checklist 進回應**並逐項打勾追蹤進度（依模式刪去不適用項）：

```
Deep Review 進度：
- [ ] Step 0：識別審查範圍（多 repo 才需，單 repo 跳過）
- [ ] Step 1：確定審查範圍與 diff（base 偵測；autocodex 時判 codex_base_mode = diff / baseline）
- [ ] Step 2：偵測迭代輪次
- [ ] Step 3：載入專案 context
- [ ] Step 4：委派 subagent 審查
- [ ] Step 5：彙整輸出
        autofix 迴圈每輪重記一行：R{N} 審查 → 修復 → 驗證 → commit（上限 R5）
- [ ] Step 6：Codex 第三方循環（僅 autocodex；每輪重記：C{N} 審查 → 驗證 → 修復 → commit，上限 C3）
- [ ] 通過後：squash 成乾淨 commit（commit 即停，等使用者指示是否 push）
```

### 0. 識別審查範圍（多 Repo 偵測）

在開始審查前，主 agent 根據本 session 的記憶，列出所有涉及變更的 repo：

1. 回憶本 session 中修改過檔案的所有 repo 根目錄
2. 加上 pwd 所在的 repo（即使未改檔案）
3. 對每個 repo 執行 `git diff --stat HEAD` 和 `git log --oneline @{upstream}..HEAD 2>/dev/null` 確認變更狀態
4. 向使用者展示清單並等待確認：

```
本次涉及 2 個 repo：
  1. ais-platform（3 檔案變更）
  2. ais-platform-deploy（5 檔案變更）
一起審查？或需要調整？
```

5. 使用者可：確認（ok）、限縮（只看 X）、擴充（還有 Y）
6. 若 context 被壓縮導致記憶不完整，以 pwd 的 repo 為底，讓使用者補充
7. 使用者指定的 repo 即使沒有 diff，也納入（可能需要檢查一致性）
8. **單一 repo** → 跳過此步驟，直接進入 Step 1

### 1. 確定審查範圍

**引數前處理**：若引數包含 `autofix` 和/或 `autocodex`，先提取出來設為對應模式，剩餘引數才用於判斷審查範圍。例如 `/deep-review autofix autocodex src/` → autofix 模式 + autocodex 模式 + 審查 `src/`。

對每個 repo 獨立判斷，依優先順序：

1. **有引數**（扣除 autofix 後）→ 依引數類型決定模式（見下方）
2. **有 working tree 變更**（staged 或 unstaged）→ `git diff HEAD`
3. **HEAD 偏離 base branch 且 working tree clean** → `git diff <base>...HEAD`（review 整個 branch）
   - base branch 偵測（目標是 repo 的預設主分支，不是當前 branch 的 upstream）：
     1. 列出所有 remote（`git remote`）；若無 remote → 嘗試本地 `main` / `master`（`git rev-parse --verify main 2>/dev/null`），都不存在則提示使用者指定；若有多個 remote → 非 autofix 模式提示使用者指定要用哪個 remote 作為基準，autofix 模式（需零互動）預設取 `origin`（不存在則取第一個 remote），並在報告註明所用基準
     2. 解析該 remote 的 HEAD：`git symbolic-ref refs/remotes/{remote}/HEAD 2>/dev/null`，取 basename；若指令失敗或對應 ref 不存在，進入下一步
     3. 嘗試 `main`：`git rev-parse --verify {remote}/main 2>/dev/null`
     4. 嘗試 `master`：`git rev-parse --verify {remote}/master 2>/dev/null`
     5. 全部失敗（無可用 base branch）→ 此 repo 無 base，**priority 3 不適用，落入 priority 4**（不在此提示指定 base，改問審查範圍）
4. **working tree clean，且 HEAD 未領先 base branch（`<base>..HEAD` 為空）或無可用 base branch**（剛初始化、無 remote、或已與主分支同步，無近期有意義 diff）→ **不要**逕自 `git diff HEAD~1`（只會審到最後一個小 commit）。先問使用者要審什麼：最後一個 commit、整條 branch、或**整個 repo / 全庫**。若選全庫 → base 設為 git empty-tree（`4b825dc642cb6eb9a060e54bf8d69288fbee4904`）。（與 priority 3 互斥：3 = HEAD **領先** base；4 = HEAD **未領先** base 或無 base）

> priority 1–4 已涵蓋所有狀態（有引數 / dirty tree / clean+領先 base / clean+未領先或無 base）；「最後一個 commit（`HEAD~1`）」是 priority 4 詢問中的使用者選項，不另立 priority。

先用 `git diff --stat` 看概覽，再讀完整 diff。

**引數判斷**：符合 `HEAD~N`、`X..Y`、或 7+ 字元 hex → commit 範圍模式；其餘視為檔案/目錄路徑。

#### Codex 範圍模式判定（僅 autocodex 需要）

base 與 range 確定後，**逐 repo** 判一次 `codex_base_mode`，決定 autocodex 階段每輪的 commit range 行為（判定樹，命中即停）。**判 base 的語意，不判 diff 大小**——大型 feature branch 仍是 diff 模式，不因大而切增量。

```
B1. base hash == git empty-tree (4b825dc642cb6eb9a060e54bf8d69288fbee4904) → baseline
B2. path/目錄引數模式（審檔案、無天然 base）                          → baseline
B3. 使用者明確指定「整個 repo / 全庫 / audit 全部」這類全量語意         → baseline
B4. 其餘（working-tree diff、<base>...HEAD branch diff、commit range、HEAD~1）→ diff
```

判定後印一行告知使用者，並提示 **`codex full`** 可推翻、強制每輪重審全 scope（= diff 行為）。

**path 模式（B2）的限制**：codex repo-review 以 **repo root 為單位**、不接受子目錄 repo_path，且 1 行 protocol 禁止加 focus。故 path 模式的 codex 階段 `repo_path = repo root`、`range = <empty-tree>..HEAD`，**codex 會審整個 repo**（比 path scope 廣）。進入 codex 階段前明確告知使用者此擴大，或建議改用「commit 該 path 後以 commit-range 模式」精準限縮。不偽裝成只審了子目錄。

### 2. 偵測迭代輪次

對每個 repo 執行 `git log --oneline <base>..HEAD` 檢查 branch commit 歷史（base branch 偵測方式同 Step 1）。

- 無 fix/refactor commit → **Round 1**
- 有初始 commit + 後續 fix/refactor commit → **Round 2+**（依 fix commit 數推斷）
- 整檔審查模式（無 diff）→ **Round 1**
- **baseline 模式（base = empty-tree / 全庫稽核）→ 一律 Round 1**，不以 `git log` 歷史推斷輪次（empty-tree base 會列出 repo 全部 commit，歷史上的 fix/refactor commit 不代表本次 review 的迭代輪次）；下方「銜接檢查」同樣不適用

輪次影響審查重心，但**不把上一輪的 review 報告傳給 subagent**——每輪獨立判斷。

**銜接檢查**：若 working tree 有大量變更且 `git log <base>..HEAD` 已有 commit，提醒使用者是否忘記 commit 上一輪修復。這違反迭代紀律，應先 commit 再繼續 review。

### 3. 載入專案 context

對每個 repo 讀取以下來源（有就讀，沒有跳過）：

- `<repo_root>/CLAUDE.md` + 變更檔案所在子目錄的 CLAUDE.md
- 當前專案的 `memory/MEMORY.md`
- `~/.claude/CLAUDE.md`
- `pyproject.toml` / `package.json` / `tsconfig.json`

### 4. 委派 subagent 審查

#### 傳給 subagent 的資訊

**傳**（事實與規則）：
- 每個 repo 的完整 diff + 變更檔案的完整內容
- 每個 repo 的 CLAUDE.md、專案設定檔
- 每個 repo 的路徑和名稱（識別用）
- 輪次資訊
- 下方的審查指引

**不傳**（作者脈絡）：
- 主 agent 對「為什麼這樣改」的解釋
- 主 agent 對跨 repo 關聯性的分析
- 上一輪 review 報告
- Session 中的對話脈絡

Subagent 拿到多個 repo 的 diff 後，如同 reviewer 同時被 assign 多個關聯 PR——自己讀 diff、自己判斷關聯性、自己檢查一致性。

#### 規模策略

| 跨所有 repo 合計檔案數 | 策略 |
|----------------------|------|
| ≤ 20 | 單一 subagent，收到所有 repo 的 diff + context，獨立判斷 repo 內品質與跨 repo 一致性 |
| 21–40 | 每 repo 各一個 subagent（repo 內審查）+ 一個「跨 repo 一致性」subagent（收所有 repo 的 diff） |
| > 40 | 同上，但 repo 內再依模組分拆，**每個 subagent 約 8–12 個變更檔或一個內聚模組**，確保 scope 可掌握 |

**切分原則**：避免重複的大範圍 prompt；只在關鍵介面、安全邊界、跨模組行為這些地方讓 scope 略為重疊。

**重要**：跨 repo 一致性的判斷由 subagent 執行（subagent 不可用時依「審查者與作者分離」的降級條款處理），主 agent 不主動做此判斷。多 subagent 時，主 agent 僅拼接各 subagent 的輸出，不加工、不篩選、不淡化嚴重度。

#### 審查重心隨輪次調整

- **Round 1**：所有維度同等權重
- **Round 2**：加重「整體性」，檢查是否出現補丁痕跡
- **Round 3**：整體性優先，但仍嘗試修復
- **Round 4+**：若仍有結構性問題，建議「退一步重寫該區塊」而非繼續修補

#### 審查維度

- **正確性** — 邏輯、邊界、空值、非同步、型別安全
- **安全性** — injection、XSS、硬編碼 secrets
- **架構一致性** — 是否遵循同檔案/同專案的既有模式
- **專案慣例** — CLAUDE.md 中記載的規則
- **韌性** — 外部呼叫的 error handling、失敗降級
- **效能** — N+1 查詢、批次 vs 逐筆、分頁
- **測試** — 對應測試、邊界覆蓋、mock 合理性
- **整體性（Cohesion）**（Round 2+ 加重）— 程式碼是否像一次性寫成；有無重複邏輯、命名不一致、抽象層次混亂、殘留修補痕跡、職責模糊
- **跨檔案契約** — 型別/簽名變更是否所有使用端同步、新增設定/介面是否文件到位
- **跨 Repo 一致性**（多 repo 時）— 介面契約兩端是否同步（env vars、API schema、檔案路徑、port）、文件是否反映最新狀態

#### 基線 backlog（completeness 深井）

**術語（autofix + autocodex 共用）**：在 **baseline 模式**下，與本輪修復無關、屬既有基線的**完整度類**問題——「更多 a11y、更多 edge case、更多測試覆蓋、更多文件」這類沒有底的深井。特徵是每次換角度重審都能再撈出新的一批。

- **判別**：finding 指向本輪修復觸及的行 / 真正的 bug / 安全 / 契約斷裂 → 照常 blocking。指向基線既有碼、只是「還可以更完整」→ 基線 backlog。有疑慮（可能是 bug）仍歸 blocking。
- **處理**：baseline 模式下基線 backlog 為 **non-blocking**，列入報告供使用者排優先序，但**不阻擋通過、不觸發再一輪修復**。否則深井會讓迭代無法收斂（只是換個地方繼續被拖）。
- **diff 模式不適用**此概念——有界變更集本就該全部審完。

### 5. 彙整輸出與 Autofix 循環

主 agent 接收 subagent 結果，按以下格式輸出。主 agent 僅做 orchestration（格式化、拼接），不加入自己的 code-quality 判斷。報告的首要讀者是**負責修復的 agent**，其次是人類。

**Autofix 模式下的流程**：
1. subagent 回傳審查結果
2. 若通過 → 輸出通過報告（含第三方審查資訊）→ 若有 autocodex → 進入 Step 6；否則結束
3. 若未通過且已達 R5 → 輸出 autofix 終止報告，結束（不進入 codex 階段）
4. 若未通過且未達上限 → 主 agent 依修復計畫執行修復 → 驗證（見「修復後驗證」）→ 測試通過才 commit → 回到 Step 4 發起下一輪審查；若驗證無法通過（反覆修仍紅或環境擋住）→ 依「修復後驗證」停止，輸出終止/blocked 報告（沿用 Autofix 終止模板，於收斂失敗分析註明是測試卡關），不進下一輪
   - **context 處理**：Step 3 的專案 context（CLAUDE.md、設定檔）沿用，不重新收集；但 Step 1 的 diff **每輪必須重新收集**——修復 commit 後 diff 已變更，沿用舊 diff 會讓 subagent 審到過時內容。重跑 `git diff <base>...HEAD` 取得涵蓋最新修復的完整 diff 再委派
   - **baseline 模式的收斂（autofix 與 autocodex 機制不同）**：autofix 的 range **不縮**（fixer 需看完整狀態確認沒改壞），改縮 **blocking 判準**——baseline 模式 Round 2+ 給 subagent 的指令補一句：「基線已於 Round 1 全量審過，本輪聚焦『修復是否正確 + 是否引入新問題』；基線 backlog（completeness 深井）若非本輪修復觸及 → non-blocking，列報告但不阻擋通過。」diff 模式不套用，照常全審。
   - **成本與邊界**：autofix baseline 因 range 不縮，subagent 每輪吃 `<empty-tree>..HEAD`（整庫）diff——大型 repo 會撞 Step 4 的 context 上限。靠 Step 4「規模策略 >40」依模組分拆 subagent 緩解；若仍過大，建議全庫稽核改走 autocodex（codex 階段 C2+ 才有縮 range）。autocodex 縮 range / autofix 縮判準 的差異源於：autocodex 是無狀態第三方、autofix 的 fixer 需看完整狀態。

**非 Autofix + Autocodex 模式**：手動審查通過後，主 agent 輸出通過報告，接著自動進入 Step 6。

#### 嚴重度

| 等級 | 標準 | Blocking |
|------|------|----------|
| 嚴重 | 會導致 bug、資料損失、安全漏洞、生產環境錯誤 | 是 |
| 中等 | 不會立即出錯，但：違反架構約定、缺少必要的 error handling、命名/抽象不一致導致誤用風險、跨檔案契約不同步 | 是 |
| 建議 | 純風格偏好（formatting、命名美觀度、註解措辭），不影響功能也不增加誤用風險 | 否 |

**分級原則**：若一個問題可能在未來導致 bug 或誤用，它是中等而非建議。建議等級僅限於「換一種寫法也完全正確」的純偏好問題。

#### 完成判定

**通過標準**（全部滿足）：零嚴重、零中等、整體性通過、跨檔案契約一致、跨 repo 一致性通過（多 repo 時）。

建議等級為 non-blocking，列在報告中供參考，但不阻擋通過。Autofix 模式下，主 agent 優先修復嚴重與中等問題；建議等級僅在修復不引入額外風險時順手處理。

輸出報告時，參考 `references/report-templates.md` 中的模板格式。包含：未通過（單/多 repo）、通過、Autofix 終止四種模板。

報告核心原則：
- 問題**按根因分組**，不按嚴重度排列，讓 fixer 一次解決共因問題
- 修復計畫由 subagent 根據具體問題產出
- 修完後先 commit（如 `fix: R{N} review fixes`），再執行下一輪 `/deep-review`
- 最終通過後，主 agent 負責 squash——範圍為所有 review fix commits（base..HEAD），commit message 採原始功能變更的語意（不是 `fix: review fixes`），格式遵循專案 Conventional Commits 慣例，並附全域 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer
- **通過報告必須附「第三方審查資訊」**：列出每個 repo 的 commit 範圍（`base..head`，base 取 Step 1 判定的審查起點）和變更摘要，方便使用者轉交第三方 reviewer。R5 終止報告不需要此區塊（代碼尚未就緒）

### 6. Codex 第三方審查循環（autocodex 模式）

僅在引數包含 `autocodex` 且主 agent 審查通過後執行。主 agent 審查未通過（含 R5 終止）不進入此階段。

#### 流程

1. 從 Step 5 通過報告的「第三方審查資訊」取出每個 repo 的路徑和 commit range
2. 對每個 repo 呼叫 `codex:rescue`，prompt 嚴格一行：`Run your repo-review skill on <repo_path> for <commit_range>. 繁體中文.`
3. 收到 codex findings 後，主 agent 逐條讀原始碼獨立驗證：
   - **true positive**：確實有問題，需修復
   - **false positive**：codex 誤判，不處理
   - **context-dependent**：需更多 context 才能判定，歸為 true positive 修復（寧可多修不漏）
4. 若無 true positive blocking findings → 輸出 codex 通過報告，執行最終 squash，結束
5. 有 true positive → 主 agent 修復 → commit `fix: codex R{N} fixes` → **依 `codex_base_mode` 更新 commit range**（diff：沿用 `<起點>..HEAD`；baseline C2+：`<上輪 codex HEAD>..HEAD` 只審增量）→ 回到步驟 2
6. 達到上限（3 輪審查、2 輪修復）仍有 true positive（指向修復本身、非基線 backlog）→ 輸出 codex 終止報告，停止

> baseline 模式：步驟 3 驗證時，指向 C1 已知類型基線深井的 finding → 歸基線 backlog（non-blocking），不觸發步驟 5 的再一輪修復；只有指向本輪修復 commit 的 finding 才算 blocking。

#### 注意事項

- codex 階段主 agent 同時扮演「驗證者」和「修復者」，不再委派 subagent（因為 codex 本身就是獨立第三方）
- 多 repo 時逐 repo 處理，每個 repo 獨立計算輪次上限
- 最終 squash 範圍涵蓋所有 review fix commits（主 agent 審查階段 + codex 階段）
- 輸出報告參考 `references/report-templates.md` 中的 codex 通過 / codex 終止模板
