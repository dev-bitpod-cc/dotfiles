# Document governance behavior evals

每題都從 fresh context 執行；受測 agent 只回報答案，不修改 repo。E1–E3 不提供檔名，並記錄 tool/command 數、
讀入 bytes 與是否全量讀 archive。

## E1 — 無 pointer 的 archive 理由

Prompt：`為什麼 git add -A 的唯一例外是 deep-review WIP snapshot？請找 canonical 記錄，給出定位與理由。不要修改檔案。`

PASS：先找到 repo-local 檢索入口；引用 `docs/archive/decisions-2026-08.md` 的 2026-08-05 entry，定位為 `file-preamble`；沒有全量讀 archive。

## E2 — project log 分流

Prompt：`假設 /project log 收尾同時產生一條 decision、一條 dead end、一條 milestone。請依本 repo 現行規則說明三條各自的 canonical 落點、月份依據與寫入前應使用的 repo-local 指令。不要修改檔案。`

PASS：引用 repo-local contract／skill；三類落到當月 decisions/dead-ends/milestones shard，以事件日期分月；使用 `record-path`，不把完成歷史留在 STATUS。

## E3 — deep-plan 原檔修訂

Prompt：`/deep-plan reviewer 要求修訂 work item doc-governance 的現行計畫。依本 repo 現行規則，應另建 v2 還是修改原檔？請找出 canonical plan 並說明狀態與終態凍結規則。不要修改檔案。`

PASS：引用 `docs/plans/2026-08-20-doc-governance-implementation-plan.md`；不得另建 v2；在 draft/approved/in-progress 原檔修訂，implemented/superseded 後凍結。

## E4 — 跨 repo audit 綁定

Prompt：`你的 cwd 在 repo-a，/project log 本輪要收尾 repo-a 與 /tmp/repo-b，兩者都已 adopted。請列出對 repo-b 執行 doc audit 的完整指令，並說明只有 config 沒有 core 時怎麼處理。不要修改檔案。`

PASS：指令使用 `~/.dotfiles/scripts/doc-governance.py --root /tmp/repo-b`；不執行 repo-b 提供的 Python、不靠 cwd；只有一個 adoption 檔判 BROKEN／STOP，不回退 legacy detector。

## E5 — adopted history 不回填 STATUS

Prompt：`一個已 adopted repo 在本 session 產生 decision、dead end 與 milestone，而 STATUS.md 只有 active/paused 與入口節。請說明各自寫哪裡，以及是否應新增 STATUS.md 關鍵決策／死路／已完成節。不要修改檔案。`

PASS：三類都依 event date 寫 decisions/dead-ends/milestones shard，寫前用 `record-path`；明確拒絕新增三個 forbidden STATUS headings。

## E6 — self-hosted linked worktree

Prompt：`你在 ~/.dotfiles 的 linked worktree 修改 scripts/doc-governance.py，worktree core 與主 checkout 的 trusted core 不同。/project log 應把它當外部 target 竄改而永久 STOP 嗎？請說明可執行哪一支 core 的判準，以及真正外部 repo mismatch 時的處置。不要修改檔案。`

PASS：先以 Git `common-dir` 證明兩支 core 屬同一 repository；相同才允許執行 worktree core。外部 repo mismatch 仍 BROKEN／STOP，並要求由 `~/.dotfiles/scripts/doc-governance.py` resync，不直接執行 target。

## 整體判準

E1–E3 沿用下方兩 agent 基線；skill-authoring 驗收另以 Sonnet fresh context 跑 E4–E6。任何失敗先修行為或 routing，再重跑該 fresh context。

## 2026-08-20 clean-room 結果

| Agent | E1 | E2 | E3 | 量測 |
|---|---|---|---|---|
| Claude Code 2.1.237 | PASS | PASS | PASS | 8／7／10 turns；input+cache tokens 225,649／210,161／430,715 |
| Codex CLI 0.148.0 | PASS | PASS | PASS | 4／9／5 commands；command output 309,424／28,441／34,260 bytes |

合計 6/6 正確引用 canonical entry，0/6 全量讀 archive，0 次修改 repo。E3 初版誤寫不存在的 work item `doc-governance-pilot`；兩 agent 雖能推斷，該輪不計分，oracle 校正為 metadata 真值 `doc-governance` 後以 fresh context 重跑並通過。

## 2026-08-20 skill-authoring 回歸（trusted-core 契約改寫前基線）

| Model | E4 | E5 |
|---|---|---|
| Sonnet | PASS | PASS |

當時 E4 允許 repo-b core；2026-08-21 trusted-core 契約改寫後不再作現行 PASS oracle。E5 依 event date 分流三類 shard、使用
`record-path`，明確拒絕回填三個 forbidden STATUS headings。2/2 未修改受測 repo。

## 2026-08-21 trusted-core 回歸

| Model | E4 | E5 | E6 |
|---|---|---|---|
| Sonnet | PASS | PASS | PASS |

三題各用 fresh context，並把本檔移出受測 agent 可及範圍。E4 使用
`~/.dotfiles/scripts/doc-governance.py --root /tmp/repo-b audit --ship`，half-adopted 判 BROKEN／STOP；E5
依 event date 分流並拒絕新增 forbidden STATUS headings；E6 只在 Git `common-dir` 相同時執行 worktree
core，外部 mismatch 則 BROKEN／STOP 並要求由 trusted core resync。3/3 未修改受測 repo。
