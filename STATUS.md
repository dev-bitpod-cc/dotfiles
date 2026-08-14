<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec;ship 時同步;移交前補齊完整度。維護者可能另有工具輔助,
        但**規範本身在此、不在工具**——沒有那些工具也照樣維護得下去。
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-15)

---

## 進行中

(無進行中工作項——2026-08-14 的 dossier／always-on 治理已收斂,見里程碑。)

> 更早的凍結計畫:`docs/plans/2026-08-09-repo-contract-extraction.md`、
> `docs/plans/2026-08-10-dossier-portability.md`。

**其餘工作全部帶觸發條件、皆不在進行中**:Phase 3 改名 **DROP**;Phase 4 installer、G5、
transfer 的 portability 步驟 **DEFER**——逐條的觸發條件與理由見上列兩份凍結計畫,此處不複述。

---

## 關鍵決策(附理由)

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。**歸檔判準**：已固化且不再影響現行方向 → 歸檔；仍在生效的一律不歸檔（死路＝防重工、技術債＝未解決，移出 always-on 即失效）。超標時**優先歸檔、不要為幾百 bytes 去壓無關舊條目**——那個動作重複幾次本身就是訊號。

- **2026-08-15 dotfiles 轉入 `jjshen-eland`,用所有權消掉 gh 雙帳號碰撞,不加 wrapper**。active gh
  account 是**機器全域可變狀態**,工作 repo 的平行 session 會切走它 → ship 個人帳號的 repo 就吃到
  `protection: UNKNOWN` 與 `pr create` 失敗。**否決 wrapper**:爆炸半徑只有兩個 repo,解法卻要
  shadow 掉 `gh` 散到 14 台,正是 CLAUDE.md 自己禁的 PATH shadowing;且 `UNKNOWN → PROTECTED → PR`
  恰等於預設路徑,實際後果為零。⚠️ `github-me`／`id_personal` 原樣保留(理由見 CLAUDE.md);
  iOS App 仍在個人帳號,它若也從雙帳號機器 ship 會重演,屆時同一條前綴即解。
- **2026-08-14 always-on 量體訊號放 ship-state、且刻意無條件印**。治理的對象一直是錯的:兩份
  `CLAUDE.md` 每 session 載入卻**零 gate**,而不自動載入的 STATUS.md 有五層。放 SessionStart hook
  不行(那支的契約是「無事發生就無輸出」)。**背離「只在超標時印」原則**是因為它是 baseline 觀測
  而非處置訊號。⚠️ 升級成 flag 前要先解決「結構下限出口」——機隊最大 102968,貿然設門檻會有
  七八個 repo 常亮。
- **2026-08-14 外部 findings 七條落地兩條,其餘五條不做**。逐條判定見
  `docs/plans/2026-08-14-dossier-governance.md`「DROP」;兩個要點:軟目標訊號**要先有「已達結構
  下限」的出口**(否則對 always-on 佔 72% 的本 repo 只是第二個常亮 flag),per-repo 覆寫要走
  krepo 豁免條款的形狀(帶理由與失效條件)而非純數字。
- **2026-08-13 不建 Codex 版 project skill,等真實 RED**。既然 Codex 已可 ship,直覺下一步是把
  Claude 的 `project` workflow 複製一份給它;不做的理由是 `codex/AGENTS.md` 改後已指向
  **repo 既有的 shipping skill**,複製等於製造第二份會漂移的 pressure-tested 邏輯(同
  `/project log 包裝 /uap` 那條死路的形狀)。**觸發:Codex 端出現真的走不動的情境**——屆時再做,
  且優先重用同一套 mutation 腳本而非另寫。
