# handoff survey：active 清單加「最後更新時戳」並依它排序

- 日期：2026-08-19（經 `/deep-plan` 兩輪審查修訂）
- 目標檔案：`claude/skills/handoff/scripts/handoff-anchor.sh`（`emit_active`）
- 連帶：`tests/run.sh`、`docs/testing-contract.md` §13、`claude/evals/setup-sandboxes.sh`（h8）、
  `claude/skills/handoff/evals.md`（h8 敘述漂移）、`claude/skills/handoff/SKILL.md`（**僅** :133 的欄位列舉）、
  `STATUS.md`（決策／死路落點）、`docs/backlog.md`

> ⚠️ `~/.claude/skills` 是指向 `~/.dotfiles/claude/skills` 的 symlink，本次直接改主 checkout。
> 若改用 worktree，所有驗證（實跑 survey）必須走 worktree 絕對路徑，否則跑到的是主 checkout 舊版。

## 問題

多份 active 交接檔並存時，`survey` 的清單無法分辨先後：只印天數，同日產生的兩份完全平手；
R1「多份 → 列給使用者選」等於讓使用者盲選。

**這個情境的頻率是可量測的、而且已經量了。** archive 每份檔帶兩個時間座標——檔名前綴＝
`consume` 寫入的**消費時刻**，mtime＝**最後寫入**（`mv` 同檔案系統為 rename，mtime 原樣保留）。
`[mtime, consume]` 因此是該份 active 期間的下界區間，兩兩取交集即可重建並存窗。對 80 份
archive 逐對比對：不同 slug 的重疊窗 **23 對**，其中**兩份 created 同日（＝現行 `Nd` 完全平手）
的有 5 對**，例如：

```
2026-08-11 13:24..13:27  krepo-mops-major-news-deep-review vs kapi-gateway-first-real-kb
2026-08-15 13:56..22:57  krepo-split-announcement        vs kapi-gateway-first-real-kb
```

> 早先版本寫「無歷史快照可查、本計畫不宣稱它高」——過度保守，已由上述重建取代。
> 真正不可復現的只有當初那次終端輸出（`handoff-anchor-mtime.md` 在 active 與 archive 皆已不存在）。

## 資料來源選擇：mtime，不是 created

`created:` 已被 `emit_active`（:428）解析出來，但它**只有日粒度**：`cmd_anchors`（:117）寫的是
`date +%Y-%m-%d`。同日兩份必然平手——而那正是上面那個情境。

### created 的真實語意（先前寫反，已核正）

早先這份計畫寫過「`created` 是首次蓋錨點的時間，續寫不更新它」。**那是假的**：W2（`cmd_anchors`）
每輪都跑、`:117` 無條件輸出**當天**日期，W3 模板明令「W2 anchors 輸出原樣貼入」（`SKILL.md:76/85`），
所以續寫後 created 就是今天。實測 81 份真實交接檔（archive 80 + active 1），`created:` 與檔案
mtime 的**日期 0 份不一致**；同一 slug 跨輪的 `kapi-gateway-first-real-kb` 共 **11 輪**
（created 08-11 → 08-17），每一輪都等於該輪寫檔日，11/11 全中。

**結論不變、理由收窄**：created 恆等於「最後一次蓋錨點的日期」，所以 mtime 相對 created 買到的
**只有同日的時分解析度**。這一條就足以支撐本計畫，不需要（也不能用）「續寫不更新 created」那個說法。

⚠️ **這個核正必須貫穿到所有衍生文字**：`docs/testing-contract.md` §13 的新段落**不得**出現
「created 不隨續寫更新」或等價說法。

### 明確不改 `created:` 格式

「改 created 帶時分」是另一條路，**不走**：既有交接檔全是 date-only，改格式會讓新舊混格，
`date_to_epoch` 的 `date -j -f "%Y-%m-%d"` 要跟著擴出第二種格式；而 `verify` 的 EXPIRED
判定只需日粒度，這條擴充買不到任何東西。→ **created 與 age／EXPIRED 判定一律不動。**

## 顯示格式

時戳整段取自 mtime，並加字標明來源，避免與 age（來自 created）混淆：

