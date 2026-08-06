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
#   d4  deep-review F20(a)     skill-authoring batch，只有措辭/完整度問題
#   d5  deep-review F20(b)     同 d4 + 夾帶 git 指令語意錯誤（兩點 range 用在整條 branch）
#   d6  deep-review F20(c)     負向邊界：product code + README，不得觸發 gate
#   d7  deep-review F21        anchor 已標記 terminal_reason=r5-blocking
#   q1  ready4quit Q1         repo 有未 commit 殘留
#   c1  check-crawl-quality C1  120 筆 JSON、3 來源、其一 80% boilerplate
#   n1  nc-notify N1          空白專案目錄
#   h1  handoff H1            WIP repo + handoffs 目錄（write-side 交接）
#   h2  handoff H2            交接檔錨點已 DRIFTED（記錄 HEAD 後 repo 又前進）
#   h5  handoff H5            續寫交接：archive 有前一份（帶死路）+ repo 有 STATUS.md
#   h6  handoff H6            多 repo 混合 verdict：repo-a FRESH、repo-b DRIFTED
#   h7  handoff H7            DIVERGED：錨點的 HEAD 被 amend 掉，不在現行歷史上
#   h8  handoff H8            同 h5 + active 有一份確實過期的交接檔（explicit slug / EXPIRED 回報）
#
set -euo pipefail

ROOT="${1:-$(mktemp -d /tmp/skill-evals.XXXXXX)}"
INSTANCE="${2:-run}"
mkdir -p "$ROOT"
# handoff fixture 會把 `$ROOT/<情境>-$INSTANCE` 寫進 anchor 行，故此處與 handoff-anchor.sh
# anchors 受同一道約束：相對路徑會讓後續從別的 cwd 驗證時對到別的 repo（且誤報成 DIVERGED），
# 含空白則破壞欄位解析。**$INSTANCE 一併驗**——它也是寫入路徑的一段，而 README 的執行方式
# 就是每個受測模型各給一個 instance 名（`sonnet run2` 這種帶空白的寫法很自然）
ROOT="$(CDPATH='' cd -- "$ROOT" && pwd -P)"
case "$ROOT$INSTANCE" in *[[:space:]]*)
    echo "error: 輸出目錄或 instance 名含空白，handoff fixture 的 anchor 行以空白分欄：ROOT=${ROOT} INSTANCE=${INSTANCE}" >&2
    exit 1 ;;
esac

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
        # 前一輪修復：補 HAVING（只修被指到的那一個）
        sed -i.bak 's/^FORBIDDEN = ("WHERE",)$/FORBIDDEN = ("WHERE", "HAVING")/' query_guard.py
        rm -f query_guard.py.bak
        git commit -qam "fix: address review findings"
        # 再一輪：補 ORDER BY——GROUP BY / LIMIT 仍未擋，README 也還停在「僅檢查 WHERE」
        # commit message 中性化（不編輪號）：2026-08-05 盲測實測 6/6 reviewer 主動跑 git log
        # 並讀到輪號寫進 finding，故 fixture 必須與 SKILL.md 的中性化規則一致，否則
        # 任何「輪次是否影響判斷」的實驗都會被 fixture 自己的 git log 汙染。
        sed -i.bak 's/^FORBIDDEN = ("WHERE", "HAVING")$/FORBIDDEN = ("WHERE", "HAVING", "ORDER BY")/' query_guard.py
        rm -f query_guard.py.bak
        git commit -qam "fix: address review findings"
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

