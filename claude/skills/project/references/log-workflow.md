# Project Log workflow

本檔是 `/project log` 的完整執行程序；`../SKILL.md` 觸發 Log 模式時必須全文讀取。

## 目錄

- Log 模式與 checklist
- Critical guardrails
- Step 0：範圍鎖定
- Step 1：狀態與流程偵測
- Step 2：文檔同步與 doc audit
- Step 3：Adaptive 提交
- Step 4：Ship 摘要與授權
- Step 5：依路徑送出

## Log 模式（/project log，= 舊 /uap 超集）

把（通常已通過 review 的）變更收尾送出：偵測狀態 → 依 repo 流程定路徑（**branch 先決，先於 commit**）→ 同步 active/history/backlog 與必要文檔 → adaptive 提交 → 依 protection 走 PR 或直接 push。支援跨 repo。銜接 `/deep-review` 結尾（feature branch + 乾淨 commit + 未 push）。

**Violating the letter of the rules below is violating their spirit.** Do not rationalize around them.

開始前**複製這份 checklist 進回應**並逐項勾選：

```
Project Log 進度：
- [ ] Step 0：多 repo 偵測（單 repo 跳過）
- [ ] Step 1：逐 repo 狀態 + 流程偵測（default branch / 變更集 / protection / ship 路徑 / branch-first）
- [ ] Step 2：同步 active/history/backlog 與受影響文檔
- [ ] Step 3：adaptive 提交（未 commit→code+docs 同 commit；已 commit→獨立 docs commit）
- [ ] Step 4：印 ship 摘要 →（有說法直接執行／無說法問一題；`verdict: STOP` 一律停）
- [ ] Step 5：依路徑送出（PR 或直接 push）；輸出 PR URL / push 結果
```

**輕量判準（fast path）**——以下**全部**成立時，儀式面從簡：免貼上方 checklist；Step 2 快速核對（確認文檔狀態無需更新即可一句帶過）；Step 4 摘要縮為 3 行精簡版：

- 單一 repo；
- 變更集 ≤3 檔、或純 docs/chore 文檔性變更；
- 本次無 decision／dead end／milestone record，也無新增或關閉的 backlog item。

**Light path relaxes ceremony only, NEVER Critical.** Branch-first, never-push-default, the Step 4 authorization requirement, `verdict: STOP`, and Unknown=protected all apply unchanged — "it's just a small change" is never a reason to skip a guardrail.

**詢問收斂（零到一題）**：使用者給了送出說法 → **一題都不問**，印完摘要做到底。沒給說法 → Step 4 問**一題**。其餘待決事項一律有預設處置或降為摘要「附註」，不另外出題、不逐項中斷（規則以 Step 4 為準，此處不重列）。例外只有兩類：`ship-state.sh` 的 `verdict: STOP`，以及 agent 無法自行安全決定的情境（身分分離、fork、push 失敗、spec 撞名）。

### Critical — Guardrails

These are hard constraints. Read them before touching git.

- **NEVER push without explicit user authorization.** Authorization comes from exactly two places: a ship keyword in this turn's user messages (see `ship-paths.md`「說法表」), or an affirmative answer to the Step 4 question. Neither present → STOP. **Always print the ship summary before pushing either way** — the keyword removes the wait, never the disclosure.
- **NEVER push to the default / protected branch directly.** On a protected default branch, open a PR instead. Sole exception: `ship-state.sh` prints `verdict: BOOTSTRAP` — it measured zero branches on the remote, so no default branch exists yet. That exemption covers **exactly one push** (creating the baseline) and expires the moment the baseline exists. Only the script grants it; never carry it over from memory or from an earlier turn's authorization.
- **NEVER merge the PR on your own.** Opening a PR ≠ merging it. Merge only on an explicit user instruction — 「明說」＝使用者說了 merge 類說法（本輪引數或任一則訊息），或在 Step 4 選了「送出並 merge」。兩者皆無 → 一律不 merge。**Never infer a merge from "ship", "push", "送出", or from having just opened the PR.**
- **Branch FIRST, before any commit.** If changes must be committed while `HEAD` is the default branch (or detached), create a feature branch **before** committing — not at push time. This is unconditional: do it regardless of protection state (see Step 1, item 5), even when protection is confirmed off.
- **Unknown protection = protected.** If `gh` is missing or the protection query fails, treat the default branch as protected (PR path). Do not assume it is open.
- **A ship keyword authorizes HOW to ship, NEVER whether a batch may ship.** Any `verdict: STOP` from `ship-state.sh` — including `review-terminal:` — outranks every keyword. Stop and follow the message.

