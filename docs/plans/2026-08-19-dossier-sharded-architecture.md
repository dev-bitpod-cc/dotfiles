# dossier 的決策與里程碑改為分片架構

- 日期：2026-08-19（**v3**——v1 與 v2 各經兩個獨立 reviewer 審查後不通過，見〈附錄〉）
- 起因：使用者第三次反映治理成本（08-14、08-15、本次）
- **v3 的範圍縮減：只做決策與里程碑。死路完全不動**（維持 `62671be` 建立、`887c1c1` 寫進規範的分層）
- 目標檔案：
  - 工具與 gate：`claude/skills/project/scripts/ship-state.sh`、`tests/xref-gate.py`、`tests/run.sh`、`docs/testing-contract.md`
  - 規範：`claude/skills/project/references/dossier.md`、`claude/skills/project/SKILL.md`、`claude/skills/project/references/pressure-tests.md`
  - **always-on**：`claude/CLAUDE.md:32`（捕捉條文）、`AGENTS.md:38`（authority 矩陣）
  - 其他消費端：`claude/skills/handoff/SKILL.md`、`claude/skills/ready4quit/SKILL.md`、`claude/skills/deep-plan/SKILL.md:169`
  - 模板：`claude/templates/STATUS-template.md`、`claude/templates/BACKLOG-template.md`、`claude/templates/transfer-guide-template.md`
  - eval：`claude/evals/setup-sandboxes.sh`、`claude/evals/contract-evals.md`、`claude/skills/deep-plan/evals.md`
  - 本 repo 內容：`STATUS.md`、`docs/`
- **不改「捕捉」的時機與內容**——決策/里程碑仍在發生當下寫入。改的是**落點**，而落點寫在 `claude/CLAUDE.md:32`，故該檔在清單內

## 一、診斷

三個無界內容放進一個有上限的檔。本 repo 現況（2026-08-19 實測）：

| 節 | B | 有界？ |
|---|---|---|
| 關鍵決策 | 8904 | **無界** |
| 死路 | 7175 | **無界**（v3 不處理） |
| 已完成里程碑 | 2326 | 半有界 |
| 進行中 | 930 | 有界 |
| 其餘四節 | 1338 | 有界 |
| **合計** | **20673** | 門檻 24576 |

全檔率（扣種子 4051 B，`1d96e45` 2026-07-16）＝ **489 B/日**，一年約 199KB，**門檻的 8.1×**。

> ⚠️ **489 是「歸檔後的殘量率」，不是產出率**——34 天內從 STATUS.md 移出去的內容沒算進來。真實 dossier 語料產出率約 **3572 B/日**（含 archive 與 dead-ends）。兩個數字用途不同：489 說的是「維持現行歸檔節奏下 STATUS.md 會怎麼長」，那正是鋸齒的斜率；3572 說的是「要被安置的內容有多少」。**本計畫的診斷用前者，容量估算用後者。**
> ⚠️ 機隊表同樣混了口徑——`krepo-common`／`krepo-judicial`／`kapi-protocol`／`pilot-api`／`rdmsys` **沒有 `docs/archive/`**（其值是產出率），其餘有（是殘量率）。故**排序不可用於「誰比誰寫得多」**，只可用於「誰快撞到門檻」。

### 機隊：誰快撞牆（量測時刻 2026-08-19 13:49，活動靶）

| repo | B/日 | 距 24576 |
|---|---|---|
| krepo-judicial | 3560 | 1.8 天 |
| krepo-mops-major-news | 1625 | 2.7 天 |
| kapi-protocol | 1646 | **1.6 天** |
| krepo-mops-announcement | 1279 | 5.1 天 |
| kapi-gateway | 1113 | **1.7 天** |
| evint / krepo / ml-env | 788 / 759 / 716 | ★ 已超標（krepo 為拆分期間明文豁免，全機隊唯一） |
| krepo-common | 741 | 11.8 天 |
| **dotfiles** | **489** | 8.0 天 |
| pilot-api | 379 | **1.5 天（最急）** |
| rdmsys | 125 | 125.8 天 |

