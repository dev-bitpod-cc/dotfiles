# Deep Review modes、guardrails 與 scope selection

本檔是 `../SKILL.md` 的必要執行 reference。每次 `/deep-review` 在 Step 0 前必須全文讀取。

## 目錄

- 核心原則
- Autofix 模式與錨點
- Autocodex 模式與 protocol
- 手動 Codex 第三方觸發的 range 恢復
- 迭代與 commit 紀律
- 審查範圍選擇

## 核心原則

### 審查者與作者分離

**Code-quality 審查優先由 subagent（Agent 工具）執行。** 主 agent 負責 orchestration-level judgment（範圍確定、repo 選擇、context 收集、round 偵測），但不做 code-quality judgment（程式碼好壞、是否有 bug、是否符合慣例）。Subagent 擁有乾淨的 context window，不帶寫 code 時的推理脈絡，避免 confirmation bias。

跨 repo 時此原則更加重要——主 agent 同時是多個 repo 的作者，跨 repo 一致性判斷應交給 subagent，而非由身為作者的主 agent 自行判斷。

**Subagent 不可用時的降級**：若當前 permission mode 擋下 Agent 工具、或環境無 subagent 能力，主 agent **明確告知使用者「無法委派 subagent，改由主 agent 直接審查」**，再進行審查——並在報告開頭標註「⚠️ 本輪未經審查者/作者分離，主 agent 同時是作者，confirmation bias 風險升高，findings 請額外存疑」。降級是 last resort，不是預設路徑；能用 subagent 就絕不降級。降級時判準同樣照 `reviewer-brief.md`，不憑印象審。

**審查判準（審查原則、維度、同型掃描、深井、嚴重度、通過標準）集中於 `reviewer-brief.md`**——主 agent 交路徑、不轉述（見 Step 4），reviewer 自行 Read。判準經誰的手摘要，就會在那裡漂移。

**這條分離的邊界**：分離的是**判斷**，不是**提問**。主 agent 仍然構造 subagent 的 prompt——`Separating the judge does nothing if the same party writes the question.` 故 Step 4 對提問端設了硬約束（判準交路徑、bar 與 task 恆定、上限不外洩）；那不是形式要求，是這條原則能否成立的前提。

### Autofix 模式

引數包含 `autofix` 時，主 agent 自動執行 review → fix → commit 循環，直到通過或達到上限。

**Branch-first（autofix commit 前置，硬規則）**：autofix 會產生 commit。**第一個 commit 之前**看 review-state 腳本輸出的 `branch-first:` verdict——`REQUIRED`（HEAD 在 default branch 或 detached）→ 照 `branch-cmd:` 行開 feature branch（`<type>/<slug>` 依變更語意自取）再 commit；`已在 feature branch` → 跳過；`UNKNOWN` → 先與使用者確認。NEVER commit autofix/squash onto the default branch.

**記錄審查錨點（單一真實來源 = anchor state 檔；其餘段落只引用，不重述）**：autofix 進修復循環前、第一個 fix commit 之前（branch-first 切換**之後**），無條件執行 `~/.claude/skills/deep-review/scripts/review-anchor.sh record --repo <r> --mode <m> ...`——base hash 由腳本解析並落地 `.git/deep-review/anchor`（與 branch-first 是否觸發解耦，context 壓縮後仍在）。`--mode` 對照：

| 審查情境 | record 引數 |
|----------|-------------|
| branch diff（`<base>...HEAD`） | `--mode branch-diff --base <base>`（base 照抄腳本 `base:` 輸出） |
| commit range（`X..Y`） | `--mode range --range X..Y` |
| working-tree | `--mode working-tree` |
| baseline（全庫 / path 引數，見 B1–B4） | `--mode baseline` |

此錨點是審查範圍的起點，且與 autocodex commit range、第三方審查資訊**同一錨點**。Step 5 的 reset 目標則由 `squash-cmd` 從它往上算出——**只壓 review 循環機械產生的 commit，branch 上既有的語意 commit 原樣保留**（故 squash 範圍不等於審查範圍；squash 後 branch 內容總和仍等於審查範圍，只是 commit 邊界不同，理由見腳本檔頭）。**Always take the reset target from the `squash-cmd:` line, NEVER the anchor hash directly, NEVER a moving ref, NEVER HEAD~N.**