#### Rationalization table — STOP if you hear yourself say these

| Excuse | Reality |
|--------|---------|
| "User said push, so push to main." | "push" means push the *feature branch*. A protected default branch needs a PR. |
| "The PR is open now, might as well merge it." | Opening ≠ merging. 需要 merge 類說法或 Step 4 勾選。兩者皆無 → 停。 |
| "They said merge, so the STOP doesn't apply." | The keyword answers *how*, not *whether*. `verdict: STOP` still stops. |
| "They said ship/送出, close enough to merge." | It is not. Only a merge keyword merges. Ambiguous wording → path B, ask once. |
| "The batch has ≥2 commits, I should ask whether to squash." | 預設已定義：保留。問就是把已決之事丟回去。Squash only on an explicit squash keyword. |
| "Docs are already committed on main, just push them." | You should have branched first. Move the commit to a feature branch; never push to protected main. |
| "Can't detect protection, so it's probably fine to push to main." | Unknown protection → treat as protected. Branch + PR, or stop and ask. |
| "Branching now is extra work; commit here first, move later." | Branch-first is one command and prevents an awkward main commit. Do it before the commit, every time. |
| "It's just a docs commit, the protection won't mind." | Protection does not care what the commit is. Same rules. |
| "Working tree is clean — nothing to ship, exit." | Docs may still lag behind already-shipped code. Check session memory for shipped work (docs-only mode, Step 1 item 2) before exiting. |

#### Red Flags — STOP and re-read Critical

- About to run `git push origin <default-branch>` or `git push` while on the default branch.
- About to run `gh pr merge` / any merge **without an explicit user merge instruction** (with one, follow `ship-paths.md`「Merge 最後一哩」).
- About to `git commit` while `HEAD == default branch` **or detached HEAD** without having branched.
- About to push without having printed the Step 4 summary, or with neither a ship keyword nor a Step 4 answer in hand.
- About to ask which merge flag to use, or whether to squash. Both已有預設——see Step 4.

### Step 0：範圍鎖定

#### 引數前處理（依**形狀**分類，不靠優先序記憶）

引數逐 token 依形狀歸類 —— **形狀規則的好處是不需要記「誰先誰後」**，同一個字不會因為位置不同而有兩種讀法：

| 形狀 | 是什麼 | 例 |
|---|---|---|
| `--` 開頭 | **flag**（模式或送出說法） | `--log` `--merge` `--pr` |
| 裸字，且是模式名 | 模式（僅限**第 1 個** token） | `spec` `log` `transfer` |
| 裸字，且命中說法表 | **送出說法**（見 `ship-paths.md`「說法表」） | `merge` `bypass merge` |
| 含 `/` 或 `.` 開頭，或存在的路徑 | repo 或 module —— 交給 `resolve` | `.` `~/Projects/krepo` `./docs/plans` |
| 其餘裸字 | 可能是 repo basename（session 記憶）→ **不命中就停下問** | `krepo` `dotfiles` |

**Module 過濾一律走路徑形式。** 裸字**永遠不會**被當成 module —— 那條舊路徑會在打錯字時靜默縮小 Step 2 的掃描範圍（掃不到的文檔不會報錯，只是沒被同步）。要以 `merge`／`pr` 這種字面當 module，寫 `./merge`、`docs/pr`。

repo / module 的判定交給腳本（**the script IS the path/realpath/toplevel logic — do not re-derive it**）：

```
~/.claude/skills/project/scripts/ship-state.sh resolve <token>
```

- `resolve: REPO <root>` → 鎖定該 repo，**跳過多 repo 偵測互動**。
- `resolve: MODULE` → 當 module 過濾（Step 2 用），不鎖定。
- `resolve: UNKNOWN` → 比對 session 記憶中的 repo 根 basename（`krepo`、`dotfiles`）——命中即鎖定；**不命中 → 停下問使用者這個字是什麼意思，NEVER 自行當成 module 或忽略**。

