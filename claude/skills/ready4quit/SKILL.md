---
name: ready4quit
description: "End-of-session pre-quit flush — 結束 Claude Code session 前的收尾總檢查：驗證 git 殘留（未 commit/未 push/待開 PR）、flush 本 session 學到但未落到持久層的事實（memory 與 repo dossier 分流）、盤點還在跑的背景/排程任務、列出未了結的 TODO，產出『可否 /quit』的總結與待辦 gate。Use before quitting or ending a session — Chinese triggers 「ready4quit」「收尾」「準備結束」「可以 quit 了嗎」「sync 一下」「結束前檢查」「退出前」. Never commits, pushes, or opens PRs — git residue always routes to /project log; destructive flush (kill task, delete cron/memory) needs explicit confirmation; additive writes are done up front and itemised in the report. Verdict carries an evidence level, never claiming more certainty than the checks produced."
user-invocable: true
disable-model-invocation: true
---

# Ready4Quit — 結束 Session 前的收尾 Flush

心智模型：reboot 前的 `sync;sync;sync`。把這個 session 裡**易失（volatile）、一旦 `/quit` 就永久消失**的狀態 flush 到持久層，並把「還沒收乾淨」的殘留攤在檯面上，讓你能安心退出。本 skill **不**自己 ship、不自己 kill、不自己 push——它先驗證、再報告、危險動作等你點頭。

## 證據強度 × 殘留狀態（verdict 的語彙）

**兩個獨立維度，必須分開標。** 把它們壓成一個標籤，就會產出「已知的 loose end 被標成沒有已知殘留、然後宣告無 blocker」這種自相矛盾的報告。本 skill 最大的失效模式不是漏查，而是**讓 verdict 的可信度高於實際證據**。

**證據強度**——這個面向查得多完整：

| 等級 | 意思 | 典型情況 |
|------|------|----------|
| **VERIFIED** | 有指令／工具的實際輸出為憑 | `git-hygiene.sh` 輸出、`tasks/` 列表、`CronList` 有回應 |
| **RECALLED** | 只能靠 session 記憶回溯，**本質不可枚舉** | loose ends、`/loop`、ScheduleWakeup、涉及哪些 repo |
| **PARTIAL** | 該查的查不到 | 工具不可用、fetch 失敗、context 被壓縮過、腳本判 UNKNOWN |

**殘留狀態**——實際找到了什麼：`✓` 無殘留／`⚠` 有殘留（後面接具體項目）。

- **Only `VERIFIED + ✓` may be reported as GREEN.**
- `RECALLED + ✓` → 只能說「沒有已知殘留」，**不可**說成「已驗證乾淨」。
- **任何 `⚠` → 有殘留，verdict 一律 NOT READY**，與證據強度無關（RECALLED 找到的殘留一樣是殘留）。
- **`⚠` means residue was actually FOUND. Being unable to check is NOT residue.** 查不到 → 把**證據強度**降成 `PARTIAL`，殘留欄仍是 `✓`（確實沒找到東西）。`⚠` 後面永遠接得出具體項目；接不出來就不是 `⚠`。
- 任何 `PARTIAL` → 明說哪一項查不到、為什麼，由使用者決定要不要帶著它退出。

兩軸會朝**兩個方向**塌陷，都要防：把找到的殘留說成沒有（證據不足 → 標 `✓`），以及把查不到說成有殘留（不確定 → 標 `⚠`）。後者產出的報告會宣告 NOT READY 卻指不出任何待辦，一樣是 verdict 與證據對不上。

## 動作邊界（什麼可以直接做）

三類，界線**不可互相滲透**：

- **NEVER — 無論是否同意都不在這裡做**：`commit`、`push`、開 PR、merge；**rewriting, deleting, moving, or compacting an existing dossier entry**。Git 殘留永遠只有一個建議：跑 `/project log`。**使用者說「你直接 commit 吧」也不做**——那是 `/project log` 的權責，不是一句同意就能移轉過來的；dossier 的改寫與整理同理，權責在 `/project log` Step 2，**consent does NOT move it here**。
- **需明確同意才做**：kill 背景任務、刪 ScheduleWakeup/cron、**刪除既有 memory 檔，或以會抹掉既有內容的方式改寫它**。一律先列出、等點頭。
- **Additive 且可逆 → 可直接做**：新增 memory 檔、**對既有 memory 檔同主題純附加**（既有內容一字不動，新條目追加在後；`MEMORY.md` 索引行就地補述同屬此類）、補 STATUS.md 漏記的決策／死路條目。但**必須在報告中逐筆列出做了什麼、跳過什麼**。

