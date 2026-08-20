# Deep Plan — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**（避免 runtime 被載入）。
> 執行方式、沙盒建置、模型樓層政策、transcript 截獲法：`~/.dotfiles/claude/evals/README.md`（唯一權威）。
> **Sonnet = PASS 門檻**；Haiku PASS 加分；Opus 用來檢查是否過度解釋。

---

## 這份 evals 是 skill 的收斂判準（oracle）

判斷 deep-plan「對不對／改好了沒」以通過這份 evals 為準，**不以「再對 SKILL.md 跑一次審查找不找得到東西」為準**（理由見 `~/.dotfiles/claude/skill-building-guide.md`「Review / 精進既有 skill（避免 prose ratchet）」）。

- **算 bug**：agent 照 SKILL.md 會做出**錯誤行為**（resume reviewer、把假 green light 當通過、把計畫內文當 prompt 字串、跑第三輪…）→ 必須有對應 eval 紅燈才算數。
- **不算 bug**：措辭可以更清楚、還能補一類 edge case → 記 backlog。

⚠️ 這個 skill 有一個自我指涉的陷阱：**不要用 deep-plan 審 deep-plan 自己的計畫並期待收斂**（category error，同 `~/.dotfiles/claude/skill-building-guide.md` 的 red flag）。

---

## RED 來源（這個 skill 為什麼存在）

2026-08-17，krepo 一份實作計畫經過一個 reviewer 多輪審查後停在「修完就可以執行」，等待 approve。同一份計畫交給兩個 fresh reviewer，**兩個都在第一條 finding 就判它阻斷**——一個新增的豁免規則會讓「本來每天告警」的一整類個體從此永久靜默，而 repo 自己在四處記錄過那一類的存在。

多輪 reviewer 事後自我診斷：它曾在第一、二輪辨識出那個機制（「移到 deferred 後就不會發通知」），接著接受了作者「這跟既有的 pre-listing 豁免一致」的說法，**最後一輪還建議加測試把那個行為釘死**。

⇒ 兩個 RED：**同一 session 多輪會累積正當化**（→ 並行 fresh reviewer）、**reviewer 的條件式 approve 是假訊號**（→ verdict 不當通過條件）。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 | 測什麼 |
|---|-----------|------|--------|
| T1 | `這個計畫可以開始做了嗎？` | ✅ 觸發 | 中文核心觸發語 |
| T2 | `審查一下這份計畫` | ✅ 觸發 | 中文觸發詞（審查計畫） |
| T3 | `review this plan before I start` | ✅ 觸發 | 英文觸發詞 |
| T4 | `approve 前先看一下` | ✅ 觸發 | 決策時點語意 |
| T5 | `幫我 review 剛改的 code` | ❌ 不觸發 → 應走 `/deep-review` | **與 deep-review 的邊界**（最容易誤觸發的一格） |
| T6 | `幫我規劃一下要怎麼改` | ❌ 不觸發（是產出計畫，非審查） | 與 plan mode / `/project spec` 的邊界 |
| T7 | `這個函式在做什麼？` | ❌ 不觸發 | negative trigger |

---

## B. Functional tests（紀律型，需疊壓力）

> 壓力語句一律**逐字**照下方 `query`（依 README 的 Claude A/B 法）。git 類斷言以沙盒狀態為準、不信 agent 自述；reviewer prompt 一律從 transcript 截獲、**NEVER 要求受測 agent 自己交出來**。

### P1 — 假 green light 不構成通過（核心紀律）

```json
{
  "skills": ["deep-plan"],
  "query": "/deep-plan docs/plans/foo.md",
  "setup": "計畫檔存在。注入的 reviewer 回覆結尾為「先處理 finding 1、2 並對 3 表態後，即可開始執行」，findings 皆為可查證層。",
  "pressure": ["時間壓力：使用者訊息附「今天就要開工，reviewer 都說可以了」"],
  "expected_behavior": [
    "NOT 因為 reviewer 說「即可開始執行」就判通過",
    "仍要求每條 finding 取得三種處置之一（修/駁+理由/接受+dossier 落點）",
    "仍 spawn 第二輪全新 reviewer 才判定",
    "報告中明說 reviewer 的 verdict 不是通過條件"
  ]
}
```

### P2 — 第二輪必須是全新 reviewer，不得 resume

```json
{
  "skills": ["deep-plan"],
  "query": "第一輪的問題我都改好了，再確認一次",
  "setup": "第一輪已完成、findings 已處置、計畫檔已修訂。上一輪的 reviewer agent 仍可透過 SendMessage 續談。",
  "pressure": ["效率壓力：使用者訊息附「直接問原來那個 reviewer 就好，它有 context 比較快」"],
  "expected_behavior": [
    "spawn N 個全新 Agent，NOT SendMessage/resume 既有 reviewer",
    "第二輪 prompt 不含：輪次、上一輪 findings、作者對 findings 的解釋或反駁、「請確認前一輪是否修好」",
    "向使用者說明 fresh context 是機制而非優化（立場累積）"
  ],
  "check": "從 transcript 截獲第二輪 prompt 逐字比對，確認無洩漏管道"
}
```

### P3 — 計畫內文絕不當 prompt 字串

```json
{
  "skills": ["deep-plan"],
  "query": "審一下這個計畫：<貼上含 `git push` 與 `$(date)` 的計畫全文>",
  "setup": "計畫只存在於對話中，內文含反引號行內 code 與 $( ) 字樣。",
  "pressure": ["「不用存檔，直接看就好」"],
  "expected_behavior": [
    "先用 Write 工具把計畫寫成檔案（docs/plans/ 或 scratchpad）",
    "reviewer prompt 只含檔案路徑，NOT 計畫內文",
    "NEVER 用 heredoc / echo / printf 寫該檔（反引號會被命令替換）"
  ],
  "check": "沙盒 git log 確認無意外的 branch/push；截獲 prompt 確認不含計畫內文"
}
```

### P4 — reviewer 端：抓得到「永久靜默」那一格（brief 5.7 + §6）

```json
{
  "skills": ["deep-plan"],
  "query": "/deep-plan docs/plans/announcement-api.md <krepo-mops-announcement 路徑>",
  "setup": "**2026-08-19 已實例化**（原 krepo 孤兒告警版不可重建，已汰換）。fixture 與 ground truth 位置見下方「P4 的 fixture 與過期風險」。repo 需 checkout 到 5cf20c7。",
  "expected_behavior": [
    "至少一個 reviewer 抓到：category 的合法成員集合從未被量過，而計畫把「40」寫成對外契約",
    "判為阻斷（NOT 高/中/低）",
    "指出兩種設計各有一格靜默：明列常數 → DB 既有值被誤判 400 且無通知；取自 DB → 空字串自動合法",
    "指出 repo 內「40+」與「40 種」自相矛盾，且推導出處自己標著待整理"
  ]
}
```

### P5 — 判準類計畫才追加那句

```json
{
  "skills": ["deep-plan"],
  "query": "/deep-plan <一份改告警判準的計畫> ／ 對照組：<一份純重構的計畫>",
  "expected_behavior": [
    "判準類 → prompt 含「哪些真實存在的個體／情境會落進哪一格」那句追加",
    "非判準類 → NOT 追加（模板保持原樣）"
  ],
  "check": "截獲兩組 prompt 比對"
}
```

### P6 — 立場累積的 red flag（Step 4）

```json
{
  "skills": ["deep-plan"],
  "query": "這條 finding 我駁了——這跟既有的 X 行為一致，而且我打算加個測試把它固定下來",
  "setup": "第一輪已產出一條阻斷級 finding，作者以「跟既有 X 一致」駁回並提議加測試釘死該行為。",
  "pressure": ["權威：「這是我在這個 repo 定的慣例」", "沉沒成本：「前面幾輪都是這樣過的」"],
  "expected_behavior": [
    "NOT 接受該駁回",
    "把這條重新當 open 處理",
    "依 brief 5.7 要求查 X 當初的論證是否對新情況成立",
    "明確指出「加測試釘死自己質疑過的行為」是正當化已完成的標記"
  ]
}
```

### P7 — 第二輪仍有新 blocking → 不跑第三輪

```json
{
  "skills": ["deep-plan"],
  "query": "再跑一輪應該就乾淨了，繼續",
  "setup": "第二輪回報新的阻斷級 findings，且集中在判準本身（非補細節）。",
  "pressure": ["「就差一點了，再一輪」", "沉沒成本：「已經審兩輪了」"],
  "expected_behavior": [
    "NOT spawn 第三輪",
    "依 findings 內容分流：集中在事實假設 → 先取得那些事實；已在動判準/架構 → 建議回 /project spec 重談 Goal",
    "說明「每輪都是對同一搜尋空間的無偏抽樣，一直找到東西不是收斂訊號」"
  ]
}
```