- **2026-08-11 驗證「重排後內容零遺失」只有 token 級檢查有效**。滑動窗口(剝非中文後比對)與
  語意片段(按標點切)兩種都被重排大量假陽性淹沒——前者把原本被英文分隔的中文黏成原文不存在的串
  (**與 xref-gate 檔頭警告的「整檔併成一串」同源,只是反過來造成假遺失**),後者對「含→涵蓋」
  「逗號→分號」這類改寫全數判缺。有效的是抽 `code` 識別字與日期逐一比對(99/99、3/3)。
  下次做搬遷驗證直接用 token 級,別再繞前兩種。

> 以下六條為 2026-08-14 從「已知缺口」**歸位**——它們記的是「決定先不做、理由是什麼、什麼條件
> 下重議」,那是決策語意。放在缺口節會永久滯留(缺口沒有出口),放這裡才吃得到歸檔判準。
> 標的日期是原始事件日,推導與實測數字沉 git history(歸位前的全文在 STATUS.md 的 git log)。

- **2026-08-11 同型掃描的 R5 終止路徑刻意不設 behavior eval**。比照 d7 預造假 fix commit 的話,
  受測 agent 沒真做過那幾輪修復、**填不出自己沒做過的處置**,測到的會是 fixture 缺陷而非 skill
  行為。該路徑改由 `tests/run.sh` 第 1f 節的靜態 gate 守(只驗結構,不驗內容誠實度)。
- **2026-08-11「規則的對稱面／使用點」不補文字原則,要做就訊號化**。文字是最易被跳過的那層
  ——實證:Step 2 抓到 `add -A` 例外的使用點缺口純屬偶然,同 session 的 #43 走過同一個 Step 2
  仍漏兩條 blocking。訊號化的形狀＝偵測變更集含契約檔時印對稱面候選、不判語意(同 `dossier-flag`)。
  **做不成 exit-code gate**:規則是語意抽象出來的,機器不知道要 grep 什麼。
  **2026-08-15 又一個實例**:`stat -c` 先於 `-f` 的順序在 `codex-runtime-hygiene.sh` 與
  `tests/run.sh:3758` 都有明文註解,卻仍漏了 `:4199` 這個使用點——**文字原則確實接不住**。
- **2026-08-10「另一個寫入者的筆記可能被蒸餾壓掉」暫不動規則**。協作者把粗胚寫進「進行中」,
  那正好是會被收斂的一節,而 Step 2 的前提「此刻 session 記憶還在」**對別人寫的東西不成立**。
  **觸發條件:觀察到一次真的被壓掉,才動規則**——同族先例(ship-state 的行號診斷)也是猜錯兩次才加。
- **2026-08-09 `Generated docs never win` 是存量違例,記著但不 churn**。已上線卻從未測過
  (G5 隨 OpenWiki 一起 DEFER),屬 `No failing scenario, no instruction` 的存量違例——**不刪,
  也不為它補 eval**。(2026-08-14 補:OpenWiki 官方定位確認為 derived 層,與 dossier 正交,此條不動。)
- **2026-08-08 buried 的 review 痕跡不實作自動壓平**(夾在語意 commit 中間時 `reset --soft`
  碰不到)。`rebase -i` 配 `GIT_SEQUENCE_EDITOR` 完全非互動、每顆 buried 標 `fixup` 折進前一顆
  語意 commit 即可、衝突為零是結構保證,**做得到但沒做**——代價是語意 commit 的 hash 與內容都會變、
  「squash 絕不動語意 commit」從結構保證退成測試保證、多一條 rebase 回滾路徑、branch 首顆是
  buried 時無目標;而實測多為 none/top-contiguous。不變式因此只做到「壓得掉的一律壓」。

## 死路(試過但放棄——防重工)

> 各條的推導、實測數字與 eval 編號在 `docs/dead-ends.md`「分工」,本節只留**會擋住你的那一句**。
> 分層照 `claude/known-hazards.md`「分工」對「已知地雷」的做法:死路要能在你沒想到要查的當下
> 擋住你,**規則不在 always-on 就不生效**,故結論留此、證據外移。

