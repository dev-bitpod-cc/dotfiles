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
# 單一來源在本腳本）/ protection verdict / ship-path / branch-first。default 定位
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

# dossier（STATUS.md）唯讀偵測：存在性、行數、進行中 ✅、規範外章節、過期。
# 只印訊號不下處置——收斂/歸檔/建立建議是 SKILL.md Step 2 的 model 決策。
detect_dossier() {
    local repo="$1" f="$1/STATUS.md"
    if [ ! -f "$f" ]; then
        echo "dossier: NONE（無 STATUS.md——repo 非 trivial 時列入 Step 4 附註建議建立）"
        return
    fi
    local lines
    lines="$(wc -l < "$f" | tr -d ' ')"
    echo "dossier: STATUS.md（${lines} 行）"
    # 標題掃描先剝 fenced code block（```/~~~ 圍欄內的範例標題不算章節）。
    # CommonMark 規則：closer 須與 opener 同字元且長度 ≥ opener——單純 toggle 會被
    # 四反引號外層包三反引號範例的巢狀圍欄誤判提前關欄（C3 審查實證）
    local unfenced
    unfenced="$(awk '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line ~ /^(```|~~~)/) {
                ch = substr(line, 1, 1)
                n = 1
                while (substr(line, n + 1, 1) == ch) n++
                if (!fence) { fence = 1; fch = ch; flen = n; next }
                if (ch == fch && n >= flen) { fence = 0 }
                next
            }
            if (!fence) print
        }' "$f")"
    # dossier 簽章（回流自 clean-room 盲寫版）：雙訊號——「進行中」章節 + 任一 dossier
    # 專屬章節（STATUS.md 命名互斥規則見 references/dossier.md）。flag 缺席即被當
    # dossier 編輯，誤放行比誤攔截危險（攔截只是停下告知），故：
    # - 章節名須為**標題結尾**（允許裝飾前綴「## ⏳ 進行中」與括號後綴「已完成(里程碑)」），
    #   子字串比對會把「## 進行中的部署」＋「## 已完成的部署」這類領域看板誤認成 dossier
    if ! printf '%s\n' "$unfenced" | grep -qE '^##[[:space:]].*進行中[[:space:]]*$' \
        || ! printf '%s\n' "$unfenced" | grep -qE '^##[[:space:]].*(決策|死路|技術債|里程碑|已完成|已知缺口|移交準備度?)[[:space:]]*([（(][^（()）]*[）)])?[[:space:]]*$'; then
        echo "dossier-flag: 簽章不符（缺「進行中」或 dossier 專屬章節——撞名領域產物？勿當 dossier 改；spec 模式遇之停下告知）"
    fi
    if [ "$lines" -gt "$DOSSIER_MAX_LINES" ]; then
        echo "dossier-flag: 全檔 ${lines} 行 > ${DOSSIER_MAX_LINES}（硬訊號——當次收斂：蒸餾＋歸檔 docs/archive/）"
    fi
    # 「進行中」節內的 ✅ = 完成項未移走；其他節（里程碑）的 ✅ 合法，不得誤報
    if awk '/^##[[:space:]]/{ in_sec = ($0 ~ /進行中/) } in_sec && /✅/ { found=1 } END { exit !found }' "$f"; then
        echo "dossier-flag: 「進行中」含 ✅ 完成項（Step 2 當場移入里程碑）"
    fi
    if printf '%s\n' "$unfenced" | grep -qE '^#{1,6}[[:space:]].*Session Log'; then
        echo "dossier-flag: 規範外章節（Session Log）——git history 才是 log，蒸餾後歸檔"
    fi
    # 過期：STATUS.md 最後 commit 落後 repo 最新活動的天數（%ct = committer time）
    local st_ct head_ct lag
    st_ct="$(git -C "$repo" log -1 --format=%ct -- STATUS.md 2>/dev/null)" || st_ct=""
    head_ct="$(git -C "$repo" log -1 --format=%ct 2>/dev/null)" || head_ct=""
    if [ -n "$st_ct" ] && [ -n "$head_ct" ]; then
        lag=$(( (head_ct - st_ct) / 86400 ))
        if [ "$lag" -gt "$DOSSIER_STALE_DAYS" ]; then
            echo "dossier-flag: 最後 commit 落後 repo 活動 ${lag} 天 > ${DOSSIER_STALE_DAYS}（過期——列入 Step 4 附註提醒、本次重點補齊）"
        fi
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
    echo "stale-branches: $((n_local + n_remote))（已完全併入 ${default}，內容零損失可清；Step 4 附註建議，經同意才刪）"
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
