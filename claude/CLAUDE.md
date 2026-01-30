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
