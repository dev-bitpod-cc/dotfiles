# 環境配置

此環境已安裝現代化 CLI 工具，可直接使用。

## 可用工具

eza, bat, fd, rg, fzf, zoxide, jq, yq, delta, lazygit, dust, duf, gh, httpie

## 別名

- 檔案：`ll`, `la`, `lt`（eza）
- Git：`gs`, `gd`, `ga`, `gc`, `gp`, `gl`, `gco`, `gb`
- 更新：`brewup` (macOS) / `sysup` (Linux) - 含 dotfiles pull

## 注意

1. 原生命令未被替換（ls, cat, find, grep 可用）
2. 不要假設單字母別名
3. Linux: `fd`/`bat` 是別名（實際為 fdfind/batcat）
4. PATH 包含 `~/.local/bin`
