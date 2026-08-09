# Behavior Rules（行為規則）

> Hard constraints. Violations have real consequences.

## Think Before Implementing

- Ambiguous task: NEVER silently pick one reading. List the plausible interpretations and let the user choose before writing anything.（自主執行時的 fallback 見下方「Uncertain?」條）
- Non-trivial task: state the success criteria (how "done" is verified) before starting; if the repo has a STATUS.md (dossier), record the spec (Context/Goal/AC/Constraints) into its「進行中」section（儀式面用 `/project spec`）.
- 工作過程中做出**關鍵取捨／放棄一條路（死路）／踩到非顯而易見的坑**時，若 repo 有 STATUS.md → **當下**就地寫入對應章節（working tree 即可、不 commit，收尾由 `/project log` 一起送出）。Do NOT defer dossier notes to ship time — context may be compacted before then.
- Uncertain?（含上條的 ambiguity）互動 session：stop and ask — do NOT assume just to keep momentum。自主執行（背景 turn、使用者無法即時回覆）：取最合理解讀繼續，but the assumption MUST land somewhere — 就地寫入 STATUS.md「進行中」（無 dossier 則在最終回報明列「本次假設」）並標示待使用者確認。**Irreversible or outward-facing actions still require asking — the autonomous fallback NEVER extends to them.**
- Bug fix: ALWAYS write a reproducing test FIRST, then fix. 無法可行地自動重現者（環境相依、一次性腳本、外部服務行為）→ 改記手動重現步驟與修後驗證方式（有 STATUS.md 寫進去、無則寫在回報裡）；「先重現、再修」的順序不變。

## PR / Git

- **NEVER merge on your own** — only when the user explicitly says merge / bypass merge（不論在哪一輪說的，`/project log` 的引數或事後另說皆算）。"push" or "open a PR" alone does NOT include merge.
- 使用者明說 merge 後的標準收尾：merge PR → 清 remote/本地 branch → 同步本地 default，**一路做完不再回問**。**壓不壓由說法決定、預設保留**（裸「merge」＝保留語意 commit）。說法表與完整序列見 `~/.claude/skills/project/references/ship-paths.md`「說法表」＋「Merge 最後一哩」（唯一權威，勿在此重述對照）。
- **說法授權的是「怎麼送」，never whether an unreviewed batch may ship.** `ship-state.sh` 印 `verdict: STOP`（含 `review-terminal:` 上一場審查未修完就終止）→ 停下處置，關鍵字不得覆蓋。
- **Solo repo is not a lighter process** — "It's just me" / "no protection anyway" is never a reason to relax branch-first, the PR default, or explicit merge（理由與完整條文見 `ship-paths.md` 檔首，勿在此重述）。
- **NEVER commit onto the default branch** (`main`/`master`). If `HEAD` is on it — or detached — create a feature branch **before** committing: `git switch -c <type>/<slug>`. This holds regardless of protection state and **regardless of whether any skill is loaded**（實測失效面：`claude/skills/handoff/evals.md` H6 首跑，同一輪 repo-a 的 commit 落在 main、repo-b 才開 branch——當時的規則只存在於 `/project` 載入後才讀得到的檔案裡）。誤 commit 已發生時的救援序列見 `~/.claude/skills/project/references/ship-paths.md`「Branch-first 與誤 commit 搬移」（唯一權威，本檔不重述）。
- **NEVER push on your own** — after finishing an issue implementation or review fixes, commit and STOP; wait for the user's next instruction.
- **NEVER `git add -A` / `git add .` / `commit -a`**——顯式路徑 stage，且**顯式路徑仍是整檔**：同一檔混了他人 session 的區段時改用 `add -p` 只 stage 驗過的 hunk（或把他人區段移出、commit 完最後放回），commit 前看 `git diff --cached`。三次誤收皆在磁碟上恆綠，**只有乾淨 clone 看得見**（`git clone --no-local <repo> <tmpdir>`）——人工看 staged diff 已實證失敗三次，不能取代它。
  - 唯一例外：`/deep-review` 的 **WIP snapshot**（`deep-review/SKILL.md` 明列，本地暫存、終態會 squash），它要的正是「使用者原始變更的完整快照」。**但執行前須確認 working tree 全屬本次工作**——混了他人 in-flight 變更就停下問，別指望 snapshot 之後再拆（squash 終態一樣會把它送進 PR）。
