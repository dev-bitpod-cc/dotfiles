# dossier 治理：問題陳述、已評估的處理方式、與遇到的死結

- 日期：2026-08-19（**v4**——取代 v3；v1／v2／v3 依 `AGENTS.md:41` write-once 凍結不改）
- 性質：**問題陳述與選項評估**，不是實作計畫
- 目的：請第三方審查「這個問題該用什麼方式解」

## ⚠️ 先講一件與內容無關但更該先知道的事：本 session 三次違反 write-once

`AGENTS.md:41` 規定 `docs/plans/*.md` 是 **Write-once：frozen at publication，被更新的權威取代，但不就地改寫**。本 session 違反三次：

| # | 違規 | 補救 |
|---|---|---|
| 1 | 分片計畫 v1→v2→v3 全部就地覆寫同一檔 | 已從 git 逐 byte 還原成 `-v1.md`／`-v2.md` |
| 2 | 問題陳述 v1 就地增修 | 當場還原，修正落成 v2 |
| 3 | **問題陳述 v2（`516ab09` 發布）又被 `6b563ce` 就地增修** | v2 已還原成 `516ab09`，修正落成 v3 |
| — | v3 起改為**每輪另開新檔**，不再就地改寫 | 本檔 v4 即依此產生 |

第 3 次最難看——它發生在**報告前兩次違規的同一則訊息裡**，用一個我自己發明的例外（「未交付、未被引用即可原地修改」）正當化，而 `AGENTS.md:41` **沒有這個例外**。⚠️ **一份論述治理的問題陳述，本身反覆違反它所受的治理規則**——這個事實本身就是〈四〉「失效形狀」的一個樣本，且是第三方抓到、不是我自己發現的。

## v4 相對 v3 的修正（第三方第三輪，7 條）

| # | 判定 | 處置 |
|---|---|---|
| G1 latch 鍵不足（缺 `agent_id`／compact 未重設／corpus revision 只認 commit） | **真陽性** | §5.2 latch 重設計 |
| G2 覆蓋面宣稱過大——**`PreToolUse` 是 Claude Code 專屬，而本 repo 契約涵蓋 Codex** | **真陽性，且我完全沒想到** | §5.2 成功條件縮小，跨 agent 列為未解 |
| G3 schema 把「事後結構化」變成「捕捉時強制結構化」 | **真陽性，文件內自相矛盾** | §5.2／Q3 改為最小 capture event ＋ enrichment |
| G4「官方已明載 additionalContext 時序／`@file`／Glob-Grep schema」 | **不成立（第二次）** | 見下方〈G4 的驗證〉 |
| G5 同一證據又判無效又拿來支撐 | **真陽性** | 附錄 C.5 修正 |
| G6 附錄 B 未凍結機隊量測 | **真陽性** | 附錄 B 補凍結表 |
| — `:471` 殘留「未另開 v3」 | **真陽性** | 附錄 C.4.6 改寫 |

### G4 的驗證（**這條我不接受，附證據**）

第三方**連續兩輪**主張官方已載明。我以**同一次 WebFetch、同一個 `code.claude.com/docs/en/hooks`** 查證：

| 宣稱 | 結果 |
|---|---|
| `agent_id` 存在 | ✅ **確認**：*"Present only when the hook fires inside a subagent call"* |
| `PostCompact` 事件存在 | ✅ **確認**：*"After context compaction completes"* |
| `additionalContext` 在「下次 model request」才讀到 | ❌ **Not present** |
| `@file` 不觸發 `PreToolUse` | ❌ **Not present** |
| Glob／Grep 的 input schema | ❌ **Not present** |

**同一頁、同一次抓取，五項中兩項逐字抓到、三項沒有** ⇒ 不是工具或頁面版本問題。

⚠️ **若成立，結論不變**（都要 deny-first），只是理由從「不賭未定義行為」變成「依已定義時序」。**但把未載明寫成已載明，正是本文件〈附錄 D〉列的失效形狀之一，不能因為結論相同就照收。** 若官方在 hooks reference **之外**載明，請提供具體段落。

## v3 相對 v2 的修正（第三方第二輪，6 條）

| # | 判定 | 處置 |
|---|---|---|
| F1 write-once 違規 | **真陽性** | 見上表 |
| F2a deny-first 缺 latch → 無限迴圈 | **真陽性**（純邏輯） | §5.2 補狀態機 |
| F2b「官方已明載 additionalContext 時序」 | **不成立** | 重抓官方文件，**仍未載明**。原本「不賭未定義行為」的寫法維持 |
| F2c `@file` 不觸發／各工具 `tool_input` 形狀 | **未經文件證實**，機制上合理 | §5.2 列為推論並標明 |
| F2d hook 輸出 **10,000 字元上限** | **真陽性、新資訊** | 官方明載，§5.2 補溢出處置 |
| F3「13 天零修訂」不是可觀察證據 | **真陽性** | §5.2 補行為 eval 為前置 |
| F4 文獻支持結構化索引、非裸路徑搜尋 | **真陽性** | §5.2 改寫，見下 |
| F5 always-on 衝突未清乾淨 | **真陽性** | `docs/dead-ends.md` 本批同步修 |
| F6 附錄 B 不能重現、年度投影基數 | **真陽性** | 附錄 B 改用 `git show`，投影拆三口徑 |

## v2 相對 v1 的修正（第三方第一輪，5 條全真陽性）

| # | v1 的錯 | 修正 |
|---|---|---|
| 1 | §4.2 的死結建立在錯前提上 | `docs/dead-ends.md:4` 曾寫「STATUS.md（always-on）」，**那是錯的**——該檔不自動載入。**三角互鎖因此不成立**，見 §4.2 |
| 2 | 真正的第三條路被埋在「判定不做」的表格列裡 | `hook`／`倒排索引` 在 v1 全文**零命中**；且其觸發條件是循環依賴。已升為 §5.2 獨立方案 |
| 3 | §二 稱「指令附在括號內」而全文指令數為 **0** | 改附〈附錄 B〉真實指令，並標明「11 次 churn」是手工分類、裸指令得 21 |
| 4 | P4 權威狀態衝突 | `backlog.md` 與 `STATUS.md` 說「待實例化」、`evals.md` 說「已實例化」。已同步 |
| 5 | 「7 個 commit」 | 實為 **6**（`origin/main..HEAD`） |

⚠️ **v1 的其他數字第三方逐項複驗，本文未改動者即為複驗通過。**

---

## 一、目標

