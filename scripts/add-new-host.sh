#!/usr/bin/env bash
#
# add-new-host.sh — 新增一台主機到 SSH CA 開發環境的單一入口
#
# 用法：
#   ./scripts/add-new-host.sh <alias> <ip>       # 完整流程（Phase A + B）
#   ./scripts/add-new-host.sh --resume <alias>   # 跳過 Phase A，只跑 Phase B（假設 inventory 已有）
#   ./scripts/add-new-host.sh --dry-run <alias> <ip>  # 預覽，不動任何東西
#
# 流程：
#   Phase A（任何 Mac 都能做）
#     1. 驗證 alias/ip
#     2. 寫入 scripts/inventory.conf
#     3. 重新生成 dotfiles 的 ssh/config
#     4. 套用 ssh/config 到 ~/.ssh/config（新 alias 立即可用）
#     5. 套用 /etc/hosts 區塊到本機（若有 sudo）
#     6. git commit（不 push）
#
#   Phase B（需要 iCloud CA 的管理機）
#     1. 驗證能 SSH 到新主機
#     2. 部署 GitHub SSH keys + authorized_keys + SSH config + known_hosts
#     3. sign-host-keys.sh <alias>
#     4. sign-user-key.sh <alias>
#
#   Phase C（使用者手動）
#     * git push
#     * ./scripts/dotfiles-sync.sh
#     * ./scripts/render-etc-hosts.sh --remote <host>（更新其他主機 /etc/hosts）
#
# 前提（使用者需先完成）：
#   - 新主機已跑過 `curl -fsSL dot.bitpod.cc | sh`
#   - 本機能 SSH 到新主機（ssh-copy-id 或 password 預先放好）
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 顏色
if [ -t 1 ]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; BLUE=''; RED=''; NC=''
fi
info()    { echo -e "${BLUE}▶${NC} $1"; }
ok()      { echo -e "${GREEN}  ✅${NC} $1"; }
warn()    { echo -e "${YELLOW}  ⚠️${NC}  $1"; }
err()     { echo -e "${RED}  ❌${NC} $1"; }
die()     { err "$1"; exit 1; }

HOST_CA="$HOME/Documents/shell/security/ssh/sshca/hostca/host_ca_key"
USER_CA="$HOME/Documents/shell/security/ssh/sshca/userca/user_ca_key"

# shellcheck source=lib/inventory.sh
source "$SCRIPT_DIR/lib/inventory.sh"

# ---- Argument parsing ----
DRY_RUN=0
RESUME=0
ALIAS=""
IP=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --resume)  RESUME=1; shift ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            die "未知參數: $1"
            ;;
        *)
            if [ -z "$ALIAS" ]; then
                ALIAS="$1"
            elif [ -z "$IP" ]; then
                IP="$1"
            else
                die "參數過多: $1"
            fi
            shift
            ;;
    esac
done

[ -z "$ALIAS" ] && die "用法: $0 [--dry-run|--resume] <alias> [<ip>]"
if [ "$RESUME" -eq 0 ] && [ -z "$IP" ]; then
    die "用法: $0 <alias> <ip>"
fi

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

# =====================================================
# Phase A: Local metadata
# =====================================================
phase_a_failure_hint() {
    local rc=$?
    if [ $rc -ne 0 ]; then
        err "Phase A 中途失敗（exit=$rc）"
        echo ""
        echo "    恢復建議："
        echo "      1. 檢查 scripts/inventory.conf 是否已寫入 ${ALIAS}"
        echo "      2. 若 inventory 已更新但 ssh/config 未同步："
        echo "           ./scripts/render-ssh-config.sh"
        echo "      3. 若一切已修復，重新執行："
        echo "           ./scripts/add-new-host.sh --resume ${ALIAS}"
        echo "      4. 若要完全 rollback，手動從 inventory.conf 移除該行並執行 render-ssh-config.sh"
    fi
}

phase_a() {
    info "Phase A: 更新 dotfiles metadata"
    trap phase_a_failure_hint ERR

    # 1. 驗證
    if inventory_has "$ALIAS"; then
        die "alias '$ALIAS' 已存在於 inventory.conf（若要重跑 Phase B，用 --resume）"
    fi
    if ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "IP 格式不正確: $IP"
    fi
    ok "驗證通過（${ALIAS} → ${IP}）"

    # 2. 寫入 inventory
    run inventory_append "$ALIAS" "$IP"
    ok "已加入 scripts/inventory.conf"

    # 3. 重新生成 ssh/config
    run "$SCRIPT_DIR/render-ssh-config.sh"

    # 4. 套用到 ~/.ssh/config
    if [ "$DRY_RUN" -eq 0 ]; then
        {
            echo "# 此檔案由 dotfiles setup 腳本產生"
            echo "# 共用設定來自 $DOTFILES_DIR/ssh/config"
            echo "# 機器特定設定請編輯 ~/.ssh/config.local"
            echo ""
            cat "$DOTFILES_DIR/ssh/config"
        } > ~/.ssh/config
        chmod 600 ~/.ssh/config
    fi
    ok "已套用 ~/.ssh/config"

    # 5. 本機 /etc/hosts
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] sudo $SCRIPT_DIR/render-etc-hosts.sh --apply /etc/hosts"
    else
        if sudo -n true 2>/dev/null; then
            sudo "$SCRIPT_DIR/render-etc-hosts.sh" --apply /etc/hosts
        else
            info "需要 sudo 更新本機 /etc/hosts"
            if sudo "$SCRIPT_DIR/render-etc-hosts.sh" --apply /etc/hosts; then
                :
            else
                warn "未能更新本機 /etc/hosts（可稍後手動執行 sudo ./scripts/render-etc-hosts.sh --apply）"
            fi
        fi
    fi

    # 6. git commit
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] git add scripts/inventory.conf ssh/config"
        echo "    [dry-run] git commit -m 'feat: 新增 $ALIAS ($IP) 至 inventory'"
    else
        (
            cd "$DOTFILES_DIR"
            git add scripts/inventory.conf ssh/config
            if git diff --cached --quiet; then
                warn "沒有變更可 commit（inventory/ssh config 已是最新？）"
            else
                git commit -m "feat: 新增 $ALIAS ($IP) 至 inventory" >/dev/null
                ok "git commit 完成"
            fi
        )
    fi

    trap - ERR
}

