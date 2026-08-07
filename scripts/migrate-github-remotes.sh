#!/usr/bin/env bash
#
# migrate-github-remotes.sh — GitHub 多身分收斂：把各 repo 的 remote 換成新的 host 寫法
#
# 用法：
#   migrate-github-remotes.sh [--apply] [--skip-identity-check] [<搜尋根目錄>...]
#
#   預設 **dry-run**（只印計畫，零 mutation），`--apply` 才動手。
#   預設搜尋根目錄：~/Projects 底下每個直屬子目錄 + ~/.dotfiles。
#
# exit code：0 = 完成（含「無事可做」）；1 = STOP（前提不成立，零 mutation）；2 = 用法錯誤
#
# 換法（`ssh/config` 收斂後的終態）：
#   git@github-work:*              → git@github.com:*        （工作＝預設＝標準寫法）
#   git@github.com:dev-bitpod-cc/* → git@github-me:*         （個人身分明示）
#   ssh://git@github-work/*        → ssh://git@github.com/*  （同上，URL 形式）
#   順帶移除 ~/.gitconfig 的 insteadOf（它們是為了讓 krepo 拉依賴而暫設的改寫層）
#
# 為何要有這支腳本，而不是照抄一段 for 迴圈：
#   1. **順序是硬前提**。spec 的遷移順序寫得很清楚：身分驗證通過**之後**才能改 remote——
#      沒過就往下做，會把 remote 改成連不對身分的形式，而失敗長相是「連得上但權限不對」。
#      靠人記得順序不可靠，這裡直接把它變成前置 gate（`--skip-identity-check` 要明說才跳過）。
#   2. **手貼的迴圈會漏**。spec 裡那段只掃 `origin`；2026-08-07 實跑工作 mac 時，biz-chat 與
#      pilot-api 各有一條指向 github-work 的 `fork` remote——照抄就留兩顆未爆彈，而且是在
#      「看起來已經全部遷完」之後。本腳本掃**每個 remote**。
#   3. 還有 12 台機器要跑同一件事，每台手貼一次就是 12 次出錯機會。
#
# ⚠ 這支腳本只改**本機**。散佈 ssh/config 到某台機器後，那台機器要自己跑一次，
#   否則它的 `git@github-work:` remote 會當場全部失效（新 config 已無 github-work 這條 Host）。

set -uo pipefail

# 預期身分（可用環境變數覆寫；硬編才抓得到「認到錯帳號」——那正是 IdentitiesOnly 沒設時的長相）
EXPECT_WORK="${MIGRATE_EXPECT_WORK:-jjshen-eland}"
EXPECT_ME="${MIGRATE_EXPECT_ME:-dev-bitpod-cc}"
# ssh 指令可注入（測試用 stub；預設就是真 ssh）
SSH_CMD="${MIGRATE_SSH:-ssh}"

APPLY=0
SKIP_IDENT=0
ROOTS=()

die_usage() { echo "用法：$0 [--apply] [--skip-identity-check] [<搜尋根目錄>...]" >&2; exit 2; }
die_stop()  { echo "verdict: STOP（$1）"; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)                APPLY=1 ;;
        --skip-identity-check)  SKIP_IDENT=1 ;;
        -h|--help)              die_usage ;;
        --*)                    echo "error: 未知選項「$1」" >&2; die_usage ;;
        *)                      ROOTS+=("$1") ;;
    esac
    shift
done

if [ "${#ROOTS[@]}" -eq 0 ]; then
    ROOTS=("$HOME/Projects" "$HOME/.dotfiles")
fi

# --- 前置 gate：身分驗證 ---
# 判準是「認到誰」不是「連得上」。認到錯帳號八成是 IdentitiesOnly 沒設，ssh 把 agent 裡的
# key 逐一送出、GitHub 收下第一把有效的——這種狀態下改 remote 只會把錯誤固化進每個 repo。
check_identity() {
    local host="$1" expect="$2" out
    out="$("$SSH_CMD" -o BatchMode=yes -T "git@${host}" 2>&1)"
    if ! grep -q "Hi ${expect}!" <<< "$out"; then
        echo "  ${host} → 期望 ${expect}，實得：$(head -1 <<< "$out")" >&2
        return 1
    fi
    echo "  ${host} → ${expect} ✓"
    return 0
}

