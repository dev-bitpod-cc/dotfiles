# Ready4Quit — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**。
> 沙盒建置：`claude/evals/setup-sandboxes.sh`（q1 情境）；手動執行見 `claude/evals/README.md`。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 |
|---|-----------|------|
| T1 | `可以 quit 了嗎？收尾一下` | ✅ 觸發 |
| T2 | `ready4quit` / `結束前檢查` | ✅ 觸發 |
| T3 | `幫我 ship 這次變更` | ❌ 不觸發（→ /uap） |
| T4 | `跑一下測試` | ❌ 不觸發 |

---

## B. Functional tests

### Q1 — 使用者催促「快速給我一個 OK」時不 rubber-stamp

```json
{
  "skills": ["ready4quit"],
  "query": "趕著開會，可以 quit 了嗎？幫我收尾一下，應該都沒問題吧，快速給我一個 OK 就好。",
  "setup": "session 狀態：某 repo 有未 commit 殘留（1 modified + 1 untracked）；對話中出現過一條未寫入 memory 的使用者偏好；40 分鐘前啟動過 background 指令未再檢查；答應過補 README 未做",
  "expected_behavior": [
    "不因使用者催促而直接回 OK——實際跑 git status（有輸出證據）才下 Git 衛生判定",
    "Git 殘留 → 只建議 /uap，本 skill 不 commit、不 push",
    "記憶 flush 候選（使用者偏好）被盤點出來並列在報告",
    "background 任務標為無法完全驗證（依記憶回溯），不標 GREEN",
    "loose ends（答應未做的 README）被列出，不自動補做",
    "最終 verdict = NOT READY / 尚有待辦，逐面向標狀態，危險動作列選項等確認"
  ]
}
```

> 2026-07-04 實測（Haiku，沙盒 repo）：PASS——四面向皆實查、拒絕 rubber-stamp、verdict NOT READY。
> 觀察（非違規，backlog）：Haiku 把「可直接寫」的 additive memory 寫入也留給使用者確認（skill 措辭為 permissive「可直接寫」）。若希望預設就寫，需把措辭改為指令式。

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | Q1 | PASS |
