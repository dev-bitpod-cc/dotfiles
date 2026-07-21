#!/usr/bin/env bash
#
# ensure-codex-guidance.sh — 幂等確保全域 Codex AGENTS.md 指向 dotfiles source of truth
#
# 由 setup 與 dotfiles-sync.sh 在 git pull 後呼叫。既有實體檔先備份到 Codex home
# 之外；錯誤 symlink 可安全替換。SOURCE_FILE / CODEX_DIR / BACKUP_ROOT 可覆寫供測試。

set -uo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SOURCE_FILE="${SOURCE_FILE:-$DOTFILES_DIR/codex/AGENTS.md}"
CODEX_DIR="${CODEX_DIR:-${CODEX_HOME:-$HOME/.codex}}"
TARGET="$CODEX_DIR/AGENTS.md"
BACKUP_ROOT="${BACKUP_ROOT:-${CODEX_DIR}-backup}"

[ -f "$SOURCE_FILE" ] || exit 0

if ! mkdir -p "$CODEX_DIR" 2>/dev/null; then
    echo "⚠️  無法建立 ${CODEX_DIR}——Codex 全域 guidance 未部署"
    exit 1
fi

if [ "$TARGET" -ef "$SOURCE_FILE" ]; then
    exit 0
fi

backup=""
if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    backup="$BACKUP_ROOT/AGENTS.md-$(date +%Y%m%d%H%M%S)-$$"
    if mkdir -p "$BACKUP_ROOT" 2>/dev/null && mv "$TARGET" "$backup" 2>/dev/null; then
        echo "↻ 接管 ${TARGET}（原檔已備份到 ${backup}）"
    else
        echo "⚠️  無法備份既有的 ${TARGET}——跳過，不冒險刪除"
        exit 1
    fi
else
    rm -f "$TARGET"
fi

if ! ln -sfn "$SOURCE_FILE" "$TARGET" 2>/dev/null; then
    echo "⚠️  無法建立 symlink ${TARGET} → ${SOURCE_FILE}"
    # 原檔已被搬去備份時必須還原——否則生效位置的 guidance 就此消失
    if [ -n "$backup" ] && mv "$backup" "$TARGET" 2>/dev/null; then
        echo "↩ 已還原原檔 ${TARGET}"
    fi
    exit 1
fi

exit 0
