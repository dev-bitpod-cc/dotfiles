#!/usr/bin/env bash
#
# brewfix.sh — macOS：cask 升版被 Gatekeeper 卡死的診斷與復原
#
# 病灶（完整機制見 claude/known-hazards.md「cask 升版卡死」）：
#   帶 `generate_completions_from_executable` 的 cask（如 codex）升版時，brew 會在
#   install_artifacts 階段對剛解壓、仍帶 quarantine 的 binary **各 exec 一次**
#   bash/zsh/fish 以產生 completion。該次 exec 若進入 Gatekeeper 首次核可流程而
#   無人回應，brew 會同步等待到天荒地老（畫面停在前一個 artifact 的 `Linking Binary`），
#   中斷後 syspolicyd 對該「完整路徑」的評估記錄卡死，之後每次 exec 都在 kernel 層等
#   一個永不返回的結果。
#
# 本腳本只做「復原」，不宣稱能預防——預防手段的有效性尚未證實（見 STATUS.md）。
#
# 用法：
#   brewfix          唯讀診斷，不動任何東西
#   brewfix --fix    執行復原（kill 卡死 process → killall syspolicyd → 清 *.upgrading）
#
# exit code：0=CLEAN  1=偵測到問題（診斷模式）或復原後仍有殘留  2=前提不成立
#
# 測試注入點（僅供 tests/run.sh；正常使用毋須設定）：
#   BREWFIX_UNAME / BREWFIX_CASKROOM / BREWFIX_PS / BREWFIX_LSOF
#   BREWFIX_KILLALL / BREWFIX_SUDO / BREWFIX_BREW_PREFIX
#
set -uo pipefail

UNAME_S="${BREWFIX_UNAME:-$(uname -s)}"
PS_CMD="${BREWFIX_PS:-ps}"
LSOF_CMD="${BREWFIX_LSOF:-lsof}"
KILLALL_CMD="${BREWFIX_KILLALL:-killall}"
SUDO_CMD="${BREWFIX_SUDO:-sudo}"

# 卡在 _dyld_start 的 process 只開著 cwd + 自身 binary + dyld + 三個 fd（實測 7 條）；
# 正常執行中的 process 會載入數十個 dylib。取 12 為保守上界。
STUCK_LSOF_MAX=12

FIX=0
case "${1:-}" in
    --fix) FIX=1 ;;
    "")    ;;
    -h|--help)
        sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "未知參數：${1}（用法：brewfix [--fix]）" >&2
        exit 2
        ;;
esac

# ---- 前提 1：平台 ----------------------------------------------------------
if [ "${UNAME_S}" != "Darwin" ]; then
    echo "brewfix 僅適用於 macOS（syspolicyd / Gatekeeper）；此處為 ${UNAME_S}" >&2
    exit 2
fi

# ---- 前提 2：brew 與 Caskroom ----------------------------------------------
if [ -n "${BREWFIX_BREW_PREFIX:-}" ]; then
    BREW_PREFIX="${BREWFIX_BREW_PREFIX}"
elif command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix)"
else
    echo "找不到 brew，無法定位 Caskroom" >&2
    exit 2
fi

CASKROOM="${BREWFIX_CASKROOM:-${BREW_PREFIX}/Caskroom}"
if [ ! -d "${CASKROOM}" ]; then
    echo "Caskroom 不存在：${CASKROOM}" >&2
    exit 2
fi

# ---- 診斷 1：*.upgrading 殘留 ----------------------------------------------
# brew cask 升版時把舊版目錄改名為 <old>.upgrading，成功後刪除。殘留即代表那次被中斷。
# `brew cleanup` 只清 cache 的 tar.gz，不碰它。
residues=()
while IFS= read -r d; do
    [ -n "${d}" ] && residues+=("${d}")
done < <(find "${CASKROOM}" -maxdepth 2 -type d -name '*.upgrading' 2>/dev/null | sort)

# ---- 診斷 2：卡死的 process ------------------------------------------------
# 判準：執行檔位於 brew prefix 底下，且 lsof 條目數異常少（＝一個 dylib 都沒載入，
# 程式碼一行未跑）。與 config / auth / 網路全然無關。
stuck=()
while IFS= read -r line; do
    [ -n "${line}" ] && stuck+=("${line}")
