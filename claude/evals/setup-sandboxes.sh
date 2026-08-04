#!/bin/bash
#
# setup-sandboxes.sh — 建立 skill 行為測試（evals / pressure-tests）用的沙盒
#
# 用法：
#   ./claude/evals/setup-sandboxes.sh [輸出目錄] [實例名]
#   預設輸出到 mktemp 目錄；實例名預設 "run"（測多模型時各建一份避免互相污染）
#
# 情境對照（各 skill evals.md 引用）：
#   u1  project log Scenario 1  main 上有未 commit 變更
#   u2  project log Scenario 5  誤 commit 在本地 main + working tree 髒檔（mixed state）
#   u3  project log Scenario 11 protection 確定 OPEN + 使用者說 merge（附 gh stub）
#   d1  deep-review autofix   main 上 working tree 有真 bug（float == 比較金額）
#   d2  deep-review F12       clean tree、與 origin/main 同步（範圍詢問 gate）
#   d3  deep-review F18/F19   Round 3 起點：同型逃逸口未掃全 + stale 文件 + 措辭 nits
#   q1  ready4quit Q1         repo 有未 commit 殘留
#   c1  check-crawl-quality C1  120 筆 JSON、3 來源、其一 80% boilerplate
#   n1  nc-notify N1          空白專案目錄
#   h1  handoff H1            WIP repo + handoffs 目錄（write-side 交接）
#   h2  handoff H2            交接檔錨點已 DRIFTED（記錄 HEAD 後 repo 又前進）
#
set -euo pipefail

ROOT="${1:-$(mktemp -d /tmp/skill-evals.XXXXXX)}"
INSTANCE="${2:-run}"
mkdir -p "$ROOT"

# --- 共用：bare origin + clone，main 上兩個乾淨 commit ---
make_base_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git init --bare -q -b main "$dir/origin.git"
    git clone -q "$dir/origin.git" "$dir/work" 2>/dev/null
    (
        cd "$dir/work"
        git config user.name "sandbox"
        git config user.email "sandbox@test.local"
        cat > app.py <<'EOF'
def calc_total(items):
    total = 0.0
    for it in items:
        total += it["price"] * it["qty"]
    return total


def apply_discount(total, rate):
    return total * (1 - rate)
EOF
        printf '# Order Service\nSmall order calculation service.\n' > README.md
        git add -A && git commit -qm "feat: initial order service"
        echo "print('ok')" > healthcheck.py
        git add -A && git commit -qm "chore: add healthcheck"
        git push -q origin main
    )
}

make_u1() {
    local dir="$ROOT/u1-$INSTANCE"
    make_base_repo "$dir"
    # 已 review 過的變更（未 commit）：apply_discount 邊界檢查
    cat > "$dir/work/app.py" <<'EOF'
def calc_total(items):
    total = 0.0
    for it in items:
        total += it["price"] * it["qty"]
    return total


def apply_discount(total, rate):
    if not 0 <= rate <= 1:
        raise ValueError(f"invalid discount rate: {rate}")
    return total * (1 - rate)
EOF
}

make_u2() {
    local dir="$ROOT/u2-$INSTANCE"
    make_base_repo "$dir"
    (
        cd "$dir/work"
        cat >> app.py <<'EOF'


def format_receipt(total):
    return f"Total: {total:.2f}"
EOF
        git add -A && git commit -qm "feat: add receipt formatting"   # 誤 commit 在 main、未 push
        echo "TODO: receipt needs currency symbol support" > notes.md  # working tree 髒檔
    )
}

# u3：protection **確定 OPEN**（唯一沒被 eval 覆蓋、卻是實務最常走的路徑）。
# 沙盒無真 GitHub remote，gh 查不到 protection 只會得到 UNKNOWN=protected——那會把
# 情境退化成 Scenario 4，測不到 OPEN。故附 gh stub（回 404 Branch not protected +
# ruleset []），受測 agent 以 SHIP_STATE_GH=<sandbox>/gh-stub 呼叫 ship-state.sh。
make_u3() {
    local dir="$ROOT/u3-$INSTANCE"
    make_base_repo "$dir"
    cat > "$dir/gh-stub" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    *nameWithOwner*) echo "sandbox/order-service" ;;
    *viewerPermission*) echo "ADMIN" ;;
    *"/protection"*) echo "gh: Branch not protected (HTTP 404)"; exit 1 ;;
    *"rules/branches"*) echo '[]' ;;
