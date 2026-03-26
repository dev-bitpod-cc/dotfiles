#!/usr/bin/env bash
#
# rotate-user-key.sh — 在遠端機器上重新產生 SSH key 並簽署 cert
#
# 用法：
#   ./scripts/rotate-user-key.sh localhost         # 本機
#   ./scripts/rotate-user-key.sh eagle03          # 指定機器
#   ./scripts/rotate-user-key.sh eagle03 db01     # 多台
#   ./scripts/rotate-user-key.sh --all            # ALL_SERVERS（不含本機）
#
# 前提：
#   - User CA private key 在 iCloud
#   - 能 SSH 到目標機器（用現有 cert 或 authorized_keys）
#

set -euo pipefail

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

print_info()    { echo -e "${BLUE}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}  ✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}  ❌ $1${NC}"; }

# 設定
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_CA="$HOME/Documents/shell/security/ssh/sshca/userca/user_ca_key"
DEFAULT_PRINCIPALS="jjshen"
VALIDITY="+52w"
ALL_SERVERS=(eagle03 eagle06 macs db01 ap01 ap02 macmini m4mini agent01)

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# 前置檢查
if [ ! -f "$USER_CA" ]; then
    print_error "User CA private key 不存在：$USER_CA"
    exit 1
fi

# 決定目標機器
if [ "${1:-}" = "--all" ]; then
    SERVERS=("${ALL_SERVERS[@]}")
elif [ $# -gt 0 ]; then
    SERVERS=("$@")
else
    echo "用法: $0 <server...> | --all"
    exit 1
fi

SUCCESS=0
FAILED=0

rotate_local() {
    print_info "處理 localhost..."

    # 1. 本機產生新 key pair
    if ! echo y | ssh-keygen -t ed25519 -f ~/.ssh/id_autogen -N "" -q 2>/dev/null; then
        print_error "localhost：產生 key 失敗"
        FAILED=$((FAILED + 1))
        return
    fi

    # 2. 本地簽署
    identity="$(hostname -s)-$(date +%Y%m%d)"
    if ! ssh-keygen -s "$USER_CA" \
        -I "$identity" \
        -n "$DEFAULT_PRINCIPALS" \
        -V "$VALIDITY" \
        ~/.ssh/id_autogen.pub 2>/dev/null; then
        print_error "localhost：簽署失敗"
        FAILED=$((FAILED + 1))
        return
    fi

    # 3. 修正權限
    chmod 600 ~/.ssh/id_autogen
    chmod 644 ~/.ssh/id_autogen.pub ~/.ssh/id_autogen-cert.pub

    print_success "localhost：key 已重新產生並簽署"
    SUCCESS=$((SUCCESS + 1))
}

rotate_remote() {
    local server="$1"
    print_info "處理 ${server}..."

    # 1. 遠端產生新 key pair
    if ! ssh "$server" "echo y | ssh-keygen -t ed25519 -f ~/.ssh/id_autogen -N '' -q" 2>/dev/null; then
        print_error "${server}：產生 key 失敗"
        FAILED=$((FAILED + 1))
        return
    fi

    # 2. 取回 public key
    local_pub="$WORK_DIR/${server}.pub"
    if ! scp "$server:~/.ssh/id_autogen.pub" "$local_pub" 2>/dev/null; then
        print_error "${server}：取回 public key 失敗"
        FAILED=$((FAILED + 1))
        return
    fi

    # 3. 本地簽署
    identity="${server}-$(date +%Y%m%d)"
    if ! ssh-keygen -s "$USER_CA" \
        -I "$identity" \
        -n "$DEFAULT_PRINCIPALS" \
        -V "$VALIDITY" \
        "$local_pub" 2>/dev/null; then
        print_error "${server}：簽署失敗"
        FAILED=$((FAILED + 1))
        return
    fi

    # 4. 上傳 cert
    local_cert="${local_pub%.pub}-cert.pub"
    if ! scp "$local_cert" "$server:~/.ssh/id_autogen-cert.pub" 2>/dev/null; then
        print_error "${server}：上傳 cert 失敗"
        FAILED=$((FAILED + 1))
        return
    fi

    # 5. 修正權限
    ssh "$server" "chmod 600 ~/.ssh/id_autogen && chmod 644 ~/.ssh/id_autogen.pub ~/.ssh/id_autogen-cert.pub" 2>/dev/null || true

    print_success "${server}：key 已重新產生並簽署"
    SUCCESS=$((SUCCESS + 1))
}

for server in "${SERVERS[@]}"; do
    if [ "$server" = "localhost" ]; then
        rotate_local
    else
        rotate_remote "$server"
    fi
done

echo ""
print_info "完成：成功 $SUCCESS / 失敗 $FAILED / 總計 ${#SERVERS[@]}"