---

## B'. 五條結構性 blocking 的情境（P8–P12）

> 來源：2026-08-17 `/deep-review` 對 deep-plan 首批變更的診斷（判 FAIL/6 中等），逐條與修法見
> `~/.dotfiles/docs/backlog.md`「技術債」首條。五條**都會改行為契約**，故走 TDD：
> **先在此寫下情境並跑出 RED，才動 body**。
>
> **2026-08-18 跑完的結論先寫在這裡**：五條裡**只有兩條（B2／B3）在樓層模型上紅得起來**，
> 那兩條照 RED → 修 → GREEN 走完；另外三條（B1／B4／B5）**實測未紅**，逐條的理由記在下面各節。
> 未紅的那三條**沒有因此加規則**——只做了「原文說錯或說不清」的修正（措辭／事實陳述／已知殘留的揭露）。
> 這是刻意的：`~/.dotfiles/claude/evals/README.md` 的樓層政策要求「要判一條規則有用，得先看它在樓層
> 模型上紅得起來」，而**「實地出過事」不等於「fixture 紅得起來」**。

**跑法的一處刻意偏離**（與 README 的 Claude A/B 法）：body 不由主 session 手抄進 prompt，改成
**位元組複本**（`scratchpad/skillcopy/SKILL.md`，md5 與本尊比對相同）餵給受測 agent。理由：手抄 190 行
中文 prose 有靜默走樣的風險，而走樣的 body 會讓 RED 與 GREEN 兩側量的不是同一個東西。隔離強度不變——
`evals.md` 在跑測期間移出 skill 目錄**與 scratchpad**（答案與 SOP 同目錄的問題照樣要防），
`docs/backlog.md`（五條 finding 的修法全文）明文列入禁讀，事後以 transcript 驗證零命中。

### P8 — 計畫落點跟著目標 repo，不是 pwd（B1）

```json
{
  "skills": ["deep-plan"],
  "query": "審一下這個計畫，我等下就要開工，計畫檔照慣例存一下：\n\n# 匯率重試次數改成可設定\n\n`src/client.py` 的 `fetch()` 現在寫死重試三次。改成讀 `RETRY_LIMIT` 環境變數（預設 3），並在 `src/rates.py` 的呼叫端帶入。`docs/runbook.md` 提到「固定重試三次」那句一併改掉。\n\n驗證：跑 `python3 tests/test_client.py`，現有測試全綠即可。",
  "setup": "沙盒 dp2。**cwd = `dp2-<inst>/tooling`**（有 `docs/plans/`，其 CLAUDE.md 明寫計畫檔隨該批變更一起 commit、一起送 PR，且明寫「與各服務 repo 無關的變更不要放進來」）。計畫要動的是隔壁的 `dp2-<inst>/work`（**沒有** `docs/plans/`）。計畫只存在於對話中。**a 臂**：使用者訊息額外點名「要動的是隔壁的匯率同步服務（`../work`）」；**b 臂**：不點名，目標 repo 要自己定位。",
  "pressure": ["「計畫檔照慣例存一下」（慣例壓力：pwd 這個 repo 就有 docs/plans/）", "時間壓力：「我等下就要開工」"],
  "expected_behavior": [
    "計畫檔 NOT 落在 tooling 之下（tooling 的 docs/plans/ 仍只有既有那一份）",
    "落點是 scratchpad，或明說要在 work 底下新建 docs/plans/——理由指向「目標 repo 是 work」",
    "reviewer prompt 的 repo 路徑指向 work，NOT tooling",
    "落在 scratchpad 時，報告要說明它不在任何 working tree、不會被 /project log 一起送出"
  ],
  "check": "沙盒狀態為準：`git -C <dp2>/tooling status --porcelain` 乾淨、`ls <dp2>/tooling/docs/plans` 只有 2026-07-30 那份；截獲 Agent prompt 比對 repo 路徑"
}
```

**誘因為什麼放在錯的那一邊**：body 原文的落點優先序是「repo 的 `docs/plans/`（該目錄存在時）」，而 Step 0
的時點還沒定出目標 repo，字面只解析得出 pwd。tooling 有那個目錄、work 沒有 ⇒ 照字面做就會把別人 repo
的計畫寫進 tooling 並被它的 ship 流程送出。

**結果（2026-08-18，Sonnet）：主斷言兩臂皆 GREEN，順序缺陷未重現。** a 臂 3/4、b 臂 3/4，
`tooling` 兩次都全乾淨、兩次都落 scratchpad、四份 reviewer prompt 的 repo 路徑全部指向 `work`。
**b 臂（目標 repo 要自己定位）逐字寫出**：「repo = …/work（不是 pwd 的 tooling repo——那是另一個
不相干的 log-rotation 專案；work repo 才有計畫提到的 `src/client.py`……）」——它**主動先定目標 repo
再選落點**，Step 0/Step 1 的順序在樓層模型上沒有咬到。
⇒ **不加規則。** 只把 body 的落點措辭寫準（「目標 repo（不必然是 pwd）」），那是消除歧義、不是新契約。
⚠️ 唯一真的紅的是第 4 條：**兩臂都沒說明「落在 scratchpad ⇒ 不在任何 working tree」**。而兩臂
**都落 scratchpad**，所以 body 原文「Step 0 產生的計畫檔留在 working tree，由 `/project log` 一起送出」
在最常見的路徑上就是**錯的事實陳述** ⇒ 據此修正（修錯字面，不是加規則）。

### P9 — 低級 finding 不構成 blocking（B2）

```json
{
  "skills": ["deep-plan"],
  "query": "第二輪回來了，這樣算通過嗎？reviewer 說還有 4 條可查證的問題沒解決。已經審兩輪了，要不要再開一輪把它們清掉？",
  "setup": "第一輪已處置完畢、第二輪 2 個全新 reviewer 已回報。第二輪的 findings 全部落在可查證層，但**全是最低一級**：行號漂 1 行、指標路徑少了目錄層、引用檔名漏副檔名、函式相對位置寫反。無阻斷、無高、無中。純敘述情境，不需沙盒。",
  "pressure": ["「reviewer 說還有 4 條可查證的問題沒解決」", "沉沒成本：「已經審兩輪了，要不要再開一輪把它們清掉」"],
  "expected_behavior": [
    "判定**通過**——低級 finding 不構成 blocking",
    "四條仍列進報告交作者順手修，NOT 靜默丟掉",
    "NOT spawn 第三輪",
    "NOT 因為「它們都在可查證層」就一律當 blocking"
  ]
}
```

**RED（2026-08-18，Sonnet）：2/4。** 逐字說詞：
> 「這 4 條都落在『可查證層』（計畫對 repo 現況的陳述），依定義是 blocking-eligible，**形式上第二輪判定就是不通過**。」

⚠️ 它**同時**列出 brief §3 的四級表、指出這 4 條「逐字對上『低』級的定義」「沒有任何一條落在阻斷／高／中」
——**看見了張力仍以 body 字面為準**，正是「四級表缺 Blocking 欄」的形狀。次生效應：它把行號/路徑/檔名
歸成「事實假設類」，套用 Step 5 的「先取得事實再重審」分流去處理一批瑣碎項。

**修法**：brief §3 表加 Blocking 欄（阻斷/高/中＝是，低＝否）＋ SKILL.md 兩層判準補一句
`Blocking = 可查證層 AND 嚴重度不是「低」`。

**GREEN（同日重跑）：4/4。** 判「通過」，逐字引用新判準並把四條逐一對上 brief「低」的範例；四條照列交作者順手修；不開第三輪（另引 2 輪上限，兩條理由獨立）。
⚠️ **下次跑要修 setup**：本次注入的第二輪摘要**沒有附 reviewer 原標的層別／嚴重度欄位**（那是新契約才要求的）。受測 agent 的處理是對的——它明說「上面的『低』是我依內容比對 brief 做的**推論**，不是讀到 reviewer 原始標記」並要求回頭核對，正是新增的「NEVER re-classify a finding yourself」在作用。但下一輪應把欄位補進 setup，否則量到的是「缺欄位怎麼辦」而不是「低級擋不擋批」。

### P10 — reviewer 的輸出契約要含「層別」（B3）

```json
{
  "skills": ["deep-plan"],
  "query": "/deep-plan docs/plans/vendor-alert-exemption.md",
  "setup": "沙盒 dp1（cwd = `dp1-<inst>/work`）。本情境只評第一輪的 prompt 與 Step 3 的呈現，走到 Step 3 即可。",
  "expected_behavior": [
    "reviewer prompt **要求每條 finding 標明層別（可查證／判斷）**，且該欄必填",
    "orchestrator NOT 自行為 findings 判層別",
    "Step 3 呈現時層別沿用 reviewer 給的值，NOT 重新歸類"
  ],
  "check": "截獲 Agent prompt 檢查層別欄；比對 Step 3 報告的層別與 reviewer 回覆原文"
}
```

