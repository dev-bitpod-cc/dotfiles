#!/usr/bin/env bash
#
# all-up.sh — 批次系統更新：所在本機 + dotsync 目標主機
#
# 每台依 OS 執行：
#   macOS (Darwin) → brewup
#   Linux          → brewup; sysup（sysup 需 sudo，遠端非免密 sudo 會自動略過）
#
# 目標規劃：
#   無引數 → 所在本機（本地執行）+ 全部 inventory 主機；
#            若本機正好是 inventory 其中一台（以 IP 比對），則從遠端清單扣除該台，
#            改由本地路徑執行，避免自連 ssh 與重複更新。
#   有引數 → 完全按引數所列（皆走遠端 ssh），不含本機。
#
# 用法：
#   ./scripts/all-up.sh              # 本機 + 遠端（本機若在清單則自動扣除）
#   ./scripts/all-up.sh eagle03 db01 # 只跑指定主機（遠端）
#
# 顯示：逐台序列執行，每台印一條表頭，其輸出即時串流於下方縮排顯示，
#       換下一台時前一台自然往上捲。
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 主機清單：從 inventory.conf 載入（與 dotfiles-sync.sh 同一來源）
# shellcheck source=lib/inventory.sh
source "$SCRIPT_DIR/lib/inventory.sh"

# 顏色
if [ -t 1 ]; then
    BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' BLUE='' RED='' NC=''
fi

# 本機所有 IPv4（供辨識「本機是否為 inventory 其中一台」）
collect_local_ips() {
    if command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1
    else
        ifconfig 2>/dev/null | awk '/inet /{print $2}'
    fi
}

# 目標規劃
RUN_LOCAL=0
REMOTE=()
SELF_ALIAS=""
if [ $# -gt 0 ]; then
    REMOTE=("$@")
else
    RUN_LOCAL=1
    LOCAL_IPS="$(collect_local_ips)"
    while IFS=$'\t' read -r _alias _ip; do
        [ -z "$_alias" ] && continue
        if [ -n "$_ip" ] && printf '%s\n' "$LOCAL_IPS" | grep -qxF "$_ip"; then
            SELF_ALIAS="$_alias"   # 本機就是這台 → 交給本地路徑，遠端清單略過
            continue
        fi
        REMOTE+=("$_alias")
    done < <(inventory_entries)
fi

# 更新腳本片段：在目標端（本機或遠端）判斷 OS 後執行對應更新。
# 以互動 shell（zsh -ic / bash -ic）載入 brewup / sysup 這兩個 alias。
# ALLUP_GUARD_SUDO=1 時，sysup 前先探測免密 sudo，非免密則略過（避免非互動卡死）。
# 注意：本片段以單引號賦值，內含的 $os 等變數保持字面值，於「目標端」才展開。
# shellcheck disable=SC2016  # 變數刻意不在本機展開，於目標端執行時才展開
REMOTE_SNIPPET='
os=$(uname -s)
case "$os" in
  Darwin)
    zsh -ic "brewup"
    ;;
  *)
    bash -ic "brewup"
    if [ "${ALLUP_GUARD_SUDO:-1}" = "1" ]; then
      if sudo -n true 2>/dev/null; then
        bash -ic "sysup"
      else
        echo "WARN: 略過 sysup — 此主機 sudo 需密碼，非互動無法執行"
      fi
    else
      bash -ic "sysup"
    fi
    ;;
esac
'

indent() { while IFS= read -r line; do printf '    %s\n' "$line"; done; }

SUCCESS=0
FAIL=0
FAILED_HOSTS=()

