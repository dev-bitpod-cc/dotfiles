<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-05)

---

## 進行中

(暫無)

---

## 關鍵決策(附理由)

- **2026-08-05 reviewer 的提問端一律走白名單契約,不用禁語黑名單**:列舉禁語**可證會漏**
  ——本 repo 實測一次(偵測 regex 列了 `final round`、實際寫法是 `FINAL allowed review
  round`,差點誤判對照組乾淨),與同批 codex fixture 的 blocklist-vs-allowlist 是同一教訓。
  白名單的代價要一起記:**收太緊會擋掉必要資訊**(契約模板漏了 priority 2 的 untracked
  清單槽,reviewer 會整批漏審新檔且不自知,由 codex C2/C3 連兩輪抓到)。
- **2026-08-05「審查者與作者分離」的邊界=分離判斷、不分離提問**:`Separating the judge
  does nothing if the same party writes the question.` 主 agent 仍構造 subagent prompt,
  故硬約束全下在提問端(判準交路徑、bar 與 task 恆定、輪次/上限不外洩)。裁決端實測無失敗
  (FP 罕見、幾乎都承認照修),故**不加 judge 覆核、不加 FP 記錄欄位**——no failing
  scenario, no instruction。
- **2026-08-05 輪次是 orchestration 私有狀態,但隱蔽有已知殘留**:保留輪次的原理由(brief
  需要它調重心)站不住——**補丁痕跡是 code 的性質、不是 history 的性質**。中性化擋掉輪號與
  剩餘輪數,**擋不掉「已改過幾次」**(commit 數量本身即訊號);要消除得每輪 squash、破壞迭代
  紀律,故接受殘留但文件不得宣稱成完全隔離。
- **2026-08-05 洩漏主管道是 harness 注入的 gitStatus,不是 reviewer 主動查**:實測
  `tool_uses=0` 的 subagent 能逐字複述主 repo 五個 commit hash——**gitStatus(含最近 5 筆
  subject)直接進 subagent system prompt,不做任何動作就看得到、且關不掉**。故 commit message
  中性化從一致性修補升為**必要條件**(寫 `fix: R4 ...` 等於把輪號直送 system prompt)。同批
  驗完 codex 列的三類 metadata 管道(task/role names、checkpoint messages)與 fresh-context
  保證皆乾淨,故不加禁令。證據見 deep-review `evals.md`。
- **2026-08-05 eval 的 `expected_behavior` 不得要求證據不支持的推論**:d4 初版的 fixture 與
  endpoint 之間無明示綁定,判準卻要 reviewer 據相似性認定 provenance——**等於獎勵無根據歸屬、
  懲罰「我無法確認」這個更嚴謹的答案**(而後者正是 brief 要求的態度)。補 `_source` metadata
  使綁定機械可驗證。與 F18「判準寫成答案導向」同型:**oracle 寫歪會系統性淘汰最該保留的行為**。
- **2026-08-05 git 收尾序列不得串成一行、更不得吞掉中間錯誤**:`git switch main 2>/dev/null;
  git pull origin main` 串一行——switch 因他線未 commit 變更而失敗,錯誤被 `2>/dev/null` 吃掉
  又沒檢 exit code,於是 **pull 在 feature branch 上跑成 rebase**,16 顆往已 squash 的 default
  重放炸出滿地衝突(`rebase --abort` 可完整還原,但屬不必要的險)。正確替代:`git fetch origin
  <default>:<default>` 更新本地 ref 再切。與 `git add -A` 誤收同根源:**為省事合併 git 動作,
  錯誤就藏在中間**。
- **2026-08-05 多 session 共用 working tree:commit 一律顯式路徑,`git add -A` 是誤收源**:
  同一錯誤犯三次(誤收 codex 端 repo-review 工作);第三次是循環陷阱——commit 後把他人區段 `cp`
  回 working tree,下次編輯同檔就疊上去、整檔 add 必然再收。**三次都只有乾淨 checkout 看得見**
  (本機檔案在磁碟上恆綠)。四條:(a) 顯式路徑;(b) 混檔按**檔案內區段**拆、非只按目錄;
  (c) 拆完必跑 `git clone --no-local` 實測;(d) 他人區段最後才放回。
- **2026-08-05 外部取證條款兩端最終都不納入**:codex 端自始拒絕移植;deep-review 側一度納入、
  同日撤除——**該條的證據(krepo 三條 finding 由 subagent 自發取證找到)恰恰證明規則不必要**,
  倒果為因;且進 brief 當批即生出第二層規則(授權邊界),而 d4 fixture 測不到那半,留下無 oracle
  的規則。折衷版(改標註 evidence 為查證/推論)同樣無 RED,降為 backlog。**repo-review 仍移植
  收斂診斷**(依根因重複/震盪 vs 各輪不同分類)並補了 tests gate。全紀錄見 deep-review `evals.md`。
