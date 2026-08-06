# Ship Paths — git/gh 指令細節

SKILL.md Step 1/5 的展開。涵蓋 repo 解析、protection 偵測、branch-first 搬移、PR 路徑、直接 push 路徑、PR body 模板、失敗處理。

> **Solo repo is not a lighter process.** One-person projects run the SAME shape as a protected-main team repo: branch → commits → review → PR → explicit merge. Never relax branch-first, the PR default, or the explicit-merge rule because "it's just me", "no one else will read this history", or "there's no protection to enforce it". 理由：repo 會移交、會加入新成員，使用者本人也會成為他人 repo 的成員——流程形狀一旦按「一人份」放寬，這些時刻就沒有秩序可交接，也養不出正式流程的手感。**這條只是防守既有規則被合理化侵蝕，不新增任何步驟。**

> **本檔通則**：下文所有 `origin` 為 canonical remote 的 **stand-in**——非 `origin` repo（如 fork 工作流）一律把 `origin` 讀作解析出的 remote（`git -C <repo> remote`：有 `origin` 用之、否則取第一個；fork 場景 push 目標與 PR/protection 查詢目標可能不同 remote，見 SKILL Step 1 remote 假設）。gh 指令多 repo 時用 `-R <owner/repo>` 或子 shell `cd` 綁定，勿靠 cwd 隱式解析。**host 假設 GitHub.com**（`gh` 走 authenticated default host、compare URL 用 `github.com`）；GHE / 自架需 `GH_HOST` + `host/owner/repo`，不在本 skill 自動處理範圍。

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
~/.claude/skills/project/scripts/ship-state.sh <repo>
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
[ -z "$default" ] && default=$(for b in main master; do git -C <repo> rev-parse --verify -q "origin/$b" >/dev/null && echo "$b" && break; done)   # symbolic-ref 失敗 → 實際試 origin/main、origin/master（不可留空，否則 endpoint 變 branches//protection；origin 為 canonical remote stand-in，見 SKILL Step 1 remote 假設）
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

> 本節序列已封裝於 `scripts/branch-first.sh`（情況 A/B 自動判定、前置檢查全過才動、porcelain 前後快照驗證，以腳本為可執行權威——SKILL Step 1 第 5 項整行照抄呼叫）；以下逐條指令供除錯、或腳本 `verdict: STOP` 後人工處理時參照。

**情況 A：變更在 working tree（人在 default branch），或在 detached HEAD（含已在其上 commit）**
```bash
git -C <repo> switch -c <type>/<slug>   # working-tree 變更與 detached HEAD 上的 commit 都跟著切過去；default branch 不動
```

**情況 B：變更已誤 commit 在本地 default branch（未 push）**
```bash
# 先用 feature branch 保住 commit，再把 default branch 退回 origin
git -C <repo> branch <type>/<slug>            # 在當前 HEAD 建 branch（保住 commit）
git -C <repo> switch <type>/<slug>
git -C <repo> branch -f <default> origin/<default>   # 本地 default 退回 remote（commit 只留在 feature branch）
# 注意：branch -f 不能對當前 branch 用，故先 switch 到 feature branch 再 -f default
```

slug 由變更語意產生（kebab-case，如 `feat/mops-announce-backfill`）。type ∈ feat/fix/refactor/docs/chore/test。

## PR 路徑

```bash
# 1. push feature branch（設 upstream）
git -C <repo> push -u origin <feature-branch>

# 2. 偵測既有 PR（多 repo：-R 綁定，勿靠 cwd）
gh pr view -R "$repo_slug" <feature-branch> --json url,state -q .url 2>/dev/null   # 有 → 印 URL 指向既有 PR（已 push 即更新）

# 3. 無既有 PR → 建立（base 預設 default branch）
gh pr create -R "$repo_slug" --base <default> --head <feature-branch> \
  --title "<conventional-commit-style title>" \
  --body "<見下方模板>"
```

- **絕不** push default branch。`gh pr merge` 僅限使用者**明說 merge** 後執行（序列見下方「Merge 最後一哩」），開 PR 當下絕不順手 merge。
- 多個 feature commit → title 取主要語意；body 列各 commit 與變更摘要。
- **fork repo**（如 `origin` 是 fork、`upstream` 是 canonical）：`gh pr create` 的 `--head` 需 `<owner>:<branch>` 格式、base/head 為不同 repo——**本 skill 不自動處理**（見檔首通則與 SKILL Step 1 fork 邊界）。遇此**停下**由使用者指定 base/head，勿讓 `gh` 觸發互動式 fork/push 流程。
- **`gh` 不可用 / 未登入時的 PR 路徑**：`git push -u origin <feature-branch>`（推 feature branch 安全、不碰 default）後，因無法 `gh pr create` → **停下**，輸出 branch 名與手動開 PR 的 compare URL。**此時 `repo_slug` 不能靠 `gh repo view`（gh 已不可用），改從 remote URL 解析**（同時吃 SSH 與 HTTPS）：
  ```bash
  repo_slug=$(git -C <repo> remote get-url origin | sed -E 's#^(git@[^:]+:|ssh://[^/]+/|https?://[^/]+/)##; s#\.git$##')   # owner/repo（吃 scp-SSH / ssh:// / HTTPS）
  echo "https://github.com/$repo_slug/compare/<default>...<feature-branch>"   # 假設 github.com（見檔首 host 通則）；GHE / 自架請改 host
  ```
  **絕不**因開不了 PR 就 fallback 直推 default branch。

