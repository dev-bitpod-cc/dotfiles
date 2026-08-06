#!/usr/bin/env bash
#
# review-anchor.sh — deep-review 審查錨點的持久 state（單 repo、子指令式）
#
# 為何存在：SKILL.md 原以 prose 要求 model「跨多輪記住」squash base hash 與
# last-codex-HEAD——context 壓縮後記憶遺失，就會退化成 HEAD~1 / moving ref 這類錯誤錨點。
# 本腳本把 state 落地到 .git/ 下的檔案，並印出「已解析完成的指令」供 model 照抄，
# model 全程不經手 hash。
#
# 用法（exit 契約：0=成功；1=verdict STOP（無 anchor/stale/GC/超上限/非 git repo/
#       lib/review-subjects.sh 不可用——僅 squash-cmd）；2=用法錯誤）：
#   review-anchor.sh record     --repo <path> --mode <branch-diff|range|working-tree|baseline> \
#                               [--base <ref>] [--range <X..Y>] [--tests-baseline <pass|fail|skip>]
#       記錄本次審查起點（**不等於 squash 的 reset 目標**——後者由 squash-cmd 自此往上掃
#       subject 求得，見下）。base hash 由腳本解析：
#         branch-diff  → merge-base <--base ref> HEAD（分叉點）
#         range        → <X..Y> 的下界（拒三點 range——A...B 為對稱差語意，非錨點）
#         working-tree → 當下 HEAD
#         baseline     → 當下 HEAD（empty-tree 非 commit，絕不作 reset 目標）
#       無條件覆蓋（新一輪 review 開始即重記；codex_* state 一併歸零）。
#       cycle：anchor 仍在就重新 record = 前一場未走完（R5 終止不 squash、故不 clear）→
#         cycle+1 並印告知行，供終止報告分流「同 reviewer 再跑 vs 換視角」；clear 後歸 1。
#       --tests-baseline：autofix 前置跑 verify-tests.sh 的結果（pass/fail/skip），
#         供「修復後驗證」區分「修復改壞」vs「baseline 本來就紅」（fail → 測試不做 gate）。
#       branch-diff / working-tree 模式另印 diff-cmd:（審查範圍的 diff 指令，供照抄轉交
#         subagent；range 模式審查指令 = range 引數本身、baseline 為全庫，兩者不印）。
#   review-anchor.sh show       --repo <path>
#       印出 anchor 內容（跨 session 恢復審查起點用）。
#   review-anchor.sh squash-cmd --repo <path>
#       印出可照抄的 `git reset --soft <固定 hash>`。消費前雙驗：hash 存在（cat-file）
#       + 是 HEAD 祖先（merge-base --is-ancestor；review 期間 rebase/換 branch 即 STOP）。
#       stale 判 ancestry 而非 branch 名——record 在 branch-first 切換前後都合法。
#       reset 目標 = squash base，由 base..HEAD 由新到舊掃 subject 求得（見 cmd_squash_cmd）：
#       只壓 review 循環機械產生的 commit，使用者的語意 commit 原樣保留並以 squash-preserve:
#       攤開。**squash 範圍自此 ≠ 審查範圍**（2026-08-06 刻意推翻 2026-07-21「兩者恆等」的
#       拍板）——審查完整性不受影響：squash 後 branch 上的內容總和仍等於審查範圍，只是
#       commit 邊界不同；而語意 commit 有參照價值（PR 逐 commit 可讀），不該被收尾壓平。
#   review-anchor.sh codex-next --repo <path> [--full]
#       取「下一輪 codex 審查」的 round 與 range，並原子性記錄本輪 HEAD（消滅「忘記
#       更新 last-codex-HEAD 導致 C2 重審或漏審」的記憶失誤）：
#         C1（首輪全審）：diff 模式 = <anchor-base>..HEAD；baseline = <empty-tree>..HEAD
#         C2+（增量驗收）：<上輪 codex HEAD>..HEAD——為何增量安全：變更集前段 C1 已全審，
#           C2+ 只需驗「新修復是否正確 + 是否引入新問題」；錨定的 last-codex-HEAD 既不漏
#           前段（anti-HEAD~1）也不重審燒額度
#         同 HEAD 重呼叫 → 冪等重印上輪結果（codex run 失敗重試時 round 不誤增）
#         --full = `codex full` 推翻鍵：range 恆為 C1 全 scope，round 照常推進
#         超過 C3 → STOP（exit 1），state 不前進
#   review-anchor.sh clear      --repo <path>
#       squash commit 完成後呼叫；刪除 anchor 檔（幂等）。刪前印內容供追溯。
#       不歸檔——anchor 只是可推導的 hash，殘留會誤導後續 session。
#
# state 檔：$(git rev-parse --absolute-git-dir)/deep-review/anchor（key=value）。
#   linked worktree 下 rev-parse 自動落到 per-worktree 目錄，各 worktree 隔離。
#   同 worktree 併行兩場 review 時後寫者勝（與 codex-exec-review rollout 回退同精神）。
#
# 依賴：git。不 mutation git state（不 commit、不 switch、不 reset）——mutation 指令
# 印出來由 model 照抄，維持 skill 腳本 git-唯讀慣例。

