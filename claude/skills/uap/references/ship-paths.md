# Ship Paths — git/gh 指令細節

SKILL.md Step 1/5 的展開。涵蓋 repo 解析、protection 偵測、branch-first 搬移、PR 路徑、直接 push 路徑、PR body 模板、失敗處理。

## 目錄
- [Repo / default branch 解析](#repo--default-branch-解析)
- [Branch protection 偵測](#branch-protection-偵測)
- [Branch-first 與誤 commit 搬移](#branch-first-與誤-commit-搬移)
- [PR 路徑](#pr-路徑)
- [直接 push 路徑](#直接-push-路徑)
- [PR title / body 模板](#pr-title--body-模板)
- [push 失敗處理](#push-失敗處理)

## Repo / default branch 解析

```bash
# owner/repo（gh 自當前 repo 解析，最穩）
gh repo view --json nameWithOwner -q .nameWithOwner    # 如 elandcomtw/krepo
# 或從 remote URL 推（gh 不可用時 fallback）：
git -C <repo> remote get-url origin

# default branch（remote HEAD）
git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null   # 如 origin/main → 取 basename main
# 失敗 fallback：gh repo view --json defaultBranchRef -q .defaultBranchRef.name
# 再 fallback：依序試 main / master（git rev-parse --verify origin/main）
```

## Branch protection 偵測

GitHub 有兩套保護：**classic branch protection** 與**新式 rulesets**，兩者都要查（只看 classic 會漏掉用 ruleset 的 repo）。

```bash
# classic：未保護回 404 {"message":"Branch not protected"}；有保護回 200 JSON
classic=$(gh api "repos/{owner}/{repo}/branches/{default}/protection" 2>&1)
classic_rc=$?
# ruleset：無規則回 []，有規則回非空陣列
rules=$(gh api "repos/{owner}/{repo}/rules/branches/{default}" 2>/dev/null)
```

判定（依序）：
- classic exit 0（200）**或** `rules` 非 `[]` → **protected** → PR 路徑。
- classic 訊息含 `Branch not protected`（404）**且** `rules` == `[]` → **確定無保護** → 直接 push 路徑。
- 其他（403 無權限 / 網路 / 無 gh / 無法分辨）→ **未知 → 視為 protected**（Unknown = protected）。

> 注意：404「Branch not protected」是 GitHub 對「該分支無 classic 保護」的明確回應（即使你是 ADMIN 也是 404），**不是**權限錯誤——要靠訊息字串分辨，別只看 exit code。
> 額外訊號（輔助判斷團隊習慣，非決策依據）：repo 有 `.github/PULL_REQUEST_TEMPLATE*` 或 `CODEOWNERS` → 偏向 PR 流程。

## Branch-first 與誤 commit 搬移

**情況 A：變更還在 working tree，人在 default branch（PR 路徑）**
```bash
git -C <repo> switch -c <type>/<slug>   # working-tree 變更跟著切過去，default branch 不動
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

# 2. 偵測既有 PR
gh pr view --json url,state -q .url 2>/dev/null   # 有 → 印 URL 指向既有 PR（已 push 即更新）

# 3. 無既有 PR → 建立（base 預設 default branch）
gh pr create --base <default> --head <feature-branch> \
  --title "<conventional-commit-style title>" \
  --body "<見下方模板>"
```

- **絕不** `gh pr merge`。**絕不** push default branch。
- 多個 feature commit → title 取主要語意；body 列各 commit 與變更摘要。

## 直接 push 路徑

僅在**明確確認無 protection** 時走：
```bash
git -C <repo> push                    # 有 upstream
git -C <repo> push -u origin <branch> # 無 upstream
```
仍需 Step 4 使用者確認。push 後無 PR 動作。

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

- `! [rejected] ... (fetch first)`：remote 有新 commit → 提示 `git -C <repo> pull --rebase origin <branch>` 後重試（feature branch 通常不會撞，除非他人也 push 同 branch）。
- `src refspec ... does not match` / 無 upstream → 用 `-u origin <branch>`。
- gh 未登入（`gh auth status` 失敗）→ 停下，提示使用者 `gh auth login`，不要硬推。
