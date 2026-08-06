#!/usr/bin/env bash
#
# git-hygiene.sh — ready4quit Step 1 的 git 衛生檢查（單次呼叫、多 repo）
#
# 用法：
#   git-hygiene.sh <repo-path>...
#
# 逐 repo 輸出 uncommitted / baseline / unpushed / pr 與 verdict：
#   CLEAN   — 無任何殘留（每一項都實際查過且為空）
#   RESIDUE — 有未 commit / 未 push / 待開 PR 殘留
#   UNKNOWN — 有檢查無法完成（無 baseline、gh 不可用等）；NOT proof of clean
#
# exit code：0 = 全部 CLEAN；1 = 任一 repo RESIDUE 或 UNKNOWN；2 = 用法錯誤
#
# 設計原則：取代 SKILL.md 舊版讓 model 逐條跑指令的做法——「執行失敗」與
# 「成功但無輸出」在此以 exit code 精確分辨，不再依賴 2>/dev/null 吞 stderr
# 後的人工判讀（Solve, don't punt）。
#
# GIT_HYGIENE_GH 僅供測試 stub gh（tests/run.sh）；正常使用不需設定。

set -uo pipefail

MAX_LIST=20  # 每類殘留最多列出的行數；只影響顯示，計數仍為完整值
GH_BIN="${GIT_HYGIENE_GH:-gh}"

# gh 的 stderr 落這裡——「查不到 PR」與「gh 執行失敗」都是 exit 1，只有訊息分得出來
ERR_FILE="$(mktemp)" || { echo "error: mktemp 失敗，無法建立暫存檔" >&2; exit 2; }
trap 'rm -f "$ERR_FILE"' EXIT