set -uo pipefail

# 照抄行裡的路徑一律過這個 helper——直接插進單引號會在路徑含單引號時讓 quoting 破裂
# （實測 `/tmp/alice's-repo` 產出的行 `bash -n` 直接 syntax error）。三支腳本各留一份 3 行
# 純函式：它是標準演算法、不是會漂移的事實，比為它多開一個跨 skill lib 依賴划算。
shq() { local q="'"; printf "%s%s%s" "$q" "${1//$q/$q\\$q$q}" "$q"; }

die_usage() { echo "error: $*" >&2; exit 2; }

# 錨點消費失敗的統一出口：印 STOP verdict、exit 1
die_stop() { echo "verdict: STOP — $*"; exit 1; }

fmt_epoch() {
    # macOS/BSD 用 -r <秒>；GNU 的 -r 是檔案語意故 fallback 到 -d @；再不行印原值
    date -r "$1" +'%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" +'%Y-%m-%d %H:%M' 2>/dev/null || echo "$1"
}

# 原子寫 anchor（stdin → 同目錄 tmp → mv）：terminate/resume 是在既有檔上做增刪，
# 中途中斷留下半份檔比不寫更糟——後續 aget 會讀到殘缺 state 卻無從察覺。
atomic_write_anchor() {
    local tmp="${ANCHOR}.tmp.$$"
    cat > "$tmp" && mv -f "$tmp" "$ANCHOR"
}

# 自 anchor 檔取 key（檔不存在回空）
aget() { sed -n "s/^$1=//p" "$ANCHOR" 2>/dev/null | head -1; }

# review 循環機械產生的 commit subject —— 定義在 lib/review-subjects.sh（三個消費者共用：
# 本檔的 squash 掃描、review-state.sh 的 round 偵測、project/ship-state.sh 的 review-residue；
# 改 pattern 前三個都要驗，理由與各自的漂移後果見該檔）。此處只負責加錨點。
REVIEW_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/review-subjects.sh"
HAVE_REVIEW_LIB=0
if [ -f "$REVIEW_LIB" ]; then
    # shellcheck source=lib/review-subjects.sh
    . "$REVIEW_LIB" && HAVE_REVIEW_LIB=1
fi
REVIEW_SUBJECT_RE="^(${REVIEW_SUBJECT_ALT:-})\$"

