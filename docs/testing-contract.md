# 測試契約（testing contract）

`./tests/run.sh` 各 gate 的**判準、反例與設計理由**。改 gate、看不懂某條斷言為什麼那樣寫、
或想放寬某個判準時看這裡。

## 權威分工

| 問題 | 權威 |
|---|---|
| 何時必跑、以什麼判綠紅 | root `CLAUDE.md`「測試」與 `AGENTS.md`「Repo specifics」 |
| 某個 gate 為什麼這樣判、放寬會壞掉什麼 | **本檔** |
| 門檻數值本身 | 各腳本內的常數（如 `ship-state.sh` 的 `DOSSIER_MAX_*`），本檔不重述數字 |

**本檔是延遲載入的**——只有真的要改 gate 時才會被讀到。凡是「不改 gate 也必須遵守」的
約束（不放寬 pattern、必跑時機、以 exit code 判綠紅）留在 `CLAUDE.md`，**不要搬進本檔**：
規則不在 always-on context 就不生效，這在 `claude/skills/handoff/evals.md` 的 H6 首跑實測過
（同一輪 repo-a 的 commit 落在 main、repo-b 才開 branch，因為規則只存在於延遲載入的檔案裡）。

## 為什麼獨立成檔

2026-08-11 從 root `CLAUDE.md` 拆出。當時該節 15,287 bytes（全檔 51.5%）且是**單一
15,123-byte 行**；對照本 repo 自己的 dossier 門檻（`ship-state.sh` 的 `DOSSIER_MAX_BYTES`
與 `DOSSIER_MAX_LINE_BYTES`，後者註解明寫「正常換行段落 <300B」），受管的 `STATUS.md`
合規、沒人管的 `CLAUDE.md` 全檔超標 21%、單行超標 15 倍。成本落在每個 session：
root `CLAUDE.md` 與全域 `claude/CLAUDE.md` 合計 58,681B 恆常載入。

## 通則

- **exit 0/2 契約**（凡獨立掃描器皆適用）：內容問題走 stdout、掃描器自身失敗走 **exit 2**。
  `tests/run.sh` 是 `set -uo pipefail`、**無 `set -e`**，掃描器死掉的空 stdout 會被判成「乾淨」，
  gate 於是靜默變成永遠綠。兩者不可混用。
- **掃描器要自檢**：RED/GREEN fixture 是必要的——掃描器被改壞而恆不匹配時，對真實檔案的
  空輸出一樣長得像「通過」。
- **gate 誤報的代價是逼人改壞寫法以求過測**，所以收窄判準時寧可放掉 false negative，
  也不要製造 false positive。

---

# 全域 gate（掃全 repo）

## 1. shellcheck gate

涵蓋 `scripts/`、setup 腳本、`claude/skills/*/scripts/` 與其 `lib/`、`shell/functions.sh`、
以及 **`claude/evals/*.sh`**。

shellcheck 以 `-P SCRIPTDIR` 解析 `source=`，故 lib 的相對寫法跨 cwd 都成立。

evals 於 2026-08-08 補入四個 gate——**納入時它零 findings**。便宜的守門要趁乾淨時加，
等長歪再加就得先還債。

## 1b. 全形標點吞變數名 gate

`"（exit=$rc）"` 會被 bash 把全形字元併入變數名 → `set -u` 下噴 `rc）: unbound variable`。
繁中訊息幾乎必踩，且**只在錯誤路徑觸發**、正常測試照樣全綠。一律要求寫 `${var}`。

## 1c. unquoted heredoc 反引號 gate

掃描器：`tests/heredoc-gate.awk`。

**判準**：delimiter 未加引號 **+ body 字面含反引號** → 那段會被 bash 當命令替換**真的執行**。
掃描器追蹤 quoted heredoc 的進出、排除 `<<<` 與註解行，並以 RED/GREEN fixture 自檢。

**判準刻意只管字面**：`$(cat 某檔)` 注入的反引號不會被執行——命令替換的結果不重新掃描
（2026-08-07 實測）。曾為它加過一條規則，會把每個用 heredoc 灌檔的正常寫法判紅，
**已撤銷**並留 GREEN fixture 釘住。

## 1d. 交叉引用完整性 gate

掃描器：`scripts/doc-governance.py audit --check xref`；`tests/xref-gate.py` 只是 compatibility wrapper。
抽出「見〈路徑〉〈節名〉」句型逐條驗證，**把「唯一權威」這個
原本純靠散文的不變式換成機檢**——指標一斷，「勿憑記憶重組」就只剩重組一途。首次掃描即抓出
1 條真死指標與 2 條指向 repo 內雙份同名檔的基名引用。