**3 個已超標、4 個在 2 天內撞牆。**

## 二、架構原則

> **有上限的檔只能裝有界的內容。無界的內容必須分片，而分片鍵要等於檢索鍵。**

### 分片鍵選錯的直接證據

`docs/archive/decisions-2026-08.md`：68354 bytes、28 次 commit **全部 `-0` 純 append**、13 天零修訂、`STATUS.md` 只有 **2** 條指標指得進去。

而它**已經是嚴格按月分片的**（07 檔內 23 條全為 2026-07、08 檔內條目全為 2026-08）。**按時間分片、且無人回頭改——時間不是決策的檢索鍵。**

現行歸檔判準（`STATUS.md:31`，本 repo 的檔頭註記；`dossier.md:98` 有措辭不同的對應規則）量的也不是時間：

> 已固化且**不再影響現行方向** → 歸檔；**仍在生效**的一律不歸檔

### 檢索鍵逐類判定

| 內容 | 怎麼找它 | 分片鍵 | v3 範圍 |
|---|---|---|---|
| **決策** | 「我要動 X，這裡以前決定過什麼」 | **領域** | ✅ |
| **里程碑** | 「什麼時候做了什麼」 | **時間** | ✅ |
| 死路 | 同決策 | 領域 | ❌ **不動**（理由見 §7） |
| 進行中 / 移交準備度 | 現況 | 有界，不分片 | — |

### 分片不會讓檔案變小

**真正的決策語料 114 條 / 61891 bytes**（已扣除 `decisions-2026-08.md` 的「已結案技術債」34 條與死路空節——**v2 誤把它們算進 146 條**）。機械歸類的分布：

| 領域 | 條 | bytes |
|---|---|---|
| dossier | 42 | **25282** |
| ship | 35 | 18074 |
| skills | 19 | 10261 |
| （未分類） | 11 | 5460 |
| env | 3 | 1277 |
| contract | 3 | 1014 |
| tests | 1 | 523 |

> ⚠️ **修正後最大領域檔 25282，只比門檻多 706 bytes**（v2 誤算為 37806）。「分片不會讓檔變小」這句**仍成立但很弱**——它現在幾乎只是打平。真正站得住的是後半句：分片買的是**相關性密度**（25KB 的 dossier 領域檔在你動 dossier 時整份相關；68KB 的時間檔任何時候都只有一小部分相關）。
> ⚠️ 此分布為粗略機械歸類，**11 條未分類需人判**，實際切法在執行時逐條定案。

## 三、設計

### 3.1 決策 → 領域分片
- 落點 **`docs/decision-log/<area>.md`**
- ⚠️ **刻意不用 `docs/decisions/`**：`krepo` 已在該路徑跑 **ADR**（`001-crawler-strategy…`～`005-…`，`krepo/CLAUDE.md:312`「新的重大技術選擇 → 新增一份 `docs/decisions/` ADR」）。兩者粒度差 20 倍（krepo 5 份／dotfiles 114 條）、語意不同，**共用目錄名會讓 `ship-state.sh` 的 glob 掃到別人的 ADR，也會讓新 session 套錯慣例**。分開命名同時把 ADR 社群第一條批評（「沒有區分什麼算 architectural」）做成了明文區分
- **無全檔量體門檻**，補償見 §3.4
- `STATUS.md` 決策節留**領域索引**：每領域一行、含條目數、以 gate 認得的指標句型指向該領域檔
- 領域檔內新的在上

### 3.2 里程碑 → 時間分片
落點 `docs/milestones/YYYY.md`。**這一類時間確實是檢索鍵**。`STATUS.md` 只留最近一批（現 5 條 / 2326 B）＋年份索引。

### 3.3 STATUS.md 變成什麼

保留七節標題（`ship-state.sh:287-288` 簽章、`:296` 章節完整性硬要求；索引化後兩者**原樣通過，不需改**）。

| 節 | v3 之後 |
|---|---|
| 進行中 / 技術債 / 已知缺口 / 移交準備度 | 不變 |
| **關鍵決策** | 領域索引 |
| **已完成里程碑** | 最近一批 + 年份索引 |
| **死路** | **不變**（16 條結論留原地，證據仍在 `docs/dead-ends.md`） |

