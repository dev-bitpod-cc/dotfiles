#!/usr/bin/env bash
#
# review-anchor.sh — deep-review 審查錨點的持久 state（單 repo、子指令式）
#
# 為何存在：SKILL.md 原以 prose 要求 model「跨多輪記住」squash base hash 與
# last-codex-HEAD——context 壓縮後記憶遺失，就會退化成 HEAD~1 / moving ref 這類錯誤錨點。
# 本腳本把 state 落地到 .git/ 下的檔案，並印出「已解析完成的指令」供 model 照抄，
# model 全程不經手 hash。
#
# 用法（exit 契約：0=成功；1=verdict STOP（無 anchor/stale/GC/超上限/非 git repo）；2=用法錯誤）：
#   review-anchor.sh record     --repo <path> --mode <branch-diff|range|working-tree|baseline> \
#                               [--base <ref>] [--range <X..Y>] [--tests-baseline <pass|fail|skip>]
#       記錄本次審查起點（squash 的 reset 目標）。base hash 由腳本解析：
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
#       squash 範圍含「審查前既有 commits」（subject 非 review 產生的固定樣式）時印
#       warning: 行——維持「squash 範圍恆等審查範圍」語意不變，僅告知（2026-07-21 拍板）。
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

die_usage() { echo "error: $*" >&2; exit 2; }

# 錨點消費失敗的統一出口：印 STOP verdict、exit 1
die_stop() { echo "verdict: STOP — $*"; exit 1; }

fmt_epoch() {
    # macOS/BSD 用 -r <秒>；GNU 的 -r 是檔案語意故 fallback 到 -d @；再不行印原值
    date -r "$1" +'%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" +'%Y-%m-%d %H:%M' 2>/dev/null || echo "$1"
}

# 自 anchor 檔取 key（檔不存在回空）
aget() { sed -n "s/^$1=//p" "$ANCHOR" 2>/dev/null | head -1; }

[ $# -ge 1 ] || die_usage "缺少子指令（record|show|squash-cmd|codex-next|clear）"
SUB="$1"; shift

REPO="" MODE_VAL="" BASE_REF="" RANGE_VAL="" TB_VAL="" FULL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)  REPO="${2:-}";      shift 2 || die_usage "--repo 缺少值" ;;
        --mode)  MODE_VAL="${2:-}";  shift 2 || die_usage "--mode 缺少值" ;;
        --base)  BASE_REF="${2:-}";  shift 2 || die_usage "--base 缺少值" ;;
        --range) RANGE_VAL="${2:-}"; shift 2 || die_usage "--range 缺少值" ;;
        --tests-baseline) TB_VAL="${2:-}"; shift 2 || die_usage "--tests-baseline 缺少值" ;;
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
    record|show|squash-cmd|codex-next|clear) : ;;
    *) die_usage "未知子指令：${SUB}（record|show|squash-cmd|codex-next|clear）" ;;
esac

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: 不是 git repo（或路徑不存在）：${REPO}" >&2
    exit 1
fi
GITDIR="$(git -C "$REPO" rev-parse --absolute-git-dir)"
ANCHOR="$GITDIR/deep-review/anchor"

echo "=== $REPO ==="

cmd_record() {
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
            echo "diff-cmd: git -C ${REPO} diff ${base_hash}...HEAD" ;;
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
    local base_hash n
    base_hash="$(aget base)"
    echo "anchor: ${base_hash}（mode=$(aget mode), branch 當時=$(aget branch), recorded $(fmt_epoch "$(aget recorded)")）"
    verify_hash_usable "$base_hash" "anchor hash"
    n="$(git -C "$REPO" rev-list --count "${base_hash}..HEAD")"
    echo "squash-range: ${base_hash}..HEAD（${n} commit）"
    if [ "$n" -eq 0 ]; then
        echo "verdict: WARNING — 無 commit 可 squash（reset 到 HEAD 無作用，照印無害）"
    else
        git -C "$REPO" log --oneline "${base_hash}..HEAD" | sed 's/^/  /'
        # 審查前既有 commits = subject 非 review 產生的固定樣式（R{N} fix / codex fix /
        # wip snapshot；codex 輪標歷史上 R、C 並見，兩者都認）。squash 語意不變、僅告知
        # ——SKILL.md 要求主 agent 在 reset 前向使用者轉述此行。
        local n_pre
        n_pre="$(git -C "$REPO" log --format=%s "${base_hash}..HEAD" \
            | grep -Evc '^(fix: R[0-9]+ review fixes|fix: codex [RC][0-9]+ fixes|wip: pre-review snapshot)$')" || true
        if [ "${n_pre:-0}" -gt 0 ]; then
            echo "warning: 將壓掉 ${n_pre} 顆審查前既有 commit（清單見上，非本次 review 產生）"
        fi
    fi
    echo "squash-cmd: git -C ${REPO} reset --soft ${base_hash}"
}

cmd_codex_next() {
    [ -f "$ANCHOR" ] || die_stop "無 anchor（先跑 record）"
    local base_hash mode_v branch_v recorded_v cycle_v tb_v head_full empty_tree c_head c_round round range
    base_hash="$(aget base)"
    mode_v="$(aget mode)"
    branch_v="$(aget branch)"
    recorded_v="$(aget recorded)"
    cycle_v="$(aget cycle)"
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
        echo "codex-cmd: ~/.claude/skills/deep-review/scripts/codex-exec-review.sh run --repo ${REPO} --range $(aget codex_range) --round C$(aget codex_round)"
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
        [ -n "$tb_v" ] && printf 'tests_baseline=%s\n' "$tb_v"
        printf 'codex_head=%s\n'  "$head_full"
        printf 'codex_round=%s\n' "$round"
        printf 'codex_range=%s\n' "$range"
    } > "$ANCHOR"

    echo "codex-round: C${round}"
    echo "codex-range: ${range}"
    echo "codex-cmd: ~/.claude/skills/deep-review/scripts/codex-exec-review.sh run --repo ${REPO} --range ${range} --round C${round}"
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
esac
