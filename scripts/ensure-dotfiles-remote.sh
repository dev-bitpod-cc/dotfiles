#!/usr/bin/env bash
#
# ensure-dotfiles-remote.sh — 幂等把 ~/.dotfiles 的 origin 指向轉移後的 owner
#
# 一次性遷移殘留（2026-08-15 dotfiles 由 dev-bitpod-cc 轉入 jjshen-eland）。
# 由 setup 與 dotfiles-sync.sh 在 git pull 後呼叫；穩態下恆為 no-op、零輸出。
#
# **為什麼需要它，而不是「反正 pull 得動就別管」**：public repo 的讀取對任何已認證
# 使用者放行，舊 URL 靠 GitHub 的轉移 redirect 照樣 pull 得動。但只要日後在舊路徑
# （dev-bitpod-cc/dotfiles）重建一個同名 repo，全機隊就會**靜默 pull 到錯的 repo**
# ——沒有錯誤訊息、沒有 exit code，只是內容悄悄變成別的東西。
#
# **保留各主機原有的 scheme**（2026-08-15 巡檢 14 台的結果決定的，不是猜的）：
#   8 台 git@github-me:…  3 種尾綴形狀（db01 沒有 .git 尾綴）
#   6 台 https://github.com/…（bootstrap.sh 裝的，只 pull）
# HTTPS 那批**不改成 SSH**——public repo 的 HTTPS pull 完全免認證，換成 SSH 等於
# 平白給只讀主機加一條金鑰依賴。SSH 那批則順帶把 Host 從 github-me（＝id_personal，
# 個人身分）換回預設 github.com，因為 repo 已不屬個人帳號。
#
# 全機隊確認跟上後，本腳本連同 dotfiles-sync.sh / setup 的呼叫點可一併移除。
#
# OLD_OWNER / NEW_OWNER / REPO_NAME / DOTFILES_DIR 可覆寫供測試。

set -uo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
OLD_OWNER="${OLD_OWNER:-dev-bitpod-cc}"
NEW_OWNER="${NEW_OWNER:-jjshen-eland}"
REPO_NAME="${REPO_NAME:-dotfiles}"

git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

url="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null)" || exit 0
[ -n "$url" ] || exit 0

# 尾綴 .git 可有可無（db01 實地就沒有），故一律以 owner/repo 為判準、不比對整串。
case "$url" in
    # scp 形式的 SSH（git@<host>:<owner>/<repo>）——含 github-me 別名
    *:"$OLD_OWNER/$REPO_NAME"|*:"$OLD_OWNER/$REPO_NAME".git)
        new="git@github.com:${NEW_OWNER}/${REPO_NAME}.git" ;;
    # HTTPS 與 ssh:// 形式（…/<owner>/<repo>）——維持 HTTPS，勿升級成 SSH
    *"://"*/"$OLD_OWNER/$REPO_NAME"|*"://"*/"$OLD_OWNER/$REPO_NAME".git)
        new="https://github.com/${NEW_OWNER}/${REPO_NAME}.git" ;;
    *)
        exit 0 ;;
esac

if git -C "$DOTFILES_DIR" remote set-url origin "$new" 2>/dev/null; then
    echo "↻ origin 已改指轉移後的 owner：${url} → ${new}"
    exit 0
fi

echo "⚠️  無法改寫 origin（仍為 ${url}）——舊 URL 目前靠 GitHub 轉移 redirect 仍可 pull，但請手動修正"
exit 1