- **2026-08-03 codex 的決策發聲採「產原料寫進行中、ship 端蒸餾」,不讓 codex 學 dossier 規範**:
  #34 暴露 cross-agent 記錄斷點(codex 改 `codex/skills/`、Claude 端 ship,理由只能從 diff 反推)。
  界線是原理性的:**機制反推無損,但否決的方案與死路在 diff 裡永遠沒有痕跡**。故 `codex/AGENTS.md`
  只要求把推不到的那部分追加到「進行中」(不 commit 不管格式),蒸餾與章節語意留 ship 端;並帶
  「純機制改動免寫」免除條款(無免除=每次小改都付儀式成本)。
- **2026-08-03 repo-review 多輪 autofix 死鎖以「gate 一次、之後查 ownership」解,不放寬 clean
  要求**:`--autofix` 要求 clean worktree,而規範要求每輪 rerun helper,R1 修完必髒 → 第二輪必得
  `autofix-safe:no`,契約自我封死。解法:`--autofix` 只當**首次編輯前的一次性起始 gate**,後續
  改跑不帶 flag 的 helper 並比對 dirty path 歸屬,遇 pre-existing/concurrent/未記錄即停。
  **反向解(放寬 clean)會讓「絕不碰使用者變更」整條保證失效**——根因是判定時機錯置,不是太嚴。
- **2026-08-03 autofix 安全判定補 `base-not-commit`——tree base 的 ancestor 檢查回 `n/a` 不是
  `no`**:`HEAD~1^{tree}..HEAD` 這類 base 先前一路穿過 ancestor gate 拿到 `autofix-safe:yes`,
  等於在無法界定祖先關係的範圍上放行改檔+checkpoint。新判定置於 ancestor gate **之前**,條件
  `BASE_TYPE != commit && BASE_HASH != EMPTY_TREE`——刻意保留 empty-tree baseline 的既有豁免
  (該路徑語意明確且已有測試,一併擋掉會誤傷首次全 repo review)。
- **2026-08-03 Codex reviewer 的 fresh context 要顯式 `fork_turns=none`,不靠預設**:spawn 介面
  預設繼承全部 turns,規範只寫「用 fresh-context subagent」等於**spec 上宣稱 fresh、行為上帶著
  parent 的實作意圖與嫌疑清單**——delegate 的價值(獨立重推結論)當場歸零。介面無法建立無歷史
  reviewer 時一律明說降級,不得聲稱跑過 fresh-context pass。

> **2026-07 及更早的決策已歸檔** → `docs/archive/decisions-2026-07.md`（機制多已固化在 skill／腳本／tests；歸檔保存的是「為什麼這樣決定、否決了什麼」）。

## 死路(試過但放棄——防重工)

- **mc(Midnight Commander)當遠端檔案管理器**:評估後放棄,理由是**協定層而非偏好**——
  mc 的 `sftp://` VFS 走內建 libssh2,**不支援 OpenSSH 使用者憑證**,而內網主機一律
  cert 認證(`id_autogen-cert.pub`,principal `jjshen`),等於主要路徑不通;可用的 `fish://`
  雖外呼真 ssh 能吃 cert,但每個操作起一次遠端 shell、且 macOS 還要處理 F1–F10 被
  Mission Control 攔截與 subshell 不繼承 cwd。同樣需求 `lftp` 的 sftp backend 預設就外呼
  `ssh -a -x`(已實測 `set -a` 確認),cert 與 `~/.ssh/config` alias 原生生效,無這些摩擦。
  **若日後想重評 mc,先確認 libssh2 是否已支援 OpenSSH cert,否則結論不變。**

- **「/project log 包裝/並存 /uap」**:disable-model-invocation 下無法鏈式呼叫,只能複製
  pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,直接取代。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:實證 general-rag-cs 的已消費
  STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] R4 non-blocking 建議未修:新增 prose 的中文半形標點與既有全形混排;Transfer 模式 commit
  紀律歸屬未明示;evals/README 路徑基準寫法;handoff evals H4 排序