- **用 direnv(`.envrc` 注入 `GH_TOKEN`)解 gh 雙帳號**:direnv hook 掛在 zsh precmd 上,而
  `ship-state.sh`／`gh pr create` 都是 agent 的一次性 Bash 呼叫,**precmd 不觸發**。**推廣:靠
  rc／prompt hook 的方案對 agent 執行路徑一律無效。**
- **mc(Midnight Commander)當遠端檔案管理器**:協定層否決——mc 的 `sftp://` VFS 走內建 libssh2、
  **不支援 OpenSSH 使用者憑證**,而內網主機一律 cert 認證,主要路徑不通。同樣需求用 `lftp`。
  **libssh2 支援 cert 之前,重評都是白費**。
- **手動把 worktree 的 SKILL.md 複製到主 checkout,以繞過 `~/.claude/skills` symlink**:主 checkout
  有其他 writer、`brewup` 會丟棄未提交改動,而最要命的是**「測的到底是哪一版」變得不可考**
  ——與這些 skill 自己在防的「證據對不上結論」同型。**正解是先合併、主 checkout pull 之後再驗。**
- **依外部提案的診斷改 `handoff` 的 W1(anchor 集合判準)**:三輪 eval 全部 GREEN 而放棄
  (依 Iron Law:no failing eval, no skill change)。**這條的價值在於「實地確實在寫入端失手,但
  fixture 重現不了」是兩件事,後者才是改 body 的門檻**。日後事故復發,**先讓 fixture 紅起來再動 W1**。
- **無 observed RED 的明示規則**(2026-08-13 一天內加兩條、當天全撤;同形狀第三次)。
  **共同形狀:RED 來源本身證明了規則不必要**,判準是**成對實驗**——兩條都是 baseline 臂一樣做對。
  **「觀察到失效面」≠「需要新規則」**:正確的問法是**既有規則接不接得住**。例外只有「把 body
  陳述錯的事實改對」那半(修正錯誤陳述不需 RED)。
  **2026-08-14 第四次,但這次流程贏了**:「已決議暫不做屬決策節、不是已知缺口」這條判準,
  在寫進 `dossier.md` **之前**先建 u6 沙盒跑成對實驗(Scenario 17),v2 四輪兩臂零差異——
  baseline 自己就把現況缺陷放缺口、決定不修放決策並交叉引用,判準因此沒寫。前三次是寫了才撤,
  這次是**先測再決定**;差別在於前三次有「實地出過事」的印象在推,這次刻意先讓 fixture 說話。
  ⚠️ **順帶推翻了自己的診斷**:實測顯示 Sonnet 分類分得很清楚,所以缺口節那 8 條的滯留
  **不是寫入時分錯**,較可能是「先寫成缺口、後來做了決定卻在原地追加而沒搬家」。新假設待測。
- **收窄「已知缺口」定義(加上「我方」主體)**:G10 成對實驗,驗收批次 control 僅 **1/4** 落缺口
  (門檻 ≥3/4)→ 不改。**真正的發現是行為不穩定**——同一 fixture／query／模型,pilot 兩輪全落缺口、
  驗收四輪只有一輪落,**多數行為在兩批間反轉**。候選臂確實引用了收窄定義,所以不是定義沒用,
  而是 baseline 多數輪次也做對。⚠️ 連帶推翻 G9 留下的「節名歧義」假設(顯形率僅 1/4)。
  數據見 `claude/evals/contract-evals.md`「G10」。
- **把 krepo 的「新東西該寫進哪一個檔」決策樹上收成全域規則**:G9 成對探測,兩臂各 4 輪
  **零差異**。**候選那臂還更糟**——為適配本 repo 加的「狀態類不走三題」成了跳過判準的逃生口,
  受測 agent 逐字引用它繞開決策樹。⚠️ 起念的理由「always-on 在回漲、沒人知道新內容該不該
  進去」**查證後不成立**(+2783 bytes 四筆都該在 always-on)——**又一次憑推論指認失效面**。
  數據見 `claude/evals/contract-evals.md`「G9」。
