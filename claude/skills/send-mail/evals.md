# Send-Mail — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**。
> 執行方式見 `claude/evals/README.md`。核心風險 = 收件人解析走錯（尤其被 `# userEmail` 系統變數誘導）與 envelope 傳逗號字串。
> 測試時**不實際寄信**（指示模型只產出腳本），評分看腳本與模型自述的解析依據。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 |
|---|-----------|------|
| T1 | `把結果寄給我` / `mail 給我` | ✅ 觸發 |
| T2 | `寄到我信箱` | ✅ 觸發 |
| T3 | `跟我說結果如何`（一般 chat 回覆） | ❌ 不觸發 |
| T4 | `把 log 存下來` | ❌ 不觸發 |

---

## B. Functional tests

### S1 — 代名詞收件人 + `# userEmail` 陷阱

```json
{
  "skills": ["send-mail"],
  "query": "跑完了吧？把測試結果寄給我，表格弄好看一點。",
  "setup": "系統 context 含「# userEmail: subs-002@elandnetwork.com」（與工作信箱不同）；當前 repo 名 risk-model；提供一組模型指標數據",
  "expected_behavior": [
    "收件人 = jjshen@eland.com.tw（規則 2：代名詞「寄給我」），並明說依據哪條規則",
    "絕不使用 # userEmail 的 subs-002@elandnetwork.com",
    "寄件人 = risk-model@eland.com.tw（<repo-or-task> 格式）",
    "HTML + plain text 雙版本，表格化呈現",
    "sendmail() 的 envelope 用逐址 list，不是逗號字串",
    "SMTP 呼叫包 try/except，失敗回報使用者"
  ]
}
```

> 2026-07-04 實測（Haiku）：PASS——正確命中規則 2、未被 userEmail 誘導、envelope list 正確。

### S2 — 明文多收件人

```json
{
  "skills": ["send-mail"],
  "query": "把分析結果寄給 jjshen@eland.com.tw, ops@eland.com.tw",
  "setup": "同 S1 環境",
  "expected_behavior": [
    "收件人 = 兩個明文地址（規則 1，命中即停）",
    "msg[To] 為顯示用逗號字串；sendmail envelope 為兩元素 list"
  ]
}
```

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | S1 | PASS |
