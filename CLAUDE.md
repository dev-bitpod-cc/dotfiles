# Shell 環境配置指引

此環境已透過標準化腳本配置，你可以直接使用以下現代化工具。

## 快速安裝

- **macOS 新機**：`curl -fsSL dot.bitpod.cc | sh`（Xcode CLT → clone → setup）
- **macOS 已有 repo**：`./setup-mac-env.sh`
- **macOS 系統偏好**：`./write-mac-defaults.sh`（選用，獨立執行）
- **Linux Ubuntu**：`./setup-linux-env.sh`

## 平台資訊

- **macOS**: zsh（`~/.zshenv`, `~/.zprofile`, `~/.zshrc`）
- **Linux Ubuntu**: bash（`~/.bashrc`, `~/.bash_profile`）
- **使用者自訂設定**：`.local` 檔案（不會被腳本覆寫）

## 可用工具

### 優先使用這些現代化工具

| 任務 | 使用 | 取代 |
|------|------|------|
| 列出檔案 | `eza` 或 `ll`/`la`/`lt`/`llt` | ls |
| 查看檔案 | `bat` | cat |
| 搜尋檔案 | `fd` | find |
| 搜尋內容 | `rg` | grep |
| 搜尋替換 | `sd` | sed |
| 目錄跳轉 | `z <keyword>` | cd |
| HTTP 請求 | `http` (HTTPie) | curl |
| JSON 處理 | `jq` | - |
| YAML 處理 | `yq` | - |
| Git diff | `gd` (自動使用 delta) | git diff |
| Git TUI | `lazygit` | - |
| 磁碟分析 | `dust` | du |
| 效能測試 | `hyperfine` | time |
| 程式碼統計 | `tokei` | cloc |
| 指令速查 | `tldr` | man |
| 環境變數自動載入 | `direnv` | - |
| 任務執行器 | `just` | make |
| 檔案變更監控 | `watchexec` | - |

### Git 別名

```
gs=git status    gd=git diff     ga=git add       gc=git commit
gp=git push      gl=git pull     gco=git checkout gb=git branch
glog=git log --oneline --graph --decorate
```

### 系統更新與同步

- macOS: `brewup`（brew update/upgrade + dotfiles pull + Claude plugins + known_hosts 同步）
- Linux: `brewup`（同 macOS）+ `sysup`（apt update/upgrade）
- `dotsync` - 同步 dotfiles 到所有遠端主機（並行 SSH pull + 重新套用 config）
- `dotsync eagle03 db01` - 只同步指定主機

### 自訂函數

- `fe` - fzf 搜尋並編輯檔案
- `proj` - 快速切換專案目錄
- `stats` - 程式碼統計（tokei）
- `venv [name]` - 建立 Python 虛擬環境（優先使用 uv）
- `sysupdate` - 詳細的系統更新（僅 Linux）

## SSH 配置

### 認證架構

- **內網伺服器**：SSH CA certificate 認證（`id_autogen` + cert）
- **GitHub 個人**：`id_github`（Host `github.com`）
- **GitHub 工作**：`id_github_work`（Host `github-work`）
- **終端設備 fallback**：伺服器 `authorized_keys` 保留舊公鑰

### 管理的檔案

| 檔案 | 說明 |
|------|------|
| `ssh/config` | 共用 SSH config（setup 腳本生成到 `~/.ssh/config`） |
| `ssh/config.local.example` | 機器特定設定範本 |
| `ssh/known_hosts` | `@cert-authority` + GitHub fingerprint |
| `ssh/host_ca.pub` | Host CA 公鑰 |
| `ssh/user_ca.pub` | User CA 公鑰 |

### 主機清單（Single Source of Truth）

`scripts/inventory.conf` 是內網主機的唯一來源，格式 `<alias> <ip>`。
以下內容皆從它生成或 source，**不要手動改**：

- `ssh/config` 的 `# BEGIN inventory hosts` ... `# END inventory hosts` 區塊
- `/etc/hosts` 的 `# pilot-infra-start` ... `# pilot-infra-end` 區塊
- `sign-host-keys.sh` / `sign-user-key.sh` / `dotfiles-sync.sh` 內的主機清單（透過 `scripts/lib/inventory.sh` source）

### CA 簽署與主機管理工具

```
scripts/add-new-host.sh <alias> <ip>      # 新增主機：單一入口（推薦）
scripts/render-ssh-config.sh              # 從 inventory 重生 ssh/config 區塊
scripts/render-etc-hosts.sh               # 從 inventory 生成 /etc/hosts 區塊（--apply / --remote）
scripts/sign-host-keys.sh [server...]     # 批次簽署 host key + 部署 User CA
scripts/sign-user-cert.sh <pubkey>        # 簽署使用者 SSH public key
scripts/sign-user-key.sh [server...]      # 遠端重新產生 key + 簽 cert
scripts/dotfiles-sync.sh [host...]        # 同步 dotfiles 到所有主機
```

