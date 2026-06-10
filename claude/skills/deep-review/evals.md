# Deep Review — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**（避免 runtime 被載入）。
> 依 Anthropic「Build evaluations first」方法論：先量無 skill 的 baseline，再對照有 skill 的表現。
> 目前無內建 runner，手動執行：在乾淨 session 載入 skill → 跑 query → 對照 `expected_behavior` 打分。
> **三模型都要測**（Haiku / Sonnet / Opus）：Haiku 看指引夠不夠、Opus 看有沒有過度解釋。

---

## 這份 evals 是 skill 的收斂判準（oracle）

判斷這兩個 skill「對不對 / 改好了沒」**以通過這份 evals（+ uap 的 `pressure-tests.md`）為準**，**不以「再對 SKILL.md 跑一次 `/deep-review` 找不找得到東西」為準**。

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
    "對該 repo 呼叫 codex:rescue，prompt 嚴格一行：Run your repo-review skill on <repo_path> for <commit_range>. 繁體中文.",
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
    "codex:rescue 的 repo_path = repo root（非子目錄），range 依 baseline 規則",
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

---

## 評分與迭代

- 每個 case 對 `expected_behavior` 逐條 pass/fail，記錄失敗模式
- 觀察 Claude 實際導航：是否漏讀 references、是否跳步、description 是否誤觸發
- 失敗 → 回到 SKILL.md 強化對應指令（置頂、強語氣、或補 reference），再重跑
