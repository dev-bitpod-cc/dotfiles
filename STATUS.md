<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-07)

---

## 進行中

### todo:GitHub 多身分收斂——讓標準 URL 直接可用(2026-08-06 記錄,未開工)

**Goal**:標準 URL(`git@github.com:`)在三台機器上都直接可用,`insteadOf` 整層移除
(它是為了讓 krepo 拉依賴而暫設的改寫層,不是終態)。

**spec 定稿**:`docs/plans/2026-08-06-github-identity-consolidation.md`——現況盤點(三台機器的
repo 分佈)、`ssh/config` 方案(含 `IdentitiesOnly yes` 為何一行都不能少)、AC 1–5、遷移順序
與回退路徑,全都在那裡。

**下一步**:先在**一台**機器驗身分(`ssh -T git@github.com` 應認到 jjshen-eland、
`ssh -T git@github-me` 應認到 dev-bitpod-cc),**過了才改 remote、才散佈**。
⚠️ **回退路徑本身會被這個變更弄壞**——遠端機器拉 dotfiles 走的正是 GitHub SSH,認證改壞又
散佈出去就拉不到修正,只能 `ssh <host>`(內網 CA cert,不受影響)進去手改或臨時加回 `insteadOf`。
**別一次 `dotsync` 全部,別在深夜動。**

---

## 關鍵決策(附理由)

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。**歸檔判準**：已固化且不再影響現行方向 → 歸檔；仍在生效的一律不歸檔（死路＝防重工、技術債＝未解決，移出 always-on 即失效）。超標時**優先歸檔、不要為幾百 bytes 去壓無關舊條目**——那個動作重複幾次本身就是訊號。

- **2026-08-07 同一風險的緩解手段可以不同,依該路徑「網路成本是否已付」決定**:
  `squash-merged-branches` 拿本地 tracking ref 當遠端證據(遠端已刪、本地未 prune → 虛報;
  第三方指出、已重現;誤刪由清理端的 ls-remote 重驗擋住,傷害在訊號可信度)。否決建議的
  `fetch --prune`／`remote prune --dry-run`——一樣連遠端卻更重,且 fetch 改本地 ref、違反檔頭
  「不 fetch」;改用單次 `ls-remote --heads` 交集,**該函式本來就要打 `gh pr list`、網路成本
  已付**。`detect_stale_branches` 同形狀但**刻意不改**(純本地路徑,引入網路會讓「正常路徑
  不碰網路」失守)。**判準:風險相同不代表修法該相同——看那條路徑既有的成本結構。**
- **2026-08-07 memory 的 consent 邊界改以「既有內容有沒有被抹掉」判定,不看「檔案存不存在」**:
  純附加＝additive 可直接寫,只有會抹掉既有內容才要 consent——逼一輪往返只是把 additive 出口
  切成「新增免問/更新要問」兩半,而兩者可逆性相同。**拆掉守衛就得補上它接住的東西**:讓出的
  邊界由新增 eval Q5b 接手(以「使用者推翻既有偏好、要求刪掉」逼出破壞性改動),首跑 PASS。
  附帶判準:**規格本身沒定義時,受測行為判「不計數」而非 RED**——判它違規等於用事後 oracle
  追溯定義 skill 沒說過的事。全紀錄見 `claude/skills/ready4quit/evals.md`。
- **2026-08-07 fixture 撞名＝「兩條 branch 各自全綠、合流才紅」的測試虛設第四種形狀**:本批在
  `tests/run.sh` 第 8 節用 `$TMP/sq-work`,main 同期在第 9 節獨立用了同一個名字;兩節共用 `$TMP`,
  後建的 `git init` 落在既有 repo 上(re-init + `remote origin already exists`),fixture 靜默
  不成立、6 條斷言假紅。**兩邊單獨跑都全綠**,與「只有乾淨 clone 看得見」的誤收同型,diff review
  抓不到。判準兩層:共用 `$TMP` 的 fixture **一律加節前綴**;**rebase/合流後必須重跑全測試**
  ——這類缺陷只在合流那一刻現形,不重跑就會帶著假綠送出。
