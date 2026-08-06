#!/usr/bin/env bash
# session-pull-check.sh — SessionStart hook:開工前偵測 clone 是否落後 origin
#
# 背景:五台主機(macmini/macs/eagle03/eagle06/db01)共用 repo,handoff/memory 為
# machine-local,git 是唯一跨機媒介——但整條 skill 鏈(ship-state.sh / git-hygiene.sh)
# 只管 push 側;eagle03 的 krepo 曾落後 origin 近 3 個月而無人察覺。本腳本補 pull 側盲區。
#
# 防禦原則(同 nc-notify):任何失敗一律靜默 exit 0,絕不擋 session 啟動、絕不留噪音。
# 唯讀例外:git fetch 會更新 origin/* remote-tracking refs(這正是偵測所需),
# 不碰 working tree、不碰本地 branch。

# 任何未預期錯誤都不能讓 hook 失敗
set +e
exec 2>/dev/null

FETCH_FRESH_SECS=3600   # FETCH_HEAD 一小時內更新過就跳過 fetch(頻繁開 session 不重複打 remote)
FETCH_TIMEOUT_SECS=6    # fetch 整體上限;離線/慢網寧可放棄偵測也不拖慢啟動
SSH_CONNECT_TIMEOUT=4   # ssh remote(github-work 等)的連線上限,小於整體上限
STALE_STATUS_DAYS=30    # STATUS.md 最後 commit 落後 repo 活動超過此天數 → 提醒 dossier 過期
MAX_WORKTREE_LIST=3     # 其他 worktree 最多列幾個;超過只報數量——開工提醒列滿螢幕等於沒人看

# --- 前置:不在 git repo 內就靜默離開 -------------------------------------------
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$repo_root" ] || exit 0
cd "$repo_root" || exit 0