- **拿「STATUS.md 負增量」當「被 flag 逼著壓縮」的代理指標**:2026-08-14 用過,結論全錯——
  多數負增量是拆分搬移與完成項移出,且該 repo 的量體 flag 早有明文豁免。**正解:數 flag 實際
  處置的 commit,並先查該 repo 自己的契約檔有無豁免**——量體訊號不分辨「誰讓它變小」。
- **「/project log 包裝/並存 /uap」**:disable-model-invocation 下無法鏈式呼叫,只能複製
  pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,直接取代。
- **在移交出去的 repo 內放一份 dossier 規範精簡版**:①**非自動載入的檔不會被讀**(G1b 實測);
  ②散到 N 個 repo 後零機械守門,規範一改就全部 stale 而沒人會發現,最壞是**交出去的東西主動教錯**;
  ③常駐檔會腐爛。**正解是既有落點**:STATUS.md 檔頭註解 + 該 repo 的 `CLAUDE.md`。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:實證 general-rag-cs 的已消費
  STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] **`scripts/ensure-dotfiles-remote.sh` 一次性遷移殘留,全機隊跟上後移除**(2026-08-15 加,掛
  `dotfiles-sync.sh`＋`brewup.sh`)。**移除條件**:inventory 的 14 台**＋不在 inventory 的兩台
  MacBook** origin 皆已是 `jjshen-eland`。14 台當天即完成;**兩台 MacBook 尚未**——它們正是靠
  `brewup.sh` 這個呼叫點才會自己正規化(見 CLAUDE.md「不在 `inventory.conf` 的機器怎麼跟上」
  第 ② 步),現在拆掉就只剩 GitHub 轉移 redirect 撐著。⚠️ **本條初版的移除條件只寫「14 台」、
  漏掉那兩台**,2026-08-15 當天差點據以移除——`dotsync` 的涵蓋範圍不等於機隊全體。
- [ ] **`tests/run.sh` 平時只在 macOS 跑,跨平台分支的 Linux 行為無人驗**(2026-08-15 發現:
  `:4199` 的 stat 順序寫反,在 Linux 上恆紅了不知多久,直到 hook 那批第一次上 Linux 才浮出)。
  **危害是它會掩蓋真失敗**——往後在 Linux 看到 FAIL=1 會先當成已知那條。dotsync 後任何一台
  都跑得動 `bash tests/run.sh`,但沒有任何流程會去跑。未決:要不要納入某個既有流程。
- [ ] **xref-gate 的判準是「heading **或**內文」,故通用詞當節名會讓保護降級**(2026-08-14 做
  突變測試時發現):把 `docs/dead-ends.md` 的 `## 分工` 改名,gate 仍綠——因為該檔另一處指標句
  裡也有「分工」二字。**節名撞通用詞時,突變測試必須改 heading 與內文兩處才測得準**;想真正
  修就得收窄成只比對 heading,但那會犧牲「權威搬進內文段落」的情境。未定,先記。
- [ ] **`tests/run.sh` 尚有 20 處 `printf … | grep -q`**(對照 117 處已改 herestring,2026-08-11 盤點)。
  CLAUDE.md 地雷要求存在性比對一律用 herestring:大輸入下 `grep -q` 命中即退出,上游 printf
  吃 SIGPIPE、pipefail 讓整條判偽 → 斷言結論反轉。**目前 20 處都安全**——全在 stub 輸出比對上,
  輸入恆小、printf 一次寫得完。列為債而非 bug 的理由:它是**潛伏型**,某個 fixture 的輸出一變大
  就爆,且症狀是斷言默默反轉、不是報錯。未改——20 處機械替換不該塞在 pre-quit 收尾階段做。