done < <(
    "${PS_CMD}" -eo pid=,comm= 2>/dev/null | while read -r pid comm; do
        # 只看執行檔位於 brew prefix 底下的 process。
        # 這裡刻意不用 case——bash 3.2（macOS 內建）在 process substitution 內部
        # 會把 case pattern 的 `)` 誤判為 `<( ` 的結束括號，整段變 syntax error。
        [[ "${comm}" == "${BREW_PREFIX}"/* ]] || continue
        n=$("${LSOF_CMD}" -p "${pid}" 2>/dev/null | wc -l | tr -d ' ')
        [ -z "${n}" ] && continue
        [ "${n}" -le "${STUCK_LSOF_MAX}" ] && printf '%s\t%s\t%s\n' "${pid}" "${comm}" "${n}"
    done
)

# ---- 報告 ------------------------------------------------------------------
for d in ${residues+"${residues[@]}"}; do
    sz=$(du -sh "${d}" 2>/dev/null | cut -f1)
    echo "upgrading-residue: ${d} (${sz:-?})"
done
for s in ${stuck+"${stuck[@]}"}; do
    pid=$(printf '%s' "${s}" | cut -f1)
    path=$(printf '%s' "${s}" | cut -f2)
    nfd=$(printf '%s' "${s}" | cut -f3)
    echo "stuck-process: pid=${pid} lsof=${nfd} ${path}"
done

n_res=${#residues[@]}
n_stk=${#stuck[@]}

if [ "${n_stk}" -gt 0 ]; then
    verdict=STUCK
elif [ "${n_res}" -gt 0 ]; then
    verdict=RESIDUE
else
    verdict=CLEAN
fi
echo "verdict: ${verdict}"

if [ "${verdict}" = CLEAN ]; then
    exit 0
fi

if [ "${FIX}" -eq 0 ]; then
    echo
    echo "唯讀診斷（未做任何變更）。要復原請執行：brewfix --fix"
    exit 1
fi

# ---- 復原 ------------------------------------------------------------------
echo
echo "▶ 執行復原"

# (1) 先清掉卡死的 process，否則 killall 後它們仍掛在舊狀態上
for s in ${stuck+"${stuck[@]}"}; do
    pid=$(printf '%s' "${s}" | cut -f1)
    kill -9 "${pid}" 2>/dev/null && echo "  已終止 pid=${pid}"
done

# (2) 重啟 syspolicyd（launchd 會 on-demand 重生；之後 launchctl list 顯示 `-  0` 屬正常）
if [ "${n_stk}" -gt 0 ]; then
    if "${SUDO_CMD}" -n true 2>/dev/null; then
        "${SUDO_CMD}" "${KILLALL_CMD}" syspolicyd 2>/dev/null
        echo "  已重啟 syspolicyd"
    else
        echo "  ⚠️  需要 sudo 才能重啟 syspolicyd，請手動執行：sudo killall syspolicyd" >&2
    fi
fi

# (3) 清 *.upgrading 殘留
#     破壞性動作，逐項複驗前提：必須是目錄、位於 Caskroom 底下、名稱以 .upgrading 結尾。
#     三者任一不成立即跳過——寧可留著讓人工處理，不可誤刪。
for d in ${residues+"${residues[@]}"}; do
    case "${d}" in
        "${CASKROOM}"/*.upgrading|"${CASKROOM}"/*/*.upgrading) : ;;
        *) echo "  ⚠️  跳過（不在 Caskroom 底下或名稱不符）：${d}" >&2; continue ;;
    esac
    [ -d "${d}" ] || { echo "  ⚠️  跳過（不是目錄）：${d}" >&2; continue; }
    rm -rf "${d}" && echo "  已清除 ${d}"
done

# ---- 復原後複驗 ------------------------------------------------------------
echo
left=$(find "${CASKROOM}" -maxdepth 2 -type d -name '*.upgrading' 2>/dev/null | wc -l | tr -d ' ')
if [ "${left}" -eq 0 ]; then
    echo "verdict: CLEAN（復原完成）"
    exit 0
fi
echo "verdict: RESIDUE（仍有 ${left} 項殘留，需人工處理）"
exit 1