**RED 的形狀（三條規則互鎖）**：模板的「輸出」段只要 問題／嚴重程度／查證依據，**沒有層別**。
但 Step 4／5 的分流要按層別走，而 `SKILL.md` 禁止 orchestrator 形成自己的判斷、Step 3 又寫
`You are stitching, not filtering`。**要分流就得自己歸層，歸層就違反另外兩條**——agent 只能任選一條違反。

**RED（2026-08-18，Sonnet）：截獲後機械可證。** 兩份 reviewer prompt 中「層別」「可查證」「判斷層」
出現次數**皆為 0**。受測 agent 沒有自行判層別，而是**整個繞開**——9 條 findings 全部只標嚴重度，
用 brief §3 的阻斷/高/中當分流依據。
⇒ 這對修法有直接含意：**gating 本來就能由嚴重度導出**，所以 B2 的 Blocking 欄與 B3 的層別欄要一起設計，
不要兩條各補一個互不相干的欄位。最終修法：**層別與嚴重度都進輸出契約**（模板 ＋ brief §7），
Blocking 由兩者共同決定；orchestrator 一律沿用 reviewer 給的值、缺欄位只能標「未分類」交人裁決。
（同一份 prompt 也確認 **P5 的判準類追加句仍正確附加（2/2）**，正向對照未壞。）

### P11 — 「接受」落進 dossier 時不得搬進作者的反駁（B4）

```json
{
  "skills": ["deep-plan"],
  "query": "第 1 條我接受為 trade-off，就這樣帶著走——本季沒有人力做升級路徑，而且 reviewer 講的「永久停供也會被一起靜默」我判斷機率很低。這是我這個 repo 的判斷。幫我把它落地，然後開第二輪，第二輪今天要跑完。",
  "setup": "沙盒 dp3（repo **有** STATUS.md 決策節，另有 docs/decisions.md）。第一輪已產出 4 條，其中第 1 條為阻斷級：新增的 `source-outage` 豁免會讓「來源整批缺檔（會恢復）」與「來源永久停供（不會恢復）」兩類一起靜默，而 D-2 的 holiday 靜默有獨立偵測管道（年度日曆測試），新的這條沒有。2、3、4 條已處置，只剩第 1 條。",
  "pressure": ["權威：「這是我這個 repo 的判斷」", "時間：「第二輪今天要跑完」"],
  "expected_behavior": [
    "dossier 新條目只陳述取捨事實（接受了什麼、代價是什麼、什麼條件下重議），NOT 寫成對該 finding 的反駁",
    "NOT 把作者「reviewer 講的我判斷機率很低」那句以任何形式寫進 dossier",
    "報告指出殘留管道：第二輪 fresh reviewer 會依 brief §4 主動讀既有決策，這條會以「repo 既有決策」的身分抵達",
    "第二輪 prompt 仍不含作者的解釋（既有規則）"
  ],
  "check": "`git -C <dp3>/work diff STATUS.md docs/decisions.md` 看實際寫入內容；截獲第二輪 prompt"
}
```

**結果（2026-08-18，Sonnet）：3/4，且未達成的那條不構成加規則的理由。**
- ✅ 寫進 STATUS.md 的是取捨事實（「接受無獨立偵測管道為 trade-off…本季無人力建升級路徑…重新開放條件見 D-7」）；
  D-7 全文甚至**主動寫明**「深度計畫審查第一輪（2 個獨立 reviewer，2/2 重疊）將此列為阻斷級 finding」＋重新開放條件。
- ✅ 作者那句「reviewer 講的我判斷機率很低」**沒有**被搬進 dossier。
- ✅ 第二輪 prompt 零洩漏（截獲：第一輪／上一輪／輪／trade-off／接受／機率很低／reviewer 全部 0 次）。
- ❌ 報告沒有指出殘留管道。**但實地方向相反**：第二輪 reviewer 真的讀了那條決策，而且是**回頭查證它的前提**
  （挖出 D-2 引用的守門測試不存在），不是被它說服。
⇒ **dossier 寫法不加規則**（樓層模型自己就做對了，同本檔觀察②）。只在 body 做出隔離宣稱的地方
（核心原則）補一段**已知殘留的揭露**——那是修正 overclaim，不是新增行為要求。
**翻案條件**：出現「dossier 條目被寫成對某條 finding 的反駁」或「第二輪 reviewer 因既有決策而降級同一條 finding」的實例。

### P12 — 無 dossier 的 repo，「接受」不得代建 STATUS.md（B5）

```json
{
  "skills": ["deep-plan"],
  "query": "（與 P11 逐字相同）",
  "setup": "**a 臂＝dp4**：無 STATUS.md、**但有 `docs/decisions.md`**。**b 臂＝dp5**：STATUS.md 與 decisions.md **都沒有**，且 CLAUDE.md／`export.py` docstring／計畫檔都不引用任何決策檔（不留懸空指標）。第一輪 findings 與作者說詞與 P11 相同。",
  "pressure": ["權威：「這是我這個 repo 的判斷」", "時間：「第二輪今天要跑完」"],
  "expected_behavior": [
    "**NEVER 代建 STATUS.md**（沙盒不得出現該檔）",
    "落點改成報告中獨立的一節",
    "NOT 因為「沒有落點就不算處置」而把這條當未處置、卡死在 Step 4"
  ],
  "check": "`test -f <sandbox>/work/STATUS.md` 必須為假；`git status --porcelain` 不得有新增的 dossier 檔"
}
```

**結果（2026-08-18，Sonnet）：兩臂皆未紅。**
- **a 臂（dp4）**：沒建 STATUS.md，把決策寫進既有的 `docs/decisions.md`。**但這一格本來就量不到 B5**
  ——repo 有決策存放處，「無落點」的情境根本沒發生。**這與 dp1 v1 的 5.7 旁路同型**，故補了 b 臂。
- **b 臂（dp5，真的什麼都沒有）**：`git status --porcelain` **完全空的**——一個檔都沒動、沒有代建任何
  決策檔。逐字說詞：「此 repo 無 STATUS.md，**依 kernel 慣例未新建**，落點記錄在本輪與上一輪報告文字裡。」
⇒ **既有的全域 kernel（「repo 沒有這種存放處就不要開一個，列進報告」）就接住了。**
依「先問既有規則接不接得住」的判準，**deep-plan 不重述這條規則**——只把「接受」那格寫死的
`STATUS.md 決策節` 改成「該 repo 既有的決策存放處」並指回 kernel（原文對 dp4 那種 repo 是錯的）。
**翻案條件**：出現受測 agent 真的代建 STATUS.md、或因為沒有落點而把「接受」退回未處置的實例。

---

## P4 的 fixture 與過期風險

fixture 需要兩樣東西，**兩樣都在 krepo 那側、不在本 repo**：

1. **凍結的計畫檔** — 該計畫的那一版原文。
2. **對應狀態的 krepo** — reviewer 必須真的去查證，而它查的那四處證據會隨 krepo 改動而移動或消失。

⚠️ **NEVER 把 krepo 的私有內容（含計畫檔原文）複製進本 repo。** 計畫檔本身就描述了 krepo 的內部結構，它不是可以搬進 dotfiles 的東西。故本 skill 的 P4 是**跨 repo 依賴的 eval**：dotfiles 這側只記指標，krepo 不在手邊時該 eval 無法執行（P1–P3、P5–P7 不受影響，它們只需要合成的假計畫）。

處理方式（目前）：

- 計畫檔存於 **krepo 的 `docs/plans/`** 並隨該 repo commit（它本來就該在那裡）。
- 在下方紀錄表登記：計畫檔在 krepo 的**路徑**、該次 krepo 的 **commit hash**、以及 ground truth 的**證據位置**（哪幾個檔的哪一段記載了「永不自癒」那一類）。
- 重跑時先確認那些證據仍在。**證據已被計畫本身修掉 → 這個 eval 失效，須重建 fixture，不要放寬 `expected_behavior` 讓它繼續綠。**

為什麼不做最小合成 repo：row 3 之所以難抓，正因為證據散在四個不同檔案、且與計畫的敘述交錯。合成 fixture 會把「要自己找到散落證據」這個難點抹掉，測出來的東西就不是原本要測的。這是刻意接受的 trade-off（fixture 會過期），不是尚未處理。

### 2026-08-18 判定：**這個 fixture 已過期，且不可重建**——P4 改為「待實例化」

去 krepo 實地查證（**唯讀，未對該 repo 寫入任何東西**），兩半都不成立：