```
active: krepo-sync-daily-rollout.md — 更新 2026-08-18 22:36 — 0d — OK
  path: /Users/jjshen/.claude/handoffs/krepo-sync-daily-rollout.md
  title: krepo 每日同步 rollout
```

- 時戳 = mtime（最後寫入），`0d` = 由 `created` 算的年齡，`OK`/`EXPIRED` 判定不變。
- 缺值印 `更新 未知`，**不用 `—`**：欄位分隔符就是 `—`，`— 更新 — — 0d —` 讀起來像分隔符重複
  （`emit_worklines` 對無前綴檔印的 `最近 —` 確實也是 U+2014（`parse_archive_entry` 設 `PA_DATE="—"`），
  但它在**行尾**故不刺眼；這裡在行中）。

### 三條輸出分支全部要定義

`emit_active` 現有**三**條輸出路徑，計畫先前只規範了第一條。三條都在改動範圍內：

| 分支 | 現況 | 改後 |
|---|---|---|
| created 可解析（:432） | `active: X — 0d — OK` | `active: X — 更新 <ts> — 0d — OK` |
| created 無法解析（:434） | `active: X — created 無法解析 — SUSPECT` | `active: X — 更新 <ts> — created 無法解析 — SUSPECT` |
| 零份 active（**:442**） | `active: none` | **不變**（但見下方「重構陷阱」） |

SUSPECT 分支現況 `grep -rn SUSPECT tests/ docs/ claude/` **只命中該行本身**——零測試、零文件。
不明定的話會變成實作者臨場決定，且怎麼決定都不會被測到。

## 排序

`active:` 依 mtime **新到舊**；tie 時以檔名升冪穩定排序。

> tie-break 防的是 **`sort` 在同鍵時不保證穩定**（GNU sort 預設不穩定），**不是** glob 順序漂移——
> bash 的 pathname expansion 是依 locale 的確定性排序，重跑之間不會變。`-k2,2` 正好解掉前者。

實作要點：

- 先蒐 `<mtime>\t<path>` 兩欄 → `LC_ALL=C sort -t$'\t' -k1,1rn -k2,2` → 再逐行讀出算
  created/age/title。**`LC_ALL=C` 不可省**：tie-break 走的是字串比較，而 glibc 的 `en_US.UTF-8`
  在第一層忽略連字號等標點、與 BSD 不同；repo 的已知地雷條款要求腳本只用 POSIX 確定性子集，
  量字串時明寫 locale 讓兩平台一致（`docs/backlog.md:67` 另記著「Linux 側分支無人驗」這個盲區）。
- **mtime 取不到一律以 `0` 佔位，不得留空**：tab 是 IFS whitespace，空的第一欄會被
  `IFS=$'\t' read` 吃掉、讓路徑整批推移到 mtime 欄（emit_worklines 的坑 (2) 同型，
  已記在腳本 :487 註解）。佔位 `0` 順帶讓這類檔排到最後。
- title 在迴圈內再讀，**不塞進排序欄位**——多一欄就多一個空欄位推移的機會。

### 重構陷阱：`found` 旗標與 `active: none`

改的正是設定 `found=1` 的那段（:423 / :426 / **:442**），而 `active: none` **目前零測試覆蓋**
（`grep -rn "active: none" tests/run.sh` 無輸出），壞掉會全綠通過。它是 R1 的硬依賴
（`SKILL.md:135`「零份 active 不等於沒有交接檔」）與 eval H3 的判定證據（`evals.md:377`）。

兩個必須同時避開的形狀：

- **`... | sort | while read`** → `found` 落在 subshell，迴圈結束後恆為 0 → 列完全部項目後
  **再多印一行 `active: none`**。（同族坑 repo 已記過：`prune_archive`（:456）用
  `< <(find …)` process substitution 而非 pipe，正是為此。）
- **`while … done <<< "$rows"` 且 `rows` 為空** → herestring 仍會產生**一次空行迭代**
  （實測 `rows=""; while IFS= read -r l; do echo "ITER:[$l]"; done <<< "$rows"` → 印一次
  `ITER:[]`），`found` 被誤設為 1 → `active: none` 反而**消失**。