flag 與裸說法**等價**（`--merge` ≡ `merge`），兩者都只是 Step 4 的授權來源；差別僅在 flag 靠形狀就無歧義。**說法也可以出現在對話裡、不必寫進引數**（見 Step 4 路徑 A）——那條路徑沒有 flag 形式，這是刻意的。

鎖定單一 repo 後 → 直接進 Step 1（不問多 repo 清單）。

#### 多 Repo 偵測（無 repo 引數時）

依本 session 記憶列出所有涉及變更的 repo（**不掃 `~/Projects/`**）：

1. 回憶 session 中改過檔案的所有 repo 根目錄 + pwd 所在 repo。
2. **單一呼叫**確認全部 repo 狀態：`~/.claude/skills/project/scripts/ship-state.sh <repo1> <repo2> ...`（default branch 偵測、三點/兩點變更集、upstream 邊界、protection 判定全在腳本內）。Step 1 直接沿用同一份輸出，**不重跑**。
3. 展示清單等使用者確認（ok / 只看 X / 還有 Y）：
   ```
   本次涉及 2 個 repo：
     1. krepo（領先 default 2 commit）
     2. pilot-api（3 檔未提交）
   一起 ship？或需要調整？
   ```
4. context 被壓縮 → 以 pwd 的 repo 為底讓使用者補充；使用者指定的 repo 即使無變更也納入。
5. 全部 repo 既無領先 default 的 commit 又無 working tree 變更 → **勿直接結束**：先逐 repo 依 Step 1 第 2 項的 **docs-only mode** 判定（session 有已 ship 變更的 repo 仍納入，跑文檔同步）。git 無變更**且** session 記憶亦無已 ship 工作 → 才告知並結束。
6. **單一 repo → 跳過此步，直接 Step 1。**

### Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）

> **remote 假設**：下文一律以 `origin` 書寫，代表「canonical remote」的 stand-in。**非 origin repo**：把下文所有 `origin` 讀作你解析出的 remote（`git -C <repo> remote`；有 `origin` 用之、否則取第一個）；無任何 remote → 停下告知使用者。**fork 工作流**（push 目標 = writable fork、PR/protection 查詢目標 = upstream，兩者為不同 remote）**本 skill 不自動分辨**——遇 fork 場景在 Step 4 摘要明列兩個 remote、由使用者確認，**不擅自對 fork 開 PR、不對唯讀 upstream push**。**host 假設**：本 skill 假設 GitHub.com（`gh` 走 authenticated default host、compare URL 用 `github.com`）；GitHub Enterprise / 自架站台需設 `GH_HOST` 並以 `host/owner/repo` 形式綁 `-R`，**不在本 skill 自動處理範圍**（SSH alias 如 `git@github-work:` 仍指向 github.com，照常適用）。

對每個 repo：

