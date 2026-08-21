#!/usr/bin/env bash
#
# ship-state.sh — /project log Step 0/1 的 ship 狀態偵測（單次呼叫、多 repo、唯讀）
#
# 用法：
#   ship-state.sh <repo-path>...          # 逐 repo ship 狀態偵測
#   ship-state.sh resolve <token>         # Step 0 repo-token 判定（單一 token）
#
# 逐 repo 輸出：branch / remotes / default / 變更集（files-vs-default 三點、
# commits-ahead 兩點、working-tree porcelain）/ misplaced（誤 commit 在本地
# default，附 branch-first-cmd 供照抄）/ dossier 偵測（STATUS.md 衛生，門檻
# 單一來源在本腳本）/ review-residue（review 迭代痕跡與可照抄的 squash 指令，Step 4 出題依據）/
# protection verdict / ship-path / branch-first。default 定位
# 不到時改印 bootstrap 判定（遠端零 branch → BOOTSTRAP + 可照抄 push 指令；遠端有
# branch → STOP，見 detect_bootstrap）。
#
# resolve 輸出單行 verdict（照 verdict 走，勿重新詮釋）：
#   resolve: REPO <toplevel>   token 解析為 repo 根（兩端 realpath 正規化後相等；'.' 恆為
#                              pwd 所屬 repo 根）
#   resolve: MODULE（...）      解析到 repo 但非根（子路徑 scope）→ 當 module 過濾
#                              （module 過濾**只能**由路徑形式產生，見 `../references/log-workflow.md`「引數前處理（依形狀分類，不靠優先序記憶）」）
#   resolve: UNKNOWN（...）     非 git repo 路徑 → 交回 session 記憶 basename 比對；
#                              不命中即**停下問**，NEVER 當成 module 過濾（靜默縮小掃描範圍）
# 注意：第一引數 `resolve` 為子指令保留字——repo 目錄字面名為 resolve 時以路徑形式
# （./resolve）傳入偵測模式即可。
#
# exit code：0 = 偵測完成（有無變更、resolve 任一 verdict 都算成功）；
#            1 = 有 repo 無效；2 = 用法錯誤
#
# 設計原則：
# - 唯讀。不 commit、不 switch——mutation 一律留給 skill 流程（branch-first
#   搬移、提交、push 都在 Step 1/3/5 由 model 依 Critical gate 執行）。**不 fetch**——
#   碰網路的例外有二，都是 ls-remote（唯讀、不改任何本地 ref），且都在「本地狀態根本
#   分辨不出來」的地方：① default 定位不到時的 bootstrap 判定（見 detect_bootstrap）；
#   ② squash-merged 的 remote 行核對（見 detect_squash_merged_branches——該段本來就要
#   打 gh，故不是新增網路依賴）。
# - protection 判定封裝於此（classic + ruleset，邏輯解說見 references/ship-paths.md，
#   本腳本為可執行權威）。Unknown = protected 直接印在輸出裡，不留給 model 重新詮釋。
#
# SHIP_STATE_GH 僅供測試 stub gh（tests/run.sh）；正常使用不需設定。

set -uo pipefail

MAX_LIST=20  # 每類清單最多列出的行數；只影響顯示，計數仍為完整值
GH_BIN="${SHIP_STATE_GH:-gh}"
# doc-governance:trusted-core:start
SHIP_STATE_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TRUSTED_DOC_CORE="$SHIP_STATE_DIR/../../../../scripts/doc-governance.py"
# doc-governance:trusted-core:end

# legacy dossier detector 的衛生門檻（單一數值來源；改門檻只改這裡）。
DOSSIER_MAX_LINES=300  # 全檔超過即「當次收斂」硬訊號（krepo 599 行先例：訊號密度崩壞）
DOSSIER_STALE_DAYS=30  # STATUS.md 最後 commit 落後 repo 活動超過即過期（假狀態比沒有更糟）
DOSSIER_MAX_BYTES=24576      # 行數代理會被巨型單行架空（evint 117 行/38KB 實證）；24KB ≈ 300 行 × krepo 收斂後密度（~85B/行）
DOSSIER_MAX_LINE_BYTES=1000  # 巨型單行風格的早期糾正訊號（≈330 中文字；正常換行段落 <300B）。量 bytes 非字元——macOS BSD awk 的 length 不分 locale 一律數 bytes，字元門檻跨平台不確定
DOSSIER_ENTRY_MAX_BYTES=800  # 決策/里程碑單一條目蒸餾上限（決策≤5行×~160B；量 bytes 防單行繞過行數）
DOSSIER_SECTIONS_TOP_N=6     # 各節佔比只列前 N 大——超標時要的是「該動哪一節」，尾巴小節是噪音
DOSSIER_TARGET_PCT=85        # 收斂建議目標＝門檻的百分比。壓到「剛好低於門檻」等於下次 ship 必再觸發（krepo #33 收到 23,920/24,576、隔天加兩條決策就再越線）——留餘裕才是一次做完