### 3.4 守門的重新配置

| gate | 遷移後會怎樣 | 處置 |
|---|---|---|
| `DOSSIER_ENTRY_MAX_BYTES=800` | 決策與里程碑條目離開作用域（**`pilot-api` 今天就在被它攔：1398 > 800**，切換後靜默） | **擴大作用域**到 `docs/decision-log/*.md`、`docs/milestones/*.md`。⚠️ **不含 `docs/dead-ends/`**——`dossier.md:120` 明文「條目 flag 不掃死路節……全靠分層這一條」，v3 不動死路故該豁免維持。實測決策條目最大 **799 B**（>800 的 3 條全在已結案技術債節，不進本落點）⇒ **今天不會產生誤報** |
| `DOSSIER_MAX_LINE_BYTES=1000`（最長行） | 只掃 STATUS.md，語料移出即失效（`milestones-2026-08.md` 已有 733 B 的行） | **同步擴大作用域** |
| append-only log 章節偵測（`ship-state.sh:409-415`） | 只掃 STATUS.md；而 §3.1 的「新的在上」正是它擋的形狀 | **明文豁免新落點**並在 `dossier.md` 記理由——它擋的是「STATUS.md 裡長出流水帳」，分片後那正是流水帳該去的地方 |
| `DOSSIER_STALE_DAYS=30` | 日常寫入移出 STATUS.md，訊號恆綠 | **維持 git committer time**（`ship-state.sh:417-419`），改取 `STATUS.md` 與兩個新目錄的**最新 commit time**。⚠️ **v2 寫「改量 mtime」是錯的**——mtime 不入 git，在驗收 5 的乾淨 clone 下恆綠 |
| 節級孤兒（`xref-gate.py`） | **不受影響**——`EVIDENCE_LAYERS` 仍是 `docs/dead-ends.md`，死路不動 | **不改** |
| 歸檔孤兒（`ship-state.sh:435`） | `docs/archive/` 遷移後清空 ⇒ 對 dotfiles no-op | 保留給未遷移的 repo；dotfiles 端由下一列接手 |
| （新）**索引完整性** | — | `docs/decision-log/`、`docs/milestones/` 內**每個檔**都必須有 `STATUS.md` 的索引指標，漏建即紅。⚠️ 這**不是**「放寬成檔級」（那個是「檔名在任何 md 出現過即綠」＝恆綠）；這是「該目錄下每個檔都要出現在 STATUS.md 索引」 |

## 四、遷移

1. 建 `docs/decision-log/<area>.md`，**114 條**依領域分派（11 條未分類需人判；`decisions-2026-08.md:408` 無日期，不影響領域分派）
2. `decisions-2026-08.md` 的另兩節：`:412` 死路空節（刪）、**`:416` 已結案技術債 34 條** —— ⚠️ **不進 backlog**（`dossier.md:25-31` 的判準是 backlog 收「未結案」，這 34 條已結案且非「不再打算做的」，送進去同時違反兩份權威）。它們是**決策語意**，進 `docs/decision-log/dossier.md`
3. `milestones-2026-07.md` + `-2026-08.md` → `docs/milestones/2026.md`
4. `STATUS.md` 兩節改索引
5. 重指（清單見驗收 6）
6. 快照類歸檔留原地（機隊上 evint／kapi-gateway／krepo-mops-major-news 的整份 STATUS 快照與本次無關）

## 五、機隊策略

dotfiles 先跑，**驗收通過且成對實驗完成後**才改全域規範檔。

- 已存 STATUS.md **不強制遷移**
- 現況本來就不一致（條目形狀 2 種、歸檔慣例 4 種、5 個 repo 完全沒有 `docs/archive/`）
- ⚠️ `xref-gate.py` **只跑 dotfiles**，機隊上沒有機制會告訴你某個 repo 切到一半
- ⚠️ `ship-state.sh` 是**跨 repo 生效**的（經 `~/.claude/skills` symlink），管轄面比 `dossier.md` 還廣 ⇒ 它的變更同樣排在驗收之後

