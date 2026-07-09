#!/usr/bin/env bash
#
# tmux-ls.sh — 列出 dotsync 目標主機（inventory）上的 tmux session
#
# 用法：
#   ./scripts/tmux-ls.sh              # 查詢所有主機
#   ./scripts/tmux-ls.sh eagle03 db01 # 只查指定主機
#
# 每台遠端主機執行：tmux ls
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 主機清單：從 inventory.conf 載入（與 dotfiles-sync.sh 同一來源）
# shellcheck source=lib/inventory.sh
source "$SCRIPT_DIR/lib/inventory.sh"
ALL_HOSTS=()
while IFS= read -r _host; do
    [ -n "$_host" ] && ALL_HOSTS+=("$_host")
done < <(inventory_hosts)

if [ $# -gt 0 ]; then
    HOSTS=("$@")
else
    HOSTS=("${ALL_HOSTS[@]}")
fi

# 顏色
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' BLUE='' RED='' NC=''
fi

echo -e "${BLUE}▶ 查詢 ${#HOSTS[@]} 台主機的 tmux session${NC}"

query_remote() {
    local host="$1"
    local out rc=0
    # tmux 無 session 時回 exit 1 並印 "no server running..."；用旗標區分「連得上但沒 session」與「連不上」
    out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
        'if command -v tmux >/dev/null 2>&1; then tmux ls 2>/dev/null || echo "__NO_SESSION__"; else echo "__NO_TMUX__"; fi' 2>/dev/null) || rc=$?

    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
        printf '%b\n' "${RED}❌ ${host}：連線失敗${NC}"
        return
    fi

    case "$out" in
        __NO_TMUX__)    printf '%b\n' "${YELLOW}⚠️  ${host}：未安裝 tmux${NC}" ;;
        __NO_SESSION__) printf '%b\n' "${YELLOW}➖ ${host}：無 session${NC}" ;;
        *)
            printf '%b\n' "${GREEN}✅ ${host}${NC}"
            printf '%s\n' "$out" | sed 's/^/    /'
            ;;
    esac
}

# 並行查詢；各主機輸出整塊組好再一次印出，降低交錯
for host in "${HOSTS[@]}"; do
    query_remote "$host" &
done
wait

echo -e "${BLUE}▶ 完成${NC}"