`STATUS.md`（dossier）是本 repo 與機隊 11 個 repo 的專案單一事實來源，隨 git 跨主機、隨專案移交。它記四類東西：**進行中的工作**、**關鍵決策（附理由）**、**死路（試過但放棄，防重工）**、**已完成里程碑**。

使用者要達成的是三件事，**優先序由高到低**：

1. **保留這套機制的價值** —— 決策與死路真的被記下來、日後找得回來。使用者明說「這套機制我本身是覺得不錯」
2. **消除治理成本** —— 現況是每隔幾天就要處理一次量體 flag，使用者三次反映（2026-08-14、08-15、本次），原話：「**花了這麼多成本，再沒幾次又要來了**」
3. **可長久運行、有 scalability** —— 不是再撐三個月，是結構上不會週期性復發

### 使用者另外提出的兩個約束

- **token 成本會跟「每次都要讀取的規模」拉扯** —— 治理本身要讀規範與被治理物，若治理花的 token 多於它省下的，就是負 ROI
- **「需要或有用處但是查不到，這有意義嗎？」** —— 使用者明確表態：**找不到就等於沒存**。因此任何「把內容搬到別處」的方案，若不同時解決可檢索性，就不算解

---

## 二、量到的事實（供獨立驗證）

所有數字為 2026-08-19 實測，重現指令見〈附錄 B〉。⚠️ **`STATUS.md` 是活動靶**——本文數字量於 `c567204`。

### 2.1 本 repo 現況

| 節 | bytes | 有界？ |
|---|---|---|
| 關鍵決策 | 8904 | 無界 |
| 死路 | 7175 | 無界（設計上「不刪」） |
| 已完成里程碑 | 2326 | 半有界 |
| 進行中 | 930 | 有界 |
| 其餘四節 | 1338 | 有界 |
| **合計** | **20673** | 門檻 `DOSSIER_MAX_BYTES=24576` |

- 種子（首次 commit `1d96e45` 2026-07-16）4051 B，34 天 → **489 B/日**
- 年度投影**三個口徑不同，v1/v2 混用過**（第三方抓出）：
  - **一年新增量**：489 × 365 ＝ 178,485 B ＝ 門檻的 **7.26×**
  - **從種子起算一年後的檔案大小**：4051 + 178,485 ≈ 182,536 B ＝ **7.43×**
  - **從量測當日再過一年**：20,673 + 178,485 ≈ 199,158 B ＝ **8.10×**
  ⇒ v1 寫的「199KB／8.1×」是第三個口徑，但被放在「489 B/日 ⇒」後面，讀起來像第一個。三者都遠超門檻，定性結論不變。

### 2.2 成長來源的分解（**這是最關鍵的一組數字**）

| 時點 | 全檔 | 死路節 | 決策節 |
|---|---|---|---|
| 2026-07-16（種子） | 4051 | 500 | 1026 |
| 2026-08-08 | 22580 | 1791 | 4608 |
| 2026-08-14（死路分層當日） | 22098 | 3003 | 6620 |
| 2026-08-19 | 20673 | 7172 | 8901 |

- 全窗 34 天：決策 +7875（232 B/日）、死路 +6672（196 B/日）
- **近 11 天：死路 +5381（489 B/日）、決策 +4293（390 B/日）** —— 死路已成為較大的貢獻者

### 2.3 鋸齒

2026-08-05 ~ 08-19（15 天）之間 `STATUS.md` 反覆被壓縮，多數時間活在建議目標（20889，門檻的 85%）以上。

⚠️ **「壓縮次數」不要用「STATUS.md 負增量」去數** —— 本 repo 已把那個代理指標明文記為死路（`docs/dead-ends.md`「STATUS.md 負增量當壓縮代理」：正解是數 flag 實際處置的 commit）。三個獨立 reviewer 分別數到 11／14／19，無一致值。

### 2.4 歸檔（現行的唯一出口）已經失效

`docs/archive/decisions-2026-08.md`：

- **68354 bytes、110+ 條**
- **28 次 commit 全部 `-0` 純 append**，13 天零修訂
- `STATUS.md` 只有 **2 條**指標指得進去
- 它**已經是嚴格按月分片的**（07 檔內 23 條全為 2026-07、08 檔內條目全為 2026-08）

### 2.5 機隊（11 個 repo，量測時刻 2026-08-19 13:49）

- **3 個已超標**：evint 28565、ml-env 26367、krepo 170637（krepo 為拆分期間**明文豁免**，帶失效條件，全機隊唯一）
- **4 個在 2 天內撞牆**：pilot-api 1.5 天、kapi-protocol 1.6、kapi-gateway 1.7、krepo-judicial 1.8
- dotfiles 累積率 489 B/日 **倒數第三**（扣除移轉種子後）
- **11 個 repo 無一採用死路分層**（無任何 repo 有 `docs/dead-ends.md`）；死路節 krepo 18960、evint 7402
- 條目形狀 2 種、歸檔慣例 4 種、5 個 repo 完全沒有 `docs/archive/`

### 2.6 治理面本身的體積

| | bytes |
|---|---|
| 被治理：`STATUS.md` | 20673 |
| 治理機制：`dossier.md` 12607 ＋ `ship-state.sh` dossier 段 20019 ＋ `xref-gate.py` 17049 ＋ 治理計畫 11603 ＋ tests 9474 | **70752（3.4×）** |
| 被排出去：`docs/archive/*` 93355 ＋ backlog/dead-ends 29274 | 122629 |

⚠️ **池子邊界未定義（第三方抓出）**：上表的「治理機制」含一份 11,603 B 的舊治理計畫，卻**排除**本問題陳述自身（v3 約 35KB）與三版分片計畫。若把所有「為了治理而寫的文件」都算進去，倍數會更高；若只算**機械層**（`ship-state.sh` dossier 段 ＋ `xref-gate.py` ＋ tests ＝ 46,542 B），則是 **2.25×**。**引用 3.4× 時必須同時說出用的是哪個邊界。**

---

## 三、已評估的處理方式

### 3.1 已落地、有效

| 做法 | 日期 | 結果 |
|---|---|---|
| **backlog 分家**（技術債＋已知缺口移出 `STATUS.md`） | 2026-08-15/16 | ✅ **有效**。當日 23564 → 15007 B。判準是**生命週期**：待辦「壓不動」（只能壓字數、條目數不會少），對它套量體門檻無效 |
| **死路分層**（結論留 `STATUS.md`、證據移 `docs/dead-ends.md`） | 2026-08-14 | ⚠️ **部分有效**。死路節 5123→3006，但 5 天內回到 7175。⚠️ 機隊零採用 |

