#!/usr/bin/env bash
#
# render-ssh-config.sh — 從 inventory.conf 重新生成 ssh/config 的內網主機區塊
#
# 用法：
#   ./scripts/render-ssh-config.sh              # 覆寫 ssh/config
#   ./scripts/render-ssh-config.sh --check      # 僅檢查是否需要更新（CI 友善）
#   ./scripts/render-ssh-config.sh --stdout     # 輸出到 stdout 不覆寫
#
# 說明：
#   - 只替換 `# BEGIN inventory hosts` / `# END inventory hosts` 之間的內容
#   - GitHub、Include、個別手寫區段不受影響
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$DOTFILES_DIR/ssh/config"

BEGIN_MARKER="# BEGIN inventory hosts (由 scripts/render-ssh-config.sh 生成，勿手動編輯)"
END_MARKER="# END inventory hosts"

# shellcheck source=lib/inventory.sh
source "$SCRIPT_DIR/lib/inventory.sh"

if [ ! -f "$CONFIG" ]; then
    echo "error: $CONFIG 不存在" >&2
    exit 1
fi
begin_count=$(grep -c '^# BEGIN inventory hosts' "$CONFIG" || true)
end_count=$(grep -cF "$END_MARKER" "$CONFIG" || true)
if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
    echo "error: $CONFIG 必須剛好有一組 marker （BEGIN=${begin_count}, END=${end_count}）" >&2
    echo "       請手動修復後重試；正確 marker 為：" >&2
    echo "         # BEGIN inventory hosts (由 scripts/render-ssh-config.sh 生成，勿手動編輯)" >&2
    echo "         $END_MARKER" >&2
    exit 1
fi

render_block() {
    echo "$BEGIN_MARKER"
    local first=1
    while IFS=$'\t' read -r alias ip; do
        [ -z "$alias" ] && continue
        if [ $first -eq 1 ]; then
            first=0
        else
            echo ""
        fi
        cat <<EOF
Host $alias
    HostName $ip
    User jjshen
    IdentityFile ~/.ssh/id_autogen
    Port 22
EOF
    done < <(inventory_entries)
    echo "$END_MARKER"
}

generate() {
    # before block
    sed -n '1,/^# BEGIN inventory hosts/{/^# BEGIN inventory hosts/!p;}' "$CONFIG"
    # rendered block
    render_block
    # after block
    sed -n "/^$END_MARKER/,\$p" "$CONFIG" | tail -n +2
}

MODE="${1:-write}"
case "$MODE" in
    --stdout)
        generate
        ;;
    --check)
        new="$(generate)"
        if [ "$new" = "$(cat "$CONFIG")" ]; then
            echo "✅ ssh/config 已同步 inventory.conf"
            exit 0
        else
            echo "❌ ssh/config 與 inventory.conf 不同步，請執行 ./scripts/render-ssh-config.sh" >&2
            exit 1
        fi
        ;;
    write|"")
        tmp="$(mktemp)"
        generate > "$tmp"
        mv "$tmp" "$CONFIG"
        count=$(inventory_hosts | wc -l | tr -d ' ')
        echo "✅ ssh/config 已更新（$count 台主機）"
        ;;
    *)
        echo "用法: $0 [--stdout|--check]" >&2
        exit 1
        ;;
esac