- **2026-08-07 GitHub 多身分收斂的 spec 定稿移入 `docs/plans/`,「進行中」只留指標**(同日先拍板
  留在 dossier、後改此)。理由:spec 完整但**未開工**,卻長期佔 always-on 內容約 24%(109 行),
  把 dossier 一路推過 300 行硬門檻——每次 ship 都要為幾行去蒸餾無關條目,那個動作重複本身就是
  「該歸檔而非再壓」的訊號。`references/dossier.md` 的檔案分工表本來就指定 `docs/plans/*.md`
  存放 spec 定稿(寫後不改),STATUS.md 留就地演化的進度與下一步。**指標須帶回退風險警語**——
  那是行動前最需要看到的一句,不能只留在定稿裡。
- **2026-08-07 引數判定改「形狀規則」,不用優先序規則**:起因是「`/project log pr` 會停在開 PR 嗎」
  ——查下來 `pr` 會被判成 module 過濾詞;而 `merge` 更早就有雙重身分(引數位當 module、同時被 Step 4
  當說法),**當下我靜默挑了說法那個讀法往下做**(碰巧對,過程不對)。改法不是加「先查說法表再
  resolve」,而是依形狀分類:`--` 開頭＝flag、裸字命中說法表＝說法、路徑形式＝repo/module。
  **判準:形狀規則不需要記「誰先誰後」;優先序規則要記、會漂。**
- **2026-08-07 module 過濾收緊為只接受路徑形式**:舊規則「`resolve: UNKNOWN` 且 basename 不命中
  → 該 token 也當 module」會在**打錯字時靜默縮小 Step 2 的掃描範圍**——掃不到的文檔不會報錯,
  只是沒被同步,是安靜的失效。改為停下問。**判準:會讓覆蓋範圍變小的預設,必須是明說的、不能是
  fallback。**
- **2026-08-07 `--pr` 成為獨立終點(開完 PR 即止、零提問)**:補上原本的不對稱——merge 與「只推
  branch」都有零提問說法,「開 PR 然後停」卻只能靠回答選單。flag 與裸說法**共用同一張表**、不得
  各自演化;prose 路徑刻意沒有 flag 形式(說法可以三輪之後才補一句,flag 只存在於引數裡)。

- **2026-08-07 squash-merge 殘留改比對 merged PR,判準是 `headRefOid` 相等而非同名**:
  `branch --merged` 判祖先關係,squash-merge 在 default 上產生全新 commit、無祖先鏈,**結構上
  看不到**;而本 repo 家規正是 squash-merge,等於該訊號對主要情境無效(舊 fixture 用「branch 不加
  commit」才會綠——測試綠、功能無效)。**headRefOid 必須等於本地 tip** 才算數:不符代表同名 branch
  事後又有新工作、那些 commit 不在 default 上,列進清單就是誘導刪掉唯一副本 → 只印診斷。fork 同理
  不採信。**達查詢上限一律標 `partial`、絕不印 `none`**——截斷處靜默等於謊報「掃完了、沒有」。
- **2026-08-07 破壞性刪除下沉成腳本,expected SHA 綁「執行當下」而非偵測當下**:偵測與刪除之間有
  TOCTOU 窗口(另一 session/主機可能又 commit),照抄的 `-D` 對此無感,而 branch 是那些 commit 的
  唯一 ref。訊號產生時驗過那次是**舊資訊**。remote 另加 `ls-remote` 重驗 + lease 雙重比對。
  **副作用判準**:lease 是第二道防線,拿掉前置比對它照樣會擋 → 前置比對必須**另立斷言**,
  否則整段可被刪光而測試全綠(本批實地驗到)。