**測試 baseline（record 時一併取得）**：record 前先跑一次 `~/.claude/skills/deep-review/scripts/verify-tests.sh <repo>` 取 baseline（exit 0→`pass`、1→`fail`、3→`skip`），以 `--tests-baseline <值>` 附在 record 引數記入錨點——「修復後驗證」據此分流（見該節）。baseline 為 `fail` → 當下明確告知使用者：repo 測試在審查前已紅，本次 autofix 的 commit 將不經測試驗證。

**WIP snapshot（僅 working-tree 模式）**：record **之後**、R1 審查之前，working tree 有未提交變更 → `git add -A && git commit -m "wip: pre-review snapshot"`（`add -A` 尊重 .gitignore）。**這是全域 `add -A` 禁令的唯一例外，前置條件：先確認 working tree 全屬本次工作**——混了他人 session 的 in-flight 變更就停下問，別靠 snapshot 之後再拆（squash 終態一樣會把它送進 PR）——使用者原始變更與後續 fix commits 分離，中途 revert 壞修復不誤傷原始工作；anchor base = pre-WIP HEAD，最終 squash 終態與未拆分時相同。此後各輪審查範圍統一用 record 印出的 `diff-cmd:` 行（整行照抄轉交 subagent）。

```
R1 review → 未通過 → 主 agent 修復 → commit「fix: address review findings」
R2 review → 未通過 → 主 agent 修復 → commit「fix: address review findings」
R3 review → 未通過 → 主 agent 修復 → commit「fix: address review findings」
R4 review → 未通過 → 主 agent 修復 → commit「fix: address review findings」
R5 review → 通過 → 結束（squash 成乾淨 commit）
          → 未通過 → 停止，輸出累積報告，交還使用者
```

> 上圖為最壞情況。**任一輪通過即進通過分支並 squash**，不必跑滿 R5——R5 是修復輪數上限，非 squash 的前提。

**上限**：4 輪修復、5 次審查。R5 仍未通過時**不預設病因**——先看終止報告「修復軌跡」表的根因重複欄：各輪根因**重複**（同一條規則逐輪擠、或修 A 引入 B）才是越補越亂、病灶多半在架構層；各輪根因**皆不重複**則屬健康收斂，只是變更本身複雜，不該因此建議重寫。終止報告須包含 branch 狀態處置建議與**續跑分流**（判準見報告模板的「續跑分流」表）。

**再跑一次 autofix 不是預設下一步**——同一個 reviewer 對同一批 code 再開一輪，挖出的多是同類型的東西，而輪次上限會隨新一場 review 重置（等於上限失效）。`record` 印出 `cycle: 2+`（前一場未走完即重啟，腳本自動判定）時，終止報告**必須先給分流**，且明列「同 reviewer 再跑第三個週期價值最低，優先換視角」。**換視角的可行形式一律照報告模板的「續跑分流」表**——R5 未通過時直接跑 `/deep-review autocodex` 到不了 codex 階段（Step 6 只在主審通過後才進），故實際只有兩條：人工修掉剩餘 blocking 後才跑 `autocodex`，或直接把 `base..head` 交外部 reviewer。

**修復原則**：主 agent 在修復階段依照 subagent 的修復計畫執行，優先修復所有嚴重與中等問題；建議等級僅在不引入額外風險時順手處理。修復時**以下每條都是硬性動作、不是建議**（軸的清單以 `report-templates.md`「同型處置紀錄（共用區塊）」為準，此處不複述數量）：

