#!/usr/bin/env bash
#
# sign-host-keys.sh — 批次簽署內網伺服器 host key
#
# 用法：
#   ./scripts/sign-host-keys.sh              # 簽署所有伺服器
#   ./scripts/sign-host-keys.sh eagle03      # 只簽署指定伺服器
#
# 前提：
#   - Host CA private key 在 iCloud（不上傳到伺服器）
#   - 能用 SSH 連線到目標伺服器（密碼或已有 key）
#   - 目標伺服器上有 sudo 權限
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

# ================================================
# 設定
# ================================================

# Host CA private key（iCloud）
HOST_CA="$HOME/Documents/shell/security/ssh/sshca/hostca/host_ca_key"

# 所有內網伺服器（Host alias → 用於 SSH 連線）
ALL_SERVERS=(eagle03 eagle06 eagle07 eagle08 eagle09 macs db01 ap01 ap02 macmini m4mini agent01 fe01 be01)

# Certificate 有效期（預設 52 週）
VALIDITY="+52w"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ================================================
# 前置檢查
# ================================================

if [ ! -f "$HOST_CA" ]; then
    print_error "Host CA private key 不存在：$HOST_CA"
    echo "請確認 iCloud Drive 已同步"
    exit 1
fi

# 決定要處理的伺服器
if [ $# -gt 0 ]; then
    SERVERS=("$@")
else
    SERVERS=("${ALL_SERVERS[@]}")
fi

# ================================================
# 主流程
# ================================================

print_info "開始簽署 ${#SERVERS[@]} 台伺服器的 host key..."
echo ""

SUCCESS=0
FAILED=0

for server in "${SERVERS[@]}"; do
    print_info "處理 ${server}..."

    # 1. 取得伺服器的 host public key
    host_pub="$WORK_DIR/${server}_host_key.pub"
    if ! ssh "$server" "cat /etc/ssh/ssh_host_ed25519_key.pub" > "$host_pub" 2>/dev/null; then
        print_error "${server}：無法取得 host key（SSH 連線失敗？）"
        FAILED=$((FAILED + 1))
        continue
    fi

    # 2. 用 Host CA 簽署（principal 包含 alias + 實際 hostname/IP）
    actual_host=$(ssh -G "$server" 2>/dev/null | awk '/^hostname / {print $2}')
    principals="$server"
    [ -n "$actual_host" ] && [ "$actual_host" != "$server" ] && principals="$server,$actual_host"

    cert_file="$WORK_DIR/${server}_host_key-cert.pub"
    if ! ssh-keygen -s "$HOST_CA" \
        -I "$server" \
        -h \
        -V "$VALIDITY" \
        -n "$principals" \
        "$host_pub" 2>/dev/null; then
        print_error "${server}：簽署失敗"
        FAILED=$((FAILED + 1))
        continue
    fi

    # ssh-keygen 會在 host_pub 旁邊產生 -cert.pub
    cert_file="${host_pub%.pub}-cert.pub"
    if [ ! -f "$cert_file" ]; then
        print_error "${server}：找不到產生的 certificate"
        FAILED=$((FAILED + 1))
        continue
    fi

    # 3. 上傳 certificate 到伺服器
    if ! scp "$cert_file" "$server:/tmp/ssh_host_ed25519_key-cert.pub" 2>/dev/null; then
        print_error "${server}：上傳 certificate 失敗"
        FAILED=$((FAILED + 1))
        continue
    fi

    # 4. 上傳 User CA 公鑰
    user_ca_pub="$DOTFILES_DIR/ssh/user_ca.pub"
    if [ -f "$user_ca_pub" ]; then
        scp "$user_ca_pub" "$server:/tmp/user_ca.pub" 2>/dev/null || true
    fi

    # 5. 在伺服器上部署 Host Certificate + User CA
    deploy_cmd='
        # 備份 sshd_config（失敗時可 rollback）
        sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

        # Host Certificate
        sudo mv /tmp/ssh_host_ed25519_key-cert.pub /etc/ssh/ssh_host_ed25519_key-cert.pub
        sudo chown root:root /etc/ssh/ssh_host_ed25519_key-cert.pub 2>/dev/null || sudo chown root:wheel /etc/ssh/ssh_host_ed25519_key-cert.pub
        sudo chmod 644 /etc/ssh/ssh_host_ed25519_key-cert.pub
        if ! grep -q "^HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub" /etc/ssh/sshd_config; then
            echo "HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub" | sudo tee -a /etc/ssh/sshd_config > /dev/null
        fi

        # User CA（TrustedUserCAKeys）
        if [ -f /tmp/user_ca.pub ]; then
            sudo mv /tmp/user_ca.pub /etc/ssh/user_ca.pub
            sudo chown root:root /etc/ssh/user_ca.pub 2>/dev/null || sudo chown root:wheel /etc/ssh/user_ca.pub
            sudo chmod 644 /etc/ssh/user_ca.pub
            if ! grep -q "^TrustedUserCAKeys /etc/ssh/user_ca.pub" /etc/ssh/sshd_config; then
                echo "TrustedUserCAKeys /etc/ssh/user_ca.pub" | sudo tee -a /etc/ssh/sshd_config > /dev/null
            fi
        fi

        if sudo sshd -t 2>/dev/null; then
            sudo rm -f /etc/ssh/sshd_config.bak
            if command -v systemctl &>/dev/null; then
                sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null
            else
                sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
            fi
            echo "OK"
        else
            sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
            echo "SSHD_CONFIG_ERROR"
        fi
    '

    result=$(ssh "$server" "$deploy_cmd" 2>/dev/null)
    if [ "$result" = "OK" ]; then
        print_success "${server}：certificate 已部署"
        SUCCESS=$((SUCCESS + 1))
    else
        print_error "${server}：部署失敗（sshd_config 語法錯誤？）"
        FAILED=$((FAILED + 1))
    fi
done

# ================================================
# 完成
# ================================================

echo ""
print_info "完成：成功 $SUCCESS / 失敗 $FAILED / 總計 ${#SERVERS[@]}"

if [ $SUCCESS -gt 0 ]; then
    echo ""
    print_info "known_hosts 現在可以簡化為 @cert-authority 模式"
    print_info "Host CA 部署完成後，執行："
    echo "  cp $DOTFILES_DIR/ssh/known_hosts $DOTFILES_DIR/ssh/known_hosts.bak"
    echo "  # 編輯 $DOTFILES_DIR/ssh/known_hosts，移除逐條 fingerprint，保留 @cert-authority + GitHub"
fi