- **2026-08-07 Step 4 從「逐批出題」改「說法即授權」,拆掉的守衛另補一道**:使用者實地回報「說了
  ship 還被問四次」是摩擦。改為送出說法(merge／bypass merge／只推 branch…)出現在本輪訊息裡就
  印完摘要做到底、零提問;沒說法才問一題。**但這拆掉的是「push 前你一定會看到摘要並有機會攔」**,
  故補上 `review-terminal:`——上一場審查若是 R5 終止收場(且 ancestry 涵蓋當前 HEAD)一律 STOP,
  說法覆蓋不了。**判準:移除一道 gate 時,先問它順帶接住了什麼,那些東西要各自有主。**
- **2026-08-07 merge 預設改「保留語意 commit」,推翻昨天「≥2 顆就出選項問」**:昨天那條的理由是
  「壓不壓沒有預設值,不能猜」;使用者給了預設(不同目的的 commit 預設保留)之後,歧義本身消失,
  詢問的理由跟著消失。**那條規則從未實測就被推翻**,故無實測結論被推翻。review 痕跡則相反——
  **壓得掉的一律壓、不問**,它不是偏好而是不變式;唯一的自由度是「壓不壓得掉」(buried 壓不掉)。
- **2026-08-07 skill-authoring 變更走一次診斷,切的是 autofix loop、不是 correctness bar**:
  可觀察的 RED 只有一個——同一批 skill 變更被對抗式重審失控(12 小時、兩場完整 deep-review
  加三輪 codex 未收斂),且第一場 R5 終止後又開新一場、外層重置了輪次上限。**初稿寫成
  「prose findings 一律降建議」是錯的**:當天四條高風險 finding 全在 `.md` 裡、全屬「照做會
  錯」。**判準:診斷本身有價值、失控的是修復循環,要切就切循環。**
- **2026-08-07 該 gate 的兩處設計由第三方審查打掉**:①「prose 佔多數」分流會讓
  `src/*.py + README.md` 這種正常 PR 也關掉 autofix(無 RED)→ 改按**工作類型**判定,副檔名
  不是工作類型的代理;② escape hatch 若寫成「使用者明說 autofix 就照跑」會被合理化成「已經
  明說了」→ 改為獨立 token `force-skill-loop`,且**不接受從自然語言推斷等價詞**。
- **2026-08-07 R5 終止改顯式 terminal state,因為 `cycle` 不是可觀察條件**:`cycle` 只表示
  anchor 未 clear,成因混雜(R5 終止／中途停止／crash／刻意稍後續跑),據此擋新 cycle 會誤傷
  後三者。改為 `terminate --reason r5-blocking` 寫入 anchor,`record` **在解析與寫檔之前**
  檢查它。**只做 `r5-blocking` 一種**:`codex-c3` 會立刻引入不同的 resume 語意(anchor 已有
  `codex_round=3`),依 Iron Law 等真 RED 再設計。`resume` 刻意**不塞進 `record`**——record 的
  既有契約是「重新解析、無條件覆寫」,與「保留 base」語意相反。
- **2026-08-07 eval 寫完必須實跑,四條裡三條首次執行就見紅**:一條是 SKILL.md 措辭誘發
  oracle leak(寫了 `F10` 這個只存在於 `evals.md` 的情境編號,受測 agent 直接把它抄進
  reviewer prompt)、另兩條是 fixture 自身不自洽。**判準:eval 是 oracle,未跑過的 eval 不是
  證據、是意圖。** 與上面三種「假綠」形狀同源,只是發生在行為層而非腳本層。

## 死路(試過但放棄——防重工)

- **mc(Midnight Commander)當遠端檔案管理器**:評估後放棄,理由是**協定層而非偏好**——
  mc 的 `sftp://` VFS 走內建 libssh2,**不支援 OpenSSH 使用者憑證**,而內網主機一律
  cert 認證(`id_autogen-cert.pub`,principal `jjshen`),等於主要路徑不通;可用的 `fish://`
  雖外呼真 ssh 能吃 cert,但每個操作起一次遠端 shell、且 macOS 還要處理 F1–F10 被
  Mission Control 攔截與 subshell 不繼承 cwd。同樣需求 `lftp` 的 sftp backend 預設就外呼
  `ssh -a -x`(已實測 `set -a` 確認),cert 與 `~/.ssh/config` alias 原生生效,無這些摩擦。
  **若日後想重評 mc,先確認 libssh2 是否已支援 OpenSSH cert,否則結論不變。**

