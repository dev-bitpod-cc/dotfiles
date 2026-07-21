#!/usr/bin/env bash
#
# handoff-anchor.sh — handoff skill 的交接檔生命週期機制（錨點產生 / 驗證 / 列表清理）
#
# 用法：
#   handoff-anchor.sh anchors <repo-path>...   # 產生 frontmatter 錨點行（created + 逐 repo anchor）
#   handoff-anchor.sh verify  <handoff.md>     # 驗證交接檔錨點 vs 各 repo 現況
#   handoff-anchor.sh consume <handoff.md>     # 消費歸檔：mv 到同層 archive/ 加秒級時戳前綴，
#                                              # 印 archived: <路徑>；已消費（父目錄為
#                                              # archive 或檔名已帶時戳前綴）→ 拒絕
#   handoff-anchor.sh list    [dir]            # 列出 active 交接檔（年齡/EXPIRED）+ 自動清過期 archive
#
# verify 逐錨點輸出判定：
#   FRESH      — 記錄的 HEAD == 現在的 HEAD（內容可信）
#   DRIFTED    — 記錄的 HEAD 是現在 HEAD 的祖先（repo 已前進 N commits；列出中間 commit 供比對）
#   DIVERGED   — 記錄的 HEAD 不在現行歷史上（rebase/換 branch/歷史改寫）；內容一律存疑
#   MISSING    — repo 路徑不存在或不是 git repo
#   BAD-ANCHOR — 錨點行欄位不足（如手寫殘缺），無法驗證
#   另檢查 created 年齡，超過 EXPIRE_DAYS 標 EXPIRED。
#
# exit code：0 = 全部 FRESH 且未過期（consume：歸檔完成）；
#            1 = 任一 DRIFTED/DIVERGED/MISSING/BAD-ANCHOR/EXPIRED（consume：拒絕或失敗——
#                檔案不存在／已在 archive 內（重複消費）／目錄解析失敗／目標同秒碰撞／
#                mv 失敗；拒絕與失敗路徑檔案一律原地不動，consume-once 由此機械保證。
#                exit 1 ≠ 已歸檔：讀 stderr 分辨，mv 失敗時交接檔仍在 active）；
#            2 = 用法錯誤
#
# 限制：repo 路徑不可含空白（anchor 行以空白分欄）——anchors 遇含空白路徑直接報錯拒絕。
# list 的 dir 預設 $HANDOFF_DIR，未設則 ~/.claude/handoffs。

set -uo pipefail

EXPIRE_DAYS=7        # active 交接檔超過即標 EXPIRED——內容與現實脫節的風險隨時間上升
ARCHIVE_KEEP_DAYS=30 # 已消費（archive/）的交接檔保留天數，過期由 list 自動清（保險絲期）
MAX_LOG=20           # DRIFTED 時最多列出的中間 commit 數；只影響顯示

usage() {
    echo "用法：$0 anchors <repo>... | verify <handoff.md> | consume <handoff.md> | list [dir]" >&2
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
        case "$repo" in *[[:space:]]*)
            echo "error: repo 路徑含空白，錨點格式不支援（anchor 行以空白分欄）：$repo" >&2
            failed=1
            continue ;;
        esac
        if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
            echo "error: 不是 git repo（或路徑不存在）：$repo" >&2
            failed=1
            continue
        fi
        local branch sha dirty
        branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || branch="DETACHED"
        # full sha：short sha 日後可能因物件增長變 ambiguous，導致 verify 誤判 DIVERGED
        sha="$(git -C "$repo" rev-parse HEAD)"
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

    local repo branch sha dirty _extra
    while IFS= read -r line; do
        # read 分欄不做 glob expansion（路徑含 * [ ? 也不會被展開成 cwd 檔名）
        IFS=' ' read -r repo branch sha dirty _extra <<< "${line#anchor: }"
        if [ -z "$sha" ]; then
            echo "--- ${repo:-?} ---"
            echo "status: BAD-ANCHOR（錨點行欄位不足，無法驗證：${line}）"
            overall=1
            continue
        fi
        verify_anchor "$repo" "$branch" "$sha" "$dirty" || overall=1
    done <<< "$anchors"

    if [ "$overall" -eq 0 ]; then
        echo "verdict: FRESH（交接內容可信）"
    else
        echo "verdict: STALE-RISK（先跑上列 drift 比對，以 repo 現況為準再行動）"
    fi
    exit "$overall"
}

# consume：R4 消費歸檔的機械化——驗位置（archive 內拒絕）→ mkdir -p archive →
# mv 加 YYYYMMDD-HHMMSS 前綴（同日同 slug 二次消費不互覆）→ 印 archived: 供回報。
# 本子指令是本腳本唯一動 active 檔的 mutation（mv 單一檔案；list 另會清過期 archive），
# 不碰 git、不碰檔案內容。
cmd_consume() {
    [ $# -eq 1 ] || usage
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "error: 交接檔不存在：${file}" >&2
        exit 1
    fi
    local dir base
    dir="$(CDPATH='' cd -- "$(dirname -- "$file")" 2>/dev/null && pwd -P)" || dir=""
    if [ -z "$dir" ]; then
        echo "error: 無法解析交接檔所在目錄：${file}" >&2
        exit 1
    fi
    base="$(basename -- "$file")"
    # 「已消費」偵測用工具自身不變量，不掃整條路徑找 archive 祖先——整路徑掃描會把
    # /srv/archive/<user>/handoffs/x.md 這類合法 active 檔誤拒（C2 審查實證），誤拒即
    # consume 永久卡死。兩個不變量：
    # (1) 直接父目錄名 archive（本工具的歸檔佈局）
    # (2) 檔名帶 YYYYMMDD-HHMMSS- 前綴（本工具的歸檔命名——被手工搬到巢狀子目錄也認得出）
    # 手工塞進 archive 巢狀子目錄且無前綴的檔案非本工具產物（從未被工具消費），不在偵測範圍
    if [ "$(basename -- "$dir")" = "archive" ]; then
        echo "error: 檔案已在 archive 內（已消費過）——consume-once，不可重複消費：${file}" >&2
        exit 1
    fi
    case "$base" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*)
            echo "error: 檔名已帶歸檔時戳前綴（已消費過）——consume-once，不可重複消費：${file}" >&2
            exit 1 ;;
    esac
    # 時戳先取出並驗格式——date 失敗時若直接串進路徑，會歸檔成 archive/-<name>
    # 且回報成功，稽核時戳靜默流失
    local ts
    ts="$(date +%Y%m%d-%H%M%S)" || ts=""
    case "$ts" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
        *)  echo "error: 無法取得時戳（date 失敗）——不歸檔，交接檔原地不動" >&2
            exit 1 ;;
    esac
    mkdir -p "$dir/archive"
    local dest="$dir/archive/${ts}-${base}"
    # -e 前置檢查而非 mv -n：BSD/GNU 的 mv -n 目標已存在時「靜默跳過且 exit 0」，
    # 會印 archived: 但檔案沒動——比檢查與 mv 之間的 TOCTOU 窗（單機單人工具）危險
    if [ -e "$dest" ]; then
        echo "error: 目標已存在（同秒重複消費？）：${dest}" >&2
        exit 1
    fi
    if ! mv -- "$file" "$dest"; then
        echo "error: mv 失敗，交接檔仍在原位：${file}" >&2
        exit 1
    fi
    echo "archived: $dest"
    exit 0
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
    consume) cmd_consume "$@" ;;
    list)    cmd_list "$@" ;;
    *) usage ;;
esac
