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
#   resolve: UNKNOWN（...）     非 git repo 路徑 → 交回 session 記憶 basename 比對
# 注意：第一引數 `resolve` 為子指令保留字——repo 目錄字面名為 resolve 時以路徑形式
# （./resolve）傳入偵測模式即可。
#
# exit code：0 = 偵測完成（有無變更、resolve 任一 verdict 都算成功）；
#            1 = 有 repo 無效；2 = 用法錯誤
#
# 設計原則：
# - 唯讀。不 commit、不 switch——mutation 一律留給 skill 流程（branch-first
#   搬移、提交、push 都在 Step 1/3/5 由 model 依 Critical gate 執行）。不 fetch，唯一
#   碰網路的例外是 default 定位不到時的 bootstrap 判定（ls-remote，理由見 detect_bootstrap）。
# - protection 判定封裝於此（classic + ruleset，邏輯解說見 references/ship-paths.md，
#   本腳本為可執行權威）。Unknown = protected 直接印在輸出裡，不留給 model 重新詮釋。
#
# SHIP_STATE_GH 僅供測試 stub gh（tests/run.sh）；正常使用不需設定。

set -uo pipefail

MAX_LIST=20  # 每類清單最多列出的行數；只影響顯示，計數仍為完整值
GH_BIN="${SHIP_STATE_GH:-gh}"

# dossier 衛生門檻（單一來源——SKILL.md Step 2 與 references/dossier.md 引用本處，
# 不另寫數字，改門檻只改這裡）
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
        echo "resolve: UNKNOWN（${token} 非 git repo 路徑——交回 session 記憶 basename 比對，不命中則當 module）"
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
        echo "resolve: UNKNOWN（${token} 無法進入（cd 失敗）——交回 session 記憶 basename 比對，不命中則當 module）"
    elif [ "$real" = "$top" ]; then
        echo "resolve: REPO ${top}"
    else
        echo "resolve: MODULE（${token} 在 repo ${top} 內但非根——當 module 過濾，不鎖定 repo）"
    fi
    exit 0
fi

overall=0

# 印一段清單（stdin），縮排並截斷到 MAX_LIST
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
    echo "bootstrap-cmd: git -C '${toplevel}' push -u ${remote} ${branch}"
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