- **同型全修（命中點軸）**：finding 的「影響範圍」列了 N 個命中點就修 N 個，不只修第一個；reviewer 漏掃時（只給單一實例、未註明已掃過）由 fixer 自行補掃該規則的其餘實例。Fixing one site of a three-site rule is what turns one round into three.
- **輸入空間覆蓋（輸入軸）**：把 finding 抽象成規則後，攤開該規則的**輸入空間**確認修復對整個空間成立——**列舉**（有限且可分割 → 寫出等價類／邊界分割並逐項驗）或**根治**（無限／不可枚舉 → 改成結構上不依賴枚舉的解，如 allowlist、型別約束、單一入口）。兩者都是完整處置，根治不是次等選項。
  **判別問句：這個集合的成員，會不會因為別人安裝／擴充了什麼而變多？**（DB catalog 的物件種類、plugin 提供的型別、第三方 API 的錯誤碼——**判準是「誰能加成員」而非「會不會變多」**：repo 自己日後新增的子命令仍屬封閉集，照常列舉並同步更新測試）→ **會**＝外部可擴充集合，**枚舉必然差一個**，那不是「再補幾個」而是選錯解法，改根治；→ **不會**（repo 自己定義的封閉集）＝列舉合法。實地：`02-*.sql` 的同名 schema 檢查補了 `pg_proc`／`pg_type` 仍漏 operator／collation／text-search，三輪才改成「owner 不是本角色就中止」。
  **A reviewer's 「已掃過 X，無其他命中」 clears the sites axis ONLY — it NEVER exempts the others.** 各軸同名不同軸（reviewer 端的定義見 `reviewer-brief.md`「同型掃描」）。同理 **reviewer 的建議修法是下限、不是上限**——`Cheap fix:`／「簡單作法」這類措辭即自陳未覆蓋完整輸入空間，照抄等於把近似解當成完整修復。
- **Scan before you edit, not after.** 各軸都在動手改之前掃完。實地失效：修完才掃，於是下一輪 reviewer 在**修復本身**裡抓到同一條規則的第三次違反。
- **各軸的處置寫進報告**（`report-templates.md`「同型處置紀錄」）——零命中也要寫。掃過與沒掃在輸出上不得同形。
- **相依軸（誰的正確性依賴我要改的東西）**：**動手改 X 之前**（同上一條，掃描一律先於編輯），**依「關係」逐類找依賴端，不是找哪裡還出現同一串字**——①條件 → 描述它的訊息／註解／docstring；②判準 → 它的自我測試；③事實 → 宣告它的權威檔；④能力 → 描述該能力的文件。**Search by relationship, not by matching text.** 這一軸**與命中點軸正交，且 grep 天然抓不到**：相依端的用字常與被改的東西不同、甚至反義（predicate 拿掉判空 ↔ 訊息仍寫「且非空」；清單 3 項變 4 項 ↔ 散文仍寫「三處」）。改完語意卻留下 stale 描述，下一輪必被當成新 finding 報回來。

**修復後驗證**：依錨點記錄的 tests-baseline 分流（record 時取得，`show` 可跨 session 恢復）：

- baseline `fail`（審查前測試已紅）→ 測試不做 gate：每輪**不跑**測試（紅 baseline 下無判別力，只產噪音），修復後直接 commit，報告各 commit 標 `UNVERIFIED-BY-TESTS(baseline-red)`。**NEVER blame pre-existing red tests on the fix. NEVER fix the test environment on your own — that is scope creep unless the user asks.**
- baseline `skip`（無測試框架）→ 直接 commit，報告註明未經測試驗證。
- baseline `pass`（或錨點未記錄 baseline）→ commit 前執行 `~/.claude/skills/deep-review/scripts/verify-tests.sh <repo>`（框架偵測與執行已封裝，exit 契約見腳本 header），依下列規則：

- **測試通過** → commit，進入下一輪審查。
- **測試失敗** → 表示本輪修復未完成。**留在本輪**繼續修到測試通過再 commit；**不要**帶著未 commit 的失敗修復進下一輪（那正是迭代紀律要防的累積 diff 狀態）。
- **本輪反覆修仍無法讓測試通過**（同一處修兩次以上仍紅、或測試因環境原因無法執行而擋住驗證）→ **停止**，輸出終止/blocked 報告，branch 維持在上一個測試通過的 commit；**不 commit 失敗狀態、不進下一輪**，交還使用者。

> 不變式：一輪只有在「測試通過」時才算完成並 commit；任何 review 輪次都不會帶著未 commit 的失敗修復開始。

