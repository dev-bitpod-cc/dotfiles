#!/usr/bin/env bash
#
# branch-first.sh — /project log Step 1 第 5 項的 branch-first 執行（情況 A/B 自動判定）
#
# 用法：
#   branch-first.sh <repo-path> <type>/<slug>
#
# ⚠ 顯性例外標注：本腳本是 project skill 腳本「git 唯讀慣例」的例外（先例：deep-review
# 的 verify-tests.sh 例外標注模式）。理由：情況 B 救援序列步驟順序敏感，做錯方向會
# 永久銷毀未 commit 變更（壓力下手打是實證失誤來源），屬 skill-building-guide 的
# 「低自由度固定腳本」。mutation 僅限三個指令：
#   git switch -c <feature>                    （情況 A）
#   git branch <feature> + git switch <feature> + git branch -f <default> <remote>/<default>（情況 B）
# NEVER reset --hard. NEVER touch the working tree. NEVER push.
# 何時呼叫仍由 model 依 `../references/log-workflow.md`「Critical — Guardrails」決定，本腳本只負責「決定後安全執行」。
#
# 情況判定（前置檢查全過才動手；any ambiguity → verdict: STOP with zero mutation）：
#   A：HEAD 在 default（無誤 commit）或 detached HEAD → git switch -c。working tree
#      變更與 detached HEAD 上的 commit 一併跟隨；detached 不需 ref 重置——它不移動
#      任何 branch ref。
#   B：誤 commit 在本地 default（領先 <remote>/<default>、快進關係、未被 remote 涵蓋）
#      → branch 保住 commit → switch → branch -f 把本地 default 退回 remote。
#      switch 發生在同一 commit 的兩個 branch 之間、branch -f 是純 ref 操作——
#      兩者都不觸碰 working tree，mixed state（另有未 commit 變更）天然安全。
#
# exit code：0 = 已執行（verdict: OK）；1 = STOP（前置檢查未過，未動任何狀態；
#            或執行中途失敗，訊息說明已完成到哪步）；2 = 用法錯誤
#
# 判定以本地 remote-tracking ref 為準（不 fetch——本腳本不碰網路）。tracking 過舊的
# 後果邊界：情況 B 的「退回 remote」意指退回**本地 remote-tracking ref**，可能落後
# 實際 remote（下次 pull fast-forward 即對齊）；誤 commit 永遠先由 feature branch 接住、
# working tree 不碰——任何 stale 情境都不存在資料損失路徑。tracking 過舊且 remote 實已
# 分岔的情境無法在本地偵測（需 fetch），不在 STOP 保證範圍內；要最新判定，呼叫前
# 自行 fetch 再跑本腳本。
#
# 設計原則：與 ship-state.sh（唯讀偵測）分工——偵測歸偵測、mutation 歸 mutation，
# 各自可獨立驗證（H9）。remote/default 解析規則與 ship-state.sh 一致。

set -uo pipefail