if [ "$SKIP_IDENT" -eq 1 ]; then
    echo "identity-check: SKIPPED（--skip-identity-check）"
else
    echo "identity-check:"
    ident_ok=1
    check_identity github.com "$EXPECT_WORK" || ident_ok=0
    check_identity github-me  "$EXPECT_ME"   || ident_ok=0
    if [ "$ident_ok" -ne 1 ]; then
        die_stop "身分驗證未通過——先確認 ssh/config 已部署且兩個 Host 都有 IdentitiesOnly yes；在這個狀態下改 remote 會把錯誤身分固化進每個 repo"
    fi
fi

# --- 掃描 + 換寫 ---
rewrite_url() {
    local url="$1"
    case "$url" in
        git@github-work:*)              printf 'git@github.com:%s'        "${url#git@github-work:}" ;;
        ssh://git@github-work/*)        printf 'ssh://git@github.com/%s'  "${url#ssh://git@github-work/}" ;;
        git@github.com:dev-bitpod-cc/*) printf 'git@github-me:%s'         "${url#git@github.com:}" ;;
        ssh://git@github.com/dev-bitpod-cc/*) printf 'ssh://git@github-me/%s' "${url#ssh://git@github.com/}" ;;
        *)                              printf '' ;;
    esac
}

repos=()
for root in "${ROOTS[@]}"; do
    [ -e "$root" ] || continue
    if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        repos+=("$root")
        continue
    fi
    for d in "$root"/*/; do
        [ -d "$d" ] || continue
        git -C "$d" rev-parse --git-dir >/dev/null 2>&1 && repos+=("${d%/}")
    done
done

if [ "${#repos[@]}" -eq 0 ]; then
    echo "repos: none（搜尋根目錄下沒有 git repo：${ROOTS[*]}）"
fi

n_change=0
n_scan=0
for repo in "${repos[@]}"; do
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        n_scan=$((n_scan + 1))
        url="$(git -C "$repo" remote get-url "$r" 2>/dev/null)" || continue
        new="$(rewrite_url "$url")"
        [ -n "$new" ] || continue
        n_change=$((n_change + 1))
        if [ "$APPLY" -eq 1 ]; then
            if git -C "$repo" remote set-url "$r" "$new"; then
                printf 'changed: %-24s %-8s %s\n' "$(basename "$repo")" "$r" "$new"
            else
                printf 'error:   %-24s %-8s set-url 失敗\n' "$(basename "$repo")" "$r"
            fi
        else
            printf 'would-change: %-24s %-8s %s → %s\n' "$(basename "$repo")" "$r" "$url" "$new"
        fi
    done <<< "$(git -C "$repo" remote 2>/dev/null)"
done

# --- insteadOf：收斂要消滅的對象 ---
# 只清指向 github-work 的那幾條（那是這次收斂要移除的改寫層），不動使用者其他的 insteadOf
n_insteadof=0
while IFS= read -r key; do
    [ -n "$key" ] || continue
    case "$key" in
        *github-work*) ;;
        *) continue ;;
    esac
    n_insteadof=$((n_insteadof + 1))
    if [ "$APPLY" -eq 1 ]; then
        git config --global --unset-all "$key" && echo "unset:   ${key}"
    else
        echo "would-unset: ${key}"
    fi
done <<< "$(git config --global --name-only --get-regexp 'insteadof' 2>/dev/null)"

echo "---"
echo "scanned: ${#repos[@]} repo / ${n_scan} remote；需換寫 ${n_change}；insteadOf 待清 ${n_insteadof}"
if [ "$APPLY" -eq 0 ] && { [ "$n_change" -gt 0 ] || [ "$n_insteadof" -gt 0 ]; }; then
    echo "（dry-run——加 --apply 才實際執行）"
fi
exit 0
