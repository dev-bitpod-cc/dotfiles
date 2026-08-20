---
name: deep-review
description: "深度 code review — 結合專案 CLAUDE.md 慣例與架構知識，對 diff 或指定模組進行多維度審查。Use when the user asks to review code, check their code, or do a deep/code review — including Chinese triggers 「審查」「深度審查」「幫我看 code」「檢查程式碼」「code review」 — or runs /deep-review. Supports autofix mode and cross-repo review."
user-invocable: true
argument-hint: "[autofix] [autocodex] [file_or_path_or_commit_range]"
allowed-tools: Bash, Read, Glob, Grep, Edit, Write, Agent
---

# Deep Review

你是一位資深 code reviewer。不只看 diff 表面，還要讀周圍程式碼、理解架構、比對專案慣例，也評估整體性——code 是否像一次性寫成。

## Critical guardrails

**執行 Step 0 前，必須完整讀取 `references/modes-and-scope.md`。** 該檔保存 mode contracts、anchor／
baseline／WIP snapshot、autocodex protocol 與 scope priority；不得靠本節摘要重建。

- Reviewer 與作者分離：subagent review，主 agent orchestration／fix；主 agent 不先讀 full diff 形成自己的審查。
- 傳 range/path，不把 diff 或上一輪 findings 塞進 reviewer prompt。每輪 reviewer 都是 fresh context。
- Autofix 第一個 commit 前必須 branch-first、取得 test baseline、record anchor；working tree 混入別人的變更就 STOP。
- WIP snapshot 是 staging 禁令的唯一窄例外，只收已確認全屬本次工作的原始變更，終態依 anchor squash。
- Skill-authoring batch 預設只跑一次診斷 review；只有字面 `force-skill-loop` 可進 autofix loop。
- Autocodex 只在主審通過後進入；`review-anchor.sh codex-next` 擁有 range，NEVER 手算、NEVER `HEAD~1`。
- 每輪修復後 commit 並驗證；R5、scanner/protocol error、stale anchor 與既有 STOP verdict 都不得合理化繞過。

## 執行流程

開始前，主 agent **複製以下 checklist 進回應**並逐項打勾追蹤進度（依模式刪去不適用項）：

```
Deep Review 進度：
- [ ] Step 0：識別審查範圍（多 repo 才需，單 repo 跳過）
- [ ] Step 1：確定審查範圍與 diff（base 偵測；autocodex 時判 codex_base_mode = diff / baseline）
- [ ] Step 2：偵測迭代輪次
- [ ] Step 3：載入專案 context
- [ ] Step 4：委派 subagent 審查（prompt 交 `reviewer-brief.md` 路徑，判準不轉述、不放寬）
- [ ] Step 5：彙整輸出
        autofix 進迴圈前：branch-first（依 verdict）→ 測試 baseline → record 錨點（--tests-baseline）
        → WIP snapshot（僅 working-tree 模式且有未提交變更）
        迴圈每輪重記一行：R{N} 審查 → 規則化+掃描（各軸，先於編輯）→ 修復 → 驗證 → commit（上限 R5）
- [ ] Step 6：Codex 第三方循環（僅 autocodex）
        進階段前先跑一次 codex runtime preflight check（非 0 只警告不阻擋）
        每輪重記一行：C{N} 審查 → 驗證 → 規則化+掃描（各軸，先於編輯）→ 修復 → commit（上限 C3）
- [ ] 通過後：squash 成乾淨 commit（`squash-cmd` 取指令 → reset → commit → `clear`；**`clear` 無條件跑，即使 WARNING 跳過了 reset/commit**；語意 message + runtime Co-Authored-By trailer；`squash-preserve:` / `squash-note:` 有印就轉述進報告；commit 即停，等使用者指示是否 push）
```

### 0. 識別審查範圍（多 Repo 偵測）

在開始審查前，主 agent 根據本 session 的記憶，列出所有涉及變更的 repo：

1. 回憶本 session 中修改過檔案的所有 repo 根目錄
2. 加上 pwd 所在的 repo（即使未改檔案）
3. **單一呼叫**確認全部 repo 狀態：`~/.claude/skills/deep-review/scripts/review-state.sh <repo1> <repo2> ...`（porcelain 含 untracked、base 偵測、領先 commit、輪次、branch-first verdict、continuity 銜接警告全在腳本內；Step 1/2 直接沿用同一份輸出，**不重跑**）
4. 向使用者展示清單並等待確認：