# =====================================================
# Phase B: CA signing + key deployment
# =====================================================
phase_b_check_prereq() {
    if [ ! -f "$HOST_CA" ] || [ ! -f "$USER_CA" ]; then
        return 1
    fi
    return 0
}

phase_b_failure_hint() {
    local rc=$?
    if [ $rc -ne 0 ]; then
        err "Phase B 中途失敗（exit=$rc）"
        echo ""
        echo "    恢復建議："
        echo "      - 金鑰部署與 CA 簽署皆為 idempotent，可直接重跑："
        echo "          ./scripts/add-new-host.sh --resume ${ALIAS}"
        echo "      - 若是 SSH 連線問題，確認能 ssh 到 ${ALIAS} 後再重試"
    fi
}

phase_b() {
    info "Phase B: 部署金鑰 + CA 簽署（new host: ${ALIAS}）"
    trap phase_b_failure_hint ERR

    # 1. 驗證能 SSH 到新主機
    if [ "$DRY_RUN" -eq 0 ]; then
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" true 2>/dev/null; then
            warn "BatchMode SSH 失敗（可能需要密碼或尚未 ssh-copy-id）"
            info "嘗試互動式連線一次以確認..."
            ssh -o ConnectTimeout=5 "$ALIAS" true || die "無法 SSH 到 $ALIAS"
        fi
    fi
    ok "SSH 連線 OK"

    # 2. 部署 GitHub keys（若本機有）
    for key in id_github id_github_work; do
        if [ -f "$HOME/.ssh/$key" ]; then
            run scp -q "$HOME/.ssh/$key" "$HOME/.ssh/$key.pub" "$ALIAS:~/.ssh/"
        fi
    done
    ok "GitHub SSH keys 已部署"

    # 3. 設定 authorized_keys（fallback）
    # 透過 scp + 遠端讀檔，避免把 key 內容經過本地 shell 展開（防 injection）
    if [ -f "$HOME/.ssh/id_github.pub" ]; then
        if [ "$DRY_RUN" -eq 0 ]; then
            scp -q "$HOME/.ssh/id_github.pub" "$ALIAS:/tmp/.add-new-host.authkey.pub"
            ssh "$ALIAS" bash -s <<'REMOTE_AUTHKEYS'
set -e
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
key=$(cat /tmp/.add-new-host.authkey.pub)
if ! grep -qxF "$key" ~/.ssh/authorized_keys; then
    cat /tmp/.add-new-host.authkey.pub >> ~/.ssh/authorized_keys
fi
rm -f /tmp/.add-new-host.authkey.pub
REMOTE_AUTHKEYS
        else
            echo "    [dry-run] scp id_github.pub 到 ${ALIAS}，遠端合併到 authorized_keys"
        fi
        ok "authorized_keys fallback 已部署"
    fi

    # 4. 部署 ssh/config + known_hosts
    if [ "$DRY_RUN" -eq 0 ]; then
        scp -q "$DOTFILES_DIR/ssh/config" "$ALIAS:~/.ssh/config"
        scp -q "$DOTFILES_DIR/ssh/known_hosts" "$ALIAS:~/.ssh/known_hosts"
        ssh "$ALIAS" "chmod 600 ~/.ssh/config ~/.ssh/known_hosts"
    else
        echo "    [dry-run] scp ssh/config + known_hosts to $ALIAS"
    fi
    ok "SSH config + known_hosts 已部署"

    # 5. sign-host-keys.sh
    run "$SCRIPT_DIR/sign-host-keys.sh" "$ALIAS"

    # 6. sign-user-key.sh
    run "$SCRIPT_DIR/sign-user-key.sh" "$ALIAS"

    trap - ERR
}

# =====================================================
# Main
# =====================================================
if [ "$RESUME" -eq 1 ]; then
    if ! inventory_has "$ALIAS"; then
        die "--resume 需要 '$ALIAS' 已在 inventory.conf 中"
    fi
    # 驗證 ssh/config 與 inventory 同步（避免 Phase A 半途失敗後誤用 --resume）
    if ! "$SCRIPT_DIR/render-ssh-config.sh" --check >/dev/null 2>&1; then
        err "ssh/config 與 inventory.conf 不同步"
        echo "       請先執行：./scripts/render-ssh-config.sh"
        echo "       修復後再 --resume"
        exit 1
    fi
    info "Resume 模式：跳過 Phase A，直接進 Phase B"
else
    phase_a
fi

echo ""
if phase_b_check_prereq; then
    phase_b
    echo ""
    info "接下來請手動執行："
    echo "    cd $DOTFILES_DIR"
    echo "    git push                                       # 發布到 remote"
    echo "    ./scripts/dotfiles-sync.sh                     # 同步到所有主機"
    echo "    ./scripts/render-etc-hosts.sh --remote <host>  # 更新其他主機 /etc/hosts（選用，逐台或批次）"
else
    warn "未偵測到 iCloud CA（${HOST_CA} / ${USER_CA}）"
    info "Phase A 已完成。在有 CA 的管理機上執行："
    echo "    cd $DOTFILES_DIR && git pull"
    echo "    ./scripts/add-new-host.sh --resume $ALIAS"
fi
