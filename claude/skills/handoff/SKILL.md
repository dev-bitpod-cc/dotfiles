---
name: handoff
description: "Session 交接 — 在 /clear 前把進行中工作的暫時狀態寫成帶 git 錨點的交接檔（handoff），讓後續 session 驗證後無損接續；resume 時先驗錨點再行動、消費即歸檔、過期自動清，杜絕失效交接內容殘留。Use when the user wants to /clear but continue related work later, write a handoff before clearing context, or resume work from a handoff file — Chinese triggers 「交接」「寫交接檔」「handoff」「接續上次的工作」「讀交接檔」「clear 前交接」. NOT for durable facts（進 memory，見 ready4quit）、NOT for shipping git changes（見 /project log）、NOT for cross-host continuation（machine-local；跨主機狀態進 repo STATUS.md）."
user-invocable: true
argument-hint: "[resume] [slug]"
---

# Handoff — /clear 前的工作交接

心智模型：process 重生前把 task state 序列化到磁碟，新 process 反序列化前先驗 checksum。交接檔是**宣稱（claims）不是事實**——repo 現況才是事實；錨點（寫檔當下的 git HEAD）就是 checksum，讓讀取端能機器判定「這份交接還新鮮嗎」。用完即歸檔，失效內容不留在檯面上。

- 存放：`~/.claude/handoffs/<slug>.md`（machine-local；**不放 repo 內**——不污染 git status，跨 repo 工作也只需一份檔多條錨點）
- 已消費：`~/.claude/handoffs/archive/YYYYMMDD-HHMMSS-<原檔名>`（秒級前綴——同日同 slug 二次消費不可互相覆蓋，archive 是 audit trail）
- 機制腳本：`~/.claude/skills/handoff/scripts/handoff-anchor.sh`（`survey` / `anchors` / `verify` / `consume`；EXPIRE_DAYS、ARCHIVE_KEEP_DAYS 常數以腳本為單一來源。`list` 與 `find-predecessor` 是 `survey` 的底層原語，本 skill 一律走 `survey`）

## 引數

- **`/handoff [slug]`** — write mode：寫交接檔。無 slug 就依工作線自取（kebab-case，如 `dotfiles-handoff-skill`）。
- **`/handoff resume [slug]`** — resume mode：接續交接。無 slug → `survey` 只列到一份 active 就直接用，多份列給使用者選。

## Critical — Guardrails

**Violating the letter of the rules below is violating their spirit.**

- **A handoff is a set of CLAIMS, not truth. The repo is truth.** On resume you MUST run `handoff-anchor.sh verify` BEFORE acting on any claim. No verify output in this session → no action based on the handoff.
- **On any verdict other than FRESH**, re-check every claim you rely on against the current repo; where they conflict, the repo wins. NEVER "restore" the repo to match the handoff.
- **Consume-once.** After loading a handoff, archive it via the `consume` subcommand (it refuses double-consumption mechanically). NEVER leave a consumed handoff in the active directory — not even rewritten with a done-marker; "done" files accumulate and rot into stale noise. The archive IS the audit trail.
- **Durable facts go to memory/, not the handoff.** User preferences, project constraints, anything that must outlive this task → write a memory file and leave only a `[[memory-name]]` pointer in the handoff. A handoff dies on consumption.
- **No state snapshots the repo already carries.** Do not paste full diffs or file contents into the handoff — point at commits and paths. Snapshots go stale silently; the anchor makes staleness detectable, a pasted diff does not.
- **Write side: every file path mentioned MUST exist** (check it) or be explicitly marked 規劃中/待新建.
- **A handoff is machine-local and does NOT travel between hosts.** If the next step is expected to continue on ANOTHER host, the continuation content goes into the repo (STATUS.md「進行中」的下一步, updated in place) and gets committed — this docs commit is the ONE commit this skill may make itself (feature branch, never push; see W2 for the code-commit prohibition). The handoff keeps only a pointer. Git is the only cross-host medium — and an unpushed commit is invisible to other hosts: say so to the user explicitly.

### Red Flags — STOP and re-read Critical