- [ ] dossier 訊號 R5 non-blocking 未修(2026-07-29,皆非 blocking、無失敗案例):
  `dossier-sections` 百分比因標題行不計而系統性略低於 100%(需在說明點一句);SKILL.md「唯一的
  例外」與 S12「使用者堅持不動也是例外」說法不一致;最長行 flag 訊息缺「何時處置」;S12 fixture
  規格內部不一致(setup 寫 >800B 條目、expected 要最長行 flag 需 >1000B);條目作用域用子字串
  比對(`決策|里程碑|已完成`)而非簽章那種端錨定,標題寫成「## 進行中(已完成 M1)」會誤掃;
  `CLAUDE.md` 摘要句未提「非錨定 pattern 的 ✅ 例外」
- [ ] hook matcher 僅 `startup`(resume/clear 不重測落後)——擴不擴待拍板
- [ ] Scenario 11 的「merge 但無 PR」分支只在 SKILL body 一行指標帶到 ship-paths,GREEN 實測中
  弱模型未展開讀——非違規故未補;重現才加明示(Iron Law)
- [ ] pressure-tests S8/S9/S12 沙盒未納入 `claude/evals/setup-sandboxes.sh`;S10(transfer
  credentials)與 S12(dossier 三 flag 蒸餾紀律)連首輪實測都還沒跑
- [ ] SessionStart hook 落後提醒未在真實落後 clone 驗過(tests 有覆蓋)——下次任一主機落後時順手確認
- [ ] autocodex exec 的 resume 分支(exit 4 救援階梯)未實戰驗證——三輪實跑皆一次成功,只有
  stub 覆蓋;遇真實空報告時確認 resume 能救回,F15(b) 才算 GREEN
- [ ] review-anchor 的 stale STOP 與 codex-next 冪等(F16 b/c)已由 tests 第 19 節釘死,
  實戰(autocodex 迭代中 rebase/重試)尚未驗過
- [ ] codex plugin 去留待定:實質只當傳輸管道,exec 接管後僅剩 `/codex:transfer` 獨有——
  exec 路徑跑穩數輪後重新評估 uninstall
- [ ] codex C2 轉交 findings 餘項(2026-07-21 代收):F6 skill-building-guide 的
  `$skill-creator/scripts/quick_validate.py` 路徑解析(context-dependent)。F5(多輪 autofix
  死鎖)已於 2026-08-03 判 true positive 並修復
- [ ] repo-review 新契約(起始 gate 一次 + 後續 ownership 檢查、mixed-context manifest)僅由
  evals F16–F18 規格覆蓋,**實戰未跑過**——下次真跑 autofix 多輪時確認弱模型不會退回每輪帶
  `--autofix`
- [ ] /project 手感驗證後半段:spec→實作(即時記錄)待驗;mid-work re-spec 2026-07-21 研究後
  判維持不改(Iron Law:no failing scenario, no instruction)——除非觀察到照過時 spec 執行或
  擅自擴大範圍,才補程序+RED eval

## 已完成(里程碑)

- ✅ 2026-08-05 repo-review 移植輪次上限的收斂診斷(codex 撰寫、Claude 代 ship):依根因重複/
  震盪 vs 各輪不同且前案仍修復來分類,禁止單憑上限推論架構問題;evals F21+tests 契約 gate。(565)
