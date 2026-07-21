---
name: check-crawl-quality
description: "檢查爬蟲清理後的內容品質——偵測 noise 殘留、boilerplate、metadata 混入，並評估 RAG 檢索適用性。Use when assessing crawled or cleaned content quality before RAG indexing, or checking crawler output for leftover noise / boilerplate. Chinese triggers：「檢查爬蟲品質」「爬蟲內容品質」「清理後品質」「RAG 適用性」「noise 殘留」."
user-invocable: true
argument-hint: "<path_or_source> [context_description]"
allowed-tools: Bash, Read, Glob, Grep
---

# Check Crawl Quality

檢查爬蟲清理後的內容，從**清潔度**（有沒有 noise）和 **RAG 適用性**（對檢索好不好用）兩個維度評估，輸出結構化品質報告。

掃描、閾值比較、扣分算術全部由腳本執行（單一真實來源；所有常數與理由在腳本頭部）：

```
uv run ~/.claude/skills/check-crawl-quality/scripts/crawl-quality-scan.py '<path|glob|db>'
```

glob 一律用引號包住（讓腳本自行展開；shell 先展開會變成多個引數而 exit 2）。

## 設計原則

- **格式無關**：JSON/JSONL/TXT/MD/CSV/SQLite 都支援（腳本自動偵測格式、內容欄位、來源分群）
- **抽樣優先**：大量資料由腳本分層抽樣（每來源有保底），報告標明抽樣比例、結果為估計值
- **per-source 必要**：問題被全域稀釋是常態——腳本同時輸出全域與逐來源結果與加權扣分
- **區分 noise 與設計**：前綴殘留和刻意 metadata 性質不同（見 Step 2 分類）
- **可操作結論**：每個發現附修正方向與具體範例

## Critical — Hard Rules

**Violating the letter of these rules is violating their spirit.**

- **READ-ONLY.** NEVER modify, move, or rewrite the source data (the script opens SQLite read-only; you must not touch the files either).
- **NEVER hand-compute metrics or scores.** Every count, threshold comparison, and deduction comes from the script output — quote it verbatim. Do NOT re-derive, "double-check by eye", or adjust a number the script produced. Disagree with a classification or a false positive? Re-run with `--classify` / `--exempt` (Step 2) — the final score always comes out of the script.
- **NEVER bulk-load the dataset into context.** The script scans records; you read its labeled output. Spot-check at most 2-3 records when a classification is genuinely ambiguous.
- **Every reported finding MUST carry verbatim examples** (from the script's `sample=` fields or spot-checks), so the user can overrule misjudgments. No example, no finding.

## 執行流程

### Step 1：掃描

`$ARGUMENTS` 是路徑/glob/DB → 直接跑腳本（glob 加引號）；是自然語言描述 → 先用 Glob 定位，多個或零個候選就停下問使用者。

```
uv run ~/.claude/skills/check-crawl-quality/scripts/crawl-quality-scan.py '<path|glob|db>'
```

- 內容欄位偵測失敗（exit 1，stderr 附可用欄位）→ 帶 `--content-field` 重跑；來源分群不對 → `--source-field`。
- exit 2 = 路徑/用法錯誤，修正後重跑。exit 契約與全部旗標見腳本 header。
- 輸出為帶前綴標籤的結構化文字（`check-4x:` / `ledger-*:` / `score:` / `verdict:`），直接判讀引用。
- 出現 `check-error:` 行 → 該項未執行成功，報告需標明「部分檢查缺失，分數偏樂觀」。

### Step 2：覆核判斷面（唯一有判斷成分的一步）

腳本對共享前綴 cluster（`check-4a:`）給的是**啟發式**分類（`class=...(heuristic)`），逐一覆核其 `sample=`：

| 分類 | 特徵 | 計分去向 | 建議方向 |
|------|------|----------|----------|
| `noise` | nav 連結列表、與正文無關的 boilerplate | 扣清潔度 | 清理階段剝除 |
| `metadata` | `key: value` 形式的刻意前綴 | 扣 RAG（混入） | 移至獨立 metadata 欄位 |
| `artifact` | 內容重複了 title/author 等獨立欄位 | 扣 RAG（冗餘） | 修 parser / 上傳時去重 |
| `false-positive` | 誤判（正文本來就長這樣） | 不扣分 | — |

- 不同意啟發式 → `--classify pN=<class>` 重跑（可多個）；同意則不需重跑。
- 使用者提供的資料集描述（`$ARGUMENTS` 第二段）是判定依據：如「技術教學網站」→ code fence 外講 HTML 的 4e 命中多半是正文 → `--exempt 4e` 重跑（該項不扣分、仍報告）。
- 樣本不足以判斷 → spot-check 2-3 筆原始記錄（僅此用途）。
- 仍不確定：互動 session 問使用者；自主執行採啟發式分類繼續，**但報告必須標明「此分類未經確認」**與改判的重跑指令。

### Step 3：輸出報告

依腳本輸出渲染繁中報告，首要讀者是**要修清理邏輯的人/agent**：

```markdown
## Crawl Quality Report

**資料來源**: {路徑} | **總筆數/抽樣**: {N}/{M}（抽樣為估計值）| **來源數**: {K}
**整體評估**: {一句話}

### 評分
（引用 score: 行——清潔度/RAG/綜合分與 verdict:；有 --classify/--exempt 需註明）

### 問題發現（依嚴重度排序：ledger 扣分大 → 小 → 未扣分但值得注意）
#### [{嚴重度}] {問題標題}
- **維度/影響範圍**: {check-id}；{source} {N}筆 ({%}) 或全域（引用 driver=）
- **範例**: {verbatim sample}
- **建議**: {修正方向——指向清理 pipeline 的哪個階段}

### Per-Source 摘要（僅列有問題的來源——引用 check-4x@<來源>: 行與 ledger 的 driver=；source-verdict: 行如有則照抄）

### 清理建議（依優先序，合併同方向修正）
```

## 注意事項

- 唯讀；不代使用者清理資料——報告修正方向，動手是資料 owner 的事。
- 分類覆核（Step 2）不可跳過：有 cluster 或可疑 4e 命中而未覆核就出報告，分數與建議都可能是錯的。

## Red Flags — STOP

- "The dataset is small, I'll just eyeball the scores." → Run the script. Eyeballed scores drift.
- "The script's number looks off, I'll adjust it in the report." → Re-run with `--classify`/`--exempt`; never patch numbers by hand.
- "Defaults look fine, skip the classification review." → Step 2 is where by-design prefixes stop being punished as noise.
- "I'll clean the data right away since I found the problem." → READ-ONLY. Report the fix direction.
- "Examples make the report long, I'll drop them." → No example, no finding.