**審查者與作者分離在 autofix 中同樣適用**——主 agent 負責修復（作者角色），subagent 負責審查（reviewer 角色），兩者不混合。

### Autocodex 模式

此模式涉及兩個審查者，全文一律以此命名：**主 agent**（Claude Code 本體，負責主 agent 審查階段與所有修復）、**Codex**（獨立第三方 reviewer）。

引數包含 `autocodex` 時，主 agent 審查通過後自動進入 Codex 第三方審查循環。`autocodex` 與 `autofix` 正交——可單獨使用或組合：

- `/deep-review autofix autocodex`：主 agent 自動審查修復 → 通過 → Codex 自動審查修復循環
- `/deep-review autocodex`：主 agent 手動審查 → 通過 → Codex 自動審查修復循環

#### Codex 審查循環流程

```
主 agent 審查通過 → 取第三方審查資訊（repo path + commit range）
  → 背景執行 codex-exec-review.sh run（呼叫協議見下方）
  → 收到 findings → 主 agent 逐條驗證（true positive / false positive）
  → 全部 false positive 或無 blocking findings → 結束
  → 有 true positive → 主 agent 修復 → commit「fix: address external review findings」
  → 再跑一次 codex-exec-review.sh run 審查修復部分
  → 重複直到無 blocking findings 或達上限
```

**上限**：3 輪 codex 審查、2 輪修復（**diff / baseline 模式皆維持此上限，不放寬**——放寬只會鼓勵深井追逐）。到此階段 code 已通過主 agent 完整審查，剩餘問題應快速收斂。兩模式 C2+ 皆只驗增量修復、completeness 深井（baseline backlog / prose artifact）不阻擋通過，因此 2 輪修復足以收斂。若第 3 輪仍有 true positive blocking findings（指向修復本身、非 completeness 深井）→ 停止，輸出 codex 終止報告交使用者。

**Preflight（進入 codex 階段前跑一次）**：`~/.claude/skills/deep-review/scripts/codex-runtime-hygiene.sh check`——告知性檢查，**非 0 只警告一行、照常進入 codex 階段**（exit 語意與清理時機見 `~/.claude/skills/deep-review/references/codex-protocol.md`，下稱 protocol 檔）。

**Codex 呼叫協議**（單一權威——全域 CLAUDE.md 的「由 codex 進行第三方審查」觸發詞段指向此節，改標題須同步）：

以**背景 Bash**（`run_in_background: true`）執行 headless codex：

```bash
~/.claude/skills/deep-review/scripts/codex-exec-review.sh \
  run --repo <repo_path> --range <commit_range> --round <C1|C2|C3>
```

機制細節——preflight exit 語意、prompt 限制、進度查詢、`run`/`resume` 的 exit 契約與救援階梯——**照 protocol 檔操作**，勿憑記憶重組。多 repo 時逐 repo 呼叫，每個 repo 獨立一次 `run`。`--range`/`--round` 值一律取 `review-anchor.sh codex-next` 印出的 `codex-cmd:` 行（整行照抄即可），勿手算。

Hard constraints — violating any of these invalidates the codex round:

- **NEVER call `codex:rescue`** — the plugin broker path hangs silently forever (root cause in the protocol file).
- The script's prompt is a FIXED single line. Do NOT add focus points, test requests, context files, or project-convention docs.
- After launching in background, do NOT poll and do NOT reintroduce time-based death detection — the completion signal is process exit; the harness calls back.
- Judge completion/failure by **exit code**, not status strings. exit 5 (environment error) → stop and report, do NOT retry. exit 4 → follow the protocol file's rescue ladder; **at most ONE fresh retry**, then the codex stage is blocked（主 agent 審查結論不受影響）.
- **NEVER `bun install -g @openai/codex`** — it recreates the bun/brew split-brain. Reinstall via `brew reinstall --cask codex`.