1. **狀態偵測（單一來源）**：沿用 Step 0 的 `ship-state.sh` 輸出（單 repo 鎖定時在此直跑一次）——每 repo 印出 `branch` / `always-on`（此 repo 的 root `CLAUDE.md`／`AGENTS.md` bytes；擁有全域 `CLAUDE.md` 的 repo 另印一行。**純資訊，處置見 Step 2**）/ `remotes`（多 remote 附 fork 提示）/ `default` / `files-vs-default`（三點，branch 自身帶來的檔）/ `commits-ahead`（兩點，領先 default 的 commit）/ `working-tree`（porcelain 含 untracked）/ `misplaced`（誤 commit 在本地 default 的警示，附 `branch-first-cmd:` 供第 5 項照抄）/ `doc-governance`（adopted repo 的 audit verdict；legacy repo 才印 dossier/backlog 訊號）/ `stale-branches`（已完全併入 default 的 local/remote branch，附 `cleanup-cmd:`；無殘留則不印）/ `squash-merged-branches`（squash-merge 後祖先鏈斷掉、`branch --merged` 看不到的殘留，經 merged PR 的 headRefOid 比對確認）/ `foreign-remote-branches`（非 canonical remote 上的 branch，**只列出、不發刪除指令**；無則不印）/ `review-residue`（review 迭代痕跡與可照抄的 squash 指令，第 6 項用）/ `protection` / `ship-path` / `branch-first`。**Do not re-run the underlying git/gh commands one by one — the script IS the detection.**
2. **變更集**（= 此 branch **相對 default 的變更**，即 PR 將含的內容；**不等於「未 push」**——已 push 到 feature branch upstream 的 commit 仍落在此範圍，push 狀態由 Step 5 處理且 push 為冪等）：取腳本的 `files-vs-default` + `working-tree` 合併為完整**檔案**清單（Step 2 判模組、Step 4 列變更檔都靠它；`commits-ahead` 只有主旨、無檔名，deep-review 交接的「clean tree + 只剩 branch commit」情境靠 `files-vs-default` 列檔）。無變更（腳本印 `changes: NONE`）→ 跳過此 repo，**除非符合下述 docs-only mode**。
   **Docs-only mode**：repo git 無變更（tree clean、無領先 default 的 commit），但 session 記憶中有本 session **已 ship**（已 merge／已 push）的變更 → 不跳過。變更集改由那批 commit 重建檔案清單：逐 commit `git -C <repo> show --name-only <sha>`（已 merge 進 default 者用 default 上的對應 commit）。後續步驟照常：Step 2 據此同步文檔、Step 3 只會產生 `docs:` commit、branch-first／protection／Step 4 確認全部適用；Step 2 掃完確認文檔皆已同步 → 該 repo 無事可做，如實回報。**A clean tree does not mean "nothing to ship" — "code shipped, docs lagging" is the common case this mode exists for.**
3. **branch protection**：取腳本的 `protection:` verdict（classic + ruleset 都查過）——`PROTECTED` / `OPEN` / `UNKNOWN → treat as PROTECTED`。**Never reinterpret the script's UNKNOWN as "probably open" — Unknown = protected, the script already says so.** verdict 附 `viewerPermission=READ`（classic `Not Found`）→ 身分分離情境，後續處置（`git push --dry-run` 探權限、Step 4 摘要點明、不自行硬推）見 `ship-paths.md`。
4. **決定 ship 路徑**：腳本印 `verdict: BOOTSTRAP`（全新空 repo，遠端零 branch）→ 走 **bootstrap 路徑**（`ship-paths.md`「Bootstrap」）：branch-first 與 protection 判定在此皆不適用（沒有 default 可保護），Step 4 摘要須標明「此 push 將決定遠端 default branch」。其餘 `verdict: STOP` 一律停下照訊息處理，**不得**自行當成 bootstrap。否則取腳本的 `ship-path:`——protected（或未知）→ **PR 路徑**（推 feature branch + 必開 PR）；確定無保護 → **仍預設 PR 路徑**（跨 repo 單一形狀，省掉每輪「這個 repo 要不要 PR」的判斷，並留下審查紀錄與可回溯 diff）。**"No protection" is not a reason to skip the PR** —— 只有使用者明說「不用 PR / 只推 branch」才退為直接 push 該 feature branch（escape hatch，不主動勸退）。**兩條路徑都推 feature branch、都不直推 default**（branch-first 無條件）——「直接 push」指**省去開 PR 的步驟、直接 push 該 branch**，不是直推 default。把變更合進 default branch 一律是**使用者**的事（agent 不 merge、不直推 default）。
5. **Branch-first（無條件，依全域「if on default branch, branch first」）**：目標——**到 Step 5 送出前，當前 branch 一定不是 default branch（也不是 detached HEAD）**，**不論 protection**。已在 feature branch（如 deep-review 結尾）→ 跳過。否則執行：

   ```
   ~/.claude/skills/project/scripts/branch-first.sh <repo> <type>/<slug>
   ```

   （ship-state 有印 `branch-first-cmd:` 時整行照抄、填上 type/slug；type 取自變更語意 feat/fix/docs…，slug kebab-case。）情況 A（default/detached 上無誤 commit → `switch -c`，working-tree 變更與 detached commit 跟隨）與情況 B（誤 commit 在本地 default → 救援序列 + porcelain 前後快照驗證）由腳本自動判定；任何 ambiguous（分岔、branch 撞名、無 remote）→ `verdict: STOP` 交回處理，零 mutation。在 default branch 上務必 **commit 之前**先跑。**Do not hand-type the rescue sequence — the script IS the mutation path**（手動 fallback 僅供除錯，見 `ship-paths.md`）。
   > 做完此步，**Step 5 一律推 feature branch，絕不直推 default branch**——即使確定無保護（branch-first 無條件，「無保護→直接 push」推的也是 feature branch，不是 default）。
