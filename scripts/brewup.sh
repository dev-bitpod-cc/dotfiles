#!/usr/bin/env bash
#
# brewup.sh — Homebrew + dotfiles + Claude plugins 更新（macOS / Linux 共用）
#
# 原為 setup-mac-env.sh / setup-linux-env.sh 各自定義的一行 alias（兩份完全相同的
# 複本）。抽成單一腳本後：雙平台共用同一份邏輯、不再有漂移風險，且 all-up.sh 可以
# 直接呼叫本檔而毋須 `bash -ic`（省掉無 TTY 時的 job control 雜訊）。
#
# 行為與原 alias 等價——本次只做搬移，不改流程。
#
set -uo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"

# 1. dotfiles 同步
#    settings.json 為唯一權威、由選定的權威機器刻意 commit；其他機器上 harness 寫入的
#    runtime drift 是拋棄式的，故 pull 前先丟棄。rebase.autoStash 作為其他 dirty 檔的安全網。
(cd "${DOTFILES}" && git checkout -- claude/settings.json 2>/dev/null; git pull --autostash 2>&1)

# 1b. pull 後的幂等部署 helper（與 dotfiles-sync.sh 同一組、同一形狀）
#     為什麼 brewup 也要跑：helper 原本只掛在 dotfiles-sync.sh，但 allup 走的是 brewup，
#     於是「日常全機隊更新」不會重建 symlink——來源檔改名或搬移時該連結會靜默失效
#     （ensure-codex-skills.sh 檔頭記載過實例：某台的 repo-review 停在四個月前的實體目錄）。
#     helper 失敗不中止更新，但**必須反映進終判**——不可誤報完成（同 dotfiles-sync.sh 的 codex C2）。
helper_warn=0
[ -f "${DOTFILES}/scripts/ensure-rc-source.sh" ] && { bash "${DOTFILES}/scripts/ensure-rc-source.sh" 2>/dev/null || helper_warn=1; } || true
[ -f "${DOTFILES}/scripts/ensure-codex-skills.sh" ] && { bash "${DOTFILES}/scripts/ensure-codex-skills.sh" 2>/dev/null || helper_warn=1; } || true
[ -f "${DOTFILES}/scripts/ensure-codex-guidance.sh" ] && { bash "${DOTFILES}/scripts/ensure-codex-guidance.sh" 2>/dev/null || helper_warn=1; } || true
[ -f "${DOTFILES}/scripts/ensure-lftprc.sh" ] && { bash "${DOTFILES}/scripts/ensure-lftprc.sh" 2>/dev/null || helper_warn=1; } || true

# 2. Homebrew
brew trust --formula oven-sh/bun/bun 2>/dev/null
brew update && brew upgrade --yes && brew cleanup

# 3. Claude Code 本體與 plugins（無 claude 時整段靜默跳過）
{
    command -v claude &>/dev/null && claude update 2>/dev/null
    claude plugins marketplace update 2>/dev/null
    jq -r ".enabledPlugins // {} | keys[]" "${DOTFILES}/claude/settings.json" 2>/dev/null |
        while read -r plugin; do
            claude plugins install "${plugin}" 2>/dev/null
            claude plugins update "${plugin}" 2>/dev/null
        done
} 2>/dev/null

# 4. known_hosts 同步
{ [ -f "${DOTFILES}/ssh/known_hosts" ] && cp "${DOTFILES}/ssh/known_hosts" ~/.ssh/known_hosts 2>/dev/null; } 2>/dev/null

# 5. 終判：helper 失敗要看得見（exit code 維持 0——不讓部署問題擋掉套件更新的成功）
if [ "${helper_warn}" -ne 0 ]; then
    echo "⚠️  部分 dotfiles helper 部署失敗——symlink 可能未更新，請跑 dotsync 或手動檢查"
fi

exit 0
