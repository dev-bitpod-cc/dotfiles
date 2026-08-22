<!--
backlog.md — 專案未結案待辦（技術債 + 已知缺口）。發現即記；解決或放棄後寫 D/X/M history
record、保留 B-* 關聯，再移除本檔條目。decision／dead end 不留在 STATUS.md 或本檔。
-->

# Backlog

待辦清單:技術債與已知缺口(更新日期:2026-08-22)

> **為什麼與 `STATUS.md`／history 分家**：三者生命週期不同。STATUS 只留 active／paused；history
> event 發生後 append-only；backlog 只留未結案狀態，直到做掉或明確放棄才會消失。
>
> **本檔刻意沒有 bytes／行數門檻**；治理靠 stable ID、關閉關聯與 repo-local audit。

## 關閉與歸檔慣例

- **償還／解決**：寫 `M-*` record，`關聯` 保留原 `B-*`，再移除本檔條目。
- **變成決策**：寫 `D-*` record（含理由與重議條件），再移除本檔條目。
- **明確放棄**：寫 `X-*` record，再移除本檔條目。
- **不刪**未解決的條目；看不順眼、過長或暫時不做都不是關閉條件。

## 技術債

- **B-20260822-debt-30** · [ ] **文檔治理收尾順序:先釘正確性、再用真 repo 逼出缺口、最後才調 ranking**(2026-08-22 加)。
  依序:① immutability 刪除軸兩格 oracle(**2026-08-22 完成**,見 `M-20260822-immutability-removal-oracles`)
  → ② canary rollout(**2026-08-22 完成**,見 `M-20260822-doc-governance-adopted`,缺口已回填 checklist)
  → ③ 檢索 ranking:`B-20260821-debt-28`(單檔洗版)**已於 2026-08-22 關閉**;`B-20260821-debt-27`(程序型
  文件召回)仍開,但已分成「跨語言」與「權重形狀」兩個子問題,見該條。
  ⚠️ **順序理由**:27/28 打到的正是「不知道標題時找不找得到」,而那是第二個 repo 第一次用才會撞到的面;
  沒有真實 rollout 語料就調 ranking,等於對 dotfiles 自己的語料過擬合。
  ⚠️ **原 plan §6 的 steady-state rollout gate 已由 `D-20260822-rollout-gate-replacement` 取代**:batch 1 定位為
  controlled canary,現在即可開始;qualifying ship 記入 `docs/rollout-ledger.md`,batch 2/3 才要求 steady-state
  證據。月份 shard 正確性不受影響,維持 blocking。(舊敘述以 `git log --merges` 為證據,在 squash merge 下恆為 0,
  已證偽:採用 commit 後實際有 2 次 ship。)

- **B-20260821-debt-27** · [ ] **檢索對程序型文件的語意召回偏弱**。Round 6 以 20 條不複製標題的
  query 探測 reference／policy／skill／eval／plan／backlog，僅 4/20 命中；本批八列 oracle 必須使用
  高辨識度 body 詞才能穩定進 top 5。後續需另以行為需求設計 ranking 改進，禁止把目標標題塞回 query
  製造假綠。
  ⚠️ **2026-08-22 用兩個語料（dotfiles ＋ canary）重量：hit@5 12/20 → 13/20**（per-file cap 帶來的，
  見 `M-20260822-retrieval-source-diversity`）。剩下的 miss **不是同一個問題，要分開處理**：
  - **跨語言**：`docs/document-governance.md` 全篇英文（語言政策要求），中文問題與它 token 交集為零
    ——**任何 ranking 改動都碰不到這一格**，要嘛加別名層、要嘛接受它只能用英文問。
  - **權重形狀**：title 命中 ×200、body ×20，而程序型文件的 section 標題是結構性的
    （「0. 前置」「2. history 遷移」），主題詞只在 body；history 條目的短標題塞滿領域詞，於是恆勝。
  - 已試過並否決：文件 H1 當弱訊號（`X-20260822-doc-h1-token-signal`，淨零）、body 覆蓋率取代全含加分
    （單獨無增益，疊在 cap 上反而 −1）。
  - 現有 ratchet：`tests/fixtures/doc-governance/title-free-recall.tsv`（dotfiles 那 10 條，hit@5 ≥6）。
    **提高門檻只能用新寫的 query 重新量。**