## 六、驗收準則

1. `./tests/run.sh` 全綠（含 `tests/run.sh:301-348` 反向 gate 與 `:1414-1482` 歸檔孤兒兩組 fixture）
2. `ship-state.sh .`：`dossier:` < 12000 bytes；**條目 flag 對新目錄有作用**——放一條 >800 B 的假條目驗證會紅（v1/v2 的「零 dossier-flag」現在就已是零、無鑑別力）
3. `xref-gate.py --root .` 空輸出；**刪一行索引驗證索引完整性 gate 會紅**
4. **內容不遺失**：決策與里程碑皆為純搬移，逐條比對條目數（114 + 34 + 里程碑）與內容 hash
5. 從乾淨 clone 驗證（`git clone --no-local`）
6. **重指完成**（實測清單）：
   - gate 認得、指向「關鍵決策」**8 條**：`BACKLOG-template.md:26`、`dead-ends.md:153`、`backlog.md:27/39/162`、`decisions-2026-07.md:3`、`decisions-2026-08.md:3`、`plans/2026-08-09-*:148`
   - 指向「已完成(里程碑)」**4 條**：`BACKLOG-template.md:24`、`backlog.md:24`、`milestones-2026-07.md:3`、`milestones-2026-08.md:3`
   - 裸路徑提及四份要搬的檔 **9 處**（排除本計畫檔自身）：`STATUS.md:31/190/191`、`deep-review/evals.md:721`、`decisions-2026-08.md:98`、`milestones-2026-08.md:16`、`backlog.md:78/179`、`plans/2026-08-09-*:83`
   - ⚠️ 七節標題保留 ⇒ 指向「關鍵決策」的指標**遷移後照樣解析成功、gate 照樣綠**，但承諾的內容已不在該節。**這 12 條必須人工逐條確認語意**，不能靠 gate
7. **成對實驗**：領域索引取代逐條結論這一項改變了 agent 讀到什麼，須在**樓層模型**上量兩臂差異（見 §9 步驟 6）

## 七、不做

| 提案 | 理由 |
|---|---|
| **死路一併改** | v2 的死路設計自相矛盾：「結論與證據同檔」使 11 條合併後 912–2436 B 全部超過 800 上限，而 flag 的處置（蒸餾/拆條）正是「不刪」禁止的；換另一種形狀則 gate 恆綠 0 命中。且 `dossier.md:120` 明文「條目 flag 不掃死路節……全靠分層這一條」——廢掉分層等於讓死路從「有一條規則管」變成「什麼都不管」。**機隊 11 個 repo 無一採用分層**（死路節 krepo 18960、evint 7402…），改規範會讓它們全部失去唯一治理規則。**死路維持現狀** |
| ADR 一決策一檔 | 機隊決策條目數百、本 repo 114 條/34 天；ADR 設計給一年 10–50 條。⚠️ **但 krepo 的 `docs/decisions/` ADR 是對的且保留**——它收「新的重大技術選擇」（5 份），與本計畫的日常取捨累積是不同粒度，故 v3 改用 `docs/decision-log/` 分開（§3.1） |
| 給領域檔設**全檔**量體門檻 | 無界內容設上限就是鋸齒的來源。補償走**單條上限＋最長行＋索引完整性**（§3.4） |
| 把 34 條已結案技術債送進 backlog | 違反 backlog 的「未結案」判準（§4 步驟 2） |
| 外部工具 | 08-14 已否決。⚠️ 本地衍生索引不在此列——見 `docs/backlog.md` 的 hook + 倒排索引候選 |
| always-on **量體治理** | 與本計畫正交。⚠️ 但 `claude/CLAUDE.md:32` 的**落點正確性**是功能性前置，已納入目標檔案 |

## 八、風險與未驗證面