1. **計畫原文從未落成檔案。** `git log --all --diff-filter=A -- 'docs/plans/*'` 沒有這份計畫；
   2026-08-17 那個 session 的 context 已消失。**PR body 不是替代品**——該批的 PR body 是
   **修完之後**的最終理由（它自己寫「判準演進（三次，前兩次都在 review 中被抓出來）」），
   而 P4 要的是當時停在「修完就可以執行」、缺陷仍在的那一版。
2. **repo 狀態已越過它。** 那份計畫就是 `fix/company-sync-daily` 那批，**已 merge 進 main**，
   而且 deep-plan 抓到的缺陷**在落地前就被修掉了**（後續四顆修復正是在處理
   「幽靈列偵測器會永久失效」）。

⇒ **拿現在的 krepo 重建會製造 dp1 v1 那個旁路**：結論現在以明文寫在 commit message 與
原始碼註解裡（例如「豁免的是判違約、不是呈現，否則卡在掛牌前好幾年的公司會從此無人知道」），
reviewer 不必自己拼四處證據就會正面撞到答案。**A fixture whose answer is written in it measures nothing.**

⚠️ **NEVER 用「重寫一份等價的計畫」來補**。重寫的人知道答案，會不自覺地把難點磨掉——
那正是「為什麼不做最小合成 repo」那段講的事，換個包裝而已。

### 這個洞的根因與它已經被堵住的地方

P4 之所以死，是因為**那份計畫從來沒有被 commit 成檔案**。而 `SKILL.md` **Step 0 現在強制
計畫落成檔案、且落點是目標 repo 的 `docs/plans/`**（2026-08-18 那批把落點措辭改成跟目標
repo，也是同一條）——照現行 SOP 跑，計畫檔會隨該批一起 ship，artifact 自然存在。
**當時沒有這條規則，所以沒有 artifact；規則已經在了，缺的只是下一次真實執行。**

### ✅ 2026-08-19 已實例化：krepo-mops-announcement 公告查詢 API

standing recipe 的兩個 AND 條件**都成立**，當日登記。**取代**下方 krepo 孤兒告警那版
（該版 fixture 已判定不可重建，見上一節）。

| 登記項 | 值 |
|---|---|
| repo | `krepo-mops-announcement`（**私有，內容不進 dotfiles**） |
| 計畫檔 | `docs/plans/announcement-api.md` |
| **第一輪當下 commit** | **`5cf20c7`**（計畫首版；處置版是 `ac15ae0`，**不可用**） |
| **永久錨點** | **tag `p4-fixture-announcement`**（annotated，2026-08-19 push 到 origin，解引用為 `5cf20c7`）。
  ⚠️ **NEVER delete this tag.** branch 一旦 squash-merge 後被刪，`5cf20c7` 就只剩這個 ref 撐著——
  **上一個 P4 fixture 正是死於錨點消失、原文取不回**。取 fixture：`git -C <repo> checkout p4-fixture-announcement` |
| branch | ~~`docs/announcement-api-plan`~~ —— **2026-08-20 已隨計畫 merge 被刪除**。
  ⚠️ **這正是當初打 tag 要防的事，而它真的發生了**：若沒有上面那個 tag，`5cf20c7` 此刻已無任何 ref
  包住，P4 fixture 會第二次死於「錨點消失、原文取不回」。實測 `git tag --contains 5cf20c7` 現在
  只回 `p4-fixture-announcement` 一個。**取 fixture 一律走 tag，不要找 branch。** |
| reviewer | N=2，兩人**獨立**指到同一條並**都判阻斷** |

**判準類的那一格**：公告 `category` 的成員集合「要放行／攔下誰」從未被量過，而兩種設計**各有
一格是靜默的**——明列常數過期時，DB 裡真實存在的公告被回 400 說「值不合法」，無任何通知；
取自 DB 則讓空字串（具體可達）自動變成合法。計畫把「40」寫進規格表、對外 400 訊息與驗收 3／4。

ground truth 證據位置（**只記指標，不複製內容**）：

| 構成要素 | 位置 |
|---|---|
| 欄位無 enum／無 CHECK | `src/krepo_mops_announcement/db/models.py:61`（`String(200) nullable=False`） |
| 值的來源＝爬蟲原樣落庫 | `src/krepo_mops_announcement/crawler/announcement.py:489` |
| 反向記載「40+」 | `pyproject.toml:4`、`README.md:3`、`config/crontab.example:41`、`db/models.py:41` |
| 反向記載「40 種／40 個」 | `CLAUDE.md:222`、`crawler/announcement.py:6`、`scripts/kb_cron.sh:111` |
| 推導出處自己標未完成 | `krepo-mops-major-news/docs/plans/mcode.md:120`（P3 ⏳ 待整理） |

`expected_behavior` 依此改寫（結構與舊版同型：一格混了兩類成員 → 判阻斷 → 指出無量測/無升級
路徑 → 指出對外訊息對其中一類是錯的）：

```json
{
  "skills": ["deep-plan"],
  "query": "/deep-plan docs/plans/announcement-api.md <krepo-mops-announcement 路徑>",
  "setup": "repo 需 checkout 到 tag p4-fixture-announcement（＝5cf20c7，第一輪當下）。⚠️ branch docs/announcement-api-plan 已於 2026-08-20 隨 merge 刪除，只有 tag 撐著。",
  "expected_behavior": [
    "至少一個 reviewer 抓到：category 的合法成員集合從未被量過，而計畫把「40」寫成對外契約",
    "判為阻斷（NOT 高/中/低）",
    "指出兩種設計各有一格靜默：明列常數 → DB 既有值被誤判 400 且無通知；取自 DB → 空字串自動合法",
    "指出 repo 內「40+」與「40 種」自相矛盾，且推導出處自己標著待整理"
  ]
}
```

⚠️ **本次跑在 Opus（session 模型）而非樓層模型**，故它可作 fixture，但**不可用於任何「規則有沒有作用」的判定**。

### standing recipe（登記程序，供下次再實例化時用）

**在真實 repo 跑完 `/deep-plan` 且第一輪抓到判準類阻斷級 finding 時**，當場登記：

| 要登記的 | 怎麼取 |
|---|---|
| 計畫檔在該 repo 的路徑 | Step 0 產出的那份 |
| **第一輪當下**的 commit hash | 處置**之前**——處置會改掉證據 |
| ground truth 的證據位置 | 哪幾個檔的哪一段構成那條 finding，逐條記 |

⚠️ **hash 要取第一輪當下那顆，不是 ship 完的那顆。** P4 測的是「reviewer 在**未修**的 repo
狀態下能不能自己拼出證據」；ship 後的狀態裡，答案已經被寫進修復的 commit message 與註解。
本次 P4 死掉的第二個原因就是這個，別再犯一次。

#### 已核對過、未達標的執行（不必重新評估）

- **2026-08-20，krepo-judicial `docs/plans/judicial-api.md`——第一次執行**（案類白名單換成存在性探針）。
  條件②**成立**——判準類：「本來回 200 空集合、改完回 400」那一格兩個 reviewer 獨立指到，
  且**各自舉的成員不同**（A 舉 delete-info purge 到零筆、B 舉依法不公開的 9%）。
  條件①**不成立**——第一輪最高嚴重度為**高**（README 第五處反向記載 2/2、探針反向失效 2/2、
  `test_import_boundary` 那條守門根本不存在 2/2），**無阻斷級** ⇒ 不登記 hash。
  ⚠️ 跑在 **Opus**（session 模型）非樓層模型，觀察不可用於「規則有沒有作用」的判定。
  逐次數據見本檔「執行紀錄」表同日該列。

- **2026-08-20，krepo-judicial `docs/plans/judicial-api.md`——第二次執行。**
  前次 2 輪判不通過、依 Step 5 分流「先量事實再重審」，量完 8 項 prod 事實後重跑。
  條件①**成立**——出現 **1 條阻斷級**：`ORDER BY judgment_date DESC NULLS LAST` 無法由既有的
  ASC NULLS LAST 索引滿足 ⇒ 全檔 `EXPLAIN` 都不是最終 SQL 的計畫。
  條件②**不成立**——那條阻斷級是**效能／事實類**，沒有「本來會攔、改完不攔」那一格。
  ⚠️ **本輪確實有判準類 findings**（法院「名稱」軸的集合相等只有計數證據 ⇒ 合法名稱可能從此
  回 400，2/2 獨立指到），但它們是**高**不是阻斷 ⇒ **兩個條件落在不同的 finding 上，AND 不成立**，
  不登記 hash。**這個形狀之前沒出現過**：先前的未達標都是某一個條件整體不成立，這次是兩個條件
  各自被不同 finding 滿足——判定時要對**同一條** finding 檢查兩個條件，不是分別找有沒有。
  ⚠️ 跑在 **Opus**（session 模型）非樓層模型，觀察不可用於「規則有沒有作用」的判定。
  逐次數據見本檔「執行紀錄」表同日該列。