- **B-20260821-debt-26** · [ ] **文檔治理 Round 3 非阻斷後續**。本批不順手擴張核心：xref 待處理
  ignored dirs、alias stale 的 finding/error 語意、正反向 section 比對、shell heredoc fence 與兩份
  `alias_sources` 推導；CLI 待決定 positional files、ship 輸出順序與 adoption 診斷；測試待解除固定
  backlog ID、補 repo-wide audit 與 route portability；另須讓 Codex always-on 接上 event-time 記錄規則。
- **B-20260820-debt-25** · [ ] **文檔治理 Round 2 非阻斷後續**（2026-08-20 加）。本批只修會讓
  gate、檢索、ship 或 agent 行為失真的 blocking findings；其餘待獨立處理：補 `supersedes` 反向邊的
  搜尋呈現、定義 glob class 的 `requires_inbound` 語意、決定 `mode: governance` 是否保留、提供
  worktree trusted-core mismatch 的操作指引，以及縮短 canonical-title 檢索測試的成長成本。
- **B-20260819-debt-01** · [ ] **決策/死路的機械召回**(2026-08-19 加,**獨立候選**)。現況是檢索靠人自覺、沒有機械觸發。
  領域索引(本批要做的那個)是**人工維護、粗粒度**的版本;機械化版本是
  **`PreToolUse` hook + 以檔案路徑為鍵的倒排索引**——要動 `xref-gate.py` 時,自動把
  「提過它的 N 條決策/死路」注入 context,**不必你想到要查**。這正是死路「要在你沒想到要查
  的當下擋住你」的機械層；同 `D-20260811-symmetric-rules-as-signal`「文字是最易被跳過的那層，
  訊號化才接得住」的判準。
  ⚠️ **本地 file-based 向量庫(sqlite-vec / LanceDB / vectorlite)不是這條的重點**:語料才
  ~200 條/300KB,暴力算 cosine 就夠,連 DB 都不需要;而**精確路徑比對比語意相似更準**。
  向量只在「動的東西與決策沒有字面重疊」時才有增益。三條硬約束(git 唯一媒介/隨 repo 移交/
  不引入第二份權威)**都不違反**——索引是衍生物、gitignored、可從 md 重建,故不在 2026-08-14
  否決 mem0/Zep/Letta 那條的範圍內;新成本是 embedding 模型這個 runtime 依賴。
  ⚠️ **2026-08-19 觸發條件重寫**:原本寫「等領域索引跑一陣子後仍然發生」,而領域索引所屬的
  分片計畫三版皆被判不通過 ⇒ **該條件永遠不會成立,是循環依賴**(第三方審查抓出)。
  **新觸發條件:本條升為獨立候選,不依賴分片計畫。** 它解的是「儲存」與「召回」拆開之後的
  召回那一半,與分片(只解儲存)正交。⚠️ 設計上須用 `permissionDecision: deny` 擋第一次呼叫
  再讓模型重讀,**不要只回 `additionalContext`**——官方文件**未載明**該欄位相對於工具執行的
  時序,不賭未定義行為。`Bash` 寫檔旁路需另有 fixture。
- **B-20260819-debt-02** · [ ] **handoff `survey`／`list` 等價 gate 的前綴白名單是寫死的**(2026-08-19 加)。
  `tests/run.sh` 那條「survey 的 active 區段與 list 逐字等價」用
  `grep -E '^(active: |  path: |  title: )'` 兩邊比對,**任何新增的縮排子行都不在名單內、
  天生豁免於這道 gate**。本次(mtime 時戳)只加欄位、未加子行故未受影響,但附錄評估過的
  「錨點 repo 欄」(`repos: dotfiles, krepo`——多份 active 時最強的辨識訊號)一旦要做,
  必須連同這個缺陷一起處理:擴白名單、或改成「比對兩邊全部 active 相關行」。
  ⇒ 該欄本次刻意不做,理由與取捨見 `docs/plans/2026-08-19-handoff-active-mtime.md`。
