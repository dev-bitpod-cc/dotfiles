# Shell 環境設定工具

跨平台（macOS + Linux Ubuntu）的現代化開發環境自動配置工具。

## 檔案結構

```
config/
├── README.md              # 本文件（快速入門）
├── CLAUDE.md              # Claude Code 環境指引（自動讀取）
├── bootstrap.sh           # 雙平台一鍵 bootstrap（macOS + Linux）
├── claude/                # Claude Code 共用設定與 skills
├── codex/                 # Codex 共用設定、rules、skills
├── setup-mac-env.sh       # macOS 開發環境安裝腳本 (v3.1)
├── write-mac-defaults.sh  # macOS 系統偏好設定腳本 (v1.0)
└── setup-linux-env.sh     # Linux Ubuntu 安裝腳本 (v4.0, Homebrew)
```

## 快速開始

### macOS（新機一鍵安裝）

```bash
curl -fsSL dot.bitpod.cc | sh
```

自動完成：Xcode CLT 安裝 → clone repo → 執行環境設定。

### Linux（新機一鍵安裝）

```bash
curl -fsSL dot.bitpod.cc | sh
```

自動完成：apt 前置依賴 → clone repo → Homebrew 安裝 → 執行環境設定。

> **Cloudflare 設定**：`dot.bitpod.cc` 302 redirect 至
> `https://raw.githubusercontent.com/dev-bitpod-cc/dotfiles/main/bootstrap.sh`

### macOS（已有 repo）

```bash
# 開發工具環境
./setup-mac-env.sh

# macOS 系統偏好設定（選用，可獨立執行）
./write-mac-defaults.sh
```

### Linux Ubuntu（已有 repo）

```bash
chmod +x setup-linux-env.sh
./setup-linux-env.sh
```

## 功能特色

- **33+ 現代化工具**：eza, bat, fd, ripgrep, fzf, zoxide, git-delta, lazygit, dust, direnv, just, watchexec 等
- **Homebrew 統一管理**：macOS 和 Linux 都透過 Homebrew 安裝工具，版本一致、更新方便
- **智能 PATH 管理**：自動統合、去重、依優先級排序
- **冪等性**：重複執行不會破壞使用者設定
- **跨平台一致**：macOS (zsh) 和 Linux (bash) 使用相同工具和別名

## 使用者自訂設定

腳本會建立 `.local` 檔案來保留使用者設定：

| 平台 | 個人設定檔 | 個人 PATH |
|------|-----------|-----------|
| macOS | `~/.zshrc.local` | `~/.zprofile.local` |
| Linux | `~/.bashrc.local` | `~/.bash_profile.local` |

這些檔案不會被覆寫，重複執行腳本時設定會保留。

## PATH 優先級

從高到低：
1. `~/.local/bin` - 使用者本地程式
2. `~/.bun/bin` - Bun（主要 JS runtime）
3. `~/.npm-global/bin` - npm 全域套件（相容性備用）
4. `~/.cargo/bin` - Cargo (Rust)
5. `~/go/bin` - Go
6. conda/nvm/pyenv 路徑
7. Homebrew 路徑
8. 系統路徑

## 安裝的工具

### 核心工具
git, gh, wget, htop, tree, tmux, bun, node, python3, uv, jq, yq

### 現代化 CLI
| 工具 | 用途 | 取代 |
|------|------|------|
| eza | 彩色檔案列表 | ls |
| bat | 語法高亮檔案查看 | cat |
| fd | 快速檔案搜尋 | find |
| rg (ripgrep) | 快速內容搜尋 | grep |
| fzf | 模糊搜尋 | - |
| zoxide | 智能目錄跳轉 | cd |
| delta | Git diff 美化 | - |
| lazygit | Git TUI 介面 | - |
| dust | 磁碟空間分析 | du |
| direnv | 目錄環境變數自動載入 | - |
| just | 任務執行器 | make |
| watchexec | 檔案變更監控執行 | - |

### 便捷別名

```bash
# 檔案列表
ll    # eza -l
la    # eza -la
lt    # eza --tree

# Git
gs    # git status
gd    # git diff
ga    # git add
gc    # git commit
gp    # git push
gl    # git pull

# 系統更新
brewup  # macOS/Linux: brew update && upgrade + dotfiles pull + Claude plugins
sysup   # Linux: apt update && upgrade && autoremove
```

### fzf 快捷鍵

- `Ctrl+R` - 搜尋命令歷史
- `Ctrl+T` - 搜尋檔案
- `Alt+C` - 切換目錄

## 注意事項

1. **原生命令保留**：`ls`, `cat`, `find`, `grep` 仍可使用
2. **Linux fd/bat 別名**：保留 fallback alias（`fdfind` → `fd`, `batcat` → `bat`），但 Homebrew 安裝的是原名，不會觸發
3. **需要新終端**：執行腳本後，開啟新終端視窗以啟用配置

## Claude Code 整合

執行腳本後，Claude Code 會自動讀取 `CLAUDE.md` 了解環境中可用的工具。

## Codex 整合

執行 `setup-mac-env.sh` 或 `setup-linux-env.sh` 時，會將 `claude/` 與 `codex/` 內的共用設定同步到對應的 home 目錄。

- Claude：同步到 `~/.claude/`
- Codex：同步到 `~/.codex/`

其中 `~/.codex/config.local.toml` 保留本機相依設定，不納入版控。

## 版本資訊

- **版本**：v4.0
- **更新日期**：2026-03-20
- **支援系統**：macOS (zsh), Ubuntu 24.04+ (bash)
- **套件管理**：Homebrew（兩平台統一）