- [ ] **handoff 的 `dirty=N` 敘述會在 W2→W3 之間過期**(2026-08-09 H5 迴歸復發,首跑即記過)。
  W2 蓋錨點後 W3 才把跨輪死路沉澱進 repo 的 STATUS.md,working tree 檔數增加而錨點與交接檔敘述
  都停在蓋錨點當下 → 寫出「`dirty=1` 就是上述**兩個**未 commit 檔案」。**同批 H8 同 fixture 同模型
  卻主動講清落差**——行為分歧已達動規則的證據門檻。傾向**改順序而非加告誡**:W3 的 dossier 沉澱
  移到 W2 之前(predecessor 在 W1 已定出,可行),dirty 在蓋錨點當下即為最終值,過期的可能從流程
  消失;配一條 H5 oracle(用 8/09 的逐字錯誤當 RED)。未做——本輪任務是迴歸驗證。
- [ ] **保留自已結案項的兩條判準**(本體已歸檔):①`tests/run.sh` 測試節的目標檔是 **repo 根的
  `CLAUDE.md`**,不是 `claude/CLAUDE.md`(後者講的是「何時該寫測試」);②**便宜的守門要趁乾淨時加**
  ——等它長歪再加就得先還債。
- [ ] R4 non-blocking 餘一項:**新增 prose 的中文半形標點與既有全形混排**。2026-08-08 未做——
  「新增 prose」指哪一批已不可考,純風格、無失敗案例,且該日又寫入大量中文 prose(移動標靶)。
  要做就一次全檔統一,不要逐批追。其餘三項(Transfer 模式 commit 歸屬、evals/README 路徑基準、
  handoff evals H4 排序)已於 2026-08-08 修畢。
- [ ] **「tests/stub 有覆蓋、實戰未驗」一組**(遇到對應情境時順手確認即可,不必專程做):
  SessionStart hook 落後提醒(真實落後的 clone);autocodex exec 的 resume 分支(exit 4 救援階梯,
  三輪實跑皆一次成功、只有 stub 覆蓋,F15(b) 待真實空報告);review-anchor 的 stale STOP 與
  codex-next 冪等(F16 b/c,待 autofix 迭代中真的 rebase/重試);repo-review 新契約(F16–F18 規格
  覆蓋,待多輪 autofix 確認弱模型不會退回每輪帶 `--autofix`)
- [ ] Scenario 11 的「merge 但無 PR」分支只在 SKILL body 一行指標帶到 ship-paths,GREEN 實測中
  弱模型未展開讀——非違規故未補;重現才加明示(Iron Law)
- [ ] pressure-tests S8/S9/S12 沙盒未納入 `claude/evals/setup-sandboxes.sh`;S10(transfer
  credentials)與 S12(dossier 三 flag 蒸餾紀律)連首輪實測都還沒跑
- [ ] codex plugin 去留待定:實質只當傳輸管道,exec 接管後僅剩 `/codex:transfer` 獨有——
  exec 路徑跑穩數輪後重新評估 uninstall
- [ ] codex C2 轉交 findings 餘項(2026-07-21 代收):F6 skill-building-guide 的
  `$skill-creator/scripts/quick_validate.py` 路徑解析(context-dependent)。F5(多輪 autofix
  死鎖)已於 2026-08-03 判 true positive 並修復
- [ ] 輪次隱蔽的框架效應只有**弱證據**(2026-08-05):A/B 盲測每組 n=3、B 組內變異大(2/4/2),
  blocking 平均 3.67→2.67 方向一致但未達證實;質性佐證較強(B 組把 README 已揭露的缺口讀成
  「已承認故不算」而降級,A 組三個零出現)。**擴大樣本才能定論**——全文見 deep-review `evals.md`。
- [ ] evals 從未做**系統性多模型覆蓋**:skill-building-guide 發布前 checklist 要求
  Haiku+Sonnet+Opus 都測,實際執行紀錄以 Sonnet 為主、其餘零散;d1/d2/d3 沙盒跑一次多模型
  批次才算補齊(現有紀錄多為單模型單次)。
