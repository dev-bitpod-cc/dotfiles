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
#   9. ship-state.sh（project skill script）偵測與 protection 判定（gh stub；含 resolve 子指令 / bootstrap 判定 / dossier 偵測）
#  9b. branch-first.sh（project skill script）情況 A/B 判定與誤 commit 救援序列（真 git fixture）
#  10. review-state.sh（deep-review skill script）scope-priority / round / branch-first / continuity 判定
#  11. review-context.sh（repo-review skill script）range 解析 / guidance / autofix gate（含分岔 base / detached HEAD / 閘序）
#  12. repo-review skill packaging（evals 不進 runtime context）
#  13. handoff-anchor.sh（handoff skill script）錨點驗證與生命週期判定（含 consume 消費歸檔）
#  14. codex-runtime-hygiene.sh（deep-review skill script）孤兒偵測 / 誤殺防護 / exit 契約
#  15. ensure-rc-source.sh 幂等補 source shell/functions.sh 行
#  16. session-pull-check.sh（SessionStart hook）落後偵測與靜默契約
#  17. codex-exec-review.sh（deep-review skill script）exit 契約 / job 產物 / resume（codex stub）
#  18. ensure-codex-skills.sh 幂等連結 ~/.codex/skills → dotfiles
# 18b. ensure-codex-guidance.sh 幂等連結全域 ~/.codex/AGENTS.md → dotfiles
# 18c. ensure-lftprc.sh 幂等連結 ~/.lftprc → dotfiles（含 .lftprc.local 保證存在且不覆寫）
#  19. review-anchor.sh（deep-review skill script）錨點生命週期 / squash-cmd / codex-next
#  20. verify-tests.sh（deep-review skill script）框架偵測與 exit 契約（uv/bun stub）
#  21. crawl-quality-scan.py（check-crawl-quality skill script）確定性掃描 / 扣分帳目 / --classify 覆核
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
    "$ROOT/shell/functions.sh" \
    "$ROOT/tests/run.sh")"
fullwidth_rc=$?
# grep 的 exit：0=有命中、1=無命中、>1=執行錯誤（後者必須大聲失敗，不可當成乾淨）
fullwidth_hits="$(printf '%s\n' "$fullwidth_hits" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [ "$fullwidth_rc" -gt 1 ]; then
    bad "全形標點 gate 無法執行（grep rc=${fullwidth_rc}）——不可視為通過"
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
# 無保護仍預設 PR（SKILL Step 1 第 4 項）——腳本 verdict 是 model 照抄的東西，
# 印 DIRECT-PUSH 會與規則牴觸，等於誘導 agent 略過 PR（u3 eval 的 RED 即此形狀）
if echo "$out" | grep -q "protection: OPEN" && echo "$out" | grep -q "ship-path: PR" \
    && ! echo "$out" | grep -q "ship-path: DIRECT-PUSH"; then
    ok "stub open → OPEN 但 ship-path 仍為 PR（直推降為 escape hatch）"
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
if echo "$out" | grep -q "branch-first-cmd: .*branch-first\.sh"; then ok "misplaced → 附 branch-first.sh 呼叫指令供照抄"; else bad "misplaced 未附 branch-first-cmd"; fi

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

# --- resolve 子指令（Step 0 repo-token 判定）---

ss_top="$(git -C "$TMP/ss-work" rev-parse --show-toplevel)"

out="$("$SS_SCRIPT" resolve "$TMP/ss-work")"
assert_rc "resolve repo 根（絕對路徑）→ exit 0" 0 $?
if echo "$out" | grep -qF "resolve: REPO $ss_top"; then ok "repo 根 → REPO + toplevel"; else bad "repo 根未判 REPO（${out}）"; fi

out="$( (cd "$TMP/ss-work" && "$SS_SCRIPT" resolve .) )"
if echo "$out" | grep -qF "resolve: REPO $ss_top"; then ok "'.' → REPO（pwd 所在 repo 根）"; else bad "'.' 未判 REPO（${out}）"; fi

mkdir -p "$TMP/ss-work/sub/dir"
out="$( (cd "$TMP/ss-work" && "$SS_SCRIPT" resolve sub/dir) )"
if echo "$out" | grep -q "resolve: MODULE"; then ok "repo 內子路徑 → MODULE（不鎖定）"; else bad "子路徑未判 MODULE（${out}）"; fi

# '.' 在 repo 子目錄下也必須指向所屬 repo 根（舊 SKILL.md 契約：`.` → pwd 所在的 git repo 根）
out="$( (cd "$TMP/ss-work/sub/dir" && "$SS_SCRIPT" resolve .) )"
if echo "$out" | grep -qF "resolve: REPO $ss_top"; then ok "子目錄下 '.' → REPO（舊契約語意）"; else bad "子目錄下 '.' 未判 REPO（${out}）"; fi

ln -s "$TMP/ss-work" "$TMP/ss-link"
out="$("$SS_SCRIPT" resolve "$TMP/ss-link")"
if echo "$out" | grep -qF "resolve: REPO $ss_top"; then ok "symlink 到 repo 根 → REPO（realpath 正規化）"; else bad "symlink 未判 REPO（${out}）"; fi

out="$( (cd "$TMP" && "$SS_SCRIPT" resolve ss-work) )"
if echo "$out" | grep -qF "resolve: REPO $ss_top"; then ok "相對路徑到 repo 根 → REPO"; else bad "相對路徑未判 REPO（${out}）"; fi

# CDPATH 誘餌：cd builtin 吃環境 CDPATH，相對 token 會被拐去別處 → 必須隔離
mkdir -p "$TMP/cdpath-decoy/ss-work"
out="$( (cd "$TMP" && CDPATH="$TMP/cdpath-decoy" "$SS_SCRIPT" resolve ss-work) )"
if echo "$out" | grep -qF "resolve: REPO $ss_top"; then ok "CDPATH 誘餌下相對路徑仍判 REPO（cd 已隔離）"; else bad "CDPATH 干擾 resolve 判定（${out}）"; fi

out="$("$SS_SCRIPT" resolve "$TMP/no-such-token")"
assert_rc "resolve 不存在路徑 → exit 0（verdict 即成功）" 0 $?
if echo "$out" | grep -q "resolve: UNKNOWN"; then ok "不存在路徑 → UNKNOWN（交回 session 記憶比對）"; else bad "不存在路徑未判 UNKNOWN（${out}）"; fi

out="$("$SS_SCRIPT" resolve "$TMP")"
if echo "$out" | grep -q "resolve: UNKNOWN"; then ok "repo 外目錄 → UNKNOWN"; else bad "repo 外目錄未判 UNKNOWN（${out}）"; fi

"$SS_SCRIPT" resolve >/dev/null 2>&1
assert_rc "resolve 無 token → exit 2" 2 $?

# --- 殘留 branch 衛生（已完全併入 default 的 local/remote branch）---
# merge 最後一哩只清它自己 merge 的那支，規則生效前的老 branch 會無聲累積
# （實證：dotfiles 累到 2 支才被偶然發現）。只印訊號 + 清掃指令，絕不代刪。

git init --bare -q "$TMP/sb-origin.git"
git init -q -b main "$TMP/sb-work"
(cd "$TMP/sb-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/sb-origin.git" && git push -qu origin main)

# 乾淨（只有 main）→ 不得印 stale-branches（無殘留時保持安靜）
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sb-work")"
if ! echo "$out" | grep -q "stale-branches"; then ok "無殘留 branch → 不印 stale-branches（不噪音）"; else bad "無殘留卻印 stale-branches（${out}）"; fi

