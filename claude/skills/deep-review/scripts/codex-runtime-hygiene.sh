#!/usr/bin/env bash
# codex-runtime-hygiene.sh — 偵測/清理 codex plugin 的孤兒 runtime（split-brain / 死 broker）。
#
# 為何存在（實證根因）：codex plugin 的 review 跑在「per-cwd 常駐 broker + codex app-server」上。
#   若正在跑的 app-server 用的 binary ≠ 現行 PATH 上的 codex（典型：codex 從 bun 遷到 brew，舊
#   bun-era broker/app-server 未收成孤兒），兩套 runtime 會搶同一份 ~/.codex/*.sqlite 狀態互踩
#   → review 長 turn 中途無聲猝死、companion status 永卡 verifying（zombie）。死掉的 broker 也會
#   留下指向死 pid 的 stale broker.json。此腳本在 autocodex 呼叫 codex:rescue 前做 preflight。
#
# 用法（exit 契約）：
#   codex-runtime-hygiene.sh check   # 只報告。0=乾淨；1=有可清項（孤兒 broker / stale json）；
#                                    #   3=僅有現役 split-brain broker（誤殺防護跳過，無可清項）
#   codex-runtime-hygiene.sh clean   # SIGTERM 孤兒 broker + 移除 stale broker.json/socket 目錄，再複驗。
#                                    #   0=可清項全清（僅剩現役 skip 亦為 0）；1=複驗仍有可清項；2=用法錯誤
#
# 何時跑：autocodex 進 codex 階段、第一次呼叫 codex:rescue 前一律跑（乾淨即秒級 no-op）。
set -uo pipefail

MODE="${1:-check}"
case "$MODE" in check|clean) ;; *) echo "未知模式 '$MODE'（用 check 或 clean）"; exit 2 ;; esac

# CODEX_HYGIENE_* 環境變數為測試掛鉤（tests/run.sh 注入 fixture 用），正常使用不設
STATE_DIR="${CODEX_HYGIENE_STATE_DIR:-$HOME/.claude/plugins/data/codex-openai-codex/state}"
BROKER_PATTERN="${CODEX_HYGIENE_BROKER_PATTERN:-app-server-broker\\.mjs serve}"   # 常駐 broker daemon 的進程特徵
TERM_WAIT_SEC=2                                  # SIGTERM 後等 broker shutdown handler 連帶收 app-server 的秒數
ACTIVE_LOG_MAX_AGE=900   # 秒；job log 於此秒數內有更新視為「正在工作」（= 死亡偵測 dual-signal 的 15 分門檻）

# 狀態追蹤（check 的 exit code 依此三者決定，契約見檔頭）
cleanable=0         # 有可清項（孤兒 broker / stale json）
orphan_brokers=""   # 可清的孤兒 broker（split-brain 且無進行中 job）
active_skips=""     # split-brain 但現役（或無 jq 無法判定）→ 誤殺防護跳過
stale_jsons=""      # pid 已死的 broker.json

