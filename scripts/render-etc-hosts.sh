#!/usr/bin/env bash
#
# render-etc-hosts.sh — 從 inventory.conf 生成 /etc/hosts 的 pilot-infra 區塊
#
# 用法：
#   ./scripts/render-etc-hosts.sh                  # 輸出區塊到 stdout
#   sudo ./scripts/render-etc-hosts.sh --apply     # 套用到本機 /etc/hosts
#   ./scripts/render-etc-hosts.sh --apply <file>   # 套用到指定檔案
#   ./scripts/render-etc-hosts.sh --remote <host>  # 套用到遠端主機（透過 SSH + sudo）
#
# 行為：
#   - 刪除檔案中既有的 `# pilot-infra-start` ... `# pilot-infra-end` 區塊（全部）
#   - 在檔案末尾 append 一個新區塊
#   - IP 以 dotted-decimal 數值排序
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BEGIN_MARKER="# pilot-infra-start"
END_MARKER="# pilot-infra-end"

# shellcheck source=lib/inventory.sh
source "$SCRIPT_DIR/lib/inventory.sh"

render_block() {
    echo "$BEGIN_MARKER"
    inventory_entries \
        | awk -F'\t' '{ printf "%s\t%s\n", $2, $1 }' \
        | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
        | awk -F'\t' '{ printf "%-14s %s\n", $1, $2 }'
    echo "$END_MARKER"
}

# 刪除檔案中所有既有區塊，將新區塊 append 到末尾
apply_to_file() {
    local target="$1"
    if [ ! -f "$target" ]; then
        echo "error: $target 不存在" >&2
        exit 1
    fi
    if [ ! -w "$target" ]; then
        echo "error: $target 無寫入權限（試試 sudo）" >&2
        exit 1
    fi

    local tmp
    tmp="$(mktemp)"
    # 移除所有 pilot-infra 區塊（包含前後重複）
    awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
        $0 == b { in_block=1; next }
        $0 == e { in_block=0; next }
        !in_block { print }
    ' "$target" > "$tmp"

    # 去除尾部多餘空行
    # （只保留不超過一個尾行的空行）
    while [ -s "$tmp" ] && [ -z "$(tail -n 1 "$tmp")" ]; do
        sed -i.bak -e '$d' "$tmp" && rm -f "$tmp.bak"
    done

    # append 新區塊（前面空一行與既有內容分隔）
    echo "" >> "$tmp"
    render_block >> "$tmp"

    # 原子替換
    cat "$tmp" > "$target"
    rm -f "$tmp"
    echo "✅ 已套用到 ${target} （$(inventory_hosts | wc -l | tr -d ' ') 台主機）"
}

apply_to_remote() {
    local host="$1"
    local block
    block="$(render_block)"
    ssh "$host" "sudo bash -s" <<REMOTE
set -e
TARGET=/etc/hosts
TMP=\$(mktemp)
awk -v b='$BEGIN_MARKER' -v e='$END_MARKER' '
    \$0 == b { in_block=1; next }
    \$0 == e { in_block=0; next }
    !in_block { print }
' "\$TARGET" > "\$TMP"
while [ -s "\$TMP" ] && [ -z "\$(tail -n 1 "\$TMP")" ]; do
    sed -i.bak -e '\$d' "\$TMP" && rm -f "\$TMP.bak"
done
echo "" >> "\$TMP"
cat >> "\$TMP" <<'BLOCK'
$block
BLOCK
cp "\$TMP" "\$TARGET"
rm -f "\$TMP"
echo "OK"
REMOTE
}

case "${1:-}" in
    ""|--stdout)
        render_block
        ;;
    --apply)
        target="${2:-/etc/hosts}"
        apply_to_file "$target"
        ;;
    --remote)
        if [ -z "${2:-}" ]; then
            echo "用法: $0 --remote <host>" >&2
            exit 1
        fi
        apply_to_remote "$2"
        ;;
    *)
        echo "用法: $0 [--stdout|--apply [file]|--remote <host>]" >&2
        exit 1
        ;;
esac
