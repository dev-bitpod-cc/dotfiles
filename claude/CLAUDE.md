# Behavior Rules（行為規則）

> Hard constraints. Violations have real consequences.

## Repo contract precedence

在任何 repo 開工前，先看根目錄有無 `AGENTS.md`（其次 `CLAUDE.md`）——**有就以它為該 repo 的慣例權威**。
下面這個 kernel 是你在**任何** repo 的行為下限：safety floor 不因任何 repo 的慣例而放寬（更嚴的往上疊），
fallback conventions 則由該 repo 自己的規定勝出。Repo 沒有契約檔時，這裡就是全部。

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

## Think Before Implementing

- Ambiguous task: NEVER silently pick one reading. List the plausible interpretations and let the user choose before writing anything.（自主執行時的 fallback 見本節下方 `Uncertain?` 條目）
- Non-trivial task: state the success criteria before starting; if the repo has `STATUS.md`, record Context／Goal／AC／Constraints in its active section（儀式面用 `/project spec`）.
- 工作過程中做出**關鍵取捨／放棄一條路（死路）／完成里程碑**時，先判 adoption：`.doc-governance.json` 與 `scripts/doc-governance.py` 兩者皆有才是 adopted，當下用 repo-local `record-path` 決定 event-time history shard 並追加 record；兩者皆無才走 legacy；只存在一個＝BROKEN，停止且不回退 legacy。Do NOT defer these notes to ship time — context may be compacted before then.
- Uncertain?（含上條的 ambiguity）互動 session：stop and ask — do NOT assume just to keep momentum。自主執行（背景 turn、使用者無法即時回覆）：取最合理解讀繼續，but the assumption MUST land somewhere — 就地寫入 STATUS.md「進行中」（無 dossier 則在最終回報明列「本次假設」）並標示待使用者確認。**Irreversible or outward-facing actions still require asking — the autonomous fallback NEVER extends to them.**
- Bug fix: ALWAYS write a reproducing test FIRST, then fix. 無法可行地自動重現者（環境相依、一次性腳本、外部服務行為）→ 改記手動重現步驟與修後驗證方式（有 STATUS.md 寫進去、無則寫在回報裡）；「先重現、再修」的順序不變。

## PR / Git

- merge 的授權來源（補充 kernel 的 merge 條）：使用者明說 merge / bypass merge——**不論在哪一輪說的**，`/project log` 的引數或事後另說皆算。
- 使用者明說 merge 後的標準收尾：merge PR → 清 remote/本地 branch → 同步本地 default，**一路做完不再回問**。**壓不壓由說法決定、預設保留**（裸「merge」＝保留語意 commit）。說法表與完整序列見 `~/.claude/skills/project/references/ship-paths.md`「說法表」＋「Merge 最後一哩」（唯一權威，勿在此重述對照）。
- **說法授權的是「怎麼送」，never whether an unreviewed batch may ship.** `ship-state.sh` 印 `verdict: STOP`（含 `review-terminal:` 上一場審查未修完就終止）→ 停下處置，關鍵字不得覆蓋。
- **Solo repo is not a lighter process** — "It's just me" / "no protection anyway" is never a reason to relax the kernel's safety floor, the PR default, or explicit merge（後兩者是個人流程、不在契約裡；理由與完整條文見 `ship-paths.md` 檔首，勿在此重述）。
- 誤 commit 已落在 default branch 時的救援序列見 `~/.claude/skills/project/references/ship-paths.md`「Branch-first 與誤 commit 搬移」（唯一權威，本檔不重述）。**規則本體在 kernel**——它不隨 skill 是否載入而變（實測失效面：`claude/skills/handoff/evals.md` H6 首跑，同一輪 repo-a 的 commit 落在 main、repo-b 才開 branch，因為當時規則只存在於 `/project` 載入後才讀得到的檔案裡）。
- kernel 廣義 staging 禁令的**唯一例外**：`/deep-review` 的 **WIP snapshot**（`deep-review/SKILL.md` 明列，本地暫存、終態會 squash），它要的正是「使用者原始變更的完整快照」。**但執行前須確認 working tree 全屬本次工作**——混了他人 in-flight 變更就停下問，別指望 snapshot 之後再拆（squash 終態一樣會把它送進 PR）。

## Third-party Review Verification

When the user pastes third-party review findings, read the source code and verify each finding independently — do not just agree. Judge each as true positive / false positive / context-dependent. Assume neither correct nor wrong by default. The user won't reveal the source or their own opinion, and you should not ask.

### 觸發詞「由 codex 進行第三方審查」（變體：「交給 codex 審查」「codex 第三方」）

載入 `deep-review` skill，完整依其 Codex protocol 與 anchor 腳本決定 range；**NEVER 猜 `HEAD~1`、
NEVER 呼叫 `codex:rescue`**。收到 findings 後先逐條驗證；最近一次流程帶 `autofix` 才自動修復，
否則列出判定等使用者決定。完整 range 恢復與已 merge 分流在該 skill，勿在 always-on 複製。

---

# Code Conventions（程式碼慣例）

## 已知地雷

> 只留動手當下需要的「觸發形狀 → 正解」；事故、反例與鑑別序列見
> `~/.dotfiles/claude/known-hazards.md`，命中時再讀。

- Shell 變數緊接全形標點時一律寫 `${var}`；否則全形字元可能被吞進變數名。
- 寫 Markdown／prose 的 heredoc 一律用 quoted delimiter（`<<'EOF'`）；變數改走 argv／environment。
- `gh * --body`／release notes／commit message 不把 prose 放進 shell 雙引號；用 `--body-file`／`-F`。
- `printf` 的 format 必須是字面常數：`printf '%s\n' "$data"`，NEVER `printf "$data"`。
- `sd` replacement 含 `$` 會被當 capture group；改用可保證字面的編輯方式。
- macOS 腳本只用 POSIX 確定子集；量 bytes 明寫 `LC_ALL=C`，需要 GNU 行為就顯式檢查工具。不要假設有 `timeout`／`gtimeout`。
- `pipefail` 下不要 `printf "$big" | grep -q`；存在性檢查用 herestring，測試命中點放輸入前段。
- 平行任務逐 PID `wait` 並驗產出完整性；裸 `wait` 會吞失敗，bash 3.2 也沒有 associative array。
- `grep -c ... || echo 0` 會得到雙 `0`；用 `n=$(grep -c ...) || n=0`。數值 command substitution 失敗先轉成可辨識 sentinel，再做算術。
- cask 卡在 `Linking Binary` 時直接跑 `brewfix` 診斷；只有 `brewfix --fix` 會修改。
- 腳本內 `git pull` 後若自身 checksum 改變，必須 `exec` 新版並設迴圈防護；呼叫端可把 pull 拆成前置指令。
- 在 worktree 驗自家 skill 時一律用該 worktree 絕對路徑；`~/.claude/skills`／`~/.codex/skills` 仍可能指向主 checkout。

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
- **ship 單一流程**：Claude 的 `/project log` 是 pressure-tested 的送出路徑（branch-first／protection／dossier 蒸餾），其「說法表」是**授權判定的唯一權威**——kernel 指向它，兩邊因此不會對同一句話給出不同答案。Codex 拿到授權時重用同一套狀態、保護與 mutation 腳本，不另寫一套近似流程；repo 沒有這套流程時，兩者都停在 feature branch 的 commit。
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
