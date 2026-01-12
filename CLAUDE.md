# Shell 環境配置指引

此環境已透過標準化腳本配置，你可以直接使用以下現代化工具。

## 平台資訊

- **macOS**: zsh（`~/.zshrc`, `~/.zprofile`）
- **Linux Ubuntu**: bash（`~/.bashrc`, `~/.bash_profile`）
- **使用者自訂設定**：`.local` 檔案（不會被腳本覆寫）

## 可用工具

### 優先使用這些現代化工具

| 任務 | 使用 | 取代 |
|------|------|------|
| 列出檔案 | `eza` 或 `ll`/`la`/`lt` | ls |
| 查看檔案 | `bat` | cat |
| 搜尋檔案 | `fd` | find |
| 搜尋內容 | `rg` | grep |
| 目錄跳轉 | `z <keyword>` | cd |
| HTTP 請求 | `http` (HTTPie) | curl |
| JSON 處理 | `jq` | - |
| YAML 處理 | `yq` | - |
| Git diff | `gd` (自動使用 delta) | git diff |
| Git TUI | `lazygit` | - |
| 磁碟分析 | `dust` | du |
| 磁碟使用 | `duf` | df |

### Git 別名

```
gs=git status    gd=git diff    ga=git add    gc=git commit
gp=git push      gl=git pull    gco=git checkout    gb=git branch
glog=git log --oneline --graph --decorate
```

### 系統更新

- macOS: `brewup`
- Linux: `sysup`

### 自訂函數

- `fe` - fzf 搜尋並編輯檔案
- `proj` - 快速切換專案目錄
- `stats` - 程式碼統計 (macOS)
- `venv [name]` - 建立 Python 虛擬環境 (Linux)

## 重要規則

1. **原生命令未被替換**：`ls`, `cat`, `find`, `grep` 仍可正常使用
2. **不要假設單字母別名**：此環境不使用 `l`, `c` 等別名
3. **Linux 注意**：`fd` 和 `bat` 是別名（實際命令為 `fdfind`, `batcat`）
4. **PATH 已包含**：`~/.local/bin`（Claude Code、pip --user 安裝於此）
5. **API Keys**：存放於 `~/.env`（權限 600，會自動載入）

## 開發環境

- **Bun**: `bun`（主要 JS runtime）
- **Node.js**: `node`, `npm`, `npx`（相容性備用）
- **Python**: `python`, `pip`（兩平台都指向 python3）
- **GitHub CLI**: `gh`

## macOS 專屬

- `tokei` / `stats` - 程式碼統計
- `hyperfine` - 效能測試
- `sd` - 搜尋替換
- `swiftlint`, `xcbeautify` - Swift 開發（需 Xcode.app）