if [ $# -ne 2 ]; then
    echo "用法：$0 <repo-path> <type>/<slug>" >&2
    exit 2
fi

repo="$1"
feature="$2"

if ! git check-ref-format --branch "$feature" >/dev/null 2>&1; then
    echo "用法錯誤：branch 名 ${feature} 非法（git check-ref-format --branch 不過）" >&2
    exit 2
fi

echo "=== $repo ==="

stop() { echo "verdict: STOP（${1}）"; exit 1; }

if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
    stop "不是 git repo（或路徑不存在）"
fi

branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || branch="DETACHED"
echo "branch: $branch"

# canonical remote / default branch：與 ship-state.sh detect_remote/detect_default_branch
# 同一規則（origin 優先、否則第一個；remote HEAD → probe main/master）。刻意的小段重複
# ——偵測/mutation 分離（H9）優先於 DRY，兩邊行為各有測試釘住；規則若改須兩處同步
remotes="$(git -C "$repo" remote)"
if printf '%s\n' "$remotes" | grep -qx origin; then
    remote=origin
else
    remote="$(printf '%s\n' "$remotes" | head -1)"
fi
if [ -z "$remote" ]; then
    stop "無 remote——無法核對誤 commit 是否已被 remote default 涵蓋，交回使用者"
fi
default="$(git -C "$repo" symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null)" || default=""
default="${default#"$remote"/}"
if [ -z "$default" ] || [ "$default" = "HEAD" ]; then
    default=""
    for cand in main master; do
        if git -C "$repo" rev-parse --verify --quiet "$remote/$cand" >/dev/null; then
            default="$cand"
            break
        fi
    done
fi
if [ -z "$default" ]; then
    stop "找不到 default branch（${remote}/HEAD、${remote}/main、${remote}/master 皆無）——若為全新空 repo，branch-first 在此不適用（首推的 branch 會變成遠端 default）：跑 ship-state.sh 取 bootstrap verdict，勿在此硬開 feature branch"
fi
echo "default: ${default}（remote=${remote}）"

if git -C "$repo" show-ref --verify -q "refs/heads/$feature"; then
    stop "feature branch ${feature} 已存在——換個名字，或由使用者自行處理"
fi

if [ "$branch" != "$default" ] && [ "$branch" != "DETACHED" ]; then
    stop "已在 feature branch（${branch}）——branch-first 無事可做，不疊 branch"
fi

# 領先 commit 數（誤 commit 偵測）。detached 一律情況 A：它不移動任何 branch ref，
# switch -c 即可接走其上的 commit（E4）。
if [ "$branch" = "DETACHED" ]; then
    n_ahead=0
else
    n_ahead="$(git -C "$repo" rev-list --count "$remote/$default..HEAD" 2>/dev/null)" \
        || stop "無法計算領先 ${remote}/${default} 的 commit 數"
fi

# porcelain 前後快照（回流自 clean-room 盲寫版）：H6「不觸碰 working tree」的機械
# 驗證——快照不一致代表本腳本自身有 bug，如實回報、不嘗試自動回滾
porcelain_before="$(git -C "$repo" status --porcelain)"

# 後驗證：porcelain 快照一致 + HEAD 已在 feature；失敗 → exit 1 完整回報現狀
verify_after() {
    local porcelain_after head_now
    porcelain_after="$(git -C "$repo" status --porcelain)"
    if [ "$porcelain_after" != "$porcelain_before" ]; then
        echo "verify: FAILED — porcelain 前後不一致（本腳本 bug，working tree 可能被動到，請立即人工檢查）"
        exit 1
    fi
    echo "verify: porcelain 前後一致（working tree 未動）"
    head_now="$(git -C "$repo" symbolic-ref --short -q HEAD)" || head_now="DETACHED"
    if [ "$head_now" != "$feature" ]; then
        echo "verify: FAILED — HEAD 在 ${head_now} 而非 ${feature}，請人工檢查"
        exit 1
    fi
}

if [ "$n_ahead" -gt 0 ]; then
    # 快進關係檢查：remote default 若有本地沒有的 commit（分岔），退回操作的語意
    # 不再是「單純撤下誤 commit」——ambiguous，交回使用者
    if ! git -C "$repo" merge-base --is-ancestor "$remote/$default" HEAD; then
        stop "本地 ${default} 與 ${remote}/${default} 分岔（remote 已被推進？）——非單純誤 commit，交回使用者處理"
    fi
    echo "case: B（${n_ahead} commit 誤 commit 在本地 ${default}、未被 ${remote}/${default} 涵蓋）"
    echo "exec: git branch ${feature}"
    br_err="$(git -C "$repo" branch "$feature" 2>&1 >/dev/null)" \
        || stop "git branch 失敗：${br_err}——未動任何狀態"
    echo "exec: git switch ${feature}"
    sw_err="$(git -C "$repo" switch "$feature" 2>&1 >/dev/null)" \
        || stop "git switch 失敗：${sw_err}——commit 已由 ${feature} 保住，${default} 未動，請手動檢查"
    echo "exec: git branch -f ${default} ${remote}/${default}"
    bf_err="$(git -C "$repo" branch -f "$default" "$remote/$default" 2>&1 >/dev/null)" \
        || stop "branch -f 失敗：${bf_err}——commit 已由 ${feature} 保住並已切換，僅 ${default} 未退回"
    verify_after
    if [ "$(git -C "$repo" rev-parse "$default")" != "$(git -C "$repo" rev-parse "$remote/$default")" ]; then
        echo "verify: FAILED — ${default} 未退回 ${remote}/${default}，請人工檢查"
        exit 1
    fi
    echo "verdict: OK（${feature} 接住 ${n_ahead} commit；${default} 已退回 ${remote}/${default}；working tree 未動）"
else
    echo "case: A（${branch} 上無誤 commit——switch -c，working tree 變更與 detached commit 跟隨）"
    echo "exec: git switch -c ${feature}"
    sw_err="$(git -C "$repo" switch -c "$feature" 2>&1 >/dev/null)" \
        || stop "git switch -c 失敗：${sw_err}"
    verify_after
    echo "verdict: OK（已在 ${feature}；未動任何既有 ref、未動 working tree）"
fi
exit 0
