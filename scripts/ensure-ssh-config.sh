#!/usr/bin/env bash
#
# ensure-ssh-config.sh — 幂等從 dotfiles 的 ssh/config 重生 ~/.ssh/config
#
# 由 setup、dotfiles-sync.sh 與 brewup.sh 在 git pull 後呼叫。
#
# 為什麼抽成 helper：本動作原本有四份行內複本（setup-mac / setup-linux /
# dotfiles-sync 本機段 / dotfiles-sync 遠端段 / add-new-host），而且**全部只掛在
# dotsync 與 setup**——不在 inventory.conf 的機器（如個人 MacBook）沒有任何自動
# 路徑會更新它的 ~/.ssh/config。實地後果：2026-08-08 全機隊完成 GitHub 身分收斂時，
# 那台完全沒跟上，且從外面看不出來。接進 brewup 之後，任何機器只要跑過 brewup
# 就會自己跟上，與是否在 inventory 無關。
#
# 與原行內版的兩個差異（都是往安全方向）：
#   1. 原版是 `{ …; cat ssh/config; } > ~/.ssh/config` ——**直接截斷寫入**，
#      磁碟滿或 cat 中斷就留下一個殘缺的 config，而且原檔已經沒了。本版寫同目錄
#      暫存檔 → 驗 bytes → 原子 mv。
#   2. 既有的**非本腳本產生**的 ~/.ssh/config 會先備份再接管，不靜默覆蓋手寫設定。
#
# ~/.ssh/config.local 刻意不在此建立——那是 setup 的職責（它會依平台寫入實際內容，
# 且以 `[ ! -f ]` 為條件；這裡先生一個空檔會讓 setup 之後跳過、內容永遠不進去）。
#
# SOURCE_FILE / TARGET_HOME / BACKUP_ROOT 可覆寫供測試。

set -uo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SOURCE_FILE="${SOURCE_FILE:-$DOTFILES_DIR/ssh/config}"
TARGET_HOME="${TARGET_HOME:-$HOME}"
SSH_DIR="$TARGET_HOME/.ssh"
TARGET="$SSH_DIR/config"
BACKUP_ROOT="${BACKUP_ROOT:-${TARGET_HOME}/.dotfiles-backup}"

SENTINEL="# 此檔案由 dotfiles 部署腳本產生"

[ -f "$SOURCE_FILE" ] || exit 0

if ! mkdir -p "$SSH_DIR" 2>/dev/null; then
    echo "⚠️  無法建立 ${SSH_DIR}——SSH config 未部署"
    exit 1
fi
chmod 700 "$SSH_DIR" 2>/dev/null

tmp="$SSH_DIR/.config.dotfiles.$$"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

# 群組的 exit status 就是 cat 的——來源讀不到／磁碟滿都在這裡當場失敗，
# 不要等下面的 bytes 比對（那道只是第二層防線）。
if ! {
    echo "$SENTINEL"
    echo "# 共用設定來自 ${SOURCE_FILE}"
    echo "# 機器特定設定請編輯 ${SSH_DIR}/config.local"
    echo ""
    cat "$SOURCE_FILE"
} > "$tmp" 2>/dev/null; then
    echo "⚠️  無法讀取 ${SOURCE_FILE} 或寫入暫存檔——原檔未動"
    exit 1
fi

# 第二層：剝掉標頭後的 bytes 必須等於來源 bytes。截斷的 ssh config 是
# 「連得上但認錯身分」那類最難查的故障，值得兩道檢查。
# ⚠ `src_bytes=$(wc -c < 檔)` 在檔案讀不到時**回空字串**，而 `$((hdr + ))` 在 bash 裡
# 當 0 → 比對自己通過、殘檔照樣蓋上去（本節測試實地抓到）。同族陷阱見
# `claude/CLAUDE.md`「已知地雷」的 `grep -c … || echo 0`：失敗時仍給出看似有效的值。
hdr_bytes=$( { echo "$SENTINEL"; echo "# 共用設定來自 ${SOURCE_FILE}"; echo "# 機器特定設定請編輯 ${SSH_DIR}/config.local"; echo ""; } | LC_ALL=C wc -c ) || hdr_bytes=-1
src_bytes=$(LC_ALL=C wc -c < "$SOURCE_FILE") || src_bytes=-1
tmp_bytes=$(LC_ALL=C wc -c < "$tmp") || tmp_bytes=-1
: "${hdr_bytes:=-1}" "${src_bytes:=-1}" "${tmp_bytes:=-1}"
if [ "$src_bytes" -lt 0 ] || [ "$hdr_bytes" -lt 0 ] || [ "$tmp_bytes" -ne "$((hdr_bytes + src_bytes))" ]; then
    echo "⚠️  產生的 SSH config 不完整（${tmp_bytes} != $((hdr_bytes + src_bytes)) bytes）——原檔未動"
    exit 1
