#!/usr/bin/env bash
#
# dotfiles-sync.sh — 同步 dotfiles 到所有遠端主機
#
# 用法：
#   ./scripts/dotfiles-sync.sh              # 同步所有主機
#   ./scripts/dotfiles-sync.sh eagle03 db01 # 只同步指定主機
#
# 每台遠端主機執行：git pull + 重新套用 SSH config + known_hosts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 主機清單：從 inventory.conf 載入
# shellcheck source=lib/inventory.sh
source "$SCRIPT_DIR/lib/inventory.sh"
ALL_HOSTS=()
while IFS= read -r _host; do
    [ -n "$_host" ] && ALL_HOSTS+=("$_host")
done < <(inventory_hosts)

if [ $# -gt 0 ]; then
    HOSTS=("$@")
else
    HOSTS=("${ALL_HOSTS[@]}")
fi

# 顏色
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' BLUE='' RED='' NC=''
fi

# 本機先同步
echo -e "${BLUE}▶ 本機同步${NC}"
(cd "$DOTFILES_DIR" && git checkout -- claude/settings.json 2>/dev/null; git pull --autostash 2>&1) || true

# 重新套用 SSH config + known_hosts
if [ -f "$DOTFILES_DIR/ssh/config" ]; then
    cat > ~/.ssh/config << SSHEOF
# 此檔案由 dotfiles setup 腳本產生
# 共用設定來自 $DOTFILES_DIR/ssh/config
# 機器特定設定請編輯 ~/.ssh/config.local

$(cat "$DOTFILES_DIR/ssh/config")
SSHEOF
    chmod 600 ~/.ssh/config
fi

if [ -f "$DOTFILES_DIR/ssh/known_hosts" ]; then
    cp "$DOTFILES_DIR/ssh/known_hosts" ~/.ssh/known_hosts
fi

# helper 部署失敗不中止同步，但必須反映進本機終判——不可誤報完成（codex C2）
local_helper_warn=0
# 確保互動 rc 有 source shell/functions.sh（幂等；讓便利函數免重跑 setup 即散佈）
[ -f "$DOTFILES_DIR/scripts/ensure-rc-source.sh" ] && { bash "$DOTFILES_DIR/scripts/ensure-rc-source.sh" 2>/dev/null || local_helper_warn=1; } || true

# 確保 ~/.codex/skills 指向 dotfiles（幂等；讓 codex skill 免重跑 setup 即散佈）
[ -f "$DOTFILES_DIR/scripts/ensure-codex-skills.sh" ] && { bash "$DOTFILES_DIR/scripts/ensure-codex-skills.sh" 2>/dev/null || local_helper_warn=1; } || true

# 確保全域 Codex guidance 指向 dotfiles（幂等；既有主機免重跑 setup）
[ -f "$DOTFILES_DIR/scripts/ensure-codex-guidance.sh" ] && { bash "$DOTFILES_DIR/scripts/ensure-codex-guidance.sh" 2>/dev/null || local_helper_warn=1; } || true

# 確保 ~/.lftprc 指向 dotfiles（幂等；既有主機免重跑 setup）
[ -f "$DOTFILES_DIR/scripts/ensure-lftprc.sh" ] && { bash "$DOTFILES_DIR/scripts/ensure-lftprc.sh" 2>/dev/null || local_helper_warn=1; } || true

if [ "$local_helper_warn" -eq 0 ]; then
    echo -e "${GREEN}  ✅ 本機完成${NC}"
else
    echo -e "${YELLOW}  ⚠️  本機完成，但 helper 部署有警告（見上方 ⚠️ 行）${NC}"
fi

# 遠端同步（並行）
echo -e "${BLUE}▶ 遠端同步 ${#HOSTS[@]} 台${NC}"

sync_remote() {
    local host="$1"
    local result
    # `|| true` 不可省：set -e 下 ssh 回非 0（主機不可達／DNS 失敗）會讓這個背景 subshell
    # 當場結束，下方的 case 完全不執行 → 連線失敗的 ❌ 永遠印不出來，dotsync 對真正的
    # 失敗一直是靜默的。失敗時 result 為空 → last_line 空 → 落到 *) 分支印 ❌，正是原意。
    result=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" '
        if [ -d ~/.dotfiles ]; then
            cd ~/.dotfiles && git checkout -- claude/settings.json 2>/dev/null
            # pull 失敗必須中止並回報：否則主機停在舊 revision（衝突／認證／remote 錯誤），
            # 後面的檔案檢查只會靜默跳過，最後仍 echo OK → 使用者看到 ✅ 卻什麼都沒部署。
            if ! git pull --autostash 2>&1; then
                echo "PULL_FAILED"
                exit 0
            fi
            # 重新套用 SSH config
            if [ -f ssh/config ]; then
                # 不用 heredoc 灌檔：不帶引號的 heredoc 會對內容做命令替換與變數展開，
                # 而 ssh/config 是**會長註解的檔案**，註解裡寫一組行內 code 的反引號就足以
                # 讓那段被當指令執行、毀損的 config 直接部署到全機隊（2026-08-07 在加
                # github-me 註解時當場撞到）。改成 echo + cat：內容完全不經 shell。
                {
                    echo "# 此檔案由 dotfiles sync 產生"
                    cat ssh/config
                } > ~/.ssh/config
                chmod 600 ~/.ssh/config
            fi
            # 覆蓋 known_hosts
            if [ -f ssh/known_hosts ]; then
                cp ssh/known_hosts ~/.ssh/known_hosts
            fi
            # helper 部署失敗不中止同步，但必須反映進終判——不可誤報 OK（codex C2）
            helper_warn=0
            # 確保互動 rc 有 source shell/functions.sh（幂等）
            [ -f scripts/ensure-rc-source.sh ] && { bash scripts/ensure-rc-source.sh 2>/dev/null || helper_warn=1; } || true
            # 確保 ~/.codex/skills 指向 dotfiles（幂等；免重跑 setup 即拿到最新 codex skill）
            [ -f scripts/ensure-codex-skills.sh ] && { bash scripts/ensure-codex-skills.sh 2>/dev/null || helper_warn=1; } || true
            # 確保全域 Codex guidance 指向 dotfiles（幂等）
            [ -f scripts/ensure-codex-guidance.sh ] && { bash scripts/ensure-codex-guidance.sh 2>/dev/null || helper_warn=1; } || true
            # 確保 ~/.lftprc 指向 dotfiles（幂等）
            [ -f scripts/ensure-lftprc.sh ] && { bash scripts/ensure-lftprc.sh 2>/dev/null || helper_warn=1; } || true
            if [ "$helper_warn" -eq 0 ]; then echo "OK"; else echo "OK_HELPER_WARN"; fi
        else
            echo "NO_DOTFILES"
        fi
    ' 2>/dev/null) || true

    # 接管實體 codex skill 目錄的告知必須撈出來——遠端輸出只取 tail -1 判成敗，其餘全丟；
    # 而「其他主機仍是舊實體目錄」正是這訊息唯一會觸發的場合，吞掉等於設計意圖落空。
    # `|| true` 不可省：穩態下（skill 已是 symlink）grep 無配對回 1，在 set -euo pipefail 下會
    # 讓整個 sync_remote 當場退出，連後面的 ✅/⚠️/❌ 回報一併消失 → 同步失敗變靜默成功。
    printf '%s\n' "$result" | grep -E '^(↻|⚠️|↩)' | sed "s|^|  ${host}: |" || true

    local last_line
    last_line="$(echo "$result" | tail -1)"
    case "$last_line" in
        OK)           echo -e "${GREEN}  ✅ ${host}${NC}" ;;
        OK_HELPER_WARN) echo -e "${YELLOW}  ⚠️  ${host}：pull 完成，但 helper 部署有警告（見上方 ⚠️ 行）${NC}" ;;
        NO_DOTFILES)  echo -e "${YELLOW}  ⚠️  ${host}：~/.dotfiles 不存在${NC}" ;;
        PULL_FAILED)  echo -e "${RED}  ❌ ${host}：git pull 失敗（仍停在舊 revision，本次未部署）${NC}" ;;
        *)            echo -e "${RED}  ❌ ${host}：連線失敗${NC}" ;;
    esac
}

for host in "${HOSTS[@]}"; do
    sync_remote "$host" &
done
wait

echo -e "${BLUE}▶ 完成${NC}"