> **「死路」不是本地發明**：它在 Design Rationale（DR）研究裡是核心關切，稱 **rejected alternatives**。該領域文獻明載其動機與本 repo 的「防重工」一致——*"Insufficient documentation of alternatives that were considered and rejected can lead to maintainers **reinventing the wheel** by going down the already considered paths."* 相關體系：IBIS（Rittel）、QOC（Questions-Options-Criteria）、DRed。**取得方式與待查證點見〈附錄 C〉。**

### 3.2 已明文否決（不要重提）

| 提案 | 否決理由 | 出處 |
|---|---|---|
| OpenWiki | 官方定位為 derived 層，與 dossier 明文不記的東西正交——**死路在程式碼裡沒有痕跡，掃描器掃不出不存在的東西** | `2026-08-14-dossier-governance.md` |
| Linear／外部 tracker | 缺的是慣例固化，不是新工具 | 同上（2026-07 已否決） |
| mem0／Zep／Letta | 違反三條硬約束：**git 唯一媒介／隨 repo 移交／不引入第二份權威**。同一架構在 repo 內已有（`claude/CLAUDE.md` always-on ＋ `known-hazards.md` 按需） | 同上 |
| 「已決議暫不做屬決策節」寫進規範 | 成對實驗兩臂零差異 | Scenario 17 |
| 「從超出常態佔比的節收」 | 超出可能來自誤放而非該節本身肥 | 同上 |

### 3.3 本次評估、判定不做

| 提案 | 理由 |
|---|---|
| **ADR（一決策一檔）** | ⚠️ **理由已於 2026-08-19 更換**——原本寫「一年 1500 檔太多」，實測樣板開銷只有 +19%（MADR 最小樣板 108 B / 中位條目 552 B），**檔案數本身不是好理由**。<br>**現行理由三條**：①**ADR 只覆蓋決策**，而近 11 天成長主力已是死路（489 vs 390 B/日），決策全 ADR 化後主要成長源原封不動；②**ADR 不解召回**——68KB archive 13 天零修訂不是難找而是沒人想到要找，1500 個檔會讓「不知道要查」更嚴重；③**粒度不匹配**：114 條裡 20% 不到 400 B（多為「撤回自己提的 X，因為 Y」），叫它 ADR 會稀釋 `krepo` 那 5 份真 ADR 的訊號——**那正是 ADR 社群第一條批評的內容**。<br>⚠️ **另有一條更強但證據較弱的理由**（DR 文獻推論）：ADR 的樣板提高**每次記錄的成本**，而 intrusiveness 是文獻指認的捕捉失敗主因，**捕捉是本 repo 唯一已經解決的那一半**。**該推論的取得方式與威脅見〈附錄 C〉。**<br>⚠️ **ADR 的真實好處也要記**：沒有任何檔會長大（門檻問題永久消失）、格式統一。<br>⚠️ `krepo` 的 `docs/decisions/` ADR（5 份，收「新的重大技術選擇」）是對的且應保留——不同粒度 |
| **收緊「什麼該記成決策」的判準** | v1 曾據「4.4 條/日排第 5、B/日 倒數第三」否決，**該否決已撤回**——前者重現不出（獨立重算為機隊第 2）、後者是循環論證（率低正因為歸檔頻繁，而那正是被抱怨的事）。**現況：未評估，不是已否決** |
| **本地 file-based 向量庫**（sqlite-vec／LanceDB／vectorlite） | 語料僅 ~200 條/300KB，暴力算 cosine 即可，不需要 DB；且**精確路徑比對比語意相似更準**。⚠️ 三條硬約束**都不違反**（衍生物、gitignored、可從 md 重建），故不在 mem0 那條否決範圍內。真正的缺口是**觸發**不是儲存。⚠️ **v1 把後續方案埋在這一列而未指名，是 v1 的重大缺陷**——完整方案已移出，見 §5.2 |
| **給新落點設全檔量體門檻** | 無界內容設上限就是鋸齒的來源 |

### 3.4 本次的主方案：分片（**三版皆被審查判定不通過**）

原則：**有上限的檔只能裝有界的內容；無界的內容必須分片，而分片鍵要等於檢索鍵。**

檢索鍵判定：決策與死路 → **領域**（「我要動 X，這裡以前決定過什麼／踩過什麼雷」）；里程碑 → **時間**。

三版的演進與被推翻的原因見〈四〉。

---

## 四、遇到的困難

### 4.1 三版計畫，每一版都被兩個獨立 reviewer 判不通過

| 版本 | 範圍 | 致命問題 |
|---|---|---|
| **v1** | 決策/里程碑按**時間**分片、死路按領域 | ①「歸檔用大小當分片鍵」的歸因**不成立**——既有歸檔已按月分片；②月檔規模低估 8.5×，`docs/decisions/2026-08.md` 落地當刻就是 68KB，**與被診斷為失效的那份檔逐 byte 相同** |
| **v2** | 三類全改領域/時間分片 | **死路那一支自我抵銷**：「結論與證據同檔」使 11 條合併後 912–2436 B **全部超過 800 B 單條上限**，而 flag 的處置（蒸餾／拆條）**正是「死路不刪」禁止的動作**；換另一種檔案形狀則 gate 恆綠 0 命中。且 `dossier.md:119` 明文「條目 flag 不掃死路節……**全靠分層這一條**」——廢掉分層等於讓死路從「有一條規則管」變成「什麼都不管」，而機隊 11 repo 無一採用分層 |
| **v3** | **縮範圍：只做決策＋里程碑，死路不動** | **只買到 31 天**（見 4.2）。另有 §3.4 與 §4 步驟 2 對同一批 34 條給出互斥指令等 8 組重疊 findings |

### 4.2 結構性死結（**這是最需要第三方意見的地方**）

```
死路一起改  →  設計自我抵銷（800B 上限 vs「不刪」），且會傷 11 個未遷移的 repo
死路不動    →  遷移後 STATUS.md ≈ 9449 B，只靠死路 489 B/日 → 31 天後重新撞牆
```

**兩條路都不通，而問題不在計畫寫得好不好：分片這個手段對死路無效，而死路正是目前的成長主力。**

v1 曾主張死路有三條互鎖規則：①不刪 ②要能在你沒想到要查的當下擋住你 → 結論必須留在會被讀到的地方 ③無界。

⚠️ **這個互鎖不成立**（第三方審查抓出，已複驗）：規則 ② 的原始論證是「**規則不在 always-on 就不生效，故結論留 STATUS.md**」（`STATUS.md` 死路節頭），**但 `STATUS.md` 本來就不自動載入**——`2026-08-14-dossier-governance.md:47` 與 `claude/skills/project/SKILL.md:192` 兩處明載。`docs/dead-ends.md:4` 曾寫成 always-on，那是錯的（已修）。

