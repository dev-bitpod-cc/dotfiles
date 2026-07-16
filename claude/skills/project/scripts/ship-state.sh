#!/usr/bin/env bash
#
# ship-state.sh — /project log Step 0/1 的 ship 狀態偵測（單次呼叫、多 repo、唯讀）
#
# 用法：
#   ship-state.sh <repo-path>...
#
# 逐 repo 輸出：branch / remotes / default / 變更集（files-vs-default 三點、
# commits-ahead 兩點、working-tree porcelain）/ misplaced（誤 commit 在本地
# default）/ protection verdict / ship-path / branch-first。
#
# exit code：0 = 全部 repo 偵測完成（有無變更都算成功）；1 = 有 repo 無效；2 = 用法錯誤
#
# 設計原則：
# - 唯讀。不 fetch、不 commit、不 switch——mutation 一律留給 skill 流程（branch-first
#   搬移、提交、push 都在 Step 1/3/5 由 model 依 Critical gate 執行）。
# - protection 判定封裝於此（classic + ruleset，邏輯解說見 references/ship-paths.md，
#   本腳本為可執行權威）。Unknown = protected 直接印在輸出裡，不留給 model 重新詮釋。
#
# SHIP_STATE_GH 僅供測試 stub gh（tests/run.sh）；正常使用不需設定。

set -uo pipefail

MAX_LIST=20  # 每類清單最多列出的行數；只影響顯示，計數仍為完整值
GH_BIN="${SHIP_STATE_GH:-gh}"

