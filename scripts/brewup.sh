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
SELF="${BASH_SOURCE[0]}"

# 1. dotfiles 同步
#    settings.json 為唯一權威、由選定的權威機器刻意 commit；其他機器上 harness 寫入的
#    runtime drift 是拋棄式的，故 pull 前先丟棄。rebase.autoStash 作為其他 dirty 檔的安全網。
self_sum_before=""
[ -f "$SELF" ] && self_sum_before=$(cksum < "$SELF" 2>/dev/null)
(cd "${DOTFILES}" && git checkout -- claude/settings.json 2>/dev/null; git pull --autostash 2>&1)

# 1a. pull 換掉了本腳本 → 用新版重跑一次。
#     **執行中的 bash 會繼續跑舊內容**——git checkout 是 unlink + 新建，正在執行的 process
#     握著舊 inode，檔案被換掉也讀不到新的（2026-08-09 實測確認）。後果是「pull 進新版、卻用
#     舊版跑完這一輪」：凡是本次更新才加進 pull 後段的動作（例如某支新的 ensure helper）
#     全部延後一個週期才生效，而且無聲——allup 會在 14 台上同時發生。
#     實地觸發：家裡那部落後的 MacBook 必須跑兩次 brewup 才部署到 helper。
#     `BREWUP_REEXEC` 是迴圈防護：只重跑一次，第二輪即使 checksum 又變也照常往下。
if [ -z "${BREWUP_REEXEC:-}" ] && [ -f "$SELF" ]; then
    self_sum_after=$(cksum < "$SELF" 2>/dev/null)
    if [ -n "$self_sum_before" ] && [ -n "$self_sum_after" ] && [ "$self_sum_before" != "$self_sum_after" ]; then
        echo "↻ brewup.sh 已更新，改用新版重跑"
        BREWUP_REEXEC=1 exec bash "$SELF" "$@"
    fi
fi

# 1b. pull 後的幂等部署 helper（與 dotfiles-sync.sh 同一組、同一形狀）
#     為什麼 brewup 也要跑：helper 原本只掛在 dotfiles-sync.sh，但 allup 走的是 brewup，
#     於是「日常全機隊更新」不會重建 symlink——來源檔改名或搬移時該連結會靜默失效
#     （ensure-codex-skills.sh 檔頭記載過實例：某台的 repo-review 停在四個月前的實體目錄）。
#     helper 失敗不中止更新，但**必須反映進終判**——不可誤報完成（同 dotfiles-sync.sh 的 codex C2）。
helper_warn=0
[ -f "${DOTFILES}/scripts/ensure-ssh-config.sh" ] && { bash "${DOTFILES}/scripts/ensure-ssh-config.sh" 2>/dev/null || helper_warn=1; } || true
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