- Conventional Commits: `<type>: <short desc>`. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.

## Third-party Review Verification

When the user pastes third-party review findings, read the source code and verify each finding independently — do not just agree. Judge each as true positive / false positive / context-dependent. Assume neither correct nor wrong by default. The user won't reveal the source or their own opinion, and you should not ask.

### 觸發詞「由 codex 進行第三方審查」（變體：「交給 codex 審查」「codex 第三方」）

載入 `deep-review` skill，執行方式一律依其「**Codex 呼叫協議**」節（唯一權威——呼叫指令、prompt 限制、exit 契約失敗處理都以該節為準，勿憑記憶重組、本檔不重述）；**不要**呼叫 `codex:rescue`（plugin broker 路徑會靜默卡死，理由見該節）。本觸發的專屬規則：

- repo 路徑 + commit range 取最近一次 `/deep-review` 輸出的「第三方審查資訊」區塊，range 直接沿用其 `base..head`（base 已錨定）；即使變更已 push（`origin/main..HEAD` 為空）也**不要**退化成 `HEAD~1..HEAD`——那會漏審變更集前段。報告未記錄 base（如新 session）→ 先跑 `~/.claude/skills/deep-review/scripts/review-anchor.sh show --repo <repo>`（anchor 檔在即得錨定 base，跨 session 有效）；anchor 也無 → **先 `git -C <repo> fetch origin`**（下面兩個分支都讀本地 remote-tracking ref，過期會讓 base 偏舊、審查範圍虛胖），再依 HEAD 是否仍領先 default 分流：
  - **仍領先**（`origin/<default>..HEAD` 非空）→ 取 `git -C <repo> merge-base origin/<default> HEAD` 當下界審整條 branch（squash 只壓 review 產生的 commit、**語意 commit 會留在 branch 上**，故 branch 全長才等於審查範圍）。
  - **已併入 default**（該 range 為空）→ **merge-base 會退化成 HEAD、range 為空**，此時沒有可自動推導的下界：**停下問使用者要審哪個範圍**（列出近期 merge commit／PR 供選）。**NEVER 退回 `HEAD~1..HEAD`** —— 那正是本條開頭要防的漏審；`HEAD~1..HEAD` 只在確認整批就只有一顆 commit 時才成立。
- 收到 findings 後的處理判準：**最近一次 `/deep-review` 帶 `autofix`** → 驗證後自動修復並 commit；否則、或無法確定當時是否帶 autofix（如新 session）→ 列出 findings 等使用者決定。

---

# Code Conventions（程式碼慣例）

## 已知地雷

