#!/usr/bin/env bash
#
# handoff-anchor.sh — handoff skill 的交接檔生命週期機制（錨點產生 / 驗證 / 列表清理）
#
# 用法：
#   handoff-anchor.sh anchors <repo-path>...   # 產生 frontmatter 錨點行（created + 逐 repo anchor）
#   handoff-anchor.sh verify  <handoff.md>     # 驗證交接檔錨點 vs 各 repo 現況
#   handoff-anchor.sh list    [dir]            # 列出 active 交接檔（年齡/EXPIRED）+ 自動清過期 archive
#
# verify 逐錨點輸出判定：
#   FRESH    — 記錄的 HEAD == 現在的 HEAD（內容可信）
#   DRIFTED  — 記錄的 HEAD 是現在 HEAD 的祖先（repo 已前進 N commits；列出中間 commit 供比對）
#   DIVERGED — 記錄的 HEAD 不在現行歷史上（rebase/換 branch/歷史改寫）；內容一律存疑
#   MISSING  — repo 路徑不存在或不是 git repo
#   另檢查 created 年齡，超過 EXPIRE_DAYS 標 EXPIRED。
#
# exit code：0 = 全部 FRESH 且未過期；1 = 任一 DRIFTED/DIVERGED/MISSING/EXPIRED；2 = 用法錯誤
#
# 限制：repo 路徑不可含空白（anchor 行以空白分欄）。
# list 的 dir 預設 $HANDOFF_DIR，未設則 ~/.claude/handoffs。

set -uo pipefail

EXPIRE_DAYS=7        # active 交接檔超過即標 EXPIRED——內容與現實脫節的風險隨時間上升
ARCHIVE_KEEP_DAYS=30 # 已消費（archive/）的交接檔保留天數，過期由 list 自動清（保險絲期）
MAX_LOG=20           # DRIFTED 時最多列出的中間 commit 數；只影響顯示

usage() {
    echo "用法：$0 anchors <repo>... | verify <handoff.md> | list [dir]" >&2
    exit 2
}

