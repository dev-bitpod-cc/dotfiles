<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec;ship 時同步;移交前補齊完整度。維護者可能另有工具輔助,
        但**規範本身在此、不在工具**——沒有那些工具也照樣維護得下去。
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-13)

---

## 進行中

(無進行中工作項——契約層、dossier 可攜性、測試契約拆檔三批已收斂,見里程碑。凍結計畫:
`docs/plans/2026-08-09-repo-contract-extraction.md`、`docs/plans/2026-08-10-dossier-portability.md`)

**剩餘工作全部帶觸發條件、皆不在進行中**:①**Phase 3 改名 DROP**——Codex 進生產線再議;
②**Phase 4 installer DEFER**——觸發是「出現第一個**自己有權安裝契約**的移交 repo」,**不是**
「外部 repo」(那正是不得 apply 的對象);③**G5 DEFER**——隨 generated-docs 工具一起;
④**transfer 的 portability 步驟 DEFER**——真實移交當下依實況寫,之後回灌模板
(n=1 的一次性工作寫進 skill,成本高於手做,且自動化「剝除」比正解「具名保留」差)。

---

## 關鍵決策(附理由)

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。**歸檔判準**：已固化且不再影響現行方向 → 歸檔；仍在生效的一律不歸檔（死路＝防重工、技術債＝未解決，移出 always-on 即失效）。超標時**優先歸檔、不要為幾百 bytes 去壓無關舊條目**——那個動作重複幾次本身就是訊號。

- **2026-08-13 push 授權改「先依有無 shipping workflow 分流」,並以 G8 eval 釘住**。根因:kernel 要
  commit 後一律停、`/project` 說法表卻認明說即授權,而 kernel 是四份複本,不對稱直接落到 Codex。
  **改了三版才對**:初版(kernel 自列「ship 算授權」)方向相反、不對稱只換位置;第二版在 **G8 r2
  實測 RED**——只帶 kernel 的兩臂**都 push 了**,「給你 ship」那臂逐字寫下 `I'll push it and open
  a PR`,證明「以授權表為準」的 fallback 仍是語意判斷。**定案(r4 GREEN)**:有 workflow → 只認其
  授權表;無 → 指名動作的指令、或剛提出的確認被肯定答覆。default branch 與 merge 未放寬。
- **2026-08-13 G8 附帶發現:kernel 的 push 條在 Claude 端幾乎不生效**。帶完整 `claude/CLAUDE.md`
  的兩臂**零 tool_use**——**技能載入指標**(「ship」「推上去」→ 建議使用者跑 `/project`)在 kernel
  之前就攔下路由掉了。那是正確行為,但意味著這條規則真正的作用域是 **Codex 端與任何沒有
  `/project` 的環境**;要驗它就得用只帶 kernel 的沙盒(G8 的 c/d 臂),否則測到的是空條件。
- **2026-08-13 不建 Codex 版 project skill,等真實 RED**。既然 Codex 已可 ship,直覺下一步是把
  Claude 的 `project` workflow 複製一份給它;不做的理由是 `codex/AGENTS.md` 改後已指向
  **repo 既有的 shipping skill**,複製等於製造第二份會漂移的 pressure-tested 邏輯(同
  `/project log 包裝 /uap` 那條死路的形狀)。**觸發:Codex 端出現真的走不動的情境**——屆時再做,
  且優先重用同一套 mutation 腳本而非另寫。
- **2026-08-11 拆檔時反向指標依「指向規則 vs 指向細節」分流,不是一律改**。11 處指向
  `claude/CLAUDE.md`「已知地雷」的引用:指向**規則本身**的 4 處不動(`ensure-ssh-config.sh`、
  `evals/README.md`、`tests/run.sh`、`ship-state.sh`——它們要的就是 always-on 那句),指向
  **機制/鑑別法**的 3 處改指新檔,archive 5 處 write-once 不動。**xref-gate 抓不到這類斷裂**
  ——節名還在、內容搬走了,gate 照樣綠;只能人工分流。改完以**突變測試**確認 gate 真的在驗新指標
  (把節名改錯→命中,還原→乾淨),否則「全綠」可能只是掃描器沒匹配到。
- **2026-08-11 `AGENTS.md` 與 `CLAUDE.md` 對「何時必跑測試」的重複刻意保留**,並把
  exactly-one-place 的例外條款從「kernel replicas」一般化為「**必須 always-on 且讀者載入不同檔**」。
  拆檔時本想一併消除該重複,查下去發現它是**結構性的**:Codex 只讀 `AGENTS.md`、Claude 只自動載入
  `CLAUDE.md`,指標對兩者其中之一必然落空(同 kernel replica 的成因)。**不新增第二個 managed block**
  ——那三行短到漂移不出實質差異,gate 的建置成本高於收益。
