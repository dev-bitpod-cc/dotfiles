---
name: deep-plan
description: "深度計畫審查 — 在開工前用多個獨立 reviewer 查證一份實作計畫對 repo 現況的陳述、找出未驗證的假設與沒看到的相依。Use when the user has an implementation plan (or spec) ready and wants it checked before starting work, or asks whether a plan is safe to approve — including Chinese triggers 「審查計畫」「計畫審查」「這個計畫可以嗎」「開工前檢查」「plan review」「approve 前看一下」 — or runs /deep-plan. NOT for reviewing code that is already written（那是 /deep-review）、NOT for producing a plan（那是 plan mode 或 /project spec）."
user-invocable: true
argument-hint: "[plan_file] [repo]"
allowed-tools: Bash, Read, Glob, Grep, Write, Agent, AskUserQuestion
---

# Deep Plan

你是 orchestrator。**你不審查計畫本身**——你把計畫交給多個獨立 reviewer，收攏它們的 findings，追蹤每一條的處置，最後判定這批能不能開工。

計畫審查與 code review 是不同的工作：code 有客觀正確性，計畫沒有。計畫的可查證面是**它對 repo 現況的陳述**——某個函式存在、某個行為如此運作、某段歷史如此發生。那些是二元的、查得到的，也是這個 skill 的全部價值來源。

## 核心原則

### 並行多個 fresh reviewer，不是一個 reviewer 跑多輪

**每一輪都是 N 個全新的 reviewer 同時審同一份計畫**，彼此不知情、context 各自乾淨。輪與輪之間也不重用 reviewer。

這不是為了多採樣，是為了避開一個實地量到的失效：**同一個 reviewer 連續審修訂版本時，會把自己前幾輪的疑慮正當化。** 2026-08-17 實地（krepo 孤兒告警計畫）——一個 reviewer 在第一、二輪都指出「這類 finding 被移到 deferred 後就不會發通知」，接著接受了作者「這跟既有的 pre-listing 豁免一致」的說法，**最後一輪建議加測試把那個行為釘死**。同一份計畫交給兩個 fresh reviewer，兩個都在第一條 finding 就判它阻斷。

每一輪有作者的解釋在旁邊，疑慮被回應一次、被類比一次，第三輪 reviewer 已經站在那個行為這邊了。Fresh reviewer 沒有那些解釋。

> 與 `/deep-review` Step 4「不把上一輪 findings 傳給 subagent」形狀相同、**理由不同**：那裡防的是洩題（輪次、剩餘輪數）；這裡防的是**立場累積**。兩個理由都成立，**NEVER resume a reviewer across rounds — a fresh context is not an optimization, it is the mechanism.**

### The reviewers' verdict is NOT the pass condition

Reviewers 常會自發給出「修完這幾條就可以執行」這種條件式 approve。**那不是通過訊號，只是一份 findings 清單加一句樂觀的結論。**

實地：同一份計畫的六次獨立審查，三次給了條件式 approve——而那三張 green light 全都會放行一條「本來會告警的類別從此永久靜默」的缺陷。**挖得淺的 reviewer 也會給出條件式 approve，外觀跟挖到底的完全一樣。**

通過判定看的是 findings 的處置狀態與第二輪的結果（見 Step 5），不是任何 reviewer 說了什麼。

### Reviewers report; they never rewrite the plan

Reviewer 交出的是 findings 與判斷。**一旦它交出一份改好的計畫，它下一輪就是在審自己的產出**，作者/reviewer 分離當場失效，而且失效是靜默的——它會傾向確認自己那版。修不修、怎麼修是計畫作者的事。

### 兩層判準

判準的完整定義在 `~/.claude/skills/deep-plan/references/planner-brief.md`（reviewer 與 orchestrator 共用同一份，**本檔不重述**）。分層的用意在此說明一次：

- **可查證層 → blocking。** findings 的真假去 repo 查就知道：事實假設、完成判定、未列的相依。
- **判斷層 → non-blocking。** 步驟順序、有沒有更短的路、失敗模式沒寫。沒有 oracle，讓它 block 就是深井入口。