6. **Review 痕跡（不出題，取處置）**：取腳本的 `review-residue:` 行決定怎麼做，**不自行比對 commit subject**（權威清單在 deep-review、model 憑印象會漂，誤判就是壓掉使用者自己的歷史）。**Review fix commits always get squashed when they can be** —— 這條不是偏好、不問使用者；決定權只在「壓不壓得掉」：

   | 腳本輸出 | 處置 |
   |---|---|
   | `review-residue: none` | 無事 |
   | 有 `top-contiguous: N` | **壓掉**那 N 顆**＋本輪 Step 3 產生的 commit**（語意 commit 原樣保留）。摘要須寫明「本輪 Step 3 的 commit（docs，mixed state 下也含 code）一併收進這顆」——否則摘要顯示的與實際送出的不是同一份 |
   | 只有 `buried: N` | **照常送出**，摘要標明「N 顆夾在語意 commit 中間，非互動式壓不掉」。**NEVER reach for `squash-all-cmd:` to satisfy the invariant** —— 那會連語意 commit 一起收，違反使用者「不同目的的 commit 預設保留」的規則，且是靜默違反 |
   | `top-contiguous` 與 `buried` 同時出現 | 只壓頂端那段（零風險），buried 那幾顆照上一列處理 |
   | `review-residue: UNKNOWN` | 不猜、不壓，摘要標明無法判定 |

   > **在此記下 `squash-cmd:` 的 hash，Step 4 套用時直接用——NEVER re-run to recompute it.** 那個 hash 不是「會過期的值」，而是**使用者語意 commit 的邊界**：Step 1 跑在 Step 3 之前，此刻 HEAD 之上還沒有本流程自己產生的 commit，所以它天然標記了「這裡以上都可壓」。
   > **重算會反過來壞事**（2026-08-06 實測，`tests/run.sh` 已釘死）：Step 3 的 commit 一落下，頂端連續段恆為 0、verdict 從 `top-contiguous` 翻成 `buried`，現場只剩會壓掉語意 commit 的全壓指令——該壓的反而沒有指令可執行。

   **不在此單獨停下**；執行序見 `ship-paths.md`「送出前的 branch 內 squash」（已 push 過的 branch，force-push 屬 Step 5）。

### Step 2：同步 active/history/backlog 與受影響文檔

先讀 `dossier.md`，再由完整變更集識別模組。防禦原則：先讀、只改相關段落、無需更新就跳過。

**Adopted repo**（config + core 兩者皆在）：

1. 核對本 session 的 decision／dead end 是否已在事件當下寫入；漏記才用 `record-path` 決定 shard 與 ID 後補寫。
2. 工作完成時寫 `M-*` milestone、從 `STATUS.md` 移除 completed active item；暫停項必須有恢復條件。
   Backlog 新項給 `B-*`；解決／放棄／變成決策時寫對應 history record、保留 `B-*` 關聯後移除原 item。
3. 同一 work item 的 plan 只修原檔；本次實作真正完成才把狀態改 `implemented`，不得另建 `-v2`／`-final`。
4. 文檔更新後執行 `scripts/doc-governance.py audit --ship`。exit 0 才通過；exit 1 的 findings 必須處置；
   exit 2 是 BROKEN。兩種非零都設定 doc STOP，但繼續收集其餘摘要。**這是 adopted repo 唯一 doc verdict；
   NEVER 再跑 legacy dossier/backlog detector 來覆蓋它。**

**Legacy repo**（兩個 adoption 檔都無）：沿用 `ship-state.sh` 印出的 `dossier:`／`dossier-flag:`／
`dossier-sections:`／`backlog-flag:`。逐 flag 照訊息處置；簽章不符或 backlog 缺必要章節就 STOP。
`dossier: NONE` 只在摘要建議建立，不自動回填。只有一個 adoption 檔存在時是 BROKEN，不得走本段。

`always-on:` 與 doc report 的 bytes 都是資訊，不在一般 ship 順手壓縮；真正 blocking 的 budget 已由 adopted audit 判定。