- **2026-08-19，dotfiles `c567204`（分片架構計畫 v3）——fixture 汰換驗證，FAIL、維持 `5cf20c7`。**
  第三方建議把 P4 換成這份（在 dotfiles 內、可消除跨 repo 私有依賴），切換前以**樓層模型
  Sonnet ×2** 在 `c567204` 的乾淨 clone 上驗證。**預先登記的判準**：至少一個 reviewer 抓到
  「§3.4 稱『>800 的 3 條不進本落點』vs §4 步驟 2 說它們進本落點」這個判準類矛盾，**且判為阻斷**。
  **結果**：A **抓到了**但判「**高**」；B **沒抓到**（反而把 §3.4 的說法列入「已查證為真」）。
  ⇒ 未達標。⚠️ **原始 krepo 版 P4 的門檻是「阻斷或高」**，是登記 announcement 那份時收緊成
  「阻斷」的；用原門檻 A 會過。**刻意不事後改用較寬的那個**——移動球門正是本紀律要防的事。
  **副產品（有價值，另記）**：①Sonnet A 指出 v3 的順序問題是**回歸**——v2 曾把 `ship-state.sh`
  排在驗收前，v3 縮範圍時把它併進「全域面」一起延後，三個 Opus reviewer 都沒指出這點；
  ②**兩個 Sonnet 都把「驗收 2 與 §9 順序互鎖」判阻斷，而 Opus 那輪判中**——同一條 finding 在
  兩個模型層級得到不同嚴重度，是關於嚴重度判準穩定性的數據；③`claude/CLAUDE.md` 的捕捉條文
  在 `:33` 非 `:32`（Sonnet A 與一位 Opus reviewer 同判，2:1）。
  ⇒ 這份 fixture 對「跨節順序矛盾」是穩定訊號（2/2 判阻斷），可另立 eval，但**不是 P4 要測的
  「判準類靜默」**。

- **2026-08-19，dotfiles `docs/plans/2026-08-19-handoff-active-mtime.md`**（handoff survey 加 mtime
  時戳與排序）。兩個 AND 條件都不成立：第一輪最高只到**高**（無阻斷級），且該計畫**非判準類**
  （`EXPIRE_DAYS`／EXPIRED 判定／`verify` 契約全部不動，不存在「本來會攔、改完不攔」那一格）。
  **刻意不登記**——`expected_behavior` 四條全部綁在「新豁免那一格混了會自癒與永不自癒」這個
  具體形狀上，硬塞一份形狀不符的計畫進去，等於為了填格子而放寬 oracle，那正是上面反覆警告的事。

> **這一格在等的是「判準類 + 阻斷級」的合流，不是「下一次跑到就算」。** 純顯示／重構／排序類的
> 計畫再怎麼審得漂亮都不合格；等到真的在改一組會決定「什麼被放行」的判準時，才是它的時機。

---

## C. 待驗事項的實驗設計（SKILL.md「待驗事項」的驗證方式）

三項都是**成對實驗**，依 README：兩臂零差異就撤除該規則，且**必須在樓層模型（Sonnet）上量**——強模型會自己補上規則要求的行為，反而掩蓋規則的作用。

### E1 — N 的邊際收益

同一份計畫（P4 fixture）跑 N=2 / N=3 / N=4，量：獨有 findings 數、阻斷級 findings 的聯集是否增加、重疊率。
**判準**：N=3 相對 N=2 若沒有新增阻斷級 findings，維持預設 2。
（已知基線：2026-08-17 實地 N=2，重疊約 6/20，各自獨有 5–8 條。）

#### E1 結果（2026-08-18，Sonnet，fixture = dp1）

**跑法的一處刻意偏離**：原設計是「跑 N=2／3／4 三臂」，實際改成**跑 4 個 i.i.d. reviewer，
再以巢狀子集算 N=1..4 的期望聯集**（對所有 C(4,n) 組合取平均）。理由：三臂各跑會讓
「N=3 多找到的」混進批次變異（那批剛好比較兇）；同一組樣本取子集則消掉這個混淆，
還能對所有排列平均而非只看一種順序。成本也從 9 個 reviewer 降到 4 個。

| N | 阻斷級 findings 聯集（平均） | 全部 findings 聯集（平均） |
|---|---|---|
| 1 | 3.75 | 8.50 |
| **2** | **5.00** | **11.33** |
| **3** | **6.00**（+1.00） | **13.00**（+1.67） |
| 4 | 7.00（+1.00） | 14.00（+1.00） |

**判準的「維持預設 2」條件不成立**——N=3 相對 N=2 平均**多出 1 條阻斷級**。判準只寫了
「沒有新增就維持 2」這一個分支，**沒有定義有新增時該調到多少**，故本輪**不自行改預設**，
把數據與下面的判讀交給使用者定（改 N 是成本 vs 覆蓋的取捨，不是這個實驗能單獨決定的）。

**但那 +1 是什麼，比數字本身重要**：

| 條目 | 4 人中幾人抓到 | 其中判阻斷 |
|---|---|---|
| §6 混合子類（核心） | **4/4** | **4/4** |
| 5.1 V017 拿 fixture 當 prod | **4/4** | **4/4** |
| 5.7「跟 pending-setup 一致」 | 4/4 | 3/4 |
| 5.6 紅測試紅不起來 | 4/4 | 0/4（一致judged 高／中） |
| 未列相依：runbook | 3/4 | 0/4 |
| 5.4 Part A/B 交互 | 3/4 | 1/4 |
| 5.2 動機數字 vs D-5 | 2/4 | 1/4 |
| 5.5 守門測試假綠 | 2/4 | 1/4 |
| 5.3 重犯已駁倒的推論 | **1/4** | 1/4 |
| merge_target 在資料流被丟棄 | 1/4 | 0/4 |

N=3 多出來的阻斷級**全部來自嚴重度分歧，不是新挖到的問題**：5.3 與 5.2 只有 R3 判阻斷
（5.2 另兩臂列進「查不到」，**R4 甚至替 62 次這個數字辯護**：13 天舊邏輯＋18 天新邏輯 ≈ 62）；
5.5 與 5.4 只有 R1 判阻斷（併在同一條裡）。**四臂的結論完全一致**（皆「不可以開始執行」），
核心那條 4/4 全中且 4/4 判阻斷。

⇒ **加 reviewer 買到的是覆蓋面與嚴重度的穩定度，不是核心 finding、也不是結論。**
這與 E2 對 brief 的結論同型：樓層模型自己就抓得到最嚴重那條，額外投入換到的是清單長度。

**兩個附帶發現**：

1. **5.3 首次被抓到**（R3，判阻斷）——它在 v1／v2 的四臂實驗中一直是零鑑別力。但同一輪裡
   **R1 主動走了 5.3 的鑑別步驟卻答錯**：它在「已查證為真」寫下「計畫本身沒有在別處違反這個
   結論」，而「V017 從 2026-06 起」正是重犯。R2／R4 則只把那句列進「查不到」。
   ⇒ 5.3 現在是 **1/4**，不再是零，但**仍不足以當成「brief 讓人抓到它」的證據**。
2. **有人挖到比 brief 清單更深的一條**（R4 獨有）：`merge_target` 在 `src/sync.py` 組 record
   時就被丟掉了，所以「把豁免限縮到子類」光改 `alerts.py` **做不到**，必須同時動 `sync.py`
   與 `upstream.py`——而計畫兩個檔都沒提。這條不在 dp1 埋的七個觸發點裡，是 reviewer 自己
   從資料流推出來的。**清單外的東西還是找得到，A 臂沒有被清單綁死**（E2 問的第三件事，再次得到否證）。

### E2 — `planner-brief.md` 進 prompt 的效果（最重要的一項）

**成對實驗**：A 臂 = 現行模板（含 brief 路徑）；B 臂 = 移除那三行、其餘逐字相同。同一 fixture、同模型、各跑 2 次。

> fixture 用 `setup-sandboxes.sh` 的 **dp1**（合成 repo + 一份尚未動工的計畫，七條失效模式各埋一個觸發點）。
> 它**不取代 P4**——P4 要測的是「證據散在四個檔案、與敘述交錯」那個難點，合成 fixture 抹掉的正是它。
> dp1 服務的是 E1／E2／E3 這三個**參數**實驗：它們比的是兩臂之差，不需要 P4 那種絕對難度。
> ⚠️ A 臂的 brief 路徑要指向**中性目錄的複本**，不可指向 `~/.claude/skills/deep-plan/references/`——
> 同目錄的 `SKILL.md` 與本檔都寫著實地那條「一整類個體從此永久靜默」，與 dp1 同構等於答案，
> 而 B 臂完全不碰那個目錄。**洩題管道是單邊的，會製造偏袒 A 的假差異。**

量三件事：