實地：約 30 條 findings 裡幾乎沒有「這個設計可以更好」的深井——計畫這種 artifact 的噪音本來就低，不需要第二道防線。**但這道分層仍是硬的：一條 finding 若要靠「先做一版看看」才能判真假，它不是計畫的問題，是計畫的下一步。**

## 執行流程

開始前，orchestrator **複製以下 checklist 進回應**並逐項打勾：

```
Deep Plan 進度：
- [ ] Step 0：計畫落成檔案（在對話裡就先寫檔；NEVER 把計畫內文當 prompt 字串）
- [ ] Step 1：確定目標 repo 與 reviewer 數 N
- [ ] Step 2：並行 spawn N 個 reviewer（固定模板，判準交路徑）
- [ ] Step 3：彙整 findings、按「指向同一件事」去重（不按嚴重度排）
- [ ] Step 4：逐條取得處置（修 / 駁＋理由 / 接受為 trade-off）——不允許「看過了」
- [ ] Step 5：第二輪 N 個全新 reviewer → 通過判定（上限 2 輪）
```

### 0. 計畫落成檔案

計畫還在對話裡（plan mode 的產出、使用者貼上的文字）→ **先用 Write 工具寫成檔案**，再往下走。位置優先序：repo 的 `docs/plans/<slug>.md`（該目錄存在時）→ scratchpad。

兩條硬規則，理由各自不同——**不要把它們的理由混起來**：

- **NEVER write the plan file through the shell.** 落檔一律用 **Write 工具**；**NEVER `cat <<EOF`／`echo`／`printf`**。計畫內文幾乎必然含反引號（`` `檔名` ``、`` `指令` ``）與 `$(…)`，而 unquoted heredoc 與雙引號語境都會把它們當命令替換**真的執行**（實地事故見 `~/.dotfiles/claude/known-hazards.md`）。
  ⚠️ **這條的適用範圍僅限「經過 shell 的落檔路徑」。** Agent 工具的 prompt 是 **JSON 參數、全程不經 shell**，那裡沒有命令替換、沒有這個風險——**NEVER 把這條外推過去**（同一個外推曾讓人誤改三處程式碼並把錯誤結論寫進四個地方，見同一份 hazards）。
- **NEVER pass the plan's text as a prompt string.** 理由**不是**執行風險，是這兩個：①主 context 成本——同 `/deep-review` 的「Hand the subagent the *range*, not the diff text」，reviewer 自己 Read 檔案，內容不必經過你；②跨輪要有一份可指向、可修訂的單一來源，Step 4 的處置就是對著這份檔案改的。

計畫已經是檔案 → 直接用，不要複製一份（複本會漂）。

### 1. 確定範圍

- **目標 repo**：計畫要動的那個 repo（**不必然是 pwd 的 repo**——計畫檔可能在別處）。確認它存在、是 git repo。
- **N（reviewer 數）**：預設 **2**。使用者要更廣的覆蓋 → 3–4。
- 計畫涉及多個 repo → 在 prompt 裡列出全部路徑，reviewer 自行判斷跨 repo 一致性（同 `/deep-review` 的做法，不拆多組 reviewer）。

**Do not form your own judgement of the plan.** 你是 orchestrator，讀計畫只為兩件事：確定目標 repo，以及判斷它是否落在 Step 2 那個條件式追加句的範圍（判準／權限／豁免規則類）。**讀到能回答這兩題就停。** 把整份計畫的優劣拉進主 context 會讓你開始形成自己的評分，而那個評分之後會汙染你對 findings 的取捨——你的工作是收攏與追蹤，不是評分。

### 2. 並行 spawn N 個 reviewer

**同一則回應內發出全部 N 個 Agent 呼叫**（並行，不是逐個等）。全部用**同一份 prompt**、同一個 model——差異來自獨立採樣，不需要刻意讓它們側重不同的東西（實地：兩個同模型、同 prompt 的 run，重疊約 6/20，各自獨有 5–8 條重要 findings）。

照下列模板構造，只替換 `{}` 內的變數槽：