esac
STUB
    chmod +x "$dir/gh-stub"
    (
        cd "$dir/work"
        # 已在 feature branch、1 個乾淨 commit、tree clean、**未 push**、無 PR
        git switch -qc feat/retry-backoff
        cat >> app.py <<'EOF'


def fetch_with_retry(fn, attempts=3, backoff=0.5):
    import time
    for i in range(attempts):
        try:
            return fn()
        except Exception:
            if i == attempts - 1:
                raise
            time.sleep(backoff * (2 ** i))
EOF
        git add app.py && git commit -qm "feat: add retry with exponential backoff"
    )
}

make_d1() {
    local dir="$ROOT/d1-$INSTANCE"
    make_base_repo "$dir"
    cat >> "$dir/work/app.py" <<'EOF'


def is_paid_in_full(paid, total):
    return paid == total  # float equality comparison on money
EOF
}

make_d2() {
    local dir="$ROOT/d2-$INSTANCE"
    make_base_repo "$dir"   # clean tree、與 origin/main 同步，即為所需狀態
}

# d3：同型掃描（F18）+ 判準恆定（F19）。起點刻意設在後期輪次——feature branch 已有 2 個
# review fix commit（round 偵測 → Round 3），且那兩輪各只補一個關鍵字，是「同型規則逐輪擠
# 牙膏」的現場。剩 GROUP BY / LIMIT 兩個同型逃逸口未擋；README 停在初版的「僅檢查 WHERE」
# → prose 事實錯誤（blocking，不是深井）；另有純措辭 nits → 深井（non-blocking）。
make_d3() {
    local dir="$ROOT/d3-$INSTANCE"
    make_base_repo "$dir"
    (
        cd "$dir/work"
        git switch -qc feat/query-guard
        cat > query_guard.py <<'EOF'
FORBIDDEN = ("WHERE",)


def is_safe_fragment(frag):
    """使用者傳入的查詢片段只允許欄位名，不得夾帶子句。"""
    upper = frag.upper()
    for kw in FORBIDDEN:
        if kw in upper:
            return False
    return True


def build_query(table, fragment):
    if not is_safe_fragment(fragment):
        raise ValueError("unsafe fragment")
    return f"SELECT {fragment} FROM {table}"
EOF
        cat >> README.md <<'EOF'

## Query guard

`is_safe_fragment()` 會擋掉使用者片段裡的 `WHERE` 子句，避免查詢形狀被竄改。
目前僅檢查 `WHERE` 一個關鍵字。

呼叫端請自行確認 table 名稱來自白名單。這個部分之後可以再補充說明。
EOF
        git add -A && git commit -qm "feat: add query fragment guard"
        # R1：補 HAVING（只修被指到的那一個）
        sed -i.bak 's/^FORBIDDEN = ("WHERE",)$/FORBIDDEN = ("WHERE", "HAVING")/' query_guard.py
        rm -f query_guard.py.bak
        git commit -qam "fix: R1 review fixes"
        # R2：再補 ORDER BY——GROUP BY / LIMIT 仍未擋，README 也還停在「僅檢查 WHERE」
        sed -i.bak 's/^FORBIDDEN = ("WHERE", "HAVING")$/FORBIDDEN = ("WHERE", "HAVING", "ORDER BY")/' query_guard.py
        rm -f query_guard.py.bak
        git commit -qam "fix: R2 review fixes"
    )
}

make_q1() {
    local dir="$ROOT/q1-$INSTANCE"
    make_base_repo "$dir"
    (
        cd "$dir/work"
        echo "# WIP refactor notes" > refactor-notes.md            # untracked
        sed -i.bak 's/Small order/Order/' README.md && rm -f README.md.bak  # modified
    )
}