# --- worktree 雙寫入者 + base 建議(純本地判斷,零網路)------------------------------
# 位置關鍵:必須在下方 upstream/fetch 早退之前跑完。那兩處在「無 upstream」與「fetch
# 失敗」時都 exit 0,而本段完全不需要網路——放後面等於離線或純本地 branch 上整組失效。
#
# `git worktree list --porcelain` 的第一筆永遠是主 checkout,用它同時判定「當前是否在
# linked worktree」。不用 --git-common-dir 比對:它在普通 repo 回相對路徑 .git、在 linked
# worktree 回絕對路徑,直接比字串會誤判。
wt_list=$(git worktree list --porcelain 2>/dev/null | awk '
    /^worktree /  { path = substr($0, 10); branch = ""; prunable = 0 }
    /^branch /    { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    /^detached$/  { branch = "(detached)" }
    /^prunable/   { prunable = 1 }
    /^$/          { if (path != "" && !prunable) print path "\t" branch; path = "" }
    END           { if (path != "" && !prunable) print path "\t" branch }
')

in_linked_worktree=0
main_wt=$(printf '%s\n' "$wt_list" | head -1 | cut -f1)
if [ -n "$main_wt" ] && [ "$repo_root" != "$main_wt" ]; then
    in_linked_worktree=1
fi

others=$(printf '%s\n' "$wt_list" | awk -F'\t' -v self="$repo_root" 'NF && $1 != self')
n_others=$(printf '%s\n' "$others" | grep -c .)
if [ "$n_others" -gt 0 ]; then
    wt_desc=""
    shown=0
    while IFS="$(printf '\t')" read -r wt_path wt_branch; do
        [ -n "$wt_path" ] || continue
        [ "$shown" -lt "$MAX_WORKTREE_LIST" ] || break
        # 路徑已消失(尚未 prune)→ 跳過該筆即可,不放棄整條訊號
        [ -d "$wt_path" ] || continue
        wt_dirty=""
        if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null | head -1)" ]; then
            wt_dirty="(有未 commit 變更)"   # dirty 才是「有人正在寫」的實證
        fi
        wt_desc="${wt_desc}${wt_desc:+、}$(basename "$wt_path") [${wt_branch:-?}]${wt_dirty}"
        shown=$((shown + 1))
    done <<< "$others"
    if [ -n "$wt_desc" ]; then
        wt_more=""
        [ "$n_others" -gt "$shown" ] && wt_more="(另有 $((n_others - shown)) 個未列出)"
        echo "ℹ 另有 ${n_others} 個 worktree 使用中:${wt_desc}${wt_more}——留意雙寫入者,勿同時編輯同一份 tree。"
    fi
fi

# base 建議只在「主 checkout + feature branch + 相對 default 有 commit」三者皆成立時出聲。
# 已在 linked worktree 裡就不報——base 是開 worktree 當下才要選的。
# 刻意不報「default branch 上有未 push commit」:那是 ship 側的事,git-hygiene.sh /
# /project log 已覆蓋,hook 不重複出聲。
if [ "$in_linked_worktree" -eq 0 ]; then
    cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    default_branch=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null)
    default_branch=${default_branch#origin/}
    if [ -n "$cur_branch" ] && [ "$cur_branch" != "HEAD" ] \
        && [ -n "$default_branch" ] && [ "$default_branch" != "HEAD" ] \
        && [ "$cur_branch" != "$default_branch" ]; then
        ahead=$(git rev-list --count "origin/${default_branch}..HEAD" 2>/dev/null)
        if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
            echo "ℹ 當前分支 ${cur_branch} 相對 origin/${default_branch} 有 ${ahead} 顆未併 commit——若要開 worktree 延續這條線,base 用 head(全域預設 fresh 會從 origin/${default_branch} 分出去,變成平行線)。"
        fi
    fi
fi

branch=$(git rev-parse --abbrev-ref HEAD) || exit 0
[ "$branch" != "HEAD" ] || exit 0   # detached HEAD 無 upstream 概念,不偵測

# upstream:優先當前 branch 的 @{u},否則試 origin/<branch>
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
if [ -z "$upstream" ]; then
    git rev-parse --verify "origin/$branch" >/dev/null 2>&1 && upstream="origin/$branch"
fi
[ -n "$upstream" ] || exit 0   # 無 remote 對應(純本地 repo)→ 無落後可言

# --- fetch(帶新鮮度快取與 timeout)---------------------------------------------
# linked worktree / submodule 下 $repo_root/.git 是檔案,須用 git-dir 解析真實路徑
git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
fetch_head="$git_dir/FETCH_HEAD"
need_fetch=1
if [ -f "$fetch_head" ]; then
    now=$(date +%s)
    # mtime:GNU stat(Linux)與 BSD stat(macOS)參數不同,兩種都試
    mtime=$(stat -c %Y "$fetch_head" 2>/dev/null || stat -f %m "$fetch_head" 2>/dev/null)
    if [ -n "$mtime" ] && [ $((now - mtime)) -lt "$FETCH_FRESH_SECS" ]; then
        need_fetch=0
    fi
fi

if [ "$need_fetch" -eq 1 ]; then
    # timeout 指令:Linux 內建 timeout、macOS 可能只有 gtimeout(coreutils)、都沒有就裸跑
    if command -v timeout >/dev/null 2>&1; then
        TIMEOUT_CMD="timeout ${FETCH_TIMEOUT_SECS}s"
    elif command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_CMD="gtimeout ${FETCH_TIMEOUT_SECS}s"
    else
        TIMEOUT_CMD=""   # 仍有 ssh ConnectTimeout 護底(本環境 remote 皆為 ssh)
    fi
    remote=${upstream%%/*}
    # GIT_TERMINAL_PROMPT=0:https remote 要求互動認證時直接失敗,不掛住 hook
    GIT_TERMINAL_PROMPT=0 \
    GIT_SSH_COMMAND="ssh -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o BatchMode=yes" \
        $TIMEOUT_CMD git fetch --quiet "$remote" || exit 0   # 離線/逾時/認證失敗 → 靜默放棄
fi

# --- 落後偵測 --------------------------------------------------------------------
behind=$(git rev-list --count "HEAD..$upstream" 2>/dev/null) || exit 0
if [ -n "$behind" ] && [ "$behind" -gt 0 ]; then
    remote_date=$(git log -1 --format=%cs "$upstream" 2>/dev/null)
    echo "⚠ $(basename "$repo_root") 落後 ${upstream} ${behind} 個 commit(remote 最後 commit ${remote_date:-?})——建議先 git pull 再開工。"
fi

# --- STATUS.md(dossier)過期偵測 -------------------------------------------------
if [ -f "$repo_root/STATUS.md" ]; then
    status_ts=$(git log -1 --format=%ct -- STATUS.md 2>/dev/null)
    repo_ts=$(git log -1 --format=%ct 2>/dev/null)
    if [ -n "$status_ts" ] && [ -n "$repo_ts" ]; then
        gap_days=$(( (repo_ts - status_ts) / 86400 ))
        if [ "$gap_days" -gt "$STALE_STATUS_DAYS" ]; then
            echo "ℹ STATUS.md 最後更新落後 repo 活動 ${gap_days} 天——dossier 可能過期,收尾時記得由 /project log 同步。"
        fi
    fi
fi

exit 0
