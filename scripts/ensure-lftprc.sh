#!/usr/bin/env bash
#
# ensure-lftprc.sh — 幂等確保 ~/.lftprc 指向 dotfiles source of truth
#
# 由 setup 與 dotfiles-sync.sh 在 git pull 後呼叫。既有實體檔先備份到 home 之外的
# 備份目錄；錯誤 symlink 可安全替換。另保證 ~/.lftprc.local 存在——lftprc 結尾會
# source 它，缺檔會讓 lftp 每次啟動印一行 "No such file or directory"。
# SOURCE_FILE / TARGET_HOME / BACKUP_ROOT 可覆寫供測試。

set -uo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SOURCE_FILE="${SOURCE_FILE:-$DOTFILES_DIR/lftprc}"
TARGET_HOME="${TARGET_HOME:-$HOME}"
TARGET="$TARGET_HOME/.lftprc"
LOCAL_FILE="$TARGET_HOME/.lftprc.local"
BACKUP_ROOT="${BACKUP_ROOT:-${TARGET_HOME}/.dotfiles-backup}"

[ -f "$SOURCE_FILE" ] || exit 0

# lftprc 結尾 source 此檔，缺檔不致命但每次啟動都會噪音
ensure_local_file() {
    [ -e "$LOCAL_FILE" ] && return 0
    if touch "$LOCAL_FILE" 2>/dev/null; then
        echo "✓ 已建立 ${LOCAL_FILE}（機器特定設定，不受版控）"
        return 0
    fi
    echo "⚠️  無法建立 ${LOCAL_FILE}——lftp 啟動時會印 source 失敗訊息"
    return 1
}

# 已是正確 symlink：只補 .local 就收工
if [ "$TARGET" -ef "$SOURCE_FILE" ]; then
    ensure_local_file
    exit $?
fi

backup=""
if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    backup="$BACKUP_ROOT/lftprc-$(date +%Y%m%d%H%M%S)-$$"
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
    # 原檔已被搬去備份時必須還原——否則使用者的設定就此消失
    if [ -n "$backup" ] && mv "$backup" "$TARGET" 2>/dev/null; then
        echo "↩ 已還原原檔 ${TARGET}"
    fi
    exit 1
fi

ensure_local_file
exit $?
