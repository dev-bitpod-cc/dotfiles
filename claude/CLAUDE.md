# 環境配置

此環境已安裝現代化 CLI 工具，可直接使用。

## 可用工具

bun, node, uv, eza, bat, fd, rg, fzf, zoxide, jq, yq, delta, lazygit, dust, duf, gh, httpie, shellcheck

## 別名

- 檔案：`ll`, `la`, `lt`（eza）
- Git：`gs`, `gd`, `ga`, `gc`, `gp`, `gl`, `gco`, `gb`
- 更新：`brewup` (macOS) / `sysup` (Linux) - 含 dotfiles pull

## 套件管理規則

1. **JavaScript/TypeScript**：一律用 `bun`，取代 `npm`/`npx`/`node`
   - 新專案：`bun init`
   - 安裝套件：`bun add`
   - 執行：`bun run`
   - 測試：`bun test`
   - 全域工具：`bun install -g`
2. **Python**：一律用 `uv`，取代 `pip`/`python`/`venv`
   - 新專案：`uv init`
   - 安裝套件：`uv add`
   - 執行：`uv run`
   - 測試：`uv run pytest`
   - 虛擬環境：`uv venv`
   - CLI 工具：`uv tool install`

## Commit 慣例

使用 Conventional Commits 格式：

```
<type>: <簡短描述>
```

type: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

## Notification Center (NC) 整合規範

NC 是統一的 Telegram 通知服務，部署在 db01:8100。
**所有背景、排程、長時間運行的程序都必須整合 NC。**

完整 API 文件：`~/Projects/notification-center/INTEGRATION.md`

### 何時必須整合

| 程序類型 | 通知 | 進度 | 說明 |
|----------|------|------|------|
| Cron 排程 | 必須 | — | 完成/失敗都要通知 |
| 背景腳本（爬蟲、回補） | 必須 | 必須 | 長時間任務需進度追蹤 |
| Pipeline（標註、訓練） | 必須 | 必須 | 每個 phase 回報進度 |
| 一次性手動腳本 | 建議 | — | 超過 10 分鐘的建議加 |
| API 服務 | — | — | 不需要（本身就是常駐服務） |

### 通知 level 規則

三級制：`info` / `warning` / `error`（無 success）

| level | 使用場景 | 範例 |
|-------|---------|------|
| `info` | 正常完成、啟動、階段完成 | `任務完成 (3m12s)` |
| `warning` | 非致命異常、需注意 | `未達標，需人工介入` |
| `error` | 失敗、中止、需立即處理 | `爬蟲異常中止: ConnectionError` |

### 通知訊息格式

```
{動作結果}: {關鍵數據}
```

規則：
1. **動作結果**在前 — 「完成」「失敗」「啟動」一眼可辨
2. **關鍵數據**跟後 — 數量、耗時、錯誤原因
3. 不加 emoji（NC 會根據 level 自動加）
4. 不重複 source（NC 會自動加 `[source]` 前綴）
5. 保持一行，不超過 200 字

範例：

```
# 好
"排程完成 (3m12s)"
"爬蟲完成: 新增 1,200 筆, 更新 350 筆"
"標註完成: 4,500 筆 (alert=320, watch=890, routine=3290)"
"IP block 偵測: net::ERR_EMPTY_RESPONSE"
"訓練未達標 (acc=82.1%), 需人工介入"

# 不好
"✅ mops-major-news 排程完成"     ← emoji 多餘，source 重複
"完成"                            ← 缺數據
"Error occurred in the system"     ← 太模糊
```

### 進度追蹤規則

task 命名：`{功能}-{動作}`，如 `revenue-backfill`、`risk-v12-train`

| 時機 | status | percent | detail |
|------|--------|---------|--------|
| 開始 | running | 0 | `共 N 筆` 或 `共 N 個 batch` |
| 進行中 | running | 計算值 | `{i}/{total}, 已處理 X 筆` |
| 完成 | completed | 100 | `完成` |
| 失敗 | failed | 當前值 | `錯誤原因` |
| 中斷 | failed | 當前值 | `使用者中斷` |

### notify_on 自動推播

超過 5 分鐘的背景任務建議設定 `notify_on`，免去手動送 /notify：

```python
report_progress(
    task="model-training-v12", percent=0, source="krepo",
    notify_on=["completed", "failed"], recipient="jjshen",
    timeout_minutes=120,
)
```

### dedup_key 去重

Cron 排程或可能重試的場景，用 dedup_key 避免重複通知：

```python
send_notify("排程完成", source="mops-daily",
            dedup_key=f"mops-daily-{date.today()}")
```

### 環境變數

所有專案統一使用：

```bash
NC_API_URL=http://localhost:8100   # NC 服務位址
NC_API_KEY=nc_xxxxx                # API key（由 POST /api/v1/keys 產生）
```

### 靜默失敗原則

NC 不可用時**不能**影響主流程。所有 NC 呼叫都必須 try/except 靜默處理。

## 安全規則

1. 不要寫死 secrets、API keys、密碼
2. 使用環境變數或 `.env` 檔案管理機密
3. 不要 commit `.env`、`*.pem`、`*.key`、`credentials.json`
4. 建立新專案時確保 `.gitignore` 包含敏感檔案

## 注意

1. 原生命令未被替換（ls, cat, find, grep 可用）
2. 不要假設單字母別名
3. Linux: `fd`/`bat` 是別名（實際為 fdfind/batcat）
4. PATH 包含 `~/.local/bin`