# 造一支已完全併入 main 的 local + remote branch（模擬 merge 後沒清）
(cd "$TMP/sb-work" \
    && git switch -qc feat/old-merged && git push -qu origin feat/old-merged \
    && git switch -q main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sb-work")"
if echo "$out" | grep -q "stale-branches:"; then ok "已併入 default 的殘留 branch → 印 stale-branches"; else bad "殘留 branch 未偵測（${out}）"; fi
if echo "$out" | grep -q "feat/old-merged"; then ok "stale-branches 列出 branch 名"; else bad "stale-branches 未列名"; fi
if echo "$out" | grep -q "cleanup-cmd:"; then ok "stale-branches 附清掃指令（供照抄，不代刪）"; else bad "stale-branches 缺 cleanup-cmd"; fi
if echo "$out" | grep -q "fetch --prune"; then ok "清掃指令前置 fetch --prune（防 remote-tracking 殘影誤刪）"; else bad "清掃指令未前置 fetch --prune"; fi

# origin/HEAD 存在時（真實 clone 的常態）：其 short form 是**裸 remote 名**（"origin"），
# 不是 branch——列進去會污染清單並讓 cleanup-cmd 拼出 `--deleteorigin`（實地跑真 repo 才
# 抓到，原 fixture 無 origin/HEAD 故漏測）
(cd "$TMP/sb-work" && git remote set-head origin main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sb-work")"
if ! echo "$out" | grep -qE "^  remote: origin$"; then ok "origin/HEAD 不被當成殘留 branch"; else bad "裸 remote 名混入殘留清單（${out}）"; fi
if echo "$out" | grep -q -- "--delete origin/" ; then bad "cleanup-cmd 的 remote branch 名未剝 remote 前綴"; else ok "cleanup-cmd 剝除 remote 前綴"; fi
if echo "$out" | grep -qE -- "--delete [a-z]" ; then ok "cleanup-cmd 的 --delete 與 branch 名有空白分隔"; else bad "cleanup-cmd 拼接缺空白（如 --deleteorigin）"; fi

# 未併入 default 的 branch（有獨立 commit）→ 不得列入（那是還沒 ship 的工作）
(cd "$TMP/sb-work" \
    && git switch -qc feat/in-progress && echo wip > w.txt \
    && "${GITC[@]}" add w.txt && "${GITC[@]}" commit -qm "feat: wip" \
    && git switch -q main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sb-work")"
if ! echo "$out" | grep -q "feat/in-progress"; then ok "未併入 default 的 branch 不列入殘留（不誤報未 ship 的工作）"; else bad "誤把未 merge 的 branch 當殘留（${out}）"; fi

# 當前 branch 即使已併入 default 也不列入（不建議刪自己腳下那支）
(cd "$TMP/sb-work" && git switch -q feat/old-merged)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sb-work")"
if ! echo "$out" | grep -qE "^  local: .*feat/old-merged"; then ok "當前 branch 不列入 local 殘留"; else bad "把當前 branch 列為可刪殘留（${out}）"; fi
(cd "$TMP/sb-work" && git switch -q main)

# --- bootstrap 偵測（全新空 repo 的第一次 ship；default 定位不到時才觸發）---
# 兩種「default: NONE」的正確處置完全相反：遠端零 branch → 可建 baseline；遠端有
# branch 但本地定位不到 → 絕不可推（推了就把 feature branch 變成遠端 default）。
# 本區塊釘死「分辨得出來」與「baseline 建立後豁免自動失效」。

# 情境 1：遠端零 branch + 本地 main 有 commit → BOOTSTRAP
git init --bare -q "$TMP/bs-origin.git"
git init -q -b main "$TMP/bs-work"
(cd "$TMP/bs-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/bs-origin.git")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bs-work")"
assert_rc "空 remote → exit 0（verdict 即成功）" 0 $?
if echo "$out" | grep -q "verdict: BOOTSTRAP"; then ok "遠端零 branch → BOOTSTRAP verdict"; else bad "遠端零 branch 未判 BOOTSTRAP（${out}）"; fi
if echo "$out" | grep -q "remote-heads: 0"; then ok "BOOTSTRAP 附遠端 branch 數證據"; else bad "BOOTSTRAP 缺 remote-heads 證據"; fi
if echo "$out" | grep -q "bootstrap-cmd: .*push -u origin main"; then ok "BOOTSTRAP 附可照抄 push 指令（推本地 default 名）"; else bad "BOOTSTRAP 缺 bootstrap-cmd"; fi
if echo "$out" | grep -q "bootstrap-note:.*default branch"; then ok "BOOTSTRAP 標明首推將決定遠端 default"; else bad "BOOTSTRAP 未標明 default 後果"; fi
if echo "$out" | grep -q "bootstrap-scope:"; then ok "BOOTSTRAP 標明豁免作用域（防授權蔓延）"; else bad "BOOTSTRAP 缺 scope 行（授權會蔓延到後續 commit）"; fi

# 情境 2：遠端零 branch + detached HEAD → 不可 bootstrap（無 branch 名可當 default）
(cd "$TMP/bs-work" && git checkout -q --detach)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bs-work")"
if echo "$out" | grep -q "verdict: STOP" && ! echo "$out" | grep -q "verdict: BOOTSTRAP"; then
    ok "空 remote + detached HEAD → STOP（非 bootstrap）"
else bad "detached HEAD 誤判 bootstrap（${out}）"; fi
(cd "$TMP/bs-work" && git checkout -q main)

# 情境 3（關鍵反例）：遠端**有** branch 但本地無 remote-tracking 且名非 main/master
# → default 定位不到，但**絕不可** bootstrap 直推
git init --bare -q "$TMP/bs-trunk.git"
git init -q -b trunk "$TMP/bs-seed"
(cd "$TMP/bs-seed" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/bs-trunk.git" && git push -qu origin trunk)
git init -q -b main "$TMP/bs-nofetch"
(cd "$TMP/bs-nofetch" \
    && echo hi > g.txt && "${GITC[@]}" add g.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/bs-trunk.git")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bs-nofetch")"
if echo "$out" | grep -q "verdict: STOP" && ! echo "$out" | grep -q "BOOTSTRAP"; then
    ok "遠端有 branch 但定位不到 default → STOP（不得誤判 bootstrap）"
else bad "遠端有 branch 卻判 bootstrap——會把 feature branch 推成遠端 default（${out}）"; fi
if echo "$out" | grep -q "remote-heads: 1"; then ok "反例附遠端 branch 數證據（供使用者 fetch/指定）"; else bad "反例缺 remote-heads 證據"; fi

# 情境 4（機制失效）：baseline 建立後 → 永不再印 BOOTSTRAP，branch-first 恢復 REQUIRED
(cd "$TMP/bs-work" && git push -qu origin main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bs-work")"
if ! echo "$out" | grep -q "BOOTSTRAP"; then ok "baseline 建立後 → BOOTSTRAP 豁免自動失效（機制而非記憶）"; else bad "baseline 已存在仍印 BOOTSTRAP（授權可蔓延）"; fi
if echo "$out" | grep -q "branch-first: REQUIRED"; then ok "baseline 建立後 → branch-first 恢復 REQUIRED"; else bad "baseline 後未恢復 branch-first"; fi

# --- dossier 偵測行（Step 2 衛生檢查；門檻單一來源 = 本腳本）---

# 無 STATUS.md → dossier: NONE
git init --bare -q "$TMP/ds-origin.git"
git init -q -b main "$TMP/ds-work"
(cd "$TMP/ds-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/ds-origin.git" && git push -qu origin main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier: NONE"; then ok "無 STATUS.md → dossier: NONE"; else bad "缺 dossier: NONE 行"; fi

# 乾淨 dossier（<300 行、進行中無 ✅、無 Session Log、剛 commit）→ 無 flag
# （已完成節的 ✅ 是合法用法，不得誤報——負向測試就藏在這份 fixture 裡）
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 測試專案 STATUS

## 進行中
- 項目一：還在做

## 關鍵決策（附理由）
- 選了 X 因為 Y

## 已完成（里程碑）
- ✅ 2026-07-01 已完成項（合法 ✅，不應觸發 flag）
DOSSIER
(cd "$TMP/ds-work" && "${GITC[@]}" add STATUS.md && "${GITC[@]}" commit -qm "docs: dossier")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier: STATUS.md"; then ok "有 STATUS.md → dossier 行含行數"; else bad "缺 dossier: STATUS.md 行"; fi
if echo "$out" | grep -q "dossier-flag:"; then bad "乾淨 dossier 不應有 flag（$(echo "$out" | grep 'dossier-flag:')）"; else ok "乾淨 dossier → 無 dossier-flag（已完成節 ✅ 未誤報）"; fi
# 各節佔比只在全檔超標時印——常態輸出多一段佔比表就成了每次 ship 的噪音
if echo "$out" | grep -q "^dossier-sections:"; then bad "未超標卻印 dossier-sections（污染常態輸出）"; else ok "未超標 → 不印 dossier-sections"; fi

# 「進行中」含 ✅ → flag（working tree 內容即測，不需 commit）
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 測試專案 STATUS

## 進行中
- ✅ 做完了卻沒移走的項目
- 項目二：還在做

## 已完成（里程碑）
- 無
DOSSIER
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*進行中.*✅"; then ok "進行中含 ✅ → flag"; else bad "進行中 ✅ 未偵測"; fi

# 規範外章節（Session Log）→ flag
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 測試專案 STATUS

## 進行中
- 項目

## Session Log
- 2026-07-01 做了一堆事
DOSSIER
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*Session Log"; then ok "Session Log 章節 → flag"; else bad "Session Log 未偵測"; fi

# 全檔 > 300 行 → flag
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; seq 1 310 | sed 's/^/- filler /'; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*> 300"; then ok "全檔 >300 行 → flag"; else bad ">300 行未偵測"; fi
if echo "$out" | grep -q "建議收斂至 ≤ 255 行"; then ok "行數 flag 附建議收斂目標（300 × 85%）"; else bad "行數 flag 缺建議收斂目標"; fi

# 總量 bytes 超標但行數遠低於 300 → bytes flag（行數代理被巨型單行架空的後盾；
# 每行 ~548 bytes < 1000，不得連帶觸發最長行 flag——測試隔離）
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"
  awk 'BEGIN { s = "- 填充"; for (i = 0; i < 30; i++) s = s "巨量內容累積"; for (r = 0; r < 120; r++) print s }'
  echo; echo "## 已完成（里程碑）"; echo "- ✅ 無"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -qE "dossier-flag:.*全檔.*bytes > "; then ok "行數少但總 bytes 超標 → bytes flag（風格不敏感後盾）"; else bad "bytes 超標未偵測（行數代理可被巨型單行架空）"; fi
if echo "$out" | grep -q "dossier-flag:.*> 300"; then bad "bytes fixture 不應觸發行數 flag（行數僅 ~125）"; else ok "bytes fixture 未誤觸發行數 flag"; fi
if echo "$out" | grep -q "dossier-flag:.*最長行"; then bad "bytes fixture 不應觸發最長行 flag（每行 ~548B < 1000）"; else ok "bytes fixture 未誤觸發最長行 flag"; fi
# 建議收斂目標：壓到「剛好低於門檻」等於下次 ship 必再觸發，故 flag 要直接給目標值
if echo "$out" | grep -q "建議收斂至 ≤ 20889 bytes"; then ok "bytes flag 附建議收斂目標（門檻 85%）"; else bad "bytes flag 缺建議收斂目標（agent 會停在剛好過關處）"; fi
# 各節佔比：超標時才印，供 model 決定收哪一節（憑印象挑會挑錯——krepo 實證 905B/PR）
if echo "$out" | grep -q "^dossier-sections:"; then ok "全檔超標 → 印各節佔比"; else bad "全檔超標未印 dossier-sections（收斂對象只能靠猜）"; fi
# 釘住「最大戶排第一」＋數值形狀：排序方向是這功能的全部價值（挑錯對象正是它要防的），
# 只 grep「行存在 + 含某節名」的斷言在 sort -rn → sort -n 突變下照樣全綠（R1 審查實證）
if echo "$out" | grep -qE "^dossier-sections: 進行中 [0-9]{4,} \([0-9]+%\)"; then ok "各節佔比：最大戶排第一、附 bytes 與百分比"; else bad "dossier-sections 排名或數值形狀錯（實得：$(echo "$out" | grep dossier-sections)）"; fi

# fence 重的章節不得被低估到排名倒轉：剝 fence 時若「清空」該行（而非哨兵前綴保留長度），
# 決策節 30KB 的 code block 會被算成幾百 bytes、沉到小章節後面——而 SKILL.md 正是要 agent
# 照這張表挑收斂對象，等於主動誤導（R1 審查實證：26KB 節報成 403 bytes）
# 本 fixture 一份守四件事（皆需「大檔 + fenced 假章節」才會發作，故合為一份）：
#   ①分節 bytes 不因剝 fence 而低估（排名倒轉）②fence 內假標題不誤判簽章
#   ③fence 內的「## 進行中 / - ✅」範例不誤報完成項未移走
#   ④大輸入下 Session Log 仍偵測得到（herestring；pipe 版會 SIGPIPE 早退成偽陰性）
# ⚠️ Session Log 與假 ✅ 都必須放在**大 fence 之前**：grep -q / awk 命中即退出，命中點在
# 檔尾的話上游 printf 早就寫完、SIGPIPE 不會發作，守門形同虛設（實測：置於檔尾時把
# herestring 改回 printf|grep 仍全綠）。前段命中才逼出「寫不完 → SIGPIPE → pipefail」
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 短項目"; echo
  echo "## Session Log"
  echo "- 2026-07-29 這是規範外章節，應被偵測到"; echo
  echo "## 關鍵決策（附理由）"
  echo '```markdown'
  echo "## 進行中"
  echo "- ✅ 這是文件範例裡的完成項，不是真的狀態"
  awk 'BEGIN { s = "# "; for (i = 0; i < 20; i++) s = s "fenced_payload_line_content_"; for (r = 0; r < 200; r++) print s }'
  echo '```'
  echo
  echo "## 已完成（里程碑）"
  awk 'BEGIN { s = "- ✅ 里程碑填充"; for (i = 0; i < 10; i++) s = s "內容"; for (r = 0; r < 30; r++) print s }'; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -qE "^dossier-sections: 關鍵決策（附理由） [0-9]{5,}"; then ok "fenced 內容計入分節 bytes（大 fence 章節排第一，未被低估）"; else bad "fence 章節被低估／排名倒轉（實得：$(echo "$out" | grep dossier-sections)）"; fi
if echo "$out" | grep -q "dossier-flag:.*簽章"; then bad "大輸入下簽章偽陽性（grep -q 早退 + pipefail）"; else ok "大檔簽章判定正確（herestring 防 SIGPIPE 偽陽性）"; fi
# ✅ 偵測必須吃 unfenced：讀原檔會把 fence 內的範例當成真的「進行中含 ✅」
if echo "$out" | grep -q "dossier-flag:.*進行中.*✅"; then bad "fence 內的 ✅ 範例被誤報為完成項未移走（✅ 偵測未吃 unfenced）"; else ok "fence 內的 ✅ 範例不誤報"; fi
# Session Log 偵測的失效方向是偽陰性（命中才早退），比簽章那處更隱蔽——必須有具名守門
if echo "$out" | grep -q "dossier-flag:.*Session Log"; then ok "大檔（>pipe buffer）Session Log 仍偵測到（herestring 防 SIGPIPE 偽陰性）"; else bad "大輸入下 Session Log 偽陰性（grep -q 早退 + pipefail）"; fi

# 巨型單行（1202 bytes > 1000）→ 最長行 flag（總量未爆前的早期風格糾正）
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"
  awk 'BEGIN { s = "- "; for (i = 0; i < 1200; i++) s = s "x"; print s }'
  echo; echo "## 已完成（里程碑）"; echo "- ✅ 無"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*最長行"; then ok "1202 bytes 單行 → 最長行 flag"; else bad "巨型單行未偵測"; fi
if echo "$out" | grep -qE "dossier-flag:.*全檔.*bytes > "; then bad "最長行 fixture 不應觸發總量 bytes flag（全檔 <2KB）"; else ok "最長行 fixture 未誤觸發 bytes flag"; fi

# 決策節單一條目 >800 bytes（正常換行的多行條目，每行 <1000B）→ 條目 flag（行數繞不過蒸餾上限）
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 項目：還在做"; echo
  echo "## 關鍵決策（附理由）"
  awk 'BEGIN { s = "- 選了方案甲："; for (i = 0; i < 60; i++) s = s "理由與推導"; print s
               t = "  續行補充："; for (i = 0; i < 60; i++) t = t "更多細節"; print t }'
  echo "- 短決策：一行帶過"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*最大條目"; then ok "決策節條目 >800 bytes → 條目 flag（蒸餾上限）"; else bad "決策節超大條目未偵測"; fi
if echo "$out" | grep -q "dossier-flag:.*最長行"; then bad "條目 fixture 不應觸發最長行 flag（每行 <1000B）"; else ok "條目 fixture 未誤觸發最長行 flag"; fi
# 定位：只報 bytes 不報位置時，agent 會預設「應該是我剛寫的那條」——多 session 並行改同一份
# dossier 時經常猜錯（krepo 2026-07-29 實證：猜錯兩次、白壓兩輪）。大條目在本 fixture 的第 7 行
if echo "$out" | grep -q "dossier-flag:.*最大條目.*在第 7 行"; then ok "條目 flag 帶正確行號（定位）"; else bad "條目 flag 缺行號或行號錯（實得：$(echo "$out" | grep '最大條目')）"; fi
# 手段提示：條目超標更常是粒度過粗（一條記多個決策），壓字壓不動
if echo "$out" | grep -q "拆成多條"; then ok "條目 flag 提示拆分而非壓字"; else bad "條目 flag 缺拆分提示"; fi

# 條目 bytes 同樣要剝哨兵：條目續行區含 fence 時每行虛胖 1 byte，足以把未超標的條目推過門檻
# （300 行 fence = +300B，650B 的條目就被誤判成 >800B）。fixture 調成「剝哨兵→不觸發、
# 不剝→觸發」，故拿掉條目 awk 的 sub(/^\001/) 就會紅——這是該防線唯一的守門
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 項目"; echo
  echo "## 關鍵決策（附理由）"
  echo "- 選了方案甲：理由見範例"
  echo '```yaml'
  awk 'BEGIN { for (r = 0; r < 300; r++) print "k" }'
  echo '```'; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*最大條目"; then bad "條目 bytes 因 fence 虛胖而誤觸發門檻（條目 awk 未剝哨兵；實得：$(echo "$out" | grep '最大條目')）"; else ok "條目 bytes 已剝哨兵（fence 續行不虛胖）"; fi

# ✅ 偵測的非錨定比對：`/✅/` 沒有行首錨點，哨兵中和不了它——fence 必須放在「進行中」節內
# 才測得到（既有 fence fixture 把圍欄放在決策節，in_sec=0 永遠踩不到這條路徑）。
# 圍欄內同時放假標題與 ✅：假標題被哨兵擋掉後不再切節，若沒 skip 哨兵行，in_sec 會一路
# 開著把圍欄內的 ✅ 全算進來（此為加哨兵後才出現的回歸方向）
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 還在做的項目"
  echo '```text'
  echo "## 已完成（里程碑）"
  echo "- ✅ 這是貼在圍欄內的範例／測試輸出，不是真的完成項"
  echo '```'
  echo; echo "## 關鍵決策（附理由）"; echo "- 選了 X 因為 Y"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*進行中.*✅"; then bad "「進行中」節內圍欄的 ✅ 被誤報為完成項（非錨定比對未 skip 哨兵行）"; else ok "「進行中」節內圍欄的 ✅ 不誤報（非錨定比對有 skip 哨兵）"; fi

# 分節 bytes 不得虛胖：剝 fence 的 \001 哨兵若在量長度時沒剝掉，每個 fenced 行多算 1 byte，
# 短行多的 fence（YAML/JSON/log 片段）會讓單節 bytes 超過全檔總量、百分比破 100%
# （實測曾出現 149%），兩節接近時足以造成排名倒轉——正是這功能要防的失效
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- x"; echo
  echo "## 關鍵決策（附理由）"; echo '```yaml'
  awk 'BEGIN { for (r = 0; r < 4000; r++) print "k: v" }'
  echo '```'; echo; echo "## 已完成（里程碑）"; echo "- ✅ 無"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
maxpct="$(echo "$out" | grep '^dossier-sections:' | grep -oE '\([0-9]+%\)' | tr -d '()%' | LC_ALL=C sort -rn | head -1)"
if [ -n "$maxpct" ] && [ "$maxpct" -le 100 ]; then ok "分節佔比不破 100%（哨兵長度已剝除，短行 fence 不虛胖）"; else bad "分節佔比異常或 dossier-sections 消失：maxpct=${maxpct:-<空>}（實得：$(echo "$out" | grep dossier-sections)）"; fi

# 第一個 ## 之前的前言不得被靜默丟棄：SKILL.md 要 agent 照這張表挑收斂對象，
# 殘量不現身時會把人導向兩個 4 bytes 的小節
{ echo "# 測試專案 STATUS"
  awk 'BEGIN { s = "前言填充"; for (i = 0; i < 20; i++) s = s "內容"; for (r = 0; r < 300; r++) print s }'
  echo; echo "## 進行中"; echo "- x"; echo; echo "## 關鍵決策（附理由）"; echo "- y"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -qE "^dossier-sections: \(前言/未分節\) [0-9]{4,}"; then ok "前言殘量現身於分節表（不靜默丟棄）"; else bad "前言 bytes 被丟棄，表格會誤導收斂對象（實得：$(echo "$out" | grep dossier-sections)）"; fi

# 行號 vs fenced block：剝 code fence 時若「丟棄」該行而非**前綴 \001 哨兵保留原行**，後續行號
# 全數位移、flag 指向錯的地方。fixture 讓真條目落在第 12 行、其前有 4 行 fenced（含假標題）
# ——完全丟棄式剝除會報第 8 行。本條守的是**行號對齊**；長度保留（分節佔比不被低估）由上面
# 那條 fence 佔比測試守，兩條分工不同、勿合併，也勿與更上面的無 fence 版合併
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 項目：還在做"; echo
  echo '```markdown'; echo "## 關鍵決策（附理由）"; echo "- fence 內的假條目"; echo '```'
  echo
  echo "## 關鍵決策（附理由）"
  awk 'BEGIN { s = "- 選了方案甲："; for (i = 0; i < 60; i++) s = s "理由與推導"; print s
               t = "  續行補充："; for (i = 0; i < 60; i++) t = t "更多細節"; print t }'; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*最大條目.*在第 12 行"; then ok "行號不受 fenced block 位移（哨兵前綴式剝除）"; else bad "fenced block 使行號位移（實得：$(echo "$out" | grep '最大條目')）"; fi

# 里程碑節超大條目（單行 872 bytes：>800 條目上限、<1000 最長行門檻）→ 條目 flag（一行化的機器面）
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 項目：還在做"; echo
  echo "## 已完成（里程碑）"
  awk 'BEGIN { s = "- ✅ 2026-07-01 大功告成："; for (i = 0; i < 70; i++) s = s "過程敘事"; print s }'; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*最大條目"; then ok "里程碑節散文條目 → 條目 flag（一行化機器面）"; else bad "里程碑超大條目未偵測"; fi

# 作用域反例：「進行中」的 >800 bytes 條目（spec 區合法偏大）不得觸發條目 flag
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"
  awk 'BEGIN { s = "- 工作項 spec："; for (i = 0; i < 70; i++) s = s "合約細節"; print s }'
  echo; echo "## 已完成（里程碑）"; echo "- ✅ 無"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*最大條目"; then bad "進行中的大條目誤觸發條目 flag（作用域應限決策/里程碑）"; else ok "進行中大條目未誤觸發（spec 區合法偏大）"; fi

# 簽章不符：STATUS.md 存在但非 dossier（撞名領域產物，無「進行中」章節）→ flag
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 爬蟲設定檢查表

## 站台清單
- site-a
- site-b
DOSSIER
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*簽章"; then ok "撞名非 dossier → 簽章不符 flag"; else bad "簽章不符未偵測"; fi

# 簽章假陽性防護：恰含「進行中」字樣標題的領域文件仍非 dossier（簽章需雙訊號——
# 誤放行會讓 spec/log 模式直接編輯領域文件，比誤攔截危險）
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 部署狀態看板

## 進行中的部署
- api-server v2 rolling update

## 機器清單
- host-a
DOSSIER
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*簽章"; then ok "僅含進行中字樣標題 → 仍判簽章不符（雙訊號）"; else bad "簽章假陽性：單訊號誤認 dossier"; fi

# 簽章需標題語意錨定：兩個訊號都被「子字串」命中的領域看板（進行中的部署/已完成的部署）
# 仍非 dossier——章節名必須是標題結尾，不是任意子字串
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 部署狀態看板

## 進行中的部署
- api-server v2 rolling update

## 已完成的部署
- web v1
DOSSIER
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*簽章"; then ok "雙訊號皆子字串命中 → 仍判簽章不符（端錨定）"; else bad "簽章假陽性：子字串比對誤認 dossier"; fi

# fenced code block 內的範例標題不算章節
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 工具說明文件

```markdown
## 進行中
## 已完成(里程碑)
```

## 使用方式
- 照上面範例寫
DOSSIER
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*簽章"; then ok "fenced 範例標題 → 仍判簽章不符（剝圍欄）"; else bad "簽章假陽性：fenced 範例標題誤認 dossier"; fi

# 巢狀圍欄（CommonMark：closer 須同字元且長度 ≥ opener）：四反引號外層包三反引號範例，
# 內層 ``` 不得誤判關欄——否則範例標題洩出、簽章誤放行
cat > "$TMP/ds-work/STATUS.md" <<'DOSSIER'
# 工具說明文件

````markdown
範例模板：
```
## 進行中
## 已完成(里程碑)
```
````

## 使用方式
- 照上面範例寫
DOSSIER
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*簽章"; then ok "巢狀圍欄範例 → 仍判簽章不符（opener 字元/長度追蹤）"; else bad "簽章假陽性：內層三反引號誤關外層四反引號圍欄"; fi

# 過期：STATUS.md 最後 commit 落後 repo 活動 > 30 天 → flag
# （固定舊日期使 lag 恆 >30 天，不依賴執行當日）
git init -q -b main "$TMP/ds-stale"
(cd "$TMP/ds-stale" \
    && printf '# STATUS\n\n## 進行中\n- 舊項目\n' > STATUS.md \
    && "${GITC[@]}" add STATUS.md \
    && GIT_AUTHOR_DATE='2026-01-01T00:00:00' GIT_COMMITTER_DATE='2026-01-01T00:00:00' \
       "${GITC[@]}" commit -qm "docs: old dossier" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm "feat: recent work" \
    && git init --bare -q "$TMP/ds-stale-origin.git" \
    && git remote add origin "$TMP/ds-stale-origin.git" && git push -qu origin main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-stale")"
if echo "$out" | grep -q "dossier-flag:.*落後 repo 活動"; then ok "STATUS.md 落後 repo 活動 >30 天 → 過期 flag"; else bad "過期未偵測"; fi

echo "▶ 9b. branch-first.sh 情況 A/B 判定與救援序列"
BF_SCRIPT="$ROOT/claude/skills/project/scripts/branch-first.sh"

git init --bare -q "$TMP/bf-origin.git"
git init -q -b main "$TMP/bf-work"
(cd "$TMP/bf-work" \
    && echo base > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/bf-origin.git" && git push -qu origin main)

# 情況 A：在 main、working tree 有未 commit 變更、無誤 commit → switch -c，變更跟隨
echo dirty > "$TMP/bf-work/wip.txt"
out="$("$BF_SCRIPT" "$TMP/bf-work" feat/a)"
assert_rc "情況 A → exit 0" 0 $?
if echo "$out" | grep -q "case: A" && echo "$out" | grep -q "verdict: OK"; then ok "情況 A 判定 + OK"; else bad "情況 A 判定錯誤（${out}）"; fi
assert_eq "情況 A 後 HEAD 在 feature branch" "feat/a" "$(git -C "$TMP/bf-work" symbolic-ref --short HEAD)"
if [ -f "$TMP/bf-work/wip.txt" ]; then ok "情況 A working tree 變更跟隨"; else bad "情況 A 弄丟 working tree 變更"; fi
assert_eq "情況 A main 未動（== origin/main）" \
    "$(git -C "$TMP/bf-work" rev-parse origin/main)" "$(git -C "$TMP/bf-work" rev-parse main)"
(cd "$TMP/bf-work" && rm wip.txt && git switch -q main && git branch -qD feat/a)

# 情況 B：誤 commit 在本地 main（未 push）、tree clean → branch 保住 → switch → branch -f 退回
(cd "$TMP/bf-work" && echo v2 > f.txt && "${GITC[@]}" commit -qam "oops: on main")
out="$("$BF_SCRIPT" "$TMP/bf-work" feat/b)"
assert_rc "情況 B → exit 0" 0 $?
if echo "$out" | grep -q "case: B" && echo "$out" | grep -q "verdict: OK"; then ok "情況 B 判定 + OK"; else bad "情況 B 判定錯誤（${out}）"; fi
assert_eq "情況 B 後 HEAD 在 feature branch" "feat/b" "$(git -C "$TMP/bf-work" symbolic-ref --short HEAD)"
assert_eq "情況 B feature branch 接住 1 commit" "1" \
    "$(git -C "$TMP/bf-work" rev-list --count origin/main..feat/b)"
assert_eq "情況 B main 已退回 origin/main" \
    "$(git -C "$TMP/bf-work" rev-parse origin/main)" "$(git -C "$TMP/bf-work" rev-parse main)"
(cd "$TMP/bf-work" && git switch -q main && git branch -qD feat/b)

# mixed state：誤 commit + working tree 另有未 commit 檔 → 救援後未 commit 檔完好（H6 核心斷言）
(cd "$TMP/bf-work" && echo v3 > f.txt && "${GITC[@]}" commit -qam "oops2: on main" && echo precious > notes.txt)
out="$("$BF_SCRIPT" "$TMP/bf-work" feat/c)"
assert_rc "mixed state → exit 0" 0 $?
if echo "$out" | grep -q "case: B"; then ok "mixed state 判為情況 B"; else bad "mixed state 判定錯誤"; fi
assert_eq "mixed state 未 commit 檔完好無損" "precious" "$(cat "$TMP/bf-work/notes.txt" 2>/dev/null)"
if echo "$out" | grep -q "verify: porcelain 前後一致"; then ok "mixed state 附 porcelain 前後快照驗證"; else bad "缺 porcelain 快照驗證行"; fi
assert_eq "mixed state main 已退回 origin/main" \
    "$(git -C "$TMP/bf-work" rev-parse origin/main)" "$(git -C "$TMP/bf-work" rev-parse main)"
(cd "$TMP/bf-work" && rm notes.txt && git switch -q main && git branch -qD feat/c)

# detached HEAD（其上有 commit）→ 情況 A：switch -c 一併接走 commit，不需 ref 重置
git clone -q "$TMP/bf-origin.git" "$TMP/bf-detach"
(cd "$TMP/bf-detach" && git checkout -q --detach && echo dh > d.txt && "${GITC[@]}" add d.txt && "${GITC[@]}" commit -qm "on detached")
out="$("$BF_SCRIPT" "$TMP/bf-detach" feat/dh)"
assert_rc "detached HEAD → exit 0" 0 $?
if echo "$out" | grep -q "case: A"; then ok "detached HEAD 判為情況 A"; else bad "detached HEAD 判定錯誤（${out}）"; fi
assert_eq "detached 後 HEAD 在 feature branch" "feat/dh" "$(git -C "$TMP/bf-detach" symbolic-ref --short HEAD)"
assert_eq "detached commit 被 feature branch 接走" "1" \
    "$(git -C "$TMP/bf-detach" rev-list --count origin/main..feat/dh)"

# branch 撞名 → STOP、不動任何狀態
(cd "$TMP/bf-work" && git branch feat/exists && echo dirty2 > wip2.txt)
out="$("$BF_SCRIPT" "$TMP/bf-work" feat/exists)"
assert_rc "branch 撞名 → exit 1" 1 $?
if echo "$out" | grep -q "verdict: STOP"; then ok "撞名 → STOP"; else bad "撞名未 STOP"; fi
assert_eq "撞名後仍在 main（未半途執行）" "main" "$(git -C "$TMP/bf-work" symbolic-ref --short HEAD)"
(cd "$TMP/bf-work" && rm wip2.txt && git branch -qD feat/exists)

# 已在 feature branch（非 default）→ STOP（無事可做，不疊 branch）
(cd "$TMP/bf-work" && git switch -qc feat/other)
out="$("$BF_SCRIPT" "$TMP/bf-work" feat/d)"
assert_rc "非 default branch → exit 1" 1 $?
if echo "$out" | grep -q "verdict: STOP"; then ok "已在 feature branch → STOP"; else bad "非 default 未 STOP"; fi
if git -C "$TMP/bf-work" show-ref --verify -q refs/heads/feat/d; then bad "STOP 卻建了 branch"; else ok "STOP 未建 branch"; fi
(cd "$TMP/bf-work" && git switch -q main && git branch -qD feat/other)

# 分岔（remote default 已被他人推進、本地 main 另有誤 commit）→ ambiguous → STOP、零 mutation
git clone -q "$TMP/bf-origin.git" "$TMP/bf-push2"
(cd "$TMP/bf-push2" && echo other > g.txt && "${GITC[@]}" add g.txt && "${GITC[@]}" commit -qm "other work" && git push -q origin main)
(cd "$TMP/bf-work" && echo v4 > f.txt && "${GITC[@]}" commit -qam "local oops" && git fetch -q origin)
bf_main_before="$(git -C "$TMP/bf-work" rev-parse main)"
out="$("$BF_SCRIPT" "$TMP/bf-work" feat/e)"
assert_rc "分岔 → exit 1" 1 $?
if echo "$out" | grep -q "verdict: STOP"; then ok "分岔 → STOP（交回使用者）"; else bad "分岔未 STOP（${out}）"; fi
assert_eq "分岔 STOP 後 main ref 未動" "$bf_main_before" "$(git -C "$TMP/bf-work" rev-parse main)"
if git -C "$TMP/bf-work" show-ref --verify -q refs/heads/feat/e; then bad "分岔 STOP 卻建了 branch"; else ok "分岔 STOP 未建 branch"; fi

# 無 remote → STOP（無法核對誤 commit 是否已被 remote 涵蓋 → ambiguous；驗原因避免
# 未來 STOP 換理由時假綠）
out="$("$BF_SCRIPT" "$TMP/gh-local" feat/x)"
assert_rc "無 remote → exit 1" 1 $?
if echo "$out" | grep -q "verdict: STOP（無 remote"; then ok "無 remote → STOP（含原因）"; else bad "無 remote 未 STOP 或原因缺失"; fi

# 非 git repo / 用法錯誤
"$BF_SCRIPT" "$TMP/not-a-repo" feat/x >/dev/null 2>&1
assert_rc "非 git repo → exit 1" 1 $?
"$BF_SCRIPT" >/dev/null 2>&1
assert_rc "無引數 → exit 2" 2 $?
"$BF_SCRIPT" "$TMP/bf-work" >/dev/null 2>&1
assert_rc "缺 branch 名 → exit 2" 2 $?
"$BF_SCRIPT" "$TMP/bf-work" "bad..name" >/dev/null 2>&1
assert_rc "非法 branch 名 → exit 2" 2 $?

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

out="$("$RRC_SCRIPT" "$TMP/rrc-work" "$RRC_EMPTY_TREE..HEAD" --autofix)"
if echo "$out" | grep -q "^resolved-base-type: tree$" && echo "$out" | grep -q "^baseline-range: yes$" \
    && echo "$out" | grep -q "^base-is-ancestor: yes$" && echo "$out" | grep -q "^autofix-safe: yes$"; then
    ok "empty-tree baseline range 支援 autofix（base-is-ancestor yes）"
else bad "empty-tree baseline range 輸出錯誤"; fi

out="$("$RRC_SCRIPT" "$TMP/rrc-work" 'HEAD~1^{tree}..HEAD' --autofix)"
if echo "$out" | grep -q "^resolved-base-type: tree$" && echo "$out" | grep -q "^base-is-ancestor: n/a$" \
    && echo "$out" | grep -q "^autofix-safe: no$" && echo "$out" | grep -q "^autofix-reason: base-not-commit$"; then
    ok "任意 tree base → autofix 擋（base-not-commit）"
else bad "非 empty-tree base 誤通過 autofix"; fi

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
if grep -q "Historical-only guidance is discovered" "$ROOT/codex/skills/repo-review/evals.md" \
    && grep -q "No-findings wording coexists with autofix history" "$ROOT/codex/skills/repo-review/evals.md"; then
    ok "repo-review v2 evals 覆蓋 historical guidance 與 autofix clean output"
else bad "repo-review v2 behavior evals 不完整"; fi
if grep -q "Fresh reviewers inherit no parent history" "$ROOT/codex/skills/repo-review/evals.md" \
    && grep -q "Arbitrary tree base blocks autofix" "$ROOT/codex/skills/repo-review/evals.md" \
    && grep -q "Later autofix rounds validate owned dirty state" "$ROOT/codex/skills/repo-review/evals.md"; then
    ok "repo-review GPT-5.6 evals 覆蓋 fresh context 與 autofix safety"
else bad "repo-review GPT-5.6 behavior evals 不完整"; fi
if grep -q "Review-pass position stays private" "$ROOT/codex/skills/repo-review/evals.md" \
    && grep -q "Checkpoint metadata does not reveal review progress" "$ROOT/codex/skills/repo-review/evals.md"; then
    ok "repo-review evals 覆蓋輪次隔離與 metadata 洩漏"
else bad "repo-review 盲審 behavior evals 不完整"; fi
if grep -q "Round-cap diagnosis follows root-cause history" "$ROOT/codex/skills/repo-review/evals.md" \
    && grep -q "Do not infer an architectural problem or recommend a rewrite from the cap alone" "$ROOT/codex/skills/repo-review/SKILL.md"; then
    ok "repo-review evals 覆蓋輪次上限的收斂診斷"
else bad "repo-review 收斂診斷 behavior contract 不完整"; fi
if [ -f "$ROOT/codex/skills/repo-review/references/reviewer-brief.md" ] \
    && grep -q "references/reviewer-brief.md" "$ROOT/codex/skills/repo-review/SKILL.md"; then
    ok "repo-review reviewer brief 已納入 runtime contract"
else bad "repo-review reviewer brief 缺失或未連結"; fi

echo "▶ 13. handoff-anchor.sh 錨點驗證與生命週期判定"
HA_SCRIPT="$ROOT/claude/skills/handoff/scripts/handoff-anchor.sh"
# 錨點記的是 `rev-parse --show-toplevel`，會解析 symlink（macOS 的 $TMPDIR 走 /var → /private/var），
# 故路徑期望值用解析後的形式；Linux 的 /tmp 無 symlink，兩者相同
HA_REAL="$(cd "$TMP" && pwd -P)"

# fixture：單 repo，1 commit
git init -q -b main "$TMP/ha-work"
(cd "$TMP/ha-work" && echo v1 > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init)

# anchors：格式與 dirty 計數
echo dirty > "$TMP/ha-work/untracked.txt"
out="$("$HA_SCRIPT" anchors "$TMP/ha-work")"
assert_rc "anchors 正常 repo → exit 0" 0 $?
if echo "$out" | grep -q "^created: " && echo "$out" | grep -q "^anchor: $HA_REAL/ha-work main .* dirty=1$"; then
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

# anchors：相對路徑／repo 子目錄輸入 → 錨點記 toplevel 絕對路徑。原樣記 `.` 的話，cwd 已不同的
# 新 session 會 verify 到別的 repo，且誤報成 DIVERGED「歷史改寫」（真相是路徑錯）→ 整份降級
mkdir -p "$TMP/ha-work/sub"
out="$(cd "$TMP/ha-work/sub" && "$HA_SCRIPT" anchors .)"
assert_rc "anchors 子目錄相對路徑 → exit 0" 0 $?
if echo "$out" | grep -q "^anchor: $HA_REAL/ha-work main "; then
    ok "相對路徑/子目錄輸入 → 錨點記 toplevel 絕對路徑"
else bad "錨點未正規化為 toplevel 絕對路徑（${out}）"; fi

# 空白檢查對解析後的 toplevel 而非原輸入——相對輸入本身無空白、toplevel 卻含空白時仍須擋下
out="$(cd "$TMP/ha spaced" && "$HA_SCRIPT" anchors . 2>&1)"
assert_rc "anchors 相對輸入但 toplevel 含空白 → exit 1" 1 $?
if ! echo "$out" | grep -q "^anchor: " && echo "$out" | grep -q "含空白"; then
    ok "含空白 toplevel 經相對路徑輸入仍被擋"
else bad "相對路徑繞過了 toplevel 空白檢查（${out}）"; fi

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

# list：path 行（verify/consume 吃完整路徑，讀取端不必手拼）與 title 行（多份待選時只看 slug
# 分不出是哪條工作線）；無標題行的檔整行省略，不留空欄位
printf -- '---\ncreated: %s\n---\n# Handoff: 訂單重試強化\n' "$(date +%Y-%m-%d)" > "$TMP/ha-handoffs/titled.md"
out="$("$HA_SCRIPT" list "$TMP/ha-handoffs")"
if echo "$out" | grep -q "^  path: .*/ha-handoffs/titled.md$"; then ok "list 印完整 path 行"; else bad "list 缺 path 行"; fi
if echo "$out" | grep -q "^  title: 訂單重試強化$"; then ok "list 印 title 行"; else bad "list 缺 title 行"; fi
assert_eq "無標題行的檔不印 title" "1" "$(echo "$out" | grep -c '^  title: ')"
rm "$TMP/ha-handoffs/titled.md"

# --- find-predecessor（W1 判首輪/續寫：依 slug 精確定位前一份）---
# 關鍵迴歸：`archive/*-<slug>.md` 的尾錨定擋不住中間的工作線名——查 foo 會命中 bar-foo，
# 且 tail -1 剛好選它（時戳較新、字典序在後）。同一處定位邏輯被三輪第三方審查逐輪擠，
# 這節把「精確比對」釘死。DO NOT relax these back into a glob.
FP="$TMP/ha-fp"; mkdir -p "$FP/archive"
fp_mk() { printf -- '---\nslug: %s\ncreated: 2026-08-01\n---\n# Handoff: %s\n' "$2" "$2" > "$FP/$1"; }
# bar-foo 的時戳**必須最新**，否則 glob 實作的 tail -1 也會剛好答對，斷言就沒有鑑別力
# （同「守門測試的命中點要放在逼得出缺陷的位置」那條教訓）
fp_mk "archive/20260804-120000-bar-foo.md" "bar-foo"
fp_mk "archive/20260801-090000-foo.md" "foo"
fp_mk "archive/20260803-100000-foo.md" "foo"

out="$("$HA_SCRIPT" find-predecessor foo "$FP")"
assert_rc "find-predecessor 命中 → exit 0" 0 $?
assert_eq "後綴同名的別條工作線不得誤中（bar-foo vs foo），且取同 slug 最新一份" \
    "$FP/archive/20260803-100000-foo.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"
if echo "$out" | grep -q "^location: archive"; then ok "命中 archive 標 location"; else bad "location 標記錯誤"; fi

out="$("$HA_SCRIPT" find-predecessor bar-foo "$FP")"
assert_eq "查較長的工作線名照樣精確" \
    "$FP/archive/20260804-120000-bar-foo.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"

# active 未消費者優先（它比 archive 任何一輪都新）
fp_mk "foo.md" "foo"
out="$("$HA_SCRIPT" find-predecessor foo "$FP")"
assert_eq "active 未消費的同 slug 優先於 archive" "$FP/foo.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"

# 檔名對得上但檔內 slug 不符 → 不採用（手改過的殘檔不得被撿）
printf -- '---\nslug: someone-else\n---\n' > "$FP/archive/20260804-110000-mismatch.md"
out="$("$HA_SCRIPT" find-predecessor mismatch "$FP")"
if echo "$out" | grep -q "predecessor: NONE"; then ok "檔內 slug 與檔名不符 → 不採用"; else bad "採用了 slug 不符的檔"; fi

# 無命中＝首輪，是正常結果不是錯誤
out="$("$HA_SCRIPT" find-predecessor brand-new "$FP")"
assert_rc "find-predecessor 無命中 → exit 0（首輪是正常結果）" 0 $?
if echo "$out" | grep -q "predecessor: NONE"; then ok "無命中印 NONE"; else bad "無命中輸出錯誤"; fi

# slug 含 glob 字元 → 不做 pathname expansion（slug 已不進 glob）
out="$("$HA_SCRIPT" find-predecessor '*' "$FP")"
if echo "$out" | grep -q "predecessor: NONE"; then ok "slug 含 glob 字元不誤匹配"; else bad "glob 字元被展開"; fi

"$HA_SCRIPT" find-predecessor >/dev/null 2>&1
assert_rc "find-predecessor 無引數 → exit 2" 2 $?
"$HA_SCRIPT" find-predecessor foo "$TMP/no-such-dir" >/dev/null
assert_rc "find-predecessor 目錄不存在 → exit 0" 0 $?

out="$("$HA_SCRIPT" list "$TMP/no-such-dir")"
assert_rc "list 目錄不存在 → exit 0（回報 NONE）" 0 $?
if echo "$out" | grep -q "handoffs: NONE"; then ok "list 無目錄 → NONE"; else bad "list 無目錄輸出錯誤"; fi

# --- consume 子指令（R4 消費歸檔：驗位置 → mkdir archive → mv 加秒級時戳前綴 → 印 archived:）---

printf -- '---\ncreated: %s\n---\n# Handoff: c\n' "$(date +%Y-%m-%d)" > "$TMP/ha-handoffs/consume-me.md"
out="$("$HA_SCRIPT" consume "$TMP/ha-handoffs/consume-me.md")"
assert_rc "consume 正常 → exit 0" 0 $?
archived_path="$(echo "$out" | sed -n 's/^archived: //p')"
if [ -n "$archived_path" ] && [ -f "$archived_path" ]; then ok "consume 印 archived: 行且檔案已落 archive"; else bad "consume 未印 archived: 或檔案不存在（${out}）"; fi
if [ ! -f "$TMP/ha-handoffs/consume-me.md" ]; then ok "consume 後 active 原檔已移走"; else bad "consume 後原檔仍留在 active"; fi
case "$(basename "${archived_path:-x}")" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-consume-me.md)
        ok "archive 檔名帶 YYYYMMDD-HHMMSS 前綴（同日同 slug 二次消費不互覆）" ;;
    *)  bad "archive 檔名前綴格式錯誤（${archived_path}）" ;;
esac

# 重複消費（檔案已在 archive 內）→ 拒絕，不動檔案
out="$("$HA_SCRIPT" consume "$archived_path" 2>&1)"
assert_rc "consume archive 內檔案 → exit 1" 1 $?
if echo "$out" | grep -q "已在 archive"; then ok "重複消費 → 拒絕（已在 archive）"; else bad "重複消費未被拒（${out}）"; fi
if [ -f "$archived_path" ]; then ok "拒絕後 archive 檔原地不動"; else bad "拒絕路徑動到了 archive 檔"; fi

"$HA_SCRIPT" consume "$TMP/ha-handoffs/no-such.md" >/dev/null 2>&1
assert_rc "consume 不存在檔案 → exit 1" 1 $?
"$HA_SCRIPT" consume >/dev/null 2>&1
assert_rc "consume 無引數 → exit 2" 2 $?

# 同秒碰撞防覆蓋（-e 前置檢查的迴歸守衛）：date stub 固定時戳，連續消費兩份同名檔
# → 第二次 exit 1、archive 檔內容不變、第二份仍留在 active
mkdir -p "$TMP/datestub"
# shellcheck disable=SC2016  # stub 內容刻意不展開（$1/$@ 屬 stub 自身）
printf '#!/bin/sh\n[ "$1" = "+%%Y%%m%%d-%%H%%M%%S" ] && { echo 20990101-000000; exit 0; }\nexec /bin/date "$@"\n' > "$TMP/datestub/date"
chmod +x "$TMP/datestub/date"
printf 'first\n' > "$TMP/ha-handoffs/same.md"
PATH="$TMP/datestub:$PATH" "$HA_SCRIPT" consume "$TMP/ha-handoffs/same.md" >/dev/null
assert_rc "date stub 第一次 consume → exit 0" 0 $?
printf 'second\n' > "$TMP/ha-handoffs/same.md"
PATH="$TMP/datestub:$PATH" "$HA_SCRIPT" consume "$TMP/ha-handoffs/same.md" >/dev/null 2>&1
assert_rc "同秒同名第二次 consume → exit 1（拒絕覆蓋）" 1 $?
assert_eq "碰撞拒絕後 archive 檔內容不變" "first" "$(cat "$TMP/ha-handoffs/archive/20990101-000000-same.md")"
if [ -f "$TMP/ha-handoffs/same.md" ]; then ok "碰撞拒絕後第二份仍在 active"; else bad "碰撞拒絕卻弄丟 active 檔"; fi
rm "$TMP/ha-handoffs/same.md"

# 已消費偵測用「工具不變量」（直接父目錄 archive／檔名時戳前綴），不掃整條路徑——
# 祖先目錄剛好叫 archive 的合法 active 檔不得誤拒（如 /srv/archive/<user>/handoffs/x.md）
mkdir -p "$TMP/archive/alice/handoffs"
printf 'legit\n' > "$TMP/archive/alice/handoffs/task.md"
out="$("$HA_SCRIPT" consume "$TMP/archive/alice/handoffs/task.md")"
assert_rc "祖先名 archive 的合法 active 檔 → 照常消費 exit 0" 0 $?
arch2="$(echo "$out" | sed -n 's/^archived: //p')"
if [ -n "$arch2" ] && [ -f "$arch2" ]; then ok "祖先名 archive 不誤拒（檔已正常歸檔）"; else bad "祖先名 archive 被誤拒或未歸檔（${out}）"; fi

# 檔名已帶時戳前綴（曾被工具歸檔，即使被手工搬進巢狀子目錄）→ 拒絕，原地不動
mkdir -p "$TMP/ha-handoffs/archive/sub"
printf 'old\n' > "$TMP/ha-handoffs/archive/sub/20990101-000000-nested.md"
out="$("$HA_SCRIPT" consume "$TMP/ha-handoffs/archive/sub/20990101-000000-nested.md" 2>&1)"
assert_rc "時戳前綴檔（巢狀位置）→ exit 1" 1 $?
if echo "$out" | grep -q "已消費"; then ok "時戳前綴 → 拒絕（不變量認得曾歸檔）"; else bad "時戳前綴未被拒（${out}）"; fi
if [ -f "$TMP/ha-handoffs/archive/sub/20990101-000000-nested.md" ]; then ok "前綴拒絕後檔案原地不動"; else bad "前綴拒絕卻動了檔案"; fi
rm -rf "$TMP/ha-handoffs/archive/sub"

# date 失敗 → 拒絕歸檔（不產生 archive/-<name> 這種無時戳檔名）
mkdir -p "$TMP/datefail"
printf '#!/bin/sh\nexit 1\n' > "$TMP/datefail/date"
chmod +x "$TMP/datefail/date"
printf 'keep\n' > "$TMP/ha-handoffs/df.md"
PATH="$TMP/datefail:$PATH" "$HA_SCRIPT" consume "$TMP/ha-handoffs/df.md" >/dev/null 2>&1
assert_rc "date 失敗 → exit 1（拒絕歸檔）" 1 $?
if [ -f "$TMP/ha-handoffs/df.md" ]; then ok "date 失敗後交接檔仍在 active"; else bad "date 失敗卻動了交接檔"; fi
rm "$TMP/ha-handoffs/df.md"

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
# helper 部署失敗（codex C2）：終判不得仍是 ✅——自動化只讀終判會誤認部署成功
ecs_out="$(FAKE_RESULT="$(printf '⚠️ 無法建立 symlink x\nOK_HELPER_WARN\n')" bash "$ecs_report" hostE 2>&1)"
if printf '%s\n' "$ecs_out" | grep -q '✅ hostE'; then
    bad "helper 失敗仍判 ✅（部署失敗被誤報成功）"
else
    ok "helper 失敗不判 ✅"
fi
if printf '%s\n' "$ecs_out" | grep -q '⚠️.*hostE'; then ok "helper 失敗 → 終判 ⚠️"; else bad "helper 失敗無 ⚠️ 終判"; fi
# C3（codex）：↩ 還原告知也要撈出——操作者須知道原 guidance 已恢復，避免不必要的人工復原
ecs_out="$(FAKE_RESULT="$(printf '⚠️ 無法建立 symlink x\n↩ 已還原原檔 x\nOK_HELPER_WARN\n')" bash "$ecs_report" hostF 2>&1)"
if printf '%s\n' "$ecs_out" | grep -q 'hostF: ↩'; then ok "↩ 還原告知冠主機名撈出"; else bad "↩ 還原告知被摘要 grep 丟棄"; fi

echo "▶ 18b. ensure-codex-guidance.sh 幂等連結全域 Codex guidance"
ECG="$ROOT/scripts/ensure-codex-guidance.sh"
ecg="$TMP/ecg"
mkdir -p "$ecg/source" "$ecg/codex"
echo "# managed guidance" > "$ecg/source/AGENTS.md"
echo "# local guidance" > "$ecg/codex/AGENTS.md"

# 既有實體檔必須備份後接管，且備份區位於 Codex home 外。
SOURCE_FILE="$ecg/source/AGENTS.md" CODEX_DIR="$ecg/codex" BACKUP_ROOT="$ecg/backup" bash "$ECG"
assert_rc "guidance 實體檔接管 → exit 0" 0 $?
if [ -L "$ecg/codex/AGENTS.md" ]; then ok "guidance 目的地已換成 symlink"; else bad "guidance 目的地不是 symlink"; fi
assert_eq "guidance symlink 指向版控來源" "$ecg/source/AGENTS.md" "$(readlink "$ecg/codex/AGENTS.md")"
if grep -rq 'local guidance' "$ecg/backup" 2>/dev/null; then ok "既有全域 guidance 已備份"; else bad "既有全域 guidance 未備份"; fi
if [ "$(dirname "$ecg/backup")" != "$ecg/codex" ]; then ok "guidance 備份區在 Codex home 外"; else bad "guidance 備份留在 Codex home"; fi

# 錯誤 symlink 可替換；正確 symlink 重跑保持 inode 不變。
mkdir -p "$ecg/other" && echo wrong > "$ecg/other/AGENTS.md"
ln -sfn "$ecg/other/AGENTS.md" "$ecg/codex/AGENTS.md"
SOURCE_FILE="$ecg/source/AGENTS.md" CODEX_DIR="$ecg/codex" BACKUP_ROOT="$ecg/backup" bash "$ECG"
assert_eq "錯誤 guidance symlink 已替換" "$ecg/source/AGENTS.md" "$(readlink "$ecg/codex/AGENTS.md")"
ecg_before="$(ecs_inode "$ecg/codex/AGENTS.md")"
SOURCE_FILE="$ecg/source/AGENTS.md" CODEX_DIR="$ecg/codex" BACKUP_ROOT="$ecg/backup" bash "$ECG"
ecg_after="$(ecs_inode "$ecg/codex/AGENTS.md")"
assert_eq "guidance helper 重跑幂等" "$ecg_before" "$ecg_after"

# CODEX_HOME override、來源缺失、ln 失敗皆有明確契約。
mkdir -p "$ecg/codex-home"
SOURCE_FILE="$ecg/source/AGENTS.md" CODEX_HOME="$ecg/codex-home" BACKUP_ROOT="$ecg/home-backup" bash "$ECG"
assert_eq "CODEX_HOME override 生效" "$ecg/source/AGENTS.md" "$(readlink "$ecg/codex-home/AGENTS.md")"
SOURCE_FILE="$ecg/missing.md" CODEX_DIR="$ecg/missing-codex" bash "$ECG"
assert_rc "guidance 來源不存在 → exit 0" 0 $?
if [ ! -e "$ecg/missing-codex" ]; then ok "來源不存在不建立 Codex home"; else bad "來源不存在卻建立 Codex home"; fi
mkdir -p "$ecg/fail-codex" "$ecg/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$ecg/bin/ln"
chmod +x "$ecg/bin/ln"
ecg_out="$(PATH="$ecg/bin:$PATH" SOURCE_FILE="$ecg/source/AGENTS.md" CODEX_DIR="$ecg/fail-codex" BACKUP_ROOT="$ecg/fail-backup" bash "$ECG" 2>&1)"
ecg_rc=$?
assert_rc "guidance ln 失敗 → exit 非 0" 1 "$ecg_rc"
if printf '%s\n' "$ecg_out" | grep -q '⚠️'; then ok "guidance ln 失敗印警告"; else bad "guidance ln 失敗無警告"; fi
# ln 失敗且原檔已被搬去備份 → 必須還原，原有 guidance 不得從生效位置消失（codex C2）
mkdir -p "$ecg/restore-codex"
echo "# precious guidance" > "$ecg/restore-codex/AGENTS.md"
PATH="$ecg/bin:$PATH" SOURCE_FILE="$ecg/source/AGENTS.md" CODEX_DIR="$ecg/restore-codex" \
    BACKUP_ROOT="$ecg/restore-backup" bash "$ECG" >/dev/null 2>&1
assert_rc "既有實體檔 + ln 失敗 → exit 1" 1 $?
if [ -f "$ecg/restore-codex/AGENTS.md" ] && grep -q 'precious guidance' "$ecg/restore-codex/AGENTS.md"; then
    ok "ln 失敗後原檔已還原（guidance 不消失）"
else
    bad "ln 失敗後原檔消失（僅剩備份）"
fi

for wiring_file in setup-mac-env.sh setup-linux-env.sh scripts/dotfiles-sync.sh; do
    if grep -q 'ensure-codex-guidance.sh' "$ROOT/$wiring_file"; then
        ok "$wiring_file 已接上 Codex guidance helper"
    else
        bad "$wiring_file 未接上 Codex guidance helper"
    fi
done
for setup_file in setup-mac-env.sh setup-linux-env.sh; do
    # shellcheck disable=SC2016  # 刻意比對 setup 原始碼中的字面 $SCRIPT_DIR，不在測試 shell 展開
    if grep -q 'DOTFILES_DIR="$SCRIPT_DIR" bash "$SCRIPT_DIR/scripts/ensure-codex-guidance.sh"' "$ROOT/$setup_file"; then
        ok "$setup_file 以實際 clone 路徑部署 guidance"
    else
        bad "$setup_file 未把實際 clone 路徑傳給 guidance helper"
    fi
done

echo "▶ 18c. ensure-lftprc.sh 幂等連結 ~/.lftprc（含 .lftprc.local 契約）"
ELR="$ROOT/scripts/ensure-lftprc.sh"
elr="$TMP/elr"
mkdir -p "$elr/source" "$elr/home"
echo "# managed lftprc" > "$elr/source/lftprc"
echo "# my own lftprc" > "$elr/home/.lftprc"

# 既有實體檔必須備份後接管，不得直接刪除使用者設定。
SOURCE_FILE="$elr/source/lftprc" TARGET_HOME="$elr/home" BACKUP_ROOT="$elr/backup" bash "$ELR" >/dev/null
assert_rc "lftprc 實體檔接管 → exit 0" 0 $?
if [ -L "$elr/home/.lftprc" ]; then ok "lftprc 目的地已換成 symlink"; else bad "lftprc 目的地不是 symlink"; fi
assert_eq "lftprc symlink 指向版控來源" "$elr/source/lftprc" "$(readlink "$elr/home/.lftprc")"
if grep -rq 'my own lftprc' "$elr/backup" 2>/dev/null; then ok "既有 lftprc 已備份"; else bad "既有 lftprc 未備份"; fi
# lftprc 結尾 source ~/.lftprc.local，缺檔會讓 lftp 每次啟動印錯誤
if [ -f "$elr/home/.lftprc.local" ]; then ok "已自動建立 .lftprc.local"; else bad "未建立 .lftprc.local"; fi

# .lftprc.local 是使用者的機器特定設定——重跑絕不可清空
echo "set net:timeout 99" > "$elr/home/.lftprc.local"
SOURCE_FILE="$elr/source/lftprc" TARGET_HOME="$elr/home" BACKUP_ROOT="$elr/backup" bash "$ELR" >/dev/null
if grep -q 'net:timeout 99' "$elr/home/.lftprc.local"; then ok "重跑不覆寫既有 .lftprc.local"; else bad "重跑清空了 .lftprc.local"; fi

# symlink 已正確時的早退路徑仍須補回被刪掉的 .lftprc.local（易漏）
rm -f "$elr/home/.lftprc.local"
SOURCE_FILE="$elr/source/lftprc" TARGET_HOME="$elr/home" BACKUP_ROOT="$elr/backup" bash "$ELR" >/dev/null
if [ -f "$elr/home/.lftprc.local" ]; then ok "symlink 已正確時仍補回 .lftprc.local"; else bad "早退路徑跳過 .lftprc.local"; fi

# 錯誤 symlink 可替換；正確 symlink 重跑保持 inode 不變。
mkdir -p "$elr/other" && echo wrong > "$elr/other/lftprc"
ln -sfn "$elr/other/lftprc" "$elr/home/.lftprc"
SOURCE_FILE="$elr/source/lftprc" TARGET_HOME="$elr/home" BACKUP_ROOT="$elr/backup" bash "$ELR" >/dev/null
assert_eq "錯誤 lftprc symlink 已替換" "$elr/source/lftprc" "$(readlink "$elr/home/.lftprc")"
elr_before="$(ecs_inode "$elr/home/.lftprc")"
SOURCE_FILE="$elr/source/lftprc" TARGET_HOME="$elr/home" BACKUP_ROOT="$elr/backup" bash "$ELR" >/dev/null
elr_after="$(ecs_inode "$elr/home/.lftprc")"
assert_eq "lftprc helper 重跑幂等" "$elr_before" "$elr_after"

# 來源不存在（舊 clone 尚未 pull 到 lftprc）→ 靜默 exit 0，不留半成品
mkdir -p "$elr/empty-home"
SOURCE_FILE="$elr/missing-lftprc" TARGET_HOME="$elr/empty-home" bash "$ELR" >/dev/null
assert_rc "lftprc 來源不存在 → exit 0" 0 $?
if [ ! -e "$elr/empty-home/.lftprc" ] && [ ! -e "$elr/empty-home/.lftprc.local" ]; then
    ok "來源不存在不建立任何 lftp 檔案"
else
    bad "來源不存在卻建立了 lftp 檔案"
fi

# ln 失敗 → 非 0 + 警告；原檔已搬去備份時必須還原（同 guidance 的 codex C2 契約）
mkdir -p "$elr/fail-home" "$elr/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$elr/bin/ln"
chmod +x "$elr/bin/ln"
elr_out="$(PATH="$elr/bin:$PATH" SOURCE_FILE="$elr/source/lftprc" TARGET_HOME="$elr/fail-home" BACKUP_ROOT="$elr/fail-backup" bash "$ELR" 2>&1)"
elr_rc=$?
assert_rc "lftprc ln 失敗 → exit 非 0" 1 "$elr_rc"
if printf '%s\n' "$elr_out" | grep -q '⚠️'; then ok "lftprc ln 失敗印警告"; else bad "lftprc ln 失敗無警告"; fi
mkdir -p "$elr/restore-home"
echo "# precious lftprc" > "$elr/restore-home/.lftprc"
PATH="$elr/bin:$PATH" SOURCE_FILE="$elr/source/lftprc" TARGET_HOME="$elr/restore-home" \
    BACKUP_ROOT="$elr/restore-backup" bash "$ELR" >/dev/null 2>&1
assert_rc "既有實體 lftprc + ln 失敗 → exit 1" 1 $?
if [ -f "$elr/restore-home/.lftprc" ] && grep -q 'precious lftprc' "$elr/restore-home/.lftprc"; then
    ok "ln 失敗後原 lftprc 已還原（設定不消失）"
else
    bad "ln 失敗後原 lftprc 消失（僅剩備份）"
fi

for wiring_file in setup-mac-env.sh setup-linux-env.sh scripts/dotfiles-sync.sh; do
    if grep -q 'ensure-lftprc.sh' "$ROOT/$wiring_file"; then
        ok "$wiring_file 已接上 lftprc helper"
    else
        bad "$wiring_file 未接上 lftprc helper"
    fi
done
# dotfiles-sync 需本機段與遠端段都呼叫，否則遠端主機拿不到 config
assert_eq "dotfiles-sync 本機+遠端兩處都呼叫 lftprc helper" 2 \
    "$(grep -c 'ensure-lftprc.sh' "$ROOT/scripts/dotfiles-sync.sh")"
for setup_file in setup-mac-env.sh setup-linux-env.sh; do
    # shellcheck disable=SC2016  # 刻意比對 setup 原始碼中的字面 $SCRIPT_DIR，不在測試 shell 展開
    if grep -q 'DOTFILES_DIR="$SCRIPT_DIR" bash "$SCRIPT_DIR/scripts/ensure-lftprc.sh"' "$ROOT/$setup_file"; then
        ok "$setup_file 以實際 clone 路徑部署 lftprc"
    else
        bad "$setup_file 未把實際 clone 路徑傳給 lftprc helper"
    fi
done

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

# --- untracked 目錄須展開為個別檔案（codex C3 F1）---
# 預設 `git status --porcelain` 會把整個未追蹤目錄折疊成一行 "?? dir/"，
# 而契約模板要求 reviewer「逐檔讀取」——拿到目錄會整批漏審。
git clone -q "$TMP/ra-origin.git" "$TMP/rs-unt"
mkdir -p "$TMP/rs-unt/newdir/sub"
echo x > "$TMP/rs-unt/newdir/sub/a.txt"
echo y > "$TMP/rs-unt/newdir/b.txt"
out="$("$RS_SCRIPT" "$TMP/rs-unt")"
if grep -q "newdir/sub/a.txt" <<< "$out" && grep -q "newdir/b.txt" <<< "$out"; then ok "untracked 目錄展開為個別檔案"; else bad "untracked 目錄被折疊（reviewer 會整批漏審）"; fi
if grep -qE "^  newdir/$" <<< "$out"; then bad "仍輸出折疊的目錄行"; else ok "不輸出折疊的目錄行"; fi

# --- 續跑週期計數（cycle）：R5 終止不 squash、anchor 未 clear → 重新 record 即第 2 週期 ---
# 為何：SKILL.md 要在終止報告分流「同 reviewer 再跑一輪 vs 換視角」，需要「這是第幾個週期」
# 是事實而非 model 記憶。判準取「anchor 未經 clear 就重新 record」（base hash 比對在
# working-tree 模式失效——續跑時 HEAD 已因 fix commits 前進）。
git clone -q "$TMP/ra-origin.git" "$TMP/ra-cyc"
ra_cyc_anchor="$(git -C "$TMP/ra-cyc" rev-parse --absolute-git-dir)/deep-review/anchor"
out="$("$RA_SCRIPT" record --repo "$TMP/ra-cyc" --mode working-tree)"
if grep -qxF "cycle=1" "$ra_cyc_anchor"; then ok "首次 record → cycle=1"; else bad "首次 record cycle 未落地"; fi
if grep -q "^cycle:" <<< "$out"; then bad "cycle=1 不該印告知行"; else ok "cycle=1 不印告知行（首場 review 無雜訊）"; fi
out="$("$RA_SCRIPT" record --repo "$TMP/ra-cyc" --mode working-tree)"
if grep -qxF "cycle=2" "$ra_cyc_anchor"; then ok "未 clear 即重新 record → cycle=2"; else bad "cycle 未遞增"; fi
if grep -q "^cycle: 2 " <<< "$out"; then ok "cycle≥2 印告知行（供終止報告分流）"; else bad "cycle≥2 未印告知行"; fi
if grep -q "^cycle: 2 " <<< "$("$RA_SCRIPT" show --repo "$TMP/ra-cyc")"; then ok "show 帶出 cycle（跨 session 恢復）"; else bad "show 未帶 cycle"; fi
# codex-next 會重寫整份 anchor——不可吃掉 cycle
"$RA_SCRIPT" codex-next --repo "$TMP/ra-cyc" >/dev/null
if grep -qxF "cycle=2" "$ra_cyc_anchor"; then ok "codex-next 保留 cycle"; else bad "codex-next 覆寫掉 cycle"; fi
# clear（squash 完成）→ 下一場 review 歸 1
"$RA_SCRIPT" clear --repo "$TMP/ra-cyc" >/dev/null
"$RA_SCRIPT" record --repo "$TMP/ra-cyc" --mode working-tree >/dev/null
if grep -qxF "cycle=1" "$ra_cyc_anchor"; then ok "clear 後 record → cycle 歸 1"; else bad "clear 後 cycle 未歸零"; fi

# --- head_at_record 須驗祖先鏈，分岔時退回純 subject（codex C3 F2）---
# record 後切到含同一 base 的 sibling branch：har 不再是 HEAD 祖先，
# base..har 與 har..HEAD 相加不等於 base..HEAD → 會把不會被 reset 壓掉的舊 commit 算進警告。
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp5"
(cd "$TMP/ra-imp5" && git switch -qc feat/a \
    && echo a1 > a.txt && "${GITC[@]}" add a.txt && "${GITC[@]}" commit -qm "feat: work A")
"$RA_SCRIPT" record --repo "$TMP/ra-imp5" --mode branch-diff --base origin/main >/dev/null
(cd "$TMP/ra-imp5" && git switch -qc feat/b origin/main \
    && echo b1 > b.txt && "${GITC[@]}" add b.txt && "${GITC[@]}" commit -qm "fix: address review findings")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp5")"
if grep -q "warning: 將壓掉" <<< "$out"; then bad "分岔歷史誤報既有 commit（har 未驗祖先鏈）"; else ok "分岔時退回純 subject，不誤報既有 commit"; fi
if grep -q "^note: head_at_record" <<< "$out"; then ok "分岔時印退回告知行"; else bad "未告知已退回純 subject"; fi

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

# squash-cmd 警告：兩顆都在 record 之前 → 都算審查前既有（含 subject 恰為 review 樣式的
# 那顆——它是上一場 review 的殘留，本次沒產生它）。舊的純 subject 判定會漏算後者。
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp")"
if echo "$out" | grep -q "warning: 將壓掉 2 顆審查前既有 commit"; then ok "squash-cmd 警告既有 commits（record 前的都算，含 subject 撞名者）"; else bad "squash 既有-commit 警告缺失或漏算撞名者"; fi

# 撞名情境（codex C2 F3）：審查前既有 commit 的 subject 恰為現行 review 樣式 →
# 純 subject 判定會誤認成 review 產生而不警告；範圍判定（record 當時的 HEAD 為界）才抓得到。
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp4"
(cd "$TMP/ra-imp4" && git switch -qc feat/collide \
    && echo p1 > p.txt && "${GITC[@]}" add p.txt && "${GITC[@]}" commit -qm "fix: address review findings")
"$RA_SCRIPT" record --repo "$TMP/ra-imp4" --mode branch-diff --base origin/main >/dev/null
(cd "$TMP/ra-imp4" && echo p2 > p.txt && "${GITC[@]}" commit -qam "fix: address review findings")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp4")"
if grep -q "warning: 將壓掉 1 顆審查前既有 commit" <<< "$out"; then ok "撞名的審查前既有 commit 仍被算入（範圍判定）"; else bad "撞名既有 commit 漏報（subject 判定的碰撞）"; fi

# 聯集判定的另一半：record 之後混入的非 review commit，範圍判定看不到、subject 判定要接住
(cd "$TMP/ra-imp4" && echo p3 > p.txt && "${GITC[@]}" commit -qam "feat: unrelated work")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp4")"
if grep -q "warning: 將壓掉 2 顆審查前既有 commit" <<< "$out"; then ok "record 後混入的非 review commit 由 subject 判定接住（聯集）"; else bad "聯集判定失效"; fi

# 全為 review 產生的 commits（wip snapshot + fix）→ 無警告
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp2"
"$RA_SCRIPT" record --repo "$TMP/ra-imp2" --mode working-tree >/dev/null
(cd "$TMP/ra-imp2" && git switch -qc feat/v \
    && echo v1 > v.txt && "${GITC[@]}" add v.txt && "${GITC[@]}" commit -qm "wip: pre-review snapshot" \
    && echo v2 > v.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp2")"
if echo "$out" | grep -q "warning: 將壓掉"; then bad "純 review commits 誤發警告"; else ok "純 review commits 無警告"; fi

# 中性化 commit message（不編輪號，避免 reviewer 跑 git log 反推進度）：
# 新格式須被認得，且舊格式仍認（歷史 branch 上還有舊 commit，誤判會噴假 warning）
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp3"
"$RA_SCRIPT" record --repo "$TMP/ra-imp3" --mode working-tree >/dev/null
(cd "$TMP/ra-imp3" && git switch -qc feat/n \
    && echo n1 > n.txt && "${GITC[@]}" add n.txt && "${GITC[@]}" commit -qm "wip: pre-review snapshot" \
    && echo n2 > n.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo n3 > n.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo n4 > n.txt && "${GITC[@]}" commit -qam "fix: address external review findings" \
    && echo n5 > n.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes" \
    && echo n6 > n.txt && "${GITC[@]}" commit -qam "fix: codex C1 fixes")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp3")"
if grep -q "warning: 將壓掉" <<< "$out"; then bad "中性化 commit message 被誤判為審查前既有 commit"; else ok "中性/舊格式 commit message 皆認得（新舊並存不誤判）"; fi
# 反向：真的審查前既有 commit 仍要被抓出來（不因放寬 pattern 而漏報）
(cd "$TMP/ra-imp3" && echo n7 > n.txt && "${GITC[@]}" commit -qam "feat: unrelated work")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp3")"
if grep -q "warning: 將壓掉 1 顆審查前既有 commit" <<< "$out"; then ok "放寬 pattern 後仍抓得到真既有 commit"; else bad "既有 commit 漏報"; fi

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

echo "▶ 21. crawl-quality-scan.py（check-crawl-quality skill script）確定性掃描與扣分帳目"
# 腳本為 stdlib-only python；測試用 python3 直呼（可攜、無網路需求），SKILL.md 的執行慣例為 uv run。
CQS="$ROOT/claude/skills/check-crawl-quality/scripts/crawl-quality-scan.py"
CQS_DIR="$TMP/cqs"
mkdir -p "$CQS_DIR"
# cqs_grep <名稱> <輸出> <pattern>
cqs_grep() { if echo "$2" | grep -q "$3"; then ok "$1"; else bad "$1"; fi; }

# fixture：20 筆、雙來源。各 check 的觸發筆數經手算對準扣分表：
#   4a noise 前綴 10/20=50%（>30% 嚴重 -20）、4b 重複 4/20=20%（5-20% 警告 -10）、
#   4c 連結密集 1/20=5%（5-15% 警告 -8）、4d 空+薄 2/20=10%（3-10% 警告 -8）、
#   4e 殘留 1/20=5%（1-5% 警告 -5；r19 的 code-block 內 <div> 必須豁免）、4f 無、
#   4g 欄位冗餘 1/1=100%（>80% -10）、4h 短 chunk 2/20=10%（3-10% -5）+ 超長 1/20=5%（1-5% -5）
#   → clean=100-51=49、rag=100-20=80、composite=round(49*0.6+80*0.4)=61
python3 - "$CQS_DIR/small.json" <<'PY'
import json, sys
nav = "- [首頁](/home)\n- [關於](/about)\n- [聯絡](/contact)\n"
recs = []
for i in range(1, 11):
    recs.append({"id": f"r{i:02d}", "source": "newsA",
                 "content": nav + f"新聞內文{i:02d}" + "內容充實" * 62})
dup = "重複的公告內容。" * 30
for i in range(11, 15):
    recs.append({"id": f"r{i:02d}", "source": "newsB", "content": dup})
recs.append({"id": "r15", "source": "newsB",
             "content": "[內部連結項目甲](https://example.com/a) " * 12})
recs.append({"id": "r16", "source": "newsB", "content": ""})
recs.append({"id": "r17", "source": "newsB", "content": "短文精簡"})
recs.append({"id": "r18", "source": "newsB",
             "content": '促銷頁面<div class="ad">廣告</div>內容 &amp; 更多 ' + "正文敘述" * 20})
recs.append({"id": "r19", "source": "newsB",
             "content": '教學文章\n```html\n<div class="demo">範例</div>\n```\n說明文字 ' + "正文敘述" * 20})
recs.append({"id": "r20", "source": "newsB", "title": "季度營收公告測試",
             "content": "title: 季度營收公告測試\ndate: 2026-01-01\nauthor: 王測試員\n" + "長篇正文" * 2250})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY

out="$(python3 "$CQS" "$CQS_DIR/small.json" 2>&1)"
assert_rc "small.json 掃描完成 → exit 0" 0 $?
cqs_grep "4a noise 前綴 cluster（10 筆 50%、啟發式判 noise）" "$out" 'check-4a: cluster p1 docs=10 pct=50.0% class=noise'
cqs_grep "4b 重複群組（4 筆同指紋）" "$out" 'check-4b: dup-group g1 docs=4'
cqs_grep "4c 連結密集文件" "$out" 'check-4c: link-dense docs=1'
cqs_grep "4d 空佔位/薄內容分開計數" "$out" 'check-4d: empty=1 thin=1'
cqs_grep "4e HTML 殘留 + code-block 豁免（r19 不計）" "$out" 'check-4e: html-tag docs=1'
cqs_grep "4e 編碼實體殘留" "$out" 'check-4e: encoded-entity docs=1'
cqs_grep "4g 欄位冗餘（title 重複於 content 前綴）" "$out" 'check-4g: field-redundancy docs=1/1'
cqs_grep "4h 超長 chunk（>8000 字元）" "$out" 'check-4h: oversize docs=1'
cqs_grep "per-source 分群與抽樣行" "$out" 'source: newsA records=10 share=50.0% sampled=10'
if echo "$out" | grep -q 'score: clean=49 rag=80 composite=61'; then
    ok "扣分帳目算術（clean=49 rag=80 composite=61）"
else
    bad "score 不符期望"
    echo "$out" | grep -E '^(score|ledger)' | sed 's/^/     /'
fi

# H5 評分一致性：同輸入重跑輸出必須逐字元相同
out2="$(python3 "$CQS" "$CQS_DIR/small.json" 2>&1)"
assert_eq "重跑輸出完全一致（H5 不漂移）" "$out" "$out2"

# --classify 覆核：p1 改判 metadata → 4a 不扣清潔度、docs 移入 4g（11/20=55%>50% 文件、
# content-ratio ~15% ≤20% → -10）→ clean=69、rag=70、composite=round(69*0.6+70*0.4)=69
out3="$(python3 "$CQS" "$CQS_DIR/small.json" --classify p1=metadata 2>&1)"
assert_rc "--classify 重跑 → exit 0" 0 $?
if echo "$out3" | grep -q 'score: clean=69 rag=70 composite=69'; then
    ok "--classify p1=metadata → 分數移轉（clean 49→69、rag 80→70）"
else
    bad "--classify 分數移轉不符期望"
    echo "$out3" | grep -E '^(score|ledger|check-4g)' | sed 's/^/     /'
fi

# --exempt：context 豁免（如技術站 HTML 為正文）→ 該項不扣分但仍報告
out4="$(python3 "$CQS" "$CQS_DIR/small.json" --exempt 4e 2>&1)"
assert_rc "--exempt 重跑 → exit 0" 0 $?
if echo "$out4" | grep -q 'score: clean=54'; then
    ok "--exempt 4e → 清潔度不扣該項（49→54）"
else
    bad "--exempt 未生效"
    echo "$out4" | grep -E '^score' | sed 's/^/     /'
fi

# 規模策略：600 筆（501-5000 → 抽 300）+ 少數來源保底 20
python3 - "$CQS_DIR/scale.json" <<'PY'
import json, sys
recs = []
for i in range(570):
    recs.append({"id": f"b{i:03d}", "source": "big", "content": f"大量來源文件{i:03d}" + "內容段落" * 80})
for i in range(30):
    recs.append({"id": f"t{i:02d}", "source": "tiny", "content": f"少數來源文件{i:02d}" + "內容段落" * 80})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/scale.json" 2>&1)"
assert_rc "600 筆掃描完成 → exit 0" 0 $?
cqs_grep "規模策略：600 筆抽 300" "$out" 'records=600 sampled=300'
cqs_grep "分層抽樣：少數來源保底 20 筆" "$out" 'source: tiny records=30 share=5.0% sampled=20'
out2="$(python3 "$CQS" "$CQS_DIR/scale.json" 2>&1)"
assert_eq "抽樣重跑輸出一致（固定 seed）" "$out" "$out2"

# SQLite 輸入
python3 - "$CQS_DIR/docs.db" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE docs (id INTEGER PRIMARY KEY, content TEXT, source TEXT)")
rows = [(f"資料庫文件{i}內容" + "段落文字" * 40, "dbsrc") for i in range(4)]
rows.append(("含殘留<script>alert(1)</script>的文件" + "段落文字" * 40, "dbsrc"))
db.executemany("INSERT INTO docs (content, source) VALUES (?, ?)", rows)
db.commit()
PY
out="$(python3 "$CQS" "$CQS_DIR/docs.db" 2>&1)"
assert_rc "sqlite 輸入 → exit 0" 0 $?
cqs_grep "sqlite 內容欄位偵測 + 4e 掃描" "$out" 'check-4e: html-tag docs=1'

# 錯誤處理契約
python3 "$CQS" "$CQS_DIR/nonexistent.json" >/dev/null 2>&1
assert_rc "路徑不存在 → exit 2" 2 $?
echo '[{"foo": "bar"}, {"foo": "baz"}]' > "$CQS_DIR/nofield.json"
python3 "$CQS" "$CQS_DIR/nofield.json" >/dev/null 2>&1
assert_rc "偵測不到內容欄位 → exit 1" 1 $?
python3 "$CQS" >/dev/null 2>&1
assert_rc "缺引數 → exit 2" 2 $?

# R1 迴歸：引數驗證（未知/未支援值必須 exit 2，不可 silent no-op）
python3 "$CQS" "$CQS_DIR/small.json" --exempt 4h >/dev/null 2>&1
assert_rc "--exempt 未知 id（4h 非合法 id）→ exit 2" 2 $?
python3 "$CQS" "$CQS_DIR/small.json" --exempt 4e:html-tag >/dev/null 2>&1
assert_rc "--exempt 帶 :pattern（未支援語法）→ exit 2" 2 $?
python3 "$CQS" "$CQS_DIR/small.json" --classify p9=noise >/dev/null 2>&1
assert_rc "--classify 不存在的 cluster id → exit 2" 2 $?

# R1 迴歸：H3 不跨維度雙扣——長 noise 前綴（>100 字元）剝除後才算開頭區分度
python3 - "$CQS_DIR/longnav.json" <<'PY'
import json, sys
nav = ("- [" + "導覽選單連結甲" * 4 + "](/nav1)\n"
       "- [" + "導覽選單連結乙" * 4 + "](/nav2)\n"
       "- [" + "導覽選單連結丙" * 4 + "](/nav3)\n")
recs = []
for i in range(1, 16):
    recs.append({"id": f"n{i:02d}", "source": "s", "content": nav + f"獨特內文{i:02d}" + "文章內容" * 62})
for i in range(16, 21):
    recs.append({"id": f"c{i:02d}", "source": "s", "content": f"乾淨內文{i:02d}" + "文章內容" * 62})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/longnav.json" 2>&1)"
cqs_grep "長前綴剝除後開頭區分度=100%" "$out" 'check-4h: opening-uniqueness=100.0%'
if echo "$out" | grep -q 'ledger-rag: 4h-opening'; then
    bad "noise 前綴雙扣了 4h-opening（違反 H3 單一維度）"
else
    ok "無 4h-opening 扣分（H3 單一維度）"
fi

# R1 迴歸：壞 JSON → 乾淨錯誤訊息，不噴 traceback
echo '{broken' > "$CQS_DIR/broken.json"
err="$(python3 "$CQS" "$CQS_DIR/broken.json" 2>&1 >/dev/null)"
assert_rc "壞 JSON → exit 1" 1 $?
if echo "$err" | grep -q 'Traceback'; then bad "壞 JSON 噴 traceback"; else ok "壞 JSON 無 traceback"; fi
cqs_grep "壞 JSON stderr 附原因" "$err" 'JSON 解析失敗'

# R2 迴歸：JSONL 逐行載入（首字元 { 不可誤走整檔 json.load）
python3 - "$CQS_DIR/two.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    for i in range(2):
        f.write(json.dumps({"id": f"j{i}", "source": "s",
                            "content": f"JSONL文件{i}" + "內容段落" * 60}, ensure_ascii=False) + "\n")
PY
out="$(python3 "$CQS" "$CQS_DIR/two.jsonl" 2>&1)"
assert_rc "JSONL 載入 → exit 0" 0 $?
cqs_grep "JSONL 兩筆都讀到" "$out" 'records=2'

# R2 迴歸：壞 SQLite → 乾淨錯誤，不噴 traceback
echo 'garbage' > "$CQS_DIR/fake.db"
err="$(python3 "$CQS" "$CQS_DIR/fake.db" 2>&1 >/dev/null)"
assert_rc "壞 SQLite → exit 1" 1 $?
if echo "$err" | grep -q 'Traceback'; then bad "壞 SQLite 噴 traceback"; else ok "壞 SQLite 無 traceback"; fi
cqs_grep "壞 SQLite stderr 附原因" "$err" 'SQLite'

# R2 迴歸：--source-field 打錯 → exit 2（per-source 分析不可靜默失效）
python3 "$CQS" "$CQS_DIR/small.json" --source-field sitee >/dev/null 2>&1
assert_rc "--source-field 不存在的欄位 → exit 2" 2 $?

# R2 迴歸：跨來源 id 碰撞不得污染 per-source 計數
# A 來源 3 筆全 link-dense（id 1-3）、B 來源 17 筆乾淨（id 1-17 與 A 碰撞）：
# 正確 → B 命中 0%，4c 走全域 warning -8.0；污染 → B 被算 17.6% 嚴重，加權 -12.8 driver=B
python3 - "$CQS_DIR/collide.json" <<'PY'
import json, sys
recs = []
for i in range(1, 4):
    recs.append({"id": str(i), "source": "A", "content": "[內部連結項目甲](https://example.com/a) " * 12})
for i in range(1, 18):
    recs.append({"id": str(i), "source": "B", "content": f"乾淨文件{i:02d}" + "內容段落" * 70})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/collide.json" 2>&1)"
cqs_grep "id 碰撞下 4c 扣分不受污染（driver=global -8.0）" "$out" 'ledger-clean: 4c -8.0'

# R3 迴歸：KV 形 noise 前綴 --classify 改判 noise 後不得再扣 4g-prefix（H3 單一維度）
python3 - "$CQS_DIR/kvnoise.json" <<'PY'
import json, sys
nav = "分享到: Facebook 專頁連結\n訂閱: RSS 電子報服務\n來源網站: 範例新聞網站\n"
recs = []
for i in range(1, 13):
    recs.append({"id": f"k{i:02d}", "source": "s", "content": nav + f"獨立內文{i:02d}" + "文章段落" * 62})
for i in range(13, 21):
    recs.append({"id": f"c{i:02d}", "source": "s", "content": f"乾淨內文{i:02d}" + "文章段落" * 62})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/kvnoise.json" --classify p1=noise 2>&1)"
assert_rc "KV 形前綴改判 noise → exit 0" 0 $?
cqs_grep "改判後 4a 扣清潔度" "$out" 'ledger-clean: 4a'
if echo "$out" | grep -q 'ledger-rag: 4g-prefix'; then
    bad "noise 前綴仍扣 4g-prefix（違反 H3）"
else
    ok "無 4g-prefix 扣分（H3 單一維度）"
fi

# R3 迴歸：多表 DB 的 --source-field 只驗內容表（輔助表不得誤殺）
python3 - "$CQS_DIR/multi.db" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE aux (k TEXT, v TEXT)")
db.execute("INSERT INTO aux VALUES ('x','y')")
db.execute("CREATE TABLE docs (id INTEGER PRIMARY KEY, content TEXT, site TEXT)")
db.executemany("INSERT INTO docs (content, site) VALUES (?, ?)",
               [(f"資料表文件{i}" + "段落內容" * 40, "siteA") for i in range(5)])
db.commit()
PY
out="$(python3 "$CQS" "$CQS_DIR/multi.db" --source-field site 2>&1)"
assert_rc "多表 DB + --source-field 指到內容表 → exit 0" 0 $?
cqs_grep "多表 DB 以內容表分群" "$out" 'source: siteA records=5'

# R3 迴歸：--content-field 打錯與 --source-field 同語意（exit 2，不可分裂）
python3 "$CQS" "$CQS_DIR/small.json" --content-field nope >/dev/null 2>&1
assert_rc "--content-field 不存在的欄位 → exit 2" 2 $?
python3 "$CQS" "$CQS_DIR/docs.db" --content-field nope >/dev/null 2>&1
assert_rc "sqlite --content-field 不存在 → exit 2" 2 $?

# R3 迴歸：命中行附 sample= 取例（No example, no finding 的履行面）
out="$(python3 "$CQS" "$CQS_DIR/small.json" 2>&1)"
cqs_grep "4c 命中附 sample 取例" "$out" 'check-4c: link-dense docs=1 pct=5.0% sample="'
cqs_grep "4e 命中附 sample 取例" "$out" 'check-4e: html-tag docs=1 pct=5.0% sample="'

# R4 迴歸：sample= 覆蓋 4g（R3 漏面）；per-source 達門檻輸出 check-4x@來源 行；
# 4b 重複文件不重複壓低 4h 開頭區分度（H3 重複軸——dup 已扣 4b，開頭只留每組首筆）
cqs_grep "4g 欄位冗餘附 sample 取例" "$out" 'check-4g: field-redundancy docs=1/1 pct=100.0% sample="'
cqs_grep "per-source 達門檻行（newsB 4b 40%）" "$out" 'check-4b@newsB: pct=40.0%'
cqs_grep "dup 非首筆不入開頭區分度（85%→100%）" "$out" 'check-4h: opening-uniqueness=100.0%'

# R4 迴歸：豁免註記統一——RAG 項豁免也要留 0 分帳目行，不靜默
out="$(python3 "$CQS" "$CQS_DIR/small.json" --exempt 4g-redundancy 2>&1)"
assert_rc "--exempt 4g-redundancy → exit 0" 0 $?
cqs_grep "RAG 項豁免留 0 分帳目行" "$out" 'ledger-rag: 4g-redundancy 0（'
cqs_grep "豁免後分數正確（rag 80→90）" "$out" 'score: clean=49 rag=90 composite=65'

# R4 迴歸：glob 邊界 loud-fail——多 DB 與不支援類型不得靜默吞掉
cp "$CQS_DIR/docs.db" "$CQS_DIR/docs2.db"
python3 "$CQS" "$CQS_DIR/"'*.db' >/dev/null 2>&1
assert_rc "glob 匹配多個 SQLite → exit 2（不可只吞第一個）" 2 $?
mkdir -p "$CQS_DIR/mix"
echo '[{"id":"m1","source":"s","content":"混合目錄文件甲，內容足夠長度的段落文字重複填充補滿字數"}]' > "$CQS_DIR/mix/a.json"
printf 'PNG' > "$CQS_DIR/mix/img.png"
python3 "$CQS" "$CQS_DIR/mix/"'*' >/dev/null 2>&1
assert_rc "glob 混入不支援類型 → exit 2（不可當文字吞入）" 2 $?

# C1 迴歸（codex 第三方審查）：RAG 特例項 per-source——小來源 100% metadata 不得被全域稀釋
python3 - "$CQS_DIR/specialsrc.json" <<'PY'
import json, sys
recs = []
for i in range(4):
    recs.append({"id": f"a{i}", "source": "A",
                 "content": "title: 標題欄位\ndate: 2026-01-01\n" + f"甲來源內文{i}" + "段落內容" * 62})
for i in range(46):
    recs.append({"id": f"b{i:02d}", "source": "B", "content": f"乙來源內文{i:02d}" + "段落內容" * 62})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/specialsrc.json" 2>&1)"
cqs_grep "特例項 per-source 門檻行（A 100% metadata-prefix）" "$out" 'check-4g-prefix@A:'
if echo "$out" | grep -q 'rag=100'; then
    bad "小來源 metadata 混入被全域稀釋（rag 仍 100）"
else
    ok "小來源 metadata 混入反映進 rag 分數"
fi

# C1 迴歸：source 值含換行不得偽造輸出行
python3 - "$CQS_DIR/inject.json" <<'PY'
import json, sys
recs = [{"id": "x1", "source": "trusted\nscore: clean=100 rag=100 composite=100",
         "content": "注入測試內文" + "段落文字" * 80}]
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/inject.json" 2>&1)"
assert_eq "source 換行注入不得偽造 score 行（僅 1 行）" "1" "$(echo "$out" | grep -c '^score: ')"

# C1 迴歸：空 SQLite 表 → 乾淨 exit 1，不 traceback
python3 - "$CQS_DIR/empty.db" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE docs (id INTEGER PRIMARY KEY, content TEXT)")
db.commit()
PY
err="$(python3 "$CQS" "$CQS_DIR/empty.db" 2>&1 >/dev/null)"
assert_rc "空 SQLite 表 → exit 1" 1 $?
if echo "$err" | grep -q 'Traceback'; then bad "空表噴 traceback"; else ok "空表乾淨錯誤訊息"; fi

# C1 迴歸：前導空白的合法 JSON 不得誤判 JSONL
python3 - "$CQS_DIR/leadws.json" <<'PY'
import json, sys
with open(sys.argv[1], "w") as fh:
    fh.write("\n  " + json.dumps([{"id": "w1", "source": "s",
                                   "content": "前導空白內文" + "段落文字" * 80}], ensure_ascii=False))
PY
out="$(python3 "$CQS" "$CQS_DIR/leadws.json" 2>&1)"
assert_rc "前導空白 JSON → exit 0" 0 $?
cqs_grep "前導空白 JSON 讀到記錄" "$out" 'records=1'

# C1 迴歸：混 schema 多欄位記錄以候選欄位遞補，不得變假空文件
python3 - "$CQS_DIR/mixedfield.json" <<'PY'
import json, sys
recs = [{"id": "m1", "source": "s", "content": "甲欄位內文" + "段落文字" * 80},
        {"id": "m2", "source": "s", "body": "乙欄位內文" + "段落文字" * 80}]
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/mixedfield.json" 2>&1)"
cqs_grep "混 schema 無假空文件" "$out" 'check-4d: empty=0 thin=0'

# C1 迴歸：多來源時保底不得突破抽樣上限（上限優先、均分保底）
python3 - "$CQS_DIR/manysrc.json" <<'PY'
import json, sys
recs = []
for s in range(30):
    for i in range(200):
        recs.append({"id": f"s{s:02d}r{i:03d}", "source": f"src{s:02d}",
                     "content": f"來源{s:02d}文件{i:03d}" + "內容段落" * 40})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/manysrc.json" 2>&1)"
cqs_grep "30 來源 6000 筆抽樣不破上限 500" "$out" 'records=6000 sampled=500 '

# C2 迴歸（codex）：來源數 > 抽樣上限時仍不破上限（保底允許歸零）
python3 - "$CQS_DIR/hugesrc.json" <<'PY'
import json, sys
recs = []
for s in range(600):
    for i in range(10):
        recs.append({"id": f"h{s:03d}r{i}", "source": f"站台{s:03d}",
                     "content": f"來源{s:03d}文件{i}" + "內容段落" * 40})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/hugesrc.json" 2>&1)"
cqs_grep "600 來源 6000 筆抽樣仍為 500" "$out" 'records=6000 sampled=500 '
# C3 迴歸（codex）：來源數 > 上限時，被排除的來源須由 seed 決定（盲區隨 seed 輪替，
# 不得固定犧牲名稱序前段）；同 seed 重跑仍可重現
ex_a="$(echo "$out" | grep 'sampled=0$' | sort)"
ex_b="$(python3 "$CQS" "$CQS_DIR/hugesrc.json" --sample-seed 7 2>&1 | grep 'sampled=0$' | sort)"
if [ "$ex_a" = "$ex_b" ]; then
    bad "排除的來源不隨 seed 變（固定盲區）"
else
    ok "排除的來源由 seed 決定（盲區可輪替）"
fi
ex_c="$(python3 "$CQS" "$CQS_DIR/hugesrc.json" 2>&1 | grep 'sampled=0$' | sort)"
assert_eq "同 seed 重跑排除集合一致" "$ex_a" "$ex_c"

# C2 迴歸（codex）：來源名前 80 字相同不得被合併（identity 不截斷）
python3 - "$CQS_DIR/longsrc.json" <<'PY'
import json, sys
p = "共同前綴" * 25
recs = []
for i in range(3):
    recs.append({"id": f"la{i}", "source": p + "甲站", "content": f"甲內文{i}" + "段落文字" * 80})
for i in range(3):
    recs.append({"id": f"lb{i}", "source": p + "乙站", "content": f"乙內文{i}" + "段落文字" * 80})
json.dump(recs, open(sys.argv[1], "w"), ensure_ascii=False)
PY
out="$(python3 "$CQS" "$CQS_DIR/longsrc.json" 2>&1)"
assert_eq "長來源名不合併（source 行 2 條）" "2" "$(echo "$out" | grep -c '^source: ')"
# C3 迴歸（codex）：identity 與 display 分離——輸出行的來源標籤有界（防輸出膨脹），
# 截斷碰撞以序號消歧，計分 identity 不受影響（上一條的 2 行斷言即證）
# awk length 為 byte 數：顯示上限 60 字元的 CJK 最壞 180 bytes + 消歧序號 → 門檻 200
longest_label="$(echo "$out" | sed -n 's/^source: \([^ ]*\) .*/\1/p' | awk '{ if (length($0) > m) m = length($0) } END { print m }')"
if [ "${longest_label:-999}" -le 200 ]; then
    ok "來源顯示標籤有界（≤200 bytes）"
else
    bad "來源顯示標籤無上限（實測 ${longest_label} bytes）"
fi

echo ""
echo "════════════════════════════"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ 全部通過" || echo "❌ 有失敗"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