## 直接 push 路徑

> **這是 escape hatch，不是無保護 repo 的預設。** 確定無保護時預設仍走 PR 路徑（SKILL Step 1 第 4 項），只有使用者**明說**「不用 PR / 只推 branch」才落到本節。理由：跨 repo 單一形狀省掉每輪判斷、PR 留下審查紀錄與可回溯 diff，而多開一個 PR 的成本近零。**"No protection" is not a reason to skip the PR.**

僅在**明確確認無 protection、且使用者明說不用 PR** 時走，**顯式 remote + branch**（不用裸 `git push`——裸 push 受 `push.default` / `remote.pushDefault` / 非預期 upstream 影響，可能推到錯 remote 或多推 ref）：
```bash
git -C <repo> push -u origin <branch>   # 顯式 remote+branch+設 upstream（已有 upstream 時 -u 無害）
```
仍需 Step 4 使用者確認。push 後無 PR 動作。

## 送出前的 branch 內 squash（Step 4 選了「先 squash 再送出」時）

**只壓 review 迭代痕跡，不動獨立語意的 commit**——與 deep-review 收尾同一條原則（語意 commit 在 PR 裡逐顆可讀，有參照價值）。

**reset 目標一律照抄 Step 1 `ship-state.sh` 記下的那一行，NEVER recompute it, NEVER pick a hash by eyeballing `git log`**——它是**使用者語意 commit 的邊界**（Step 1 跑在 Step 3 之前，此刻 HEAD 之上還沒有本流程自己的 commit）。套用當下重跑會讓 verdict 形狀翻轉（`top-contiguous` 恆為 0），現場只剩會壓掉語意 commit 的全壓指令——理由與實測見 SKILL Step 1 第 6 項 —— 判「哪顆是 review 迭代痕跡」需要 deep-review 的權威 subject 清單（理由見 SKILL Step 1 第 6 項），挑錯就是把使用者的語意 commit 一起壓掉。

| 使用者在 Step 4 選的 | 照抄哪一行 | 結果 |
|---|---|---|
| 壓掉頂端那段 review 痕跡 | `squash-cmd:` | 語意 commit 原樣保留 |
| 整支壓成一顆（僅在使用者明確要求時） | `squash-all-cmd:` | **連語意 commit 一起收**，選項文案須已講明 |

```bash
# 1. reset 到腳本給的 hash（整行照抄，勿自行改寫路徑或 hash）
git -C <toplevel> reset --soft <腳本給的 hash>

# 2. 重新 commit。message 要同時涵蓋「這批 review 修復」與「本輪文檔同步」——本輪 Step 3
#    產生的 commit 位於 reset 目標之上，會一併被收進這顆；不沿用被保留 commit 的 subject。
#    附環境指定的 Co-Authored-By trailer，同 Step 3 的規則。
git -C <toplevel> commit -m "<type>: <描述>

<Co-Authored-By trailer，取 runtime system prompt 的 Git 區塊>"
```

> `review-anchor.sh squash-cmd` **不是這裡的來源**——deep-review 收尾最後一步就是 `clear`，anchor 已刪、該指令會回 `verdict: STOP`。它只在「deep-review 中途停下、anchor 仍在」時可用。

**本節到 commit 為止，不含任何 push。** branch 已 push 過時，覆寫 remote 需要 `--force-with-lease`——**那是 Step 5 的送出動作**，必須等重印摘要、使用者再次確認後才做（`git -C <repo> push --force-with-lease origin <feature-branch>`）。在這裡順手推掉，等於用 gate 沒顯示過的 commit set 重寫 remote，正是 Step 4 硬 gate 要防的事。

- **`--force-with-lease`, NEVER `--force`** —— 前者在 remote 有他人新 commit 時會拒絕，後者直接蓋掉。
- **NEVER reset past anything already on the default branch** —— 目標一律落在 `<default>..HEAD` 之內。
- 目標拿不準就**不要壓**：回報現況讓使用者定奪。壓錯要救比不壓貴得多。

## Merge 最後一哩（使用者明說 merge 後）

**Trigger: the user EXPLICITLY says "merge"** — either in any turn after the PR exists, **or by picking「送出並 merge」in the Step 4 confirmation options**（後者是同一個 gate 內收掉的預先授權，效力相同；使用者選「停在 PR」則一律不 merge）。 "push" or "open a PR" alone is NOT a merge instruction（沿用全域 CLAUDE.md 語意）。明說即是授權：不要因 skill 通篇的「絕不 merge」而拒絕或反覆再確認，把使用者卡在最後一哩。