⇒ **「沒想到要查時擋住你」現行機制從來沒有達成過。** 它不是一條會被新設計打破的約束，而是一個**從未滿足的目標**。

修正後的正確描述：
- **強形式（always-on）從未滿足** —— 所以搬走不會失去它
- **弱形式（ship 時必然被讀，`/project log` Step 2）確實成立且會被打破** —— 這是搬走的真實損失，但它遠弱於原本宣稱的
- ⇒ **死結消失，問題退化成「儲存」與「召回」兩件可獨立處理的事**（見 §5.2）

**但 4.1 的兩難仍然成立**：死路一起改會撞上 800B 上限 vs「不刪」；死路不動則只買到 31 天。差別在於這是**分片這個手段的侷限**，不是結構定理。

### 4.3 反覆出現的失效形狀（三版共通）

三輪審查、六個獨立 reviewer，**blocking 沒有一條打中診斷**（「無界內容放進有上限的檔」四個 reviewer 都認可），全部落在兩處：

- **盤點的池子邊界**：v1 拿同一量測口徑套兩種對象；v2 把 34 條非決策條目算進分母；v3 把它們排除出分母卻在執行步驟塞回同一個分子
- **補償機制寫成一句話而沒驗證它成不成立**：v2 的死路 800B 上限、v3 的 append-only 豁免（實測那道 gate 擋的是**章節名**不是排序，根本不需要豁免）、v3 的 stale gate 修法（方向講反，且提出的修法會讓它永不亮）

### 4.4 治理成本本身的量化

- 一次歸檔處置釋出約 4KB ≈ 1200 tok，買 3 次 ship ⇒ 省 ~3600 tok
- 執行一次要讀 `STATUS.md`（6180 tok）＋判斷「收哪節、哪幾條」的來回
- ⚠️ v1 曾宣稱「還要讀 `dossier.md` 3808 tok」，**該數字已撤回**——`dossier.md` 是 `references/`、按需載入，`project/SKILL.md:186-189` 設計上讓一般 ship 不必打開它
- **ROI 為負的方向成立，幅度未精確重算**

### 4.5 規則變更本身也是成本

自 2026-08-06 起，dossier 機制**本身**被改了 11 次（約每 1.3 天一次），而「照 flag 實際處置」的 commit 只有 9 次——**機制被改的次數多於被用的次數**。

`2026-08-14-dossier-governance.md` 立的 Meta 原則是「凡『加規則』預設先跑成對實驗；凡『修既有矛盾』或『加機械防線』**可直接做**」。逐條核對那 11 次，**11 次全部走了後者的豁免**，證據門檻從未適用過。

---

## 五、尚未評估的替代方案

### 5.1 repo 早已登記的 ④⑤

`docs/plans/2026-08-14-dossier-governance.md:127-129` 逐字：

> **④⑤ 的處置：兩條都降級為「暫不需要」**，不是否決。門檻對分家後的 dossier 重新可達，軟目標訊號與 per-repo 覆寫失去當前的驅動力。**復活條件**：分家後的 dossier 又長期貼門檻，或機隊上出現「決策＋死路本身就撐爆門檻」的 repo——那才是門檻真的太緊，屆時 ④⑤ 的分析仍有效。

- **④＝軟目標訊號的「結構下限出口」**——當一個 repo 在不違反自身判準的前提下達不到建議目標時，訊號該怎麼降級。08-14 卡在「『已達結構下限』怎麼定義，目前沒有答案」
- **⑤＝per-repo 門檻**——處方要走 krepo 豁免條款的形狀（**帶理由、帶失效條件、帶不在豁免範圍的 flag 清單**）。08-14 卡在「多寬才算合理沒有非任意的答案」與防濫用

**兩條復活條件今天都成立**（dotfiles 20673/24576 = 84%、8 天撞牆；evint／ml-env／krepo 已超標），而三版分片計畫**從頭到尾沒有引用過它們**。

④⑤ 相對分片的優勢：**不動任何內容** ⇒ 對死路一樣有效、不會撞上「不刪」；⑤ 的防濫用問題 krepo 已示範答案；成本遠低於分片（不需搬 148 條、不需重指 21 條、不需改 10 個消費端）。

⚠️ 但它們也有未解處：④ 的「結構下限」定義仍然沒有答案；⑤ 若只是把數字放大，**下一次撞牆只是延後**，並未解決無界性。

### 5.2 觸發式召回：把「儲存」與「召回」拆開（**v1 漏出候選集合**）

既然 §4.2 的死結已解消，三個要求可以改寫成互不衝突的形式：

1. 歷史**不刪**，留在 git 內的 canonical Markdown
2. **不要求全部常駐 context**
3. 在相關檔案第一次被讀／改之前，**由機械觸發召回**

⇒ 物理分片鍵**不必**等於檢索鍵；有索引之後兩者應刻意解耦。

**具體形狀**（已記於 `docs/backlog.md`「決策/死路的機械召回」）：`PreToolUse` hook ＋ 以檔案路徑為鍵的倒排索引。要動 `xref-gate.py` 時，自動把「提過它的 N 條決策/死路」注入。

已查證的機制事實（官方 hooks 文件）：
- PreToolUse **在工具執行前跑、可 block**
- 支援 `permissionDecision: allow/deny/ask` 與 `additionalContext`
- file 類工具的 `tool_input` 帶 `file_path`

⚠️ **未載明的一項**：`additionalContext` 相對於工具執行的時序，官方文件**沒有說明**。第三方稱「官方現在明載在下一次模型請求才讀到」，**我重抓官方文件後確認仍未載明**——故原判斷維持：用 `deny` 擋第一次呼叫、讓模型重讀後再試，理由是**不賭未定義行為**，不是「已知會太晚」。

### ⚠️ deny-first 需要 latch，否則是無限迴圈（第三方抓出，成立）

只寫「第一次 deny、重讀後再試」是不完整的：**hook 無法區分第一次與第二次**，對同一路徑會恆命中 ⇒ deny → retry → deny。必須有一次性 latch：

⚠️ **v3 的鍵 `(session_id, repo, path, corpus revision)` 有三個漏洞**（第三方第三輪抓出，全部成立）：

