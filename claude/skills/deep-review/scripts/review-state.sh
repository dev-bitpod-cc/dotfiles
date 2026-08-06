#!/usr/bin/env bash
#
# review-state.sh — deep-review Step 0/1/2 的審查狀態偵測（單次呼叫、多 repo、唯讀）
#
# 用法：
#   review-state.sh <repo-path>...
#
# 逐 repo 輸出：branch / base（含偵測途徑）/ working-tree（porcelain 含 untracked）/
# ahead（<base>..HEAD）/ scope-priority 建議 / round（review 機械修復 commit 推斷）/
# hashes（HEAD、merge-base——squash base 表的候選值）/ stat（建議 scope 的 diff 概覽）。
#
# exit code：0 = 全部 repo 偵測完成；1 = 有 repo 無效；2 = 用法錯誤
#
# 設計原則：
# - 唯讀。不寫 index（不 add -N）、不 commit、不 switch。
# - 只做「無引數」情境的 priority 2/3/4 事實偵測；有引數（priority 1，range/path）
#   的語意解讀仍由 model 依 SKILL.md 判定，但 base / round / hashes 照樣可沿用本輸出。
# - priority 4 的範圍選擇是使用者的事——腳本印 MUST ASK USER，不代選。

set -uo pipefail

# round 偵測要認得哪些 subject 屬 review 循環——與 review-anchor.sh 的 squash 掃描共用同一份。
# 缺席時降級（round 恆 1）而非中途 unbound variable 死掉：本腳本的其餘輸出（base / 變更集 /
# branch-first）與這份 pattern 無關，不該被它拖垮——與另兩個消費者的降級處置一致。
REVIEW_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/review-subjects.sh"
HAVE_REVIEW_LIB=0
if [ -f "$REVIEW_LIB" ]; then
    # shellcheck source=lib/review-subjects.sh
    . "$REVIEW_LIB" && HAVE_REVIEW_LIB=1
fi

MAX_LIST=20  # 每類清單最多列出的行數；只影響顯示，計數仍為完整值

