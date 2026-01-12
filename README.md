# Shell 環境設定工具

跨平台（macOS + Linux Ubuntu）的現代化開發環境自動配置工具。

## 檔案結構

```
config/
├── README.md              # 本文件（快速入門）
├── CLAUDE.md              # Claude Code 環境指引（自動讀取）
├── setup-mac-env.sh       # macOS 安裝腳本 (v3.1)
└── setup-linux-env.sh     # Linux Ubuntu 安裝腳本 (v3.1)
```

## 快速開始

### macOS

```bash
chmod +x setup-mac-env.sh
./setup-mac-env.sh
```

### Linux Ubuntu

```bash
chmod +x setup-linux-env.sh
./setup-linux-env.sh
```

## 功能特色

- **31+ 現代化工具**：eza, bat, fd, ripgrep, fzf, zoxide, git-delta, lazygit, dust, duf 等
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
2. Homebrew Python (macOS) / Bun
3. npm 全域套件
4. Cargo (Rust)
5. Go
6. conda/nvm/pyenv 路徑
7. 系統路徑

## 安裝的工具

### 核心工具
git, gh, wget, htop, tree, tmux, node, python3, jq, yq

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
| duf | 磁碟使用量 | df |

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
brewup  # macOS: brew update && upgrade && cleanup
sysup   # Linux: apt update && upgrade && autoremove
```

### fzf 快捷鍵

- `Ctrl+R` - 搜尋命令歷史
- `Ctrl+T` - 搜尋檔案
- `Alt+C` - 切換目錄

## 注意事項

1. **原生命令保留**：`ls`, `cat`, `find`, `grep` 仍可使用
2. **Linux 別名**：`fd` 和 `bat` 已設定別名（實際命令為 `fdfind` 和 `batcat`）
3. **需要新終端**：執行腳本後，開啟新終端視窗以啟用配置

## Claude Code 整合

執行腳本後，Claude Code 會自動讀取 `CLAUDE.md` 了解環境中可用的工具。

## 版本資訊

- **版本**：v3.1
- **更新日期**：2026-01-12
- **支援系統**：macOS (zsh), Ubuntu 24.04+ (bash)
