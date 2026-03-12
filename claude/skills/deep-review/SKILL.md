---
name: deep-review
description: "深度 code review — 結合專案 CLAUDE.md 慣例與架構知識，對 diff 或指定模組進行多維度審查。Use when user says \"review\", \"check my code\", \"deep review\", \"code review\", or runs /deep-review. Supports autofix mode and cross-repo review."
user-invocable: true
argument-hint: "[autofix] [file_or_path_or_commit_range]"
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# Deep Review

你是一位資深 code reviewer。不只看 diff 表面，還要讀周圍程式碼、理解架構、比對專案慣例，也評估整體性——code 是否像一次性寫成。

## 核心原則

### 審查者與作者分離

**Code-quality 審查一律由 subagent（Agent 工具）執行。** 主 agent 負責 orchestration-level judgment（範圍確定、repo 選擇、context 收集、round 偵測），但不做 code-quality judgment（程式碼好壞、是否有 bug、是否符合慣例）。Subagent 擁有乾淨的 context window，不帶寫 code 時的推理脈絡，避免 confirmation bias。

跨 repo 時此原則更加重要——主 agent 同時是多個 repo 的作者，**絕不能**由主 agent 判斷跨 repo 一致性。

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

**上限**：4 輪修復、5 次審查。若 R5 仍未通過，代表問題可能在架構層面，繼續自動修只會越補越亂。

**修復原則**：主 agent 在修復階段依照 subagent 的修復計畫執行，優先修復所有嚴重與中等問題；建議等級僅在不引入額外風險時順手處理。修復後必須 commit 再進入下一輪審查。

**審查者與作者分離在 autofix 中同樣適用**——主 agent 負責修復（作者角色），subagent 負責審查（reviewer 角色），兩者不混合。

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

### 0. 識別審查範圍（多 Repo 偵測）

在開始審查前，主 agent 根據本 session 的記憶，列出所有涉及變更的 repo：

1. 回憶本 session 中修改過檔案的所有 repo 根目錄
2. 加上 pwd 所在的 repo（即使未改檔案）
3. 對每個 repo 執行 `git diff --stat HEAD` 和 `git log --oneline @{upstream}..HEAD 2>/dev/null` 確認變更狀態
4. 向使用者展示清單並等待確認：

```
本次涉及 2 個 repo：
  1. rag-platform（3 檔案變更）
  2. rag-platform-deploy（5 檔案變更）
一起審查？或需要調整？
```

5. 使用者可：確認（ok）、限縮（只看 X）、擴充（還有 Y）
6. 若 context 被壓縮導致記憶不完整，以 pwd 的 repo 為底，讓使用者補充
7. 使用者指定的 repo 即使沒有 diff，也納入（可能需要檢查一致性）
8. **單一 repo** → 跳過此步驟，直接進入 Step 1

### 1. 確定審查範圍

**引數前處理**：若引數包含 `autofix`，先提取出來設為 autofix 模式，剩餘引數才用於判斷審查範圍。例如 `/deep-review autofix src/` → autofix 模式 + 審查 `src/`。

對每個 repo 獨立判斷，依優先順序：

1. **有引數**（扣除 autofix 後）→ 依引數類型決定模式（見下方）
2. **有 working tree 變更**（staged 或 unstaged）→ `git diff HEAD`
3. **HEAD 偏離 base branch 且 working tree clean** → `git diff <base>...HEAD`（review 整個 branch）
   - base branch 偵測（目標是 repo 的預設主分支，不是當前 branch 的 upstream）：
     1. 列出所有 remote（`git remote`）；若無 remote → 嘗試本地 `main` / `master`（`git rev-parse --verify main 2>/dev/null`），都不存在則提示使用者指定；若有多個 remote → 提示使用者指定要用哪個 remote 作為基準
     2. 解析該 remote 的 HEAD：`git symbolic-ref refs/remotes/{remote}/HEAD 2>/dev/null`，取 basename；若指令失敗或對應 ref 不存在，進入下一步
     3. 嘗試 `main`：`git rev-parse --verify {remote}/main 2>/dev/null`
     4. 嘗試 `master`：`git rev-parse --verify {remote}/master 2>/dev/null`
     5. 全部失敗 → 提示使用者指定 base branch
4. **都沒有** → `git diff HEAD~1`

先用 `git diff --stat` 看概覽，再讀完整 diff。

**引數判斷**：符合 `HEAD~N`、`X..Y`、或 7+ 字元 hex → commit 範圍模式；其餘視為檔案/目錄路徑。

### 2. 偵測迭代輪次

對每個 repo 執行 `git log --oneline <base>..HEAD` 檢查 branch commit 歷史（base branch 偵測方式同 Step 1）。

- 無 fix/refactor commit → **Round 1**
- 有初始 commit + 後續 fix/refactor commit → **Round 2+**（依 fix commit 數推斷）
- 整檔審查模式（無 diff）→ **Round 1**

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
| > 40 | 同上，但 repo 內可再依模組分拆 |

**重要**：跨 repo 一致性的判斷**永遠由 subagent 執行**，主 agent 不做此判斷。多 subagent 時，主 agent 僅拼接各 subagent 的輸出，不加工、不篩選、不降級。

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

### 5. 彙整輸出與 Autofix 循環

主 agent 接收 subagent 結果，按以下格式輸出。主 agent 僅做 orchestration（格式化、拼接），不加入自己的 code-quality 判斷。報告的首要讀者是**負責修復的 agent**，其次是人類。

**Autofix 模式下的流程**：
1. subagent 回傳審查結果
2. 若通過 → 輸出通過報告，結束
3. 若未通過且已達 R5 → 輸出 autofix 終止報告，結束
4. 若未通過且未達上限 → 主 agent 依修復計畫執行修復 → commit → 回到 Step 4 發起下一輪審查（Step 0-3 的 context 沿用，不重新收集）

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
- 最終通過後，squash 成乾淨的 commit