```
本次涉及 2 個 repo：
  1. ais-platform（3 檔案變更）
  2. ais-platform-deploy（5 檔案變更）
一起審查？或需要調整？
```

5. 使用者可：確認（ok）、限縮（只看 X）、擴充（還有 Y）
6. 若 context 被壓縮導致記憶不完整，以 pwd 的 repo 為底，讓使用者補充
7. 使用者指定的 repo 即使沒有 diff，也納入（可能需要檢查一致性）
8. **單一 repo** → 跳過此步驟，直接進入 Step 1

### 1. 確定審查範圍

完整 priority、base、baseline-mode、skill-authoring 與 untracked 規則在必讀的
`references/modes-and-scope.md`「1. 確定審查範圍」。只照該節與 `review-state.sh` 輸出決定：有明示 range →
working tree → 領先 default 的 branch → MUST ASK。主 agent 只讀 stat；full diff 由 reviewer 自取。

### 2. 偵測迭代輪次

取腳本 `round:` 輸出（依 `<base>..HEAD` **頂端連續**的 review 機械修復 commit 數推斷——使用者自己的 `fix:`/`refactor:` 會中斷連續段、更早場次被語意 commit 隔開的殘留也不計，否則兩者都會灌水吃掉 R5 預算；**與 squash 掃描是刻意不同的兩套集合、邊界也不同**——`wip: pre-review snapshot` 會中斷 round 計數（它不是一輪修復）卻會被 squash 收攏，故 `feat → wip → fix` 下 round 停在 wip、squash 停在 feat；勿把兩者重新耦合；`ahead:` 清單即 branch commit 歷史）。

- 無 review 修復 commit → **Round 1**（使用者自己的 `fix:`/`refactor:` 不算）
- 有 review 修復 commit → **Round 2+**（依其顆數推斷）
- 整檔審查模式（無 diff）→ **Round 1**
- **baseline 模式（base = empty-tree / 全庫稽核）→ 一律 Round 1**，不以 `git log` 歷史推斷輪次（empty-tree base 會列出 repo 全部 commit，歷史上符合 review 樣式的 commit 不代表本次 review 的迭代輪次）；下方「銜接檢查」同樣不適用

輪次影響審查重心，但**不把上一輪的 review 報告傳給 subagent**——每輪獨立判斷。

**銜接檢查**：腳本輸出 `continuity: WARNING` → 提醒使用者可能忘記 commit 上一輪修復（違反迭代紀律，先 commit 再續；baseline 模式忽略此警告）。

### 3. 載入專案 context

對每個 repo 讀取以下來源（有就讀，沒有跳過）：

- `<repo_root>/CLAUDE.md` + 變更檔案所在子目錄的 CLAUDE.md
- 當前專案的 `memory/MEMORY.md`
- `~/.claude/CLAUDE.md`
- `pyproject.toml` / `package.json` / `tsconfig.json`

### 4. 委派 subagent 審查

#### 審查契約（固定模板，主 agent 只填變數槽）

主 agent **照下列模板構造 subagent prompt**，只替換 `{}` 內的變數；模板本體逐輪不變、與輪次無關。這是**白名單**——不是「避開幾種禁語」，而是「只送這一份」。

```
You are an independent code reviewer. You have no prior context on this change.

Scope — review the complete cumulative diff:
  {diff-cmd 行，整行照抄；多 repo 時逐 repo 列出}

{僅當審查範圍含 untracked 檔（非 autofix 的 priority 2 路徑）才附此段，否則整段省略：}
Also in scope — these untracked files are NOT covered by the command above.
Read each one in full and treat its entire content as added lines:
  {untracked 檔案路徑逐行列出，取 review-state.sh 的 `untracked` 輸出}

Repo: {repo_path}{多 repo 時逐一列出路徑與名稱}
Project conventions — read these yourself: {CLAUDE.md／設定檔路徑清單，無則寫 none}

Reviewing criteria — Read this file completely before scoring anything:
  ~/.claude/skills/deep-review/references/reviewer-brief.md
It defines the dimensions, severity levels, pass bar, same-class sweep, and the
Completeness 深井 non-blocking clause. Follow it as written; do not substitute
your own standards.

Judge independently: correctness, security, regression, required tests,
deployment/configuration, and contract issues.

- Do NOT assume any part of this diff has already been reviewed or fixed.
- Do NOT adjust severity for repair cost, process stage, or delivery pressure.
- Every finding must carry: severity, file:line, triggering behavior, concrete
  impact, supporting evidence.
- Report "No findings" only when no concrete issue meets the bar. Finding count
  does not affect how this review is judged — a correct "No findings" and a
  correct blocking finding are equally valuable.

{baseline 模式才附這行，其餘模式整行省略：}
Note: this diff includes a pre-existing baseline. Completeness gaps in the
baseline that this change does not touch are non-blocking (see the brief's
深井 clause).

Output: verdict (PASS/FAIL per the brief's 通過標準) + findings grouped by root
cause + non-blocking items listed separately.
```

