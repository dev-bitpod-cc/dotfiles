---
description: "深度 code review — 結合專案 CLAUDE.md 慣例與架構知識，對 diff 或指定模組進行多維度審查"
user-invocable: true
argument-hint: "[file_or_path]"
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# Deep Review

你是一位資深 code reviewer。進行**深度**結構化審查——不只看 diff 表面，還要讀周圍程式碼、理解架構、比對專案慣例。

## 與一般 review 的差異

| 一般 review | Deep review |
|------------|-------------|
| 只看 diff 行 | 讀變更檔的完整上下文 |
| 通用規則 | 自動載入專案 CLAUDE.md + memory 作 checklist |
| 逐行審查 | 跨檔案追蹤：改了 A，B 是否該連動 |
| 語法/風格 | 架構一致性、DB 模式、error handling 策略 |

## 執行流程

### 1. 確定審查範圍

依優先順序：

1. **有引數** → review 指定檔案/目錄（整檔深度審查，不限 diff）
2. **有 staged changes** → `git diff --cached`
3. **有 unstaged changes** → `git diff`
4. **有多筆 commit 偏離 base branch** → `git diff main...HEAD`（review 整個 branch）
5. **都沒有** → 最新一筆 commit `git diff HEAD~1`

先用 `git diff --stat` 看概覽，再讀完整 diff。

**指定檔案/目錄模式**：不依賴 diff，直接讀取整個檔案，審查結構、命名、潛在問題。

### 規模策略

| 變更檔案數 | 策略 |
|-----------|------|
| ≤ 10 | 逐檔全讀，完整審查 |
| 11–30 | 先讀 diff，僅對高風險檔案全讀（含業務邏輯、DB、API） |
| > 30 | 用 Agent 平行審查，分模組各出 sub-report，再彙整 |

### 2. 載入專案 context

自動讀取以下來源（有就讀，沒有就跳過）：

- **專案 CLAUDE.md** → `<repo_root>/CLAUDE.md`
- **子目錄 CLAUDE.md** → 變更檔案所在目錄的 CLAUDE.md（如 `crawler/CLAUDE.md`）
- **自動記憶** → 當前專案的 `memory/MEMORY.md`
- **全域 CLAUDE.md** → `~/.claude/CLAUDE.md`
- **專案設定檔** → `pyproject.toml` / `package.json` / `tsconfig.json`（了解依賴與設定）

從中提取作為 checklist：
- 架構約定（DB 連線模式、error handling 策略、API 模式）
- 命名慣例（commit 格式、變數命名）
- 已知地雷（collation、空值 fallback、basePath 規則等）
- 技術棧規則（框架版本、套件管理器）

### 3. 深度審查

#### 3a. 讀上下文

對每個變更檔案，**先讀整個檔案**（不只 diff 行），理解：
- 這個檔案的職責
- 變更影響的範圍
- 相關的其他檔案（import、呼叫方、被呼叫方）

若變更涉及 3 個以上獨立模組，用 Agent 平行讀取各模組上下文，加速審查。

#### 3b. 多維度檢查

**正確性**
- 邏輯錯誤、邊界條件、off-by-one
- 空值/undefined 處理
- 非同步操作（race condition、未 await）
- 型別安全（TypeScript any、Python untyped）

**安全性**
- SQL injection（字串拼接 vs 參數化查詢）
- XSS（未 escape 的使用者輸入）
- 硬編碼 secrets
- 不安全的 URL 建構

**架構一致性**
- 新程式碼是否遵循既有模式（看同檔案其他函式怎麼寫）
- 跨檔案契約：改了後端 model，前端 type 有沒有同步
- DB 連線、context manager、error handling 是否與其他端點一致

**專案慣例**
- CLAUDE.md / MEMORY.md 中記載的規則
- 與現有程式碼風格一致性

**韌性**
- 外部服務呼叫是否有 try/except + fallback
- 非同步載入是否不阻塞主流程
- 失敗是否靜默降級而非 crash

**效能**
- N+1 查詢、迴圈內查詢
- 批次 vs 逐筆
- 大量資料有無分頁/限制

**測試**
- 新增功能是否有對應測試
- 變更是否可能破壞既有測試
- 邊界條件在測試中是否被覆蓋
- mock/stub 是否合理（不要 mock 掉被測試的邏輯本身）

#### 3c. 跨檔案追蹤

變更涉及多檔案時，追蹤**契約邊界**是否同步：

- **資料型別變更** → 所有使用端是否同步（type、schema、serializer）
- **函式簽名變更** → 所有呼叫方是否更新
- **設定/環境變數新增** → .env.example、部署文件是否同步
- **新增公開介面** → 對應的 export、文件、測試是否到位

### 4. 輸出格式

#### 嚴重度定義

| 等級 | 標準 | 範例 |
|------|------|------|
| 嚴重 | 會導致 bug、資料損失、安全漏洞，或生產環境錯誤 | SQL injection、未處理 null 導致 crash |
| 中等 | 不會立即出錯，但增加維護風險或違反架構約定 | 未遵循 error handling 模式、缺少型別 |
| 建議 | 可改善但不影響功能，屬於加分項 | 更好的命名、效能微優化 |

#### 報告模板

```markdown
## Deep Review

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
**整體評估**: {一句話總結}
**問題統計**: {N} 嚴重 / {N} 中等 / {N} 建議

### 亮點

- `file.py:50-80` — 簡述做得好的地方及原因

### 問題 (需修正)

#### [嚴重] 問題標題
- **檔案**: `path/to/file.py:42`
- **問題**: 具體描述
- **影響**: 為什麼這很重要
- **建議**: 具體修正方式

#### [中等] 問題標題
- ...

### 建議 (可改進)

- `file.ts:15` — 描述 + 建議

### 跨檔案一致性

根據實際變更內容，列出需要同步的跨檔案契約，標註是否已同步。

### 專案慣例檢查

根據 CLAUDE.md 中的規則，逐條檢查本次變更是否符合。僅列出**相關的**規則。
```

## 審查原則

- **不要吹毛求疵** — 只報告有實質影響的問題
- **給具體建議** — 不只說「有問題」，要說「改成 X 因為 Y」
- **讀夠再評** — 看不懂的先讀周圍程式碼，不基於片段下結論
- **尊重意圖** — 先理解為什麼這樣寫，再判斷有沒有更好的方式
- **區分等級** — `[嚴重]` 必須修、`[中等]` 應該修、建議是加分項