# 解析 YYYY-MM-DD → epoch（macOS 的 date -j 與 GNU date -d 皆支援）
date_to_epoch() {
    date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

age_days_from_created() {  # <YYYY-MM-DD> → 天數；解析失敗輸出空字串
    local epoch
    epoch="$(date_to_epoch "$1")" || return 1
    [ -n "$epoch" ] || return 1
    echo $(( ($(date +%s) - epoch) / 86400 ))
}

cmd_anchors() {
    [ $# -ge 1 ] || usage
    local failed=0
    echo "created: $(date +%Y-%m-%d)"
    for repo in "$@"; do
        if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
            echo "error: 不是 git repo（或路徑不存在）：$repo" >&2
            failed=1
            continue
        fi
        local branch sha dirty
        branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || branch="DETACHED"
        sha="$(git -C "$repo" rev-parse --short HEAD)"
        dirty="$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')"
        echo "anchor: $repo $branch $sha dirty=$dirty"
    done
    return "$failed"
}

verify_anchor() {  # <path> <branch> <sha> <dirty=n> → 輸出判定；FRESH 回 0，其餘回 1
    local repo="$1" branch="$2" sha="$3"
    echo "--- $repo ---"
    echo "recorded: branch=$branch head=$sha ${4:-dirty=?}"

    if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "status: MISSING（路徑不存在或不是 git repo）"
        return 1
    fi

    local cur_branch cur_sha cur_dirty
    cur_branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || cur_branch="DETACHED"
    cur_sha="$(git -C "$repo" rev-parse --short HEAD)"
    cur_dirty="$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')"
    echo "current:  branch=$cur_branch head=$cur_sha dirty=$cur_dirty"

    if ! git -C "$repo" rev-parse --verify --quiet "$sha^{commit}" >/dev/null; then
        echo "status: DIVERGED（記錄的 HEAD 已不存在——歷史改寫或錯誤錨點；內容一律存疑）"
        return 1
    fi

    if [ "$(git -C "$repo" rev-parse "$sha")" = "$(git -C "$repo" rev-parse HEAD)" ]; then
        [ "$branch" != "$cur_branch" ] && echo "note: branch 已從 $branch 切到 $cur_branch"
        echo "status: FRESH"
        return 0
    fi

    if git -C "$repo" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
        local n
        n="$(git -C "$repo" rev-list --count "$sha..HEAD")"
        echo "status: DRIFTED（repo 已前進 $n commits，交接內容可能已失效——逐條對 repo 現況重驗）"
        git -C "$repo" log --oneline "$sha..HEAD" | head -n "$MAX_LOG" | sed 's/^/  /'
        [ "$n" -gt "$MAX_LOG" ] && echo "  ...（其餘 $((n - MAX_LOG)) commits 略）"
        return 1
    fi

    echo "status: DIVERGED（記錄的 HEAD 不在現行歷史上——rebase 或換了 branch；內容一律存疑）"
    return 1
}

cmd_verify() {
    [ $# -eq 1 ] || usage
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "error: 交接檔不存在：$file" >&2
        exit 1
    fi

    local overall=0

    # -- 年齡 --
    local created age
    created="$(sed -n 's/^created:[[:space:]]*//p' "$file" | head -1)"
    if [ -n "$created" ] && age="$(age_days_from_created "$created")"; then
        if [ "$age" -gt "$EXPIRE_DAYS" ]; then
            echo "age: ${age}d — EXPIRED（超過 ${EXPIRE_DAYS} 天，內容以 repo 現況為準）"
            overall=1
        else
            echo "age: ${age}d — OK"
        fi
    else
        echo "age: UNKNOWN（無法解析 created 欄位）"
        overall=1
    fi

    # -- 錨點 --
    local anchors
    anchors="$(grep '^anchor: ' "$file" || true)"
    if [ -z "$anchors" ]; then
        echo "anchors: NONE（無錨點——無法判斷交接內容是否過時，一律存疑）"
        echo "verdict: UNVERIFIABLE"
        exit 1
    fi

    while IFS= read -r line; do
        # shellcheck disable=SC2086  # 錨點欄位刻意以空白分欄
        verify_anchor ${line#anchor: } || overall=1
    done <<< "$anchors"

    if [ "$overall" -eq 0 ]; then
        echo "verdict: FRESH（交接內容可信）"
    else
        echo "verdict: STALE-RISK（先跑上列 drift 比對，以 repo 現況為準再行動）"
    fi
    exit "$overall"
}

cmd_list() {
    local dir="${1:-${HANDOFF_DIR:-$HOME/.claude/handoffs}}"
    if [ ! -d "$dir" ]; then
        echo "handoffs: NONE（目錄不存在：${dir}）"
        exit 0
    fi

    # -- active 交接檔 --
    local found=0 f base created age flag
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        found=1
        base="$(basename "$f")"
        created="$(sed -n 's/^created:[[:space:]]*//p' "$f" | head -1)"
        if [ -n "$created" ] && age="$(age_days_from_created "$created")"; then
            flag="OK"
            [ "$age" -gt "$EXPIRE_DAYS" ] && flag="EXPIRED（建議：確認已無用即刪，或 resume 重驗）"
            echo "active: $base — ${age}d — $flag"
        else
            echo "active: $base — created 無法解析 — SUSPECT"
        fi
    done
    [ "$found" -eq 0 ] && echo "active: none"

    # -- archive 自動清理（已消費的交接檔過保險絲期即刪）--
    if [ -d "$dir/archive" ]; then
        local pruned=0
        while IFS= read -r f; do
            rm -f "$f" && pruned=$((pruned + 1))
        done < <(find "$dir/archive" -name '*.md' -type f -mtime "+$ARCHIVE_KEEP_DAYS")
        [ "$pruned" -gt 0 ] && echo "archive: 已清 $pruned 份超過 ${ARCHIVE_KEEP_DAYS} 天的已消費交接檔"
    fi
    exit 0
}

[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
    anchors) cmd_anchors "$@" ;;
    verify)  cmd_verify "$@" ;;
    list)    cmd_list "$@" ;;
    *) usage ;;
esac