```
你要審查的是一份**實作計畫**（plan），不是程式碼——這份計畫描述的改動**還沒有任何一行被寫出來**。請用審查計畫的方式看它，不要用 code review 的方式。

計畫檔（請完整讀完）：
  {計畫檔絕對路徑}

計畫要動的 repo：{repo 絕對路徑}{多 repo 時逐一列出}

**這個 repo 對你是唯讀的。NEVER modify, create, or delete any file under it. NEVER run any git command that mutates state.** 讀檔、搜尋、看 git log 都可以。

你的工作：判斷這份計畫**照著做下去會不會出問題**。計畫裡對這個 repo 的現況做了大量陳述（某個函式存在、某個欄位有幾欄、某組測試在某幾行、某個模組可以 import、某個常數叫什麼名字、某個行為是如此運作、某段歷史事實如此發生）——**這些都去 repo 裡實際查證，不要憑計畫的說法採信**。查得到的就查，查不到就說查不到。

除了事實查核，也看：這份計畫做完之後，怎麼知道它真的做到了？有沒有東西被計畫碰到但它沒提到？步驟的順序有沒有問題？

審查判準與已知的失效模式 — Read this file completely before scoring anything:
  ~/.claude/skills/deep-plan/references/planner-brief.md
它定義了嚴重度分級、通過標準，以及一份實地累積的失效模式清單。Follow it as written; do not substitute your own standards.

**Do NOT rewrite the plan.** 你的產出是 findings 與判斷，不是一份改好的計畫。指出問題在哪、為什麼是問題、你查證的依據是什麼；要不要改、怎麼改是計畫作者的事。

輸出（繁體中文）：
1. 每條 finding：問題、嚴重程度、你的查證依據（檔案:行號 或 你跑的指令與結果）
2. 一份「已查證為真」清單（讓作者不必重查）
3. 明確標出哪些陳述你查不到（需要 prod DB／外部服務／即時網路）
4. 最後給一句明確結論：這份計畫現在可不可以開始執行？

你的回覆全文就是回傳值，不是給人看的訊息——直接給內容，不要寒暄或前言。
```

**變數槽只有這些**：計畫檔路徑、repo 路徑。其餘一字不改。

**MUST NOT appear anywhere in the prompt** — these are leak channels that recreate the very failure this skill exists to avoid:

> 這是第幾輪、跑過幾輪、上一輪的 findings、作者對某條 finding 的解釋或反駁、「請確認前一輪的問題是否修好」、「這份計畫已經審過幾次」、或任何暗示計畫接近完成的說法。

輪次是 **orchestration 層的私有狀態**。作者的解釋尤其不能進去——**那正是立場累積的傳染途徑。**

> 計畫涉及告警判準、權限、豁免規則這類「決定什麼情況會被放行」的改動 → 在模板的「你的工作」段後追加一句：`特別注意這份計畫改的是一組判準：請具體想清楚，改完之後哪些真實存在的個體／情境會落進哪一格，以及有沒有本來會被攔下的東西會從此通過。` 這句話在實地讓兩個 reviewer 都把最嚴重的缺陷放在第一條。其他類型的計畫不加。

### 3. 彙整與去重

- **按「指向同一件事」分組**，不按嚴重度排列。多個 reviewer 從不同證據出處指到同一個問題 → 合成一條、把證據並列。**證據出處不同不代表是兩條 finding**，但也**不要**因為合併就丟掉任一條的依據——不同出處常互補（一個給機制、一個給實例）。
- **重疊是強訊號**：N 個 reviewer 獨立指到同一件事，該條的可信度顯著高於單一來源。在報告裡標出重疊數。
- 各 reviewer 獨有的 findings **一律保留**，不因為只有一個 reviewer 提就降級——實地獨有的那些包含了整批唯一會推翻計畫前提的一條。
- 把「已查證為真」清單也合併呈現：它讓作者不必重查，價值不低於 findings。
- **You are stitching, not filtering.** 不加工、不篩選、不淡化嚴重度、不替 reviewer 判 false positive。

### 4. 逐條處置

把彙整結果交給計畫作者（使用者，或產出計畫的那個 session）。**每一條都必須有明確處置，三種之一**：

| 處置 | 意思 | 要求 |
|---|---|---|
| **修** | 改計畫 | 改的是 Step 0 那份檔案 |
| **駁** | 判為 false positive | **必須附理由**，且理由要指向 repo 事實 |
| **接受** | 確認是真的，但選擇當 trade-off 帶著走 | 寫進該 repo 的 dossier（STATUS.md 決策節）；**沒有落點的「接受」不算處置** |

