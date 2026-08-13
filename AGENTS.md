# Agent Contract

這份檔案是本 repo 對**任何** agent（Claude Code / Codex / 其他）的行為契約。Clone 下來就生效，
不需要安裝任何工具，也不依賴任何人的個人設定或 skill。

分兩層：**Safety floor** 是你在任何 repo 的行為下限，不因任何 repo 的慣例而放寬（更嚴的規定往上疊）；
**Fallback conventions** 則是「這個 repo 沒有自己的規定時才適用」——它有，就照它的。
分界判準是**錯了會產出什麼**：多開一條本地 branch 完全可逆、不留錯誤產物；用錯 commit 格式
則直接產出必須重寫的東西。前者是安全，後者是慣例。

<!-- agent-contract:kernel:start v1 -->
## Kernel

### Safety floor — never relaxed by any repo

- **NEVER commit onto the default branch** (`main`/`master`). If `HEAD` is on it — or detached — create a feature branch first: `git switch -c <type>/<slug>`. This holds regardless of protection state and regardless of which tooling is loaded.
- **NEVER push without explicit user authorization.** An ordinary request to implement, fix, or commit does not authorize pushing. A direct instruction to ship, push, or open a PR—or an affirmative answer in a shipping workflow—does authorize pushing the current feature branch and opening or updating its PR after the ship summary. It never authorizes pushing the default branch.
- **NEVER merge on your own.** "push" or "open a PR" alone does NOT include merge. Only an explicit merge instruction does.
- **NEVER `git add -A` / `git add .` / `commit -a`.** Stage explicit paths.
- **If the working tree holds changes you did not make, STOP and report before staging, committing, or building on top of them.** Whether two sessions may share one tree is a dispatch decision made above you — never resolve it locally by guessing which changes are yours. Once authorized, explicit paths are still whole-file: stage verified hunks with `git add -p`.
- **Inspect `git diff --cached` before every commit.** After splitting a mixed file, verify from a clean clone — `git clone --no-local <repo> <tmpdir>`. "I checked the working tree" is not evidence.

### Fallback conventions — this repo's own convention wins where it has one

- Conventional Commits: `<type>: <short desc>`, type is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. **If this repo mandates another commit format, follow the repo.**
- Record non-obvious trade-offs, rejected alternatives, and dead ends **where this repo already keeps them**. Skip whenever the diff alone recovers the rationale — a rejected path leaves no trace in the diff, an added gate does. **If the repo has no such store, do NOT create one; list them in your report instead.**
<!-- agent-contract:kernel:end -->

<!-- agent-contract:portable:start v1 -->
## Documentation authority

衝突時照這張表判，不要憑「哪份看起來比較新」。

| Kind of fact | Authority | On conflict |
|---|---|---|
| Agent behaviour, git discipline | this file's **Kernel** | Nothing may relax the safety floor. A repo may only be **stricter** |
| Repo conventions, architecture, commands | `CLAUDE.md` / `AGENTS.md`（root，其次最接近改動位置的那份） | 最近者勝 |
| Project state, decisions, dead ends, debt | `STATUS.md`（若有） | |
| Install & usage for humans | `README.md` | |
| Dated design docs / discussion snapshots | `docs/plans/*.md`（若有） | **Write-once**：frozen at publication，被更新的權威取代，但不就地改寫 |
| Handover | `docs/transfer.md`（若有） | 移交期間才存在 |
| **Generated / derived docs**（codegen、API dump、LLM 產的 repo map／wiki） | **none — descriptive only** | 見下 |

**Generated docs never win.** 與上表任一列衝突時，權威檔為準、generated 那份就是 stale——
**重新生成它，NEVER 改 generated 檔來贏一場爭論**。每個 generated artifact 都必須寫明自己的
重建指令；沒有重建指令的一律當作不可信。

**Rules are stated in exactly one place.** If a rule is needed elsewhere, point at it; do not restate it.
**The sole exception is a rule that must be in always-on context AND whose readers load different files**
（Claude 自動載入 `CLAUDE.md`、Codex 讀 `AGENTS.md`）—— a pointer cannot work there, because a rule that
was never loaded never fires. Keep such replicas short, and verify them by machine check where the cost of
drift is real; the kernel block is the managed instance of this pattern. Everything else points.

## Working discipline

- **Bug fix: write a reproducing test first, then fix.** 無法可行地自動重現者（環境相依、外部服務行為）
  改記手動重現步驟與修後驗證方式；「先重現、再修」的順序不變。
- **Ambiguous task: NEVER silently pick one reading.** 列出可能的解讀讓人選，不要為了維持動能而假設。
- **Irreversible or outward-facing actions require explicit authorization**——push、發信、對外送出、刪除。
  當前請求已明說該動作時就是授權，不要再問一次；未明說才停下確認。
- **Solo repo is not a lighter process.**「只有我一個人」「反正也沒保護」都不是放寬上述任何一條的理由。
- 為什麼 kernel 要求 clean clone 驗證：混檔誤收**在磁碟上恆綠**，只有乾淨 clone 看得見；
  人工看 staged diff 已實證失敗過三次，不能取代它。
<!-- agent-contract:portable:end -->

## Repo specifics

<!-- 安裝到其他 repo 時，這一節整段重填；上面兩個 block 由工具維護，不要手改 -->

- **測試**：`./tests/run.sh`，**以 exit code 判綠紅**（接 pipeline 會吃掉失敗）。
  改動 `scripts/`、setup 腳本、skill 腳本後必跑；改動任何 `.md` 的節名或搬動權威內容後同樣要跑
  （交叉引用 gate 掃全 repo 的 md）。
  這三行在 root `CLAUDE.md`「測試」另有一份——**這是上面 always-on 例外條款的實例**：
  Codex 只讀本檔、Claude 只自動載入 `CLAUDE.md`，指標對兩者其中之一必然落空。
  各 gate 的判準、反例與設計理由（**放寬判準前必讀**）見 `docs/testing-contract.md`。
- **本 repo 的額外約束**：`~/.dotfiles` 同時是多台機器的部署來源，`scripts/` 底下的改動會經
  `dotsync` / `brewup` 散佈出去。散佈類變更的前提是**變更已進 `origin/main`**——本地 branch 未 push
  時散佈等於空轉。
- 更詳細的專案事實（工具、腳本清單、SSH 架構、主機清單）見 root `CLAUDE.md`。