→ 採用形狀：`rows` 為空時**直接走 none 分支、不進迴圈**；進迴圈者一律 `[ -n "$mt" ] || continue`。

### 可攜性（雙平台）

repo 既有慣例，順序不可顛倒（`claude/scripts/session-pull-check.sh:97`、
`claude/skills/deep-review/scripts/codex-runtime-hygiene.sh:105-107`——後者記著「順序反過來
GNU 的 `stat -f %m` 會印掛載點」）：

```sh
mt="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)" || mt=0
case "$mt" in ''|*[!0-9]*) mt=0 ;; esac     # 非純數字（stat 異常／印出掛載點）
```

**那道純數字守門要一起搬**：先例 `codex-runtime-hygiene.sh:108` 就有它，存在理由正是同段註解
描述的「GNU `stat -f %m` 印掛載點」這條非數字輸出路徑。少了它，`[ "$mt" -gt 0 ]` 拿到非數字會
讓 bash 噴 `integer expression expected` 到 stderr——而 survey 是 W1／R1 開場的純資訊路徑，
那行雜訊會直接出現在使用者眼前。

格式化沿用 `claude/skills/deep-review/scripts/review-anchor.sh:71-73` 的
`date -r <epoch>` / `date -d "@<epoch>"`。⚠️ 該處實為**三段**（第三段 `|| echo "$1"` 印原始 epoch），
**本計畫只取前兩段**：sentinel 已在前面攔掉缺值，兩段都失敗代表 `date` 本身異常，此時印
`更新 未知` 比印一串 epoch 誠實。

### `0` 是 sentinel，不是合法 epoch

**不可以**把 `0` 丟進格式化函式再靠它失敗——`date -r 0 +'%Y-%m-%d %H:%M'` 在 macOS
**成功**回 `1970-01-01 08:00`（rc=0），GNU 側 `date -d "@0"` 同樣成功。照「兩者都失敗才印缺值」
寫，永遠印出 1970 而不是缺值。→ 顯示端先判 sentinel：`[ "$mt" -gt 0 ]` 為真才格式化，否則 `更新 未知`。

**這條分支實務上不可達**（`[ -f "$f" ]` 已通過，`stat` 幾乎不可能失敗；只有 glob 與 stat
之間的刪除競態），故：**不列入驗收準則、不寫測試**（不可執行的驗收比沒有更糟），改在腳本
註解標明它是防禦碼與不可達的理由。保留它的唯一原因是**空值會造成欄位推移**——那比印 1970 更糟。

## 不改什麼

- `created:` 欄位格式、`age_days_from_created`、`EXPIRE_DAYS`、`verify` 的 EXPIRED 判定。
- `emit_worklines` / `emit_predecessor` 的排序：archive 續用**歸檔前綴時戳**。
  理由**不是**「`mv` 對 mtime 的行為不保證」（那不精確——POSIX `mv` 保留 mtime，實測 archive 檔
  的 mtime 也確實是歸檔前的最後寫入）；真正的理由是**語意不同**：歸檔前綴＝**消費時刻**，
  mtime＝**最後寫入**，audit trail 要的是前者。
- `prune_archive` 先於 archive 衍生輸出的次序、survey 的四段輸出順序。
- **SKILL.md 不補「依最後更新時間排序」那句**——見下節，它與「補欄位列舉」是兩件事。

### SKILL.md：補列舉、不補排名（兩件事，分開論證）

早先版本把兩者併成一句「不改 SKILL.md，格式權威在腳本檔頭」。**那個前提是假的**，兩邊都不成立：

- `SKILL.md:133` **現在就在**列舉 active 行的欄位組成（「每份 `active:` 會附 `path:`…與 `title:`…」）
  ——加了時戳欄之後它就是**不完整的列舉**。
- `handoff-anchor.sh:5-22` 的檔頭 usage **完全沒有**定義 active 行格式（只寫「active 清單」四個字）。
  所以下面第 5 項不是「更新既有權威」，是**建立**一個尚不存在的權威。

拆開後：

