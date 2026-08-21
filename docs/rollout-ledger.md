<!--
rollout-ledger.md — 文檔治理 rollout 的 qualifying ship 計量器。判準與取代關係見
D-20260822-rollout-gate-replacement；逐 repo 採用程序見 docs/doc-governance-rollout.md。
-->

# Rollout ledger

文檔治理 batch 2/3 的 steady-state 證據就在這裡累積。**沒記進來的 ship 不算數** — 這份 ledger 存在的理由，
正是原門檻「連續 10 次 ship 無人工 compaction」沒有計量器、因此不可數。

## 記法

一次 qualifying ship 一條 top-level bullet，欄位固定：

- **repo**：採用了治理核心的 repo。
- **commit**：merge 進 default branch 的 commit（squash merge 下就是那顆單親 commit；**不要用
  `git log --merges` 數 ship**，它在 squash 流程恆為 0）。
- **lifecycle 操作**：這次 ship 動到的治理面向 — 新增 record／backlog 開關／plan 狀態轉換／STATUS 更新／
  純程式碼。十顆同型的 review-fix 不構成樣本覆蓋。
- **first audit**：`audit --ship` 的**第一次**結果（rc 與 finding codes）。事後修完再跑的那次不是它。
- **人工介入**：`none`／`lifecycle`（照既有規則新增或搬動內容）／`compaction`（為了讓 audit 過而壓縮、
  裁剪或重組既有內容）。判為 `compaction` 即暫停擴張並記 root cause。
- **final audit**：收尾時的 rc。
- **surface bytes**：`report` 的 governance-surface 前後值。

## 計數狀態

- 目標：10 次 qualifying ship，且 canary repo 自己必須貢獻數次 post-cutover ship。
- 已記錄：0 次。
- ⚠️ 採用 commit `9d3e891` 之後、本 ledger 建立之前，dotfiles 已有 2 次 ship（PR 124、125）。兩者的
  first-audit 結果與人工介入分類**無法事後重建**，因此不計入 — 計數從本檔建立後的下一次 ship 起算。

## 記錄