- **B-20260819-debt-05** · [ ] **`deep-plan` 的模型層級待一個獨立決定**(2026-08-19 加,與下一條同型)。2026-08-19 首次真實執行
  跑在 **Opus**(session 模型),而全部 evals 校準在 **Sonnet**(樓層)。兩個後果性質不同:①**成本**
  ——第二輪與 N 都動不得(理由見 `claude/skills/deep-plan/field-log.md`「C2 — 第二輪不能砍，但它審的是處置而非計畫」),
  模型是唯一沒動過的降本槓桿;②**可比性**——強模型會自己補上規則要求的行為,**跑在 Opus 的觀察
  一律不能拿來判「某條規則有沒有作用」**。要決定的是「預設釘 Sonnet、需要時才升」還是「維持吃
  session 模型、只在 field log 記下當次模型」。⚠️ 不該在檢討裡順手改——同下一條。
- **B-20260818-debt-06** · [ ] **`deep-plan` 的 N 預設值待一個獨立決定**(2026-08-18 加)。E1 實測阻斷級聯集 N=2→5.00、
  N=3→6.00,**判準寫的「沒有新增就維持 2」條件不成立**,而它只定義了那一個分支 ⇒ 預設維持 2 未動。
  要決定的是成本 vs 覆蓋:多出來的**全是嚴重度分歧、不是新問題**(核心那條 4/4 全中、四臂結論一致),
  但每加一個 reviewer 約多 1.7 條 findings。⚠️ **同批還有第二格沒定義到**:E3 的判準要求
  「(c) 佔多數**且**含阻斷級」才判上限不足,實測落在「(c) 少數卻含唯一阻斷」——兩格都**不可事後補**,
  要改判準是新的一次決定。逐條數據見該 skill `evals.md` 的 E1／E3 節。
- **B-20260817-debt-07** · [ ] **`deep-plan/evals.md` 未經 2026-08-17 那場 `/deep-review`**(batch 條款禁止 eval 檔進 reviewer
  prompt)。要不要單獨審是獨立決定,尚未做。⚠️ 2026-08-18 該檔又大幅擴充(P8–P12 ＋ 八次實跑紀錄),
  未審的面積比當初更大。
- **B-20260816-debt-08** · [ ] **`settings.json` 的 `autoMode.environment` 固化了 20 個內建 slot 的複本,升版不會自動跟上**
  (2026-08-16 加)。`allow` 那半邊已用 `$defaults` sentinel 解掉(該決策已歸檔至 `docs/archive/decisions-2026-08.md`),但
  **`environment` 不吃 sentinel**——放了是純附加,會出現兩行同名 slot 且內容互斥,所以只能全量
  寫出。代價:官方調整內建 slot 措辭時我們不會跟著變,**且無訊號**。偵測法:
  `diff <(claude auto-mode defaults | jq -r '.environment[]' | sed 's/:.*//') <(claude auto-mode config | jq -r '.environment[]' | sed 's/:.*//')`
  ——比 slot 名可抓到新增/更名,措辭漂移則要逐條比。**可能的收法**:`brewup.sh` 加一道比對提示
  (與 bun 落後提示同性質,只提示不自動改)。⚠️ 若日後 `environment` 也支援覆寫語意,這條連同那
  20 條複本都該直接刪掉。
- **B-20260815-debt-09** · [ ] **`scripts/ensure-dotfiles-remote.sh` 一次性遷移殘留,移除條件已滿足、待動手**(2026-08-15 加,
  掛 `dotfiles-sync.sh`＋`brewup.sh`)。條件是 inventory 的 14 台**＋不在 inventory 的兩台 MacBook**
  origin 皆為 `jjshen-eland`:14 台當天完成,兩台 MacBook **同日確認已跟上**(它們正是靠 `brewup.sh`
  這個呼叫點自己正規化的)。**尚未拆**——要同時清兩個呼叫點與 `tests/run.sh` 第 23b 節,列為獨立
  工作項。⚠️ **本條初版的移除條件只寫「14 台」、漏掉那兩台**,當天差點據以移除——`dotsync` 的
  涵蓋範圍不等於機隊全體。
