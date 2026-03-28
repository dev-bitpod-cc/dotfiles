#!/usr/bin/env bash
#
# dotfiles-sync.sh — 同步 dotfiles 到所有遠端主機
#
# 用法：
#   ./scripts/dotfiles-sync.sh              # 同步所有主機
#   ./scripts/dotfiles-sync.sh eagle03 db01 # 只同步指定主機
#
# 每台遠端主機執行：git pull + 重新套用 SSH config + known_hosts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ALL_HOSTS=(eagle03 eagle06 eagle07 eagle08 eagle09 macs db01 ap01 ap02 macmini m4mini agent01)

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

# 本機先同步
echo -e "${BLUE}▶ 本機同步${NC}"
(cd "$DOTFILES_DIR" && git pull 2>/dev/null) || true

# 重新套用 SSH config + known_hosts
if [ -f "$DOTFILES_DIR/ssh/config" ]; then
    cat > ~/.ssh/config << SSHEOF
# 此檔案由 dotfiles setup 腳本產生
# 共用設定來自 $DOTFILES_DIR/ssh/config
# 機器特定設定請編輯 ~/.ssh/config.local

$(cat "$DOTFILES_DIR/ssh/config")
SSHEOF
    chmod 600 ~/.ssh/config
fi

if [ -f "$DOTFILES_DIR/ssh/known_hosts" ]; then
    cp "$DOTFILES_DIR/ssh/known_hosts" ~/.ssh/known_hosts
fi

echo -e "${GREEN}  ✅ 本機完成${NC}"

# 遠端同步（並行）
echo -e "${BLUE}▶ 遠端同步 ${#HOSTS[@]} 台${NC}"

sync_remote() {
    local host="$1"
    local result
    result=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" '
        if [ -d ~/.dotfiles ]; then
            cd ~/.dotfiles && git pull 2>/dev/null
            # 重新套用 SSH config
            if [ -f ssh/config ]; then
                SCRIPT_DIR="$(pwd)"
                cat > ~/.ssh/config << SSHEOF
# 此檔案由 dotfiles sync 產生
$(cat ssh/config)
SSHEOF
                chmod 600 ~/.ssh/config
            fi
            # 覆蓋 known_hosts
            if [ -f ssh/known_hosts ]; then
                cp ssh/known_hosts ~/.ssh/known_hosts
            fi
            echo "OK"
        else
            echo "NO_DOTFILES"
        fi
    ' 2>/dev/null)

    local last_line
    last_line="$(echo "$result" | tail -1)"
    case "$last_line" in
        OK)           echo -e "${GREEN}  ✅ ${host}${NC}" ;;
        NO_DOTFILES)  echo -e "${YELLOW}  ⚠️  ${host}：~/.dotfiles 不存在${NC}" ;;
        *)            echo -e "${RED}  ❌ ${host}：連線失敗${NC}" ;;
    esac
}

for host in "${HOSTS[@]}"; do
    sync_remote "$host" &
done
wait

echo -e "${BLUE}▶ 完成${NC}"