if [ $# -eq 0 ]; then
    echo "用法：$0 <repo-path>..." >&2
    exit 2
fi

overall=0

# 印一段清單（stdin），縮排並截斷到 MAX_LIST
print_list() {
    local total="$1"
    head -n "$MAX_LIST" | sed 's/^/  /'
    [ "$total" -gt "$MAX_LIST" ] && echo "  ...（其餘 $((total - MAX_LIST)) 行略）"
}

# canonical remote：有 origin 用之，否則取第一個；無 remote 輸出空字串
detect_remote() {
    local repo="$1" remotes
    remotes="$(git -C "$repo" remote)"
    if printf '%s\n' "$remotes" | grep -qx origin; then
        echo origin
    else
        printf '%s\n' "$remotes" | head -1
    fi
}

# default branch：remote HEAD → probe main/master；找不到輸出空字串
detect_default_branch() {
    local repo="$1" remote="$2" ref cand
    ref="$(git -C "$repo" symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null)" || ref=""
    ref="${ref#"$remote"/}"
    if [ -n "$ref" ] && [ "$ref" != "HEAD" ]; then
        echo "$ref"
        return 0
    fi
    for cand in main master; do
        if git -C "$repo" rev-parse --verify --quiet "$remote/$cand" >/dev/null; then
            echo "$cand"
            return 0
        fi
    done
    echo ""
}

# protection 判定（classic + ruleset；判定順序見 ship-paths.md）
# 輸出單行 "protection: ..."，UNKNOWN 一律附 treat as PROTECTED
detect_protection() {
    local repo="$1" remote="$2" default="$3"
    if ! command -v "$GH_BIN" >/dev/null 2>&1; then
        echo "protection: UNKNOWN（gh 不可用）→ treat as PROTECTED"
        return
    fi
    local slug
    slug="$( (cd "$repo" && "$GH_BIN" repo view --json nameWithOwner -q .nameWithOwner) 2>/dev/null)"
    if [ -z "$slug" ]; then
        # fallback：從 remote URL 解析 owner/repo（吃 scp-SSH / ssh:// / HTTPS）
        slug="$(git -C "$repo" remote get-url "$remote" 2>/dev/null \
            | sed -E 's#^(git@[^:]+:|ssh://[^/]+/|https?://[^/]+/)##; s#\.git$##')"
    fi
    case "$slug" in
        */*) ;;  # 長得像 owner/repo 才能查 API
        *)  echo "protection: UNKNOWN（無法解析 owner/repo）→ treat as PROTECTED"
            return ;;
    esac
    local enc="${default//\//%2F}"  # default 名含 '/'（如 release/2026）→ encode
    local classic classic_rc rules
    classic="$("$GH_BIN" api "repos/$slug/branches/$enc/protection" 2>&1)"
    classic_rc=$?
    rules="$("$GH_BIN" api "repos/$slug/rules/branches/$enc" 2>/dev/null)" || rules=""

    if [ "$classic_rc" -eq 0 ] || { [ -n "$rules" ] && [ "$rules" != "[]" ]; }; then
        echo "protection: PROTECTED（classic rc=${classic_rc}；ruleset $([ -n "$rules" ] && [ "$rules" != "[]" ] && echo 非空 || echo 空/未查得)）"
    elif printf '%s' "$classic" | grep -q "Branch not protected" && [ "$rules" = "[]" ]; then
        echo "protection: OPEN（classic 404 Branch not protected + ruleset []）"
    elif printf '%s' "$classic" | grep -q "Not Found"; then
        # Not Found ≠ 無保護：常見 gh 帳號無權讀 protection（身分分離，見 ship-paths.md）
        local perm
        perm="$( (cd "$repo" && "$GH_BIN" repo view "$slug" --json viewerPermission -q .viewerPermission) 2>/dev/null)"
        echo "protection: UNKNOWN（classic Not Found，gh 帳號可能無權讀 protection；viewerPermission=${perm:-?}，注意身分分離）→ treat as PROTECTED"
    else
        echo "protection: UNKNOWN（無法分辨：403/網路/其他）→ treat as PROTECTED"
    fi
}

check_repo() {
    local repo="$1"

    echo "=== $repo ==="

    if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "error: 不是 git repo（或路徑不存在）"
        return 1
    fi

    # -- branch / remotes --
    local branch remote remotes_n
    branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || branch="DETACHED"
    echo "branch: $branch"

    remote="$(detect_remote "$repo")"
    if [ -z "$remote" ]; then
        echo "remotes: NONE（local-only repo，無從 ship）"
        echo "verdict: STOP（無 remote，停下告知使用者）"
        return 0
    fi
    remotes_n="$(git -C "$repo" remote | wc -l | tr -d ' ')"
    if [ "$remotes_n" -gt 1 ]; then
        echo "remotes: $remotes_n 個（canonical=${remote}）— 可能是 fork 工作流，Step 4 需明列兩個 remote 由使用者確認"
        git -C "$repo" remote -v | grep '(push)' | sed 's/^/  /'
    else
        echo "remotes: $remote ($(git -C "$repo" remote get-url "$remote" 2>/dev/null))"
    fi

    # -- default branch --
    local default
    default="$(detect_default_branch "$repo" "$remote")"
    if [ -z "$default" ]; then
        echo "default: NONE（找不到 $remote/HEAD、$remote/main、$remote/master）"
        echo "verdict: STOP（無法定位 default branch，交由使用者確認）"
        return 0
    fi
    echo "default: $default"

    # -- 變更集：三點 diff（branch 自身帶來的檔）+ 兩點 log（領先 commit）+ porcelain --
    local files n_files commits n_commits porcelain n_dirty
    files="$(git -C "$repo" diff --name-only "$remote/$default...HEAD" 2>/dev/null)" || files=""
    commits="$(git -C "$repo" log --oneline "$remote/$default..HEAD" 2>/dev/null)" || commits=""
    porcelain="$(git -C "$repo" status --porcelain)"

    if [ -n "$files" ]; then
        n_files="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
        echo "files-vs-default: $n_files 檔（三點，branch 自身帶來的）"
        printf '%s\n' "$files" | print_list "$n_files"
    else
        echo "files-vs-default: none"
    fi
    if [ -n "$commits" ]; then
        n_commits="$(printf '%s\n' "$commits" | wc -l | tr -d ' ')"
        echo "commits-ahead: ${n_commits}（兩點，領先 $remote/${default}）"
        printf '%s\n' "$commits" | print_list "$n_commits"
    else
        n_commits=0
        echo "commits-ahead: none"
    fi
    if [ -n "$porcelain" ]; then
        n_dirty="$(printf '%s\n' "$porcelain" | wc -l | tr -d ' ')"
        echo "working-tree: $n_dirty 檔（含 untracked）"
        printf '%s\n' "$porcelain" | print_list "$n_dirty"
    else
        n_dirty=0
        echo "working-tree: clean"
    fi

    # -- 誤 commit 偵測（Step 1 情況 B 的觸發條件）--
    if [ "$branch" = "$default" ] && [ "$n_commits" -gt 0 ]; then
        echo "misplaced: WARNING — $n_commits commit 已誤 commit 在本地 ${default}（情況 B：branch 保住 commit → switch → branch -f 退回；勿 reset --hard）"
    fi

    # -- 無變更 → docs-only gate（判定需要 session 記憶，交回 model）--
    if [ -z "$files" ] && [ "$n_commits" -eq 0 ] && [ "$n_dirty" -eq 0 ]; then
        echo "changes: NONE — do NOT exit yet: check session memory for already-shipped work (docs-only mode, Step 1 item 2)"
        return 0
    fi

    # -- protection → ship path --
    local prot
    prot="$(detect_protection "$repo" "$remote" "$default")"
    echo "$prot"
    case "$prot" in
        *OPEN*) echo "ship-path: DIRECT-PUSH（仍推 feature branch，絕不直推 ${default}）" ;;
        *)      echo "ship-path: PR（推 feature branch + 開 PR，不 merge）" ;;
    esac

    # -- branch-first --
    if [ "$branch" = "$default" ] || [ "$branch" = "DETACHED" ]; then
        echo "branch-first: REQUIRED（HEAD 在 $branch —— commit 之前先開 feature branch，無條件）"
    else
        echo "branch-first: 已在 feature branch（${branch}）"
    fi
}

for repo in "$@"; do
    check_repo "$repo" || overall=1
    echo ""
done

exit "$overall"