判準是**既有內容有沒有被抹掉**，不是「檔案存不存在」——對既有檔純附加沒有損失任何東西，逼一輪往返只是把 additive 出口切成兩半（新增免問、更新要問），而兩者的可逆性相同。

`report-first` 約束的是前兩類：**不在使用者看到報告前做任何對外或破壞性動作**。第三類可以先做——單一份報告即為完整交代，不需要兩階段往返。

**Violating the letter of the rules below is violating their spirit.** Do not rationalize a green verdict you did not actually verify.

開始時**複製這份 checklist 進回應**並逐項勾選：

```
Ready4Quit 進度：
- [ ] Step 1：Git 衛生（逐 session repo 驗證未 commit / 未 push / 待開 PR）
- [ ] Step 2：持久化 flush（session 學到的事實 → memory / dossier 路由）
- [ ] Step 3：背景/排程任務（background Bash / Task / loop / ScheduleWakeup / cron）
- [ ] Step 4：未了結 loose ends（答應要做卻沒做的 TODO / half-done / 待你決定的開放問題）
- [ ] Step 5：總結 verdict（逐面向標證據強度 + 殘留狀態）→ 對外/破壞性項列選項等確認
```

## Critical — Guardrails

硬約束，做任何 flush 動作前先讀。

- **Report-first for outward / destructive actions.** 那些動作一律先出現在報告裡等你點頭；additive 寫入可先做，但必須逐筆列出（範圍見〈動作邊界〉，單一來源）。
- **NEVER push / open PR here.** Git 殘留只**建議** `/project log`，本 skill 不 commit、不 push、不開 PR、不 merge。Ship 是 `/project log` 的事。
- **Outward / destructive flush needs explicit confirmation.** Kill 背景任務、刪 ScheduleWakeup/cron、刪除既有 memory 檔或抹掉其既有內容——一律先列出、等明確同意，沒同意 → 不做。
- **Memory writes are additive but still surface them.** 新增 memory 檔、或對既有檔同主題純附加，都是可逆的附加動作，可直接寫，但**必須在報告中列出寫了什麼、跳過什麼**，不靜默塞。
- **Dossier writes are additive and stop at the working tree.** 補寫 STATUS.md 漏記的決策/死路同屬可逆附加動作，可直接寫；但 **writing the working tree is NOT shipping** —— 本 skill 仍不 commit、不 push，且不改寫既有條目、不整理 dossier。
- **Don't rubber-stamp.** 每個面向都要**實際跑指令/掃描**才能標 GREEN。沒查就說「應該沒問題」= 違規。

### Red Flags — STOP and re-read Critical

- Declaring any dimension GREEN you never actually inspected (no `git-hygiene.sh` output, no `tasks/` listing, no `CronList` check, no scan).
- Reporting RECALLED as GREEN. "I didn't see any" is not "I verified there are none" — name which one it is, every time.
- Marking a dimension `✓` while listing an actual open item under it. Evidence strength and residue are separate axes: RECALLED still takes `⚠` the moment you find something.
- Marking a dimension `⚠` when you found nothing, because the check could not be completed. Uncertainty belongs on the evidence axis (`PARTIAL`), never on the residue axis. Writing "⚠ 沒有殘留，但查不到" contradicts itself and forces a NOT READY that names no actual to-do.
- Inferring a background task's liveness from its `.output` size or contents. A silent command leaves an empty file too.
- Treating a `git-hygiene.sh` CLEAN as proof the remote agrees when the same output says `remote: UNKNOWN`. A stale tracking ref makes `unpushed: none` meaningless.
- Reading `TaskList` as the background-task check. It lists `TaskCreate` to-dos, not background shells or subagents — an empty result proves nothing about what is still running.
- About to `git push` / `gh pr` / kill a task / delete a wakeup/cron/memory file from inside this skill without listing it and getting an explicit yes.
- Offering to `git commit` for the user — even "just say yes and I'll commit". Git residue has exactly ONE recommendation: run `/project log`. "The user would approve it anyway" does not move commit/ship into this skill.
- Routing a decision or dead-end into machine-local memory **when that repo has a STATUS.md**. That is exactly how it gets lost — memory does not travel between hosts. Route it to the dossier. (No dossier at all? Then memory is the stated fallback — but say so in the report and point at `/project spec`; see the routing table.)
- Tidying the dossier during a pre-quit flush — moving 進行中 items into 里程碑, rewriting entries, compacting sections. Additive only; distillation belongs to `/project log`.

