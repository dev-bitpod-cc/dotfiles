#!/usr/bin/env bash
#
# tests/run.sh — dotfiles 腳本驗證（shellcheck + 語法 + 純邏輯行為測試）
#
# 用法：./tests/run.sh
# 涵蓋：
#   1. shellcheck / bash -n 全腳本 gate（含 claude/skills/*/scripts/）
#   2. scripts/lib/inventory.sh 解析與 append 行為
#   3. render-etc-hosts.sh 區塊生成、IP 數值排序、--apply 冪等
#   4. render-ssh-config.sh 區塊替換、--check、marker 防呆
#   5. add-new-host.sh --dry-run 煙霧測試（不動任何檔案）
#   6. git-hygiene.sh（ready4quit skill script）verdict 判定
#   7. ship-state.sh（uap skill script）偵測與 protection 判定（gh stub）
#   8. review-state.sh（deep-review skill script）scope-priority / round 判定
#   9. handoff-anchor.sh（handoff skill script）錨點驗證與生命週期判定
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
    "$ROOT"/claude/skills/*/scripts/*.sh \
    "$ROOT/setup-mac-env.sh" "$ROOT/setup-linux-env.sh" "$ROOT/write-mac-defaults.sh" \
    "$ROOT/tests/run.sh"; then
    ok "shellcheck 全部通過"
else
    bad "shellcheck 有 findings"
fi

echo "▶ 2. bash -n 語法 gate"
syntax_fail=0
for f in "$ROOT"/scripts/*.sh "$ROOT/scripts/lib/inventory.sh" \
         "$ROOT"/claude/skills/*/scripts/*.sh \
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
SS_SCRIPT="$ROOT/claude/skills/uap/scripts/ship-state.sh"

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

# 全乾淨 → changes NONE + docs-only 提醒（不查 protection）
git clone -q "$TMP/ss-origin.git" "$TMP/ss-clean"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ss-clean")"
assert_rc "乾淨 repo → exit 0" 0 $?
if echo "$out" | grep -q "changes: NONE" && echo "$out" | grep -q "docs-only"; then
    ok "乾淨 repo → changes NONE + docs-only 提醒"
else bad "乾淨 repo 輸出缺 docs-only 提醒"; fi

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

echo "▶ 11. handoff-anchor.sh 錨點驗證與生命週期判定"
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

echo ""
echo "════════════════════════════"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ 全部通過" || echo "❌ 有失敗"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
