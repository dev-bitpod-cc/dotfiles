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

> **Claude Code settings 同步模型**：`claude/settings.json` 為唯一權威，由選定的權威機器刻意 `commit + push`。
> 其他機器 `brewup` 會在 pull 前 `git checkout -- claude/settings.json`，**丟棄本機 harness runtime drift、用 repo 版覆蓋**（drift 是拋棄式的）。
> `git/config` 設 `rebase.autoStash` 作為其他偶發 dirty 檔的安全網。
> 真正屬於單機的 key 放 `~/.claude/settings.local.json`（untracked、harness 不寫、優先級高於 settings.json）。
> Caveat：在權威機器上要先 `commit` 再跑 `brewup`，否則未提交的刻意改動會被丟棄。
- `dotsync` - 同步 dotfiles 到所有遠端主機（並行 SSH pull + 重新套用 config）
- `dotsync eagle03 db01` - 只同步指定主機
- `tmuxls` - 列出各主機的 tmux session（`tmuxls eagle03 db01` 只看指定主機）
- `allup` - 批次系統更新：各主機依 OS 跑 `brewup`（Linux 另加 `sysup`）。無引數＝本機＋全部遠端（本機若在 inventory 清單則自動以 IP 比對扣除，避免重複）；`allup eagle03 db01` 只跑指定主機（不含本機）；`ALLUP_DRYRUN=1 allup` 只預覽計畫不執行

> **便利函數散佈模型**：`dotsync` / `tmuxls` / `allup` 等跨主機便利函數版控於 `shell/functions.sh`（唯一來源），互動 rc（`~/.zshrc` / `~/.bashrc`）只 `source` 它。`dotsync` 於 pull 後由 `scripts/ensure-rc-source.sh` 幂等補上該 `source` 行。故新增便利函數只需改 `shell/functions.sh` + `commit` + `dotsync`，各主機下次開 shell 即生效，**毋須逐台重跑 setup**。

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

在**有 iCloud CA 的管理 Mac** 上執行 `./scripts/add-new-host.sh <alias> <ip>`（單一入口；`--dry-run` 只預覽不動檔案）。腳本自動跑 Phase A（inventory → ssh/config → /etc/hosts → commit）＋ Phase B（金鑰部署 + CA 簽署）；結束後手動 Phase C：`git push` + `./scripts/dotfiles-sync.sh`。無 CA 的 Mac 只會跑 Phase A，commit + push 後到管理機 `--resume <alias>` 接續。

前提條件、Phase 細節、降級情境、驗證步驟、使用者手動收尾與 known_hosts 清理 → 見 `docs/add-new-host.md`。

## 內網工具

```
scripts/routing_10.10.sh     # 新增 10.10.0.0/16 路由
scripts/routing_172.18.sh    # 新增 172.18.0.0/16 路由
scripts/dotfiles-sync.sh     # 同步 dotfiles 到所有主機
```

## 測試

- `./tests/run.sh` — 腳本驗證一鍵跑完：shellcheck + bash -n 全腳本 gate（含 `claude/skills/*/scripts/`、`shell/functions.sh`）、**全形標點吞變數名 gate**（`"（exit=$rc）"` 會被 bash 併入變數名 → `set -u` 下 unbound variable，且只在錯誤路徑觸發，一律要求寫 `${var}`）、inventory/render 純邏輯行為測試、skill 腳本行為測試（git-hygiene / ship-state / review-state / handoff-anchor / **codex-exec-review**，protection 判定用 gh stub、codex 用會模擬 clap argv 拒絕的 stub）、`ensure-rc-source.sh` / **`ensure-codex-skills.sh`** 幂等測試、**dotfiles-sync 遠端回報段**（ssh 失敗與無告知時都不可吞掉主機結果）、`add-new-host.sh --dry-run` 煙霧測試。改動 `scripts/`、setup 腳本或 skill 腳本後必跑。
- Skill 行為測試（弱模型 evals）：`claude/evals/README.md`（沙盒建置 + 手動 runner），各 skill 情境在其目錄的 `evals.md`。

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