- **B-20260815-debt-10** · [ ] **`BLOCKED` ＋ `no checks reported` 這一格沒有 eval 覆蓋**(2026-08-15 加)。判準已寫進
  `ship-paths.md`(exit 1 要看輸出才分得出「check 失敗」與「這 repo 沒有 required check」),但
  Scenario 15 的 stub 回的是全綠 exit 0,**測不到這一格**。補法:`gh-stub` 加 `CHECKS_RC=1` ＋
  `no checks reported` 輸出的變體,配一則情境。⚠️ **這個洞是實戰撞出來的、不是 fixture 抓到的**
  ——本批三臂 eval 全綠仍漏了它,因為三臂都沒有「repo 沒有 CI」的形狀。
- **B-20260815-debt-11** · [ ] **`tests/run.sh` 平時只在 macOS 跑,跨平台分支的 Linux 行為無人驗**(2026-08-15 發現:
  `:4199` 的 stat 順序寫反,在 Linux 上恆紅了不知多久,直到 hook 那批第一次上 Linux 才浮出)。
  **危害是它會掩蓋真失敗**——往後在 Linux 看到 FAIL=1 會先當成已知那條。dotsync 後任何一台
  都跑得動 `bash tests/run.sh`,但沒有任何流程會去跑。未決:要不要納入某個既有流程。
- **B-20260814-debt-12** · [ ] **xref-gate 的判準是「heading **或**內文」,故通用詞當節名會讓保護降級**(2026-08-14 做
  突變測試時發現):把 `docs/dead-ends.md` 的 `## 分工` 改名,gate 仍綠——因為該檔另一處指標句
  裡也有「分工」二字。**節名撞通用詞時,突變測試必須改 heading 與內文兩處才測得準**;想真正
  修就得收窄成只比對 heading,但那會犧牲「權威搬進內文段落」的情境。未定,先記。
- **B-20260811-debt-13** · [ ] **`tests/run.sh` 尚有 20 處 `printf … | grep -q`**(對照 117 處已改 herestring,2026-08-11 盤點)。
  CLAUDE.md 地雷要求存在性比對一律用 herestring:大輸入下 `grep -q` 命中即退出,上游 printf
  吃 SIGPIPE、pipefail 讓整條判偽 → 斷言結論反轉。**目前 20 處都安全**——全在 stub 輸出比對上,
  輸入恆小、printf 一次寫得完。列為債而非 bug 的理由:它是**潛伏型**,某個 fixture 的輸出一變大
  就爆,且症狀是斷言默默反轉、不是報錯。未改——20 處機械替換不該塞在 pre-quit 收尾階段做。
- **B-20260809-debt-14** · [ ] **handoff 的 `dirty=N` 敘述會在 W2→W3 之間過期**(2026-08-09 H5 迴歸復發,首跑即記過)。
  W2 蓋錨點後 W3 才把跨輪死路沉澱進 repo 的 STATUS.md,working tree 檔數增加而錨點與交接檔敘述
  都停在蓋錨點當下 → 寫出「`dirty=1` 就是上述**兩個**未 commit 檔案」。**同批 H8 同 fixture 同模型
  卻主動講清落差**——行為分歧已達動規則的證據門檻。傾向**改順序而非加告誡**:W3 的 dossier 沉澱
  移到 W2 之前(predecessor 在 W1 已定出,可行),dirty 在蓋錨點當下即為最終值,過期的可能從流程
  消失;配一條 H5 oracle(用 8/09 的逐字錯誤當 RED)。未做——本輪任務是迴歸驗證。
- **B-20260820-debt-15** · [ ] **保留自已結案項的兩條判準**(本體已歸檔):①`tests/run.sh` 測試節的目標檔是 **repo 根的
  `CLAUDE.md`**,不是 `claude/CLAUDE.md`(後者講的是「何時該寫測試」);②**便宜的守門要趁乾淨時加**
  ——等它長歪再加就得先還債。
- **B-20260808-debt-16** · [ ] R4 non-blocking 餘一項:**新增 prose 的中文半形標點與既有全形混排**。2026-08-08 未做——
  「新增 prose」指哪一批已不可考,純風格、無失敗案例,且該日又寫入大量中文 prose(移動標靶)。
  要做就一次全檔統一,不要逐批追。其餘三項(Transfer 模式 commit 歸屬、evals/README 路徑基準、
  handoff evals H4 排序)已於 2026-08-08 修畢。
