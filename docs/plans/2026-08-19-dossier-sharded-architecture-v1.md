# STATUS.md dossier 改為分片架構

- 日期：2026-08-19
- 起因：使用者第三次反映治理成本（08-14、08-15、本次）。前兩次診斷為「工具缺陷」與「管轄範圍太大」，處置後鋸齒仍在
- 目標檔案：`claude/skills/project/references/dossier.md`、`claude/skills/project/SKILL.md`、`claude/skills/project/scripts/ship-state.sh`、`claude/templates/STATUS-template.md`、`tests/run.sh`、`tests/xref-gate.py`、本 repo 的 `STATUS.md` 與 `docs/`
- **本計畫不改「捕捉」**——決策/死路/里程碑在發生當下寫入、`/project log` Step 2 同步，一律不動。改的只是**寫到哪個檔**

## 一、診斷：現行架構在數學上不可能長久運行

把三個**無界**的內容放進一個**有上限**的檔。以本 repo 34 天實測率外推：

| 節 | 現況 B | B/日 | 有界？ | 一年後 |
|---|---|---|---|---|
| 關鍵決策 | 8888 | 261 | **無界** | 104303 |
| 死路 | 6674 | 196 | **無界** | 78321 |
| 已完成里程碑 | 2326 | 68 | 半有界 | 27296 |
| 進行中 | 930 | 27 | 有界 | 930 |
| 其他 | 855 | 55 | 有界 | 855 |
| **合計** | 19673 | 608 | | **211706**（門檻 24576 的 **8.6×**） |

**鋸齒是這個架構的必然輸出，不是紀律問題。** 15 天內 11 次壓縮事件、多數時間活在建議目標以上，任何歸檔次數都改變不了斜率。

### 使用者原話的量化
「花了這麼多成本，再沒幾次又要來了」——一次歸檔釋出約 4KB ≈ 1200 tok、買 3 次 ship；而執行一次要讀 `dossier.md`（3808 tok）＋ `STATUS.md`（6180 tok），**光讀取就 10K tok 去換 3600**，未計判斷來回。

### 機隊：dotfiles 不是特例，是先撞上的那一個
扣除首次 commit 的移轉種子後的累積率：

| repo | 累積 B/日 | 距 24576 |
|---|---|---|
| krepo-judicial | 2394 | 3.6 天 |
| krepo-mops-major-news | 2364 | ★ 已超標 |
| kapi-protocol | 1646 | **1.6 天** |
| krepo-mops-announcement | 1279 | 5.1 天 |
| kapi-gateway | 1113 | **1.7 天** |
| evint | 788 | ★ 已超標 |
| krepo | 759 | ★ 已超標（拆分期間**明文豁免**，帶失效條件） |
| krepo-common | 741 | 11.8 天 |
| ml-env | 716 | ★ 已超標 |
| **dotfiles** | **489** | 8.0 天 |
| pilot-api | 314 | 8.6 天 |
| rdmsys | 125 | 125.8 天 |

**dotfiles 成長率倒數第三**（決策 4.4 條/日排第 5，均條 690B 接近機隊中位）。4 個 repo 已超標、7 個在 12 天內撞牆。

> ⚠️ 本節第一版曾以絕對數量斷言「只有 dotfiles 在痛、其他 repo 無視 flag」，**該結論已被正規化後的數據推翻**。記在此處是因為它是本批第三次「憑推論指認失效面」——與 08-14 的兩次同形狀。

## 二、架構原則

> **有上限的檔只能裝有界的內容。無界的內容必須分片，而分片鍵要等於檢索鍵。**

第二句是現行歸檔做錯的地方：**歸檔用「大小」當分片鍵，但沒有人用大小檢索**——這就是 `docs/archive/decisions-2026-08.md`（68KB、110 條、STATUS.md 只有 2 條指標指進去、28 次 commit 全是 `-0` 純 append、14 天零修訂）沒人讀的結構性原因。

| 內容 | 實際檢索方式 | ⇒ 分片鍵 | 落點 |
|---|---|---|---|
| 決策 | 「當時為什麼這樣決定」 | **時間** | `docs/decisions/YYYY-MM.md` |
| 里程碑 | 「什麼時候做了什麼」 | **時間** | `docs/milestones/YYYY.md` |
| 死路 | 「我要動 X，X 踩過什麼雷」（時間完全無用） | **領域** | `docs/dead-ends/<area>.md` |
| 進行中 / 移交準備度 | 現況 | 有界，不分片 | `STATUS.md` |