if [ $# -eq 0 ]; then
    echo "用法：$0 <repo-path>... | resolve <token>" >&2
    exit 2
fi

# --- resolve 子指令（Step 0 repo-token 判定）---
if [ "$1" = "resolve" ]; then
    shift
    if [ $# -ne 1 ]; then
        echo "用法：$0 resolve <token>" >&2
        exit 2
    fi
    token="$1"
    top="$(git -C "$token" rev-parse --show-toplevel 2>/dev/null)" || top=""
    if [ -z "$top" ]; then
        echo "resolve: UNKNOWN（${token} 非 git repo 路徑——交回 session 記憶 basename 比對；不命中即停下問，勿當 module）"
        exit 0
    fi
    # '.' 恆指 pwd 所屬 repo 根（舊 SKILL.md 契約）——在子目錄下也鎖定所屬 repo，
    # 不落入下方「非根 → MODULE」判定
    if [ "$token" = "." ]; then
        echo "resolve: REPO ${top}"
        exit 0
    fi
    # 兩端正規化比對：--show-toplevel 回傳已解 symlink 的絕對路徑，token 可能是
    # 相對路徑/含 symlink——裸字串比對會 false-negative，故 token 端用 pwd -P 正規化。
    # CDPATH='' 隔離環境干擾（cd builtin 吃 CDPATH，相對 token 會被拐去別處且污染 stdout）；
    # cd 失敗（權限/競態）→ real 留空走 UNKNOWN，不謊稱 MODULE
    real="$(CDPATH='' cd -- "$token" 2>/dev/null && pwd -P)" || real=""
    if [ -z "$real" ]; then
        echo "resolve: UNKNOWN（${token} 無法進入（cd 失敗）——交回 session 記憶 basename 比對；不命中即停下問，勿當 module）"
    elif [ "$real" = "$top" ]; then
        echo "resolve: REPO ${top}"
    else
        echo "resolve: MODULE（${token} 在 repo ${top} 內但非根——當 module 過濾，不鎖定 repo）"
    fi
    exit 0
fi

overall=0

# 印一段清單（stdin），縮排並截斷到 MAX_LIST
# 照抄行裡的路徑一律過這個 helper——直接插進單引號會在路徑含單引號時讓 quoting 破裂
# （實測 `/tmp/alice's-repo` 產出的行 `bash -n` 直接 syntax error）。三支腳本各留一份 3 行
# 純函式：它是標準演算法、不是會漂移的事實，比為它多開一個跨 skill lib 依賴划算。
shq() { local q="'"; printf "%s%s%s" "$q" "${1//$q/$q\\$q$q}" "$q"; }

print_list() {
    local total="$1"
    head -n "$MAX_LIST" | sed 's/^/  /'
    [ "$total" -gt "$MAX_LIST" ] && echo "  ...（其餘 $((total - MAX_LIST)) 行略）"
}

# canonical remote：有 origin 用之，否則取第一個；無 remote 輸出空字串
detect_remote() {
    local repo="$1" remotes
    remotes="$(git -C "$repo" remote)"
    if printf '%s\n' "$remotes" | grep -qx origin; then
        echo origin
    else
        printf '%s\n' "$remotes" | head -1
    fi
}

# default branch：remote HEAD → probe main/master；找不到輸出空字串
detect_default_branch() {
    local repo="$1" remote="$2" ref cand
    ref="$(git -C "$repo" symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null)" || ref=""
    ref="${ref#"$remote"/}"
    if [ -n "$ref" ] && [ "$ref" != "HEAD" ]; then
        echo "$ref"
        return 0
    fi
    for cand in main master; do
        if git -C "$repo" rev-parse --verify --quiet "$remote/$cand" >/dev/null; then
            echo "$cand"
            return 0
        fi
    done
    echo ""
}

# Bootstrap 偵測（僅在 default 定位不到時呼叫）：分辨「遠端零 branch」（全新空 repo，
# 尚無 default branch 可保護 → 可建 baseline）與「遠端有 branch 但本地定位不到 default」
# （未 fetch / default 名非 main|master → 絕不可推）。兩者的正確處置完全相反。
#
# ⚠ 本函式是本腳本**唯一碰網路**的地方（檔頭「不 fetch」設計原則的顯性例外）。理由：
# 未 fetch 的 clone 下，兩種情境的本地 ref 長得一模一樣，靠本地狀態無法分辨；猜錯的
# 代價是把 feature branch 推成遠端 default branch（GitHub 以第一個 push 的 branch 為
# default，事後只能人工進 settings 改）。ls-remote 唯讀、不改任何本地 ref。
# 例外限縮在 default: NONE 分支內——正常路徑一次網路都不碰。
#
# 防授權蔓延：BOOTSTRAP 的成立條件是「遠端零 branch」，baseline 一 push 條件即永久為假，
# 本函式再也不會印 BOOTSTRAP、branch-first 恢復 REQUIRED。豁免作用域由此機制界定，
# 不靠 agent 記憶（實證失效模式：初始匯入的 push 授權被延伸到後續 commit）。
detect_bootstrap() {
    local repo="$1" remote="$2" branch="$3" toplevel="$4" heads rc n
    heads="$(git -C "$repo" ls-remote --heads "$remote" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "remote-heads: UNKNOWN（ls-remote 失敗 rc=${rc}：$(printf '%s' "${heads}" | head -1)）"
        echo "verdict: STOP（無法判定遠端是否為空——網路/認證問題，修好再跑；NOT bootstrap，勿臆測）"
        return
    fi
    if [ -n "$heads" ]; then
        n="$(printf '%s\n' "${heads}" | wc -l | tr -d ' ')"
        echo "remote-heads: ${n}（遠端有 branch，但本地定位不到 default）"
        printf '%s\n' "${heads}" | awk '{print $2}' | print_list "$n"
        echo "verdict: STOP（NOT bootstrap——先 git fetch，或由使用者指定 default 名；此情境直推會推錯 branch）"
        return
    fi
    echo "remote-heads: 0（遠端無任何 branch）"
    if [ "$branch" = "DETACHED" ]; then
        echo "verdict: STOP（遠端雖空，但 HEAD detached、無 branch 名可當 baseline——先 switch 到具名 branch）"
        return
    fi
    echo "verdict: BOOTSTRAP（全新空 repo 的第一次 ship：遠端尚無 default branch，故無 default 可保護、branch-first 在此不適用）"
    echo "bootstrap-note: 首推的 branch 將成為遠端 default branch —— 推 '${branch}' 即以它為 default（事後只能人工進 repo settings 改），Step 4 摘要須向使用者標明"
    echo "bootstrap-scope: 豁免僅涵蓋下面這一次 push（建立 baseline）。baseline 一存在，本 verdict 即不再出現、branch-first 與 never-push-default 全數恢復——後續 commit 一律走 feature branch"
    echo "bootstrap-cmd: git -C $(shq "$toplevel") push -u $(shq "$remote") $(shq "$branch")"
}

# protection 判定（classic + ruleset；判定順序見 ship-paths.md）
# 輸出單行 "protection: ..."，UNKNOWN 一律附 treat as PROTECTED
detect_protection() {
    local repo="$1" remote="$2" default="$3"
    if ! command -v "$GH_BIN" >/dev/null 2>&1; then
        echo "protection: UNKNOWN（gh 不可用）→ treat as PROTECTED"
        return
    fi
    local slug
    slug="$( (cd "$repo" && "$GH_BIN" repo view --json nameWithOwner -q .nameWithOwner) 2>/dev/null)"
    if [ -z "$slug" ]; then
        # fallback：從 remote URL 解析 owner/repo（吃 scp-SSH / ssh:// / HTTPS）
        slug="$(git -C "$repo" remote get-url "$remote" 2>/dev/null \
            | sed -E 's#^(git@[^:]+:|ssh://[^/]+/|https?://[^/]+/)##; s#\.git$##')"
    fi
    case "$slug" in
        */*) ;;  # 長得像 owner/repo 才能查 API
        *)  echo "protection: UNKNOWN（無法解析 owner/repo）→ treat as PROTECTED"
            return ;;
    esac
    local enc="${default//\//%2F}"  # default 名含 '/'（如 release/2026）→ encode
    local classic classic_rc rules
    classic="$("$GH_BIN" api "repos/$slug/branches/$enc/protection" 2>&1)"
    classic_rc=$?
    rules="$("$GH_BIN" api "repos/$slug/rules/branches/$enc" 2>/dev/null)" || rules=""

    if [ "$classic_rc" -eq 0 ] || { [ -n "$rules" ] && [ "$rules" != "[]" ]; }; then
        echo "protection: PROTECTED（classic rc=${classic_rc}；ruleset $([ -n "$rules" ] && [ "$rules" != "[]" ] && echo 非空 || echo 空/未查得)）"
    elif printf '%s' "$classic" | grep -q "Branch not protected" && [ "$rules" = "[]" ]; then
        echo "protection: OPEN（classic 404 Branch not protected + ruleset []）"
    elif printf '%s' "$classic" | grep -q "Not Found"; then
        # Not Found ≠ 無保護：常見 gh 帳號無權讀 protection（身分分離，見 ship-paths.md）
        local perm
        perm="$( (cd "$repo" && "$GH_BIN" repo view "$slug" --json viewerPermission -q .viewerPermission) 2>/dev/null)"
        echo "protection: UNKNOWN（classic Not Found，gh 帳號可能無權讀 protection；viewerPermission=${perm:-?}，注意身分分離）→ treat as PROTECTED"
    else
        echo "protection: UNKNOWN（無法分辨：403/網路/其他）→ treat as PROTECTED"
    fi
}

# 標題掃描前剝 fenced code block（```/~~~ 圍欄內的範例標題不算章節），印到 stdout。
# CommonMark 規則：closer 須與 opener 同字元且長度 ≥ opener——單純 toggle 會被
# 四反引號外層包三反引號範例的巢狀圍欄誤判提前關欄（C3 審查實證）。
#
# 剝除方式是**前綴 \001 哨兵**，不是丟棄、也不是清空——兩個下游同時有要求：
# - 行號要對齊原檔：條目 flag 得報「超標的是第幾行」，丟棄會讓後續 NR 全數位移。
# - 長度要保留真實值：清空會讓 fence 重的章節在 dossier-sections 佔比中被低估，
#   嚴重時排名倒轉（實測 26KB 的決策節報成 403 bytes、沉到 4.5KB 的節後面）。
#   那正是該功能要防的「挑錯收斂對象」，清空等於讓它主動誤導。
# 哨兵前綴打掉三個 pattern 家族（^##[[:space:]] 章節/簽章、^#{1,6} Session Log、
# ^-[[:space:]] 條目起始），圍欄內的假標題/假條目照樣不被誤認。
#
# **抽成函數是因為第二個消費者出現了**（detect_backlog）。同一份圍欄規則若複製一份，
# 兩邊必然漂移——那正是這支腳本反覆在防的形狀（SKILL.md 與腳本各寫一份處置的先例）。
strip_fences() {
    awk '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line ~ /^(```|~~~)/) {
                ch = substr(line, 1, 1)
                n = 1
                while (substr(line, n + 1, 1) == ch) n++
                if (!fence) { fence = 1; fch = ch; flen = n; print "\001" $0; next }
                if (ch == fch && n >= flen) { fence = 0 }
                print "\001" $0
                next
            }
            if (!fence) { print } else { print "\001" $0 }
        }' "$1"
}

# dossier（STATUS.md）唯讀偵測：存在性、尺寸訊號、進行中 ✅、規範外章節、過期。
# **量測與逐 flag 處置皆在此**（單一來源；legacy 流程只照 flag 訊息做、不複述——
# 兩邊各寫一份必然漂移，實證：SKILL 曾把「改正常換行段落」列為處置，腳本卻明說換行不夠）。
# 留給 model 的判斷層：蒸餾什麼內容、傘狀雙重記載比對、使用者說「別動它」時怎麼處置。
detect_dossier() {
    local repo="$1" f="$1/STATUS.md"
    if [ ! -f "$f" ]; then
        echo "dossier: NONE（無 STATUS.md——repo 非 trivial 時在 Step 4 摘要附註建議建立，不出題、不自動建）"
        return
    fi
    # 三個尺寸量測皆為確定性訊號（prose 下沉為腳本——蒸餾判斷歸 model、量測歸腳本）：
    # 行數（換行風格 repo 最易讀的代理）、bytes（風格不敏感後盾）、最長行（巨型單行早期糾正）。
    local lines bytes maxlen
    lines="$(wc -l < "$f" | tr -d ' ')"
    bytes="$(wc -c < "$f" | tr -d ' ')"
    maxlen="$(LC_ALL=C awk '{ if (length > m) m = length } END { print m + 0 }' "$f")"
    echo "dossier: STATUS.md（${lines} 行 / ${bytes} bytes / 最長行 ${maxlen} bytes）"
    # 標題掃描先剝 fenced code block（機制與哨兵設計見 strip_fences 檔內註解）。
    # 讀 unfenced 的 code site 共五處：簽章 grep、分節 awk、條目 awk、✅ awk、Session Log grep。
    # **新增消費者時記得也吃 unfenced**——漏一個就是誤報（✅ 偵測就漏過一次）。
    # 例外：上面三個全檔量測（行數/bytes/最長行）刻意讀原檔——它們量的是檔案本身的體積，
    # fence 內容同樣佔預算。副作用：fence 裡的長行（長指令/base64/URL）會觸發最長行 flag，
    # 該處置提示對 code block 無意義，人工判斷即可。
    # 代價：fenced 內容計入條目與分節 bytes——那是對的，那些 bytes 真的佔 dossier 預算。
    local unfenced
    unfenced="$(strip_fences "$f")"
    # dossier 簽章（回流自 clean-room 盲寫版）：雙訊號——「進行中」章節 + 任一 dossier
    # 專屬章節（legacy schema 見 ~/.dotfiles/claude/templates/STATUS-legacy-template.md）。flag 缺席即被當
    # dossier 編輯，誤放行比誤攔截危險（攔截只是停下告知），故：
    # - 章節名須為**標題結尾**（允許裝飾前綴「## ⏳ 進行中」與括號後綴「已完成(里程碑)」），
    #   子字串比對會把「## 進行中的部署」＋「## 已完成的部署」這類領域看板誤認成 dossier
    # ⚠ 用 herestring 不用 `printf | grep -q`：grep -q 命中即退出，上游 printf 在大輸入下
    # （unfenced 可達 100KB+）寫不完就拿到 SIGPIPE(141)，`set -o pipefail` 讓整條判偽 →
    # `!` 反轉後**正常的大 dossier 被誤報簽章不符**，而該 flag 的處置是「停下、勿當 dossier 改」。
    # 實證：115KB fixture 下 cond1/cond2 皆 rc=141；小檔不發作（printf 寫得完），故潛伏。
    # 同型前例：krepo 的 scripts/backup/lib/dest_r2.sh（保底清單比對）。已入 claude/CLAUDE.md 已知地雷。
    if ! grep -qE '^##[[:space:]].*進行中[[:space:]]*$' <<< "$unfenced" \
        || ! grep -qE '^##[[:space:]].*(決策|死路|技術債|里程碑|已完成|已知缺口|移交準備度?)[[:space:]]*([（(][^（()）]*[）)])?[[:space:]]*$' <<< "$unfenced"; then
        echo "dossier-flag: 簽章不符（缺「進行中」或 dossier 專屬章節——撞名領域產物？勿當 dossier 改；spec 模式遇之停下告知）"
    else
        # 章節完整性：簽章只要求「任一」專屬章節在，故**整節被刪它抓不到**。
        # 2026-08-06 實地：一次 lines 操作的邊界只檢查下一個條目、沒檢查 `## `，把
        # 「已知缺口」「移交準備度」兩整節吃掉；行數變少不觸發任何尺寸 flag（那些只管上限），
        # 一路 merge 進 main 才發現。**內容遺失是 dossier 最貴的失效，靜默是最糟的形式。**
        local sec missing=""
        for sec in 進行中 決策 死路 技術債 里程碑 已知缺口 移交準備; do
            grep -qE "^##[[:space:]].*${sec}" <<< "$unfenced" || missing="${missing}${sec} "
        done
        if [ -n "$missing" ]; then
            echo "dossier-flag: 缺少規範章節：${missing}（legacy 七節模板見 ~/.dotfiles/claude/templates/STATUS-legacy-template.md）——**先確認是不是被誤刪**（尺寸 flag 只管上限、抓不到整節消失），確認是刻意留空則在該節寫一行說明"
        fi
    fi
    # 收斂建議目標：不是「壓到剛好低於門檻」（見 DOSSIER_TARGET_PCT 註解）
    local target_lines target_bytes oversize=0 order_hint
    target_lines=$(( DOSSIER_MAX_LINES * DOSSIER_TARGET_PCT / 100 ))
    target_bytes=$(( DOSSIER_MAX_BYTES * DOSSIER_TARGET_PCT / 100 ))
    # 收斂順序（兩條全檔 flag 共用一份，不得各自演化）。
    # 為何順序要寫進 flag 而不是只留在 references/dossier.md：那份規範早就寫了「超標時
    # **優先歸檔**、不要為幾百 bytes 去壓無關舊條目」，但**只有 flag 會在動手當下被讀到**
    # ——舊文字「蒸餾＋歸檔」把最不可逆的手段排在第一個，與規範相反。
    # 危險不對稱才是理由：歸檔只是搬家（留指標即可取回），蒸餾砍掉的是理由與實測數字，
    # git history 找得回文字、找不回「當初為什麼認為這個數字重要」。
    order_hint="收斂順序：①砍掉 repo 內已有權威的重複（規格/CLAUDE.md 已載明者）②整批歸檔已成歷史的段落並留指標 ③**最後才蒸餾**——逐條壓字通常收不回足夠 bytes，而被壓掉的往往正是理由與實測數字"
    if [ "$lines" -gt "$DOSSIER_MAX_LINES" ]; then
        oversize=1
        echo "dossier-flag: 全檔 ${lines} 行 > ${DOSSIER_MAX_LINES}（硬訊號——當次收斂。${order_hint}；建議收斂至 ≤ ${target_lines} 行，留得下數次 ship 的成長）"
    fi
    if [ "$bytes" -gt "$DOSSIER_MAX_BYTES" ]; then
        oversize=1
        echo "dossier-flag: 全檔 ${bytes} bytes > ${DOSSIER_MAX_BYTES}（行數代理失真——硬訊號同全檔過長，當次收斂。${order_hint}；巨型單行另需改正常換行段落；建議收斂至 ≤ ${target_bytes} bytes）"
    fi
    # 各節佔比：只在超標時印（平時是噪音）。沒有這行，收斂對象只能靠印象猜——
    # 實證：krepo 2026-07-29 憑印象挑了里程碑節開刀，一輪 PR 只省 905 bytes，
    # 真正的大戶是關鍵決策 30% + 進行中 25%。量一次就不會挑錯。
    if [ "$oversize" -eq 1 ]; then
        local sections
        sections="$(LC_ALL=C awk '
            # b > 0 而非 sec != ""：第一個 ## 之前的前言（檔頭註解 + H1 + 定位句）與空名
            # 章節原本被靜默丟棄，表格會把 agent 導向錯的地方——殘量要現身、空節不佔位
            function emit() { if (b > 0) printf "%d\t%s\n", b, (sec == "" ? "(前言/未分節)" : sec) }
            # 標題行本身計入它開啟的那一節（b 從標題長度起算、不是 0）：歸零會讓各節加總
            # 系統性少掉每個標題的長度，佔比表恆略低於 100%，讀的人會以為有一塊沒被算到
            /^##[[:space:]]/ { emit(); sec = $0; sub(/^##[[:space:]]+/, "", sec); l = $0; sub(/^\001/, "", l); b = length(l) + 1; next }
            { l = $0; sub(/^\001/, "", l); b += length(l) + 1 }
            END { emit() }' <<< "$unfenced" | LC_ALL=C sort -rn | head -n "$DOSSIER_SECTIONS_TOP_N" | LC_ALL=C awk -v total="$bytes" -F'\t' '
            { printf "%s%s %d (%d%%)", (NR > 1 ? " / " : ""), $2, $1, ($1 * 100 / total) }
            END { printf "\n" }')"
        # 百分比分母是全檔 bytes，而各節量的是剝掉 fenced 區塊後的內容——故加總必然 <100%，
        # 差額就是 code fence。明寫出來，免得讀的人以為漏算了哪一節
        [ -n "$sections" ] && echo "dossier-sections: ${sections}（前 ${DOSSIER_SECTIONS_TOP_N} 大，佔全檔 bytes；不含 fenced 區塊，故加總 <100%。先量再決定動哪節）"
    fi
    if [ "$maxlen" -gt "$DOSSIER_MAX_LINE_BYTES" ]; then
        echo "dossier-flag: 最長行 ${maxlen} bytes > ${DOSSIER_MAX_LINE_BYTES}（巨型單行——**風格訊號、非硬門檻**：不必當次收斂，下次編到該段時順手 rewrap 即可；但 rewrap 後仍超標者需蒸餾，不是只換行）"
    fi
    # 決策/里程碑條目蒸餾上限：以頂層「- 」bullet 為條目邊界、續行（含縮排子彈）併入條目，
    # 量 bytes（LC_ALL=C 下 awk length 即 bytes）防巨型單行繞過行數。只掃這兩節——
    # 「進行中」條目含 spec 區（Context/Goal/AC/Constraints）合法偏大，設上限會逼薄工作合約。
    # 掃 unfenced 版：fenced 範例內的假標題不得切換節狀態（同簽章偵測的理由）。
    # 同時記錄超標條目的起始行號：只報 bytes 不報位置時，agent 的預設猜測是「應該是我剛
    # 寫的那條」——多 session 並行改同一份 dossier 時經常猜錯（krepo 2026-07-29 實證：
    # 猜錯兩次、白壓兩輪，最後自己寫 awk 才找到真正超標的是別人稍早改的條目）。
    # 只給行號不給內容摘錄：LC_ALL=C 下 substr 按 bytes 切，中文會被截在字中間變亂碼。
    local entry_out max_entry max_entry_line
    entry_out="$(LC_ALL=C awk '
        function flush() { if (cur > max) { max = cur; maxline = curline } cur = 0 }
        # 節名錨在標題開頭，不用子字串比對：`## 進行中（已完成 M1）` 這種寫法含「已完成」
        # 三個字，子字串版會把整個進行中章節當成里程碑節掃進條目尺寸判定（進行中的 spec 區
        # 合法偏大，於是恆誤報）。錨定後只有真的以那些節名開頭的標題才算。
        /^##[[:space:]]/ { flush(); insec = ($0 ~ /^##[[:space:]]*(關鍵決策|已完成|里程碑)/); next }
        insec && /^-[[:space:]]/ { flush(); cur = length($0); curline = NR; next }
        # 條目止於「不是續行」的東西：行首 blockquote、標題（### 不被上面的 ^## 攔到）、
        # 分隔線。三者都是條目外的獨立區塊，續行則一律有縮排、不會匹配到這裡。
        # 少了這條，緊跟在條目後的**歸檔指標 blockquote** 會被算進前一條 → 假陽性超標，
        # 而它正是收斂做對之後的產物（krepo-mops-major-news 2026-08-13：280B 決策 ＋
        # 524B 指標 ＝ 804B，超標 4 bytes，且「拆成多條」的處置對它無效）。
        # 帶哨兵 \001 的行不在此列——那是 fenced 內容，計入條目 bytes 是刻意的。
        insec && cur && /^(>|#|---)/ { flush(); next }
        insec && cur { l = $0; sub(/^\001/, "", l); cur += length(l) + 1 }
        END { flush(); printf "%d\t%d\n", max + 0, maxline + 0 }' <<< "$unfenced")"
    max_entry="${entry_out%%	*}"
    max_entry_line="${entry_out##*	}"
    if [ "$max_entry" -gt "$DOSSIER_ENTRY_MAX_BYTES" ]; then
        # 建議目標同全檔 flag 的理由（見 DOSSIER_TARGET_PCT）：壓到剛好低於上限＝下次
        # 任何編輯即再觸發。這裡漏套用過——2026-08-13 實測五個 repo 的最大條目落在
        # 798 / 788 / 784 / 778 / 725，聚在上限下緣，正是「壓到剛好過關」的形狀。
        local target_entry
        target_entry=$(( DOSSIER_ENTRY_MAX_BYTES * DOSSIER_TARGET_PCT / 100 ))
        echo "dossier-flag: 決策/里程碑節最大條目 ${max_entry} bytes > ${DOSSIER_ENTRY_MAX_BYTES}（在第 ${max_entry_line} 行；蒸餾上限——決策留結論、里程碑一行化，推導史沉 git history。**若該條涵蓋多個決策 → 拆成多條，不是壓字**；建議收斂至 ≤ ${target_entry} bytes，留得下數次 ship 的成長）"
    fi
    # 「進行中」節內的 ✅ = 完成項未移走；其他節（里程碑）的 ✅ 合法，不得誤報。
    # ⚠ `/✅/` **沒有行首錨點**，哨兵中和不了它——必須自行 `/^\001/ { next }` 跳過圍欄行。
    # 少了那條會出現兩個方向的誤報：①圍欄內貼的測試輸出（滿是 ✅）被當成未移走的完成項
    # ②哨兵讓圍欄內的假標題不再切節，in_sec 一路開著，圍欄內的 ✅ 全算進「進行中」
    # （②是加哨兵後才出現的回歸——改動前假標題會把 in_sec 關掉，反而歪打正著）
    # 節名同樣錨在標題開頭（理由見上方條目 awk）：`## 已完成（進行中殘項）` 含「進行中」
    # ⚠ 只認**條目形狀（list item）**的行，不是「節內任何一行含 ✅」。表格儲存格的 ✅ 是
    # 子項狀態欄（「這個共用件已就位」），不是「一個做完卻沒搬走的項目」——krepo 2026-08-10
    # 連三次 ship 都被誤報同一張盤點表，每次只能在 Step 4 附註寫「未處理」。flag 訊息叫人
    # 「移入里程碑」而里程碑節的內容形狀就是 bullet，一列表格搬過去無處可放：訊息本身就
    # 透露了判準抓錯對象。**誤報的代價不是美觀**——同一份輸出裡混著「要照做的」與「照例
    # 忽略的」，久了會稀釋其他硬訊號 flag 的可信度。
    # marker 後**必須**有空白：少了它 `**粗體** ✅` 這種散文強調行會被當成 bullet，收窄失效。
    # 前導空白放行（縮排子項 `  - ✅ x` 同樣是真的完成項未移走）。
    # 兩個被實地反例否決的候選判準，別再走回頭路：
    #   ①「整張表全 ✅ 才算做完」——krepo 那張表 4 列**全部**含 ✅，這條照樣誤報，而且還要
    #     多辨識表格邊界。②「把續行併入所屬條目」（比照上方條目 bytes 的 awk）——krepo 的
    #     表格前隔著散文、但更前面第 259 行有 bullet，寬續行模型會把表格收回同一條目，同樣
    #     照樣誤報。兩者都有守門 fixture 釘住。
    # 已知且刻意放棄的 false negative：✅ 寫在條目**續行**上不會亮（如 `- 項目\n  ✅ 某步完成`）。
    # 那與盤點表同性質——都是條目內部的進度標註，不是「整條做完該搬去里程碑」；且要撈回它
    # 就得採上面②那個已被否決的模型。以表格逐列管理待辦的 dossier 同理不亮。
    if awk '/^\001/ { next } /^##[[:space:]]/{ in_sec = ($0 ~ /^##[[:space:]]*進行中/) } in_sec && /^[[:space:]]*[-*+][[:space:]]/ && /✅/ { found=1 } END { exit !found }' <<< "$unfenced"; then
        echo "dossier-flag: 「進行中」含 ✅ 完成項（Step 2 當場移入里程碑）"
    fi
    # herestring 同上：避免大輸入下 grep 早退觸發 SIGPIPE + pipefail 的偽陰性
    # 別名家族：規範說的是「NEVER add an append-only log section」，不是「不要叫 Session Log」
    # ——只認那一個字面時，換個名字（變更紀錄／工作日誌／CHANGELOG）就整個漏掉。
    # ASCII 走 -i（涵蓋 CHANGELOG／change log）；中文含記/紀異體。
    # **限完整章節名（允許括號或冒號後綴）**，不做寬鬆子字串——否則「## 為何不使用 Change Log」
    # 這類討論性章節會被判紅，而 gate 誤報的代價是逼人改壞寫法以求過測。
    # 訊息附**實際命中的 heading**：硬寫「Session Log」會讓別名命中時的處置指向錯的章節。
    local ao_hit
    ao_hit="$(grep -iEm1 '^#{1,6}[[:space:]]+(Session[[:space:]]*Log|Change[[:space:]]*Log|變更記錄|變更紀錄|工作日誌|開發日誌)([[:space:]]*[（(：:].*)?[[:space:]]*$' <<< "$unfenced")" || ao_hit=""
    if [ -n "$ao_hit" ]; then
        echo "dossier-flag: 規範外章節（append-only log：${ao_hit}）——git history 才是 log，蒸餾後歸檔"
    fi
    # 過期：STATUS.md 最後 commit 落後 repo 最新活動的天數（%ct = committer time）
    local st_ct head_ct lag
    st_ct="$(git -C "$repo" log -1 --format=%ct -- STATUS.md 2>/dev/null)" || st_ct=""
    head_ct="$(git -C "$repo" log -1 --format=%ct 2>/dev/null)" || head_ct=""
    if [ -n "$st_ct" ] && [ -n "$head_ct" ]; then
        lag=$(( (head_ct - st_ct) / 86400 ))
        if [ "$lag" -gt "$DOSSIER_STALE_DAYS" ]; then
            echo "dossier-flag: 最後 commit 落後 repo 活動 ${lag} 天 > ${DOSSIER_STALE_DAYS}（過期——列入 Step 4 附註告知、本次重點補齊）"
        fi
    fi

    # 歸檔孤兒：`docs/archive/*.md` 沒有被任何 md 連到 → 檔案還在 git 裡，但從 dossier
    # 走不到，**等於不存在**。歸檔正是製造這種失效的主要途徑，而它完全靜默——本檔開頭
    # 那句「內容遺失是 dossier 最貴的失效，靜默是最糟的形式」講的就是這個。
    # 既有守門只驗**正向**（dotfiles 的 xref-gate：指標指到的節/檔在不在），反向從沒查過，
    # 且那個 gate 只跑本 repo。實測 2026-08-14：evint 6/10、krepo 9/29 是孤兒，
    # 而提出此缺口的 repo 自己 0/8——**風險真實，但在自己的 repo 裡看不見**。
    # 只印訊號、絕不自動刪（同 stale-branches 的紀律：刪東西永遠不會自動發生）。
    if [ -d "${repo}/docs/archive" ]; then
        local orphans="" orph_n=0 af ab arch_refs cand ref_cnt
        # **單次掃描**收集所有提到 archive 的行（帶來源檔名，`-H`）。
        # 逐檔各跑一次 `grep -r` 的寫法對大 repo 會爆：krepo 29 個歸檔檔 → 13.0s，
        # 而這支腳本每次 ship 都跑。改成掃一次、之後都在這個小集合上比對。
        # `--include` 必須在 `--` **之前**——`--` 之後的一切都不再被當成選項，
        # 寫成 `-- pat --include=...` 會把 include 當搜尋路徑（首版踩過，靜默誤判）。
        # pattern 用 `.md` 而非 `archive`：**任何**對歸檔檔的引用必然含 `.md`（檔名本身
        # 就以它結尾），但不見得含 `archive`——實地反例（evint）：
        # `> （`…2026-07-27-status-pre-condense.md`）` 整行沒有 archive 字樣，
        # 用 `archive` 掃會把它判成孤兒。窄 pattern 的假陽性比多掃幾行貴得多：
        # 它會叫人去補一條本來就存在的指標，或更糟——以為那份歸檔可以刪。
        arch_refs="$(grep -rHF --include='*.md' -- '.md' "$repo" 2>/dev/null)" || arch_refs=""
        for af in "${repo}"/docs/archive/*.md; do
            [ -e "$af" ] || continue          # glob 無命中時字面展開
            ab="$(basename "$af")"
            # herestring 而非 pipe：`grep -q` 命中即退出會讓上游吃 SIGPIPE，
            # `set -o pipefail` 下整條判偽（CLAUDE.md 已知地雷）。
            cand="$(grep -F -- "$ab" <<< "$arch_refs")" || cand=""
            ref_cnt=0
            # 排除「檔案自己提到自身檔名」。grep -c 找不到時印 0 且 exit 1，故用
            # `|| ref_cnt=0` 而非 `$(... || echo 0)`——後者會產生雙行 `0\n0`。
            [ -n "$cand" ] && { ref_cnt="$(grep -cvF -- "${af}:" <<< "$cand")" || ref_cnt=0; }
            if [ "$ref_cnt" -eq 0 ]; then
                orph_n=$(( orph_n + 1 ))
                [ "$orph_n" -le "$MAX_LIST" ] && orphans="${orphans} docs/archive/${ab}"
            fi
        done
        if [ "$orph_n" -gt 0 ]; then
            [ "$orph_n" -gt "$MAX_LIST" ] && orphans="${orphans} …（共 ${orph_n} 份）"
            echo "dossier-flag: 歸檔孤兒${orphans}（無任何 md 連到——內容還在 git 裡但從 dossier 走不到,等於不存在。補一條指標、或確認確實不再需要;**不自動刪**）"
        fi
    fi
}
# backlog（docs/backlog.md）唯讀偵測：**只驗章節完整性，刻意不量體**。
# 為什麼這裡沒有 bytes／行數門檻：待辦是未結案狀態，你只能把字數壓短、條目數不會少，
# 直到真的把它做掉。量體門檻對它無效，而每次 ship 又都得走一遍那個檢查——2026-08-15 實測
# 本 repo 的 STATUS.md 有 11018 bytes（47%）是技術債＋已知缺口、26 條無一已解決，
# dossier 因此長期貼著門檻飛（8 次 commit 落在門檻的 98–99.8%）。分家正是為了消掉那個
# 結構下限（見 `../references/dossier.md`「角色分工」），**在新檔重設一套門檻等於把
# 問題原樣搬過來**。治理靠關閉與歸檔慣例，那是 model 的判斷層、不是腳本的。
# 保留的唯一機械保障是章節完整性：2026-08-06 實地「一次 lines 操作吃掉兩整節、尺寸 flag
# 抓不到（那些只管上限）、一路 merge 進 main」的失效面對新檔同樣成立，而它完全靜默——
# 這裡更該守，因為本檔連尺寸 flag 這個間接訊號都沒有。
# repo 沒有 `docs/backlog.md` 就零輸出：未分家的 repo 完全不受影響、零回填。
detect_backlog() {
    local repo="$1" f="$1/docs/backlog.md"
    [ -f "$f" ] || return 0
    local unfenced sec missing=""
    unfenced="$(strip_fences "$f")"
    for sec in 技術債 已知缺口; do
        grep -qE "^##[[:space:]].*${sec}" <<< "$unfenced" || missing="${missing}${sec} "
    done
    if [ -n "$missing" ]; then
        echo "backlog-flag: docs/backlog.md 缺少章節：${missing}（**先確認是不是被誤刪**——本檔刻意無尺寸 flag，整節消失沒有第二道訊號會提醒你）"
    fi
    return 0
}

# always-on 量體：這個 repo 的 root `CLAUDE.md`（Claude 每個 session 自動載入）與 `AGENTS.md`
# （Codex 每次讀），外加「該 repo 就是全域 CLAUDE.md 的來源」時的那一份。**只量 Claude 側是
# 半套**——這個工作流是雙 agent 的。
#
# 為什麼在 ship 時印：always-on 檔只在 ship 那一刻被 commit，訊號印在**動手當下**才有處置窗口
# （同全檔 flag 收斂順序的論證）。放 SessionStart hook 不行——那支的契約是「無事發生就完全
# 無輸出」，`tests/run.sh` 第 16 節有五條 `assert_eq ""` 擋著。
#
# **這是對 `dossier-sections:`「只在超標時印、平時是噪音」那條原則的刻意背離**：本行是
# baseline 觀測、不是處置訊號，無條件印才看得到趨勢。
# ⚠️ **升級成 flag 之前必須先解決「結構下限出口」**（見 `docs/plans/2026-08-14-dossier-governance.md`）
# ——機隊 root `CLAUDE.md` 最大 102968、dotfiles 16993 只排第十，貿然設門檻會有七八個 repo
# 每次 ship 都亮，那正是 krepo 137KB 現在的狀態：flag 常亮＝沒有 flag。
#
# ⚠️ **必須在 remote／default 的 early return 之前呼叫**——無 remote 的 repo 會在那裡就返回。
detect_always_on() {
    local repo="$1" toplevel="$2" f b parts="" present=0
    for f in CLAUDE.md AGENTS.md; do
        if [ ! -f "${toplevel}/${f}" ]; then
            parts="${parts}${parts:+ ＋ }${f} NONE"
            continue
        fi
        # 讀取失敗與「不存在」不得混為一談：UNKNOWN 是不知道、NONE 是確定沒有（同 protection
        # verdict 的語意）。空字串餵進數值比較會靜默當 0，故失敗顯式賦 -1（CLAUDE.md 已知地雷）。
        b="$(LC_ALL=C wc -c < "${toplevel}/${f}" 2>/dev/null | tr -d ' ')" || b=-1
        [ -n "$b" ] || b=-1
        if [ "$b" -lt 0 ]; then
            parts="${parts}${parts:+ ＋ }${f} UNKNOWN"
        else
            parts="${parts}${parts:+ ＋ }${f} ${b} bytes"
        fi
        present=$(( present + 1 ))
    done

    # 全域那一份：只有「擁有 symlink target」的 repo 才印，故多 repo ship 不會重複印。
    # **不要改成無條件印**——全域檔是 repo-independent 的，check_repo 是 per-repo 迴圈。
    local global_src="${HOME}/.claude/CLAUDE.md" gpath="" gnote="" gb cdir main_ck
    if [ -e "$global_src" ]; then
        if [ -e "${toplevel}/claude/CLAUDE.md" ] && [ "${toplevel}/claude/CLAUDE.md" -ef "$global_src" ]; then
            gpath="${toplevel}/claude/CLAUDE.md"; gnote="生效中"
        else
            # linked worktree 裡 `-ef` 為假，而「在 worktree 改自家 CLAUDE.md」正是常態工作方式
            # ——訊號恰好在最需要它的場合消失。沿 common-dir 找主 checkout 補印，
            # **並驗證主 checkout 那份確實 `-ef` 全域檔**：只憑「有 common-dir」會把其他 repo
            # 的 linked worktree 也誤認成 dotfiles。
            cdir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || cdir=""
            if [ -n "$cdir" ]; then
                main_ck="$(dirname "$cdir")"
                if [ "$main_ck" != "$toplevel" ] && [ -e "${main_ck}/claude/CLAUDE.md" ] \
                   && [ "${main_ck}/claude/CLAUDE.md" -ef "$global_src" ] \
                   && [ -e "${toplevel}/claude/CLAUDE.md" ]; then
                    gpath="${toplevel}/claude/CLAUDE.md"; gnote="worktree 副本，生效的是主 checkout"
                fi
            fi
        fi
    fi

    if [ "$present" -eq 0 ] && [ -z "$gpath" ]; then
        echo "always-on: NONE"
        return 0
    fi
    echo "always-on: ${parts}（此 repo 的 always-on 面；純資訊，不必當次處置）"
    if [ -n "$gpath" ]; then
        gb="$(LC_ALL=C wc -c < "$gpath" 2>/dev/null | tr -d ' ')" || gb=-1
        [ -n "$gb" ] || gb=-1
        if [ "$gb" -lt 0 ]; then
            echo "           claude/CLAUDE.md UNKNOWN（全域，${gnote}）"
        else
            echo "           claude/CLAUDE.md ${gb} bytes（全域，${gnote}）"
        fi
    fi
}

# doc-governance:integration:start
detect_doc_governance() {
    local repo="$1" config="$1/.doc-governance.json" core="$1/scripts/doc-governance.py" runner=""
    if [ ! -e "$config" ] && [ ! -e "$core" ]; then
        return 3
    fi
    if [ ! -f "$config" ] || [ ! -f "$core" ]; then
        echo "doc-governance: BROKEN"
        echo "doc-flag: adoption incomplete"
        return 2
    fi
    if [ ! -f "$TRUSTED_DOC_CORE" ]; then
        echo "doc-governance: BROKEN"
        echo "doc-flag: trusted core unavailable: ${TRUSTED_DOC_CORE}（修復 ~/.dotfiles checkout 後重跑）"
        return 2
    fi
    if cmp -s "$core" "$TRUSTED_DOC_CORE"; then
        runner="$TRUSTED_DOC_CORE"
    else
        local target_common trusted_common
        target_common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || target_common=""
        trusted_common="$(git -C "$(dirname "$TRUSTED_DOC_CORE")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || trusted_common=""
        if [ -n "$target_common" ] && [ "$target_common" = "$trusted_common" ]; then
            echo "doc-note: self-hosted worktree core（與 trusted core 共用 git common-dir）"
            runner="$core"
        else
            echo "doc-governance: BROKEN"
            echo "doc-flag: trusted core mismatch（拒絕執行 target；以 ~/.dotfiles/scripts/doc-governance.py 重新同步 target）"
            return 2
        fi
    fi
    python3 "$runner" --root "$repo" audit --ship
}
# doc-governance:integration:end

# doc-governance:stop-output:start
print_doc_stop() {
    echo "verdict: STOP（doc-governance findings/broken；修復後再送，其餘偵測輸出保留）"
}
# doc-governance:stop-output:end

# review 痕跡的權威 subject 清單在 deep-review——那些 commit 是它產生的，清單跟著產生者走。
# 跨 skill source；缺席時降級印 UNKNOWN 而**不猜**：讓 model 憑印象比對 subject，漂一個字
# 就會把使用者自己的 `fix: 修正某某` 當成迭代痕跡建議壓掉，而使用者一句「好」就 force-push 了。
REVIEW_LIB="$(dirname "${BASH_SOURCE[0]}")/../../deep-review/scripts/lib/review-subjects.sh"
HAVE_REVIEW_LIB=0
if [ -f "$REVIEW_LIB" ]; then
    # shellcheck source=../../deep-review/scripts/lib/review-subjects.sh
    . "$REVIEW_LIB" && HAVE_REVIEW_LIB=1
fi

# Step 4 squash 選項的判定依據：branch 上有無 review 迭代痕跡、能不能安全壓、reset 目標是誰。
# 注意 `squash-cmd:` 這個 key 與 deep-review 的 review-anchor.sh 同名但**語意不同**：那邊從
# 審查 anchor 往上掃（review 收尾用），這邊從 merge-base 往上掃（ship 前整理用）。兩者不可互換
# ——ship 時 anchor 多半已被 clear，照抄那邊只會拿到 verdict: STOP。
# 三者都是 model 憑印象會漂的 git 事實，故一律由腳本解析、印成可照抄的指令。
detect_review_residue() {
    local repo="$1" remote="$2" default="$3" toplevel="$4"
    local base_ref mb n_all n_top n_buried top_hash h subj
    if [ "$HAVE_REVIEW_LIB" -ne 1 ]; then
        echo "review-residue: UNKNOWN（deep-review 的 lib/review-subjects.sh 不可用——勿憑印象比對 subject，不猜不壓，摘要標明無法判定）"
        return
    fi
    base_ref="${remote:+${remote}/}${default}"
    if ! mb="$(git -C "$repo" merge-base "$base_ref" HEAD 2>/dev/null)"; then
        # 無共同祖先等情況：靜默 return 會讓 Step 4 的判定表少一列可對，model 只能猜——
        # 走與 lib 缺席同一個 UNKNOWN 出口，處置一致。
        echo "review-residue: UNKNOWN（merge-base ${base_ref}..HEAD 解析失敗——勿憑印象比對 subject，不猜不壓，摘要標明無法判定）"
        return
    fi
    n_all="$(grep -cE "^(${REVIEW_SUBJECT_ALT})\$" <<< "$(git -C "$repo" log --format=%s "${mb}..HEAD" 2>/dev/null)")" || n_all=0
    if [ "${n_all:-0}" -eq 0 ]; then
        echo "review-residue: none（無 review 機械 commit，無事可壓）"
        return
    fi
    # 頂端連續段＝可安全 reset --soft 的範圍（不跨越語意 commit），與 deep-review 的 squash
    # 掃描同形狀；被語意 commit 隔在下層的壓不到，reset 只能整支來（後果不同，分開印）。
    n_top=0
    top_hash="$mb"
    while IFS=$'\t' read -r h subj; do
        [ -n "$h" ] || continue
        if ! grep -Eq "^(${REVIEW_SUBJECT_ALT})\$" <<< "$subj"; then top_hash="$h"; break; fi
        n_top=$((n_top + 1))
    done <<< "$(git -C "$repo" log --topo-order --format='%H%x09%s' "${mb}..HEAD")"
    n_buried=$(( n_all - n_top ))
    echo "review-residue: ${n_all} 顆（${base_ref}..HEAD 內 review 機械 commit；壓得掉的一律壓，不出題）"
    if [ "$n_top" -gt 0 ]; then
        echo "  top-contiguous: ${n_top} 顆（可安全壓，語意 commit 原樣保留）"
        echo "  squash-cmd: git -C $(shq "$toplevel") reset --soft ${top_hash}   # 此 hash = 使用者語意 commit 的邊界；記下來，Step 4 套用時直接用（本流程後續產生的 commit 會落在 reset 範圍內，**勿重跑重算**）"
    fi
    if [ "$n_buried" -gt 0 ]; then
        echo "  buried: ${n_buried} 顆（被非 review commit 隔開，reset --soft 壓不到——要單獨壓需 rebase -i，本 skill 不走互動式）"
        echo "  squash-all-cmd: git -C $(shq "$toplevel") reset --soft ${mb}   # 整支壓成一顆：**會連語意 commit 一起收**，選項文案須講明後果"
    fi
}

# review-terminal：上一場 deep-review 以「R5 仍有 blocking → 終止」收場，且那場涵蓋當前 HEAD。
#
# 為何 ship 端要讀 deep-review 的 anchor：Step 4 改成「說法關鍵字即授權、不再逐批停下確認」
# 之後，原本那道 gate 順帶接住的「這批還沒審完」就沒有別人接了。拆掉守衛就得補上它接住的
# 東西——這不是為沒見過的問題加規則，是為新造出的暴露補償。
#
# 鑑別力全靠 ancestry：anchor 存在 .git/ 下、跨 branch 共用，只憑「有沒有 terminal_reason」
# 會讓一場舊終止把之後每一批都擋住——天天響的訊號等於沒有訊號。terminal_head 必須是當前
# HEAD 的祖先，才代表那場終止涵蓋的正是現在要送的這批。
#
# 三種結局刻意不同：非祖先＝別批的事，靜默；terminal_head 已不存在（歷史重建 / gc）＝無從
# 鑑別，fail-safe 照報；祖先＝攔。誤攔的代價是一個指令，漏放的代價是未審完的 code 進 main。
detect_review_terminal() {
    local repo="$1"
    local gitdir anchor reason thead tat when note fmt
    gitdir="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    anchor="${gitdir}/deep-review/anchor"
    [ -f "$anchor" ] || return 0
    reason="$(sed -n 's/^terminal_reason=//p' "$anchor" | head -1)"
    [ -n "$reason" ] || return 0

    thead="$(sed -n 's/^terminal_head=//p' "$anchor" | head -1)"
    note=""
    if [ -z "$thead" ]; then
        note="（anchor 無 terminal_head，無從鑑別涵蓋範圍——fail-safe 照報）"
    elif ! git -C "$repo" cat-file -e "${thead}^{commit}" 2>/dev/null; then
        note="（terminal_head ${thead} 已不存在，歷史被重建或 gc——fail-safe 照報）"
    elif ! git -C "$repo" merge-base --is-ancestor "$thead" HEAD 2>/dev/null; then
        return 0
    fi

    # BSD 的 `date -r <epoch>` 與 GNU 的 `date -d @<epoch>` 語意不同且互不相容
    # （GNU 的 -r 是「參照檔案 mtime」），兩邊都試；都失敗就不印時間，不為此中斷
    when=""
    if [ -n "${tat:="$(sed -n 's/^terminal_at=//p' "$anchor" | head -1)"}" ]; then
        fmt='+%Y-%m-%d %H:%M'
        when="$(date -r "$tat" "$fmt" 2>/dev/null || date -d "@${tat}" "$fmt" 2>/dev/null)" || when=""
        [ -n "$when" ] && when="（終止於 ${when}）"
    fi

    echo "review-terminal: ${reason}${when}${note}"
    echo "  deep-review 在仍有未修的 blocking findings 時終止，本批未經完整審查。"
    echo "  A ship keyword authorizes HOW to ship, NEVER whether an unreviewed batch may ship. Do NOT let one override this."
    echo "  處置二選一（Step 4 停下問使用者）：重跑審查（通過並 squash 後 anchor 自動清除）／使用者明說照送（PR 須記一筆「未完整審查」）"
    echo "verdict: STOP（review-terminal——處置後再送；其餘偵測輸出照常，供摘要使用）"
}

# feature branch 對**自己的** remote tracking ref 是否分岔。
#
# 為何需要：本檔其餘訊號全在講「對 default 領先多少」，branch 與**它自己**的遠端版本分岔
# 這件事完全看不見——2026-08-07 跑 eval 時是受測 agent 自己去 `branch -vv` 才發現的。
# 分岔時 push 會被 non-fast-forward 拒；prose 端有防線（ship-paths.md squash 步驟 0 的
# fetch + `--is-ancestor`），但那是在流程後段，而使用者在 Step 1 就該知道。
#
# 只印訊號、不動 verdict：分岔本身不是錯（squash/rebase/amend 之後的常態），要的只是
# 「別在 push 那一刻才發現」。判定用本地 tracking ref、**不 fetch**（同本檔其餘偵測）——
# 代價是遠端剛前進時會漏報，但要抓的主要情境「本地重寫過歷史、遠端還是舊的」本地就看得見。
# 訊號因此明寫「本地快照」，處置一律要求先 fetch 再判。
detect_branch_diverged() {
    local repo="$1" remote="$2" default="$3" branch="$4"
    local upstream tracked counts behind ahead
    [ "$branch" = "$default" ] && return
    [ "$branch" = "DETACHED" ] && return
    # upstream 優先；沒設 upstream 就退用同名 <remote>/<branch>——「已 push 但沒 -u」是常態，
    # 只認 upstream 會讓那批 branch 完全不受檢（判準同 git-hygiene.sh）
    upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || upstream=""
    if [ -n "$upstream" ]; then
        tracked="$upstream"
    elif git -C "$repo" rev-parse --verify -q "refs/remotes/${remote}/${branch}" >/dev/null 2>&1; then
        tracked="${remote}/${branch}"
    else
        return                      # 從未 push 過 → 無從分岔
    fi
    git -C "$repo" merge-base --is-ancestor "$tracked" HEAD 2>/dev/null && return   # 純領先＝正常
    counts="$(git -C "$repo" rev-list --left-right --count "${tracked}...HEAD" 2>/dev/null)" || counts=""
    behind="$(awk '{print $1}' <<< "$counts")"; ahead="$(awk '{print $2}' <<< "$counts")"
    if git -C "$repo" merge-base --is-ancestor HEAD "$tracked" 2>/dev/null; then
        echo "branch-diverged: ${tracked} 領先本地 ${behind:-?} commit、本地零領先（本地快照——別台主機或另一個 session 推過？）"
        echo "  處置：先 \`git -C $(shq "$repo") fetch $(shq "$remote")\` 取新事實，再決定 pull/rebase；勿在落後狀態上直接 ship"
    else
        echo "branch-diverged: 與 ${tracked} 已分岔（本地快照：領先 ${ahead:-?}、落後 ${behind:-?}）——push 會被 non-fast-forward 拒"
        echo "  處置：先 \`git -C $(shq "$repo") fetch $(shq "$remote")\` 取新事實；確認遠端那幾顆確實已被本地重寫涵蓋，才用 --force-with-lease，勿裸 --force"
    fi
}

# 殘留 branch 衛生：已**完全併入** default 的 local / remote branch。
# 動機：merge 最後一哩只清它自己 merge 的那支——規則生效前的老 branch、或走別條路
# 合併的 branch 會無聲累積（實證：dotfiles 累到 2 支，是偶然跑 branch --list 才發現，
# 流程從未告知）。與 dossier 衛生同性質：只印訊號，處置見 `../references/log-workflow.md`「Step 4：Ship 摘要 → 確認（critical-op gate）」。
#
# 判定用本地 ref、不碰網路——代價是 remote-tracking 可能含**已在遠端刪除但本地未
# prune 的殘影**，故 cleanup-cmd 前置 `fetch --prune`（先對齊再刪，殘影會自己消失）。
# ⚠ 與 detect_squash_merged_branches 的處置**刻意不同**：那邊改成 ls-remote 直接核對，
# 因為它本來就要打 gh、網路成本已經付了；這裡是純本地路徑，為了殘影而引入網路會讓
# 「正常路徑一次網路都不碰」的原則失守。兩者的殘影風險相同，緩解手段依成本結構分流。
# 上述分流只約束**偵測**這一側。**刪除一側兩邊一致**：remote 都走 cleanup-stale-branch.sh
# （執行當下 ls-remote 重驗 + lease），那是使用者主動照抄時才付的網路成本，與「正常路徑
# 不碰網路」無關。local 側則維持照抄式 `branch -d`——git 自己就會拒絕未併入的 branch，
# 已有等價保護，換成腳本反而會把把關換成較弱的 `-D`＋SHA 比對。
# 排除當前 branch 與 default 本身；未併入 default 的 branch 是「還沒 ship 的工作」，
# 不在此列（誤報會誘導刪掉未送出的成果）。
detect_stale_branches() {
    local repo="$1" remote="$2" default="$3" branch="$4" toplevel="$5"
    local locals remotes_merged n_local n_remote cmd b name tip kept
    locals="$(git -C "$repo" branch --merged "$remote/$default" --format='%(refname:short)' 2>/dev/null \
        | grep -vxF "$default" | grep -vxF "$branch")" || locals=""
    # `branch -r` 會把 <remote>/HEAD 的 short form 印成**裸 remote 名**（如 "origin"）——
    # 那不是 branch，漏排除會污染清單並讓 cleanup-cmd 拼出 `--deleteorigin`（實地跑真 repo 才發現）
    # 排除當前 branch 的 **remote 對應**：2026-08-07 實地誤報——遠端有一條與當前 branch 同名、
    # 指向 default tip 的 branch（意外 push 造成）時，它符合「已併入 default」而被列為可刪，
    # 照抄 cleanup-cmd 就會把「本次正要送出的那條」從遠端砍掉。local 側早已排除，remote 側漏了。
    remotes_merged="$(git -C "$repo" branch -r --merged "$remote/$default" --format='%(refname:short)' 2>/dev/null \
        | grep -vxF "$remote/$default" | grep -vxF "$remote" | grep -vxF "$remote/$branch" | grep -v '/HEAD$')" || remotes_merged=""
    # 非 canonical remote 的 ref 在此**整批剔除**——它們是**另一個 repo 的內容**，訊號改由
    # detect_foreign_remote_branches 集中處理（只列出、不發刪除指令）。
    # 病灶（2026-08-16 實地）：漏了這道過濾時，候選來自 `branch -r`（列**所有** remote），
    # 但下面組 cleanup-cmd 只剝 canonical 前綴 → `fork/feat/x` 原樣被當成 branch 名傳給
    # cleanup-stale-branch.sh，而後者自己把 remote 解析成 canonical → 等於
    # `ls-remote origin fork/feat/x`，必然落空、永遠 verdict: STOP。單 remote 下「tracking
    # ref 路徑」與「canonical 上的 branch 名」恰好等價，故這條認知不一致潛伏至今。
    # 字面前綴比對而非 grep 正則：remote 名允許含 `.`（`my.fork`），`^my.fork/` 會誤配
    # `myXfork/…`——那種誤判是靜默的。
    kept=""
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        case "$b" in "${remote}/"*) kept="${kept}${b}"$'\n' ;; esac
    done <<< "$remotes_merged"
    remotes_merged="$(printf '%s' "$kept")"
    [ -z "$locals" ] && [ -z "$remotes_merged" ] && return
    n_local=$([ -n "$locals" ] && printf '%s\n' "$locals" | wc -l | tr -d ' ' || echo 0)
    n_remote=$([ -n "$remotes_merged" ] && printf '%s\n' "$remotes_merged" | wc -l | tr -d ' ' || echo 0)
    echo "stale-branches: $((n_local + n_remote))（已完全併入 ${default}，內容零損失可清；Step 4 摘要附註列出，NEVER delete on your own）"
    if [ -n "$locals" ]; then
        printf '%s\n' "$locals" | sed 's/^/  local: /'
    fi
    # remote 側**逐支**發 cleanup-stale-branch.sh，不再拼裸 `push --delete`。
    # 為何：偵測與刪除之間有 TOCTOU 窗口，而 remote 側沒有 local `-d` 那種「git 自己把關」的
    # 等價保護——裸 `push --delete` 對「偵測後有人推過」完全無感，砍下去遠端就沒有那些 commit
    # 了（本地也未必有副本）。腳本會在**執行當下** ls-remote 重驗 tip、再帶 `--force-with-lease`
    # 讓遠端自己做最後比對。這也順帶讓殘影從「對不存在的 branch 下刪除」的模糊失敗，變成一句
    # 明確的 STOP（遠端已無此 branch）。形狀與 detect_squash_merged_branches 一致。
    if [ -n "$remotes_merged" ]; then
        while IFS= read -r b; do
            echo "  remote: ${b}"
            name="${b#"${remote}"/}"
            # tip 取自本地 tracking ref：它只是**候選值**，正確性由腳本執行當下的 ls-remote
            # 重驗負責（殘影／過期快照都會在那裡被擋下），故此處不為它額外連網。
            tip="$(git -C "$repo" rev-parse --verify -q "refs/remotes/${b}" 2>/dev/null)" || tip=""
            if [ -n "$tip" ]; then
                echo "  cleanup-cmd: ~/.claude/skills/project/scripts/cleanup-stale-branch.sh $(shq "$toplevel") remote $(shq "$name") ${tip}"
            else
                # 取不到 tip 就給不出帶重驗的指令。**不退化成裸刪**——沒有 expected SHA 的刪除
                # 正是這段要消滅的東西，寧可要求人工確認。
                echo "  skipped-cmd: ${b} — 取不到 tracking ref 的 tip，無帶重驗的刪除指令可給（請手動確認後再刪）"
            fi
        done <<< "$remotes_merged"
    fi
    # `--` option terminator：ref 名可以長得像選項——`git branch -- '--all'` 前端會拒，但
    # `git update-ref refs/heads/--all` 建得起來且 `check-ref-format` 判合法。shell quoting
    # 擋不住這個（quote 完 git 仍把 `--all` 當選項），要靠 terminator。
    # 清掃指令：fetch --prune 先行（清掉已在遠端刪除的本地殘影，避免對不存在的 branch 下刪除）。
    # 逐項串接而非 sed 拼字串——前一版用 sed 補空白，遇裸 remote 名就拼出 `--deleteorigin`
    cmd="git -C $(shq "$toplevel") fetch --prune"
    if [ -n "$locals" ]; then
        cmd="${cmd} && git -C $(shq "$toplevel") branch -d --"
        while IFS= read -r b; do cmd="${cmd} $(shq "$b")"; done <<< "$locals"
    fi
    echo "cleanup-cmd: ${cmd}"
}

# squash-merge 盲視的補償訊號（只加訊號，刪除一律走 cleanup-stale-branch.sh）。
#
# 為何需要：上面那段判的是**祖先關係**，而 squash-merge 在 default 上產生一顆全新 commit、
# 與 branch 沒有祖先鏈——內容零損失卻永遠偵測不到。**本 repo 家規正是 squash-merge**，
# 等於那條訊號對主要情境無效（既有 fixture 用「branch 不加 commit」才會綠，是測試綠、
# 功能無效的形狀）。
#
# 判準只認一件事：merged PR 的 **headRefOid 等於本機該 branch 的 tip**。
# 不符即「同名 branch 事後又有新工作」——那些 commit 不在 default 上，列進清理清單就是
# 誘導使用者刪掉唯一的副本，故只印診斷、不列入。fork 來源的 PR 同理不採信（headRefName
# 相同不代表是這個 repo 的 branch）。
#
# 上限 200：`gh pr list` 預設只回 30，靜默截斷會讓「沒列出來」被讀成「沒有」。取 200 是
# 單次查詢仍快、又遠高於任何一輪 ship 的合理 PR 量；達上限一律標 partial，**絕不印 none**。
SQUASH_PR_LIMIT=200

detect_squash_merged_branches() {
    local repo="$1" remote="$2" default="$3" branch="$4" toplevel="$5"
    local locals_un remotes_un names slug prs n_rows scan b kept_un names_r
    local n name tip pr_num pr_oid pr_owner owner row hits listed skipped
    local rheads rheads_ok rc

    # 候選 = 祖先判定「未併入」者（已併入的由上一段處理，別重複列）
    locals_un="$(git -C "$repo" branch --no-merged "$remote/$default" --format='%(refname:short)' 2>/dev/null \
        | grep -vxF "$default" | grep -vxF "$branch")" || locals_un=""
    remotes_un="$(git -C "$repo" branch -r --no-merged "$remote/$default" --format='%(refname:short)' 2>/dev/null \
        | grep -vxF "$remote/$default" | grep -vxF "$remote" | grep -vxF "$remote/$branch" | grep -v '/HEAD$')" || remotes_un=""
    # 同 detect_stale_branches：非 canonical remote 的 ref 整批剔除（訊號歸
    # detect_foreign_remote_branches）。原寫法 `${remotes_un//${remote}\//}` 有兩個獨立缺陷：
    #   ① 它是**全域**替換而非剝前綴——branch 名裡再出現一次 `origin/` 也會被吃掉；
    #   ② 對 `fork/x` 完全無效，帶前綴的名字於是流進下游，拿去比對 merged PR 的
    #      headRefName 必然落空 → `[ -n "$row" ] || continue` **靜默略過**。
    # ②的實測（2026-08-16，PR owner 相同、headRefOid 與 tip 相符、條件全部齊備）是整段
    # 不印、連 skipped: 都沒有——**不是被下方的 owner 檢查擋住，是根本走不到那裡**。
    # 故此處同時修掉兩者：只留 canonical、逐條 `${b#<remote>/}` 剝前綴。
    kept_un=""; names_r=""
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        case "$b" in "${remote}/"*)
            kept_un="${kept_un}${b}"$'\n'
            names_r="${names_r}${b#"${remote}"/}"$'\n' ;;
        esac
    done <<< "$remotes_un"
    remotes_un="$(printf '%s' "$kept_un")"
    names="$(printf '%s\n%s\n' "$locals_un" "$names_r" | grep -v '^$' | sort -u)"
    [ -z "$names" ] && return

    # remote 行以**遠端事實**為準，不拿本地 tracking ref 當證據。
    # 理由：`gh pr merge --delete-branch` 之後遠端 branch 已不存在，但本機沒 prune 時
    # `refs/remotes/<remote>/<name>` 還在——只讀本地 ref 會把「本地沒 prune」報成
    # 「遠端有殘留」。危害不是誤刪（cleanup-stale-branch.sh 會 ls-remote 重驗並 STOP），
    # 而是**訊號混入虛報後，真有殘留時分不出哪支是真的**。
    # 判準因此與 cleanup-stale-branch.sh 對齊（該檔亦註明「不讀本地 remote-tracking ref
    # ——後者不 fetch 就是舊快照」）。單次呼叫、與 branch 數無關；本函式本來就要打 gh，
    # 不是新增網路依賴。GIT_TERMINAL_PROMPT=0：認證失敗直接失敗，不掛在互動提示上。
    # ⚠ ls-remote 的 exit code 必須單獨抓——接了 awk/sed 之後 `$?` 是 pipeline 最後一段的
    #   狀態，ls-remote 失敗會被吃掉、rheads_ok 誤判成 1，退化成「靜默把 remote 行丟掉」。
    rheads=""; rheads_ok=0
    if [ -n "$remotes_un" ]; then
        rheads="$(GIT_TERMINAL_PROMPT=0 git -C "$repo" ls-remote --heads "$remote" 2>/dev/null)"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            rheads_ok=1
            rheads="$(printf '%s\n' "$rheads" | awk '{print $2}' | sed 's|^refs/heads/||')"
        fi
    fi

    owner=""
    slug="$( (cd "$repo" && "$GH_BIN" repo view --json nameWithOwner -q .nameWithOwner) 2>/dev/null)" || slug=""
    if [ -n "$slug" ]; then owner="${slug%%/*}"; fi
    if [ -z "$slug" ]; then
        # 查不到 ≠ 沒有。宣稱 none 會讓使用者以為掃過了
        echo "squash-merged-branches: UNKNOWN（gh 不可用或 repo slug 解析失敗——無從比對 merged PR；未列出不代表沒有）"
        return
    fi
    prs="$("$GH_BIN" pr list -R "$slug" --state merged --limit "$SQUASH_PR_LIMIT" \
        --json number,headRefName,headRefOid,headRepositoryOwner \
        -q '.[] | [.number, .headRefName, .headRefOid, .headRepositoryOwner.login] | @tsv' 2>/dev/null)" || prs=""
    if [ -z "$prs" ]; then
        echo "squash-merged-branches: UNKNOWN（gh pr list 無輸出或失敗——無從比對；未列出不代表沒有）"
        return
    fi
    n_rows="$(grep -c . <<< "$prs")"
    if [ "$n_rows" -ge "$SQUASH_PR_LIMIT" ]; then
        scan="partial（結果數達上限 ${SQUASH_PR_LIMIT}，更舊的 merged PR 未掃到——未列出不代表沒有）"
    else
        scan="complete（掃過 ${n_rows} 筆 merged PR，未達上限 ${SQUASH_PR_LIMIT}）"
    fi

    listed=""; skipped=""; n=0
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        row="$(awk -F'\t' -v b="$name" '$2 == b {print; exit}' <<< "$prs")"
        [ -n "$row" ] || continue          # 沒有對應的 merged PR = 還沒 ship 的工作，靜默略過
        pr_num="$(cut -f1 <<< "$row")"; pr_oid="$(cut -f3 <<< "$row")"; pr_owner="$(cut -f4 <<< "$row")"
        if [ "$pr_owner" != "$owner" ]; then
            skipped="${skipped}  skipped: ${name} — PR #${pr_num} 來自 fork（${pr_owner}），不採信"$'\n'
            continue
        fi
        hits=""
        grep -qxF "$name" <<< "$locals_un" && hits="local"
        grep -qxF "${remote}/${name}" <<< "$remotes_un" && hits="${hits}${hits:+,}remote"
        tip="$(git -C "$repo" rev-parse --verify -q "$name" 2>/dev/null)" \
            || tip="$(git -C "$repo" rev-parse --verify -q "${remote}/${name}" 2>/dev/null)" || tip=""
        if [ "$pr_oid" != "$tip" ]; then
            skipped="${skipped}  skipped: ${name} — PR #${pr_num} 的 headRefOid 與本地 tip 不符（SHA mismatch：同名 branch 事後又有新工作？那些 commit 不在 ${default} 上）"$'\n'
            continue
        fi
        case "$hits" in
            *local*)  listed="${listed}  local: ${name}（PR #${pr_num}）"$'\n'
                      listed="${listed}  cleanup-cmd: ~/.claude/skills/project/scripts/cleanup-stale-branch.sh $(shq "$toplevel") local $(shq "$name") ${tip}"$'\n'
                      n=$((n + 1)) ;;
        esac
        case "$hits" in
            *remote*)
                if [ "$rheads_ok" -eq 1 ] && ! grep -qxF "$name" <<< "$rheads"; then
                    # 本地有 tracking ref、遠端沒有 → 未 prune 的殘影，不是遠端殘留。
                    # 仍要說出來（使用者才知道該 prune），但不給刪除指令、不計入 n。
                    skipped="${skipped}  skipped: ${name} — 遠端已無此 branch（本地 tracking 是未 prune 的殘影；\`git fetch --prune\` 可清）"$'\n'
                else
                    if [ "$rheads_ok" -eq 1 ]; then
                        listed="${listed}  remote: ${remote}/${name}（PR #${pr_num}）"$'\n'
                    else
                        # ls-remote 失敗：查不到 ≠ 沒有。保留該行但標明未經遠端核對，
                        # 與上方 gh 失敗時「不宣稱 none」同一判準。
                        listed="${listed}  remote: ${remote}/${name}（PR #${pr_num}；**未驗證**——ls-remote 失敗，此行來自本地 tracking 快照）"$'\n'
                    fi
                    listed="${listed}  cleanup-cmd: ~/.claude/skills/project/scripts/cleanup-stale-branch.sh $(shq "$toplevel") remote $(shq "$name") ${tip}"$'\n'
                    n=$((n + 1))
                fi ;;
        esac
    done <<< "$names"

    [ -z "$listed" ] && [ -z "$skipped" ] && return
    echo "squash-merged-branches: ${n}（PR 已 squash-merge：內容在 ${default} 上但無祖先鏈，\`branch --merged\` 看不到；Step 4 摘要附註列出，NEVER delete on your own）"
    [ -n "$listed" ] && printf '%s' "$listed"
    [ -n "$skipped" ] && printf '%s' "$skipped"
    echo "  scan: ${scan}"
}

# 非 canonical remote 上的 branch：只列訊號、**不發刪除指令**。
#
# 為何自成一段，而不是在上面兩段各留一條 foreign 分支：那些 ref 屬於**另一個 repo**，
# 「是否已併入我的 default」對它們不構成任何處置依據。實地（2026-08-16，pilot-api）：5 支
# 殘留全在同事的 fork 上、其中一支還是那個 repo 的 `main`，而 stale 段的措辭「已完全併入
# default，內容零損失可清」讀起來像本地垃圾。集中成一段也讓上面兩段各自回到單純的
# canonical-only 邏輯，訊號才不會分裂成「祖先路徑講得出、squash 路徑靜默漏報」。
#
# **刻意不給刪除指令**：刪 fork 上的 branch 是對外破壞性操作、動到的是別人的 repo，
# 而本 skill 的 remote 假設已明訂 fork 場景「不擅自對 fork 開 PR、不對唯讀 upstream push」
# ——一鍵刪除更在其外。這裡缺的從來不是「刪得掉的指令」，是「這是別人的東西」這個資訊。
# 純本地判定、不碰網路（與 detect_stale_branches 同一原則）。
detect_foreign_remote_branches() {
    local repo="$1" remote="$2"
    local all remotes_all b r rem foreign="" rems="" n
    all="$(git -C "$repo" branch -r --format='%(refname:short)' 2>/dev/null | grep -v '/HEAD$')" || all=""
    [ -n "$all" ] || return
    remotes_all="$(git -C "$repo" remote)" || return
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        # 歸屬用**最長前綴**比對 `git remote` 的實際清單，不用 `${b%%/*}`：remote 名本身
        # 可以含 `/`，切第一段會歸錯家。落不進任何 remote 的（如 <remote>/HEAD 的 short
        # form＝裸 remote 名）rem 為空，直接略過。
        rem=""
        while IFS= read -r r; do
            [ -n "$r" ] || continue
            case "$b" in "${r}/"*) [ "${#r}" -gt "${#rem}" ] && rem="$r" ;; esac
        done <<< "$remotes_all"
        [ -n "$rem" ] || continue
        [ "$rem" = "$remote" ] && continue
        foreign="${foreign}  branch: ${b}"$'\n'
        grep -qxF "$rem" <<< "$rems" || rems="${rems}${rem}"$'\n'
    done <<< "$all"
    [ -n "$foreign" ] || return
    n="$(grep -c . <<< "$foreign")"
    echo "foreign-remote-branches: ${n}（在非 canonical remote 上——**另一個 repo 的內容**，只列出、不發刪除指令）"
    printf '%s' "$foreign"
    while IFS= read -r rem; do
        [ -n "$rem" ] || continue
        echo "  note: 要停止追蹤「${rem}」（本地不再列出，對方 repo 完全不動）：git -C $(shq "$repo") remote remove $(shq "$rem")"
    done <<< "$rems"
    echo "  note: 真要刪除那些 branch 需明確意圖（會動到別人的 repo）——本流程不代勞，請自行對該 remote 執行"
}

check_repo() {
    local repo="$1"

    echo "=== $repo ==="

    local toplevel
    if ! toplevel="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"; then
        echo "error: 不是 git repo（或路徑不存在）"
        return 1
    fi

    # -- branch / remotes --
    local branch remote remotes_n
    branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || branch="DETACHED"
    echo "branch: $branch"

    # 落點在此、**不得往下移**：下面 remote／default 兩處都會 early return，
    # 移到那之後會讓「任何 repo 都量」與 `always-on: NONE` 兩條都不成立（tests 第 9 節有守門）。
    detect_always_on "$repo" "$toplevel"

    # doc-governance:check-init:start
    local doc_rc=0 doc_stop=0 doc_adopted=0
    detect_doc_governance "$toplevel" || doc_rc=$?
    if [ "$doc_rc" -ne 3 ]; then
        doc_adopted=1
        [ "$doc_rc" -eq 0 ] || doc_stop=1
    fi
    # doc-governance:check-init:end

    remote="$(detect_remote "$repo")"
    if [ -z "$remote" ]; then
        echo "remotes: NONE（local-only repo，無從 ship）"
        echo "verdict: STOP（無 remote，停下告知使用者）"
        # doc-governance:no-remote-stop:start
        [ "$doc_stop" -eq 0 ] || print_doc_stop
        # doc-governance:no-remote-stop:end
        return 0
    fi
    remotes_n="$(git -C "$repo" remote | wc -l | tr -d ' ')"
    if [ "$remotes_n" -gt 1 ]; then
        echo "remotes: $remotes_n 個（canonical=${remote}）— 可能是 fork 工作流，Step 4 需明列兩個 remote 由使用者確認"
        git -C "$repo" remote -v | grep '(push)' | sed 's/^/  /'
    else
        echo "remotes: $remote ($(git -C "$repo" remote get-url "$remote" 2>/dev/null))"
    fi

    # -- default branch --
    local default
    default="$(detect_default_branch "$repo" "$remote")"
    if [ -z "$default" ]; then
        echo "default: NONE（找不到 $remote/HEAD、$remote/main、$remote/master）"
        # doc-governance:no-default-stop:start
        if [ "$doc_stop" -eq 1 ]; then
            print_doc_stop
            return 0
        fi
        # doc-governance:no-default-stop:end
        # 全新空 repo？兩種 default: NONE 的處置相反，交由 detect_bootstrap 實測遠端分辨
        detect_bootstrap "$repo" "$remote" "$branch" "$toplevel"
        return 0
    fi
    echo "default: $default"

    # -- 變更集：三點 diff（branch 自身帶來的檔）+ 兩點 log（領先 commit）+ porcelain --
    local files n_files commits n_commits porcelain n_dirty
    files="$(git -C "$repo" diff --name-only "$remote/$default...HEAD" 2>/dev/null)" || files=""
    commits="$(git -C "$repo" log --oneline "$remote/$default..HEAD" 2>/dev/null)" || commits=""
    porcelain="$(git -C "$repo" status --porcelain)"

    if [ -n "$files" ]; then
        n_files="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
        echo "files-vs-default: $n_files 檔（三點，branch 自身帶來的）"
        printf '%s\n' "$files" | print_list "$n_files"
    else
        echo "files-vs-default: none"
    fi
    if [ -n "$commits" ]; then
        n_commits="$(printf '%s\n' "$commits" | wc -l | tr -d ' ')"
        echo "commits-ahead: ${n_commits}（兩點，領先 $remote/${default}）"
        printf '%s\n' "$commits" | print_list "$n_commits"
    else
        n_commits=0
        echo "commits-ahead: none"
    fi
    if [ -n "$porcelain" ]; then
        n_dirty="$(printf '%s\n' "$porcelain" | wc -l | tr -d ' ')"
        echo "working-tree: $n_dirty 檔（含 untracked）"
        printf '%s\n' "$porcelain" | print_list "$n_dirty"
    else
        n_dirty=0
        echo "working-tree: clean"
    fi

    # -- 誤 commit 偵測（Step 1 情況 B 的觸發條件）--
    if [ "$branch" = "$default" ] && [ "$n_commits" -gt 0 ]; then
        echo "misplaced: WARNING — $n_commits commit 已誤 commit 在本地 ${default}（情況 B——用下行指令救援，勿手打序列、勿 reset --hard）"
        # 印 toplevel 絕對路徑而非呼叫端引數——照抄行可能在另一個 cwd 執行，相對路徑會指錯 repo
        echo "branch-first-cmd: ~/.claude/skills/project/scripts/branch-first.sh $(shq "$toplevel") <type>/<slug>"
    fi

    # doc-governance:legacy-skip:start
    if [ "$doc_adopted" -eq 0 ]; then
        # legacy repo 才走舊 detector；adopted repo 的唯一文檔 verdict 是上面的 audit --ship。
        detect_dossier "$toplevel"
        detect_backlog "$toplevel"
    fi
    # doc-governance:legacy-skip:end

    # -- 殘留 branch 衛生（已併入 default 的 local/remote branch；無殘留則靜默）--
    detect_stale_branches "$repo" "$remote" "$default" "$branch" "$toplevel"
    detect_squash_merged_branches "$repo" "$remote" "$default" "$branch" "$toplevel"
    detect_foreign_remote_branches "$repo" "$remote"
    detect_review_residue "$repo" "$remote" "$default" "$toplevel"
    detect_review_terminal "$repo"

    # -- 與自己的 remote tracking ref 分岔（只比對 default 會漏；無分岔則靜默）--
    detect_branch_diverged "$repo" "$remote" "$default" "$branch"

    # -- 無變更 → docs-only gate（判定需要 session 記憶，交回 model）--
    # 不在此早退：docs-only mode 隨後會產生 docs commit 走 Step 4/5，
    # protection / ship-path / branch-first 的 verdict 仍須輸出（Step 1 不重跑偵測）
    if [ -z "$files" ] && [ "$n_commits" -eq 0 ] && [ "$n_dirty" -eq 0 ]; then
        echo "changes: NONE — do NOT exit yet: check session memory for already-shipped work (docs-only mode, Step 1 item 2)"
    fi

    # -- protection → ship path --
    local prot
    prot="$(detect_protection "$repo" "$remote" "$default")"
    echo "$prot"
    case "$prot" in
        # 無保護**仍預設 PR**（見 `../references/log-workflow.md`「Step 1：逐 repo 狀態 + 流程偵測（先於任何 commit）」）。
        # 直推 feature branch 是 escape hatch，需使用者明說不用 PR——故此處印 PR，
        # 不印 DIRECT-PUSH：verdict 是 model 照抄的東西，兩邊不一致等於留一個誘導錯誤的破口
        *OPEN*) echo "ship-path: PR（${default} 無保護，但預設仍開 PR；使用者明說「不用 PR」才退為直推 feature branch，絕不直推 ${default}）" ;;
        *)      echo "ship-path: PR（推 feature branch + 開 PR，不 merge）" ;;
    esac

    # -- branch-first --
    if [ "$branch" = "$default" ] || [ "$branch" = "DETACHED" ]; then
        echo "branch-first: REQUIRED（HEAD 在 $branch —— commit 之前先開 feature branch，無條件）"
    else
        echo "branch-first: 已在 feature branch（${branch}）"
    fi
    # doc-governance:final-stop:start
    if [ "$doc_stop" -eq 1 ]; then
        print_doc_stop
    fi
    # doc-governance:final-stop:end
}

for repo in "$@"; do
    check_repo "$repo" || overall=1
    echo ""
done

exit "$overall"