[ $# -ge 1 ] || die_usage "缺少子指令（record|show|squash-cmd|codex-next|clear）"
SUB="$1"; shift

REPO="" MODE_VAL="" BASE_REF="" RANGE_VAL="" TB_VAL="" REASON_VAL="" FULL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)  REPO="${2:-}";      shift 2 || die_usage "--repo 缺少值" ;;
        --mode)  MODE_VAL="${2:-}";  shift 2 || die_usage "--mode 缺少值" ;;
        --base)  BASE_REF="${2:-}";  shift 2 || die_usage "--base 缺少值" ;;
        --range) RANGE_VAL="${2:-}"; shift 2 || die_usage "--range 缺少值" ;;
        --tests-baseline) TB_VAL="${2:-}"; shift 2 || die_usage "--tests-baseline 缺少值" ;;
        --reason) REASON_VAL="${2:-}"; shift 2 || die_usage "--reason 缺少值" ;;
        --full)  FULL=1; shift ;;
        *) die_usage "未知引數：$1" ;;
    esac
done
case "$TB_VAL" in
    ""|pass|fail|skip) : ;;
    *) die_usage "--tests-baseline 應為 pass|fail|skip：${TB_VAL}" ;;
esac
[ -n "$REPO" ] || die_usage "缺少 --repo"

case "$SUB" in
    record|show|squash-cmd|codex-next|clear|terminate|resume-after-terminal) : ;;
    *) die_usage "未知子指令：${SUB}（record|show|squash-cmd|codex-next|clear|terminate|resume-after-terminal）" ;;
esac

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: 不是 git repo（或路徑不存在）：${REPO}" >&2
    exit 1
fi
GITDIR="$(git -C "$REPO" rev-parse --absolute-git-dir)"
# 照抄行（diff-cmd / squash-cmd / codex-cmd）一律印 toplevel 絕對路徑，不印呼叫端給的 $REPO：
# 那可能是相對路徑，而照抄行常在另一個 cwd 執行，指到別的 repo 或直接失敗（ship-state.sh
# 對同類輸出已是此慣例，兩支對齊）。
REPO_ABS="$(git -C "$REPO" rev-parse --show-toplevel)" || REPO_ABS="$REPO"
ANCHOR="$GITDIR/deep-review/anchor"

echo "=== $REPO ==="

