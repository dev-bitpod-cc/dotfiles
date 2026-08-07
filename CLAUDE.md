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

- `./tests/run.sh` — 腳本驗證一鍵跑完：shellcheck + bash -n 全腳本 gate（含 `claude/skills/*/scripts/` 與其 `lib/`、`shell/functions.sh`；shellcheck 以 `-P SCRIPTDIR` 解析 `source=`，故 lib 的相對寫法跨 cwd 都成立）、**全形標點吞變數名 gate**（`"（exit=$rc）"` 會被 bash 併入變數名 → `set -u` 下 unbound variable，且只在錯誤路徑觸發，一律要求寫 `${var}`）、inventory/render 純邏輯行為測試、skill 腳本行為測試（git-hygiene（**遠端事實優先**——判 unpushed 前先 `fetch --prune`；多 remote 時「branch 設定的 remote」與 `origin` **兩者都 fetch**、任一失敗即整體降 UNKNOWN，只 fetch 其中一個＝拿 A 的新鮮度替 B 背書，實測可重現假 CLEAN。`--porcelain -uall`——預設把未追蹤目錄折成 `?? dir/`，殘留檔數被低估；**gh 失敗 ≠ 無 PR**——兩者都是 exit 1，吞 stderr 會把「查不到」報成 MISSING；無 upstream 的已 push branch 用同名 `origin/<branch>` 當 baseline，退用 default 會把早已在 remote 的 commit 全報成未 push；MERGED 以 `headRefOid` 為界、拿不到就保守不撤銷（寧可誤報殘留，不可誤報乾淨）；**多 repo 單次呼叫的聚合**——區段不漏、verdict 逐 repo 成立、CLEAN 不吞 RESIDUE/UNKNOWN、全 CLEAN 才 exit 0；fetch 上限的斷言由 `(timeout+grace)×目標數` 推導，**不放寬到十幾秒**否則每 repo 卡十秒的 regression 照樣綠） / ship-state（含 resolve 子指令、dossier 簽章偵測、**dossier 尺寸訊號**——總量 bytes/最長行/決策·里程碑條目 bytes（條目附**行號**、全檔附**建議收斂目標**、超標時另印 **`dossier-sections:` 各節佔比**），巨型單行不再架空行數門檻，條目訊號作用域限決策/里程碑兩節、進行中 spec 區合法偏大不誤報；**剝 fence 用哨兵前綴**（行號對齊＋長度不失真，量長度前剝哨兵否則佔比虛胖），五個 code site 皆吃 unfenced（三個 pattern 家族）；**大輸入比對一律 herestring**（`printf | grep -q` 早退觸發 SIGPIPE＋pipefail 判偽；守門 fixture 的命中點須在**前段**才逼得出來，置於檔尾則 printf 已寫完、測試形同虛設）、**bootstrap 判定**——遠端零 branch 才給 BOOTSTRAP 豁免，遠端有 branch 但定位不到 default 一律 STOP，baseline 建立後豁免自動失效）、**殘留 branch 衛生**（已併入 default 的 local/remote branch 才列、未併入的不誤報、`origin/HEAD` 的裸 remote 名不得混入、cleanup-cmd 前置 `fetch --prune`、**當前 branch 的 remote 對應不得列入**——實地誤報過一次，照抄就會砍掉正要送出的那條）、**squash-merge 盲視補償**（`branch --merged` 判祖先關係，squash-merge 後結構上看不到；改比對 merged PR 的 `headRefOid` == 本地 tip，不符只印診斷不列入、fork 不採信、達 limit 標 `partial` 絕不印 `none`；fixture 前提自檢「祖先判定確實看不到它」，否則後續斷言全是假的）、**`cleanup-stale-branch.sh`**（破壞性刪除的唯一入口：branch 存在／執行當下 tip == expected SHA／local 不得是 checked-out，三道前提任一不成立即 STOP 零 mutation；remote 走 `ls-remote` 重驗 + `--force-with-lease` 雙重比對。**lease 是第二道防線，故前置比對另立斷言**——否則整段前置檢查可被刪光而全綠）、**review-residue**（Step 4 squash 出題依據：none／top-contiguous／buried 三形狀與混合、全壓指令附後果警語、reset 目標由腳本解析、lib 缺席與 merge-base 失敗皆降級 UNKNOWN）、**照抄行的 shell quoting**（路徑與 ref 名都過 `shq`——含單引號的路徑會讓 `bash -n` 直接 syntax error、`refs/heads/--all` 這種 option-like ref 靠 `--` terminator 才擋得住；斷言驗 round-trip 與「出現次數＝quoted 次數」，光看「有沒有 quoted 形式」會假綠）、**跨 Step 時序**（Step 1 的 squash hash 不得重算，正反兩組斷言）、**`mktemp` 失敗的自我防護**（`cd ""` 回傳 0 且不改目錄 → TMP 退化成 cwd → EXIT trap `rm -rf` 掉整個 repo；用 stub 逼失敗，設 `TMPDIR` 沒用、macOS 的 mktemp 會忽略它）/ **branch-first**（真 git fixture：情況 A/B、mixed state、分岔/撞名/無 remote 一律 STOP）/ review-state（**untracked 用 `-uall` 展開目錄**——預設 porcelain 折疊成 `?? dir/`，reviewer 拿到目錄名會整批漏審）/ **review-anchor**（cycle 續跑計數；**squash base 由 subject 掃描求得**——自 HEAD 往回跳過 review 機械樣式、停在第一顆語意 commit（該顆保留），全為樣式才退回 anchor base；`squash-preserve:`／`squash-note:` 訊號、續跑跨兩場 fix 一併壓、分岔歷史不誤列 preserve 皆有守門。**squash 範圍自此 ≠ 審查範圍**）/ **handoff-anchor**（`anchors` 記 `--show-toplevel` 絕對路徑——相對輸入原樣寫進錨點會讓跨 session 的 verify 對到**別的 repo**、還誤報成 DIVERGED；空白檢查對解析後的 toplevel 而非原輸入。`find-predecessor` 依 slug 精確定位前一份,**active 與 archive 判準不同**——active 比完整檔名(一併剝前綴會讓 `20260804-foo` 這種合法 slug 失配、判成首輪後整檔覆寫)、archive 才剝歸檔前綴且取**時戳數值**最大者(靠 glob 字典序會選到同日的 legacy 舊檔);檔內 `slug:` 存在時須相符、無該欄位者放行(向後相容)。不可退回 glob——`archive/*-<slug>.md` 的 `*` 吃得下中間的工作線名,查 `foo` 會撈到 `bar-foo`;**fixture 的 `bar-foo` 時戳必須最新**,否則 glob 實作的 `tail -1` 也剛好答對、斷言等於虛設)/ **session-pull-check.sh（SessionStart hook）**（**落後偵測與 base 建議都不得拿 repo-global `FETCH_HEAD` 的新鮮度替別的 remote 背書**——多 remote 時剛 fetch 過 `other`，真正落後的 clone 會完全不出聲；單 remote 才保留快取快路徑。fetch 真的失敗時 base 建議仍要出、但須帶「可能已過期」警語，該臂另立守門否則 `stale_note` 會變沒有覆蓋的死碼） / **codex-exec-review** / **crawl-quality-scan**，protection 判定用 gh stub、codex 用會模擬 clap argv 拒絕的 stub、crawl-quality-scan 用 python fixture 對準扣分表）、`ensure-rc-source.sh` / **`ensure-codex-skills.sh`** / **`ensure-codex-guidance.sh`** / **`ensure-lftprc.sh`**（含 `.lftprc.local` 不覆寫、早退路徑仍補檔）幂等測試、**dotfiles-sync 遠端回報段**（ssh 失敗與無告知時都不可吞掉主機結果）、`add-new-host.sh --dry-run` 煙霧測試。改動 `scripts/`、setup 腳本或 skill 腳本後必跑。deep-review 時 `verify-tests.sh` 對本 repo 判 SKIP（無 uv/bun 測試框架）——真測試就是本指令，每輪修復後手動跑、以 **exit code** 判綠紅（pipeline 接 tail 會吃掉失敗）。
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
