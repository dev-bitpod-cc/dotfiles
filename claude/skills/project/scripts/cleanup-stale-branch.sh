#!/usr/bin/env bash
#
# cleanup-stale-branch.sh — 刪除一支已確認殘留的 branch，執行當下重驗 tip
#
# 用法：
#   cleanup-stale-branch.sh <repo-path> <local|remote> <branch> <expected-sha>
#
# exit code：0 = 已刪除；1 = STOP（前提不成立，零 mutation）；2 = 用法錯誤
#
# 為何存在（而不是照抄一行 `git branch -D`）：
# 偵測與刪除之間有 TOCTOU 窗口——`ship-state.sh` 印出殘留訊號後，另一個 session、另一台
# 主機、或使用者自己都可能在那支 branch 上再 commit。照抄的 `-D` 對此完全無感（它本來
# 就是「不管有沒有 merge 都刪」），砍下去就沒了；而 branch 是那些 commit 的唯一 ref，
# 刪掉即進 unreachable、只剩 reflog 可救，遠端更是直接沒有。把 expected SHA 綁在**執行
# 當下**重驗，才是真的關掉那個窗口——訊號產生時驗過一次不算數，那是舊資訊。
#
# 三道前提，任一不成立即 STOP 且不動任何 ref：
#   1. branch 存在（不存在 ≠ 已成功刪除——可能打錯名字，靜默當成功會讓真正的殘留留著）
#   2. 當下 tip == expected-sha
#   3. local 模式下該 branch 不是 checked-out（git 自己也會拒，但要給明確 verdict，
#      不是把 git 的錯誤訊息丟回去讓呼叫端猜）
#
# remote 模式一律帶 `--force-with-lease=<branch>:<sha>` 才刪：本地的 remote-tracking ref
# 可能過期（沒 fetch 就是舊快照），lease 讓**遠端自己**做最後一次比對——這是唯一不依賴
# 本地資訊正確性的檢查。**NEVER 退化成裸 `push --delete`**，那等於放棄這道保護。

set -uo pipefail

die_usage() { echo "用法：$0 <repo-path> <local|remote> <branch> <expected-sha>" >&2; exit 2; }
die_stop()  { echo "verdict: STOP（$1）"; exit 1; }

[ $# -eq 4 ] || die_usage
REPO="$1"; SCOPE="$2"; BRANCH="$3"; EXPECTED="$4"

case "$SCOPE" in
    local|remote) ;;
    *) echo "error: 未知 scope「${SCOPE}」（只接受 local / remote）" >&2; die_usage ;;
esac
[ -n "$BRANCH" ] && [ -n "$EXPECTED" ] || die_usage

if ! git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "error: ${REPO} 不是 git repo（或路徑不存在）" >&2
    exit 1
fi

# canonical remote：有 origin 用之，否則取第一個（同 ship-state.sh 的解析）
if git -C "$REPO" remote | grep -qx origin; then
    REMOTE=origin
else
    REMOTE="$(git -C "$REPO" remote | head -1)"
fi

if [ "$SCOPE" = "local" ]; then
    if ! ACTUAL="$(git -C "$REPO" rev-parse --verify -q "refs/heads/${BRANCH}" 2>/dev/null)"; then
        die_stop "local branch「${BRANCH}」不存在——確認名字是否正確；不存在不等於已刪成功，故不當成功回報"
    fi
    CURRENT="$(git -C "$REPO" symbolic-ref --short -q HEAD)" || CURRENT=""
    if [ "$CURRENT" = "$BRANCH" ]; then
        die_stop "「${BRANCH}」是當前 checked-out 的 branch——先 switch 到別的 branch 再刪"
    fi
    if [ "$ACTUAL" != "$EXPECTED" ]; then
        die_stop "「${BRANCH}」的當下 tip ${ACTUAL} ≠ expected ${EXPECTED}——偵測之後它又前進了（另一個 session？），那些 commit 未必在 default 上。重跑 ship-state.sh 取新訊號，勿沿用舊 SHA"
    fi
    # 到此三道前提全過。`-D` 而非 `-d`：squash-merge 的 branch 在祖先關係上「未合併」，
    # `-d` 會拒——但「內容已在 default 上」正是呼叫端已用 headRefOid 驗過的前提。
    if ! out="$(git -C "$REPO" branch -D -- "$BRANCH" 2>&1)"; then
        echo "error: 刪除失敗：${out}" >&2
        exit 1
    fi
    echo "deleted: local ${BRANCH}（tip ${EXPECTED}，執行當下重驗相符）"
    exit 0
fi

# --- remote ---
if [ -z "$REMOTE" ]; then
    die_stop "repo 無任何 remote，remote 模式不適用"
fi
# 直接問遠端，不讀本地 remote-tracking ref——後者不 fetch 就是舊快照，用它比對等於沒比對
if ! LS="$(git -C "$REPO" ls-remote --heads "$REMOTE" "$BRANCH" 2>&1)"; then
    die_stop "ls-remote 失敗（網路/認證？）：$(printf '%s' "$LS" | head -1)——無法確認遠端狀態，不刪"
fi
if [ -z "$LS" ]; then
    die_stop "遠端沒有 branch「${BRANCH}」——確認名字是否正確；不存在不等於已刪成功"
fi
ACTUAL="$(printf '%s\n' "$LS" | head -1 | awk '{print $1}')"
if [ "$ACTUAL" != "$EXPECTED" ]; then
    die_stop "遠端「${BRANCH}」的當下 tip ${ACTUAL} ≠ expected ${EXPECTED}——偵測之後有人推過，勿沿用舊 SHA"
fi
# lease 帶 expected SHA：上面的 ls-remote 與這次 push 之間仍有一個更小的窗口，
# 由遠端自己在寫入前做最後比對關掉它
if ! out="$(git -C "$REPO" push --force-with-lease="refs/heads/${BRANCH}:${EXPECTED}" \
        "$REMOTE" --delete -- "refs/heads/${BRANCH}" 2>&1)"; then
    echo "error: 遠端刪除失敗（lease 可能已被他人更新推翻）：${out}" >&2
    exit 1
fi
echo "deleted: remote ${REMOTE}/${BRANCH}（tip ${EXPECTED}，ls-remote 重驗 + lease 雙重比對）"
exit 0