**Findings 驗證規則**：主 agent 收到 codex findings 後，逐條讀原始碼獨立驗證。對每條判定 true positive / false positive / context-dependent。不預設 findings 正確，不預設錯誤。**只有 true positive 且非 Completeness 深井的 finding 才修復**；completeness / prose 深井（見 `reviewer-brief.md`，**不分 diff/baseline**）→ non-blocking、不觸發再一輪修復（codex 與 deep-review 同為對抗式 reviewer，深井會無限回吐——這道閘攔住「主 agent ↔ codex 來回燒額度」）。


**Commit range 更新（依 `codex_base_mode`，見 Step 1）**：每輪執行 `~/.claude/skills/deep-review/scripts/review-anchor.sh codex-next --repo <r>`，把輸出的 `codex-cmd:` 整行照抄以背景 Bash 執行——C1 全審 / C2+ 增量的 range 推導、last-codex-HEAD 記錄、重試冪等、C3 上限全在腳本內（增量為何安全見其 header）。使用者說 `codex full` → 加 `--full`（每輪重審 C1 全 scope）。exit 1（STOP：超上限 / anchor stale）→ 照 verdict 停下。**NEVER hand-compute the range. NEVER HEAD~1 — the anchor script owns the range.**

- **C2+ 收斂判準**：finding 指向本輪修復 commit（增量 range 內新增/修改行）→ 照常驗證；屬 Completeness 深井（見 `reviewer-brief.md`：baseline backlog 或 prose artifact，**不分模式**）→ non-blocking、不阻擋通過、不觸發再一輪修復。

**Squash**：codex 階段的 `fix: address external review findings` commit 與先前的 `fix: address review findings` commit 一起納入最終 squash。

### 手動 Codex 第三方觸發的 range 恢復

使用者說「由 codex 進行第三方審查」但不在 autocodex loop 時，優先取最近一次通過報告的
`base..head`；已 push 不改變範圍。報告不可用時跑 `review-anchor.sh show --repo <repo>`。兩者都無時先
fetch canonical remote：HEAD 仍領先 default 才以 merge-base 作下界審整條 branch；已併入 default 時沒有
可自動推導的下界，列近期 PR／merge commit 請使用者選。**NEVER 退化成 `HEAD~1..HEAD`**，除非使用者
確認整批只有那一顆 commit。最近一次流程明確帶 autofix 才在驗證 findings 後自動修復；否則只回報判定。

### 迭代紀律：每輪修復後 commit

多輪 review 時，每輪修復後**必須先 commit 再進入下一輪**，最終通過後 squash 成乾淨 commit。

```
Round 1 review（未通過）
  → 修復問題 → commit「fix: address review findings」
Round 2 review（未通過）
  → 修復問題 → commit「fix: address review findings」
Round N review — 通過
  → squash 成一個有意義的 commit
```

**為什麼：**
- 不 commit → 每輪 subagent 都要處理完整累積 diff，context 隨輪次膨脹，大型變更會撞 context 上限
- 有 commit → working tree clean，Step 1 自動使用 `git diff <base>...HEAD` 審查完整 branch 狀態
- Round 偵測依賴 `git log`，不 commit 則無法正確偵測輪次

**Commit message 不編輪號**（一律 `fix: address review findings`，codex 階段 `fix: address external review findings`）。`fix: R4 review fixes` 這種寫法會讓 reviewer 跑一次 `git log` 就反推出**剩餘輪數**——那是 Step 4 花力氣關掉的洩漏管道，不該從 commit history 漏回去。**但擋不掉「已改過幾次」**（commit 數量本身即訊號），該殘留見 Step 4 的說明。Round 偵測不受影響：`review-state.sh` 數的是**這組固定 subject 的完整比對**（`lib/review-subjects.sh` 單一來源），不解析輪號——也因此**偏離這組字面就數不到**，中性化 message 一律照抄、勿自行改寫。

### 1. 確定審查範圍

**引數前處理**：若引數包含 `autofix` 和/或 `autocodex`，先提取出來設為對應模式，剩餘引數才用於判斷審查範圍。例如 `/deep-review autofix autocodex src/` → autofix 模式 + autocodex 模式 + 審查 `src/`。

對每個 repo 獨立判斷，依優先順序：