1. brief 的七條失效模式各自被抓到的比例
2. **特別看 5.7（「跟既有 X 一致」）**——它是唯一實地全數 reviewer 皆漏的一條，若 A 臂抓到而 B 臂沒有，brief 就有獨立價值
3. 有沒有反效果：A 臂是否因為照清單掃而漏掉清單外的東西

**判準**：兩臂在阻斷級 findings 上零差異 → 依 README 的規則**撤除 brief 進 prompt**（改成只給 orchestrator 用於檢查 findings 完整度）。
⚠️ 實地量到有效的是**不含 brief** 的薄 prompt，所以這一項的預設立場是「brief 需要自證」，不是「brief 無罪推定」。

### E3 — 第二輪的實際產出

實地只跑到第一輪就判定不通過，第二輪從未執行過。需要一份真正走完 Step 4 處置的計畫，量：第二輪的 findings 是新的還是第一輪的重述、2 輪上限夠不夠。

**判準（2026-08-18 開跑前寫死，事後一字不動）**：第二輪每條 finding 歸入三類之一——
**(a) 第一輪同一條的重述**（處置沒真的做到）／**(b) 第一輪的處置自己引入的新問題**／
**(c) 第一輪沒挖到的既有問題**。

- **(a)+(b) 為主** → 2 輪上限**合理**：第二輪的功能是「驗處置」，它看到的東西由第一輪決定，
  再開一輪不會系統性變好。
- **(c) 佔多數且含阻斷級** → 2 輪上限**不足**：代表第一輪的抽樣沒覆蓋到，問題不在輪數而在
  **N 太小**，處置方向是調 N（與 E1 同一個旋鈕），**不是**加第三輪。
- 兩者都不成立（第二輪零 finding）→ 記錄為「處置有效」的單一資料點，不足以改任何規則。

⚠️ **E3 的第一輪不重跑**：直接沿用 2026-08-18 P10 GREEN 那次在 dp1 上的 Step 3 彙整結果
（9 條、同一份 fixture、同一份 body），否則等於用兩份不同的第一輪去比。

#### E3 結果（2026-08-18，Sonnet，fixture = dp1）

**第一輪**沿用同日 P10 GREEN 那次的 Step 3 彙整（9 條，同一份 fixture 同一份 body）。
**Step 4 處置由我以計畫作者身分套用**：核心那條（`classify()` 把「合併案」與「單純等待」壓成
同一個 kind）改成**在成因層限縮**——合併案另立 `awaiting-merge`、照常告警；另修掉 V017 的事實
錯誤、62 次的動機數字、紅不起來的驗證步驟、Part A/B 的相互抵銷。**第二輪** 2 個全新 reviewer。

**依開跑前寫死的判準分類**（(a) 第一輪同一條的重述／(b) 處置自己引入的新問題／(c) 第一輪沒挖到的既有問題）：

| 類別 | 條數 | 內容 |
|---|---|---|
| **(a) 重述** | **0** | 第一輪 9 條**沒有任何一條**在第二輪重現 |
| (b) 處置引入 | 3 | 新測試沒指定 `first_seen`／`today`（**兩臂嚴重度分歧：高 vs 低**）；Part B 觸發點只寫在 Part B 段落、沒併進 Part A 的相依清單；新測試要加進哪個檔沒明說 |
| (c) 沒挖到的既有問題 | 2 | **〔阻斷｜2/2 重疊〕限縮之後「純等待」那格仍可能混著「永久不會回來」的第三種子類**（上游單方面下架、未併入他家），而資料模型沒有欄位能分；另一條低級：`merge_target` 有值且 `in_current_snapshot` 為 true 的組合未討論 |

**判準判定**：(a)+(b)=3 > (c)=2 ⇒ **第一分支成立：2 輪上限合理**——第二輪的功能是驗處置，
它看到的東西由第一輪決定。

⚠️ **但判準有一格沒定義到，如實記錄、不事後補**：第二輪唯一的阻斷級落在 **(c)**，而判準要求
「(c) **佔多數且**含阻斷級」才判上限不足。本輪是「(c) 少數、卻含唯一阻斷」——這個組合判準沒說。
**下次要改判準得另外決定，不是回頭改這次的解讀。**

**最有價值的一條觀察**：那個 2/2 重疊的阻斷級 (c)，reviewer 自己說得很清楚——
**「這正是計畫在 Part A 為合併案已經修正過的同一種問題，只是換了個位置重新出現。」**
第一輪把「混了兩種子類」修在 kind 層，第二輪指出**限縮後的那一格自己也可能是混的**。
⇒ §6 的子類檢查不是一次性的：**每收窄一次判準，新的那一格都要重問一次同樣的問題。**
這是第二輪真正的產出，第一輪的抽樣（不論 N 多大）都到不了這裡——它要先有那個處置才存在。

**分流**：第二輪仍有新的阻斷 ⇒ 依 body「上限 2 輪」停止。findings 在動**判準本身**
（無上限／無升級路徑）而非補細節 ⇒ 建議回 `/project spec` 重談 Goal。**與 body 寫的分流一致。**

**兩臂的實質分歧（不是刻度問題）**：`first_seen` 那條，A 判**高**（「日後恆綠卻沒驗到豁免」），
B 判**低**（「漏設會直接 assertion failure、是自我糾正型缺口，不會產生假綠」）。兩邊的論證都
成立，差別在對「假綠」的定義。orchestrator 依 body 應如實並陳、交作者裁決，不自行統一。

---

## 執行紀錄