fi

# 內容相同即收工：讓每次 brewup / dotsync 不留無謂的 mtime 變動與輸出雜訊
if [ -f "$TARGET" ] && cmp -s "$tmp" "$TARGET"; then
    exit 0
fi

# 換上新 config 之前，先確認它指到的 key 在這台機器上真的存在。
#
# 為什麼需要：本 helper 讓 ssh/config 開始「自動」重生，於是**key 檔名落後的機器**
# （例如從未跟上 2026-08-08 那次 id_github_work → id_github_com 改名的離線筆電）
# 會在第一次 brewup 當場把可用的舊 config 換成指向不存在的 key ——
# GitHub 認證斷掉，而修正正是要靠 GitHub 拉回來（散佈憑證三條紀律的第①條）。
#
# 判準刻意收窄成「拿可用的換成壞的」：新 config 有 key 缺席**且**現行 config 指到的
# key 還在（＝現在是好的）→ 拒絕。全新機器（還沒有 config、或一把 key 都還沒放）
# 不受影響，否則 setup 首跑就會被自己擋住。
identity_files() {   # $1=config 檔；印出展開後的絕對路徑
    [ -f "$1" ] || return 0
    awk 'tolower($1) == "identityfile" { print $2 }' "$1" |
        sed "s|^~/|${TARGET_HOME}/|"
}
missing_new=""
while IFS= read -r idf; do
    [ -n "$idf" ] || continue
    [ -e "$idf" ] || missing_new="${missing_new}${idf}
"
done <<< "$(identity_files "$tmp")"
if [ -n "$missing_new" ] && [ -f "$TARGET" ]; then
    present_old=0
    while IFS= read -r idf; do
        [ -n "$idf" ] || continue
        [ -e "$idf" ] && present_old=1
    done <<< "$(identity_files "$TARGET")"
    if [ "$present_old" -eq 1 ]; then
        echo "⚠️  拒絕更新 ${TARGET}——新 config 指到的 key 在本機不存在，換上去會斷掉現在可用的認證："
        printf '%s' "$missing_new" | sed 's/^/      /'
        echo "    先把 key 備成新檔名（**cp 不要 mv**，新舊並存才不會中途斷線），再重跑本腳本。"
        echo "    2026-08-08 的對照：id_github_work → id_github_com、id_github → id_personal"
        exit 1
    fi
fi

# 既有檔不是本腳本產生的（手寫或更早的版本）→ 先備份再接管
if [ -e "$TARGET" ] && ! head -n 1 "$TARGET" 2>/dev/null | grep -qF "$SENTINEL"; then
    backup="$BACKUP_ROOT/ssh-config-$(date +%Y%m%d%H%M%S)-$$"
    if mkdir -p "$BACKUP_ROOT" 2>/dev/null && cp "$TARGET" "$backup" 2>/dev/null; then
        echo "↻ 接管 ${TARGET}（原檔已備份到 ${backup}）"
    else
        echo "⚠️  無法備份既有的 ${TARGET}——跳過，不冒險覆蓋"
        exit 1
    fi
fi

chmod 600 "$tmp" 2>/dev/null
if ! mv -f "$tmp" "$TARGET" 2>/dev/null; then
    echo "⚠️  無法寫入 ${TARGET}——原檔未動"
    exit 1
fi
chmod 600 "$TARGET" 2>/dev/null
echo "✓ 已更新 ${TARGET}"
