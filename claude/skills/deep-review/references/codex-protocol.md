# Codex 呼叫協議 — 機制詳解（autocodex）

> 本檔是 SKILL.md「Codex 呼叫協議」節的機制層：低自由度、照表操作，勿憑記憶重組。
> 硬約束（NEVER 類）同時列於 SKILL.md body 該節——兩處衝突時以 body 為準。

## 目錄

- [Preflight：runtime 告知性檢查](#preflight-runtime-告知性檢查)
- [呼叫方式](#呼叫方式)
- [Prompt 限制](#prompt-限制)
- [背景執行與進度查詢](#背景執行與進度查詢)
- [run 的 exit 契約](#run-的-exit-契約)
- [exit 4 救援階梯](#exit-4-救援階梯)
- [為何不需要死亡偵測啟發式（設計根因）](#為何不需要死亡偵測啟發式設計根因)
- [codex 安裝管理](#codex-安裝管理)

## Preflight：runtime 告知性檢查

進入 codex 階段前跑一次——exec 路徑不經 broker，孤兒 broker 對它已無殺傷力，故此處只**報告**、不清理：

```bash
~/.claude/skills/deep-review/scripts/codex-runtime-hygiene.sh check
```

exit 0 = 乾淨；1 = 有孤兒 broker / stale broker.json；3 = 僅有現役 split-brain broker。**非 0 只警告一行、照常進入 codex 階段**（孤兒 app-server 與 exec 共用 `~/.codex/*.sqlite`，但 WAL 模式容得下並行讀取，不構成阻擋理由）。要實際清理才跑 `clean`——那是 plugin 路徑（`/codex:*` 手動指令）的維護動作，autocodex 不需要。

## 呼叫方式

以 **背景 Bash**（`run_in_background: true`）執行 headless codex，**不要**呼叫 `codex:rescue`（plugin 的 broker 路徑會靜默卡死，根因見下方設計根因節）：

```bash
~/.claude/skills/deep-review/scripts/codex-exec-review.sh \
  run --repo <repo_path> --range <commit_range> --round <C1|C2|C3>
```

**多 repo 時**：逐 repo 呼叫，每個 repo 獨立一次 `run`。

## Prompt 限制

腳本內部送出的 prompt **固定一行**，不可經由任何旗標改寫：

```
Run your repo-review skill on <repo_path> for <commit_range>. 繁體中文.
```

**絕對不要**：寫自訂 focus points、要求跑測試、加 context files、解釋要審什麼、傳專案慣例文件。

## 背景執行與進度查詢

背景執行後**不要輪詢、不要猜測進度**——harness 會在進程結束時回叫。需要向使用者報告進度時才跑 `codex-exec-review.sh status --job-dir <dir>`（job 目錄由 `run` 的第一行 stdout `job-dir:` 給出）。

## run 的 exit 契約

完成訊號是 **exit code**，不是狀態字串。腳本已把「進程退出 + 報告檔落地」兩個 OS 層級事實收斂成 exit 契約，照表操作即可。（`resume` 的 4 語意不同，見下方救援階梯——**不要**照本表對 `resume` 的回傳再 resume 一次。）

| exit | 意義 | 動作 |
|---|---|---|
| 0 | 報告已產出（路徑見 stdout `report:`） | 讀報告，進入 findings 驗證 |
| 4 | 進程結束但報告空 | `codex-exec-review.sh resume --job-dir <dir>` 救一次 |
| 5 | 環境/引數錯誤（codex 不在 PATH、非 git repo、range 無法解析） | 停，回報使用者，**不要重試** |
| 2 | 用法錯誤（引數寫錯） | 修正引數重下 |

## exit 4 救援階梯

依序，成功即停：

1. `resume --job-dir <dir>`——偵查通常已完成、報告卡在 session 裡，以記錄的 session id 續跑即可完整救回。
2. resume 回 4（仍空，或該 job 根本不可續）→ 重跑一次 `run`（同引數，等同全新 session）。**resume 的 4 絕不觸發第二次 resume**。**At most ONE fresh retry** — a second identical failure is an environment problem: codex 階段判 blocked、輸出 blocked 報告（主 agent 審查結論不受影響），do NOT burn quota on a third attempt.

## 為何不需要死亡偵測啟發式（設計根因）

舊 plugin 路徑（`codex:rescue`）把執行者與等待者拆成兩組進程——broker→app-server 以 detached 生成、照跑不誤，而等待端只 await 一個「僅由 broker 轉發的 `turn/completed` 才 resolve」的 promise，無 timeout、無輪詢、也不與連線死亡 race。通知一斷即**永久靜默等待**，才需要「log 停滯 15 分 + 進程無網路活動」這種雙訊號事後撈救。exec 路徑沒有這個中介，進程結束就是結束。**Do NOT reintroduce polling or time-based death detection here.**

## codex 安裝管理

codex 由 **brew cask** 管理（非 bun）。**NEVER `bun install -g @openai/codex` to "fix" codex** — it recreates the bun/brew split-brain. Reinstall via `brew reinstall --cask codex`.