- **殘留 branch 衛生（三個訊號，來源不同、指令也不同）**：
  - `stale-branches:`（祖先關係判定：已完全併入 default）→ 附 `cleanup-cmd:`，整行照抄。
  - `squash-merged-branches:`（**squash-merge 後祖先鏈斷掉**，`branch --merged` 結構上看不到；腳本已用 merged PR 的 `headRefOid` == 本地 tip 驗過）→ 每支附一行 `cleanup-cmd:` 呼叫 `cleanup-stale-branch.sh`，**它會在執行當下重驗 tip**（偵測到刪除之間 branch 可能又前進）。同段的 `skipped:` 行是**診斷、不是待刪清單**——SHA 不符或來自 fork 的一律不碰。`scan: partial` 代表查詢達上限，**未列出不代表沒有**，摘要要照實說。
  - `foreign-remote-branches:`（在**非 canonical remote** 上的 branch）→ **只列出，沒有也不該有 `cleanup-cmd:`**。那些 ref 屬於**另一個 repo**，「是否已併入我的 default」對它們不構成處置依據；上面兩段刻意把它們整批排除（漏過濾時發出的刪除指令會永遠 `verdict: STOP`——名字帶了 remote 前綴，而 `cleanup-stale-branch.sh` 只認 canonical）。段內 `note:` 行給的是合法出路：停止追蹤走 `git remote remove <remote>`（本地不再列出、對方 repo 完全不動）；真要刪除需使用者明確意圖並自行對該 remote 執行。**NEVER 代為刪除、NEVER 拼一條刪它的指令給使用者照抄。**
  - 三者都是 **在 Step 4 摘要「附註」列出，不出題、絕不自動刪**。Deleting branches is never something this flow does on its own. merge 最後一哩只清它自己 merge 的那支，老殘留靠這三個訊號才會被看見。
- 涉及模組的 `**/CLAUDE.md`（只動受影響的）。
- 相關 `docs/plans/*.md`（存在時）。
- 所有更動文檔頂部的 `updated` 日期改為今天（YYYY-MM-DD；STATUS.md 的對應欄位名為「更新日期」）。
- `$ARGUMENTS` 中（mode 與 repo token 之後的）module 名 → 限縮文檔掃描範圍。

### Step 3：Adaptive 提交

依 reviewed code 的狀態決定文檔如何「一起提交」。**前提：送出前所有 reviewed code 都必須已 commit**——working tree 不留未 commit 的 code，否則 Step 5 會送出不完整變更集。

- **code 未 commit**（review 在 working tree）：`git add` 程式 + 文檔 → 一個或多個語意 commit（Conventional Commits），code 與其文檔**同 commit**。
- **code 已 commit**（如 deep-review 已 squash）：文檔另起 `docs: …` commit，**同 branch**（同 PR 一起出）。**不 amend、不重寫已 review 的 commit。**
- **mixed state**（部分 code 已 commit、部分仍在 working tree——如 Step 1 情況 B 搬移後又改了東西）：**先**把 working-tree 的 code 補成語意 commit（與已 commit 的同 branch），**不可只補 `docs:` commit 就送出、把未 commit 的 code 留在 working tree**；code 全部 commit 後再依「code 已 commit」處理文檔。
- 無文檔需更新且 code 已 commit → 本步不產生 commit。

> **與 Step 4 squash 選項的交互**：使用者若在 Step 4 選了「先 squash 再送出」，本步產生的 commit 會被收進那顆 squash commit（reset 目標是 Step 1 記下的邊界，位於本步之下）。這**不違反**上面「不 amend、不重寫已 review 的 commit」——那條護的是**已經過 review 的 code commit**，而本步的 docs/code commit 是本輪剛產生的新物。squash commit 的 message 因此要同時涵蓋「這批 review 修復」與「本輪文檔同步」。

commit message 用 Conventional Commits，附環境指定的 `Co-Authored-By` trailer（以 runtime system prompt 的 Git 區塊為權威，**勿在 skill 寫死 model 名稱/版本**——它每次升 model 就漂移）。

### Step 4：Ship 摘要 → 確認（critical-op gate）

push **之前**，逐 repo 印摘要等使用者確認（plan → validate → execute）：

