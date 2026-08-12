#!/usr/bin/env bash
#
# handoff-anchor.sh — handoff skill 的交接檔生命週期機制（錨點產生 / 驗證 / 列表清理）
#
# 用法：
#   handoff-anchor.sh anchors <repo-path>...   # 產生 frontmatter 錨點行（created + 逐 repo anchor）
#                                              # 路徑可為相對或 repo 子目錄，錨點一律記 toplevel 絕對路徑
#                                              # **全有或全無**：任一 repo 前提不成立 → stdout 全空 + exit 1
#   handoff-anchor.sh verify  <handoff.md>     # 驗證交接檔錨點 vs 各 repo 現況
#   handoff-anchor.sh consume <handoff.md>     # 消費歸檔：mv 到同層 archive/ 加秒級時戳前綴，
#                                              # 印 archived: <路徑>；已消費（父目錄為
#                                              # archive 或檔名已帶時戳前綴）→ 拒絕
#   handoff-anchor.sh survey [--slug <slug>] [dir]
#                                              # W1／R1 的單一入口：archive 過期清理（**先做**）
#                                              # → active 清單 → 既有工作線（依 slug 聚合）
#                                              # → 給了 --slug 才印 predecessor 判定。一律 exit 0
#   handoff-anchor.sh list    [dir]            # 底層原語：active 清單 + 清過期 archive
#   handoff-anchor.sh find-predecessor <slug> [dir]
#                                              # 底層原語：依 slug 精確定位前一份（active 優先，
#                                              # 其次 archive 最新一輪）；無命中印 NONE（＝首輪）
#   （SKILL.md 一律走 survey；兩個原語留給除錯與既有守門測試）
#
# verify 逐錨點輸出判定：
#   FRESH      — 記錄的 HEAD == 現在的 HEAD（內容可信）
#   DRIFTED    — 記錄的 HEAD 是現在 HEAD 的祖先（repo 已前進 N commits；列出中間 commit 供比對）
#   DIVERGED   — 記錄的 HEAD 不在現行歷史上（rebase/換 branch/歷史改寫）；內容一律存疑
#   MISSING    — repo 路徑不存在或不是 git repo
#   BAD-ANCHOR — 錨點行欄位不足（如手寫殘缺），或 head 欄位不是完整 canonical object ID
#                （`HEAD`／branch 名／短 sha 都會隨時間改指，無從判斷過時與否）
#   另檢查 created 年齡，超過 EXPIRE_DAYS 標 EXPIRED。
#
# exit code：0 = 全部 FRESH 且未過期（consume：歸檔完成）；
#            1 = 任一 DRIFTED/DIVERGED/MISSING/BAD-ANCHOR/EXPIRED（consume：拒絕或失敗——
#                檔案不存在／已在 archive 內（重複消費）／目錄解析失敗／目標同秒碰撞／
#                mv 失敗；拒絕與失敗路徑檔案一律原地不動，consume-once 由此機械保證。
#                exit 1 ≠ 已歸檔：讀 stderr 分辨，mv 失敗時交接檔仍在 active）；
#            2 = 用法錯誤
#
# 限制：repo 路徑（解析後的 toplevel）不可含空白（anchor 行以空白分欄）——anchors 直接報錯拒絕。
# list 的 dir 預設 $HANDOFF_DIR，未設則 ~/.claude/handoffs。

set -uo pipefail

EXPIRE_DAYS=7        # active 交接檔超過即標 EXPIRED——內容與現實脫節的風險隨時間上升
ARCHIVE_KEEP_DAYS=30 # 已消費（archive/）的交接檔保留天數，過期由 list 自動清（保險絲期）
MAX_LOG=20           # DRIFTED 時最多列出的中間 commit 數；只影響顯示

usage() {
    echo "用法：$0 anchors <repo>... | verify <handoff.md> | consume <handoff.md>" >&2
    echo "      $0 survey [--slug <slug>] [dir]        # W1／R1 單一入口" >&2
    echo "      $0 list [dir] | find-predecessor <slug> [dir]   # 底層原語（SKILL.md 一律走 survey）" >&2
    exit 2
}

