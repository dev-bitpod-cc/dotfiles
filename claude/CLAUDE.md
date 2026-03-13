# 環境配置

## 可用工具

bun, node, uv, eza, bat, fd, rg, fzf, zoxide, jq, yq, delta, lazygit, dust, duf, gh, httpie, shellcheck, sd, hyperfine, tokei, tldr, tmux

## 別名

- 檔案：`ll`, `la`, `lt`, `llt`（eza）
- Git：`gs`, `gd`, `ga`, `gc`, `gp`, `gl`, `gco`, `gb`, `glog`
- 更新：`brewup` (macOS) / `sysup` (Linux) - 含 dotfiles pull

## 自訂函數

- `fe` - fzf 搜尋並編輯檔案
- `proj` - 快速切換專案目錄
- `stats` - 程式碼統計（tokei）
- `venv [name]` - 建立 Python 虛擬環境（優先使用 uv）
- `sysupdate` - 詳細的系統更新（僅 Linux）

## 套件管理規則

1. **JavaScript/TypeScript**：一律用 `bun`，取代 `npm`/`npx`/`node`
   - 新專案：`bun init`｜安裝：`bun add`｜執行：`bun run`｜測試：`bun test`｜全域：`bun install -g`
2. **Python**：一律用 `uv`，取代 `pip`/`python`/`venv`
   - 新專案：`uv init`｜安裝：`uv add`｜執行：`uv run`｜測試：`uv run pytest`｜venv：`uv venv`｜CLI：`uv tool install`

## Commit 慣例

Conventional Commits：`<type>: <簡短描述>`，type: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

## Notification Center (NC) 整合規範

NC 是統一的 Telegram 通知服務（db01:8100）。**所有背景、排程、長時間運行的程序都必須整合。**
完整 API 文件：`~/Projects/notification-center/INTEGRATION.md`

### 何時整合

| 程序類型 | 通知 | 進度 | 說明 |
|----------|------|------|------|
| Cron 排程 | 必須 | — | 完成/失敗都要通知 |
| 背景腳本（爬蟲、回補） | 必須 | 必須 | 長時間任務需進度追蹤 |
| Pipeline（標註、訓練） | 必須 | 必須 | 每個 phase 回報進度 |
| 一次性手動腳本 | 建議 | — | 超過 10 分鐘的建議加 |
| API 服務 | — | — | 不需要 |

### 通知規則

三級制：`info`（正常完成）/ `warning`（非致命異常）/ `error`（失敗、需立即處理）

訊息格式：`{動作結果}: {關鍵數據}`
- 動作結果在前，關鍵數據跟後，一行不超過 200 字
- 不加 emoji（NC 根據 level 自動加）、不重複 source（NC 自動加前綴）

```
# 好
"排程完成 (3m12s)"
"爬蟲完成: 新增 1,200 筆, 更新 350 筆"
# 壞
"✅ mops-major-news 排程完成"     ← emoji 多餘，source 重複
"完成"                            ← 缺數據
```

### 進度追蹤

task 命名：`{功能}-{動作}`，如 `revenue-backfill`、`risk-v12-train`

| 時機 | status | percent | detail |
|------|--------|---------|--------|
| 開始 | running | 0 | `共 N 筆` |
| 進行中 | running | 計算值 | `{i}/{total}` |
| 完成 | completed | 100 | `完成` |
| 失敗 | failed | 當前值 | `錯誤原因` |

- 超過 5 分鐘的任務用 `notify_on` 自動推播（見 INTEGRATION.md）
- Cron/重試場景用 `dedup_key` 去重（見 INTEGRATION.md）

### 環境變數與原則

```bash
NC_API_URL=http://localhost:8100
NC_API_KEY=nc_xxxxx                # POST /api/v1/keys 產生
```

**靜默失敗**：NC 不可用時不能影響主流程，所有 NC 呼叫必須 try/except 靜默處理。

## 程式碼慣例

