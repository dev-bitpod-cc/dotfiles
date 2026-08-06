#!/usr/bin/env bash
#
# git-hygiene.sh — ready4quit Step 1 的 git 衛生檢查（單次呼叫、多 repo）
#
# 用法：
#   git-hygiene.sh <repo-path>...
#
# 逐 repo 輸出 remote / uncommitted / baseline / unpushed / pr 與 verdict：
#   CLEAN   — 無任何殘留（每一項都實際查過且為空）
#   RESIDUE — 有未 commit / 未 push / 無 PR / PR 為 DRAFT 或 CLOSED
#   UNKNOWN — 有檢查無法完成（fetch 失敗、無 baseline、gh 不可用等）；NOT proof of clean
#
# CLEAN 的前提是 remote 事實而非本機 cache：跑判定前會先 fetch --prune 該 repo 的
# remote，fetch 失敗一律把 unpushed 降為 UNKNOWN。沒有這道，遠端 branch 被刪或
# force-push 後 tracking ref 仍指向舊 commit，unpushed: none 會是假的。
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

# fetch 參數。GIT_HYGIENE_FETCH_TIMEOUT 僅供測試縮短等待；正常使用不需設定。
FETCH_TIMEOUT_SECS="${GIT_HYGIENE_FETCH_TIMEOUT:-8}"  # 單一 repo 的 fetch 上限；寧可判 UNKNOWN 也不拖住收尾
SSH_CONNECT_TIMEOUT=4     # ssh 連線建立的上限；只擋連不上，擋不住連上後卡住的傳輸，故仍需 watchdog
KILL_GRACE_SECS=1         # 逾時後 TERM 與 KILL 之間的緩衝，讓 git 有機會自己收乾淨

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

# 純 bash 的 watchdog。不用 timeout/gtimeout：macOS 預設兩者皆無（實測本機都不存在），
# 靠外部指令會讓「上限 N 秒」的宣告在主要環境直接不成立——裸 fetch 實測跑滿 30 秒。
run_with_timeout() {   # <秒> <指令...>
    local secs="$1"; shift
    "$@" &
    local cmd_pid=$!
    ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null
      sleep "$KILL_GRACE_SECS"; kill -KILL "$cmd_pid" 2>/dev/null ) &
    local watch_pid=$! rc=0
    wait "$cmd_pid" 2>/dev/null || rc=$?
    kill -TERM "$watch_pid" 2>/dev/null   # 指令先跑完就收掉 watchdog，別讓它空等
    wait "$watch_pid" 2>/dev/null
    return "$rc"
}

# 推導 baseline 所屬的 remote：優先當前 branch 設定的 remote，否則 origin，再否則第一個。
# 用 config 而非 ref，才不會受 stale/缺失的 tracking ref 影響。
detect_remote() {
    local repo="$1" branch="$2" remote=""
    if [ "$branch" != "DETACHED" ]; then
        remote="$(git -C "$repo" config --get "branch.${branch}.remote" 2>/dev/null)" || remote=""
    fi
    if [ -z "$remote" ]; then
        if git -C "$repo" remote | grep -qx origin; then
            remote="origin"
        else
            remote="$(git -C "$repo" remote | head -1)"
        fi
    fi
    echo "$remote"
}

# 讓指定 remote 的 tracking ref 反映此刻的遠端。不 fetch 就只是在讀本機 cache——遠端
# branch 被刪掉或 force-push 之後 cache 仍指向舊 commit，unpushed 會報 none，而東西
# 其實沒送出去。--prune 是必要的：已刪除的遠端 branch 不 prune 就永遠留著 stale ref。
#
# 刻意不做新鮮度快取：FETCH_HEAD 是 repo-global 的，多 remote 時「剛 fetch 過 other」
# 會讓 origin 的 stale ref 被當成新鮮（實測可重現誤判 CLEAN）。pre-quit 是一次性檢查，
# 省那一次 fetch 不值得拿 verdict 的可信度去換。
# 回傳 0 = ref 可信；1 = 不可信（無 remote / 失敗 / 逾時）——呼叫端據此把 unpushed 降 UNKNOWN。
refresh_remote() {   # <repo> <remote>
    local repo="$1" remote="$2" rc=0
    [ -n "$remote" ] || return 1
    # 用 env 而非 `VAR=x func`：後者在 bash 中會讓變數在函式返回後殘留
    # GIT_TERMINAL_PROMPT=0：https remote 要求互動認證時直接失敗，不掛住收尾流程
    run_with_timeout "$FETCH_TIMEOUT_SECS" \
        env GIT_TERMINAL_PROMPT=0 \
            GIT_SSH_COMMAND="ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o BatchMode=yes" \
            git -C "$repo" fetch --prune --quiet "$remote" 2>/dev/null || rc=1
    return "$rc"
}

