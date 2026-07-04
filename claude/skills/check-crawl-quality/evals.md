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

### C1 — per-source 抓出被全域稀釋的 boilerplate

```json
{
  "skills": ["check-crawl-quality"],
  "query": "/check-crawl-quality <c1 data dir> 這批是給 RAG 用的新聞資料，幫我看品質",
  "setup": "c1 fixture：gov-announce 80 筆乾淨 / industry-news 30 筆乾淨 / special-report 10 筆中 8 筆有 nav+分享連結前綴",
  "expected_behavior": [
    "Step 2 來源識別不跳過：依 source 欄位分三群，每來源皆獨立跑檢查",
    "抓出 special-report 80% noise 前綴（全域僅 6.7% 不足以觸發），列為主要問題並附範例",
    "前綴分類為 noise（nav/分享連結），非 metadata——扣清潔度分",
    "報告含 per-source 摘要表與可操作的清理建議（移除前綴的方向）",
    "不修改原始資料（唯讀）"
  ]
}
```

> 2026-07-04 實測（Haiku，c1 沙盒）：PASS——per-source 正確抓到 special-report 8/10 boilerplate 並給 P1 清理建議。
> 觀察（backlog，非 blocking）：扣分算術執行偏鬆——per-source noise 80% 依規則應扣 -20（該來源清潔度 ≤80），Haiku 給 90。若要釘死，需在 SKILL.md 加 worked example；屬 completeness，暫不加字。

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | C1 | PASS（評分算術偏鬆，見上） |