if [ $# -eq 0 ]; then
    echo "用法：$0 <repo-path>..." >&2
    exit 2
fi

overall=0

# 照抄行裡的路徑一律過這個 helper——直接插進單引號會在路徑含單引號時讓 quoting 破裂
# （實測 `/tmp/alice's-repo` 產出的行 `bash -n` 直接 syntax error）。三支腳本各留一份 3 行
# 純函式：它是標準演算法、不是會漂移的事實，比為它多開一個跨 skill lib 依賴划算。
shq() { local q="'"; printf "%s%s%s" "$q" "${1//$q/$q\\$q$q}" "$q"; }

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

# base branch 偵測（SKILL Step 1 priority 3 的順序）：
#   有 remote → remote HEAD → remote/main → remote/master
#   無 remote → 本地 main → master
# 輸出完整 ref（如 origin/main 或 main）；找不到輸出空字串
detect_base() {
    local repo="$1" remote="$2" ref cand
    if [ -n "$remote" ]; then
        ref="$(git -C "$repo" symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null)" || ref=""
        if [ -n "$ref" ] && [ "$ref" != "$remote/HEAD" ]; then
            echo "$ref"
            return 0
        fi
        for cand in main master; do
            if git -C "$repo" rev-parse --verify --quiet "$remote/$cand" >/dev/null; then
                echo "$remote/$cand"
                return 0
            fi
        done
    else
        for cand in main master; do
            if git -C "$repo" rev-parse --verify --quiet "refs/heads/$cand" >/dev/null; then
                echo "$cand"
                return 0
            fi
        done
    fi
    echo ""
}

check_repo() {
    local repo="$1"

    echo "=== $repo ==="

    if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "error: 不是 git repo（或路徑不存在）"
        return 1
    fi

    local branch remote base toplevel
    # 照抄行用絕對路徑（同 review-anchor.sh 的理由：照抄處的 cwd 未必是這裡）
    toplevel="$(git -C "$repo" rev-parse --show-toplevel)" || toplevel="$repo"
    branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || branch="DETACHED"
    echo "branch: $branch"

    remote="$(detect_remote "$repo")"
    local remotes_n
    remotes_n="$(git -C "$repo" remote | wc -l | tr -d ' ')"
    if [ "$remotes_n" -gt 1 ]; then
        echo "remotes: $remotes_n 個（腳本取 ${remote}）— 非 autofix 模式須向使用者確認以哪個 remote 為基準"
    fi
    base="$(detect_base "$repo" "$remote")"
    if [ -n "$base" ]; then
        echo "base: ${base}（remote=${remote:-無，退用本地 branch}）"
    else
        echo "base: NONE（無 remote HEAD / main / master 可用）"
    fi

    # -- working tree（含 untracked）--
    local porcelain n_dirty untracked
    # -uall：預設會把整個未追蹤目錄折疊成單行 "?? dir/"，而契約模板要求 reviewer
    # 逐檔讀取——拿到目錄名會整批漏審（codex C3 F1 實測）。展開成個別檔案。
    porcelain="$(git -C "$repo" status --porcelain -uall)"
    if [ -n "$porcelain" ]; then
        n_dirty="$(printf '%s\n' "$porcelain" | wc -l | tr -d ' ')"
        echo "working-tree: $n_dirty 檔（含 untracked）"
        printf '%s\n' "$porcelain" | print_list "$n_dirty"
        # untracked 另列：git diff HEAD 看不到它們，subagent 須逐檔 Read
        untracked="$(printf '%s\n' "$porcelain" | grep '^??' | sed 's/^?? //')" || untracked=""
        if [ -n "$untracked" ]; then
            echo "untracked（git diff HEAD 不含，須逐檔讀）:"
            printf '%s\n' "$untracked" | sed 's/^/  /'
        fi
    else
        n_dirty=0
        echo "working-tree: clean"
    fi

    # -- 領先 base 的 commit --
    local ahead n_ahead=0
    if [ -n "$base" ]; then
        if ahead="$(git -C "$repo" log --oneline "$base..HEAD" 2>/dev/null)"; then
            if [ -n "$ahead" ]; then
                n_ahead="$(printf '%s\n' "$ahead" | wc -l | tr -d ' ')"
                echo "ahead: $n_ahead commit（$base..HEAD）"
                printf '%s\n' "$ahead" | print_list "$n_ahead"
            else
                echo "ahead: none"
            fi
        else
            echo "ahead: UNKNOWN（log $base..HEAD 執行失敗）"
        fi
    else
        echo "ahead: n/a（無 base）"
    fi

    # -- 銜接檢查（迭代紀律：dirty tree + 已有 branch commit → 可能忘記 commit 上一輪修復）--
    if [ "$n_dirty" -gt 0 ] && [ "$n_ahead" -gt 0 ]; then
        echo "continuity: WARNING — working tree ${n_dirty} 檔未 commit 且 ${base}..HEAD 已有 ${n_ahead} commit：可能忘記 commit 上一輪修復，先 commit 再續（baseline 模式忽略此警告）"
    fi

    # -- scope priority 建議（僅無引數情境；priority 1 引數由 model 判）--
    local priority
    if [ "$n_dirty" -gt 0 ]; then
        priority=2
        echo "scope-priority: 2（working-tree diff：git diff HEAD ＋ untracked 逐檔讀）"
    elif [ -n "$base" ] && [ "$n_ahead" -gt 0 ]; then
        priority=3
        echo "scope-priority: 3（branch diff：$base...HEAD）"
    else
        priority=4
        echo "scope-priority: 4 — MUST ASK USER（clean 且未領先 base／無 base）。Scope is the user's call — present the options (最後一個 commit / 整條 branch / 全庫) and STOP. Do NOT pick one yourself."
        # 全庫選項的 base；值由 git 推導（empty tree 為 git 內建常數 4b825dc6...），不 hardcode
        echo "empty-tree: $(git hash-object -t tree /dev/null)（全庫選項的 base；tree 非 commit，不可作 reset 目標）"
    fi

    # -- round 偵測（baseline 模式一律 Round 1，由 model 依模式覆蓋）--
    local n_fix=0 subj
    if [ "$HAVE_REVIEW_LIB" -ne 1 ]; then
        echo "round: 1（review-subjects.sh 不可用，無法辨識 review 機械 commit——輪次視為 1，勿憑印象推斷）"
    elif [ -n "$base" ] && [ "$n_ahead" -gt 0 ]; then
        # 從 HEAD 往回數**連續**的 review 機械修復 commit，遇到任何其他 subject 即停。
        # 為何是連續段而非整個範圍：**被語意 commit 隔開的上一場殘留**（squash-note 情境）
        # 不會灌進新一場的輪次、白吃 R5 修復額度。
        # 與 squash 掃描是**刻意不同的兩套集合，邊界也不同**，勿重新耦合：
        #   round  用 REVIEW_FIX_ALT      → `wip:` 會**中斷**計數（它不是一輪修復）
        #   squash 用 REVIEW_SUBJECT_ALT  → `wip:` 會被**收攏**（它要跟 fix 一起壓掉）
        # 故 `feat → wip → fix` 下 round 停在 wip、squash 越過 wip 停在 feat（實證）。
        # 取 %s 另跑一次而非解析上面的 --oneline：後者在使用者設了 log.decorate 時會多出
        # `(HEAD -> x)`，行尾錨定就失效；herestring 避開 pipefail + SIGPIPE 早退。
        while IFS= read -r subj; do
            grep -Eq "^(${REVIEW_FIX_ALT})\$" <<< "$subj" || break
            n_fix=$((n_fix + 1))
        done <<< "$(git -C "$repo" log --topo-order --format=%s "$base..HEAD" 2>/dev/null)"
        echo "round: $((n_fix + 1))（$base..HEAD 頂端連續 review 修復 commit ×${n_fix}；使用者自己的 fix:/refactor: 與更早場次的殘留皆不計；baseline 模式一律視為 Round 1）"
    else
        echo "round: 1"
    fi

    # -- hashes（squash base 表候選值：working-tree 模式=HEAD、branch diff=merge-base）--
    local head_hash mb
    head_hash="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" || head_hash="?"
    echo "hash-HEAD: $head_hash"
    if [ -n "$base" ]; then
        if mb="$(git -C "$repo" merge-base "$base" HEAD 2>/dev/null)"; then
            echo "hash-merge-base: ${mb}（$base 與 HEAD 的分叉點）"
        else
            echo "hash-merge-base: UNKNOWN（merge-base 執行失敗）"
        fi
    fi

    # -- branch-first（autofix 第一個 commit 前的 gate；措辭對齊 project/ship-state.sh 的 verdict）--
    local default_name=""
    if [ -n "$base" ]; then
        if [ -n "$remote" ]; then
            default_name="${base#"$remote"/}"
        else
            default_name="$base"
        fi
    fi
    if [ -z "$default_name" ]; then
        echo "branch-first: UNKNOWN（無 default 可判）— autofix 前先與使用者確認"
    elif [ "$branch" = "$default_name" ] || [ "$branch" = "DETACHED" ]; then
        echo "branch-first: REQUIRED（HEAD 在 ${branch} —— autofix 第一個 commit 之前先開 feature branch，無條件）"
        echo "branch-cmd: git -C $(shq "$toplevel") switch -c <type>/<slug>   # <type>/<slug> 由 model 依變更語意取（type ∈ feat/fix/refactor/docs/chore/test）"
    else
        echo "branch-first: 已在 feature branch（${branch}）"
    fi

    # -- diff 概覽（--stat only；完整 diff 由 subagent 自行收集）--
    if [ "$priority" -eq 2 ]; then
        echo "stat（git diff HEAD --stat；untracked 不含在內）:"
        git -C "$repo" diff HEAD --stat | sed 's/^/  /'
    elif [ "$priority" -eq 3 ]; then
        echo "stat（git diff $base...HEAD --stat）:"
        git -C "$repo" diff "$base...HEAD" --stat | sed 's/^/  /'
    fi
}

for repo in "$@"; do
    check_repo "$repo" || overall=1
    echo ""
done

exit "$overall"