```
Ship 摘要：
  krepo  路徑=PR（main 受保護）
    feature branch: feat/mops-announce-backfill
    branch commit（相對 default，= PR 內容）: 2 feat + 1 docs（push 為冪等，已 push 則 no-op）
    變更檔: src/..., scripts/..., STATUS.md, docs/archive/...
    PR: feat/... → main（將開，不 merge）
    附註: doc-governance audit OK；新增 D-*、M-* records
```

「附註」列兩類：**純告知**（已依 flag 處置完的結果）、以及**超出出題上限而未出成選項的待決項**（後者一律標明「未處理」，不得因出不了題就靜默丟掉）。無則省略。輕量路徑摘要縮為 3 行（路徑＋branch＋變更檔），確認語意不變。

摘要之後怎麼收尾，**由使用者這輪有沒有給送出說法決定**（說法表的唯一權威是 `ship-paths.md`「說法表」——照該表分派，勿在此重述對照或自行擴充等價詞）：

**A. 有送出說法**（「merge」「bypass merge」「開 PR」「只推 branch」…或其 `--` flag 形式，出現在本輪任何一則使用者訊息／引數裡）→ **印完摘要直接執行到底，不再詢問任何一題**。說法即授權：它已經回答了「送不送」與「怎麼送」，再問一次是把已決之事丟回去。

> **「執行到底」的終點由說法決定，不是一律 merge**：`--merge` 類 → 做完 Merge 最後一哩；**`--pr`／「開 PR」→ 開完 PR 就停**（與路徑 B 選「送出，停在 PR」同一個終點，差別只在沒問你）；`--no-pr` → push 完 branch 就停。

**B. 沒有送出說法** → 用 **`AskUserQuestion`** 收確認，單一題「這批怎麼處理？」：PR 路徑三選項 `送出，停在 PR` ／ `送出並 merge` ／ `取消`；直接 push 與 Bootstrap 路徑無 PR 可 merge，退為 `送出` / `取消`。選了「送出並 merge」＝ explicit merge instruction，**開完 PR 接著做完，不再問第二次**。

> 想連這一題都省掉又不要 merge → 下次用 `--pr`（或說「開 PR」）。

**兩條路都不出 squash 題、不出衛生題**——理由是這些問題現在都有預設答案：

| 事項 | 處置（不詢問） |
|---|---|
| `review-residue:` 有 `top-contiguous:` | **一律壓掉再送**，reset 目標照抄 Step 1 記下的 `squash-cmd:`（NEVER recompute——理由見 Step 1 第 6 項） |
| `review-residue:` 只有 `buried:` | 照常送出，摘要標明「N 顆夾在語意 commit 中間，非互動式壓不掉」 |
| `review-residue: UNKNOWN` | 照常送出，摘要標明無法判定、未處理 |
| `stale-branches:` / `squash-merged-branches:` / legacy `dossier: NONE` / doc finding | **不出題也不自動做**，寫進摘要「附註」一行提示（`scan: partial` 要照實標明「未列出不代表沒有」）。刪東西永遠不會自動發生 |

「附註」列兩類：**純告知**（已依 flag 處置完的結果）、以及**未處理的待決項**（一律標明「未處理」，不得因為不出題就靜默丟掉）。無則省略。輕量路徑摘要縮為 3 行（路徑＋branch＋變更檔）。

**處置先於送出**：本輪若要套用會改變待送內容的處置（squash、Step 3 的 commit），順序一律是**套用 → 重新 commit → 摘要印的是套用後的結果 → 才 push**。**Never push a commit set that differs from the one the summary displayed.** 含 `fetch` 的處置（stale-branch 清掃）**建議**排在 push 之後（順序清楚）；lease 帶了錨定 SHA 之後它已不是安全前提，見 `ship-paths.md`。

`AskUserQuestion` 不可用（背景 turn／工具被停用）且落在路徑 B → 退回文字編號選項並 **STOP**。

#### 說法覆蓋不了的事實前提（一律停）

`ship-state.sh` 印 `verdict: STOP` → **停下照訊息處理，即使使用者已給說法**。**A ship keyword authorizes HOW to ship, NEVER whether a batch may ship at all.** 目前會走到這裡的：無 remote、非 bootstrap 的 default 解析失敗、以及——