cmd_record() {
    # terminal 檢查放在最前面：先重算再覆蓋，等於讓終止狀態靜默消失（2026-08-06 的 RED
    # 正是「R5 終止 → 又開一場」，外層 orchestration 重置了輪次上限）。
    if [ -f "$ANCHOR" ]; then
        local t_reason
        t_reason="$(aget terminal_reason)"
        if [ -n "$t_reason" ]; then
            die_stop "前一場審查已終止（terminal_reason=${t_reason}）——不得靜默重開新 cycle。續審同一批變更：\`resume-after-terminal\`；重建全新審查範圍：\`clear\` 再 \`record\`。先照終止報告的續跑分流判斷走哪條。"
        fi
    fi
    local base_hash
    case "$MODE_VAL" in
        branch-diff)
            [ -n "$BASE_REF" ] || die_usage "--mode branch-diff 需要 --base <ref>（取 review-state 的 base: 輸出）"
            if ! base_hash="$(git -C "$REPO" merge-base "$BASE_REF" HEAD 2>/dev/null)"; then
                echo "error: merge-base ${BASE_REF} HEAD 失敗（ref 不存在？）" >&2
                exit 1
            fi
            ;;
        range)
            [ -n "$RANGE_VAL" ] || die_usage "--mode range 需要 --range <X..Y>"
            case "$RANGE_VAL" in
                *...*) die_usage "拒絕三點 range（A...B 為對稱差語意，錨點需兩點 range 的下界）：${RANGE_VAL}" ;;
                *..*)  : ;;
                *)     die_usage "--range 應為 X..Y 形式：${RANGE_VAL}" ;;
            esac
            local lower="${RANGE_VAL%%..*}"
            if ! base_hash="$(git -C "$REPO" rev-parse --verify --quiet "${lower}^{commit}")"; then
                echo "error: range 下界無法解析為 commit：${lower}" >&2
                exit 1
            fi
            ;;
        working-tree|baseline)
            base_hash="$(git -C "$REPO" rev-parse HEAD)" || exit 1
            ;;
        "") die_usage "record 需要 --mode <branch-diff|range|working-tree|baseline>" ;;
        *)  die_usage "--mode 應為 branch-diff|range|working-tree|baseline：${MODE_VAL}" ;;
    esac
    if ! git -C "$REPO" cat-file -e "${base_hash}^{commit}" 2>/dev/null; then
        echo "error: 解析出的 base 不是 commit：${base_hash}" >&2
        exit 1
    fi
    local branch
    branch="$(git -C "$REPO" symbolic-ref --short -q HEAD)" || branch="DETACHED"
    # 續跑週期：anchor 仍在 = 前一場 review 未走完（R5 終止不 squash、也就不 clear）。
    # 不比對 base hash——working-tree 模式續跑時 HEAD 已因 fix commits 前進，比對必失效。
    # 舊版 anchor 無 cycle key → 視為 1，本次即第 2 週期。
    local prev_cycle cycle=1
    if [ -f "$ANCHOR" ]; then
        prev_cycle="$(aget cycle)"
        cycle=$(( ${prev_cycle:-1} + 1 ))
    fi
    mkdir -p "$GITDIR/deep-review"
    {
        printf 'base=%s\n'     "$base_hash"
        printf 'mode=%s\n'     "$MODE_VAL"
        printf 'branch=%s\n'   "$branch"
        printf 'recorded=%s\n' "$(date +%s)"
        printf 'cycle=%s\n'    "$cycle"
        # head_at_record：目前**無讀者**（原為 squash 既有-commit 判定的時間邊界，2026-08-06
        # 改純 subject 掃描後移除該用途——它在分岔歷史下自身會誤判，codex C3 F2）。保留是為了
        # 追溯「這場 review 從哪個 HEAD 起跑」，codex-next 重寫 anchor 時一併保存。
        # 要新增讀者前先想清楚分岔情境，別直接當可信的祖先邊界用。
        printf 'head_at_record=%s\n' "$(git -C "$REPO" rev-parse HEAD)"
        [ -n "$TB_VAL" ] && printf 'tests_baseline=%s\n' "$TB_VAL"
    } > "$ANCHOR"
    echo "anchor-recorded: ${base_hash}（mode=${MODE_VAL}${BASE_REF:+, base-ref=${BASE_REF}}）"
    echo "branch: ${branch}"
    if [ "$cycle" -gt 1 ]; then
        echo "cycle: ${cycle} — 前一場 review 未走完即重啟（R5 終止後續跑，或中途放棄）；終止報告須據此分流，勿逕自再跑一輪"
    fi
    [ -n "$TB_VAL" ] && echo "tests-baseline: ${TB_VAL}"
    # range 模式審查指令 = range 引數本身、baseline 為全庫審查，...HEAD 都會審錯範圍——不印
    case "$MODE_VAL" in
        branch-diff|working-tree)
            echo "diff-cmd: git -C $(shq "$REPO_ABS") diff ${base_hash}...HEAD" ;;
    esac
}

cmd_show() {
    if [ ! -f "$ANCHOR" ]; then
        echo "anchor: NONE"
        die_stop "無 anchor（先跑 record）"
    fi
    echo "anchor: $(aget base)（mode=$(aget mode), branch 當時=$(aget branch), recorded $(fmt_epoch "$(aget recorded)")）"
    local cyc
    cyc="$(aget cycle)"
    if [ "${cyc:-1}" -gt 1 ] 2>/dev/null; then
        echo "cycle: ${cyc} — 本批變更的第 ${cyc} 個 review 週期（前一場未走完）"
    fi
    if [ -n "$(aget tests_baseline)" ]; then
        echo "tests-baseline: $(aget tests_baseline)"
    fi
    if [ -n "$(aget codex_head)" ]; then
        echo "codex: C$(aget codex_round) 已審至 $(aget codex_head)（range $(aget codex_range)）"
    fi
}

