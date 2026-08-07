#!/usr/bin/env bash
#
# ensure-rc-source.sh — 幂等維護互動 rc
#
#   (1) 確保 rc 有 source shell/functions.sh
#   (2) 移除已遷移到 functions.sh 的舊 alias（brewup / sysup）
#
# 由 dotfiles-sync.sh（本機與遠端）於 git pull 後呼叫，讓既有主機不必重跑
# setup 也能取得 shell/functions.sh 內的便利函數。跑幾次都收斂到同一結果。
#
# 為什麼 (2) 必須「刪行」而不是在 functions.sh 裡 unalias：
#   alias 展開優先於 function 查找，所以 rc 裡殘留的 `alias brewup=` 會遮蔽
#   functions.sh 定義的同名 function。unalias 只在「source 行位於 alias 之後」
#   時有效，而 rc 的實際順序因機器而異——2026-08-07 實地巡檢 14 台：13 台的
#   source 行由本腳本附加在檔尾（unalias 可行），但 macmini 是新版 setup 生成的
#   rc、source(70) 在 alias(73) 之前（unalias 無效）。靠 unalias 會變成「多數機器
#   生效、少數靜默失效」，是最難察覺的那種壞法。
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
# 已遷移到 shell/functions.sh 的 alias（見 scripts/brewup.sh、scripts/sysup.sh）
STALE_ALIAS='^alias (brewup|sysup)='

# rc 不存在就不動作（setup 會負責建立完整 rc）
[ -f "$RC" ] || exit 0

# ---- (1) 補 source 行（幂等）----------------------------------------------
if ! grep -qF "$MARKER" "$RC"; then
    printf '\n# dotfiles 便利函數（由 dotsync 補上；版控於 shell/functions.sh）\n%s\n' "$LINE" >> "$RC"
fi

# ---- (2) 移除舊 alias（幂等）----------------------------------------------
grep -qE "$STALE_ALIAS" "$RC" || exit 0

TMP="$(mktemp)" || { echo "mktemp 失敗，略過舊 alias 清理：$RC" >&2; exit 0; }
[ -n "$TMP" ] && [ -f "$TMP" ] || { echo "mktemp 未產生可用檔案，略過清理" >&2; exit 0; }
trap 'rm -f "$TMP"' EXIT

before=$(wc -l < "$RC" | tr -d ' ')
grep -vE "$STALE_ALIAS" "$RC" > "$TMP" || true
after=$(wc -l < "$TMP" | tr -d ' ')

# 破壞性覆寫前的前提檢查：行數必須只減少、且減幅在合理範圍（brewup + sysup 至多 2 行）。
# 任一不成立就原封不動——寧可留著讓人工處理，不可把使用者的 rc 寫壞。
if [ "$after" -lt "$before" ] && [ "$((before - after))" -le 2 ]; then
    # 用 cat 覆寫而非 mv，保留原檔的 inode 與權限
    cat "$TMP" > "$RC" && echo "已移除 $RC 內已遷移的 brewup/sysup alias（$((before - after)) 行）"
else
    echo "⚠️  $RC 的舊 alias 清理未通過前提檢查（${before} → ${after} 行），已略過" >&2
fi