- **source 句型**：掃「backtick path + 節名」、「裸 path + 節名」，以及「見 + 本檔節名」（含上／下方別名）。
  `.sh` 只掃註解行，避免把 heredoc fixture 當現行指標。本檔指標只認 heading，不用 body
  fallback 自我滿足。

- **source 與 target 的非正文排除刻意不對稱**：source 排 fenced、**掃** HTML comment
  （圍欄內是示範怎麼寫，註解裡卻是真的要你去看——krepo 的量體豁免指標就寫在檔首 comment）；
  target 的 heading 與 body **兩者皆排除**（註解掉的模板與圍欄裡的範例標題都不構成「該節存在」的證據）。
- **節名比對**用 normalize 後前綴（heading 可帶括號補充），不中則退一步比對**逐行非 heading**內文
  （引用一條規則而非節名是合法寫法）——整檔併成一串會讓兩行的尾首拼接成假命中。
  normalize 須剝 inline 修飾，否則原文帶 `**` 的規則引用被判紅。
- **normalize 後 < 2 字即 blocking**：空字串是任何字串的子字串，恆假綠。
- **不做全 repo 同名搜尋**：兩份 `reviewer-brief.md` 是「review 刻意隔離」下故意不同的兩套判準，
  模糊搜尋會指到錯的那份而毫無警訊。
- **fence 偵測**明訂為已驗證的 CommonMark 子集（closer 須同字元且長度 ≥ opener、closer 後只允許
  空白、opener 縮排上限 3 格），三者各有 fixture。

⚠️ **pattern 分不出「使用」與「提及」**：討論一條（尤其壞掉的）引用時，寫法與真指標一模一樣。
處置是放進 code fence 或在路徑與引號間插字，**不放寬 pattern**——能區分兩者的唯一訊號就是 fence。

## 1e. agent contract kernel block 完整性 gate

掃描器：`tests/kernel-gate.py`（判準與輸出契約以該檔檔頭為準）。

kernel 必須在**四處**逐字存在：`AGENTS.md`（工具中立入口）、root `CLAUDE.md`（Claude 唯一會
自動載入的）、`claude/CLAUDE.md`（全域 Claude 部署來源）、`codex/AGENTS.md`（全域 Codex 部署來源）。
純指標方案已被實測證偽——2026-08-10 clean-room：Claude Code 自動載入 root `CLAUDE.md`、
**不**自動載入 root `AGENTS.md`（後者只在 agent 剛好探索 repo 時才被 `cat` 到）。

四份自足的代價是複本會漂移，而「same fact stated in N places」是 skill-building-guide 明列的
red flag。**這支 gate 就是把那個代價換成機檢**：漂移即紅。除逐字比對外另驗——

- 檔名寫死：漏改會找不到檔而判紅，比靜默略過安全。
- `MIN_RULE_LINES`：擋 block 被掏空。
- **CANARIES**（規則本體的指紋）出現在 block 之外 → 有人又抄了一份，複本一旦落在 gate 管不到的
  地方，漂移就回來了。
- portable block 只准在 `AGENTS.md`，且不得巢狀於 kernel 之內（兩者必須並列）。
- **可攜性**：契約檔不得含 `~/.dotfiles`、`~/.claude`、`/Users/` 等私人路徑——clone 下來就要生效。
- route block 只放在 repo-resident 的 `AGENTS.md`／`CLAUDE.md`：全域規則服務未採用
  doc-governance 的 repo，不能假設該執行檔存在。兩份必須逐字相同、至少保留 heading 與一條規則，
  且規則必須含 `doc-find` 或 `doc-governance.py find` 可執行入口，不能退化成人工 pointer；全域部署來源
  若出現 route block 也會判紅。portable block 同理只准存在於 repo-resident `AGENTS.md`。
- kernel／route／portable 三個 managed block 都會被複製到其他 repo，因此共用私人路徑與跨檔指標的
  可攜性檢查。掃描器以封閉的 finding code 集合列舉所有 blocking 分支；RED fixtures 的實際輸出
  必須覆蓋每一碼，新增分支卻沒新增可證偽 fixture 時 meta-test 會紅。

## 1f. deep-review 同型處置紀錄

五個終態模板都要接上共用定義。

## 1g. doc-governance 跨檔契約

守搬遷後的 skill 指標、xref wrapper exit contract、adopted／legacy template 分流、doc STOP 與 G7 fixture
fail-closed。這些依賴端用字與核心實作不同，不能靠一般 xref pattern 完整覆蓋。

## 2. bash -n 語法 gate

涵蓋範圍同第 1 節。

## 2b. doc-governance deterministic suite

掃描器：`scripts/doc-governance.py`；oracle：`tests/test_doc_governance.py` 與
`tests/fixtures/doc-governance/retrieval.tsv`。