> 此 skill 的核心不是「對抗合理化」（baseline 顯示 agent 天生會查 git、不擅自動手），而是**覆蓋度**——提醒別只顧 git，還要 flush memory、盤點 async 狀態、掃 loose ends，這些是 fresh agent 想不到要查的。

---

## Step 1：Git 衛生（驗證，不 ship）

對本 session **動過檔案的所有 repo**（+ pwd 所在 repo）逐一驗證殘留——依 session 記憶列出 repo，**不掃 `~/Projects/`**（同 `/project log` Step 0 的範圍原則）。context 被壓縮就以 pwd 的 repo 為底，請使用者補充還涉及哪些 repo。

**單一呼叫**跑完所有 repo 的全部檢查（未 commit / 未 push / 待開 PR 的偵測與 fallback 邏輯都在腳本內）：

```
~/.claude/skills/ready4quit/scripts/git-hygiene.sh <repo1> <repo2> ...
```

腳本逐 repo 輸出 `remote` / `uncommitted` / `baseline` / `unpushed` / `pr` 與 verdict，判讀：

- **RESIDUE** → 有殘留（未 commit / 未 push / 無 PR / PR 是 DRAFT 或 CLOSED），細項見各欄位。
- **UNKNOWN**（`remote: UNKNOWN`、`NO-REMOTE`、`NONE` baseline、gh 查詢失敗等）→ 該項**無法驗證**。**UNKNOWN is NOT clean** — report it as unverifiable, never GREEN.
- **CLEAN** → 每一項都實查為空，可標 VERIFIED / GREEN（腳本輸出就是證據）。

兩個欄位特別要看懂：

- **`remote:`** —— 腳本會先 `fetch --prune` 讓 tracking ref 反映此刻遠端。印 `UNKNOWN` 代表 fetch 失敗／逾時，此時 `unpushed` 一律降為 UNKNOWN：**遠端 branch 被刪掉或 force-push 後，本機 cache 仍會讓 `unpushed: none` 看起來很乾淨**。
- **`pr:`** —— `DRAFT`（草稿未真正送審）與 `CLOSED`（未合併就關掉，變更沒進去）都算殘留；`MERGED` 不算殘留（squash merge 後 branch 的 commit 不在 default 歷史裡是正常的），只是 branch 可以清掉。

Do not re-run the underlying git commands one by one — the script IS the check; one call covers all repos.
（腳本會逐 repo `fetch --prune` 該 repo 的 remote，每個硬上限 8 秒——多 repo 時要等幾秒。這是拿「遠端事實」換的，別因為慢就改回本機比對。）

**只報告，不收尾。** 任一項有殘留 → 在總結建議：「git 有殘留，結束前先跑 `/project log` ship 掉」。git 細節（branch-first、protection、PR）全交給 `/project log`，本 skill 不重做。

## Step 2：持久化 flush（memory / dossier 路由）

掃過本 session，盤點「對未來有價值、但還沒落到持久層」的事實。**先判去哪，再判存不存**——兩個出口的存活範圍不同（memory 不跨主機、repo 跟著 git 走；判準與理由的單一來源是全域 CLAUDE.md「跨主機工作流」節）：

| 事實 | 出口 |
|------|------|
| **user** / **feedback** 型 | memory —— machine-local 正是對的層 |
| **project** 型：本 session 的關鍵決策 / 死路 / 新增技術債，且屬某個**有 STATUS.md 的 repo** | 該 repo 的 **STATUS.md** 對應章節，不進 memory（該 repo 有 `docs/backlog.md` 時，技術債／缺口寫那裡）|
| **project** 型：該 repo **無** STATUS.md | 暫存 memory，**且報告必須明說「此 repo 無 dossier，這筆跨不了主機」**並建議跑 `/project spec` 建檔後搬過去。**不在這裡建 STATUS.md** |
| **reference** 型 | 綁專案 → STATUS.md；綁使用者工作流 → memory |

檢查對象＝Step 1 已列出的那組 repo 中有 `STATUS.md` 者（**不掃 `~/Projects/`**）。

### memory 出口