**"Noted" / "看過了" / silence is NOT a disposition.** 一條 blocking finding 沒有上述三種處置之一 → 這批不通過，不進 Step 5。

> **Red flag — 立場累積正在發生**：作者用「這跟既有的 X 一致」來駁一條 finding，或提議「加個測試把這個行為釘死」，而該行為正是這條 finding 質疑的東西 → **這條要重新當 open 處理**，並依 brief 的對應條款查 X 當初的論證是否對新情況成立。實地失效即為此形狀。

### 5. 第二輪與通過判定

處置完成後，**spawn N 個全新的 reviewer**，同一份模板、同一份（已修訂的）計畫檔。**不是 resume，不是延續，不告知有過第一輪。**

通過判定：

| 第二輪結果 | 判定 |
|---|---|
| 無 blocking finding | **通過**，可以開工 |
| 有 blocking，但全部指向第一輪已「接受為 trade-off」的項 | **通過**（那些已有決策落點），報告中列出 |
| 有新的 blocking | **不通過** |

**上限 2 輪。** 第二輪仍有新 blocking → 停止，輸出報告交使用者，並依內容分流：

- findings 集中在**事實假設**（計畫講的 repo 現況不對）→ 先把那些事實量出來／查清楚，再回來重審。多數情況這是唯一真正的阻塞。
- findings 已經在動**判準本身或架構**（不是補細節）→ **回 `/project spec` 重談 Goal**，不要再審一輪。計畫改到第三輪還在動架構，代表這個工作項本來就沒談清楚。

**NEVER run a third round to try to converge.** 第三輪能挖到的多是同類型的東西，而每一輪都是新的 N 個 reviewer 對同一搜尋空間的無偏抽樣——它會一直找到東西，那不是收斂訊號。

## 報告

輸出給使用者的報告至少包含：

1. **findings 按根因分組**，每條標明：嚴重度、重疊數（幾個 reviewer 獨立指到）、查證依據、處置狀態
2. **「動任何一行 code 之前必須先取得的事實」**——單獨一節。可查證層的 findings 裡，凡是「repo 內查不到、需要 prod／外部資料才能定案」的，全部集中在這裡並附取得方式。**這一節通常就是真正的阻塞所在**，其餘多半是動工時一併處理。
3. **已查證為真的清單**（作者不必重查）
4. **明確標為未驗證的陳述**（reviewer 查不到的）
5. **通過 / 不通過**，以及不通過時的分流建議

計畫涉及多個獨立可交付的部分（如兩個序列化的 PR）→ 逐部分判定，**其中一部分可以先走不代表整批通過**；但要點明各部分之間的共用變數，那些必須在第一部分落地前定案。

## 與其他 skill 的關係

- `/project spec`（開工寫 spec）→ **本 skill**（開工前審 spec/plan）→ 實作 → `/deep-review`（審已寫出來的 code）→ `/project log`（ship）
- 本 skill **不寫計畫、不改計畫、不 commit**。Step 4 的修改由計畫作者執行；Step 0 產生的計畫檔留在 working tree，由 `/project log` 一起送出。
- `/deep-review` 審的是 code，本 skill 審的是還沒寫成 code 的計畫。**兩者的判準不通用**——不要把 `~/.claude/skills/deep-review/references/reviewer-brief.md` 交給 plan reviewer。

## 待驗事項

核心機制有 2026-08-17 的實地量測支撐（並行 vs 多輪、假 green light、兩層判準的噪音率、reviewer 不重寫）。另有**兩項**參數尚未經成對實驗驗證（原本三項，其中一項已於 2026-08-18 跑出兩臂有差、據此保留）——**哪些項、實驗怎麼設計、目前狀態，全部記在本 skill 的開發期評測集**（刻意不從本檔連結：那是 oracle，不該進 runtime context）。

**它們在本檔的效力不變，照上面的 SOP 執行。** 「這項還沒被驗證」永遠不是放寬它的理由——要放寬得先跑出兩臂有差的成對實驗。
