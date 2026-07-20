#!/usr/bin/env bash
#
# ensure-codex-skills.sh — 幂等確保 ~/.codex/skills/<name> 指向 dotfiles 的 codex/skills/<name>
#
# 由 dotfiles-sync.sh（本機與遠端）於 git pull 後呼叫，讓既有主機不必重跑 setup 也能拿到
# 最新的 codex skill。setup 腳本的 __codex_link_skills 只在跑 setup 時作用，而 codex skill
# 會隨 dotfiles 演進（如 repo-review），沒有這條散佈路徑就會停在安裝當下的版本——
# 實證：某台的 ~/.codex/skills/repo-review 停在 3/21 的實體目錄，dotfiles 已到 7/17，
# autocodex 的一行協議因此跑到舊 skill。
#
# 只接管 dotfiles 有的 skill 名稱；~/.codex/skills 下的其他項目（如 codex 自帶的 .system/）不動。
#
# SRC_ROOT / DST_ROOT 可覆寫供測試使用。
#

set -uo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SRC_ROOT="${SRC_ROOT:-$DOTFILES_DIR/codex/skills}"
DST_ROOT="${DST_ROOT:-$HOME/.codex/skills}"

[ -d "$SRC_ROOT" ] || exit 0

# 備份區刻意放在 DST_ROOT **之外**：codex 會掃 ~/.codex/skills/ 下的每個目錄當 skill，
# 備份若留在裡面會被當成另一個（過期的）skill 載入。
BACKUP_ROOT="${BACKUP_ROOT:-${DST_ROOT}-backup}"

# mkdir 失敗是真失敗（權限／唯讀 fs），不可與「本機沒有 ~/.codex」混為一談後靜默 exit 0
if ! mkdir -p "$DST_ROOT" 2>/dev/null; then
    echo "⚠️  無法建立 ${DST_ROOT}——codex skill 未部署"
    exit 1
fi

rc=0

for skill_dir in "$SRC_ROOT"/*; do
    [ -d "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue        # 沒有 SKILL.md 的不是 skill，跳過

    skill_name="$(basename "$skill_dir")"
    target="$DST_ROOT/$skill_name"

    # 已指向正確來源 → no-op（幂等，跑幾次都不動檔）。
    # 用 -ef 比 inode 而非 readlink 逐字比字串：DOTFILES_DIR 帶尾斜線、或該主機經 symlink 路徑
    # 存取 dotfiles 時，字串會對不上 → 每次 dotsync 都無謂 rm -rf + 重建。
    # 不加 -L 條件：若 ~/.codex/skills 本身是指向 dotfiles codex/skills 的 symlink，
    # $target 會解析成 $skill_dir 本體——帶 -L 會判定「需接管」而 rm -rf 掉 repo 內的
    # skill 原始碼，再留下自指斷鏈。單看 -ef（比 inode）即可同時擋掉這條自毀路徑。
    if [ "$target" -ef "$skill_dir" ]; then
        continue
    fi

    # 接管實體目錄：**備份而非 rm -rf**。這個腳本現在每台主機每次 dotsync 都跑，
    # 直接刪除等於把「只有重跑 setup 才會發生的破壞」變成例行性的——手工改過的內容
    # 會不可逆地消失。改成搬到備份區：可回收，且告知印到 stdout（呼叫端帶 2>/dev/null）。
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        backup="$BACKUP_ROOT/${skill_name}-$(date +%Y%m%d%H%M%S)"
        if mkdir -p "$BACKUP_ROOT" 2>/dev/null && mv "$target" "$backup" 2>/dev/null; then
            # ${} 必須帶大括號：全形括號會被 bash 併入變數名 → set -u 下 unbound variable
            echo "↻ 接管 ~/.codex/skills/${skill_name}（原實體目錄已備份到 ${backup}）"
        else
            echo "⚠️  無法備份既有的 ${target}——跳過，不冒險刪除"
            rc=1
            continue
        fi
    else
        # symlink（指向別處）→ 直接移除，刪掉 symlink 本身不損失內容
        rm -f "$target"
    fi

    # ln 必須檢查：上面已把原目錄搬走，此處若失敗又不報，skill 會整個消失而呼叫端仍見成功
    if ! ln -sfn "$skill_dir" "$target" 2>/dev/null; then
        echo "⚠️  無法建立 symlink ${target} → ${skill_dir}"
        rc=1
    fi
done

exit "$rc"