- **shell 訊息裡 `$var` 緊接全形標點** → bash 會把全形字元併入變數名（`"（exit=$rc）"` → `set -u` 下噴 `rc）: unbound variable`）。繁中訊息幾乎必踩，且**只在錯誤路徑觸發**、正常測試照樣全綠。一律寫 `${var}`。（dotfiles 有 `tests/run.sh` 第 1b 節 gate 擋，其他 repo 沒有）
- **不帶引號的 heredoc（`<<EOF`）內含反引號 → bash 做命令替換，指令真的被執行**。2026-08-07 實地：用 `python3 - <<PY` 產生 eval prompt，文字裡有 `` `git push` `` 與 `` `gh pr` `` 說明用的反引號，結果 **`git push` 真的推了一條 branch 上 GitHub**、`gh pr` 的說明文字被塞進產出的檔案，而變數展開位置留下空白。**寫 Markdown/prose 進檔案時幾乎必踩**——反引號是行內 code 的標準寫法。一律用 `<<'EOF'`（quoted delimiter，全文字面），需要帶入變數就走 `os.environ` / `sys.argv`，不要靠 shell 內插。⚠️ **範圍僅限「反引號寫在 body 字面」**：`$(cat 某檔)` 注入進來的內容**不會**被執行——命令替換的結果不重新掃描（2026-08-07 實測；當時誤把「用 heredoc 灌一個含反引號的檔案」也當成同一個雷，據此改了三處程式碼還把錯誤結論寫進 commit/PR/dossier 四處）。**看到 heredoc 就警覺是對的，但要分清楚反引號是在源碼裡還是在被注入的資料裡。**（dotfiles 有 `tests/run.sh` 第 1c 節 gate 擋，掃描器 `tests/heredoc-gate.awk`——判準即「delimiter 未加引號 + body 字面含反引號」，會追蹤 quoted heredoc 的進出、排除 `<<<` 與註解行，並有 GREEN fixture 釘住「`$(cat …)` 不得誤報」；其他 repo 沒有）
- **同根因的第二個觸發點：`gh pr create --body "…"` 的內文含反引號**。根因是同一條——**shell 雙引號語境內的反引號一律是命令替換**，heredoc 只是其中一種語境。而 PR 內文幾乎必然寫到 `` `檔名` ``／`` `指令` ``，`--body` 的值又正好在雙引號裡，等於**每次 ship 都會走一次的路徑**。後果比 heredoc 版更難察覺：指令照樣執行（可能又是一個 `git push`），替換後的空白直接**送上 GitHub 成為 PR 內文**，本地終端看不出異狀，要點開 PR 才發現內文缺字。同型的還有 `gh issue create --body`、`gh release create --notes`、`git commit -m "…"`。一律改用 **`--body-file <檔>`**（檔案內容原樣送出，完全不經 shell；`--body-file -` 讀 stdin），commit 訊息則用 `-F <檔>`。真要行內給值就寫 `--body "$(cat <<'EOF' … EOF)"`（quoted delimiter 讓 heredoc 全文字面，命令替換只負責搬運）。無自動 gate 可擋。
- **`sd` 的替換字串含 shell 變數** → `$job` 會被當成 capture group 展開為空，靜默毀損程式碼且過得了 `bash -n` 與 shellcheck。含 `$` 的替換改用 Edit 或 python 字面替換
- **macOS 內建 CLI 是凍結的舊版**（Apple 因 GPLv3 停更：bash 3.2、rsync 已換自寫 openrsync、BSD awk 的 `length` 不分 locale 一律數 **bytes**）→ 分兩層應對：互動/運維工具用 brew 新版（rsync 已入 setup-mac-env.sh）；**腳本/tests 只用 POSIX 確定性子集**（量 bytes 明寫 `LC_ALL=C`，讓 BSD/GNU 結果一致），需要 GNU 行為就顯式呼叫 `gawk` 並 `command -v` 檢查——**勿靠 gnubin PATH shadowing**（隱形環境依賴，shellcheck 抓不到、換一台機器就變行為）。**另一類是「根本不存在」而非「版本舊」**：`timeout` / `gtimeout` 在 macOS 皆無（coreutils 才有，2026-08-09 實測兩者都空）。危險不在缺工具本身，而在 **`command not found` 是 exit 127**——測試裡包一層 `timeout` 就變成整段沒跑卻只回一個 127，被 grep 過濾後**看起來像通過**（當天據此誤判「某條斷言是虛設的」，實際那次根本沒執行）。要限時就自己封頂（讓受測對象自然收斂），不要引入 `timeout`
- **`set -o pipefail` 下的 `printf "$big" | grep -q`** → `grep -q` 命中即退出，上游 printf 在**大輸入**下寫不完就吃 `SIGPIPE(141)`，pipefail 讓整條判偽 → 條件式（尤其前面有 `!`）結論反轉。**小輸入不發作**（printf 一次寫得完），故潛伏很久才在某個大檔上突然爆。存在性比對一律改 **herestring**：`grep -q PATTERN <<< "$big"`。兩處實地踩過：krepo `scripts/backup/lib/dest_r2.sh`（零備份保底清單比對）、dotfiles `ship-state.sh`（dossier 簽章與 Session Log 偵測——115KB STATUS.md 被誤報「簽章不符」，該 flag 的處置是「停下、勿當 dossier 改」，等於整份檔案被拒絕處理）。**寫守門測試時命中點必須放輸入前段**——放檔尾則 printf 早已寫完、SIGPIPE 不觸發，斷言形同虛設（實測：檔尾版突變仍全綠）。無自動 gate 可擋，靠這條記憶。
- **`n=$(grep -c PAT f || echo 0)` 在找不到時產生雙行 `0\n0`**——`grep -c` 找不到時**本來就會印 `0`**、同時 exit 1，於是 `|| echo 0` 再補一個，command substitution 收到兩行。變數帶了換行後，**後續 `printf` 的參數會整批推移位**：格式字串被重複套用、欄位錯格、輸出看起來像被截斷，而**全程沒有任何錯誤訊息**。2026-08-07 實地：巡檢 14 台 rc 狀態的腳本，Linux 10 台因為 `alias sysup` 確實存在（grep 命中、exit 0）而正常，macOS 4 台找不到就觸發，**同一支腳本只有部分主機的輸出壞掉**，第一眼會誤判成「遠端環境差異」而去查錯方向。正確寫法是讓 substitution 失敗才賦值、不讓兩個 `0` 疊加：`n=$(grep -c PAT f) || n=0`（`grep -c` 的 `0` 本身就是要的答案）。同型陷阱：任何「失敗時仍會輸出有效值」的指令都不該用 `|| echo <fallback>` 兜底。無自動 gate 可擋。
  - **同族的第二種形狀：substitution 失敗回「空字串」，而 `$(( ))` 把空變數當 0**。`bytes=$(wc -c < 讀不到的檔)` → `bytes=""` → `$((hdr + bytes))` **不是語法錯誤、直接算成 `hdr`**，於是「產出完整性」這類自我檢查會自己通過。2026-08-09 實地：`ensure-ssh-config.sh` 的 bytes 比對因此放行了一個只有標頭的殘缺 ssh config 並覆蓋原檔（守門測試當場抓到）。**判準：凡把 command substitution 的結果餵進 `$(( ))` 或數值比較，都要先讓失敗變成可辨識的值**（`x=$(...) || x=-1` 再加 `[ "$x" -lt 0 ]` 守門），不能倚賴「失敗會是 0」。
