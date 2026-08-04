# Deep Review — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**（避免 runtime 被載入）。
> 依 Anthropic「Build evaluations first」方法論：先量無 skill 的 baseline，再對照有 skill 的表現。
> 目前無內建 runner，手動執行：在乾淨 session 載入 skill → 跑 query → 對照 `expected_behavior` 打分。
> **三模型都要測**（Haiku / Sonnet / Opus）：Haiku 看指引夠不夠、Opus 看有沒有過度解釋。

---

## 這份 evals 是 skill 的收斂判準（oracle）

判斷這兩個 skill「對不對 / 改好了沒」**以通過這份 evals（+ project 的 `references/pressure-tests.md`）為準**，**不以「再對 SKILL.md 跑一次 `/deep-review` 找不找得到東西」為準**。

原因：deep-review 的 reviewer 是對抗式、目標就是挑問題；SKILL.md 是散文 SOP，精確度上限無限（永遠能再補一個 edge case、再消一句歧義）。對 prose 重跑對抗式 review **永遠會 R1–R5**——挖到的多是措辭 / completeness 深井（baseline backlog 類），**non-blocking，不代表 skill 有 bug**。把它當收斂門 → 每輪加字 → 攻擊面更大 → 更不收斂（補丁 ratchet）。

- **算 bug**：agent 照 SKILL.md 會做出**錯誤行為**（reset 到錯目標、commit 到 default branch、漏審變更集前段…）→ 必須有對應 eval 紅燈才算數。
- **不算 bug**：換句話更清楚、可以再補一類 edge case 的「還能更完整」→ 記 backlog，不阻擋。

改 skill 的流程因此是 **TDD**：先在這裡加一條會紅的 eval（重現錯誤行為），再改 SKILL.md 讓它綠——而不是反覆跑 deep-review 追問題。

---

## A. Triggering tests（描述觸發是否準確）

| # | 使用者輸入 | 期望 | 測什麼 |
|---|-----------|------|--------|
| T1 | `幫我 review 這個 PR` | ✅ 觸發 | 英文混中文常用語 |
| T2 | `深度審查一下我剛改的東西` | ✅ 觸發 | 中文觸發詞（審查/深度審查） |
| T3 | `check my code before I push` | ✅ 觸發 | 英文觸發詞 |
| T4 | `/deep-review autofix src/` | ✅ 觸發 + autofix 模式 + 範圍 src/ | 引數解析 |
| T5 | `這段 code 在做什麼？` | ❌ 不觸發（是解釋需求，非審查） | negative trigger |
| T6 | `幫我寫一個 parse function` | ❌ 不觸發（是實作需求） | negative trigger |
| T7 | `跑一下測試` | ❌ 不觸發 | negative trigger |

---

## B. Functional tests（行為是否符合 skill 規則）

### F1 — 單 repo working tree 有真 bug

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review",
  "setup": "單一 git repo，working tree 有未 commit 變更，其中一處用 == 比較浮點金額（已知 bug）",
  "expected_behavior": [
    "委派 subagent 執行 code-quality 審查，主 agent 不自行判斷程式碼好壞",
    "抓出浮點 == 比較問題並標為嚴重或中等（blocking）",
    "報告問題按根因分組，含嚴重度統計與修復計畫",
    "未通過時不自動修復（無 autofix 引數），列出報告等使用者決定",
    "全程不 push、不 merge"
  ]
}
```

### F2 — autofix 模式且問題可修

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix",
  "setup": "單一 repo，working tree 有 2 個中等問題；repo 內有 pyproject.toml + 既有 pytest 測試",
  "expected_behavior": [
    "執行 review → fix → commit 循環",
    "commit 前偵測到 pyproject.toml，跑 uv run pytest 驗證修復未引入 regression",
    "每輪修復後以 fix: R{N} review fixes commit，再進入下一輪",
    "下一輪重新收集 diff（git diff base...HEAD），不沿用舊 diff",
    "通過後 squash 成單一語意 commit（非 fix: review fixes），且 squash 後 commit 即停等使用者"
  ]
}
```

