# Document governance behavior evals

三題都從 fresh context、repo root 執行；不得提供檔名。受測 agent 只回報答案，不修改 repo。每題記錄 tool/command 數、讀入 bytes 與是否全量讀 archive。

## E1 — 無 pointer 的 archive 理由

Prompt：`為什麼 git add -A 的唯一例外是 deep-review WIP snapshot？請找 canonical 記錄，給出定位與理由。不要修改檔案。`

PASS：先找到 repo-local 檢索入口；引用 `docs/archive/decisions-2026-08.md` 的 2026-08-05 entry，定位為 `file-preamble`；沒有全量讀 archive。

## E2 — project log 分流

Prompt：`假設 /project log 收尾同時產生一條 decision、一條 dead end、一條 milestone。請依本 repo 現行規則說明三條各自的 canonical 落點、月份依據與寫入前應使用的 repo-local 指令。不要修改檔案。`

PASS：引用 repo-local contract／skill；三類落到當月 decisions/dead-ends/milestones shard，以事件日期分月；使用 `record-path`，不把完成歷史留在 STATUS。

## E3 — deep-plan 原檔修訂

Prompt：`/deep-plan reviewer 要求修訂 work item doc-governance 的現行計畫。依本 repo 現行規則，應另建 v2 還是修改原檔？請找出 canonical plan 並說明狀態與終態凍結規則。不要修改檔案。`

PASS：引用 `docs/plans/2026-08-20-doc-governance-implementation-plan.md`；不得另建 v2；在 draft/approved/in-progress 原檔修訂，implemented/superseded 後凍結。

## 整體判準

Claude Code 與 Codex 各跑 E1–E3 一次，共 6 次。必須 6/6 找到 repo-local 入口與正確 canonical entry，且 0/6 全量讀 archive；任何失敗先修行為或 routing，再重跑該 fresh context。

## 2026-08-20 clean-room 結果

| Agent | E1 | E2 | E3 | 量測 |
|---|---|---|---|---|
| Claude Code 2.1.237 | PASS | PASS | PASS | 8／7／10 turns；input+cache tokens 225,649／210,161／430,715 |
| Codex CLI 0.148.0 | PASS | PASS | PASS | 4／9／5 commands；command output 309,424／28,441／34,260 bytes |

合計 6/6 正確引用 canonical entry，0/6 全量讀 archive，0 次修改 repo。E3 初版誤寫不存在的 work item `doc-governance-pilot`；兩 agent 雖能推斷，該輪不計分，oracle 校正為 metadata 真值 `doc-governance` 後以 fresh context 重跑並通過。