# dossier（STATUS.md）唯讀偵測：存在性、尺寸訊號、進行中 ✅、規範外章節、過期。
# **量測與逐 flag 處置皆在此**（單一來源；SKILL.md Step 2 只說「照 flag 訊息做」、不複述——
# 兩邊各寫一份必然漂移，實證：SKILL 曾把「改正常換行段落」列為處置，腳本卻明說換行不夠）。
# 留給 model 的判斷層：蒸餾什麼內容、傘狀雙重記載比對、使用者說「別動它」時怎麼處置。
detect_dossier() {
    local repo="$1" f="$1/STATUS.md"
    if [ ! -f "$f" ]; then
        echo "dossier: NONE（無 STATUS.md——repo 非 trivial 時列入 Step 4 確認選項建議建立）"
        return
    fi
    # 三個尺寸量測皆為確定性訊號（prose 下沉為腳本——蒸餾判斷歸 model、量測歸腳本）：
    # 行數（換行風格 repo 最易讀的代理）、bytes（風格不敏感後盾）、最長行（巨型單行早期糾正）。
    local lines bytes maxlen
    lines="$(wc -l < "$f" | tr -d ' ')"
    bytes="$(wc -c < "$f" | tr -d ' ')"
    maxlen="$(LC_ALL=C awk '{ if (length > m) m = length } END { print m + 0 }' "$f")"
    echo "dossier: STATUS.md（${lines} 行 / ${bytes} bytes / 最長行 ${maxlen} bytes）"
    # 標題掃描先剝 fenced code block（```/~~~ 圍欄內的範例標題不算章節）。
    # CommonMark 規則：closer 須與 opener 同字元且長度 ≥ opener——單純 toggle 會被
    # 四反引號外層包三反引號範例的巢狀圍欄誤判提前關欄（C3 審查實證）
    #
    # 剝除方式是**前綴 \001 哨兵**，不是丟棄、也不是清空——兩個下游同時有要求：
    # - 行號要對齊原檔：條目 flag 得報「超標的是第幾行」，丟棄會讓後續 NR 全數位移。
    # - 長度要保留真實值：清空會讓 fence 重的章節在 dossier-sections 佔比中被低估，
    #   嚴重時排名倒轉（實測 26KB 的決策節報成 403 bytes、沉到 4.5KB 的節後面）。
    #   那正是該功能要防的「挑錯收斂對象」，清空等於讓它主動誤導。
    # 哨兵前綴打掉三個 pattern 家族（^##[[:space:]] 章節/簽章、^#{1,6} Session Log、
    # ^-[[:space:]] 條目起始），圍欄內的假標題/假條目照樣不被誤認。讀 unfenced 的 code site
    # 共五處：簽章 grep、分節 awk、條目 awk、✅ awk、Session Log grep。
    # **新增消費者時記得也吃 unfenced**——漏一個就是誤報（✅ 偵測就漏過一次）。
    # 例外：上面三個全檔量測（行數/bytes/最長行）刻意讀原檔——它們量的是檔案本身的體積，
    # fence 內容同樣佔預算。副作用：fence 裡的長行（長指令/base64/URL）會觸發最長行 flag，
    # 該處置提示對 code block 無意義，人工判斷即可。
    # 代價：fenced 內容計入條目與分節 bytes——那是對的，那些 bytes 真的佔 dossier 預算。
    local unfenced
    unfenced="$(awk '
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
        }' "$f")"
    # dossier 簽章（回流自 clean-room 盲寫版）：雙訊號——「進行中」章節 + 任一 dossier
    # 專屬章節（STATUS.md 命名互斥規則見 references/dossier.md）。flag 缺席即被當
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
    fi
    # 收斂建議目標：不是「壓到剛好低於門檻」（見 DOSSIER_TARGET_PCT 註解）
    local target_lines target_bytes oversize=0
    target_lines=$(( DOSSIER_MAX_LINES * DOSSIER_TARGET_PCT / 100 ))
    target_bytes=$(( DOSSIER_MAX_BYTES * DOSSIER_TARGET_PCT / 100 ))
    if [ "$lines" -gt "$DOSSIER_MAX_LINES" ]; then
        oversize=1
        echo "dossier-flag: 全檔 ${lines} 行 > ${DOSSIER_MAX_LINES}（硬訊號——當次收斂：蒸餾＋歸檔 docs/archive/；建議收斂至 ≤ ${target_lines} 行，留得下數次 ship 的成長）"
    fi
    if [ "$bytes" -gt "$DOSSIER_MAX_BYTES" ]; then
        oversize=1
        echo "dossier-flag: 全檔 ${bytes} bytes > ${DOSSIER_MAX_BYTES}（行數代理失真——硬訊號同全檔過長：當次收斂，蒸餾＋改正常換行段落；建議收斂至 ≤ ${target_bytes} bytes）"
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
            /^##[[:space:]]/ { emit(); sec = $0; sub(/^##[[:space:]]+/, "", sec); b = 0; next }
            { l = $0; sub(/^\001/, "", l); b += length(l) + 1 }
            END { emit() }' <<< "$unfenced" | LC_ALL=C sort -rn | head -n "$DOSSIER_SECTIONS_TOP_N" | LC_ALL=C awk -v total="$bytes" -F'\t' '
            { printf "%s%s %d (%d%%)", (NR > 1 ? " / " : ""), $2, $1, ($1 * 100 / total) }
            END { printf "\n" }')"
        [ -n "$sections" ] && echo "dossier-sections: ${sections}（前 ${DOSSIER_SECTIONS_TOP_N} 大；先量再決定動哪節）"
    fi
    if [ "$maxlen" -gt "$DOSSIER_MAX_LINE_BYTES" ]; then
        echo "dossier-flag: 最長行 ${maxlen} bytes > ${DOSSIER_MAX_LINE_BYTES}（巨型單行——rewrap 後仍超標者需蒸餾，不是只換行）"
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
        /^##[[:space:]]/ { flush(); insec = ($0 ~ /決策|里程碑|已完成/); next }
        insec && /^-[[:space:]]/ { flush(); cur = length($0); curline = NR; next }
        insec && cur { l = $0; sub(/^\001/, "", l); cur += length(l) + 1 }
        END { flush(); printf "%d\t%d\n", max + 0, maxline + 0 }' <<< "$unfenced")"
    max_entry="${entry_out%%	*}"
    max_entry_line="${entry_out##*	}"
    if [ "$max_entry" -gt "$DOSSIER_ENTRY_MAX_BYTES" ]; then
        echo "dossier-flag: 決策/里程碑節最大條目 ${max_entry} bytes > ${DOSSIER_ENTRY_MAX_BYTES}（在第 ${max_entry_line} 行；蒸餾上限——決策留結論、里程碑一行化，推導史沉 git history。**若該條涵蓋多個決策 → 拆成多條，不是壓字**）"
    fi
    # 「進行中」節內的 ✅ = 完成項未移走；其他節（里程碑）的 ✅ 合法，不得誤報。
    # ⚠ `/✅/` **沒有行首錨點**，哨兵中和不了它——必須自行 `/^\001/ { next }` 跳過圍欄行。
    # 少了那條會出現兩個方向的誤報：①圍欄內貼的測試輸出（滿是 ✅）被當成未移走的完成項
    # ②哨兵讓圍欄內的假標題不再切節，in_sec 一路開著，圍欄內的 ✅ 全算進「進行中」
    # （②是加哨兵後才出現的回歸——改動前假標題會把 in_sec 關掉，反而歪打正著）
    if awk '/^\001/ { next } /^##[[:space:]]/{ in_sec = ($0 ~ /進行中/) } in_sec && /✅/ { found=1 } END { exit !found }' <<< "$unfenced"; then
        echo "dossier-flag: 「進行中」含 ✅ 完成項（Step 2 當場移入里程碑）"
    fi
    # herestring 同上：避免大輸入下 grep -q 早退觸發 SIGPIPE + pipefail 的偽陰性
    if grep -qE '^#{1,6}[[:space:]].*Session Log' <<< "$unfenced"; then
        echo "dossier-flag: 規範外章節（Session Log）——git history 才是 log，蒸餾後歸檔"
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
}
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
# 三者都是 model 憑印象會漂的 git 事實，故一律由腳本解析、印成可照抄的指令。
detect_review_residue() {
    local repo="$1" remote="$2" default="$3" toplevel="$4"
    local base_ref mb n_all n_top n_buried top_hash h subj
    if [ "$HAVE_REVIEW_LIB" -ne 1 ]; then
        echo "review-residue: UNKNOWN（deep-review 的 lib/review-subjects.sh 不可用——勿憑印象比對 subject，改在 Step 4 詢問使用者）"
        return
    fi
    base_ref="${remote:+${remote}/}${default}"
    if ! mb="$(git -C "$repo" merge-base "$base_ref" HEAD 2>/dev/null)"; then
        # 無共同祖先等情況：靜默 return 會讓 Step 4 的判定表少一列可對，model 只能猜——
        # 走與 lib 缺席同一個 UNKNOWN 出口，處置一致。
        echo "review-residue: UNKNOWN（merge-base ${base_ref}..HEAD 解析失敗——勿憑印象比對 subject，改在 Step 4 詢問使用者）"
        return
    fi
    n_all="$(grep -cE "^(${REVIEW_SUBJECT_ALT})\$" <<< "$(git -C "$repo" log --format=%s "${mb}..HEAD" 2>/dev/null)")" || n_all=0
    if [ "${n_all:-0}" -eq 0 ]; then
        echo "review-residue: none（無 review 機械 commit，Step 4 不出 squash 題）"
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
    echo "review-residue: ${n_all} 顆（${base_ref}..HEAD 內 review 機械 commit；Step 4 squash 選項依此出題）"
    if [ "$n_top" -gt 0 ]; then
        echo "  top-contiguous: ${n_top} 顆（可安全壓，語意 commit 原樣保留）"
        echo "  squash-cmd: git -C '${toplevel}' reset --soft ${top_hash}   # 此 hash = 使用者語意 commit 的邊界；記下來，Step 4 套用時直接用（本流程後續產生的 commit 會落在 reset 範圍內，**勿重跑重算**）"
    fi
    if [ "$n_buried" -gt 0 ]; then
        echo "  buried: ${n_buried} 顆（被非 review commit 隔開，reset --soft 壓不到——要單獨壓需 rebase -i，本 skill 不走互動式）"
        echo "  squash-all-cmd: git -C '${toplevel}' reset --soft ${mb}   # 整支壓成一顆：**會連語意 commit 一起收**，選項文案須講明後果"
    fi
}