- Executing a handoff's next-steps without a `verify` run in this session.
- "I'll update the handoff in place with status: done for traceability" → archive it; traceability lives in `archive/`, not the active directory.
- Re-doing a next-step item on a DRIFTED handoff without checking the drift commits — it may already be done.
- Putting a durable rule in the handoff "so it won't get lost after /clear". That is exactly how it gets lost — route it to memory.
- Routing cross-host continuation into a machine-local handoff — the other host will never see it. Route it to the repo (STATUS.md).
- Committing a throwaway HANDOFF.md into the repo. The add→delete churn and the rotting consumed-handoff (the general-rag-cs failure mode) are exactly what this forbids — repo-side state lives in STATUS.md, updated in place.
- Dropping earlier rounds' dead-ends when re-handing off the same slug because "they're in archive/ anyway" — nothing reads archive/ on resume. Carry them forward, or sink them into STATUS.md (see W3 續寫交接).
- Concluding "no active handoff with this slug, so this is round 1" — a consumed handoff sits in archive/, which is exactly where round 2+ normally finds its predecessor. Check archive before deciding (W1).
- Treating the aggregate `verdict:` line as the verdict for every repo in a multi-anchor handoff. It is a rollup; reconcile per repo (R3).
- Reporting "no handoff exists" when `survey` listed the workline under `archive/`. It was consumed, not absent (R1).
- Treating a FRESH verdict on an archive-sourced handoff as permission to act on it directly. Archive provenance caps it at clue (R3).
- Pasting `anchors` output into the frontmatter after a non-zero exit. It prints nothing on failure — whatever you are looking at is from an earlier run (W2).

## Write mode（/clear 前交接）

### W1：範圍

依 session 記憶列出本次工作涉及的 repo（同跨 repo 工作流原則，**不掃 `~/Projects/`**；context 被壓縮就以 pwd 的 repo 為底請使用者補充）。多 repo = 同一份交接檔、多條錨點。

接著**定 slug 並判定首輪或續寫**。一律先跑一次 `survey`——**不論使用者有沒有指定 slug**：

```
~/.claude/skills/handoff/scripts/handoff-anchor.sh survey [--slug <slug>]
```

單一呼叫涵蓋四件事：清掉過保留期的 archive（先做）、`active:` 清單（含 EXPIRED，**W4 的 housekeeping 吃的就是這份輸出**）、`workline:` 既有工作線（archive 依 slug 聚合，附輪數與最近日期）、以及給了 `--slug` 時的 `predecessor:` 判定。

- **slug 已定**（含 `/handoff <slug>`）→ 直接 `survey --slug <slug>`。
- **slug 未定** → 先不帶 `--slug` 跑，從 `workline:` 看本次工作屬不屬於既有工作線：屬於就**沿用該 slug**、確定是全新工作線才自取；定出後再跑一次帶 `--slug` 確認。

`predecessor:` 有值（不是 `NONE`）→ **續寫**，把該路徑帶進 W3 的「續寫交接」；本 session 稍早 resume 過同一條工作線亦然。

兩個誤判方向都要防：只查 active 會把第 N 輪當成首輪（前一份通常已被消費進 archive）；不看既有工作線就自取新 slug，等於讓同一條工作線改名重啟。**定位一律走 `survey`，不要自己拼 glob**——`archive/*-<slug>.md` 看似尾錨定，`*` 卻吃得下中間的工作線名（查 `foo` 會撈到 `bar-foo`）。精確判準與 archive 檔名的身分解析政策以腳本檔頭為準，勿在此重組。

### W2：蓋錨點

```
~/.claude/skills/handoff/scripts/handoff-anchor.sh anchors <repo1> <repo2> ...
```

輸出的 `created:` + `anchor:` 行原樣放進 frontmatter。`anchors` 是**全有或全無**：任一 repo 的前提不成立（路徑不是 repo、含空白、repo 尚無 commit、status 讀不到）就一行都不印、exit 非零——**非零退出時不得使用本次任何輸出**，依 stderr 修正該 repo 的前提後重跑。錨點含 `dirty=N`：N>0 時在報告提醒「未 commit 內容只存在 working tree，/clear 不影響它、但它不受錨點保護」——建議先 commit（ship 走 `/project log`），本 skill 不代為 commit **code**（唯一例外：Critical 的跨主機 STATUS.md 分流 docs commit，見該節；仍不 push）。

### W3：寫檔

寫到 `~/.claude/handoffs/<slug>.md`；**同 slug 已存在 → 整檔覆寫**（更新錨點與內容），不 append、不留多版本。slug 勿以 `YYYYMMDD-HHMMSS-` 時戳格式開頭——那是 `consume` 判定「已歸檔」的保留命名空間，撞名會被拒收。模板：