synthetic repos 固定 config 錯誤、tracked／untracked 分類、零／多重分類、H2 前頂層 bullet、mixed legacy entry shapes、空 H2、
archive-month／event-month 日期語意、新 record type/month mismatch、plan lifecycle、xref compatibility、
commit range 內 history／frozen plan／legacy plan removal（含取消追蹤但保留 working-tree 檔案，及 branch
內建立、凍結後刪除）、Unicode slug、STATUS staleness、trusted scanner、ship fail-closed、deterministic tie
與 8 KiB 輸出上限。
真實 corpus 的 query 不得複製目標 entry／section 的標題核心詞，避免 oracle 把答案直接嵌進輸入；每列
宣告 family，集合必須完整覆蓋 decision、dead end、milestone、backlog、plan、policy、skill body、
skill reference、eval 與 archive。每題必須在 top 5 命中預期 path＋entry，需驗定位語意者另釘 expected
section。query 逐字包含 expected entry 的可判定形狀由測試守門；其餘「標題核心詞」的模糊重疊邊界
仍靠人工審 fixture，刻意不機檢：詞彙偶然重疊與標題複製沒有可靠的機械分界，近似 gate 會誤殺正常 query。

ranking 只能由 observed RED 驅動。Oracle 的 query／expected answer 只存在 TSV，不得從 config 注入答案詞；
remote branch 題改用使用者可合理提供的機制詞，並驗證未出現在 query 的 canonical title 片段。

---

# 純邏輯與 render

## 3–4. inventory.sh 解析、inventory_append

## 5–6. render-etc-hosts.sh、render-ssh-config.sh

## 7. add-new-host.sh --dry-run 煙霧測試

---

# skill 腳本行為測試

## 8. git-hygiene.sh verdict 判定

- **遠端事實優先**：判 unpushed 前先 `fetch --prune`。多 remote 時「branch 設定的 remote」與
  `origin` **兩者都 fetch**、任一失敗即整體降 UNKNOWN——只 fetch 其中一個＝拿 A 的新鮮度替 B 背書，
  實測可重現假 CLEAN。
- `--porcelain -uall`：預設把未追蹤目錄折成 `?? dir/`，殘留檔數被低估。
- **gh 失敗 ≠ 無 PR**：兩者都是 exit 1，吞 stderr 會把「查不到」報成 MISSING。
- 無 upstream 的已 push branch 用同名 `origin/<branch>` 當 baseline；退用 default 會把早已在
  remote 的 commit 全報成未 push。
- MERGED 以 `headRefOid` 為界，拿不到就保守不撤銷（**寧可誤報殘留，不可誤報乾淨**）。
- **多 repo 單次呼叫的聚合**：區段不漏、verdict 逐 repo 成立、CLEAN 不吞 RESIDUE/UNKNOWN、
  全 CLEAN 才 exit 0。
- fetch 上限的斷言由 `(timeout+grace)×目標數` 推導，**不放寬到十幾秒**——否則每 repo 卡十秒的
  regression 照樣綠。

## 9. ship-state.sh 偵測與 protection 判定

含 resolve 子指令、dossier 簽章偵測、bootstrap 判定、殘留 branch 衛生。protection 判定用 gh stub。

### dossier 尺寸訊號

總量 bytes／最長行／決策·里程碑條目 bytes（條目附**行號**、全檔附**建議收斂目標**、
超標時另印 `dossier-sections:` 各節佔比）。巨型單行不再架空行數門檻；條目訊號作用域限
決策/里程碑兩節，進行中 spec 區合法偏大不誤報。

**分節 bytes 把標題行計入所屬節**，斷言「加總 == 檔案 bytes」——歸零會讓佔比表系統性偏低，
讀的人以為漏算了一塊。**剝 fence 用哨兵前綴**（行號對齊＋長度不失真；量長度前剝哨兵，
否則佔比虛胖），五個 code site 皆吃 unfenced（三個 pattern 家族）。

### backlog 章節完整性（`docs/backlog.md`）

分家後待辦（技術債／已知缺口）落在此檔，而它**刻意沒有尺寸門檻**——待辦只壓得短、條目不會少，
量體門檻對它無效，那正是分家要消掉的東西。代價是整節被誤刪時**沒有第二道訊號**（dossier 那邊
至少還有尺寸 flag 會抖一下），比 2026-08-06 那次「兩整節被吃掉、一路 merge 進 main」更靜默，
故這道章節檢查是本檔唯一的機械保障。