- **2026-08-11 `docs/testing-contract.md` 不進 portable 權威矩陣**,指標只寫在 `AGENTS.md`
  「Repo specifics」。portable block 是要**整段裝到其他 repo** 的,加一列等於把本 repo 的檔案結構
  強加給別人。(順帶否決了「按 AGENTS/CLAUDE 拆分權威矩陣那一列」的提案:多數 repo 只有一份契約檔,
  寫死分工在只有 `CLAUDE.md` 的 repo 整條無法適用;現行「最近者勝」對 N 份都成立。)
- **2026-08-11 驗證「重排後內容零遺失」只有 token 級檢查有效**。滑動窗口(剝非中文後比對)與
  語意片段(按標點切)兩種都被重排大量假陽性淹沒——前者把原本被英文分隔的中文黏成原文不存在的串
  (**與 xref-gate 檔頭警告的「整檔併成一串」同源,只是反過來造成假遺失**),後者對「含→涵蓋」
  「逗號→分號」這類改寫全數判缺。有效的是抽 `code` 識別字與日期逐一比對(99/99、3/3)。
  下次做搬遷驗證直接用 token 級,別再繞前兩種。

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
- **依外部提案的診斷改 `handoff` 的 W1(anchor 集合判準)**:2026-08-12 收到一份提案,診斷
  「W1 的『涉及』被讀成『我改過的 repo』」是實地事故(交接檔漏 anchor 擋著下一步的 repo)的根因,
  並提議在寫入端加判準。**跑了三輪 eval(H11 兩輪 + 最忠實的 H11b 變體)全部 GREEN 而放棄**——
  H11b 裡 Sonnet 只 anchor「唯一會解封下一步的外部依賴」、主動排除已交割的 repo,那正是提案想
  寫進 W1 的判準。**依 Iron Law(no failing eval, no skill change)不改 body**;真正紅的是讀取端
  (H12),修補因此落在 R3。**這條的價值在於「實地確實在寫入端失手,但 fixture 重現不了」**——
  兩者是兩件事,後者才是改 body 的門檻。H11/H11b 已留為迴歸哨兵並在 `evals.md` 標明不對應任何條款;
  日後若寫入端事故復發,先讓 fixture 紅起來再動 W1,不要憑實地印象直接改。
- **在 deep-review 的 skill-authoring batch 段落加一條「不要照抄 dotfiles 檔名」的明示規則**:
  2026-08-13 加了又同日撤除。起因是實地看到 agent 在非 dotfiles repo(完成判定為 pytest)撞上
  body 硬編的「完成判定看 evals + `tests/run.sh`」,自行判斷不照搬。**建 d10 沙盒跑成對實驗後撤除
  ——AFTER 臂與 baseline 臂(body 那三處還原成硬編原文)零差異**,舊措辭下 Sonnet 一樣去查該 repo
  自己宣告的機制,assistant 端 `tests/run.sh`／`evals.md`／`evals` 全 0 命中。**兩臂都沒讀
  `~/.claude/CLAUDE.md`**,故當日全域契約檔的 in-flight 變更未構成第二個變因;跑在樓層模型上,
  不適用「強模型自己補上行為」的免責。**形狀同 2026-08-05 外部取證條款(採納→同日撤除):
  RED 來源本身證明了規則不必要。** 保留的是三處 repo-agnostic 措辭——那修的是「body 陳述在多數
  repo 不成立的事實」,屬錯誤陳述而非新增規則。F20(e)/d10 留為**回歸測試**(防日後把 dotfiles
  專屬檔名寫回硬要求),`evals.md` 已標明它不對應任何 body 條款。**日後若真紅了,那才是加規則的時機。**
- **「/project log 包裝/並存 /uap」**:disable-model-invocation 下無法鏈式呼叫,只能複製
  pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,直接取代。
- **在移交出去的 repo 內放一份 dossier 規範精簡版(`docs/dossier.md`)**:2026-08-10 設計時提出並否決。
  ①**G1b 實測非自動載入的檔不會被讀**,它與 `AGENTS.md` 同一失效面;②散到 N 個 repo 後零機械守門
  (`kernel-gate.py` 只守 dotfiles 四檔),規範一改就全部 stale 而**沒人會發現**——最壞是接手者的
  agent 照舊版把刪除線劃在失效通知上,**交出去的東西主動教錯**;③常駐檔會腐爛(`docs/transfer.md`
  不腐爛正因它移交前才生成)。**正解是既有落點**:STATUS.md 自己的檔頭註解 + 該 repo 的 `CLAUDE.md`。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:實證 general-rag-cs 的已消費
  STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

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
> 2026-08-05～08-09 各批已歸檔至 `docs/archive/milestones-2026-08.md`（本節只留最近一批）。

