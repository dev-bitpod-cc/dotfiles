#!/usr/bin/env bash
# codex-exec-review.sh — 以 headless `codex exec` 執行 codex 第三方審查（autocodex 階段的傳輸層）。
#
# 為何存在（實證根因，2026-07-20 定位）：codex plugin 的 broker 路徑把「執行者」與「等待者」拆成兩組
#   進程——broker→app-server 以 detached+unref 生成，不管等待者死活都會把 turn 跑完並落檔到
#   ~/.codex/sessions/*.jsonl；而等待端 captureTurn() 只 await 一個「僅由 broker 轉發的 turn/completed
#   才 resolve」的 promise，無 timeout、無輪詢、也不與連線死亡 race。**通知一斷即永久靜默等待**，
#   外觀與正常執行無法區分，只能靠 15 分鐘啟發式事後撈救。
#   改走 `codex exec` 後，完成訊號是「進程退出」+「結果檔落地」兩個 OS 層級事實，不再依賴通知轉發。
#
# 用法（exit 契約）：
#   codex-exec-review.sh run --repo <path> --range <base..head> --round <C1|C2|C3>
#       阻塞執行（呼叫端應以背景 Bash 啟動，由 harness 於進程結束時回叫）。
#       0=report.md 非空（成功）；4=進程結束但報告空（升級 resume）；
#       5=環境不具備或引數值不合法（codex 不在 PATH、非 git repo、range 無法解析；多數情況下
#         尚未建立 job 目錄，例外是 mkdir/mktemp 本身失敗）；
#       2=引數結構寫錯（缺必填、未知子指令）
#   codex-exec-review.sh resume --job-dir <dir> [--prompt <text>]
#       以該 job 記錄的 session id 續跑，救回卡在 session 裡的報告。
#       0=report-resume.md 非空；4=仍空**或此 job 不可續**（無 session id / meta 無 repo → 往下一階跑 fresh run）；
#       5=環境/引數錯誤（codex 不在 PATH、job 目錄不存在）；2=用法錯誤
#   codex-exec-review.sh status --job-dir <dir>
#       印 job 摘要（狀態、報告大小、events 末幾行、耗時）。0=可讀；5=job 目錄無效；2=用法錯誤
#
# job 目錄產物：
#   run    — cmd / meta / events.jsonl / stderr.log / report.md / session-id / exit-code / .started
#   resume — cmd-resume / events-resume.jsonl / stderr-resume.log / report-resume.md /
#            exit-code-resume / .started-resume（meta 追加 resume-started= / resume-ended=）
#
# CODEX_EXEC_* 環境變數為測試掛鉤（tests/run.sh 注入 fixture 用），正常使用不設。
set -uo pipefail

JOB_ROOT="${CODEX_EXEC_REVIEW_DIR:-$HOME/.claude/deep-review/codex}"
SESSIONS_DIR="${CODEX_EXEC_SESSIONS_DIR:-$HOME/.codex/sessions}"

# 審查者需要跑會建立暫存/cache 的測試，但 repo 必須保持唯讀。permission profile 從
# :read-only 繼承，只開目前 $TMPDIR；--strict-config 讓不支援 profile 的舊版 Codex
# 直接失敗，NEVER 靜默落回使用者 config 的 danger-full-access。
CODEX_REVIEW_PERMISSION_ARGS=(
    --ignore-user-config
    --strict-config
    -c 'default_permissions="repo_review_temp"'
    -c 'permissions.repo_review_temp.extends=":read-only"'
    -c 'permissions.repo_review_temp.filesystem={":tmpdir"="write"}'
)

# resume 專用 prompt 的唯一文字來源；救援流程語意見 `../references/codex-protocol.md`「exit 4 救援階梯」。
RESUME_PROMPT_DEFAULT='你先前的審查已完成偵查與驗證，請直接輸出最終審查報告（findings：嚴重度、檔案:行號、問題、建議；繁體中文）。不要再執行任何指令。'

# run 與 resume 共用同一則訊息——兩條路徑都會撞到，指引不該只有一邊有
CODEX_MISSING_MSG='codex 不在 PATH（brew install --cask codex；NEVER bun install -g @openai/codex——會重造 bun/brew split-brain）'

die_usage() { echo "用法錯誤：$1" >&2; exit 2; }
die_env()   { echo "環境錯誤：$1" >&2; exit 5; }