# h5：續寫交接（同 slug 第 2 輪）。前一份已消費落在 archive/、active 目錄空——模擬新 session
# 未經 resume 直接寫交接，前一份不在 context。repo 有 STATUS.md（死路節刻意不含前一份那兩條，
# 讓「沉澱進 dossier」有落點）。
# h5/h8 共用的 pipeline 續寫 fixture（目錄由呼叫端給）
make_pipeline_sandbox() {
    local dir="$1"
    mkdir -p "$dir" "$dir/handoffs/archive"
    git init --bare -q -b main "$dir/origin.git"
    git clone -q "$dir/origin.git" "$dir/work" 2>/dev/null
    (
        cd "$dir/work"
        git config user.name "sandbox"
        git config user.email "sandbox@test.local"
        cat > pipeline.py <<'EOF'
import time

import httpx


def fetch(url, timeout=10):
    for attempt in range(3):
        try:
            return httpx.get(url, timeout=timeout)
        except httpx.TransportError:
            if attempt == 2:
                raise
            time.sleep(2**attempt)
EOF
        cat > STATUS.md <<'EOF'
# STATUS.md

訂單 pipeline 服務——外部 API 取單與正規化的單一來源

---

## 進行中

### pipeline 穩定性強化
retry/backoff 已上；timeout 參數化已上；metrics 做到一半。

---

## 關鍵決策(附理由)

- **backoff 用 2^n**:外部 API 文件建議的重試節奏,固定間隔在尖峰會同步撞牆。

---

## 死路(試過但放棄——防重工)

- **不用 tenacity 套件**:只需要三行 backoff,多一個相依不划算。

---

## 已完成(里程碑)

- 2026-08-01 retry + backoff 上線
EOF
        git add -A && git commit -qm "feat: fetch with retry/backoff"
        # 本輪進度：timeout 參數化已 commit
        git commit -q --allow-empty -m "feat: parameterize timeout"
        git push -q origin main
        # WIP：metrics 做到一半（未 commit）
        cat >> pipeline.py <<'EOF'


def record_latency(name, seconds):
    # TODO: 接 statsd client、加 tag（endpoint / status）
    print(f"{name}={seconds}")
EOF
    )
    # 前一份交接檔（已消費，帶兩條跨輪仍有效的死路——STATUS.md 裡刻意沒有）。
    # 錨點指向前一輪當時的 HEAD，agent 若去 verify 會得到合理的 DRIFTED（repo 已前進一個 commit）
    local prev_sha
    prev_sha="$(git -C "$dir/work" rev-parse HEAD~1)"
    cat > "$dir/handoffs/archive/20260801-101500-order-pipeline-hardening.md" <<EOF
---
slug: order-pipeline-hardening
created: 2026-08-01
anchor: $dir/work main $prev_sha dirty=0
---

# Handoff: 訂單 pipeline 穩定性強化

## 目標
讓 pipeline.py 的外部取單在不穩定網路與限流下可靠。

## 已完成
- fetch() retry + exponential backoff

## 關鍵決策（附理由）
- backoff 用 2^n——外部 API 文件建議的重試節奏

## 死路（試過但放棄——防重工）
- **threading 併發打外部 API 已放棄**：對方有 per-key QPS 限制，併發只換到一波 429，
  改回序列 + backoff 反而穩。不要再試「加 worker 就會更快」。
- **pydantic v2 全面遷移已放棄**：相依的 legacy 套件把 pydantic 釘在 v1，升上去整條
  pipeline 匯入就爆。

## 下一步（逐條可執行）
1. timeout 從 hardcode 改成 fetch() 參數（預設 10）
2. 加 latency metrics

## 涉及檔案
- pipeline.py
EOF
}

make_h5() { make_pipeline_sandbox "$ROOT/h5-$INSTANCE"; }

# h8：同 h5 的續寫 fixture，但 query 會明確給 slug；**額外在 active 放一份確實過期的交接檔**
# ——否則 `list` 不會產生任何 EXPIRED 項目，「有 EXPIRED 就列出」變成空條件，agent 完全
# 忽略 list 輸出照樣過關（vacuous expectation，第三方審查抓到）。這份用另一條工作線的
# slug，不干擾 find-predecessor 的定位判定。
make_h8() {
    local dir="$ROOT/h8-$INSTANCE"
    make_pipeline_sandbox "$dir"
    local sha
    sha="$(git -C "$dir/work" rev-parse HEAD)"
    cat > "$dir/handoffs/stale-tej-export.md" <<EOF
---
slug: stale-tej-export
created: 2026-06-20
anchor: $dir/work main $sha dirty=0
---

# Handoff: TEJ 匯出格式調查（擱置已久）

## 目標
釐清 TEJ 匯出檔的欄位對應，供下游 ingest 使用。

## 已完成
- 取得樣本檔、確認分隔符為 tab

## 關鍵決策（附理由）
- 先不寫 parser——欄位定義還沒跟對方確認，寫了會白工

## 死路（試過但放棄——防重工）
-（無）

## 下一步（逐條可執行）
1. 跟對方要正式的欄位定義文件

## 涉及檔案
- （尚未新建）
EOF
}