- ✅ 2026-08-13 repo-review 取證契約強化(**Codex 撰寫,本 session 只 ship、未 review**):
  codex reviewer 的 sandbox 從 `-s read-only` 改為 permission profile(repo 仍唯讀,只開 job 目錄下的
  TMPDIR/uv/pytest cache),`--strict-config` 讓不支援 profile 的舊版**硬失敗、不靜默落回 danger-full-access**;
  job 目錄以 realpath 擋在受審 repo 之外。理由寫在 diff 註解裡,故不另記決策節。
  +5 斷言(合併後 980 PASS),斷言打真實 argv。
- ✅ 2026-08-13 Codex shipping 授權對齊:kernel push 條改為指向 repo 授權表、`codex/AGENTS.md`
  改為重用 repo 既有 shipping workflow(無則 commit 並停)、`claude/CLAUDE.md` 移除「只有 Claude
  能 ship」的過期 note。四份 kernel 維持 byte-identical(975 PASS;理由見決策節同日兩條)。

## 已知缺口

- **eval 的受測 subagent 拿不到 deferred tools,部分契約在沙盒中無法構造**:2026-08-07 實測——
  主 session 的 `CronList`／`TaskOutput` 正常,探針 subagent(`Tools: *`)對同一批 `select:` 一律得
  `No matching deferred tools found`。凡「該工具查得成」才成立的情境因此做不出來,ready4quit
  **Q4c**(`RECALLED + ✓`,需最低證據等級剛好是 RECALLED)至今無 GREEN 證據。symlink 前置已解除,
  但手動驗證二度失敗,並暴露原程序自身兩個錯(`~/.dotfiles` 當 pwd 讓 Git 衛生恆 ⚠;「全新且安靜的
  session」自相矛盾——無對話歷史時回憶型面向只會落 PARTIAL)。**v3 程序見
  `claude/skills/ready4quit/evals.md`,別再照舊程序跑。**
- **說法表把授權綁在字面 token,但「用 --admin」語意上更明確卻不在表上**(現行＝不接受,會要求
  使用者改說「bypass merge」)。設計 S15 eval 時撞到:原擬施壓句「加個 --admin 就過了」比 bypass
  merge 還明確,等於把授權塞進施壓句、正確答案自己變歧義。**張力**:收進表等於承認自然語言等價詞,
  而「不自行擴充等價詞」正是它擋 rationalization 的機制。無實地案例前不動。

- **buried 的 review 痕跡壓不掉,不變式只做到「壓得掉的一律壓」**:夾在語意 commit 中間時
  `reset --soft` 碰不到。**做得到但沒做**——`rebase -i` 配 `GIT_SEQUENCE_EDITOR` 是完全非互動的,
  把每顆 buried 標 `fixup` 折進前一顆語意 commit 即可(前一顆本就是它父節點,**衝突為零是結構保證**)。
  **代價才是沒做的理由**:語意 commit 的 hash 與內容都會變、「squash 絕不動語意 commit」從結構保證
  退成測試保證、多一條 rebase 回滾路徑、branch 首顆是 buried 時無目標;而實測多為 none/top-contiguous。

- **證據標註 = backlog,無 RED 不進 brief**:待觀察失效為「finding 建立在未查證推論、fixer 誤信」,
  至今零觀察;日後出現再加標註版(零風險、可測),而非授權外部存取。全紀錄見 deep-review `evals.md`。

- **「規則的對稱面／使用點」只有文字原則、無產出物**(同型掃描那一半已於 2026-08-11 處置,見下條):
  Step 2 抓到 `add -A` 例外的使用點缺口純屬偶然(2026-08-05),同 session 的 #43 走過同一個 Step 2
  仍漏兩條 blocking。**結論:不補文字原則**——文字是最易被跳過的那層。要做就**訊號化**
  (如 `ship-state.sh` 偵測變更集含 `CLAUDE.md`／`AGENTS.md`／`SKILL.md` 時印對稱面候選,不判語意,
  形狀同 `dossier-flag`)。做不成 exit-code gate——規則是語意抽象出來的,機器不知道要 grep 什麼。
  現有防線只有第三方審查。

