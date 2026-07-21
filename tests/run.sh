#!/usr/bin/env bash
#
# tests/run.sh — dotfiles 腳本驗證（shellcheck + 語法 + 純邏輯行為測試）
#
# 用法：./tests/run.sh
# 涵蓋：
#   1. shellcheck / bash -n 全腳本 gate（含 claude/skills/*/scripts/、codex/skills/*/scripts/）
#   2. bash -n 語法 gate
#   3. scripts/lib/inventory.sh 解析
#   4. inventory_append 行為
#   5. render-etc-hosts.sh 區塊生成、IP 數值排序、--apply 冪等
#   6. render-ssh-config.sh 區塊替換、--check、marker 防呆
#   7. add-new-host.sh --dry-run 煙霧測試（不動任何檔案）
#   8. git-hygiene.sh（ready4quit skill script）verdict 判定
#   9. ship-state.sh（project skill script）偵測與 protection 判定（gh stub）
#  10. review-state.sh（deep-review skill script）scope-priority / round / branch-first / continuity 判定
#  11. review-context.sh（repo-review skill script）range 解析 / guidance / autofix gate（含分岔 base / detached HEAD / 閘序）
#  12. repo-review skill packaging（evals 不進 runtime context）
#  13. handoff-anchor.sh（handoff skill script）錨點驗證與生命週期判定
#  14. codex-runtime-hygiene.sh（deep-review skill script）孤兒偵測 / 誤殺防護 / exit 契約
#  15. ensure-rc-source.sh 幂等補 source shell/functions.sh 行
#  16. session-pull-check.sh（SessionStart hook）落後偵測與靜默契約
#  17. codex-exec-review.sh（deep-review skill script）exit 契約 / job 產物 / resume（codex stub）
#  18. ensure-codex-skills.sh 幂等連結 ~/.codex/skills → dotfiles
#  19. review-anchor.sh（deep-review skill script）錨點生命週期 / squash-cmd / codex-next
#  20. verify-tests.sh（deep-review skill script）框架偵測與 exit 契約（uv/bun stub）
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1   # 相對路徑的 source 解析與 git 操作以 repo 根為基準（從外部目錄執行時避免 SC1091 誤報）
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }

# assert_eq <名稱> <期望> <實際>
assert_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else
        bad "$1"
        echo "     expected: $(printf '%q' "$2")"
        echo "     actual:   $(printf '%q' "$3")"
    fi
}
# assert_rc <名稱> <期望exit> <實際exit>
assert_rc() {
    if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1（期望 exit=$2，實際 exit=$3）"; fi
}

