# 行為規則

> 本段為硬性約束，違反會造成實質影響。

## 實作前先 Think

- 歧義任務**不要 silent pick**。多重合理解讀時先列出、讓使用者選，不要自己挑一個就開始寫
- 非 trivial 任務先講 success criteria（「完成」怎麼驗證），再動手
- 不確定就停下來問，不要為了維持推進感而 assume
- Bug fix 一律先寫能重現的 test，再改

## PR 與 Git

- **不可自作主張 merge**——使用者明確說 merge / bypass merge 時才執行。只說「push」或「開 PR」時不要加 merge
- **不可自作主張 push**——完成 issue 實作或 review 修復後，commit 即停，等使用者指示下一步
- Conventional Commits：`<type>: <簡短描述>`，type: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

## 第三方審查驗證

使用者貼「第三方審查結果」+ findings 時，逐條讀原始碼獨立驗證，不附和。對每條判定 true positive / false positive / context-dependent。不預設 findings 正確，不預設錯誤。使用者不會告訴你來源或自己的看法，你也不要問。

### 觸發詞：「由 codex 進行第三方審查」

使用者說這句話時（或變體「交給 codex 審查」、「codex 第三方」），觸發固定流程：

1. 從最近一次 `/deep-review` 輸出的「第三方審查資訊」區塊取出 repo 路徑 + commit range（例如 `HEAD~1..HEAD`、`origin/main..HEAD`、或具體 hash 範圍）
2. 呼叫 `codex:rescue`，**prompt 只含一行**：
   ```
   Run your repo-review skill on <repo_path> for <commit_range>. 繁體中文.
   ```
3. **絕對不要**：寫自訂 focus points、要求跑測試、加 context files、解釋要審什麼、傳專案慣例文件
4. 收到 Codex findings 後依當前模式處理（autofix → 自動修復 commit；否則列出等使用者決定）

**Why**：Codex 的 `repo-review` skill 有自己的 workflow（讀 diff + 必要的周邊 context）。自訂 prompt 會讓它偏離既有流程、嘗試不可用的 sandbox 操作（uv/pytest），拉長審查時間。最精簡的 prompt 才能讓它用最有效率的路徑完成。

**注意**：若「第三方審查資訊」已被 push（`origin/main..HEAD` 為空），改用 `HEAD~1..HEAD`（或前 N 個 commits 的範圍）。

## 安全規則

1. 不要寫死 secrets、API keys、密碼
2. 使用環境變數或 `.env` 檔案管理機密
3. 不要 commit `.env`、`*.pem`、`*.key`、`credentials.json`
4. 建立新專案時確保 `.gitignore` 包含敏感檔案

---

# 程式碼慣例

## 命名

- **Python**：變數與函式 `snake_case`，類別 `PascalCase`，常數 `UPPER_SNAKE`
- **TypeScript**：變數與函式 `camelCase`，類別與型別 `PascalCase`，常數 `UPPER_SNAKE`
- **檔案名**：`kebab-case`（如 `setup-mac-env.sh`、`risk-model.py`）

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

## 測試

- **何時需要測試**：新增業務邏輯、修 bug（先寫重現測試再修）、公開 API/函式
- **不需要測試**：設定檔、純 glue code、一次性腳本
- **檔案位置**：與原始碼同目錄或 `tests/` 目錄，依專案既有慣例
- **命名**：Python `test_*.py`，TypeScript `*.test.ts`
- **原則**：測行為不測實作、mock 外部依賴但不 mock 被測邏輯本身、每個 test case 只驗證一件事

---

# 工作流

## 套件管理

1. **JavaScript/TypeScript**：一律用 `bun`，取代 `npm`/`npx`/`node`
   - 新專案：`bun init`｜安裝：`bun add`｜執行：`bun run`｜測試：`bun test`｜全域：`bun install -g`
2. **Python**：一律用 `uv`，取代 `pip`/`python`/`venv`
   - 新專案：`uv init`｜安裝：`uv add`｜執行：`uv run`｜測試：`uv run pytest`｜venv：`uv venv`｜CLI：`uv tool install`

## 跨 Repo 工作流

同一 session 經常涉及多個相關 repo（如產品 + 部署）。

### 原則

- 主 agent 是唯一擁有跨 repo 全局 context 的角色
- 觸發 skill（`/deep-review`、`/uap`）時，主 agent 根據 session 記憶列出涉及的 repo 清單，讓使用者確認後再開始
- 使用者可確認（ok）、限縮（只看 X）、擴充（還有 Y）
- 不掃描 `~/Projects/`——靠主 agent 記憶 + 使用者確認，快速且精確

### 確認流程（適用所有跨 repo skill）

確認流程：列出 `(repo, 檔案數)` 清單、等使用者確認（ok）/ 限縮（只看 X）/ 擴充（還有 Y）。

### 注意

- 若 context 被壓縮導致記憶不完整，以當前 pwd 的 repo 為底，讓使用者補充
- 使用者指定的 repo 即使沒有 diff，也納入處理（可能是需要檢查一致性）

## Claude Skill 建立

- 建立或修改 skill 前，**必須先讀** `~/.dotfiles/claude/skill-building-guide.md`（Anthropic 官方指南摘要，2026/03 公開，超出模型知識截止日）
- 可搭配 `/skill-creator` plugin 加速建立和迭代
- 現有 skill 位於 `~/.dotfiles/claude/skills/`

---

# Notification Center (NC) 整合規範

NC 是統一的 Telegram 通知服務（db01:8100）。完整 API 文件與範例：`~/Projects/notification-center/INTEGRATION.md` — 細節（status 欄位、notify_on、dedup_key 用法、範例訊息）去那裡查。

**何時必須整合**：cron 排程、背景腳本（爬蟲/回補）、pipeline（標註/訓練）的開始/完成/失敗必發通知；長時間任務（>5 分鐘）加進度追蹤。一次性手動腳本 >10 分鐘建議加。API 服務不需要。

**訊息格式**：`{動作結果}: {關鍵數據}`，動作在前、數據在後、一行 ≤200 字。**不加 emoji**（NC 依 level 自動加）、**不重複 source**（NC 自動加前綴）。三級制：`info`（完成）/ `warning`（非致命異常）/ `error`（需立即處理）。

**進度追蹤**：task 命名 `{功能}-{動作}`（如 `revenue-backfill`、`risk-v12-train`）。

**環境變數**：`NC_API_URL` + `NC_API_KEY`。

**靜默失敗**：NC 不可用不能影響主流程，所有 NC 呼叫必須 try/except 靜默處理。

---

# 環境配置

## 可用工具

bun, node, uv, eza, bat, fd, rg, fzf, zoxide, jq, yq, delta, lazygit, dust, gh, httpie, shellcheck, sd, hyperfine, tokei, tldr, tmux, direnv, just, watchexec

## 工具安裝原則

需要 CLI 工具時，先 `command -v <tool>` 檢查，沒有就 `brew install`，直接使用。不要因為工具不在就繞路。僅限標準 CLI 工具，專案依賴走 uv/bun 管理。