五條斷言：兩節齊全不誤報／**分家後的 STATUS.md（兩節只留標題與指標）仍通過 dossier 章節檢查**
（保留標題的用意就在此，工具面零分叉）／**無該檔的 repo 零輸出**——未分家零回填是這個設計
能落地的前提，回填成本一旦非零就推不動／整節被刪抓得到並列出是哪一節／fenced 內的假標題
不算章節。最後一條驗的是新消費者確實吃 `strip_fences`（該函數為此從 `detect_dossier` 抽出共用
——同一份圍欄規則複製第二份必然漂移），突變測試（改回直接 `cat`）必須**只讓那一條紅**，已驗。

### 歸檔孤兒（反向守門）

`docs/archive/*.md` 沒有被任何 md 連到 → 檔案還在 git 裡但從 dossier 走不到。既有
`xref-gate` 只驗**正向**（指標指到的節/檔在不在），這一條補的是反向，且只印訊號、**絕不自動刪**
（同 stale-branches 的紀律）。

**掃描 pattern 用 `.md` 而非 `archive`**：任何對歸檔檔的引用必然含前者、不見得含後者
（evint 實地反例 `…2026-07-27-…md` 整行無 archive 字樣）。**窄 pattern 的假陽性比多掃幾行貴
得多** —— 它會叫人補一條本來就在的指標，或更糟、以為那份歸檔可以刪。斷言含一條「省略號形式
的指標仍認得」的哨兵；突變測試（把 pattern 收窄）必須只讓那一條紅。

實作為**單次掃描**：逐檔各跑一次 `grep -r` 在 krepo（29 個歸檔檔）要 13.0s，而這支腳本每次
ship 都跑；改成掃一次後 2.5s。

### always-on 量體訊號（純資訊，不判紅綠）

量此 repo 的 root `CLAUDE.md`（Claude 每 session 自動載入）與 `AGENTS.md`（Codex 每次讀），
擁有全域 `CLAUDE.md` symlink target 的 repo 另印一行。**只量 Claude 側是半套** —— 這個工作流
是雙 agent 的。

**落點必須在 remote／default 的 early return 之前**（`check_repo` 有兩處 `return`）。移到後面
會讓「任何 repo 都量」與 `always-on: NONE` 兩條同時不成立 —— 第 9 節有一條「無 remote 的 repo
仍印」專門守這個落點。

**三態不得混用**：兩份都無 → 整行 `NONE`；只有一份 → **逐檔標示**；讀取失敗 → 該檔 `UNKNOWN`
（同 `protection:` 的語意，不知道 ≠ 沒有）。bytes 讀取失敗顯式賦 `-1` 再守門，不能讓空字串餵
進數值比較（那會靜默當 0）。

**這是對「`dossier-sections:` 只在超標時印、平時是噪音」那條原則的刻意背離**：本行是 baseline
觀測、不是處置訊號，無條件印才看得到趨勢。⚠️ **升級成 flag 之前必須先解決「結構下限出口」**
——機隊 root `CLAUDE.md` 最大 102968、dotfiles 16993 只排第十，貿然設門檻會有七八個 repo 每次
ship 都亮，那正是 krepo 137KB 現在的狀態：flag 常亮＝沒有 flag。

**linked worktree 要另外接**：`-ef` 在 worktree 副本為假，而「在 worktree 改自家 CLAUDE.md」
正是常態工作方式 —— 訊號會恰好在最需要它的場合消失。沿 `--git-common-dir` 找主 checkout 補印，
**並驗證主 checkout 那份確實 `-ef` 全域檔**：只憑「有 common-dir」會把其他 repo 的 linked
worktree 也誤認成 dotfiles。

### 節名判定一律端錨定、不用子字串

`## 進行中（已完成 M1）` 這種自然寫法含「已完成」三字，子字串版會把整個進行中章節當里程碑節
掃進條目判定而恆誤報；反向 `## 已完成（進行中殘項）` 則讓里程碑的 ✅ 算成進行中的。
兩條斷言各經突變驗證。

### 「進行中含 ✅」只認條目形狀（list item）

不是節內任何一行。表格儲存格的 ✅ 是子項狀態欄——krepo 2026-08-10 連三次 ship 被同一張盤點表
誤報，每次只能在附註寫「未處理」，而 flag 訊息說的「移入里程碑」對一列表格根本無處可放。

**兩個候選各被實地反例否決**：
1. 「整張表全 ✅ 才算做完」——那張表本就 4 列全綠、照樣誤報。
2. 「續行併入所屬條目」（比照條目 bytes 的 awk）——表格前雖隔著散文、更前面仍有 bullet，
   寬續行模型照樣把它收回來。

marker 後**須有空白**，否則 `**粗體** ✅` 這種散文強調行被當成 bullet、收窄當場失效。
代價是續行 ✅ 與表格式待辦不再亮（**刻意放棄**，兩者都是條目內部的進度標註），
六條 fixture 連同這個 false negative 一併釘住。

### append-only 章節的別名家族

