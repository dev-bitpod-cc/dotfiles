# NC-Notify — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**。
> 執行方式見 `claude/evals/README.md`；本 skill 的測法 = 給模型一個寫 cron 腳本的任務，檢查產出腳本是否過整合 checklist。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 |
|---|-----------|------|
| T1 | `寫一個爬蟲回補腳本，之後排 cron 每天跑` | ✅ 觸發 |
| T2 | `這個 pipeline 跑完通知我` | ✅ 觸發 |
| T3 | `寫一個 FastAPI endpoint` | ❌ 不觸發（API 服務不需 NC） |
| T4 | `跑一下這個測試` | ❌ 不觸發 |

---

## B. Functional tests

### N1 — 寫每日 cron 回補腳本，NC 整合完整

```json
{
  "skills": ["nc-notify"],
  "query": "幫我寫一個回補腳本 backfill.py：讀 orders.csv，逐筆算 total 寫進 sqlite。之後會排 cron 每天凌晨跑。順便給我 crontab 那行。",
  "setup": "空白專案目錄",
  "expected_behavior": [
    "開始發 info、完成發 info、失敗路徑（except 區）發 error——三者齊備",
    "訊息格式 {動作結果}: {關鍵數據}（如「回補完成: 處理 N 筆，跳過 M 筆」），無 emoji、無 source 前綴",
    "所有 NC 呼叫 try/except 靜默——NC 失敗只 log warning，絕不 raise、不影響主流程",
    "讀 NC_API_URL / NC_API_KEY，缺任一則直接跳過通知（不報錯）",
    "task 命名 {功能}-{動作}（如 orders-backfill）",
    "crontab 建議可執行（cd 進專案、log 導向、env 帶入）"
  ]
}
```

> 2026-07-04 實測（Haiku，沙盒目錄）：PASS——checklist 六項全過並自測 10 筆資料；僅一個未使用變數的小瑕疵（非 skill 違規）。

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | N1 | PASS |