check_repo() {
    local repo="$1"
    # residue 依來源分開記：PR 判定為 MERGED 時要能單獨撤銷 unpushed 那筆
    # （squash merge 後 remote branch 被刪，baseline 退回 default，原始 commit 會被
    #   算成「未 push」，但它們早已以 squash 形式進了 default）
    local residue_uncommitted=0 residue_unpushed=0 residue_pr=0 unknown=0

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
        residue_uncommitted=1
    else
        echo "uncommitted: none"
    fi

    # -- remote 新鮮度：unpushed 的可信度完全建立在 tracking ref 是否反映此刻遠端 --
    local has_remote=0 remote_fresh=0 remote_name=""
    [ -n "$(git -C "$repo" remote)" ] && has_remote=1
    if [ "$has_remote" -eq 1 ]; then
        remote_name="$(detect_remote "$repo" "$branch")"
        if refresh_remote "$repo" "$remote_name"; then
            remote_fresh=1
            echo "remote: 已同步（fetch --prune ${remote_name}）"
        else
            echo "remote: UNKNOWN（fetch ${remote_name} 失敗/逾時——tracking ref 可能過期，unpushed 不可信）"
        fi
    fi

    # -- baseline（未 push 比較基準）：upstream → origin/<default> → 無 --
    local baseline="" upstream default_branch="" baseline_kind=""
    if upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
        baseline="$upstream"
        baseline_kind="upstream"
        echo "baseline: upstream $upstream"
    elif [ "$branch" != "DETACHED" ] \
        && git -C "$repo" rev-parse --verify --quiet "origin/$branch" >/dev/null; then
        # 已 push 但沒設 upstream（push 不帶 -u）：拿 origin/<default> 當基準會把
        # 早已在 remote 的 commit 全報成「未 push」——同名 remote branch 才是正確基準
        baseline="origin/$branch"
        baseline_kind="same-name"
        echo "baseline: ${baseline}（無 upstream，退用同名 remote branch）"
    else
        default_branch="$(detect_default_branch "$repo")"
        if [ -n "$default_branch" ]; then
            baseline="origin/$default_branch"
            baseline_kind="default"
            echo "baseline: ${baseline}（無 upstream，退用 default branch）"
        elif [ -z "$(git -C "$repo" remote)" ]; then
            echo "baseline: NO-REMOTE（local-only repo，無從判斷 push 狀態）"
        else
            echo "baseline: NONE（有 remote 但找不到 origin/HEAD、origin/main、origin/master）"
        fi
    fi

    # -- 未 push commit --
    if [ -n "$baseline" ] && [ "$remote_fresh" -eq 0 ]; then
        # 有 baseline 但 ref 不新鮮：拿本機 cache 比出來的 none 不能當「已送出」
        echo "unpushed: UNKNOWN（remote 狀態無從確認，見上方 remote 行）"
        unknown=1
    elif [ -n "$baseline" ]; then
        local unpushed n_unpushed
        if unpushed="$(git -C "$repo" log --oneline "$baseline..HEAD" 2>/dev/null)"; then
            if [ -n "$unpushed" ]; then
                n_unpushed="$(printf '%s\n' "$unpushed" | wc -l | tr -d ' ')"
                echo "unpushed: $n_unpushed commits"
                printf '%s\n' "$unpushed" | head -n "$MAX_LIST" | sed 's/^/  /'
                residue_unpushed=1
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
        # 只讀 url 不夠：CLOSED（未合併就關掉）與 draft 都會回 url，卻都不代表變更送得出去
        local pr_info pr_rc=0 pr_err pr_state pr_draft pr_url
        pr_info="$(cd "$toplevel" && "$GH_BIN" pr view --json url,state,isDraft \
            -q '[.state,(.isDraft|tostring),.url]|@tsv' 2>"$ERR_FILE")" || pr_rc=$?
        if [ "$pr_rc" -eq 0 ] && [ -n "$pr_info" ]; then
            pr_state="$(printf '%s' "$pr_info" | cut -f1)"
            pr_draft="$(printf '%s' "$pr_info" | cut -f2)"
            pr_url="$(printf '%s' "$pr_info" | cut -f3)"
            case "$pr_state" in
                OPEN)
                    if [ "$pr_draft" = "true" ]; then
                        echo "pr: DRAFT ${pr_url}（草稿，尚未真正送審）"
                        residue_pr=1
                    else
                        echo "pr: ${pr_url}"
                    fi ;;
                MERGED)
                    echo "pr: MERGED ${pr_url}（已合併，branch 可清理）"
                    # remote branch 被刪掉後 baseline 退回 default，squash 前的原始 commit
                    # 會被算成「未 push」——PR 既然已合併，那些內容早就進去了，撤銷該筆殘留。
                    # baseline 是同名 remote branch 時不撤銷：那時的 unpushed 是真的沒 push。
                    if [ "$residue_unpushed" -eq 1 ] && [ "$baseline_kind" = "default" ]; then
                        echo "  ↳ 上方 unpushed 為 squash 前的原始 commit（remote branch 已刪），不計入殘留"
                        residue_unpushed=0
                    fi ;;
                CLOSED)
                    echo "pr: CLOSED ${pr_url}（未合併就關閉，變更沒進去）"
                    residue_pr=1 ;;
                *)
                    echo "pr: UNKNOWN（未預期的 PR state：${pr_state}）"
                    unknown=1 ;;
            esac
        elif grep -qi 'no pull requests found' "$ERR_FILE"; then
            echo "pr: MISSING（feature branch 有 commit 但無 PR）"
            residue_pr=1
        else
            pr_err="$(head -n 1 "$ERR_FILE")"
            echo "pr: UNKNOWN（gh 查詢失敗：${pr_err:-無錯誤訊息}）"
            unknown=1
        fi
    fi

    # -- verdict：RESIDUE 優先於 UNKNOWN（都有時先處理殘留）--
    if [ $((residue_uncommitted + residue_unpushed + residue_pr)) -gt 0 ]; then
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