規範是「NEVER add an append-only log section」而非「不要叫 Session Log」——只認一個字面時，
換名為變更紀錄／工作日誌／CHANGELOG 就整個漏掉。ASCII 走 `-i`、中文含記/紀異體，
**限完整章節名**（允許括號或冒號後綴），否則「## 為何不使用 Change Log」這類討論性章節會被判紅。
訊息附**實際命中的 heading**——硬寫「Session Log」會讓別名命中時的處置指向錯的章節。
7 條正向別名 + 3 條負向討論性章節守門。

### 大輸入比對一律 herestring

`printf | grep -q` 早退觸發 SIGPIPE ＋ pipefail 判偽。守門 fixture 的**命中點須在前段**才逼得出來，
置於檔尾則 printf 已寫完、測試形同虛設。

### bootstrap 判定

遠端零 branch 才給 BOOTSTRAP 豁免；遠端有 branch 但定位不到 default 一律 STOP。
baseline 建立後豁免自動失效。

### 殘留 branch 衛生

已併入 default 的 local/remote branch 才列、未併入的不誤報、`origin/HEAD` 的裸 remote 名不得混入、
cleanup-cmd 前置 `fetch --prune`、**當前 branch 的 remote 對應不得列入**（實地誤報過一次，
照抄就會砍掉正要送出的那條）。

**squash-merge 盲視補償**：`branch --merged` 判祖先關係，squash-merge 後結構上看不到。
改比對 merged PR 的 `headRefOid` == 本地 tip，不符只印診斷不列入、fork 不採信、達 limit 標
`partial` **絕不印 `none`**。fixture 前提自檢「祖先判定確實看不到它」，否則後續斷言全是假的。

**多 remote（B1c）**：非 canonical remote 上的 branch **只列訊號、不得產生 cleanup-cmd**——
`branch -r` 列所有 remote，只剝 canonical 前綴時 `fork/x` 會被當成 branch 名傳給只認 canonical
的清理腳本，指令必然 STOP。判準刻意釘**行為**而非文字：**凡印出的 cleanup-cmd，照抄執行必須
exit 0**（既有單 remote 端到端斷言的推廣——「指令長得對」不等於「跑得動」，且不論日後改採
哪種修法都適用）。另驗 canonical 側不被誤過濾、兩條偵測路徑（祖先／squash）都不靜默吞掉
foreign、附上 `git remote remove` 的出路。**fixture 必須有第二個 remote**——單 remote 下
「tracking ref 路徑」與「canonical 上的 branch 名」恰好等價，整條缺陷不成立。

### cleanup-stale-branch.sh

破壞性刪除的唯一入口。三道前提：branch 存在／執行當下 tip == expected SHA／local 不得是
checked-out——任一不成立即 STOP 零 mutation。remote 走 `ls-remote` 重驗 + `--force-with-lease`
雙重比對。**lease 是第二道防線，故前置比對另立斷言**——否則整段前置檢查可被刪光而全綠。
傳進 remote-tracking ref 路徑（`fork/x`）時，STOP 訊息須指出**是 remote 錯了、不是名字打錯**：
那個案例裡名字其實是對的，「確認名字是否正確」會把人導向錯誤的排查方向（發射端已過濾，
這條守的是手打指令的人）。

### 照抄行的 shell quoting

路徑與 ref 名都過 `shq`：含單引號的路徑會讓 `bash -n` 直接 syntax error；`refs/heads/--all`
這種 option-like ref 靠 `--` terminator 才擋得住。斷言驗 round-trip 與「出現次數＝quoted 次數」——
光看「有沒有 quoted 形式」會假綠。

### mktemp 失敗的自我防護

`cd ""` 回傳 0 且不改目錄 → TMP 退化成 cwd → EXIT trap `rm -rf` 掉整個 repo。
用 stub 逼失敗；設 `TMPDIR` 沒用，macOS 的 mktemp 會忽略它。

## 9b. branch-first.sh 情況 A/B 判定與救援序列

真 git fixture：情況 A/B、mixed state、分岔／撞名／無 remote 一律 STOP。

## 10. review-state.sh scope-priority / round 判定

**untracked 用 `-uall` 展開目錄**：預設 porcelain 折疊成 `?? dir/`，reviewer 拿到目錄名會整批漏審。

## 11. repo-review review-context.sh range / guidance / autofix gate

## 12. repo-review skill packaging

## 13. handoff-anchor.sh 錨點驗證與生命週期判定

### `anchors` 是全有或全無

逐 repo 四項前提（toplevel 可解析／路徑無空白／`rev-parse --verify HEAD^{commit}` 成功／
`status` 可讀）任一不成立即 stdout 全空 + exit 1。半成品輸出與成功輸出長得一模一樣（錯誤只在
stderr），而 `verify` 只在**完全無錨點**時才判 UNVERIFIABLE——少一條時什麼都不說＝該 repo
從此沒有 checksum。

