#!/usr/bin/env bash
#
# sign-user-cert.sh — 用 User CA 簽署使用者的 SSH public key
#
# 用法：
#   ./scripts/sign-user-cert.sh ~/.ssh/id_ed25519.pub              # 簽署本機 key
#   ./scripts/sign-user-cert.sh /tmp/newmachine.pub                # 簽署其他機器的 key
#   ./scripts/sign-user-cert.sh ~/.ssh/id_ed25519.pub jjshen,root  # 指定允許的使用者
#
# 前提：
#   - User CA private key 在 iCloud
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
print_error()   { echo -e "${RED}  ❌ $1${NC}"; }

# ================================================
# 設定
# ================================================

USER_CA="$HOME/Documents/shell/security/ssh/sshca/userca/user_ca_key"
DEFAULT_PRINCIPALS="jjshen"
VALIDITY="+52w"

# ================================================
# 參數
# ================================================

PUB_KEY="${1:-}"
PRINCIPALS="${2:-$DEFAULT_PRINCIPALS}"

if [ -z "$PUB_KEY" ]; then
    echo "用法: $0 <public_key_file> [principals]"
    echo ""
    echo "  public_key_file  要簽署的 SSH public key（.pub）"
    echo "  principals       允許登入的使用者名稱（逗號分隔，預設: $DEFAULT_PRINCIPALS）"
    echo ""
    echo "範例："
    echo "  $0 ~/.ssh/id_ed25519.pub"
    echo "  $0 /tmp/newmachine.pub jjshen,root"
    exit 1
fi

if [ ! -f "$PUB_KEY" ]; then
    print_error "找不到 public key：$PUB_KEY"
    exit 1
fi

if [ ! -f "$USER_CA" ]; then
    print_error "User CA private key 不存在：$USER_CA"
    echo "請確認 iCloud Drive 已同步"
    exit 1
fi

# ================================================
# 簽署
# ================================================

# 從 public key 取得 identity（用於 certificate 識別）
IDENTITY="$(hostname -s)-$(date +%Y%m%d)"

print_info "簽署 $PUB_KEY"
print_info "Identity: $IDENTITY"
print_info "Principals: $PRINCIPALS"
print_info "有效期: $VALIDITY"

ssh-keygen -s "$USER_CA" \
    -I "$IDENTITY" \
    -n "$PRINCIPALS" \
    -V "$VALIDITY" \
    "$PUB_KEY"

CERT_FILE="${PUB_KEY%.pub}-cert.pub"

if [ -f "$CERT_FILE" ]; then
    print_success "Certificate 已產生：$CERT_FILE"
    echo ""
    print_info "Certificate 資訊："
    ssh-keygen -L -f "$CERT_FILE"
else
    print_error "簽署失敗"
    exit 1
fi