- **cask 升版卡在 `Linking Binary` → 該路徑之後永久 hang**（實地三次：codex 271MB，`codex --version` 無限 hang、CPU 0%、無任何輸出）。**觸發者是 brew 自己，不是你也不是 shell**：codex cask 帶 `generate_completions_from_executable`（`brew info --cask codex` 的 Artifacts 段可見），其 `install_phase` 對 **bash/zsh/fish 各 exec 一次**剛解壓、仍帶 `com.apple.quarantine` 的 binary 來產生 completion。首次 exec quarantined binary → 進入 Gatekeeper 首次核可流程。畫面停在 `Linking Binary` 是因為那是**前一個** artifact 的訊息；brew 的 `rescue => e` 只攔例外、攔不住 hang，所以 brew 自己也不會跳過。**不是每次發作**——只在該 cask 實際有新版時走這條（`Caskroom/<cask>/<old>.upgrading` 殘留＝那次被中斷的證據）。
  **確切觸發條件未知，別再花時間重測**。已知：(a) 對話框「〈名稱〉是一個從網際網路下載的 App。確定要打開嗎？」確實會出現並等人按——2026-08-07 經 SSH 跑 `allup` 時實地確認（Jump Desktop 連進 console 才看到，SSH session 結構上看不到 GUI 對話框）；(b) **無可見對話框也會卡**——在本機 console 開 terminal 跑 `brewup` 也遇過卡在 `Linking Binary`、對彈窗無印象。故 **`ssh` 不是必要條件，「去 console 按掉對話框」也不是可靠處置**。
  **2026-08-07 的負面結果（省下下次的重測）**：事後想重現，把**同一份** binary 複製到全新路徑、在 SSH session 下帶 quarantine 立即執行——**3 秒正常完成，完全不卡**。以此逐一排除：SSH session ✗、首次評估（全新路徑）✗、quarantine 存在且無 `0x0040` ✗、檔案大小 271MB ✗、notarization 與簽章差異 ✗（同機的 agy 162MB 各項條件相同卻從不卡）。合理解釋是 **Gatekeeper 的「成功評估結果」以 cdhash（內容）為 key 快取，而「卡死的 pending 記錄」才以路徑為 key**——兩者不衝突，但意味著**同版本內容事後永遠重現不了**，要重現只能等該 cask 真正出新版。


  中斷後進入第二段病灶：syspolicyd 的 Gatekeeper 掃描記錄**以「完整路徑」為 key**，該路徑上的記錄一旦卡在未完成狀態，之後每次 exec 都在 kernel 層等一個永遠不回來的結果（該路徑在 syspolicyd log 中全程無任何評估紀錄，對照組則有完整 `Updating cached scan`）。鑑別：`sample <pid>` 卡在 `_dyld_start + 0`、`lsof -p <pid>` 只有 dyld + binary 本身、**一個 dylib 都沒載入**（＝程式碼一行未跑，與 config/auth/sqlite/網路全無關，`env -i` 也一樣卡）；**同目錄只換檔名就能跑 → 確認 key 是路徑**（換 inode、`touch` 改 mtime 皆無效，別白費）。修法：**`brewfix`**（`scripts/brewfix.sh`；預設唯讀診斷，`brewfix --fix` 才動手：kill 卡死 process → `sudo killall syspolicyd` → 清 `*.upgrading` 殘留 → 複驗）。手動等價：`sudo killall syspolicyd`（launchd on-demand 重生，之後 `launchctl list` 顯示 `-  0` 是正常的）＋清 `Caskroom/<cask>/<old>.upgrading`（**`brew cleanup` 只清 cache 的 tar.gz、不碰它**）；`brew reinstall` 路徑不變、多半無效。
  **三條沒有用的路，別再走**：①「更新後先在終端手動跑一次讓它自然跑完」——brew 在你之前就 exec 過了；②`--no-quarantine`——**Homebrew 6.x 已移除該旗標**（install/upgrade 都拒絕，原始碼無此識別字），且原本就屬不必要的安全弱化；③ 期待 Homebrew 內建的核可繼承（`Quarantine.inherit_user_approval!`）幫忙——`cask/upgrade.rb` 兩處都是 `artifacts.grep(Artifact::App)`，**只服務 `.app` bundle**，binary cask 拿不到，所以 `USER_APPROVED_FLAG (0x0040)` 永遠不會被設上。**復原是實證有效的，預防手段目前都不是**——復發時直接 `brewfix` 即可，別再重查一遍。