```markdown
---
slug: <slug>
<W2 anchors 輸出原樣貼入：created 一行 + 逐 repo 的 anchor 行，行首即 created:/anchor:，不另加前綴>
---

# Handoff: <一句話標題>

## 目標
<這條工作線要達成什麼；怎樣算完成>

## 已完成
<條列；能對應 commit 的附 short sha>

## 關鍵決策（附理由）
<選了什麼、為什麼——沒有理由的決策會被新 session 翻案>

## 死路（試過但放棄——防重工）
<試過什麼、為何放棄；真的沒有才寫「無」>

## 下一步（逐條可執行）
1. <具體到新 session 能直接動手；多 repo 時每條標所屬 repo，如 `[krepo]`>

## 涉及檔案
<相對路徑；不存在的標「待新建」；多 repo 時分 repo 列>

## 坑
<已知陷阱、環境限制；無則省略本節>
```

內容規則（Critical 已定硬約束，這裡是品質要點）：死路一節是交接檔最值錢的部分，新 session 最容易在這裡重蹈覆轍；「下一步」寫到可直接執行，不寫「繼續完成」這種空話。多 repo 時「下一步」條目必須**看得出所屬 repo**——resume 端是逐 repo 對帳（R3），歸屬只藏在 `cd <path>` 指令裡就對不上帳。

#### 續寫交接（同 slug 第 2 輪起）

整檔覆寫意味著**前一份的內容不會自動留下**——resume 端沒有任何機制會去讀 archive。跨輪仍有效的死路與決策必須主動處理，否則多輪之後「防重工」就空了：

- **主路徑（repo 有 STATUS.md）**：跨輪仍有效的死路/決策沉澱進 dossier 對應章節，交接檔只留本輪增量 + 一句指標（如「既有死路見 STATUS.md 死路節，勿重開」）。這是全域 CLAUDE.md「死路當下寫入 STATUS.md」的自然延伸——dossier 隨 git 走且跨主機，交接檔消費即死。
- **Fallback（repo 無 dossier，或前一份不在本 session context——如未經 resume 直接 `/handoff <slug>`）**：Read W1 掃到的那一份（active 或 archive 皆可能），取其「死路」「關鍵決策」兩節，仍有效者逐條帶進新檔。不要憑本輪記憶重寫。

### W4：收尾報告

報告：檔案路徑、錨點摘要（含 dirty 提醒）、durable 事實路由結果（寫了哪些 memory / 無）。拿 W1 那次 `survey` 的 `active:` 區段做 housekeeping（不必重跑）——有 EXPIRED 的舊交接檔就列出，建議處置（resume 重驗或確認無用後刪；**刪除先經使用者同意**）。最後提醒：新 session 開場說「接續交接 <slug>」或 `/handoff resume <slug>`。

## Resume mode（新 session 接續）

### R1：定位

```
~/.claude/skills/handoff/scripts/handoff-anchor.sh survey [--slug <slug>]
```

指定了 slug 就用它；未指定且僅一份 active → 直接用；多份 → 列給使用者選。每份 `active:` 會附 `path:`（完整路徑，直接餵給下一步的 verify/consume）與 `title:`（多份時辨識工作線）。

**零份 active 不等於沒有交接檔。** `workline:` 或 `predecessor: …（archive）` 命中，代表這條工作線的前一份**已經被消費過**（前一個 session 載入它並開工，之後 session 才結束）。此時：報告它何時被消費、內容依 R3 的信任上限當**線索**、**不要對它呼叫 `consume`**（consume-once 會機械拒絕），並問使用者是要據此接續、還是這是新一輪。active 與 archive **都**零命中，才是真的沒有交接檔——明說並請使用者指路（不要憑空猜工作內容）。

### R2：驗證

```
~/.claude/skills/handoff/scripts/handoff-anchor.sh verify <handoff.md>
```

單一呼叫涵蓋年齡（EXPIRED）與全部錨點（FRESH / DRIFTED / DIVERGED / MISSING），**勿逐條重跑底層 git 指令**。無錨點的檔（如手寫的）會判 UNVERIFIABLE——當線索不當事實。

### R3：對帳（reconcile）

