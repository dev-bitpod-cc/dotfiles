# 已知地雷 — 完整案例與診斷

`~/.claude/CLAUDE.md`「已知地雷」各條的**實地事故、負面結果、鑑別法與修復序列**。
規則本體在 CLAUDE.md（always-on），本檔是**踩到之後**才需要讀的那一半。

## 分工

| 問題 | 權威 |
|---|---|
| 這個寫法安不安全、該怎麼寫 | `~/.claude/CLAUDE.md`「已知地雷」 |
| 為什麼知道、當時怎麼爆的、試過什麼沒用、怎麼診斷與復原 | **本檔** |

**本檔是延遲載入的。** 凡是「動手寫的當下就必須知道」的判準留在 CLAUDE.md ——
規則不在 always-on context 就不生效。本檔存在的目的是**省下重查與重測的時間**，
不是承接規則。

---

## heredoc / `--body` 的反引號命令替換

### 2026-08-07 實地：`git push` 真的被執行

用 `python3 - <<PY` 產生 eval prompt，文字裡有 `` `git push` `` 與 `` `gh pr` ``
兩個說明用的行內 code。結果：

- **`git push` 真的推了一條 branch 上 GitHub**
- `gh pr` 的說明文字被塞進產出的檔案
- 變數展開位置留下空白

### 同一天的誤判（更貴的那半）

當時把「用 heredoc 灌一個含反引號的**檔案**」也當成同一個雷，據此**改了三處程式碼**，
還把錯誤結論寫進 commit / PR / dossier **四處**。

實測結論：`$(cat 某檔)` 注入進來的內容**不會**被執行 —— 命令替換的結果不重新掃描。
判準只管**反引號是否寫在 body 字面**。

> 這個誤判的形狀值得記住：「符合地雷的形狀」≠「就是那個地雷」。沒實測就別把重構寫成修 bug。

### gate 的判準細節

`tests/heredoc-gate.awk`：delimiter 未加引號 + body 字面含反引號。追蹤 quoted heredoc
的進出、排除 `<<<` 與註解行。有 GREEN fixture 釘住「`$(cat …)` 不得誤報」——
曾為它加過一條規則，會把每個用 heredoc 灌檔的正常寫法判紅，已撤銷。

### `--body` 版沒有 gate

`gh pr create --body "…"`、`gh issue create --body`、`gh release create --notes`、
`git commit -m "…"` 都是同一個根因（shell 雙引號語境內的反引號一律是命令替換）。

真要行內給值：`--body "$(cat <<'EOF' … EOF)"` —— quoted delimiter 讓 heredoc 全文字面，
命令替換只負責搬運。

---

## macOS 內建 CLI

### 為什麼是凍結的

Apple 因 GPLv3 停更：bash 3.2、rsync 已換成自寫的 openrsync、BSD awk 的 `length`
不分 locale 一律數 **bytes**。

### `timeout` 的 exit 127 陷阱（2026-08-09）

`timeout` / `gtimeout` 在 macOS **兩者都不存在**（coreutils 才有，當天實測兩者都空）。

危險不在缺工具，而在 **`command not found` 是 exit 127**：測試裡包一層 `timeout`
就變成整段沒跑、卻只回一個 127，被 grep 過濾後**看起來像通過**。當天據此誤判
「某條斷言是虛設的」，實際那次根本沒執行。

---

## SIGPIPE + pipefail

### 兩處實地

1. **krepo `scripts/backup/lib/dest_r2.sh`** —— 零備份保底清單比對。
2. **dotfiles `ship-state.sh`** —— dossier 簽章與 Session Log 偵測。115KB 的 STATUS.md
   被誤報「簽章不符」，而該 flag 的處置是「停下、勿當 dossier 改」——**等於整份檔案被拒絕處理**。

### 為什麼守門測試的命中點必須放前段

放檔尾則 printf 早已寫完、SIGPIPE 不觸發，斷言形同虛設。實測：檔尾版突變仍全綠。

---

## 裸 `wait`

### 實測（2026-08-10）

`(exit 7) & (exit 0) & wait` → `rc=0`，`set -e` 下同。

### 實地：G7 成對實驗

`claude/evals/contract-evals.md` 的 G7 runbook 用裸 `wait`，任一臂認證／網路失敗
都會讓「baseline vs 修後」的比較**拿半份資料成立**。

### 為什麼不要用 `declare -A` 存 pid

macOS 系統 bash 是 3.2、沒有 associative array —— 那個改法會在**最可能被貼進去的
那個 shell** 上當場壞掉。純量寫法在 bash 3.2 與 zsh 5.9 都實測可抓到失敗。

---

## `|| echo <fallback>` 家族

### 實地：14 台巡檢只壞一半（2026-08-07）

巡檢 14 台 rc 狀態的腳本用了 `n=$(grep -c PAT f || echo 0)`：

- Linux 10 台因為 `alias sysup` 確實存在（grep 命中、exit 0）→ 正常
- macOS 4 台找不到 → 觸發雙行 `0\n0`

**同一支腳本只有部分主機的輸出壞掉**，第一眼會誤判成「遠端環境差異」而去查錯方向。

### 第二種形狀的實地（2026-08-09）

`ensure-ssh-config.sh` 的 bytes 比對：`bytes=$(wc -c < 讀不到的檔)` → `bytes=""` →
`$((hdr + bytes))` 直接算成 `hdr`，於是「產出完整性」自我檢查自己通過，
**放行了一個只有標頭的殘缺 ssh config 並覆蓋原檔**（守門測試當場抓到）。

---

## cask 升版卡死（Gatekeeper / syspolicyd）

> **先看結論**：復發時直接 `brewfix`。以下是機制與已排除的路，**不必重查**。

### 觸發者是 brew 自己