echo "▶ 1. shellcheck gate"
if shellcheck -x -P "$ROOT/scripts" \
    "$ROOT"/scripts/*.sh "$ROOT/scripts/lib/inventory.sh" \
    "$ROOT"/claude/scripts/*.sh \
    "$ROOT"/claude/skills/*/scripts/*.sh \
    "$ROOT"/codex/skills/*/scripts/*.sh \
    "$ROOT/shell/functions.sh" \
    "$ROOT/setup-mac-env.sh" "$ROOT/setup-linux-env.sh" "$ROOT/write-mac-defaults.sh" \
    "$ROOT/tests/run.sh"; then
    ok "shellcheck 全部通過"
else
    bad "shellcheck 有 findings"
fi

echo "▶ 1b. 全形標點吞變數名 gate"
# bash 在部分 locale 下會把緊接在 $var 後的多位元組字元併進變數名：
#   echo "（exit=$rc）"  →  set -u 下噴 `rc）: unbound variable`
# 本 repo 大量使用繁中訊息，這個雷已在 2026-07-20 一天內踩中三次（run/resume 訊息、
# ensure-codex-skills 接管告知、range 驗證），且只在錯誤路徑觸發、正常測試照樣全綠。
# 一律要求寫成 ${var}。DO NOT relax this gate — 它守的是「只有出事時才會爆」的那條路徑。
# 寫法必須可攜：`grep -P` 只有 GNU grep 有，macOS 的 BSD grep 會直接報錯——若再把 stderr
# 導掉並 `|| true`，gate 會把「執行失敗」誤判成「乾淨」（本 gate 初版即如此假綠）。
# 改用 C locale + `[^[:print:][:space:]]`：C locale 下多位元組字元的每個 byte 都非 print，
# 且排除 space/tab（`$var<TAB>` 在 bash 中會正常斷詞，不是問題）。
fullwidth_hits="$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^[:print:][:space:]]' \
    "$ROOT"/scripts/*.sh "$ROOT/scripts/lib/inventory.sh" \
    "$ROOT"/claude/scripts/*.sh \
    "$ROOT"/claude/skills/*/scripts/*.sh \
    "$ROOT"/codex/skills/*/scripts/*.sh \
    "$ROOT/shell/functions.sh")"
fullwidth_rc=$?
# grep 的 exit：0=有命中、1=無命中、>1=執行錯誤（後者必須大聲失敗，不可當成乾淨）
fullwidth_hits="$(printf '%s\n' "$fullwidth_hits" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [ "$fullwidth_rc" -gt 1 ]; then
    bad "全形標點 gate 無法執行（grep rc=$fullwidth_rc）——不可視為通過"
elif [ -z "$fullwidth_hits" ]; then
    ok "無 \$var 緊接全形/多位元組字元的寫法"
else
    bad "有 \$var 緊接多位元組字元（set -u 下會 unbound variable，須改 \${var}）"
    printf '%s\n' "$fullwidth_hits" | sed 's/^/     /'
fi

echo "▶ 2. bash -n 語法 gate"
syntax_fail=0
for f in "$ROOT"/scripts/*.sh "$ROOT/scripts/lib/inventory.sh" \
         "$ROOT"/claude/scripts/*.sh \
         "$ROOT"/claude/skills/*/scripts/*.sh \
         "$ROOT"/codex/skills/*/scripts/*.sh \
         "$ROOT/shell/functions.sh" \
         "$ROOT/setup-mac-env.sh" "$ROOT/setup-linux-env.sh" "$ROOT/write-mac-defaults.sh"; do
    bash -n "$f" || { syntax_fail=1; echo "     syntax fail: $f"; }
done
if [ "$syntax_fail" -eq 0 ]; then ok "bash -n 全部通過"; else bad "bash -n 有語法錯誤"; fi

echo "▶ 3. inventory.sh 解析"
# 在子 shell 內 source，避免污染本 shell
inv() { (INVENTORY_FILE="$1" && export INVENTORY_FILE && shift && source "$ROOT/scripts/lib/inventory.sh" && "$@"); }

assert_eq "inventory_hosts 忽略註解/空行、保序" \
    "$(printf 'alpha\nbeta\ngamma')" \
    "$(inv "$FIX/inventory.conf" inventory_hosts)"

assert_eq "inventory_ip 查得到" "10.0.0.10" "$(inv "$FIX/inventory.conf" inventory_ip beta)"

inv "$FIX/inventory.conf" inventory_ip nonexistent >/dev/null 2>&1
assert_rc "inventory_ip 查不到 → exit 1" 1 $?

inv "$FIX/inventory.conf" inventory_has alpha
assert_rc "inventory_has 存在 → exit 0" 0 $?

inv "$FIX/inventory.conf" inventory_has zz
assert_rc "inventory_has 不存在 → exit 1" 1 $?

assert_eq "inventory_entries tab 分隔" \
    "$(printf 'alpha\t10.0.0.2\nbeta\t10.0.0.10\ngamma\t172.16.1.1')" \
    "$(inv "$FIX/inventory.conf" inventory_entries)"

INVENTORY_FILE="/nonexistent/path.conf" bash -c \
    'source "'"$ROOT"'/scripts/lib/inventory.sh"; inventory_hosts' >/dev/null 2>&1
assert_rc "inventory 檔不存在 → exit 1" 1 $?

echo "▶ 4. inventory_append"
cp "$FIX/inventory.conf" "$TMP/inv-append.conf"
inv "$TMP/inv-append.conf" inventory_append delta 10.0.0.99
assert_rc "append 新 alias → exit 0" 0 $?
assert_eq "append 後可查回 IP" "10.0.0.99" "$(inv "$TMP/inv-append.conf" inventory_ip delta)"

inv "$TMP/inv-append.conf" inventory_append alpha 1.1.1.1 2>/dev/null
assert_rc "append 重複 alias 被拒 → exit 1" 1 $?

inv "$TMP/inv-append.conf" inventory_append onlyalias "" 2>/dev/null
assert_rc "append 缺 IP 被拒 → exit 1" 1 $?

echo "▶ 5. render-etc-hosts.sh"
expected_block="$(
    echo "# pilot-infra-start"
    printf '%-14s %s\n' 10.0.0.2 alpha 10.0.0.10 beta 172.16.1.1 gamma
    echo "# pilot-infra-end"
)"
actual_block="$(INVENTORY_FILE="$FIX/inventory.conf" "$ROOT/scripts/render-etc-hosts.sh" --stdout)"
assert_eq "--stdout 區塊內容 + IP 數值排序（10.0.0.2 < 10.0.0.10）" "$expected_block" "$actual_block"

cp "$FIX/etc-hosts-before" "$TMP/hosts"
INVENTORY_FILE="$FIX/inventory.conf" "$ROOT/scripts/render-etc-hosts.sh" --apply "$TMP/hosts" >/dev/null
if grep -q "stale-entry" "$TMP/hosts"; then bad "--apply 未移除舊區塊"; else ok "--apply 移除舊區塊"; fi
if grep -q "^127.0.0.1 localhost$" "$TMP/hosts"; then ok "--apply 保留區塊外內容"; else bad "--apply 弄丟區塊外內容"; fi

cp "$TMP/hosts" "$TMP/hosts.once"
INVENTORY_FILE="$FIX/inventory.conf" "$ROOT/scripts/render-etc-hosts.sh" --apply "$TMP/hosts" >/dev/null
if diff -q "$TMP/hosts" "$TMP/hosts.once" >/dev/null; then ok "--apply 冪等（跑兩次內容不變）"; else bad "--apply 不冪等"; fi

INVENTORY_FILE="$FIX/inventory.conf" "$ROOT/scripts/render-etc-hosts.sh" --apply "$TMP/no-such-file" >/dev/null 2>&1
assert_rc "--apply 目標不存在 → exit 1" 1 $?

echo "▶ 6. render-ssh-config.sh"
cp "$FIX/ssh-config-before" "$TMP/sshconf"
out="$(INVENTORY_FILE="$FIX/inventory.conf" SSH_CONFIG_FILE="$TMP/sshconf" "$ROOT/scripts/render-ssh-config.sh" --stdout)"
if echo "$out" | grep -q "HostName 10.0.0.10"; then ok "--stdout 含渲染的 host"; else bad "--stdout 缺渲染的 host"; fi
if echo "$out" | grep -q "stale-host"; then bad "--stdout 未替換舊區塊"; else ok "--stdout 替換舊區塊"; fi
if echo "$out" | grep -q "^Include config.local$"; then ok "--stdout 保留區塊前內容"; else bad "--stdout 弄丟區塊前內容"; fi
if echo "$out" | grep -q "IdentityFile ~/.ssh/id_github"; then ok "--stdout 保留區塊後內容"; else bad "--stdout 弄丟區塊後內容"; fi

INVENTORY_FILE="$FIX/inventory.conf" SSH_CONFIG_FILE="$TMP/sshconf" "$ROOT/scripts/render-ssh-config.sh" --check >/dev/null 2>&1
assert_rc "--check 不同步 → exit 1" 1 $?

INVENTORY_FILE="$FIX/inventory.conf" SSH_CONFIG_FILE="$TMP/sshconf" "$ROOT/scripts/render-ssh-config.sh" >/dev/null
INVENTORY_FILE="$FIX/inventory.conf" SSH_CONFIG_FILE="$TMP/sshconf" "$ROOT/scripts/render-ssh-config.sh" --check >/dev/null 2>&1
assert_rc "write 後 --check 同步 → exit 0" 0 $?

cp "$TMP/sshconf" "$TMP/sshconf.once"
INVENTORY_FILE="$FIX/inventory.conf" SSH_CONFIG_FILE="$TMP/sshconf" "$ROOT/scripts/render-ssh-config.sh" >/dev/null
if diff -q "$TMP/sshconf" "$TMP/sshconf.once" >/dev/null; then ok "write 冪等"; else bad "write 不冪等"; fi

# marker 防呆：兩組 BEGIN → 必須拒絕
{ cat "$FIX/ssh-config-before"; echo "# BEGIN inventory hosts (dup)"; } > "$TMP/sshconf-dup"
INVENTORY_FILE="$FIX/inventory.conf" SSH_CONFIG_FILE="$TMP/sshconf-dup" "$ROOT/scripts/render-ssh-config.sh" --stdout >/dev/null 2>&1
assert_rc "marker 數量異常 → exit 1" 1 $?

echo "▶ 7. add-new-host.sh --dry-run 煙霧測試"
before_status="$(git -C "$ROOT" status --porcelain -- scripts/inventory.conf ssh/config)"
"$ROOT/scripts/add-new-host.sh" --dry-run zzeval-smoke 10.99.99.99 >/dev/null 2>&1
assert_rc "dry-run 新 alias → exit 0" 0 $?
after_status="$(git -C "$ROOT" status --porcelain -- scripts/inventory.conf ssh/config)"
assert_eq "dry-run 不動 inventory.conf / ssh/config" "$before_status" "$after_status"

"$ROOT/scripts/add-new-host.sh" --dry-run eagle03 1.2.3.4 >/dev/null 2>&1
assert_rc "dry-run 重複 alias 被拒 → exit 1" 1 $?

echo "▶ 8. git-hygiene.sh verdict 判定"
GH_SCRIPT="$ROOT/claude/skills/ready4quit/scripts/git-hygiene.sh"
GITC=(git -c user.name=test -c user.email=test@test -c commit.gpgsign=false)

# fixture：bare origin + clone（有 upstream 的正常 repo）
git init --bare -q "$TMP/gh-origin.git"
git init -q -b main "$TMP/gh-work"
(cd "$TMP/gh-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/gh-origin.git" && git push -qu origin main)

out="$("$GH_SCRIPT" "$TMP/gh-work")"
assert_rc "clean repo → exit 0" 0 $?
if echo "$out" | grep -q "verdict: CLEAN"; then ok "clean repo → CLEAN"; else bad "clean repo 未判 CLEAN"; fi

echo dirty > "$TMP/gh-work/untracked.txt"
out="$("$GH_SCRIPT" "$TMP/gh-work")"
assert_rc "untracked 殘留 → exit 1" 1 $?
if echo "$out" | grep -q "verdict: RESIDUE"; then ok "untracked → RESIDUE"; else bad "untracked 未判 RESIDUE"; fi
rm "$TMP/gh-work/untracked.txt"

(cd "$TMP/gh-work" && echo v2 > f.txt && "${GITC[@]}" commit -qam "unpushed change")
out="$("$GH_SCRIPT" "$TMP/gh-work")"
assert_rc "unpushed commit → exit 1" 1 $?
if echo "$out" | grep -q "unpushed: 1 commits"; then ok "unpushed commit 被偵測"; else bad "unpushed commit 未偵測"; fi

# local-only repo（無 remote）→ push 狀態無從判斷 → UNKNOWN，不可當乾淨
git init -q -b main "$TMP/gh-local"
(cd "$TMP/gh-local" && echo x > a.txt && "${GITC[@]}" add a.txt && "${GITC[@]}" commit -qm init)
out="$("$GH_SCRIPT" "$TMP/gh-local")"
assert_rc "local-only repo → exit 1" 1 $?
if echo "$out" | grep -q "verdict: UNKNOWN"; then ok "local-only → UNKNOWN（不判 CLEAN）"; else bad "local-only 未判 UNKNOWN"; fi

out="$("$GH_SCRIPT" "$TMP/not-a-repo")"
assert_rc "非 git repo → exit 1" 1 $?
if echo "$out" | grep -q "verdict: UNKNOWN"; then ok "非 repo → UNKNOWN"; else bad "非 repo 未判 UNKNOWN"; fi

"$GH_SCRIPT" >/dev/null 2>&1
assert_rc "無引數 → exit 2" 2 $?

echo "▶ 9. ship-state.sh 偵測與 protection 判定"
SS_SCRIPT="$ROOT/claude/skills/project/scripts/ship-state.sh"

# gh stub 三態：PROTECTED / OPEN(404 Branch not protected) / Not Found(身分分離)
make_gh_stub() {  # <path> <protection行為: protected|open|notfound>
    local mode="$2"
    cat > "$1" <<STUB
#!/usr/bin/env bash
case "\$*" in
    *nameWithOwner*) echo "acme/widget" ;;
    *viewerPermission*) echo "READ" ;;
    *"/protection"*)
        case "$mode" in
            protected) echo '{"required_status_checks":{}}'; exit 0 ;;
            open)      echo "gh: Branch not protected (HTTP 404)"; exit 1 ;;
            notfound)  echo "gh: Not Found (HTTP 404)"; exit 1 ;;
        esac ;;
    *"rules/branches"*) echo '[]' ;;
esac
STUB
    chmod +x "$1"
}
make_gh_stub "$TMP/gh-protected" protected
make_gh_stub "$TMP/gh-open" open
make_gh_stub "$TMP/gh-notfound" notfound

# fixture：bare origin + clone，feature branch 上 1 commit、tree clean
git init --bare -q "$TMP/ss-origin.git"
git init -q -b main "$TMP/ss-work"
(cd "$TMP/ss-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/ss-origin.git" && git push -qu origin main \
    && git switch -qc feat/x && echo v2 > f.txt && "${GITC[@]}" commit -qam "feat: x")

out="$(SHIP_STATE_GH="$TMP/gh-protected" "$SS_SCRIPT" "$TMP/ss-work")"
assert_rc "feature branch 偵測 → exit 0" 0 $?
if echo "$out" | grep -q "protection: PROTECTED"; then ok "stub protected → PROTECTED"; else bad "stub protected 未判 PROTECTED"; fi
if echo "$out" | grep -q "ship-path: PR"; then ok "PROTECTED → PR 路徑"; else bad "PROTECTED 未走 PR 路徑"; fi
if echo "$out" | grep -q "files-vs-default: 1 檔"; then ok "三點 diff 列出 branch 帶來的檔"; else bad "三點 diff 未列檔"; fi
if echo "$out" | grep -q "branch-first: 已在 feature branch"; then ok "feature branch → 免 branch-first"; else bad "feature branch 誤判 branch-first"; fi

out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ss-work")"
if echo "$out" | grep -q "protection: OPEN" && echo "$out" | grep -q "ship-path: DIRECT-PUSH"; then
    ok "stub open → OPEN + DIRECT-PUSH（仍推 feature branch）"
else bad "stub open 判定錯誤"; fi

out="$(SHIP_STATE_GH="$TMP/gh-notfound" "$SS_SCRIPT" "$TMP/ss-work")"
if echo "$out" | grep -q "protection: UNKNOWN" && echo "$out" | grep -q "treat as PROTECTED" \
    && echo "$out" | grep -q "viewerPermission=READ" && echo "$out" | grep -q "ship-path: PR"; then
    ok "stub notfound → UNKNOWN=protected + 身分分離提示"
else bad "stub notfound 判定錯誤"; fi

# 站在 main + 未 commit 變更 → branch-first REQUIRED
(cd "$TMP/ss-work" && git switch -q main && echo dirty > new.txt)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ss-work")"
if echo "$out" | grep -q "branch-first: REQUIRED"; then ok "main + 髒 tree → branch-first REQUIRED"; else bad "未要求 branch-first"; fi

# 誤 commit 在本地 main → misplaced WARNING（情況 B）
(cd "$TMP/ss-work" && "${GITC[@]}" add new.txt && "${GITC[@]}" commit -qm "oops on main")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ss-work")"
if echo "$out" | grep -q "misplaced: WARNING"; then ok "誤 commit 在 main → misplaced WARNING"; else bad "misplaced 未偵測"; fi

# 全乾淨 → changes NONE + docs-only 提醒；protection/ship-path/branch-first 仍須輸出
# （docs-only mode 隨後會產生 docs commit 走 Step 4/5，Step 1 取 verdict 不可缺）
git clone -q "$TMP/ss-origin.git" "$TMP/ss-clean"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ss-clean")"
assert_rc "乾淨 repo → exit 0" 0 $?
if echo "$out" | grep -q "changes: NONE" && echo "$out" | grep -q "docs-only"; then
    ok "乾淨 repo → changes NONE + docs-only 提醒"
else bad "乾淨 repo 輸出缺 docs-only 提醒"; fi
if echo "$out" | grep -q "protection: OPEN" && echo "$out" | grep -q "ship-path:" \
    && echo "$out" | grep -q "branch-first: REQUIRED"; then
    ok "乾淨 repo 仍印 protection/ship-path/branch-first（docs-only mode 需用）"
else bad "乾淨 repo 缺 protection/ship-path/branch-first（docs-only mode 取不到 verdict）"; fi

# local-only（無 remote）→ STOP
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/gh-local")"
if echo "$out" | grep -q "remotes: NONE"; then ok "無 remote → STOP 告知"; else bad "無 remote 未 STOP"; fi

"$SS_SCRIPT" "$TMP/not-a-repo" >/dev/null 2>&1
assert_rc "非 git repo → exit 1" 1 $?
"$SS_SCRIPT" >/dev/null 2>&1
assert_rc "無引數 → exit 2" 2 $?

echo "▶ 10. review-state.sh scope-priority / round 判定"
RS_SCRIPT="$ROOT/claude/skills/deep-review/scripts/review-state.sh"

# fixture：bare origin + clone，main 已 push
git init --bare -q "$TMP/rs-origin.git"
git init -q -b main "$TMP/rs-work"
(cd "$TMP/rs-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/rs-origin.git" && git push -qu origin main)

# dirty tree（modified + untracked）→ priority 2
(cd "$TMP/rs-work" && echo v2 > f.txt && echo new > new.txt)
out="$("$RS_SCRIPT" "$TMP/rs-work")"
assert_rc "dirty tree 偵測 → exit 0" 0 $?
if echo "$out" | grep -q "scope-priority: 2"; then ok "dirty tree → priority 2"; else bad "dirty tree 未判 priority 2"; fi
if echo "$out" | grep -qA2 "untracked" && echo "$out" | grep -q "new.txt"; then ok "untracked 另列（diff HEAD 不含）"; else bad "untracked 未另列"; fi

# feature branch 領先、tree clean → priority 3 + merge-base
(cd "$TMP/rs-work" && git checkout -q -- f.txt && rm new.txt \
    && git switch -qc feat/y && echo v3 > f.txt && "${GITC[@]}" commit -qam "feat: y")
mb_expect="$(git -C "$TMP/rs-work" rev-parse origin/main)"
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "scope-priority: 3"; then ok "clean+領先 → priority 3"; else bad "未判 priority 3"; fi
if echo "$out" | grep -q "base: origin/main"; then ok "base 偵測 origin/main"; else bad "base 偵測錯誤"; fi
if echo "$out" | grep -q "hash-merge-base: $mb_expect"; then ok "merge-base = 分叉點（squash base 候選）"; else bad "merge-base 錯誤"; fi
if echo "$out" | grep -q "round: 1"; then ok "無 fix commit → Round 1"; else bad "round 誤判"; fi

# 加 fix commit → Round 2
(cd "$TMP/rs-work" && echo v4 > f.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes")
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "round: 2"; then ok "1 個 fix commit → Round 2"; else bad "fix commit 輪次誤判"; fi

# clean 且與 base 同步 → priority 4 MUST ASK
git clone -q "$TMP/rs-origin.git" "$TMP/rs-clean"
out="$("$RS_SCRIPT" "$TMP/rs-clean")"
if echo "$out" | grep -q "scope-priority: 4" && echo "$out" | grep -q "MUST ASK USER"; then
    ok "clean 同步 → priority 4 + MUST ASK USER"
else bad "priority 4 gate 輸出缺失"; fi

# local-only repo（無 remote，有本地 main）→ base 退用本地 branch
out="$("$RS_SCRIPT" "$TMP/gh-local")"
if echo "$out" | grep -q "base: main"; then ok "無 remote → base 退用本地 main"; else bad "本地 base fallback 錯誤"; fi

"$RS_SCRIPT" "$TMP/not-a-repo" >/dev/null 2>&1
assert_rc "非 git repo → exit 1" 1 $?
"$RS_SCRIPT" >/dev/null 2>&1
assert_rc "無引數 → exit 2" 2 $?

# --- branch-first / continuity / empty-tree（增量輸出行）---

# feature branch（rs-work 現在 feat/y、clean）→ 資訊行、無 continuity
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "branch-first: 已在 feature branch（feat/y）"; then ok "feature branch → branch-first 資訊行"; else bad "feature branch branch-first 誤判"; fi
if echo "$out" | grep -q "continuity: WARNING"; then bad "clean tree 不應有 continuity 警告"; else ok "clean tree 無 continuity 警告"; fi

# dirty + ahead>0 → continuity WARNING
(cd "$TMP/rs-work" && echo v5 > f.txt)
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "continuity: WARNING"; then ok "dirty+ahead → continuity WARNING"; else bad "continuity 警告缺失"; fi
(cd "$TMP/rs-work" && git checkout -q -- f.txt)

# HEAD 在 main（rs-clean、priority 4）→ REQUIRED + branch-cmd + empty-tree 常數
out="$("$RS_SCRIPT" "$TMP/rs-clean")"
if echo "$out" | grep -q "branch-first: REQUIRED"; then ok "HEAD 在 main → branch-first REQUIRED"; else bad "main branch-first 誤判"; fi
if echo "$out" | grep -qF "branch-cmd: git -C $TMP/rs-clean switch -c <type>/<slug>"; then ok "branch-cmd 印出待填指令"; else bad "branch-cmd 缺失"; fi
if echo "$out" | grep -q "empty-tree: 4b825dc642cb6eb9a060e54bf8d69288fbee4904"; then ok "priority 4 印 empty-tree 常數"; else bad "empty-tree 常數缺失"; fi

# dirty 但 ahead=0 → 無 continuity（兩條件須同時成立）
(cd "$TMP/rs-clean" && echo x > d.txt)
out="$("$RS_SCRIPT" "$TMP/rs-clean")"
if echo "$out" | grep -q "continuity: WARNING"; then bad "ahead=0 不應有 continuity 警告"; else ok "dirty 但 ahead=0 → 無 continuity 警告"; fi
(cd "$TMP/rs-clean" && rm d.txt)

# detached HEAD → REQUIRED
git clone -q "$TMP/rs-origin.git" "$TMP/rs-detach"
(cd "$TMP/rs-detach" && git checkout -q --detach)
out="$("$RS_SCRIPT" "$TMP/rs-detach")"
if echo "$out" | grep -q "branch-first: REQUIRED（HEAD 在 DETACHED"; then ok "detached HEAD → branch-first REQUIRED"; else bad "detached branch-first 誤判"; fi

echo "▶ 11. repo-review review-context.sh range / guidance / autofix gate"
RRC_SCRIPT="$ROOT/codex/skills/repo-review/scripts/review-context.sh"
RRC_EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

git init -q -b main "$TMP/rrc-work"
(cd "$TMP/rrc-work" \
    && mkdir -p src \
    && printf 'root guidance\n' > CLAUDE.md \
    && printf 'subtree guidance\n' > src/AGENTS.md \
    && printf 'v1\n' > src/app.txt \
    && "${GITC[@]}" add CLAUDE.md src/AGENTS.md src/app.txt \
    && "${GITC[@]}" commit -qm init)
rrc_base="$(git -C "$TMP/rrc-work" rev-parse HEAD)"
(cd "$TMP/rrc-work" \
    && printf 'v2\n' > src/app.txt \
    && "${GITC[@]}" commit -qam "feat: update app")
rrc_head="$(git -C "$TMP/rrc-work" rev-parse HEAD)"

out="$("$RRC_SCRIPT" "$TMP/rrc-work" "HEAD~1..HEAD")"
assert_rc "review-context 基本 range → exit 0" 0 $?
if echo "$out" | grep -q "^resolved-base: $rrc_base$" \
    && echo "$out" | grep -q "^resolved-head: $rrc_head$" \
    && echo "$out" | grep -q "^review-range: $rrc_base..$rrc_head$"; then
    ok "range endpoint 解析成固定 object id"
else bad "range endpoint 解析輸出錯誤"; fi
if echo "$out" | grep -q "  CLAUDE.md" && echo "$out" | grep -q "  src/AGENTS.md"; then
    ok "guidance 偵測 root + subtree"
else bad "guidance 偵測缺 root 或 subtree"; fi
if echo "$out" | grep -q "src/app.txt" && echo "$out" | grep -q "^autofix-safe: n/a$"; then
    ok "changed files 與非 autofix 狀態輸出"
else bad "changed files 或 autofix n/a 輸出錯誤"; fi

out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$rrc_base..HEAD" --autofix)"
assert_rc "clean current HEAD autofix gate → exit 0" 0 $?
if echo "$out" | grep -q "^autofix-safe: yes$" && echo "$out" | grep -q "^autofix-reason: clean-current-head$"; then
    ok "clean current HEAD → autofix-safe yes"
else bad "clean current HEAD 未判 autofix-safe yes"; fi

printf 'dirty\n' > "$TMP/rrc-work/untracked.txt"
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$rrc_base..HEAD" --autofix)"
if echo "$out" | grep -q "^autofix-safe: no$" && echo "$out" | grep -q "^autofix-reason: dirty-worktree$"; then
    ok "dirty worktree → autofix-safe no"
else bad "dirty worktree gate 失效"; fi
rm "$TMP/rrc-work/untracked.txt"

rrc_old_head="$rrc_head"
(cd "$TMP/rrc-work" \
    && printf 'v3\n' > src/app.txt \
    && "${GITC[@]}" commit -qam "feat: advance head")
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$rrc_base..$rrc_old_head" --autofix)"
if echo "$out" | grep -q "^autofix-safe: no$" && echo "$out" | grep -q "^autofix-reason: requested-head-not-current$"; then
    ok "requested head 非 current HEAD → autofix-safe no"
else bad "requested-head-not-current gate 失效"; fi

out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$RRC_EMPTY_TREE..HEAD")"
if echo "$out" | grep -q "^resolved-base-type: tree$" && echo "$out" | grep -q "^baseline-range: yes$" \
    && echo "$out" | grep -q "^base-is-ancestor: yes$"; then
    ok "empty-tree baseline range 支援（base-is-ancestor yes）"
else bad "empty-tree baseline range 輸出錯誤"; fi

# 新訊號基準：branch / detached-head / base-is-ancestor / merge-base / guidance-source
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "HEAD~1..HEAD")"
if echo "$out" | grep -q "^branch: main$" && echo "$out" | grep -q "^detached-head: no$" \
    && echo "$out" | grep -q "^base-is-ancestor: yes$" && echo "$out" | grep -q "^merge-base: n/a$"; then
    ok "祖先 base + attached HEAD → 新訊號基準輸出"
else bad "新訊號基準輸出錯誤"; fi
if echo "$out" | grep -q "^guidance-source: worktree$"; then
    ok "guidance-source 標示 worktree"
else bad "guidance-source 標示缺失"; fi

# 分岔 base（非祖先）→ base-is-ancestor no + merge-base 分叉點 + autofix 擋
(cd "$TMP/rrc-work" && git switch -qc rrc-feat "$rrc_base" \
    && printf 'branch\n' > src/feat.txt \
    && "${GITC[@]}" add src/feat.txt && "${GITC[@]}" commit -qm "feat: diverge")
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "main..HEAD" --autofix)"
if echo "$out" | grep -q "^base-is-ancestor: no$" && echo "$out" | grep -q "^merge-base: $rrc_base$"; then
    ok "分岔 base → base-is-ancestor no + merge-base 分叉點"
else bad "分岔 base 偵測錯誤"; fi
if echo "$out" | grep -q "^autofix-safe: no$" && echo "$out" | grep -q "^autofix-reason: base-not-ancestor$"; then
    ok "分岔 base → autofix 擋（base-not-ancestor）"
else bad "base-not-ancestor gate 失效"; fi

# merge-base 重錨定後 → autofix 通過
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$rrc_base..HEAD" --autofix)"
if echo "$out" | grep -q "^autofix-safe: yes$" && echo "$out" | grep -q "^base-is-ancestor: yes$"; then
    ok "merge-base 重錨定 → autofix 通過"
else bad "重錨定後 autofix 仍被擋"; fi

# detached HEAD → autofix 擋、純 review 不擋
(cd "$TMP/rrc-work" && git checkout -q --detach HEAD)
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$rrc_base..HEAD" --autofix)"
if echo "$out" | grep -q "^branch: (detached)$" && echo "$out" | grep -q "^detached-head: yes$" \
    && echo "$out" | grep -q "^autofix-safe: no$" && echo "$out" | grep -q "^autofix-reason: detached-head$"; then
    ok "detached HEAD → autofix 擋（detached-head）"
else bad "detached-head gate 失效"; fi
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$rrc_base..HEAD")"
if echo "$out" | grep -q "^detached-head: yes$" && echo "$out" | grep -q "^autofix-safe: n/a$"; then
    ok "detached HEAD 純 review → 不擋"
else bad "detached 純 review 被誤擋"; fi

# 閘序：dirty-worktree 優先於 detached-head
printf 'dirty\n' > "$TMP/rrc-work/untracked.txt"
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$rrc_base..HEAD" --autofix)"
if echo "$out" | grep -q "^autofix-reason: dirty-worktree$"; then
    ok "閘序：dirty-worktree 優先於 detached-head"
else bad "閘序錯誤（dirty 未優先於 detached）"; fi
rm "$TMP/rrc-work/untracked.txt"

# 無共同祖先 → merge-base (none)
(cd "$TMP/rrc-work" && git checkout -q --orphan rrc-orphan && git rm -rq --cached . \
    && rm -rf src CLAUDE.md && printf 'x\n' > z.txt \
    && "${GITC[@]}" add z.txt && "${GITC[@]}" commit -qm "orphan root")
out="$("$RRC_SCRIPT" "$TMP/rrc-work" "main..HEAD")"
if echo "$out" | grep -q "^base-is-ancestor: no$" && echo "$out" | grep -q "^merge-base: (none)$"; then
    ok "無共同祖先 → merge-base (none)"
else bad "unrelated histories 偵測錯誤"; fi

"$RRC_SCRIPT" "$TMP/not-a-repo" "$rrc_base..$rrc_head" >/dev/null 2>&1
assert_rc "review-context 非 git repo → exit 1" 1 $?
"$RRC_SCRIPT" "$TMP/rrc-work" "HEAD...HEAD" >/dev/null 2>&1
assert_rc "three-dot range 被拒 → exit 1" 1 $?
"$RRC_SCRIPT" >/dev/null 2>&1
assert_rc "review-context 無引數 → exit 2" 2 $?

echo "▶ 12. repo-review skill packaging"
if [ -f "$ROOT/codex/skills/repo-review/evals.md" ]; then
    ok "repo-review evals.md 存在（開發 oracle）"
else bad "repo-review evals.md 不存在"; fi
if ! grep -qi 'evals\.md' "$ROOT/codex/skills/repo-review/SKILL.md"; then
    ok "SKILL.md 不連結 evals.md（避免 runtime 載入）"
else bad "SKILL.md 不應連結 evals.md"; fi
if grep -q "Run your repo-review skill on /path/repo for abc123..def456" "$ROOT/codex/skills/repo-review/evals.md"; then
    ok "evals 覆蓋 Claude Code autocodex 一行協議"
else bad "evals 缺 Claude Code autocodex 相容性 case"; fi

echo "▶ 13. handoff-anchor.sh 錨點驗證與生命週期判定"
HA_SCRIPT="$ROOT/claude/skills/handoff/scripts/handoff-anchor.sh"

# fixture：單 repo，1 commit
git init -q -b main "$TMP/ha-work"
(cd "$TMP/ha-work" && echo v1 > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init)

# anchors：格式與 dirty 計數
echo dirty > "$TMP/ha-work/untracked.txt"
out="$("$HA_SCRIPT" anchors "$TMP/ha-work")"
assert_rc "anchors 正常 repo → exit 0" 0 $?
if echo "$out" | grep -q "^created: " && echo "$out" | grep -q "^anchor: $TMP/ha-work main .* dirty=1$"; then
    ok "anchors 輸出 created + anchor（dirty=1）"
else bad "anchors 輸出格式錯誤"; fi
rm "$TMP/ha-work/untracked.txt"

"$HA_SCRIPT" anchors "$TMP/not-a-repo" >/dev/null 2>&1
assert_rc "anchors 非 git repo → exit 1" 1 $?

# anchors：路徑含空白 → 寫入端擋下（anchor 行以空白分欄，這種錨點 verify 必誤判）
git init -q -b main "$TMP/ha spaced"
(cd "$TMP/ha spaced" && echo v1 > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init)
out="$("$HA_SCRIPT" anchors "$TMP/ha spaced" 2>&1)"
assert_rc "anchors 含空白路徑 → exit 1" 1 $?
if ! echo "$out" | grep -q "^anchor: " && echo "$out" | grep -q "含空白"; then
    ok "含空白路徑 → 報錯且不輸出 anchor 行"
else bad "含空白路徑未被寫入端擋下"; fi

# verify：FRESH
mkdir -p "$TMP/ha-handoffs"
{ echo "---"; "$HA_SCRIPT" anchors "$TMP/ha-work"; echo "---"; echo "# Handoff: test"; } > "$TMP/ha-handoffs/t.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md")"
assert_rc "verify 未動的 repo → exit 0" 0 $?
if echo "$out" | grep -q "verdict: FRESH"; then ok "未動的 repo → FRESH"; else bad "未判 FRESH"; fi

# verify：DRIFTED（記錄後 repo 前進，列出中間 commit）
(cd "$TMP/ha-work" && echo v2 > f.txt && "${GITC[@]}" commit -qam "advance after handoff")
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md")"
assert_rc "verify 前進後的 repo → exit 1" 1 $?
if echo "$out" | grep -q "status: DRIFTED" && echo "$out" | grep -q "advance after handoff"; then
    ok "repo 前進 → DRIFTED + 列中間 commit"
else bad "DRIFTED 判定或 commit 清單缺失"; fi
if echo "$out" | grep -q "verdict: STALE-RISK"; then ok "DRIFTED → verdict STALE-RISK"; else bad "verdict 未標 STALE-RISK"; fi

# verify：DIVERGED（記錄的 HEAD 被 rebase 掉、不在現行歷史）
{ echo "---"; "$HA_SCRIPT" anchors "$TMP/ha-work"; echo "---"; } > "$TMP/ha-handoffs/t.md"
(cd "$TMP/ha-work" && echo v3 > f.txt && "${GITC[@]}" commit -qa --amend -m "rewritten")
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md")"
assert_rc "verify 歷史改寫 → exit 1" 1 $?
if echo "$out" | grep -q "status: DIVERGED"; then ok "歷史改寫 → DIVERGED"; else bad "未判 DIVERGED"; fi

# verify：MISSING（repo 路徑不存在）
printf -- '---\ncreated: %s\nanchor: %s/gone main abc1234 dirty=0\n---\n' "$(date +%Y-%m-%d)" "$TMP" > "$TMP/ha-handoffs/t.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md")"
assert_rc "verify repo 消失 → exit 1" 1 $?
if echo "$out" | grep -q "status: MISSING"; then ok "repo 消失 → MISSING"; else bad "未判 MISSING"; fi

# verify：EXPIRED（created 超過 EXPIRE_DAYS）
{ echo "---"; echo "created: 2026-01-01"; "$HA_SCRIPT" anchors "$TMP/ha-work" | grep '^anchor: '; echo "---"; } > "$TMP/ha-handoffs/t.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md")"
assert_rc "verify 過期交接檔 → exit 1" 1 $?
if echo "$out" | grep -q "EXPIRED"; then ok "created 超過 7 天 → EXPIRED"; else bad "未標 EXPIRED"; fi

# verify：無錨點 → UNVERIFIABLE
printf -- '---\ncreated: %s\n---\nno anchors here\n' "$(date +%Y-%m-%d)" > "$TMP/ha-handoffs/t.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md")"
assert_rc "verify 無錨點 → exit 1" 1 $?
if echo "$out" | grep -q "verdict: UNVERIFIABLE"; then ok "無錨點 → UNVERIFIABLE"; else bad "未判 UNVERIFIABLE"; fi

"$HA_SCRIPT" verify "$TMP/ha-handoffs/no-such.md" >/dev/null 2>&1
assert_rc "verify 檔案不存在 → exit 1" 1 $?

# verify：錨點行欄位不足（手寫殘缺）→ BAD-ANCHOR 優雅判定，不裸崩潰
printf -- '---\ncreated: %s\nanchor: %s/ha-work\n---\n' "$(date +%Y-%m-%d)" "$TMP" > "$TMP/ha-handoffs/t.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md" 2>&1)"
assert_rc "verify 欄位不足錨點 → exit 1" 1 $?
if echo "$out" | grep -q "status: BAD-ANCHOR" && ! echo "$out" | grep -q "unbound variable"; then
    ok "欄位不足 → BAD-ANCHOR（無 bash 錯誤）"
else bad "欄位不足錨點未優雅判定"; fi

# verify：錨點路徑含 glob 字元 → 不做 pathname expansion（欄位原樣進判定）
printf -- '---\ncreated: %s\nanchor: * main abc1234 dirty=0\n---\n' "$(date +%Y-%m-%d)" > "$TMP/ha-handoffs/t.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-handoffs/t.md")"
assert_rc "verify glob 字元錨點 → exit 1" 1 $?
if echo "$out" | grep -q "recorded: branch=main head=abc1234" && echo "$out" | grep -q "status: MISSING"; then
    ok "glob 字元不展開 → 判 MISSING"
else bad "glob 字元錨點被 pathname expansion 展開"; fi

# list：EXPIRED 標記 + archive 自動清理
rm "$TMP/ha-handoffs/t.md"
printf -- '---\ncreated: %s\n---\n' "$(date +%Y-%m-%d)" > "$TMP/ha-handoffs/fresh.md"
printf -- '---\ncreated: 2026-01-01\n---\n' > "$TMP/ha-handoffs/old.md"
mkdir -p "$TMP/ha-handoffs/archive"
printf 'consumed\n' > "$TMP/ha-handoffs/archive/20260101-dead.md"
touch -t 202601011200 "$TMP/ha-handoffs/archive/20260101-dead.md"
printf 'consumed\n' > "$TMP/ha-handoffs/archive/recent.md"
out="$("$HA_SCRIPT" list "$TMP/ha-handoffs")"
assert_rc "list → exit 0" 0 $?
if echo "$out" | grep -q "active: fresh.md — 0d — OK"; then ok "list 新檔標 OK"; else bad "list 新檔標記錯誤"; fi
if echo "$out" | grep "active: old.md" | grep -q "EXPIRED"; then ok "list 過期檔標 EXPIRED"; else bad "list 未標 EXPIRED"; fi
if [ ! -f "$TMP/ha-handoffs/archive/20260101-dead.md" ] && [ -f "$TMP/ha-handoffs/archive/recent.md" ]; then
    ok "list 清超過保留期的 archive、留新的"
else bad "archive 清理行為錯誤"; fi
if echo "$out" | grep -q "archive: 已清 1 份"; then ok "list 回報清理數量"; else bad "list 未回報清理"; fi

out="$("$HA_SCRIPT" list "$TMP/no-such-dir")"
assert_rc "list 目錄不存在 → exit 0（回報 NONE）" 0 $?
if echo "$out" | grep -q "handoffs: NONE"; then ok "list 無目錄 → NONE"; else bad "list 無目錄輸出錯誤"; fi

"$HA_SCRIPT" >/dev/null 2>&1
assert_rc "無引數 → exit 2" 2 $?
"$HA_SCRIPT" bogus >/dev/null 2>&1
assert_rc "未知子指令 → exit 2" 2 $?

echo "▶ 14. codex-runtime-hygiene.sh 孤兒偵測 / 誤殺防護 / exit 契約"
CH_SCRIPT="$ROOT/claude/skills/deep-review/scripts/codex-runtime-hygiene.sh"
CH_STATE="$TMP/ch-state"
# 假「現行 codex」：讓 CURRENT_CODEX 判定不依賴這台機器有沒有裝 codex。
# 注意：假 binary 用 sleep 迴圈（不可單發長 sleep——孫進程會繼承 stdout pipe 卡住整個測試管線，
# 且 pkill 殺不到裸 `sleep N` 的 argv）；spawn 一律 >/dev/null 斷開 pipe 繼承。
mkdir -p "$TMP/ch-current-bin" "$TMP/ch-orphan-bin"
printf '#!/bin/sh\nwhile :; do sleep 5; done\n' > "$TMP/ch-current-bin/codex"
printf '#!/bin/sh\nwhile :; do sleep 5; done\n' > "$TMP/ch-orphan-bin/codex"
chmod +x "$TMP/ch-current-bin/codex" "$TMP/ch-orphan-bin/codex"
CH_ENV=(env "PATH=$TMP/ch-current-bin:$PATH" \
    "CODEX_HYGIENE_STATE_DIR=$CH_STATE" \
    "CODEX_HYGIENE_BROKER_PATTERN=ch-fake-broker-serve")
ch_pids_cleanup() { pkill -f ch-fake-broker-serve 2>/dev/null; pkill -f "$TMP/ch-orphan-bin/codex" 2>/dev/null; return 0; }
# source-only 掛鉤載入函式後呼叫 broker_actively_working（子 shell 隔離 env 與 set -uo，變更不外洩——刻意）。
# source 前必須 set -- 清位置參數：sourced script 的 $1 會繼承本函式參數，污染其 MODE 判定
# shellcheck disable=SC1090,SC2030,SC2031
ch_actively_working() {
    (export CODEX_HYGIENE_SOURCED=1 CODEX_HYGIENE_STATE_DIR="$CH_STATE"
     ch_bpid="$1"; set --
     . "$CH_SCRIPT"; broker_actively_working "$ch_bpid")
}

# --- broker_actively_working 函式級測試（source-only 掛鉤）---
# S1 迴歸：plugin 的 jobs 陣列「新的在前」（unshift + updatedAt 降冪 prune）。
# jobs[0]=running＋新鮮 log、jobs[尾]=completed → 必須判現役（rc=0）；讀錯端（.jobs[-1]）會誤殺。
mkdir -p "$CH_STATE/.myrepo-aaa111"   # dot 開頭目錄：glob 會漏、find 不會
touch "$TMP/ch-job.log"
printf '{"pid":4242,"sessionDir":"none"}\n' > "$CH_STATE/.myrepo-aaa111/broker.json"
printf '{"jobs":[{"status":"running","logFile":"%s"},{"status":"completed","logFile":"%s"}]}\n' \
    "$TMP/ch-job.log" "$TMP/ch-job.log" > "$CH_STATE/.myrepo-aaa111/state.json"
rc=0
ch_actively_working 4242 || rc=$?
assert_rc "S1：jobs[0]=running＋新鮮 log → 現役不殺（rc=0）" 0 "$rc"

# 全 completed（無 active job）→ 非現役可清（rc=1）
printf '{"jobs":[{"status":"completed","logFile":"%s"}]}\n' "$TMP/ch-job.log" \
    > "$CH_STATE/.myrepo-aaa111/state.json"
rc=0
ch_actively_working 4242 || rc=$?
assert_rc "全 completed → 非現役（rc=1）" 1 "$rc"

# active job 但 log 停滯（>15 分）→ 非現役（rc=1）
touch -t 202601011200 "$TMP/ch-job.log"
printf '{"jobs":[{"status":"running","logFile":"%s"}]}\n' "$TMP/ch-job.log" \
    > "$CH_STATE/.myrepo-aaa111/state.json"
rc=0
ch_actively_working 4242 || rc=$?
assert_rc "active 但 log 停滯 → 可清（rc=1）" 1 "$rc"
rm -f "$CH_STATE/.myrepo-aaa111"/broker.json "$CH_STATE/.myrepo-aaa111"/state.json

# --- 端到端：split-brain 現役 SKIP（check exit 3）→ 轉可清（exit 1）→ clean 收割（exit 0）---
# 假 broker：argv 帶測試 pattern，子進程跑「非現行 codex」絕對路徑 binary（= split-brain）
bash -c ": ch-fake-broker-serve; \"$TMP/ch-orphan-bin/codex\" & wait" >/dev/null 2>&1 &
CH_BPID=$!
sleep 0.3   # 等子進程 spawn
touch "$TMP/ch-job.log"
printf '{"pid":%s,"sessionDir":"%s"}\n' "$CH_BPID" "$TMP/ch-sock-cxc-none" > "$CH_STATE/.myrepo-aaa111/broker.json"
printf '{"jobs":[{"status":"running","logFile":"%s"}]}\n' "$TMP/ch-job.log" > "$CH_STATE/.myrepo-aaa111/state.json"
"${CH_ENV[@]}" "$CH_SCRIPT" check >/dev/null 2>&1
assert_rc "e2e：split-brain＋現役 job → check exit 3（SKIP 不殺）" 3 $?
kill -0 "$CH_BPID" 2>/dev/null
assert_rc "e2e：check 後假 broker 仍存活" 0 $?

# job 轉 completed → 可清孤兒（check exit 1）→ clean 收割並複驗乾淨（exit 0）
printf '{"jobs":[{"status":"completed","logFile":"%s"}]}\n' "$TMP/ch-job.log" > "$CH_STATE/.myrepo-aaa111/state.json"
"${CH_ENV[@]}" "$CH_SCRIPT" check >/dev/null 2>&1
assert_rc "e2e：job 已完 → check exit 1（可清孤兒）" 1 $?
"${CH_ENV[@]}" "$CH_SCRIPT" clean >/dev/null 2>&1
assert_rc "e2e：clean 收割孤兒＋複驗 → exit 0" 0 $?
sleep 0.3
if ! kill -0 "$CH_BPID" 2>/dev/null && ! pgrep -f "$TMP/ch-orphan-bin/codex" >/dev/null 2>&1; then
    ok "e2e：孤兒 broker 與其 app-server 子進程皆被收"
else bad "e2e：孤兒進程未收乾淨"; ch_pids_cleanup; fi
if [ ! -e "$CH_STATE/.myrepo-aaa111/broker.json" ]; then ok "e2e：孤兒 broker.json 已移除"; else bad "e2e：broker.json 未移除"; fi

# --- stale broker.json（pid 已死）＋ rm -rf 前綴防護 ---
mkdir -p "$CH_STATE/normal-bbb222" "$TMP/ch-sock/cxc-good" "$TMP/ch-sock/important-data"
printf '{"pid":99999999,"sessionDir":"%s"}\n' "$TMP/ch-sock/cxc-good" > "$CH_STATE/.myrepo-aaa111/broker.json"
printf '{"pid":null,"sessionDir":"%s"}\n' "$TMP/ch-sock/important-data" > "$CH_STATE/normal-bbb222/broker.json"
"${CH_ENV[@]}" "$CH_SCRIPT" check >/dev/null 2>&1
assert_rc "stale json（含 dot 目錄）→ check exit 1" 1 $?
"${CH_ENV[@]}" "$CH_SCRIPT" clean >/dev/null 2>&1
assert_rc "stale json clean → exit 0" 0 $?
if [ ! -e "$CH_STATE/.myrepo-aaa111/broker.json" ] && [ ! -e "$CH_STATE/normal-bbb222/broker.json" ]; then
    ok "stale broker.json 兩目錄（含 dot）皆清除"
else bad "stale broker.json 未清乾淨（dot 目錄漏掃？）"; fi
if [ ! -d "$TMP/ch-sock/cxc-good" ]; then ok "cxc- sessionDir 已移除"; else bad "cxc- sessionDir 未移除"; fi
if [ -d "$TMP/ch-sock/important-data" ]; then ok "非 cxc- sessionDir 保留（rm -rf 前綴防護）"; else bad "非 cxc- 路徑被誤刪"; fi
"${CH_ENV[@]}" "$CH_SCRIPT" check >/dev/null 2>&1
assert_rc "清理後 → check exit 0（乾淨）" 0 $?
"${CH_ENV[@]}" "$CH_SCRIPT" bogus >/dev/null 2>&1
assert_rc "未知模式 → exit 2" 2 $?
ch_pids_cleanup

echo "▶ 15. ensure-rc-source.sh 幂等補 source 行"
ERS="$ROOT/scripts/ensure-rc-source.sh"
MARKER='shell/functions.sh'

# rc 無 marker → 補上一行
ers_rc="$TMP/rc-plain"
printf '# 既有內容\nexport FOO=bar\n' > "$ers_rc"
RC_FILE="$ers_rc" bash "$ERS"
assert_rc "無 marker → exit 0" 0 $?
if grep -qF "$MARKER" "$ers_rc"; then ok "已補上 source 行"; else bad "未補上 source 行"; fi
if grep -qxF 'export FOO=bar' "$ers_rc"; then ok "原有內容保留"; else bad "原有內容遺失"; fi

# 再跑一次 → 幂等不重複（數 source 行本身，避開含 marker 的註解行）
RC_FILE="$ers_rc" bash "$ERS"
ers_count=$(grep -cF 'source ~/.dotfiles/shell/functions.sh' "$ers_rc")
assert_eq "重跑不重複（source 行出現 1 次）" "1" "$ers_count"

# 已含 marker 的 rc → 原封不動
ers_pre="$TMP/rc-pre"
printf 'source ~/.dotfiles/shell/functions.sh\n' > "$ers_pre"
cp "$ers_pre" "$ers_pre.orig"
RC_FILE="$ers_pre" bash "$ERS"
if diff -q "$ers_pre" "$ers_pre.orig" >/dev/null; then ok "已含 marker → 內容不變"; else bad "已含 marker 仍被改動"; fi

# rc 不存在 → 不建立、exit 0
ers_none="$TMP/rc-nonexistent"
RC_FILE="$ers_none" bash "$ERS"
assert_rc "rc 不存在 → exit 0" 0 $?
if [ ! -e "$ers_none" ]; then ok "rc 不存在 → 不建立檔案"; else bad "rc 不存在卻建立了檔案"; fi

echo "▶ 16. session-pull-check.sh（SessionStart hook）落後偵測與靜默契約"
SPC="$ROOT/claude/scripts/session-pull-check.sh"

# fixture：bare origin + clone a（推進 3 commits）+ clone b（停在第 1 個 commit）
spc="$TMP/spc"; mkdir -p "$spc"
git init -q --bare -b main "$spc/origin.git"
git clone -q "$spc/origin.git" "$spc/a" 2>/dev/null
(cd "$spc/a" && git config user.name t && git config user.email t@t.local \
  && echo 1 > f && git add . && git commit -qm c1 && git push -q origin main)
git clone -q "$spc/origin.git" "$spc/b" 2>/dev/null
(cd "$spc/b" && git config user.name t && git config user.email t@t.local)
(cd "$spc/a" && echo 2 >> f && git commit -qam c2 && echo 3 >> f && git commit -qam c3 && git push -q origin main)

# (1) 落後 clone → 提醒輸出且 exit 0
rm -f "$spc/b/.git/FETCH_HEAD"
spc_out="$(cd "$spc/b" && bash "$SPC")"
assert_rc "落後 clone → exit 0" 0 $?
if echo "$spc_out" | grep -q "落後"; then ok "落後 clone → 提醒輸出（含 behind 數）"; else bad "落後 clone 無提醒：$spc_out"; fi

# (2) 非 git repo → 靜默 exit 0
spc_out="$(cd "$TMP" && bash "$SPC")"
assert_rc "非 repo → exit 0" 0 $?
assert_eq "非 repo → 無輸出" "" "$spc_out"

# (3) detached HEAD → 靜默 exit 0
(cd "$spc/b" && git checkout -q --detach HEAD)
spc_out="$(cd "$spc/b" && bash "$SPC")"
assert_rc "detached HEAD → exit 0" 0 $?
assert_eq "detached HEAD → 無輸出" "" "$spc_out"
(cd "$spc/b" && git checkout -q main)

# (4) FETCH_HEAD 新鮮 → 跳過 fetch（證法：壞 remote 下仍能報落後 = 未嘗試 fetch；
#     對照組：FETCH_HEAD 過期時同樣壞 remote → fetch 失敗靜默 exit 0、無輸出）
(cd "$spc/b" && git remote set-url origin "$spc/nonexistent.git" && touch .git/FETCH_HEAD)
spc_out="$(cd "$spc/b" && bash "$SPC")"
assert_rc "壞 remote + FETCH_HEAD 新鮮 → exit 0" 0 $?
if echo "$spc_out" | grep -q "落後"; then ok "FETCH_HEAD 新鮮 → 跳過 fetch 仍報落後"; else bad "FETCH_HEAD 新鮮未跳過 fetch：$spc_out"; fi
rm -f "$spc/b/.git/FETCH_HEAD"
spc_out="$(cd "$spc/b" && bash "$SPC")"
assert_rc "壞 remote + 需 fetch → exit 0" 0 $?
assert_eq "壞 remote + 需 fetch → 靜默放棄偵測" "" "$spc_out"
(cd "$spc/b" && git remote set-url origin "$spc/origin.git")

# (5) STATUS.md 過期（最後 commit 落後 repo 活動 > 30 天）→ staleness 提醒
(cd "$spc/a" && echo "# STATUS" > STATUS.md && git add STATUS.md \
  && GIT_COMMITTER_DATE="2026-01-01T10:00:00" git commit -qm "docs: status" --date="2026-01-01T10:00:00" \
  && echo 4 >> f && git commit -qam c4)
spc_out="$(cd "$spc/a" && bash "$SPC")"
assert_rc "stale STATUS.md → exit 0" 0 $?
if echo "$spc_out" | grep -q "過期"; then ok "stale STATUS.md → dossier 過期提醒"; else bad "stale STATUS.md 無提醒：$spc_out"; fi

# (6) 同步且無 STATUS.md → 完全靜默（happy path，「絕不留噪音」契約的正面驗證）
(cd "$spc/b" && git pull -q origin main >/dev/null 2>&1)
rm -f "$spc/b/.git/FETCH_HEAD"
spc_out="$(cd "$spc/b" && bash "$SPC")"
assert_rc "同步 clone → exit 0" 0 $?
assert_eq "同步 clone → 完全靜默" "" "$spc_out"

echo "▶ 17. codex-exec-review.sh（deep-review skill script）exit 契約與 job 產物"
CER="$ROOT/claude/skills/deep-review/scripts/codex-exec-review.sh"
cer_base="$TMP/cer"
mkdir -p "$cer_base/bin" "$cer_base/jobs"

# 測試用 repo（兩個 commit，供 range 解析）
cer_repo="$cer_base/repo"
mkdir -p "$cer_repo"
(cd "$cer_repo" && git init -q && git config user.email t@t && git config user.name t \
    && echo one > a.txt && git add -A && git commit -qm first \
    && echo two >> a.txt && git commit -qam second) >/dev/null 2>&1
cer_range="$(cd "$cer_repo" && git rev-parse HEAD~1)..HEAD"

# codex stub：可切換「寫報告」/「不寫報告」，並吐出帶 session id 的 events。
# **模擬 clap 的 argv 拒絕行為**：`codex exec` 與 `codex exec resume` 是不同 subcommand、
# 旗標集合不同（resume 無 --color / -s / -C）。stub 若照單全收，旗標層級的契約違反在測試裡
# 等於不存在——2026-07-20 R1 審查即因此讓 resume 三處介面不符一路綠燈進 commit。
# NEVER loosen this stub to accept unknown flags.
cer_make_stub() {   # cer_make_stub <write_report:yes|no> [id_field]
    cat > "$cer_base/bin/codex" <<EOF
#!/usr/bin/env bash
# 落檔供斷言：實際 argv 與執行時的 cwd
printf '%s\n' "\$@" > "\${CODEX_STUB_ARGV:-/dev/null}"
pwd > "\${CODEX_STUB_CWD:-/dev/null}"

[ "\$1" = "exec" ] || { echo "error: unexpected subcommand '\$1'" >&2; exit 2; }
shift
mode="exec"
if [ "\${1:-}" = "resume" ]; then mode="resume"; shift; [ -n "\${1:-}" ] && case "\$1" in -*) ;; *) shift ;; esac; fi

out=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        --json|--ephemeral|--skip-git-repo-check) shift ;;
        -o|--output-last-message) out="\${2:-}"; shift 2 ;;
        -m|--model|-c|--config|--output-schema) shift 2 ;;
        --color|-s|--sandbox|-C|--cd)
            # 僅 exec 合法；resume 遇到即如 clap 般拒絕
            if [ "\$mode" = "resume" ]; then
                echo "error: unexpected argument '\$1' found" >&2; exit 2
            fi
            shift 2 ;;
        -*) echo "error: unexpected argument '\$1' found" >&2; exit 2 ;;
        *) shift ;;   # prompt 位置引數
    esac
done

echo '{"${2:-session_id}":"sess-fixture-1","type":"session_meta"}'
[ "$1" = "yes" ] && [ -n "\$out" ] && printf 'CODEX 報告\n' > "\$out"
exit 0
EOF
    chmod +x "$cer_base/bin/codex"
}
cer_run() { PATH="$cer_base/bin:$PATH" CODEX_EXEC_REVIEW_DIR="$cer_base/jobs" bash "$CER" "$@"; }

# (1) 報告產出 → exit 0 + job 產物齊全 + session id 取出
# 斷言一律打**真實 argv**（stub 落檔），不打 $job/cmd——後者是重建字串，
# 真實呼叫若漂移（如掉了 -s read-only）它照樣長對，等於守空。
cer_make_stub yes
cer_argv_run="$TMP/cer-run.argv"
cer_out="$(CODEX_STUB_ARGV="$cer_argv_run" cer_run run --repo "$cer_repo" --range "$cer_range" --round C1 2>/dev/null)"
assert_rc "run 產出報告 → exit 0" 0 $?
cer_job="$(printf '%s\n' "$cer_out" | sed -n 's/^job-dir: //p' | head -1)"
if [ -n "$cer_job" ] && [ -d "$cer_job" ]; then ok "run 第一行印出 job-dir"; else bad "run 未印出可用的 job-dir"; fi
cer_missing=""
for f in cmd meta events.jsonl report.md session-id exit-code; do
    [ -f "$cer_job/$f" ] || cer_missing="$cer_missing $f"
done
assert_eq "job 產物齊全" "" "$cer_missing"
assert_eq "session id 自 events 取出" "sess-fixture-1" "$(cat "$cer_job/session-id")"
if grep -qxF "Run your repo-review skill on $cer_repo for $cer_range. 繁體中文." "$cer_argv_run"; then
    ok "送出的 prompt 為一行協議原文（真實 argv）"
else bad "prompt 偏離一行協議原文"; fi
if grep -qxF -- "-s" "$cer_argv_run" && grep -qxF "read-only" "$cer_argv_run"; then
    ok "run 以 read-only sandbox 執行（真實 argv；審查者不改碼）"
else bad "run 未帶 -s read-only"; fi
if grep -qxF -- "-C" "$cer_argv_run" && grep -qxF "$cer_repo" "$cer_argv_run"; then
    ok "run 以 -C 指向受審 repo（真實 argv）"
else bad "run 未以 -C 指向受審 repo"; fi
if grep -qxF -- "--json" "$cer_argv_run"; then ok "run 帶 --json（events 可解析）"; else bad "run 未帶 --json"; fi
# $job/cmd 仍須忠實反映真實呼叫（同一 argv 陣列衍生），供事後複製重跑
if grep -qF -- "-s read-only" "$cer_job/cmd" || grep -qF -- "-s" "$cer_job/cmd"; then
    ok "cmd 記錄與真實呼叫同源"
else bad "cmd 記錄與真實呼叫脫節"; fi

# (2) 進程結束但報告空 → exit 4（升級 resume），且 thread_id 欄位也能取到 session id
cer_make_stub no thread_id
cer_out="$(cer_run run --repo "$cer_repo" --range "$cer_range" --round C1 2>/dev/null)"
assert_rc "run 報告空 → exit 4" 4 $?
cer_job2="$(printf '%s\n' "$cer_out" | sed -n 's/^job-dir: //p' | head -1)"
assert_eq "session id 亦支援 thread_id 欄位" "sess-fixture-1" "$(cat "$cer_job2/session-id")"
# job 目錄唯一性（mktemp）：同秒兩次 run 若共用目錄，會把上一輪的 report.md 當本輪產出 → 假成功
if [ "$cer_job" != "$cer_job2" ]; then ok "同秒兩次 run 的 job 目錄不碰撞"; else bad "job 目錄碰撞（會誤報上輪報告）"; fi

# (3) resume：用記錄的 session id，救不回 → 4；救得回 → 0
cer_run resume --job-dir "$cer_job2" >/dev/null 2>&1
assert_rc "resume 仍無產出 → exit 4" 4 $?
cer_make_stub yes
cer_argv="$TMP/cer-resume.argv"
cer_cwd="$TMP/cer-resume.cwd"
cer_out="$(CODEX_STUB_ARGV="$cer_argv" CODEX_STUB_CWD="$cer_cwd" cer_run resume --job-dir "$cer_job2" 2>/dev/null)"
assert_rc "resume 救回報告 → exit 0" 0 $?
if printf '%s\n' "$cer_out" | grep -qF "resume session: sess-fixture-1"; then
    ok "resume 沿用 job 記錄的 session id"
else bad "resume 未使用記錄的 session id"; fi

# resume 的 CLI 介面契約（對照真實 binary：resume 無 --color / -s / -C）
if grep -qxF -- "--color" "$cer_argv"; then bad "resume 帶了 --color（真實 binary 會 clap 拒絕）"; else ok "resume 未帶 --color"; fi
if grep -qxF -- "-s" "$cer_argv"; then bad "resume 帶了 -s（真實 binary 會 clap 拒絕）"; else ok "resume 未帶 -s"; fi
if grep -qxF -- "-C" "$cer_argv"; then bad "resume 帶了 -C（真實 binary 會 clap 拒絕）"; else ok "resume 未帶 -C"; fi
# session id 也要打真實 argv：只驗腳本自印的 "resume session:" 的話，argv 掉了 sid 仍會全綠
# （真實 binary 缺 SESSION_ID 且無 --last 會失敗）
if grep -qxF "sess-fixture-1" "$cer_argv"; then ok "resume 的 session id 出現在真實 argv"; else bad "resume 未把 session id 傳給 codex"; fi
# resume 無 -s，須改以 -c sandbox_mode 達成同一約束（否則落回 config.toml 的 danger-full-access）
if grep -qF 'sandbox_mode="read-only"' "$cer_argv" || grep -qF 'sandbox_mode=read-only' "$cer_argv"; then
    ok "resume 以 -c sandbox_mode 維持 read-only"
else bad "resume 未約束 sandbox（會落回 danger-full-access）"; fi
# resume 不支援 -C，須自行 cd 到受審 repo，否則繼承呼叫者 cwd
assert_eq "resume 在受審 repo 的工作目錄下執行" "$(cd "$cer_repo" && pwd -P)" "$(cd "$(cat "$cer_cwd")" && pwd -P)"
# 失敗現場可見（B1）
if [ -f "$cer_job2/cmd-resume" ]; then ok "resume 記錄實際指令（cmd-resume）"; else bad "resume 未記錄 cmd-resume"; fi
cer_status_r="$(cer_run status --job-dir "$cer_job2" 2>/dev/null)"
if printf '%s\n' "$cer_status_r" | grep -q '^codex-exit-resume='; then
    ok "status 印出 resume 的 exit code"
else bad "status 未涵蓋 resume（失敗原因看不到）"; fi

# (4) 環境/引數錯誤 → exit 5
cer_make_stub yes
cer_run run --repo "$cer_base/nonexistent" --range "$cer_range" --round C1 >/dev/null 2>&1
assert_rc "repo 不存在 → exit 5" 5 $?
cer_run run --repo "$cer_base" --range "$cer_range" --round C1 >/dev/null 2>&1
assert_rc "非 git repo → exit 5" 5 $?
cer_run run --repo "$cer_repo" --range "HEAD..nosuchref" --round C1 >/dev/null 2>&1
assert_rc "range head 端無法解析 → exit 5" 5 $?
cer_run run --repo "$cer_repo" --range "noDots" --round C1 >/dev/null 2>&1
assert_rc "range 缺 .. → exit 5" 5 $?
CODEX_EXEC_REVIEW_DIR="$cer_base/jobs" PATH=/usr/bin:/bin bash "$CER" run --repo "$cer_repo" --range "$cer_range" --round C1 >/dev/null 2>&1
assert_rc "codex 不在 PATH → exit 5" 5 $?

# (5) baseline 模式：base 端非 rev（∅）只警告不阻擋——不可退化成 exit 5
cer_make_stub yes
cer_err="$TMP/cer-baseline.err"
cer_run run --repo "$cer_repo" --range "∅..HEAD" --round C1 >/dev/null 2>"$cer_err"
assert_rc "baseline ∅ base → 不判環境錯誤" 0 $?
if grep -qF "baseline 模式" "$cer_err"; then ok "baseline base 端有告知"; else bad "baseline base 端未告知"; fi

# (6) 用法錯誤 → exit 2
cer_run run --repo "$cer_repo" --range "$cer_range" >/dev/null 2>&1
assert_rc "缺 --round → exit 2" 2 $?
cer_run bogus >/dev/null 2>&1
assert_rc "未知子指令 → exit 2" 2 $?
# --round 直接進 mktemp 樣板：含路徑分隔字元須在此攔下，否則錯誤訊息會誤指「無法建立 job 目錄」
cer_run run --repo "$cer_repo" --range "$cer_range" --round "C1/x" >/dev/null 2>&1
assert_rc "--round 含 / → exit 2" 2 $?
# range 多組 .. 會讓中段被靜默吞掉；三點 range（branch diff）則必須照常可用
cer_run run --repo "$cer_repo" --range "a..b..c" --round C1 >/dev/null 2>&1
assert_rc "range 多組 .. → exit 5" 5 $?
# 三點 range 必須**拒絕**：下游 codex/skills/repo-review/scripts/review-context.sh 明確
# die「three-dot ranges are ambiguous here」。wrapper 若放行，codex 只會把該錯誤寫進
# report.md，而報告非空 → 回 0 → 假成功。（stub 不會真的跑 review-context.sh，故這條
# 契約只能靠斷言釘死，不能靠測試自然發現。）
cer_run run --repo "$cer_repo" --range "HEAD...HEAD" --round C1 >/dev/null 2>&1
assert_rc "三點 range → exit 5（與下游 repo-review 契約一致）" 5 $?
# base 端只放行明確的 baseline 表示法：拼錯的 base 若只警告就放行，會產出「成功但其實
# 什麼都沒審」的報告（codex 把無法 diff 的錯誤寫進 report.md，腳本照樣回 0）
cer_run run --repo "$cer_repo" --range "maim..HEAD" --round C1 >/dev/null 2>&1
assert_rc "拼錯的 base → exit 5（不得只警告放行）" 5 $?
cer_argv_bl="$TMP/cer-baseline.argv"
CODEX_STUB_ARGV="$cer_argv_bl" cer_run run --repo "$cer_repo" --range "∅..HEAD" --round C1 >/dev/null 2>&1
assert_rc "baseline ∅ base → 照常放行" 0 $?
# ∅ 是報告模板的顯示寫法，下游 review-context.sh 不認得 → 必須正規化成 empty-tree hash 再送出
if grep -q '4b825dc642cb6eb9a060e54bf8d69288fbee4904\.\.HEAD' "$cer_argv_bl"; then
    ok "∅ 已正規化為 empty-tree hash 才送給 codex"
else bad "∅ 原樣送出——下游會回 cannot resolve range base"; fi
cer_run run --repo "$cer_repo" --range "4b825dc642cb6eb9a060e54bf8d69288fbee4904..HEAD" --round C1 >/dev/null 2>&1
assert_rc "baseline empty-tree hash → 照常放行" 0 $?
cer_run >/dev/null 2>&1
assert_rc "無引數 → exit 2" 2 $?

# (7) status 可讀出關鍵欄位
cer_status="$(cer_run status --job-dir "$cer_job" 2>/dev/null)"
assert_rc "status → exit 0" 0 $?
if printf '%s\n' "$cer_status" | grep -q '^codex-exit='; then ok "status 印出 codex-exit"; else bad "status 缺 codex-exit"; fi
if printf '%s\n' "$cer_status" | grep -q '^report=.*bytes'; then ok "status 印出報告大小"; else bad "status 缺報告資訊"; fi

# (8) 錯誤分支：status / resume 的前置檢查
cer_run status --job-dir "$cer_base/no-such-job" >/dev/null 2>&1
assert_rc "status 對不存在的 job dir → exit 5" 5 $?
cer_run status >/dev/null 2>&1
assert_rc "status 缺 --job-dir → exit 2" 2 $?
# 「此 job 不可續」須回 4（往下一階跑 fresh run），不可回 5——5 的契約是「停、不重試」，
# 會讓呼叫端跳過階梯第 2 步並輸出誤導性的環境診斷（codex 明明就在 PATH）
cer_bare="$cer_base/jobs/bare"; mkdir -p "$cer_bare"
cer_run resume --job-dir "$cer_bare" >/dev/null 2>&1
assert_rc "resume 無 session-id → exit 4（非 5）" 4 $?
printf 'sess-x\n' > "$cer_bare/session-id"
cer_run resume --job-dir "$cer_bare" >/dev/null 2>&1
assert_rc "resume 的 meta 無可用 repo → exit 4（非 5）" 4 $?
# 真環境錯誤才回 5
cer_run resume --job-dir "$cer_base/no-such-job" >/dev/null 2>&1
assert_rc "resume 對不存在的 job dir → exit 5" 5 $?
# cmd-resume 需可直接貼回 shell 執行（&& 不可被 %q 轉義）
if grep -q ' && ' "$cer_job2/cmd-resume" && ! grep -q '\\&\\&' "$cer_job2/cmd-resume"; then
    ok "cmd-resume 可直接複製重跑（&& 未被轉義）"
else bad "cmd-resume 的 && 被轉義，貼回 shell 不能跑"; fi

# (9) 路徑含空白（job root 與 repo 皆是）
cer_sp="$cer_base/with space"
mkdir -p "$cer_sp/repo root"
(cd "$cer_sp/repo root" && git init -q && git config user.email t@t && git config user.name t \
    && echo x > f.txt && git add -A && git commit -qm one) >/dev/null 2>&1
cer_out="$(PATH="$cer_base/bin:$PATH" CODEX_EXEC_REVIEW_DIR="$cer_sp/jobs" \
    bash "$CER" run --repo "$cer_sp/repo root" --range "HEAD..HEAD" --round C1 2>/dev/null)"
assert_rc "路徑含空白 → exit 0" 0 $?
cer_job_sp="$(printf '%s\n' "$cer_out" | sed -n 's/^job-dir: //p' | head -1)"
if [ -s "$cer_job_sp/report.md" ]; then ok "路徑含空白 → 報告正確落檔"; else bad "路徑含空白 → 報告未落檔"; fi

echo "▶ 18. ensure-codex-skills.sh 幂等連結 codex skill"
ECS="$ROOT/scripts/ensure-codex-skills.sh"
ecs="$TMP/ecs"
mkdir -p "$ecs/src/repo-review" "$ecs/src/not-a-skill" "$ecs/dst/.system"
echo "# skill" > "$ecs/src/repo-review/SKILL.md"
echo "noise"   > "$ecs/src/not-a-skill/README.md"

# 目的地是舊的實體目錄 → 換成 symlink（這正是 7/20 實證的 stale 情境）
mkdir -p "$ecs/dst/repo-review" && echo "# 舊版" > "$ecs/dst/repo-review/SKILL.md"
SRC_ROOT="$ecs/src" DST_ROOT="$ecs/dst" bash "$ECS"
assert_rc "實體舊目錄 → exit 0" 0 $?
if [ -L "$ecs/dst/repo-review" ]; then ok "舊實體目錄已換成 symlink"; else bad "仍是實體目錄"; fi
assert_eq "symlink 指向 dotfiles 來源" "$ecs/src/repo-review" "$(readlink "$ecs/dst/repo-review")"
assert_eq "透過 symlink 讀到新版內容" "# skill" "$(cat "$ecs/dst/repo-review/SKILL.md")"

# 無 SKILL.md 的目錄不接管；~/.codex/skills 下的其他項目（.system）不動
if [ ! -e "$ecs/dst/not-a-skill" ]; then ok "無 SKILL.md 的目錄不建連結"; else bad "誤建了非 skill 連結"; fi
if [ -d "$ecs/dst/.system" ] && [ ! -L "$ecs/dst/.system" ]; then ok ".system 未被動到"; else bad ".system 被誤動"; fi

# 接管實體目錄須「備份而非刪除」：此腳本每台每次 dotsync 都跑，直接 rm -rf 等於把
# 手工修改的內容不可逆地消滅。備份區必須在 DST_ROOT 之外——codex 會把 skills/ 下每個
# 目錄當 skill 載入，備份留在裡面會變成另一個過期 skill。
if find "$ecs/dst-backup" -name SKILL.md 2>/dev/null | grep -q .; then
    ok "原實體目錄已備份（非直接刪除）"
else bad "原實體目錄被直接刪除，內容不可回收"; fi
if grep -rq '舊版' "$ecs/dst-backup" 2>/dev/null; then
    ok "備份保留了接管前的內容"
else bad "備份內容不正確"; fi
if [ -z "$(find "$ecs/dst" -maxdepth 1 -name 'repo-review-*' 2>/dev/null)" ]; then
    ok "備份未留在 skills/ 內（不會被當成另一個 skill）"
else bad "備份留在 skills/ 內，會被 codex 當成另一個過期 skill"; fi

# ln 失敗須回報而非靜默成功（rm/mv 已把原目錄移走，此時失敗＝skill 消失）。
# 用 ln stub 而非 chmod 500：root（容器／CI）可繞過 mode bits 讓 ln 意外成功 → 測試不可攜。
ecs_ro="$TMP/ecs-ro"
mkdir -p "$ecs_ro/src/s1" "$ecs_ro/dst" "$ecs_ro/bin"
echo "# s" > "$ecs_ro/src/s1/SKILL.md"
printf '#!/usr/bin/env bash\nexit 1\n' > "$ecs_ro/bin/ln"
chmod +x "$ecs_ro/bin/ln"
ecs_out="$(PATH="$ecs_ro/bin:$PATH" SRC_ROOT="$ecs_ro/src" DST_ROOT="$ecs_ro/dst" BACKUP_ROOT="$ecs_ro/bak" bash "$ECS" 2>&1)"
ecs_rc=$?
assert_rc "ln 失敗 → exit 非 0（不報成功）" 1 "$ecs_rc"
if printf '%s\n' "$ecs_out" | grep -q '⚠️'; then ok "ln 失敗印出警告（stdout，不被 2>/dev/null 吞）"; else bad "ln 失敗無警告"; fi

# 重跑幂等：已是正確 symlink → 不動檔（比對 inode 確認沒有 rm+重建）
# stat -c 先試（GNU 成功、BSD 失敗）再退 -f；順序不可顛倒——GNU 的 -f 是「檔案系統」會假成功
ecs_inode() { stat -c %i "$1" 2>/dev/null || stat -f %i "$1" 2>/dev/null; }
ecs_before="$(ecs_inode "$ecs/dst/repo-review")"
SRC_ROOT="$ecs/src" DST_ROOT="$ecs/dst" bash "$ECS"
ecs_after="$(ecs_inode "$ecs/dst/repo-review")"
assert_eq "重跑幂等（symlink 未重建）" "$ecs_before" "$ecs_after"

# 來源不存在 → 靜默 exit 0，不建立目的地
SRC_ROOT="$ecs/nonexistent" DST_ROOT="$ecs/dst2" bash "$ECS"
assert_rc "來源不存在 → exit 0" 0 $?
if [ ! -e "$ecs/dst2" ]; then ok "來源不存在 → 不建立目的地"; else bad "來源不存在卻建了目的地"; fi

# dotfiles-sync.sh 遠端回報段：撈 ↻ 告知的 pipeline 在 set -euo pipefail 下不可吃掉成敗回報。
# （實證：grep 無配對回 1 + pipefail + set -e → sync_remote 提早退出，所有主機的 ✅/⚠️/❌ 全消失，
#   同步失敗變靜默成功。故此處測的是「無 ↻ 時仍要印出結果」這個行為。）
# fixture 自原始碼抽出整個 sync_remote（**含 ssh 賦值行**——ssh 失敗同樣會在 set -e 下
# 吞掉整段回報，若只從 ↻ 那行往下抽會繞開這個最常見的失敗路徑，給出不存在的覆蓋保證），
# 只把 ssh 指令替換成可控的假指令。
ecs_report="$TMP/ecs-report.sh"
{
    echo 'set -euo pipefail'
    # shellcheck disable=SC2016,SC2028  # 刻意寫成字面：這些要寫進 fixture 腳本、由它自己展開
    printf '%s\n' 'fake_ssh() { printf "%s\n" "$FAKE_RESULT"; return "${FAKE_RC:-0}"; }'
    # shellcheck disable=SC2016  # 刻意字面：sed 的 pattern 要比對原始碼裡的 ${GREEN} 等字樣本身
    sed -n '/^sync_remote() {/,/^}/p' "$ROOT/scripts/dotfiles-sync.sh" \
        | sed 's/ssh -o BatchMode=yes -o ConnectTimeout=5 "\$host"/fake_ssh/; s/${GREEN}//g; s/${YELLOW}//g; s/${RED}//g; s/${NC}//g; s/echo -e/echo/g'
    # shellcheck disable=SC2016  # 同上，$1 由 fixture 自己展開
    echo 'sync_remote "$1"'
} > "$ecs_report"
# 哨兵：抽取失效時直接指出「原始碼抽取失效」，而非誤導成「回報消失」
if [ -s "$ecs_report" ] && grep -q 'esac' "$ecs_report" && grep -q 'fake_ssh' "$ecs_report"; then
    ok "fixture 自 dotfiles-sync.sh 抽取成功（含 ssh 賦值行）"
else bad "fixture 抽取失效——下列斷言不具意義，請檢查 sync_remote 的結構是否變動"; fi

ecs_out="$(FAKE_RESULT="OK" bash "$ecs_report" hostA 2>&1)"
assert_rc "無 ↻ 告知時 → 回報段仍正常結束" 0 $?
if printf '%s\n' "$ecs_out" | grep -q '✅ hostA'; then ok "無 ↻ 時仍印出主機結果（不被 pipefail 吃掉）"; else bad "回報被 pipeline 吃掉——同步失敗會變靜默成功"; fi
ecs_out="$(FAKE_RESULT="$(printf '↻ 接管 x\nOK\n')" bash "$ecs_report" hostB 2>&1)"
if printf '%s\n' "$ecs_out" | grep -q 'hostB: ↻ 接管 x'; then ok "有 ↻ 時撈出並冠上主機名"; else bad "↻ 告知未被撈出"; fi
if printf '%s\n' "$ecs_out" | grep -q '✅ hostB'; then ok "有 ↻ 時成敗回報不受影響"; else bad "有 ↻ 時成敗回報消失"; fi
# ssh 失敗（主機不可達）→ 必須印 ❌，不可整段靜默
ecs_out="$(FAKE_RESULT="" FAKE_RC=255 bash "$ecs_report" hostC 2>&1)"
assert_rc "ssh 失敗 → sync_remote 仍正常結束" 0 $?
if printf '%s\n' "$ecs_out" | grep -q '❌ hostC'; then ok "ssh 失敗 → 印出連線失敗（不靜默）"; else bad "ssh 失敗被 set -e 吞掉——同步失敗變靜默成功"; fi
ecs_out="$(FAKE_RESULT="NO_DOTFILES" bash "$ecs_report" hostD 2>&1)"
if printf '%s\n' "$ecs_out" | grep -q 'hostD'; then ok "NO_DOTFILES → 印出警告"; else bad "NO_DOTFILES 回報消失"; fi

echo "▶ 19. review-anchor.sh（deep-review skill script）錨點生命週期 / squash-cmd / codex-next"
RA_SCRIPT="$ROOT/claude/skills/deep-review/scripts/review-anchor.sh"

# fixture：bare origin + clone，main 已 push；feature branch 領先 2 commit
git init --bare -q "$TMP/ra-origin.git"
git init -q -b main "$TMP/ra-work"
(cd "$TMP/ra-work" \
    && echo a > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/ra-origin.git" && git push -qu origin main \
    && git switch -qc feat/x \
    && echo b > f.txt && "${GITC[@]}" commit -qam "feat: x" \
    && echo c > f.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes")

# show 無 anchor → exit 1（STOP）
"$RA_SCRIPT" show --repo "$TMP/ra-work" >/dev/null 2>&1
assert_rc "show 無 anchor → exit 1（STOP）" 1 $?

# record branch-diff → base = merge-base（腳本自解析，model 不心算）
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode branch-diff --base origin/main >/dev/null
assert_rc "record branch-diff → exit 0" 0 $?
ra_mb="$(git -C "$TMP/ra-work" merge-base origin/main HEAD)"
ra_anchor="$(git -C "$TMP/ra-work" rev-parse --absolute-git-dir)/deep-review/anchor"
if [ -f "$ra_anchor" ] && grep -qxF "base=$ra_mb" "$ra_anchor"; then ok "anchor 檔落地且 base=merge-base"; else bad "anchor base 錯誤"; fi

# squash-cmd happy path → 精確整行（固定 hash）+ commit 清單
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-work")"
assert_rc "squash-cmd happy path → exit 0" 0 $?
if echo "$out" | grep -qxF "squash-cmd: git -C $TMP/ra-work reset --soft $ra_mb"; then ok "squash-cmd 印解析完成指令（固定 hash）"; else bad "squash-cmd 指令錯誤"; fi
if echo "$out" | grep -q "fix: R1 review fixes"; then ok "squash-range 列出 commit"; else bad "squash-range 清單缺失"; fi

# record 無條件覆蓋（working-tree → base=HEAD）
ra_head="$(git -C "$TMP/ra-work" rev-parse HEAD)"
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode working-tree >/dev/null
if grep -qxF "base=$ra_head" "$ra_anchor"; then ok "record 二次呼叫無條件覆蓋"; else bad "record 未覆蓋"; fi

# range mode：下界解析 / 三點拒絕 / 壞 ref
ra_first="$(git -C "$TMP/ra-work" rev-parse main)"
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode range --range "$ra_first..HEAD" >/dev/null
assert_rc "record range → exit 0" 0 $?
if grep -qxF "base=$ra_first" "$ra_anchor"; then ok "range 下界解析正確"; else bad "range 下界錯誤"; fi
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode range --range "main...HEAD" >/dev/null 2>&1
assert_rc "三點 range → exit 2" 2 $?
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode range --range "nope..HEAD" >/dev/null 2>&1
assert_rc "壞 ref → exit 1" 1 $?

# anchor hash 不存在（GC/rebase 模擬）→ STOP
printf 'base=%s\nmode=branch-diff\nbranch=feat/x\nrecorded=0\n' "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" > "$ra_anchor"
"$RA_SCRIPT" squash-cmd --repo "$TMP/ra-work" >/dev/null 2>&1
assert_rc "anchor hash 已不存在 → exit 1（STOP）" 1 $?

# anchor 非 HEAD 祖先（換到不含 anchor 的 branch）→ STOP
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode working-tree >/dev/null
(cd "$TMP/ra-work" && git switch -qc other main)
"$RA_SCRIPT" squash-cmd --repo "$TMP/ra-work" >/dev/null 2>&1
assert_rc "anchor 非 HEAD 祖先 → exit 1（STOP）" 1 $?
(cd "$TMP/ra-work" && git switch -q feat/x && git branch -qD other)

# record 在 main、之後 switch -c → squash-cmd 照常（stale 判 ancestry、非 branch 名）
git clone -q "$TMP/ra-origin.git" "$TMP/ra-bf"
"$RA_SCRIPT" record --repo "$TMP/ra-bf" --mode working-tree >/dev/null
(cd "$TMP/ra-bf" && git switch -qc feat/z && echo z > z.txt && "${GITC[@]}" add z.txt && "${GITC[@]}" commit -qm "fix: z")
"$RA_SCRIPT" squash-cmd --repo "$TMP/ra-bf" >/dev/null
assert_rc "record→switch -c 後 squash-cmd 照常 → exit 0" 0 $?

# 空 range → WARNING、exit 0（reset 到 HEAD 無害）
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode working-tree >/dev/null
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-work")"
assert_rc "無 commit 可 squash → exit 0" 0 $?
if echo "$out" | grep -q "WARNING"; then ok "空 range → WARNING"; else bad "空 range 未警告"; fi

# codex-next：C1 → 冪等 → C2 增量 → --full → C4 上限
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode branch-diff --base origin/main >/dev/null
ra_h1="$(git -C "$TMP/ra-work" rev-parse HEAD)"
out="$("$RA_SCRIPT" codex-next --repo "$TMP/ra-work")"
assert_rc "codex-next C1 → exit 0" 0 $?
if echo "$out" | grep -q "codex-round: C1" && echo "$out" | grep -qxF "codex-range: $ra_mb..$ra_h1"; then ok "C1 range = anchor-base..HEAD"; else bad "C1 range 錯誤"; fi
if echo "$out" | grep -qF "codex-cmd: ~/.claude/skills/deep-review/scripts/codex-exec-review.sh run --repo $TMP/ra-work --range $ra_mb..$ra_h1 --round C1"; then ok "codex-cmd 整行照抄可執行"; else bad "codex-cmd 錯誤"; fi
out="$("$RA_SCRIPT" codex-next --repo "$TMP/ra-work")"
assert_rc "同 HEAD 再呼叫 → exit 0" 0 $?
if echo "$out" | grep -q "codex-round: C1"; then ok "同 HEAD 冪等（round 不誤增）"; else bad "冪等失敗"; fi
(cd "$TMP/ra-work" && echo d > f.txt && "${GITC[@]}" commit -qam "fix: codex C1 fixes")
ra_h2="$(git -C "$TMP/ra-work" rev-parse HEAD)"
out="$("$RA_SCRIPT" codex-next --repo "$TMP/ra-work")"
if echo "$out" | grep -q "codex-round: C2" && echo "$out" | grep -qxF "codex-range: $ra_h1..$ra_h2"; then ok "C2 增量 range = 上輪 HEAD..HEAD"; else bad "C2 range 錯誤"; fi
(cd "$TMP/ra-work" && echo e > f.txt && "${GITC[@]}" commit -qam "fix: codex C2 fixes")
ra_h3="$(git -C "$TMP/ra-work" rev-parse HEAD)"
out="$("$RA_SCRIPT" codex-next --repo "$TMP/ra-work" --full)"
if echo "$out" | grep -q "codex-round: C3" && echo "$out" | grep -qxF "codex-range: $ra_mb..$ra_h3"; then ok "--full → C1 scope、round 照推"; else bad "--full 錯誤"; fi
(cd "$TMP/ra-work" && echo f2 > f.txt && "${GITC[@]}" commit -qam "fix: codex C3 fixes")
"$RA_SCRIPT" codex-next --repo "$TMP/ra-work" >/dev/null 2>&1
assert_rc "超過 C3 上限 → exit 1（STOP）" 1 $?
if grep -qxF "codex_round=3" "$ra_anchor"; then ok "超上限 state 不前進"; else bad "超上限 state 誤前進"; fi

# baseline：record base=HEAD（非 empty-tree）、C1 range=empty-tree..HEAD
git clone -q "$TMP/ra-origin.git" "$TMP/ra-base"
"$RA_SCRIPT" record --repo "$TMP/ra-base" --mode baseline >/dev/null
ra_bh="$(git -C "$TMP/ra-base" rev-parse HEAD)"
if grep -qxF "base=$ra_bh" "$(git -C "$TMP/ra-base" rev-parse --absolute-git-dir)/deep-review/anchor"; then ok "baseline record base=HEAD（非 empty-tree）"; else bad "baseline base 錯誤"; fi
out="$("$RA_SCRIPT" codex-next --repo "$TMP/ra-base")"
if echo "$out" | grep -qxF "codex-range: 4b825dc642cb6eb9a060e54bf8d69288fbee4904..$ra_bh"; then ok "baseline C1 range = empty-tree..HEAD"; else bad "baseline C1 range 錯誤"; fi

# clear：刪檔 + 幂等
"$RA_SCRIPT" clear --repo "$TMP/ra-work" >/dev/null
assert_rc "clear → exit 0" 0 $?
if [ -f "$ra_anchor" ]; then bad "clear 未刪檔"; else ok "clear 刪除 anchor 檔"; fi
"$RA_SCRIPT" clear --repo "$TMP/ra-work" >/dev/null
assert_rc "clear 幂等（檔不存在仍 0）" 0 $?

# 用法錯誤 / 非 git repo
"$RA_SCRIPT" bogus --repo "$TMP/ra-work" >/dev/null 2>&1
assert_rc "未知子指令 → exit 2" 2 $?
"$RA_SCRIPT" record --repo "$TMP/ra-work" >/dev/null 2>&1
assert_rc "record 缺 --mode → exit 2" 2 $?
"$RA_SCRIPT" record --repo "$TMP/ra-work" --mode branch-diff >/dev/null 2>&1
assert_rc "branch-diff 缺 --base → exit 2" 2 $?
"$RA_SCRIPT" record --repo "$TMP/not-a-repo" --mode working-tree >/dev/null 2>&1
assert_rc "非 git repo → exit 1" 1 $?

# --- clean-room 回流改進：tests-baseline / diff-cmd / squash 既有-commit 警告 ---

# fixture：feature branch = 1 顆審查前既有 commit（feat: w feature）+ 1 顆 review fix commit
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp"
(cd "$TMP/ra-imp" \
    && git switch -qc feat/w \
    && echo w1 > w.txt && "${GITC[@]}" add w.txt && "${GITC[@]}" commit -qm "feat: w feature" \
    && echo w2 > w.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes")
ra_imp_anchor="$(git -C "$TMP/ra-imp" rev-parse --absolute-git-dir)/deep-review/anchor"
ra_imp_mb="$(git -C "$TMP/ra-imp" merge-base origin/main HEAD)"

# record --tests-baseline fail → 寫入 anchor + show 顯示
"$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode branch-diff --base origin/main --tests-baseline fail >/dev/null
assert_rc "record --tests-baseline → exit 0" 0 $?
if grep -qxF "tests_baseline=fail" "$ra_imp_anchor" 2>/dev/null; then ok "tests_baseline 寫入 anchor"; else bad "tests_baseline 未寫入 anchor"; fi
out="$("$RA_SCRIPT" show --repo "$TMP/ra-imp" 2>/dev/null)"
if echo "$out" | grep -q "tests-baseline: fail"; then ok "show 顯示 tests-baseline"; else bad "show 未顯示 tests-baseline"; fi

# codex-next 改寫 anchor 時保留 tests_baseline（否則 autocodex 階段丟失 baseline 資訊）
"$RA_SCRIPT" codex-next --repo "$TMP/ra-imp" >/dev/null 2>&1
if grep -qxF "tests_baseline=fail" "$ra_imp_anchor" 2>/dev/null; then ok "codex-next 保留 tests_baseline"; else bad "codex-next 丟失 tests_baseline"; fi

# record（branch-diff）輸出 diff-cmd 整行（固定 hash，照抄慣例）
out="$("$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode branch-diff --base origin/main --tests-baseline pass 2>/dev/null)"
if echo "$out" | grep -qxF "diff-cmd: git -C $TMP/ra-imp diff $ra_imp_mb...HEAD"; then ok "record 印 diff-cmd（固定 hash）"; else bad "diff-cmd 缺失或錯誤"; fi

# range 模式不印 diff-cmd（審查指令 = range 引數本身，...HEAD 會審錯範圍）
out="$("$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode range --range "$ra_imp_mb..HEAD" 2>/dev/null)"
if echo "$out" | grep -q "^diff-cmd:"; then bad "range 模式誤印 diff-cmd"; else ok "range 模式不印 diff-cmd"; fi

# tests-baseline 值域驗證
"$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode working-tree --tests-baseline bogus >/dev/null 2>&1
assert_rc "tests-baseline 非法值 → exit 2" 2 $?

# 無 flag 覆蓋 → tests_baseline 不殘留（record 無條件覆蓋語意）
"$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode branch-diff --base origin/main >/dev/null
if grep -q "^tests_baseline=" "$ra_imp_anchor"; then bad "無 flag 時 tests_baseline 殘留"; else ok "無 flag 覆蓋 → tests_baseline 不殘留"; fi

# squash-cmd 警告：feat: w feature 為審查前既有（1 顆）；fix: R1 review fixes 屬 review 產生
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp")"
if echo "$out" | grep -q "warning: 將壓掉 1 顆審查前既有 commit"; then ok "squash-cmd 警告既有 commits（數量正確）"; else bad "squash 既有-commit 警告缺失"; fi

# 全為 review 產生的 commits（wip snapshot + fix）→ 無警告
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp2"
"$RA_SCRIPT" record --repo "$TMP/ra-imp2" --mode working-tree >/dev/null
(cd "$TMP/ra-imp2" && git switch -qc feat/v \
    && echo v1 > v.txt && "${GITC[@]}" add v.txt && "${GITC[@]}" commit -qm "wip: pre-review snapshot" \
    && echo v2 > v.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp2")"
if echo "$out" | grep -q "warning: 將壓掉"; then bad "純 review commits 誤發警告"; else ok "純 review commits 無警告"; fi

echo "▶ 20. verify-tests.sh（deep-review skill script）框架偵測與 exit 契約（uv/bun stub）"
VT_SCRIPT="$ROOT/claude/skills/deep-review/scripts/verify-tests.sh"

# stub：PATH 前置注入假 uv/bun；argv 落檔供斷言（打真實 argv，不打重建字串）
mkdir -p "$TMP/vt-bin"
cat > "$TMP/vt-bin/uv" <<'STUB'
#!/usr/bin/env bash
[ -n "${VT_UV_ARGV:-}" ] && printf '%s\n' "$@" > "$VT_UV_ARGV"
exit "${VT_UV_RC:-0}"
STUB
cat > "$TMP/vt-bin/bun" <<'STUB'
#!/usr/bin/env bash
[ -n "${VT_BUN_ARGV:-}" ] && printf '%s\n' "$@" > "$VT_BUN_ARGV"
if [ "${VT_BUN_MODE:-ok}" = "notests" ]; then
    echo 'error: 0 test files matching **{.test,.spec,_test_,_spec_}.{js,ts,jsx,tsx} in --cwd=/x' >&2
    exit 1
fi
exit "${VT_BUN_RC:-0}"
STUB
chmod +x "$TMP/vt-bin/uv" "$TMP/vt-bin/bun"
vt_run() { PATH="$TMP/vt-bin:$PATH" "$VT_SCRIPT" "$@"; }

# pytest：rc 0/1/5 → exit 0/1/3
mkdir -p "$TMP/vt-py" && touch "$TMP/vt-py/pyproject.toml"
VT_UV_ARGV="$TMP/vt-uv-argv" vt_run "$TMP/vt-py" >/dev/null
assert_rc "pytest 全綠 → exit 0（PASS）" 0 $?
assert_eq "stub 收到真實 argv：uv run pytest" "run
pytest" "$(cat "$TMP/vt-uv-argv")"
out="$(VT_UV_RC=1 vt_run "$TMP/vt-py")"
assert_rc "pytest 紅 → exit 1（FAIL）" 1 $?
if echo "$out" | grep -q "verdict: FAIL"; then ok "FAIL 印 verdict 行"; else bad "FAIL verdict 缺失"; fi
VT_UV_RC=5 vt_run "$TMP/vt-py" >/dev/null
assert_rc "pytest rc=5（no tests collected）→ exit 3（SKIP）" 3 $?

# bun：test script 存在 → 執行；紅 / 無測試檔 / placeholder → 1 / 3 / 3
mkdir -p "$TMP/vt-js"
echo '{"scripts":{"test":"bun test"}}' > "$TMP/vt-js/package.json"
VT_BUN_ARGV="$TMP/vt-bun-argv" vt_run "$TMP/vt-js" >/dev/null
assert_rc "bun test 全綠 → exit 0" 0 $?
assert_eq "stub 收到真實 argv：bun test" "test" "$(cat "$TMP/vt-bun-argv")"
VT_BUN_RC=1 vt_run "$TMP/vt-js" >/dev/null
assert_rc "bun test 紅 → exit 1" 1 $?
VT_BUN_MODE=notests vt_run "$TMP/vt-js" >/dev/null
assert_rc "bun 無測試檔（0 test files matching）→ exit 3" 3 $?
mkdir -p "$TMP/vt-js-ph"
printf '{"scripts":{"test":"echo \\"Error: no test specified\\" && exit 1"}}\n' > "$TMP/vt-js-ph/package.json"
VT_BUN_ARGV="$TMP/vt-bun-ph-argv" vt_run "$TMP/vt-js-ph" >/dev/null
assert_rc "npm placeholder test script → exit 3" 3 $?
if [ -f "$TMP/vt-bun-ph-argv" ]; then bad "placeholder 不應執行 bun"; else ok "placeholder 未執行 bun（無 argv 落檔）"; fi

# 並存（monorepo）：都跑；任一紅即 FAIL
mkdir -p "$TMP/vt-both" && touch "$TMP/vt-both/pyproject.toml"
echo '{"scripts":{"test":"bun test"}}' > "$TMP/vt-both/package.json"
VT_UV_ARGV="$TMP/vt-both-uv" VT_BUN_ARGV="$TMP/vt-both-bun" vt_run "$TMP/vt-both" >/dev/null
assert_rc "並存皆綠 → exit 0" 0 $?
if [ -f "$TMP/vt-both-uv" ] && [ -f "$TMP/vt-both-bun" ]; then ok "並存 → 兩個框架都被執行"; else bad "並存未都執行"; fi
VT_BUN_RC=1 vt_run "$TMP/vt-both" >/dev/null
assert_rc "並存任一紅 → exit 1" 1 $?

# 無框架 / 用法錯誤
mkdir -p "$TMP/vt-none"
out="$(vt_run "$TMP/vt-none")"
assert_rc "無框架 → exit 3（SKIP）" 3 $?
if echo "$out" | grep -q "verdict: SKIP"; then ok "SKIP 印 verdict 行"; else bad "SKIP verdict 缺失"; fi
vt_run >/dev/null 2>&1
assert_rc "缺引數 → exit 2" 2 $?
vt_run "$TMP/vt-nope" >/dev/null 2>&1
assert_rc "路徑不存在 → exit 2" 2 $?

echo ""
echo "════════════════════════════"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ 全部通過" || echo "❌ 有失敗"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
