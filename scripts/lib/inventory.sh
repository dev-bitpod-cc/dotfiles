#!/usr/bin/env bash
#
# inventory.sh — 讀取 scripts/inventory.conf 並提供 helper 函式
#
# 用法（其他腳本 source 本檔）：
#   source "$(dirname "$0")/lib/inventory.sh"
#   mapfile -t HOSTS < <(inventory_hosts)
#   ip=$(inventory_ip eagle03)
#
# 提供的函式：
#   inventory_hosts              列出所有 alias（每行一個）
#   inventory_ip <alias>         查 IP（找不到回 exit 1）
#   inventory_has <alias>        檢查 alias 是否存在（回 exit code）
#   inventory_append <alias> <ip>  將新主機寫入 inventory.conf 末尾（ sorted 保留原順序）
#

# 解析 inventory.conf 路徑（允許被 source 的腳本覆寫 INVENTORY_FILE）
_inventory_default_file() {
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$lib_dir/../inventory.conf"
}
: "${INVENTORY_FILE:=$(_inventory_default_file)}"

_inventory_require_file() {
    if [ ! -f "$INVENTORY_FILE" ]; then
        echo "inventory: 找不到 $INVENTORY_FILE" >&2
        return 1
    fi
}

# 列出所有 alias
inventory_hosts() {
    _inventory_require_file || return 1
    awk '/^[[:space:]]*#/ || NF==0 { next } { print $1 }' "$INVENTORY_FILE"
}

# 列出所有 "alias ip" pair（tab 分隔）
inventory_entries() {
    _inventory_require_file || return 1
    awk '/^[[:space:]]*#/ || NF==0 { next } { printf "%s\t%s\n", $1, $2 }' "$INVENTORY_FILE"
}

# 查指定 alias 的 IP
inventory_ip() {
    local alias="$1"
    _inventory_require_file || return 1
    local ip
    ip=$(awk -v a="$alias" '
        /^[[:space:]]*#/ || NF==0 { next }
        $1 == a { print $2; found=1; exit }
        END { if (!found) exit 1 }
    ' "$INVENTORY_FILE") || {
        echo "inventory: 找不到 alias '$alias'" >&2
        return 1
    }
    echo "$ip"
}

# 檢查 alias 是否存在
inventory_has() {
    local alias="$1"
    _inventory_require_file || return 1
    awk -v a="$alias" '
        /^[[:space:]]*#/ || NF==0 { next }
        $1 == a { found=1; exit }
        END { exit (found ? 0 : 1) }
    ' "$INVENTORY_FILE"
}

# 將新主機 append 到 inventory.conf 末尾
# 重複 alias 會拒絕（回 exit 1）
inventory_append() {
    local alias="$1" ip="$2"
    if [ -z "$alias" ] || [ -z "$ip" ]; then
        echo "inventory_append: 需要 <alias> <ip>" >&2
        return 1
    fi
    _inventory_require_file || return 1
    if inventory_has "$alias"; then
        echo "inventory_append: alias '$alias' 已存在" >&2
        return 1
    fi
    # 寬度 12 足以對齊至 11 字元 alias；超過也只是視覺影響，不影響解析
    printf '%-12s %s\n' "$alias" "$ip" >> "$INVENTORY_FILE"
}