- **腳本在自己內部 `git pull` → 這一輪跑的仍是舊版**。`git checkout` 是 **unlink + 新建**，正在執行的 bash 握著舊 inode，檔案被換掉也讀不到新內容 → **pull 進新版、卻用舊版跑完這一輪**。凡是「本次更新才加進 pull 後段」的動作全部延後一個週期才生效，**而且無聲**。2026-08-09 實地：`brewup.sh` 新增 ensure helper 區塊後，落後的機器必須跑兩次才部署到 helper（第一次跑舊版）；`allup` 會讓這件事在整個機隊同時發生。**修法：pull 後比對自身 checksum，變了就 `exec` 新版重跑，並用環境變數做迴圈防護**（`brewup.sh` 的 `BREWUP_REEXEC`）。**呼叫端的等價解法是把 pull 拆成獨立前置指令**（`git -C <repo> pull && bash <repo>/script.sh`）——那樣被呼叫的已經是新版；這個順序是**功能性的、不是排版**。⚠️ **分辨另一種失效**：若換檔方式是 `>` **原地截斷**（同 inode，如 `curl -o` 或 `cat >`），正在跑的 bash 會從舊 offset 讀到 EOF、**整支腳本靜默中止在中途**——症狀完全不同（不是跑到舊邏輯，是跑一半就沒了）。
- **在 worktree 改自家 skill 時，`~/.claude/skills` 仍指向主 checkout**（`ls -la ~/.claude/skills` → `~/.dotfiles/claude/skills`；`~/.codex/skills` 由 `ensure-codex-skills.sh` 建立，同一形狀）→ 任何走 `~/.claude/skills/...` 的路徑（skill body 自己寫的腳本路徑、eval、實際觸發）跑的都是**主 checkout 的舊版**，你在 worktree 改的新版根本沒被執行到。**失敗是靜默的**：測試照樣全綠，因為它測的是舊檔——與「只有乾淨 clone 看得見」的誤收同一類，人工看 diff 抓不到。實地：2026-08-06 於 worktree 修 ready4quit 的 `git-hygiene.sh`，eval 必須把腳本路徑手動覆寫成 **worktree 絕對路徑**才測到新版。**凡在 worktree 內驗證自家 skill，路徑一律用 worktree 絕對路徑，不要用 `~/.claude/skills/...`**（`tests/run.sh` 以 `$ROOT` 解析故不受影響，坑只在 skill body／eval／手動呼叫這三處）。