- **B-20260820-debt-17** · [ ] **「tests/stub 有覆蓋、實戰未驗」一組**(遇到對應情境時順手確認即可,不必專程做):
  SessionStart hook 落後提醒(真實落後的 clone);autocodex exec 的 resume 分支(exit 4 救援階梯,
  三輪實跑皆一次成功、只有 stub 覆蓋,F15(b) 待真實空報告);review-anchor 的 stale STOP 與
  codex-next 冪等(F16 b/c,待 autofix 迭代中真的 rebase/重試);repo-review 新契約(F16–F18 規格
  覆蓋,待多輪 autofix 確認弱模型不會退回每輪帶 `--autofix`)
- **B-20260820-debt-18** · [ ] Scenario 11 的「merge 但無 PR」分支只在 SKILL body 一行指標帶到 ship-paths,GREEN 實測中
  弱模型未展開讀——非違規故未補;重現才加明示(Iron Law)
- **B-20260820-debt-19** · [ ] pressure-tests S8/S9/S12 沙盒未納入 `claude/evals/setup-sandboxes.sh`;S10(transfer
  credentials)與 S12(dossier 三 flag 蒸餾紀律)連首輪實測都還沒跑
- **B-20260820-debt-20** · [ ] codex plugin 去留待定:實質只當傳輸管道,exec 接管後僅剩 `/codex:transfer` 獨有——
  exec 路徑跑穩數輪後重新評估 uninstall
- **B-20260721-debt-21** · [ ] codex C2 轉交 findings 餘項(2026-07-21 代收):F6 skill-building-guide 的
  `$skill-creator/scripts/quick_validate.py` 路徑解析(context-dependent)。F5(多輪 autofix
  死鎖)已於 2026-08-03 判 true positive 並修復
- **B-20260805-debt-22** · [ ] 輪次隱蔽的框架效應只有**弱證據**(2026-08-05):A/B 盲測每組 n=3、B 組內變異大(2/4/2),
  blocking 平均 3.67→2.67 方向一致但未達證實;質性佐證較強(B 組把 README 已揭露的缺口讀成
  「已承認故不算」而降級,A 組三個零出現)。**擴大樣本才能定論**——全文見 deep-review `evals.md`。
- **B-20260820-debt-23** · [ ] evals 從未做**系統性多模型覆蓋**:skill-building-guide 發布前 checklist 要求
  Haiku+Sonnet+Opus 都測,實際執行紀錄以 Sonnet 為主、其餘零散;d1/d2/d3 沙盒跑一次多模型
  批次才算補齊(現有紀錄多為單模型單次)。
- **B-20260721-debt-24** · [ ] /project 手感驗證後半段:spec→實作(即時記錄)待驗;mid-work re-spec 2026-07-21 研究後
  判維持不改(Iron Law:no failing scenario, no instruction)——除非觀察到照過時 spec 執行或
  擅自擴大範圍,才補程序+RED eval

## 已知缺口

- **B-20260813-gap-01** · **codex reviewer 跑得動測試、但跑不完**(2026-08-13 C1 實測):PR #94 的 profile 解決了「建不了 cache」
  (events 實查真跑了三次),但 sandbox 內 `PASS=956` vs 主機 `983`,伴隨 `cloned an empty repository`
  ——建 git fixture 在 `:read-only`+tmpdir-write 下仍受限。**「能啟動」≠「跑得完」**;那個中途計數正是同輪
  假 `verification: executed` 的來源(被讀成「全部通過」,漏掉 `TEST_RC=1`)。調 profile 前先看這條。
- **B-20260807-gap-02** · **eval 的受測 subagent 拿不到 deferred tools,部分契約在沙盒中無法構造**:2026-08-07 實測——
  主 session 的 `CronList`／`TaskOutput` 正常,探針 subagent(`Tools: *`)對同一批 `select:` 一律得
  `No matching deferred tools found`。凡「該工具查得成」才成立的情境因此做不出來,ready4quit
  **Q4c**(`RECALLED + ✓`,需最低證據等級剛好是 RECALLED)至今無 GREEN 證據。symlink 前置已解除,
  但手動驗證二度失敗,並暴露原程序自身兩個錯(`~/.dotfiles` 當 pwd 讓 Git 衛生恆 ⚠;「全新且安靜的
  session」自相矛盾——無對話歷史時回憶型面向只會落 PARTIAL)。**v3 程序見
  `claude/skills/ready4quit/evals.md`,別再照舊程序跑。**