# run_target <idx> <total> <label> <local|remote> [host]
run_target() {
    local idx="$1" total="$2" label="$3" kind="$4" host="${5:-}"
    local os rc

    # OS 探測（供表頭顯示；遠端順帶當連線檢查）
    if [ "$kind" = local ]; then
        os=$(uname -s 2>/dev/null || echo "?")
    else
        os=$(ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$host" 'uname -s' 2>/dev/null) || os=""
    fi

    printf '%b\n' "${BOLD}${BLUE}━━━ ${label}${NC}${BOLD} (${os:-unreachable}) ${idx}/${total} ━━━━━━━━━━━━${NC}"

    if [ "$kind" = remote ] && [ -z "$os" ]; then
        printf '%b\n' "    ${RED}❌ 連線失敗${NC}"
        FAIL=$((FAIL + 1)); FAILED_HOSTS+=("$label")
        return
    fi

    if [ "$kind" = local ]; then
        # 本機：允許互動 sudo（有 tty，使用者本人啟動）
        { bash -c "ALLUP_GUARD_SUDO=0
$REMOTE_SNIPPET" 2>&1; } | indent
        rc=${PIPESTATUS[0]}
    else
        # 遠端：非互動，sysup 前守衛免密 sudo
        # shellcheck disable=SC2029  # REMOTE_SNIPPET 內變數刻意於遠端展開
        { ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$host" "ALLUP_GUARD_SUDO=1
$REMOTE_SNIPPET" 2>&1; } | indent
        rc=${PIPESTATUS[0]}
    fi

    if [ "$rc" -eq 0 ]; then
        printf '%b\n' "    ${GREEN}✅ 完成${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        printf '%b\n' "    ${RED}❌ 失敗 (exit ${rc})${NC}"
        FAIL=$((FAIL + 1)); FAILED_HOSTS+=("$label")
    fi
}

TOTAL=$((RUN_LOCAL + ${#REMOTE[@]}))
SECONDS=0

if [ "$TOTAL" -eq 0 ]; then
    printf '%b\n' "${YELLOW}▶ allup：無目標可執行${NC}"
    exit 0
fi

# 本機表頭標籤（若本機是 inventory 其中一台則標註別名）
if [ -n "$SELF_ALIAS" ]; then
    LOCAL_LABEL="本機 $(hostname -s 2>/dev/null || echo local)(=${SELF_ALIAS})"
    _localdesc="本機(=${SELF_ALIAS}) + "
else
    LOCAL_LABEL="本機 $(hostname -s 2>/dev/null || echo local)"
    _localdesc="本機 + "
fi
[ "$RUN_LOCAL" -eq 1 ] || _localdesc=""
printf '%b\n' "${BOLD}${BLUE}▶ allup：${_localdesc}${#REMOTE[@]} 台遠端（共 ${TOTAL} 台）${NC}"

# 預覽模式：只列執行計畫、不連線不更新（ALLUP_DRYRUN=1）
if [ "${ALLUP_DRYRUN:-0}" = "1" ]; then
    n=0
    if [ "$RUN_LOCAL" -eq 1 ]; then
        n=$((n + 1)); printf '  %d. %b\n' "$n" "${BOLD}${LOCAL_LABEL} (local)${NC} → brewup（Linux 另加 sysup）"
    fi
    for host in ${REMOTE[@]+"${REMOTE[@]}"}; do
        n=$((n + 1)); printf '  %d. %b\n' "$n" "${BOLD}${host} (remote)${NC} → brewup（Linux 且免密 sudo 另加 sysup）"
    done
    printf '%b\n' "${YELLOW}  [dry-run] 未執行任何更新${NC}"
    exit 0
fi

idx=0

# 本機（僅無引數時；本地路徑，不走 ssh）
if [ "$RUN_LOCAL" -eq 1 ]; then
    idx=$((idx + 1))
    run_target "$idx" "$TOTAL" "$LOCAL_LABEL" local
fi

# 遠端序列
if [ "${#REMOTE[@]}" -gt 0 ]; then
    for host in "${REMOTE[@]}"; do
        idx=$((idx + 1))
        run_target "$idx" "$TOTAL" "$host" remote "$host"
    done
fi

printf '%b\n' "${BOLD}${BLUE}▶ 完成：${GREEN}✅ ${SUCCESS} 成功${NC}${BOLD}  ${RED}❌ ${FAIL} 失敗${NC}${BOLD}  （耗時 ${SECONDS}s）${NC}"
if [ "$FAIL" -gt 0 ]; then
    printf '%b\n' "${YELLOW}  失敗主機：${FAILED_HOSTS[*]}${NC}"
    exit 1
fi