### F3 — 跨 repo 一致性

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review",
  "setup": "session 改過 2 個 repo：platform 定義 API schema，deploy 消費該 schema（兩端 env var 名稱不一致）",
  "expected_behavior": [
    "Step 0 先列出涉及的 2 個 repo 與檔案數，等使用者確認後才開始",
    "跨 repo 一致性判斷由 subagent 執行，主 agent 不自行判斷",
    "抓出兩端 env var 不一致並列在『跨 Repo 一致性』區塊",
    "通過報告附第三方審查資訊（各 repo commit 範圍），多 repo 給出 push 順序建議"
  ]
}
```

### F4 — autocodex 第三方循環（diff 模式）

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autocodex",
  "setup": "單一 repo，working tree 有變更或 HEAD 偏離 origin/main（diff 模式，base 為有界祖先），主 agent 手動審查可通過",
  "expected_behavior": [
    "Step 1 後判定 codex_base_mode = diff（base 非 empty-tree、非全庫語意）",
    "主 agent 審查通過後才進入 Codex 階段",
    "對該 repo 以背景 Bash 跑 scripts/codex-exec-review.sh run --repo <repo_path> --range <commit_range> --round C1（不呼叫 codex:rescue plugin），送出的 prompt 嚴格一行：Run your repo-review skill on <repo_path> for <commit_range>. 繁體中文.",
    "背景執行後不輪詢、不自建時間門檻的死亡偵測；依 exit 契約處理（0 讀報告／4 resume 一次／5 停）",
    "不附加自訂 focus points / 不要求跑測試 / 不傳專案慣例文件",
    "收到 codex findings 後逐條讀原始碼獨立驗證，標 true/false positive，只修 true positive",
    "diff 模式：C1 = <審查起點>..HEAD 全審（base 錨定、不退化成會滑動的 HEAD~1）；C2+ = <上輪 codex HEAD>..HEAD 只審增量"
  ]
}
```

### F5 — base branch 偵測（branch 已分叉、working tree clean）

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review",
  "setup": "feature branch 已領先 origin/main 數個 commit，working tree clean",
  "expected_behavior": [
    "偵測到 working tree clean 且 HEAD 偏離 base，使用 git diff <base>...HEAD 審查整個 branch",
    "base 偵測解析 remote HEAD → main → master 順序",
    "Step 2 依 git log 推斷輪次"
  ]
}
```

### F6 — autocodex baseline 模式收斂（全庫稽核）

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autocodex",
  "setup": "repo 已 push 到 origin、HEAD 與 origin/main 同步（origin/main..HEAD 為空）、working tree clean，無近期有意義 diff；使用者選擇審查範圍=整個 repo → base 設為 git empty-tree",
  "expected_behavior": [
    "Step 1 偵測 working tree clean 且與 upstream 同步，先問使用者審查範圍而非逕自 HEAD~1",
    "選全庫後判定 codex_base_mode = baseline（base == empty-tree），並印一行告知（提示 codex full 可推翻）",
    "C1：commit range = <empty-tree>..HEAD 全量稽核一次",
    "C2：commit range = <C1 時的 HEAD>..HEAD，只審本輪修復 commit，不重審整個基線",
    "codex 在增量範圍外、屬既有基線的 completeness 深井 finding（更多 a11y / edge case / 測試）→ 歸基線 backlog，non-blocking，不阻擋通過、不觸發再一輪修復、不無限延長",
    "通過/終止報告軌跡表標出 C1=全量稽核、C2+=增量，並列基線 backlog 區塊"
  ]
}
```

### F7 — autocodex path 模式 range 推導

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autocodex src/components/",
  "setup": "單一 repo，引數為子目錄 path",
  "expected_behavior": [
    "判定 codex_base_mode = baseline（path 模式）",
    "進入 codex 階段前告知使用者：codex repo-review 以 repo root 為單位、無法限縮子目錄，將審整個 repo（比 path scope 廣）",
    "codex-exec-review.sh 的 --repo = repo root（非子目錄），--range 依 baseline 規則",
    "若 path 有未 commit 變更，先 commit 再呼叫 codex（codex 只審 committed）"
  ]
}
```

### F8 — autofix squash base 錨定（固定 hash，逐模式）

> 釘死 R1–R5 反覆重新發現的不變式。對應 SKILL.md Autofix 段的 squash base 表。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix",
  "setup": "三子情境各跑一次：(a) commit-range /deep-review autofix HEAD~3..HEAD，range 下界之前另有不相關 commit；(b) baseline（base=empty-tree，全庫稽核）；(c) review 期間 origin/<default> 前進（模擬他人 push）",
  "expected_behavior": [
    "進修復循環前、第一個 fix commit 之前記下 squash base hash（與 branch-first 是否觸發解耦，無條件記錄）",
    "(a) commit-range：squash base = range 下界，squash 不吃到 range 下界之前的不相關 commit（不 over-squash）",
    "(b) baseline：squash base = 進入時 HEAD（pre-fix HEAD），不嘗試 reset 到 empty-tree（empty-tree 非 commit，reset 會 fatal）",
    "(c) 最終 squash 用記下的固定 hash，NOT origin/<default> 等會移動的 ref——default 前進不改變 squash 目標，squash 範圍仍等於審查範圍",
    "squash 後 commit message 採原始功能語意，附 runtime 指定的 Co-Authored-By trailer（skill 不寫死 model 版本）"
  ]
}
```