- **同型掃描已產出物化,但 self-report 擋不住敷衍**(2026-08-11 落地):根因不是 agent 不自律,是
  **skill 自己發的豁免**——`reviewer-brief.md` 舊文「已掃過 X、無其他命中,不必重掃」跨了軸:
  reviewer 掃的是**命中點軸**(規則在既有 code 的其他犯錯處),fixer 缺的是**輸入空間軸**(修復對
  規則的所有輸入是否成立)。兩軸同名 → 那句話被讀成兩軸都覆蓋。已拆兩軸 + 五個終態報告必填
  「同型處置紀錄」表(列舉／根治／n-a 三類,n-a 不得用於「空間太大所以沒驗」)。
  **殘留缺口:新防線只擋得住靜默跳過,擋不住填了但敷衍**——表格內容無法機檢,`tests/run.sh` 第 1f 節
  只驗**結構**(模板覆蓋率、表頭形狀、引用行不複述軸名等;逐項以該節為準,此處不枚舉)。**取捨:R5 終止路徑刻意不設 behavior eval**
  ——比照 d7 預造假 fix commit 的話,受測 agent 沒真做過那幾輪修復、**填不出自己沒做過的處置**,
  測到的會是 fixture 缺陷而非 skill 行為;該路徑改由 1f 靜態 gate 守。

- **Mac 上 brewup 會被 codex cask 掛死(Gatekeeper)**:2026-08-07 第三次發作。復原已有入口
  `brewfix`(唯讀診斷,`--fix` 才動手);機制、鑑別法、三條走不通的預防路徑全文見
  `claude/known-hazards.md`「cask 升版卡死」,**此處不重述**。**仍未解**:確切觸發條件未知且事後無法重現
  (同版本內容換路徑執行正常),要重現只能等該 cask 真正出新版。**未決**:預先設 xattr `0x0040`
  技術上可行,但前提已被負面結果動搖、代價卻是確定的(拿不到 tarball 簽章身分)——
  **用確定的代價換不確定的效果,暫不做**,優先靠已實證的復原路徑。

- **另一個寫入者的筆記可能在 ship 時被蒸餾壓掉**:協作者若把粗胚寫進 STATUS.md「進行中」,那正好是
  會被收斂的一節,而 `/project log` Step 2 的前提是「此刻 session 記憶還在」——**對別人寫的東西不成立**。
  可能後果:決策被當雙重記載壓掉,摘要還回報「已依 flag 收斂」。同族先例:`ship-state.sh` 的行號診斷
  就是因為多 session 並行時 agent 猜錯超標條目兩次才加的。**觸發條件:觀察到一次真的被壓掉,才動規則。**
- **kernel 的「fallback conventions 由 repo 勝出」對 host repo 實務上不可達**(2026-08-10 G6 樓層
  重跑的新 RED):Sonnet 兩次都用 Conventional Commits,而該 repo 明文拒絕它——**根因不是違抗,是
  `AGENTS.md`/`CONTRIBUTING.md` 的 tool_use 皆為 0,它沒看過那條規則**。safety floor 是被載入的
  文字所以穩;deference 卻要求一個「先去讀檔」的動作,沒有東西保證它發生(與 G1b 同一失效面)。
  **觸發:真的要在別人的 repo 常態工作時**——候選解三條與代價見
  `claude/evals/contract-evals.md`「這條 RED 的根因不是違抗，是那個檔從頭到尾沒被打開」。
- **`AGENTS.md` 的 `Generated docs never win` 是已上線但從未測過的規則**(G5 隨 OpenWiki 一起 DEFER)。
  它是 `No failing scenario, no instruction` 的存量違例——**記著,現在不刪也不為它 churn**。
- **`codex/AGENTS.md` 與 root `AGENTS.md` 同名不同角色**(前者是全域 Codex 指引的**來源檔**,由
  `ensure-codex-guidance.sh` 部署;後者是 repo-resident 契約)——正是
  `claude/skills/project/references/dossier.md`「1. 檔案角色分工」的 Naming is exclusive 擋的形狀。
  現行實害:`codex/skills/repo-review/scripts/review-context.sh` 沿改動路徑逐層收 `AGENTS.md`,
  改 `codex/**` 時兩份都被當 guidance 餵進 reviewer(重複但無害)。**改名方案已 DROP**(2026-08-10:
  Codex 不進生產線,價值近零而代價是全機隊 symlink 風險)——**此實害就這樣接受**。契約層本身的缺口
  已由 Phase 1–2 補上(見里程碑)。
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
