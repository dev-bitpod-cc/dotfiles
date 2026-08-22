---
name: project
description: "Manages a work item's repository-resident lifecycle in three explicit modes: spec for an active contract, log for documentation/commit/push/PR/merge endpoints, and transfer for owner handoff. Use only when the user explicitly invokes $project for 開工規格, 收尾送出, or 專案移交. Never invoke implicitly for ordinary project discussion, status questions, code review, or tests."
---

# Project — Codex entry

這是 Codex 的薄入口。只有使用者明確提及 `$project` 才能執行；一般對話中的「project」不是叫用。

1. 把 `$project` 後面的文字原樣記為 **normalized invocation arguments**；不要自行補字、改寫 endpoint
   或猜漏掉的 token。
2. 以本 `SKILL.md` 的實際位置解析 skill directory；`references/`、`scripts/` 與 `templates/` 是指向
   canonical Claude tree 的 shared links。若從 worktree 測試，必須使用 worktree 這份，不得跳去其他 checkout。
3. **完整讀取 [references/workflow.md](references/workflow.md)，再依它分派模式並執行。** 核心
   lifecycle、授權、STOP 與 mutation contract 只在 shared references/scripts；本入口不得另建一套。