- **B-20260811-gap-03** · **同型處置的 self-report 擋得住靜默跳過,擋不住填了但敷衍**(2026-08-11 落地兩軸拆分＋五個終態
  報告必填「同型處置紀錄」表之後的殘留面):**表格內容無法機檢**,`tests/run.sh` 第 1f 節只驗
  **結構**(模板覆蓋率、表頭形狀、引用行不複述軸名等,逐項以該節為準)。R5 終止路徑為何不補
  behavior eval 見 `docs/archive/decisions-2026-08.md`「同型掃描的 R5 終止路徑刻意不設 behavior eval」。

- **B-20260807-gap-04** · **Mac 上 brewup 會被 codex cask 掛死(Gatekeeper)**:2026-08-07 第三次發作。復原已有入口
  `brewfix`(唯讀診斷,`--fix` 才動手);機制、鑑別法、三條走不通的預防路徑全文見
  `claude/known-hazards.md`「cask 升版卡死」,**此處不重述**。**仍未解**:確切觸發條件未知且事後無法重現
  (同版本內容換路徑執行正常),要重現只能等該 cask 真正出新版。**未決**:預先設 xattr `0x0040`
  技術上可行,但前提已被負面結果動搖、代價卻是確定的(拿不到 tarball 簽章身分)——
  **用確定的代價換不確定的效果,暫不做**,優先靠已實證的復原路徑。

- **B-20260810-gap-05** · **kernel 的「fallback conventions 由 repo 勝出」對 host repo 實務上不可達**(2026-08-10 G6 樓層
  重跑的新 RED):Sonnet 兩次都用 Conventional Commits,而該 repo 明文拒絕它——**根因不是違抗,是
  `AGENTS.md`/`CONTRIBUTING.md` 的 tool_use 皆為 0,它沒看過那條規則**。safety floor 是被載入的
  文字所以穩;deference 卻要求一個「先去讀檔」的動作,沒有東西保證它發生(與 G1b 同一失效面)。
  **觸發:真的要在別人的 repo 常態工作時**——候選解三條與代價見
  `claude/evals/contract-evals.md`「這條 RED 的根因不是違抗，是那個檔從頭到尾沒被打開」。
- **B-20260820-gap-06** · **`codex/AGENTS.md` 與 root `AGENTS.md` 同名不同角色**(來源檔 vs repo-resident 契約):改
  `codex/**` 時兩份都被當 guidance 餵進 reviewer——**重複但無害,改名已 DROP、此實害就這樣接受**
  (理由見 `docs/archive/decisions-2026-08.md`)。
- **B-20260820-gap-07** · 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,
  改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- **B-20260820-gap-08** · biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+credentials 明文散於三台。
- **B-20260807-gap-09** · **`agy`(Antigravity CLI)只手動裝在 macs,未寫進 `setup-mac-env.sh`**:2026-08-07 因 gemini-cli
  已於 2026-06-18 停服而改裝其後繼(`brew install --cask antigravity-cli`,binary 名 `agy`)。
  後果:新機器跑 setup 不會裝、macmini/m4mini 目前也沒有。該 cask 標 `auto_updates`,故 `brewup`
  不會升它(除非 `--greedy`)。**它沒有 `generate_completions_from_executable`,不會踩 codex 那個
  Gatekeeper 坑**,但首次執行仍會走核可流程——要裝就在該機 console 前跑一次。
- **B-20260809-gap-10** · **兩部個人 MacBook 不在 `inventory.conf`**(公司／家中,經 VPN ssh 進 macs),`dotsync`／`allup`
  涵蓋不到——兩機已各自補齊,**留下的是結構性事實**:要跟上得在該機本地跑 `brewup`,不會有人幫
  它們 pull,而**漏跑是無聲的**(skill／地雷／模板停在舊版)。**加進 inventory 這條路今天不可用**:
  2026-08-09 查 tailnet 沒有它們,且常離線的筆電會讓每次 dotsync 都帶 ❌、稀釋訊號。
  **待確認是刻意(終端設備不入清單)還是缺口。**