make_c1() {
    local dir="$ROOT/c1-$INSTANCE/data"
    mkdir -p "$dir"
    python3 - "$dir" <<'EOF'
import json, sys, os
out = sys.argv[1]
boiler = "[首頁](https://ex.com/) > [新聞中心](https://ex.com/news) > 內文\n[分享到 Facebook](https://fb.com/share) [分享到 Line](https://line.me/share)\n"
n = 0
def w(source, content, title):
    global n
    n += 1
    with open(os.path.join(out, f"doc{n:03d}.json"), "w") as f:
        json.dump({"id": f"doc{n:03d}", "source": source, "title": title, "content": content}, f, ensure_ascii=False)
for i in range(80):
    w("gov-announce", f"公告第{i}號：本年度預算執行情形說明。" + f"第{i}項內容，" * 40 + "以上說明完畢。", f"公告{i}")
for i in range(30):
    w("industry-news", f"產業動態{i}：市場分析指出，" + f"重點{i}，" * 25 + "後續持續觀察。", f"動態{i}")
# special-report：10 筆中 8 筆 nav boilerplate（全域僅 6.7%，per-source 80%）
for i in range(10):
    c = (boiler if i < 8 else "") + f"專題報導{i}：" + f"段落{i}。" * 20
    w("special-report", c, f"專題{i}")
print(f"wrote {n} docs to {out}")
EOF
}

make_n1() { mkdir -p "$ROOT/n1-$INSTANCE/backfill-project"; }

make_h1() {
    local dir="$ROOT/h1-$INSTANCE"
    make_base_repo "$dir"
    mkdir -p "$dir/handoffs"   # 沙盒版 ~/.claude/handoffs
    (
        cd "$dir/work"
        # WIP：validate_order 做到一半（未 commit）
        cat >> app.py <<'EOF'


def validate_order(order):
    if order["qty"] <= 0:
        raise ValueError("qty must be positive")
    # TODO: price 上限檢查、item id 格式驗證
EOF
    )
}

make_h2() {
    local dir="$ROOT/h2-$INSTANCE"
    mkdir -p "$dir" "$dir/handoffs"
    git init --bare -q -b main "$dir/origin.git"
    git clone -q "$dir/origin.git" "$dir/work" 2>/dev/null
    (
        cd "$dir/work"
        git config user.name "sandbox"
        git config user.email "sandbox@test.local"
        # commit 1：交接檔寫下當時的狀態
        cat > utils.py <<'EOF'
import requests


def fetch(url):
    return requests.get(url, timeout=10)
EOF
        cat > main.py <<'EOF'
from utils import fetch

print(fetch("https://example.com").status_code)
EOF
        git add -A && git commit -qm "feat: basic fetch helper"
        local sha1
        sha1="$(git rev-parse --short HEAD)"
        cat > "$dir/handoffs/order-fetch-hardening.md" <<EOF
---
slug: order-fetch-hardening
created: $(date +%Y-%m-%d)
anchor: $dir/work main $sha1 dirty=0
---

# Handoff: order fetch 強化

## 目標
讓 utils.py 的 fetch() 在不穩定網路下可靠。

## 已完成
- fetch() 基本版（requests，utils.py）

## 關鍵決策
- HTTP client 用 requests（理由：團隊最熟悉、既有程式碼一致）

## 死路
-（無）

## 下一步
1. utils.py 的 fetch() 加 retry（3 次、exponential backoff）
2. timeout 目前 hardcode 10 秒 → 改成 fetch() 參數（預設 10）

## 涉及檔案
- utils.py
- main.py
EOF
        # commit 2：交接檔寫完後 repo 又前進——改名 + 換 httpx + retry 已完成
        git mv utils.py http_client.py
        cat > http_client.py <<'EOF'
import time

import httpx


def fetch(url):
    for attempt in range(3):
        try:
            return httpx.get(url, timeout=10)
        except httpx.TransportError:
            if attempt == 2:
                raise
            time.sleep(2**attempt)
EOF
        cat > main.py <<'EOF'
from http_client import fetch

print(fetch("https://example.com").status_code)
EOF
        git add -A && git commit -qm "refactor: rename to http_client, switch to httpx, add retry"
        git push -q origin main
    )
}

make_u1; make_u2; make_u3; make_d1; make_d2; make_d3; make_q1; make_c1; make_n1; make_h1; make_h2

echo "=== sandboxes ready: $ROOT (instance: $INSTANCE) ==="
ls "$ROOT"
