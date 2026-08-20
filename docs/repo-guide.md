# Repo 文檔入口

需要找 repo 的決策、死路、里程碑、規範、plan、skill reference 或 eval 時，先跑：

```sh
scripts/doc-governance.py find '<自然語言問題或 record ID>'
```

結果已限制為 logical entries，不要為了找一條理由先整批讀 `docs/archive/`。若無命中，再使用 `rg`
做診斷，並把可重現的自然語言問題加入 retrieval corpus。

寫入前用 `record-path` 計算 history 落點；送出前用 `audit --ship`。完整資料模型與 exit contract 見
`docs/document-governance.md`。

## 平台、工具與運維詳情

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
| SFTP 傳檔 | `lftp` | sftp |
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

- macOS: `brewup`（brew update/upgrade + dotfiles pull + **ensure helper 部署** + Claude plugins + known_hosts 同步 + **bun 全域套件落後提示**）
- Linux: `brewup`（同 macOS）+ `sysup`（apt update/upgrade）

> **`brewup` 對 bun 只提示、不自動升。** `bun` 本體是 brew formula、跟著 `brew upgrade` 走；
> 但 `bun install -g` 裝的（如 `wrangler`）**不升**——那類套件會改變部署行為，而 `brewup` 由
> `allup` 在整個機隊同時跑，不該靜默升版。要升自己跑 `bun update -g`。
> 判準是 **Current != Update**：只有 `Latest` 不同的（major 被 semver range 擋住）刻意不提示，
> 否則每次 brewup 都會亮一個 `bun update -g` 升不動的東西。
- macOS: `brewfix`（cask 升版被 Gatekeeper 卡死時的診斷與復原；**預設唯讀**，`brewfix --fix` 才動手。病灶與鑑別法見 `claude/known-hazards.md`「cask 升版卡死」）

> `brewup` / `sysup` 原為兩個 setup 腳本各自定義的 rc alias（`brewup` 兩份完全相同的複本），現已抽成
> `scripts/brewup.sh` / `scripts/sysup.sh`，由 `shell/functions.sh` 包裝成函數——雙平台共用同一份邏輯。
> 附帶效果：`all-up.sh` 可直接呼叫腳本，不必再用 `bash -ic` 去載入 alias，無 TTY 時的
> `cannot set terminal process group` / `no job control` 兩行雜訊隨之消失。
> **切勿在 rc 或 setup 裡重新定義同名 alias**——alias 展開優先於 function 查找，會靜默遮蔽 functions.sh 的版本；
> 既有主機 rc 裡的舊 alias 由 `ensure-rc-source.sh` 於 `dotsync` 時移除（不能靠 `unalias`：rc 裡 alias 與
> `source` 行的相對順序因機器而異，2026-08-07 巡檢 14 台發現 13 台 source 在後、macmini 在前，
> `unalias` 會變成多數生效、少數靜默失效）。

> **Claude Code settings 同步模型**：`claude/settings.json` 為唯一權威，由選定的權威機器刻意 `commit + push`。
> 其他機器 `brewup` 會在 pull 前 `git checkout -- claude/settings.json`，**丟棄本機 harness runtime drift、用 repo 版覆蓋**（drift 是拋棄式的）。
> `git/config` 設 `rebase.autoStash` 作為其他偶發 dirty 檔的安全網。
> 真正屬於單機的 key 放 `~/.claude/settings.local.json`（untracked、harness 不寫、優先級高於 settings.json）。
> Caveat：在權威機器上要先 `commit` 再跑 `brewup`，否則未提交的刻意改動會被丟棄。
- `dotsync` - 同步 dotfiles 到所有遠端主機（並行 SSH pull + 重新套用 config）

> **不在 `inventory.conf` 的機器（個人 MacBook）怎麼跟上**——`dotsync` 涵蓋不到它們，要自己跑一次：
>
> ```bash
> git -C ~/.dotfiles pull && bash ~/.dotfiles/scripts/brewup.sh
> ```
>
> **絕對路徑是給「rc 還沒 source 過 `functions.sh`」的機器用的**（那時還沒有 `brewup` function）。
> 已部署過的機器**直接打 `brewup` 就好**——2026-08-15 實測兩台個人 MacBook 皆已是 function 版（`type brewup`），
> 舊 alias 早由 `ensure-rc-source.sh` 清掉；同次也確認 `brewup.sh` 偵測自身更新會 `exec` 新版重跑（印 `↻` 那行），
> 故舊說法「落後的機器要跑兩次」亦已不成立。**前面那個 `git pull &&` 仍建議保留**：它是功能性的、不是排版——
> `brewup.sh` 自己也會 pull，但**執行中的 bash 握著舊 inode**，先獨立 pull 才保證這一輪就跑新版。
>
> 2026-08-08 GitHub 身分收斂的一次性步驟（SSH key 改名、`scripts/migrate-github-remotes.sh --apply` 換各 repo 的
> remote、`ssh -T` 雙身分驗證）**兩台皆已完成**，不再列於此；未來若有全新機器需要，序列見 git history。
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
- **GitHub 工作**（預設）：`id_github_com`（Host `github.com`）——標準 URL `git@github.com:` 直接可用，
  `gh` 也才對得上（**gh 完全不看 SSH alias**，那是 alias 方案永遠解不掉的一半）
- **GitHub 個人**：`id_personal`（Host `github-me`）——少數個人 repo 明示走這條。
  這個 alias 不可約：GitHub 一把 key 只能綁一個帳號，兩個身分必須有區分方式。
  **key 名刻意不帶 `github`**：同一把私鑰也是下面那條 `authorized_keys` fallback 用的私鑰，
  叫 `id_github_*` 會把那個角色藏起來（`id_personal-cert.pub` 是早期用它簽的內網 cert，遺留物）
- ⚠️ 兩個 Host 的 `IdentitiesOnly yes` **一行都不能少**：少了它 ssh 會把 agent 裡的 key 逐一送出、
  GitHub 收下第一把有效的 → 認到**錯誤帳號**，長相是「連得上但權限不對」，比連不上更難查
- 舊寫法 `github-work` 與 `~/.gitconfig` 的 `insteadOf` 改寫層**已移除**。某台機器部署新 `ssh/config`
  後，該機器要跑一次 `scripts/migrate-github-remotes.sh --apply`（預設 dry-run），否則它既有的
  `git@github-work:` remote 會當場全部失效。該腳本以身分驗證為硬前提、掃**每個** remote（不只
  `origin`——工作 mac 上就有兩條 `fork` remote 走 github-work）、順帶清 `insteadOf`
- **終端設備 fallback**：伺服器 `authorized_keys` 保留 `id_personal.pub`（CA cert 那條路失效時的後路，
  由 `add-new-host.sh` 部署）。**存的是公鑰內容、不是檔名**，所以本地改 key 檔名不影響它

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

## 開發環境

- **Bun**: `bun`（主要 JS runtime，取代 npm/npx）
- **uv**: `uv`（主要 Python 套件管理，取代 pip/venv）
- **Node.js**: `node`（相容性備用，不使用 npm）
- **Python**: `python`（兩平台都指向 python3）
- **GitHub CLI**: `gh`