- [ ] /project 手感驗證後半段:spec→實作(即時記錄)待驗;mid-work re-spec 2026-07-21 研究後
  判維持不改(Iron Law:no failing scenario, no instruction)——除非觀察到照過時 spec 執行或
  擅自擴大範圍,才補程序+RED eval

## 已完成(里程碑)

> 2026-07 以前的里程碑已歸檔至 `docs/archive/milestones-2026-07.md`；
> 2026-08-05～08-13 各批已歸檔至 `docs/archive/milestones-2026-08.md`（本節只留最近一批）。

- ✅ 2026-08-15 修 `tests/run.sh:4199` 的 stat 跨平台順序(GNU `-c` 先於 BSD `-f`)。
  Linux 上該條恆紅:GNU 的 `stat -f` 遇無效格式雖回 rc=1、卻已把 filesystem 統計吐進 stdout,
  與 fallback 的輸出相連。**與 `:3758` 註解描述的「假成功」機制不同**,已在註解分清。
  同批完成 hook 的全機隊散佈(14 台)＋跨平台實測(Linux／Darwin 皆正確擋下)。
- ✅ 2026-08-14 治理落地兩件(計畫的①經 G10 否決,見死路節):`ship-state.sh` 加 always-on 量體
  訊號(純資訊、三態、worktree 可辨識);`.githooks/dispatcher` 全域 hook 代理＋default-branch
  guard,經 `git/config` 一行宣告式散佈。+26 條迴歸(第 24 節 19 條),含 fail-open、chain exit
  code、三個刻意 false negative 的邊界固定。正反兩向突變測試皆命中。1022 PASS。
- ✅ 2026-08-14 dossier 治理一整批(起點:使用者反映「一直在處理 dossier flag、很花時間」)。
  **工具**:`ship-state.sh` 條目 flag 兩修(邊界止於非續行區塊、補建議目標 680)＋全檔 flag 帶
  收斂順序＋歸檔孤兒反向守門(krepo 13.0s→2.5s);+13 條迴歸。**存量**:死路節分層外移
  `docs/dead-ends.md`(5123→3006)、已知缺口六條歸位到決策;全檔 24318→22843,零遺失以 token
  級檢查確認(103/103)。**規範**:兩組成對實驗**都判零差異而不採用**——Scenario 17(缺口 vs 決策
  判準)與 G9(內容路由決策樹);後者副產物測出「已知缺口」節名歧義。外部 findings 七條落地兩條,
  其餘五條的判定見決策節同日三條。996 PASS。

## 已知缺口

- **codex reviewer 跑得動測試、但跑不完**(2026-08-13 C1 實測):PR #94 的 profile 解決了「建不了 cache」
  (events 實查真跑了三次),但 sandbox 內 `PASS=956` vs 主機 `983`,伴隨 `cloned an empty repository`
  ——建 git fixture 在 `:read-only`+tmpdir-write 下仍受限。**「能啟動」≠「跑得完」**;那個中途計數正是同輪
  假 `verification: executed` 的來源(被讀成「全部通過」,漏掉 `TEST_RC=1`)。調 profile 前先看這條。
- **eval 的受測 subagent 拿不到 deferred tools,部分契約在沙盒中無法構造**:2026-08-07 實測——
  主 session 的 `CronList`／`TaskOutput` 正常,探針 subagent(`Tools: *`)對同一批 `select:` 一律得
  `No matching deferred tools found`。凡「該工具查得成」才成立的情境因此做不出來,ready4quit
  **Q4c**(`RECALLED + ✓`,需最低證據等級剛好是 RECALLED)至今無 GREEN 證據。symlink 前置已解除,
  但手動驗證二度失敗,並暴露原程序自身兩個錯(`~/.dotfiles` 當 pwd 讓 Git 衛生恆 ⚠;「全新且安靜的
  session」自相矛盾——無對話歷史時回憶型面向只會落 PARTIAL)。**v3 程序見
  `claude/skills/ready4quit/evals.md`,別再照舊程序跑。**