## 測試

- **何時需要**：新增業務邏輯、修 bug（先寫重現測試再修；無法可行自動重現的豁免見上方 Behavior Rules）、公開 API/函式
- **不需要**：設定檔、純 glue code、一次性腳本
- **檔案位置**：與原始碼同目錄或 `tests/`，依專案既有慣例
- **命名**：Python `test_*.py`，TypeScript `*.test.ts`

---

# Workflow（工作流）

## Package Management

- **JavaScript/TypeScript**: ALWAYS use `bun` (replaces `npm`/`npx`/`node`). init `bun init`｜add `bun add`｜run `bun run`｜test `bun test`｜global `bun install -g`
- **Python**: ALWAYS use `uv` (replaces `pip`/`python`/`venv`). init `uv init`｜add `uv add`｜run `uv run`｜test `uv run pytest`｜venv `uv venv`｜CLI `uv tool install`
- **適用範圍：新專案與自有專案。既有 repo 尊重其現有 lockfile 對應的工具**——`package-lock.json`/`pnpm-lock.yaml`/`yarn.lock` → npm/pnpm/yarn；`poetry.lock`/`Pipfile.lock` → poetry/pipenv。NEVER introduce a second package manager's lockfile into an existing repo.

## 跨 Repo 工作流

主 agent 是唯一擁有跨 repo 全局 context 的角色。觸發跨 repo skill（`/deep-review`、`/project log`）時，依 session 記憶列出 `(repo, 檔案數)` 清單讓使用者確認（ok / 只看 X / 還有 Y），**不掃描** `~/Projects/`。確認流程細節見各 skill 的 Step 0。context 被壓縮就以 pwd 的 repo 為底讓使用者補充；使用者指定的 repo 即使無 diff 也納入（檢查一致性）。

## 跨 Agent 工作分配（Claude Code / Codex 並用）

- **writer 不限**：一般實作、測試、除錯兩邊都可做，依當下工具與模型選，**不按目錄分**（「codex 只碰 `codex/`」向來只是慣例、非規則）。
- **ship 單一入口**：只有 Claude 的 `/project log` 是 pressure-tested 的送出路徑（branch-first／protection／dossier 蒸餾）。Codex 寫完 commit 並停，由 Claude 收尾。這是**現行 operational authority、非永久架構**——codex 端出現真實 shipping 需求 + RED 且能重用同一套 mutation 腳本時再重評。
- **review 刻意隔離**：同一變更的作者與 reviewer 用不同 agent。可共用＝repo 事實／程式碼／測試／機械腳本／最終決策；**不主動共用**＝嫌疑清單、上輪 findings、輪次、預期答案、作者的判斷路徑；可刻意不同＝兩邊 reviewer 的判準與 orchestration（各自有 eval oracle 即可）。**共用與獨立審查是張力**——共用越多判準，blind review 的價值越低。
- **One writer per work item.** Two agent sessions must NEVER edit the same working tree concurrently — use a separate worktree or clone. 這與上方 staging 紀律同源：並行編輯製造混檔，混檔製造誤收。

## 跨主機工作流（多主機開發；主機清單見 `~/.dotfiles/scripts/inventory.conf`，勿在此硬編清單——會漂移）

