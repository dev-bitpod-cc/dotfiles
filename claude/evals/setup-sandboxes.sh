#!/bin/bash
#
# setup-sandboxes.sh — 建立 skill 行為測試（evals / pressure-tests）用的沙盒
#
# 用法：
#   ./claude/evals/setup-sandboxes.sh [輸出目錄] [實例名]
#   預設輸出到 mktemp 目錄；實例名預設 "run"（測多模型時各建一份避免互相污染）
#
# 情境對照（各 skill evals.md 引用）：
#   u1  uap Scenario 1        main 上有未 commit 變更
#   u2  uap Scenario 5        誤 commit 在本地 main + working tree 髒檔（mixed state）
#   d1  deep-review autofix   main 上 working tree 有真 bug（float == 比較金額）
#   d2  deep-review F12       clean tree、與 origin/main 同步（範圍詢問 gate）
#   q1  ready4quit Q1         repo 有未 commit 殘留
#   c1  check-crawl-quality C1  120 筆 JSON、3 來源、其一 80% boilerplate
#   n1  nc-notify N1          空白專案目錄
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

make_u1; make_u2; make_d1; make_d2; make_q1; make_c1; make_n1

echo "=== sandboxes ready: $ROOT (instance: $INSTANCE) ==="
ls "$ROOT"