# 解析 symlink 到最終實體（可移植：不依賴 GNU `readlink -f`，用單層 readlink 迴圈；BSD/macOS 適用）。
resolve_link() {
  local p="$1" hops=0
  while [ -L "$p" ] && [ "$hops" -lt 10 ]; do
    local t; t="$(readlink "$p")" || break
    case "$t" in
      /*) p="$t" ;;                       # 絕對 target
      *)  p="$(cd "$(dirname "$p")" && cd "$(dirname "$t")" 2>/dev/null && pwd)/$(basename "$t")" ;;  # 相對 target
    esac
    hops=$((hops + 1))
  done
  printf '%s\n' "$p"
}

# 現行 codex 實體路徑（PATH 上的 codex 解 symlink 後）。找不到 codex → 印空字串，交由呼叫端判斷。
CURRENT_CODEX=""
if c="$(command -v codex 2>/dev/null)"; then
  CURRENT_CODEX="$(resolve_link "$c")"
fi

# 判斷一條 app-server 進程的命令列是否為「孤兒」（binary ≠ 現行 codex）。
#   規則：命令列若含**絕對路徑**的 codex binary token → 解析後與 CURRENT_CODEX 比對，不同即孤兒。
#   若只有裸 `codex`（無斜線）→ 它是靠 PATH 解析出來的 = 現行 codex = 健康。
#   （bun 是 `node /…/.bun/bin/codex app-server` 或 vendor 絕對路徑 → 會被抓到；brew 常見為裸 `codex`。）
is_orphan_cmd() {
  local cmd="$1" tok
  local -a toks=()
  [ -n "${cmd// }" ] || return 1
  read -ra toks <<< "$cmd"   # read 不做 glob 展開，token 含萬用字元也不會被展開
  for tok in "${toks[@]}"; do
    case "$tok" in
      # 絕對路徑且含 "codex"（bun 的 …/bin/codex、…/vendor/…/codex-*-darwin 都會命中；
      # 裸 codex 無斜線不會進來，代表它靠 PATH 解析＝現行 codex＝健康）
      /*codex*)
        [ "$(resolve_link "$tok")" != "$CURRENT_CODEX" ] && return 0 ;;
    esac
  done
  return 1
}

# 進程存活判斷
alive() { kill -0 "$1" 2>/dev/null; }

# 列出全部 broker.json。用 find 而非 "$STATE_DIR"/*/broker.json glob：plugin 的 state 目錄名取
# workspace basename（如 .dotfiles-<hash>/），dot 開頭目錄會被 glob 跳過 → 現役 broker 被誤判
# untracked orphan、stale json 永不被清。
list_broker_jsons() {
  [ -d "$STATE_DIR" ] || return 0
  find "$STATE_DIR" -mindepth 2 -maxdepth 2 -name broker.json 2>/dev/null
}

# broker_actively_working <broker_pid>：該 broker 有正在進行的 job → return 0（別殺）。
#   誤殺防護：split-brain 判斷只看 binary 路徑，無法區分「舊安裝的孤兒」與「upgrade 前就在跑、
#   app-server 還在舊路徑的現役 review」。故殺之前再驗一次活性——仍有進行中的 job（status ∈
#   {queued, running}，對齊 plugin isActiveJobStatus；UI 顯示的 starting/verifying 是 phase
#   欄位，不會出現在 job.status）且 log 15 分內有更新，就是現役，跳過只警告。無對應 broker.json
#   （untracked）或 job 已完/停/log 停滯 → 非現役，可清。
#   回傳值三態：0=現役別殺、1=非現役可清、2=無法判定（無 jq / state.json 壞損；呼叫端須保守跳過）。
broker_actively_working() {
  local bpid="$1" bj sd sj logf mtime now
  command -v jq >/dev/null 2>&1 || return 2   # 無 jq → 無法判活性
  while IFS= read -r bj; do
    [ -e "$bj" ] || continue
    [ "$(jq -r '.pid // empty' "$bj" 2>/dev/null)" = "$bpid" ] || continue
    sd="$(dirname "$bj")"; sj="$sd/state.json"
    [ -e "$sj" ] || return 1
    # jobs 陣列「新的在前」（plugin unshift + updatedAt 降冪 prune）——不賭索引，掃任一 active job
    logf="$(jq -r '[.jobs[]? | select(.status=="queued" or .status=="running")][0].logFile // empty' "$sj" 2>/dev/null)" || return 2
    { [ -n "$logf" ] && [ -e "$logf" ]; } || return 1   # 無 active job、或其 log 檔不存在 → 無從證明現役
    # GNU stat 先試 -c %Y（BSD 的 -c 會失敗再退 -f %m）；順序反過來 GNU 的 `stat -f %m` 會
    # 「成功」印出掛載點（-f=filesystem、%m=mount point）害 fallback 永不執行
    mtime="$(stat -c %Y "$logf" 2>/dev/null || stat -f %m "$logf" 2>/dev/null)"
    case "$mtime" in ''|*[!0-9]*) return 1 ;; esac      # 非純數字（stat 異常）→ 無從證明現役
    now="$(date +%s)"
    [ $(( now - mtime )) -lt "$ACTIVE_LOG_MAX_AGE" ] && return 0
    return 1
  done < <(list_broker_jsons)
  return 1   # 無對應 broker.json（untracked orphan）→ 非現役
}