codex cask 帶 `generate_completions_from_executable`（`brew info --cask codex` 的
Artifacts 段可見），其 `install_phase` 對 **bash/zsh/fish 各 exec 一次**剛解壓、
仍帶 `com.apple.quarantine` 的 binary 來產生 completion。首次 exec quarantined binary
→ 進入 Gatekeeper 首次核可流程。

畫面停在 `Linking Binary` 是因為那是**前一個** artifact 的訊息。brew 的 `rescue => e`
只攔例外、攔不住 hang，所以 brew 自己也不會跳過。

**不是每次發作** —— 只在該 cask 實際有新版時走這條
（`Caskroom/<cask>/<old>.upgrading` 殘留＝那次被中斷的證據）。

### 確切觸發條件未知，別再花時間重測

已知：

- **(a)** 對話框「〈名稱〉是一個從網際網路下載的 App。確定要打開嗎？」確實會出現並等人按
  —— 2026-08-07 經 SSH 跑 `allup` 時實地確認（Jump Desktop 連進 console 才看到，
  SSH session 結構上看不到 GUI 對話框）。
- **(b)** **無可見對話框也會卡** —— 在本機 console 開 terminal 跑 `brewup` 也遇過卡在
  `Linking Binary`、對彈窗無印象。

故 **`ssh` 不是必要條件，「去 console 按掉對話框」也不是可靠處置**。

### 2026-08-07 的負面結果（省下下次的重測）

事後想重現：把**同一份** binary 複製到全新路徑、在 SSH session 下帶 quarantine 立即執行
—— **3 秒正常完成，完全不卡**。

以此逐一排除：

| 假設 | 結果 |
|---|---|
| SSH session | ✗ |
| 首次評估（全新路徑） | ✗ |
| quarantine 存在且無 `0x0040` | ✗ |
| 檔案大小 271MB | ✗ |
| notarization 與簽章差異 | ✗（同機的 agy 162MB 各項條件相同卻從不卡） |

合理解釋是 **Gatekeeper 的「成功評估結果」以 cdhash（內容）為 key 快取，而「卡死的
pending 記錄」才以路徑為 key** —— 兩者不衝突，但意味著**同版本內容事後永遠重現不了**，
要重現只能等該 cask 真正出新版。

### 第二段病灶：syspolicyd 以「完整路徑」為 key

該路徑上的掃描記錄一旦卡在未完成狀態，之後每次 exec 都在 kernel 層等一個永遠不回來的結果
（該路徑在 syspolicyd log 中全程無任何評估紀錄，對照組則有完整 `Updating cached scan`）。

**鑑別**：

- `sample <pid>` 卡在 `_dyld_start + 0`
- `lsof -p <pid>` 只有 dyld + binary 本身、**一個 dylib 都沒載入**
  （＝程式碼一行未跑，與 config／auth／sqlite／網路全無關，`env -i` 也一樣卡）
- **同目錄只換檔名就能跑 → 確認 key 是路徑**（換 inode、`touch` 改 mtime 皆無效，別白費）

### 修法

`brewfix`（`scripts/brewfix.sh`；預設唯讀診斷，`brewfix --fix` 才動手）：
kill 卡死 process → `sudo killall syspolicyd` → 清 `*.upgrading` 殘留 → 複驗。

手動等價：`sudo killall syspolicyd`（launchd on-demand 重生，之後 `launchctl list`
顯示 `-  0` 是正常的）＋清 `Caskroom/<cask>/<old>.upgrading`
（**`brew cleanup` 只清 cache 的 tar.gz、不碰它**）。`brew reinstall` 路徑不變、多半無效。

### 三條沒有用的路，別再走

1. 「更新後先在終端手動跑一次讓它自然跑完」—— brew 在你之前就 exec 過了。
2. `--no-quarantine` —— **Homebrew 6.x 已移除該旗標**（install/upgrade 都拒絕，
   原始碼無此識別字），且原本就屬不必要的安全弱化。
3. 期待 Homebrew 內建的核可繼承（`Quarantine.inherit_user_approval!`）幫忙 ——
   `cask/upgrade.rb` 兩處都是 `artifacts.grep(Artifact::App)`，**只服務 `.app` bundle**，
   binary cask 拿不到，所以 `USER_APPROVED_FLAG (0x0040)` 永遠不會被設上。

**復原是實證有效的，預防手段目前都不是。**

---

## 腳本在自己內部 `git pull`

### 實地（2026-08-09）

`brewup.sh` 新增 ensure helper 區塊後，落後的機器**必須跑兩次**才部署到 helper
（第一次跑舊版）。`allup` 會讓這件事在整個機隊同時發生。

### 兩種換檔方式，症狀完全不同

| 換檔方式 | 機制 | 症狀 |
|---|---|---|
| `git checkout`（unlink + 新建，換 inode） | 執行中的 bash 握著舊 inode | 跑完**舊版**邏輯，無聲 |
| `>` 原地截斷（同 inode，如 `curl -o`、`cat >`） | 從舊 offset 讀到 EOF | **整支腳本靜默中止在中途** |

---

## worktree 內驗證自家 skill

### 實地（2026-08-06）

於 worktree 修 ready4quit 的 `git-hygiene.sh`，eval 必須把腳本路徑**手動覆寫成
worktree 絕對路徑**才測到新版。

### 為什麼看不出來

`~/.claude/skills` → `~/.dotfiles/claude/skills`（主 checkout）；`~/.codex/skills`
由 `ensure-codex-skills.sh` 建立，同一形狀。測試照樣全綠，因為它測的是舊檔 ——
與「只有乾淨 clone 看得見」的誤收同一類，人工看 diff 抓不到。

`tests/run.sh` 以 `$ROOT` 解析故不受影響；坑只在 **skill body／eval／手動呼叫**這三處。