**unborn HEAD 尤其惡性**：`rev-parse HEAD` 會把**字面字串 `HEAD`** 印到 stdout 且 rc=0，
寫進錨點後 `HEAD^{commit}` 每次都解析成當下 HEAD → **永久判 FRESH**（實測前進兩顆 commit 仍 FRESH），
比沒有錨點更糟。

**驗證端配套用 canonical OID 比對**（`resolved != sha` → BAD-ANCHOR），擋掉 `HEAD`／branch 名／短 sha。
**判準不得硬編雜湊長度**——SHA-1 是 40 hex、SHA-256 是 64 hex，寫死 40 會把整個 sha256 repo
判成壞錨點，故另立 sha256 正常路徑守門。

`anchors` 記 `--show-toplevel` **絕對路徑**：相對輸入原樣寫進錨點會讓跨 session 的 verify 對到
別的 repo、還誤報成 DIVERGED。空白檢查對解析後的 toplevel 而非原輸入。

### `survey` 是 W1／R1 單一入口

**清理必須先於任何 archive 衍生輸出**，否則剛好過 TTL 的 predecessor 會被先印後刪、讀取端拿到
dangling path。worklines 上限只截顯示並印略過筆數，**不靜默截斷**。清理斷言用**獨立 fixture**——
沿用 `list` 已清過的目錄會變空條件。

awk 聚合兩個坑：`$2 > k[$1]` 在 k 未初始化時是數值比較，key `00000000000000` 於是永不被採用；
**tab 是 IFS whitespace**，空欄位會被 `read` 吃掉而讓後續欄位整批推移，故空值以 `-` 佔位。

### active 清單的時戳與排序

時戳欄取 **mtime**、`Nd` 取 **created**，兩欄來源不同。用 mtime 的理由是 **created 只有日粒度**
（`cmd_anchors` 寫 `date +%Y-%m-%d`），同日多份必然平手。**不要寫成「created 不隨續寫更新」**——
那是假的：W2 每輪都跑、W3 原樣貼入，created 恆等於最後一次蓋錨點的日期（81 份真實交接檔實測，
與 mtime 的日期 0 份不一致）。mtime 買到的只有**同日的時分解析度**。

排序 fixture 的 **mtime 順序必須與檔名字典序相反**——否則現行 glob（字典序升冪）也剛好答對，
斷言等於虛設（同下方 `bar-foo` 的教訓）。tie-break 防的是 **`sort` 同鍵不保證穩定**，
不是 glob 順序漂移（後者是確定性的）。

**`LC_ALL=C` 不可省，而 tie-break fixture 必須含一個大小寫混排的檔名（`a-Zed`）才守得住它**：
只有 `a-first`/`z-second` 的話，拿掉 `LC_ALL=C` 斷言照樣綠。實測同一組輸入在 C 與 UTF-8 locale
下給出**相反**順序，**兩平台皆然**（BSD sort 2.3-Apple 與 glibc sort 都會翻），所以這一份 fixture
同時守住 macOS 與 Linux。GNU 側另外三條原語（`stat -c %Y`、`date -d @epoch`、`date -r <epoch>`
**必須失敗**才會退到 `-d @`）本 repo 的測試跑不到——它們在 2026-08-19 由 eagle03／db01／agent01
三台實跑確認。

**`active: none` 與 SUSPECT 兩條分支各自有斷言**：改動前兩者皆零覆蓋，而重構動到的正是決定
`active: none` 印不印的那段——`… | sort | while read` 會讓旗標困在 subshell（列完項目又多印一行），
空 rows 直接餵 herestring 則會產生一次空行迭代（反而讓它消失）。兩個方向都要釘。

`0` 是 mtime 的 **sentinel 不是合法 epoch**（`date -r 0` 會成功回 1970），故顯示端先判再格式化；
該分支在 `[ -f ]` 已通過的前提下不可達，**刻意不寫測試**——不可執行的驗收比沒有更糟。

**空欄位推移是同一條坑的第二個觸發點**（第一個見上方 worklines 的 awk 聚合）：`<mtime>\t<path>`
的 mtime 若留空，`IFS=$'\t' read` 會把路徑吃進 mtime 欄。故 stat 失敗一律填 `0`，並比照
`codex-runtime-hygiene.sh` 加純數字守門（GNU `stat -f %m` 會印掛載點）。

### archive 檔名身分解析

抽成兩個消費端共用的 parser。**候選 slug 不可壓成單一值**，key 逐候選各自成立。
**frontmatter `slug:` 是否決權不是索引**——與候選相符則升為首選以消歧，全不符則以檔名歸戶並標
「find-predecessor 不會採用」，讓本來完全隱形的殘檔可見。正反兩面都有斷言：只釘一面的話
「改用 frontmatter 當索引」照樣全綠。