# 測試掛鉤：CODEX_HYGIENE_SOURCED=1 時只定義函式、不執行主流程（tests/run.sh 做函式級測試用）
if [ "${CODEX_HYGIENE_SOURCED:-0}" = "1" ]; then
  # shellcheck disable=SC2317  # exit 只在「被直接執行而非 source」時可達，非死碼
  return 0 2>/dev/null || exit 0
fi

echo "== codex runtime hygiene ($MODE) =="
[ -n "$CURRENT_CODEX" ] && echo "現行 codex: $CURRENT_CODEX" || echo "現行 codex: (PATH 上找不到 — 略過 split-brain 比對)"

# ---- 1) 孤兒 broker（其 app-server 子進程用的 binary ≠ 現行 codex）----
if command -v pgrep >/dev/null 2>&1 && [ -n "$CURRENT_CODEX" ]; then
  for bpid in $(pgrep -f "$BROKER_PATTERN" 2>/dev/null); do
    cwd_hint="$(ps -o command= -p "$bpid" 2>/dev/null | grep -oE -- '--cwd [^ ]+' | head -1)"
    is_orphan=0
    for cpid in $(pgrep -P "$bpid" 2>/dev/null); do
      ccmd="$(ps -o command= -p "$cpid" 2>/dev/null)"
      if is_orphan_cmd "$ccmd"; then is_orphan=1; fi
    done
    if [ "$is_orphan" -eq 1 ]; then
      broker_actively_working "$bpid" && rc=0 || rc=$?
      case "$rc" in
        0)
          # 誤殺防護：split-brain 但最新 job 正在進行（log 新鮮）→ 可能是 upgrade 前起跑的現役 review，跳過
          active_skips="$active_skips $bpid"
          echo "  [SKIP 現役 broker] pid=$bpid $cwd_hint — binary ≠ 現行 codex 但 job 仍在進行（log 15 分內有更新），不殺；如確為孤兒請手動處理"
          ;;
        2)
          # 無 jq 無法驗活性 → 保守跳過（誤殺代價 > 漏清代價）
          active_skips="$active_skips $bpid"
          echo "  [SKIP 無法判定] pid=$bpid $cwd_hint — 無 jq 無法驗證活性，保守不殺；brew install jq 後重跑"
          ;;
        *)
          cleanable=1
          orphan_brokers="$orphan_brokers $bpid"
          echo "  [孤兒 broker] pid=$bpid $cwd_hint — 子 app-server binary ≠ 現行 codex（無進行中 job）"
          ;;
      esac
    fi
  done
fi

# ---- 2) stale broker.json（記的 pid 已死）----
while IFS= read -r bj; do
  [ -e "$bj" ] || continue
  if command -v jq >/dev/null 2>&1; then
    pid="$(jq -r '.pid // empty' "$bj" 2>/dev/null)"
  else
    # 冒號後直接接數字才算（"pid":null 不可誤抓後面欄位的數字）
    pid="$(grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' "$bj" 2>/dev/null | head -1 | grep -oE '[0-9]+')"
  fi
  if [ -z "$pid" ] || ! alive "$pid"; then
    cleanable=1
    stale_jsons="$stale_jsons $bj"
    echo "  [stale broker.json] $(basename "$(dirname "$bj")") — pid=${pid:-none} 已死"
  fi
done < <(list_broker_jsons)

if [ "$cleanable" -eq 0 ] && [ -z "${active_skips// }" ]; then
  echo "  乾淨：無孤兒 broker、無 stale broker.json。"
fi

# ---- check 模式：只報告（exit 契約見檔頭）----
if [ "$MODE" = "check" ]; then
  [ "$cleanable" -eq 1 ] && exit 1
  [ -n "${active_skips// }" ] && exit 3
  exit 0
fi

# ---- clean 模式：清理 ----
# 只有現役 skip、無可清項 → 不動手（誤殺防護已跳過現役 broker），視為完成（exit 0）
if [ "$cleanable" -eq 0 ]; then
  [ -n "${active_skips// }" ] \
    && echo "無可清項：僅有現役（或無法判定）split-brain broker 已跳過（見上），如確為孤兒請手動 kill。" \
    || echo "無需清理。"
  exit 0