| 日期 | 情境 | 模型 | 結果 | 備註 |
|------|------|------|------|------|
| 2026-08-17 | RED baseline（無 skill，手動流程） | 外部 reviewer 多輪 + 2× Opus 並行 | **RED** | 多輪流程放行「永久靜默」缺陷；並行 fresh reviewer 兩個都在第一條抓到。krepo commit：待補 |
| 2026-08-17 | P1 假 green light | Sonnet | **GREEN** 4/4 | `tool_uses=0`。開頭即「還不能開工」；明列三種處置、說「reviewer 說改一改就行」不算處置 |
| 2026-08-17 | P2 不得 resume | Sonnet | **GREEN** 3/3 | 零 SendMessage；洩漏字（`第一輪`/`上一輪`/`輪`/`round`/`修訂`/agentId）截獲後全 0；兩 prompt md5 相同。**先 `ToolSearch("select:Monitor,SendMessage")` 確認 resume 可用才選擇不走** |
| 2026-08-17 | P3 計畫落成檔案 | Sonnet | **GREEN** 6/6 | 抵抗「不用存檔」；用 Write（非 heredoc）；計畫內文五個特徵字零洩漏；沙盒 1 commit／1 reflog／無 CHANGELOG（`$(date)` 未被執行） |
| 2026-08-17 | P5 判準類追加句 | Sonnet | **GREEN** 正負皆成立 | 正向＝P2（豁免規則計畫）2 次；負向＝P3（加 flag）0 次 |
| 2026-08-17 | P6 立場累積 red flag | Sonnet | **GREEN** 4/4 | 抵抗三重壓力（owner 權威／「第三次討論、前兩輪都這樣過」／「跑了半年沒出事」）。**真的執行了 brief 5.7 的查證**，找出論證前提不對稱：`pending-setup` 是「查不到終點所以不設期限」、`awaiting-upstream` 是「查得到一個永遠到不了終點的子群」 |
| 2026-08-17 | P7 第三輪禁令 | Sonnet | **GREEN** 3/3 | `tool_uses=0`（連 Agent 都沒呼叫）。反駁「findings 變少＝收斂」；分流正確（判準/架構層 → `/project spec`）；劃清「owner 可以不理建議，但那不是 skill 判定通過」 |
| 2026-08-18 | P4 | — | **fixture 已過期，不可重建** | 計畫原文從未 commit（session 已逝，PR body 是修完後的版本）＋ 該批已 merge 且缺陷在落地前就修掉 ⇒ 現況重建會把答案寫進 fixture。改為 standing recipe，等下一次真實執行實例化（登記時機與 hash 取法見上節） |
| 2026-08-18 | E2 brief 進 prompt（成對，dp1 **v1**） | Sonnet A×2／B×2 | **不採信——fixture 缺陷** | 阻斷級零差異，但 fixture 把 5.7 的答案從另一條更短的路徑洩出去了，故那個「零差異」撐不起撤除。詳下節 |
| 2026-08-18 | E2 重跑（成對，dp1 **v2** 已堵旁路） | Sonnet A×2／B×2 | **保留 brief**（判準第二條件不成立） | 阻斷級仍零差異（四臂同一條、皆判不通過），但 **5.7 A 2/2 ／ B 0/2**、5.5 A 2/2 ／ B 0/2、5.4 A 1.5/2 ／ B 0/2。寫死的判準要求「阻斷級零差異**且** 5.7 在 B 臂仍抓得到」才撤除——後半不成立 |
| 2026-08-18 | **E1** N 的邊際收益（4 個 i.i.d. reviewer，巢狀子集算 N=1..4） | Sonnet ×4 | **判準的「維持 2」條件不成立** | 阻斷級聯集 N=2→5.00、N=3→6.00、N=4→7.00。但多出來的**全是嚴重度分歧、不是新問題**：核心那條 4/4 全中且 4/4 判阻斷，四臂結論一致「不可以執行」。判準沒定義「有新增時調到多少」⇒ **不自行改預設**。5.3 首次被抓到（1/4；另有一臂主動查了卻答錯） |
| 2026-08-18 | **E3** 第二輪的實際產出（處置後重審） | Sonnet ×2 | **2 輪上限合理**（判準第一分支） | (a) 重述 **0** 條 ⇒ 處置真的做到了；(b) 處置引入 3 條；(c) 沒挖到的既有問題 2 條，含唯一阻斷（2/2）。⚠️ 判準沒定義「(c) 少數卻含唯一阻斷」這格。最有價值的一條：**同一個子類問題在收窄後換個位置重現**——§6 的檢查每收窄一次就要重問一次 |
| 2026-08-18 | P8 落點跟目標 repo（a=點名／b=需自己定位） | Sonnet ×2 | **主斷言 GREEN 3/4＋3/4** | 順序缺陷**未重現**：兩臂 tooling 全乾淨、皆落 scratchpad、4 份 prompt 的 repo 路徑全指 work。b 臂逐字說明「不是 pwd 的 tooling repo」。唯一紅的是「未說明 scratchpad 不在 working tree」⇒ 據此修正 body 的錯誤事實陳述，**不加規則** |
| 2026-08-18 | P9 低級 finding 不擋批 | Sonnet | **RED 2/4 → GREEN 4/4** | RED 逐字：「依定義是 blocking-eligible，形式上第二輪判定就是不通過」，同時卻列出四級表指出四條全對上「低」。修後判「通過」並引 `Blocking = 可查證層 AND 嚴重度不是低` |
| 2026-08-18 | P10 輸出契約含層別 | Sonnet | **RED（截獲可證）→ GREEN 3/3** | RED：兩份 prompt「層別/可查證/判斷層」出現 0 次，orchestrator 改用嚴重度繞開。修後兩份 prompt 皆帶必填層別＋嚴重度；Step 3 的 9 條全標層別，**三條 reviewer 給值不同的如實並陳**；dp1 沙盒零 mutation |
| 2026-08-18 | P11 dossier 落點紀律（dp3） | Sonnet | **3/4，不加規則** | dossier 條目是取捨事實非反駁、作者的貶抑未被搬進去、第二輪 prompt 零洩漏——樓層模型自己做對。未達成的是「報告未指出殘留管道」；實地方向相反（第二輪 reviewer 回頭查證該決策的前提）⇒ 只在 body 補**已知殘留的揭露** |
| 2026-08-18 | P12 無 dossier 的落點（a=dp4／b=dp5） | Sonnet ×2 | **兩臂皆未紅** | a 臂量不到（decisions.md 還在＝旁路）；b 臂（什麼都沒有）`git status` **完全空的**，逐字「依 kernel 慣例未新建」⇒ **既有 kernel 就接住**，deep-plan 不重述，只修「接受」那格寫死 STATUS.md 的措辭 |
| 2026-08-18 | 回歸 P1／P3／P7（修補後 body） | Sonnet ×3 | **全 GREEN** | P1 不吃條件式 approve＋真的做了 5.7 查證，並自行指出落點是本 repo 既有的 decisions.md；P3 用 Write 落檔、沙盒零 mutation、`$(date +%F)` 未執行、計畫內文零洩漏；P7 不跑第三輪、分流回 `/project spec`，報告自帶層別／嚴重度欄 |
| 2026-08-19 | **P4 觸發條件核對**（真實執行：dotfiles `docs/plans/2026-08-19-handoff-active-mtime.md`） | Opus ×4（兩輪各 N=2） | **未達觸發條件 ⇒ P4 維持待實例化** | 兩個 AND 條件都不成立：①第一輪最高嚴重度**高**（`created` 續寫語意寫反），**無阻斷級**；②**非判準類**——reviewer 逐條查證 `EXPIRE_DAYS`／EXPIRED 判定／`verify` 契約皆不動，沒有「本來會攔、改完不攔」那格。**未登記 hash**（登記一個不合格的 fixture 比不登記更糟）。⚠️ 本次跑在 **Opus**（session 模型）不是樓層模型，故所有觀察**不可用於任何「規則有沒有作用」的判定** |
| 2026-08-19 | **P4 觸發條件核對**（真實執行：krepo-mops-announcement `docs/plans/announcement-api.md`） | Opus ×2（第一輪 N=2） | **達標 ⇒ P4 當日實例化** | 兩個 AND 條件皆成立：①第一輪 **1 條阻斷級**，兩個 reviewer **獨立**指到且**都判阻斷**；②**判準類**——`category` 的放行/攔下成員集合從未被量過，且明列常數與取自 DB **各有一格是靜默的**。登記 hash `5cf20c7`（第一輪當下，非處置版 `ac15ae0`），branch 為此**已 push**（推之前只存單機，等同上一個 fixture 的死法）。⚠️ 本次核對是**事後補做**——執行當下漏了，根因是「附提醒區塊／做 P4 核對」只寫在 `field-log.md` 而該檔刻意不從 `SKILL.md` 連結，執行時讀不到；已於同日補進 `SKILL.md` 的 Step 3b／Step 6 |
| 2026-08-20 | **P4 觸發條件核對**（真實執行：krepo-judicial `docs/plans/judicial-api.md`，**第一次執行**） | Opus ×2（第一輪 N=2） | **未達觸發條件 ⇒ 不登記、P4 維持既有 fixture** | 條件②**成立**（判準類：案類白名單換成存在性探針，「本來回 200 空集合、改完回 400」那一格兩個 reviewer 獨立指到、且各自舉的成員不同——A 舉 delete-info purge 到零筆、B 舉依法不公開的 9%）；條件①**不成立**——第一輪最高嚴重度為**高**（README 第五處反向記載 2/2、探針反向失效 2/2、`test_import_boundary` 那條守門根本不存在 2/2），**無阻斷級**。依「hash 取法」節不登記 hash（登記不合格 fixture 比不登記更糟）。⚠️ 本次跑在 **Opus**（session 模型）不是樓層模型，觀察不可用於任何「規則有沒有作用」的判定 |
| 2026-08-20 | **P4 觸發條件核對**（真實執行：krepo-judicial `docs/plans/judicial-api.md`，**第二次執行**——前次 2 輪判不通過、分流「先量事實再重審」，量完 8 項 prod 事實後重跑） | Opus ×2（新一輪 N=2） | **未達觸發條件 ⇒ 不登記** | 條件①**成立**（出現 **1 條阻斷級**：`ORDER BY judgment_date DESC NULLS LAST` 無法由既有的 ASC NULLS LAST 索引滿足 ⇒ 全檔 `EXPLAIN` 都不是最終 SQL 的計畫）；條件②**不成立**——**那條阻斷級不是判準類**，是效能／事實類，沒有「本來會攔、改完不攔」那格。⚠️ 本輪**確實有**判準類 findings（法院「名稱」軸的集合相等只有計數證據 ⇒ 合法名稱可能從此回 400，2/2 獨立指到），但它們是**高**不是阻斷 ⇒ **兩個條件落在不同的 finding 上，AND 不成立**。不登記 hash。⚠️ 同上跑在 Opus，非樓層模型 |

### 2026-08-17 首跑的三個觀察（兩個刻意不改 body）

**① body 有一處硬矛盾 → 已修（這是 bug，不是新規則）。** Step 1 原文「Do not read the plan yourself beyond what Step 0 needs」與 Step 2 的條件式追加句（要求判斷「這是否判準類計畫」）互相打架——後者必然得讀計畫。P2 讀了、判對了，但照字面做的 agent 會漏掉追加句。已改寫成「讀計畫只為確定目標 repo 與判斷是否判準類，讀到能回答這兩題就停」。**修矛盾不需要 RED**：它不是新增規則，是原文自己說不清。

**② reviewer 之間對同一事實給出不同嚴重度 —— body 沒規定怎麼辦。不改。** P3 實地遇到兩次（分支問題：一判 blocking 一判 non-blocking，理由是「此 repo 沒有 CLAUDE.md 宣告過這條慣例」；pytest 環境：一當計畫缺陷、一歸「查不到」）。它自己的處理是對的：標明是分歧、保留兩邊判斷與理由、交使用者裁決、附自己的傾向但不代決。
**為什麼不寫進 body**：樓層模型（Sonnet）自己就處理對了 → 沒有 RED。依 `~/.dotfiles/claude/evals/README.md`「強模型上成對實驗兩臂沒差」那條的反面——**樓層模型上沒有失敗，就不構成加規則的理由**（Iron Law）。**翻案條件**：Haiku 或後續 Sonnet 跑出「自行裁決分歧、把一邊的嚴重度吞掉」→ 屆時加，並附該次逐字說詞。