四型定義：**user**（身分/偏好/專長中本 session 才揭露的）、**feedback**（工作方式的糾正或確認，附 **Why** / **How to apply**）、**project**（工作目標/約束，**且 code、git history、CLAUDE.md、STATUS.md 都查不到**的）、**reference**（值得留存的外部資源：URL / dashboard / ticket）。

判讀規則（避免噪音）：

- repo 結構、過往修法、git history、CLAUDE.md／STATUS.md 已記錄的 → **不存**。
- 只對本次對話有意義的 → **不存**。
- 存之前先比對既有 memory 檔，覆蓋同一主題就**更新該檔**，不要建重複檔。

新增 memory 檔是可逆附加動作，可直接寫（依記憶系統 frontmatter 格式 + 在 `MEMORY.md` 補一行索引）。**同主題更新既有檔時只附加、不動既有內容**（`MEMORY.md` 已有的索引行就地補述，不新增重複列）——同屬 additive，可直接寫。**刪除既有 memory 檔，或改寫／移除其既有內容，屬破壞性** → 先確認。

### dossier 出口

寫入該 repo `STATUS.md` 的對應章節（章節語意與條目格式的單一來源：`~/.claude/skills/project/references/dossier.md`），**寫 working tree、不 commit**——全域規則本就要求決策當下就地寫入，這裡是補做遲到的動作。

- **Additive only. NEVER rewrite or delete an existing entry, NEVER move 進行中 items into 里程碑, NEVER compact or distill the dossier here** —— 那是 `/project log` Step 2 的職責，pre-quit 不做整理；dossier 尺寸治理同樣不在本 skill 範圍。
- **NEVER create a STATUS.md that does not exist** —— 建 dossier 是 `/project spec` 的事；該 repo 的 project 型事實依路由表走 memory 回落並在報告標示，不是在這裡開檔。
- 寫入會**新增 git 殘留**：Step 5 的 Git 衛生行須反映，並提示需 `/project log` 送出。

兩個出口都要在報告列出**寫了哪些、跳過哪些**；候選為空 → **明說「本 session 無新增 memory／dossier」**，不要靜默跳過。

## Step 3：背景 / 排程任務盤點

列出仍綁在本 session、會隨 `/quit` 一起死掉，或會在你離開後繼續跑的非同步狀態：

- **background Bash / subagent**：本 session 用 `run_in_background` 或 Agent 啟動、可能還沒結束的。
- **/loop**：本 session 設過的循環任務。
- **ScheduleWakeup**：已排定的 wakeup（會在未來再叫醒這條 session——若 session 已 quit 行為需提醒）。
- **cron / routine**：本 session 建立、預期持續的排程（這類**本應**在 session 外存活，重點是區分「該留」vs「忘了清的臨時排程」）。

證據來源分三類，標 GREEN 的根據各不相同：

**① background Bash / subagent —— 列 session 的 tasks 目錄**

harness 把本 session 每個背景任務的 output 檔放在 **scratchpad 目錄的同層 `tasks/`**（scratchpad 路徑見 system prompt；勿硬編 session id）：`ls -la <scratchpad 同層>/tasks/`，每個 `<task-id>.output` 即一個背景任務。

- **`TaskList` 查不到背景任務**——它列的是 `TaskCreate` 的待辦清單。**Never treat an empty `TaskList` as evidence that no background task is running.**
- **`tasks/` 只能拿來枚舉「有哪些背景任務」，判不了死活。** output 檔在任務結束後仍留著；**空檔可能是靜默完成、也可能是還沒輸出；有內容一樣可能還在跑**——`.output` is NOT a liveness oracle，不可用它的大小或內容推斷狀態。
- 死活只有兩個來源：`TaskOutput`（deferred，需 `ToolSearch`）帶 `block=false` 的狀態，或 harness 送達的完成通知。**兩者都拿不到 → 該任務標 PARTIAL**，照實說「列得出來、但確認不了還在不在跑」。
- **`ls -la` 顯示為 symlink（`->`）的 `.output` 是 subagent 的完整 transcript — NEVER Read it; it will overflow the context window.** 一律改用 `TaskOutput`。
- 目錄不存在（harness 版本差異）→ 併入 ③ 處理，**不可**當成「沒有背景任務」。

**② cron / routine —— `CronList`**

deferred tool，先一輪 `ToolSearch`（`select:CronList`）載入 schema 再呼叫；有實際輸出才算查過。

**③ /loop 與 ScheduleWakeup —— 無列表工具**