| 動作 | 做不做 | 理由 |
|---|---|---|
| :133 補上時戳欄（純描述性列舉） | **做** | 該處本來就在列舉欄位，漏一欄是既有敘述變得不完整，與行為誘因無關 |
| 補「依最後更新時間新到舊排序」 | **不做** | R1 現行契約是「多份 → **列給使用者選**」；給出排名可能誘使 agent 直接挑第一份。**這是行為誘因的改動**，依 repo 既有決策（`STATUS.md:172-173`）要成對實驗才動，而本次沒有觀察到相關失效 |

## 刻意不做（本次；記 backlog）

- **錨點 repo 欄（`repos: dotfiles, krepo`）**——辨識力可能不錯，但成本被低估：
  `tests/run.sh:3079-3080` 的「survey/list 逐字等價」用的是**寫死的前綴白名單**
  `^(active: |  path: |  title: )`，新增的 `  repos: ` 子行**不在名單內、不會被比對**，
  等於新欄位天生豁免於那道 gate。要做就得連同「白名單是寫死的」這個 gate 缺陷一起處理。
  → 依 `docs/backlog.md` 既有章節格式記一條，本次範圍收斂在 mtime 時戳＋排序。

## 連帶改動

1. **`tests/run.sh:2934`** —— `active: fresh.md — 0d — OK` 是**不錨定的子字串**斷言，格式改了會紅。
   更新時：用 pattern 吃掉時戳值（別把當下時間寫死），但**`0d` 與 `OK` 兩個欄位仍必須被斷言**——
   最省事的改法（`grep -q "active: fresh.md"`）會照樣全綠，那格從此不再守 age 與 flag。
   - `:3081` 的 `^active: old.md — .* — EXPIRED` 與 `:3078` 的「survey/list 逐字等價」
     不受影響（前者 `.*` 吃得下、後者兩邊共用 `emit_active`，且本次不新增子行）。
2. **新增守門測試**（接在 survey 區段，**用獨立 fixture 目錄**——沿用 `$SV` 會改變
   `:3074-3082` 那批既有斷言所依賴的 active 集合，§13 已記過同型教訓）：
   - **排序**：造三份 active，`touch -t`（BSD/GNU 共通 `[[CC]YY]MMDDhhmm`）給不同 mtime，
     斷言輸出順序為新→舊。**mtime 順序必須與檔名字典序相反**，否則現行的 glob 順序也剛好答對、
     斷言等於虛設（同 §13 記過的 `bar-foo` 教訓）。
   - **時戳欄**存在且形如 `更新 YYYY-MM-DD HH:MM`。
   - **SUSPECT 分支**也帶時戳（現況零覆蓋）。
   - **`active: none`**：目錄存在但無 `*.md` → 恰好印一次 `active: none`、且不得同時列出項目
     （現況零覆蓋，兩個 subshell/空迭代陷阱都靠它擋）。
   - **tie-break**：兩份同 mtime → 檔名升冪。⚠️ **這條在現行 code 下本來就綠**
     （glob 即字典序），它是**回歸護欄、不是紅先行測試**。
3. **`docs/testing-contract.md` §13** 加一小節：為何排序用 mtime（**日粒度不足**，不得寫成
   「created 不隨續寫更新」）、`found` 旗標的兩個陷阱、排序 fixture 必須與字典序相反、
   `0` 是 sentinel 且該分支不可達故無測試。**空欄位推移寫成「同一條坑的第二個觸發點」**，
   不新增獨立條目——§13 已記過該坑（`:320-321` 一帶），兩處各記一次會漂移。
4. **`claude/evals/setup-sandboxes.sh`（h8）** —— `stale-tej-export.md` 是唯一硬編過去日期的
   active fixture（`created: 2026-06-20`，:773-799），但由建置當下寫出、之後沒有 `touch -t`
   （`grep -n "touch -t" setup-sandboxes.sh` 無輸出）。加了 mtime 欄後那行會變成
   `— 更新 <今天> — 60d — EXPIRED`：「剛更新」與「60 天前過期」並列。
   → 寫檔後補 `touch -t 202606201200` 對齊。其餘沙盒用 `$(date +%Y-%m-%d)`，不受影響。
   ⚠️ **「這會削弱 h8 鑑別力」是未量測的推論**：h8 的 oracle（`evals.md:229`）只要求收尾報告
   列出該檔為 EXPIRED 並建議處置，未涉及 mtime；「並列會讓 agent 改判」沒有跑過。修法成本近零
   且無害故仍做，但**不宣稱它修好了一個已觀察到的失效**。