**變數槽只有這些**：`diff-cmd` 行、repo 路徑與名稱、專案 context 檔路徑、untracked 檔清單（條件段）、baseline 條件行。其餘一字不改。

> untracked 那段是**必要的 scope 資訊、不是額外指示**——priority 2 明訂審查範圍 = `git diff HEAD` + untracked 逐檔（見 Step 1），而 `git diff HEAD` 不含 untracked。少了它 reviewer 會漏審新檔且不自知（codex C2 抓到的契約衝突）。

**MUST NOT appear anywhere in the prompt** — these are leak channels, not style preferences:

> round number, round cap, rounds remaining, "final round", "last pass", "we're near max rounds", prior-round findings, the author's fix summary, "please verify the fixes", "only look for newly introduced problems", or any framing that the change is near completion or has already been vetted.

輪次是 **orchestration 層的私有狀態**：Step 2 照常偵測，用來決定何時停、報告怎麼寫——但不進 reviewer 的上下文。同理，`fix:` commit 的 message 不編輪號（見 `references/modes-and-scope.md`「迭代紀律：每輪修復後 commit」）。

**已知殘留，不要宣稱成完全隔離**：commit history 有兩條抵達 reviewer 的管道——(1) **harness 把 gitStatus（含最近 5 筆 commit 的 hash 與 subject）注入 subagent 的 system prompt**，reviewer 不做任何動作就看得到（2026-08-05 實測：`tool_uses=0` 的 subagent 能逐字複述主 repo 的 5 個 commit hash）；(2) reviewer 自行跑 `git log`（實測 6/6 都跑）。每輪恰好產生一個 fix commit，故**數同名 commit 仍可反推「已改過幾次」**。中性化擋掉的是輪號與「還剩幾輪」，擋不掉「已完成幾輪」。要完全消除得每輪 squash，那會破壞迭代紀律與 context 控制，成本大於收益，故接受此殘留。**但管道 (1) 無需 reviewer 主動、也關不掉，故 commit message 中性化是必要而非可選**——寫成 `fix: R4 review fixes` 等於把輪號零成本送進 reviewer 的 system prompt。

**Why a fixed template rather than a ban list**: a ban list must enumerate every phrasing, and enumeration provably leaks — 本 repo 實測過一次（列了 `final round`，實際寫法是 `FINAL allowed review round`，差點誤判；見 evals.md 2026-08-04 方法論教訓）。同一個 blocklist-vs-allowlist 教訓。

**Hand the subagent the *range*, not the diff text.** Re-sending the full diff through the main context costs double tokens for zero information gain — the subagent runs the exact same `git diff` and sees the identical content. Main agent stays at stat-level. Same principle for the bar: hand over the brief's *path*, never a paraphrase of it.

Subagent 收齊多個 repo 的 diff 後，如同 reviewer 同時被 assign 多個關聯 PR——自己讀 diff、自己判斷關聯性、自己檢查一致性。

#### 規模策略

| 跨所有 repo 合計檔案數 | 策略 |
|----------------------|------|
| ≤ 20 | 單一 subagent，收到所有 repo 的 diff + context，獨立判斷 repo 內品質與跨 repo 一致性 |
| 21–40 | 每 repo 各一個 subagent（repo 內審查）+ 一個「跨 repo 一致性」subagent（收所有 repo 的 diff） |
| > 40 | 同上，但 repo 內再依模組分拆，**每個 subagent 約 8–12 個變更檔或一個內聚模組**，確保 scope 可掌握 |

**切分原則**：避免重複的大範圍 prompt；只在關鍵介面、安全邊界、跨模組行為這些地方讓 scope 略為重疊。

**重要**：跨 repo 一致性的判斷由 subagent 執行（subagent 不可用時依「審查者與作者分離」的降級條款處理），主 agent 不主動做此判斷。多 subagent 時，主 agent 僅拼接各 subagent 的輸出，不加工、不篩選、不淡化嚴重度。

### 5. 彙整輸出與 Autofix 循環

