---
name: project
description: "Project state, history & ship — 三模式：spec（開工：active contract）、log（收尾：history/backlog/active 同步、commit、push/PR）、transfer（移交完整度）。Use for /project, uap, ship, 提交, 推上去, 開工 spec, or project transfer. Branches first before commits; never pushes without current authorization and never merges without an explicit merge instruction."
user-invocable: true
disable-model-invocation: true
argument-hint: "[--spec|--log|--transfer] [--merge|--pr|--no-pr|--bypass-merge] [repo|.] [./module...]"
allowed-tools: Bash, Read, Glob, Grep, Edit, Write, AskUserQuestion
---

# Project — Active state、History 與 Ship

涵蓋工作項三個時點：開工（spec）、收尾送出（log）、移交（transfer）。每次執行先讀
`references/dossier.md`；它定義 adopted repo 的 active／backlog／history 生命週期與 legacy fallback。

## 模式分派

`$ARGUMENTS` 第一個 token 分派模式，其餘 token 傳給該模式：

- `spec`／`--spec` → Spec 模式。
- `log`／`--log` → Log 模式。
- `transfer`／`--transfer` → Transfer 模式。
- 其他或無模式引數 → 預設 Log；與舊 `/uap` 相容。
- mode flag 可出現在任意位置；spec／transfer 的 repo token 沿用 Log Step 0 的 path resolver。

## Spec 模式

開工儀式：把願望變成可驗證的 active contract。本模式只寫文檔，不改 code、不 commit。

1. 判斷 adoption：`.doc-governance.json` 與 `scripts/doc-governance.py` 兩者皆有＝adopted；兩者皆無＝legacy；
   只存在一個＝BROKEN，停止且不要回退 legacy。
2. Adopted repo 先執行 `python3 ~/.dotfiles/scripts/doc-governance.py --root "$repo" find '<工作問題>'` 查相關 decision／dead end；命中的
   stable IDs 稍後寫入 active item 的 `關聯`。不得先整批讀 archive。
3. 無 `STATUS.md` 時，adopted repo 從 `~/.dotfiles/claude/templates/STATUS-template.md` 建立；legacy repo
   從 `~/.dotfiles/claude/templates/STATUS-legacy-template.md` 建立。建立後確認專案定位；撞名的領域產物不得覆寫。
4. 在 `進行中` 寫 Context／Goal／Acceptance Criteria／Constraints／進度／下一步／關聯 IDs。
   模糊處直接問，不猜。暫停則移到 `暫停中` 並寫可觀察的恢復條件。
5. Legacy repo 依自己的 STATUS schema 寫 spec，不強迫建立 history/backlog family。

## Log 模式

**執行前必須完整讀取 `references/log-workflow.md`，並逐步照做。** 該檔包含 checklist、Critical guardrails、
Step 0–5、授權表路由與所有 STOP 條件；它是 Log 程序本體，不可只靠本節摘要或記憶重建。

Adopted repo 的文檔差異只有一個入口：Step 2 依 `references/dossier.md` 寫 event-time records、移除完成的
active/backlog item，然後以 `python3 ~/.dotfiles/scripts/doc-governance.py --root "$repo" audit --ship` 的 exit code 作唯一 doc verdict。
Legacy repo 才沿用 workflow 內既有 detector。Push／merge authority 仍只由 kernel 與
`references/ship-paths.md` 說法表決定；doc adoption 不改寫任何授權規則。

## Transfer 模式

本模式不 commit、不 push、不 merge、不改 repo 權限。產物留在 working tree，由 Log 一起送出；
credentials 永遠不進 git。

1. Adopted repo：檢查 active／paused 真實反映現況、paused 有恢復條件、相關 `D/X/M/B-*` 可由 `find`
   定位，並跑 `audit --ship`。Legacy repo 依 `references/dossier.md` 的 fallback 檢查既有權威。
2. 盤點 `.env.example` 或等價設定範本、掃描硬編碼 secrets；秘密走 gitignored 檔與安全通道。
3. 從 `~/.dotfiles/claude/templates/transfer-guide-template.md` 建 `<repo>/docs/transfer.md`，待決策留給移交雙方。
4. Owner 移交結論在 adopted repo 寫 `D-*` record；legacy repo 寫其既有決策落點。

## References

- `references/log-workflow.md`：Log 的完整 checklist／Critical／Step 0–5（Log 模式必讀）。
- `references/dossier.md`：active、backlog、history、record schema、adopted/legacy 分流。
- `references/ship-paths.md`：授權說法表、git/gh 指令與 merge 最後一哩。
- `references/pressure-tests.md`：紀律行為 oracle。

典型流程：`/project spec` →（可選 `/deep-plan`）→ 實作 → `/deep-review` → `/project log` →
同主機 `/handoff` 或跨主機更新 active 下一步 → `/ready4quit`。
