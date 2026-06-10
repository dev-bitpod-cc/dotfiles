# Behavior Rules（行為規則）

> Hard constraints. Violations have real consequences.

## Think Before Implementing

- Ambiguous task: NEVER silently pick one reading. List the plausible interpretations and let the user choose before writing anything.
- Non-trivial task: state the success criteria (how "done" is verified) before starting.
- Uncertain? Stop and ask. Do NOT assume just to keep momentum.
- Bug fix: ALWAYS write a reproducing test FIRST, then fix. → load `root-cause-first` skill (find root cause before fixing).

## PR / Git

- **NEVER merge on your own** — only when the user explicitly says merge / bypass merge. "push" or "open a PR" alone does NOT include merge.
- **NEVER push on your own** — after finishing an issue implementation or review fixes, commit and STOP; wait for the user's next instruction.
- Conventional Commits: `<type>: <short desc>`. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.

## Third-party Review Verification

When the user pastes third-party review findings, read the source code and verify each finding independently — do not just agree. Judge each as true positive / false positive / context-dependent. Assume neither correct nor wrong by default. The user won't reveal the source or their own opinion, and you should not ask.

### 觸發詞「由 codex 進行第三方審查」（變體：「交給 codex 審查」「codex 第三方」）

取最近一次 `/deep-review` 輸出「第三方審查資訊」區塊的 repo 路徑 + commit range，依 `deep-review` skill 的 Codex 呼叫協議執行：呼叫 `codex:rescue`，**prompt 只含一行** `Run your repo-review skill on <repo_path> for <commit_range>. 繁體中文.`。**絕對不要**：自訂 focus、要求跑測試、加 context files、加 subagent/平行化指示、傳慣例文件（codex repo-review 有自己的 workflow，會自行切 scope/開 subagent，多寫只會干擾、拖長時間）。收到 findings 後依當前模式處理（autofix → 自動修復 commit；否則列出等使用者決定）。
注意：commit range 直接沿用報告「第三方審查資訊」記錄的 `base..head`（base 已錨定）；即使該變更已 push（`origin/main..HEAD` 為空）也**不要**退化成 `HEAD~1..HEAD`——那會漏審變更集前段。只有報告未記錄 base 時，才回退用 `HEAD~1..HEAD`。

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
- **Filenames**: `kebab-case`（如 `setup-mac-env.sh`、`risk-model.py`）

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
- 遇 bug / 測試失敗 / 非預期行為 → 先 root cause 再修（`root-cause-first` skill）

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

主 agent 是唯一擁有跨 repo 全局 context 的角色。觸發跨 repo skill（`/deep-review`、`/uap`）時，依 session 記憶列出 `(repo, 檔案數)` 清單讓使用者確認（ok / 只看 X / 還有 Y），**不掃描** `~/Projects/`。確認流程細節見各 skill 的 Step 0。context 被壓縮就以 pwd 的 repo 為底讓使用者補充；使用者指定的 repo 即使無 diff 也納入（檢查一致性）。

## Skill 建立

- 建立或修改 skill 前，**必須先讀** `~/.dotfiles/claude/skill-building-guide.md`（含 Anthropic 官方 best-practices、TDD-for-skills 紀律測試、定向英文語言政策）
- 可搭配 `/skill-creator` plugin；現有 skill 位於 `~/.dotfiles/claude/skills/`

---

# 技能載入指標（Skill Pointers）

特定情境下，相關 SOP 已抽成 skill 按需載入。遇以下情境**主動載入對應 skill**（避免 silent miss）：

- 寫 **cron / 背景腳本（爬蟲/回補）/ pipeline** 的開始·完成·失敗 → `nc-notify`（必發通知；NC 不可用須靜默不影響主流程）
- 使用者要求**「寄信 / mail 給我」** → `send-mail`（收件人預設 `jjshen@eland.com.tw`，勿用 `# userEmail` 推斷）
- 遇 **bug / 測試失敗 / 非預期行為** → `root-cause-first`（先 root cause 再修）

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