**分片鍵的選擇不是風格問題**——選錯就會複製現在 archive 的失效模式。

## 三、設計

### 3.1 決策 → 時間分片
- 落點 `docs/decisions/YYYY-MM.md`，**檔名由寫入當天的日期決定，零判斷**
- 該目錄**無量體門檻**（同 `docs/backlog.md` 的先例，刻意）
- 每個月檔開頭有該月條目目錄；`STATUS.md` 只留**月份索引**（一年 12 行）
- 條目格式不變（`- **YYYY-MM-DD <標題>**：…`），既有 148 條實測 100% 有日期、100% 可抽標題
- **「歸檔」這個動作消失**：不再有「挑哪幾條搬走」

規模：本 repo 261 B/日 → **約 8KB/月、一年 12 檔**。高產出 repo（如 krepo-judicial 2394 B/日）可在該 repo 契約檔改為**週分片**——一次設定，之後仍零判斷。

### 3.2 里程碑 → 時間分片
同上，落點 `docs/milestones/YYYY.md`。`STATUS.md` 只留**最近一批**（現 5 條 / 2302 B）＋ 年份索引。

### 3.3 死路 → 領域分片
- 落點 `docs/dead-ends/<area>.md`，`STATUS.md` 留**領域索引**（每領域一行，含該領域條目數）
- 現有 16 條的實測領域分布：`dossier` 5、`handoff` 4、`ship` 3、`env` 2、`deep-review` 1、`skill-discipline` 1
- **領域怎麼切由各 repo 自己定**，判準：**領域＝你會在動那塊東西之前想查的單位**（多數 repo 即頂層模組/子系統）。`dossier.md` 給判準，不給固定清單
- 今天（`887c1c1`）落地的「結論留 STATUS.md、證據移 `docs/dead-ends.md`」分層**併入本設計**：`docs/dead-ends/<area>.md` 同時承接結論的推導與證據，STATUS.md 只留索引
- ⚠️ **今天那道節級孤兒 gate 需要改**：`EVIDENCE_LAYERS` 從單檔改為掃 `docs/dead-ends/*.md`

### 3.4 STATUS.md 變成什麼

保留七節標題（`ship-state.sh:288` 簽章與 `:296` 章節完整性檢查硬要求），內容改為：

| 節 | 內容 | 有界性 |
|---|---|---|
| 進行中 | 不變 | 有界（工作項數量有限） |
| 關鍵決策 | 月份索引 + 指標 | 一年 +12 行 |
| 死路 | 領域索引 + 指標 | 領域數有限 |
| 技術債 / 已知缺口 | 不變（已分家至 `docs/backlog.md`） | 已有界 |
| 已完成里程碑 | 最近一批 + 年份索引 | 一年 +1 行 |
| 移交準備度 | 不變 | 有界 |

推算：**現況 19673 B → 約 5211 B，一年後約 6811 B（門檻的 28%）**。

**門檻原封不動保留**——它從此不再是日常節奏，響了就是真的異常。

## 四、遷移（dotfiles）

1. `docs/archive/decisions-2026-07.md` → `docs/decisions/2026-07.md`；`decisions-2026-08.md` → `docs/decisions/2026-08.md`（**幾乎只是改名**——檔名一直是對的，錯的是觸發機制）
2. `milestones-2026-07.md` / `-2026-08.md` → `docs/milestones/2026.md`（合併，加月份小節）
3. `STATUS.md` 決策節 13 條依日期分派進 `docs/decisions/2026-08.md`；死路 16 條依領域分派；里程碑留最近一批
4. `docs/dead-ends.md`（12 節）拆進 `docs/dead-ends/<area>.md`
5. `STATUS.md` 三節改為索引
6. **快照類歸檔留原地不動**——`docs/archive/` 其餘內容與機隊上 evint／kapi-gateway／krepo-mops-major-news 的「整份 STATUS 快照」是不同的東西，不納入本次

## 五、機隊策略

**dotfiles 先跑，驗證後推全機隊。**

