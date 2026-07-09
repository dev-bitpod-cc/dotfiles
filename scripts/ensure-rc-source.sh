#!/usr/bin/env bash
#
# ensure-rc-source.sh — 幂等確保互動 rc 有 source shell/functions.sh
#
# 由 dotfiles-sync.sh（本機與遠端）於 git pull 後呼叫，讓既有主機不必重跑
# setup 也能取得 shell/functions.sh 內的便利函數。跑幾次都只加一行。
#
# 目標 rc 依 OS 決定（mac→~/.zshrc、linux→~/.bashrc）；測試可用 RC_FILE 覆寫。
#

set -uo pipefail

if [ -n "${RC_FILE:-}" ]; then
    RC="$RC_FILE"
else
    case "$(uname -s)" in
        Darwin) RC="$HOME/.zshrc" ;;
        *)      RC="$HOME/.bashrc" ;;
    esac
fi

MARKER='shell/functions.sh'
LINE='[ -f ~/.dotfiles/shell/functions.sh ] && source ~/.dotfiles/shell/functions.sh'

# rc 不存在就不動作（setup 會負責建立完整 rc）
[ -f "$RC" ] || exit 0

# 已有 → 幂等結束
grep -qF "$MARKER" "$RC" && exit 0

printf '\n# dotfiles 便利函數（由 dotsync 補上；版控於 shell/functions.sh）\n%s\n' "$LINE" >> "$RC"