# 取 job 目錄用的 repo 短識別：basename + 絕對路徑雜湊（避免同名 repo 互撞；cksum 為 POSIX，免依賴 shasum）
repo_slug() {
    local abs="$1" hash
    hash="$(printf '%s' "$abs" | cksum | awk '{print $1}')"
    printf '%s-%s\n' "$(basename "$abs")" "$hash"
}

# 自 events JSONL 取 codex session id（resume 依賴它）。依序：jq → regex → rollout 回退。
extract_session_id() {
    local events="$1" repo="$2" marker="$3" sid=""

    if [ -s "$events" ] && command -v jq >/dev/null 2>&1; then
        sid="$(jq -r 'first((.session_id? // .thread_id? // .threadId? // .thread?.id? // .payload?.session_id?) | select(. != null and . != ""))' \
               "$events" 2>/dev/null | head -1)"
        [ "$sid" = "null" ] && sid=""
    fi

    if [ -z "$sid" ] && [ -s "$events" ]; then
        sid="$(grep -o -E '"(session_id|thread_id|threadId)"[[:space:]]*:[[:space:]]*"[^"]+"' "$events" 2>/dev/null \
               | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
    fi

    # 回退：掃本次執行期間寫入、且 cwd 指向本 repo 的 rollout（codex exec 一律落檔，除非 --ephemeral）。
    # 用 -newer <marker 檔> 而非 -newermt '@epoch'——BSD/macOS find 不保證吃得下 @epoch 寫法。
    # 唯一命中才採用：這條回退只靠「比 marker 新 + cwd 同 repo」關聯，同 repo 的兩場 review
    # 重疊執行時會同時命中同一批 rollout，取「最新」等於擲骰子——續錯 session 會拿到別人的
    # 報告或干擾對方。寧可回空（→ resume 回 4 → 走 fresh run），不要猜。
    if [ -z "$sid" ] && [ -d "$SESSIONS_DIR" ] && [ -f "$marker" ]; then
        local f candidate="" hits=0
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if head -1 "$f" 2>/dev/null | grep -qF "\"$repo\""; then
                # rollout 與 events 的欄位名可能不同（實測 events 用 thread_id），兩者都收
                local found
                found="$(head -1 "$f" 2>/dev/null \
                       | grep -o -E '"(session_id|thread_id|threadId)"[[:space:]]*:[[:space:]]*"[^"]+"' \
                       | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
                if [ -n "$found" ]; then
                    candidate="$found"
                    hits=$((hits + 1))
                fi
            fi
        done <<< "$(find "$SESSIONS_DIR" -name 'rollout-*.jsonl' -newer "$marker" 2>/dev/null | sort -r)"

        if [ "$hits" -eq 1 ]; then
            sid="$candidate"
        elif [ "$hits" -gt 1 ]; then
            echo "⚠️  rollout 回退命中 $hits 筆同 repo session，無法唯一關聯 → 不猜，留空" >&2
        fi
    fi

    printf '%s\n' "$sid"
}

# 從 job 的 meta 取 key（run 寫入、resume/status 讀取）
meta_get() {   # meta_get <job_dir> <key>
    sed -n "s/^$2=//p" "$1/meta" 2>/dev/null | head -1
}

prepare_review_tmp() {   # prepare_review_tmp <job_dir>
    mkdir -p "$1/tmp/uv" "$1/tmp/pytest" \
        || die_env "無法建立 reviewer 暫存目錄：$1/tmp"
}

# 印一段耗時；ended 未寫入表示該階段仍在執行
print_elapsed() {   # print_elapsed <job_dir> <label> <started_key> <ended_key>
    local job="$1" label="$2" s e now elapsed
    s="$(meta_get "$job" "$3")"
    [ -n "$s" ] || return 0
    e="$(meta_get "$job" "$4")"
    now="${e:-$(date +%s)}"
    elapsed=$((now - s))
    if [ -n "$e" ]; then
        printf '%s=%ss\n' "$label" "$elapsed"
    else
        printf '%s=%ss (執行中)\n' "$label" "$elapsed"
    fi
}

cmd_run() {
    local repo="" range="" round=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo)  repo="${2:-}";  shift 2 || die_usage "--repo 缺少值" ;;
            --range) range="${2:-}"; shift 2 || die_usage "--range 缺少值" ;;
            --round) round="${2:-}"; shift 2 || die_usage "--round 缺少值" ;;
            *) die_usage "未知引數 '$1'" ;;
        esac
    done
    [ -n "$repo" ]  || die_usage "缺少 --repo"
    [ -n "$range" ] || die_usage "缺少 --range"
    [ -n "$round" ] || die_usage "缺少 --round"
    # round 會直接進 mktemp 樣板：含 / 會讓 mktemp 失敗，錯誤訊息卻指向「無法建立 job 目錄」誤導
    # 不可寫成 C[0-9]*——尾隨的 * 會讓 "C1/x" 這種含路徑分隔的值矇混過關
    case "$round" in
        C[0-9]|C[0-9][0-9]) ;;
        *) die_usage "--round 應為 C1/C2/C3 形式：$round" ;;
    esac

    command -v codex >/dev/null 2>&1 || die_env "$CODEX_MISSING_MSG"
    [ -d "$repo" ] || die_env "repo 路徑不存在：$repo"
    repo="$(cd "$repo" && pwd)" || die_env "無法解析 repo 路徑：$repo"
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die_env "不是 git repo：$repo"

    # range 驗證必須與**下游 repo-review 的契約**一致（codex/skills/repo-review/scripts/review-context.sh）：
    # 它明確拒絕三點 range 與無法解析的 base。wrapper 放行、下游拒絕的話，codex 只會把錯誤訊息
    # 寫進 report.md，而報告非空 → 本腳本回 0 → 產出「成功但其實什麼都沒審」的報告。
    # Validate against the DOWNSTREAM contract, not just against git.
    case "$range" in
        *...*) die_env "repo-review 不接受三點 range（語意歧義），請給明確的 <base>..<head>：$range" ;;
        *..*..*) die_env "range 只能有一組 ..（否則中段會被靜默吞掉）：$range" ;;
        *..*) ;;
        *) die_env "range 格式應為 <base>..<head>：$range" ;;
    esac
    local head_ref="${range##*..}" base_ref="${range%%..*}"
    [ -n "$head_ref" ] || die_env "range 缺少 head 端：$range"
    git -C "$repo" rev-parse --verify --quiet "$head_ref" >/dev/null 2>&1 \
        || die_env "range 的 head 端無法解析：$head_ref"
    # base 端：只放行**明確的 baseline 表示法**，其餘無法解析者一律攔下。
    # 若一概只警告，`maim..HEAD` 這種拼錯照樣啟動 codex；codex 把「無法 diff」寫進報告後
    # 腳本仍回 0 → 產出一份「成功但其實什麼都沒審」的報告。
    # ∅ / EMPTY 是**報告模板用的顯示寫法**，下游 review-context.sh 不認得（實測回
    # `cannot resolve range base: ∅`）→ 必須在此正規化成 empty-tree hash 再送出，
    # 不能原樣傳遞。
    local EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
    if [ -n "$base_ref" ] && ! git -C "$repo" rev-parse --verify --quiet "$base_ref" >/dev/null 2>&1; then
        case "$base_ref" in
            ∅|EMPTY)
                echo "ℹ️  baseline 模式：base 端 ${base_ref} 正規化為 empty-tree（全量稽核）" >&2
                base_ref="$EMPTY_TREE"
                range="${base_ref}..${head_ref}" ;;
            "$EMPTY_TREE")
                echo "ℹ️  baseline 模式：base 端為 empty-tree（全量稽核）" >&2 ;;
            *)
                die_env "range 的 base 端無法解析：${base_ref}（baseline 請用 ∅ 或 empty-tree hash）" ;;
        esac
    fi

    local started job job_parent
    started="$(date +%s)"
    job_parent="$JOB_ROOT/$(repo_slug "$repo")"
    mkdir -p "$job_parent" || die_env "無法建立 job 目錄：$job_parent"
    local job_parent_real repo_real
    job_parent_real="$(cd "$job_parent" && pwd -P)" || die_env "無法解析 job 目錄：$job_parent"
    repo_real="$(cd "$repo" && pwd -P)" || die_env "無法解析 repo 路徑：$repo"
    case "$job_parent_real" in
        "$repo_real"|"$repo_real"/*)
            die_env "reviewer 暫存目錄不得位於受審 repo 內：$job_parent_real" ;;
    esac
    job_parent="$job_parent_real"
    # mktemp 保證唯一：同一秒內的兩次 run（C{N} 重跑、多 repo 併發）若共用目錄，
    # 會把上一輪殘留的 report.md 當成本輪產出回報 → 假成功。NEVER derive job dir from timestamp alone.
    job="$(mktemp -d "$job_parent/$round-$started-XXXXXX")" || die_env "無法建立 job 目錄：$job_parent"
    echo "job-dir: $job"
    local marker="$job/.started"
    : > "$marker"
    prepare_review_tmp "$job"

    # 一行協議 prompt：逐字固定。NEVER add focus points, test requests, context files, or convention docs.
    local prompt="Run your repo-review skill on $repo for $range. 繁體中文."

    {
        printf 'repo=%s\n' "$repo"
        printf 'range=%s\n' "$range"
        printf 'round=%s\n' "$round"
        printf 'started=%s\n' "$started"
    } > "$job/meta"
    local -a argv=(exec --json --color never -C "$repo" "${CODEX_REVIEW_PERMISSION_ARGS[@]}" \
        -o "$job/report.md" "$prompt")
    local pytest_addopts="${PYTEST_ADDOPTS:-}"
    pytest_addopts="${pytest_addopts:+$pytest_addopts }-o cache_dir=\"$job/tmp/pytest\""

    # 記錄與執行**衍生自同一個 argv 陣列**：兩者若各寫一遍，$job/cmd 只是重建字串，
    # 對它做的斷言守不住真實呼叫（實證：拿掉真實呼叫的 -s，測試仍全綠）。
    # NEVER reconstruct the command line separately from the one actually executed.
    { printf '%q ' codex "${argv[@]}"; printf '\n'; } > "$job/cmd"

    TMPDIR="$job/tmp" UV_CACHE_DIR="$job/tmp/uv" PYTEST_ADDOPTS="$pytest_addopts" \
        codex "${argv[@]}" > "$job/events.jsonl" 2> "$job/stderr.log"
    local rc=$?

    printf '%s\n' "$rc" > "$job/exit-code"
    printf 'ended=%s\n' "$(date +%s)" >> "$job/meta"
    extract_session_id "$job/events.jsonl" "$repo" "$marker" > "$job/session-id"

    if [ -s "$job/report.md" ]; then
        echo "report: $job/report.md"
        return 0
    fi

    # ${rc} 必須帶大括號：全形括號在部分 locale 下會被 bash 併入變數名 → unbound variable
    echo "⚠️  codex 進程已結束但報告為空（codex exit=${rc}）——升級 resume：" >&2
    printf '    %q resume --job-dir %q\n' "$0" "$job" >&2
    return 4
}

cmd_resume() {
    local job="" prompt="$RESUME_PROMPT_DEFAULT"
    while [ $# -gt 0 ]; do
        case "$1" in
            --job-dir) job="${2:-}";    shift 2 || die_usage "--job-dir 缺少值" ;;
            --prompt)  prompt="${2:-}"; shift 2 || die_usage "--prompt 缺少值" ;;
            *) die_usage "未知引數 '$1'" ;;
        esac
    done
    [ -n "$job" ] || die_usage "缺少 --job-dir"
    [ -d "$job" ] || die_env "job 目錄不存在：$job"
    command -v codex >/dev/null 2>&1 || die_env "$CODEX_MISSING_MSG"

    # 「此 job 不可續」回 4 而非 5：5 的契約是「環境錯誤 → 停、不重試」，會讓呼叫端跳過階梯
    # 第 2 步的 fresh run，並向使用者輸出「檢查 codex 是否在 PATH」這種誤導性診斷。
    # 4 的語意才對——這條路救不回，往下一階走。5 僅保留給真正的環境/引數錯誤（見上方三項檢查）。
    local sid=""
    [ -f "$job/session-id" ] && sid="$(tr -d '[:space:]' < "$job/session-id")"
    if [ -z "$sid" ]; then
        echo "⚠️  job 未記錄 codex session id，無法 resume（$job/session-id）——依階梯改跑 fresh run" >&2
        return 4
    fi

    # `codex exec resume` 與 `codex exec` 是不同 subcommand，旗標集合不同：
    #   無 --color、無 -s/--sandbox、無 -C/--cd（帶了會被 clap 當 unexpected argument 拒絕）。
    # permission profile 可透過兩者共有的 -c/--strict-config 套用；工作根改以 cd 達成
    # （resume 不吃 -C，不 cd 會繼承呼叫端 cwd——多 repo 下幾乎必為錯的 repo）。
    local repo=""
    repo="$(meta_get "$job" repo)"
    if [ -z "$repo" ] || [ ! -d "$repo" ]; then
        echo "⚠️  job meta 未記錄可用的 repo 路徑，無法 resume（$job/meta）——依階梯改跑 fresh run" >&2
        return 4
    fi

    echo "resume session: $sid"

    # marker 用本次 resume 的時間，不沿用 run 的 $job/.started——resume 可能數小時後才跑，
    # 用舊 marker 會讓 rollout 回退的時間窗過寬，撈到期間別的 job 的 session。
    local marker="$job/.started-resume"
    : > "$marker"
    printf 'resume-started=%s\n' "$(date +%s)" >> "$job/meta"
    prepare_review_tmp "$job"

    local -a argv=(exec resume "$sid" --json "${CODEX_REVIEW_PERMISSION_ARGS[@]}" \
        -o "$job/report-resume.md" "$prompt")
    local pytest_addopts="${PYTEST_ADDOPTS:-}"
    pytest_addopts="${pytest_addopts:+$pytest_addopts }-o cache_dir=\"$job/tmp/pytest\""
    # `&&` 必須留在 %q 之外，否則被轉義成 \&\& → 貼回 shell 時變成 cd 的字面引數，codex 根本不會跑
    { printf 'cd %q && ' "$repo"; printf '%q ' codex "${argv[@]}"; printf '\n'; } > "$job/cmd-resume"

    ( cd "$repo" && TMPDIR="$job/tmp" UV_CACHE_DIR="$job/tmp/uv" PYTEST_ADDOPTS="$pytest_addopts" \
        codex "${argv[@]}" ) \
        > "$job/events-resume.jsonl" 2> "$job/stderr-resume.log"
    local rc=$?
    printf '%s\n' "$rc" > "$job/exit-code-resume"
    printf 'resume-ended=%s\n' "$(date +%s)" >> "$job/meta"

    # resume 可能開新 thread：取得非空才覆寫，避免把既有 sid 洗成空值
    local new_sid=""
    new_sid="$(extract_session_id "$job/events-resume.jsonl" "$repo" "$marker")"
    [ -n "$new_sid" ] && printf '%s\n' "$new_sid" > "$job/session-id"

    if [ -s "$job/report-resume.md" ]; then
        echo "report: $job/report-resume.md"
        return 0
    fi

    echo "⚠️  resume 仍無產出（codex exit=${rc}）——依 SKILL.md 階梯重跑一次 run，再失敗即判 blocked" >&2
    return 4
}

cmd_status() {
    local job=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --job-dir) job="${2:-}"; shift 2 || die_usage "--job-dir 缺少值" ;;
            *) die_usage "未知引數 '$1'" ;;
        esac
    done
    [ -n "$job" ] || die_usage "缺少 --job-dir"
    [ -d "$job" ] || die_env "job 目錄不存在：$job"

    [ -f "$job/meta" ] && cat "$job/meta"

    # run 與 resume 各自算 elapsed——只算 run 的話，resume 執行中時會顯示一個早已「結束」的耗時
    print_elapsed "$job" elapsed started ended
    print_elapsed "$job" elapsed-resume resume-started resume-ended

    if [ -f "$job/exit-code" ]; then
        printf 'codex-exit=%s\n' "$(cat "$job/exit-code")"
    else
        printf 'codex-exit=(尚未結束)\n'
    fi
    # resume 跑過就一併呈現——否則 resume 的失敗原因（如 CLI 介面不符）只落在 stderr-resume.log
    # 而無人看得到，會被誤判成「codex 環境問題」走 blocked。
    [ -f "$job/exit-code-resume" ] && printf 'codex-exit-resume=%s\n' "$(cat "$job/exit-code-resume")"

    local report="$job/report.md"
    [ -s "$job/report-resume.md" ] && report="$job/report-resume.md"
    if [ -s "$report" ]; then
        printf 'report=%s (%s bytes)\n' "$report" "$(wc -c < "$report" | tr -d ' ')"
    else
        printf 'report=(空)\n'
    fi

    if [ -s "$job/events.jsonl" ]; then
        echo "--- events（末 5 行）"
        tail -5 "$job/events.jsonl"
    fi
    if [ -s "$job/events-resume.jsonl" ]; then
        echo "--- events-resume（末 5 行）"
        tail -5 "$job/events-resume.jsonl"
    fi
    if [ -s "$job/stderr.log" ]; then
        echo "--- stderr（末 5 行）"
        tail -5 "$job/stderr.log"
    fi
    if [ -s "$job/stderr-resume.log" ]; then
        echo "--- stderr-resume（末 5 行）"
        tail -5 "$job/stderr-resume.log"
    fi
    return 0
}

MODE="${1:-}"
[ $# -gt 0 ] && shift
case "$MODE" in
    run)    cmd_run "$@" ;;
    resume) cmd_resume "$@" ;;
    status) cmd_status "$@" ;;
    *)      die_usage "未知子指令 '${MODE:-}'（用 run / resume / status）" ;;
esac