| 漏洞 | 為什麼是漏洞 | 官方依據 |
|---|---|---|
| 缺 **`agent_id`** | subagent 執行同一組 hooks。主 agent 開了 latch 之後，**subagent 沿用它、卻從未看過注入內容** | 文件明載 `agent_id`：*"Present only when the hook fires inside a subagent call"* |
| **compact 後未重設** | 壓縮摘要**不保證**保留召回內容，但 latch 仍開著 | 文件有 **`PostCompact`** 事件：*"After context compaction completes"* |
| corpus revision **只認 commit** | 本 repo 契約**明文允許決策／死路先寫 working tree、ship 時才 commit**（`claude/CLAUDE.md`）⇒ **同 session 新增的未提交條目不會讓 latch 失效** | repo 自身契約 |

**修正後的設計**：

| 項 | 設計 |
|---|---|
| 鍵 | `(context identity, corpus content hash, context epoch)` |
| **context identity** | `session_id` ＋ **`agent_id`**（subagent 各自獨立，不繼承主 agent 的 latch） |
| **corpus content hash** | 對 canonical 條目的**內容**取 hash，**不是 commit revision** —— working tree 的未提交新增會改變它 |
| **context epoch** | 每次 **`PostCompact`** 遞增 ⇒ 壓縮後全部 latch 失效、重新召回 |
| 存放 | session-scoped 暫存，**不進 git**（衍生狀態） |

**沒有這個 latch，整個機制不能實作。**

### ⚠️ 觸發面與旁路（**部分未經文件證實，標明如下**）

| 路徑 | 會不會觸發 PreToolUse | 依據 |
|---|---|---|
| `Read` / `Edit` / `Write` | ✅ 會，且 `tool_input` 有 `file_path` | 官方文件確認 file 類工具帶 `file_path` |
| `Bash` 讀檔（`cat`／`rg`） | ⚠️ 觸發，但只拿得到 `command` 字串、無 `file_path` | **推論**——官方範例顯示 Bash 的 `tool_input` 只有 `command`／`description`／`timeout` |
| `Grep` / `Glob` | ⚠️ 可能只有目錄或 pattern | **推論，文件未載明各工具的 `tool_input` 形狀** |
| `@file` 提及載入 | ⚠️ 推測**完全不觸發**（那是 prompt 展開、不是工具呼叫） | **文件完全沒提 `@file`**，純推論 |

⇒ **deny-first 只能承諾 `Write`／`Edit` 這條防線，不能承諾「第一次讀取之前必然召回」。**

### ⚠️⚠️ 更根本的覆蓋缺口：`PreToolUse` 是 Claude Code 專屬，而本 repo 的契約涵蓋任何 agent

第三方第三輪抓出，**我完全沒想到**：這個 repo **兩個 agent 並用**（`codex/AGENTS.md` 在、`~/.codex/skills` symlink 在、ship 流程明文兩邊共用）。而 hook 只在 Claude Code 生效。

⇒ **§5.2 目前只能宣稱一個有限的成功條件：**

> **「在 Claude Code 中，經 `Edit`／`Write` 修改某檔之前，召回與該檔相關的決策／死路。」**

**不能宣稱它是全機隊或跨 agent 的長期解。** 要那樣宣稱，必須先定義**跨 client 的 delivery adapter 或共同 enforcement point**（例如 git pre-commit 層、或兩邊都會呼叫的狀態腳本）——**那是未解項，不在本文件的候選集合裡**。

### ⚠️ 注入內容有 10,000 字元硬上限（官方明載，v2 不知道）

> Hook output strings, including `additionalContext`, `systemMessage`, and plain stdout, are capped at **10,000 characters**. Output that exceeds this limit is saved to a file and replaced with a preview and file path.

⇒ 召回 payload 必須是 **bounded retrieval**：命中太多條時要排序取前 N、或只給結論句＋指標。**溢出處置必須在實作前定案**，否則超限時會退化成「一個檔案路徑」——那等於回到「你要自己去讀」，機制失效。

### ⚠️ 投入實作之前需要一組行為 eval（第三方抓出，成立）

§2.4 的「13 天零修訂」**不能證明沒人讀**——讀取不產生 commit，純 append 歷史區分不了「沒人讀」與「讀過但不需修改」；兩條 inbound link 也只量到明示指標，量不到 `rg`、人工瀏覽或模型召回。

⇒ 動手前先建 eval：**給定一個必須依賴某條已歸檔決策／死路才能做對的任務**，量 baseline vs hook 版本的**召回率、誤召回率、額外 turns、token、延遲**。

⚠️ **通過門檻必須「預註冊」**（事前寫死，不得看到結果才定）——這是本 session 已經實作過一次的紀律（P4 fixture 汰換驗證：事前登記「抓到且判阻斷」，事後 A 抓到但判高，**刻意不改用較寬的原始門檻**，判 FAIL）。預註冊項目至少：

| 指標 | 門檻 |
|---|---|
| 召回率（該召回時真的召回） | 待定，**動手前寫死** |
| 誤召回率（不相關卻注入） | 待定 |
| 額外 turns | 待定（deny-first 每次相關 edit 多一次往返） |
| token／延遲 | 待定 |

**在這組數字出來之前，§5.2 的地位是「首選候選」，不是「已解」。** v3 §4.2 曾宣告死結「已解」，那講得過滿——**解消的是「三角互鎖是結構定理」這個錯誤前提，不是問題本身。**

**⚠️ v2 曾寫「第一版用 `rg` 掃 canonical Markdown 即可」——第三方指出那不被文獻支持，已撤。**

理由：現有條目**沒有穩定的 `applies_to` 路徑／glob**。字面沒提到檔名的條目、跨檔規則、改名後的路徑，裸文字搜尋全部漏掉。而 DR 文獻支持的恰恰是**結構**——該領域論文摘要逐字：

> capture design communication and, **over time, incrementally structured** into argumentation and other formalisms **to enable improved retrieval**

⇒ **改善檢索的是「逐步結構化」，不是對散文做精確比對。** 這與 §5.2 下方 event log 那個形狀（stable ID、`applies_to`、狀態、`supersedes`）一致，與 `rg` 不一致。

⚠️ 第三方另稱該文獻把成功歸因於 typed relationships／issue links／associative indexing 三種機制——**我從摘要層驗不到那三個詞**，雙方都停在摘要層（見〈附錄 C〉）。**方向（結構化→改善檢索）已證實，具體機制未證實。**

**規模仍然不需要向量庫**：語料約 200 條／300KB，精確的 `applies_to` 比對比語意相似更準。但索引必須從**結構化欄位**建，不是從全文。

**三條硬約束都不違反**：索引是衍生物、gitignored、可從 md 重建。