1. **領域索引取代逐條結論會不會讓「擋住你」失效**——最大的未驗證面。緩解：索引每行帶條目數。⚠️ **條目數沒有 gate 驗證**，漂掉就變裝飾，且是靜默的——這一項列為已知缺口
2. **領域檔會長到 25KB+ 並繼續長**，無全檔門檻。刻意的，但長期需要領域內的二次收斂，本計畫不解
3. **領域切法有歧義**：114 條有 11 條未分類。執行時逐條定案並記錄
4. **`ship-state.sh` 條目上限擴到 `docs/decision-log/*.md` 後，機隊上採用同路徑的 repo 會開始被掃**——目前無 repo 使用該路徑，但 `krepo` 的量體豁免不涵蓋新落點，需在 `krepo/CLAUDE.md` 同步
5. **成本量化**：v1 的「10K tok 換 3600」高估——`dossier.md` 是 `references/`、按需載入。ROI 為負的方向不變（判斷成本仍在），但幅度未重算
6. **token 數字與 always-on 建議值屬外部依據**，repo 內無 tokenizer

## 九、執行順序

1. 遷移本 repo 存量（§4 步驟 1–3、5–6）
2. 改 `tests/xref-gate.py`（新增索引完整性；**節級孤兒不動**）與 `tests/run.sh` fixture
3. `STATUS.md` 兩節改索引
4. **驗收 1–6**
5. **成對實驗**（驗收 7）：兩臂為「逐條結論」vs「領域索引」，量 agent 在動某領域前會不會找到相關決策。**必須在樓層模型上量**
6. 通過後才改跨 repo／全域面：`ship-state.sh`、`dossier.md`、`project/SKILL.md`、`claude/CLAUDE.md:32`、`AGENTS.md:38`、handoff／ready4quit／deep-plan SKILL、`pressure-tests.md`、三份模板
7. 更新 eval：`setup-sandboxes.sh`、受影響為 `u6`、`g7/g7base`（改模板 ⇒ 結果作廢需重跑）、`dp3/dp4/dp5`（`docs/decisions.md` fixture 與新落點已分開命名，衝突消解）、`G4`、`contract-evals.md:221`、**`handoff/evals.md:136/369/378` 與 `ready4quit/evals.md:85/98`**（oracle 釘住 STATUS.md 決策節）
8. `docs/testing-contract.md`（該檔仍寫「xref-gate 只驗正向」，`887c1c1` 之後已不成立）
9. ⚠️ `pressure-tests.md:258-266` 的 Scenario 以「決策節有 >1000 B 巨型單行條目」為 fixture，分片後四類訊號一個都不會出現，**該格要整個重設計**

## 附錄：v1 與 v2 被推翻的事

**v1（4 條阻斷）**
- 「歸檔用大小當分片鍵」不成立——既有歸檔已按月分片。修正後結論更強：按時間分片且無人讀，正是「時間不是檢索鍵」的證據
- 「月檔約 8KB」低估 8.5×——261 B/日 是殘量率非產出率；`docs/decisions/2026-08.md` 落地當刻就是 68KB。時間分片方案整個放棄
- 死路領域索引與節級孤兒 gate 互斥
- `claude/CLAUDE.md` 的捕捉條文被誤判為「正交」

**v2（4 條阻斷／高）**
- **死路那一支設計自相矛盾**（§7 第一列）⇒ v3 整支移除
- **「146 條決策」含 34 條已結案技術債**，使「最大領域檔 37806 > 門檻」建立在灌了 25% 非決策內容的語料上。修正後 **25282**，結論勉強成立但很弱
- **stale gate 改 mtime** 會在自己指定的乾淨 clone 驗證下恆綠
- **§8.1 自己寫「應先跑成對實驗」，§9 卻沒排進去**；且改 `dossier.md` 會讓 11 個未遷移 repo 失去死路節唯一的治理規則

**共同形狀**：v1 是同一量測口徑套在兩種對象上；v2 是**盤點的池子含了不該含的內容**，以及**把「補償機制」寫成一句話而沒有驗證它成不成立**。兩次的 blocking 都落在「守門/判準的重新配置」，**沒有一條打中診斷**。

---
> **本計畫走過 `/deep-plan`** → ship 時補一段進 `claude/skills/deep-plan/field-log.md`。
> 關鍵欄位是「會 ship 的 ?/?」——**只有實作完的當下答得出來**，事後補是猜的。
