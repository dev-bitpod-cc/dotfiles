# Shell 環境配置指引

> **行為契約在 `AGENTS.md`「Kernel」**（repo 根，工具中立）——git 紀律、文件權威矩陣、
> generated docs 不得覆蓋權威檔，都在那裡。本檔是**本專案的事實**（工具、腳本、SSH 架構、
> 主機清單），不重述契約。

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

- macOS: `brewup`（brew update/upgrade + dotfiles pull + **ensure helper 部署** + Claude plugins + known_hosts 同步）
- Linux: `brewup`（同 macOS）+ `sysup`（apt update/upgrade）
- macOS: `brewfix`（cask 升版被 Gatekeeper 卡死時的診斷與復原；**預設唯讀**，`brewfix --fix` 才動手。病灶與鑑別法見 `claude/CLAUDE.md`「已知地雷」）

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

> **不在 `inventory.conf` 的機器（個人 MacBook）怎麼跟上**——`dotsync` 涵蓋不到它們，而且**打 `brewup` 沒有用**：
> 那些機器的 rc 裡還留著舊的 `brewup` alias，而 alias 展開優先於 function 查找，跑到的是不含 helper 的舊一行版。
> 補齊一律**用絕對路徑呼叫腳本**繞過 alias：
>
> ```bash
> # ① 只有「從未跟上 2026-08-08 GitHub 身分收斂」的機器需要這步，而且必須在 ② 之前。
> #    cp 不要 mv——新舊並存，任一步失敗都不會斷線。
> cp ~/.ssh/id_github_work ~/.ssh/id_github_com   # 舊名 → 新名
> cp ~/.ssh/id_github      ~/.ssh/id_personal
> # ② pull + 部署（brewup.sh 會跑 ensure-ssh-config / rc-source / codex-skills / codex-guidance / lftprc）
> #    ⚠ 前面那個 `git pull &&` 是功能性的、不是排版：brewup.sh 自己也會 pull，但**執行中的
> #    bash 會跑完舊版**，落後的機器因此要跑兩次才部署到 helper。先獨立 pull 就只需一次。
> #    （新版 brewup.sh 已會偵測自身更新並 exec 重跑，但那段程式碼要先進到機器上才有用。）
> git -C ~/.dotfiles pull && bash ~/.dotfiles/scripts/brewup.sh
> # ③ 把該機器上所有 repo 的 remote 換成標準 URL（預設 dry-run，確認後才 --apply）
> bash ~/.dotfiles/scripts/migrate-github-remotes.sh --apply
> # ④ 驗兩個身分都認得對，才刪舊 key（順序不可顛倒）
> ssh -T git@github.com; ssh -T git@github-me
> ```
>
> ② 跑完之後 rc 的舊 alias 已由 `ensure-rc-source.sh` 移除，之後打 `brewup` 就是 functions.sh 的版本、會自己帶 helper——
> **這台機器從此不需要再手動補齊**。若 ① 漏做，`ensure-ssh-config.sh` 會擋下並印出缺哪一把 key（它拒絕拿可用的
> 認證換成壞的），不會把機器弄斷。
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