主 agent 接收 subagent 結果，按以下格式輸出。主 agent 僅做 orchestration（格式化、拼接），不加入自己的 code-quality 判斷。報告的首要讀者是**負責修復的 agent**，其次是人類。

**Autofix 模式下的流程**：
1. subagent 回傳審查結果
2. 若通過 → 輸出通過報告（含第三方審查資訊）→ 若有 autocodex → 進入 Step 6；否則結束
3. 若未通過且已達 R5 → **先執行 `~/.claude/skills/deep-review/scripts/review-anchor.sh terminate --repo <r> --reason r5-blocking`（成功後）再輸出 autofix 終止報告**，結束（不進入 codex 階段）。
   **順序不可顛倒**——final response 之後沒有保證還能執行工具，寫成「報告後再 terminate」等於它可能永遠不會落盤。報告中標明 terminal 已落盤。
   > 這道 state 讓「終止」成為 terminal：下一次 `record` 會 STOP，不會靜默重開新 cycle（2026-08-06 實地發生過，外層重置了輪次上限）。續審同一批變更用 `resume-after-terminal`（base 不變、cycle +1）；要重建全新審查範圍才用 `clear` + `record`。
4. 若未通過且未達上限 → 主 agent 依修復計畫執行修復 → 驗證（見 `references/modes-and-scope.md`「Autofix 模式」）→ 測試通過才 commit → 回到 Step 4 發起下一輪審查；若驗證無法通過（反覆修仍紅或環境擋住）→ 依該節停止，輸出終止/blocked 報告（沿用 Autofix 終止模板，於收斂失敗分析註明是測試卡關），不進下一輪
   - **context 處理**：Step 3 的專案 context（CLAUDE.md、設定檔）沿用，不重新收集；diff 由**每輪全新的 subagent 自行收集**（傳同一條 range 指令即可——修復 commit 後 HEAD 前進，subagent 跑 `git diff <base>...HEAD` 拿到的自然是涵蓋最新修復的完整 diff），主 agent 不搬運 diff 內容、也不讓 subagent 沿用任何舊輪產物
   - **baseline 模式的收斂（autofix 與 autocodex 機制不同）**：autofix 的 range **不縮**（fixer 需看完整狀態確認沒改壞），改縮 **blocking 判準**——baseline 模式時，契約模板加上那個 baseline 條件行（見 Step 4 模板；它描述的是 artifact 狀態「此 diff 含既有基線」，**不提輪次、不提已審過幾次**）。此 range 機制 diff 模式不套用、照常全審；但 diff 內若含 prose artifact，其措辭/完整度 nits 仍套 Completeness 深井判準（見 `references/reviewer-brief.md`，不分模式）。
   - **成本與邊界**：autofix baseline 因 range 不縮，subagent 每輪吃 `<empty-tree>..HEAD`（整庫）diff——大型 repo 會撞 Step 4 的 context 上限。靠 Step 4「規模策略 >40」依模組分拆 subagent 緩解；若仍過大，建議全庫稽核改走 autocodex（codex 階段 C2+ 才有縮 range）。autocodex 縮 range / autofix 縮判準 的差異源於：autocodex 是無狀態第三方、autofix 的 fixer 需看完整狀態。

**非 Autofix + Autocodex 模式**：手動審查通過後，主 agent 輸出通過報告，接著自動進入 Step 6。

#### 完成判定

嚴重度分級與通過標準見 `references/reviewer-brief.md`（reviewer 與主 agent 共用同一份，不在此重述）。Autofix 模式下，主 agent 優先修復嚴重與中等問題；建議等級僅在修復不引入額外風險時順手處理。

輸出報告時，參考 `references/report-templates.md` 中的模板格式。包含：未通過（單/多 repo）、通過、Autofix 終止四種模板。

