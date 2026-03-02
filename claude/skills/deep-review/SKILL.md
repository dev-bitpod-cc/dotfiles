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
4. **都沒有** → 最新一筆 commit `git diff HEAD~1`

先用 `git diff --stat` 看概覽，再讀完整 diff。

**指定檔案/目錄模式**：不依賴 diff，直接讀取整個檔案，審查結構、命名、潛在問題。

### 2. 載入專案 context

自動讀取以下來源（有就讀，沒有就跳過）：

- **專案 CLAUDE.md** → `<repo_root>/CLAUDE.md`
- **自動記憶** → 當前專案的 `memory/MEMORY.md`
- **全域 CLAUDE.md** → `~/.claude/CLAUDE.md`

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

#### 3c. 跨檔案追蹤

如果變更涉及多個檔案，檢查：
- 後端 model 新增欄位 → 前端 type 是否同步
- 新 API 端點 → api.ts 是否有對應函式
- 新組件 → page.tsx 是否有整合
- SQL 欄位 → 對應的 DB 是否真的有這個欄位（根據 CLAUDE.md 中的 DB 資訊判斷）

### 4. 輸出格式

```markdown
## Deep Review

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
**整體評估**: {一句話總結}

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
- `file.py:88` — 描述 + 建議

### 跨檔案一致性

- [x] 後端 model ↔ 前端 type 同步
- [ ] 新端點缺少 api.ts 函式
- [x] 組件已整合至 page.tsx

### 專案慣例檢查

- [x] DB 連線用 context manager
- [ ] navi 查詢缺少 try/except fallback
- [x] 符合 commit 慣例
```

## 審查原則

- **不要吹毛求疵** — 只報告有實質影響的問題
- **給具體建議** — 不只說「有問題」，要說「改成 X 因為 Y」
- **讀夠再評** — 看不懂的先讀周圍程式碼，不基於片段下結論
- **尊重意圖** — 先理解為什麼這樣寫，再判斷有沒有更好的方式
- **區分等級** — `[嚴重]` 必須修、`[中等]` 應該修、建議是加分項