- **Git is the ONLY cross-host medium.** Machine-local state（`~/.claude/handoffs/`、memory/）does NOT travel between hosts.
- 跨主機要延續的工作狀態 → repo 的 `STATUS.md`「進行中」章節就地更新 + commit（WIP 走 feature branch）；push 由使用者確認——**未 push 其他主機不可見，須主動標示**。handoff 只服務同主機 /clear。
- 多主機共用的專案，project-type 事實優先寫 repo 檔案（CLAUDE.md/STATUS.md）而非 ~/.claude memory（memory 留給 user/feedback 型）。
- 開工前的 clone 落後偵測由 SessionStart hook（`session-pull-check.sh`）自動報；看到落後提醒先 pull。

## Skill 建立

- 建立或修改 skill 前，**必須先讀** `~/.dotfiles/claude/skill-building-guide.md`（含 Anthropic 官方 best-practices、TDD-for-skills 紀律測試、定向英文語言政策）
- 可搭配 `/skill-creator` plugin；現有 skill 位於 `~/.dotfiles/claude/skills/`

---

# 技能載入指標（Skill Pointers）

特定情境下，相關 SOP 已抽成 skill 按需載入。遇以下情境**主動載入對應 skill**（避免 silent miss）：

- 寫 **cron / 背景腳本（爬蟲/回補）/ pipeline** 的開始·完成·失敗 → `nc-notify`（必發通知；NC 不可用須靜默不影響主流程）
- 使用者要求**「寄信 / mail 給我」** → `send-mail`（收件人依 skill 內〈收件人解析〉優先序，勿用 `# userEmail` 推斷）
- 遇 **bug / 測試失敗 / 非預期行為** → `root-cause-first`（先 root cause 再修）
- 使用者要 **/clear 但後續工作延續**（「交接」「接續上次的工作」）→ `handoff`（resume 必先 verify 錨點；消費即歸檔；**同主機限定**——跨主機延續走 repo STATUS.md）
- 使用者要**移交專案給同事 / 換 owner**（「移交」「交接給同事」「請他接手」）→ **建議使用者執行** `/project transfer`（user-invoked only——該 skill 為 `disable-model-invocation`，勿嘗試以 Skill tool 載入；其 dossier 完整度檢查 + 移交指南、credentials 絕不進 git）
- 使用者說**「uap」「ship」「推上去」「提交送 PR」**（收尾送出語意）→ **建議使用者執行** `/project --merge`（一路做到 merge）或 `/project --pr`（開 PR 即止）——**兩者都零提問**；要走多遠不確定就建議裸 `/project`（會問一題）。說法表與 flag 對照見 `~/.claude/skills/project/references/ship-paths.md`（唯一權威，勿在此重述）。（user-invoked only，同上勿以 Skill tool 載入）
- 使用者說**「收尾」「sync 一下」「可以 quit 了嗎」「結束前檢查」**（結束 session 語意）→ **建議使用者執行** `/ready4quit`（user-invoked only，同上勿以 Skill tool 載入。它是 pre-quit flush：驗 git 殘留、flush memory、盤點背景/排程任務與 loose ends，**本身不 ship**——git 殘留仍導向上一條的 `/project`）

---

# 撰寫語言政策（Language Policy）

> Meta-rule：編輯本檔或任何 skill 時一律遵循。完整版見 `skill-building-guide.md`。

- 硬約束 / 否定句 / 紀律強制塊（Iron Law、rationalization table、red flags）→ **英文**
- 程序步驟 / 領域 SOP / 概念解說 → **繁中**
- 觸發詞 / description → **中英關鍵字並列**
- 面向使用者的輸出 → **繁中**

---

# 環境配置

## 可用工具

bun, node, uv, eza, bat, fd, rg, fzf, zoxide, jq, yq, delta, lazygit, dust, gh, httpie, lftp, shellcheck, sd, hyperfine, tokei, tldr, tmux, direnv, just, watchexec

## 工具安裝原則

需要 CLI 工具時，先 `command -v <tool>` 檢查，沒有就 `brew install`，直接使用。不要因為工具不在就繞路。僅限標準 CLI 工具，專案依賴走 uv/bun 管理。
