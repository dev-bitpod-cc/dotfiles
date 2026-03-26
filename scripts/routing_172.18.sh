#!/usr/bin/env bash
#
# 新增 172.18.0.0/16 路由（經由 172.17.1.254）
#

set -euo pipefail

NETWORK="172.18.0.0/16"
GATEWAY="172.17.1.254"

add_route() {
    local os
    os="$(uname)"
    case "$os" in
        Darwin)
            if netstat -rn | grep -q "^172\.18"; then
                echo "Route to $NETWORK already exists"
                return 0
            fi
            echo "Adding route to $NETWORK via $GATEWAY"
            sudo route add -net "$NETWORK" "$GATEWAY"
            ;;
        Linux)
            if ip route show | grep -q "^172\.18\."; then
                echo "Route to $NETWORK already exists"
                return 0
            fi
            echo "Adding route to $NETWORK via $GATEWAY"
            sudo ip route add "$NETWORK" via "$GATEWAY"
            ;;
        *)
            echo "Unsupported OS: $os"
            exit 1
            ;;
    esac
}

add_route
