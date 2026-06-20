---
name: ready4quit
description: "End-of-session pre-quit flush — 結束 Claude Code session 前的收尾總檢查：驗證 git 殘留（未 commit/未 push/待開 PR）、flush 本 session 學到但未寫進 memory 的事實、盤點還在跑的背景/排程任務、列出未了結的 TODO，產出『可否 /quit』的總結與待辦 gate。Use before quitting or ending a session — Chinese triggers 「ready4quit」「收尾」「準備結束」「可以 quit 了嗎」「sync 一下」「結束前檢查」「退出前」. Report-first; outward or destructive flush (push, kill task, delete memory) needs explicit confirmation; recommends /uap for git residue rather than shipping itself."
user-invocable: true
disable-model-invocation: true
argument-hint: "[--flush]"
---

# Ready4Quit — 結束 Session 前的收尾 Flush

心智模型：reboot 前的 `sync;sync;sync`。把這個 session 裡**易失（volatile）、一旦 `/quit` 就永久消失**的狀態 flush 到持久層，並把「還沒收乾淨」的殘留攤在檯面上，讓你能安心退出。本 skill **不**自己 ship、不自己 kill、不自己 push——它先驗證、再報告、危險動作等你點頭。

## 引數

- **預設 `/ready4quit`** — report-first：先驗證、給報告，收尾動作多數列給你挑（新增 memory 這類可逆附加動作會在報告後直接寫，並列出寫了/跳過什麼）。
- **`--flush`** — 對**安全且可逆**的收尾更積極、少問你幾次（寫 memory、收無爭議的小 loose end 直接做掉）。**對外/破壞性動作（push、kill task、刪 wakeup/cron、覆寫既有 memory）不受 `--flush` 影響，一律照常先確認**（見 Critical）。整體仍走 report-first，只是 Step 5 的安全項執行強度更高。

**Violating the letter of the rules below is violating their spirit.** Do not rationalize a green verdict you did not actually verify.

開始時**複製這份 checklist 進回應**並逐項勾選：

```
Ready4Quit 進度：
- [ ] Step 1：Git 衛生（逐 session repo 驗證未 commit / 未 push / 待開 PR）
- [ ] Step 2：記憶 flush（盤點 session 學到但未寫進 memory/ 的事實）
- [ ] Step 3：背景/排程任務（background Bash / Task / loop / ScheduleWakeup / cron）
- [ ] Step 4：未了結 loose ends（答應要做卻沒做的 TODO / half-done / 待你決定的開放問題）
- [ ] Step 5：總結 verdict（逐面向 GREEN/待辦）→ flush gate（安全項確認後執行，對外項先確認）
```

## Critical — Guardrails

硬約束，做任何 flush 動作前先讀。

- **Report-first.** 預設只驗證與報告。產出總結後才提出 flush 動作，不在使用者沒看到報告前就動手收尾。
- **NEVER push / open PR here.** Git 殘留只**建議** `/uap`，本 skill 不 commit、不 push、不開 PR、不 merge。Ship 是 `/uap` 的事。
- **Outward / destructive flush needs explicit confirmation.** Kill 背景任務、刪 ScheduleWakeup/cron、刪除既有 memory 檔——一律先列出、等明確同意，沒同意 → 不做。
- **Memory writes are additive but still surface them.** 新增 memory 檔是可逆的附加動作，可在報告後直接寫，但**必須在報告中列出寫了什麼、跳過什麼**，不靜默塞。
- **Don't rubber-stamp.** 每個面向都要**實際跑指令/掃描**才能標 GREEN。沒查就說「應該沒問題」= 違規。

### Red Flags — STOP and re-read Critical

- Declaring any dimension GREEN you never actually inspected (no `git status` output, no `TaskList`/`CronList` check, no scan).
- About to `git push` / `gh pr` / kill a task / delete a wakeup/cron/memory file from inside this skill without listing it and getting an explicit yes.

> 此 skill 的核心不是「對抗合理化」（baseline 顯示 agent 天生會查 git、不擅自動手），而是**覆蓋度**——提醒別只顧 git，還要 flush memory、盤點 async 狀態、掃 loose ends，這些是 fresh agent 想不到要查的。

---

## Step 1：Git 衛生（驗證，不 ship）

對本 session **動過檔案的所有 repo**（+ pwd 所在 repo）逐一驗證殘留——依 session 記憶列出 repo，**不掃 `~/Projects/`**（同 `/uap` Step 0 的範圍原則）。context 被壓縮就以 pwd 的 repo 為底，請使用者補充還涉及哪些 repo。

每個 repo 跑：

- `git -C <repo> status --porcelain`（含 untracked）→ 有輸出 = **未 commit 殘留**。
- `git -C <repo> log --oneline @{upstream}..HEAD 2>/dev/null`；無 upstream 時改 `git -C <repo> log --oneline origin/<default>..HEAD`（`<default>` = `origin/HEAD` 的 basename，失敗則試 `main`/`master`）→ 有輸出 = **未 push commit**。
- 若已在 feature branch 且有 commit 但無 PR（`gh pr view --json url 2>/dev/null` 失敗/空）→ **待開 PR**。