報告核心原則：
- 問題**按根因分組**，不按嚴重度排列，讓 fixer 一次解決共因問題
- 修復計畫由 subagent 根據具體問題產出
- 修完後先 commit（如 `fix: address review findings`），再執行下一輪 `/deep-review`
- 最終通過後，主 agent squash 掉 squash base 之上的 review fix commits：執行 `~/.claude/skills/deep-review/scripts/review-anchor.sh squash-cmd --repo <r>`，照 `squash-cmd:` 輸出照抄 reset（腳本拒給——`verdict: STOP`——時停下交使用者，勿自行湊 hash），重新 commit 後跑 `clear`。腳本另印兩行訊號，**有印就在通過報告轉述、不必中斷等待**：`squash-preserve:`（保留下來的既有語意 commit，它們會與新 squash commit 並存在 branch/PR 上）、`squash-note:`（被非 review commit 隔開、因此未納入本次 squash 的 review 樣式 commit——需要併掉得由使用者決定，勿自行擴大 reset 範圍）。**message 依 `squash-preserve:` 分流**（reset 目標一移動，「描述整個功能」就會失真）：無 `squash-preserve:`（squash base == anchor base，新 commit 即完整變更）→ 採原始功能變更的語意（不是 `fix: review fixes`）；**有 `squash-preserve:`** → 新 commit 的內容只是「相對保留 commit 的增量」，message 就描述那個增量（如 `fix: 修正 X 的邊界處理`），**NEVER reuse the preserved commit's subject** —— 寫成同一句功能語意會讓 PR 上出現兩顆同名 commit、其中一顆沒有該功能的內容。兩種情形都遵循專案 Conventional Commits，並附 `Co-Authored-By` trailer（以 runtime system prompt 的 Git 區塊為權威，勿在 skill 寫死 model 名稱/版本）。**`verdict: WARNING`（無 commit 可 squash）時跳過 reset 與 commit，但 `clear` 照跑**——沒有可壓的東西（`git commit` 會因無 staged 內容而失敗），但審查已完成，anchor 不清會讓下一場 review 被誤判成續跑（`cycle: 2+`）、也會讓 `show` 交出過期的審查起點
- **通過報告必須附「第三方審查資訊」**：列出每個 repo 的 commit 範圍（`base..head`，base = anchor 記錄的審查起點，跨 session 可用 `review-anchor.sh show` 恢復）和變更摘要，方便使用者轉交第三方 reviewer。R5 終止報告不需要此區塊（代碼尚未就緒）

### 6. Codex 第三方審查循環（autocodex 模式）

僅在引數包含 `autocodex` 且主 agent 審查通過後執行。主 agent 審查未通過（含 R5 終止）不進入此階段。

#### 流程

1. 從 Step 5 通過報告的「第三方審查資訊」取出每個 repo 的路徑
2. 對每個 repo 跑 `review-anchor.sh codex-next --repo <repo>` 取 `codex-cmd:` 行，以背景 Bash 整行照抄執行（見 `references/modes-and-scope.md`「Autocodex 模式」；exit 契約與救援階梯照其 protocol 檔）
3. 收到 codex findings 後，主 agent 逐條讀原始碼獨立驗證：
   - **true positive**：確實有問題，需修復
   - **false positive**：codex 誤判，不處理
   - **context-dependent**：需更多 context 才能判定——**可能是真 bug** → 當 true positive 修；**屬 completeness / prose 深井**（見 `references/reviewer-brief.md`）→ non-blocking，不修、不觸發再一輪
4. 若無 true positive blocking findings（深井不算）→ 輸出 codex 通過報告，執行最終 squash，結束
5. 有 true positive（非深井）→ 主 agent 修復 → commit `fix: address external review findings` → 回到步驟 2（下一輪 range 由 `codex-next` 給出，兩模式 C2+ 皆只審增量，見 `references/modes-and-scope.md`「Commit range 更新」）
6. 達到上限（3 輪審查、2 輪修復）仍有 true positive（指向修復本身、非 Completeness 深井）→ 輸出 codex 終止報告，停止

> 步驟 3 驗證時，屬 Completeness 深井的 finding（baseline backlog 或 prose artifact，見 `references/reviewer-brief.md`，**不分模式**）→ non-blocking，不觸發步驟 5 的再一輪修復；只有指向本輪修復 commit 的真 bug / 安全 / 契約斷裂才算 blocking。達上限時若只剩深井（無真 bug）→ 判通過走通過報告，非終止報告。

#### 注意事項

- codex 階段主 agent 同時扮演「驗證者」和「修復者」，不再委派 subagent（因為 codex 本身就是獨立第三方）
- 多 repo 時逐 repo 處理，每個 repo 獨立計算輪次上限
- 最終 squash 範圍涵蓋 squash base 之上的 review fix commits（主 agent 審查階段 + codex 階段）；被語意 commit 隔在下層而未納入者由 `squash-note:` 列出，**要不要併由使用者決定，勿自行擴大 reset 範圍**
- 輸出報告參考 `references/report-templates.md` 中的 codex 通過 / codex 終止 / codex blocked 模板
- codex 執行失敗（救援階梯走完仍無報告）→ 走 **blocked 模板**，不是終止模板：終止＝審完但沒收斂，blocked＝根本沒審成，兩者不可混用
