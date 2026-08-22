# Ship Paths — git/gh 指令細節

`workflow.md`「Log 模式」的 git/gh 實作參考：repo 解析、protection、branch-first、PR／push、PR body 與失敗處理。

> **Solo repo is not a lighter process.** One-person projects run the SAME shape as a protected-main team repo: branch → commits → review → PR → explicit merge. Never relax branch-first, the PR default, or the explicit-merge rule because "it's just me", "no one else will read this history", or "there's no protection to enforce it". 理由：repo 會移交、會加入新成員，使用者本人也會成為他人 repo 的成員——流程形狀一旦按「一人份」放寬，這些時刻就沒有秩序可交接，也養不出正式流程的手感。**這條只是防守既有規則被合理化侵蝕，不新增任何步驟。**

> **本檔通則**：下文所有 `origin` 為 canonical remote 的 **stand-in**——非 `origin` repo（如 fork 工作流）一律把 `origin` 讀作解析出的 remote（`git -C <repo> remote`：有 `origin` 用之、否則取第一個；fork 場景 push 目標與 PR/protection 查詢目標可能不同 remote，見 `log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」）。gh 指令多 repo 時用 `-R <owner/repo>` 或子 shell `cd` 綁定，勿靠 cwd 隱式解析。**host 假設 GitHub.com**（`gh` 走 authenticated default host、compare URL 用 `github.com`）；GHE / 自架需 `GH_HOST` + `host/owner/repo`，不在本 skill 自動處理範圍。

## 目錄
- [Repo / default branch 解析](#repo--default-branch-解析)
- [Bootstrap：全新空 repo 的第一次 ship](#bootstrap全新空-repo-的第一次-ship)
- [Branch protection 偵測](#branch-protection-偵測)
- [gh 帳號權限 vs git push 身分（身分分離）](#gh-帳號權限-vs-git-push-身分身分分離)
- [Branch-first 與誤 commit 搬移](#branch-first-與誤-commit-搬移)
- [PR 路徑](#pr-路徑)
- [直接 push 路徑](#直接-push-路徑)
- [送出前的 branch 內 squash](#送出前的-branch-內-squashstep-4-選了先-squash-再送出時)
- [Merge 最後一哩（使用者明說 merge 後）](#merge-最後一哩使用者明說-merge-後)
  - [說法表（唯一權威）](#說法表唯一權威skill-step-4-照此分派)
  - [merge 受阻時的分流](#merge-受阻時的分流先看狀態不做失敗就-retry)
- [PR title / body 模板](#pr-title--body-模板)
- [push 失敗處理](#push-失敗處理)

## Repo / default branch 解析

> 本節與下節〈Branch protection 偵測〉的邏輯已封裝於 `scripts/ship-state.sh`（Step 0/1 單次呼叫，以腳本為可執行權威）；以下逐條指令供除錯、或腳本不可用時的手動 fallback。

```bash
# owner/repo（多 repo：在該 repo 目錄下執行，勿靠 cwd 隱式解析）
repo_slug=$( (cd <repo> && gh repo view --json nameWithOwner -q .nameWithOwner) )    # 如 elandcomtw/krepo
# 或從 remote URL 推（gh 不可用時 fallback）：
git -C <repo> remote get-url origin