- `./tests/run.sh` — 腳本驗證一鍵跑完：shellcheck + bash -n 全腳本 gate（含 `claude/skills/*/scripts/` 與其 `lib/`、`shell/functions.sh`、**`claude/evals/*.sh`**；shellcheck 以 `-P SCRIPTDIR` 解析 `source=`，故 lib 的相對寫法跨 cwd 都成立。evals 於 2026-08-08 補入四個 gate——**納入時它零 findings，便宜的守門要趁乾淨時加**，等長歪再加就得先還債）、**全形標點吞變數名 gate**（`"（exit=$rc）"` 會被 bash 併入變數名 → `set -u` 下 unbound variable，且只在錯誤路徑觸發，一律要求寫 `${var}`）、**unquoted heredoc 反引號 gate**（掃描器 `tests/heredoc-gate.awk`：delimiter 未加引號 + body **字面**含反引號 → 那段會被 bash 當命令替換**真的執行**；追蹤 quoted heredoc 的進出、排除 `<<<` 與註解行，並以 RED/GREEN fixture 自檢——掃描器被改壞而恆不匹配時，對真實檔案的空輸出一樣是「通過」。**判準刻意只管字面**：`$(cat 某檔)` 注入的反引號不會被執行（命令替換結果不重新掃描，2026-08-07 實測），曾為它加過一條規則、會把每個用 heredoc 灌檔的正常寫法判紅，已撤銷並留 GREEN fixture 釘住）、**交叉引用完整性 gate**（掃描器 `tests/xref-gate.py`：抽出「見〈路徑〉〈節名〉」句型逐條驗證，**把「唯一權威」這個原本純靠散文的不變式換成機檢**——指標一斷，`claude/CLAUDE.md` 要求的「勿憑記憶重組」就只剩重組一途；首次掃描即抓出 1 條真死指標與 2 條指向 repo 內雙份同名檔的基名引用。**source 與 target 的非正文排除刻意不對稱**：source 排 fenced、**掃** HTML comment（圍欄內是示範怎麼寫，註解裡卻是真的要你去看——krepo 的量體豁免指標就寫在檔首 comment）；target 的 heading/body **兩者皆排除**（註解掉的模板與圍欄裡的範例標題都不構成「該節存在」的證據）。節名比對用 normalize 後子字串（heading 常帶括號補充），不中則退一步比對**逐行**內文（引用一條規則而非節名是合法寫法）——整檔併成一串會讓兩行的尾首拼接成假命中；normalize 須剝 inline 修飾，否則原文帶 `**` 的規則引用被判紅。**normalize 後 < 2 字即 blocking**（空字串是任何字串的子字串，恆假綠）。**不做全 repo 同名搜尋**——兩份 `reviewer-brief.md` 是「review 刻意隔離」下故意不同的兩套判準，模糊搜尋會指到錯的那份而毫無警訊。fence 偵測明訂為**已驗證的 CommonMark 子集**（closer 須同字元且長度 ≥ opener、closer 後只允許空白、opener 縮排上限 3 格），三者各有 fixture。**exit 0/2 契約**：內容問題走 stdout、scanner 自身失敗走 exit 2——`run.sh` 無 `set -e`，掃描器死掉的空 stdout 會被判成乾淨。⚠️ **pattern 分不出「使用」與「提及」**：討論一條（尤其壞掉的）引用時寫法與真指標一模一樣，處置是放進 code fence 或在路徑與引號間插字，**不放寬 pattern**——能區分兩者的唯一訊號就是 fence）、inventory/render 純邏輯行為測試、skill 腳本行為測試（git-hygiene（**遠端事實優先**——判 unpushed 前先 `fetch --prune`；多 remote 時「branch 設定的 remote」與 `origin` **兩者都 fetch**、任一失敗即整體降 UNKNOWN，只 fetch 其中一個＝拿 A 的新鮮度替 B 背書，實測可重現假 CLEAN。`--porcelain -uall`——預設把未追蹤目錄折成 `?? dir/`，殘留檔數被低估；**gh 失敗 ≠ 無 PR**——兩者都是 exit 1，吞 stderr 會把「查不到」報成 MISSING；無 upstream 的已 push branch 用同名 `origin/<branch>` 當 baseline，退用 default 會把早已在 remote 的 commit 全報成未 push；MERGED 以 `headRefOid` 為界、拿不到就保守不撤銷（寧可誤報殘留，不可誤報乾淨）；**多 repo 單次呼叫的聚合**——區段不漏、verdict 逐 repo 成立、CLEAN 不吞 RESIDUE/UNKNOWN、全 CLEAN 才 exit 0；fetch 上限的斷言由 `(timeout+grace)×目標數` 推導，**不放寬到十幾秒**否則每 repo 卡十秒的 regression 照樣綠） / ship-state（含 resolve 子指令、dossier 簽章偵測、**dossier 尺寸訊號**——總量 bytes/最長行/決策·里程碑條目 bytes（條目附**行號**、全檔附**建議收斂目標**、超標時另印 **`dossier-sections:` 各節佔比**），巨型單行不再架空行數門檻，條目訊號作用域限決策/里程碑兩節、進行中 spec 區合法偏大不誤報；**節名判定一律端錨定、不用子字串**——`## 進行中（已完成 M1）` 這種自然寫法含「已完成」三字，子字串版會把整個進行中章節當里程碑節掃進條目判定而恆誤報，反向 `## 已完成（進行中殘項）` 則讓里程碑的 ✅ 算成進行中的（兩條斷言各經突變驗證）；**分節 bytes 把標題行計入所屬節**，斷言「加總 == 檔案 bytes」（歸零會讓佔比表系統性偏低，讀的人以為漏算了一塊）；**剝 fence 用哨兵前綴**（行號對齊＋長度不失真，量長度前剝哨兵否則佔比虛胖），五個 code site 皆吃 unfenced（三個 pattern 家族）；**大輸入比對一律 herestring**（`printf | grep -q` 早退觸發 SIGPIPE＋pipefail 判偽；守門 fixture 的命中點須在**前段**才逼得出來，置於檔尾則 printf 已寫完、測試形同虛設）、**append-only 章節的別名家族**（規範是「NEVER add an append-only log section」而非「不要叫 Session Log」——只認一個字面時，換名為變更紀錄／工作日誌／CHANGELOG 就整個漏掉；ASCII 走 `-i`、中文含記/紀異體，**限完整章節名**（允許括號或冒號後綴）否則「## 為何不使用 Change Log」這類討論性章節會被判紅，而 gate 誤報的代價是逼人改壞寫法以求過測；訊息附**實際命中的 heading**，硬寫「Session Log」會讓別名命中時的處置指向錯的章節。7 條正向別名 + 3 條負向討論性章節守門）、**bootstrap 判定**——遠端零 branch 才給 BOOTSTRAP 豁免，遠端有 branch 但定位不到 default 一律 STOP，baseline 建立後豁免自動失效）、**殘留 branch 衛生**（已併入 default 的 local/remote branch 才列、未併入的不誤報、`origin/HEAD` 的裸 remote 名不得混入、cleanup-cmd 前置 `fetch --prune`、**當前 branch 的 remote 對應不得列入**——實地誤報過一次，照抄就會砍掉正要送出的那條）、**squash-merge 盲視補償**（`branch --merged` 判祖先關係，squash-merge 後結構上看不到；改比對 merged PR 的 `headRefOid` == 本地 tip，不符只印診斷不列入、fork 不採信、達 limit 標 `partial` 絕不印 `none`；fixture 前提自檢「祖先判定確實看不到它」，否則後續斷言全是假的）、**`cleanup-stale-branch.sh`**（破壞性刪除的唯一入口：branch 存在／執行當下 tip == expected SHA／local 不得是 checked-out，三道前提任一不成立即 STOP 零 mutation；remote 走 `ls-remote` 重驗 + `--force-with-lease` 雙重比對。**lease 是第二道防線，故前置比對另立斷言**——否則整段前置檢查可被刪光而全綠）、**review-residue**（Step 4 squash 出題依據：none／top-contiguous／buried 三形狀與混合、全壓指令附後果警語、reset 目標由腳本解析、lib 缺席與 merge-base 失敗皆降級 UNKNOWN）、**照抄行的 shell quoting**（路徑與 ref 名都過 `shq`——含單引號的路徑會讓 `bash -n` 直接 syntax error、`refs/heads/--all` 這種 option-like ref 靠 `--` terminator 才擋得住；斷言驗 round-trip 與「出現次數＝quoted 次數」，光看「有沒有 quoted 形式」會假綠）、**跨 Step 時序**（Step 1 的 squash hash 不得重算，正反兩組斷言）、**`mktemp` 失敗的自我防護**（`cd ""` 回傳 0 且不改目錄 → TMP 退化成 cwd → EXIT trap `rm -rf` 掉整個 repo；用 stub 逼失敗，設 `TMPDIR` 沒用、macOS 的 mktemp 會忽略它）/ **branch-first**（真 git fixture：情況 A/B、mixed state、分岔/撞名/無 remote 一律 STOP）/ review-state（**untracked 用 `-uall` 展開目錄**——預設 porcelain 折疊成 `?? dir/`，reviewer 拿到目錄名會整批漏審）/ **review-anchor**（cycle 續跑計數；**squash base 由 subject 掃描求得**——自 HEAD 往回跳過 review 機械樣式、停在第一顆語意 commit（該顆保留），全為樣式才退回 anchor base；`squash-preserve:`／`squash-note:` 訊號、續跑跨兩場 fix 一併壓、分岔歷史不誤列 preserve 皆有守門。**squash 範圍自此 ≠ 審查範圍**）/ **handoff-anchor**（**`anchors` 是全有或全無**——逐 repo 四項前提（toplevel 可解析／路徑無空白／`rev-parse --verify HEAD^{commit}` 成功／`status` 可讀）任一不成立即 stdout 全空 + exit 1；半成品輸出與成功輸出長得一模一樣（錯誤只在 stderr），而 `verify` 只在**完全無錨點**時才判 UNVERIFIABLE，少一條時什麼都不說＝該 repo 從此沒有 checksum。unborn HEAD 尤其惡性：`rev-parse HEAD` 會把**字面字串 `HEAD`** 印到 stdout 且 rc=0，寫進錨點後 `HEAD^{commit}` 每次都解析成當下 HEAD → **永久判 FRESH**（實測前進兩顆 commit 仍 FRESH），比沒有錨點更糟。**驗證端配套用 canonical OID 比對**（`resolved != sha` → BAD-ANCHOR），擋掉 `HEAD`／branch 名／短 sha；**判準不得硬編雜湊長度**——SHA-1 是 40 hex、SHA-256 是 64 hex，寫死 40 會把整個 sha256 repo 判成壞錨點，故另立 sha256 正常路徑守門。`survey` 是 W1／R1 單一入口（**清理必須先於任何 archive 衍生輸出**，否則剛好過 TTL 的 predecessor 會被先印後刪、讀取端拿到 dangling path；worklines 上限只截顯示並印略過筆數，不靜默截斷；清理斷言用**獨立 fixture**，沿用 `list` 已清過的目錄會變空條件。awk 聚合兩個坑：`$2 > k[$1]` 在 k 未初始化時是數值比較，key `00000000000000` 於是永不被採用；**tab 是 IFS whitespace**，空欄位會被 `read` 吃掉而讓後續欄位整批推移，故空值以 `-` 佔位）。archive 檔名身分解析抽成兩個消費端共用的 parser（**候選 slug 不可壓成單一值**，key 逐候選各自成立；**frontmatter `slug:` 是否決權不是索引**——與候選相符則升為首選以消歧，全不符則以檔名歸戶並標「find-predecessor 不會採用」，讓本來完全隱形的殘檔可見，正反兩面都有斷言，只釘一面的話「改用 frontmatter 當索引」照樣全綠）。`anchors` 記 `--show-toplevel` 絕對路徑——相對輸入原樣寫進錨點會讓跨 session 的 verify 對到**別的 repo**、還誤報成 DIVERGED；空白檢查對解析後的 toplevel 而非原輸入。`find-predecessor` 依 slug 精確定位前一份,**active 與 archive 判準不同**——active 比完整檔名(一併剝前綴會讓 `20260804-foo` 這種合法 slug 失配、判成首輪後整檔覆寫)、archive 才剝歸檔前綴且取**時戳數值**最大者(靠 glob 字典序會選到同日的 legacy 舊檔);檔內 `slug:` 存在時須相符、無該欄位者放行(向後相容)。不可退回 glob——`archive/*-<slug>.md` 的 `*` 吃得下中間的工作線名,查 `foo` 會撈到 `bar-foo`;**fixture 的 `bar-foo` 時戳必須最新**,否則 glob 實作的 `tail -1` 也剛好答對、斷言等於虛設)/ **session-pull-check.sh（SessionStart hook）**（**落後偵測與 base 建議都不得拿 repo-global `FETCH_HEAD` 的新鮮度替別的 remote 背書**——多 remote 時剛 fetch 過 `other`，真正落後的 clone 會完全不出聲；單 remote 才保留快取快路徑。fetch 真的失敗時 base 建議仍要出、但須帶「可能已過期」警語，該臂另立守門否則 `stale_note` 會變沒有覆蓋的死碼） / **codex-exec-review** / **crawl-quality-scan**，protection 判定用 gh stub、codex 用會模擬 clap argv 拒絕的 stub、crawl-quality-scan 用 python fixture 對準扣分表）、`ensure-rc-source.sh`（含**舊 alias 清理**——`brewup`/`sysup` 遷成 function 後必須從 rc 刪行而非 `unalias`；其他 alias 與非 alias 內容不得誤刪、清完重跑須幂等，且**「行數減幅 > 2 即原封不動」那道前提檢查另立斷言**，否則整段防護可被刪光而全綠）/ **`ensure-codex-skills.sh`** / **`ensure-codex-guidance.sh`** / **`ensure-lftprc.sh`**（含 `.lftprc.local` 不覆寫、早退路徑仍補檔）幂等測試、**`brewfix.sh`**（macOS-only guard／未知參數不得被當成 `--fix`／唯讀模式絕不刪除／`--fix` 清完複驗／**無卡死 process 時不得驚動 `killall syspolicyd`**／lsof 條目正常的同一 process 不得誤判為卡死／**破壞性刪除作用域限 Caskroom 內**，Caskroom 外的 `*.upgrading` 不得被碰；ps/lsof/killall/sudo 皆以 stub 注入）、`sysup.sh` 平台 guard、**dotfiles-sync 遠端回報段**（ssh 失敗與無告知時都不可吞掉主機結果）、`add-new-host.sh --dry-run` 煙霧測試、**`migrate-github-remotes.sh`**（身分驗證是硬前提——認到錯帳號即 STOP 且零 mutation；dry-run 零 mutation；三種換寫正確且非 GitHub remote 不得被碰；**非 `origin` 的 remote 同樣換寫**——手貼迴圈只掃 origin，實跑工作 mac 時有兩條 `fork` remote 會被留下；`insteadOf` 只清 github-work 那幾條、不波及使用者其他改寫規則；`--apply` 幂等；未知選項 exit 2 而非當成路徑。`GIT_CONFIG_GLOBAL` 隔離，絕不碰真的 `~/.gitconfig`）。改動 `scripts/`、setup 腳本或 skill 腳本後必跑；**改動任何 `.md` 的節名或搬動權威內容後同樣要跑**（交叉引用 gate 掃全 repo 的 md，改節名等於讓指向它的指標斷掉）。deep-review 時 `verify-tests.sh` 對本 repo 判 SKIP（無 uv/bun 測試框架）——真測試就是本指令，每輪修復後手動跑、以 **exit code** 判綠紅（pipeline 接 tail 會吃掉失敗）。
- Skill 行為測試（弱模型 evals）：`claude/evals/README.md`（沙盒建置 + 手動 runner），各 skill 情境在其目錄的 `evals.md`。

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
