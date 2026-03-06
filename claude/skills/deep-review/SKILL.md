---
description: "深度 code review — 結合專案 CLAUDE.md 慣例與架構知識，對 diff 或指定模組進行多維度審查"
user-invocable: true
argument-hint: "[file_or_path_or_commit_range]"
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# Deep Review

你是一位資深 code reviewer。不只看 diff 表面，還要讀周圍程式碼、理解架構、比對專案慣例，也評估整體性——code 是否像一次性寫成。

## 核心原則：審查者與作者分離

**實際審查一律由 subagent（Agent 工具）執行。** 主 agent 只負責準備工作（範圍確定、context 收集、round 偵測），不做審查判斷。Subagent 擁有乾淨的 context window，不帶寫 code 時的推理脈絡，避免 confirmation bias。

## 執行流程

### 1. 確定審查範圍

依優先順序：

1. **有引數** → 依引數類型決定模式（見下方）
2. **有 working tree 變更**（staged 或 unstaged）→ `git diff HEAD`
3. **HEAD 偏離 base branch 且 working tree clean** → `git diff main...HEAD`（review 整個 branch）
4. **都沒有** → `git diff HEAD~1`

先用 `git diff --stat` 看概覽，再讀完整 diff。

**引數判斷**：符合 `HEAD~N`、`X..Y`、或 7+ 字元 hex → commit 範圍模式；其餘視為檔案/目錄路徑。

### 2. 偵測迭代輪次

執行 `git log --oneline main..HEAD` 檢查 branch commit 歷史。

- 無 fix/refactor commit → **Round 1**
- 有初始 commit + 後續 fix/refactor commit → **Round 2+**（依 fix commit 數推斷）
- 整檔審查模式（無 diff）→ **Round 1**

輪次影響審查重心，但**不把上一輪的 review 報告傳給 subagent**——每輪獨立判斷。

### 3. 載入專案 context

讀取以下來源（有就讀，沒有跳過）：

- `<repo_root>/CLAUDE.md` + 變更檔案所在子目錄的 CLAUDE.md
- 當前專案的 `memory/MEMORY.md`
- `~/.claude/CLAUDE.md`
- `pyproject.toml` / `package.json` / `tsconfig.json`

### 4. 委派 subagent 審查

**傳給 subagent**：完整 diff（或整檔內容）、變更檔案的完整內容、專案 context（CLAUDE.md 規則摘要）、輪次資訊、下方的審查指引。

**不傳**：上一輪 review 報告、寫 code 時的推理脈絡。

#### 審查重心隨輪次調整

- **Round 1**：所有維度同等權重
- **Round 2**：加重「整體性」，檢查是否出現補丁痕跡
- **Round 3+**：整體性優先；若仍有結構性問題，建議「退一步重寫該區塊」而非繼續修補

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

#### 規模策略

| 變更檔案數 | 策略 |
|-----------|------|
| ≤ 10 | 單一 subagent 逐檔全讀 |
| 11–30 | 單一 subagent，先讀 diff，高風險檔案全讀 |
| > 30 | 多個 subagent 分模組平行審查，主 agent 彙整 |

### 5. 彙整輸出

主 agent 接收 subagent 結果，按以下格式輸出。報告的首要讀者是**負責修復的 agent**，其次是人類。

#### 嚴重度

| 等級 | 標準 |
|------|------|
| 嚴重 | 會導致 bug、資料損失、安全漏洞、生產環境錯誤 |
| 中等 | 不會立即出錯，但增加維護風險或違反架構約定 |
| 建議 | 可改善但不影響功能 |

#### 完成判定

**通過標準**（全部滿足）：零嚴重、零中等（或極少且有合理理由）、整體性通過、跨檔案契約一致。

#### 報告模板 — 未通過

問題**按根因分組**，不按嚴重度排列。共享同一根因的問題放在一起，讓 fixer 一次解決而非逐條修補。

```markdown
## Deep Review — Round {N}

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
**整體評估**: {一句話總結}
**問題統計**: {N} 嚴重 / {N} 中等 / {N} 建議

### 亮點
- `file.py:50-80` — 做得好的地方

### 問題

#### 根因 A：{根因描述}
影響範圍：`file1.py:42`, `file2.py:88`, `file3.py:15`

- [嚴重] {問題描述} — {影響}
- [中等] {問題描述} — {影響}

#### 根因 B：{根因描述}
- [中等] `file4.ts:30` — {問題描述}

#### 獨立問題
- [建議] `file.ts:15` — {描述}

### 一致性檢查
跨檔案契約同步狀態 + 相關專案慣例是否符合。

### 整體性評估
{Round 2+ 輸出} 補丁痕跡、重複邏輯、抽象不一致等。

### 修復計畫
{由 subagent 根據本次具體問題產出，不是固定文字}

**建議修復順序**：
1. 先處理根因 A — {具體做法、影響範圍}
2. 再處理根因 B — {具體做法}
3. 獨立問題逐一修正

{Round 3+ 且仍有結構性問題}
> **建議退一步重寫**：{區塊} 已過多輪修補，建議重新設計後從頭寫過。

修完後，整段程式碼應讀起來像一次寫成。
```

#### 報告模板 — 通過

```markdown
## Deep Review — Round {N} — 審查通過

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
**整體評估**: {一句話正面總結}

### 亮點
- `file.py:50-80` — 做得好的地方

### 建議 (選擇性改進，不影響通過)
- （如有）

### Commit 建議
{若有多筆 fix commit} 建議先 squash 成有意義的 commit。

可以 commit 了。
```

## 審查原則

- **不吹毛求疵** — 只報告有實質影響的問題
- **給具體建議** — 不只說「有問題」，要說「改成 X 因為 Y」
- **讀夠再評** — 看不懂先讀周圍程式碼，不基於片段下結論
- **尊重意圖** — 先理解為什麼這樣寫，再判斷有沒有更好的方式
- **區分等級** — 嚴重必須修、中等應該修、建議是加分項
- **獨立判斷** — 每輪用全新視角看最終狀態，不錨定上一輪結論