### find-predecessor 依 slug 精確定位

**active 與 archive 判準不同**：active 比完整檔名（一併剝前綴會讓 `20260804-foo` 這種合法 slug
失配、判成首輪後整檔覆寫）；archive 才剝歸檔前綴，且取**時戳數值**最大者（靠 glob 字典序會選到
同日的 legacy 舊檔）。檔內 `slug:` 存在時須相符、無該欄位者放行（向後相容）。

**不可退回 glob**：`archive/*-<slug>.md` 的 `*` 吃得下中間的工作線名，查 `foo` 會撈到 `bar-foo`。
**fixture 的 `bar-foo` 時戳必須最新**，否則 glob 實作的 `tail -1` 也剛好答對、斷言等於虛設。

## 14. codex-runtime-hygiene.sh 孤兒偵測 / 誤殺防護 / exit 契約

## 16. session-pull-check.sh（SessionStart hook）

**落後偵測與 base 建議都不得拿 repo-global `FETCH_HEAD` 的新鮮度替別的 remote 背書**：
多 remote 時剛 fetch 過 `other`，真正落後的 clone 會完全不出聲。單 remote 才保留快取快路徑。

fetch 真的失敗時 base 建議**仍要出**、但須帶「可能已過期」警語。該臂另立守門，
否則 `stale_note` 會變成沒有覆蓋的死碼。

## 17. codex-exec-review.sh exit 契約與 job 產物

codex 用**會模擬 clap argv 拒絕**的 stub。

## 19. review-anchor.sh 錨點生命週期 / squash-cmd / codex-next

cycle 續跑計數。**squash base 由 subject 掃描求得**：自 HEAD 往回跳過 review 機械樣式、
停在第一顆語意 commit（該顆保留），全為樣式才退回 anchor base。`squash-preserve:`／`squash-note:`
訊號、續跑跨兩場 fix 一併壓、分岔歷史不誤列 preserve 皆有守門。

**squash 範圍自此 ≠ 審查範圍。**

## 20. verify-tests.sh 框架偵測與 exit 契約

用 uv/bun stub。對本 repo 判 SKIP（無 uv/bun 測試框架）——本 repo 的真測試就是 `./tests/run.sh`。

## 21. crawl-quality-scan.py 確定性掃描與扣分帳目

用 python fixture 對準扣分表。

## review-residue（Step 4 squash 出題依據）

none／top-contiguous／buried 三形狀與混合；全壓指令附後果警語；reset 目標由腳本解析；
lib 缺席與 merge-base 失敗皆降級 UNKNOWN。

**跨 Step 時序**：Step 1 的 squash hash 不得重算，正反兩組斷言。

---

# 部署 helper 與運維腳本

## 15. ensure-rc-source.sh 幂等補 source 行

含**舊 alias 清理**：`brewup`/`sysup` 遷成 function 後必須從 rc **刪行**而非 `unalias`。
其他 alias 與非 alias 內容不得誤刪、清完重跑須幂等。

**「行數減幅 > 2 即原封不動」那道前提檢查另立斷言**——否則整段防護可被刪光而全綠。

## 18 / 18b / 18c. ensure-codex-skills.sh、ensure-codex-guidance.sh、ensure-lftprc.sh

幂等測試。`ensure-lftprc.sh` 另含 `.lftprc.local` 不覆寫、早退路徑仍補檔。

## 18d. brewup.sh helper 部署與失敗告知（全隔離）

## 18e. ensure-ssh-config.sh 幂等重生 ~/.ssh/config

原子寫入 + 完整性驗證。

## 22. brewup / sysup / brewfix

`sysup.sh` 平台 guard。

**`brewfix.sh`**：macOS-only guard／未知參數不得被當成 `--fix`／唯讀模式絕不刪除／`--fix` 清完複驗／
**無卡死 process 時不得驚動 `killall syspolicyd`**／lsof 條目正常的同一 process 不得誤判為卡死／
**破壞性刪除作用域限 Caskroom 內**（Caskroom 外的 `*.upgrading` 不得被碰）。
ps／lsof／killall／sudo 皆以 stub 注入。

## 23. migrate-github-remotes.sh

- **身分驗證是硬前提**：認到錯帳號即 STOP 且零 mutation。
- dry-run 零 mutation。
- 三種換寫正確，且非 GitHub remote 不得被碰。
- **非 `origin` 的 remote 同樣換寫**：手貼迴圈只掃 origin，實跑工作 mac 時有兩條 `fork` remote
  會被留下。