**為什麼這一半才是該補的**：DR 文獻的主結論與本問題陳述 v1 的框架**相反**——
*"While **capture** of argumentative rationale remains **problematic**, **retrieval** of relevant rationale is an area where the argumentation approach has **excelled**."*
即：捕捉才是該領域普遍失敗的那一半，檢索反而是強項。而**本 repo 剛好倒過來**——捕捉已由
`claude/CLAUDE.md` 的「發生當下就地寫入」＋ ship 時機械強制解決（114 條/34 天），未解的是檢索。
⇒ **要補的正是文獻認為比較好解的那一半，而不是重做已經做對的那一半。**
⚠️ 此推論有一個明確威脅（文獻談的是人類設計者的抗拒，本 repo 的捕捉由 agent 依規則執行），
**見〈附錄 C〉的待查證點 3**。

---

## 六、想請第三方回答的問題

1. ~~4.2 的死結有沒有第三條路？~~ **已解**：死結建立在錯前提上，正解是 §5.2 的觸發式召回（儲存與召回拆開）。**新問題：§5.2 的形狀對不對？** 特別是 deny-first 的代價（每次相關 edit 多一次往返）是否可接受
2. **④⑤ vs 分片 vs 觸發式召回，三者的關係是什麼？** 目前的判斷是：④是訊號降級、⑤只延後撞牆、分片只解物理存放，**三者都不是單獨的正解**；長期形狀應為「無總量上限的 canonical corpus ＋ 可重建索引 ＋ bounded retrieval payload」，⑤只適合 rollout 期間的有期限豁免。這個判斷對嗎？
3. **「無界的歷史」的長期正確形狀是什麼？** 候選答案是 **event log ＋ derived materialized index**。

   ⚠️ **v3 把它寫成「每條立即具備 stable ID／applies_to／狀態／翻案條件／supersedes」——那與本文件自己引用的文獻直接矛盾**（第三方第三輪抓出）。文獻的核心是**先低摩擦捕捉、再逐步結構化、並盡量由電腦承擔整理成本**，不是要求作者在捕捉當下填完索引欄位。**v3 等於一邊引用「incrementally structured」、一邊要求 capture-time 全結構化。**

   **v4 修正後的形狀**：

   | 層 | 內容 | 誰產生 |
   |---|---|---|
   | **最小 immutable capture event** | 只要 stable ID ＋ 日期 ＋ 結論句 ＋ 自由文字 | 人／agent，**捕捉成本與現況相同** |
   | **enrichment events** | `applies_to`、狀態、`supersedes`、翻案條件——**事後追加，可分次** | 可由腳本提案、人確認 |
   | **materialized view** | 供召回用的索引 | 完全由前兩層重建，**不進 git** |

   **未解的四項**（第三方列出，我確認都沒答案）：①既有約 200 條散文的 backfill 成本與標註品質；②`applies_to` 對 rename／刪檔／跨檔規則／非檔案概念的語意；③immutable event 與**會變動的** applicability 如何共存；④**未完成結構化的條目如何仍可召回**（否則 backfill 完成前機制形同虛設）。

   這個形狀在「只能用 git、隨 repo 移交、不引入第二份權威」的約束下站得住嗎？
4. **4.3 的失效形狀（盤點池子邊界、補償機制未驗證）是計畫作者的問題，還是這類改動本身的固有難點？** 如果是後者，是否該先用腳本把盤點面掃出來、而不是靠 reviewer 逐輪抓？
5. **⚠️〈附錄 C〉那組 Design Rationale 結論站得住嗎？** 它不是從 repo 量出來的，是從**只讀過摘要層的外部文獻**推論的。附錄 C.4 列了六個我自認最可能錯的地方，其中 **C.4.3（文獻談的是人類抗拒書寫，而本 repo 的捕捉由 agent 依規則執行）我完全沒有證據排除**。請一併查證：引文有沒有被誤讀、推論鏈成不成立、以及 C.5 的連帶影響評估對不對。

---

## 附：相關檔案

| 檔 | 內容 |
|---|---|
| `docs/plans/2026-08-19-dossier-sharded-architecture.md` | v3 實作計畫（已判不通過） |
| `…-sharded-architecture-v1.md` / `-v2.md` | v1／v2 原文，**已從 git 逐 byte 還原**（違反 write-once 的補救） |
| `docs/plans/2026-08-19-dossier-governance-problem.md` | 本檔的 v1，凍結不改 |
| `docs/plans/2026-08-14-dossier-governance.md` | 前一輪治理計畫，含 ④⑤ 與其復活條件 |
| `claude/skills/project/references/dossier.md` | dossier 規範（全機隊生效） |
| `claude/skills/project/scripts/ship-state.sh` | 門檻常數與所有 dossier flag 的實作（跨 repo 生效） |
| `STATUS.md` | 本 repo 的 dossier 本體 |
| `docs/dead-ends.md` | 死路的證據層（分層的產物） |
| `docs/backlog.md` | 分家出去的待辦（**刻意無量體門檻**，實測有效） |


---

## 附錄 B：重現指令

於 `~/.dotfiles` 執行。⚠️ **v2 的指令讀 working tree、不是宣稱的 `c567204`**（第三方抓出：直接跑得到 21,032 B 而表中是 20,673 B）。以下**全部改用 `git show c567204:`**，可逐位重現。

```bash
# 2.1 各節 bytes
git show c567204:STATUS.md | LC_ALL=C awk '/^## /{if(s)printf "%-24s %6d\n",s,b; s=$0; b=0}
              {b+=length($0)+1} END{printf "%-24s %6d\n",s,b}'

# 2.1 種子與累積率（種子 4051、34 天 → 489 B/日）
SEED=$(git show 1d96e45:STATUS.md | wc -c)          # 4051
CUR=$(git show c567204:STATUS.md | wc -c)           # 20673 —— NOT `wc -c < STATUS.md`

# 2.2 成長來源分解
sec() { git show "$1:STATUS.md" | LC_ALL=C awk -v n="$2" '
        $0 ~ "^## "n {f=1;next} /^## /{f=0} f{b+=length($0)+1} END{print b+0}'; }
for c in 1d96e45 7a21e2c 62671be 887c1c1; do
  echo "$c 死路=$(sec $c 死路) 決策=$(sec $c 關鍵決策)"; done

# 2.4 歸檔是純 append（28 次 commit、刪除欄全 0）
git log --numstat --format=%h -- docs/archive/decisions-2026-08.md |
  LC_ALL=C awk 'NF==3{n++; if($2!="0")bad++} END{printf "%d commits, %d with deletions\n",n,bad+0}'

# 2.5 機隊累積率——⚠️ v3 此處仍以 wc 讀 working tree，無法重現 13:49 那份快照。
#      v4 改為凍結表（見下方），指令只用於**日後重量**、不用於重現本文數字。
for r in evint kapi-gateway kapi-protocol krepo krepo-common krepo-judicial \
         krepo-mops-announcement krepo-mops-major-news ml-env pilot-api rdmsys; do
  H=$(git -C "$r" log --reverse --format=%h -- STATUS.md | head -1)
  SEED=$(git -C "$r" show "$H:STATUS.md" | wc -c)
  CUR=$(git -C "$r" show HEAD:STATUS.md | wc -c)      # NOT wc -c < STATUS.md
  echo "$r seed=$SEED cur=$CUR head=$(git -C "$r" rev-parse --short HEAD)"; done

# 2.6 治理面體積
for f in claude/skills/project/references/dossier.md tests/xref-gate.py \
         docs/plans/2026-08-14-dossier-governance.md; do
  echo "$f $(git show c567204:$f | wc -c)"; done
git show c567204:claude/skills/project/scripts/ship-state.sh |
  LC_ALL=C awk '/^detect_dossier|^# 歸檔孤兒|^detect_backlog/,/^}/' | wc -c
```

