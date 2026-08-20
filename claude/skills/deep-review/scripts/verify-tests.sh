#!/usr/bin/env bash
#
# verify-tests.sh — deep-review autofix「修復後驗證」的測試框架偵測與執行（單 repo）
#
# 用法：verify-tests.sh <repo-path>
#
# 偵測與執行（照 `../references/modes-and-scope.md`「Autofix 模式」現行為，不擴權）：
#   pyproject.toml 存在          → uv run pytest（pytest rc=5「no tests collected」→ SKIP）
#   package.json .scripts.test   → bun test；test script 為 npm placeholder（no test specified）
#                                  → SKIP 不執行；rc!=0 且輸出含「0 test files matching」→ SKIP
#   兩者並存（monorepo）→ 都跑，任一紅即 FAIL；都不在 → SKIP
#
# exit：0=PASS；1=FAIL（留在本輪續修，勿 commit）；3=SKIP（無測試框架/無測試，依 SKILL 直接 commit）；
#       2=用法/路徑錯誤
#
# 依賴：jq（package.json 解析）；uv / bun 依偵測結果才呼叫。
#
# 邊界：
# - 本腳本會「執行專案程式碼」（uv 可能建 venv／裝依賴）——與 model 手跑的現行為相同，
#   是 skill 腳本 git-唯讀慣例的例外面（不動 git state，只動專案環境）。
# - 不做內部 timeout：macOS 無內建 timeout(1)，為此引入 coreutils 依賴不值；
#   呼叫端（Claude Code Bash tool）的 10 分鐘上限兜底。
# - bun「無測試檔」的辨識訊息（error: 0 test files matching）為實測行為
#   （2026-07-21，bun v1.3.14）；bun 改版若換訊息，SKIP 會退化成 FAIL——保守方向，
#   不會誤判通過。

set -uo pipefail

if [ $# -ne 1 ]; then
    echo "用法：$0 <repo-path>" >&2
    exit 2
fi
repo="$1"
if [ ! -d "$repo" ]; then
    echo "error: 路徑不存在：${repo}" >&2
    exit 2
fi

echo "=== $repo ==="

fail=0   # 任一框架紅
ran=0    # 至少一個框架真的跑了測試（PASS/FAIL 都算；SKIP 不算）

# -- Python：pyproject.toml → uv run pytest --
if [ -f "$repo/pyproject.toml" ]; then
    echo "framework: pytest（pyproject.toml）"
    echo "cmd: uv run pytest"
    out_py="$(cd "$repo" && uv run pytest 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ran=1
        echo "pytest: PASS"
    elif [ "$rc" -eq 5 ]; then
        # pytest 契約：rc=5 = no tests collected
        echo "pytest: SKIP（rc=5，no tests collected）"
    else
        ran=1
        fail=1
        echo "pytest: FAIL（rc=${rc}）"
        echo "tail:"
        printf '%s\n' "$out_py" | tail -30 | sed 's/^/  /'
    fi
fi

# -- JS/TS：package.json 有 test script → bun test --
if [ -f "$repo/package.json" ]; then
    tscript="$(jq -r '.scripts.test // empty' "$repo/package.json" 2>/dev/null)" || tscript=""
    if [ -z "$tscript" ]; then
        :   # 無 test script → 不算框架
    elif printf '%s' "$tscript" | grep -q "no test specified"; then
        echo "framework: bun（package.json test script 為 npm placeholder）"
        echo "bun: SKIP（placeholder，不執行）"
    else
        echo "framework: bun test（package.json scripts.test）"
        echo "cmd: bun test"
        out_js="$(cd "$repo" && bun test 2>&1)"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            ran=1
            echo "bun: PASS"
        elif printf '%s\n' "$out_js" | grep -q "0 test files matching"; then
            echo "bun: SKIP（無測試檔）"
        else
            ran=1
            fail=1
            echo "bun: FAIL（rc=${rc}）"
            echo "tail:"
            printf '%s\n' "$out_js" | tail -30 | sed 's/^/  /'
        fi
    fi
fi

if [ "$fail" -eq 1 ]; then
    echo "verdict: FAIL"
    exit 1
elif [ "$ran" -eq 1 ]; then
    echo "verdict: PASS"
    exit 0
else
    echo "verdict: SKIP（無測試框架，依 SKILL 直接 commit）"
    exit 3
fi