- `insteadOf` 只清 github-work 那幾條，不波及使用者其他改寫規則。
- `--apply` 幂等；未知選項 exit 2 而非當成路徑。
- `GIT_CONFIG_GLOBAL` 隔離，**絕不碰真的 `~/.gitconfig`**。

## 24. `.githooks/dispatcher`（全域 core.hooksPath 的單一入口）

### 為什麼是 dispatcher 而不是單一 pre-commit

全域 `core.hooksPath` **取代整個 hook 目錄**。目錄裡沒有的 hook 名，repo 自己 `.git/hooks/`
的同名版本就**靜默不執行** —— `post-checkout`／`post-merge` 正是 Git LFS 用的。「靜默」是本
repo 已知地雷的共同形狀，所以本目錄掛上**全部 client-side hook 名**（各為指向 dispatcher 的
symlink），每一個都先 chain 回 repo 自己的版本。

**代理清單不由實作者挑**：`.git/hooks/*.sample` 只有 14 個、不是全集（缺 `post-commit`／
`post-checkout`／`post-merge`／`post-rewrite`／`pre-auto-gc`）。server-side 的 receive 系列與
Perforce `p4-*` 刻意不代理 —— **git 升版時要重新盤點**，測試以 18 個名字逐一斷言。

**只有 dispatcher 是實體檔**：四道 gate 只列它（掃 symlink 等於重複掃同一內容），
所以有一條「`.githooks` 下只有 dispatcher 是實體檔」的斷言 —— 新增第二個實體檔會漏掉 gate。

### chain 與 fail-open 的邊界（順序不可調換）

1. 先跑 repo 自己的同名 hook，**exit code 原樣傳回**，本檔不吞。
2. 逃生變數與「進行中操作早退」**只停用 guard，不跳過 repo 自己的 hook**。
3. guard 跑在 **subshell**，以 `exit 97` 表示「確認命中、應阻擋」；**其餘任何非零一律視為
   內部失敗 → 放行**。

⚠️ **不能用 `set -u` 做 fail-open**：實測未綁定變數會讓整支 `exit 1`，那是 fail-**closed**，
正好相反 —— 而 hook 自己出錯回非零就會擋掉 14 台上所有 commit，包括修這個 bug 的那顆。
語法錯誤與 interpreter 不存在**本質上無法 fail-open**，那一層只能靠四道 gate 擋在 commit 之前。

### 路徑解析：兩者用途不同、不可互換（linked worktree 實測）

- repo hook 在 **`--git-common-dir`**`/hooks/`
- `MERGE_HEAD`／`sequencer/` 等**操作狀態**在 **`--absolute-git-dir`**（worktree 下是
  `.git/worktrees/<name>`）

**不要用 `git rev-parse --git-path hooks/…`** —— 它被 `core.hooksPath` 汙染（實測回
`<hooksPath>/pre-commit`），拿來 chain 會無限遞迴呼叫自己。另用 `-ef` 排除「chain 目標其實
就是 dispatcher 本身」。

### 三個刻意保留的 false negative（各有一條測試固定邊界）

`detached HEAD`、`純本地 git init 的 main`、`缺 origin/HEAD 的自訂 default`（如 trunk）
**都不擋**。這**弱於 kernel 的明文要求**，是為了讓 `tests/run.sh` 的 74 個 `git init` fixture
與 eval 沙盒跑得動而保留的 —— **不得讓 AC 說成「default branch 上一律被擋」**。

另有一個擋不住的邊界：**repo 自設 local `core.hooksPath` 會完全繞過本防線**（已實測：
local 覆寫 global）。同樣明列、不假裝擋得住。

### 測試隔離

`tests/run.sh` 與 `claude/evals/setup-sandboxes.sh` 各 `export DOTFILES_PRECOMMIT_OFF=1`
—— 否則全域 hooksPath 一生效，兩者的 fixture（含 g8 刻意造的「誤 commit 在 main」，也就是
**證明救援路徑有效的那一個**）就造不出來。

⚠️ 第 24 節要驗「無變數→擋」與三個 false negative 的地方，必須在 subshell 內
`unset DOTFILES_PRECOMMIT_OFF` **反向解除** —— 否則測到的是逃生變數而不是判定序（假綠）。
**exit code 一律直接呼叫 dispatcher 驗**：`git commit` 對 hook 只看零/非零、自己回 1，
透過它量不到 42（2026-08-14 首版測試就是這樣誤判成實作壞掉）。

## 未列於本檔的節

`dotfiles-sync` 遠端回報段（ssh 失敗與無告知時都不可吞掉主機結果）已有測試但無獨立節號。

`tests/run.sh` 的節號是唯一權威——本檔若少了某節，代表**該節的設計理由尚未記錄**，
不代表該節不存在。補記時請對照節號。
