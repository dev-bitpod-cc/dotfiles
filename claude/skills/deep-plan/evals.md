# Deep Plan — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**（避免 runtime 被載入）。
> 執行方式、沙盒建置、模型樓層政策、transcript 截獲法：`~/.dotfiles/claude/evals/README.md`（唯一權威）。
> **Sonnet = PASS 門檻**；Haiku PASS 加分；Opus 用來檢查是否過度解釋。

---

## 這份 evals 是 skill 的收斂判準（oracle）

判斷 deep-plan「對不對／改好了沒」以通過這份 evals 為準，**不以「再對 SKILL.md 跑一次審查找不找得到東西」為準**（理由見 `~/.dotfiles/claude/skill-building-guide.md`「避免 prose ratchet」）。

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
  "query": "/deep-plan <凍結的 final plan 路徑> <krepo 路徑>",
  "setup": "fixture 見下方「P4 的 fixture 與過期風險」。",
  "expected_behavior": [
    "至少一個 reviewer 抓到：新豁免那一格混了「會自癒」與「永不自癒」兩種成員",
    "判為阻斷或高（NOT 中/低）",
    "指出該格無上限、無升級路徑，且既有豁免的無上限有明文論證、新的沒有",
    "指出訊息「等上游收錄」對永不自癒那類是錯的建議"
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

---

## C. 待驗事項的實驗設計（SKILL.md「待驗事項」的驗證方式）

三項都是**成對實驗**，依 README：兩臂零差異就撤除該規則，且**必須在樓層模型（Sonnet）上量**——強模型會自己補上規則要求的行為，反而掩蓋規則的作用。

### E1 — N 的邊際收益

同一份計畫（P4 fixture）跑 N=2 / N=3 / N=4，量：獨有 findings 數、阻斷級 findings 的聯集是否增加、重疊率。
**判準**：N=3 相對 N=2 若沒有新增阻斷級 findings，維持預設 2。
（已知基線：2026-08-17 實地 N=2，重疊約 6/20，各自獨有 5–8 條。）

### E2 — `planner-brief.md` 進 prompt 的效果（最重要的一項）

**成對實驗**：A 臂 = 現行模板（含 brief 路徑）；B 臂 = 移除那三行、其餘逐字相同。同一 fixture、同模型、各跑 2 次。

量三件事：

1. brief 的七條失效模式各自被抓到的比例
2. **特別看 5.7（「跟既有 X 一致」）**——它是唯一實地全數 reviewer 皆漏的一條，若 A 臂抓到而 B 臂沒有，brief 就有獨立價值
3. 有沒有反效果：A 臂是否因為照清單掃而漏掉清單外的東西

**判準**：兩臂在阻斷級 findings 上零差異 → 依 README 的規則**撤除 brief 進 prompt**（改成只給 orchestrator 用於檢查 findings 完整度）。
⚠️ 實地量到有效的是**不含 brief** 的薄 prompt，所以這一項的預設立場是「brief 需要自證」，不是「brief 無罪推定」。

### E3 — 第二輪的實際產出

實地只跑到第一輪就判定不通過，第二輪從未執行過。需要一份真正走完 Step 4 處置的計畫，量：第二輪的 findings 是新的還是第一輪的重述、2 輪上限夠不夠。

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
| — | P4 | — | 未執行 | 需 krepo fixture（見上方「P4 的 fixture 與過期風險」） |
| — | E1–E3 | — | 未執行 | 見上方實驗設計 |

### 2026-08-17 首跑的三個觀察（兩個刻意不改 body）

**① body 有一處硬矛盾 → 已修（這是 bug，不是新規則）。** Step 1 原文「Do not read the plan yourself beyond what Step 0 needs」與 Step 2 的條件式追加句（要求判斷「這是否判準類計畫」）互相打架——後者必然得讀計畫。P2 讀了、判對了，但照字面做的 agent 會漏掉追加句。已改寫成「讀計畫只為確定目標 repo 與判斷是否判準類，讀到能回答這兩題就停」。**修矛盾不需要 RED**：它不是新增規則，是原文自己說不清。

**② reviewer 之間對同一事實給出不同嚴重度 —— body 沒規定怎麼辦。不改。** P3 實地遇到兩次（分支問題：一判 blocking 一判 non-blocking，理由是「此 repo 沒有 CLAUDE.md 宣告過這條慣例」；pytest 環境：一當計畫缺陷、一歸「查不到」）。它自己的處理是對的：標明是分歧、保留兩邊判斷與理由、交使用者裁決、附自己的傾向但不代決。
**為什麼不寫進 body**：樓層模型（Sonnet）自己就處理對了 → 沒有 RED。依 `~/.dotfiles/claude/evals/README.md`「強模型上成對實驗兩臂沒差」那條的反面——**樓層模型上沒有失敗，就不構成加規則的理由**（Iron Law）。**翻案條件**：Haiku 或後續 Sonnet 跑出「自行裁決分歧、把一邊的嚴重度吞掉」→ 屆時加，並附該次逐字說詞。

**④ 六次受測中，受測 agent 五度做出 body 沒教、但正確的推理。** 逐一列出免得日後誤以為那些是 body 的功勞：P1 前瞻使用 Step 4 的 red flag；P1 區分「事實缺口 vs 政策決定缺口」；P3 處理 reviewer 間分歧；P6 自行援引 dossier 的「不要用調門檻消音」並論證其適用；P7 反駁「findings 變少＝收斂」並檢驗作者估計站不站得住。
**這對 E2 有直接含意**：樓層模型在這些點上餘裕很大，所以 brief 的邊際價值可能比想像小——成對實驗更該跑，而不是更不用跑。
（⚠️ P7 另有一項是 fixture 造成、非 body 缺口：它手上只有注入的 findings 摘要、沒有 reviewer 原文，於是誠實回報「無法轉述已查證為真清單」而**沒有編造**。真實流程中 orchestrator 持有完整回覆，不會遇到；但這個誠實反應本身值得記。）

**③「取得事實後重審」與「NEVER run a third round」的界線 —— body 措辭偏鬆。不改。** P2 結尾寫「建議作者依此清單修訂計畫後，再開一輪全新 reviewer」，字面讀起來像第三輪，但它同時明說「已達 2 輪上限，不再開第三輪」，且分流正確（阻塞是事實缺口 → 先取得資料）。body 的 Step 5 已寫「先把那些事實量出來／查清楚，**再回來重審**」，兩者實質一致——差別在那是**新的一場**（有新事實進來），不是同一場的第三輪。
**為什麼不寫進 body**：同 ②，樓層模型沒有做錯。**翻案條件**：出現「沒有任何新事實進來就直接再開一輪」的實例。