# 消費前雙驗（squash-cmd 與 codex-next 共用）：hash 存在 + 是 HEAD 祖先
verify_hash_usable() {
    local hash="$1" label="$2"
    if ! git -C "$REPO" cat-file -e "${hash}^{commit}" 2>/dev/null; then
        die_stop "${label} 已不存在（GC/rebase？）——重新 record 或交還使用者"
    fi
    if ! git -C "$REPO" merge-base --is-ancestor "$hash" HEAD 2>/dev/null; then
        die_stop "${label} 已非 HEAD 祖先（review 期間 rebase/換 branch？）——不可沿用，交還使用者"
    fi
}

cmd_squash_cmd() {
    [ -f "$ANCHOR" ] || die_stop "無 anchor（先跑 record）"
    # 只有本子指令需要 subject 清單。缺席時 STOP 而非用空 regex 硬跑——後者會把每顆 commit
    # 都會被當成語意 commit、squash 範圍恆為空，看起來「成功」卻什麼都沒壓（靜默失效）。
    [ "$HAVE_REVIEW_LIB" -eq 1 ] || die_stop "lib/review-subjects.sh 不可用——無法判定哪些 commit 屬 review 循環，拒絕給 reset 目標（勿憑印象挑）"
    local base_hash
    base_hash="$(aget base)"
    echo "anchor: ${base_hash}（mode=$(aget mode), branch 當時=$(aget branch), recorded $(fmt_epoch "$(aget recorded)")）"
    verify_hash_usable "$base_hash" "anchor hash"
    # squash base：base..HEAD 由新到舊掃，跳過 review 樣式 commit，停在第一顆真語意 commit
    # （該顆本身保留、成為 reset 目標）。全為樣式 → 退回 anchor base（下界保護，也是
    # working-tree 模式的原行為：WIP snapshot + fix commits 全壓成一顆）。
    # 掃描碰到語意 commit 就停、不跨越——review commit 被他線 commit 隔開時保守少壓，
    # 未納入的那幾顆以 squash-note: 攤開，由主 agent 轉述給使用者處置。
    # 撞名取捨：使用者手寫的 commit 若 subject 恰為那四個機械字串之一，會被當成 review 產生
    # 而壓掉。人工撞名機率極低，且後果等同舊實作（舊版同樣全壓、只多印一行 warning），
    # 故不加 head_at_record 之類的補償判定——它在分岔歷史下自身就會誤判（codex C3 F2）。
    local squash_base="$base_hash" h s n n_pre n_note
    while IFS=$'\t' read -r h s; do
        [ -n "$h" ] || continue
        if grep -Eq "$REVIEW_SUBJECT_RE" <<< "$s"; then continue; fi
        squash_base="$h"
        break
    done <<< "$(git -C "$REPO" log --topo-order --format='%H%x09%s' "${base_hash}..HEAD")"

    n="$(git -C "$REPO" rev-list --count "${squash_base}..HEAD")"
    echo "squash-range: ${squash_base}..HEAD（${n} commit）"
    if [ "$n" -eq 0 ]; then
        # 兩種來源：branch 上真的沒有新 commit，或 HEAD 本身即語意 commit（掃描停在原地）。
        # 後者下方仍可能印 squash-note: 指出有 review commit 存在——兩行不衝突：確實沒有
        # 「可安全壓的範圍」，被隔開的那幾顆要不要併由使用者決定。
        echo "verdict: WARNING — 無 commit 可 squash（squash base 已是 HEAD，reset 無作用；下方若有 squash-note: 表示有 review commit 被語意 commit 隔在下層）"
    else
        git -C "$REPO" log --oneline "${squash_base}..HEAD" | sed 's/^/  /'
    fi
    if [ "$squash_base" != "$base_hash" ]; then
        n_pre="$(git -C "$REPO" rev-list --count "${base_hash}..${squash_base}")"
        echo "squash-preserve: ${n_pre} 顆 commit 保留（不納入 squash；若其中含 review 樣式者，下行 squash-note: 會點出）"
        git -C "$REPO" log --oneline "${base_hash}..${squash_base}" | sed 's/^/  /'
        # 大輸入下 `git log | grep` 會讓 grep 早退觸發 SIGPIPE + pipefail 判偽 → 用 herestring
        n_note="$(grep -Ec "$REVIEW_SUBJECT_RE" <<< "$(git -C "$REPO" log --format=%s "${base_hash}..${squash_base}")")" || true
        if [ "${n_note:-0}" -gt 0 ]; then
            echo "squash-note: 保留範圍內仍有 ${n_note} 顆 review 樣式 commit（被非 review commit 隔開，未納入 squash）"
        fi
    fi
    echo "squash-cmd: git -C $(shq "$REPO_ABS") reset --soft ${squash_base}"
}