- ✅ 2026-08-05 deep-review 第三方回饋落地 + 輪次隱蔽缺口結案(#40):終止報告根因重複欄、
  R5 措辭修正;codex 三輪 4/4 TP 全修。外部取證判準同日撤除,見決策節。(564)
- ✅ 2026-08-05 codex repo-review 移植同批治理(#39):reviewer-brief 判準下沉、stage-neutral
  prompt 模板、pass 位置 orchestration-private(範圍比 deep-review 側更廣);evals F19/F20。
- ✅ 2026-08-05 deep-review 審查偏誤治理(#38):根因在**提問端**(主 agent 自行放寬 prompt),
  修法為判準下沉+白名單契約+輪次隱蔽;驗證三層與 codex 九條 findings 見其 `evals.md`。(547→564)
- ✅ 2026-08-04 lftp 納入標準工具鏈取代內建 sftp(#36):setup 加裝+版控 `lftprc`+
  `ensure-lftprc.sh` 接 dotsync 散佈,14 台全到位(4.9.3);選型見死路節,`ls` 單檔陷阱(報錯但
  其實已傳成功、須用 `cls`)見 `lftprc` 註解。(526→547)

- ✅ 2026-08-03 codex repo-review 契約補強:autofix 起始 gate 一次化+後續 ownership 檢查(解 C2 F5 死鎖)、tree base 擋 autofix、reviewer `fork_turns=none`、mixed-context manifest;順帶 gitignore_global 收 `**/.claude/settings.local.json`(單機 key 檔全 repo 免誤 commit)。(#34;evals F16–F18,tests 526/0)
- ✅ 2026-08-03 macOS 大型 notarized binary 路徑快取卡死地雷入庫(#33;syspolicyd 以完整路徑為 key,`killall` 解)
- ✅ 2026-07-29 dossier 治理再下沉三訊號:條目行號/建議收斂目標/各節佔比(#32;SKILL.md 逐條處置複述改指腳本,消一處已漂移的重複記載)
- ✅ 2026-07-22 殘留 branch 衛生訊號+實地清掉兩支老殘留(#28;教訓:git fixture 須複製真 clone 的 origin/HEAD ref 佈局)
- ✅ 2026-07-22 無 protection repo 改 PR 預設,Scenario 11 首次覆蓋 OPEN 路徑(u3 RED→GREEN,#27)
- ✅ 2026-07-22 /project 補 bootstrap 路徑——空 repo 首次 ship 的機制門控豁免(tests 先 RED 後 GREEN,#26)
- ✅ 2026-07-21 skills 下沉三部曲收官:check-crawl-quality/project/handoff(#21/#22/#23;tests 235→478 全綠)
- ✅ 2026-07-21 deep-review prose 下沉腳本+body 密度收斂(review-anchor/verify-tests/codex-protocol.md,#18/#12;evals d1/d2 雙 PASS)
- ✅ 2026-07-20 autocodex 卡死根治——傳輸層改 headless codex exec(#8;exec 三輪實跑無卡死)
- ✅ 2026-07-17 /project 摩擦修復+全機隊生效(#1/#2;輕量路徑/詢問收斂/merge 最後一哩,dotsync 14 台)
- ✅ 2026-07-16 多主機工作流改造(c673844;/project 取代 /uap、SessionStart pull hook、dossier/transfer 模板)

## 已知缺口

- **證據標註 = backlog,無 RED 不進 brief**:待觀察失效為「finding 建立在未查證推論、fixer 誤信」,
  至今零觀察;日後出現再加標註版(零風險、可測),而非授權外部存取。全紀錄見 deep-review `evals.md`。

- **deep-review anchor 跨批次會 stale,`squash-cmd` 因而指向錯誤目標**:anchor 只在 autofix 的
  `record` 寫入,走「codex 第三方審查」觸發詞路徑(非 autofix)時不 record,`squash-cmd` 遂讀到
  **上一批**的 anchor。2026-08-05 實遇:本批 3 顆 commit,腳本卻給出會壓掉 5 顆(含已 merge 的
  #38/#39)的 reset 目標。**腳本行為正確**(照 anchor 算並自印 warning),缺的是「anchor 屬於哪
  一批」;現行防線只有人看 warning。可能解:`squash-cmd` 偵測 anchor 已併入 default 或不在當前
  branch 歷史時改判 STOP。未實作。

- **同型掃描有文字原則、無產出物(機制不對稱)**:deep-review 對「測試」有機械化 gate
  (`verify-tests.sh` 的 exit code 契約),對「同型掃描」只有 `reviewer-brief.md` 與 SKILL.md
  的文字要求。2026-08-05 krepo 實戰回饋指出:連跑四輪修復時最容易被跳過的正是這類原則性
  敘述,且該次漏的就是它。**做不成 exit-code gate**——規則是語意抽象出來的,機器不知道要
  grep 什麼;可行的只有 checklist 化(要求 fixer 每輪在報告寫出「本輪抽象出的規則 + `rg`
  命中數」),但那會改動 fixer 每輪的報告格式,待單獨評估。終止報告新增的「根因與前輪
  重複?」欄只在**終止時**部分暴露此失效模式,太晚。

- **Mac 上 brewup 會被 codex cask 掛死(Gatekeeper 首次執行核可)**:cask 的 completion artifact
  首次 exec quarantine 過的新 binary,同步等系統核可對話框(常沒搶到焦點,看似卡死於
  `Linking Binary`)。解法:在對話框按允許(誤按取消→系統設定「仍要允許」),再
  `brew reinstall --cask codex` 補完並清 `*.upgrading` 殘留。**勿用 xattr 除 quarantine 或
  --no-quarantine**(核可即足夠,那是不必要的安全弱化)。僅 codex 實際升版時發生(對話框綁
  CDHash 問一次);經 SSH 的 allup 對話框只出現在實體螢幕,該 Mac 須先本機核可過該版。
- 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,
  改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+credentials 明文散於三台。

## 移交準備度

(個人 infra,暫無移交打算——平時留空)