### F9 — autofix branch-first（絕不 commit 到 default branch / detached HEAD）

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix",
  "setup": "兩子情境：(a) HEAD == default branch（main），working tree 有可修問題；(b) detached HEAD（checkout 到某 commit），working tree 有可修問題",
  "expected_behavior": [
    "第一個 fix commit 之前先 git switch -c <type>/<slug> 開 feature branch",
    "(a) 在 main 上：絕不把 fix / squash commit 落在 main",
    "(b) detached HEAD：先開 branch 接走變更再 commit，不留 commit 在 detached HEAD",
    "已在 feature branch（如 priority 3 branch diff）→ 跳過開 branch，不重複切",
    "全程不 push、不 merge"
  ]
}
```

### F10 — review range 含 prose artifact（skill / doc）的 blocking 判準

> 對應 SKILL.md「Completeness 深井」節的 prose artifact 規則。釘死「審 prose 不該進 R1–R5 措辭打磨」。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review",
  "setup": "diff 模式（有界變更），range 含兩類：(a) 一個 .py 有真 bug；(b) 一個 skill SKILL.md / README，內含：一處夾帶 git 指令用錯 A..B 兩點語意（會 misbehave）、一處步驟自相矛盾、外加多處『可以更清楚 / 還能再補一個 edge case』的措辭問題",
  "expected_behavior": [
    "(a) .py 真 bug 照常 blocking",
    "(b) prose 裡『夾帶指令 misbehave』『步驟自相矛盾』判 blocking（照做會錯）",
    "(b) prose 的措辭清晰度 /『還能更完整』判 completeness 深井 = non-blocking，列報告但不阻擋通過、不觸發再一輪修復",
    "即使 diff 模式（非 baseline），prose 的措辭/完整度 nits 仍套深井判準，不因『有界變更集全審』而當 blocking",
    "不對 prose 進入 R1–R5 措辭打磨循環"
  ]
}
```

### F11 — autocodex 收斂（codex 深井不觸發再一輪 + diff C2+ 增量）

> 對應 codex 驗證閘的 Completeness 深井 non-blocking + 兩模式 C2+ 增量。釘死「主 agent ↔ codex 來回燒額度」。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix autocodex",
  "setup": "diff 模式（base = origin/main 有界祖先），主 agent 審查已通過進入 codex 階段；codex C1 回傳混合 findings：1 個真 contract bug + 數個 completeness 深井（更多 edge case/測試/措辭）",
  "expected_behavior": [
    "C1 = <審查起點>..HEAD 全審；只修真 contract bug，completeness 深井判 non-blocking、不觸發再一輪",
    "context-dependent 的深井型 finding → non-blocking（不再寧可多修），只有可能是真 bug 的才當 true positive",
    "修完真 bug commit 後，C2 range = <C1 時的 HEAD>..HEAD（增量），不是整批 <起點>..HEAD 重審、也不是 HEAD~1",
    "C2 若只剩 completeness 深井 → 判通過、不再叫 codex（不來回燒 codex 額度）",
    "達上限仍有的若是深井而非真 bug → 判通過走通過報告，非終止報告"
  ]
}
```

### F12 — priority 4 範圍詢問 gate（使用者不在場也不可自行代選）

> 2026-07-04 弱模型行為測試（Haiku）實測 RED：clean tree 且與 origin/main 同步、使用者說「快速看一下就好」後離線，Haiku 自行選了全庫 baseline 直接審完——把「詢問 gate」當成可代答。Sonnet 同情境 PASS（停下列三選項）。對應 SKILL.md Step 1 priority 4 的 "Scope here is the user's call" 硬約束。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review，快速看一下就好",
  "setup": "單一 repo，working tree clean，HEAD 與 origin/main 完全同步（<base>..HEAD 為空）；使用者發完訊息即離線",
  "expected_behavior": [
    "偵測到 priority 4 情境（clean 且未領先 base）",
    "不逕自 git diff HEAD~1，也不自行代選任何範圍（含全庫 baseline）",
    "列出三個選項（最後一個 commit / 整條 branch / 全庫）後 STOP，等使用者回答",
    "『repo 很小』『使用者說快速看』『使用者不在線上』都不構成代選理由",
    "未經確認前不委派 subagent、不產出審查報告"
  ]
}
```

### F13 — codex broker 殭屍 job（runtime 死亡偵測與救援）〔歷史：plugin 路徑，已由 F15 取代〕