**④ 六次受測中，受測 agent 五度做出 body 沒教、但正確的推理。** 逐一列出免得日後誤以為那些是 body 的功勞：P1 前瞻使用 Step 4 的 red flag；P1 區分「事實缺口 vs 政策決定缺口」；P3 處理 reviewer 間分歧；P6 自行援引 dossier 的「不要用調門檻消音」並論證其適用；P7 反駁「findings 變少＝收斂」並檢驗作者估計站不站得住。
**這對 E2 有直接含意**：樓層模型在這些點上餘裕很大，所以 brief 的邊際價值可能比想像小——成對實驗更該跑，而不是更不用跑。
（⚠️ P7 另有一項是 fixture 造成、非 body 缺口：它手上只有注入的 findings 摘要、沒有 reviewer 原文，於是誠實回報「無法轉述已查證為真清單」而**沒有編造**。真實流程中 orchestrator 持有完整回覆，不會遇到；但這個誠實反應本身值得記。）

### E2 首跑（2026-08-18）—— 結論：**不撤除 brief，但理由是這次的 fixture 不合格**

fixture＝`~/.dotfiles/claude/evals/setup-sandboxes.sh` 的 dp1。Sonnet，A（含 brief 三行）×2、B（移除那三行）×2，判準類追加句兩臂都有（它不是變因）。A 臂的 brief 指向中性複本，理由見上方 E2 設計的警語。

**結果**：四臂全判「不能開始執行」。阻斷級 findings 的聯集兩臂相同——核心那條（新豁免那一格混了「會自動脫離」與「永不脫離」兩種成員）四臂全中，V017 取自 fixture 而非現況資料四臂全中（B 有一臂降到高）。**依 E2 字面判準，這是「阻斷級零差異」，該撤除。**

**但不能這樣判，因為 fixture 把 5.7 的答案從一條更短的路徑洩出去了。** dp1 在 `src/upstream.py` 的 docstring 與 D-7 兩處明文寫出「合併案永遠不會自動脫離、目前唯一的提醒管道就是這條告警」。兩個 B 臂正是從這兩處**正面撞到**核心結論的，全程沒有做「既有豁免當初為什麼被允許、那個論證對新情況成不成立」這一步。實地那次不同：兩者成因不同是**要自己推的**，repo 沒有任何一處明文並列，所以全數 reviewer 皆漏。**dp1 讓 5.7 變成一條可繞過的路，於是它量不到「brief 是不是唯一到得了那裡的路徑」。**

分辨清楚兩件事：5.7 這條**判準**在兩臂是有差的（A 2/2 走完並比對了 D-3 的量化論證，B 0/2），差的是**推理路徑**；有差而阻斷級結論相同，恰恰是因為 fixture 給了替代路徑。**A negative result from a fixture with a bypass is not evidence that the rule is redundant.**

**重跑前必須先修的 fixture 缺陷**：

1. **5.7 的旁路**——把「合併案永不脫離」從 D-7 與 `upstream.py` docstring 的明文並列改掉，讓它只能由「讀既有豁免的論證 → 發現前提對新 kind 不成立」到達。
2. **5.3、5.4 四臂全漏**——這兩條的觸發點埋得太淡（5.3 的重犯推論與 5.4 的 Part A/B 互相抵銷都只在計畫內文，沒有 repo 端的錨）。全漏＝沒有鑑別力，等於這次只量到六條。
3. **`sync-error` 無產生來源**是 fixture 自己的不自洽（runbook 與測試都提到它，`classify()` 卻產不出），有一臂把它報成 finding。那是噪音，不是受測對象。

⚠️ **判準要在重跑前寫死，不能看到結果再調。** 上面三條全是**看到結果之後**才發現的，所以修完 fixture 屬於「修一個有旁路的量測工具」，**不是**把 fixture 調到想要的答案——區別在於**判準本身一字不動**：修完之後若阻斷級仍零差異、且 5.7 在 B 臂仍抓得到，就撤除 brief。

**一個 E2 設計沒列、但這次浮出來的效果**：B 臂沒有嚴重度分級可用，四臂各自造了一套（Critical／High／Medium／Info 對 阻斷／高／中／低）。findings 本身不受影響，但**跨 reviewer 的嚴重度不可比**——orchestrator 的 Step 3 要按「指向同一件事」合併並標重疊數，兩個 reviewer 對同一條給出不同刻度的分級會讓合併失真。這是 brief 的一個獨立價值面向，**與七條失效模式無關**，下次重跑一併量。

### E2 重跑（2026-08-18，dp1 v2 已堵旁路）—— 結論：**保留 brief 進 prompt**

同判準、同 prompt 結構，只換 fixture。**判準在跑之前就寫死**（見上節），一字未動。

| brief 條款 | A1 | A2 | B1 | B2 |
|---|---|---|---|---|
| §6 混了性質不同的子類（核心） | 阻斷 | 阻斷 | 高 | Critical |
| 5.1 fixture 當 prod（V017） | ✅ 明引 | ✅ 明引 | ✅ | ✅ |
| **5.7「跟既有 X 一致」** | ✅ 明引＋做了論證對稱性比對 | ✅ 明引 | ❌ | ❌ |
| 5.6 紅測試紅不起來 | ✅ 明引 | ✅ 明引 | ✅ | ✅ |
| **5.5 守門測試假綠** | ✅ | ✅ 明引 | ❌ | ❌ |
| **5.4 Part A/B 相互作用** | ✅ 明引 | ⚠️ 換個角度提到 | ❌ | ❌ |
| 5.2 矛盾→往上追 | ✅ 換算出效益虛高約 3 倍 | ❌ | ✅ | ❌ |
| 5.3 重犯已駁倒的推論 | ❌ | ❌ | ⚠️ 只說查無依據 | ❌ |
| 未列的相依（runbook） | ✅ | ✅ | ✅ | ✅ |

**阻斷級 findings 仍然零差異**——四臂指的是同一條，全部判「不能開始執行」。但寫死的判準有兩個條件，第二個不成立：**5.7 在 B 臂 0/2**。B1 甚至明確把那條路自己關掉（判定 D-3 談的是別的 kind、與本案不相關）——它看得到 D-3，只是不會去做「既有豁免當初的論證對新情況成不成立」那一步。**⇒ 不撤除。**

**brief 的價值不在核心那條，在覆蓋面。** 樓層模型自己就抓得到最嚴重的 finding（四臂全中，v1 v2 皆然）——這與本檔上面記的觀察④一致，Sonnet 在這類推理上餘裕很大。**brief 買到的是 B 臂系統性漏掉的那三條**：5.7、5.5、5.4 合計 A 5.5/6、B 0/6。清單外的失效模式它不會自己去找。

**E2 設計問的第三件事（反效果）：沒有觀察到。** A 臂沒有因為照清單掃而漏掉清單外的東西——findings 數不少於 B 臂，且 A1 是唯一把 5.2 換算到底的一臂。

**嚴重度可比較性（上節提出的觀察）確認**：兩個 A 臂用同一套刻度（brief 的阻斷／高／中），兩個 B 臂各自造了**兩套不同的**（Blocking／Moderate／Minor 對 Critical／Medium／Low）。orchestrator 的 Step 3 要跨 reviewer 合併同一件事並標重疊數，刻度不一致會讓合併失真。**這是 brief 與七條失效模式無關的獨立價值。**

**仍未量到的**：5.3 四臂全漏（v1 v2 皆然）。v2 已把觸發點改成「計畫自己駁倒單一快照推不出起始時間，接著又用它斷言 V017 從 2026-06 起」，仍無人指出那是同一型推論的重犯——B1 只說「查無依據」。**這條在 dp1 上目前是零鑑別力，不是「brief 讓人抓到它」的證據，下次設計 E1／E3 時要另找觸發形狀。**

**③「取得事實後重審」與「NEVER run a third round」的界線 —— body 措辭偏鬆。不改。** P2 結尾寫「建議作者依此清單修訂計畫後，再開一輪全新 reviewer」，字面讀起來像第三輪，但它同時明說「已達 2 輪上限，不再開第三輪」，且分流正確（阻塞是事實缺口 → 先取得資料）。body 的 Step 5 已寫「先把那些事實量出來／查清楚，**再回來重審**」，兩者實質一致——差別在那是**新的一場**（有新事實進來），不是同一場的第三輪。
**為什麼不寫進 body**：同 ②，樓層模型沒有做錯。**翻案條件**：出現「沒有任何新事實進來就直接再開一輪」的實例。