5. **`claude/skills/handoff/evals.md:224`** —— h8 的 setup 敘述硬編「**47 天前**的
   `stale-tej-export.md`」，以今日算是 60 天（`:379` 的歷史紀錄寫 50d）。這是既有漂移、非本次造成，
   但本次是唯一一次「手已經伸進 h8」的機會，順手收：改成不綁絕對天數的寫法。
6. **`claude/skills/handoff/scripts/handoff-anchor.sh` 檔頭 usage**：**新增** active 行的格式定義
   （目前不存在），含時戳欄與 mtime 排序。這是為了讓「格式權威在腳本檔頭」這句話成立。
7. **`claude/skills/handoff/SKILL.md:133`**：欄位列舉補上時戳欄。**只補列舉、不寫排序語意**（見上節表）。
8. **`STATUS.md`** —— 本計畫產生的決策與死路在 diff 裡留不下痕跡，依 repo 的 authority 表
   （`AGENTS.md:41`：decisions/dead ends 的權威是 `STATUS.md`，`docs/plans/*.md` 是 write-once
   snapshot）與 kernel 的記錄條款，要落到「關鍵決策(附理由)」／「死路」節。至少四條：
   - 排序改用 mtime、**且不改 `created:` 格式**（零 diff，理由：verify 只需日粒度）
   - **撤回 SKILL.md 的排序句**（零 diff，理由：行為誘因需成對實驗）
   - archive 續用歸檔前綴而非 mtime（語意：消費時刻 vs 最後寫入）
   - `0` sentinel 分支不可達、刻意不寫測試
9. **`docs/backlog.md`**：記「repos 欄 + 等價 gate 白名單寫死」，依該檔既有章節格式。

## 驗收準則

- `bash tests/run.sh` **exit 0**（直接看退出碼，不接 `| tail`——pipeline 會吃掉失敗）。
  起點是綠的（改動前 PASS=1046 FAIL=0），故 exit 0 是有效 oracle。
  改了 `.md` 內容／節名，交叉引用 gate 必須一起綠。
- **多份排序的驗收由自動化測試負責**（連帶第 2 項），**不靠真實目錄**：本機
  `~/.claude/handoffs/` 目前只有一份 active，跑 survey 只印一行、無從確認排序。
- **煙霧測試不對真實目錄跑**：`cmd_survey`（:582）**無條件先跑 `prune_archive`**，它對
  `archive/*.md` 且 `-mtime +30` 的檔案 `rm -f`——那些檔不在 git、machine-local、**刪了回不來**。
  實測目前到期數為 0，但最舊一份（`20260720-233639-…`）距門檻**不到一天**，這條驗收若拖過一天
  再做就會靜默刪掉一份真實 archive。→ **`cp -Rp ~/.claude/handoffs <tmpdir>` 後對複本跑**
  （⚠️ **`-p` 不可省**：`cp -R` 不保留 mtime，複本的時戳全變成複製當下，煙霧測試會量到
  一個假的值卻看起來正常——實地踩過一次）
  （`HANDOFF_DIR=<tmpdir>` 或 `survey <tmpdir>`），確認不炸、單份仍正常、`path:`/`title:` 仍跟在
  對應行下、`workline:` 與 `predecessor:` 區段不受影響。
- h8 沙盒重建後，`stale-tej-export.md` 那行的時戳為 `2026-06-20 12:00`、仍標 EXPIRED。

## 執行順序

1. 先改測試（排序／時戳／SUSPECT／`active: none`）**並更新 `:2934`** → 跑 `tests/run.sh`，
   **確認紅在預期處**：排序、時戳、SUSPECT、`:2934` **四**格會紅；`active: none` 與 tie-break
   兩格現況即綠（回歸護欄）。