### ⚠️ 「11 次機制 churn」無法由裸指令重跑（第三方指出，屬實）

```bash
git log --since=2026-08-05 --format=%H | while read c; do
  git show --name-only --format= "$c" |
    grep -qE 'dossier\.md|ship-state\.sh|xref-gate|dossier-governance' && echo x
done | wc -l                                    # → 21，不是 11
```

**11 是手工分類後的子集**——只計「改動 dossier 機制本身」者，排除只動 ship 流程
（squash／merge／remote／說法表）的 `ship-state.sh` commit。那 11 顆是：
`c765d55`(08-06) `5adc757`/`ba8163c`(08-08) `3e5a97f`(08-10)
`04dc437`/`4cdaddf`/`62671be`/`7b61ca7`/`956b780`(08-14) `f2e7aa0`(08-16) `887c1c1`(08-19)。

**這個分類沒有機械判準，換一個人數可能不同。** 引用時應標明是手工分類。


---

## 附錄 C：Design Rationale 那組結論是怎麼得到的（**請一併查證**）

本節存在的理由：§3.1／§3.3／§5.2 引入的一組結論**不是從 repo 量出來的，是從外部文獻推論的**。
推論鏈與其弱點寫在這裡，供第三方判斷它站不站得住。

### C.1 取得方式（完整、無省略）

1. 使用者問「其他類型（死路／里程碑／進行中）沒有人有經驗可以參照嗎」。**在此之前，本問題陳述
   只查過 ADR 與本地向量庫兩項外部先例，死路／里程碑／進行中三類一次都沒查過。**
2. 兩次網路搜尋：
   - `documenting failed approaches software "lessons learned" register never read anti-pattern catalog rejected alternatives design rationale`
   - `design rationale capture problem IBIS QOC rejected options "intrusiveness" why rationale documentation is not used retrieval`
3. **只讀了搜尋引擎回傳的摘要與節錄，未取得任何一篇原始論文全文。** 下列引文均來自該摘要層。

### C.2 依賴的四段引文（原文照錄）

| # | 引文 | 用在哪 |
|---|---|---|
| A | *"While capture of argumentative rationale remains problematic, retrieval of relevant rationale is an area where the argumentation approach has excelled."* | §5.2「捕捉才是普遍失敗的那一半」 |
| B | *"Despite the known costs of not capturing rationale, it is frequently not done at all, or done as an afterthought. Knowledge workers tend to resist the requirement to document their rationale."* | 同上 |
| C | *"The issue of intrusiveness is related to the overhead burden on designers. DRed is a simple and unobtrusive software tool…"* | §3.3「ADR 樣板提高捕捉成本」 |
| D | *"Insufficient documentation of alternatives that were considered and rejected can lead to maintainers 'reinventing the wheel' by going down the already considered paths."* | §3.1「死路＝rejected alternatives」 |

來源（皆為搜尋結果頁，未讀全文）：Capturing design rationale（ScienceDirect）／QOC Design Rationale
Retrieval: A Cognitive Task Analysis（Semantic Scholar）／Questions, Options, and Criteria（AcaWiki）／
Capturing Design Rationale with QOC。

### C.3 推論鏈

```
A + B  →  DR 領域裡「捕捉」難、「檢索」相對可解
本 repo 實測 114 條決策 / 34 天、ship 時機械強制  →  本 repo 的捕捉已解
∴ 本 repo 與文獻常態相反：未解的是檢索
∴ 該補的是檢索（§5.2），不是重做捕捉

C  →  intrusiveness 是捕捉失敗主因
ADR 樣板 = 每次記錄多一層固定成本 = intrusiveness ↑
∴ 全面 ADR 化會傷害本 repo 唯一已解決的那一半
```

### C.4 **待查證點（這些是我認為最可能錯的地方）**

1. **引文是否被正確理解？** 我只看到摘要層的節錄，沒有上下文。特別是引文 A——「retrieval has
   excelled」可能指的是「IBIS/QOC **這類結構化標記法**讓檢索變好」，而不是「檢索問題已解」。
   若是前者，我的「檢索相對可解」就是誤讀。⚠️ 同一批搜尋還回傳了相反方向的一段：*"the locality
   of arguments and the lack of context in the IBIS notation led to difficulty in searching and
   retrieving desirable information from large IBIS based systems"* —— **這段與引文 A 張力明顯，
   我在正文只引用了對我有利的那半（用來支持「1500 個 ADR 檔難檢索」），未處理它與 A 的衝突。**

2. **「本 repo 的捕捉已解」是否成立？** 依據只有「量大」（114 條/34 天）。**量 ≠ 品質**——
   也可能是記了大量低價值條目。本問題陳述 §3.3 另有一列寫著「收緊記錄判準」的否決**已撤回、
   現況未評估**，兩者其實互相牽制：若判準太鬆，那「捕捉已解」就講得太滿。

3. **⚠️ 最大的威脅：文獻談的是「人類設計者抗拒書寫」，本 repo 的捕捉由 agent 依規則執行。**
   引文 B 的機制是**動機**（knowledge workers resist），而 agent 沒有動機問題——它會照樣把樣板
   填完。若如此，「ADR 樣板 → intrusiveness ↑ → 捕捉率 ↓」這條**在本 repo 不成立**，
   §3.3 那條「更強的理由」就整條垮掉，只剩原本那三條。**這一點我沒有任何證據可以排除。**