# 解析 YYYY-MM-DD → epoch（macOS 的 date -j 與 GNU date -d 皆支援）
date_to_epoch() {
    date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

age_days_from_created() {  # <YYYY-MM-DD> → 天數；解析失敗輸出空字串
    local epoch
    epoch="$(date_to_epoch "$1")" || return 1
    [ -n "$epoch" ] || return 1
    echo $(( ($(date +%s) - epoch) / 86400 ))
}

# anchors：**全有或全無**。任一 repo 的前提不成立就一行都不印——半成品輸出看起來與成功
# 輸出一模一樣（錯誤只在 stderr），agent 照樣會貼進 frontmatter，而少一條錨點時 cmd_verify
# 什麼都不說（它只在**完全無錨點**時才判 UNVERIFIABLE），該 repo 的交接內容從此沒有 checksum。
# 逐 repo 四項前提：toplevel 可解析 / 路徑無空白 / HEAD 是真的 commit / status 可讀。
cmd_anchors() {
    [ $# -ge 1 ] || usage
    local failed=0 lines=""
    for repo in "$@"; do
        # 記錄路徑一律用 toplevel 絕對路徑：輸入可能是相對路徑（`.`）或 repo 子目錄，原樣寫進
        # 錨點後，日後在 cwd 已不同的新 session verify 會對到**別的 repo**——而失敗訊息會是
        # 誤導性的 DIVERGED「歷史改寫」（真相是路徑錯），其處置又是整份交接檔降級為線索，
        # 錨點機制等於白費。順帶把子目錄輸入對齊 repo root。
        local top
        top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"
        if [ -z "$top" ]; then
            echo "error: 不是 git repo（或路徑不存在）：${repo}" >&2
            failed=1
            continue
        fi
        # 空白檢查對解析後的 top 而非原輸入：相對路徑輸入本身可以無空白、toplevel 卻含空白
        case "$top" in *[[:space:]]*)
            echo "error: repo 路徑含空白，錨點格式不支援（anchor 行以空白分欄）：${top}" >&2
            failed=1
            continue ;;
        esac
        local branch sha dirty porcelain
        branch="$(git -C "$top" symbolic-ref --short -q HEAD)" || branch="DETACHED"
        # full sha：short sha 日後可能因物件增長變 ambiguous，導致 verify 誤判 DIVERGED。
        # `--verify HEAD^{commit}` 的 exit code 必須看——unborn HEAD（repo 剛 init、還沒
        # 第一顆 commit）下 `rev-parse HEAD` 會把**字面字串 `HEAD`** 印到 stdout，寫進錨點
        # 後 verify 每次都拿 `HEAD^{commit}` 重新解析、永遠等於當下 HEAD → **永久判 FRESH**。
        # 那比沒有錨點更糟：無錨點至少會判 UNVERIFIABLE、整份降級為線索。
        if ! sha="$(git -C "$top" rev-parse --verify --quiet "HEAD^{commit}")" || [ -z "$sha" ]; then
            echo "error: repo 尚無 commit（unborn HEAD），無法蓋錨點——先 commit 再交接：${top}" >&2
            failed=1
            continue
        fi
        # status 失敗時 dirty 會靜默記成 0，讓「未 commit 內容不受錨點保護」的提醒消失
        if ! porcelain="$(git -C "$top" status --porcelain)"; then
            echo "error: 無法讀取 working tree 狀態（status 失敗）：${top}" >&2
            failed=1
            continue
        fi
        dirty="$(printf '%s' "$porcelain" | grep -c '^' | tr -d ' ')"
        lines="${lines}anchor: $top $branch $sha dirty=${dirty}"$'\n'
    done
    if [ "$failed" -ne 0 ]; then
        echo "error: 有 repo 的前提不成立——**不輸出任何錨點行**（部分錨點會讓該 repo 的交接內容永遠無法驗證）。修正後重跑。" >&2
        return 1
    fi
    echo "created: $(date +%Y-%m-%d)"
    printf '%s' "$lines"
    return 0
}

verify_anchor() {  # <path> <branch> <sha> <dirty=n> → 輸出判定；FRESH 回 0，其餘回 1
    local repo="$1" branch="$2" sha="$3"
    echo "--- $repo ---"
    echo "recorded: branch=$branch head=$sha ${4:-dirty=?}"

    if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "status: MISSING（路徑不存在或不是 git repo）"
        return 1
    fi

    local cur_branch cur_sha cur_dirty
    cur_branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" || cur_branch="DETACHED"
    cur_sha="$(git -C "$repo" rev-parse --short HEAD)"
    cur_dirty="$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')"
    echo "current:  branch=$cur_branch head=$cur_sha dirty=$cur_dirty"

    # 錨點的 sha 欄位必須是**完整 canonical object ID**，不能是任何 ref-ish 字串。
    # 只修寫入端擋不住既存的壞錨點：`HEAD` 每次都解析成當下 HEAD → 永遠 FRESH；branch 名
    # 同理；短 sha 則會隨物件增長變 ambiguous（本檔 cmd_anchors 早就為此只記 full sha）。
    # 判準用「解析結果 == 記錄值」而非硬編長度——SHA-1 是 40 hex、SHA-256 是 64 hex，
    # 寫死 40 會把整個 sha256 repo 判成壞錨點。
    local resolved
    if ! resolved="$(git -C "$repo" rev-parse --verify --quiet "$sha^{commit}")" || [ -z "$resolved" ]; then
        echo "status: DIVERGED（記錄的 HEAD 已不存在——歷史改寫或錯誤錨點；內容一律存疑）"
        return 1
    fi
    if [ "$resolved" != "$sha" ]; then
        echo "status: BAD-ANCHOR（錨點的 head 不是完整 object ID（記錄=${sha}、解析成 ${resolved}）——"
        echo "        ref 名／HEAD／短 sha 都會隨時間改指，無法判斷交接內容是否過時；一律存疑）"
        return 1
    fi

    if [ "$(git -C "$repo" rev-parse "$sha")" = "$(git -C "$repo" rev-parse HEAD)" ]; then
        [ "$branch" != "$cur_branch" ] && echo "note: branch 已從 $branch 切到 $cur_branch"
        echo "status: FRESH"
        return 0
    fi

    if git -C "$repo" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
        local n
        n="$(git -C "$repo" rev-list --count "$sha..HEAD")"
        echo "status: DRIFTED（repo 已前進 $n commits，交接內容可能已失效——逐條對 repo 現況重驗）"
        git -C "$repo" log --oneline "$sha..HEAD" | head -n "$MAX_LOG" | sed 's/^/  /'
        [ "$n" -gt "$MAX_LOG" ] && echo "  ...（其餘 $((n - MAX_LOG)) commits 略）"
        return 1
    fi

    echo "status: DIVERGED（記錄的 HEAD 不在現行歷史上——rebase 或換了 branch；內容一律存疑）"
    return 1
}

cmd_verify() {
    [ $# -eq 1 ] || usage
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "error: 交接檔不存在：$file" >&2
        exit 1
    fi

    local overall=0

    # -- 年齡 --
    local created age
    created="$(sed -n 's/^created:[[:space:]]*//p' "$file" | head -1)"
    if [ -n "$created" ] && age="$(age_days_from_created "$created")"; then
        if [ "$age" -gt "$EXPIRE_DAYS" ]; then
            echo "age: ${age}d — EXPIRED（超過 ${EXPIRE_DAYS} 天，內容以 repo 現況為準）"
            overall=1
        else
            echo "age: ${age}d — OK"
        fi
    else
        echo "age: UNKNOWN（無法解析 created 欄位）"
        overall=1
    fi

    # -- 錨點 --
    local anchors
    anchors="$(grep '^anchor: ' "$file" || true)"
    if [ -z "$anchors" ]; then
        echo "anchors: NONE（無錨點——無法判斷交接內容是否過時，一律存疑）"
        echo "verdict: UNVERIFIABLE"
        exit 1
    fi

    local repo branch sha dirty _extra
    while IFS= read -r line; do
        # read 分欄不做 glob expansion（路徑含 * [ ? 也不會被展開成 cwd 檔名）
        IFS=' ' read -r repo branch sha dirty _extra <<< "${line#anchor: }"
        if [ -z "$sha" ]; then
            echo "--- ${repo:-?} ---"
            echo "status: BAD-ANCHOR（錨點行欄位不足，無法驗證：${line}）"
            overall=1
            continue
        fi
        verify_anchor "$repo" "$branch" "$sha" "$dirty" || overall=1
    done <<< "$anchors"

    if [ "$overall" -eq 0 ]; then
        # 措辭刻意不寫「交接內容可信」：本判定的範圍只到「列出的錨點」。未蓋錨點的 repo
        # 從不出現在上面任何一行，讀取端卻會把這句話當成整份交接檔的背書（2026-08-12 實地）。
        echo "verdict: FRESH（列出的錨點自蓋章以來未前進；未蓋錨點的 repo 不在本判定範圍）"
    else
        echo "verdict: STALE-RISK（先跑上列 drift 比對，以 repo 現況為準再行動）"
    fi
    exit "$overall"
}

# consume：R4 消費歸檔的機械化——驗位置（archive 內拒絕）→ mkdir -p archive →
# mv 加 YYYYMMDD-HHMMSS 前綴（同日同 slug 二次消費不互覆）→ 印 archived: 供回報。
# 本子指令是本腳本唯一動 active 檔的 mutation（mv 單一檔案；list 另會清過期 archive），
# 不碰 git、不碰檔案內容。
cmd_consume() {
    [ $# -eq 1 ] || usage
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "error: 交接檔不存在：${file}" >&2
        exit 1
    fi
    local dir base
    dir="$(CDPATH='' cd -- "$(dirname -- "$file")" 2>/dev/null && pwd -P)" || dir=""
    if [ -z "$dir" ]; then
        echo "error: 無法解析交接檔所在目錄：${file}" >&2
        exit 1
    fi
    base="$(basename -- "$file")"
    # 「已消費」偵測用工具自身不變量，不掃整條路徑找 archive 祖先——整路徑掃描會把
    # /srv/archive/<user>/handoffs/x.md 這類合法 active 檔誤拒（C2 審查實證），誤拒即
    # consume 永久卡死。兩個不變量：
    # (1) 直接父目錄名 archive（本工具的歸檔佈局）
    # (2) 檔名帶 YYYYMMDD-HHMMSS- 前綴（本工具的歸檔命名——被手工搬到巢狀子目錄也認得出）
    # 手工塞進 archive 巢狀子目錄且無前綴的檔案非本工具產物（從未被工具消費），不在偵測範圍
    if [ "$(basename -- "$dir")" = "archive" ]; then
        echo "error: 檔案已在 archive 內（已消費過）——consume-once，不可重複消費：${file}" >&2
        exit 1
    fi
    case "$base" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*)
            echo "error: 檔名已帶歸檔時戳前綴（已消費過）——consume-once，不可重複消費：${file}" >&2
            exit 1 ;;
    esac
    # 時戳先取出並驗格式——date 失敗時若直接串進路徑，會歸檔成 archive/-<name>
    # 且回報成功，稽核時戳靜默流失
    local ts
    ts="$(date +%Y%m%d-%H%M%S)" || ts=""
    case "$ts" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
        *)  echo "error: 無法取得時戳（date 失敗）——不歸檔，交接檔原地不動" >&2
            exit 1 ;;
    esac
    mkdir -p "$dir/archive"
    local dest="$dir/archive/${ts}-${base}"
    # -e 前置檢查而非 mv -n：BSD/GNU 的 mv -n 目標已存在時「靜默跳過且 exit 0」，
    # 會印 archived: 但檔案沒動——比檢查與 mv 之間的 TOCTOU 窗（單機單人工具）危險
    if [ -e "$dest" ]; then
        echo "error: 目標已存在（同秒重複消費？）：${dest}" >&2
        exit 1
    fi
    if ! mv -- "$file" "$dest"; then
        echo "error: mv 失敗，交接檔仍在原位：${file}" >&2
        exit 1
    fi
    echo "archived: $dest"
    exit 0
}

# 讀 frontmatter 的 slug 欄位。輸出 `=<值>` 表示**欄位存在**（值可能為空）；輸出空字串
# 表示無 frontmatter 或其中無該欄位。只掃第一個 `---` 到下一個 `---`——正文／code fence
# 裡的 `slug:` 不算數（W3 模板本身就長那樣，交接檔在講 handoff skill 時會把它貼進正文，
# 掃全檔會把範例值當成真欄位、進而拒絕正確的前一份）。
fm_slug() {
    awk '
        NR==1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        /^slug:/ { sub(/^slug:[[:space:]]*/, ""); print "=" $0; exit }
    ' "$1"
}

# 檔內 frontmatter slug 存在時須完全相符；沒有該欄位者放行（向後相容舊手寫檔）。
# 欄位存在但值為空 → 屬 malformed，不當成「沒有欄位」放行。
slug_matches() {
    local fs
    fs="$(fm_slug "$1")"
    [ -z "$fs" ] || [ "${fs#=}" = "$2" ]
}

# ---- archive 檔名身分解析（emit_predecessor 與 emit_worklines 共用）----
#
# 為何共用：同一份檔在 survey 的 predecessor 區段與 worklines 區段各解析一次的話，兩區段
# 會對它給出不同答案。結果放 PA_* 全域（bash 3.2 無 associative array、無 local -n）。
#
#   PA_CANDIDATES — 每行 `<key><TAB><slug>`，第一行即首選。**不可壓成單一值**：
#                   `YYYYMMDD-HHMMSS-<slug>` 與 legacy `YYYYMMDD-<slug>` 在 slug 恰以
#                   「6 位數字-」開頭時無法從檔名區分（`20260807-120000-foo` 讀得成
#                   slug=foo 也讀得成 slug=120000-foo）。歧義消不掉，兩種解讀都保留、
#                   任一命中即算——壓扁會讓正確的 slug 找不到自己的前一份（已修過的迴歸）。
#                   **key 逐候選各自成立**（legacy 解讀補零＝當日最早），不是整檔共用一個。
#   PA_PRIMARY / PA_KEY / PA_DATE — 顯示用首選 slug、其排序鍵、YYYY-MM-DD（無前綴為「—」）
#   PA_FLAGS      — 空白分隔：ambiguous ／ no-prefix ／ fm-mismatch:<檔內值>
#
# frontmatter `slug:` 的角色是**在檔名允許的解讀之間消歧，不是索引**：
#   - 與某個候選相符 → 該候選升為首選，歧義就此消解（不標 ambiguous）
#   - 與所有候選都不符 → 標 fm-mismatch。這種檔 find-predecessor **兩個方向都撈不到**
#     （檔名閘門擋掉 frontmatter 值、frontmatter 閘門擋掉檔名值，見 slug_matches），
#     本來完全隱形；標出來才讓 worklines 說得出「它在那裡，但定位器不會採用」。
#     **不讓 frontmatter 當索引**：那會使 survey 宣傳一條 find-predecessor 拒絕採用的
#     工作線，也與「手改過的殘檔不得被撿」的既有語意打架。
PA_CANDIDATES=""; PA_PRIMARY=""; PA_KEY=""; PA_DATE=""; PA_FLAGS=""
parse_archive_entry() {
    local f="$1" base name legacy newread fs v k s hit=""
    base="$(basename -- "$f")"
    name="${base%.md}"
    PA_CANDIDATES=""; PA_FLAGS=""
    case "$name" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*)
            newread="${name#????????-??????-}"
            legacy="${name#????????-}"
            PA_DATE="${name:0:4}-${name:4:2}-${name:6:2}"
            PA_CANDIDATES="${name:0:8}${name:9:6}"$'\t'"$newread"$'\n'"${name:0:8}000000"$'\t'"$legacy"
            ;;
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*)
            PA_DATE="${name:0:4}-${name:4:2}-${name:6:2}"
            PA_CANDIDATES="${name:0:8}000000"$'\t'"${name#????????-}"
            ;;
        *)  PA_DATE="—"
            PA_CANDIDATES="00000000000000"$'\t'"$name"
            PA_FLAGS="no-prefix"
            ;;
    esac
    fs="$(fm_slug "$f")"
    if [ -n "$fs" ]; then
        v="${fs#=}"
        while IFS=$'\t' read -r k s; do
            [ "$s" = "$v" ] && hit="${k}"$'\t'"${s}"
        done <<< "$PA_CANDIDATES"
        if [ -n "$hit" ]; then
            PA_CANDIDATES="$hit"
        else
            PA_FLAGS="${PA_FLAGS:+$PA_FLAGS }fm-mismatch:${v}"
        fi
    elif [ "$(grep -c '^' <<< "$PA_CANDIDATES")" -gt 1 ]; then
        PA_FLAGS="${PA_FLAGS:+$PA_FLAGS }ambiguous"
    fi
    PA_KEY="$(head -1 <<< "$PA_CANDIDATES" | cut -f1)"
    PA_PRIMARY="$(head -1 <<< "$PA_CANDIDATES" | cut -f2-)"
}

