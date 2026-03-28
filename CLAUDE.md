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

### CA 簽署工具

```
scripts/sign-host-keys.sh [server...]     # 批次簽署 host key + 部署 User CA
scripts/sign-user-cert.sh <pubkey>        # 簽署使用者 SSH public key
scripts/rotate-user-key.sh [server...]    # 遠端重新產生 key + 簽 cert
```

### 新主機加入開發環境

將已完成基礎安裝的主機納入 SSH CA 認證、主機名稱解析、dotfiles 同步等基礎設施。

**前提條件**（使用者在新主機上已完成）：
- `curl -fsSL dot.bitpod.cc | sh`（自動 clone dotfiles + 執行平台對應的 setup script）
- 能從本機 SSH 連線（使用者需先用 `ssh-copy-id` 放臨時公鑰）

**執行步驟**（從本機 .dotfiles 目錄操作）：

#### 1. 修改 dotfiles 配置

需要修改的檔案與位置：

| 檔案 | 修改內容 |
|------|----------|
| `ssh/config` | 新增 Host block（HostName、User jjshen、IdentityFile ~/.ssh/id_autogen、Port 22） |
| `scripts/dotfiles-sync.sh` | `ALL_HOSTS` 陣列加入新主機 |
| `scripts/sign-host-keys.sh` | `ALL_SERVERS` 陣列加入新主機 |
| `scripts/rotate-user-key.sh` | `ALL_SERVERS` 陣列加入新主機 |

`ssh/known_hosts` 使用 `@cert-authority` 萬用字元，通常不需修改（確認新 IP 在已涵蓋的範圍：`10.10.12.*`、`10.10.40.*`、`172.17.13.*`、`172.18.110.*`）。

#### 2. 套用本機 SSH config

修改 dotfiles 後，立即將 `ssh/config` 寫入 `~/.ssh/config`，讓 host alias 可用。

#### 3. SSH keys 部署

複製到新主機（兩組 GitHub key 都要）：
- `~/.ssh/id_github` + `.pub` — GitHub 個人帳號 + fallback 認證
- `~/.ssh/id_github_work` + `.pub` — GitHub 工作帳號

設定 `~/.ssh/authorized_keys`：放入 `id_github.pub`（所有伺服器統一的 fallback key，用於不支援 cert 的終端設備連入）。bootstrap 期間可暫時保留 `id_autogen.pub`，CA 設定完成後可移除。

#### 4. SSH config + known_hosts 套用到新主機

將 `ssh/config` 寫入新主機的 `~/.ssh/config`，`ssh/known_hosts` 複製到 `~/.ssh/known_hosts`。建立空的 `~/.ssh/config.local`（如不存在）。

#### 5. CA 簽署

依序執行（需要 iCloud 中的 CA private key）：
```bash
./scripts/sign-host-keys.sh <new_hosts...>    # Host CA：簽署 host key + 部署 User CA
./scripts/rotate-user-key.sh <new_hosts...>   # User cert：產生各機器 id_autogen + 簽 cert
```

完成後新主機即加入 cert 互信網路，可用 cert 認證 SSH 到其他所有主機。

#### 6. /etc/hosts 更新

所有主機（含新舊）的 `/etc/hosts` 都要有完整的 `# pilot-infra-start/end` block。

格式範例：
```
# pilot-infra-start
10.10.12.6    eagle06
10.10.12.7    eagle07
...
# pilot-infra-end
```

- **遠端主機**：透過 SSH 用 `sudo sed` 刪除舊 block + `sudo tee -a` 寫入新 block
- **本機 Mac**：需要 `sudo`，提示使用者手動執行（Claude Code sandbox 無法 sudo）

#### 7. Commit、Push、Sync

```bash
git add ssh/config scripts/dotfiles-sync.sh scripts/sign-host-keys.sh scripts/rotate-user-key.sh
git commit -m "feat: 新增 <hostname> 至 SSH config 與主機清單"
git push
./scripts/dotfiles-sync.sh    # 同步到所有主機
```

#### 8. 驗證

- 本機 → 新主機 SSH（cert 認證，不應要求密碼）
- 新主機 → 既有主機 SSH（`ssh <host> "ssh <other_host> hostname"`）
- `/etc/hosts` 解析（`ssh <new_host> "getent hosts <any_host>"`）

#### 使用者仍需手動完成

- 新主機上填寫 `~/.env`（API keys 等機密）
- 新主機上設定 `~/.gitconfig` 的 `user.name` / `user.email`

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