4. **DRed 的 "unobtrusive" 是產品定位語，不是對照實驗結論。** 我用它反推「先前工具被認為有摩擦」，
   那是從行銷語言做的推論。

5. **里程碑對到 Keep a Changelog、進行中判為「不適用（違反 git-only 約束）」——這兩項我沒有查證，
   是憑既有認知寫的。** 尤其「進行中」那類，可能存在我不知道的先例。

6. ~~本檔就地增修（未另開 v3）的判斷是否違反 write-once。~~ **已判定違反**（第三方第二輪，
   `AGENTS.md:41` 無該例外）。v2 已還原、v3 另開、v4 再另開。⚠️ **此條在 v3 仍原樣留著、
   與 v3 自己的身分衝突**——第三方第三輪抓出，本檔修正。

### C.5 若上述任一點被推翻，會影響什麼

| 被推翻的點 | 連帶失效的結論 |
|---|---|
| 1（誤讀引文 A） | §5.2「該補檢索」的文獻支撐消失。⚠️ **v3 此處原寫「但實測支撐仍在（13 天零修訂、2 條指標）」，那與 §5.2 自己的結論直接矛盾**（第三方第三輪抓出）——同一份證據在 §5.2 被判定「不能證明沒人讀」，不能在這裡又當支撐。**正確說法：零修訂只證明 archive 缺乏維護活動，不證明召回率。§5.2 的證據基礎因此只剩「兩條 inbound 指標」這個明示可達性訊號，強度遠低於 v1–v3 的陳述。** |
| 2（捕捉未必已解） | §3.3 的「ADR 傷捕捉」與 §5.2 的「不必重做捕捉」同時鬆動 |
| **3（agent 無動機問題）** | **§3.3 那條「更強的理由」整條垮掉**——但原本三條（只覆蓋決策／不解召回／粒度不匹配）不受影響，ADR 仍然不是單獨的解 |
| 5（其他類型有先例） | 可能存在更好的方案沒被納入候選集合——**這正是 v1 犯過的錯（把 hook 候選埋起來）** |


---

## 附錄 D：第二輪第三方審查後，我對自己判斷穩定性的觀察

兩輪第三方審查，**11 條 findings 裡 10 條真陽性**。唯一不成立的那條（F2b，「官方已明載時序」）是**對方過度斷言**，而我是靠**重抓官方文件**才確認的——如果照收，我會把一個仍然正確的保守判斷（不賭未定義行為）改成錯的。

⇒ **「第三方命中率高」不是照單全收的理由。** 這一輪如果我沒去重抓，會被一條錯的 finding 帶偏。

反過來，我自己漏掉的形狀高度一致：

| 形狀 | 出現 |
|---|---|
| **池子邊界沒定義** | v2 決策條目數（含技術債）、§2.6 治理面 3.4×、「11 次 churn」的手工分類 |
| **補償機制寫成一句話沒驗證** | v2 死路 800B 上限、v3 append-only 豁免、v3 stale 改 mtime、**§5.2 的 deny-first 缺 latch** |
| **只引用對自己有利的那半** | 附錄 C.4.1 自陳一次（IBIS 檢索困難那段），F4 再一次（`rg` vs 結構化） |
| **自創例外正當化違規** | write-once 第三次 |

**四種形狀在三個不同層級（計畫內容、文獻引用、契約遵守）重複出現**，這比任何單條 finding 更值得作為〈六〉第 4 問的證據。


---

## 附錄 E：機隊量測的凍結快照（G6）

⚠️ **v1–v3 的機隊表無法被日後 reviewer 精確重跑**——指令讀 working tree，而機隊是活動靶
（實測期間兩個 repo 被其他 session 改動）。以下凍結 commit 與 blob SHA，任何時候都可逐位重建。

**日率公式**：`(cur_bytes − seed_bytes) ÷ (量測日 − seed_date)`，量測日 = **2026-08-19**。
**距門檻天數**：`(24576 − cur_bytes) ÷ 日率`，`cur_bytes > 24576` 記為已超標。

| repo | HEAD | `STATUS.md` blob | cur B | seed commit | seed B | seed date |
|---|---|---|---|---|---|---|
| evint | `f882aa9` | `24cdd5e` | 28565 | `b249fc2` | 6511 | 2026-07-22 |
| kapi-gateway | `36f358f` | `a47d698` | 22708 | `80ddab9` | 12691 | 2026-08-10 |
| kapi-protocol | `a04263c` | `1ea018a` | 21970 | `c5ba2ca` | 10451 | 2026-08-12 |
| krepo | `38f21ab` | `a539416` | 170210 | `15d8e08` | 10557 | 2026-01-20 |
| krepo-common | `ad19463` | `f378090` | 15850 | `7f25a86` | 6211 | 2026-08-06 |
| krepo-judicial | `90667fb` | `5256fc4` | 17663 | `6047e0b` | 11156 | 2026-08-17 |
| krepo-mops-announcement | `8bdaf23` | `66bffd6` | 18096 | `a6cdbbb` | 9143 | 2026-08-12 |
| krepo-mops-major-news | `e48806f` | `2ae6740` | 20207 | `e6fcdb8` | 5580 | 2026-08-10 |
| ml-env | `4c40859` | `7f525a8` | 26367 | `6e1f14e` | 5610 | 2026-07-21 |
| pilot-api | `1348edf` | `fe64869` | 24023 | `d42b5ac` | 11514 | 2026-07-17 |
| rdmsys | `6f40339` | `c035a42` | 8504 | `7138279` | 5349 | 2026-07-22 |

**豁免狀態**：只有 `krepo` 有量體豁免（該 repo 的 `CLAUDE.md` 內，節名為「dossier 量體門檻：拆分期間豁免」，
只涵蓋全檔行數／bytes 兩個 flag，帶失效條件）。其餘 10 個無。

⚠️ **本表與 §2.5 的數字有出入**（如 `krepo` 170210 vs 170637、`krepo-judicial` 17663 vs 15944、
`rdmsys` 8504 vs 8850）——**因為 §2.5 量於 13:49，本表量於稍後**，中間有 repo 被改動。
**這正是「機隊是活動靶」的實證，也是 v1–v3 沒有凍結導致的直接後果。以本表為準。**

### 驗證方式

```bash
# 逐 repo 驗證 blob 與 bytes 是否與本表一致
git -C ~/Projects/<repo> rev-parse --short HEAD:STATUS.md   # 應等於表中 blob
git -C ~/Projects/<repo> cat-file -s <blob>                 # 應等於表中 cur B
```