# default branch（remote HEAD）
git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null   # 如 origin/main → 取 basename main
# 失敗 fallback：(cd <repo> && gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
# 再 fallback：依序試 main / master（git rev-parse --verify origin/main）
```

## Bootstrap：全新空 repo 的第一次 ship

**唯一觸發來源**：`ship-state.sh` 印 `verdict: BOOTSTRAP`（腳本以 `git ls-remote --heads` **實測**遠端零 branch，不是推測）。任何其他來源——使用者說「這是新 repo」、上一輪對話的授權、你自己的推論——都**不構成** bootstrap。

為什麼此處是例外：遠端還沒有 default branch，**沒有 default 可保護、也沒有別人的工作可破壞**。而 GitHub 以**第一個被 push 的 branch** 為 default branch——此時照 branch-first 開 `feat/xxx` 再推，遠端 default 就變成 `feat/xxx`（事後只能人工進 repo settings 改）。故 bootstrap 這一次：branch-first 不適用，推本地 default 名建立 baseline。

```bash
# 1. 照抄 ship-state.sh 的 bootstrap-cmd（repo / remote / branch 已填好）
git -C <repo> push -u origin <local-default>
# 2. baseline 建立後重跑偵測：BOOTSTRAP 應已消失，protection / branch-first 回到正常判定
<project-scripts>/ship-state.sh <repo>
```

- **仍走 Step 4 硬 gate**：摘要須明列「此 push 將決定遠端 default branch = `<branch>`」再等確認。
- **The exemption covers exactly this one push — creating the baseline.** It expires the moment the baseline exists; every later commit goes through a feature branch, rules unchanged. The script stops printing the verdict on its own, so re-check it — never carry the exemption forward from memory or from an earlier turn's authorization.
- 拿到的是 `verdict: STOP`（遠端有 branch／`ls-remote` 失敗／detached HEAD）→ **NOT bootstrap**：照訊息處理（先 `git fetch`、修網路、或切到具名 branch），**絕不**改推 default branch。

## Branch protection 偵測

GitHub 有兩套保護：**classic branch protection** 與**新式 rulesets**，兩者都要查（只看 classic 會漏掉用 ruleset 的 repo）。

```bash
# 先取實際值代入——gh api 只替換 {owner}/{repo}/{branch}，**不認 {default}**；
# 且多 repo 時 {owner}/{repo} 依 cwd 解析會打到錯 repo，故顯式帶 owner/repo 與 default 名。
default=$(git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
[ -z "$default" ] && default=$(for b in main master; do git -C <repo> rev-parse --verify -q "origin/$b" >/dev/null && echo "$b" && break; done)   # symbolic-ref 失敗 → 實際試 origin/main、origin/master（不可留空，否則 endpoint 變 branches//protection；origin 為 canonical remote stand-in，見 `log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」）
default_enc=${default//\//%2F}   # default 名含 '/'（如 release/2026，少見）→ encode，否則 endpoint path 會被切錯段
repo_slug=$( (cd <repo> && gh repo view --json nameWithOwner -q .nameWithOwner) )                        # owner/repo（gh 無 -C，用子 shell cd）
# classic：未保護回 404 {"message":"Branch not protected"}；有保護回 200 JSON
classic=$(gh api "repos/$repo_slug/branches/$default_enc/protection" 2>&1)
classic_rc=$?
# ruleset：無規則回 []，有規則回非空陣列
rules=$(gh api "repos/$repo_slug/rules/branches/$default_enc" 2>/dev/null)
```

判定（依序）：
- classic exit 0（200）**或** `rules` 非 `[]` → **protected** → PR 路徑。
- classic 訊息含 `Branch not protected`（404）**且** `rules` == `[]` → **確定無保護** → 直接 push 路徑。
- 其他（403 無權限 / 網路 / 無 gh / 無法分辨）→ **未知 → 視為 protected**（Unknown = protected）。

> 注意：404「Branch not protected」是 GitHub 對「該分支無 classic 保護」的明確回應（即使你是 ADMIN 也是 404），**不是**權限錯誤——要靠訊息字串分辨，別只看 exit code。
> 額外訊號（輔助判斷團隊習慣，非決策依據）：repo 有 `.github/PULL_REQUEST_TEMPLATE*` 或 `CODEOWNERS` → 偏向 PR 流程。

## gh 帳號權限 vs git push 身分（身分分離）

protection classic 回 **`Not Found`**（非 `Branch not protected`）常代表 **gh 帳號對該 repo 沒有 admin/read-protection 權限**（GitHub 對非 admin 隱藏 protection 狀態），而**不是**「無保護」。此時 `gh repo view --json viewerPermission` 多半是 `READ`。

關鍵：**gh 帳號的權限 ≠ git push 用的身分**。git remote 走 SSH（如 `git@github.com:org/repo`）時，push 用的是 **SSH key 對應的 GitHub 身分**，可能與 gh CLI 登入的帳號**不同**——常見「gh 帳號 READ（開不了 PR / 讀不到 protection）、但 SSH key 有 WRITE（推得動）」。

偵測到此情境時：
1. `gh repo view "$repo_slug" --json viewerPermission -q .viewerPermission`（多 repo：repo 用 **positional 引數**綁定——`gh repo view` **不吃 `-R`**，與 `gh pr` / `gh api` 不同）→ 若 `READ` 且 protection 回 `Not Found` → **主動向使用者點明身分分離**（別假設無權限就停、也別假設無保護就直推）。
2. **用 `git push --dry-run` 探實際 push 權限**（`--dry-run` 不傳資料、不改 remote，**不算 Critical / Step 4 所指的 push**，無需事先確認）：
   ```bash
   git -C <repo> push --dry-run -u origin <branch> 2>&1
   # 成功印 "[new branch] ... -> ..." / "Would set upstream" → SSH 身分有 write
   # 403 / "permission denied" → 無 write
   ```
3. **檢查 gh 是否已登入其他有權帳號**：`gh auth status` 會列出**所有**已登入帳號（active 只有一個）——若另一已登入帳號對該 repo 有 write（如個人 repo 的 owner 本尊、active 卻是工作帳號），`gh auth switch -u <有權帳號>` 後執行 gh 操作（`pr create`／merge 最後一哩），**用完切回原 active 帳號**（實證：active 帳號 READ 時 `gh pr create` 吃 `must be a collaborator`，switch 到已登入的 owner 帳號即通）。
4. 把「protection 無法判定 + dry-run 的 push 權限結果」一併放進 Step 4 ship 摘要，讓使用者定奪：開 PR、換身分、或（若使用者選擇直推）**由使用者自行 push**。**agent 端預設 PR、不自行 push default branch**（Unknown=protected，見下方 ⚠）。**仍不在確認前實際 push。**

> ⚠ **不可**把「硬推會被 remote 擋（無害）」當作直推 default branch 的理由：protection 對 gh 不可見（gh 帳號 READ）但分支實際無保護的 repo（SSH 身分有 write）下，硬推會**成功**，正中 `Unknown = protected` 要防的破口（見 `pressure-tests.md` Scenario 4）。所以「protection 未知 + 使用者要直推」→ **agent 不自行 push default branch**：停下、向使用者點明身分分離與 protection 不可判定，由**使用者自行**執行 push，或明確改走 PR 路徑。

## Branch-first 與誤 commit 搬移

> 本節序列已封裝於 `scripts/branch-first.sh`（情況 A/B 自動判定、前置檢查全過才動、porcelain 前後快照驗證，以腳本為可執行權威——`log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」要求整行照抄呼叫）；以下逐條指令供除錯、或腳本 `verdict: STOP` 後人工處理時參照。

**情況 A：變更在 working tree（人在 default branch），或在 detached HEAD（含已在其上 commit）**
```bash
git -C <repo> switch -c <feature-branch>   # working-tree 變更與 detached HEAD 上的 commit 都跟著切過去；default branch 不動
```

**情況 B：變更已誤 commit 在本地 default branch（未 push）**
```bash
# 先用 feature branch 保住 commit，再把 default branch 退回 origin
git -C <repo> branch <feature-branch>            # 在當前 HEAD 建 branch（保住 commit）
git -C <repo> switch <feature-branch>
git -C <repo> branch -f <default> origin/<default>   # 本地 default 退回 remote（commit 只留在 feature branch）
# 注意：branch -f 不能對當前 branch 用，故先 switch 到 feature branch 再 -f default
```

branch 名先遵循 target repo contract；沒有規定時，slug 由變更語意產生（kebab-case，如
`feat/mops-announce-backfill`），type ∈ feat/fix/refactor/docs/chore/test。

## PR 路徑

```bash
# 1. push feature branch（設 upstream）
git -C <repo> push -u origin <feature-branch>

# 2. 偵測既有 PR（多 repo：-R 綁定，勿靠 cwd）
gh pr view -R "$repo_slug" <feature-branch> --json url,state -q .url 2>/dev/null   # 有 → 印 URL 指向既有 PR（已 push 即更新）

# 3. 無既有 PR → 建立（base 預設 default branch）
gh pr create -R "$repo_slug" --base <default> --head <feature-branch> \
  --title "<repo-conformant semantic title>" \
  --body "<見下方模板>"
```

- **絕不** push default branch。`gh pr merge` 僅限使用者**明說 merge** 後執行（序列見下方「Merge 最後一哩」），開 PR 當下絕不順手 merge。
- repo contract 的 commit／PR title 格式優先；沒有規定時，PR title 才沿用主要 Conventional Commit 的 subject。
- 多個 feature commit → title 取主要語意；body 列各 commit 與變更摘要。
- **fork repo**（如 `origin` 是 fork、`upstream` 是 canonical）：`gh pr create` 的 `--head` 需 `<owner>:<branch>` 格式、base/head 為不同 repo——**本 skill 不自動處理**（見檔首通則與 `log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」）。遇此**停下**由使用者指定 base/head，勿讓 `gh` 觸發互動式 fork/push 流程。
- **`gh` 不可用 / 未登入時的 PR 路徑**：`git push -u origin <feature-branch>`（推 feature branch 安全、不碰 default）後，因無法 `gh pr create` → **停下**，輸出 branch 名與手動開 PR 的 compare URL。**此時 `repo_slug` 不能靠 `gh repo view`（gh 已不可用），改從 remote URL 解析**（同時吃 SSH 與 HTTPS）：
  ```bash
  repo_slug=$(git -C <repo> remote get-url origin | sed -E 's#^(git@[^:]+:|ssh://[^/]+/|https?://[^/]+/)##; s#\.git$##')   # owner/repo（吃 scp-SSH / ssh:// / HTTPS）
  echo "https://github.com/$repo_slug/compare/<default>...<feature-branch>"   # 假設 github.com（見檔首 host 通則）；GHE / 自架請改 host
  ```
  **絕不**因開不了 PR 就 fallback 直推 default branch。

## 直接 push 路徑

> **這是 escape hatch，不是無保護 repo 的預設。** 確定無保護時預設仍走 PR 路徑（見 `log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」），只有使用者**明說**「不用 PR / 只推 branch」才落到本節。理由：跨 repo 單一形狀省掉每輪判斷、PR 留下審查紀錄與可回溯 diff，而多開一個 PR 的成本近零。**"No protection" is not a reason to skip the PR.**

僅在**明確確認無 protection、且使用者明說不用 PR** 時走，**顯式 remote + branch**（不用裸 `git push`——裸 push 受 `push.default` / `remote.pushDefault` / 非預期 upstream 影響，可能推到錯 remote 或多推 ref）：
```bash
git -C <repo> push -u origin <branch>   # 顯式 remote+branch+設 upstream（已有 upstream 時 -u 無害）
```
仍需 Step 4 使用者確認。push 後無 PR 動作。

## 送出前的 branch 內 squash（Step 4 選了「先 squash 再送出」時）

**只壓 review 迭代痕跡，不動獨立語意的 commit**——與 deep-review 收尾同一條原則（語意 commit 在 PR 裡逐顆可讀，有參照價值）。

**reset 目標一律照抄 `log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」中 `ship-state.sh` 記下的那一行，NEVER recompute it, NEVER pick a hash by eyeballing `git log`**——它是**使用者語意 commit 的邊界**（Step 1 跑在 Step 3 之前，此刻 HEAD 之上還沒有本流程自己的 commit）。**Step 3 一旦產生 commit**，套用當下重跑就會讓 verdict 形狀翻轉（頂端連續段歸零），現場只剩會壓掉語意 commit 的全壓指令（實測見同節「Review 痕跡」）。判「哪顆是 review 迭代痕跡」需要 deep-review 的權威 subject 清單（理由同前），挑錯就是把使用者的語意 commit 一起壓掉。

| 使用者在 Step 4 選的 | 照抄哪一行 | 結果 |
|---|---|---|
| 壓掉頂端那段 review 痕跡 | `squash-cmd:` | 語意 commit 原樣保留 |
| 整支壓成一顆（僅在使用者明確要求時） | `squash-all-cmd:` | **連語意 commit 一起收**，選項文案須已講明。**該行只在有 `buried:` 時才印**——沒有 buried 卻臨時要全壓，現場無行可抄 → 照本節末條「目標拿不準就不要壓」，回報現況讓使用者定奪 |

```bash
# 0. branch 已 push 過才需要。**先 fetch 那支 branch**——下面兩步都讀 remote-tracking ref，
#    而它不會自己更新：不 fetch 就是拿舊資料做安全判斷，協作者剛推的 commit 看不見，
#    ancestry 檢查會放行、reset 照跑，一路到 push 才被 lease 擋下——那時本地歷史已經重寫。
git -C <toplevel> fetch origin <feature-branch>

# 錨定遠端當下的 SHA（Step 5 的 lease 要用）。**錨定之後值就固定了**，此後流程再怎麼
# fetch（commit 計數、cleanup 的 --prune）都不影響它——這正是帶 expected SHA 的用意。
git -C <toplevel> rev-parse origin/<feature-branch>    # ← 記下這個值

# 確認遠端沒有你沒有的東西。判準是**祖先關係、不是 SHA 相等**——push 之後又加了
# review fix / docs commit 是正常狀態，本地領先本來就會讓 SHA 不同。
git -C <toplevel> merge-base --is-ancestor origin/<feature-branch> HEAD
# 非 0 → **停下**：遠端 tip 不在本地歷史裡（協作者推過），squash + force-push 會覆蓋掉它們。
# **這一步的價值全靠上面那次 fetch**——沒 fetch 的話它檢查的是本地舊快照，等於沒檢查。

# 1. reset 到腳本給的 hash（整行照抄，勿自行改寫路徑或 hash）
git -C <toplevel> reset --soft <腳本給的 hash>

# 2. 重新 commit。message 要同時涵蓋「這批 review 修復」與「本輪文檔同步」——本輪 Step 3
#    產生的 commit 位於 reset 目標之上，會一併被收進這顆；不沿用被保留 commit 的 subject。
#    附環境指定的 Co-Authored-By trailer，同 Step 3 的規則。
git -C <toplevel> commit -m "<符合 target repo convention 的語意描述>

<Co-Authored-By trailer，取 runtime system prompt 的 Git 區塊>"
```

> `review-anchor.sh squash-cmd` **不是這裡的來源**——deep-review 收尾最後一步就是 `clear`，anchor 已刪、該指令會回 `verdict: STOP`。它只在「deep-review 中途停下、anchor 仍在」時可用。

**本節到 commit 為止，不含任何 push。** branch 已 push 過時，覆寫 remote 需要 `--force-with-lease`——**那是 Step 5 的送出動作**，必須等重印摘要、使用者再次確認後才做（`git -C <repo> push --force-with-lease=<feature-branch>:<步驟 0 記下的 SHA> origin <feature-branch>`——**帶 expected SHA，理由見下**）。在這裡順手推掉，等於用 gate 沒顯示過的 commit set 重寫 remote，正是 Step 4 硬 gate 要防的事。

- **`--force-with-lease`, NEVER `--force`** —— 前者在 remote 有他人新 commit 時會拒絕，後者直接蓋掉。
- **一律帶 expected SHA：`--force-with-lease=<feature-branch>:<步驟 0 記下的 SHA>`**。裸的 `--force-with-lease` 比對的是本地 remote-tracking ref，而**本流程自己就會 fetch**（本節步驟 0 的 `fetch origin <feature-branch>`、`cleanup-cmd` 的 `fetch --prune`）——fetch 一跑，tracking ref 就更新成遠端的新狀態，lease 檢查形同虛設，協作者剛推的 commit 會被靜默覆蓋。**「別在中間 fetch」不是有效的防護**（流程自己會跑），錨定 SHA 才是。
- **`cleanup-cmd`（stale branch 清掃）仍建議排在 force-push 之後**——順序清楚、少一件要想的事。但**它已不是安全前提**：lease 帶了步驟 0 錨定的 SHA，中間再怎麼 fetch 都不影響比較基準。（此條在錨定 SHA 之前確實是硬要求，別讀成現在還是。）
- **NEVER reset past anything already on the default branch** —— 目標最遠只到 `merge-base(<default>, HEAD)`（`squash-all-cmd:` 用的就是它），絕不越過它往 default 上已有的 commit 去。
- 目標拿不準就**不要壓**：回報現況讓使用者定奪。壓錯要救比不壓貴得多。

## Merge 最後一哩（使用者明說 merge 後）

**Trigger: the user EXPLICITLY says "merge"** — either in any turn after the PR exists, **or by picking「送出並 merge」in the Step 4 confirmation options**（後者是同一個 gate 內收掉的預先授權，效力相同；使用者選「停在 PR」則一律不 merge）。 "push" or "open a PR" alone is NOT a merge instruction（沿用全域 CLAUDE.md 語意）。明說即是授權：不要因 skill 通篇的「絕不 merge」而拒絕或反覆再確認，把使用者卡在最後一哩。

**無 PR 可 merge 時**（形狀：使用者先前明說「不用 PR」走了 escape hatch，或全新空 repo 剛建 baseline——總之從頭到尾沒開過 PR）：**do NOT guess what "merge" meant.** 先跑 `ship-state.sh` 取當下狀態，再依狀態停下確認：

- `verdict: BOOTSTRAP` → 使用者要的其實是「把東西弄上去」，走上方〈Bootstrap〉節（首推 baseline），這不是 merge。
- default 已存在、當前在 feature branch、但無 PR → 用 runtime user-input primitive 給兩個選項：**開 PR 再 merge**（留紀錄，預設建議），或**只把 branch push 上去**由使用者自行合併。
- feature branch 尚未 push → 先照 Step 4/5 送出，再回到本節。
- **"merge" is never permission to push the default branch.** 使用者要的是變更進 default，不是繞過流程進 default。

標準收尾序列（PR 已存在；`<merge-flag>` 由下節決定）：

```bash
gh pr merge <PR-number|URL> -R "$repo_slug" <merge-flag> --delete-branch
# --delete-branch 刪 remote branch；在該 repo 工作目錄內執行時，gh 會順帶切回 default 並刪本地 branch
git -C <repo> switch <default>          # 若 gh 未代切（如以 -R 在 repo 外執行）
git -C <repo> pull origin <default>     # 同步本地 default——merge 產生新 commit，本地必落後
git -C <repo> branch -D <feature>       # 本地 branch 若仍殘留。squash/rebase 後 -d 會誤判「未 merge」拒刪，
                                        # 故先確認 PR 已 MERGED（gh pr view --json state）再 -D
```

### 說法表（唯一權威；`log-workflow.md`「Step 4：Ship 摘要 → 確認（critical-op gate）」照此分派）

| 使用者說 | 引數 flag（等價） | 送到哪 | `<merge-flag>` |
|---|---|---|---|
| （無送出詞） | — | push branch + 開 PR，**停在 PR，然後問一題** | — |
| 「開 PR」／「開 pr」／「停在 PR」／「pr」 | `--pr` | push branch + 開 PR，**停在 PR，零提問** | — |
| 「merge」／「合併」 | `--merge` | 全程走完 | `--rebase` |
| 「merge 壓成一顆」／「squash merge」 | `--merge --squash` | 全程走完 | `--squash` |
| 「merge 不壓」／「merge 保留 commit」 | `--merge`（同預設） | 全程走完 | `--rebase` |
| 「merge commit」／「merge 留分支圖」 | `--merge --merge-commit` | 全程走完 | `--merge` |
| 「bypass merge」 | `--bypass-merge` | 全程走完；僅 `BLOCKED` 時 `--admin`（見下） | `--rebase`（可再疊壓的說法） |
| 「merge 照送」／「merge 未審完」 | `--merge --anyway` | 全程走完；預先放行 `review-terminal` 攔截 | `--rebase` |
| 「只推 branch」／「不用 PR」 | `--no-pr` | 只 push feature branch，不開 PR | — |

**flag 與裸說法完全等價**，只是形狀不同：`--merge` ≡ 「merge」。**flag 只存在於 `/project …` 的引數裡**，而裸說法在**本輪任何一則訊息**都算數（那是 prose 路徑，刻意沒有 flag 形式——你可以三輪之後才補一句「merge」）。兩者共用這張表，**不得各自演化**。

> **「（無送出詞）」與 `--pr` 的差別只有一個：問不問。** 兩者最終狀態相同（PR 開著、沒 merge）；`--pr` 是「我知道我要停在 PR」，所以跳過那一題。

**預設保留、不預設壓**：語意 commit 在 PR 裡逐顆可讀、日後可追，那是它們存在的理由。GitHub 的 squash-merge 全有全無、做不到只壓部分，故「壓」必須是使用者說出口的意圖，**不是流程的預設**。

**Do NOT ask which flag to use.** 表上每一列都已經是答案，裸「merge」也是（＝保留）。以前要問是因為預設未定義；現在定義了，問就只是把已決之事再丟回去。

**引數位的形狀規則**（單一來源在 `log-workflow.md`「引數前處理（依形狀分類，不靠優先序記憶）」）：`--` 開頭 = flag；裸字命中本表 = 說法；**module 過濾一律走路徑形式**（`./merge`、`docs/pr`）。裸字永遠不會被當成 module —— 打錯字時它會靜默縮小 Step 2 的掃描範圍，而掃不到的文檔不會報錯。

> **review 迭代痕跡不走這張表**——那批由 branch 內 squash 在送出前處理掉（見上節），無條件執行、不出題。兩件事常被混為一談：這裡決定的是「你自己的語意 commit 進 default 時長什麼樣」，上節處理的是「review 過程的機械痕跡不該留下」。

- PR 內仍殘留 review 樣式 commit → **先跑 `ship-state.sh <repo>` 取 `review-residue:` 判定，不自行看 `git log` 認**（同本檔上節與 `log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」的禁令；誤認就是壓掉使用者自己的歷史，且緊接 force-push 不可回復）：有 `top-contiguous:` → 照該行的 `squash-cmd:` 壓掉再送，不必詢問；只有 `buried:` → **照常送出**，在摘要標明「N 顆 review 痕跡夾在語意 commit 中間，非互動式壓不掉」；`UNKNOWN` → 如實說明現況、不猜。
- **選定的 flag 不可用**（`Rebase merging is not allowed` / `Merge commits are not allowed`；或 branch 含 merge commit 而 GitHub 拒絕 rebase——拒絕原因不同、處置相同）→ 停下回報、以剩下可用的方式給選項。**NEVER silently fall back to another flag** — 尤其別退回 `--squash`：那會壓掉使用者要保留的 commit。這是少數仍需詢問的例外：使用者選的做法在該 repo 不存在，沒有預設可推。

### merge 受阻時的分流（先看狀態，不做「失敗就 retry」）

`gh pr merge` 失敗的原因不只 protection，而 `--admin` 只繞得過 **protection 規則**——衝突它一樣過不了。盲目 retry 只是多失敗一次，還把「繞過」用在不該用的地方。故**先查狀態再決定**：

```bash
gh pr view <PR-number|URL> -R "$repo_slug" --json mergeStateStatus,mergeable -q .mergeStateStatus
```

⚠️ **本流程一定是「push → 開 PR → 查狀態」這個順序，所以第一次查很可能拿到 `UNKNOWN`**——GitHub 的 mergeability 是收到 push 後才非同步算的（2026-08-15 實戰即撞到，重查一次就變 `CLEAN`）。**那是暫態，不是查詢失敗**：重查（隔幾秒，最多三次）拿到實態再分流。**Never report a first-poll `UNKNOWN` as "無從判定" and stop** —— 那會讓每一次 ship 都可能卡在最後一哩。

**`BLOCKED` 不是單一成因，拿到它就必須再追問一句。** CI 還在跑、required check 失敗、protection 真的擋——三者在 `mergeStateStatus` 眼中長得一模一樣，正解卻相反（等／停／可 bypass）。**Never read a bare `BLOCKED` as "protection is really blocking"**：

```bash
# --required 只看 protection 實際在意的 check
gh pr checks <PR-number|URL> -R "$repo_slug" --required
# exit 0 = required check 全綠｜exit 8 = 還有 pending｜其他非零 = 有 check 失敗（或查詢失敗）
```

⚠️ **exit 1 有兩個意思，必須看輸出才分得開**（2026-08-15 實戰撞到）：真的有 check 失敗會列出那些 check；而**這個 repo 根本沒有 required check** 時，輸出是 `no checks reported on the '<branch>' branch`、**exit 同樣是 1**。後者代表阻擋與 check 無關 → **當成「全綠」走第三列**（protection 的其他規則），不是「測試失敗」。**Never read a bare exit 1 as a failing test** —— 對「有 required review、沒有 CI」的 repo，那個誤讀會把「缺 approval」報成「哪個 check 壞了」，而使用者根本找不到那個 check。

判準吃 **exit code**，不要自己數 `statusCheckRollup`——rollup 單筆沒有 `isRequired` 欄位（分不出必要與非必要：非必要 check 還在跑會讓你空等、非必要 check 失敗會讓你誤停）、同名 check 會有多筆（被取代的 workflow run 仍留在清單裡）、且它混了 check run 與 legacy commit status 兩種型別（後者用 `state`/`context`，拿 `status != "COMPLETED"` 去篩對它恆真）。`gh pr checks` 已把這三件事正規化。

| 狀態 | 意思 | 「merge」 | 「bypass merge」 |
|---|---|---|---|
| `CLEAN` / `HAS_HOOKS` / `UNSTABLE` | 沒有硬性阻擋（`UNSTABLE` = **非必要** check 有問題，protection 不在意——與上面 `--required` 是同一判準的兩面） | 直接 merge | 直接 merge（`--admin` 用不到） |
| `BLOCKED` ＋ checks **exit 8** | **CI 還在跑，不是 protection 擋** | **等它跑完再 merge**（見下方等待策略） | **一樣等**——`--admin` 在此繞過的是還沒跑完的測試，不是規則 |
| `BLOCKED` ＋ checks **其他非零，且列出了失敗的 check** | required check 失敗 | 停，回報是哪個 check 失敗 | **一樣停**——繞過等於把沒通過測試的變更送進 default |
| `BLOCKED` ＋ checks **exit 0**，或 **`no checks reported`**（見上方 ⚠️） | protection 真的擋（缺 review／其他規則），與 check 無關 | **停**，回報並告知可用「bypass merge」 | 加 `--admin` 重試 |
| `DIRTY` | 有衝突 | 停，回報 | **一樣停**——`--admin` 不解決衝突 |
| `BEHIND` | base 落後、protection 要求最新 | 停，回報 | **一樣停**——該做的是更新 branch，不是繞過 |
| `DRAFT` | 這是 draft PR，本來就不能 merge | 停，問「要我先 `gh pr ready` 轉正式嗎」——**不自行轉** | 一樣停——`--admin` 不能 merge draft |
| `UNKNOWN`，**且剛 push／剛開 PR** | GitHub 還在算 mergeability（非同步，數秒內解析）——**暫態，不是查詢失敗** | **重查**（隔幾秒，最多三次），拿到實態再依本表分流 | 同左 |
| 其他／查詢失敗（含**重查後仍** `UNKNOWN`） | 無從判定 | 停，回報實際錯誤 | 停，回報 |

- **`--admin` 只在「bypass merge」＋「`BLOCKED` 且 required check 全綠」這一格出現。** Never reach for it on any other row, and never as a retry after an unexplained failure. 它需要 admin 權限；ruleset 也可設成連 admin 都不能繞——兩種情況都是失敗即停、回報，不再想別的辦法。
- **`BLOCKED` ＋ CI 還在跑時的等待策略**（`--watch` 自己輪詢，不要手寫迴圈）：
  ```bash
  gh pr checks <PR-number|URL> -R "$repo_slug" --required --watch --interval 15 --fail-fast
  # 回來之後重查一次狀態再決定 merge——判準看 check，不看上一次 merge 失敗沒有
  gh pr view <PR-number|URL> -R "$repo_slug" --json mergeStateStatus -q .mergeStateStatus
  ```
  - **刻意不封頂**：跑到 check 收斂為止。agent 全程在場、使用者隨時可中斷，那就是上限。
  - **NEVER wrap the wait in `timeout` / `gtimeout`.** Neither exists on macOS, and `command not found` is exit 127 — the whole wait silently never runs while the exit code still reads like a pass. 需要停就中斷，不要引入 `timeout`。
  - **NEVER re-run `gh pr merge` while waiting.** 這正是本節標題那條「不做失敗就 retry」的具體化：判準是 check 狀態，不是上一次 merge 失敗與否；重試只是多一次 API 呼叫，還把「還是被擋」的假訊號餵回自己。
  - 「有的還在跑、有的已失敗」同時成立時 exit code 只會回一個。**不論回哪個，處置都不是 `--admin`**——差別只在「等」還是「立刻回報」；`--fail-fast` 會讓 watch 在第一個失敗就返回。
- **required check 失敗時要把回程路線一起講**：回報附一句「check 修綠之後跟我說一聲 **merge**，我接手最後一哩」。使用者之後說「merge」即是說法表的授權——**重查一次現況**（不沿用本輪快照）再走「Merge 最後一哩」，**不必重跑整個 `/project`**。
- **`--auto` 預設不用。** GitHub 的錯誤訊息會建議它，但 merge 真正發生時 agent 已經結束，「Merge 最後一哩」剩下的三步（切回 default、`pull` 同步、刪 branch）沒有人做——本地 default 落後、feature branch 殘留，要等下一輪 `ship-state.sh` 的 `stale-branches:` 才補報。只有在 CI 明顯很慢、使用者不想等時才提供它當選項，並在回報明說「本地 default 與 branch 清理要你之後自己做」。
- **`BLOCKED` 缺的是什麼，去讀規則與 check，NEVER infer it from an empty PR field.** `reviewDecision: ""` 不等於「缺 approval」——`required_approving_review_count: 0` 的 repo 它本來就一直是空的（2026-08-14 與 08-15 兩次實地誤診同一來源）。要確認 protection 要求什麼就直接讀：`gh api repos/{owner}/{repo}/rulesets`（再取 `/rulesets/{id}` 看內容）與上面〈Branch protection 偵測〉那組指令。
- **動用了 `--admin` 就必須在送出回報裡明說「這次繞過了 protection」。** 繞過本身要留在使用者看得到的地方。
- **失敗即停**：gh 帳號無 write 權限、其他未列狀態 → 停下回報實際錯誤。**Never bypass checks by other means, never fall back to pushing the default branch directly.**
- 多 repo（多個 PR 同輪開出）：先確認使用者的 merge 指令涵蓋哪些 PR，勿一句 merge 就全 merge。
- merge 完成後回報：merged commit / 本地 default 已同步 / branch 已清。
- **本序列只清它自己 merge 的那支**——更早的、或走別條路合併的 branch 不在此列，由 `ship-state.sh` 的 `stale-branches:` 訊號在下一輪 Step 1 攤開（附 `cleanup-cmd:`，經使用者同意才刪）。

## PR title / body 模板

```
<符合 target repo convention 的 PR title；無規定時用主要 Conventional Commit subject>

## 變更摘要
- <commit 1 語意>
- <commit 2 語意>

## 測試
- <測試指令與結果，如 uv run pytest …：N passed>

## Review
- <若經 /deep-review：貼「第三方審查資訊」commit range + 結論；否則略>

```

PR body 不自行加入產品 attribution。若目前 runtime 或 repo contract 明定 attribution，再依該權威加入；
不要把 Claude Code 執行標成 Codex，也不要把 Codex 執行標成 Claude Code。

## push 失敗處理

- `! [rejected] ...`：**先分流，兩種成因的處置相反**——
  - **本輪做過 branch 內 squash**（歷史被刻意改寫，見上節）→ `git -C <toplevel> push --force-with-lease=<feature-branch>:<squash 前記下的遠端 SHA> origin <feature-branch>`（帶 expected SHA 的理由見上節）。**NEVER `pull --rebase` here** —— 它會把剛壓掉的那串 review commit 原封不動拉回來，squash **靜默失效**（PR 上痕跡照舊），或因同內容重疊卡在 rebase 衝突中途。
  - **沒改寫歷史**（純粹 remote 有他人新 commit）→ 提示 `git -C <repo> pull --rebase origin <branch>` 後重試（feature branch 通常不會撞，除非他人也 push 同 branch）。
- `src refspec ... does not match` / 無 upstream → 用 `-u origin <branch>`。
- gh 未登入（`gh auth status` 失敗）→ 停下，提示使用者 `gh auth login`，不要硬推。