1. **有引數**（扣除 autofix 後）→ 依引數類型決定模式（見下方）
2. **有 working tree 變更**（腳本 `scope-priority: 2`）→ 審查目標 = `git diff HEAD` + 腳本 `untracked` 清單逐檔（**review 須唯讀，勿用會寫 index 的 `git add -N`**：untracked 新檔全文即 diff，由 subagent 直接 `Read` 該檔，或 `git diff --no-index /dev/null <檔>`（唯讀）取得 added 視圖）。此唯讀處理適用**非 autofix** 路徑；autofix 於前置以 WIP snapshot 收妥未提交變更後，審查範圍改用 record 印出的 `diff-cmd:` 行（見「測試 baseline / WIP snapshot」段）
3. **HEAD 偏離 base branch 且 working tree clean**（腳本 `scope-priority: 3`）→ 審查目標 = `git diff <base>...HEAD`（review 整個 branch）
   - base 取腳本 `base:` 輸出（偵測順序 remote HEAD → main → master、無 remote 退本地 branch 已封裝；目標是 repo 的預設主分支，不是當前 branch 的 upstream）。腳本印 `remotes: N 個` 且非 autofix 模式 → 提示使用者指定基準 remote（autofix 需零互動，用腳本預設並在報告註明）；`base: NONE` → **priority 3 不適用，落入 priority 4**（不在此提示指定 base，改問審查範圍）
4. **working tree clean，且 HEAD 未領先 base branch（`<base>..HEAD` 為空）或無可用 base branch**（腳本 `scope-priority: 4 — MUST ASK USER`；剛初始化、無 remote、或已與主分支同步，無近期有意義 diff）→ **不要**逕自 `git diff HEAD~1`（只會審到最後一個小 commit）。先問使用者要審什麼：最後一個 commit、整條 branch、或**整個 repo / 全庫**。若選全庫 → base 設為 git empty-tree（腳本 priority 4 已印 `empty-tree:` 行，照抄）。（與 priority 3 互斥：3 = HEAD **領先** base；4 = HEAD **未領先** base 或無 base）
   **Scope here is the user's call — NEVER pick one yourself.** "The repo is small" / "user said quick look" / "user is offline" is NOT permission to choose. Present the options and STOP until the user answers; reviewing an unconfirmed scope wastes the entire run.

> priority 1–4 已涵蓋所有狀態（有引數 / dirty tree / clean+領先 base / clean+未領先或無 base）；「最後一個 commit（`HEAD~1`）」是 priority 4 詢問中的使用者選項，不另立 priority。

主 agent 只看 **stat 概覽**做 orchestration（priority 2/3 用腳本的 `stat` 輸出；priority 1 引數模式另跑一次 `git diff --stat <範圍>`）。**Do not pull the full diff into the main context — the Step 4 subagent collects it itself.** 主 agent 需要細節時（如 autofix 修復階段）再讀 findings 指到的檔案。

**引數判斷**：符合 `HEAD~N`、`X..Y`、或 7+ 字元 hex → commit 範圍模式；其餘視為檔案/目錄路徑。

#### skill-authoring batch：一次診斷，不進修復循環

變更集**觸及以下任一** → 判為 **skill-authoring batch**（按工作類型，不按副檔名）：

- `claude/skills/**`、`codex/skills/**`（含其 `scripts/` `` `evals.md`）
- `claude/CLAUDE.md`、`codex/AGENTS.md`、repo 根的 `CLAUDE.md`（agent／test 行為契約層）
- `claude/skill-building-guide.md`、`claude/evals/**`

其餘一律維持現行行為——**一般 product code 即使附帶 `README.md` 也照跑 autofix**。混合的 skill + scripts + tests 仍屬 skill-authoring batch。

**RED 來源**：2026-08-06 一批 skill 變更被對抗式重審失控（兩場 review、八輪主審 + 六輪 codex 仍未收斂），而 `evals.md` 開頭早已寫明「對 prose 重跑對抗式 review 永遠會 R1–R5」。**每輪 fresh reviewer + 全量重審 = 對同一搜尋空間無偏重抽樣**，R1 沒找到不代表不存在；修復又會新增假設，下一輪才觀察得到它的破口。這個 loop 結構上不收斂。