### 新主機加入開發環境

**前提條件**（使用者在新主機上已完成）：
- `curl -fsSL dot.bitpod.cc | sh`（自動 clone dotfiles + 執行平台對應的 setup script）
- 能從本機 SSH 連線（使用者需先用 `ssh-copy-id` 放臨時公鑰）
- 新主機 IP 需在 `ssh/known_hosts` 的 `@cert-authority` 涵蓋範圍內（`10.10.12.*`、`10.10.40.*`、`10.200.50.*`、`172.17.13.*`、`172.18.110.*`），否則先擴充

#### 主要流程

在**有 iCloud CA 的管理 Mac** 上，從 `~/.dotfiles` 目錄執行：

```bash
./scripts/add-new-host.sh <alias> <ip>
```

腳本自動完成：

1. **Phase A（metadata）**：驗證 → 寫入 `inventory.conf` → 重生 `ssh/config` → 套用 `~/.ssh/config` → 更新本機 `/etc/hosts`（需 sudo）→ git commit（不 push）
2. **Phase B（金鑰部署 + CA 簽署）**：部署 `id_github` / `id_github_work` / `authorized_keys` / `ssh/config` / `known_hosts` 到新主機 → `sign-host-keys.sh` → `sign-user-key.sh`

Phase B 結束後，手動完成 Phase C：

```bash
git push
./scripts/dotfiles-sync.sh                      # 同步到所有主機
./scripts/render-etc-hosts.sh --remote <host>   # 更新其他主機 /etc/hosts（每台逐一，選用）
```

#### 降級情境：沒 iCloud CA 的 Mac

腳本會偵測到 CA 缺失，只跑 Phase A 並提示：

```
Phase A 已完成。在有 CA 的管理機上執行：
    cd ~/.dotfiles && git pull
    ./scripts/add-new-host.sh --resume <alias>
```

先在無 CA Mac commit + push，再到管理機 `--resume` 接著跑 Phase B。

#### 預覽模式

```bash
./scripts/add-new-host.sh --dry-run <alias> <ip>    # 只印出會做什麼，不動檔案
```

#### 驗證

- 本機 → 新主機 SSH（cert 認證，不應要求密碼）
- 新主機 → 既有主機 SSH（`ssh <host> "ssh <other_host> hostname"`）
- `/etc/hosts` 解析（`ssh <new_host> "getent hosts <any_host>"`）

#### 使用者仍需手動完成

- 新主機上填寫 `~/.env`（API keys 等機密）
- 新主機上設定 `~/.gitconfig` 的 `user.name` / `user.email`

> **known_hosts 清理**：bootstrap 階段 SSH 連線會在本機 `~/.ssh/known_hosts` 留下個別 host fingerprint。`dotfiles-sync.sh` 會用 repo 的 `ssh/known_hosts`（僅含 `@cert-authority` + GitHub）覆蓋本機和所有遠端主機的 known_hosts，自動清除這些殘留條目。

## 內網工具

```
scripts/routing_10.10.sh     # 新增 10.10.0.0/16 路由
scripts/routing_172.18.sh    # 新增 172.18.0.0/16 路由
scripts/dotfiles-sync.sh     # 同步 dotfiles 到所有主機
```

## 重要規則

1. **原生命令未被替換**：`ls`, `cat`, `find`, `grep` 仍可正常使用
2. **不要假設單字母別名**：此環境不使用 `l`, `c` 等別名
3. **Linux 注意**：工具透過 Homebrew 安裝，`fd` 和 `bat` 是原名（保留 fdfind/batcat fallback alias）
4. **PATH 已包含**：`~/.local/bin`（uv、Claude Code 安裝於此）
5. **API Keys**：存放於 `~/.env`（權限 600，會自動載入）
6. **Git 設定**：透過 `include.path` 引入 `git/config`，`user.name`/`email` 在各機器的 `~/.gitconfig` 設定
7. **SSH keys**：`id_github`（GitHub）、`id_github_work`（工作 GitHub）、`id_autogen`（內網 cert）

## 開發環境

- **Bun**: `bun`（主要 JS runtime，取代 npm/npx）
- **uv**: `uv`（主要 Python 套件管理，取代 pip/venv）
- **Node.js**: `node`（相容性備用，不使用 npm）
- **Python**: `python`（兩平台都指向 python3）
- **GitHub CLI**: `gh`
