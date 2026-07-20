# Behavior Rules（行為規則）

> Hard constraints. Violations have real consequences.

## Think Before Implementing

- Ambiguous task: NEVER silently pick one reading. List the plausible interpretations and let the user choose before writing anything.
- Non-trivial task: state the success criteria (how "done" is verified) before starting; if the repo has a STATUS.md (dossier), record the spec (Context/Goal/AC/Constraints) into its「進行中」section（儀式面用 `/project spec`）.
- 工作過程中做出**關鍵取捨／放棄一條路（死路）／踩到非顯而易見的坑**時，若 repo 有 STATUS.md → **當下**就地寫入對應章節（working tree 即可、不 commit，收尾由 `/project log` 一起送出）。Do NOT defer dossier notes to ship time — context may be compacted before then.
- Uncertain? Stop and ask. Do NOT assume just to keep momentum.
- Bug fix: ALWAYS write a reproducing test FIRST, then fix.

## PR / Git

- **NEVER merge on your own** — only when the user explicitly says merge / bypass merge. "push" or "open a PR" alone does NOT include merge.
- 使用者明說 merge 後的標準收尾：merge PR（預設 squash）→ 清 remote/本地 branch → 同步本地 default（序列見 `~/.dotfiles/claude/skills/project/references/ship-paths.md`「Merge 最後一哩」）。
- **NEVER push on your own** — after finishing an issue implementation or review fixes, commit and STOP; wait for the user's next instruction.
- Conventional Commits: `<type>: <short desc>`. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.

## Third-party Review Verification

When the user pastes third-party review findings, read the source code and verify each finding independently — do not just agree. Judge each as true positive / false positive / context-dependent. Assume neither correct nor wrong by default. The user won't reveal the source or their own opinion, and you should not ask.

### 觸發詞「由 codex 進行第三方審查」（變體：「交給 codex 審查」「codex 第三方」）

載入 `deep-review` skill，依其「**Codex 呼叫協議**」節以背景 Bash 執行 `codex-exec-review.sh run`（一行 prompt 由腳本固定、禁加 focus/測試/context——以該節為唯一權威，勿憑記憶重組 prompt；**不要**呼叫 `codex:rescue`，那條 plugin broker 路徑會靜默卡死）。失敗處理照該 skill 的 exit 契約（0 讀報告／4 resume 一次／5 停）。本觸發的專屬規則：

- repo 路徑 + commit range 取最近一次 `/deep-review` 輸出的「第三方審查資訊」區塊，range 直接沿用其 `base..head`（base 已錨定）；即使變更已 push（`origin/main..HEAD` 為空）也**不要**退化成 `HEAD~1..HEAD`——那會漏審變更集前段。只有報告未記錄 base 時，才回退用 `HEAD~1..HEAD`。
- 收到 findings 後的處理判準：**最近一次 `/deep-review` 帶 `autofix`** → 驗證後自動修復並 commit；否則、或無法確定當時是否帶 autofix（如新 session）→ 列出 findings 等使用者決定。

## Security

- NEVER hardcode secrets, API keys, or passwords.
- Manage secrets via environment variables or a `.env` file.
- NEVER commit `.env`, `*.pem`, `*.key`, `credentials.json`.
- New project: ensure `.gitignore` covers sensitive files.

---

# Code Conventions（程式碼慣例）

## Naming

- **Python**: vars/functions `snake_case`, classes `PascalCase`, constants `UPPER_SNAKE`
- **TypeScript**: vars/functions `camelCase`, classes/types `PascalCase`, constants `UPPER_SNAKE`
- **Filenames**: `kebab-case`（如 `setup-mac-env.sh`）；例外：**Python 可 import 的模組/套件檔一律 `snake_case`**（如 `risk_model.py`——kebab-case 無法 import），僅獨立執行腳本可 kebab-case

## Error Handling

- 外部服務呼叫一律 try/except（或 try/catch），不讓第三方錯誤 crash 主流程
- 失敗時 log 足夠的 context（什麼操作、什麼輸入、什麼錯誤），不只 `except: pass`
- 可重試的操作（HTTP、DB）考慮加 retry with backoff
- 使用者輸入在邊界驗證，內部函式之間信任參數

## 已知地雷

- SQL 字串拼接 → 一律用參數化查詢
- `datetime.now()` → 注意 timezone，需要 UTC 用 `datetime.now(UTC)`
- float 比較 → 金額、分數不要用 `==` 比較浮點數
- 大量資料迴圈內呼叫 API/DB → 改用批次操作
- **shell 訊息裡 `$var` 緊接全形標點** → bash 會把全形字元併入變數名（`"（exit=$rc）"` → `set -u` 下噴 `rc）: unbound variable`）。繁中訊息幾乎必踩，且**只在錯誤路徑觸發**、正常測試照樣全綠。一律寫 `${var}`。（dotfiles 有 `tests/run.sh` 第 1b 節 gate 擋，其他 repo 沒有）
- **`sd` 的替換字串含 shell 變數** → `$job` 會被當成 capture group 展開為空，靜默毀損程式碼且過得了 `bash -n` 與 shellcheck。含 `$` 的替換改用 Edit 或 python 字面替換