只能靠 session 對話記憶回溯，本質不可枚舉 → 證據強度最高只到 **RECALLED**，永遠不是 VERIFIED。context 若被壓縮過，降為 **PARTIAL** 並明說「依記憶回溯，可能不完整」。**找到殘留就標 `⚠`**——RECALLED 說的是「查得多完整」，不是「有沒有東西」。

報告每一項的狀態與建議（留著 / 等它跑完 / 該清掉）。**Kill 任何一項都要先確認**——尤其別誤殺使用者刻意留的長期 cron。

## Step 4：未了結的 loose ends

掃對話，盤點答應過、但到 session 結束仍未閉合的事：

- 明確說「等下做 / 接著處理」卻沒做的 TODO。
- half-done 的任務（改到一半、測到一半）。
- 丟給使用者、還沒回的開放問題 / 待決策點。
- 跑失敗還沒重試或還沒交代結論的步驟。

列成清單，每項標「未做 / 半成品 / 待你決定」。**只盤點不自動補做**——是否在 quit 前收掉由使用者決定（小事可順手做，但大改不要在收尾階段擅自展開）。

本面向靠對話記憶，證據強度**最高只到 RECALLED**；context 被壓縮過就是 PARTIAL。列出的每一項都是殘留 → 該面向標 `⚠`，verdict 一律 NOT READY。

## Step 5：總結 verdict → 對外項 gate

印出一份「可否 `/quit`」總結。**每一面向都要標證據等級**（見開頭〈證據等級〉，單一來源）：

```
Ready4Quit 收尾報告：
  Git 衛生      [VERIFIED] ⚠ repo-a 3 檔未 commit、repo-b 1 未 push → 建議先 /project log
  持久化 flush  [VERIFIED] ✓ memory 寫 2 筆（feedback: …／user: …）
                           ✓ dossier 寫 1 筆（repo-a 死路節：試過 X 因 Y 放棄）
                             ↳ STATUS.md 未 commit，需 /project log 送出
                           ✓ 跳過 1 筆（STATUS.md 決策節已記）
  背景/排程     [PARTIAL]  ⚠ tasks/ 列到 1 個（b1ada7mt7）；TaskOutput 與 CronList 皆不可用
                             ↳ 該任務死活確認不了、cron 完全沒查到
  Loose ends    [RECALLED] ⚠ 待你決定：API schema 用 v2 還是 v3（Step 4 問過未回）
  ────────────────────────────────────────
  Verdict：NOT READY（有殘留）。另有一項背景狀態只到 PARTIAL，查不到死活。
```

接著：

- **已做的 additive 項**（寫入的 memory 檔、補上的 dossier 條目）→ 逐筆列出；dossier 寫入須同時更新 Git 衛生行的殘留敘述。
- **對外 / 破壞性項**（建議的 `/project log`、要 kill 的背景任務、要刪的 wakeup/cron）→ **列出選項等使用者點頭**，不自動做。
- 收斂語句由兩個維度共同決定，不可越級：
  - **任何面向是 `⚠` → NOT READY**，先講殘留，證據強度不能拿來淡化它。
  - 全部 `✓` 且全部 VERIFIED → 「volatile 狀態已 flush，**可安全** `/quit`」。
  - 全部 `✓` 但最低只到 RECALLED → 「**沒有已知**殘留，可以 `/quit`」——不可說成已驗證乾淨。
  - 任何 PARTIAL → 額外點名**哪一項查不到、為什麼**，由使用者決定要不要帶著它退出。

---

## 設計備忘

- 本 skill 是 **pre-quit 驗證 + flush 階段**，不是 ship、不是 review。git 殘留交 `/project log`，需要 review 交 `/deep-review`。
- 與 `/project log` 銜接：典型流程 `/deep-review` → `/project log`（ship）→ `/ready4quit`（最後收尾確認）。`/project log` 已處理 git，本 skill 多半在 Step 1 只做驗證、其餘力氣放在 memory / dossier / 背景 / loose ends。
- Step 2 的 dossier 出口針對的是 **`/project log` 沒被觸發**的情況：它的 Step 2 本就會核對補漏 dossier，但 git 乾淨時使用者沒有理由 ship——本 session 產生的決策/死路就沒有任何一步接住。有殘留時仍是導向 `/project log`，本 skill 不重做蒸餾。
- 核心鐵則：**不在沒實際檢查的情況下宣告「可以退出」**——每個 GREEN 都要有對應的指令輸出或掃描根據。