fi

echo "-- 清理中 --"
# 2a-0) 先快照孤兒 broker 的子進程（app-server）：父進程一死子進程立即 reparent 到 launchd/init，
#       事後 pgrep -P 必回空——快照必須在 SIGTERM 之前
orphan_children=""
for bpid in $orphan_brokers; do
  orphan_children="$orphan_children $(pgrep -P "$bpid" 2>/dev/null || true)"
done
# 2a) 優雅收孤兒 broker：SIGTERM 觸發 broker 的 shutdown handler 連帶關掉 app-server 子進程。
#     kill 前重驗 argv 仍匹配 broker 特徵（防掃描→kill 間隙的 pid 重用）
for bpid in $orphan_brokers; do
  if alive "$bpid" && ps -o command= -p "$bpid" 2>/dev/null | grep -qE "$BROKER_PATTERN"; then
    kill -TERM "$bpid" 2>/dev/null && echo "  SIGTERM broker $bpid"
  fi
done
[ -n "${orphan_brokers// }" ] && sleep "$TERM_WAIT_SEC"
# 殘留就補 SIGKILL（broker 或其 app-server 沒被 handler 收乾淨時的保險；app-server 用開頭的快照）
for bpid in $orphan_brokers; do
  alive "$bpid" && kill -KILL "$bpid" 2>/dev/null && echo "  SIGKILL broker ${bpid}（TERM 未收）"
done
for cpid in $orphan_children; do
  # 快照到此處隔了 TERM_WAIT_SEC——SIGKILL 前重驗 argv 仍像 codex/app-server，防 pid 重用誤殺
  ccmd="$(ps -o command= -p "$cpid" 2>/dev/null)"
  case "$ccmd" in
    *codex*|*app-server*)
      alive "$cpid" && kill -KILL "$cpid" 2>/dev/null && echo "  SIGKILL 殘留 app-server $cpid" ;;
  esac
done

# 2b) 移除 stale broker.json 與其孤兒 socket 目錄（sessionDir）
remove_socket_dir() {
  local bj="$1" sdir=""
  command -v jq >/dev/null 2>&1 || return 0
  sdir="$(jq -r '.sessionDir // empty' "$bj" 2>/dev/null)"
  { [ -n "$sdir" ] && [ -d "$sdir" ]; } || return 0
  # plugin 以 mkdtemp(tmpdir, "cxc-") 產生 sessionDir；非此樣式（json 損壞/被改）絕不 rm -rf
  case "$(basename "$sdir")" in
    cxc-*) rm -rf "$sdir" && echo "  移除 socket 目錄 $sdir" ;;
    *)     echo "  [跳過] sessionDir 非預期樣式（${sdir}）— 不 rm -rf，請手動確認" ;;
  esac
}
for bj in $stale_jsons; do
  remove_socket_dir "$bj"
  rm -f "$bj" && echo "  移除 stale broker.json $(basename "$(dirname "$bj")")"
done
# 被 SIGTERM 收掉的孤兒 broker 也把它的 broker.json 一併清（下次會重生乾淨的）
for bpid in $orphan_brokers; do
  while IFS= read -r bj; do
    [ -e "$bj" ] || continue
    if command -v jq >/dev/null 2>&1 && [ "$(jq -r '.pid // empty' "$bj" 2>/dev/null)" = "$bpid" ]; then
      remove_socket_dir "$bj"; rm -f "$bj" && echo "  移除孤兒 broker.json $(basename "$(dirname "$bj")")"
    fi
  done < <(list_broker_jsons)
done

# ---- 清理後複驗（clean 的 exit 契約見檔頭：僅剩現役 skip 也算完成）----
echo "-- 複驗 --"
if "$0" check; then
  exit 0
else
  rc=$?
  [ "$rc" -eq 3 ] && exit 0   # 僅剩被跳過的現役 broker → 可清項已歸零，clean 完成
  exit 1                       # 仍有可清項 → 清理未竟
fi