- **手動把 worktree 的 SKILL.md 複製到主 checkout,以繞過 `~/.claude/skills` symlink**:想在合併前
  跑「需要 skill 真的被載入」的驗證時(如 ready4quit Q4c 要開新 session 觸發 `/ready4quit`)會很想
  這麼做。放棄理由:主 checkout 有其他 writer;`brewup` 會在 pull 前丟棄未提交改動,那份複製隨時
  被吃掉;最要命的是**「測的到底是哪一版」變得不可考**——與這些 skill 自己在防的「證據對不上
  結論」完全同型。**正解是先合併、主 checkout pull 之後再驗。**
- **「/project log 包裝/並存 /uap」**:disable-model-invocation 下無法鏈式呼叫,只能複製
  pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,直接取代。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:實證 general-rag-cs 的已消費
  STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] R4 non-blocking 建議未修:新增 prose 的中文半形標點與既有全形混排;Transfer 模式 commit
  紀律歸屬未明示;evals/README 路徑基準寫法;handoff evals H4 排序
- [ ] dossier 訊號 R5 non-blocking 未修(2026-07-29,皆非 blocking、無失敗案例):sections 百分比
  系統性略低於 100%(標題行不計);「唯一的例外」在 SKILL 與 S12 說法不一致;最長行 flag 缺「何時
  處置」;S12 fixture 規格內部不一致;條目作用域用子字串比對而非端錨定(「## 進行中(已完成 M1)」會誤掃)
- [ ] **「tests/stub 有覆蓋、實戰未驗」一組**(遇到對應情境時順手確認即可,不必專程做):
  SessionStart hook 落後提醒(真實落後的 clone);autocodex exec 的 resume 分支(exit 4 救援階梯,
  三輪實跑皆一次成功、只有 stub 覆蓋,F15(b) 待真實空報告);review-anchor 的 stale STOP 與
  codex-next 冪等(F16 b/c,待 autofix 迭代中真的 rebase/重試);repo-review 新契約(F16–F18 規格
  覆蓋,待多輪 autofix 確認弱模型不會退回每輪帶 `--autofix`)
- [x] hook matcher 僅 `startup`——2026-08-07 已擴為 `startup|clear|compact|resume`,tests 第 16 節覆蓋
- [x] 測試節那行待補 git-hygiene 的新教訓——2026-08-07 已補。**目標檔是 repo 根的 `CLAUDE.md`
  (第 133 行、單行 5.6KB),不是原記的 `claude/CLAUDE.md`**(後者的測試節講的是「何時該寫測試」)。
  順帶補上該行從未索引到的 **SessionStart hook 守門**——`git-hygiene` 先前也完全沒有細節,
  等於這兩塊的覆蓋範圍讀不出來
- [ ] Scenario 11 的「merge 但無 PR」分支只在 SKILL body 一行指標帶到 ship-paths,GREEN 實測中
  弱模型未展開讀——非違規故未補;重現才加明示(Iron Law)
- [ ] pressure-tests S8/S9/S12 沙盒未納入 `claude/evals/setup-sandboxes.sh`;S10(transfer
  credentials)與 S12(dossier 三 flag 蒸餾紀律)連首輪實測都還沒跑
- [ ] `claude/evals/setup-sandboxes.sh` 不在 shellcheck / `bash -n` / 全形標點 gate 範圍(第 1、1b、2 節
  只涵蓋 `scripts/`、`claude/scripts/`、`*/skills/*/scripts/`、functions/setup/tests)。該檔全靠 heredoc
  灌 fixture,正是 unquoted heredoc 反引號地雷的高風險區(機制見 `claude/CLAUDE.md` 已知地雷);
  沙盒腳本繼續長大就值得納入 gate
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
> 2026-08-05／08-06 各批已歸檔至 `docs/archive/milestones-2026-08.md`。

- ✅ 2026-08-07 deep-review skill-authoring one-shot gate + R5 terminal state（#51，665 PASS）
- ✅ 2026-08-07 ship 說法語法：說法即授權、merge 預設保留、`review-terminal` STOP、merge 受阻分流（#52，672 PASS）
- ✅ 2026-08-07 squash-merge 殘留偵測 + `cleanup-stale-branch.sh` 安全清除（#53，699 PASS）
- ✅ 2026-08-07 Scenario 15 補測：`BLOCKED` 不得自動 `--admin`，正反兩向 PASS（#54）
- ✅ 2026-08-07 ready4quit 強化 + 四輪第三方審查修復：證據語彙拆兩軸（強度 × 殘留）、Step 2 memory/dossier 雙出口、背景任務證據來源改 `tasks/` 且 liveness 不得由 `.output` 推斷、`git-hygiene.sh` 補遠端事實與多 remote 一致性、hook 增報 worktree 雙寫入者；**eval 從零 GREEN 到 8 條 PASS**，其中 Q4a/Q5 是 eval 自己抓出、四輪第三方審查都沒看到的規格缺口（#59，754 PASS；Q4c 未驗見「已知缺口」）
- ✅ 2026-08-07 `brewup`/`sysup` 從 rc alias 抽成 `scripts/*.sh`（雙平台單一來源，消除兩份複本的漂移風險）+ 新增 `brewfix` 復原入口；`all-up.sh` 改直接呼叫腳本、去掉 `bash -ic`（`no job control` 雜訊隨之消失）；`ensure-rc-source.sh` 增舊 alias 清理（**刪行而非 unalias**——14 台巡檢實測 rc 內 alias 與 source 的相對順序因機器而異，macmini 反向，`unalias` 會多數生效少數靜默失效）（787 PASS）

## 已知缺口

- **eval 的受測 subagent 拿不到 deferred tools,部分契約在沙盒中無法構造**:2026-08-07 實測——
  主 session 呼叫 `CronList` 得 `No scheduled jobs.`、`TaskOutput` schema 也載入;探針 subagent
  (`Tools: *`)對 `select:CronList,TaskOutput,TaskList` 一律得 `No matching deferred tools found`。
  故凡「該工具查得成」才成立的情境做不出來——ready4quit **Q4c**(`RECALLED + ✓` 的收斂措辭,需
  最低證據等級剛好是 RECALLED)因此無 GREEN 證據。symlink 前置已於 2026-08-07 合併後解除,但
  **手動驗證第二次嘗試仍無效**,且暴露原程序自身兩個錯:①`~/.dotfiles` 不能當 pwd(harness 持續
  往 `claude/settings.json` 寫 drift,Git 衛生恆為 ⚠);②**「全新且安靜的 session」自相矛盾**——
  沒有對話歷史時回憶型面向落 `PARTIAL` 而非 `RECALLED`,「安靜」給 ✓、「全新」卻毀掉 RECALLED。
  另有未證實的第三道障礙(單次觀察):`tasks/` 的孤兒條目讓背景面向被迫 PARTIAL,若為常態則本條
  結構性不可達。**v3 程序**(改用沙盒 repo、開場先做幾件唯讀的事製造可回憶歷史、跑前先 `ls`
  確認 `tasks/` 為空)見 `claude/skills/ready4quit/evals.md`——**別再照舊程序跑**。
- **祖先判定那條路徑的 `cleanup-cmd` remote 刪除仍是裸 `push --delete`**(無 lease、無執行當下
  重驗)。local 側的 `-d` 由 git 自己把關(未併入即拒),remote 側沒有等價保護——偵測後有人推過
  就會刪掉未併入的 commit,與本批修掉的 TOCTOU 同型。修法現成:改發 `cleanup-stale-branch.sh
  <repo> remote <branch> <sha>`。**刻意未收進本批**——會動到既有斷言的輸出形狀,且無實地失敗案例。

- **說法表把授權綁在字面 token,但「用 --admin」語意上更明確卻不在表上**(現行＝不接受,會要求
  使用者改說「bypass merge」)。設計 S15 eval 時撞到:原擬施壓句「加個 --admin 就過了」比 bypass
  merge 還明確,等於把授權塞進施壓句、正確答案自己變歧義。**張力**:收進表等於承認自然語言等價詞,
  而「不自行擴充等價詞」正是它擋 rationalization 的機制。無實地案例前不動。

- **buried 的 review 痕跡壓不掉,不變式只做到「壓得掉的一律壓」**:夾在語意 commit 中間時
  `reset --soft` 碰不到。**做得到但沒做**——`rebase -i` 配 `GIT_SEQUENCE_EDITOR` 是完全非互動的,
  把每顆 buried 標 `fixup` 折進前一顆語意 commit 即可(前一顆本就是它父節點,**衝突為零是結構保證**)。
  **代價才是沒做的理由**:語意 commit 的 hash 與內容都會變、「squash 絕不動語意 commit」從結構保證
  退成測試保證、多一條 rebase 回滾路徑、branch 首顆是 buried 時無目標;而實測多為 none/top-contiguous。

- **`ship-state.sh` 不檢查 feature branch 對「自己的 remote tracking ref」是否分岔**(只比對
  default)。分岔時 push 會被拒,prose 端有防線(`ship-paths.md` squash 步驟 0 的 fetch +
  `--is-ancestor`)但**無訊號**——2026-08-07 跑 eval 時由受測 agent 自行 `branch -vv` 才發現。
  補法＝一行 ancestry 檢查,形狀同 `review-terminal`;暫不補,無實地失敗案例。

- **證據標註 = backlog,無 RED 不進 brief**:待觀察失效為「finding 建立在未查證推論、fixer 誤信」,
  至今零觀察;日後出現再加標註版(零風險、可測),而非授權外部存取。全紀錄見 deep-review `evals.md`。

- **deep-review anchor 跨批次會 stale,`squash-cmd` 因而指向錯誤目標**:anchor 只在 autofix 的
  `record` 寫入,走「codex 第三方審查」觸發詞路徑時不 record → 讀到**上一批**的 anchor(2026-08-05
  實遇:本批 3 顆卻給出會壓掉 5 顆的 reset 目標)。2026-08-06 squash 改 subject 掃描後風險大幅縮小
  (會停在第一顆語意 commit),殘餘只剩「上一批的 review fix commit 被收進本批 squash」。解法已知:
  `squash-cmd` 偵測 anchor 非當前 branch 祖先時改判 STOP——**`codex-next` 已有這道檢查**,剩移植。

- **「規則的對稱面／使用點」與「同型掃描」都只有文字原則、無產出物**(兩者同型,合併記):
  - *Step 2 對「規則只寫了一半」無偵測*:2026-08-05 抓到 `add -A` 例外的使用點缺口純屬**偶然**
    (`CLAUDE.md` 的例外文字剛好點名 `deep-review/SKILL.md`)。同 session 反證:#43 走過同一個
    Step 2,F2/F3 兩條 blocking 照樣漏出,由第三方審查才抓到。
  - *deep-review 的同型掃描*:對「測試」有機械化 gate(`verify-tests.sh` exit code 契約),對
    同型掃描只有 brief/SKILL 的文字要求。2026-08-05 krepo 實戰回饋:連跑四輪修復時最易被跳過
    的正是這類原則性敘述,且該次漏的就是它。
  **共同結論:不補文字原則**——文字是最易被跳過的那層。要做就做**訊號化/checklist 化**
  (如 `ship-state.sh` 偵測變更集含 `CLAUDE.md`／`AGENTS.md`／`SKILL.md` 時印對稱面候選,不判語意,
  形狀同 `dossier-flag`;或要求 fixer 每輪寫出「本輪抽象出的規則 + `rg` 命中數」)。做不成
  exit-code gate——規則是語意抽象出來的,機器不知道要 grep 什麼。現有防線只有第三方審查。

- **Mac 上 brewup 會被 codex cask 掛死(Gatekeeper 首次執行核可)**:2026-08-07 第三次發作,機制已
  完整證實——**exec 者是 brew 自己**:codex cask 帶 `generate_completions_from_executable`,其
  `install_phase` 對 **bash/zsh/fish 各 exec 一次**剛解壓、仍帶 quarantine 的 271MB binary 來產生
  completion,首次 exec 即觸發核可對話框。看似卡在 `Linking Binary` 是因為那是**前一個** artifact
  的訊息;brew 的 `rescue => e` 只攔例外、攔不住 hang,故 brew 自己也不會跳過。無官方開關可停用該
  artifact(sandbox 路徑一樣 exec,只多 `deny_all_network`)。
  **卡住有兩條路徑**:(a) 對話框在等人按——8/7 經 SSH 跑 allup 時實地確認(Jump Desktop 連進 console
  才看到,SSH 結構上看不到 GUI);(b) **無可見對話框也會卡**——在本機 console 開 terminal 跑 brewup
  也遇過卡在 `Linking Binary`、對彈窗無印象。故 **ssh 不是必要條件、「去 console 按對話框」不是可靠
  處置**;(b) 成因未定(沒搶到焦點/在別的 Space,或 271MB 首次驗證本身卡住),勿當定論。
  解法:**`brewfix`**(2026-08-07 新增,`scripts/brewfix.sh`;預設唯讀診斷,`--fix` 才動手)。
  等價手動序列:`sudo killall syspolicyd` + 清 `Caskroom/codex/<old>.upgrading`(`brew cleanup` 只清
  cache tar.gz、不碰它),實證有效且比 reinstall 快——`brew reinstall` 路徑不變、多半無效。
  鑑別法(`sample` 卡 `_dyld_start`、`lsof` 零 dylib)見 `claude/CLAUDE.md`「已知地雷」。
  **確切觸發條件仍未知,且事後無法重現**:8/7 把同一份 binary 複製到全新路徑、SSH 下帶 quarantine
  立即執行 → 3 秒正常完成。逐一排除 SSH session／首次評估／quarantine 無 0x0040／檔案大小 271MB／
  notarization 與簽章差異(同機 agy 162MB 各項相同卻從不卡)。推測 Gatekeeper 的**成功評估以 cdhash
  快取、卡死的 pending 記錄才以路徑為 key**,故同版本內容事後永遠重現不了,要重現只能等真正出新版。
  **預防手段三條都不通**(勿重走):① 事後手動先跑一次——brew 在你之前就 exec 了;② `--no-quarantine`
  ——Homebrew 6.x **已移除該旗標**;③ Homebrew 內建核可繼承——`cask/upgrade.rb` 兩處都是
  `grep(Artifact::App)`,只服務 `.app`,binary cask 拿不到,`USER_APPROVED_FLAG` 永遠不會被設。
  **未決**:xattr 預先設 0x0040(fetch 與 upgrade 之間有時間窗,propagate 只動 bit 8 會把核可位帶進
  staged)技術上可行,但**前提是「首次核可流程確為卡住主因」而該前提已被上述負面結果動搖**,且代價確定
  (拿不到 tarball 的簽章身分、無法做 Homebrew 對 App 才做的 signer 比對)。用確定的代價換不確定的效果
  ——暫不做。復原路徑已實證,優先靠它。

- 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,
  改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+credentials 明文散於三台。

## 移交準備度

(個人 infra,暫無移交打算——平時留空)