### 命名

- **Python**：變數與函式 `snake_case`，類別 `PascalCase`，常數 `UPPER_SNAKE`
- **TypeScript**：變數與函式 `camelCase`，類別與型別 `PascalCase`，常數 `UPPER_SNAKE`
- **檔案名**：`kebab-case`（如 `setup-mac-env.sh`、`risk-model.py`）

### Error Handling

- 外部服務呼叫一律 try/except（或 try/catch），不讓第三方錯誤 crash 主流程
- 失敗時 log 足夠的 context（什麼操作、什麼輸入、什麼錯誤），不只 `except: pass`
- 可重試的操作（HTTP、DB）考慮加 retry with backoff
- 使用者輸入在邊界驗證，內部函式之間信任參數

### 已知地雷

- SQL 字串拼接 → 一律用參數化查詢
- `datetime.now()` → 注意 timezone，需要 UTC 用 `datetime.now(UTC)`
- float 比較 → 金額、分數不要用 `==` 比較浮點數
- 大量資料迴圈內呼叫 API/DB → 改用批次操作

### 測試

- **何時需要測試**：新增業務邏輯、修 bug（先寫重現測試再修）、公開 API/函式
- **不需要測試**：設定檔、純 glue code、一次性腳本
- **檔案位置**：與原始碼同目錄或 `tests/` 目錄，依專案既有慣例
- **命名**：Python `test_*.py`，TypeScript `*.test.ts`
- **原則**：測行為不測實作、mock 外部依賴但不 mock 被測邏輯本身、每個 test case 只驗證一件事

## 跨 Repo 工作流

同一 session 經常涉及多個相關 repo（如產品 + 部署）。

### 原則

- 主 agent 是唯一擁有跨 repo 全局 context 的角色
- 觸發 skill（`/deep-review`、`/uap`）時，主 agent 根據 session 記憶列出涉及的 repo 清單，讓使用者確認後再開始
- 使用者可確認（ok）、限縮（只看 X）、擴充（還有 Y）
- 不掃描 `~/Projects/`——靠主 agent 記憶 + 使用者確認，快速且精確

### 確認流程（適用所有跨 repo skill）

```
主 agent: "本次涉及 2 個 repo：
  1. rag-platform（3 檔案變更）
  2. rag-platform-deploy（5 檔案變更）
  一起處理？或需要調整？"

使用者回覆：
  "ok"          → 開始
  "只看 deploy" → 限縮
  "還有 repo-X" → 擴充
```

### 注意

- 若 context 被壓縮導致記憶不完整，以當前 pwd 的 repo 為底，讓使用者補充
- 使用者指定的 repo 即使沒有 diff，也納入處理（可能是需要檢查一致性）

## 安全規則

1. 不要寫死 secrets、API keys、密碼
2. 使用環境變數或 `.env` 檔案管理機密
3. 不要 commit `.env`、`*.pem`、`*.key`、`credentials.json`
4. 建立新專案時確保 `.gitignore` 包含敏感檔案

## Claude Skill 建立

- 建立或修改 skill 前，**必須先讀** `~/.dotfiles/claude/skill-building-guide.md`（Anthropic 官方指南摘要，2026/03 公開，超出模型知識截止日）
- 可搭配 `/skill-creator` plugin 加速建立和迭代
- 現有 skill 位於 `~/.dotfiles/claude/skills/`

## 第三方審查驗證

使用者貼「第三方審查結果」+ findings 時，逐條讀原始碼獨立驗證，不附和。對每條判定 true positive / false positive / context-dependent。不預設 findings 正確，不預設錯誤。使用者不會告訴你來源或自己的看法，你也不要問。

## 注意

1. 原生命令未被替換（ls, cat, find, grep 可用）
2. 不要假設單字母別名
3. Linux: `fd`/`bat` 是別名（實際為 fdfind/batcat）
4. PATH 包含 `~/.local/bin`