# emit_predecessor：依 slug 精確定位前一份交接檔（W1 判首輪／續寫用）。
#
# 為何不是一行 glob：`archive/*-<slug>.md` 看似尾錨定，但 `*` 一樣吃得下中間的工作線名——
# 查 `foo` 會命中 `20260802-120000-bar-foo.md`，`tail -1` 還剛好選它（時戳較新，字典序在後）。
# 同一處的定位邏輯被三輪第三方審查逐輪擠（只查 active → 分支迴歸 → glob 誤中），根因就是
# 拿 glob 做精確比對。改用精確判準（slug 不再進 glob，含 glob 字元或空白也不誤匹配）：
#   (1) 檔名比對——**active 與 archive 規則不同**：active 檔名就是 <slug>.md，一個字元都不剝
#       （剝了會讓「以日期開頭的合法 slug」比對失敗：W3 只禁 YYYYMMDD-HHMMSS- 開頭，
#       日期-only 的 slug 是合法的）；archive 走 parse_archive_entry 的候選清單。
#   (2) 檔內 slug: frontmatter 存在時須完全相等（不符即跳過）——見 slug_matches。
#
# archive 取「最新一輪」用**解析出的時戳數值**比大小，不靠 glob 字典序：legacy 的
# `YYYYMMDD-` 在字典序上排在同日 `YYYYMMDD-HHMMSS-` 之後（第 10 字元 'f' > '1'），
# 靠字典序會選到較舊的那份。
emit_predecessor() {  # <slug> <dir>
    local slug="$1" dir="$2"
    local hit_active="" hit_archive="" hit_key="" hit_flags="" f base key k s
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        base="$(basename -- "$f")"
        [ "${base%.md}" = "$slug" ] || continue
        slug_matches "$f" "$slug" || continue
        hit_active="$f"
    done

    for f in "$dir"/archive/*.md; do
        [ -f "$f" ] || continue
        parse_archive_entry "$f"
        key=""
        while IFS=$'\t' read -r k s; do
            [ "$s" = "$slug" ] && key="$k"
        done <<< "$PA_CANDIDATES"
        [ -n "$key" ] || continue
        slug_matches "$f" "$slug" || continue
        if [ -z "$hit_key" ] || [ "$key" -gt "$hit_key" ]; then
            hit_archive="$f"; hit_key="$key"; hit_flags="$PA_FLAGS"
        fi
    done

    if [ -n "$hit_active" ]; then
        echo "predecessor: $hit_active"
        echo "location: active（尚未消費——續寫會整檔覆寫它）"
    elif [ -n "$hit_archive" ]; then
        echo "predecessor: $hit_archive"
        echo "location: archive（已消費的前一輪）"
        case " $hit_flags " in *" ambiguous "*)
            echo "note: AMBIGUOUS——檔名新舊兩種歸檔格式都讀得通、檔內又無 slug: 可佐證，同一份會被兩個 slug 撈到。採用前先讀內容確認確實是這條工作線。" ;;
        esac
    else
        echo "predecessor: NONE（active 與 archive 皆無 slug=${slug} 的交接檔 → 首輪）"
    fi
}

emit_active() {  # <dir>
    local dir="$1" found=0 f base created age flag title
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        found=1
        base="$(basename "$f")"
        created="$(sed -n 's/^created:[[:space:]]*//p' "$f" | head -1)"
        if [ -n "$created" ] && age="$(age_days_from_created "$created")"; then
            flag="OK"
            [ "$age" -gt "$EXPIRE_DAYS" ] && flag="EXPIRED（建議：確認已無用即刪，或 resume 重驗）"
            echo "active: $base — ${age}d — $flag"
        else
            echo "active: $base — created 無法解析 — SUSPECT"
        fi
        # path：verify/consume 吃完整路徑，印出來免得讀取端自己手拼
        echo "  path: $f"
        # title：多份待選時光看 slug 分不出是哪條工作線；無標題行則整行省略
        title="$(sed -n 's/^# Handoff:[[:space:]]*//p' "$f" | head -1)"
        [ -n "$title" ] && echo "  title: $title"
    done
    [ "$found" -eq 0 ] && echo "active: none"
    return 0
}

