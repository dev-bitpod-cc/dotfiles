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
#  10. review-state.sh（deep-review skill script）scope-priority / round 判定
#  11. review-context.sh（repo-review skill script）range 解析 / guidance / autofix gate（含分岔 base / detached HEAD / 閘序）
#  12. repo-review skill packaging（evals 不進 runtime context）
#  13. handoff-anchor.sh（handoff skill script）錨點驗證與生命週期判定
#  14. codex-runtime-hygiene.sh（deep-review skill script）孤兒偵測 / 誤殺防護 / exit 契約
#  15. ensure-rc-source.sh 幂等補 source shell/functions.sh 行
#  16. session-pull-check.sh（SessionStart hook）落後偵測與靜默契約
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

echo ""
echo "════════════════════════════"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ 全部通過" || echo "❌ 有失敗"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
