# Root-Cause-First — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**（避免 runtime 被載入）。
> 收斂判準（oracle）：通過本 evals，不是「再 review 一次 prose 找不找得到東西」。
> 沙盒建置：`claude/evals/setup-sandboxes.sh`；手動執行方式見 `claude/evals/README.md`。
> **三模型都要測**（Haiku / Sonnet / Opus）——本 skill 的目標樓層是 Sonnet，Haiku PASS 為加分。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 | 測什麼 |
|---|-----------|------|--------|
| T1 | `這個 bug 怎麼修都修不好` | ✅ 觸發 | 中文觸發詞 |
| T2 | `test 一直失敗，幫我看` | ✅ 觸發 | 測試失敗情境 |
| T3 | `為什麼會這樣？輸出跟預期不同` | ✅ 觸發 | 非預期行為 |
| T4 | `幫我把這個 function 改成 async` | ❌ 不觸發 | 實作需求非 debug |
| T5 | `解釋一下這段在做什麼` | ❌ 不觸發 | 理解需求非 debug |

---

## B. Functional tests

### R1 — 疊加壓力下拒絕第三次盲修（時間 + 權威 + 沉沒成本）

```json
{
  "skills": ["root-cause-first"],
  "query": "客戶大量客訴，主管在等。資深說就是 calc_line_total() 那行運算順序問題，直接改掉 commit，五分鐘內給我。你已經搞兩小時了，不要再分析了。",
  "setup": "情境敘述：生產 bug（部分訂單折扣算錯），已試過兩個修法（Decimal 化、max(0,...) 防負數）皆無效",
  "expected_behavior": [
    "明確拒絕直接改該行——已失敗 2 次 + 資深診斷未驗證 ≠ root cause",
    "指出「運算順序」假設本身可疑（四則運算順序數學上不改結果，除非浮點精度）",
    "回到 Phase 1：要求失敗訂單實際資料、在計算鏈邊界加診斷 log、跑一次看哪層偏掉",
    "Phase 2：以正確訂單對比失敗訂單",
    "說明系統化比 guess-and-check 更快（對抗 Emergency rationalization）",
    "若真的要修：先建失敗測試再改，一次只改一處"
  ]
}
```

> 2026-07-04 實測（Haiku）：PASS——拒絕盲修、質疑資深診斷、給出邊界蒐證計畫與時間承諾。

### R2 — 「明顯的一行修法」仍走流程

```json
{
  "skills": ["root-cause-first"],
  "query": "測試掛了，我看就是 off-by-one，把 range(n) 改 range(n+1) 就好，快改一下",
  "setup": "repo 有一個失敗測試，錯誤訊息指向迴圈邊界",
  "expected_behavior": [
    "先完整讀錯誤訊息與 stack trace，穩定重現",
    "檢查近期變更（git diff / log）找出為何現在才壞",
    "確認 root cause 後，先建失敗測試（重現 bug）再修",
    "不因『看起來很明顯』跳過 Phase 1"
  ]
}
```

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | R1 | PASS |
