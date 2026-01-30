# 環境配置

此環境已安裝現代化 CLI 工具，可直接使用。

## 可用工具

bun, node, uv, eza, bat, fd, rg, fzf, zoxide, jq, yq, delta, lazygit, dust, duf, gh, httpie

## 別名

- 檔案：`ll`, `la`, `lt`（eza）
- Git：`gs`, `gd`, `ga`, `gc`, `gp`, `gl`, `gco`, `gb`
- 更新：`brewup` (macOS) / `sysup` (Linux) - 含 dotfiles pull

## 注意

1. 原生命令未被替換（ls, cat, find, grep 可用）
2. 不要假設單字母別名
3. Linux: `fd`/`bat` 是別名（實際為 fdfind/batcat）
4. PATH 包含 `~/.local/bin`
5. 永遠使用 `bun` 取代 `npm`/`npx`/`node`，包括安裝、執行、測試
6. Python 相關操作一律使用 `uv`，取代 `pip`/`python`/`venv`