**只報告，不收尾。** 任一項有殘留 → 在總結建議：「git 有殘留，結束前先跑 `/uap` ship 掉」。git 細節（branch-first、protection、PR）全交給 `/uap`，本 skill 不重做。

## Step 2：記憶 flush（持久化易失知識）

掃過本 session，盤點「對未來 session 有價值、但還沒寫進 memory/」的事實。對照記憶系統四型：

- **user**：使用者身分/偏好/專長中本 session 才揭露的。
- **feedback**：使用者這次給的工作方式糾正或確認（附 **Why** / **How to apply**）。
- **project**：進行中工作的目標/約束，**且 code、git history、CLAUDE.md 都查不到**的。
- **reference**：本 session 出現、值得留存的外部資源（URL / dashboard / ticket）。

判讀規則（避免噪音）：

- repo 結構、過往修法、git history、CLAUDE.md 已記錄的 → **不存**。
- 只對本次對話有意義的 → **不存**。
- 存之前先比對既有 memory 檔，覆蓋同一主題就**更新該檔**，不要建重複檔。
- 候選為空 → 在報告**明說「本 session 無新增 memory」**，不要靜默跳過。

flush 方式：在總結列出候選（type + 一句摘要）；新增 memory 檔是可逆附加動作，可直接寫（依記憶系統 frontmatter 格式 + 在 `MEMORY.md` 補一行索引），但報告須列出**寫了哪些、跳過哪些**。**刪除/覆寫既有 memory 屬破壞性** → 先確認。

## Step 3：背景 / 排程任務盤點

列出仍綁在本 session、會隨 `/quit` 一起死掉，或會在你離開後繼續跑的非同步狀態：

- **background Bash**：本 session 用 `run_in_background` 啟動、還沒結束的指令。
- **Task / subagent**：用 `TaskList` 查仍在 running 的 agent。
- **/loop**：本 session 設過的循環任務。
- **ScheduleWakeup**：已排定的 wakeup（會在未來再叫醒這條 session——若 session 已 quit 行為需提醒）。
- **cron / routine**：用 `CronList` 查本 session 建立、預期持續的排程（這類**本應**在 session 外存活，重點是區分「該留」vs「忘了清的臨時排程」）。

報告每一項的狀態與建議（留著 / 等它跑完 / 該清掉）。**Kill 任何一項都要先確認**——尤其別誤殺使用者刻意留的長期 cron。

## Step 4：未了結的 loose ends

掃對話，盤點答應過、但到 session 結束仍未閉合的事：

- 明確說「等下做 / 接著處理」卻沒做的 TODO。
- half-done 的任務（改到一半、測到一半）。
- 丟給使用者、還沒回的開放問題 / 待決策點。
- 跑失敗還沒重試或還沒交代結論的步驟。

列成清單，每項標「未做 / 半成品 / 待你決定」。**只盤點不自動補做**——是否在 quit 前收掉由使用者決定（小事可順手做，但大改不要在收尾階段擅自展開）。

## Step 5：總結 verdict → flush gate

印出一份「可否 `/quit`」總結，逐面向標狀態：

```
Ready4Quit 收尾報告：
  Git 衛生        ⚠ krepo 有 3 檔未 commit、pilot-api 有 1 未 push commit → 建議先 /uap
  記憶 flush      ✓ 已寫 2 筆（feedback: …／project: …）；跳過 1 筆（CLAUDE.md 已記）
  背景/排程       ⚠ 1 個 background crawler 仍在跑（task#3）；cron daily-backfill 為刻意保留
  Loose ends      ⚠ 待你決定：API schema 用 v2 還是 v3（Step 4 問過未回）
  ────────────────────────────────────────
  Verdict：尚有待辦。處理完即可安全 /quit。
```

接著：

- **安全項**（已寫的 memory）→ 已執行，報告中明列。
- **對外 / 破壞性項**（建議的 `/uap`、要 kill 的背景任務、要刪的 wakeup/cron）→ **列出選項等使用者點頭**，不自動做。
- 全面向皆 GREEN → 明確說「volatile 狀態已 flush，可安全 `/quit`」。

`--flush` 引數的行為見開頭〈引數〉節（單一來源）——本步是它生效的地方：帶 `--flush` 時，Step 5 對安全可逆項的執行強度更高，對外/破壞性項仍照常先確認。

---

## 設計備忘

- 本 skill 是 **pre-quit 驗證 + flush 階段**，不是 ship、不是 review。git 殘留交 `/uap`，需要 review 交 `/deep-review`。
- 與 `/uap` 銜接：典型流程 `/deep-review` → `/uap`（ship）→ `/ready4quit`（最後收尾確認）。`/uap` 已處理 git，本 skill 多半在 Step 1 只做驗證、其餘力氣放在 memory / 背景 / loose ends。
- 核心鐵則：**不在沒實際檢查的情況下宣告「可以退出」**——每個 GREEN 都要有對應的指令輸出或掃描根據。
