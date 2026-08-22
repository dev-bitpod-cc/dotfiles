---
name: project
description: "Project state, history & ship — 三模式：spec（開工：active contract）、log（收尾：history/backlog/active 同步、commit、push/PR）、transfer（移交完整度）。Use for /project, uap, ship, 提交, 推上去, 開工 spec, or project transfer. Branches first before commits; never pushes without current authorization and never merges without an explicit merge instruction."
user-invocable: true
disable-model-invocation: true
argument-hint: "[--spec|--log|--transfer] [--merge|--pr|--no-pr|--bypass-merge] [repo|.] [./module...]"
allowed-tools: Bash, Read, Glob, Grep, Edit, Write, AskUserQuestion
---

# Project — Active state、History 與 Ship

這是 Claude Code 的薄入口。只有使用者明確輸入 `/project` 才能執行；不要把一般對話裡的
「project」當成叫用。

1. 把 Claude Code 提供的 `$ARGUMENTS` 原樣記為 **normalized invocation arguments**；不要自行補字、
   改寫 endpoint 或猜漏掉的 token。
2. 以本 `SKILL.md` 的實際位置解析 skill directory；所有 relative references、scripts 與 templates 都從該目錄
   解析。若從 worktree 測試，必須使用 worktree 這份，不得跳去全域安裝副本。
3. **完整讀取 [references/workflow.md](references/workflow.md)，再依它分派模式並執行。** 核心
   lifecycle、授權、STOP 與 mutation contract 只在 shared references/scripts；本入口不得另建一套。