**逐 repo 判定、逐 repo 處置**：先把「下一步」各條歸屬到 repo，再套該 repo 的 status。`verify` 尾行的 `verdict:` 只是**全域聚合旗標**（任一 repo 非 FRESH 即 `STALE-RISK`），多錨點時拿它一刀切整份交接檔，會讓 FRESH repo 的下一步被無謂降級。

| 該 repo 的 status | 處置 |
|---------|------|
| FRESH | 該 repo 的內容可信，直接依「下一步」接續 |
| DRIFTED | 讀 verify 列出的中間 commits（必要時 `git show`）逐條對帳，**報告落差**後依性質分流：「下一步已被做掉」→ 標記不重做、其餘項照做；**「決策被推翻」→ 停下等使用者確認**——要沿用新方向還是回退是人的判斷，在那之前不動受該決策影響的項目 |
| DIVERGED / MISSING / BAD-ANCHOR | 該 repo 的內容降級為線索；對 repo 重建現況，落差大就先報告等指示 |

檔案級的 **EXPIRED**（超過 EXPIRE_DAYS）與 **UNVERIFIABLE**（無錨點）不分 repo，**整份**降級為線索。

**Archive provenance caps trust; verify can only lower it, never raise it.** 交接檔來自 `archive/`（R1 的 archive 命中）時，**即使 verify 判 FRESH 也只是線索**，不得套用上表 FRESH 列的「直接接續」。它已經被消費過——前一個 session 載入它並開始動工，而**未 commit 的進度不會讓錨點漂移**：FRESH 只證明沒有新 commit，不證明沒人動過。依賴的每一條都要對 repo 現況重新核對。

### R4：消費歸檔，然後開工

計畫確立後、動工前，依交接檔的來源分流：

- **來自 active** → 歸檔（消費）後才開工：

  ```
  ~/.claude/skills/handoff/scripts/handoff-anchor.sh consume <handoff.md>
  ```

  位置驗證、archive 建立、時戳前綴、重複消費拒絕都在子指令內——**do not hand-type the mkdir/mv sequence**。照 `archived:` 行回報「交接檔已消費歸檔」，然後才開始執行工作。若中途發現還需要它，archive/ 內在保留期內都找得回（超過 ARCHIVE_KEEP_DAYS 由 `survey` 自動清）。

- **來自 archive**（R1 的 archive 命中）→ **NEVER consume it again.** 它已經是消費過的稽核紀錄，`consume` 會機械拒絕。verify 與對帳照做（受 R3 的信任上限約束），然後直接開工。

開工後若誤 commit 在 default branch，走 `~/.claude/skills/project/references/ship-paths.md`「Branch-first 與誤 commit 搬移」的救援序列（該檔為權威，本節不重述）。「commit 前先開 feature branch」本身已是全域規則、不隨 skill 載入與否而變，故此處不重述。Ship 走 `/project log`，**本 skill 不 push**。

## 生命週期總覽

```
write（蓋錨點）→ ACTIVE（~/.claude/handoffs/*.md）
                    │ 超過 EXPIRE_DAYS 未消費 → survey/verify 標 EXPIRED（重驗或確認後刪）
                    ▼ resume 消費（verify → reconcile → consume）
                 ARCHIVE（archive/YYYYMMDD-HHMMSS-*.md）
                    │ survey 仍列為 workline：已消費的線索，不再 consume
                    ▼ 超過 ARCHIVE_KEEP_DAYS
                 由 survey 自動刪除
```

失效內容的三道防線：錨點讓過時**可偵測**（DRIFTED/DIVERGED）、消費即歸檔讓已用內容**不佔檯面**、TTL 讓被遺忘的檔**有期限**。

## 設計備忘

- 分工：durable 事實 → memory（`/ready4quit` Step 2 也會抓漏）；git ship → `/project log`；review → `/deep-review`；**跨主機**延續 → repo STATUS.md（git 為唯一跨機媒介）。本 skill 只管「暫時性任務狀態在**同一台主機**上跨 /clear 存活」。
- 典型流程：`/deep-review` → `/project log`（ship）→ `/handoff`（同主機要延續的工作線）→ `/ready4quit` → `/clear` 或 `/quit`。
- 交接檔品質仰賴主 session 的對話記憶——write mode 越晚跑、context 被壓縮得越多，死路與決策理由越難完整。快壓縮前就該交接。