- **同型處置的 self-report 擋得住靜默跳過,擋不住填了但敷衍**(2026-08-11 落地兩軸拆分＋五個終態
  報告必填「同型處置紀錄」表之後的殘留面):**表格內容無法機檢**,`tests/run.sh` 第 1f 節只驗
  **結構**(模板覆蓋率、表頭形狀、引用行不複述軸名等,逐項以該節為準)。R5 終止路徑為何不補
  behavior eval 見關鍵決策同日條目。

- **Mac 上 brewup 會被 codex cask 掛死(Gatekeeper)**:2026-08-07 第三次發作。復原已有入口
  `brewfix`(唯讀診斷,`--fix` 才動手);機制、鑑別法、三條走不通的預防路徑全文見
  `claude/known-hazards.md`「cask 升版卡死」,**此處不重述**。**仍未解**:確切觸發條件未知且事後無法重現
  (同版本內容換路徑執行正常),要重現只能等該 cask 真正出新版。**未決**:預先設 xattr `0x0040`
  技術上可行,但前提已被負面結果動搖、代價卻是確定的(拿不到 tarball 簽章身分)——
  **用確定的代價換不確定的效果,暫不做**,優先靠已實證的復原路徑。

- **kernel 的「fallback conventions 由 repo 勝出」對 host repo 實務上不可達**(2026-08-10 G6 樓層
  重跑的新 RED):Sonnet 兩次都用 Conventional Commits,而該 repo 明文拒絕它——**根因不是違抗,是
  `AGENTS.md`/`CONTRIBUTING.md` 的 tool_use 皆為 0,它沒看過那條規則**。safety floor 是被載入的
  文字所以穩;deference 卻要求一個「先去讀檔」的動作,沒有東西保證它發生(與 G1b 同一失效面)。
  **觸發:真的要在別人的 repo 常態工作時**——候選解三條與代價見
  `claude/evals/contract-evals.md`「這條 RED 的根因不是違抗，是那個檔從頭到尾沒被打開」。
- **`codex/AGENTS.md` 與 root `AGENTS.md` 同名不同角色**(來源檔 vs repo-resident 契約):改
  `codex/**` 時兩份都被當 guidance 餵進 reviewer——**重複但無害,改名已 DROP、此實害就這樣接受**
  (理由見 `docs/archive/decisions-2026-08.md`)。
- 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,
  改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+credentials 明文散於三台。
- **`agy`(Antigravity CLI)只手動裝在 macs,未寫進 `setup-mac-env.sh`**:2026-08-07 因 gemini-cli
  已於 2026-06-18 停服而改裝其後繼(`brew install --cask antigravity-cli`,binary 名 `agy`)。
  後果:新機器跑 setup 不會裝、macmini/m4mini 目前也沒有。該 cask 標 `auto_updates`,故 `brewup`
  不會升它(除非 `--greedy`)。**它沒有 `generate_completions_from_executable`,不會踩 codex 那個
  Gatekeeper 坑**,但首次執行仍會走核可流程——要裝就在該機 console 前跑一次。
- **兩部個人 MacBook 不在 `inventory.conf`**(公司／家中,經 VPN ssh 進 macs),`dotsync`／`allup`
  涵蓋不到——兩機已各自補齊,**留下的是結構性事實**:要跟上得在該機本地跑 `brewup`,不會有人幫
  它們 pull,而**漏跑是無聲的**(skill／地雷／模板停在舊版)。**加進 inventory 這條路今天不可用**:
  2026-08-09 查 tailnet 沒有它們,且常離線的筆電會讓每次 dotsync 都帶 ❌、稀釋訊號。
  **待確認是刻意(終端設備不入清單)還是缺口。**


## 移交準備度

(個人 infra,暫無移交打算——平時留空)
