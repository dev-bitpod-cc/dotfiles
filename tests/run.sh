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
# 18d. brewup.sh helper 部署與失敗告知（temp HOME + PATH stub 全隔離；不得碰真實環境）
#  19. review-anchor.sh（deep-review skill script）錨點生命週期 / squash-cmd / codex-next
#  20. verify-tests.sh（deep-review skill script）框架偵測與 exit 契約（uv/bun stub）
#  21. crawl-quality-scan.py（check-crawl-quality skill script）確定性掃描 / 扣分帳目 / --classify 覆核
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1   # 相對路徑的 source 解析與 git 操作以 repo 根為基準（從外部目錄執行時避免 SC1091 誤報）
# gate 的 glob（含 skills 的 lib/）在無匹配時預設會以**字面值**傳給 shellcheck / bash -n，
# 讓 gate 以「檔案不存在」失敗而非跳過——某個 skill 沒有 lib/ 就會誤報。
shopt -s nullglob
# nullglob 是 process-wide 的，代價是**其他** glob 若哪天失效會靜默窄化（gate 照樣全綠、
# 實際少掃一批檔）。用下界斷言把那個代價擋回來：數字取保守下界，新增腳本只會讓它更寬鬆。
_gate_files=("$ROOT"/scripts/*.sh "$ROOT"/claude/skills/*/scripts/*.sh)   # nullglob 下無匹配即空陣列
if [ "${#_gate_files[@]}" -lt 15 ]; then
    echo "❌ gate 檔案數異常少（${#_gate_files[@]}）——glob 可能已靜默窄化，先修再跑" >&2
    exit 1
fi
FIX="$ROOT/tests/fixtures"
# mktemp 失敗必須當場中止：本腳本沒有 set -e，而下面的 `cd "$TMP"` 在 TMP 為空時**回傳 0
# 且不改目錄**，pwd -P 於是交出當下 cwd（第 35 行剛切到 repo 根）——EXIT trap 就會
# `rm -rf` 掉整個 repo。空值 fallback 到 cwd + 破壞性指令，是這裡唯一不能省的檢查。
TMP="$(mktemp -d)" || { echo "mktemp -d 失敗（TMPDIR 不存在或不可寫？）" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d 未產生可用目錄：'${TMP}'" >&2; exit 1; }
# macOS 的 mktemp 給 /var/...（symlink），而腳本的照抄行印 git --show-toplevel 的 realpath
# （/private/var/...）——不正規化，所有「整行照抄」斷言都會因路徑前綴不同而假紅。
TMP="$(cd "$TMP" && pwd -P)"
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
if shellcheck -x -P "SCRIPTDIR:$ROOT/scripts" \
    "$ROOT"/scripts/*.sh "$ROOT/scripts/lib/inventory.sh" \
    "$ROOT"/claude/scripts/*.sh \
    "$ROOT"/claude/skills/*/scripts/*.sh "$ROOT"/claude/skills/*/scripts/lib/*.sh \
    "$ROOT"/codex/skills/*/scripts/*.sh \
    "$ROOT/shell/functions.sh" \
    "$ROOT/setup-mac-env.sh" "$ROOT/setup-linux-env.sh" "$ROOT/write-mac-defaults.sh" \
    "$ROOT"/claude/evals/*.sh \
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
    "$ROOT"/claude/skills/*/scripts/*.sh "$ROOT"/claude/skills/*/scripts/lib/*.sh \
    "$ROOT"/codex/skills/*/scripts/*.sh \
    "$ROOT/shell/functions.sh" \
    "$ROOT"/claude/evals/*.sh \
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

echo "▶ 1c. unquoted heredoc 反引號 gate"
# bash 對 `<<EOF`（delimiter 未加引號）的 body 做命令替換 → 文字裡一組行內 code 的反引號
# 會**真的被執行**。2026-08-07 兩次實地：一次讓 `git push` 真的推了一條 branch 上 GitHub；
# 一次是 dotfiles-sync/setup 用 `<< SSHEOF` 灌 ssh/config，而 ssh/config 正是會長註解的檔案
# ——差一步就把毀損的 ~/.ssh/config 部署到全機隊。判準與掃描器見 tests/heredoc-gate.awk。
# DO NOT relax this gate — 失敗是靜默的：產出的檔案少一段文字，副作用發生在別的地方。
HD_GATE="$ROOT/tests/heredoc-gate.awk"
mkdir -p "$TMP/hd"
# 掃描器自檢（RED 抓得到、GREEN 不誤報）。少了這兩條，掃描器被改壞而恆不匹配時，
# 底下對真實檔案的空輸出一樣是「通過」——gate 會靜默變成永遠綠。
cat > "$TMP/hd/red.sh" <<'HDFIX'
cat > /tmp/out.md << EOF
說明：`git push` 會把 branch 推上去
EOF
HDFIX
# `$(cat 某檔)` 注入外部檔案內容 → **不得**報。命令替換的結果不會被重新掃描，該檔裡的
# 反引號不會被執行（2026-08-07 實測；當時誤判成同一個地雷、為它加過一條誤報規則，
# 那條規則會把每個「用 heredoc 灌檔」的正常寫法都判紅）。
cat > "$TMP/hd/green-cat.sh" <<'HDFIX'
cat > ~/.ssh/config << SSHEOF
# 此檔案由 dotfiles setup 腳本產生
$(cat "$DOTFILES_DIR/ssh/config")
SSHEOF
HDFIX
cat > "$TMP/hd/green.sh" <<'HDFIX'
cat > /tmp/out.md << 'SAFE'
說明：`git push` 在這裡是字面，不會被執行
內含 <<INNER 樣式的文字也不該讓掃描器誤判成新的 heredoc
SAFE
grep -q pattern <<< "$big"
echo "一般行的 `date` 不歸本 gate 管"
# 註解裡討論 <<EOF 這個寫法時不得被當成 heredoc 起始——本 gate 自己的註解就會這樣寫，
# 誤判會把後面數行全報成 body（第一版即如此，真正的問題行反而被蓋掉）
echo "上一行是註解，這行的 `date` 同樣不歸本 gate 管"
cat > "$1" <<STUB
printf '%s\n' "\$(cat '${3:-/dev/null}')"
STUB
HDFIX
if [ -n "$(awk -f "$HD_GATE" "$TMP/hd/red.sh")" ]; then ok "gate 自檢：unquoted heredoc 含反引號 → 命中"; else bad "gate 失效（RED fixture 沒被抓，真實掃描的空輸出不可信）"; fi
if [ -z "$(awk -f "$HD_GATE" "$TMP/hd/green-cat.sh")" ]; then ok "gate 自檢：\$(cat 某檔) 注入 → 不報（展開結果不重新掃描，實測確認）"; else bad "gate 把安全的灌檔寫法判紅——每個用 heredoc 灌檔的地方都會被逼著改"; fi
if [ -z "$(awk -f "$HD_GATE" "$TMP/hd/green.sh")" ]; then ok "gate 自檢：quoted heredoc／herestring／註解／跳脫的 \\\$(cat → 不誤報"; else bad "gate 誤報（會逼人把安全寫法改壞以求過測）"; fi
hd_hits="$(awk -f "$HD_GATE" \
    "$ROOT"/scripts/*.sh "$ROOT"/scripts/lib/*.sh \
    "$ROOT"/claude/scripts/*.sh \
    "$ROOT"/claude/skills/*/scripts/*.sh "$ROOT"/claude/skills/*/scripts/lib/*.sh \
    "$ROOT"/codex/skills/*/scripts/*.sh \
    "$ROOT/shell/functions.sh" \
    "$ROOT/setup-mac-env.sh" "$ROOT/setup-linux-env.sh" "$ROOT/write-mac-defaults.sh" \
    "$ROOT"/claude/evals/*.sh \
    "$ROOT/tests/run.sh")"
if [ -z "$hd_hits" ]; then
    ok "無 unquoted heredoc 的 body 含反引號"
else
    bad "有 unquoted heredoc 的 body 含反引號（一律改 <<'EOF'，變數走 os.environ/sys.argv）"
    printf '%s\n' "$hd_hits" | sed 's/^/     /'
fi

echo "▶ 1d. 交叉引用完整性 gate"
# repo 的規範網靠「唯一權威」維持：同一主題只有一處定義，別處寫「見 `X 檔`「Y 節」，此處不
# 重述」。那個不變式原本**全靠散文**。指標斷掉的後果不是不整潔——claude/CLAUDE.md 要求
# 「勿憑記憶重組」，指標斷掉時重組就是唯一選擇。首次掃描實測：1 條真死指標、2 條指向
# repo 內有兩份同名檔的基名引用（reviewer-brief.md 有 Claude／Codex 兩份，刻意隔離的兩套
# 判準，指錯即破壞 blind review）。判準與輸出契約見 tests/xref-gate.py 檔頭。
XREF_GATE="$ROOT/tests/xref-gate.py"
XR="$TMP/xref"
mkdir -p "$XR/sub"
# 共用 target：heading 帶括號補充（釘 G1 的子字串比對）、一條含 ** 修飾的內文規則（G2）、
# 一個只活在 fence 內的節名（R2）、一個只活在 HTML comment 內的節名（R3）。
cat > "$XR/target.md" <<'XREFFIX'
# 目標檔

## 說法表（唯一權威；照此分派）

- 存之前先比對既有項目，覆蓋同一主題就**更新該檔**，不要建重複檔。

```markdown
## 只活在圍欄裡的節
```

<!--
## 只活在註解裡的節
-->
XREFFIX
cat > "$XR/sub/dup.md" <<'XREFFIX'
# 同名檔（放在 root 底下的別處，不在引用檔目錄，也不在 root 直下）
## 某節
XREFFIX
xref_run() { python3 "$XREF_GATE" --root "$XR" "$@" 2>/dev/null; }
# 掃描器自檢在前：少了 RED，掃描器被改壞而恆不匹配時，對真實檔案的空輸出一樣是「通過」。
cat > "$XR/r1.md" <<'XREFFIX'
見 `target.md`「這個節名根本不存在於任何地方」。
XREFFIX
cat > "$XR/r2.md" <<'XREFFIX'
見 `target.md`「只活在圍欄裡的節」。
XREFFIX
cat > "$XR/r3.md" <<'XREFFIX'
見 `target.md`「只活在註解裡的節」。
XREFFIX
cat > "$XR/r4.md" <<'XREFFIX'
見 `dup.md`「某節」。
XREFFIX
cat > "$XR/r5.md" <<'XREFFIX'
見 `target.md`「**」。
XREFFIX
cat > "$XR/r7.md" <<'XREFFIX'
<!--
維護提示：豁免條件見 `target.md`「這個節名同樣不存在」。
-->
XREFFIX
cat > "$XR/g1.md" <<'XREFFIX'
見 `target.md`「說法表」。
XREFFIX
cat > "$XR/g2.md" <<'XREFFIX'
見 `target.md`「覆蓋同一主題就更新該檔，不要建重複檔」。
XREFFIX
cat > "$XR/g3.md" <<'XREFFIX'
報告模板範例（fenced，示範怎麼寫，不是治理指標）：

```markdown
見 `target.md`「範例用的假節名」。
```
XREFFIX
# G5：外層四反引號、內層三反引號。內層若被當 closer，fence 會提前關欄，
# 後面那條假引用就會被誤報。
cat > "$XR/g5.md" <<'XREFFIX'
````markdown
```
見 `target.md`「巢狀圍欄裡的假節名」。
```
````
XREFFIX
# G6：四格縮排的字面 ``` 不是 fence opener（CommonMark 上限 3 格）。若誤判為 opener，
# 後面那條**真的壞掉**的引用會被吞掉而漏報——所以這條的期望是「必須命中」。
cat > "$XR/g6.md" <<'XREFFIX'
    ```
    這是四格縮排的字面內容，不是圍欄。

見 `target.md`「縮排誤判就會漏掉這條」。
XREFFIX
# G7：fence 內的 ```text 不是 closer（closer 後只允許空白）。若誤判為 closer，
# 圍欄提前結束 → 圍欄內那條假引用被誤報，且真正的 closer 之後那條壞引用反被吞掉。
cat > "$XR/g7.md" <<'XREFFIX'
```
```text
見 `target.md`「圍欄內的假節名」。
```

見 `target.md`「圍欄外必須抓到的節名」。
XREFFIX
if [ -n "$(xref_run "$XR/r1.md")" ]; then ok "gate 自檢：節名與內文皆無 → 命中"; else bad "gate 失效（RED 沒被抓，真實掃描的空輸出不可信）"; fi
if [ -n "$(xref_run "$XR/r2.md")" ]; then ok "gate 自檢：目標節名只在 fenced block → 仍是死指標"; else bad "target 端未剝 fence（圍欄裡的範例標題被當成節存在 → 假綠）"; fi
if [ -n "$(xref_run "$XR/r3.md")" ]; then ok "gate 自檢：目標節名只在 HTML comment → 仍是死指標"; else bad "target 端未剝 comment（註解掉的模板被當成節存在 → 假綠）"; fi
if [ -n "$(xref_run "$XR/r4.md")" ]; then ok "gate 自檢：同名檔在 root 別處但引用處解析不到 → 命中（不做全 repo 模糊搜尋）"; else bad "gate 用基名模糊搜尋放行了——repo 內兩份 reviewer-brief.md 是刻意隔離的判準，指錯無警訊"; fi
if [ -n "$(xref_run "$XR/r5.md")" ]; then ok "gate 自檢：節名 normalize 後為空 → 命中"; else bad "空節名放行（空字串是任何字串的子字串，會恆假綠）"; fi
if [ -n "$(xref_run "$XR/r7.md")" ]; then ok "gate 自檢：source 的 HTML comment 內死指標 → 命中"; else bad "source 端漏掃 comment（krepo 的豁免指標就寫在 comment 裡）"; fi
xref_missing_rc=0
xref_run "$XR/nosuch-file.md" >/dev/null 2>&1 || xref_missing_rc=$?
if [ "$xref_missing_rc" -eq 2 ]; then ok "gate 自檢：不存在的輸入檔 → exit 2（錯誤不得冒充零命中）"; else bad "scanner 失敗未走 exit 2（實得 ${xref_missing_rc}）——run.sh 無 set -e，空 stdout 會被判成乾淨"; fi
if [ -z "$(xref_run "$XR/g1.md")" ]; then ok "gate 自檢：節名前綴對上帶括號補充的 heading → 不報"; else bad "子字串比對失效（heading 帶括號補充是常態寫法，會全面誤紅）"; fi
if [ -z "$(xref_run "$XR/g2.md")" ]; then ok "gate 自檢：引用內文一行（原文含 ** 修飾）→ 不報"; else bad "normalize 未剝 inline 修飾（合法的規則引用被判紅）"; fi
if [ -z "$(xref_run "$XR/g3.md")" ]; then ok "gate 自檢：source 的 fenced 範例 → 不報"; else bad "source 端未剝 fence（報告模板的範例被當治理指標，逼人改模板文字）"; fi
if [ -z "$(xref_run "$XR/g5.md")" ]; then ok "gate 自檢：巢狀圍欄（4 反引號包 3）不提前關欄"; else bad "closer 未檢查同字元與長度 → 圍欄提前關，內層範例被誤報"; fi
if [ -n "$(xref_run "$XR/g6.md")" ]; then ok "gate 自檢：四格縮排的圍欄標記不是 opener（後續正文照掃）"; else bad "縮排無上限 → 四格縮排被當 opener，後面的真死指標被吞掉"; fi
xref_g7="$(xref_run "$XR/g7.md")"
if [ -n "$xref_g7" ] && ! grep -q '圍欄內的假節名' <<< "$xref_g7"; then
    ok "gate 自檢：fence 內的 \`\`\`text 不是 closer（圍欄內不誤報、圍欄外照抓）"
else
    bad "closer 後未限定只允許空白 → 圍欄提前結束，內文被當正文誤報／圍欄外的死指標漏抓"
fi
# 真實掃描：本 repo 的治理指標必須全部可解析
xref_hits="$(python3 "$XREF_GATE" --root "$ROOT")"
xref_rc=$?
if [ "$xref_rc" -ne 0 ]; then
    bad "xref-gate 掃描器執行失敗（exit ${xref_rc}）——空輸出不可信"
elif [ -z "$xref_hits" ]; then
    ok "無斷掉的交叉引用"
else
    bad "有斷掉的交叉引用（節名改過就要同步指標；權威搬家要改指向）"
    printf '%s\n' "$xref_hits" | sed 's/^/     /'
fi

echo "▶ 2. bash -n 語法 gate"
syntax_fail=0
for f in "$ROOT"/scripts/*.sh "$ROOT/scripts/lib/inventory.sh" \
         "$ROOT"/claude/scripts/*.sh \
         "$ROOT"/claude/skills/*/scripts/*.sh "$ROOT"/claude/skills/*/scripts/lib/*.sh \
         "$ROOT"/codex/skills/*/scripts/*.sh \
         "$ROOT/shell/functions.sh" \
         "$ROOT/setup-mac-env.sh" "$ROOT/setup-linux-env.sh" "$ROOT/write-mac-defaults.sh" \
         "$ROOT"/claude/evals/*.sh; do
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

# untracked 目錄須展開到檔案層級：porcelain 預設折疊成 "?? dir/"，殘留規模被低估、
# 檔名看不到（review-state.sh 同源前例）。命中點放輸入前段以免斷言被截斷路徑架空。
mkdir -p "$TMP/gh-work/newdir/sub"
: > "$TMP/gh-work/newdir/a.txt"
: > "$TMP/gh-work/newdir/sub/b.txt"
out="$("$GH_SCRIPT" "$TMP/gh-work")"
if grep -q "newdir/a.txt" <<< "$out" && grep -q "newdir/sub/b.txt" <<< "$out"; then
    ok "untracked 目錄展開到檔案層級"
else bad "untracked 目錄未展開（porcelain 折疊成 ?? dir/）"; fi
assert_eq "untracked 計數為展開後檔數" "uncommitted: 2 檔" \
    "$(grep -o 'uncommitted: [0-9]* 檔' <<< "$out")"
rm -rf "$TMP/gh-work/newdir"

# (h) fetch 的 remote 必須涵蓋 baseline 實際所屬的 remote。branch.<n>.remote 指向 other
#     （且沒設 branch.<n>.merge，@{upstream} 因此解析不到）時 baseline 會 fallback 到
#     origin/*——只 fetch other 就讓 stale 的 origin ref 過關，等於拿 A 的新鮮度替 B 背書
git init --bare -q -b main "$TMP/mx-origin.git"
git init --bare -q -b main "$TMP/mx-other.git"
git init -q -b main "$TMP/mx-work"
(cd "$TMP/mx-work" \
    && echo a > f && "${GITC[@]}" add f && "${GITC[@]}" commit -qm c1 \
    && git remote add origin "$TMP/mx-origin.git" && git remote add other "$TMP/mx-other.git" \
    && git push -q origin main && git push -q other main \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
    && git config branch.main.remote other \
    && echo b >> f && "${GITC[@]}" commit -qam c2 && git push -q origin main)
git -C "$TMP/mx-origin.git" update-ref refs/heads/main "$(git -C "$TMP/mx-work" rev-parse HEAD~1)"
assert_eq "fixture 前置：origin 端已 rewind，本機 HEAD 不在遠端" \
    "1" "$(git -C "$TMP/mx-work" rev-list --count "$(git -C "$TMP/mx-origin.git" rev-parse main)..HEAD" 2>/dev/null)"
out="$("$GH_SCRIPT" "$TMP/mx-work")"
if grep -q "verdict: CLEAN" <<< "$out"; then
    bad "fetch 的 remote 與 baseline 的不一致，stale origin ref 過關判 CLEAN：$out"
else ok "baseline 所屬 remote 一併 fetch → 不再誤判 CLEAN"; fi

# git-hygiene 的 gh stub：只回應 `pr view`。腳本取 url,state,isDraft 三欄（tsv），
# 因為只讀 url 會把 CLOSED（未合併就關掉）與 draft 都當成「已有 PR、無殘留」
make_hyg_gh_stub() {  # <path> <nopr|authfail|open|draft|closed|merged> [headRefOid]
    case "$2" in
        nopr)
            cat > "$1" <<'STUB'
#!/usr/bin/env bash
echo 'no pull requests found for branch "feat/y"' >&2
exit 1
STUB
            ;;
        authfail)
            cat > "$1" <<'STUB'
#!/usr/bin/env bash
echo 'HTTP 401: Bad credentials (https://api.github.com/graphql)' >&2
exit 1
STUB
            ;;
        open)
            cat > "$1" <<'STUB'
#!/usr/bin/env bash
printf 'OPEN\tfalse\thttps://github.com/acme/widget/pull/7\n'
STUB
            ;;
        draft)
            cat > "$1" <<'STUB'
#!/usr/bin/env bash
printf 'OPEN\ttrue\thttps://github.com/acme/widget/pull/8\n'
STUB
            ;;
        closed)
            cat > "$1" <<'STUB'
#!/usr/bin/env bash
printf 'CLOSED\tfalse\thttps://github.com/acme/widget/pull/9\n'
STUB
            ;;
        merged)
            # 第 4 欄 headRefOid = PR 合併當下的 head；用它區分「squash 前的原始 commit」
            # 與「合併之後才寫的 commit」——後者是真殘留。
            # sha 由外部檔案供給，同一支 stub 才能服務多個情境（各自寫入不同的 head）
            cat > "$1" <<STUB
#!/usr/bin/env bash
printf 'MERGED\tfalse\thttps://github.com/acme/widget/pull/10\t%s\n' "\$(cat '${3:-/dev/null}' 2>/dev/null)"
STUB
            ;;
    esac
    chmod +x "$1"
}
make_hyg_gh_stub "$TMP/hyg-gh-nopr" nopr
make_hyg_gh_stub "$TMP/hyg-gh-authfail" authfail
make_hyg_gh_stub "$TMP/hyg-gh-open" open
make_hyg_gh_stub "$TMP/hyg-gh-draft" draft
make_hyg_gh_stub "$TMP/hyg-gh-closed" closed
: > "$TMP/hyg-head-oid"        # merged stub 讀這個檔取得 headRefOid
make_hyg_gh_stub "$TMP/hyg-gh-merged" merged "$TMP/hyg-head-oid"

# fixture：feature branch 已 push 到 origin/feat/y 但**未設 upstream**（tree clean）
git init --bare -q "$TMP/gh-b4-origin.git"
git init -q -b main "$TMP/gh-b4"
(cd "$TMP/gh-b4" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/gh-b4-origin.git" && git push -qu origin main \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
    && git switch -qc feat/y && echo v2 > f.txt && "${GITC[@]}" commit -qam "feat: y" \
    && git push -q origin feat/y)

# commit 已在 remote，退用 origin/<default> 當 baseline 會誤報「未 push」
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-nopr" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "unpushed: none" <<< "$out"; then
    ok "已 push 到 origin/<branch> 但無 upstream → 不誤報 unpushed"
else bad "無 upstream 的已 push branch 被誤報 unpushed"; fi

# gh 執行失敗 ≠ 沒有 PR：兩者都 exit 1，吞掉 stderr 就分不出來（腳本檔頭設計原則）
if grep -q "pr: MISSING" <<< "$out"; then ok "gh 明示無 PR → MISSING"; else bad "真無 PR 未判 MISSING"; fi

out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-authfail" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "pr: UNKNOWN" <<< "$out" && ! grep -q "pr: MISSING" <<< "$out"; then
    ok "gh 認證失敗 → UNKNOWN（不誤報 MISSING）"
else bad "gh 認證失敗被誤判成無 PR"; fi
if grep -q "401" <<< "$out"; then ok "UNKNOWN 附 gh 失敗原因"; else bad "UNKNOWN 未印失敗原因"; fi
if grep -q "verdict: UNKNOWN" <<< "$out"; then ok "gh 失敗 → verdict UNKNOWN"; else bad "gh 失敗 verdict 錯誤"; fi

out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-open" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "pull/7" <<< "$out"; then ok "OPEN PR → 印出 URL"; else bad "OPEN PR 未印 URL"; fi
if grep -q "verdict: CLEAN" <<< "$out"; then ok "已 push + OPEN PR → CLEAN"; else bad "已 push + OPEN PR 未判 CLEAN"; fi

# PR 存在不等於變更送得出去：只讀 url 會把下面三種都當成「有 PR、無殘留」
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-draft" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "DRAFT" <<< "$out" && grep -q "verdict: RESIDUE" <<< "$out"; then
    ok "draft PR → 標 DRAFT 且判 RESIDUE"
else bad "draft PR 被當成完備的 PR：$out"; fi

out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-closed" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "CLOSED" <<< "$out" && grep -q "verdict: RESIDUE" <<< "$out"; then
    ok "CLOSED PR（未合併）→ 標 CLOSED 且判 RESIDUE"
else bad "CLOSED PR 被當成已送出：$out"; fi

# MERGED 反過來不算殘留——squash merge 後 branch 的 commit 不在 default 歷史裡，
# 相對 default 仍「未併」但東西已經進去了，只是 branch 可以清掉
git -C "$TMP/gh-b4" rev-parse HEAD > "$TMP/hyg-head-oid"   # 合併後沒有新 commit
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-merged" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "MERGED" <<< "$out"; then ok "MERGED PR → 標 MERGED"; else bad "MERGED PR 未標示：$out"; fi
if grep -q "verdict: RESIDUE" <<< "$out"; then bad "MERGED PR 誤判 RESIDUE：$out"; else ok "MERGED PR → 不算殘留"; fi

# --- remote 事實 vs 本機 cache：unpushed 判定不能只信 remote-tracking ref ---

# (a) 遠端 branch 被刪掉，本機 origin/feat/y 仍指向 HEAD → 未 fetch 會誤報「已送出」
git -C "$TMP/gh-b4-origin.git" update-ref -d refs/heads/feat/y
rm -f "$TMP/gh-b4/.git/FETCH_HEAD"
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-nopr" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "unpushed: none" <<< "$out"; then
    bad "遠端 branch 已刪除仍報 unpushed: none（stale tracking ref 被當成遠端事實）"
else ok "遠端 branch 已刪除 → 不再報 unpushed: none"; fi
if grep -q "verdict: CLEAN" <<< "$out"; then
    bad "遠端 branch 已刪除仍判 CLEAN：$out"
else ok "遠端 branch 已刪除 → 不判 CLEAN"; fi

# (b) fetch 跑不動（remote 壞掉）→ remote 狀態無從得知，只能 UNKNOWN，絕不可 CLEAN
git -C "$TMP/gh-b4" remote set-url origin "$TMP/nonexistent-origin.git"
rm -f "$TMP/gh-b4/.git/FETCH_HEAD"
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-nopr" "$GH_SCRIPT" "$TMP/gh-b4")"
if grep -q "verdict: CLEAN" <<< "$out"; then
    bad "fetch 失敗仍判 CLEAN（把本機 cache 當遠端事實）：$out"
else ok "fetch 失敗 → 不判 CLEAN"; fi
if grep -q "unpushed: UNKNOWN" <<< "$out"; then
    ok "fetch 失敗 → unpushed 標 UNKNOWN"
else bad "fetch 失敗未把 unpushed 標 UNKNOWN：$out"; fi

# (c) 多 remote：fetch 別的 remote 不算「baseline 那個 remote 已同步」。
#     FETCH_HEAD 是 repo-global 的，拿它的 mtime 當新鮮度會讓 origin 的 stale ref
#     從側門被當成新鮮——正是本節其餘測試想擋的失效模式
git init --bare -q -b main "$TMP/mr-origin.git"
git init --bare -q -b main "$TMP/mr-other.git"
git init -q -b main "$TMP/mr-work"
(cd "$TMP/mr-work" \
    && echo a > f && "${GITC[@]}" add f && "${GITC[@]}" commit -qm c1 \
    && git remote add origin "$TMP/mr-origin.git" && git remote add other "$TMP/mr-other.git" \
    && git push -q origin main && git push -q other main \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
    && echo b >> f && "${GITC[@]}" commit -qam c2 && git push -q origin main)
# origin 端 rewind 掉 c2（force-push 情境），本機 origin/main 仍指向 c2
mr_first="$(git -C "$TMP/mr-work" rev-parse HEAD~1)"
git -C "$TMP/mr-origin.git" update-ref refs/heads/main "$mr_first"
git -C "$TMP/mr-work" fetch -q other      # 只碰 other，卻會更新 repo-global FETCH_HEAD
out="$("$GH_SCRIPT" "$TMP/mr-work")"
if grep -q "verdict: CLEAN" <<< "$out"; then
    bad "fetch 別的 remote 後仍判 CLEAN（freshness 未綁 remote）：$out"
else ok "多 remote：fetch other 不會讓 origin 的 stale ref 過關"; fi

# (d) squash merge 後 remote branch 被刪：commit 已經以 squash 形式進了 default，
#     baseline 退回 default 會把它們算成「未 push」——PR 是 MERGED 時不該計入殘留
#     fixture 名前綴 hyg-：第 9 節（ship-state）另有一組同語意的 sq-work/sq-origin，
#     兩節共用 $TMP，撞名會讓後建的那組 `git init` 落在既有 repo 上（re-init + remote
#     already exists），fixture 靜默不成立、斷言整批假紅。前綴是唯一防線，勿改回裸 sq-。
git init --bare -q -b main "$TMP/hyg-sq-origin.git"
git init -q -b main "$TMP/hyg-sq-work"
(cd "$TMP/hyg-sq-work" \
    && echo a > f && "${GITC[@]}" add f && "${GITC[@]}" commit -qm c1 \
    && git remote add origin "$TMP/hyg-sq-origin.git" && git push -q origin main \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
    && git switch -qc feat/sq && echo b > g && "${GITC[@]}" add g && "${GITC[@]}" commit -qm "feat: sq" \
    && git push -q origin feat/sq)
git -C "$TMP/hyg-sq-origin.git" update-ref -d refs/heads/feat/sq   # merge 後刪 remote branch
git -C "$TMP/hyg-sq-work" rev-parse HEAD > "$TMP/hyg-head-oid"     # PR 合併當下的 head = 現在的 HEAD
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-merged" "$GH_SCRIPT" "$TMP/hyg-sq-work")"
if grep -q "verdict: RESIDUE" <<< "$out"; then
    bad "MERGED + remote branch 已刪仍判 RESIDUE（與『MERGED 不算殘留』矛盾）：$out"
else ok "MERGED + remote branch 已刪 → 不判 RESIDUE"; fi

# (f) MERGED 不可掩蓋「合併之後才寫的 commit」——那些是真殘留。
#     撤銷的依據必須是 PR 的 headRefOid，不能因為 state=MERGED 就整批清掉
(cd "$TMP/hyg-sq-work" && echo after > after.txt && "${GITC[@]}" add after.txt \
    && "${GITC[@]}" commit -qm "feat: 合併後才寫的")
# headRefOid 仍停在 PR 合併當下那顆（上一行的新 commit 不在其中）
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-merged" "$GH_SCRIPT" "$TMP/hyg-sq-work")"
if grep -q "verdict: RESIDUE" <<< "$out"; then
    ok "MERGED 後新增的 commit → 仍判 RESIDUE"
else bad "MERGED 掩蓋了合併後新增的 commit（假 CLEAN）：$out"; fi

# headRefOid 拿不到時必須保守：不可撤銷（寧可誤報殘留，不可誤報乾淨）
: > "$TMP/hyg-head-oid"
out="$(GIT_HYGIENE_GH="$TMP/hyg-gh-merged" "$GH_SCRIPT" "$TMP/hyg-sq-work")"
if grep -q "verdict: CLEAN" <<< "$out"; then
    bad "headRefOid 不可得時仍撤銷 unpushed（假 CLEAN）：$out"
else ok "headRefOid 不可得 → 保守不撤銷"; fi

# (e) fetch 必須有硬上限：本機可能沒有 timeout/gtimeout，不能靠外部指令
#     ext:: transport 直接執行指令當 transport，是純本地製造「fetch 卡住」的可靠方法
git init -q -b main "$TMP/slow-work"
(cd "$TMP/slow-work" \
    && git config protocol.ext.allow always \
    && echo a > f && "${GITC[@]}" add f && "${GITC[@]}" commit -qm c1 \
    && git remote add origin "ext::sleep 30")
slow_start="$(date +%s)"
out="$(GIT_HYGIENE_FETCH_TIMEOUT=2 "$GH_SCRIPT" "$TMP/slow-work" 2>/dev/null)"
slow_elapsed=$(( $(date +%s) - slow_start ))
#     界線由契約推導，不是拍腦袋的寬鬆值：每個 fetch 目標最多 FETCH_TIMEOUT + KILL_GRACE
#     秒，本 fixture 只有 origin 一個目標 → 2+1=3s，再給 3s 餘裕吸收 process 啟動（實測 2s）。
#     放寬到十幾秒等於讓「每個 repo 卡 10 秒」的 regression 照樣綠，多 repo 時還會累加。
#     改 fixture 的 remote 數時照 (timeout+grace)×目標數 重算，不要直接調大這個數字。
slow_budget=6
if [ "$slow_elapsed" -lt "$slow_budget" ]; then
    ok "fetch 卡住 → 在上限內放棄（實測 ${slow_elapsed}s，界線 ${slow_budget}s）"
else bad "fetch 卡住未被中斷（${slow_elapsed}s ≥ ${slow_budget}s，宣告的上限不存在）"; fi
if grep -q "remote: UNKNOWN" <<< "$out"; then
    ok "fetch 逾時 → remote 標 UNKNOWN"
else bad "fetch 逾時未標 remote UNKNOWN：$out"; fi

# (g) fetch 成功時不可還等滿 timeout：watchdog 的 sleep 若持有輸出 pipe，
#     command substitution 會等到它結束才收到 EOF——每個 repo 都固定耗掉整個上限
fast_start="$(date +%s)"
out="$(GIT_HYGIENE_FETCH_TIMEOUT=6 "$GH_SCRIPT" "$TMP/gh-work" 2>/dev/null)"
fast_elapsed=$(( $(date +%s) - fast_start ))
if [ "$fast_elapsed" -lt 4 ]; then
    ok "本地 remote fetch 成功 → 立刻返回（實測 ${fast_elapsed}s，上限 6s）"
else bad "fetch 成功仍等滿 watchdog timeout（${fast_elapsed}s）"; fi

# (i) 多 repo 單次呼叫：SKILL.md Step 1 要求一次帶完所有 session repo。彙總有兩個失效
#     方向——漏印某個 repo 的區段，或讓某個 repo 的 RESIDUE/UNKNOWN 被另一個的 CLEAN
#     蓋掉（exit 0 = 全 CLEAN，是使用者唯一會看的那個數字）。此前所有呼叫都是單 repo，
#     聚合迴圈與 overall exit code 完全沒有覆蓋。
git init --bare -q -b main "$TMP/mrepo-o1.git"
git init --bare -q -b main "$TMP/mrepo-o2.git"
git init -q -b main "$TMP/mrepo-clean"
(cd "$TMP/mrepo-clean" && echo a > a.txt && "${GITC[@]}" add a.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/mrepo-o1.git" && git push -q -u origin main)
git init -q -b main "$TMP/mrepo-residue"
(cd "$TMP/mrepo-residue" && echo a > a.txt && "${GITC[@]}" add a.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/mrepo-o2.git" && git push -q -u origin main \
    && echo wip > untracked.txt)
git init -q -b main "$TMP/mrepo-unknown"
(cd "$TMP/mrepo-unknown" && echo a > a.txt && "${GITC[@]}" add a.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/mrepo-nonexistent.git")

# 前置：三個 repo 單獨跑時各自是 CLEAN / RESIDUE / UNKNOWN——沒有這條，下面的彙總
# 斷言可能只是因為 fixture 根本沒造出三種狀態而「剛好對」
for mrepo_case in "clean:CLEAN" "residue:RESIDUE" "unknown:UNKNOWN"; do
    mrepo_name="${mrepo_case%%:*}"; mrepo_want="${mrepo_case##*:}"
    mrepo_one="$(GIT_HYGIENE_GH=/usr/bin/false "$GH_SCRIPT" "$TMP/mrepo-${mrepo_name}" 2>/dev/null)"
    if grep -q "verdict: ${mrepo_want}" <<< "$mrepo_one"; then
        ok "fixture 前置：mrepo-${mrepo_name} 單獨跑為 ${mrepo_want}"
    else bad "fixture 前置不成立：mrepo-${mrepo_name} 不是 ${mrepo_want}：$mrepo_one"; fi
done

# CLEAN 排最前面：先看到 CLEAN 不能讓後面的殘留被吞掉
mrepo_out="$(GIT_HYGIENE_GH=/usr/bin/false "$GH_SCRIPT" \
    "$TMP/mrepo-clean" "$TMP/mrepo-residue" "$TMP/mrepo-unknown" 2>/dev/null)"
mrepo_rc=$?
assert_rc "多 repo：任一 RESIDUE/UNKNOWN → exit 1" 1 "$mrepo_rc"
mrepo_sections="$(grep -c '^=== ' <<< "$mrepo_out")"
assert_eq "多 repo：三個 repo 的區段都印出（不漏 repo）" "3" "$mrepo_sections"
assert_eq "多 repo：verdict 逐 repo 各自成立（1 CLEAN / 1 RESIDUE / 1 UNKNOWN）" \
    "1 1 1" \
    "$(grep -c 'verdict: CLEAN' <<< "$mrepo_out") $(grep -c 'verdict: RESIDUE' <<< "$mrepo_out") $(grep -c 'verdict: UNKNOWN' <<< "$mrepo_out")"

# CLEAN 排最後面：反方向再測一次，擋「用最後一個 repo 的結果覆寫 overall」這種寫法
mrepo_out="$(GIT_HYGIENE_GH=/usr/bin/false "$GH_SCRIPT" \
    "$TMP/mrepo-residue" "$TMP/mrepo-unknown" "$TMP/mrepo-clean" 2>/dev/null)"
mrepo_rc=$?
assert_rc "多 repo：CLEAN 排最後仍 exit 1（overall 不被最後一個覆寫）" 1 "$mrepo_rc"

# 全 CLEAN 才是 exit 0——否則上面兩條可能只是「永遠回 1」
mrepo_out="$(GIT_HYGIENE_GH=/usr/bin/false "$GH_SCRIPT" "$TMP/mrepo-clean" "$TMP/mrepo-clean" 2>/dev/null)"
mrepo_rc=$?
assert_rc "多 repo：全部 CLEAN → exit 0" 0 "$mrepo_rc"

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

# --- branch 與**自己的** remote tracking ref 分岔（只比對 default 會漏）---
# 缺口實據：2026-08-07 跑 eval 時，是受測 agent 自己去 `branch -vv` 才發現分岔——
# 腳本所有訊號都在講「對 default 領先多少」，push 那一刻才被 non-fast-forward 拒。
git init --bare -q "$TMP/bd-origin.git"
git init -q -b main "$TMP/bd-work"
(cd "$TMP/bd-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/bd-origin.git" && git push -qu origin main)

out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bd-work")"
if ! grep -q '^branch-diverged:' <<< "$out"; then ok "在 default 上 → 不報 branch-diverged"; else bad "default 誤報分岔（${out}）"; fi

# feature branch 尚未 push → 無從分岔，必須靜默（噪音會讓訊號被學會忽略）
(cd "$TMP/bd-work" && git switch -qc feat/bd \
    && echo a > a.txt && "${GITC[@]}" add a.txt && "${GITC[@]}" commit -qm "feat: a")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bd-work")"
if ! grep -q '^branch-diverged:' <<< "$out"; then ok "未 push 過的 branch → 不報分岔"; else bad "未 push 的 branch 誤報分岔（${out}）"; fi

# push 之後單純領先（正常 ship 途中的常態）→ 仍須靜默
(cd "$TMP/bd-work" && git push -qu origin feat/bd \
    && echo b > b.txt && "${GITC[@]}" add b.txt && "${GITC[@]}" commit -qm "feat: b")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bd-work")"
if ! grep -q '^branch-diverged:' <<< "$out"; then ok "純領先 upstream → 不報分岔"; else bad "純領先誤報成分岔（${out}）"; fi

# 純落後：別台主機/另一個 session 推過，本地只是舊的（fetch 過但沒 merge）
git clone -q "$TMP/bd-origin.git" "$TMP/bd-other"
(cd "$TMP/bd-other" && git switch -q feat/bd \
    && echo c > c.txt && "${GITC[@]}" add c.txt && "${GITC[@]}" commit -qm "feat: c" \
    && git push -q origin feat/bd)
(cd "$TMP/bd-work" && git reset -q --hard origin/feat/bd && git fetch -q origin)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bd-work")"
if grep -q '^branch-diverged:' <<< "$out"; then ok "落後自己的 upstream → 報 branch-diverged"; else bad "落後 upstream 完全沒訊號（${out}）"; fi
if grep -qE '^branch-diverged: .*零領先' <<< "$out"; then ok "純落後與真分岔的措辭分開（處置不同）"; else bad "純落後被講成 push 會被拒（處置會被導錯）"; fi

# 真分岔：本地在落後狀態上又 commit → 互不為祖先，push 必被拒
(cd "$TMP/bd-work" && echo d > d.txt && "${GITC[@]}" add d.txt && "${GITC[@]}" commit -qm "feat: d")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bd-work")"
if grep -qE '^branch-diverged: .*已分岔' <<< "$out"; then ok "與 upstream 互不為祖先 → 報已分岔"; else bad "真分岔未被偵測（${out}）"; fi
if grep -q 'non-fast-forward' <<< "$out"; then ok "分岔訊號說明後果（push 會被拒）"; else bad "分岔訊號未說明後果"; fi
if grep -q 'force-with-lease' <<< "$out"; then ok "處置給 --force-with-lease（不給裸 --force）"; else bad "處置未指定 lease"; fi
# 負面斷言鎖「可照抄的裸指令形式」，不鎖字串 `--force` 本身——處置文案裡的「勿裸 --force」
# 是**警語**，把它一起判紅會逼人刪掉警語來過測試（第一版就誤中，正是這個形狀）
if grep -qE 'push +--force([^-]|$)' <<< "$out"; then bad "處置給出裸 push --force（照抄會蓋掉遠端別人的 commit）"; else ok "處置不含可照抄的裸 push --force"; fi

# 沒設 upstream 但已 push（`git push origin <b>` 不帶 -u，常態）→ 仍須以同名 tracking ref 受檢。
# 只認 @{upstream} 會讓這一整批 branch 完全不受檢，而它們正是最容易被別台主機推過的一批。
(cd "$TMP/bd-work" && git switch -qc feat/bd-noup \
    && echo e > e.txt && "${GITC[@]}" add e.txt && "${GITC[@]}" commit -qm "feat: e" \
    && git push -q origin feat/bd-noup)
if (cd "$TMP/bd-work" && git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1); then
    bad "fixture 前提失效：feat/bd-noup 竟有 upstream（fallback 分支測不到）"
else
    ok "fixture 前提成立：feat/bd-noup 無 upstream"
    (cd "$TMP/bd-work" && "${GITC[@]}" commit -q --amend -m "feat: e (rewritten)")
    out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/bd-work")"
    if grep -qE '^branch-diverged: .*已分岔' <<< "$out"; then ok "無 upstream 者退用同名 tracking ref，分岔仍被偵測"; else bad "無 upstream 的已 push branch 不受檢（${out}）"; fi
fi

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

# --- dossier 章節完整性：整節被刪必須被抓到 ---
# 簽章只要求「任一」專屬章節在，尺寸 flag 只管上限——兩者都攔不住「刪掉整節」。
# 2026-08-06 實地踩過：兩整節被誤刪、行數反而變少、一路 merge 進 main 才發現。
mkdir -p "$TMP/ds-full"
cat > "$TMP/ds-full/STATUS.md" <<'DOSSIER'
# STATUS.md
專案一句話定位(更新日期:2026-08-06)

## 進行中
- 一個工作項

## 關鍵決策(附理由)
- 一條決策

## 死路(試過但放棄——防重工)
- 一條死路

## 技術債
- 一條技術債

## 已完成(里程碑)
- ✅ 一個里程碑

## 已知缺口
- 一條缺口

## 移交準備度
(暫無)
DOSSIER
# 需有 remote：無 remote 時 ship-state 在 verdict: STOP 就返回，dossier 檢查根本跑不到
# （前一版漏了這點，「七節齊全→不報」那條是假綠——輸出裡沒有該字串只是因為沒執行）
git init --bare -q "$TMP/ds-full-origin.git"
(cd "$TMP/ds-full" && git init -q -b main . && "${GITC[@]}" add STATUS.md && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/ds-full-origin.git" && git push -qu origin main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-full" 2>/dev/null)"
if grep -q "缺少規範章節" <<< "$out"; then bad "完整的 dossier 誤報缺章節"; else ok "七節齊全 → 不報缺章節"; fi

# 刪掉兩節（模擬邊界判斷吃掉尾段）→ 必須抓到
python3 - "$TMP/ds-full/STATUS.md" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(s[:s.index("## 已知缺口")])
PYEOF
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-full" 2>/dev/null)"
if grep -q "缺少規範章節" <<< "$out" && grep -q "已知缺口" <<< "$out" && grep -q "移交準備" <<< "$out"; then ok "整節被刪 → 印缺少規範章節並列出是哪幾節"; else bad "整節被刪未被抓到（尺寸 flag 抓不到、簽章也放行）"; fi

# --- review 痕跡偵測（Step 4 squash 選項的判定依據；prose 下沉）---
# 為何下沉：判「哪些 commit 算 review 迭代痕跡」需要 deep-review 的權威 subject 清單，
# model 憑印象比對會把使用者自己的 `fix: 修正某某` 當痕跡建議壓掉，而使用者一句「好」
# 就 force-push 了。reset 目標 hash 同理，不讓 model 湊。
git clone -q "$TMP/sb-origin.git" "$TMP/rr-work"   # 沿用 stale-branches 段的 origin（同段 fixture，baseline 明確）
(cd "$TMP/rr-work" && git switch -qc feat/rr \
    && echo r1 > r.txt && "${GITC[@]}" add r.txt && "${GITC[@]}" commit -qm "feat: 使用者的語意實作")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-work")"
if grep -q "^review-residue: none" <<< "$out"; then ok "無 review 痕跡 → review-residue: none"; else bad "無痕跡卻未印 none（${out}）"; fi

# 頂端連續段 → 可安全 reset（目標 = 第一顆語意 commit，不動它以下）
rr_feat="$(git -C "$TMP/rr-work" rev-parse HEAD)"
(cd "$TMP/rr-work" && echo r2 > r.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo r3 > r.txt && "${GITC[@]}" commit -qam "fix: address external review findings")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-work")"
if grep -q "^review-residue: 2 顆" <<< "$out"; then ok "review-residue 計數正確"; else bad "review-residue 計數錯誤（${out}）"; fi
if grep -q "top-contiguous: 2 顆" <<< "$out"; then ok "頂端連續段顆數正確"; else bad "頂端連續段錯誤"; fi
if grep -qE "^  squash-cmd: git -C .* reset --soft ${rr_feat}( |\$)" <<< "$out"; then ok "squash-cmd 指向第一顆語意 commit（腳本解析，model 不湊 hash）"; else bad "squash-cmd 目標錯誤"; fi   # 路徑取 toplevel（realpath），只驗 hash；hash 後可接說明註解
if grep -q "buried:" <<< "$out"; then bad "無 buried 卻誤印"; else ok "無 buried 時不印該行"; fi

# 被非 review commit 隔開（Step 3 的 docs commit 壓在最上）→ reset --soft 壓不到，
# 須改印整支全壓指令，且明示會連語意 commit 一起收
(cd "$TMP/rr-work" && echo r4 > r.txt && "${GITC[@]}" commit -qam "docs: 同步 dossier")
rr_mb="$(git -C "$TMP/rr-work" merge-base origin/main HEAD)"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-work")"
if grep -q "top-contiguous:" <<< "$out"; then bad "頂端非 review commit 卻報 top-contiguous"; else ok "頂端被隔開 → 不報可安全壓的連續段"; fi
if grep -q "buried: 2 顆" <<< "$out"; then ok "被隔開的痕跡計為 buried"; else bad "buried 計數錯誤（${out}）"; fi
if grep -qE "^  squash-all-cmd: git -C .* reset --soft ${rr_mb} " <<< "$out"; then ok "buried 時改印整支全壓指令"; else bad "缺 squash-all-cmd"; fi
if grep -q "會連語意 commit 一起收" <<< "$out"; then ok "全壓指令附後果警語"; else bad "全壓指令缺警語"; fi

# --- 跨 Step 時序：Step 1 的 hash 是「使用者語意 commit 的邊界」，Step 3 之後不得重算 ---
# 2026-08-06 一次真實回歸的重現：曾把規則改成「套用當下重跑」，但 Step 3 的 docs commit 會讓
# 頂端連續段恆為 0、verdict 從 top-contiguous 翻成 buried，現場只剩會壓掉語意 commit 的全壓
# 指令——使用者勾的處置沒有對應指令可執行。連兩輪 review 沒被測試擋住，故在此釘死。
git clone -q "$TMP/sb-origin.git" "$TMP/rr-time"
(cd "$TMP/rr-time" && git switch -qc feat/t \
    && echo t1 > t.txt && "${GITC[@]}" add t.txt && "${GITC[@]}" commit -qm "feat: 使用者的語意實作" \
    && echo t2 > t.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo t3 > t.txt && "${GITC[@]}" commit -qam "fix: address review findings")
rr_t_feat="$(git -C "$TMP/rr-time" rev-parse HEAD~2)"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-time")"       # 模擬 Step 1
rr_t_hash="$(grep -oE "reset --soft [0-9a-f]{40}" <<< "$out" | head -1 | awk '{print $3}')"
if [ "$rr_t_hash" = "$rr_t_feat" ]; then ok "Step 1 的 squash-cmd 指向使用者語意 commit（邊界）"; else bad "Step 1 hash 未指向語意 commit"; fi

(cd "$TMP/rr-time" && echo t4 > t.txt && "${GITC[@]}" commit -qam "docs: 同步 dossier")   # 模擬 Step 3
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-time")"
if grep -q "top-contiguous:" <<< "$out"; then bad "Step 3 後仍報 top-contiguous（測試前提失效，重看 detect_review_residue）"; else ok "Step 3 後 top-contiguous 消失——這就是不得重算的理由"; fi
if grep -q "buried: 2 顆" <<< "$out"; then ok "Step 3 後形狀翻轉為 buried（重算只會剩全壓指令）"; else bad "buried 未如預期出現"; fi

(cd "$TMP/rr-time" && git reset --soft "$rr_t_hash")                     # 模擬 Step 4 用 Step 1 的 hash
if [ "$(git -C "$TMP/rr-time" rev-parse HEAD)" = "$rr_t_feat" ]; then ok "用 Step 1 的 hash reset → 停在使用者語意 commit"; else bad "reset 目標錯誤"; fi
if [ "$(git -C "$TMP/rr-time" rev-list --count origin/main..HEAD)" = "1" ]; then ok "語意 commit 保留、其上全部收攏"; else bad "語意 commit 未保留"; fi
if [ -n "$(git -C "$TMP/rr-time" diff --cached --name-only)" ]; then ok "review 痕跡 + 本輪 docs 進 index（內容零損失）"; else bad "index 為空（內容遺失）"; fi

# --- top-contiguous 與 buried 同時出現：SKILL 為此專列一行處置，須有守門 ---
git clone -q "$TMP/sb-origin.git" "$TMP/rr-both"
(cd "$TMP/rr-both" && git switch -qc feat/b2 \
    && echo b1 > b.txt && "${GITC[@]}" add b.txt && "${GITC[@]}" commit -qm "feat: 第一段語意" \
    && echo b2 > b.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo b3 > b.txt && "${GITC[@]}" commit -qam "feat: 第二段語意" \
    && echo b4 > b.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo b5 > b.txt && "${GITC[@]}" commit -qam "fix: address external review findings")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-both")"
if grep -q "^review-residue: 3 顆" <<< "$out"; then ok "混合情境總數正確"; else bad "混合情境總數錯誤"; fi
if grep -q "top-contiguous: 2 顆" <<< "$out" && grep -q "buried: 1 顆" <<< "$out"; then ok "混合情境兩組訊號並存"; else bad "混合情境訊號缺失（SKILL 有此列處置卻無守門）"; fi
if grep -qE "^  squash-cmd: " <<< "$out" && grep -qE "^  squash-all-cmd: " <<< "$out"; then ok "混合情境兩條指令都印（由使用者選，不由 agent 併）"; else bad "混合情境指令不全"; fi

# --- lib 缺席 → UNKNOWN 降級（不猜、不 set -u 爆炸）---
mkdir -p "$TMP/ss-nolib"
cp "$SS_SCRIPT" "$TMP/ss-nolib/ship-state.sh"      # 不複製 ../../deep-review/scripts/lib/
out="$(SHIP_STATE_GH="$TMP/gh-open" "$TMP/ss-nolib/ship-state.sh" "$TMP/rr-both" 2>&1)"
assert_rc "lib 缺席 → ship-state 照常完成（不因缺 pattern 而死）" 0 $?
if grep -q "^review-residue: UNKNOWN" <<< "$out"; then ok "lib 缺席 → review-residue 降級 UNKNOWN"; else bad "缺 UNKNOWN 降級（model 會被迫憑印象猜）"; fi
if grep -q "^protection:" <<< "$out"; then ok "lib 缺席不影響其餘偵測輸出"; else bad "lib 缺席拖垮了其他輸出"; fi

# --- review-terminal：上一場審查是「R5 終止」收場時，ship 前必須停 ---
# 為何存在：Step 4 改成「說法關鍵字即授權、不再逐批確認」後，原本那道確認 gate 會順帶
# 接住的「這批還沒審完」就沒人接了。拆掉守衛就得補上它接住的東西——這不是為沒見過的
# 問題加規則，是為新造出的暴露補償。
# 鑑別力來源是 ancestry：anchor 存在 .git/ 下、跨 branch 共用，只憑「有沒有 terminal_reason」
# 會讓一場舊終止把之後每一批都擋住。terminal_head 必須是當前 HEAD 的祖先才算涵蓋這批。
RA_FOR_SS="$ROOT/claude/skills/deep-review/scripts/review-anchor.sh"
git clone -q "$TMP/sb-origin.git" "$TMP/rt-work"
(cd "$TMP/rt-work" && git switch -qc feat/rt \
    && echo t1 > t.txt && "${GITC[@]}" add t.txt && "${GITC[@]}" commit -qm "feat: 待審的實作")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rt-work")"
if grep -q "^review-terminal:" <<< "$out"; then bad "無 anchor 卻報 review-terminal（會把每一批都擋住）"; else ok "無 anchor → 不印 review-terminal"; fi

# 正常審查中（record 過但未終止）→ 不得誤報：那是進行中，不是終止收場
"$RA_FOR_SS" record --repo "$TMP/rt-work" --mode branch-diff --base origin/main >/dev/null
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rt-work")"
if grep -q "^review-terminal:" <<< "$out"; then bad "anchor 存在但未終止卻報 review-terminal"; else ok "anchor 存在但無 terminal_reason → 不報"; fi

# R5 終止 → 必須印訊號且壓成 STOP（走真腳本寫入，順帶守住兩支腳本間的 anchor 格式漂移）
"$RA_FOR_SS" terminate --repo "$TMP/rt-work" --reason r5-blocking >/dev/null
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rt-work")"
if grep -q "^review-terminal: r5-blocking" <<< "$out"; then ok "terminal 且為祖先 → 印 review-terminal"; else bad "R5 終止未被偵測（未審完的變更會被關鍵字一路送出）"; fi
if grep -q "^verdict: STOP" <<< "$out"; then ok "review-terminal 壓成 verdict: STOP"; else bad "缺 STOP——說法關鍵字會直接覆蓋掉這道攔截"; fi
if grep -q "^ship-path:" <<< "$out"; then ok "STOP 之外的偵測輸出照常保留"; else bad "review-terminal 早退吃掉了其餘輸出"; fi

# 換到另一條由 default 長出的 branch → terminal_head 非祖先 → 那場終止與這批無關，須靜默
(cd "$TMP/rt-work" && git switch -q main && git switch -qc feat/rt-other \
    && echo o1 > o.txt && "${GITC[@]}" add o.txt && "${GITC[@]}" commit -qm "feat: 另一批工作")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rt-work")"
if grep -q "^review-terminal:" <<< "$out"; then bad "非祖先的舊終止仍攔截（每批都會被擋，訊號會被學會忽略）"; else ok "terminal_head 非祖先 → 不攔（那是別批的事）"; fi

# terminal_head 指向已不存在的物件（歷史被重建/gc）→ 無法鑑別，一律 fail-safe 報出來
(cd "$TMP/rt-work" && git switch -q feat/rt)
python3 - "$TMP/rt-work/.git/deep-review/anchor" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert "terminal_head=" in s, "fixture 前提失效：anchor 無 terminal_head"
p.write_text(re.sub(r"^terminal_head=.*$", "terminal_head=" + "0" * 40, s, flags=re.M))
PYEOF
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rt-work")"
if grep -q "^review-terminal:" <<< "$out"; then ok "terminal_head 物件不存在 → fail-safe 仍報"; else bad "物件不存在時靜默放行（fail-open）"; fi

# origin/HEAD 存在時（真實 clone 的常態）：其 short form 是**裸 remote 名**（"origin"），
# 不是 branch——列進去會污染清單並讓 cleanup-cmd 拼出 `--deleteorigin`（實地跑真 repo 才
# 抓到，原 fixture 無 origin/HEAD 故漏測）
(cd "$TMP/sb-work" && git remote set-head origin main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sb-work")"
if ! echo "$out" | grep -qE "^  remote: origin$"; then ok "origin/HEAD 不被當成殘留 branch"; else bad "裸 remote 名混入殘留清單（${out}）"; fi
# remote 側的刪除**一律走 cleanup-stale-branch.sh**（執行當下 ls-remote 重驗 + lease），
# **絕不退化成裸 `push --delete`**：local 側有 git 自己把關（`-d` 對未併入的 branch 直接拒），
# remote 側沒有等價保護——偵測後有人推過，裸刪就把那些 commit 從唯一的副本上砍掉。
if echo "$out" | grep -qE "^  cleanup-cmd: .*cleanup-stale-branch\.sh .+ remote "; then ok "remote 殘留附 cleanup-stale-branch.sh（帶執行當下重驗）"; else bad "remote 殘留缺帶重驗的刪除指令（${out}）"; fi
if echo "$out" | grep -qE "push .*--delete"; then bad "remote 刪除退回裸 push --delete（無 lease、無執行當下重驗）"; else ok "cleanup-cmd 不含裸 push --delete"; fi
if echo "$out" | grep -qF "remote 'origin/"; then bad "cleanup-cmd 的 remote branch 名未剝 remote 前綴"; else ok "cleanup-cmd 剝除 remote 前綴"; fi
# expected SHA 必須是該 tracking ref 的當下 tip。給錯就一律 STOP——指令看起來還在、實際上
# 每次照抄都被擋，等於訊號默默廢掉（且失敗長相像「有人推過」，會誤導去查不存在的第二寫入者）
sb_exp="$(git -C "$TMP/sb-work" rev-parse refs/remotes/origin/feat/old-merged)"
if echo "$out" | grep -qE "^  cleanup-cmd: .*remote 'feat/old-merged' ${sb_exp}\$"; then ok "cleanup-cmd 帶正確的 expected SHA（＝tracking ref 當下 tip）"; else bad "cleanup-cmd 的 expected SHA 不符 tracking ref tip（照抄必被 STOP）"; fi

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

# 當前 branch 的 **remote 對應**同樣不得列入（2026-08-07 實地誤報：意外 push 了一條指向
# main tip 的同名 branch，腳本排除了 local 卻沒排除 origin/<當前 branch>，於是建議刪掉
# 「本次正要送出的那條」——照抄就會把自己的 branch 從遠端砍掉）
(cd "$TMP/sb-work" && git switch -q feat/old-merged)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sb-work")"
if ! echo "$out" | grep -qE "^  remote: origin/feat/old-merged"; then ok "當前 branch 的 remote 對應不列入殘留"; else bad "把當前 branch 的 remote 對應列為可刪（照抄會砍掉正要送出的 branch）"; fi
(cd "$TMP/sb-work" && git switch -q main)

# 端到端：把 remote 的 cleanup-cmd **照抄執行**，遠端 branch 必須真的消失。
# 為何不只比對字串：上面驗的是「拼出來的樣子」，拼對了仍可能整條跑不動——參數順序、
# quoting、SHA 位置任一錯都是**靜默失敗**，腳本回 STOP，而 STOP 的長相與「偵測後有人推過」
# 這個正常保護一模一樣，讀不出是 bug。獨立 fixture（sbe- 前綴），不動上面共用的 sb-work。
# ⚠ 路徑要換成 $ROOT 下的腳本：輸出裡的 `~/.claude/skills/...` 是**主 checkout** 的 symlink
# 目標，在 worktree／乾淨 clone 上跑到的是別一份（見 claude/CLAUDE.md 已知地雷最後一條）。
git init --bare -q "$TMP/sbe-origin.git"
git init -q -b main "$TMP/sbe-work"
(cd "$TMP/sbe-work" \
    && echo hi > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/sbe-origin.git" && git push -qu origin main \
    && git switch -qc feat/e2e-merged && git push -qu origin feat/e2e-merged \
    && git switch -q main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/sbe-work")"
sbe_cmd="$(grep -E '^  cleanup-cmd: .*cleanup-stale-branch\.sh .+ remote ' <<< "$out" | head -1 | sed 's/^  cleanup-cmd: //')"
sbe_args="${sbe_cmd#*cleanup-stale-branch.sh }"
if [ -n "$sbe_cmd" ] && [ "$sbe_args" != "$sbe_cmd" ]; then
    # `$0` 帶路徑、引數維持原樣照抄——腳本路徑本身不是本次要驗的東西，引數拼接才是
    if bash -c '"$0" '"$sbe_args" "$ROOT/claude/skills/project/scripts/cleanup-stale-branch.sh" >/dev/null 2>&1; then ok "照抄 remote cleanup-cmd 可實際刪除（參數拼接端到端成立）"; else bad "照抄 remote cleanup-cmd 執行失敗（STOP／參數錯，訊號等於廢掉）"; fi
    if git -C "$TMP/sbe-work" ls-remote --heads origin feat/e2e-merged 2>/dev/null | grep -q .; then bad "照抄後遠端 branch 仍在（指令實際沒生效）"; else ok "照抄後遠端殘留 branch 確實消失"; fi
else
    bad "未取得 remote 的 cleanup-cmd（fixture 前提失效）"
fi

# --- squash-merge 盲視（B1：只加訊號，不產生 -D 指令）---
# 為何存在：`git branch --merged` 判的是**祖先關係**，而 squash-merge 在 default 上產生
# 一顆全新 commit、與 branch 無祖先鏈——內容零損失卻永遠偵測不到。**本 repo 家規正是
# squash-merge**，等於這條訊號對主要情境完全無效；而既有 fixture 用「branch 不加 commit」
# （純祖先）才會綠，是「測試綠、功能無效」的教科書形狀。
# 判準取 `gh pr list` 的 merged PR：**headRefOid 必須等於本機 branch tip** 才算數——
# 同名 branch 事後又有新工作時 SHA 會不同，那些 commit 不在 default 上，列進去就是誘導刪掉。
make_gh_prlist_stub() {   # $1=路徑 $2=headRefOid $3=owner $4=額外 PR 筆數(湊 limit 用)
    cat > "$1" <<STUB
#!/usr/bin/env bash
case "\$*" in
    *nameWithOwner*) echo "acme/widget" ;;
    *viewerPermission*) echo "READ" ;;
    *"/protection"*) echo "gh: Branch not protected (HTTP 404)"; exit 1 ;;
    *"rules/branches"*) echo '[]' ;;
    *"pr list"*)
        printf '12\tfeat/squashed\t%s\t%s\n' "$2" "$3"
        i=0
        while [ "\$i" -lt "$4" ]; do
            printf '%d\tfiller-%d\tdeadbeef\tacme\n' "\$((100+i))" "\$i"
            i=\$((i+1))
        done ;;
esac
STUB
    chmod +x "$1"
}

# fixture：squash-merge 的真實形狀——branch 有自己的 commit，main 上是「內容相同但另一顆」
git init --bare -q "$TMP/sq-origin.git"
git init -q -b main "$TMP/sq-work"
(cd "$TMP/sq-work" \
    && echo base > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/sq-origin.git" && git push -qu origin main \
    && git switch -qc feat/squashed && echo feature > f.txt && "${GITC[@]}" commit -qam "feat: 功能" \
    && git push -qu origin feat/squashed \
    && git switch -q main && echo feature > f.txt && "${GITC[@]}" commit -qam "feat: 功能 (#12)" \
    && git push -q origin main)
sq_tip="$(git -C "$TMP/sq-work" rev-parse feat/squashed)"

# 前提自檢：祖先判定看不到它（看得到就代表 fixture 沒造出 squash-merge 的形狀，後面全是假的）
if ! grep -qx 'feat/squashed' <<< "$(git -C "$TMP/sq-work" branch --merged origin/main --format='%(refname:short)')"; then
    ok "fixture 前提成立：squash-merge 後 branch --merged 看不到它（結構盲視）"
else bad "fixture 未造出 squash-merge 形狀（branch 仍是祖先，後續斷言全部失效）"; fi

make_gh_prlist_stub "$TMP/gh-sq" "$sq_tip" acme 0
out="$(SHIP_STATE_GH="$TMP/gh-sq" "$SS_SCRIPT" "$TMP/sq-work")"
if grep -q "^squash-merged-branches:" <<< "$out"; then ok "squash-merge 的殘留 branch 被偵測"; else bad "squash-merged branch 漏偵測（家規就是 squash-merge，等於訊號無效）"; fi
if grep -q "feat/squashed" <<< "$out"; then ok "列出 branch 名與 PR 編號"; else bad "未列出 squash-merged branch"; fi
if grep -qE "^  scan: complete" <<< "$out"; then ok "未達 limit → scan: complete"; else bad "缺 scan 狀態（達 limit 與否無從分辨）"; fi
if grep -q "cleanup-stale-branch.sh" <<< "$out"; then ok "清掃走專用腳本（執行當下重驗 SHA），不給裸 -D"; else bad "squash-merged 段給了裸刪除指令或無指令"; fi
if grep -qE "^  (local|remote): .*feat/squashed.* -[dD] " <<< "$out"; then bad "squash-merged 段出現裸 -D"; else ok "squash-merged 段不產生裸 -D 指令"; fi

# headRefOid 與本地 tip 不符（同名 branch 已有新工作）→ 只印診斷，**不列入清理**
make_gh_prlist_stub "$TMP/gh-sq-mismatch" 0000000000000000000000000000000000000000 acme 0
out="$(SHIP_STATE_GH="$TMP/gh-sq-mismatch" "$SS_SCRIPT" "$TMP/sq-work")"
if grep -q "SHA mismatch" <<< "$out"; then ok "headRefOid 不符 → 印診斷"; else bad "SHA 不符卻無診斷（靜默）"; fi
if grep -qE "^  (local|remote): .*feat/squashed" <<< "$out"; then bad "SHA 不符仍列入可清理（會誘導刪掉不在 default 上的 commit）"; else ok "SHA 不符 → 不列入清理清單"; fi

# fork 來源的 PR 不採信（headRefName 同名但那是別人 repo 的 branch）
make_gh_prlist_stub "$TMP/gh-sq-fork" "$sq_tip" outsider 0
out="$(SHIP_STATE_GH="$TMP/gh-sq-fork" "$SS_SCRIPT" "$TMP/sq-work")"
if grep -qE "^  (local|remote): .*feat/squashed" <<< "$out"; then bad "採信了 fork 來源的 PR"; else ok "fork 來源不採信"; fi

# 達 limit → partial，**絕不輸出 none**（截斷處靜默＝謊報「掃完了、沒有」）
make_gh_prlist_stub "$TMP/gh-sq-limit" "$sq_tip" acme 199
out="$(SHIP_STATE_GH="$TMP/gh-sq-limit" "$SS_SCRIPT" "$TMP/sq-work")"
if grep -qE "^  scan: partial" <<< "$out"; then ok "結果數達 limit → scan: partial"; else bad "達 limit 未標 partial（截斷被當成掃完）"; fi

# gh 不可用 → partial，且不得宣稱沒有殘留
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/gh-sq-dead"; chmod +x "$TMP/gh-sq-dead"
out="$(SHIP_STATE_GH="$TMP/gh-sq-dead" "$SS_SCRIPT" "$TMP/sq-work" 2>/dev/null)"
if grep -qE "^squash-merged-branches: none" <<< "$out"; then bad "gh 失敗卻宣稱 none（查不到不等於沒有）"; else ok "gh 失敗 → 不宣稱 none"; fi

# --- B1b：remote 行必須以**遠端事實**為準，不得拿本地 tracking 殘影當殘留 ---
# 形狀：`gh pr merge --delete-branch` 之後遠端 branch 已不存在，但本機沒 prune，
# `refs/remotes/origin/<name>` 還在。只讀本地 ref 就會把「本地沒 prune」報成「遠端有殘留」。
# 危害不是誤刪（清理端 `cleanup-stale-branch.sh` 會 ls-remote 重驗並 STOP），而是**真有殘留時
# 分不出哪支是真的**——訊號一旦混入虛報就失去可信度，正是本 repo 最在意的「結論高於證據」。
# 同一支腳本的 `detect_stale_branches` 早就知道這個殘影問題（見其註解），只是選了另一種緩解；
# 這裡改為對齊 `cleanup-stale-branch.sh` 的判準：直接問遠端。
git init --bare -q -b main "$TMP/sqs-origin.git"
git init -q -b main "$TMP/sqs-work"
(cd "$TMP/sqs-work" \
    && echo base > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
    && git remote add origin "$TMP/sqs-origin.git" && git push -q origin main \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
    && git switch -qc feat/squashed && echo feature > f.txt && "${GITC[@]}" commit -qam "feat: 功能" \
    && git push -q -u origin feat/squashed \
    && git switch -q main && echo feature > f.txt && "${GITC[@]}" commit -qam "feat: 功能 (#12)" \
    && git push -q origin main)
sqs_tip="$(git -C "$TMP/sqs-work" rev-parse feat/squashed)"
git -C "$TMP/sqs-origin.git" update-ref -d refs/heads/feat/squashed   # 模擬 --delete-branch

# 前置自檢：缺任一條，下面的斷言就不是在測它宣稱要測的東西
if [ -z "$(git -C "$TMP/sqs-origin.git" for-each-ref --format='%(refname:short)' refs/heads/feat/squashed)" ]; then
    ok "fixture 前置：遠端已無 feat/squashed"
else bad "fixture 未刪掉遠端 branch，虛報情境不成立（後續斷言失效）"; fi
if git -C "$TMP/sqs-work" rev-parse --verify -q origin/feat/squashed >/dev/null; then
    ok "fixture 前置：本地 tracking 殘影仍在（未 prune）"
else bad "fixture 的本地殘影不存在，虛報情境不成立（後續斷言失效）"; fi

make_gh_prlist_stub "$TMP/gh-sqs" "$sqs_tip" acme 0
out="$(SHIP_STATE_GH="$TMP/gh-sqs" "$SS_SCRIPT" "$TMP/sqs-work")"
if grep -qE "^  local: feat/squashed" <<< "$out"; then ok "本地 branch 仍列出（那是真殘留）"; else bad "連真的本地殘留也漏掉：$out"; fi
if grep -qE "^  remote: origin/feat/squashed" <<< "$out"; then
    bad "拿本地 tracking 殘影當遠端殘留（虛報——遠端其實已無該 branch）：$out"
else ok "遠端已刪 → remote 行不列入（以遠端事實為準）"; fi
if grep -qE "^  skipped: feat/squashed — 遠端已無" <<< "$out"; then
    ok "殘影有診斷（使用者知道該 prune，不是靜默消失）"
else bad "殘影被靜默丟棄，使用者不知道本地要 prune：$out"; fi

# ls-remote 失敗 → **不得**靜默把 remote 行丟掉（查不到 ≠ 沒有，與 gh 失敗那條同判準）
(cd "$TMP/sqs-work" && git remote set-url origin "$TMP/sqs-nonexistent.git")
out="$(SHIP_STATE_GH="$TMP/gh-sqs" "$SS_SCRIPT" "$TMP/sqs-work" 2>/dev/null)"
if grep -qE "^  remote: origin/feat/squashed.*未驗證" <<< "$out"; then
    ok "ls-remote 失敗 → remote 行保留並標「未驗證」"
else bad "ls-remote 失敗時把 remote 行靜默丟掉、或未標未驗證：$out"; fi
(cd "$TMP/sqs-work" && git remote set-url origin "$TMP/sqs-origin.git")

# --- B2：cleanup-stale-branch.sh（破壞性刪除，執行當下重驗）---
# 為何要專用腳本而非照抄 `git branch -D`：偵測與刪除之間有 TOCTOU 窗口——ship-state 印出
# 訊號後，另一個 session（或使用者自己）可能在那支 branch 上又 commit 了東西。照抄的 `-D`
# 對此完全無感，砍下去就砍了；把 expected SHA 綁在**執行當下**重驗才關得掉那個窗口。
CL_SCRIPT="$ROOT/claude/skills/project/scripts/cleanup-stale-branch.sh"
mk_cl_repo() {   # $1=路徑；造 main + feat/gone（local + remote）
    rm -rf "$1"
    git init --bare -q "$1-origin.git"
    git init -q -b main "$1"
    (cd "$1" && echo a > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init \
        && git remote add origin "$1-origin.git" && git push -qu origin main \
        && git switch -qc feat/gone && echo b > f.txt && "${GITC[@]}" commit -qam "feat: gone" \
        && git push -qu origin feat/gone && git switch -q main)
}

mk_cl_repo "$TMP/cl-work"
cl_tip="$(git -C "$TMP/cl-work" rev-parse feat/gone)"

# SHA 相符 → 刪得掉（local）
out="$("$CL_SCRIPT" "$TMP/cl-work" local feat/gone "$cl_tip" 2>&1)"; rc=$?
assert_rc "SHA 相符 → local 刪除成功（exit 0）" 0 $rc
if ! git -C "$TMP/cl-work" rev-parse --verify -q feat/gone >/dev/null; then ok "local branch 已刪除"; else bad "回報成功卻沒刪掉（${out}）"; fi

# SHA 不符（branch 在偵測之後又前進）→ STOP，且**不得刪**
mk_cl_repo "$TMP/cl-moved"
cl_old="$(git -C "$TMP/cl-moved" rev-parse feat/gone)"
(cd "$TMP/cl-moved" && git switch -q feat/gone && echo c > f.txt && "${GITC[@]}" commit -qam "feat: 別的 session 又推進了" && git switch -q main)
out="$("$CL_SCRIPT" "$TMP/cl-moved" local feat/gone "$cl_old" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then ok "SHA 不符 → 非 0 退出"; else bad "SHA 不符卻回報成功（TOCTOU 窗口沒關）"; fi
if git -C "$TMP/cl-moved" rev-parse --verify -q feat/gone >/dev/null; then ok "SHA 不符 → branch 原封不動（零 mutation）"; else bad "SHA 不符仍把 branch 刪了（不可逆）"; fi
if grep -q "STOP" <<< "$out"; then ok "SHA 不符 → 輸出 STOP verdict"; else bad "缺 STOP verdict（${out}）"; fi

# 當前 checked-out 的 branch → 拒刪（git 自己也會拒，但要給清楚 verdict 而非 git 的錯誤訊息）
mk_cl_repo "$TMP/cl-cur"
cl_cur_tip="$(git -C "$TMP/cl-cur" rev-parse feat/gone)"
(cd "$TMP/cl-cur" && git switch -q feat/gone)
out="$("$CL_SCRIPT" "$TMP/cl-cur" local feat/gone "$cl_cur_tip" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then ok "刪當前 branch → 非 0 退出"; else bad "刪掉了自己腳下那支"; fi
if grep -q "STOP" <<< "$out"; then ok "刪當前 branch → 輸出 STOP verdict"; else bad "缺 STOP verdict（${out}）"; fi

# remote 刪除：帶 lease，SHA 相符才刪
mk_cl_repo "$TMP/cl-rem"
cl_rem_tip="$(git -C "$TMP/cl-rem" rev-parse feat/gone)"
out="$("$CL_SCRIPT" "$TMP/cl-rem" remote feat/gone "$cl_rem_tip" 2>&1)"; rc=$?
assert_rc "SHA 相符 → remote 刪除成功（exit 0）" 0 $rc
if ! git -C "$TMP/cl-rem" ls-remote --heads origin feat/gone | grep -q .; then ok "remote branch 已刪除"; else bad "remote 未刪除（${out}）"; fi

# remote SHA 不符 → STOP，遠端原封不動
mk_cl_repo "$TMP/cl-rem-moved"
cl_rm_old="$(git -C "$TMP/cl-rem-moved" rev-parse feat/gone)"
(cd "$TMP/cl-rem-moved" && git switch -q feat/gone && echo d > f.txt && "${GITC[@]}" commit -qam "feat: 遠端也前進了" && git push -q origin feat/gone && git switch -q main)
out="$("$CL_SCRIPT" "$TMP/cl-rem-moved" remote feat/gone "$cl_rm_old" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then ok "remote SHA 不符 → 非 0 退出"; else bad "remote SHA 不符卻刪了"; fi
if git -C "$TMP/cl-rem-moved" ls-remote --heads origin feat/gone | grep -q .; then ok "remote SHA 不符 → 遠端 branch 仍在"; else bad "remote SHA 不符仍刪掉遠端（不可逆）"; fi
# lease 是第二道防線（拿掉前置比對它照樣會擋），故另立一條看**前置檢查本身**還在不在——
# 少了這條，前置比對可以被整段刪掉而全綠：使用者拿到的會是 git 的 lease 錯誤訊息而非 STOP
if grep -q "STOP" <<< "$out"; then ok "remote SHA 不符 → 輸出 STOP verdict（前置比對，不倚賴 lease 兜底）"; else bad "remote SHA 不符只靠 lease 擋（輸出是 git 錯誤，非 STOP verdict）"; fi

# 引數與環境錯誤：用法錯 → 2；非 git repo → 非 0；branch 不存在 → STOP
"$CL_SCRIPT" "$TMP/cl-work" local feat/gone >/dev/null 2>&1; assert_rc "引數不足 → exit 2" 2 $?
"$CL_SCRIPT" "$TMP/cl-work" bogus feat/gone "$cl_tip" >/dev/null 2>&1; assert_rc "未知 scope → exit 2" 2 $?
mkdir -p "$TMP/cl-notgit"
if ! "$CL_SCRIPT" "$TMP/cl-notgit" local feat/gone "$cl_tip" >/dev/null 2>&1; then ok "非 git repo → 非 0 退出"; else bad "非 git repo 卻回報成功"; fi
out="$("$CL_SCRIPT" "$TMP/cl-work" local feat/nonexistent "$cl_tip" 2>&1)"
if grep -q "STOP" <<< "$out"; then ok "branch 不存在 → STOP（不當成已刪成功）"; else bad "branch 不存在未給 STOP（${out}）"; fi

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
if echo "$out" | grep -qF "push -u 'origin' 'main'"; then ok "BOOTSTRAP 附可照抄 push 指令（remote/branch 均已 quote）"; else bad "BOOTSTRAP 缺 bootstrap-cmd"; fi
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

## 死路（試過但放棄）
- 試過 Z，放棄

## 技術債
- 一條債

## 已知缺口
- 一條缺口

## 移交準備度
（暫無）
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

# append-only 章節的**別名家族**：規範是「NEVER add an append-only log section」，不是
# 「不要叫 Session Log」——只認一個字面時，換個名字就整個漏掉。訊息須附**實際命中的
# heading**，否則別名命中卻回報 Session Log，處置會指向錯的章節。
for ao_name in "變更紀錄" "變更記錄" "工作日誌" "開發日誌" "CHANGELOG" "Change Log" "Session Log（2026-08）"; do
    { echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 項目"; echo; echo "## ${ao_name}"; echo "- 條目"; } > "$TMP/ds-work/STATUS.md"
    out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
    if echo "$out" | grep -q "dossier-flag:.*append-only log：## ${ao_name}"; then
        ok "append-only 別名「${ao_name}」→ flag（訊息附實際 heading）"
    else
        bad "append-only 別名「${ao_name}」未偵測或訊息未附實際 heading"
    fi
done
# 負向：討論性章節不得誤報——gate 誤報的代價是逼人把安全寫法改壞以求過測
for ao_safe in "為何不使用 Change Log" "Session Log 的替代方案" "已完成(里程碑)"; do
    { echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 項目"; echo; echo "## ${ao_safe}"; echo "- 條目"; } > "$TMP/ds-work/STATUS.md"
    out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
    if echo "$out" | grep -q "dossier-flag:.*append-only log"; then
        bad "討論性章節「${ao_safe}」被誤報成 append-only log"
    else
        ok "討論性章節「${ao_safe}」→ 不誤報"
    fi
done

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

# 分節 bytes 必須把**標題行本身**算進它開啟的那一節：歸零會讓各節加總系統性少掉每個標題
# 的長度，讀表的人會以為有一塊沒被算到。此 fixture 無 fence、節數 < TOP_N，故加總應**恰好**
# 等於檔案 bytes（差額只可能來自標題行被漏計）。
{ echo "# 測試專案 STATUS"
  awk 'BEGIN { s = "前言填充"; for (i = 0; i < 20; i++) s = s "內容"; for (r = 0; r < 300; r++) print s }'
  echo; echo "## 進行中"; echo "- x"
  echo; echo "## 關鍵決策（附理由）"; echo "- y"
  echo; echo "## 已完成（里程碑）"; echo "- z"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
sec_sum="$(echo "$out" | grep '^dossier-sections:' | grep -oE ' [0-9]+ \([0-9]+%\)' | grep -oE '[0-9]+ ' | LC_ALL=C awk '{ t += $1 } END { print t+0 }')"
file_bytes="$(LC_ALL=C wc -c < "$TMP/ds-work/STATUS.md" | tr -d ' ')"
if [ "${sec_sum:-0}" = "$file_bytes" ]; then ok "分節 bytes 加總 == 檔案 bytes（標題行已計入所屬節）"; else bad "分節加總 ${sec_sum:-0} ≠ 檔案 ${file_bytes}（標題行未計入，佔比表恆偏低）"; fi

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

# 作用域比對必須**錨在標題開頭**，不是子字串：`## 進行中（已完成 M1）` 含「已完成」三個字，
# 子字串版會把整個進行中章節當里程碑節掃進來——而 spec 區合法偏大，於是恆誤報。
# 這種標題是自然寫法（記錄里程碑進度），不是刻意刁難的 fixture。
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中（已完成 M1）"
  awk 'BEGIN { s = "- 工作項 spec："; for (i = 0; i < 70; i++) s = s "合約細節"; print s }'
  echo; echo "## 已完成（里程碑）"; echo "- ✅ 無"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*最大條目"; then bad "標題含「已完成」的進行中章節被當成里程碑節（作用域用子字串比對，未端錨定）"; else ok "節名端錨定：`## 進行中（已完成 M1）` 不被當成里程碑節"; fi

# ✅ 掃描同型：`## 已完成（進行中殘項）` 含「進行中」，子字串版會把里程碑的 ✅ 當成
# 「進行中章節有已完成項」而誤報。此處進行中章節本身沒有 ✅，故不得印該 flag。
{ echo "# 測試專案 STATUS"; echo; echo "## 進行中"; echo "- 還在做的事"
  echo; echo "## 已完成（進行中殘項）"; echo "- ✅ 2026-07-01 某里程碑"; } > "$TMP/ds-work/STATUS.md"
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/ds-work")"
if echo "$out" | grep -q "dossier-flag:.*✅"; then bad "標題含「進行中」的里程碑節，其 ✅ 被當成進行中章節的（✅ 掃描未端錨定）"; else ok "✅ 掃描節名端錨定（不被標題內的「進行中」三字騙到）"; fi

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

# 現行中性格式（主 agent 階段 + codex 階段）在 round 端也要認得——上面只驗到舊的 R{N} 格式，
# review-state 側對主要格式的 ^(...)$ 錨定屬未測路徑
(cd "$TMP/rs-work" && echo v5 > f.txt && "${GITC[@]}" commit -qam "fix: address review findings")
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "round: 3"; then ok "中性主格式計入 round"; else bad "中性主格式未被 round 偵測認出"; fi
(cd "$TMP/rs-work" && echo v6 > f.txt && "${GITC[@]}" commit -qam "fix: address external review findings")
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "round: 4"; then ok "codex 階段格式計入 round"; else bad "codex 階段格式未被 round 偵測認出"; fi

# 使用者自寫的 fix: 中斷連續段 → 輪次歸零重算。
# 注意 round 與 squash 是刻意不同的集合：`wip:` 中斷 round、卻會被 squash 收攏，
# 兩者邊界因此不同（見 review-state.sh 註解），不要把這兩組斷言互相對齊。
(cd "$TMP/rs-work" && echo v7 > f.txt && "${GITC[@]}" commit -qam "fix: 修正邊界處理")
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "round: 1"; then ok "使用者自寫的 fix: 中斷連續段 → round 歸 1"; else bad "使用者的 fix: 未中斷計數（會灌水吃掉 R5 預算）"; fi

# 跨場次殘留不得灌進新一場：上一場被語意 commit 隔開而未壓掉的 review commit（squash-note
# 情境）仍在 branch 下層，新一場的輪次只能數自己這段——全範圍計數在此會得 round 5。
(cd "$TMP/rs-work" && echo v8 > f.txt && "${GITC[@]}" commit -qam "fix: address review findings")
out="$("$RS_SCRIPT" "$TMP/rs-work")"
if echo "$out" | grep -q "round: 2"; then ok "更早場次的殘留 review commit 不計入新一場"; else bad "跨場次殘留灌進 round（白吃修復輪次額度）"; fi

# wip snapshot 位於連續段底部（真實流程的位置）→ 不算輪次，也不影響其上 fix 的計數
git clone -q "$TMP/rs-origin.git" "$TMP/rs-wip"
(cd "$TMP/rs-wip" && git switch -qc feat/wip \
    && echo w1 > w.txt && "${GITC[@]}" add w.txt && "${GITC[@]}" commit -qm "wip: pre-review snapshot" \
    && echo w2 > w.txt && "${GITC[@]}" commit -qam "fix: address review findings")
out="$("$RS_SCRIPT" "$TMP/rs-wip")"
if echo "$out" | grep -q "round: 2"; then ok "wip snapshot 不算輪次（其上的 fix 照常計）"; else bad "wip snapshot 計數錯誤"; fi

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
if echo "$out" | grep -qF "branch-cmd: git -C '$TMP/rs-clean' switch -c <type>/<slug>"; then ok "branch-cmd 印出待填指令"; else bad "branch-cmd 缺失"; fi
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

# --- 錨點完整性：寫入端原子輸出 ---
# 部分失敗仍印 created:/anchor: 的話，agent 會把「少一條錨點」的半成品貼進 frontmatter，
# 而 cmd_verify 只在**完全無錨點**時才判 UNVERIFIABLE——少一條時它什麼都不說，那個 repo
# 的交接內容從此沒有 checksum。stdout/stderr 必須分開捕捉：用 2>&1 驗原子輸出契約等於自廢武功
git init -q -b main "$TMP/ha-work2"
(cd "$TMP/ha-work2" && echo v1 > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init)

out="$("$HA_SCRIPT" anchors "$TMP/ha-work" "$TMP/not-a-repo" 2>/dev/null)"
assert_rc "anchors 混合 good/bad → exit 1" 1 $?
if [ -z "$out" ]; then ok "混合 good/bad → stdout 全空（不留半成品錨點）"
else bad "部分失敗仍輸出錨點行（${out}）"; fi

# unborn HEAD：合法 repo 但尚無 commit（新 repo 剛 git init 正是會寫交接檔的時機）。
# `rev-parse HEAD` 失敗卻沒被檢查時，字面字串 "HEAD" 被寫進 sha 欄位且 rc=0，之後
# verify 拿 HEAD^{commit} 解析永遠等於當下 HEAD → **永久判 FRESH**，比沒有錨點更糟
git init -q -b main "$TMP/ha-empty"
out="$("$HA_SCRIPT" anchors "$TMP/ha-work" "$TMP/ha-empty" 2>/dev/null)"
assert_rc "anchors 遇 unborn HEAD → exit 1" 1 $?
if [ -z "$out" ]; then ok "unborn HEAD → stdout 全空"
else bad "unborn HEAD 仍輸出錨點（${out}）"; fi

err="$("$HA_SCRIPT" anchors "$TMP/ha-empty" 2>&1 >/dev/null)"
if grep -q "尚無 commit" <<< "$err"; then ok "unborn HEAD 錯誤訊息點名「尚無 commit」（可操作）"
else bad "unborn HEAD 錯誤訊息不可操作（${err}）"; fi

# 成功路徑不得被原子化改壞
out="$("$HA_SCRIPT" anchors "$TMP/ha-work" "$TMP/ha-work2")"
assert_rc "anchors 兩個好 repo → exit 0" 0 $?
assert_eq "多 repo 恰一行 created" "1" "$(grep -c '^created: ' <<< "$out")"
assert_eq "多 repo 恰兩行 anchor" "2" "$(grep -c '^anchor: ' <<< "$out")"

# --- 錨點完整性：驗證端 canonical object ID ---
# 只修寫入端擋不住**既存**的壞錨點：手寫 head=HEAD 的檔案照樣會被判 FRESH。
# 判準用「解析結果 == 記錄值」而非硬編長度——SHA-1 是 40 hex、SHA-256 是 64 hex
mkdir -p "$TMP/ha-oid"
printf -- '---\ncreated: %s\nanchor: %s/ha-work main HEAD dirty=0\n---\n' \
    "$(date +%Y-%m-%d)" "$HA_REAL" > "$TMP/ha-oid/head-literal.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-oid/head-literal.md")"
assert_rc "verify head=HEAD 的錨點 → exit 1" 1 $?
if grep -q "BAD-ANCHOR" <<< "$out" && ! grep -q "status: FRESH" <<< "$out"; then
    ok "head=HEAD → BAD-ANCHOR（不得判 FRESH）"
else bad "head=HEAD 被當成有效錨點（${out}）"; fi

# 短 sha 同理——腳本檔頭早就警告它會隨物件增長變 ambiguous，這裡把警告變成守門
ha_short="$(git -C "$TMP/ha-work" rev-parse --short HEAD)"
printf -- '---\ncreated: %s\nanchor: %s/ha-work main %s dirty=0\n---\n' \
    "$(date +%Y-%m-%d)" "$HA_REAL" "$ha_short" > "$TMP/ha-oid/short-sha.md"
out="$("$HA_SCRIPT" verify "$TMP/ha-oid/short-sha.md")"
assert_rc "verify 短 sha 錨點 → exit 1" 1 $?
if grep -q "BAD-ANCHOR" <<< "$out"; then ok "短 sha → BAD-ANCHOR（刻意收緊）"
else bad "短 sha 未被判 BAD-ANCHOR（${out}）"; fi

# SHA-256 repo 的正常路徑：長度期望由該 repo 的 rev-parse 推導，不在測試裡再硬編一次數字
if git init -q -b main --object-format=sha256 "$TMP/ha-256" 2>/dev/null; then
    (cd "$TMP/ha-256" && echo v1 > f.txt && "${GITC[@]}" add f.txt && "${GITC[@]}" commit -qm init)
    ha256_sha="$(git -C "$TMP/ha-256" rev-parse HEAD)"
    out="$("$HA_SCRIPT" anchors "$TMP/ha-256")"
    assert_rc "anchors SHA-256 repo → exit 0" 0 $?
    assert_eq "SHA-256 錨點記完整 OID" "$ha256_sha" "$(awk '/^anchor: /{print $4}' <<< "$out")"
    { echo "---"; printf '%s\n' "$out"; echo "---"; } > "$TMP/ha-oid/sha256.md"
    out="$("$HA_SCRIPT" verify "$TMP/ha-oid/sha256.md")"
    assert_rc "verify SHA-256 repo 未動 → exit 0" 0 $?
    if grep -q "verdict: FRESH" <<< "$out"; then ok "SHA-256 repo 判 FRESH（判準不綁 40 hex）"
    else bad "SHA-256 repo 被誤判（${out}）"; fi
else
    bad "本機 git 不支援 --object-format=sha256——64 位 OID 守門未執行（git ≥ 2.29 才有）"
fi

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

# active 檔名就是 <slug>.md，**不得**剝任何前綴——W3 只禁 YYYYMMDD-HHMMSS- 開頭，
# 日期-only 的 slug 合法；剝了會把它比成 `foo`、判成首輪，接著整檔覆寫、前一輪內容無聲蒸發
fp_mk "20260804-dated-slug.md" "20260804-dated-slug"
out="$("$HA_SCRIPT" find-predecessor "20260804-dated-slug" "$FP")"
assert_eq "以日期開頭的合法 slug（active）不被前綴剝除誤判為首輪" \
    "$FP/20260804-dated-slug.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"
rm "$FP/20260804-dated-slug.md"

# archive 取最新用**時戳數值**而非 glob 字典序：legacy 的 `YYYYMMDD-` 第 10 字元是 slug 首字，
# 字典序上排在同日 `YYYYMMDD-HHMMSS-` 之後（'l' > '1'），靠字典序會選到較舊那份
fp_mk "archive/20260807-120000-legacy-mix.md" "legacy-mix"   # 新格式，當日 12:00
fp_mk "archive/20260807-legacy-mix.md" "legacy-mix"          # legacy 無時分秒，視為當日最早
out="$("$HA_SCRIPT" find-predecessor legacy-mix "$FP")"
assert_eq "legacy 與新格式同日並存 → 取真正較新的那份（非字典序末筆）" \
    "$FP/archive/20260807-120000-legacy-mix.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"

# 無 slug: frontmatter 的檔仍採用——舊手寫交接檔沒有該欄位，這是刻意的向後相容、不是漏驗
printf -- '---\ncreated: 2026-08-01\n---\n' > "$FP/archive/20260808-100000-nofm.md"
out="$("$HA_SCRIPT" find-predecessor nofm "$FP")"
assert_eq "無 slug: frontmatter 的檔仍採用（向後相容，契約如此）" \
    "$FP/archive/20260808-100000-nofm.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"

# `YYYYMMDD-<slug>` 與 `YYYYMMDD-HHMMSS-<slug>` 在 slug 恰以「6 位數字-」開頭時無法從檔名
# 區分（20260807-120000-foo 可讀成 slug=foo 或 slug=120000-foo）。歧義消不掉 → 兩種解讀都試，
# 否則正確的那個 slug 反而找不到自己的前一份
printf -- '---\nslug: 120000-ambig\n---\n' > "$FP/archive/20260807-120000-ambig.md"
out="$("$HA_SCRIPT" find-predecessor "120000-ambig" "$FP")"
assert_eq "legacy 檔的 slug 恰以 6 位數字開頭 → 仍定位得到" \
    "$FP/archive/20260807-120000-ambig.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"

# frontmatter 判定只掃第一個 --- 到下一個 ---：正文／code fence 裡的 `slug:` 不算數
# （W3 模板本身就長那樣，交接檔在講 handoff skill 時會把它貼進正文）
# shellcheck disable=SC2016  # 三個反引號是 fixture 的字面 markdown code fence，不是命令替換
printf -- '---\ncreated: 2026-08-01\n---\n# Handoff\n\n```\nslug: other-line\n```\n' \
    > "$FP/archive/20260808-110000-fenced.md"
out="$("$HA_SCRIPT" find-predecessor fenced "$FP")"
assert_eq "正文/code fence 內的 slug: 不得被當成 frontmatter" \
    "$FP/archive/20260808-110000-fenced.md" "$(echo "$out" | sed -n 's/^predecessor: //p')"

# 歧義檔名 **+ 無 slug: frontmatter** → 兩種解讀都合法，同一份必然被兩個 slug 撈到。
# 資訊不足、消不掉，但必須附 AMBIGUOUS note 讓讀取端知道要先確認內容再採用
printf -- '---\ncreated: 2026-08-01\n---\n' > "$FP/archive/20260810-120000-ambignofm.md"
out="$("$HA_SCRIPT" find-predecessor ambignofm "$FP")"
if echo "$out" | grep -q "^note: AMBIGUOUS"; then
    ok "歧義檔名 + 無 metadata → 附 AMBIGUOUS note"
else bad "歧義且無 metadata 卻未標 AMBIGUOUS"; fi
assert_eq "歧義檔確實會被另一個 slug 也撈到（故 note 是必要的，不是裝飾）" \
    "$(echo "$out" | sed -n 's/^predecessor: //p')" \
    "$("$HA_SCRIPT" find-predecessor "120000-ambignofm" "$FP" | sed -n 's/^predecessor: //p')"

# 有 slug: frontmatter 佐證者無歧義 → 不得誤標 AMBIGUOUS
out="$("$HA_SCRIPT" find-predecessor "120000-ambig" "$FP")"
if echo "$out" | grep -q "^note: AMBIGUOUS"; then
    bad "檔內 slug: 已可佐證歸屬，卻誤標 AMBIGUOUS"
else ok "有 slug: 佐證 → 不標 AMBIGUOUS"; fi

# frontmatter 有 slug: 但值為空 → malformed，不可當成「沒有欄位」放行
printf -- '---\nslug:\ncreated: 2026-08-01\n---\n' > "$FP/archive/20260809-100000-emptyfm.md"
out="$("$HA_SCRIPT" find-predecessor emptyfm "$FP")"
if echo "$out" | grep -q "predecessor: NONE"; then
    ok "frontmatter slug: 空值 → 不採用（不等同缺少欄位）"
else bad "空值 slug 被當成缺少欄位而放行"; fi

"$HA_SCRIPT" find-predecessor >/dev/null 2>&1
assert_rc "find-predecessor 無引數 → exit 2" 2 $?
"$HA_SCRIPT" find-predecessor foo "$TMP/no-such-dir" >/dev/null
assert_rc "find-predecessor 目錄不存在 → exit 0" 0 $?

out="$("$HA_SCRIPT" list "$TMP/no-such-dir")"
assert_rc "list 目錄不存在 → exit 0（回報 NONE）" 0 $?
if echo "$out" | grep -q "handoffs: NONE"; then ok "list 無目錄 → NONE"; else bad "list 無目錄輸出錯誤"; fi

# --- survey（W1／R1 單一入口：清理 → active → worklines → predecessor）---
# 存在理由是機制取代散文契約：W1 曾把 `list` 寫成「只在未指定 slug 時跑」，W4 的 EXPIRED 回報
# 與 archive 保留期清理在 `/handoff <slug>` 路徑上雙雙沉默失效。單一無條件呼叫讓該分支不存在。
SV="$TMP/ha-sv"; mkdir -p "$SV/archive"
sv_mk() { printf -- '---\nslug: %s\ncreated: %s\n---\n# Handoff: %s\n' "$2" "$3" "$2" > "$SV/$1"; }
sv_mk "cur.md" "cur" "$(date +%Y-%m-%d)"
sv_mk "old.md" "old" "2026-01-01"
sv_mk "archive/20260801-101500-pipe.md" "pipe" "2026-08-01"
sv_mk "archive/20260803-090000-pipe.md" "pipe" "2026-08-03"
sv_mk "archive/20260802-120000-gate.md" "gate" "2026-08-02"

out="$("$HA_SCRIPT" survey "$SV")"
assert_rc "survey → exit 0" 0 $?
# active 區段必須與 list 逐字等價——兩個入口對同一份 active 目錄給出不同答案的話，
# 「SKILL.md 一律走 survey」就成了行為變更而非單純收斂
assert_eq "survey 的 active 區段與 list 逐字等價" \
    "$("$HA_SCRIPT" list "$SV" | grep -E '^(active: |  path: |  title: )')" \
    "$(grep -E '^(active: |  path: |  title: )' <<< "$out")"
if grep -q "^active: old.md — .* — EXPIRED" <<< "$out"; then ok "survey active 標 EXPIRED"
else bad "survey 未標 EXPIRED"; fi

assert_eq "worklines 依 slug 聚合輪數與最近日期" \
    "workline: pipe — 2 輪 — 最近 2026-08-03" "$(grep '^workline: pipe ' <<< "$out")"
assert_eq "worklines 依最近時戳新到舊排序" "pipe gate" \
    "$(awk '/^workline: /{printf "%s%s", sep, $2; sep=" "}' <<< "$out")"
if ! grep -q '^predecessor: ' <<< "$out"; then ok "未給 --slug → 不印 predecessor 區段"
else bad "未給 --slug 卻印了 predecessor"; fi

out="$("$HA_SCRIPT" survey --slug pipe "$SV")"
assert_eq "--slug 命中 archive 最新一輪" \
    "$HA_REAL/ha-sv/archive/20260803-090000-pipe.md" "$(sed -n 's/^predecessor: //p' <<< "$out")"

# --- archive parser 的三條身分解析政策（predecessor 與 worklines 共用同一份解析）---
printf -- '---\ncreated: 2026-08-04\n---\n' > "$SV/archive/20260804-110000-nofm.md"
printf -- '---\nslug: someone-else\n---\n' > "$SV/archive/20260805-110000-mism.md"
printf -- 'handwritten\n' > "$SV/archive/manual-drop.md"
out="$("$HA_SCRIPT" survey "$SV")"

# ① 歧義檔名 + 無 frontmatter：兩種解讀都合法，標出來讓讀取端先確認內容
if grep -q '^workline: nofm — 1 輪 — 最近 2026-08-04（檔名格式歧義' <<< "$out"; then
    ok "parser ①：歧義檔名 + 無 frontmatter → 標歧義"
else bad "歧義檔名未標記（$(grep '^workline: nofm' <<< "$out")）"; fi

# ② frontmatter 與所有候選都不符：**以檔名歸戶 + 標不可達**，不讓 frontmatter 當索引。
# 這種殘檔 find-predecessor 兩個方向都撈不到（檔名閘門擋 frontmatter 值、frontmatter 閘門
# 擋檔名值），本來完全隱形；正反兩面都要釘，只釘一面會讓「改用 frontmatter 當索引」照樣全綠
if grep -q '^workline: mism — 1 輪 — 最近 2026-08-05（檔內 slug=someone-else' <<< "$out"; then
    ok "parser ②：frontmatter 不符 → 以檔名歸戶並標不可達"
else bad "fm-mismatch 未以檔名歸戶或未標註（$(grep '^workline: mism' <<< "$out")）"; fi
if "$HA_SCRIPT" find-predecessor mism "$SV" | grep -q 'predecessor: NONE' \
    && "$HA_SCRIPT" find-predecessor someone-else "$SV" | grep -q 'predecessor: NONE'; then
    ok "fm-mismatch 檔：查檔名與查 frontmatter 值皆 NONE（frontmatter 是否決權不是索引）"
else bad "fm-mismatch 檔被某個方向撿走了"; fi

# ③ 無歸檔前綴的手工檔：沒有日期來源，但不得因此從清單消失
if grep -q '^workline: manual-drop — 1 輪 — 最近 —（有手工放入' <<< "$out"; then
    ok "parser ③：無歸檔前綴 → 日期印「—」且仍列出"
else bad "無前綴手工檔遺失或格式錯（$(grep '^workline: manual-drop' <<< "$out")）"; fi
assert_eq "無前綴檔排序視為最舊（排在最後，但不得消失）" "manual-drop" \
    "$(awk '/^workline: /{last=$2} END{print last}' <<< "$out")"

# --- worklines 顯示上限：只截顯示並印出略過筆數，不靜默截斷 ---
SVC="$TMP/ha-sv-cap"; mkdir -p "$SVC/archive"
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
    printf -- '---\nslug: wl%s\n---\n' "$i" > "$SVC/archive/202608${i}-120000-wl${i}.md"
done
out="$("$HA_SCRIPT" survey "$SVC")"
assert_eq "worklines 顯示上限 10 條" "10" "$(grep -c '^workline: ' <<< "$out")"
if grep -q '^…（其餘 2 條工作線略）' <<< "$out"; then ok "超出上限印出略過筆數（不靜默截斷）"
else bad "超出上限未印略過筆數"; fi

# --- survey 的 archive 過期清理：**獨立 fixture** ---
# 沿用 list 已清過的目錄會讓斷言變空條件（清過的目錄裡沒東西可清），與 h5/h8 沙盒同一個教訓
SVP="$TMP/ha-sv-prune"; mkdir -p "$SVP/archive"
printf 'consumed\n' > "$SVP/archive/20260101-120000-dead.md"
touch -t 202601011200 "$SVP/archive/20260101-120000-dead.md"
printf 'consumed\n' > "$SVP/archive/20260807-120000-alive.md"
out="$("$HA_SCRIPT" survey "$SVP")"
if [ ! -f "$SVP/archive/20260101-120000-dead.md" ] && [ -f "$SVP/archive/20260807-120000-alive.md" ]; then
    ok "survey 清掉過保留期的已消費交接檔、保留期內的不動"
else bad "survey 的 archive 清理失效"; fi
if grep -q '^archive: 已清 1 份' <<< "$out"; then ok "survey 印出清理摘要"
else bad "survey 未印清理摘要"; fi

# --- TTL × predecessor：清理必須先於任何 archive 衍生輸出 ---
# 某工作線唯一一份 archive 剛好過 TTL 時，先印後刪會讓讀取端拿到 dangling 的
# workline/predecessor 路徑——連「把內容當線索讀」都做不到
SVT="$TMP/ha-sv-ttl"; mkdir -p "$SVT/archive"
printf 'consumed\n' > "$SVT/archive/20260101-120000-gone.md"
touch -t 202601011200 "$SVT/archive/20260101-120000-gone.md"
out="$("$HA_SCRIPT" survey --slug gone "$SVT")"
if ! grep -q '^workline: gone' <<< "$out" && grep -q '^predecessor: NONE' <<< "$out"; then
    ok "唯一一份 archive 過 TTL → 清理先行，不輸出隨即失效的 workline/predecessor"
else bad "survey 印出了會被自己刪掉的 archive 路徑（${out}）"; fi

# --- survey 介面守門 ---
"$HA_SCRIPT" survey "$SV" --slug >/dev/null 2>&1
assert_rc "survey --slug 缺值 → exit 2" 2 $?
"$HA_SCRIPT" survey --slug "" "$SV" >/dev/null 2>&1
assert_rc "survey --slug 空值 → exit 2（不得靜默當成沒給 slug）" 2 $?
"$HA_SCRIPT" survey --bogus "$SV" >/dev/null 2>&1
assert_rc "survey 未知 flag → exit 2" 2 $?
"$HA_SCRIPT" survey "$SV" "$SV" >/dev/null 2>&1
assert_rc "survey 多餘位置參數 → exit 2" 2 $?
out="$("$HA_SCRIPT" survey "$TMP/no-such-dir")"
assert_rc "survey 目錄不存在 → exit 0" 0 $?
if grep -q "handoffs: NONE" <<< "$out"; then ok "survey 無目錄 → NONE"; else bad "survey 無目錄輸出錯誤"; fi

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

# --- 已遷移到 functions.sh 的舊 alias 清理 ---
# 不能靠 functions.sh 裡 unalias：alias 展開優先於 function 查找，而 rc 裡 alias 與
# source 行的相對順序因機器而異（實地 14 台：13 台 source 在後、macmini 在前），
# unalias 會變成「多數生效、少數靜默失效」。故這裡驗的是「確實從 rc 刪行」。
ers_stale="$TMP/rc-stale"
printf 'alias brewup=%s\nalias sysup=%s\nalias ll=%s\nexport KEEP=1\n' "'old-brewup'" "'old-sysup'" "'eza -l'" > "$ers_stale"
RC_FILE="$ers_stale" bash "$ERS" >/dev/null
assert_rc "含舊 alias → exit 0" 0 $?
ers_n=$(grep -cE '^alias (brewup|sysup)=' "$ers_stale")
assert_eq "brewup/sysup alias 已移除" "0" "$ers_n"
if grep -qxF "alias ll='eza -l'" "$ers_stale"; then ok "其他 alias 未被誤刪"; else bad "誤刪了其他 alias"; fi
if grep -qxF 'export KEEP=1' "$ers_stale"; then ok "非 alias 內容保留"; else bad "非 alias 內容遺失"; fi
if grep -qF "$MARKER" "$ers_stale"; then ok "同時補上 source 行"; else bad "未補上 source 行"; fi

# 重跑 → 幂等（已無舊 alias，檔案不再變動）
cp "$ers_stale" "$ers_stale.after1"
RC_FILE="$ers_stale" bash "$ERS" >/dev/null
if diff -q "$ers_stale" "$ers_stale.after1" >/dev/null; then ok "清理後重跑 → 內容不變"; else bad "清理後重跑仍改動檔案"; fi

# 前提檢查：減幅超過 2 行 → 原封不動（守住「破壞性覆寫前先驗行數」那道閘）
# 沒有這條，整段前提檢查可以被刪光而測試照樣全綠。
ers_many="$TMP/rc-many"
printf 'alias brewup=%s\nalias brewup=%s\nalias sysup=%s\nalias sysup=%s\nexport KEEP=1\n' \
    "'a'" "'b'" "'c'" "'d'" > "$ers_many"
cp "$ers_many" "$ers_many.orig"
RC_FILE="$ers_many" bash "$ERS" >/dev/null 2>&1
ers_many_n=$(grep -cE '^alias (brewup|sysup)=' "$ers_many")
assert_eq "減幅 4 行 > 上限 2 → 四行舊 alias 全數保留（未覆寫）" "4" "$ers_many_n"

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

# --- worktree 雙寫入者與 base 建議（純本地判斷：必須在 fetch/upstream 早退之前就跑完，
#     否則離線或無 upstream 的 branch 上整組訊號失效）---

# (7) feature branch 相對 origin/<default> 有未併 commit → base 建議
(cd "$spc/b" && git switch -qc feat/base && echo x > g && git add g && git commit -qm "feat: g")
spc_out="$(cd "$spc/b" && bash "$SPC")"
assert_rc "feature branch 有未併 commit → exit 0" 0 $?
if grep -q "未併 commit" <<< "$spc_out" && grep -q "base 用 head" <<< "$spc_out"; then
    ok "feature branch 有未併 commit → 報 base 建議"
else bad "feature branch 未報 base 建議：$spc_out"; fi
# squash merge 不保留 commit id，origin/<default>..HEAD 在已合併的線上仍非空；
# hook 沒有 PR 狀態可查，只能給保守提示，不可斷言「這條線還沒併」
if grep -q "squash" <<< "$spc_out"; then
    ok "base 建議帶 squash-merge 的保守提示"
else bad "base 建議未提示 squash merge 可能已併入：$spc_out"; fi

# (8) feature branch 無未併 commit（剛開的分支）→ 完全靜默
(cd "$spc/b" && git switch -q main && git switch -qc feat/empty)
spc_out="$(cd "$spc/b" && bash "$SPC")"
assert_eq "feature branch 無未併 commit → 完全靜默" "" "$spc_out"

# (9) default branch 上有未 push commit → 不報 base 建議（刻意收斂：那是 ship 側的事，
#     git-hygiene.sh / /project log 已覆蓋，hook 不重複出聲）
(cd "$spc/b" && git switch -q main && echo y > h && git add h && git commit -qm "chore: h")
spc_out="$(cd "$spc/b" && bash "$SPC")"
if grep -q "base 用 head" <<< "$spc_out"; then
    bad "default branch 誤報 base 建議：$spc_out"
else ok "default branch 有未 push commit → 不報 base 建議"; fi

# (10) 有 linked worktree（clean）→ 報其存在與 branch，不標 dirty
git -C "$spc/b" worktree add -q "$spc/b-wt" -b feat/wt
spc_out="$(cd "$spc/b" && bash "$SPC")"
if grep -q "worktree 使用中" <<< "$spc_out" && grep -q "feat/wt" <<< "$spc_out"; then
    ok "linked worktree → 報 worktree 名與 branch"
else bad "未報 linked worktree：$spc_out"; fi
if grep -q "未 commit 變更" <<< "$spc_out"; then
    bad "clean worktree 誤標 dirty：$spc_out"
else ok "clean worktree → 不標 dirty"; fi

# (11) worktree 的 working tree 髒了 → 標示（dirty 才是「有人正在寫」的實證）
echo dirty > "$spc/b-wt/dirtyfile"
spc_out="$(cd "$spc/b" && bash "$SPC")"
if grep -q "未 commit 變更" <<< "$spc_out"; then
    ok "dirty worktree → 標示有未 commit 變更"
else bad "dirty worktree 未標示：$spc_out"; fi

# (12) 在 linked worktree 內執行 → 仍報另一個 worktree，但**不報 base 建議**
#      （base 是開 worktree 當下才要選的；feat/wt 相對 origin/main 有 commit，
#        少了這道條件就會誤報——故本斷言是條件 1 的守門）
spc_out="$(cd "$spc/b-wt" && bash "$SPC")"
assert_rc "linked worktree 內 → exit 0" 0 $?
if grep -q "worktree 使用中" <<< "$spc_out"; then
    ok "linked worktree 內 → 仍報另一個 worktree"
else bad "linked worktree 內未報 worktree：$spc_out"; fi
if grep -q "base 用 head" <<< "$spc_out"; then
    bad "linked worktree 內誤報 base 建議：$spc_out"
else ok "linked worktree 內 → 不報 base 建議"; fi

# (13) base 建議必須用 fetch 之後的 ref 重算：別台已把這些 commit 併進 default 時，
#      stale 的 origin/<default> 會讓 hook 建議「base 用 head」，而正確答案是沒有未併 commit
git clone -q "$spc/origin.git" "$spc/c" 2>/dev/null
(cd "$spc/c" && git config user.name t && git config user.email t@t.local \
  && git switch -qc feat/merged && echo m > m.txt && git add m.txt && git commit -qm "feat: m")
# 在 origin 端快轉 main（模擬別台 merge 後 push）。兩個坑：
#   1. 直接 update-ref 會失敗——那顆 commit 的 object 只在本機 clone 裡，bare repo 沒有
#      （fatal: trying to write ref with nonexistent object），main 根本不會動
#   2. 但不能用 `push origin HEAD:main` 送 object，那會順手更新本機的 origin/main，
#      stale 情境就沒了
# 故：先推到別名 ref 把 object 送過去，再 update-ref 快轉 main，最後清掉別名。
spc_c_sha="$(git -C "$spc/c" rev-parse HEAD)"
if ! git -C "$spc/c" push -q origin "HEAD:refs/heads/tmp-import" \
    || ! git -C "$spc/origin.git" update-ref refs/heads/main "$spc_c_sha"; then
    bad "fixture 建立失敗：無法在 origin 端快轉 main（下一條斷言將失去意義）"
fi
git -C "$spc/origin.git" update-ref -d refs/heads/tmp-import
rm -f "$spc/c/.git/FETCH_HEAD"
# 前置條件：此刻本機 ref 仍是 stale 的（ahead=1），fetch 之後才會變 0。
# 這條斷言在守 fixture 本身——沒有它，fixture 一壞就會偽裝成「實作有問題」
assert_eq "fixture 前置：fetch 前 ahead=1（stale ref 情境成立）" \
    "1" "$(git -C "$spc/c" rev-list --count origin/main..HEAD 2>/dev/null)"
spc_out="$(cd "$spc/c" && bash "$SPC")"
if grep -q "base 用 head" <<< "$spc_out"; then
    bad "base 建議未用 fetch 後的 ref 重算（stale origin/<default> 造成誤報）：$spc_out"
else ok "base 建議在 fetch 後重算 → 已併入 default 時不再誤報"; fi

# (14) 多 remote：fetch 別的 remote 讓 FETCH_HEAD 變新鮮，但 origin/<default> 仍是舊的。
#      base 建議固定比較 origin/<default>，不能把「剛 fetch 過某個 remote」當成它新鮮
git init --bare -q -b main "$spc/mr-other.git"
git clone -q "$spc/origin.git" "$spc/d" 2>/dev/null
(cd "$spc/d" && git config user.name t && git config user.email t@t.local \
  && git remote add other "$spc/mr-other.git" && git push -q other main \
  && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
  && git switch -qc feat/mr && echo mr > mr.txt && git add mr.txt && git commit -qm "feat: mr")
spc_d_sha="$(git -C "$spc/d" rev-parse HEAD)"
if ! git -C "$spc/d" push -q origin "HEAD:refs/heads/tmp-mr" \
    || ! git -C "$spc/origin.git" update-ref refs/heads/main "$spc_d_sha"; then
    bad "fixture 建立失敗：無法在 origin 端快轉 main（下一條斷言將失去意義）"
fi
git -C "$spc/origin.git" update-ref -d refs/heads/tmp-mr
git -C "$spc/d" fetch -q other        # 只碰 other，卻讓 repo-global FETCH_HEAD 變新鮮
assert_eq "fixture 前置：origin/<default> 仍 stale（ahead=1）" \
    "1" "$(git -C "$spc/d" rev-list --count origin/main..HEAD 2>/dev/null)"
spc_out="$(cd "$spc/d" && bash "$SPC")"
if grep -q "base 用 head" <<< "$spc_out" && ! grep -q "可能已過期" <<< "$spc_out"; then
    bad "fetch 別的 remote 後仍給無警告的 base 建議（stale origin/<default>）：$spc_out"
else ok "多 remote：未實際 fetch baseline remote → base 建議不出現或帶過期警告"; fi

# (15) 多 remote 的落後偵測：剛 fetch 過別的 remote 會讓 repo-global 的 FETCH_HEAD 變新鮮，
#      但 upstream（origin/main）的 tracking ref 仍是舊的。拿快取當「upstream 已刷新」的
#      證據 → 真正落後的 clone 完全不出聲。這是 false negative，配上 hook「失敗一律靜默」
#      的契約更難察覺——(14) 只保護 base 建議那一半，這條保護落後偵測那一半。
git init --bare -q -b main "$spc/mr2-other.git"
git clone -q "$spc/origin.git" "$spc/e" 2>/dev/null
(cd "$spc/e" && git config user.name t && git config user.email t@t.local \
  && git remote add other "$spc/mr2-other.git" && git push -q other main)
spc_e_old="$(git -C "$spc/e" rev-parse HEAD)"
(cd "$spc/e" && echo behind > behind.txt && git add behind.txt && git commit -qm c4 && git push -q origin main)
# 本機退回舊 commit，並把 tracking ref 一起退回 → 不 fetch 就看不出落後
(cd "$spc/e" && git reset -q --hard "$spc_e_old")
git -C "$spc/e" update-ref refs/remotes/origin/main "$spc_e_old"
git -C "$spc/e" fetch -q other        # 只碰 other，卻讓 repo-global FETCH_HEAD 變新鮮
assert_eq "fixture 前置：stale 的 origin/main 看不出落後（behind=0）" \
    "0" "$(git -C "$spc/e" rev-list --count HEAD..origin/main 2>/dev/null)"
assert_eq "fixture 前置：origin 端實際已前進 1 個 commit" \
    "1" "$(git -C "$spc/origin.git" rev-list --count "${spc_e_old}..refs/heads/main" 2>/dev/null)"
spc_out="$(cd "$spc/e" && bash "$SPC")"
if grep -q "落後" <<< "$spc_out"; then
    ok "多 remote：fetch other 不會讓落後偵測改用 stale upstream 判定"
else bad "多 remote：真實落後的 clone 未提醒（fetch other 讓 FETCH_HEAD 假新鮮）：$spc_out"; fi

# (16) fetch 真的失敗（單 remote，快取不介入）→ base 建議仍要出，但必須帶過期警告。
#      (14) 在多 remote 快取失效後走的是「建議不出現」那一臂，這條把「出現且帶警告」
#      那一臂釘住，否則 stale_note 整段會變成沒有測試覆蓋的死碼。
git clone -q "$spc/origin.git" "$spc/f" 2>/dev/null
(cd "$spc/f" && git config user.name t && git config user.email t@t.local \
  && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
  && git switch -qc feat/stale && echo s > s.txt && git add s.txt && git commit -qm "feat: stale")
(cd "$spc/f" && git remote set-url origin "$spc/nonexistent.git")
rm -f "$spc/f/.git/FETCH_HEAD"        # 強制真的去 fetch（而且會失敗）
spc_out="$(cd "$spc/f" && bash "$SPC")"
assert_rc "fetch 失敗 + feature branch → exit 0" 0 $?
if grep -q "base 用 head" <<< "$spc_out" && grep -q "可能已過期" <<< "$spc_out"; then
    ok "fetch 失敗 → base 建議帶「可能已過期」警告"
else bad "fetch 失敗後的 base 建議未標示 ref 可能過期：$spc_out"; fi

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

# brewup 也必須接上：allup 走的是 brewup 而非 dotsync，只掛 dotfiles-sync 等於
# 「日常全機隊更新」不重建 symlink，來源檔改名時該連結靜默失效。
for wiring_file in setup-mac-env.sh setup-linux-env.sh scripts/dotfiles-sync.sh scripts/brewup.sh; do
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

for wiring_file in setup-mac-env.sh setup-linux-env.sh scripts/dotfiles-sync.sh scripts/brewup.sh; do
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

echo "▶ 18d. brewup.sh helper 部署與失敗告知（全隔離）"
# brewup 除了 helper 還會跑 git / brew / claude / jq 與 cp known_hosts。fixture 必須同時
# 隔離 DOTFILES_DIR、HOME 與 PATH——否則這節測試本身會去動真的 repo、真的 Homebrew 與真的 $HOME。
BUP="$ROOT/scripts/brewup.sh"
bup="$TMP/bup"
bup_real_home="$HOME"
bup_real_kh_sum=""
[ -f "$bup_real_home/.ssh/known_hosts" ] && bup_real_kh_sum="$(cksum < "$bup_real_home/.ssh/known_hosts")"
mkdir -p "$bup/dotfiles/scripts" "$bup/dotfiles/claude" "$bup/dotfiles/ssh" "$bup/home/.ssh" "$bup/bin" "$bup/marks"

# 受控 stub：只記錄被呼叫，不做任何真事
for bup_cmd in git brew claude jq; do
    {
        echo '#!/usr/bin/env bash'
        echo "echo \"\$0 \$*\" >> \"$bup/marks/$bup_cmd.log\""
        echo 'exit 0'
    } > "$bup/bin/$bup_cmd"
    chmod +x "$bup/bin/$bup_cmd"
done
echo '{}' > "$bup/dotfiles/claude/settings.json"
echo "# fixture known_hosts" > "$bup/dotfiles/ssh/known_hosts"

bup_make_helpers() {   # $1=失敗的 helper 名（空字串＝全部成功）
    for bup_h in ensure-rc-source ensure-codex-skills ensure-codex-guidance ensure-lftprc; do
        {
            echo '#!/usr/bin/env bash'
            echo "echo ran >> \"$bup/marks/${bup_h}.log\""
            if [ "$bup_h" = "$1" ]; then echo 'exit 1'; else echo 'exit 0'; fi
        } > "$bup/dotfiles/scripts/${bup_h}.sh"
        chmod +x "$bup/dotfiles/scripts/${bup_h}.sh"
    done
}

# RED 臂：guidance helper 失敗
bup_make_helpers ensure-codex-guidance
bup_out="$(DOTFILES_DIR="$bup/dotfiles" HOME="$bup/home" PATH="$bup/bin:$PATH" bash "$BUP" 2>&1)"
assert_rc "helper 失敗 → brewup 仍 exit 0（不擋套件更新）" 0 $?
if printf '%s\n' "$bup_out" | grep -q '⚠️'; then
    ok "helper 失敗 → 終判印出警告（不誤報完成）"
else
    bad "helper 失敗被靜默——symlink 未更新卻顯示正常完成"
fi
# 失敗不得中斷：下游的 Homebrew 段仍須執行，否則 helper 一失敗就整台不再更新套件
if [ -f "$bup/marks/brew.log" ]; then ok "helper 失敗後下游 brew 段仍執行"; else bad "helper 失敗中斷了後續更新"; fi
for bup_h in ensure-rc-source ensure-codex-skills ensure-codex-guidance ensure-lftprc; do
    if [ -f "$bup/marks/${bup_h}.log" ]; then ok "brewup 呼叫了 ${bup_h}"; else bad "brewup 未呼叫 ${bup_h}"; fi
done

# GREEN 臂：全部成功 → 不得出現警告（否則警告變雜訊、下次真失敗時沒人看）
rm -f "$bup/marks/"*.log
bup_make_helpers ""
bup_out="$(DOTFILES_DIR="$bup/dotfiles" HOME="$bup/home" PATH="$bup/bin:$PATH" bash "$BUP" 2>&1)"
assert_rc "全部成功 → exit 0" 0 $?
if printf '%s\n' "$bup_out" | grep -q '⚠️'; then bad "全部成功卻仍印警告"; else ok "全部成功 → 無警告"; fi

# 隔離自證：cp 落在沙盒 HOME，真實 $HOME/.ssh/known_hosts 一個 byte 未動
if [ -f "$bup/home/.ssh/known_hosts" ]; then ok "known_hosts 寫進沙盒 HOME"; else bad "known_hosts 未寫進沙盒——隔離可能失效"; fi
if [ -n "$bup_real_kh_sum" ]; then
    assert_eq "真實 \$HOME/.ssh/known_hosts 未被觸碰" "$bup_real_kh_sum" "$(cksum < "$bup_real_home/.ssh/known_hosts")"
else
    ok "真實 \$HOME 無 known_hosts（無可觸碰之物）"
fi

echo "▶ 18e. ensure-ssh-config.sh 幂等重生 ~/.ssh/config（原子寫入 + 完整性驗證）"
ESC="$ROOT/scripts/ensure-ssh-config.sh"
esc="$TMP/esc"
mkdir -p "$esc/src" "$esc/home"
printf 'Host example\n  User demo\n' > "$esc/src/config"

esc_run() { SOURCE_FILE="$esc/src/config" TARGET_HOME="$1" BACKUP_ROOT="$esc/backup" bash "$ESC"; }

esc_out="$(esc_run "$esc/home")"; esc_rc=$?
assert_rc "首次部署 → exit 0" 0 "$esc_rc"
if [ -f "$esc/home/.ssh/config" ]; then ok "config 已產生"; else bad "config 未產生"; fi
assert_eq "權限 600" "600" "$(stat -f '%Lp' "$esc/home/.ssh/config" 2>/dev/null || stat -c '%a' "$esc/home/.ssh/config")"
if grep -q 'Host example' "$esc/home/.ssh/config"; then ok "來源內容已灌入"; else bad "來源內容遺失"; fi
# config.local 是 setup 的職責——這裡先生一個空檔會讓 setup 的 `[ ! -f ]` 永遠跳過真內容
if [ -e "$esc/home/.ssh/config.local" ]; then bad "不該建立 config.local（會讓 setup 跳過真內容）"; else ok "不建立 config.local"; fi

esc_out="$(esc_run "$esc/home")"
assert_rc "二次跑 → exit 0" 0 $?
assert_eq "內容相同時靜默（無輸出，避免每次 brewup 都噪音）" "" "$esc_out"

printf 'Host example\n  User demo2\n' > "$esc/src/config"
esc_out="$(esc_run "$esc/home")"
if grep -q 'demo2' "$esc/home/.ssh/config"; then ok "來源變更 → 重生"; else bad "來源變更未反映"; fi

# 既有「非本腳本產生」的手寫 config：必須先備份才接管
mkdir -p "$esc/handwritten/.ssh"
printf '# my own config\nHost secret\n' > "$esc/handwritten/.ssh/config"
esc_run "$esc/handwritten" >/dev/null
assert_rc "接管手寫 config → exit 0" 0 $?
if grep -rq 'my own config' "$esc/backup" 2>/dev/null; then ok "手寫 config 已備份"; else bad "手寫 config 未備份即被覆蓋"; fi
if grep -q 'Host example' "$esc/handwritten/.ssh/config"; then ok "接管後內容為 dotfiles 版"; else bad "接管失敗"; fi
# 本腳本產生的檔不得每次都再備份一次——否則備份目錄無限膨脹、真正的手寫檔淹沒其中
esc_backup_n="$(find "$esc/backup" -type f | wc -l | tr -d ' ')"
printf 'Host example\n  User demo3\n' > "$esc/src/config"
esc_run "$esc/handwritten" >/dev/null
assert_eq "已受管的檔重生時不再備份" "$esc_backup_n" "$(find "$esc/backup" -type f | wc -l | tr -d ' ')"

# 來源缺席 → 早退且不建檔（新機器 clone 前、或路徑打錯時不得留半成品）
mkdir -p "$esc/nosrc"
SOURCE_FILE="$esc/src/missing" TARGET_HOME="$esc/nosrc" BACKUP_ROOT="$esc/backup" bash "$ESC" >/dev/null 2>&1
assert_rc "來源缺席 → exit 0（早退）" 0 $?
if [ -e "$esc/nosrc/.ssh/config" ]; then bad "來源缺席仍建了檔"; else ok "來源缺席不建檔"; fi

# 產出不完整（來源讀不到）→ 原檔一個 byte 都不能動。原本的行內版是 `> ~/.ssh/config`
# 直接截斷寫入，這種情況會留下殘缺的 config，而殘缺的 ssh config 正是「連得上但認錯身分」
# 那類最難查的故障。
esc_before="$(cksum < "$esc/home/.ssh/config")"
chmod 000 "$esc/src/config"
esc_out="$(SOURCE_FILE="$esc/src/config" TARGET_HOME="$esc/home" BACKUP_ROOT="$esc/backup" bash "$ESC" 2>&1)"
esc_rc=$?
chmod 644 "$esc/src/config"
assert_rc "產出不完整 → exit 1" 1 "$esc_rc"
# 兩道防線任一先攔到都可以（cat 失敗 / bytes 不符），但**不得靜默**——
# 靜默失敗會讓 dotsync 的 helper warn 有理由、使用者卻看不到是哪一項壞了
if printf '%s\n' "$esc_out" | grep -q '⚠️'; then ok "失敗有明確訊息"; else bad "失敗卻靜默"; fi
assert_eq "不完整時原檔未動" "$esc_before" "$(cksum < "$esc/home/.ssh/config")"
if find "$esc/home/.ssh" -name '.config.dotfiles.*' | grep -q .; then bad "殘留暫存檔"; else ok "暫存檔已清"; fi

# key 檔名落後的機器：拿「可用的舊 config」換成「指向不存在的 key」＝當場斷認證，
# 而修正要靠 GitHub 拉回來。本 helper 讓重生變自動，這道守門是配套。
mkdir -p "$esc/legacy/.ssh"
printf 'Host github.com\n  IdentityFile ~/.ssh/id_old\n' > "$esc/legacy/.ssh/config"
touch "$esc/legacy/.ssh/id_old"
printf 'Host github.com\n  IdentityFile ~/.ssh/id_new\n' > "$esc/src/config"
esc_before="$(cksum < "$esc/legacy/.ssh/config")"
esc_out="$(SOURCE_FILE="$esc/src/config" TARGET_HOME="$esc/legacy" BACKUP_ROOT="$esc/backup" bash "$ESC" 2>&1)"
assert_rc "新 config 的 key 缺席且舊 key 仍在 → 拒絕（exit 1）" 1 $?
assert_eq "拒絕時原 config 一個 byte 未動" "$esc_before" "$(cksum < "$esc/legacy/.ssh/config")"
if printf '%s\n' "$esc_out" | grep -q 'id_new'; then ok "訊息點名缺席的 key"; else bad "沒說是哪一把 key 缺席"; fi
if printf '%s\n' "$esc_out" | grep -q 'cp'; then ok "訊息給出處置（cp 不 mv）"; else bad "訊息無處置指引"; fi
# 補上新 key 之後就該放行——守門不能變成永久卡死
touch "$esc/legacy/.ssh/id_new"
SOURCE_FILE="$esc/src/config" TARGET_HOME="$esc/legacy" BACKUP_ROOT="$esc/backup" bash "$ESC" >/dev/null 2>&1
assert_rc "補上新 key 後放行" 0 $?
if grep -q 'id_new' "$esc/legacy/.ssh/config"; then ok "放行後已換成新 config"; else bad "放行後未更新"; fi
# 全新機器（尚無 config、也還沒放 key）不得被自己擋住——否則 setup 首跑就死在這裡
mkdir -p "$esc/fresh"
SOURCE_FILE="$esc/src/config" TARGET_HOME="$esc/fresh" BACKUP_ROOT="$esc/backup" bash "$ESC" >/dev/null 2>&1
assert_rc "全新機器（無既有 config）照常部署" 0 $?
if [ -f "$esc/fresh/.ssh/config" ]; then ok "全新機器有拿到 config"; else bad "全新機器被守門擋住"; fi
printf 'Host example\n  User demo3\n' > "$esc/src/config"

# 五個消費端都必須改呼叫 helper，且行內複本要真的消失——留一份沒改就會漂移
for esc_wiring in setup-mac-env.sh setup-linux-env.sh scripts/dotfiles-sync.sh scripts/brewup.sh scripts/add-new-host.sh; do
    if grep -q 'ensure-ssh-config.sh' "$ROOT/$esc_wiring"; then
        ok "$esc_wiring 已接上 ssh-config helper"
    else
        bad "$esc_wiring 未接上 ssh-config helper"
    fi
    if grep -q '} > ~/.ssh/config' "$ROOT/$esc_wiring"; then
        bad "$esc_wiring 仍留著行內生成複本（dedup 未完成）"
    else
        ok "$esc_wiring 行內複本已移除"
    fi
done
# dotfiles-sync 需本機段與遠端段都呼叫，否則遠端主機的 config 從此不再更新。
# 數「實際呼叫」而非「提及」——註解也會寫到腳本名，光數字面會把註解算進去。
assert_eq "dotfiles-sync 本機+遠端兩處都呼叫 ssh-config helper" 2 \
    "$(grep -c 'bash .*ensure-ssh-config.sh' "$ROOT/scripts/dotfiles-sync.sh")"

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
# squash base ≠ anchor base：base..HEAD 由新到舊掃，跳過 review 樣式 commit，停在第一顆
# 真語意 commit（此處 feat: x）——review fix 才壓，使用者的語意 commit 原樣留下。
ra_feat_x="$(git -C "$TMP/ra-work" rev-parse HEAD~1)"
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-work")"
assert_rc "squash-cmd happy path → exit 0" 0 $?
if echo "$out" | grep -qxF "squash-cmd: git -C '$TMP/ra-work' reset --soft $ra_feat_x"; then ok "squash-cmd 停在語意 commit（不壓既有 feat）"; else bad "squash-cmd 指令錯誤（squash base 未避開既有語意 commit）"; fi
if echo "$out" | grep -q "fix: R1 review fixes"; then ok "squash-range 列出 commit"; else bad "squash-range 清單缺失"; fi
if echo "$out" | grep -q "^squash-preserve: 1 顆" && grep -q "feat: x" <<< "$out"; then ok "squash-preserve 列出保留的既有 commit"; else bad "squash-preserve 缺失或未列保留 commit"; fi

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
if echo "$out" | grep -qF "codex-cmd: ~/.claude/skills/deep-review/scripts/codex-exec-review.sh run --repo '$TMP/ra-work' --range $ra_mb..$ra_h1 --round C1"; then ok "codex-cmd 整行照抄可執行"; else bad "codex-cmd 錯誤"; fi
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

# --- 分岔歷史不誤壓（原 codex C3 F2 的回歸位）---
# record 後切到含同一 base 的 sibling branch。原實作靠 head_at_record 算「審查前既有」，
# 分岔時 base..har + har..HEAD ≠ base..HEAD 會誤報；新算法只掃 base..HEAD 的 subject，
# 結構上不可能把範圍外的 commit 算進來——本案例改守「分岔時 squash 範圍仍精確」。
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp5"
(cd "$TMP/ra-imp5" && git switch -qc feat/a \
    && echo a1 > a.txt && "${GITC[@]}" add a.txt && "${GITC[@]}" commit -qm "feat: work A")
"$RA_SCRIPT" record --repo "$TMP/ra-imp5" --mode branch-diff --base origin/main >/dev/null
ra_imp5_mb="$(git -C "$TMP/ra-imp5" rev-parse origin/main)"
(cd "$TMP/ra-imp5" && git switch -qc feat/b origin/main \
    && echo b1 > b.txt && "${GITC[@]}" add b.txt && "${GITC[@]}" commit -qm "fix: address review findings")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp5")"
if grep -q "^squash-preserve:" <<< "$out"; then bad "分岔歷史誤列 preserve（範圍外 commit 被算入）"; else ok "分岔時不誤列既有 commit"; fi
if grep -qxF "squash-cmd: git -C '$TMP/ra-imp5' reset --soft $ra_imp5_mb" <<< "$out"; then ok "分岔時 squash base 仍為 anchor base（全為 review commit）"; else bad "分岔時 squash base 錯誤"; fi

# --- 照抄行一律絕對路徑（相對路徑呼叫時尤其重要：照抄處的 cwd 未必是這裡）---
# 一條 case 覆蓋三種輸出；只驗絕對性，不比對整段路徑（避免與 fixture 路徑寫死耦合）
(cd "$TMP/ra-work" && "$RA_SCRIPT" record --repo . --mode branch-diff --base origin/main >/dev/null)
out="$( (cd "$TMP/ra-work" && "$RA_SCRIPT" record --repo . --mode branch-diff --base origin/main) )"
if grep -qE "^diff-cmd: git -C '/" <<< "$out"; then ok "相對 --repo → diff-cmd 印絕對路徑"; else bad "diff-cmd 沿用了相對路徑"; fi
out="$( (cd "$TMP/ra-work" && "$RA_SCRIPT" squash-cmd --repo .) )"
if grep -qE "^squash-cmd: git -C '/" <<< "$out"; then ok "相對 --repo → squash-cmd 印絕對路徑"; else bad "squash-cmd 沿用了相對路徑"; fi
out="$( (cd "$TMP/ra-work" && "$RA_SCRIPT" codex-next --repo .) )"
if grep -qE "^codex-cmd: .* --repo '/" <<< "$out"; then ok "相對 --repo → codex-cmd 印絕對路徑（下游 codex-exec-review 會對 --repo 做 -d 檢查）"; else bad "codex-cmd 沿用了相對路徑（換 cwd 執行會 exit 5 或指到別的 repo）"; fi

# --- lib 缺席：只有需要 subject 清單的 squash-cmd 該停，其餘子指令照常 ---
mkdir -p "$TMP/ra-nolib/scripts"
cp "$RA_SCRIPT" "$TMP/ra-nolib/scripts/review-anchor.sh"   # 不複製 lib/
"$TMP/ra-nolib/scripts/review-anchor.sh" record --repo "$TMP/ra-work" --mode working-tree >/dev/null 2>&1
assert_rc "lib 缺席 → record 照常（不需要 subject 清單）" 0 $?
out="$("$TMP/ra-nolib/scripts/review-anchor.sh" squash-cmd --repo "$TMP/ra-work" 2>&1)"
rc=$?
assert_rc "lib 缺席 → squash-cmd STOP（不用空 regex 硬跑）" 1 $rc
if grep -q "verdict: STOP" <<< "$out"; then ok "lib 缺席的 squash-cmd 印 STOP verdict"; else bad "缺 STOP verdict（會被當成正常結果）"; fi

# merge-base 解析失敗 → 同樣走 UNKNOWN 出口（不靜默 return，Step 4 判定表才有得對）
git clone -q "$TMP/sb-origin.git" "$TMP/rr-nomb"
(cd "$TMP/rr-nomb" && git checkout -q --orphan orphan-line \
    && git rm -rqf . 2>/dev/null; cd "$TMP/rr-nomb" && echo o > o.txt && "${GITC[@]}" add o.txt && "${GITC[@]}" commit -qm "feat: 無共同祖先")
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-nomb" 2>&1)"
if grep -q "^review-residue: UNKNOWN" <<< "$out"; then ok "merge-base 失敗 → review-residue 走 UNKNOWN 出口"; else bad "merge-base 失敗時靜默漏印（Step 4 判定表無列可對）"; fi

# --- option-like ref 名：quoting 擋不住，要靠 `--` terminator ---
# `git branch -- '--all'` 前端會拒，但 `git update-ref refs/heads/--all` 建得起來且
# `check-ref-format` 判合法（實測 rc=0）；quote 完 git 仍把 `--all` 當選項（codex C3）。
git init --bare -q "$TMP/opt-origin.git"
git clone -q "$TMP/opt-origin.git" "$TMP/rr-opt"
(cd "$TMP/rr-opt" && echo o > o.txt && "${GITC[@]}" add o.txt && "${GITC[@]}" commit -qm init && git push -qu origin main)
git -C "$TMP/rr-opt" update-ref 'refs/heads/--all' HEAD
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-opt" 2>/dev/null)"
opt_cmd="$(grep '^cleanup-cmd: ' <<< "$out" | sed 's/^cleanup-cmd: //')"
if [ -n "$opt_cmd" ]; then
    if grep -qF -- "branch -d --" <<< "$opt_cmd"; then ok "cleanup-cmd 帶 -- option terminator"; else bad "cleanup-cmd 缺 --，option-like ref 會被當選項"; fi
    ( eval "$opt_cmd" ) >/dev/null 2>&1 || true
    if git -C "$TMP/rr-opt" show-ref --verify --quiet 'refs/heads/--all'; then bad "照抄 cleanup-cmd 後 option-like branch 仍在（指令實際失敗）"; else ok "照抄 cleanup-cmd 可實際刪除 option-like branch"; fi
else
    bad "未取得 cleanup-cmd（fixture 前提失效）"
fi

# --- 照抄行的 ref 名也必須 quote：git 接受 `feat/$(id)` / `feat/a;id` 這種合法 branch 名，
# 照抄含未 quote ref 的指令等於執行任意 shell（codex C2 實證 git 三種都收）---
git clone -q "$TMP/sb-origin.git" "$TMP/rr-ref"
# shellcheck disable=SC2016  # 刻意不展開：這是 fixture 要用的字面 branch 名
sq_ref_name='feat/$(id);x'   # git 接受（ref 名不可含空白，但 $ ( ) ; 皆合法）
# 不加 commit：stale-branches 只列「已完全併入 default」者（同 sb-work fixture 的做法）
(cd "$TMP/rr-ref" && git switch -qc "$sq_ref_name" \
    && git push -qu origin "$sq_ref_name" >/dev/null 2>&1 && git switch -q main)
out="$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$TMP/rr-ref" 2>/dev/null)"
ref_cmd="$(grep '^cleanup-cmd: ' <<< "$out" | sed 's/^cleanup-cmd: //')"
if [ -n "$ref_cmd" ]; then
    if bash -n <<< "$ref_cmd" 2>/dev/null; then ok "含 shell 元字元的 branch 名 → cleanup-cmd 仍可解析"; else bad "cleanup-cmd 因 ref 名破裂"; fi
    # 真正的判準：ref 取回來要與原名相同（未 quote 的話 $(…) 會被展開成別的東西或空字串）
    # 逐一比對而非「有出現就算」：cleanup-cmd 會列多個 ref（local + remote 兩處），
    # 只要有一處漏 quote 就是漏洞——出現次數必須全等於 quoted 出現次數
    n_ref_all="$(grep -oF -- "$sq_ref_name" <<< "$ref_cmd" | wc -l | tr -d ' ')"
    n_ref_q="$(grep -oF -- "'${sq_ref_name}'" <<< "$ref_cmd" | wc -l | tr -d ' ')"
    if [ "${n_ref_all:-0}" -gt 0 ] && [ "$n_ref_all" = "$n_ref_q" ]; then ok "cleanup-cmd 內每一處 ref 名都被 quote（${n_ref_q}/${n_ref_all}）"; else bad "有 ${n_ref_all} 處 ref、僅 ${n_ref_q} 處 quoted——照抄即執行任意指令"; fi
else
    bad "未取得 cleanup-cmd（fixture 前提失效）"
fi

# --- 照抄行對特殊字元路徑必須可執行（含單引號、空白、$(...)）---
# 直接把路徑插進單引號在 `/tmp/alice's-repo` 這種合法路徑上會讓 quoting 破裂，照抄行
# 送進 bash 直接 syntax error（codex C1 實證）。三支腳本共用同形的 shq helper。
sq_dir="$TMP/we'ird \$(echo x) dir"
mkdir -p "$sq_dir"
git init -q --bare "$TMP/sq-origin.git"
git clone -q "$TMP/sq-origin.git" "$sq_dir/repo" 2>/dev/null
(cd "$sq_dir/repo" && echo s > s.txt && "${GITC[@]}" add s.txt && "${GITC[@]}" commit -qm init \
    && git push -qu origin main && git switch -qc feat/sq \
    && echo s2 > s.txt && "${GITC[@]}" commit -qam "feat: 語意" \
    && echo s3 > s.txt && "${GITC[@]}" commit -qam "fix: address review findings")
"$RA_SCRIPT" record --repo "$sq_dir/repo" --mode branch-diff --base origin/main >/dev/null 2>&1
sq_bad=0
for sq_line in "$("$RA_SCRIPT" record --repo "$sq_dir/repo" --mode branch-diff --base origin/main 2>/dev/null | grep '^diff-cmd: ' | sed 's/^diff-cmd: //')" \
               "$("$RA_SCRIPT" squash-cmd --repo "$sq_dir/repo" 2>/dev/null | grep '^squash-cmd: ' | sed 's/^squash-cmd: //')" \
               "$("$RA_SCRIPT" codex-next --repo "$sq_dir/repo" 2>/dev/null | grep '^codex-cmd: ' | sed 's/^codex-cmd: //')" \
               "$(SHIP_STATE_GH="$TMP/gh-open" "$SS_SCRIPT" "$sq_dir/repo" 2>/dev/null | grep '^  squash-cmd: ' | sed 's/^  squash-cmd: //')" \
               "$("$RS_SCRIPT" "$sq_dir/repo" 2>/dev/null | grep '^branch-cmd: ' | sed 's/^branch-cmd: //')"; do
    [ -n "$sq_line" ] || continue
    bash -n <<< "$sq_line" 2>/dev/null || { sq_bad=$((sq_bad + 1)); echo "     不可解析: ${sq_line}"; }
done
if [ "$sq_bad" -eq 0 ]; then ok "特殊字元路徑下所有照抄行皆可被 shell 解析"; else bad "${sq_bad} 條照抄行 quoting 破裂"; fi
# round-trip：eval 後取回的路徑必須與原路徑相同（不是「能解析」就算數）
sq_cmd="$("$RA_SCRIPT" squash-cmd --repo "$sq_dir/repo" 2>/dev/null | grep '^squash-cmd: ' | sed 's/^squash-cmd: //')"
sq_got="$(eval "set -- ${sq_cmd#git -C }"; echo "$1")"
if [ "$sq_got" = "$(cd "$sq_dir/repo" && pwd -P)" ]; then ok "照抄行的路徑 round-trip 相符（非僅可解析）"; else bad "round-trip 不符：${sq_got}"; fi

# --- 本腳本自身的防護：mktemp 失敗不得讓 TMP 退化成 cwd ---
# 為何測這個：`cd ""` 回傳 0 且不改目錄，pwd -P 會交出 cwd（本腳本第 35 行已切到 repo 根），
# 而 EXIT trap 是 `rm -rf "$TMP"`——空值 fallback 直接通向「刪掉整個 repo」。
# 用 stub 逼 mktemp 失敗——macOS 的 mktemp 會忽略無效 TMPDIR 改用預設值，設環境變數擋不住
mkdir -p "$TMP/mt-bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/mt-bin/mktemp"
chmod +x "$TMP/mt-bin/mktemp"
out="$(PATH="$TMP/mt-bin:$PATH" bash -c '
    cd /tmp || exit 9
    TMP="$(mktemp -d)" || { echo GUARDED; exit 1; }
    [ -n "$TMP" ] && [ -d "$TMP" ] || { echo GUARDED; exit 1; }
    TMP="$(cd "$TMP" && pwd -P)"
    echo "UNGUARDED:$TMP"' 2>/dev/null)"
if grep -q "^GUARDED$" <<< "$out"; then ok "mktemp 失敗 → 當場中止（不讓 TMP 退化成 cwd）"; else bad "mktemp 失敗未被擋下（${out}）——EXIT trap 會 rm -rf 該目錄"; fi

# --- review-state.sh 的 lib 缺席降級（三個消費者的最後一個守門）---
mkdir -p "$TMP/rs-nolib"
cp "$RS_SCRIPT" "$TMP/rs-nolib/review-state.sh"   # 不複製 lib/
out="$("$TMP/rs-nolib/review-state.sh" "$TMP/ra-work" 2>&1)"
assert_rc "lib 缺席 → review-state 照常完成（round 以外的偵測不該被拖垮）" 0 $?
if grep -q "^round: 1（review-subjects.sh 不可用" <<< "$out"; then ok "lib 缺席 → round 降級並說明原因"; else bad "缺 round 降級（會在 set -u 下中途 unbound variable）"; fi
if grep -q "^branch-first:" <<< "$out"; then ok "lib 缺席不影響其餘偵測輸出"; else bad "lib 缺席拖垮了其他輸出"; fi

# --- terminal state：R5 終止後不得靜默重開新 cycle ---
# RED 來源（2026-08-06 實地）：第一場 R5 終止 → 人工修一條 → 又開一場（R1–R4 + C1–C3），
# 外層 orchestration 重置了輪次上限。cycle 計數判別不了成因（終止/中途停止/crash/刻意續跑），
# 故改為顯式狀態。terminate 與 resume 語意不重疊：resume 保留 base，record 是無條件覆寫。
git clone -q "$TMP/ra-origin.git" "$TMP/ra-term"
(cd "$TMP/ra-term" && git switch -qc feat/t \
    && echo t1 > t.txt && "${GITC[@]}" add t.txt && "${GITC[@]}" commit -qm "feat: 語意")
ra_term_anchor="$(git -C "$TMP/ra-term" rev-parse --absolute-git-dir)/deep-review/anchor"
"$RA_SCRIPT" record --repo "$TMP/ra-term" --mode branch-diff --base origin/main --tests-baseline pass >/dev/null
ra_term_before="$(cat "$ra_term_anchor")"

# terminate：新增三個 key，既有欄位逐一不變
"$RA_SCRIPT" terminate --repo "$TMP/ra-term" --reason r5-blocking >/dev/null
assert_rc "terminate → exit 0" 0 $?
if grep -qxF "terminal_reason=r5-blocking" "$ra_term_anchor" && grep -q "^terminal_head=" "$ra_term_anchor" && grep -q "^terminal_at=" "$ra_term_anchor"; then
    ok "terminate 寫入 terminal_reason/head/at"
else bad "terminate 未寫入三個 key"; fi
ra_term_kept=1
while IFS= read -r kv; do grep -qxF "$kv" "$ra_term_anchor" || { ra_term_kept=0; echo "     遺失: $kv"; }; done <<< "$ra_term_before"
if [ "$ra_term_kept" -eq 1 ]; then ok "terminate 逐一保留既有欄位（不覆寫 base/mode/range）"; else bad "terminate 動到既有欄位"; fi

# terminate 冪等 / 換 reason 拒絕 / 無 anchor 拒絕
"$RA_SCRIPT" terminate --repo "$TMP/ra-term" --reason r5-blocking >/dev/null 2>&1
assert_rc "terminate 同 reason 重複 → 冪等成功" 0 $?
# 本批只有一個合法 reason，故「換 reason」只可能是傳非法值 → 用法錯誤(2)，不是 STOP(1)。
# 引數合法性先於狀態檢查，是標準順序；等未來真支援多個 reason，才會有「同 anchor 換 reason」的 STOP。
"$RA_SCRIPT" terminate --repo "$TMP/ra-term" --reason codex-c3 >/dev/null 2>&1
assert_rc "terminate 非法 reason → 用法錯誤（codex-c3 無 RED，本批不支援）" 2 $?
if grep -qxF "terminal_reason=r5-blocking" "$ra_term_anchor"; then ok "非法 reason 未污染既有 terminal 狀態"; else bad "既有 terminal 被覆蓋"; fi
git clone -q "$TMP/ra-origin.git" "$TMP/ra-noanchor"
"$RA_SCRIPT" terminate --repo "$TMP/ra-noanchor" --reason r5-blocking >/dev/null 2>&1
assert_rc "terminate 無 anchor → STOP" 1 $?

# record 撞上 terminal：STOP 且**不得覆寫** anchor（寫檔前先檢查）
out="$("$RA_SCRIPT" record --repo "$TMP/ra-term" --mode working-tree 2>&1)"
rc=$?
assert_rc "terminal 狀態下 record → STOP" 1 $rc
if grep -q "verdict: STOP" <<< "$out"; then ok "record 撞 terminal 印 STOP verdict"; else bad "缺 STOP verdict"; fi
if grep -qxF "mode=branch-diff" "$ra_term_anchor"; then ok "record 撞 terminal 未覆寫 anchor（mode 仍為原值）"; else bad "record 先重算再覆蓋了 anchor"; fi

# resume-after-terminal：清 terminal、cycle +1、其餘欄位全留
ra_term_cycle_before="$(sed -n 's/^cycle=//p' "$ra_term_anchor")"
"$RA_SCRIPT" resume-after-terminal --repo "$TMP/ra-term" >/dev/null
assert_rc "resume-after-terminal → exit 0" 0 $?
if grep -q "^terminal_" "$ra_term_anchor"; then bad "resume 未清 terminal_*"; else ok "resume 清掉 terminal_*"; fi
if [ "$(sed -n 's/^cycle=//p' "$ra_term_anchor")" = "$((ra_term_cycle_before + 1))" ]; then ok "resume 使 cycle +1"; else bad "resume 未遞增 cycle"; fi
if grep -qxF "base=$(git -C "$TMP/ra-term" merge-base origin/main HEAD)" "$ra_term_anchor" && grep -qxF "tests_baseline=pass" "$ra_term_anchor"; then
    ok "resume 保留 base 與其餘欄位（與 record 的無條件覆寫語意不同）"
else bad "resume 動到 base 或其他欄位"; fi
"$RA_SCRIPT" resume-after-terminal --repo "$TMP/ra-term" >/dev/null 2>&1
assert_rc "resume 重複呼叫（已無 terminal）→ STOP" 1 $?

# 回歸鎖：非 terminal 狀態下 record 行為不變
"$RA_SCRIPT" record --repo "$TMP/ra-term" --mode working-tree >/dev/null 2>&1
assert_rc "非 terminal 狀態 → record 照常覆寫（行為不變）" 0 $?

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
if echo "$out" | grep -qxF "diff-cmd: git -C '$TMP/ra-imp' diff $ra_imp_mb...HEAD"; then ok "record 印 diff-cmd（固定 hash）"; else bad "diff-cmd 缺失或錯誤"; fi

# range 模式不印 diff-cmd（審查指令 = range 引數本身，...HEAD 會審錯範圍）
out="$("$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode range --range "$ra_imp_mb..HEAD" 2>/dev/null)"
if echo "$out" | grep -q "^diff-cmd:"; then bad "range 模式誤印 diff-cmd"; else ok "range 模式不印 diff-cmd"; fi

# tests-baseline 值域驗證
"$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode working-tree --tests-baseline bogus >/dev/null 2>&1
assert_rc "tests-baseline 非法值 → exit 2" 2 $?

# 無 flag 覆蓋 → tests_baseline 不殘留（record 無條件覆蓋語意）
"$RA_SCRIPT" record --repo "$TMP/ra-imp" --mode branch-diff --base origin/main >/dev/null
if grep -q "^tests_baseline=" "$ra_imp_anchor"; then bad "無 flag 時 tests_baseline 殘留"; else ok "無 flag 覆蓋 → tests_baseline 不殘留"; fi

# squash base 避開既有語意 commit：branch 上的 feat 保留，只壓其上的 review fix
ra_imp_feat="$(git -C "$TMP/ra-imp" rev-parse HEAD~1)"
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp")"
if grep -qxF "squash-cmd: git -C '$TMP/ra-imp' reset --soft $ra_imp_feat" <<< "$out"; then ok "squash base = 既有 feat commit（只壓其上的 review fix）"; else bad "squash base 未停在既有語意 commit"; fi
if grep -q "^squash-preserve: 1 顆" <<< "$out" && grep -q "feat: w feature" <<< "$out"; then ok "squash-preserve 列出被保留的 feat"; else bad "squash-preserve 缺失"; fi

# 撞名取捨（原 codex C2 F3 的位置）：使用者手寫的 commit 若 subject 恰為 review 固定樣式，
# 會被當成 review 產生而壓掉。四個樣式都是機械字串、人工撞名機率極低，且後果等同舊行為
# （舊實作同樣全壓、只多印一行 warning），故接受此代價、不加 head_at_record 之類的補償機制。
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp4"
(cd "$TMP/ra-imp4" && git switch -qc feat/collide \
    && echo p1 > p.txt && "${GITC[@]}" add p.txt && "${GITC[@]}" commit -qm "fix: address review findings")
"$RA_SCRIPT" record --repo "$TMP/ra-imp4" --mode branch-diff --base origin/main >/dev/null
ra_imp4_mb="$(git -C "$TMP/ra-imp4" rev-parse origin/main)"
(cd "$TMP/ra-imp4" && echo p2 > p.txt && "${GITC[@]}" commit -qam "fix: address review findings")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp4")"
if grep -qxF "squash-cmd: git -C '$TMP/ra-imp4' reset --soft $ra_imp4_mb" <<< "$out"; then ok "全為 review 樣式 → squash base 退回 anchor base（下界保護）"; else bad "全樣式時 squash base 錯誤"; fi
if grep -q "^squash-preserve:" <<< "$out"; then bad "全為 review 樣式卻列 preserve"; else ok "全為 review 樣式 → 不列 preserve"; fi

# review commit 被非 review commit 隔開（HEAD 本身即非 review）→ 保守不跨越，
# 範圍歸零，且下方未納入的 review 樣式 commit 須以 squash-note 攤開讓使用者看見。
(cd "$TMP/ra-imp4" && echo p3 > p.txt && "${GITC[@]}" commit -qam "feat: unrelated work")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp4")"
if grep -q "^squash-note: 保留範圍內仍有 2 顆 review 樣式 commit" <<< "$out"; then ok "被隔開的 review commit 以 squash-note 告知"; else bad "squash-note 缺失或顆數錯誤"; fi
if grep -q "WARNING" <<< "$out"; then ok "HEAD 即非 review commit → 無 commit 可 squash"; else bad "應報無 commit 可 squash"; fi

# 三段交錯：squash 範圍非空 **且** 同時有 squash-note（squash_base 嚴格落在 base 與 HEAD 之間）
git clone -q "$TMP/ra-origin.git" "$TMP/ra-mix"
(cd "$TMP/ra-mix" && git switch -qc feat/mix \
    && echo m1 > m.txt && "${GITC[@]}" add m.txt && "${GITC[@]}" commit -qm "fix: address review findings" \
    && echo m2 > m.txt && "${GITC[@]}" commit -qam "feat: 中間插入的語意 commit")
ra_mix_feat="$(git -C "$TMP/ra-mix" rev-parse HEAD)"
(cd "$TMP/ra-mix" && echo m3 > m.txt && "${GITC[@]}" commit -qam "fix: address review findings")
"$RA_SCRIPT" record --repo "$TMP/ra-mix" --mode branch-diff --base origin/main >/dev/null
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-mix")"
if grep -qxF "squash-cmd: git -C '$TMP/ra-mix' reset --soft $ra_mix_feat" <<< "$out"; then ok "交錯：squash base 停在中間的語意 commit"; else bad "交錯情境 squash base 錯誤"; fi
if grep -q "^squash-range: .*（1 commit）" <<< "$out"; then ok "交錯：squash 範圍非空（1 顆）"; else bad "交錯情境範圍錯誤"; fi
if grep -q "^squash-note: 保留範圍內仍有 1 顆 review 樣式 commit" <<< "$out"; then ok "交錯：範圍非空時仍印 squash-note"; else bad "範圍非空時漏印 squash-note"; fi

# 全為 review 產生的 commits（wip snapshot + fix）→ base 不動、無 preserve
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp2"
"$RA_SCRIPT" record --repo "$TMP/ra-imp2" --mode working-tree >/dev/null
ra_imp2_base="$(git -C "$TMP/ra-imp2" rev-parse HEAD)"
(cd "$TMP/ra-imp2" && git switch -qc feat/v \
    && echo v1 > v.txt && "${GITC[@]}" add v.txt && "${GITC[@]}" commit -qm "wip: pre-review snapshot" \
    && echo v2 > v.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp2")"
if grep -q "^squash-preserve:" <<< "$out"; then bad "純 review commits 誤列 preserve"; else ok "純 review commits 無 preserve"; fi
if grep -qxF "squash-cmd: git -C '$TMP/ra-imp2' reset --soft $ra_imp2_base" <<< "$out"; then ok "working-tree 模式行為不變（base = anchor base）"; else bad "working-tree 模式 squash base 漂移"; fi

# 中性化 commit message（不編輪號，避免 reviewer 跑 git log 反推進度）：
# 新格式須被認得，且舊格式仍認（歷史 branch 上還有舊 commit，誤判會噴假 warning）
git clone -q "$TMP/ra-origin.git" "$TMP/ra-imp3"
"$RA_SCRIPT" record --repo "$TMP/ra-imp3" --mode working-tree >/dev/null
ra_imp3_base="$(git -C "$TMP/ra-imp3" rev-parse HEAD)"
(cd "$TMP/ra-imp3" && git switch -qc feat/n \
    && echo n1 > n.txt && "${GITC[@]}" add n.txt && "${GITC[@]}" commit -qm "wip: pre-review snapshot" \
    && echo n2 > n.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo n3 > n.txt && "${GITC[@]}" commit -qam "fix: address review findings" \
    && echo n4 > n.txt && "${GITC[@]}" commit -qam "fix: address external review findings" \
    && echo n5 > n.txt && "${GITC[@]}" commit -qam "fix: R1 review fixes" \
    && echo n6 > n.txt && "${GITC[@]}" commit -qam "fix: codex C1 fixes" \
    && echo n7 > n.txt && "${GITC[@]}" commit -qam "fix: codex R1 fixes")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp3")"
if grep -qxF "squash-cmd: git -C '$TMP/ra-imp3' reset --soft $ra_imp3_base" <<< "$out"; then ok "中性/舊格式 commit message 皆認得（新舊並存、全數納入 squash）"; else bad "中性化或舊格式 message 未被認出（squash base 提前停下）"; fi
if grep -q "^squash-preserve:" <<< "$out"; then bad "全為 review 樣式卻列 preserve"; else ok "六種樣式全認得 → 無 preserve"; fi
# 反向：真的語意 commit 仍要擋住掃描（不因放寬 pattern 而越界壓掉）
(cd "$TMP/ra-imp3" && echo n8 > n.txt && "${GITC[@]}" commit -qam "feat: unrelated work")
ra_imp3_feat="$(git -C "$TMP/ra-imp3" rev-parse HEAD)"
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-imp3")"
if grep -qxF "squash-cmd: git -C '$TMP/ra-imp3' reset --soft $ra_imp3_feat" <<< "$out"; then ok "放寬 pattern 後語意 commit 仍擋得住掃描"; else bad "語意 commit 被越過（會被誤壓）"; fi
if grep -q "^squash-note: 保留範圍內仍有 7 顆 review 樣式 commit" <<< "$out"; then ok "被隔開的 7 顆 review commit 以 squash-note 攤開"; else bad "squash-note 顆數錯誤或缺失"; fi

# --- 續跑（cycle≥2）：兩場 review 的 fix commit 一併壓，base 不停在上一場的 fix ---
# 為何：續跑時 record 重跑、head_at_record 前移，若拿它當下界，上一場的 fix commit 會殘留
# 在 branch 上（無語意、無參照價值）。純 subject 掃描天然不受 record 次數影響。
git clone -q "$TMP/ra-origin.git" "$TMP/ra-cyc2"
(cd "$TMP/ra-cyc2" && git switch -qc feat/cyc \
    && echo c1 > c.txt && "${GITC[@]}" add c.txt && "${GITC[@]}" commit -qm "feat: base work")
ra_cyc2_feat="$(git -C "$TMP/ra-cyc2" rev-parse HEAD)"
"$RA_SCRIPT" record --repo "$TMP/ra-cyc2" --mode branch-diff --base origin/main >/dev/null
(cd "$TMP/ra-cyc2" && echo c2 > c.txt && "${GITC[@]}" commit -qam "fix: address review findings")
"$RA_SCRIPT" record --repo "$TMP/ra-cyc2" --mode branch-diff --base origin/main >/dev/null
(cd "$TMP/ra-cyc2" && echo c3 > c.txt && "${GITC[@]}" commit -qam "fix: address review findings")
out="$("$RA_SCRIPT" squash-cmd --repo "$TMP/ra-cyc2")"
if grep -qxF "squash-cmd: git -C '$TMP/ra-cyc2' reset --soft $ra_cyc2_feat" <<< "$out"; then ok "續跑：兩場的 fix commit 一併壓、停在 feat"; else bad "續跑時 squash base 錯誤（上一場 fix 殘留）"; fi
if grep -q "^squash-preserve: 1 顆" <<< "$out"; then ok "續跑：既有 feat 仍保留"; else bad "續跑 preserve 錯誤"; fi

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

echo "▶ 22. brewup / sysup / brewfix（rc alias 抽成腳本後的三個入口）"

# --- sysup.sh 平台 guard ---
SYSUP_SH="$ROOT/scripts/sysup.sh"
SYSUP_UNAME=Darwin bash "$SYSUP_SH" >/dev/null 2>&1
assert_rc "sysup 於非 Linux → exit 2（不觸碰 apt）" 2 $?

# --- brewfix.sh ---
BFX="$ROOT/scripts/brewfix.sh"
bfx="$TMP/bfx"; mkdir -p "$bfx/Caskroom" "$bfx/bin"

# stub：預設「無 brew prefix 底下的 process」
cat > "$bfx/ps-empty" <<'STUB'
#!/usr/bin/env bash
echo "  501 /usr/sbin/unrelated"
STUB
# stub：一個位於 brew prefix 底下、lsof 條目極少（＝一個 dylib 都沒載入）的 process
cat > "$bfx/ps-stuck" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' 99999 "__PREFIX__/Caskroom/codex/1.0/bin/codex"
STUB
sed -i.bak "s|__PREFIX__|$bfx|" "$bfx/ps-stuck" && rm -f "$bfx/ps-stuck.bak"
cat > "$bfx/lsof-few" <<'STUB'
#!/usr/bin/env bash
printf 'a\nb\nc\nd\ne\nf\ng\n'
STUB
cat > "$bfx/lsof-many" <<'STUB'
#!/usr/bin/env bash
for i in $(seq 1 60); do echo "line$i"; done
STUB
cat > "$bfx/killall-stub" <<'STUB'
#!/usr/bin/env bash
echo "killall $*" >> "$KILLALL_LOG"
STUB
cat > "$bfx/sudo-stub" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "-n" ] && exit 0     # 佯裝免密 sudo 可用
shift 0; exec "$@"
STUB
chmod +x "$bfx"/ps-* "$bfx"/lsof-* "$bfx"/killall-stub "$bfx"/sudo-stub

bfx_env() {
    BREWFIX_UNAME=Darwin BREWFIX_BREW_PREFIX="$bfx" BREWFIX_CASKROOM="$bfx/Caskroom" \
    BREWFIX_PS="$1" BREWFIX_LSOF="$2" BREWFIX_KILLALL="$bfx/killall-stub" \
    BREWFIX_SUDO="$bfx/sudo-stub" KILLALL_LOG="$bfx/killall.log" bash "$BFX" "${3:-}"
}

# 非 macOS → exit 2
BREWFIX_UNAME=Linux bash "$BFX" >/dev/null 2>&1
assert_rc "非 macOS → exit 2" 2 $?

# 未知參數 → exit 2（不得被當成 --fix）
BREWFIX_UNAME=Darwin bash "$BFX" --wipe >/dev/null 2>&1
assert_rc "未知參數 → exit 2" 2 $?

# Caskroom 不存在 → exit 2
BREWFIX_UNAME=Darwin BREWFIX_BREW_PREFIX="$bfx" BREWFIX_CASKROOM="$bfx/nope" bash "$BFX" >/dev/null 2>&1
assert_rc "Caskroom 不存在 → exit 2" 2 $?

# 乾淨 → CLEAN / exit 0
out=$(bfx_env "$bfx/ps-empty" "$bfx/lsof-many"); rc=$?
assert_rc "無殘留無卡死 → exit 0" 0 $rc
assert_eq "verdict: CLEAN" "verdict: CLEAN" "$(echo "$out" | grep '^verdict:')"

# 有 *.upgrading 殘留 → RESIDUE / exit 1，且唯讀模式**不得刪除**
mkdir -p "$bfx/Caskroom/codex/0.1.upgrading"
out=$(bfx_env "$bfx/ps-empty" "$bfx/lsof-many"); rc=$?
assert_rc "有殘留 → exit 1" 1 $rc
assert_eq "verdict: RESIDUE" "verdict: RESIDUE" "$(echo "$out" | grep '^verdict:')"
if [ -d "$bfx/Caskroom/codex/0.1.upgrading" ]; then ok "唯讀模式未刪除殘留"; else bad "唯讀模式竟刪除了殘留"; fi

# --fix → 清除殘留並複驗 CLEAN
out=$(bfx_env "$bfx/ps-empty" "$bfx/lsof-many" --fix); rc=$?
assert_rc "--fix 清完 → exit 0" 0 $rc
if [ ! -d "$bfx/Caskroom/codex/0.1.upgrading" ]; then ok "--fix 已清除殘留"; else bad "--fix 未清除殘留"; fi

# 無卡死 process 時不得驚動 syspolicyd（killall 是全系統動作，不該無謂執行）
if [ ! -s "$bfx/killall.log" ]; then ok "無卡死 process → 不呼叫 killall"; else bad "無卡死卻呼叫了 killall"; fi

# 卡死 process（lsof 條目極少）→ STUCK
out=$(bfx_env "$bfx/ps-stuck" "$bfx/lsof-few"); rc=$?
assert_rc "偵測到卡死 process → exit 1" 1 $rc
assert_eq "verdict: STUCK" "verdict: STUCK" "$(echo "$out" | grep '^verdict:')"
if echo "$out" | grep -q '^stuck-process: pid=99999'; then ok "列出卡死 pid"; else bad "未列出卡死 pid"; fi

# 同一個 process，但 lsof 條目正常（dylib 已載入）→ 不得判為卡死
out=$(bfx_env "$bfx/ps-stuck" "$bfx/lsof-many"); rc=$?
assert_rc "lsof 條目正常 → 不誤判為卡死（exit 0）" 0 $rc
assert_eq "verdict: CLEAN（正常執行中的 process）" "verdict: CLEAN" "$(echo "$out" | grep '^verdict:')"

# --fix 遇卡死 → 才呼叫 killall syspolicyd
: > "$bfx/killall.log"
bfx_env "$bfx/ps-stuck" "$bfx/lsof-few" --fix >/dev/null 2>&1
if grep -q 'killall syspolicyd' "$bfx/killall.log"; then ok "--fix 遇卡死 → 呼叫 killall syspolicyd"; else bad "--fix 遇卡死卻未呼叫 killall"; fi

# 破壞性刪除的作用域：Caskroom 外的 *.upgrading 不得被碰
outside="$TMP/outside.upgrading"; mkdir -p "$outside"
mkdir -p "$bfx/Caskroom/tool/9.9.upgrading"
bfx_env "$bfx/ps-empty" "$bfx/lsof-many" --fix >/dev/null 2>&1
if [ -d "$outside" ]; then ok "Caskroom 外的 *.upgrading 未被觸碰"; else bad "誤刪了 Caskroom 外的目錄"; fi
if [ ! -d "$bfx/Caskroom/tool/9.9.upgrading" ]; then ok "Caskroom 內殘留已清"; else bad "Caskroom 內殘留未清"; fi

echo "▶ 23. migrate-github-remotes.sh（GitHub 多身分收斂的遷移入口）"
# 這支要在 12 台機器上各跑一次，且它會**改每個 repo 的 remote**——錯一次的代價是那台機器
# 所有 repo 一起連不上。三件事必須守住：身分驗證是硬前提（順序錯就把錯誤身分固化）、
# dry-run 真的零 mutation、非 origin 的 remote 不能漏（實跑工作 mac 時就有兩條 fork remote）。
MG_SCRIPT="$ROOT/scripts/migrate-github-remotes.sh"
mg="$TMP/mg"; mkdir -p "$mg/roots"
export GIT_CONFIG_GLOBAL="$mg/gitconfig"   # 隔離：絕不能碰使用者真的 ~/.gitconfig
: > "$GIT_CONFIG_GLOBAL"

# ssh stub：認到正確身分
cat > "$mg/ssh-ok" <<'MGEOF'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in
        git@github.com) echo "Hi jjshen-eland! You've successfully authenticated"; exit 1 ;;
        git@github-me)  echo "Hi dev-bitpod-cc! You've successfully authenticated"; exit 1 ;;
    esac
done
echo "unexpected: $*"; exit 1
MGEOF
# ssh stub：**連得上但認到錯帳號**——IdentitiesOnly 沒設時的真實長相，正是 gate 要擋的
cat > "$mg/ssh-wrong" <<'MGEOF'
#!/usr/bin/env bash
echo "Hi dev-bitpod-cc! You've successfully authenticated"; exit 1
MGEOF
chmod +x "$mg/ssh-ok" "$mg/ssh-wrong"

mg_mkrepo() {   # $1=名字 $2=origin url [$3=額外 remote 名 $4=額外 url]
    local d="$mg/roots/$1"
    git init -q -b main "$d"
    git -C "$d" remote add origin "$2"
    [ $# -ge 4 ] && git -C "$d" remote add "$3" "$4"
}
mg_reset() {
    rm -rf "$mg/roots"; mkdir -p "$mg/roots"
    mg_mkrepo work-a  "git@github-work:elandcomtw/krepo.git"
    mg_mkrepo work-b  "git@github-work:elandinfo/biz-chat.git" fork "git@github-work:elandinfo/fork-biz-chat"
    mg_mkrepo mine    "git@github.com:dev-bitpod-cc/isdotgd.git"
    mg_mkrepo other   "https://gitlab.internal/iac/thing.git"
}
mg_url() { git -C "$mg/roots/$1" remote get-url "${2:-origin}"; }

# 身分認到錯帳號 → STOP 且零 mutation
mg_reset
MIGRATE_SSH="$mg/ssh-wrong" "$MG_SCRIPT" --apply "$mg/roots" >/dev/null 2>&1
assert_rc "身分認到錯帳號 → exit 1（STOP）" 1 $?
assert_eq "STOP 時零 mutation（remote 原封不動）" \
    "git@github-work:elandcomtw/krepo.git" "$(mg_url work-a)"

# dry-run：印計畫、零 mutation
out="$(MIGRATE_SSH="$mg/ssh-ok" "$MG_SCRIPT" "$mg/roots")"
assert_rc "dry-run → exit 0" 0 $?
if grep -q '^would-change: ' <<< "$out"; then ok "dry-run 印出換寫計畫"; else bad "dry-run 未印計畫（${out}）"; fi
assert_eq "dry-run 零 mutation" "git@github-work:elandcomtw/krepo.git" "$(mg_url work-a)"
if grep -q 'dry-run' <<< "$out"; then ok "dry-run 明示未執行"; else bad "dry-run 未告知這只是計畫"; fi

# --apply：三種換寫都對，不該動的不動
out="$(MIGRATE_SSH="$mg/ssh-ok" "$MG_SCRIPT" --apply "$mg/roots")"
assert_rc "--apply → exit 0" 0 $?
assert_eq "github-work → 標準 github.com" "git@github.com:elandcomtw/krepo.git" "$(mg_url work-a)"
assert_eq "個人 repo → github-me"          "git@github-me:dev-bitpod-cc/isdotgd.git" "$(mg_url mine)"
assert_eq "非 GitHub 的 remote 不得被碰"   "https://gitlab.internal/iac/thing.git"   "$(mg_url other)"
# 本次的重點：spec 那段手貼迴圈只掃 origin，工作 mac 上就有兩條 fork remote 會被留下
assert_eq "非 origin 的 remote 同樣換寫"   "git@github.com:elandinfo/fork-biz-chat"  "$(mg_url work-b fork)"

# 幂等：再跑一次應無事可做
out="$(MIGRATE_SSH="$mg/ssh-ok" "$MG_SCRIPT" --apply "$mg/roots")"
if grep -q '需換寫 0' <<< "$out"; then ok "--apply 幂等（第二次無事可做）"; else bad "重跑仍有換寫（${out}）"; fi

# insteadOf：只清 github-work 那幾條，使用者其他的改寫規則不得被波及
git config --global "url.git@github-work:elandcomtw/.insteadOf" "git@github.com:elandcomtw/"
git config --global "url.git@internal-mirror/.insteadOf" "https://internal/"
MIGRATE_SSH="$mg/ssh-ok" "$MG_SCRIPT" --apply "$mg/roots" >/dev/null 2>&1
if ! git config --global --get-regexp 'insteadof' 2>/dev/null | grep -q 'github-work'; then ok "github-work 的 insteadOf 已清"; else bad "insteadOf 未清（收斂沒完成）"; fi
if git config --global --get-regexp 'insteadof' 2>/dev/null | grep -q 'internal-mirror'; then ok "無關的 insteadOf 未被波及"; else bad "誤刪了使用者其他的 insteadOf"; fi

# --skip-identity-check：明說才跳過（stub 給錯身分也照跑）
mg_reset
MIGRATE_SSH="$mg/ssh-wrong" "$MG_SCRIPT" --apply --skip-identity-check "$mg/roots" >/dev/null 2>&1
assert_rc "--skip-identity-check → 跳過 gate、exit 0" 0 $?
assert_eq "跳過 gate 後仍正常換寫" "git@github.com:elandcomtw/krepo.git" "$(mg_url work-a)"

# 未知選項 → exit 2（**不得**被當成路徑或靜默忽略：那會讓 --aply 這種打錯字變成
# 「掃了整個 $HOME、什麼都沒做」而使用者以為跑過了）
"$MG_SCRIPT" --aply "$mg/roots" >/dev/null 2>&1
assert_rc "未知選項 → exit 2" 2 $?

unset GIT_CONFIG_GLOBAL

echo ""
echo "════════════════════════════"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ 全部通過" || echo "❌ 有失敗"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