**無 PR 可 merge 時**（形狀：使用者先前明說「不用 PR」走了 escape hatch，或全新空 repo 剛建 baseline——總之從頭到尾沒開過 PR）：**do NOT guess what "merge" meant.** 先跑 `ship-state.sh` 取當下狀態，再依狀態停下確認：

- `verdict: BOOTSTRAP` → 使用者要的其實是「把東西弄上去」，走上方〈Bootstrap〉節（首推 baseline），這不是 merge。
- default 已存在、當前在 feature branch、但無 PR → 用 `AskUserQuestion` 給兩個選項：**開 PR 再 merge**（留紀錄，預設建議），或**只把 branch push 上去**由使用者自行合併。
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

### 壓或不壓（`<merge-flag>` 的決定）

review 迭代痕跡（`fix: address review findings` 這類）該壓，**使用者的語意 commit 不該壓**——它們在 PR 裡逐 commit 可讀、日後可追。GitHub 的 squash-merge 是全有全無、做不到只壓部分，故這是**整個 PR 的一次決定**。

明確關鍵字 → 直接執行，不再問：

| 使用者說 | `<merge-flag>` |
|---|---|
| 「merge 壓成一顆」／「squash merge」／「merge squash」 | `--squash` |
| 「merge 不壓」／「merge 保留 commit」／「merge 別壓」 | `--rebase` |
| 「merge commit」／「merge 留分支圖」 | `--merge` |

裸「merge」／「合併」（未指定壓不壓）：

- PR 相對 default **只有 1 顆 commit** → `--squash`，直接做（無歧義，不打斷）。顆數用指令取，別憑印象：
  ```bash
  git -C <toplevel> fetch origin                                              # 先對齊——「另起一輪說 merge」時本地可能落後 remote
  git -C <toplevel> rev-list --count origin/<default>..origin/<feature-branch>  # 以 remote ref 為上界，數的才是 PR 上真正有的
  ```
  本地 ref 落後時 `--count` 會少算 → 誤判「只有 1 顆」而直接 `--squash`，把 PR 上實際存在的多顆語意 commit 壓平。
- **≥2 顆 commit** → 用 `AskUserQuestion` 給三個選項，題目**列出實際 commit 清單**：`保留 commit（rebase，線性歷史）` ／ `保留 commit + merge commit` ／ `壓成一顆`。**A bare "merge" is not an answer to this question** — 使用者若再回一次「merge」，重問，never pick a reading and proceed.
- PR 內仍殘留 review 樣式 commit（`fix: address review findings`／`wip: pre-review snapshot` 等）→ 在選項文案點出，並補一句可先在 branch 上壓掉它們（`reset --soft` + 重 commit + `push --force-with-lease`）再回來 merge。
- **選定的 flag 不可用**（`Rebase merging is not allowed` / `Merge commits are not allowed`；或 branch 含 merge commit 而 GitHub 拒絕 rebase——拒絕原因不同、處置相同）→ 停下回報、以剩下可用的方式重新給選項。**NEVER silently fall back to another flag** — 尤其別退回 `--squash`：那會壓掉使用者剛選擇要保留的 commit。

其餘：

- **失敗即停**：required checks 未過、merge conflict、gh 帳號無 write 權限 → 停下回報實際錯誤。**Never `--admin`, never bypass checks, never fall back to pushing default directly.**
- 多 repo（多個 PR 同輪開出）：先確認使用者的 merge 指令涵蓋哪些 PR，勿一句 merge 就全 merge。
- merge 完成後回報：merged commit / 本地 default 已同步 / branch 已清。
- **本序列只清它自己 merge 的那支**——更早的、或走別條路合併的 branch 不在此列，由 `ship-state.sh` 的 `stale-branches:` 訊號在下一輪 Step 1 攤開（附 `cleanup-cmd:`，經使用者同意才刪）。

## PR title / body 模板

```
<type>: <精簡描述>

## 變更摘要
- <commit 1 語意>
- <commit 2 語意>

## 測試
- <測試指令與結果，如 uv run pytest …：N passed>

## Review
- <若經 /deep-review：貼「第三方審查資訊」commit range + 結論；否則略>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

> PR body 結尾用上面這行 Claude Code 標註（與 commit 的 `Co-Authored-By` trailer 分工：commit 用 trailer、PR body 用這行）。

## push 失敗處理

- `! [rejected] ...`：**先分流，兩種成因的處置相反**——
  - **本輪做過 branch 內 squash**（歷史被刻意改寫，見上節）→ `git -C <toplevel> push --force-with-lease origin <feature-branch>`。**NEVER `pull --rebase` here** —— 它會把剛壓掉的那串 review commit 原封不動拉回來，squash **靜默失效**（PR 上痕跡照舊），或因同內容重疊卡在 rebase 衝突中途。
  - **沒改寫歷史**（純粹 remote 有他人新 commit）→ 提示 `git -C <repo> pull --rebase origin <branch>` 後重試（feature branch 通常不會撞，除非他人也 push 同 branch）。
- `src refspec ... does not match` / 無 upstream → 用 `-u origin <branch>`。
- gh 未登入（`gh auth status` 失敗）→ 停下，提示使用者 `gh auth login`，不要硬推。
