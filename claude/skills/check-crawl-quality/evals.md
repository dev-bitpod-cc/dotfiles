# Check-Crawl-Quality — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**。
> 沙盒資料集由 `claude/evals/setup-sandboxes.sh`（c1 情境）生成：120 筆 JSON、3 來源，其中 special-report 10 筆有 8 筆開頭是 nav boilerplate——全域佔比僅 6.7%（看不出來），per-source 佔 80%（must catch）。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 |
|---|-----------|------|
| T1 | `檢查爬蟲品質` / `這批清理後的資料能不能餵 RAG` | ✅ 觸發 |
| T2 | `幫我寫一個爬蟲` | ❌ 不觸發（實作需求） |
| T3 | `資料庫 schema 幫我看一下` | ❌ 不觸發 |

---

## B. Functional tests

### C1 — per-source 抓出被全域稀釋的 boilerplate（腳本驅動）

> RED 事實（2026-07-04 Haiku 實測）：檢查行為正確，但**扣分算術由 model 手執行**、
> 結果不可重現——當時記錄把 Haiku 給的 90 分記為「偏鬆」，事後核對其實是誤判：
> per-source 80% 命中經佔比加權（10/120 筆）保底半額後應扣 -10，90 分正是規則結果，
> 真正的問題是「每次手算、對錯全憑運氣」。2026-07-21 據此把八項檢查與扣分表下沉為
> `scripts/crawl-quality-scan.py`（tests/run.sh 第 21 節釘死算術，含 per-source 加權），
> SKILL.md 改為「分數一律出自腳本、勿手算」。本 case 的期望行為隨之更新。

```json
{
  "skills": ["check-crawl-quality"],
  "query": "/check-crawl-quality <c1 data dir> 這批是給 RAG 用的新聞資料，幫我看品質",
  "setup": "c1 fixture：gov-announce 80 筆乾淨 / industry-news 30 筆乾淨 / special-report 10 筆中 8 筆有 nav+分享連結前綴",
  "expected_behavior": [
    "invokes crawl-quality-scan.py; does NOT hand-implement thresholds/regexes/deduction arithmetic",
    "報告的分數與比例逐字引用腳本 score:/ledger-*:/check-4x: 輸出，未手調任何數字",
    "抓出 special-report 的 noise 前綴 cluster（driver=special-report 的 per-source 加權扣分），列為主要問題並附腳本的 sample= 範例",
    "Step 2 覆核 cluster 分類：確認 nav/分享連結為 noise（同意啟發式則不需重跑）",
    "報告含 per-source 摘要與可操作的清理建議（清理階段剝除前綴的方向）",
    "不修改原始資料（唯讀）"
  ]
}
```

### C2 — 分類覆核與 context 豁免（不手調分數）

```json
{
  "skills": ["check-crawl-quality"],
  "query": "/check-crawl-quality <data dir> 這是技術教學網站的文章，開頭那三行是我們刻意加的欄位標頭",
  "setup": "資料集：多數記錄開頭有 'title:/date:/tags:' 三行刻意 metadata 前綴（腳本啟發式可能判 metadata 或 noise）；部分正文在 code fence 外講解 HTML 標籤（4e 誤中）",
  "expected_behavior": [
    "讀懂使用者 context：前綴是刻意設計 → 若啟發式判 noise，用 --classify pN=metadata 重跑；技術教學站的 4e 命中 → --exempt 4e 重跑",
    "does NOT adjust any number by hand — every score in the report comes from a script run",
    "報告註明使用的 --classify/--exempt 與理由，metadata 建議為「移至獨立欄位」而非「清除」",
    "若無法確定分類且為互動 session → 問使用者；自主執行 → 採啟發式並標明「此分類未經確認」"
  ]
}
```

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | C1 | PASS（評分算術偏鬆——本 RED 促成 2026-07-21 腳本下沉） |
| 2026-07-21 | — | C1/C2 | 算術面由 tests/run.sh 第 21 節行為測試釘死（RED→GREEN）；agent 導航面（invoke 腳本、覆核分類、不手調）實戰 GREEN 待下次沙盒實跑 |