# h6：多 repo 混合 verdict——repo-a 錨點未動（FRESH）、repo-b 錨點後又前進（DRIFTED，
# 且「下一步」其中一條已被做掉）。驗逐 repo 處置，不因聚合旗標把 repo-a 一起降級。
make_h6() {
    local dir="$ROOT/h6-$INSTANCE"
    mkdir -p "$dir" "$dir/handoffs"
    local sha_a sha_b r
    for r in repo-a repo-b; do
        git init -q -b main "$dir/$r"
        (
            cd "$dir/$r"
            git config user.name "sandbox"
            git config user.email "sandbox@test.local"
            printf 'def handle(req):\n    return {"ok": True}\n' > svc.py
            git add -A && git commit -qm "feat: initial $r service"
        )
    done
    sha_a="$(git -C "$dir/repo-a" rev-parse HEAD)"
    sha_b="$(git -C "$dir/repo-b" rev-parse HEAD)"
    cat > "$dir/handoffs/gateway-and-order-hardening.md" <<EOF
---
slug: gateway-and-order-hardening
created: $(date +%Y-%m-%d)
anchor: $dir/repo-a main $sha_a dirty=0
anchor: $dir/repo-b main $sha_b dirty=0
---

# Handoff: gateway 限流 + order 取單強化

## 目標
gateway 擋住突發流量；order 取單在限流下不掉單。

## 已完成
- 兩邊的基本 handler（repo-a / repo-b 各 svc.py）

## 關鍵決策（附理由）
- **[repo-b] HTTP client 用 requests**：團隊最熟悉

## 死路（試過但放棄——防重工）
-（無）

## 下一步（逐條可執行）
1. **[repo-a]** svc.py 加 rate limit（token bucket，每 key 10 req/s）
2. **[repo-b]** svc.py 的取單加 retry（3 次、exponential backoff）
3. **[repo-b]** timeout 改成參數（預設 10 秒）

## 涉及檔案
- repo-a/svc.py
- repo-b/svc.py
EOF
    # repo-b 在交接檔寫完後前進：retry 已完成（下一步第 2 條已被做掉）、client 換成 httpx
    (
        cd "$dir/repo-b"
        cat > svc.py <<'EOF'
import time

import httpx


def handle(req):
    for attempt in range(3):
        try:
            return httpx.get(req["url"], timeout=10).json()
        except httpx.TransportError:
            if attempt == 2:
                raise
            time.sleep(2**attempt)
EOF
        git add -A && git commit -qm "feat: add retry, switch to httpx"
    )
}

# h7：DIVERGED——錨點記錄的 HEAD 被 amend 掉，已不在現行歷史上。內容一律降級為線索。
make_h7() {
    local dir="$ROOT/h7-$INSTANCE"
    mkdir -p "$dir" "$dir/handoffs"
    git init -q -b main "$dir/work"
    (
        cd "$dir/work"
        git config user.name "sandbox"
        git config user.email "sandbox@test.local"
        printf 'def parse(raw):\n    return raw.split(",")\n' > parser.py
        git add -A && git commit -qm "feat: naive csv parser"
    )
    local sha
    sha="$(git -C "$dir/work" rev-parse HEAD)"
    cat > "$dir/handoffs/csv-parser-rewrite.md" <<EOF
---
slug: csv-parser-rewrite
created: $(date +%Y-%m-%d)
anchor: $dir/work main $sha dirty=0
---

# Handoff: CSV parser 改寫

## 目標
parser.py 能正確處理帶引號與跳脫的欄位。

## 已完成
- naive split(",") 版本（parser.py）

## 關鍵決策（附理由）
- 先自己寫而不用 csv 模組——輸入格式非標準，欄位分隔符會動態變

## 死路（試過但放棄——防重工）
-（無）

## 下一步（逐條可執行）
1. parser.py 的 parse() 加引號欄位支援（帶引號的 "a,b" 應保持成一欄，整列解析成 2 欄）
2. 加跳脫字元處理

## 涉及檔案
- parser.py
EOF
    # 交接檔寫完後歷史被改寫：改用標準 csv 模組，原 commit 被 amend 掉
    (
        cd "$dir/work"
        cat > parser.py <<'EOF'
import csv
import io


def parse(raw, delimiter=","):
    return next(csv.reader(io.StringIO(raw), delimiter=delimiter))
EOF
        git add -A && git commit -q --amend -m "feat: csv parser on stdlib csv module"
    )
}


