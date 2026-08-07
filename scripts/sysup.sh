#!/usr/bin/env bash
#
# sysup.sh — apt 系統更新（Linux only）
#
# 原為 setup-linux-env.sh 的一行 alias。抽成腳本是為了讓 all-up.sh 能直接呼叫，
# 不必再用 `bash -ic` 去載入 alias（無 TTY 時會噴 job control 雜訊）。
#
# 行為與原 alias 等價——本次只做搬移。
#
# 已知待決（不在本次範圍）：非互動環境下 apt 可能跳出 needrestart 服務清單或
# conffile keep/replace 詢問而卡住，硬化需要 DEBIAN_FRONTEND / NEEDRESTART_MODE /
# Dpkg::Options 的組合，其中 --force-confold 會丟棄套件方的新設定檔——屬策略取捨，
# 待決定後另行處理。
#
set -uo pipefail

# SYSUP_UNAME 僅供 tests/run.sh 注入平台，正常使用毋須設定
UNAME_S="${SYSUP_UNAME:-$(uname -s)}"

if [ "${UNAME_S}" != "Linux" ]; then
    echo "sysup 僅適用於 Linux（apt）；此處為 ${UNAME_S}" >&2
    exit 2
fi

sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