## 測試

- **何時需要**：新增業務邏輯、修 bug（先寫重現測試再修）、公開 API/函式
- **不需要**：設定檔、純 glue code、一次性腳本
- **檔案位置**：與原始碼同目錄或 `tests/`，依專案既有慣例
- **命名**：Python `test_*.py`，TypeScript `*.test.ts`
- **原則**：測行為不測實作、mock 外部依賴但不 mock 被測邏輯本身、每個 test case 只驗證一件事

---

# Workflow（工作流）

## Package Management

- **JavaScript/TypeScript**: ALWAYS use `bun` (replaces `npm`/`npx`/`node`). init `bun init`｜add `bun add`｜run `bun run`｜test `bun test`｜global `bun install -g`
- **Python**: ALWAYS use `uv` (replaces `pip`/`python`/`venv`). init `uv init`｜add `uv add`｜run `uv run`｜test `uv run pytest`｜venv `uv venv`｜CLI `uv tool install`

## 跨 Repo 工作流

主 agent 是唯一擁有跨 repo 全局 context 的角色。觸發跨 repo skill（`/deep-review`、`/project log`）時，依 session 記憶列出 `(repo, 檔案數)` 清單讓使用者確認（ok / 只看 X / 還有 Y），**不掃描** `~/Projects/`。確認流程細節見各 skill 的 Step 0。context 被壓縮就以 pwd 的 repo 為底讓使用者補充；使用者指定的 repo 即使無 diff 也納入（檢查一致性）。

## 跨主機工作流（多主機開發；主機清單見 `~/.dotfiles/scripts/inventory.conf`，勿在此硬編清單——會漂移）

- **Git is the ONLY cross-host medium.** Machine-local state（`~/.claude/handoffs/`、memory/）does NOT travel between hosts.
- 跨主機要延續的工作狀態 → repo 的 `STATUS.md`「進行中」章節就地更新 + commit（WIP 走 feature branch）；push 由使用者確認——**未 push 其他主機不可見，須主動標示**。handoff 只服務同主機 /clear。
- 多主機共用的專案，project-type 事實優先寫 repo 檔案（CLAUDE.md/STATUS.md）而非 ~/.claude memory（memory 留給 user/feedback 型）。
- 開工前的 clone 落後偵測由 SessionStart hook（`session-pull-check.sh`）自動報；看到落後提醒先 pull。

## Skill 建立

- 建立或修改 skill 前，**必須先讀** `~/.dotfiles/claude/skill-building-guide.md`（含 Anthropic 官方 best-practices、TDD-for-skills 紀律測試、定向英文語言政策）
- 可搭配 `/skill-creator` plugin；現有 skill 位於 `~/.dotfiles/claude/skills/`

---

# 技能載入指標（Skill Pointers）

特定情境下，相關 SOP 已抽成 skill 按需載入。遇以下情境**主動載入對應 skill**（避免 silent miss）：

- 寫 **cron / 背景腳本（爬蟲/回補）/ pipeline** 的開始·完成·失敗 → `nc-notify`（必發通知；NC 不可用須靜默不影響主流程）
- 使用者要求**「寄信 / mail 給我」** → `send-mail`（收件人預設 `jjshen@eland.com.tw`，勿用 `# userEmail` 推斷）
- 遇 **bug / 測試失敗 / 非預期行為** → `root-cause-first`（先 root cause 再修）
- 使用者要 **/clear 但後續工作延續**（「交接」「接續上次的工作」）→ `handoff`（resume 必先 verify 錨點；消費即歸檔；**同主機限定**——跨主機延續走 repo STATUS.md）
- 使用者要**移交專案給同事 / 換 owner**（「移交」「交接給同事」「請他接手」）→ **建議使用者執行** `/project transfer`（user-invoked only——該 skill 為 `disable-model-invocation`，勿嘗試以 Skill tool 載入；其 dossier 完整度檢查 + 移交指南、credentials 絕不進 git）
- 使用者說**「uap」「ship」「推上去」「提交送 PR」**（收尾送出語意）→ **建議使用者執行** `/project log`（user-invoked only，同上勿以 Skill tool 載入；裸 `/project` 亦可，預設即 log 模式）

---

# 撰寫語言政策（Language Policy）

> Meta-rule：編輯本檔或任何 skill 時一律遵循。完整版見 `skill-building-guide.md`。

- 硬約束 / 否定句 / 紀律強制塊（Iron Law、rationalization table、red flags）→ **英文**
- 程序步驟 / 領域 SOP / 概念解說 → **繁中**
- 觸發詞 / description → **中英關鍵字並列**
- 面向使用者的輸出 → **繁中**

---

# 環境配置

## 可用工具

bun, node, uv, eza, bat, fd, rg, fzf, zoxide, jq, yq, delta, lazygit, dust, gh, httpie, shellcheck, sd, hyperfine, tokei, tldr, tmux, direnv, just, watchexec

## 工具安裝原則

需要 CLI 工具時，先 `command -v <tool>` 檢查，沒有就 `brew install`，直接使用。不要因為工具不在就繞路。僅限標準 CLI 工具，專案依賴走 uv/bun 管理。