2. 改 `emit_active`（三條分支＋`found` 形狀＋sentinel＋純數字守門）。
3. 跑 `tests/run.sh` 轉綠。
4. 補腳本檔頭 usage、`SKILL.md:133`、`docs/testing-contract.md` §13、`STATUS.md`、
   `docs/backlog.md`，再跑一次（xref gate）。
5. 改 h8 fixture 的 `touch -t` 與 `evals.md:224` 的天數敘述。⚠️ `setup-sandboxes.sh` **沒有
   選擇性建置入口**——`make_h8` 與其餘約 40 個 `make_*` 一起無條件呼叫（:2614），腳本只吃
   `[輸出目錄] [實例名]`。要嘛整批重建到暫存目錄，要嘛 `source` 後單跑 `make_h8`；擇一並記下。
6. 對真實目錄的**複本**跑一次 survey 煙霧測試（見驗收準則，不可對本尊跑）。

---

## 附錄：其他候選輔助資訊

判準只有一條——**能不能降低「多份 active 時選錯那份」的機率**。降低不了的一律不加
（清單每多一行，真正有辨識力的那行就被稀釋一分）。

### 刻意不做（記下理由，避免日後重新提案）

- **錨點 repo 欄**——見上方〈刻意不做（本次；記 backlog）〉。不是判它沒價值，是它綁著一個
  gate 缺陷，值得單獨一輪。
- **`created ≠ mtime` 時附註「建於 MM-DD」**——先前列為「建議一併做」，**撤除**：既然
  created 每次寫檔都刷新，兩者的**日期永遠相同**，這個附註在 81 份真實檔上一次都不會觸發；
  真的觸發代表該檔被 W2/W3 以外的方式改過（手改／複製），語意與「已續寫過」**相反**。
  按附錄自訂的判準，它被自己的判準刷掉。
- **`dirty=N` 提示**——錨點裡有這個欄位，但它是**蓋錨點當時**的計數。survey 階段原樣印出，
  使用者會當成現況讀；而現況要靠 R2 的 `verify` 才問得到。**過時的數字比沒有數字更糟**，
  它正好長得像可信事實。dirty 的提醒點維持在 W2／R2，不前移。
- **錨點新鮮度（FRESH／DRIFTED／DIVERGED）**——最有價值，但要對每份 active × 每個 repo 跑 git。
  survey 是 W1／R1 開場的純資訊快路徑（**一律 exit 0**），塞進 git 呼叫等於引入
  「會慢、會因 repo 不存在而部分失敗」的路徑，還要決定失敗時 exit code 怎麼辦——
  那是 `verify` 的職責與 exit 契約，不重複實作。**R1 選定一份後緊接就是 R2**，資訊晚一步不痛。
- **這條 slug 的輪數（第 N 輪）**——同一份 survey 輸出裡 `workline:` 已經有輪數與最近日期，
  搬到 `active:` 是複製而非新資訊，代價是 `emit_active` 要去讀 archive（目前完全不需要）。
- **檔案大小／行數**——與「是哪條工作線」無關。
- **同分鐘並存時的「時間相近，請確認」警語**——本次仍不加，但先前駁回的理由（「tie-break 已定為
  檔名升冪、順序穩定」）**答非所問**：tie-break 只在 epoch **完全相同**時生效；epoch 差幾秒、
  分鐘相同時，兩行時戳一字不差而順序由 mtime 決定，使用者**看不出誰新**。實測這不是假想
  （`krepo-split-announcement` 13:55 vs `kapi-gateway-first-real-kb` 13:56，只差一分鐘）。
  真正的理由是：要解就該提高**顯示精度**（秒），加警語只是把判斷推回使用者。
  → 顯示精度到秒列為後續可選，本次維持分。

### 順帶檢查（不改，但實作時確認）

- `path:` 與 `title:` 兩行必須跟著各自的 `active:` 行一起移動——排序改的是外層迴圈次序，
  縮排子行若在迴圈外組裝就會與父行錯配。這是排序測試要順便釘住的第二件事。