- **`review-terminal:`**：上一場 deep-review 在仍有未修 blocking findings 時終止，且那場涵蓋當前 HEAD（腳本已驗過 ancestry，不必自行判斷）。停下用 `AskUserQuestion` 給兩個選項：`重跑審查`（通過並 squash 後 anchor 自動清除）／`知道了，照送`（PR body 記一筆「未完整審查」）。**anchor 的欄位與指令不要攤給使用者看**——那是實作細節，使用者只需回答這一題。
  - 例外：使用者說的是**「merge 照送」／「merge 未審完」**（見說法表）→ 已預先放行，不停、照送，PR 仍記一筆。

> 為什麼這條存在：Step 4 從「每批停下確認」改成「說法即授權」之後，原本那道 gate 順帶接住的「這批還沒審完」就沒有別人接了。**拆掉守衛就得補上它接住的東西。**

### Step 5：依路徑送出

確認後逐 repo 執行（完整指令序列見 `ship-paths.md`）：

> **修飾條件（不是第四條路徑）**：本輪做過 branch 內 squash 且該 branch 已 push 過 → 下列各路徑的 push 指令改為 `git -C <repo> push --force-with-lease=<feature-branch>:<squash 前記下的遠端 SHA> origin <feature-branch>`（**必須帶 expected SHA**——裸 lease 比對本地 tracking ref，而本流程自己會 fetch，詳見 `ship-paths.md`）（**NEVER `--force`**；被拒的分流見 `ship-paths.md`「push 失敗處理」——那裡 `pull --rebase` 會把剛壓掉的 commit 拉回來）。未 push 過的 branch 照常首推，不需要 force。
- **PR 路徑**：`git -C <repo> push -u origin <feature-branch>` → 偵測既有 PR（`gh pr view`，多 repo 須 `-R <owner/repo>` 綁定）：有則指向、無則 `gh pr create`（同樣 `-R` 綁定；title/body 由 commits 組；deep-review 的「第三方審查資訊」若有一併放進 body）。完整綁定指令見 `ship-paths.md`。輸出 PR URL。**接著依 Step 4 的授權來源分流**：

  - 給了 **merge 類說法**（`--merge` / `--bypass-merge` / 對應裸說法）、或在 Step 4 選了「送出並 merge」→ 直接進「Merge 最後一哩」（flag 依「說法表」，`BLOCKED` 等受阻狀態依「merge 受阻時的分流」），**不再問一次**。
  - 給了 **`--pr` /「開 PR」**、或在 Step 4 選了「送出，停在 PR」→ **開完 PR 即止**，附一句提示：「之後說『merge』即可由我接手最後一哩（merge + 清 branch + 同步本地 default），預設保留你的 commit；要壓成一顆就說『merge 壓成一顆』」。
  - **`--pr` 不是 merge 的預備動作**——它是一個完整的終點。**NEVER treat "the PR is now open" as a reason to continue into merge**（rationalization 表已列）。

  **不 push default branch；未獲明說 merge 前不 merge。**
- **直接 push 路徑**（escape hatch：確定無保護**且**使用者明說不用 PR）：push **當前 branch**（branch-first 無條件，故此處一定是 feature branch、非 default）：`git -C <repo> push -u origin <feature-branch>`（**顯式 remote + branch**，不用裸 `git push`——裸 push 受 `push.default` / `remote.pushDefault` / 非預期 upstream 影響，可能推到錯 remote 或多推 ref；`origin` 為 stand-in）。**本路徑不是無保護 repo 的預設**——預設仍是 PR（見 Step 1 第 4 項），走到這裡代表使用者已明說不用 PR，故不再回頭勸開 PR。
- **Bootstrap 路徑**（`verdict: BOOTSTRAP`）：照抄腳本的 `bootstrap-cmd:`（推本地 default 建立 baseline），完成後**重跑 `ship-state.sh` 確認 BOOTSTRAP 已消失**——此後回到正常路徑，後續 commit 一律 feature branch。
- 多 repo：逐 repo 送出，最後彙總（各 repo 的 PR URL / push 結果）。
- push 失敗處理（`rejected` / 無 upstream / gh 未登入）→ 見 `ship-paths.md`「push 失敗處理」（單一來源）。

---