# prune_archive：已消費的交接檔過保險絲期即刪。摘要放 PRUNE_NOTE 而非直接印——survey 必須
# 先清理再產生任何 archive 衍生輸出（否則剛好過 TTL 的 predecessor 會被先印後刪，讀取端
# 拿到 dangling path），但輸出順序仍要把這行留在最後。
PRUNE_NOTE=""
prune_archive() {  # <dir>
    local dir="$1" pruned=0 f
    PRUNE_NOTE=""
    [ -d "$dir/archive" ] || return 0
    while IFS= read -r f; do
        rm -f "$f" && pruned=$((pruned + 1))
    done < <(find "$dir/archive" -name '*.md' -type f -mtime "+$ARCHIVE_KEEP_DAYS")
    [ "$pruned" -gt 0 ] && PRUNE_NOTE="archive: 已清 $pruned 份超過 ${ARCHIVE_KEEP_DAYS} 天的已消費交接檔"
    return 0
}

# emit_worklines：把 archive 依 slug 聚合成「既有工作線」清單。W1 定 slug 時要看的是
# 「本次工作屬不屬於某條既有工作線」，而不是最近 N 個檔名——後者只是個會被別條工作線
# 刷掉的視窗。上限只截**顯示**並印出略過筆數，不靜默截斷。
WORKLINE_MAX=10
emit_worklines() {  # <dir>
    local dir="$1" f rows="" agg total shown key n slug date flags note
    if [ ! -d "$dir/archive" ]; then
        echo "worklines: none（無 archive 目錄）"
        return 0
    fi
    for f in "$dir"/archive/*.md; do
        [ -f "$f" ] || continue
        parse_archive_entry "$f"
        rows="${rows}${PA_PRIMARY}"$'\t'"${PA_KEY}"$'\t'"${PA_DATE}"$'\t'"${PA_FLAGS}"$'\n'
    done
    if [ -z "$rows" ]; then
        echo "worklines: none（archive 內無已消費的交接檔）"
        return 0
    fi
    # 聚合：每條工作線取輪數、最新 key 與其日期、旗標聯集（去重）。bash 3.2 無 associative
    # array，故聚合交給 awk；輸出 `<key>\t<n>\t<slug>\t<date>\t<flags>` 再由 sort 排序。
    #
    # ⚠ 兩個踩過的坑，改動這段前先讀：
    # (1) `$2 > k[$1]` 在 k 未初始化時是**數值**比較（uninit 當 0），無歸檔前綴的
    #     key `00000000000000` 於是 `0 > 0` 為偽、永遠不被採用 → 該筆的 key/date 留空。
    #     一律先判 `!($1 in k)`。
    # (2) **tab 是 IFS whitespace**：下方 `IFS=$'\t' read` 會吃掉前導 tab、並把連續 tab
    #     併成一個，空欄位一消失，後續欄位整批往前推移（實地長相：日期跑到輪數欄）。
    #     故空值一律以 `-` 佔位、由讀取端還原，讓五個欄位永遠非空。
    agg="$(printf '%s' "$rows" | awk -F'\t' '
        {
            n[$1]++
            if (!($1 in k) || $2 > k[$1]) { k[$1] = $2; d[$1] = $3 }
            if ($4 != "") {
                split($4, t, " ")
                for (i in t) if (t[i] != "" && index(" " fl[$1] " ", " " t[i] " ") == 0)
                    fl[$1] = (fl[$1] == "" ? t[i] : fl[$1] " " t[i])
            }
        }
        END {
            for (s in n) printf "%s\t%d\t%s\t%s\t%s\n", \
                k[s], n[s], s, (d[s] == "" ? "-" : d[s]), (fl[s] == "" ? "-" : fl[s])
        }
    ' | sort -r)"
    total="$(grep -c '^' <<< "$agg")"
    shown=0
    while IFS=$'\t' read -r key n slug date flags; do
        [ -n "$slug" ] || continue
        [ "$flags" = "-" ] && flags=""     # `-` 是佔位符，見上方 (2)
        shown=$((shown + 1))
        [ "$shown" -gt "$WORKLINE_MAX" ] && break
        note=""
        case " $flags " in
            *" ambiguous "*) note="${note}（檔名格式歧義，採用前讀內容確認）" ;;
        esac
        case " $flags " in
            *" no-prefix "*) note="${note}（有手工放入、無歸檔前綴的檔）" ;;
        esac
        case "$flags" in
            *fm-mismatch:*) note="${note}（檔內 slug=${flags#*fm-mismatch:} 與檔名不符，find-predecessor 不會採用）" ;;
        esac
        echo "workline: $slug — ${n} 輪 — 最近 ${date}${note}"
    done <<< "$agg"
    [ "$total" -gt "$WORKLINE_MAX" ] && echo "…（其餘 $((total - WORKLINE_MAX)) 條工作線略）"
    return 0
}

# 找不到是正常結果（＝首輪，不是錯誤），故一律 exit 0；用法錯誤才 exit 2。
cmd_find_predecessor() {
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    local dir="${2:-${HANDOFF_DIR:-$HOME/.claude/handoffs}}"
    if [ ! -d "$dir" ]; then
        echo "predecessor: NONE（目錄不存在：${dir}）"
        exit 0
    fi
    emit_predecessor "$1" "$dir"
    exit 0
}

cmd_list() {
    local dir="${1:-${HANDOFF_DIR:-$HOME/.claude/handoffs}}"
    if [ ! -d "$dir" ]; then
        echo "handoffs: NONE（目錄不存在：${dir}）"
        exit 0
    fi
    # path 行要能直接餵給 verify/consume，相對輸入先解析成絕對（同 consume 的解析模式）
    local abs
    abs="$(CDPATH='' cd -- "$dir" 2>/dev/null && pwd -P)" && dir="$abs"
    emit_active "$dir"
    prune_archive "$dir"
    [ -n "$PRUNE_NOTE" ] && echo "$PRUNE_NOTE"
    exit 0
}

# survey：W1／R1 的單一入口。把「active 清單 + 既有工作線 + predecessor 判定 + archive
# 清理」收成一次呼叫——這三件事原本靠 SKILL.md 的散文指揮 agent 分別去跑哪幾個指令，而
# 該契約實證會漏（W1 曾把 list 改成「只在未指定 slug 時跑」，W4 的 EXPIRED 回報與保留期
# 清理在 `/handoff <slug>` 路徑上雙雙沉默失效）。無條件單一呼叫讓那個分支不存在。
# 一律 exit 0（純資訊）；用法錯誤 exit 2。
cmd_survey() {
    local slug="" slug_given=0 dir=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --slug)   [ $# -ge 2 ] || usage; slug="$2"; slug_given=1; shift 2 ;;
            --slug=*) slug="${1#--slug=}"; slug_given=1; shift ;;
            -*)       usage ;;
            *)        [ -z "$dir" ] || usage; dir="$1"; shift ;;
        esac
    done
    # `--slug ""` 是缺值，不是「沒給 slug」——靜默當成後者會讓 predecessor 區段消失而無人察覺
    [ "$slug_given" -eq 1 ] && [ -z "$slug" ] && usage
    [ -n "$dir" ] || dir="${HANDOFF_DIR:-$HOME/.claude/handoffs}"
    if [ ! -d "$dir" ]; then
        echo "handoffs: NONE（目錄不存在：${dir}）"
        exit 0
    fi
    local abs
    abs="$(CDPATH='' cd -- "$dir" 2>/dev/null && pwd -P)" && dir="$abs"

    # 清理必須在任何 archive 衍生輸出**之前**：某工作線唯一一份 archive 剛好過 TTL 時，
    # 先印後刪會讓讀取端拿到 dangling 的 workline/predecessor 路徑，連「當線索讀」都做不到。
    prune_archive "$dir"
    emit_active "$dir"
    emit_worklines "$dir"
    [ "$slug_given" -eq 1 ] && emit_predecessor "$slug" "$dir"
    [ -n "$PRUNE_NOTE" ] && echo "$PRUNE_NOTE"
    exit 0
}

[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
    anchors) cmd_anchors "$@" ;;
    verify)  cmd_verify "$@" ;;
    consume) cmd_consume "$@" ;;
    survey)  cmd_survey "$@" ;;
    list)    cmd_list "$@" ;;
    find-predecessor) cmd_find_predecessor "$@" ;;
    *) usage ;;
esac