if [ $# -eq 0 ]; then
    echo "用法：$0 <repo-path>..." >&2
    exit 2
fi

overall=0  # 0=全 CLEAN；1=有 RESIDUE/UNKNOWN

# 解析 repo 的 default branch 名（origin/HEAD → main → master）；找不到輸出空字串
detect_default_branch() {
    local repo="$1" ref
    ref="$(git -C "$repo" rev-parse --abbrev-ref origin/HEAD 2>/dev/null)" || ref=""
    ref="${ref#origin/}"
    # origin/HEAD 未設定時 rev-parse 可能回空或原樣回 "origin/HEAD"→basename "HEAD"
    if [ -n "$ref" ] && [ "$ref" != "HEAD" ]; then
        echo "$ref"
        return 0
    fi
    local cand
    for cand in main master; do
        if git -C "$repo" rev-parse --verify --quiet "origin/$cand" >/dev/null; then
            echo "$cand"
            return 0
        fi
    done
    echo ""
}

check_repo() {
    local repo="$1"
    local residue=0 unknown=0

    echo "=== $repo ==="

    # -- repo 有效性 --
    local toplevel
    if ! toplevel="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"; then
        echo "error: 不是 git repo（或路徑不存在）"
        echo "verdict: UNKNOWN"
        return 1
    fi

    # -- 當前 branch --
    local branch
    branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || branch="DETACHED"
    echo "branch: $branch"

    # -- 未 commit（含 untracked）--
    # -uall：預設會把整個未追蹤目錄折疊成 "?? dir/"，殘留檔數被低估、檔名也看不到
    local porcelain n_uncommitted
    porcelain="$(git -C "$repo" status --porcelain -uall)"
    if [ -n "$porcelain" ]; then
        n_uncommitted="$(printf '%s\n' "$porcelain" | wc -l | tr -d ' ')"
        echo "uncommitted: $n_uncommitted 檔"
        printf '%s\n' "$porcelain" | head -n "$MAX_LIST" | sed 's/^/  /'
        [ "$n_uncommitted" -gt "$MAX_LIST" ] && echo "  ...（其餘 $((n_uncommitted - MAX_LIST)) 檔略）"
        residue=1
    else
        echo "uncommitted: none"
    fi

    # -- baseline（未 push 比較基準）：upstream → origin/<default> → 無 --
    local baseline="" upstream default_branch=""
    if upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
        baseline="$upstream"
        echo "baseline: upstream $upstream"
    elif [ "$branch" != "DETACHED" ] \
        && git -C "$repo" rev-parse --verify --quiet "origin/$branch" >/dev/null; then
        # 已 push 但沒設 upstream（push 不帶 -u）：拿 origin/<default> 當基準會把
        # 早已在 remote 的 commit 全報成「未 push」——同名 remote branch 才是正確基準
        baseline="origin/$branch"
        echo "baseline: ${baseline}（無 upstream，退用同名 remote branch）"
    else
        default_branch="$(detect_default_branch "$repo")"
        if [ -n "$default_branch" ]; then
            baseline="origin/$default_branch"
            echo "baseline: ${baseline}（無 upstream，退用 default branch）"
        elif [ -z "$(git -C "$repo" remote)" ]; then
            echo "baseline: NO-REMOTE（local-only repo，無從判斷 push 狀態）"
        else
            echo "baseline: NONE（有 remote 但找不到 origin/HEAD、origin/main、origin/master）"
        fi
    fi

    # -- 未 push commit --
    if [ -n "$baseline" ]; then
        local unpushed n_unpushed
        if unpushed="$(git -C "$repo" log --oneline "$baseline..HEAD" 2>/dev/null)"; then
            if [ -n "$unpushed" ]; then
                n_unpushed="$(printf '%s\n' "$unpushed" | wc -l | tr -d ' ')"
                echo "unpushed: $n_unpushed commits"
                printf '%s\n' "$unpushed" | head -n "$MAX_LIST" | sed 's/^/  /'
                residue=1
            else
                echo "unpushed: none"
            fi
        else
            echo "unpushed: UNKNOWN（log $baseline..HEAD 執行失敗）"
            unknown=1
        fi
    else
        echo "unpushed: UNKNOWN（無 baseline 可比）"
        unknown=1
    fi

    # -- 待開 PR：feature branch（≠ default）且相對 default 有 commit 才需要查 --
    # default_branch 可能已在 baseline fallback 算過；沒算過（走 upstream 分支）再算一次
    [ -n "$default_branch" ] || default_branch="$(detect_default_branch "$repo")"
    if [ "$branch" = "DETACHED" ]; then
        echo "pr: n/a（detached HEAD）"
    elif [ -z "$default_branch" ]; then
        echo "pr: n/a（無法判定 default branch）"
    elif [ "$branch" = "$default_branch" ]; then
        echo "pr: n/a（在 default branch 上）"
    elif [ -z "$(git -C "$repo" log --oneline "origin/$default_branch..HEAD" 2>/dev/null)" ]; then
        echo "pr: n/a（相對 origin/$default_branch 無 commit）"
    elif ! command -v "$GH_BIN" >/dev/null 2>&1; then
        echo "pr: UNKNOWN（gh 不可用，無法查 PR 狀態）"
        unknown=1
    else
        # 「真的沒 PR」與「gh 跑不動」（未登入 / 帳號切錯 / 網路 / 權限）都是 exit 1。
        # 吞掉 stderr 會把後者誤報成 MISSING → 使用者被導去開一個可能已存在的 PR
        local pr_url pr_rc=0 pr_err
        pr_url="$(cd "$toplevel" && "$GH_BIN" pr view --json url -q .url 2>"$ERR_FILE")" || pr_rc=$?
        if [ "$pr_rc" -eq 0 ] && [ -n "$pr_url" ]; then
            echo "pr: $pr_url"
        elif grep -qi 'no pull requests found' "$ERR_FILE"; then
            echo "pr: MISSING（feature branch 有 commit 但無 PR）"
            residue=1
        else
            pr_err="$(head -n 1 "$ERR_FILE")"
            echo "pr: UNKNOWN（gh 查詢失敗：${pr_err:-無錯誤訊息}）"
            unknown=1
        fi
    fi

    # -- verdict：RESIDUE 優先於 UNKNOWN（都有時先處理殘留）--
    if [ "$residue" -eq 1 ]; then
        echo "verdict: RESIDUE"
        return 1
    elif [ "$unknown" -eq 1 ]; then
        echo "verdict: UNKNOWN"
        return 1
    fi
    echo "verdict: CLEAN"
    return 0
}

for repo in "$@"; do
    check_repo "$repo" || overall=1
    echo ""
done

exit "$overall"