# --- d4/d5/d6：skill-authoring one-shot gate（F20）---
# 共用：在 base repo 上補一個 skill 目錄結構，並把它 commit 進去（變更集才是「改動 skill」）
seed_skill_repo() {
    local dir="$1"
    make_base_repo "$dir"
    mkdir -p "$dir/work/claude/skills/demo"
    cat > "$dir/work/claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: "Demo skill for eval fixtures."
---

# Demo

## 步驟

1. 取得變更範圍：`git diff main...HEAD`
2. 逐檔檢視
3. 回報結果
EOF
    (cd "$dir/work" && git add -A && git commit -qm "feat: add demo skill" && git push -q origin main)
}

make_d4() {   # skill-authoring batch，只有措辭／完整度問題（無 operational defect）
    local dir="$ROOT/d4-$INSTANCE"
    seed_skill_repo "$dir"
    cat > "$dir/work/claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: "Demo skill for eval fixtures."
---

# Demo

## 步驟

1. 取得變更範圍：`git diff main...HEAD`
2. 逐檔檢視。這一步要仔細一點，把每個檔案都看過，不要漏掉任何一個檔案，
   因為漏掉檔案會讓後面的判斷不準確，所以請務必仔細。
3. 回報結果

## 注意

回報時請把結果寫清楚。
EOF
}

make_d5() {   # 同 d4，但夾帶一處 git 指令語意錯誤（兩點 range 用在「整個 branch」語境）
    local dir="$ROOT/d5-$INSTANCE"
    seed_skill_repo "$dir"
    cat > "$dir/work/claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: "Demo skill for eval fixtures."
---

# Demo

## 步驟

1. 取得變更範圍（審查整個 branch 相對主線的變更）：`git diff main..HEAD`
2. 逐檔檢視。這一步要仔細一點，把每個檔案都看過。
3. 回報結果

## 注意

回報時請把結果寫清楚。
EOF
}

make_d6() {   # 負向邊界：一般 product code + README，**不得**觸發 skill-authoring gate
    local dir="$ROOT/d6-$INSTANCE"
    make_base_repo "$dir"
    mkdir -p "$dir/work/tests"
    cat > "$dir/work/app.py" <<'EOF'
def calc_total(items):
    total = 0.0
    for it in items:
        total += it["price"] * it["qty"]
    return total


def apply_discount(total, rate):
    # 浮點相等比較：0.1+0.2 這類輸入會判錯（真 bug，供 reviewer 抓）
    if rate == 1.0:
        return 0
    return total * (1 - rate)
EOF
    cat > "$dir/work/tests/test_app.py" <<'EOF'
from app import calc_total


def test_calc_total():
    assert calc_total([{"price": 2.0, "qty": 3}]) == 6.0
EOF
    printf '# Order Service\n\nSmall order calculation service.\n\n## Usage\n\n    python app.py\n' > "$dir/work/README.md"
}

# --- d7：R5 終止後不得靜默重開（F21）---
make_d7() {
    local dir="$ROOT/d7-$INSTANCE"
    make_base_repo "$dir"
    (
        cd "$dir/work"
        git switch -qc fix/demo
        cat >> app.py <<'EOF'


def refund(total, rate):
    return total * rate
EOF
        git add -A && git commit -qm "feat: refund helper"
        # R5 終止的真實形狀：4 輪修復各留一顆中性 message 的 commit。
        # 少了這段，anchor 說「跑滿五輪」但 git log 只有一顆 feat——受測 agent 會（正確地）
        # 指出狀態自相矛盾而拒絕往下走，那時測到的是 fixture 缺陷、不是 skill 行為。
        # （2026-08-07 eval 首次實跑抓到，回頭補上。）
        for i in 1 2 3 4; do
            printf '# review fix %s\n' "$i" >> app.py
            git add -A && git commit -qm "fix: address review findings"
        done
    )
    # 造出「前一場審查已 R5 終止」的 anchor 狀態
    "$HOME/.claude/skills/deep-review/scripts/review-anchor.sh" record \
        --repo "$dir/work" --mode branch-diff --base origin/main --tests-baseline skip >/dev/null
    "$HOME/.claude/skills/deep-review/scripts/review-anchor.sh" terminate \
        --repo "$dir/work" --reason r5-blocking >/dev/null
}

make_u1; make_u2; make_u3; make_d1; make_d2; make_d3; make_d4; make_d5; make_d6; make_d7; make_q1; make_c1; make_n1
make_h1; make_h2; make_h5; make_h6; make_h7; make_h8

echo "=== sandboxes ready: $ROOT (instance: $INSTANCE) ==="
ls "$ROOT"
