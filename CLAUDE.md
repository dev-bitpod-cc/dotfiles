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

<!-- agent-contract:route:start v1 -->
## 文檔檢索路由

查 repo 的決策、死路、里程碑、規範、plan、skill reference 或 eval 時，先執行
`scripts/doc-governance.py find '<自然語言問題或 stable ID>'`；不要先整批讀 archive，也不要把人工 pointer
當成可檢索性的代理。寫入與生命週期規則見 `docs/document-governance.md`。
<!-- agent-contract:route:end -->

## 快速安裝

- **macOS 新機**：`curl -fsSL dot.bitpod.cc | sh`（Xcode CLT → clone → setup）
- **macOS 已有 repo**：`./setup-mac-env.sh`
- **macOS 系統偏好**：`./write-mac-defaults.sh`（選用，獨立執行）
- **Linux Ubuntu**：`./setup-linux-env.sh`

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

## 延遲載入的 repo facts

工具、平台、更新同步、SSH 架構、inventory、內網工具與 runtime 詳情見 `docs/repo-guide.md`。