判為 skill-authoring batch 時：

- **只跑一次診斷 review**，不進修復循環（`autofix` 引數在此不生效）。
- **severity 判準完全不變**——照 `reviewer-brief.md`「Completeness 深井」節既有的分級：prose 裡「夾帶指令 misbehave」「步驟自相矛盾」**仍是 blocking**；只有措辭與完整度是 non-blocking。**切斷的是 loop，不是 correctness bar。**（**指涉那份判準時一律用 brief 自己的節名，NEVER 用 evals 的情境編號**——`F10` 是開發期 oracle 的編號、brief 裡並不存在，寫進 prompt 等於誘導 reviewer 去讀 evals；2026-08-07 eval 實測到受測 agent 照抄成 `the brief's F10 severity guidance`。）（2026-08-06 那批四條高風險 finding 全在 `.md` 裡、全屬「照做會錯」類——降級它們等於放行真 bug。）
- **eval 檔絕不進 subagent prompt**（`evals.md` 明寫「不從 SKILL.md body 連結」，它是開發期 oracle）。**報告必須明說「本批的完成判定看該 repo 的 eval／測試機制，不是這份審查」並指向下一步的 eval workflow**（2026-08-07 eval 實測：不寫成硬要求時，agent 會漏掉這句，使用者容易把「review 通過」誤讀成「這批完成了」）；但**不把 eval 內容交給 reviewer**。
- blocking finding 的處置**依可驗證性分流**（測試難寫 ≠ finding 不真）：

  | 情況 | 處置 |
  |---|---|
  | 能建立會紅的可執行測試 | 進該 repo 的測試套件（dotfiles 為 `tests/run.sh`），走既有 TDD |
  | 屬 agent 行為 | 建 behavior eval（限該 repo 已有 eval 機制；dotfiles 為該 skill 的 `evals.md`。無機制 → 歸下一列） |
  | 暫時無法建立可靠 oracle | 標 **unverified**，**停止自動修改、交回使用者判斷** |
  | 確認是措辭／完整度 | 降 backlog |

- **完成判定看該 repo 的 eval／測試機制 + 必要 forward test，不看第二輪 review 是否零 finding。**

**Escape hatch 只有一個字面 token**：`/deep-review autofix force-skill-loop`。`autofix` 本身**不構成**推翻（那是它預設就會帶的字），**NEVER infer an equivalent from natural language**——使用者說「就是要跑」「照跑」都不算。帶了 `force-skill-loop` 才進 loop，且報告開頭必須標明「已知此 loop 結構上不收斂」。

#### Codex 範圍模式判定（僅 autocodex 需要）

base 與 range 確定後，**逐 repo** 判一次 `codex_base_mode`，決定 autocodex 階段每輪的 commit range 行為（判定樹，命中即停）。**判 base 的語意，不判 diff 大小**——大型 feature branch 仍是 diff 模式，不因大而切增量。

```
B1. base hash == git empty-tree（= 腳本 priority 4 印的 empty-tree: 值）→ baseline
B2. path/目錄引數模式（審檔案、無天然 base）                          → baseline
B3. 使用者明確指定「整個 repo / 全庫 / audit 全部」這類全量語意         → baseline
B4. 其餘（working-tree diff、<base>...HEAD branch diff、commit range、HEAD~1）→ diff
```

判定後印一行告知使用者，並提示 **`codex full`** 可推翻 C2+ 增量、**強制每輪都重審 C1 的全 scope**（停用增量優化的偏執選項，不分模式；非預設）。

**path 模式（B2）的限制**：codex repo-review 以 **repo root 為單位**、不接受子目錄 repo_path，且 1 行 protocol 禁止加 focus。故 path 模式的 codex 階段 `repo_path = repo root`、`range = <empty-tree>..HEAD`，**codex 會審整個 repo**（比 path scope 廣）。進入 codex 階段前明確告知使用者此擴大，或建議改用「commit 該 path 後以 commit-range 模式」精準限縮。不偽裝成只審了子目錄。