cmd_codex_next() {
    [ -f "$ANCHOR" ] || die_stop "無 anchor（先跑 record）"
    local base_hash mode_v branch_v recorded_v cycle_v har_v tb_v head_full empty_tree c_head c_round round range
    base_hash="$(aget base)"
    mode_v="$(aget mode)"
    branch_v="$(aget branch)"
    recorded_v="$(aget recorded)"
    cycle_v="$(aget cycle)"
    har_v="$(aget head_at_record)"
    tb_v="$(aget tests_baseline)"
    c_head="$(aget codex_head)"
    c_round="$(aget codex_round)"
    head_full="$(git -C "$REPO" rev-parse HEAD)" || exit 1
    empty_tree="$(git hash-object -t tree /dev/null)"

    # C1 全 scope（--full 與首輪共用）
    c1_scope() {
        if [ "$mode_v" = "baseline" ]; then
            echo "${empty_tree}..${head_full}"
        else
            echo "${base_hash}..${head_full}"
        fi
    }

    if [ -z "$c_head" ]; then
        round=1
        if [ "$mode_v" != "baseline" ]; then
            verify_hash_usable "$base_hash" "anchor hash"
        fi
        range="$(c1_scope)"
    elif [ "$c_head" = "$head_full" ]; then
        # 冪等重印：codex run 失敗重試場景，round 不誤增、state 不動
        echo "codex-round: C$(aget codex_round)"
        echo "codex-range: $(aget codex_range)"
        echo "codex-cmd: ~/.claude/skills/deep-review/scripts/codex-exec-review.sh run --repo $(shq "$REPO_ABS") --range $(aget codex_range) --round C$(aget codex_round)"
        return 0
    else
        round=$((c_round + 1))
        if [ "$round" -gt 3 ]; then
            die_stop "已達 3 輪 codex 上限（C3）仍有新 commit 未審——輸出 codex 終止報告，交還使用者"
        fi
        verify_hash_usable "$c_head" "上輪 codex HEAD"
        if [ "$FULL" -eq 1 ]; then
            range="$(c1_scope)"
        else
            range="${c_head}..${head_full}"
        fi
    fi

    {
        printf 'base=%s\n'        "$base_hash"
        printf 'mode=%s\n'        "$mode_v"
        printf 'branch=%s\n'      "$branch_v"
        printf 'recorded=%s\n'    "$recorded_v"
        [ -n "$cycle_v" ] && printf 'cycle=%s\n' "$cycle_v"
        [ -n "$har_v" ] && printf 'head_at_record=%s\n' "$har_v"
        [ -n "$tb_v" ] && printf 'tests_baseline=%s\n' "$tb_v"
        printf 'codex_head=%s\n'  "$head_full"
        printf 'codex_round=%s\n' "$round"
        printf 'codex_range=%s\n' "$range"
    } > "$ANCHOR"

    echo "codex-round: C${round}"
    echo "codex-range: ${range}"
    echo "codex-cmd: ~/.claude/skills/deep-review/scripts/codex-exec-review.sh run --repo $(shq "$REPO_ABS") --range ${range} --round C${round}"
}

