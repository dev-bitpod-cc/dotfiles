# Deep Review — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**（避免 runtime 被載入）。
> 依 Anthropic「Build evaluations first」方法論：先量無 skill 的 baseline，再對照有 skill 的表現。
> 目前無內建 runner，手動執行：在乾淨 session 載入 skill → 跑 query → 對照 `expected_behavior` 打分。
> **三模型都要測**（Haiku / Sonnet / Opus）：Haiku 看指引夠不夠、Opus 看有沒有過度解釋。

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
    "diff 模式：commit range base 端錨在審查起點 hash，每輪沿用 <起點>..HEAD，不退化成 HEAD~1..HEAD"
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

---

## 評分與迭代

- 每個 case 對 `expected_behavior` 逐條 pass/fail，記錄失敗模式
- 觀察 Claude 實際導航：是否漏讀 references、是否跳步、description 是否誤觸發
- 失敗 → 回到 SKILL.md 強化對應指令（置頂、強語氣、或補 reference），再重跑
