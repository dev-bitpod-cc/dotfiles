# Shell 環境配置指引

本檔是**本專案的事實**（工具、腳本、SSH 架構、主機清單）。行為契約的 kernel 逐字內嵌在下方；
權威矩陣與 working discipline 見 `AGENTS.md`「Documentation authority」。

> **為什麼 kernel 要在這裡再放一份而不是只寫指標**：2026-08-10 實測（clean room，不帶全域
> `CLAUDE.md`）——root `CLAUDE.md` 會被**自動載入**（瑣碎問題也遵守其中的 sentinel，2/2），
> 而 root `AGENTS.md` **不會**（同一 sentinel 只在 agent 剛好探索 repo 時才生效：需理解 repo
> 的問題 3/3、瑣碎問題 0/2，且 stream-json 顯示是探索時 `cat` 讀到的）。指標也救不了——
> 指標只是告訴你契約在別處，瑣碎任務照樣不會去讀。**Claude 端要綁得住，kernel 就得在
> 自動載入的檔案裡。** Codex 端不受影響（原生讀 `AGENTS.md`）。

<!-- agent-contract:kernel:start v1 -->
## Kernel

### Safety floor — never relaxed by any repo

- **NEVER commit onto the default branch** (`main`/`master`). If `HEAD` is on it — or detached — create a feature branch first: `git switch -c <type>/<slug>`. This holds regardless of protection state and regardless of which tooling is loaded.
- **NEVER push without authorization for the push in front of you.** Implementing, fixing, or committing never carries it, and neither does approval given before this change existed. **Where a shipping workflow applies, its authorization table is the only source — NEVER extend it with synonyms of your own.** Where none applies, authorization is an instruction naming the action itself ("push", "open a PR"), or an affirmative answer to a confirmation you just presented. **A bare "ship it" / "送出" names an outcome, not an action — on its own it authorizes nothing**; present the confirmation and wait. Deciding for yourself which wording is close enough is the failure this rule exists to prevent. No authorization ever covers the default branch.
- **NEVER merge on your own.** "push" or "open a PR" alone does NOT include merge. Only an explicit merge instruction does.
- **NEVER `git add -A` / `git add .` / `commit -a`.** Stage explicit paths.
- **If the working tree holds changes you did not make, STOP and report before staging, committing, or building on top of them.** Whether two sessions may share one tree is a dispatch decision made above you — never resolve it locally by guessing which changes are yours. Once authorized, explicit paths are still whole-file: stage verified hunks with `git add -p`.
- **Inspect `git diff --cached` before every commit.** After splitting a mixed file, verify from a clean clone — `git clone --no-local <repo> <tmpdir>`. "I checked the working tree" is not evidence.

### Fallback conventions — this repo's own convention wins where it has one

- Conventional Commits: `<type>: <short desc>`, type is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. **If this repo mandates another commit format, follow the repo.**
- Record non-obvious trade-offs, rejected alternatives, and dead ends **where this repo already keeps them**. Skip whenever the diff alone recovers the rationale — a rejected path leaves no trace in the diff, an added gate does. **If the repo has no such store, do NOT create one; list them in your report instead.**
<!-- agent-contract:kernel:end -->

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

## 測試

- `./tests/run.sh` — 腳本驗證一鍵跑完（shellcheck／`bash -n`／全形標點吞變數名／unquoted heredoc 反引號／交叉引用完整性／agent contract kernel 一致性，加上 inventory·render 純邏輯與各 skill 腳本的行為測試）。**以 exit code 判綠紅**——接 pipeline（如 `| tail`）會吃掉失敗。
- **何時必跑**：改動 `scripts/`、setup 腳本、skill 腳本後必跑；**改動任何 `.md` 的節名或搬動權威內容後同樣要跑**——交叉引用 gate 掃全 repo 的 md，改節名等於讓指向它的指標斷掉。
- ⚠️ **寫文件時會踩到的一條**：交叉引用 gate 的 pattern 分不出「使用」與「提及」——討論一條（尤其壞掉的）引用時，寫法與真指標一模一樣。處置是放進 code fence 或在路徑與引號間插字，**不放寬 pattern**（能區分兩者的唯一訊號就是 fence）。
- 各 gate 的判準、反例與設計理由見 `docs/testing-contract.md`。**放寬任何判準前先讀該檔**——多數判準是踩過才收窄的，且不少收窄伴隨刻意放棄的 false negative。
- Skill 行為測試（弱模型 evals）：`claude/evals/README.md`（沙盒建置 + 手動 runner），各 skill 情境在其目錄的 `evals.md`。
- deep-review 時 `verify-tests.sh` 對本 repo 判 SKIP（無 uv/bun 測試框架）——真測試就是本指令，每輪修復後手動跑。

## 重要規則

1. **原生命令未被替換**：`ls`, `cat`, `find`, `grep` 仍可正常使用
2. **不要假設單字母別名**：此環境不使用 `l`, `c` 等別名
3. **Linux 注意**：工具透過 Homebrew 安裝，`fd` 和 `bat` 是原名（保留 fdfind/batcat fallback alias）
4. **PATH 已包含**：`~/.local/bin`（uv、Claude Code 安裝於此）
5. **API Keys**：存放於 `~/.env`（權限 600，會自動載入）
6. **Git 設定**：透過 `include.path` 引入 `git/config`，`user.name`/`email` 在各機器的 `~/.gitconfig` 設定
7. **SSH keys**：`id_github_com`（GitHub 工作＝`github.com` 預設）、`id_personal`（GitHub 個人＝`github-me`，兼 `authorized_keys` fallback）、`id_autogen`（內網 cert）

## 開發環境

- **Bun**: `bun`（主要 JS runtime，取代 npm/npx）
- **uv**: `uv`（主要 Python 套件管理，取代 pip/venv）
- **Node.js**: `node`（相容性備用，不使用 npm）
- **Python**: `python`（兩平台都指向 python3）
- **GitHub CLI**: `gh`