# 把「這場審查已終止」寫成可觀察狀態。cycle 判別不了成因（終止/中途停止/crash/刻意續跑），
# 靠它猜等於再寫一條 agent 規則。**只支援 r5-blocking**：codex-c3 會引入不同的 resume 語意
# （anchor 已有 codex_round=3，清 terminal 後 codex-next 直接 C4 STOP 或重印 C3），
# user-abort 則不可靠（真 interrupt 時未必還能執行工具）——兩者都等真的出現 RED 再設計。
cmd_terminate() {
    [ -f "$ANCHOR" ] || die_stop "無 anchor（沒有進行中的審查可終止）"
    [ "$REASON_VAL" = "r5-blocking" ] || die_usage "--reason 目前只支援 r5-blocking（收到：${REASON_VAL:-空}）"
    local existing
    existing="$(aget terminal_reason)"
    if [ -n "$existing" ]; then
        [ "$existing" = "$REASON_VAL" ] || die_stop "已標記 terminal_reason=${existing}，拒絕改成 ${REASON_VAL}（換 reason 須先 clear）"
        echo "terminal: ${existing}（已標記，冪等）"
        return 0
    fi
    {
        cat "$ANCHOR"
        printf 'terminal_reason=%s\n' "$REASON_VAL"
        printf 'terminal_head=%s\n'   "$(git -C "$REPO" rev-parse HEAD)"
        printf 'terminal_at=%s\n'     "$(date +%s)"
    } | atomic_write_anchor
    echo "terminal: r5-blocking 已落盤——下一次 record 會 STOP。續審用 resume-after-terminal；重建範圍用 clear + record。"
}

# 與 record 語意刻意不同：record 是「重新解析範圍、無條件覆寫、codex state 歸零」，
# 本指令是「同一批變更再審一場」——base 與其餘欄位全部保留，只清 terminal 並推進 cycle。
cmd_resume_after_terminal() {
    [ -f "$ANCHOR" ] || die_stop "無 anchor"
    local reason cycle_v next
    reason="$(aget terminal_reason)"
    [ -n "$reason" ] || die_stop "anchor 未標記 terminal（沒有可 resume 的終止狀態；要開新一場請用 record）"
    [ "$reason" = "r5-blocking" ] || die_stop "terminal_reason=${reason} 不在本指令支援範圍"
    cycle_v="$(aget cycle)"
    next=$(( ${cycle_v:-1} + 1 ))
    # sed 刪除 terminal_* 並就地推進 cycle——用 sed 不用 grep -v：後者無匹配時 exit 1，
    # pipefail 下會讓整條管線判偽（本檔已有同型地雷的紀錄）
    sed -e '/^terminal_/d' -e "s/^cycle=.*/cycle=${next}/" "$ANCHOR" | atomic_write_anchor
    echo "resumed: terminal 已清、cycle → ${next}（base 不變。要重建審查範圍請改用 clear + record）"
}

cmd_clear() {
    if [ -f "$ANCHOR" ]; then
        echo "cleared（原內容，供追溯）:"
        sed 's/^/  /' "$ANCHOR"
        rm -f "$ANCHOR"
    else
        echo "cleared: 無 anchor 檔（幂等）"
    fi
}

case "$SUB" in
    record)     cmd_record ;;
    show)       cmd_show ;;
    squash-cmd) cmd_squash_cmd ;;
    codex-next) cmd_codex_next ;;
    clear)      cmd_clear ;;
    terminate)              cmd_terminate ;;
    resume-after-terminal)  cmd_resume_after_terminal ;;
esac