- `dossier.md` 的規範同批更新（全域生效，12 個 repo 適用）
- **已存 STATUS.md 不強制遷移**——舊形狀繼續可用，各 repo 下次做 dossier 工作時自然切換
- 現況本來就不一致（條目形狀 2 種：10 個 `- **`、krepo-judicial 與 krepo-mops-announcement 用 `### `；歸檔慣例 4 種），這降低了同步壓力
- ⚠️ **時效**：kapi-protocol 1.6 天、kapi-gateway 1.7 天、krepo-judicial 3.6 天內撞牆。它們可能在切換前先被壓一輪——可接受，但若本批拖過一週，這三個 repo 的存量會更難遷

## 六、驗收準則

1. `./tests/run.sh` 全綠（含改寫後的 xref 反向 gate）
2. `ship-state.sh .` 對本 repo：`dossier:` < 8000 bytes、**零 `dossier-flag:`**
3. `python3 tests/xref-gate.py --root .` 空輸出（正向零死指標、反向零節級孤兒）
4. 148 條決策 + 16 條死路 + 5 條里程碑**逐條可追**：遷移前後以 script 比對條目數與內容 hash，零遺失
5. 從乾淨 clone 驗證（`git clone --no-local`），確認不是只有 working tree 對
6. 既有 13 條指向「關鍵決策(附理由)」的指標全部重指且 gate 通過

## 七、不做

| 提案 | 理由 |
|---|---|
| ADR 一決策一檔 | 機隊決策條目 399+ 起跳、本 repo 一年 1543 條；ADR 設計給一年 10–50 條。且 ADR 社群第一條批評（判準不清 → 記下每個決定 → 看不見重要的）**本 repo 已在該狀態**，換成 1500 個檔只是把問題換個形狀 |
| 收緊「什麼該記成決策」的判準 | 機隊數據顯示本 repo 產出率不離群（4.4 條/日排第 5、B/日 倒數第三），「記太多」的診斷證據不足 |
| 給 `docs/decisions/` 設量體門檻 | 在新檔重設一套等於把問題原樣搬過來（`docs/backlog.md` 分家時已付過這個學費） |
| 補歸檔檔的 stale / 節級守門 | 14 天零修訂、無讀取痕跡，補守門收益接近零；且屬本批已量到的 rule churn |
| 外部工具（Linear / mem0 / Zep / Letta / OpenWiki） | 08-14 已否決（三條硬約束）。且它們解的是執行成本，而痛點在 deliberation |
| always-on 量體治理（463 行 / 14089 tok，超建議 2.3×） | **與本計畫正交，值得單獨做**。外部共識的理由不是 token 貴，是「每加一行讓 agent 更容易忽略既有的行」——槓桿可能比本計畫大，但不該混批 |

## 八、風險與未驗證面

1. **死路領域分片會不會讓「擋住你」失效**——死路的價值在於你沒想到要查時就擋住你，分片後只有動到該領域才會讀到。**未驗證**。緩解：`STATUS.md` 領域索引每行帶條目數，且領域切得夠粗（本 repo 4–6 個）
2. **月檔在高產出 repo 會很大**（krepo-judicial 率 → 72KB/月）。緩解：該 repo 契約檔改週分片。**未實測**
3. **今天 `887c1c1` 剛落地的分層規則要再改一次**——`dossier.md` 死路條文與 `EVIDENCE_LAYERS` 都要重寫。這是本批自己製造的返工
4. **機隊不一致期**：切換前後兩種形狀並存，`ship-state.sh` 必須對兩者都不誤報
5. 條目形狀 `### ` 的兩個 repo（krepo-judicial、krepo-mops-announcement）遷移時需另外處理

## 九、執行順序

1. 改 `ship-state.sh`：簽章/章節完整性接受「索引式」節；條目 flag 與節佔比對新形狀不誤報
2. 改 `dossier.md`：分片架構、三個分片鍵與判準、刪除「歸檔」相關條文、改寫死路離場規則
3. 改 `xref-gate.py`：`EVIDENCE_LAYERS` 改掃目錄
4. 改 `STATUS-template.md`、`SKILL.md` Step 2
5. 遷移本 repo 存量（含逐條 hash 比對）
6. `tests/run.sh` fixture 更新（現有 17 處提及決策節）
7. 驗收 1–6

## 十、建議跑 `/deep-plan`

本計畫改動 `dossier.md`（全域權威檔）、`SKILL.md`、`ship-state.sh`、`testing-contract` 面的 fixture，且對「分片鍵＝檢索鍵」「死路領域分片仍能擋住你」兩條**沒有實測、只有推理**。依 2026-08-19 立的判準（會不會產生無法從 diff 反推的宣稱），這正是值得跑的形狀。