# 殘留 branch 衛生：已**完全併入** default 的 local / remote branch。
# 動機：merge 最後一哩只清它自己 merge 的那支——規則生效前的老 branch、或走別條路
# 合併的 branch 會無聲累積（實證：dotfiles 累到 2 支，是偶然跑 branch --list 才發現，
# 流程從未告知）。與 dossier 衛生同性質：只印訊號，處置留給 SKILL Step 4 由使用者定奪。
#
# 判定用本地 ref、不碰網路——代價是 remote-tracking 可能含**已在遠端刪除但本地未
# prune 的殘影**，故 cleanup-cmd 前置 `fetch --prune`（先對齊再刪，殘影會自己消失）。
# 排除當前 branch 與 default 本身；未併入 default 的 branch 是「還沒 ship 的工作」，
# 不在此列（誤報會誘導刪掉未送出的成果）。
detect_stale_branches() {
    local repo="$1" remote="$2" default="$3" branch="$4" toplevel="$5"
    local locals remotes_merged n_local n_remote cmd b
    locals="$(git -C "$repo" branch --merged "$remote/$default" --format='%(refname:short)' 2>/dev/null \
        | grep -vxF "$default" | grep -vxF "$branch")" || locals=""
    # `branch -r` 會把 <remote>/HEAD 的 short form 印成**裸 remote 名**（如 "origin"）——
    # 那不是 branch，漏排除會污染清單並讓 cleanup-cmd 拼出 `--deleteorigin`（實地跑真 repo 才發現）
    remotes_merged="$(git -C "$repo" branch -r --merged "$remote/$default" --format='%(refname:short)' 2>/dev/null \
        | grep -vxF "$remote/$default" | grep -vxF "$remote" | grep -v '/HEAD$')" || remotes_merged=""
    [ -z "$locals" ] && [ -z "$remotes_merged" ] && return
    n_local=$([ -n "$locals" ] && printf '%s\n' "$locals" | wc -l | tr -d ' ' || echo 0)
    n_remote=$([ -n "$remotes_merged" ] && printf '%s\n' "$remotes_merged" | wc -l | tr -d ' ' || echo 0)
    echo "stale-branches: $((n_local + n_remote))（已完全併入 ${default}，內容零損失可清；Step 4 確認選項建議，經同意才刪）"
    if [ -n "$locals" ]; then
        printf '%s\n' "$locals" | sed 's/^/  local: /'
    fi
    if [ -n "$remotes_merged" ]; then
        printf '%s\n' "$remotes_merged" | sed 's/^/  remote: /'
    fi
    # 清掃指令：fetch --prune 先行（清掉已在遠端刪除的本地殘影，避免對不存在的 branch 下刪除）。
    # 逐項串接而非 sed 拼字串——前一版用 sed 補空白，遇裸 remote 名就拼出 `--deleteorigin`
    cmd="git -C '${toplevel}' fetch --prune"
    if [ -n "$locals" ]; then
        cmd="${cmd} && git -C '${toplevel}' branch -d"
        while IFS= read -r b; do cmd="${cmd} ${b}"; done <<< "$locals"
    fi
    if [ -n "$remotes_merged" ]; then
        cmd="${cmd} && git -C '${toplevel}' push ${remote} --delete"
        while IFS= read -r b; do cmd="${cmd} ${b#"${remote}"/}"; done <<< "$remotes_merged"
    fi
    echo "cleanup-cmd: ${cmd}"
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

    remote="$(detect_remote "$repo")"
    if [ -z "$remote" ]; then
        echo "remotes: NONE（local-only repo，無從 ship）"
        echo "verdict: STOP（無 remote，停下告知使用者）"
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
        echo "branch-first-cmd: ~/.claude/skills/project/scripts/branch-first.sh '$toplevel' <type>/<slug>"
    fi

    # -- dossier 偵測（Step 2 衛生檢查；門檻見檔頭常數，單一來源）--
    detect_dossier "$repo"

    # -- 殘留 branch 衛生（已併入 default 的 local/remote branch；無殘留則靜默）--
    detect_stale_branches "$repo" "$remote" "$default" "$branch" "$toplevel"
    detect_review_residue "$repo" "$remote" "$default" "$toplevel"

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
        # 無保護**仍預設 PR**（SKILL Step 1 第 4 項：跨 repo 單一形狀＋審查紀錄）。
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
}

for repo in "$@"; do
    check_repo "$repo" || overall=1
    echo ""
done

exit "$overall"