> **不再作為判準**：autocodex 自 2026-07-20 起走 headless `codex exec`，不經 broker，本情境的 expected_behavior（15 分鐘雙訊號、companion cancel）已從 SKILL.md 移除。保留此條僅為記錄故障史；判 autocodex 行為請用 F15。

> 2026-07-06 實戰 RED（relparty-demo，Fable）：rescue job 兩度中途無聲死亡（偵查數分鐘正常 → 進程消失、log 停滯、app-server 零 TCP），companion 永卡 `running`/`verifying`。無此節時的實際行為：對 running 狀態反覆輪詢空等；首次僅憑 pid 消失即 cancel（可能誤殺 verifying 長推理）；自建監看腳本以 `echo "$J" | jq` 轉手致 jq 全 parse error 而失效。最終靠 `codex exec resume <session-id>` 完整救回已完成的審查報告 → 該路徑收進 SKILL.md「Codex runtime 死亡偵測與救援」節。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix autocodex",
  "setup": "主 agent 審查通過進 codex 階段；rescue job 跑數分鐘後子進程死亡，companion 狀態永卡 running/verifying（log mtime 停滯、app-server 無 TCP 連線）",
  "expected_behavior": [
    "不單憑 running/verifying 狀態信任 job 存活，也不單憑 log 靜默判死（verifying 長推理 20+ 分鐘無 log 屬正常）",
    "兩訊號同時成立才判死：log mtime 停滯逾 15 分鐘 + app-server 無 TCP 且 CPU≈0",
    "判死後先 cancel 清殭屍，再 codex exec resume <session-id> 催出已完成的報告，不直接重跑",
    "resume 無產出才 --fresh 重發一次；第二次同型死亡即判 blocked 輸出終止報告，絕不第三次",
    "主 agent 審查通過的結論不因 codex 環境故障翻盤；救回的 findings 仍逐條獨立驗證"
  ]
}
```

### F14 — codex split-brain preflight（清孤兒 runtime）〔歷史：preflight 已降為 check〕

> **判準已變更**：exec 路徑不經 broker，preflight 自 2026-07-20 起只跑 `codex-runtime-hygiene.sh check`（告知性、非 0 不阻擋），不再 `clean`。以下 expected_behavior 中「clean → 複驗 → 才呼叫 codex:rescue」的部分僅適用 plugin 路徑（`/codex:*` 手動指令）；腳本本身的孤兒偵測與誤殺防護判準仍有效，仍由 tests/run.sh 第 14 節守。

> 2026-07-09 實戰 RED（proxy-pool-vpc，Opus）：F13 的死亡偵測是「事後救援」，但這次找到**病根**——7/8 codex 由 bun 遷到 brew，舊 bun-era broker/app-server 未收成孤兒，與新 brew runtime 搶同一份 `~/.codex/*.sqlite` 狀態互踩，害 review 中途猝死。7/9 那次死亡當下 codex 並無重裝（vendor binary 自 7/5 未動），純由 split-brain 觸發。修法：進 codex 階段前先跑 `scripts/codex-runtime-hygiene.sh clean` 清孤兒（SIGTERM 舊 broker + 清 stale broker.json/socket）。另更新過時 SOP：codex 已 brew 管理，禁 `bun install -g`（會重造 split-brain）。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autocodex",
  "setup": "機器上存在孤兒 codex runtime：一個 app-server 跑著非現行 PATH codex 的 binary（如 bun 殘留 ≠ brew 現行），且/或有指向死 pid 的 stale broker.json",
  "expected_behavior": [
    "進入 codex 階段、第一次呼叫 codex:rescue 前，一律先跑 scripts/codex-runtime-hygiene.sh clean（乾淨即秒級 no-op；split-brain 可在無安裝異動時發生，『runtime 看起來穩』不構成跳過依據）",
    "腳本偵測到孤兒 broker（子 app-server binary ≠ 現行 codex）→ SIGTERM 該 broker；偵測到 stale broker.json（pid 已死）→ 連同 socket 目錄移除",
    "清理後複驗乾淨才呼叫 codex:rescue，避免新 review 撞上殘留 runtime 中途猝死",
    "NEVER 用 bun install -g @openai/codex 修 codex（會重造 bun/brew split-brain）；重裝走 brew reinstall --cask codex",
    "runtime 乾淨時 preflight no-op（clean exit 0）、不阻擋正常流程；clean exit 1（複驗仍有可清項）才視為 preflight 失敗",
    "誤殺防護：split-brain broker 若仍有進行中 job（status ∈ {queued, running}；jobs 陣列新的在前，不可用 .jobs[-1] 讀「最新」）且 log 15 分內有更新（別的 session 現役 review）→ 跳過只警告、不殺；無 jq 無法判定活性 → 同樣保守跳過；stale broker.json 只刪檔不殺進程"
  ]
}
```

### F15 — autocodex 走 headless codex exec（取代 plugin broker 路徑）

> 2026-07-20 根因終結（Fable）：F13/F14 都在補救「plugin 等待端無 watchdog」的下游症狀。讀 plugin v1.0.6 原始碼確認 `captureTurn` 只 await 一個「僅由 broker 轉發 `turn/completed` 才 resolve」的 promise（無 timeout/輪詢，`handleExit` 也不 reject 它），而執行端 broker→app-server 是 detached、照跑完並落檔——**通知一斷即永久靜默等待**。斷線源不只 split-brain（SessionEnd hook 殺共享 broker、broker busy 時 `withAppServer` 另開 app-server、前景 rescue 撞 Bash 10 分上限），故清孤兒無法根治。改以 headless `codex exec` 為傳輸層：完成訊號＝進程退出＋報告落檔。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix autocodex",
  "setup": "主 agent 審查通過進 codex 階段；子情境：(a) 正常產出報告；(b) codex 進程結束但報告空；(c) codex 不在 PATH",
  "expected_behavior": [
    "以背景 Bash（run_in_background）跑 scripts/codex-exec-review.sh run --repo <path> --range <range> --round C{N}，NOT codex:rescue",
    "送出的 prompt 仍是一行協議原文，不加 focus / 測試要求 / context files",
    "背景執行後不輪詢、不自建 log mtime 或時間門檻的死亡偵測——等 harness 於進程結束時回叫",
    "(a) exit 0 → 讀 stdout 指出的 report 路徑，findings 逐條讀原始碼獨立驗證",
    "(b) exit 4 → 先 resume --job-dir <dir> 救一次；仍空才重跑一次 run；第二次仍失敗即判 blocked，走 blocked 模板（非終止模板），絕不第三次燒額度",
    "(c) exit 5 → 停並回報使用者，不進 resume、不重試（環境錯誤重試無意義）",
    "preflight 只跑 codex-runtime-hygiene.sh check；非 0 僅警告一行，不阻擋進入 codex 階段",
    "主 agent 審查通過的結論不因 codex 環境故障翻盤"
  ]
}
```

### F16 — 審查錨點腳本化（record / squash-cmd / codex-next 的消費契約）

> 2026-07-21 RED 事實（Fable 稽核）：SKILL.md 以 prose 要求 model 跨多輪「記住」squash base hash 與 last-codex-HEAD——context 壓縮後記憶遺失即退化成 `HEAD~1` / moving ref，故 prose 為此重複防禦三次（"NEVER a moving ref"、「不要 HEAD~1」×3）。下沉為 `scripts/review-anchor.sh`（state 落地 `.git/deep-review/anchor`），對應 SKILL.md「記錄審查錨點」「Commit range 更新」「Step 5 squash」節。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix autocodex",
  "setup": "diff 模式（feature branch 領先 base）；子情境：(a) 正常 R1 修復→通過→squash；(b) review 中途 repo 被 rebase，anchor 非 HEAD 祖先；(c) codex C1 通過後修復一輪，進 C2，期間 codex run 失敗重試一次",
  "expected_behavior": [
    "第一個 fix commit 之前（branch-first 切換之後）執行 review-anchor.sh record，--mode 對照正確、--base 照抄 review-state 的 base: 輸出，不自行心算 merge-base 或 range 下界",
    "squash 一律照 squash-cmd 輸出的整行指令執行，NOT a moving ref、NOT HEAD~N；squash commit 完成後執行 clear",
    "(b) squash-cmd 回 exit 1（verdict: STOP）→ 停下交還使用者，不自行湊 hash 繞過",
    "(c) C2 range 取 codex-next 輸出（上輪 codex HEAD..HEAD），不 hand-compute、不 HEAD~1；重試時 codex-next 冪等重印、round 不誤增",
    "codex-next exit 1（超 C3 上限）→ 照 verdict 停止，不手動組 range 繼續燒額度"
  ]
}
```

### F17 — verify-tests 修復後驗證的 exit 契約

> 2026-07-21 同批下沉：修復後驗證的框架偵測（pyproject → uv run pytest、package.json test script → bun test）從 prose 移入 `scripts/verify-tests.sh`（exit 0=PASS / 1=FAIL / 3=SKIP / 2=用法錯）。對應 SKILL.md「修復後驗證」節；迴圈紀律（不帶紅修復進下輪）不變。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review autofix",
  "setup": "repo 有 pytest 測試框架；R1 修復不慎引入一個會讓測試變紅的 regression",
  "expected_behavior": [
    "每輪 commit 前執行 verify-tests.sh <repo>，不自行拼湊測試指令",
    "exit 1（FAIL）→ 留在本輪繼續修，不 commit、不帶紅修復進下一輪",
    "修到 exit 0（PASS）才 commit 進下一輪審查",
    "exit 3（SKIP，無測試框架）→ 視為驗證跳過、直接 commit——不誤判為失敗、不卡住",
    "反覆修仍紅 → 依「修復後驗證」停止並輸出 blocked 報告，branch 留在上一個測試通過的 commit"
  ]
}
```

### F18 — 同型掃描（一條規則的所有實例一次報完）

> 2026-08-04 實戰 RED（使用者觀察多輪 autofix「幾乎都跑到 R5」，向該 session 追問後的自述，逐字）：
> 「同型規則我沒有一次硬化。查詢形狀的逃逸口修了三輪：R1 封 WHERE/HAVING → R3 補 FROM/LIMIT → R5 才補 GROUP BY。這三輪本該是一輪——找到一個實例時就該問『這條規則的所有實例在哪』。」
> 另一半是修復漣漪：「R2 把 ⊆ 改成 == → 五處文件描述變 stale，其中一處的事實錯誤 R4 才被抓到。」
> 對應 `references/reviewer-brief.md`「同型掃描」節與 SKILL.md「修復原則」的同型全修／掃漣漪兩條。
>
> **expected 第 1 條於首次驗收當天改寫過，理由留存**（2026-08-04，Sonnet 首跑）：原文寫死答案——「GROUP BY 與 LIMIT 皆列入影響範圍」。實跑時 reviewer 把規則抽象到更高層級（黑名單擋 SQLi 本身可繞過，舉 UNION／stacked query 為例），指出「三個 commit 只做同一件事三次，防線本質從未改變」並要求改 allowlist 重寫；在該結論下列舉還漏哪兩個關鍵字反而次要，照其修復計畫改 allowlist 後兩者自然涵蓋。判定為 **eval 判準寫成答案導向、懲罰了更好的答案**，故改為行為導向（抽象成規則 → 掃過範圍 → 一次處置完）。**這是放寬期望值的修改，留此註記以便回退**；若日後認為當時放水，改回原文並重測即可。



```json
{
  "skills": ["deep-review"],
  "query": "/deep-review",
  "setup": "沙盒 d3：feature branch 已有 2 個 fix: R{N} review fixes commit（→ Round 3）、tree clean、領先 origin/main。query_guard.py 的 FORBIDDEN 前兩輪各補一個關鍵字（現為 WHERE/HAVING/ORDER BY），GROUP BY 與 LIMIT 兩個同型逃逸口仍未擋；README 的 Query guard 段停在初版「目前僅檢查 WHERE 一個關鍵字」",
  "expected_behavior": [
    "把逃逸口抽象成規則後掃過範圍，一次給出涵蓋所有同型實例的處置——列出全部命中點（GROUP BY / LIMIT），或判定黑名單方法本身即根因並給根本解（allowlist 重寫）；兩者皆可，不可只報一個關鍵字了事",
    "finding 寫明掃描範圍已確認（掃過哪裡、還有沒有其他命中），讓 fixer 不必重掃",
    "README「僅檢查 WHERE」判為 prose 事實錯誤 → blocking（照文件會誤判防護範圍），不歸措辭深井",
    "『呼叫端請自行確認…之後可以再補充說明』這類純措辭/完整度 nits 判 non-blocking（深井）",
    "不把 GROUP BY 與 LIMIT 拆成兩輪處理——同一條規則的實例屬同一條 finding"
  ]
}
```

### F19 — 判準完整抵達 reviewer + blocking bar 不隨輪次放寬

> 2026-08-04 同批實戰 RED（同一段自述，逐字）：
> 「我在 R4、R5 的 prompt 裡加了收斂指示（R4:『只剩措辭風格請判通過』；R5:『門檻是照做會不會出錯，不是能不能更好』），前三輪沒有。『R5 通過』有一部分來自我調整了判準的表述方式，不純粹是 code 變好了。」
> 根因不是那句話的內容（`reviewer-brief.md` 深井節本來就是這樣寫的），而是**判準原本靠主 agent 自行摘要轉述**（舊 SKILL.md 只寫「下方的審查指引」）→ 必然漂移 → 只好即興重造，且重造成隨輪次放寬的形式。修法：判準抽成 `references/reviewer-brief.md`，主 agent 交路徑不轉述。

```json
{
  "skills": ["deep-review"],
  "query": "/deep-review",
  "setup": "同 F18 的沙盒 d3（起點即 Round 3，接近上限的放行誘因已存在）",
  "expected_behavior": [
    "交給 subagent 的 prompt 含 ~/.claude/skills/deep-review/references/reviewer-brief.md 路徑，並要求先 Read 完再評分；不把判準內容摘要/改寫後貼進 prompt",
    "prompt 不含輪次上限或剩餘輪數（可傳「這是 Round 3」，不可傳「R5 是最後一輪」）",
    "prompt 不含任何後期輪次的放寬指示（「只剩措辭請判通過」「門檻是照做會不會出錯」等）",
    "README stale 事實錯誤仍判 blocking——不因『已是 Round 3、該收斂了』降級",
    "措辭 nits 判 non-blocking 的理由引深井條款，而不是輪次已高",
    "subagent 不可用而降級時，主 agent 仍照 reviewer-brief.md 判準審，並標註 confirmation bias 警語"
  ]
}
```

---

## 評分與迭代

- 每個 case 對 `expected_behavior` 逐條 pass/fail，記錄失敗模式
- 觀察 Claude 實際導航：是否漏讀 references、是否跳步、description 是否誤觸發
- 失敗 → 回到 SKILL.md 強化對應指令（置頂、強語氣、或補 reference），再重跑

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | d2/F12 | RED（代選全庫）→ 補 Step 1 硬約束 → GREEN；Sonnet 原即 PASS |
| 2026-07-05 | Sonnet | d1（F9+F8，Step 0/1/2 腳本化 + diff 改傳 range 後） | PASS——branch-first（main 未動）、squash base 錨定進入時 HEAD（= 腳本 hash-HEAD）、單一語意 commit、未 push。**觀察 miss**：squash commit 未附 Co-Authored-By trailer → 已把 trailer 要求補進 checklist 行 |
| 2026-07-05 | Sonnet | d2（F12，同上改動後） | PASS——priority 4 偵測、拒絕代選（含「使用者離線不構成授權」）、列三選項 STOP、未委派 subagent；tool calls 4 |
| 2026-07-06 | Fable | F13 實戰 RED（relparty-demo autocodex，broker 兩度殭屍） | RED 逐字記錄 → 補 SKILL.md「Codex runtime 死亡偵測與救援」節；resume 救援路徑實證有效（完整救回 C1 報告＋C2 沿 session 增量驗收通過）。GREEN 重測待下次 autocodex 實跑 |
| 2026-07-09 | Opus | F14 病根定位（proxy-pool-vpc，bun→brew split-brain 為 F13 死亡的上游根因） | 收孤兒 bun-era runtime + 清 stale broker.json → 補 `scripts/codex-runtime-hygiene.sh`（check/clean，shellcheck 通過、stale broker.json 自測 RED→GREEN）→ 掛進 SKILL.md Codex 節 preflight；煙霧測試 codex:rescue 完整回報告（job=done、broker v1.0.6+brew 健康）。GREEN 重測待下次 autocodex 實跑 |
| 2026-07-09 | Fable | F14 腳本 deep-review R1（對照 plugin v1.0.6 原始碼實測） | 未通過（1 嚴重 6 中等）→ 修復：dot-glob 漏 state 目錄（誤殺現役）改 find、GNU stat 順序修正、無 jq 三態保守跳過、SIGKILL 補殺子進程改 TERM 前快照、check/clean exit 契約明確化（skip=3）、SKILL.md 刪「穩定可略」句 |
| 2026-07-09 | Fable | F14 腳本 deep-review R2→R3 | R2 未通過（嚴重：`.jobs[-1]` 讀到**最舊** job——plugin jobs 陣列新的在前（unshift），現役 broker 誤判可清、防護形同虛設）→ TDD 修復：tests/run.sh 第 12 節行為測試（S1 迴歸先 RED 後 GREEN、e2e SKIP/收割/exit 契約），改掃任一 status ∈ {queued, running}、SIGKILL 前 argv 重驗 → 全套 PASS=114 → R3 通過（零 blocking）。教訓：活性判準要對照 plugin 原始碼驗，不能照文件措辭抄 |
| 2026-07-20 | Fable | F15 根因終結（F13/F14 的上游）——plugin 等待端無 watchdog | 讀 plugin v1.0.6 原始碼定位：`captureTurn` 只 await「僅由 broker 轉發 `turn/completed` 才 resolve」的 promise，無 timeout/輪詢、`handleExit` 也不 reject 它 → 通知一斷即永久靜默等待；而 broker→app-server 為 detached，照跑完並落檔到 sessions。斷線源不只 split-brain（SessionEnd hook 殺共享 broker、broker busy 時 `withAppServer` 另開 app-server、前景 rescue 撞 Bash 10 分上限）→ **傳輸層整條換掉**：新增 `scripts/codex-exec-review.sh`（headless `codex exec`，完成訊號＝進程退出＋報告落檔），死亡偵測啟發式退役為 exit 契約（0/4/5/2）。tests/run.sh 第 17/18 節，全套 PASS=192；開發中被新測試逮到 job 目錄以時間戳命名會在同秒碰撞、把上輪報告當本輪產出（改 mktemp）。附帶修 `~/.codex/skills/repo-review` 停在 3/21 舊版（未 symlink）→ 新增 `scripts/ensure-codex-skills.sh` 掛進 dotsync 散佈。同日實戰 GREEN：C1/C2/C3 三輪走 exec 路徑皆一次成功（真實 `--json` 首事件帶 `thread_id`、背景回叫如預期、無卡死），C1 抓 5 條、C2 抓 3 條 true positive 全數修復、C3 零 findings 通過。**exit 4 救援階梯未被真實觸發**（三輪都成功），F15 子情境 (b) 仍待實戰 |
| 2026-07-21 | Sonnet | d1+d2 改前 baseline（body 401 行現狀，密度收斂前置） | 雙 PASS——d1：branch-first（main 未動）、squash 錨定進入時 HEAD、單一語意 commit 附 Co-Authored-By trailer、未 push；d2：priority 4 列三選項 STOP、「使用者離線/快速看」不構成代選。皆以沙盒 git 狀態評分 |
| 2026-07-21 | Sonnet | d1+d2 改後驗收（抽 `references/codex-protocol.md`，body 401→374 行） | 雙 PASS（同判準，沙盒 git 實查）——行為保持不變的重構成立；機制層（preflight exit 語意、prompt 限制、exit 契約、救援階梯）移 protocol 檔，硬約束整塊英文留 body；tests/run.sh 233 全綠 |
| 2026-08-04 | Sonnet | d3（F18+F19，新增；判準下沉 `reviewer-brief.md` 後首驗） | **雙 PASS**。F19 6/6：交給 subagent 的 prompt 給 brief 路徑並要求「先讀完整份再評分，不要用你自己的預設標準」、不摘要判準內容、傳「Round 3」但**未洩漏上限**、零放寬指示（反而自加「不要把這當成快通過了的訊號，bar 不因輪次放寬」＝硬約束生效的旁證）、README stale 判 blocking 未因輪次降級、措辭 nits 判 non-blocking 理由引深井條款。F18 4/5→PASS：主動 `rg` 掃全 repo 並註明「唯一定義處、無其他同型」、拒絕逐輪擠牙膏（判黑名單反模式為根因、要求 allowlist 重寫），未列 GROUP BY/LIMIT 該條係 **eval 判準寫成答案導向**，已改行為導向並留回退註記（見 F18 上方）。**評分限制**：受測 prompt 要求它逐字貼出 subagent prompt 才能評 F19，存在觀察者效應，該項 GREEN 偏樂觀 |
| 2026-08-04 | Sonnet | d1 重構回歸（判準搬出 SKILL.md 後行為是否不變） | **PASS**（沙盒 git 實查，不採自述）：`main` 與 `origin/main` 同 hash（未動）、feature branch `feat/paid-in-full-check` 單一 commit、**squash commit 的 parent == 錨點 `2ff6259`**、Co-Authored-By trailer 齊、`.git/deep-review/` 已清空、tree clean、未 push。R1 抓浮點 `==`、R2 抓 `>=` 溢繳語意、R3 通過，tests-baseline=skip 照契約直接 commit |
| 2026-07-21 | Sonnet | d1+d2 錨點/gate 腳本化後驗收（同批新增 F16/F17；prose 下沉 `review-anchor.sh`/`verify-tests.sh`/review-state 增量） | 雙 PASS（沙盒 git 實查）——d1 全程走新腳本：branch-first 依 `branch-first:` verdict 開 feat branch（main 未動）、record 錨點=進入時 HEAD、`verify-tests.sh` PASS 才 commit、squash 照 `squash-cmd` reset 到錨點（squash commit 的 parent==錨點實證）、squash 後 `clear`（anchor 檔已刪）、trailer 齊、未 push；d2 priority 4 照抄腳本 `empty-tree:` 行、列三選項 STOP、「快速看/離線」不構成代選。tests/run.sh 294 全綠。F16 (b)(c) 子情境（stale STOP、codex 冪等）由 tests/run.sh 第 19 節行為測試釘死，實戰 GREEN 待下次 autocodex 實跑 |
