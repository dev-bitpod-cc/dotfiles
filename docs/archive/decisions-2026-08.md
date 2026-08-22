# 關鍵決策歸檔 — 2026-08

> 從 `STATUS.md`「關鍵決策(附理由)」節歸檔（2026-08-06，總量治理；做法與先例見
> `~/.claude/skills/project/references/dossier.md`，判準見 STATUS.md 內「dossier 超標
> 優先歸檔」一條——**已固化在 skill/腳本/tests 且不再影響現行方向者才歸檔**）。
>
> 這些決策的**機制**多已固化在 skill / 腳本 / tests / CLAUDE.md 裡，從程式碼即可反推；
> 此處保存的是**當初為什麼這樣決定、否決了哪條路**——那部分永遠無法從 diff 反推，
> 所以歸檔而非刪除。
>
> 按需查閱，不進 always-on context。要追某個現行行為的理由時搜這裡。
>
> 2026-08-18 追加一批（08-14～08-16 的 9 條：autoMode／fleet wrappers／`BLOCKED` 判準／等 CI 不封頂／
> repo 所有權轉移／always-on 量體訊號／外部 findings 結案）——機制皆已固化在 `settings.json`／
> `ship-state.sh`／`shell/functions.sh`，且無待觸發條件。

- **2026-08-05 `add -A` 禁令的例外只有 deep-review WIP snapshot,且附前置條件**:新立的全域
  禁令與 `deep-review/SKILL.md` 的 `git add -A && git commit -m "wip: ..."` 直接對撞(第三方
  審查抓到,全 repo 唯一衝突點)。**不改 skill**——WIP snapshot 要的正是「使用者原始變更的
  完整快照」以便後續 revert 壞修復,改顯式路徑會毀掉語意。改在禁令側開例外,但**必須附
  「執行前確認 working tree 全屬本次工作」**:snapshot 終態會 squash 進 PR,混了他人變更
  一樣誤收,「先 snapshot 再拆」是假解。
- **2026-08-05 codex 側需要自己的 branch-first,不能只說「ship 歸 shipping agent」**:原條
  「Branching...belong to the shipping agent + leave the work committed on the current
  branch」在 HEAD 站 main 時,字面就是**要 codex commit 到 default branch**。Branching 移出
  該條、改要求 codex 自行 `switch -c`(只做乾淨情境;誤 commit 的救援仍歸 Claude 的
  `branch-first.sh`)。
- **2026-08-05「先 STOP」與「混檔 staging 技法」必須寫明順序**:兩條並列會被讀成二選一
  (一律停 vs 照樣 stage)。正解是鏈條——發現非自己的變更→停下報告→使用者確認→才用
  `add -p` 等技法。本 session 實走過一次(STATUS.md 混了先前未提交的技術債,處置是 ship
  摘要問使用者,而非自行硬拆)。:外部建議
  「先取消固定所有權(codex 只碰 `codex/`)再談共用」**順序顛倒**——固定所有權當時是唯一在
  擋 codex 的東西(`AGENTS.md` 只有 skill authoring + decision notes、零 git 紀律,而
  `config.toml` 是 `danger-full-access`);且所有權早已自然鬆動(#39/#40 即 codex 撰寫、
  Claude 代 ship),那個要解的問題並不存在。
- **2026-08-05 跨 agent 共用的污染邊界分三層**:可共用=repo 事實、程式碼、測試、機械腳本、
  最終決策;**不主動共用**=嫌疑清單、上輪 findings、輪次、預期答案、作者的判斷路徑;
  **可刻意不同**=兩邊 reviewer 的判準與 orchestration,只要各自有 eval oracle。無邊界的
  「共用 contract」會慢性稀釋 8/5 整批隔離決策(審查者與作者分離、輪次隱蔽、gitStatus 洩漏)
  ——**共用與獨立審查是張力,不是可並列的好處**。
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
  (本機檔案在磁碟上恆綠)。四條:(a) 顯式路徑——但 `git add <path>` **仍是整檔、擋不住同檔
  混改**(2026-08-05 補),混檔須 `add -p` 只 stage 驗過的 hunk、且 commit 前看 `diff --cached`;
  (b) 混檔按**檔案內區段**拆、非只按目錄;(c) 拆完必跑 `git clone --no-local` 實測——人工看
  staged diff 已實證失敗三次,不能取代這條;(d) 他人區段最後才放回。
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

- **2026-08-05 handoff 續寫偵測必須查 archive,不能只查 active**:原判準是「active 有同 slug
  **或** 本 session 剛 resume 過」,刻意不查 archive(當時理由:續寫入口通常是 resume,前一份
  已在 context)。codex C1 指出「新 session 直接 `/handoff <slug>`」整條失效——前一份已被消費
  躺在 archive,兩個判準都不成立,第 N 輪判成首輪。**自打臉點:h5 沙盒的 setup 正是該路徑,
  等於造了自己規則涵蓋不到的反例卻沒察覺。**教訓:**規則與 eval fixture 同批寫時,先拿
  fixture 對規則走一遍**——fixture 是反例產生器,不只是驗收工具。

- **2026-08-05 改寫規則的分支條件,比新增規則更容易掉情境**:同一條判準**連中三次**——修法
  改了三版才收斂(v2 把 v1 覆蓋的情境換成互斥分支,codex C2 抓到);之後又一次把 W1 的 `list`
  從「一律跑」改成「只在未指定 slug 時跑」,而 W4 的 housekeeping 正吃它的輸出,explicit-slug
  路徑上 EXPIRED 提醒與 archive 清理**雙雙沉默失效**。判準兩層:改寫分支條件前先確認
  **① 舊版覆蓋的情境沒被新分支排除 ② 誰還在依賴舊分支的副作用**。
- **2026-08-05 跨 agent 不預先建抽象:共用 contract 層與 `/project spec` 移植皆否決**:
  移植實測不是複製(codex 側 reviewer-brief 27 行 vs Claude 側 97 行、#39 pass-privacy 範圍
  刻意更廣),抽共用檔會退化成「共用+兩份 override」,反製造該建議自己列的「兩邊語意不同」
  風險;`/project spec` 則低風險=低價值——上次真實 cross-agent 斷點(#34)的解是 12 行
  decision notes 條款,已證明正確粒度是**薄契約+既有 artifact**。兩者皆等 RED 再議。
- **2026-08-05 外部取證條款兩端最終都不納入**:codex 端自始拒絕移植;deep-review 側一度納入、
  同日撤除——**該條的證據(krepo 三條 finding 由 subagent 自發取證找到)恰恰證明規則不必要**,
  倒果為因;且進 brief 當批即生出第二層規則(授權邊界),而 d4 fixture 測不到那半,留下無 oracle
  的規則。折衷版(改標註 evidence 為查證/推論)同樣無 RED,降為 backlog。**repo-review 仍移植
  收斂診斷**(依根因重複/震盪 vs 各輪不同分類)並補了 tests gate。全紀錄見 deep-review `evals.md`。

- **2026-08-06 predecessor 定位改用腳本子指令,推翻「一行 `ls` 足夠」的原判斷**:計畫階段
  刻意不加子指令(理由:續寫入口通常是 resume、前一份已在 context)。結果同一處被 codex
  **C1/C2/C3 三輪逐輪擠**:只查 active → 分支迴歸 → glob 尾錨定仍誤中(`*` 吃得下中間的
  工作線名,查 `foo` 撈到 `bar-foo`)。根因是拿 glob 做本質上需要精確比對的事。新增
  `find-predecessor`(檔名去時戳前綴後全等 + 檔內 `slug:` 相符,兩層精確)。**判準:同一處
  連續三輪被審查擠,問題在抽象層級、不在措辭**——此時「不要為改而改」不再適用,已有實據。
- **2026-08-06 handoff 歸檔檔名的格式歧義選擇「容納並標示」,不是消除**:`YYYYMMDD-<slug>`
  與 `YYYYMMDD-HHMMSS-<slug>` 在 slug 恰以「6 位數字-」開頭時無法從檔名區分,且該檔若無
  `slug:` frontmatter 就沒有佐證來源——**資訊不足,消不掉**。三個選項按後果排序:只試一種
  解讀→正確的 slug 找不到前一份→判首輪→整檔覆寫→**無聲遺失**(最糟);拒絕歧義檔→兩邊都
  找不到;兩種都試→可能撈到別條工作線,但 agent 讀內容看得出來(最輕且可偵測)。故選第三,
  並加 `note: AMBIGUOUS` 把不確定性交給讀取端。**判準:資訊上不可判定時,選「後果可偵測」
  的那條,別選「看起來乾淨但會無聲出錯」的。**

- **2026-08-06 squash 範圍與審查範圍解耦,推翻 2026-07-21「兩者恆等」的拍板**:舊 base =
  anchor base,branch-diff 下等於整條 branch 全壓,使用者的 `feat:` 連同 review fix 壓平、
  只印 warning 不中斷。改為由 HEAD 往回掃 subject、停在第一顆語意 commit。**恆等沒被破壞
  的那一半才是重點**:squash 後內容總和仍等於審查範圍,變的只是 commit 邊界。撞名(手寫
  commit 恰撞機械字串)接受——後果等同舊行為,故不加 `head_at_record` 補償(分岔歷史下它自身
  會誤判,codex C3 F2 已證)。
- **2026-08-06 round 偵測改「頂端連續段」,與 squash 刻意用不同集合**:branch 保留語意 commit
  後,舊的「數全範圍 `fix|refactor` 前綴」會被使用者自己的 fix: 與上一場殘留雙重灌水,**直接
  吃掉 R5 預算**(極端情況第一次審查就判已達上限、零修復輪)。改為自 HEAD 往回數連續的 review
  機械 subject。**兩者邊界不同且刻意如此**:`wip:` 中斷 round(不是一輪修復)、卻會被 squash
  收攏。pattern 抽到 `scripts/lib/review-subjects.sh` 單一來源——漏認→squash 只壓一半、
  多認→輪次灌水,兩個方向都難察覺。
- **2026-08-06 merge 的「壓不壓」改關鍵字分流 + 選項式詢問,預設不再是 `--squash`**:GitHub
  squash-merge 全有全無,故是整個 PR 的一次決定;舊規則預設全壓、保留要靠 agent 主動察覺,
  方向與「語意 commit 有參照價值」相反。裸「merge」在 PR ≥2 顆 commit 時給三選項,**且再答
  一次「merge」不算回答**——該詞同時是動作與 `--merge` flag,自行挑解讀正是
  `disambiguate-overloaded-terms` 記的失效形狀。
- **2026-08-06 merge 授權收進 Step 4 第 1 題,同批推翻自己稍早的拍板**:先寫了「merge 授權絕不
  進 Step 4 選項」,但那等於把本來一句「merge」就一路到底(push→PR→merge→清 branch→同步
  default)的路徑拆成兩步——**使用者實地被問兩次才發現**。改為第 1 題即「這批怎麼處理?」
  (送出停在 PR／送出並 merge／取消),勾選即構成 explicit merge instruction。**merge 方式仍不
  在該題細分**:當下 PR 還沒開、commit 數還會被同批 squash 題改變,此刻問等於要使用者預測。
- **2026-08-06 dossier 加「章節完整性」訊號,因為既有防線全都只管上限**:一次批次編輯的邊界
  只檢查「下一個條目」、沒檢查 `## `,把「已知缺口」「移交準備度」兩整節吃掉;**行數反而變少
  → 尺寸 flag 不響、簽章只要求「任一」專屬章節 → 也放行**,一路 merge 進 main 才發現。
  補 `dossier-flag: 缺少規範章節`(比對模板七節)。**判準:內容遺失是 dossier 最貴的失效,而
  現有訊號全是「太多」向的;凡是「變少」的方向都要另外設門。** 同批第三次踩到「fixture 前提
  未成立 → 假綠」(此次:測試 repo 無 remote,ship-state 在 verdict STOP 就返回,檢查根本沒跑)。
- **2026-08-06 「同型掃描」的完備度由 pattern 選擇決定,不由「有掃」決定**:R1–R5 每輪都做了
  grep 同型掃描、每輪也都掃乾淨了,但下一輪 reviewer 換一種措辭又找到新殘留(5 輪都是同一根因
  「語意反轉的下游未同步」的不同實例)。**判準:改動語意時先列出「誰消費這個語意」的清單再逐一
  驗,別靠當下想得到的措辭去 grep;宣稱兩個機制「相同」之前,先跑一次反例。**

- **2026-08-06 修復本身會製造下一輪的 finding**:codex C2 三條全指向 C1 的修復、C3 兩條全指向
  C2 的修復;主審側也有一次(R4 修「hash 過期」引進的重算規則,被 R5 實測打掉)。每次修法都對,
  錯在只想到一半——quote 了路徑沒 quote ref、把判準從 SHA 相等改成 ancestry 卻沒想到那個 ref
  會過期。**判準:修完問「這個修法自己引進了什麼新前提」,那個前提就是下一輪的 finding。**
- **2026-08-06 「測試看似在測、實際不可能失敗」有三種形狀**:fixture 排序讓錯誤實作也答對
  (`bar-foo` 時戳若比 `foo` 舊,退回 glob 也剛好選對)、突變未生效卻誤判成斷言無鑑別力
  (見下條)、**vacuous expectation**(eval 寫「有 EXPIRED 就列出」但 fixture 不會產生
  EXPIRED,忽略 `list` 輸出照樣過關)。共通點:**斷言為真的方式與實作正確性無關**。
  判準:答不出「什麼具體情境會讓它紅」就是虛設。
- **2026-08-06 突變測試要先驗「突變已生效」,且雙層防禦須一次全破**:本輪兩次假綠——
  第一次 `str.replace` 沒命中(靜默無效),第二次只突變第一層、被第二層 frontmatter 驗證
  擋下,兩次都看似「斷言無鑑別力」實則突變未達成。修法:replace 前 `assert old in s`、
  寫入後 grep 確認,且要**一次破壞所有防線**才算模擬回退。

- **2026-08-05 dossier 超標優先歸檔,不靠壓縮無關的舊條目**:本次為容納新增內容,接連蒸餾五條
  無關的歷史決策才勉強壓在 24576 門檻下——每次都無損(留結論與理由、砍推導史),但「為了幾百
  bytes 去改一條無關舊決策」重複五次本身即訊號:**邊際壓縮效益遞減,再壓會開始損失資訊**。
  改採歸檔後一次降 33%(24556→16444)。**判準**:條目已固化在 skill/腳本/tests 且不再影響現行
  方向 → 歸檔;仍在生效的一律不歸檔(死路=防重工、技術債=未解決,移出 always-on 即失效)。

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

---

## 2026-08-07（ship 流程機制批；機制已固化於 `claude/skills/project/` 的 SKILL 與 references，從那裡可反推）

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

- **2026-08-07 Step 4 從「逐批出題」改「說法即授權」,拆掉的守衛另補一道**:使用者實地回報「說了
  ship 還被問四次」是摩擦。改為送出說法(merge／bypass merge／只推 branch…)出現在本輪訊息裡就
  印完摘要做到底、零提問;沒說法才問一題。**但這拆掉的是「push 前你一定會看到摘要並有機會攔」**,
  故補上 `review-terminal:`——上一場審查若是 R5 終止收場(且 ancestry 涵蓋當前 HEAD)一律 STOP,
  說法覆蓋不了。**判準:移除一道 gate 時,先問它順帶接住了什麼,那些東西要各自有主。**
- **2026-08-07 merge 預設改「保留語意 commit」,推翻昨天「≥2 顆就出選項問」**:昨天那條的理由是
  「壓不壓沒有預設值,不能猜」;使用者給了預設(不同目的的 commit 預設保留)之後,歧義本身消失,
  詢問的理由跟著消失。**那條規則從未實測就被推翻**,故無實測結論被推翻。review 痕跡則相反——
  **壓得掉的一律壓、不問**,它不是偏好而是不變式;唯一的自由度是「壓不壓得掉」(buried 壓不掉)。

- **2026-08-07 「符合已知地雷的形狀」≠「就是那個地雷」——沒實測就別把重構寫成修 bug**:
  誤判 `<< SSHEOF` 灌 `ssh/config` 會執行該檔註解裡的反引號,據此改了三處並把結論寫進
  commit / PR / dossier / CLAUDE.md **四處**。**實測全錯**——命令替換的結果不會被重新掃描,
  注入的反引號不執行;危險的只有寫在 heredoc body **字面**那種。重構無害故留,四處理由更正。
  **教訓兩層**:①地雷記憶會讓人用「形狀相符」代替驗證,而展開規則細到形狀不夠判;
  ②錯誤結論進了 dossier 就會被當事實引用——**發現時要回頭改所有出處,不能只改程式碼**。
- **2026-08-07 判準寫得出來的地雷就該做成 gate,但 gate 的判準只能涵蓋實際驗過的形狀**:
  unquoted heredoc 含反引號這條記憶**當天早上才寫進 CLAUDE.md**、同一晚仍差點再踩,
  **記憶擋不住「寫 prose 時反引號是標準寫法」這種肌肉記憶**,故改做掃描器(第 1c 節)。
  判準嚴格限定「body **字面**含反引號」——上一條那次誤判還為它加過一條 `$(cat …)` 規則,
  那會把每個用 heredoc 灌檔的正常寫法都判紅,已撤銷並留 GREEN fixture 釘住。
  **掃描器自己必須有 RED/GREEN 自檢**——被改壞而恆不匹配時,對真實檔案的空輸出一樣是「通過」,
  正是 gate 靜默失效的標準形狀(第一版漏掉 `<< EOF` 的空白,RED 反綠、GREEN 反紅)。
- **2026-08-07 一次性遷移也值得做成帶 gate 的腳本,判準是「還要在幾台機器上重跑」**:GitHub
  收斂的 remote 換寫在 spec 裡本來是一段照抄的 `for` 迴圈。改做成 `scripts/migrate-github-remotes.sh`
  的理由有二、都不是「比較整齊」:①**順序是硬前提**——spec 明寫「身分驗證通過才能改 remote」
  (沒過就往下做會把錯誤身分固化進每個 repo),靠人記得不可靠,腳本把它變成 STOP gate;
  ②**手貼的迴圈會漏**——那段只掃 `origin`,而實跑工作 mac 時 biz-chat/pilot-api 各有一條指向
  github-work 的 `fork` remote,照抄就在「看起來已遷完」之後留兩顆未爆彈。另有 12 台要跑同一件事。
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

## 2026-08-09 歸檔批次（xref gate 機制 + key 命名）

> 機制皆已固化：xref gate 三條在 `tests/xref-gate.py` 與 `CLAUDE.md`「測試」節（該節已逐條重述判準與理由），
> key 命名在 `ssh/config` 與 `CLAUDE.md`「SSH 配置」節。此處保存的是當初的取捨過程。

- **2026-08-08 source 與 target 的「非正文」排除規則刻意不對稱**(反直覺,故記):
  source 抽取**排 fenced、掃 HTML comment**;target 的 heading/body **兩者皆排除**。
  理由是兩端問的問題不同——source 問「這是不是一條治理指標」(圍欄內是示範怎麼寫,
  註解裡卻是真的要你去看,krepo 的量體豁免指標就寫在檔首 comment);target 問「該節是否真的存在」
  (註解掉的模板與圍欄裡的範例標題都不構成存在證據,放行即假綠)。四條 fixture 各自釘住一個方向。
- **2026-08-08 gate 的 pattern 分不出「使用」與「提及」,處置是改寫而非放寬**:討論一條(尤其
  壞掉的)引用時,寫法與真指標一模一樣——實地:把死指標當例子寫進 STATUS.md 的 spec,gate 當場
  咬自己。兩條出路:放進 code fence(source 端排除),或在路徑與引號間插字。
  **不為此放寬 pattern**——能區分兩者的唯一訊號就是 fence,放寬會讓真指標從縫隙漏掉。
- **2026-08-08 兩處判準在實作時比計畫收斂得更準,都是因為先量了存量**:①純基名原訂「一律
  blocking」,實測發現 `ready4quit/evals.md` 引用同目錄 `SKILL.md` 是合法寫法,改為「引用檔目錄
  與 root 都解析不到才 blocking」,並**不做全 repo 同名搜尋**(repo 內兩份 `reviewer-brief.md`
  是刻意隔離的兩套判準,模糊搜尋會指到錯的那份而毫無警訊);②append-only 章節限**完整章節名**
  (允許括號/冒號後綴)而非寬鬆子字串,否則「## 為何不使用 Change Log」這類討論性章節會被判紅
  ——gate 誤報的代價是逼人改壞寫法以求過測。
- **2026-08-08 key 檔名要反映**所有**角色,不只最顯眼那個**:原提議把個人 key 改叫 `id_github_me`
  (對稱於 Host `github-me`),使用者指出它同時是各主機 `authorized_keys` 的 fallback 私鑰,
  故定為 `id_personal`。**判準:命名跟著角色集合走,不跟著最常用的那個場景走**——叫 `id_github_*`
  會讓後來的人以為「不用 GitHub 就能刪」,而那把 key 是 CA cert 失效時進遠端機器的唯一後路。
- **2026-08-09 錨點 sha 判準用 canonical OID 比對,不硬編雜湊長度**:判準是
  `rev-parse --verify "<sha>^{commit}"` 的解析結果 == 記錄值。**不寫 40 hex** ——SHA-256 repo 的
  OID 是 64 hex(實測),寫死會錯殺整個 sha256 repo;而這個判準同時擋掉 `HEAD`／branch 名／短 sha
  且與演算法無關。副作用是收緊(手寫短 sha 的舊檔變 BAD-ANCHOR):查過實檔 55 份 76 條錨點全是
  完整 sha,production 零衝擊,故接受。
- **2026-08-09 handoff 的 frontmatter `slug:` 是否決權、不是索引**:第三方審查建議「查 frontmatter
  slug 也應命中」,但那是行為變更——既有斷言明文釘住「手改過的殘檔不得被撿」。改以 frontmatter 為
  身分的話,survey 會宣傳一條 `find-predecessor` 拒絕採用的工作線,兩個消費端對同一份檔案給出相反
  答案。改採「以檔名歸戶 + 標註不可達」:不動已釘住的語意,又把隱形殘檔變可見。**正反兩面都要有
  斷言**——只釘一面的話,改用 frontmatter 當索引照樣全綠。
- **2026-08-09 不強制 handoff resume 呼叫 `branch-first.sh`**:resume 開工的正解是 `git switch -c`
  (情況 A),該腳本的價值在情況 B 的救援序列;強制呼叫等於把 ship pipeline 的一角搬進 handoff。
  R4 只留一行 branch 紀律 + 指標,約束力由 H6 新增的 oracle 擔任(首跑實測 commit 落在 main、
  同輪 repo-b 卻開了 branch——行為分歧就是加這條 oracle 的證據)。
- **2026-08-08 跨機隊的破壞性收尾,要把前提檢查放進每台自己的執行裡**:刪 14 台的舊 key 時,
  每台先自檢「config 指向新檔名／新檔存在／兩個身分認得對」三道,任一不成立即跳過該台、
  零刪除。**判準:前提由執行端當場驗,不由發起端事先假設**——發起端的「我剛剛驗過了」
  在並行散佈裡是舊資訊。形狀同 `cleanup-stale-branch.sh` 的執行當下重驗。
- **2026-08-09 OpenWiki 只配 derived 層,且 dotfiles 不當第一試點**:它產的是「從 code/git 可推導」
  的 repo 地圖,與 dossier 明文不記的東西正交,架構上不衝突。不選 dotfiles 的理由是三條摩擦在此
  同時發作:①官方 workflow 的 staged 範圍含 `CLAUDE.md` 與 **workflow 檔自己**;②幾百頁 LLM 改寫版
  稀釋「唯一權威」不變式,而最易被摘壞的正是帶反面教訓的地雷條——LLM 只看得到「這裡用了 herestring」,
  推不出「為什麼不能寫另一種」;③`.openwikiignore` **只擋讀取、不保證主題不被提及**(README 自陳,
  agent 仍能從 tests／commit message 反推),對帶內網 inventory 的 repo 它不是保密邊界。
  **採用與否未拍板**,本條記的是邊界。
- **2026-08-09 契約分兩層:safety floor 不可放寬,fallback conventions 由 repo 勝出**:外部 repo
  可能要求 `JIRA-123:` 或 gitmoji(與 Conventional Commits **互斥**,不是更嚴或更鬆),也可能沒有
  決策存放處。**分界判準:錯了會產出什麼**——多開一條本地 branch 完全可逆;用錯 commit 格式則
  直接產出必須重寫的東西。
- **2026-08-09 kernel 用三份逐字複本 + identity gate,不用純指標**:純指標**已被 H6 證偽**
  (換個名字仍是延遲載入,且 repo 沒契約時全域完全空手),三份都必須自足,故改用機械手段擋漂移
  ——形狀同 `tests/xref-gate.py` 把「唯一權威」從散文換成 gate。**代價明記**:`tests/run.sh` 只跑
  本 repo,裝到其他 repo 的複本沒有守門,與 2026-08-08 那條不對稱同型。
- **2026-08-09 判斷一條部署路徑夠不夠,看它涵蓋的機器集合,不是看它跑幾次**:`~/.ssh/config` 的重生
  原本有四份行內複本,卻全掛在 dotsync 與 setup ——兩部個人 MacBook 因此永遠拿不到更新,實地後果
  是 2026-08-08 全機隊身分收斂它們完全沒跟上,**而且從外面看不出來**。下沉為 `ensure-ssh-config.sh`
  並接進 `brewup` 後,任何機器跑過 brewup 就自己跟上。
- **2026-08-09 把重生自動化,就必須同時擋住「拿可用的換成壞的」**:自動重生會讓 key 檔名落後的機器
  在第一次 brewup 把可用的舊 config 換成指向不存在的 key → 認證斷掉,**而修正要靠 GitHub 拉回來**
  (散佈紀律①的新形態)。故替換前檢查新 config 指到的 key 是否存在,**判準收窄成「新的缺席且舊的
  還在」**——全新機器不受影響,否則 setup 首跑被自己擋住。**這種順序陷阱要由腳本擋,寫散文不夠。**
- **2026-08-09 通用契約不得只活在延遲載入的檔案裡**:branch-first 原本只在 `ship-paths.md`,
  全域檔僅側面提及「不得放寬」→ 不載入 `/project` 就沒有這條規則,H6 首跑即實測 commit 落在 main。
  **判準:規則的生效範圍不能小於它要防的失敗範圍**;per-skill 補丁蓋系統性缺口,只會讓下一個
  未覆蓋的路徑再踩一次。修法是 promotion + dedup,淨變動 +1 行。
- **2026-08-09 自我更新的部署腳本要 exec 重跑,不能只在文件寫「記得跑兩次」**:`brewup.sh` 在自己
  內部 pull,但**執行中的 bash 跑完的是舊版**(git 是 unlink+新建,舊 inode 存活)——本次更新才加進
  pull 後段的動作因此延後一個週期、無聲,`allup` 會讓它在整個機隊同時發生。使用者在落後的 MacBook
  上實地撞到(要跑兩次才部署到 helper)。修法是比對自身 checksum + `exec` 重跑 + 環境變數迴圈防護。
  **判準:凡「更新自己」的腳本,一輪之內就要收斂,不能把收斂責任丟給呼叫者的記憶。**
- **2026-08-10 契約 kernel 必須落在自動載入的檔案裡**:G1b 實測 root `CLAUDE.md` **會**被自動載入、
  root `AGENTS.md` **不會**(後者只在 agent 剛好探索 repo 時被 `cat` 到)。已就地套用:root
  `CLAUDE.md` 成為第四份逐字複本。Codex 端不受影響(原生讀 `AGENTS.md`)。逐項數據與 clean-room
  構造見 `claude/evals/contract-evals.md`「G1b — root `AGENTS.md` 是否被自動載入」。

## 2026-08-10 歸檔批次之二（兩條已失效決策 + 三條已固化 + 一條已消缺口留下的教訓）

> 前四條的機制已固化在 `STATUS-template.md` / `docs/transfer.md` / `tests/xref-gate.py`，
> 從產出物即可反推；**兩條 `~~刪除線~~` 的保存價值全在「當初為什麼這樣決定、又為什麼同日
> 被推翻」**——那部分永遠無法從 diff 反推。最後一條原屬「已知缺口」節，缺口本身已消、
> 留下的是方法論教訓，故隨決策一起歸檔而非留在 always-on。

- **2026-08-09 接手首屏由 `docs/transfer.md` 承擔,不動 STATUS.md 的 schema**:survey 建議在 dossier
  加固定 schema 的接手快照,但那必然與「進行中」雙重記載(它自己也提了這個疑慮),違反傘狀蒸餾規則。
  `docs/transfer.md` 本就為接手者而寫、移交前才生成、不常駐,故不會腐爛;STATUS.md 是常駐演化檔,
  加一塊只在移交時有意義的區塊,等於替它增一塊固定會過期的面積。
- ~~**2026-08-09 不現在把 `CLAUDE.md` 拆成「工具中立入口 + Claude 薄層」——先 eval,後搬遷**:
  survey 的終態圖把它降為薄層,但檔內最值錢的是「已知地雷」那批,每條對應一次實地事故,屬硬約束
  而非可按形狀搬動的敘述。**在 clean-room eval 量到「Codex 端因缺 repo 規則而犯錯」之前不動**
  ——為文件形狀而改,正是該 survey 自己反對的完成標準。~~
  **已失效(2026-08-09,同日)**:門檻找錯地方——洞在 Claude 端一樣存在且早有 RED(H6),不必等
  clean-room eval(該 eval 仍未跑,照實記)。現行決策與完整理由見
  `docs/plans/2026-08-09-repo-contract-extraction.md`「生效模型（兩輪 P0 的裁決，先讀這節）」。
- **2026-08-10 模板可攜性判準「規範本身在此、不在工具」;死指標的危害是「往下傳」不是「卡住」**:
  形狀取自 krepo 現場自行收斂的檔頭(兩次獨立手動偏離)。G7 乾淨重跑(Sonnet)baseline **1/2 失敗**
  ——agent 沒去讀死指標,卻把它**原樣轉述給接手者**,教對方去查一個打不開的路徑;修後 2/2 乾淨。
  第三版 fixture 重跑同結果,但**失敗落點改成 agent 的 memory 筆記**——比落在回覆更糟,它會在
  往後每個 session 被 recall。⚠️ 本條同日修正三次(fixture 兩度作廢),數據與作廢理由見
  `claude/evals/contract-evals.md`「G7 — 移交後接手者能否維護 dossier（2026-08-10，已跑）」。
- ~~**2026-08-10 branch-first 是 Claude Code 產品原生的,輕量 fixture 量不到 kernel 的邊際效果**~~
  **已失效(2026-08-10,同日)**:那是 Opus 專屬觀察。樓層模型 Sonnet 上同一 fixture,clean 臂
  **2/2 直接 commit 到 main**、rules 臂 2/2 另開 branch——**kernel 就是 branch 有沒有被開出來的
  唯一原因**;連帶作廢「對 Claude 邊際價值有限」那句推論。判準本身(強模型兩臂沒差 ≠ 規則多餘)
  已沉為通則,見 `claude/evals/README.md`「模型樓層政策」。
- **2026-08-08 xref gate 只保障 dotfiles,但它服務的規範是全域的——這個不對稱要講明**:
  `tests/run.sh` 只跑本 repo,故「唯一權威」指標的機械守門僅及於 dotfiles;而同批改的
  `ship-state.sh`(append-only 偵測)與 dossier 規範(失效標記)**跨 repo 生效**。
  故不得說「其他 repo 零影響」(它們未來的 `/project log` 行為確實變了),也不得說
  「失效標記已有守門」(其他 repo 的指標沒人掃)。**不擴大到 `ship-state.sh --repo` 的理由**:
  其他 repo 的引用可能指向 repo 外(如 `~/Projects/...`),需要另一套外部路徑政策;
  規範已要求指標寫成 gate 可解析的形狀,將來擴大時零回填。
- **缺口條目寫「解法已知、剩移植」時,那句本身也要有人去核對一次**——它讀起來像查證過的結論,
  實際上常是當時的推測,而後來的人會直接照做。2026-08-07 實例(deep-review anchor 跨批次 stale)
  核實後發現守門早就在、且照定義擋不到該風險,真正兜住的是另一個機制。**該缺口已消,留這條教訓。**

## 死路(試過但放棄——防重工)



## 已結案技術債（2026-08-10 歸檔）

> 從 `STATUS.md`「技術債」節歸檔——**已結案的債不再影響現行排序**，機制已固化在
> tests / 腳本 / skill 裡、從程式碼可反推。結案時留下的兩條判準仍在 STATUS.md 為 live。

- [x] G 系列 eval 樓層補齊——2026-08-10 G1a/G1b/G2/G4/G4b/G6/G7 **全數在 Sonnet 重跑**,
  fixture 一併腳本化(`make_g1b`/`make_g1a`/`make_g4`/`make_g4b`)。**不是例行迴歸**:推翻一條
  決策(見決策節)、掀出一條新缺口(見缺口節)
- [x] dossier 訊號 R5 non-blocking 五項——2026-08-08 全數修畢(細節在 tests,可反推)
- [x] hook matcher 僅 `startup`——2026-08-07 已擴為 `startup|clear|compact|resume`,tests 第 16 節覆蓋
- [x] 測試節那行待補 git-hygiene 的新教訓——2026-08-07 已補。留一條:**目標檔是 repo 根的
  `CLAUDE.md`**,不是 `claude/CLAUDE.md`(後者的測試節講的是「何時該寫測試」)
- [x] `claude/evals/*.sh` 已於 2026-08-08 納入全部四個 gate,納入時零 findings——
  **便宜的守門要趁乾淨時加**,等它長歪再加就得先還債

- **2026-08-10「進行中含 ✅」flag 收窄到條目形狀(list item)**:krepo 連三次 ship 被同一張盤點表
  誤報(那是子項狀態欄)。**兩個候選各被實地反例否決**:「整張表全 ✅ 才算做完」——那張表本就 4 列
  全綠;「續行併入所屬條目」——表格前更早處仍有 bullet,寬續行模型照樣收回來。**刻意放棄**:續行 ✅
  與表格式待辦不再亮。判準註解與六條 fixture 是權威。
- **2026-08-10 模板只帶「做錯會壞掉」的生命週期規則**:模板帶走了結構(節名+每節放什麼),沒帶走
  生命週期規則——盤點 `references/dossier.md`(私有、不隨 repo 走)發現同類共 6 條缺席。**補 3 條**
  (完成即移入里程碑、死路不刪、不得加 append-only log;各有實地事故),**排除**總量門檻/事件當下
  記錄/stale 比沒有更糟——後者是「做了比較好」,而模板刻意壓短。⚠️ **排除是刻意的,下輪審查再提
  不是新發現。** 附帶:pattern gate 只抓列舉過的東西,綁外部生態的耦合(`.env.example`)掃不到。
- **2026-08-10 installer 不得只寫 pointer,必須把 kernel block 本體裝進目標 repo 的 `CLAUDE.md`**
  (推翻計畫的 P0-2 樂觀分支)。理由見上一條:pointer 即使在自動載入的檔案裡,也只是「告訴你契約在
  別處」,瑣碎任務照樣不會去讀它指向的檔。代價是**每個安裝過的 repo 都多一份無機械守門的複本**
  (`tests/run.sh` 只跑本 repo),與 2026-08-08 xref gate 那條不對稱同型。
- **2026-08-09 本輪範圍界線:無 RED 者一律 DEFER 並記觸發條件**(防下一個 session 的對抗式 review
  原樣再提一次):①`transfer onboard` 子形狀 → 等第一個真實協作者(**已存在的模板比空白頁更容易被
  照填**,會鎖死第一次真實情境的形狀);②`contract-flag:` 訊號 → 等「缺契約沒人發現」的實例;
  ③skill 可攜化 → 等真實需求;④全域檔與契約 Working discipline 的措辭重複 → 等實測到行為分歧。
- **2026-08-09 handoff 的跨主機 docs commit 與 ready4quit「一律不 commit」刻意相反**:前者是跨機
  唯一媒介(不 commit 就沒有管道),後者是 pre-quit 純驗證(commit 權責屬 `/project log`)。兩者都對
  但沒互相標註,下次審查易報成不一致,故記於此。**刻意不寫進 SKILL.md body**——不是觀察到的 agent
  失敗,違反 `No failing scenario, no instruction`,只會替每次載入加 token。
- **2026-08-08 散佈憑證變更的三條紀律**(全機隊改 SSH 身分與 key 檔名時實地得出):
  ①**`cp` 不 `mv`**——新舊並存,任一步失敗都不斷線;遠端拉 dotfiles 靠的正是 GitHub SSH,
  認證改壞又散佈出去就拉不到修正,只剩 `ssh <host>`(內網 CA cert)進去手改。
  ②**散佈前提是變更已進 `origin/main`**——遠端 `dotsync` 拉的是 main,本地 branch 未 push
  時散佈等於空轉(實地踩過一次,以為散完了其實什麼都沒變)。
  ③**先散一台走完全程再放其餘**——挑最有代表性的那台(這次是 db01:remote 最多、唯一有
  `insteadOf`、且有 krepo 可驗依賴路徑),不是挑最安全的。

<!-- 2026-08-14 歸檔:契約層拆檔那一批。機制已固化在 xref-gate／kernel-gate／AGENTS.md,
     從程式碼可反推;此處留的是當初為什麼這樣分流。 -->

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
- **2026-08-10 `codex/AGENTS.md` 的改名方案 DROP,同名實害就這樣接受**(2026-08-14 從
  STATUS.md「已知缺口」歸檔,該處只留一行現象)。它與 root `AGENTS.md` 同名不同角色——前者是
  全域 Codex 指引的**來源檔**(由 `ensure-codex-guidance.sh` 部署),後者是 repo-resident 契約,
  正是 `claude/skills/project/references/dossier.md`「1. 檔案角色分工」的 Naming is exclusive
  擋的形狀。實害:`codex/skills/repo-review/scripts/review-context.sh` 沿改動路徑逐層收
  `AGENTS.md`,改 `codex/**` 時兩份都被當 guidance 餵進 reviewer(重複但無害)。**不改名的理由**:
  Codex 不進生產線,價值近零而代價是全機隊 symlink 風險。契約層本身的缺口已由 Phase 1–2 補上。

<!-- 2026-08-14 歸檔:G8 那批 shipping 授權決策。機制已固化在四份 kernel 複本、
     kernel-gate.py 與 G8 eval,從程式碼與 evals 可反推;此處留當初為什麼這樣分流。 -->

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

<!-- 2026-08-14 歸檔:條目 flag 那兩修。機制已固化在 ship-state.sh 的實作與註解、
     tests/run.sh 第 9 節、docs/testing-contract.md,從程式碼可反推;此處留當初的失效形狀。 -->

- **2026-08-14 條目 flag 邊界止於非續行區塊**(行首 blockquote／標題／分隔線;機制與實證見
  `ship-state.sh` 該處註解與 `tests/run.sh` 第 9 節)。**值得記的是失效的形狀**:被誤併的
  524B 是**歸檔指標**——收斂做對之後才會產生的東西,於是**做對事反被判超標**,而處置指引
  「涵蓋多個決策→拆成多條」對它無效(它本來就是一條)。修後十個 repo 只有出問題的那個變
  (804→722)、其餘差 0:**精準修復,不是放寬門檻**。
- **2026-08-14 條目 flag 補上建議收斂目標(680)**。`DOSSIER_TARGET_PCT` 原本只套在全檔 flag、
  條目漏了,於是每次都壓到剛好過關(五個 repo 的最大條目落在 798/788/784/778/725,聚在上限
  下緣不是巧合)。理由與全檔 flag 同,見該常數註解。

<!-- 2026-08-15 歸檔:PR #98 那批(收斂順序＋歸檔孤兒)。已落地並散佈全機隊,
     機制固化在 ship-state.sh、tests/run.sh 第 9 節、docs/testing-contract.md。 -->

- **2026-08-14 全檔 flag 帶收斂順序:①砍重複 ②歸檔留指標 ③最後才蒸餾**。舊文字把最不可逆的
  手段排在第一,與規範的「超標時優先歸檔」相反,而**只有 flag 會在動手當下被讀到**。判準是
  危險不對稱:歸檔可取回,蒸餾砍掉的是理由與實測數字。
- **2026-08-14 加歸檔孤兒偵測(反向守門)**:既有 xref-gate 只驗正向,「歸檔出去後沒人連」從沒
  查過——那正是靜默內容遺失的主要途徑(實測 evint 6/10、krepo 9/29)。只印訊號、絕不自動刪。
- **2026-08-14 hook 用宣告式部署(`git/config` 一行),不寫 ensure helper**。原以為
  `core.hooksPath` 的 `~` 不展開,**實測會**(git 2.50.1／機隊 2.55.0),而該檔已由 setup 以
  `include.path` 掛在全機隊 → 改一行、下次 pull 即生效,省掉 helper＋dotfiles-sync 兩處掛載＋
  一整節測試。⚠️ **代價是它取代整個 hook 目錄**——必須寫成 dispatcher 代理全部 client-side
  hook 名,否則 repo 自己的 LFS hook 會靜默失效;邊界與判準見 `docs/testing-contract.md`
  「24. `.githooks/dispatcher`(全域 core.hooksPath 的單一入口)」。
- **2026-08-14 guard 的 fail-open 用三態 exit code,不用 `set -u`**。實測 `set -u` 遇未綁定變數
  會 `exit 1` ——那是 fail-**closed**,正好相反,而 hook 自己出錯就會擋掉全機隊所有 commit。
  改成 guard 跑 subshell、約定 exit 97 才擋,其餘非零一律放行。**語法錯誤與 interpreter 缺失
  本質上無法 fail-open**,只能靠四道 gate。
- **2026-08-05「用 `--admin`」不收進說法表**(2026-08-15 歸檔:說法表本身＋CLAUDE.md kernel 的
  「NEVER extend it with synonyms of your own」已是 always-on 的保護,此處只剩「為什麼」)。它語意上
  比 `bypass merge` 更明確,但**「不自行擴充等價詞」正是說法表擋 rationalization 的機制**,收進去等於
  承認自然語言等價詞。設計 S15 eval 時撞到:施壓句「加個 `--admin` 就過了」會把授權塞進施壓句、
  正確答案自己變歧義。現行＝不接受,要求使用者改說 bypass merge。**無實地案例前不動。**
- **2026-08-11 驗證「重排後內容零遺失」只有 token 級檢查有效**(2026-08-15 歸檔:方法已用過兩批、
  結論穩定,要做搬遷驗證時查這裡即可)。滑動窗口(剝非中文後比對)與語意片段(按標點切)兩種都被
  重排大量假陽性淹沒——前者把原本被英文分隔的中文黏成原文不存在的串(**與 xref-gate 檔頭警告的
  「整檔併成一串」同源,只是反過來造成假遺失**),後者對「含→涵蓋」「逗號→分號」這類改寫全數判缺。
  有效的是抽 `code` 識別字與日期逐一比對(99/99、3/3)。下次做搬遷驗證直接用 token 級,別再繞前兩種。
- **2026-08-11 同型掃描的 R5 終止路徑刻意不設 behavior eval**(2026-08-15 歸檔:已由 `tests/run.sh`
  第 1f 節的靜態 gate 固化)。比照 d7 預造假 fix commit 的話,受測 agent 沒真做過那幾輪修復、
  **填不出自己沒做過的處置**,測到的會是 fixture 缺陷而非 skill 行為。該 gate 只驗結構,不驗內容誠實度。
- **2026-08-08 buried 的 review 痕跡不實作自動壓平**(2026-08-15 歸檔:不變式「壓得掉的一律壓」
  已固化在 `project/SKILL.md` Step 1 第 6 項的處置表與 `ship-state.sh` 的 `review-residue:` 三態)。
  夾在語意 commit 中間時 `reset --soft` 碰不到;`rebase -i` 配 `GIT_SEQUENCE_EDITOR` 完全非互動、
  每顆 buried 標 `fixup` 折進前一顆語意 commit 即可、衝突為零是結構保證,**做得到但沒做**——代價是
  語意 commit 的 hash 與內容都會變、「squash 絕不動語意 commit」從結構保證退成測試保證、多一條
  rebase 回滾路徑、branch 首顆是 buried 時無目標;而實測多為 none/top-contiguous。

- **2026-08-16 `autoMode.environment` 以權威機器身分固定**。`/auto-mode-setup` 把它寫進
  `~/.claude/settings.json`,而該檔是指向本 repo 的 symlink——於是它直接落在 working tree
  成為 drift,下次 `brewup` 的 `git checkout -- claude/settings.json` 便把它丟掉,setup
  因此重複詢問(同一台機器被問兩次)。commit 讓它隨 pull 散佈全機隊。
- **2026-08-16 repo-scoped 三行當天就改回動態措辭,推翻同日稍早「刻意不改」的判斷**。原判斷
  是「偏差方向保守、非危險方向,故不阻擋送出」;`claude auto-mode critique` 推翻它——寫死 repo
  會讓其他 repo 的 origin 掉出 trust boundary(routine push 被當 Data Exfiltration 判),且預設的
  `Repository visibility` 本是**決策程序**(assume private unless…),被單一 repo 事實換掉後其他
  repo 連 fallback 都沒有。**判準修正:「偏差方向保守」不構成留著的理由**——保守的代價就是每次
  操作都被問,而那正是 auto mode 要消除的東西。
- **2026-08-16 `autoMode` 各段是取代語意,`allow` 用 `$defaults` sentinel 繼承內建**。實測:直接
  自訂一條 allow → `config` 的 allow 從 17 掉到 1,`Read-Only Operations`／`Git Push Destination`
  等核心豁免全被踢掉、**零警告**,結果比不設定還麻煩。正解是把字面字串 `"$defaults"` 放在陣列
  首位——實測展開後與內建 17 條**逐字相符**,升版自動跟上、不必存複本。⚠️ **`environment` 不適用**:
  同樣放 `$defaults` 是**純附加、不覆寫**,實測出現兩行 `**Trusted repo**:` 且內容互斥,故它只能
  全量寫出就地改(這正是 `/auto-mode-setup` 把每個 slot 含 `None configured` 都列出的原因)。
- **2026-08-16 fleet wrappers 依風險分兩條路,不全塞 classifier**。`permissions.allow` 命中的規則
  在 auto mode 下**直接放行、不進 classifier**(零 token);原始碼判準:規則被停用只有三種情形——
  `classifyAllShell=true`(預設 false)、全域 wildcard、或規則涵蓋 26 個危險命令(`python*`/`node`/
  `bash`/`sh`/`ssh`/`eval`/`exec`/`env`/`xargs`/`sudo`…)。故 `tmuxls`(唯讀)、`brewup`(本機)進
  `permissions.allow`;`dotsync`／`allup` **留在 autoMode 規則**——比對只看規則字串,`Bash(dotsync)`
  不命中 `ssh` 卻會把它內部的 fan-out 一併放行,而 classifier 規則才表達得了「腳本本 session 被
  改過就不適用」這種條件。**省 token 與可表達的條件是對價關係**,按風險挑邊。
- **2026-08-15 `BLOCKED` 的成因判準吃 `gh pr checks --required` 的 exit code**(0 全綠／8 pending／
  其他非零 失敗;否決 `statusCheckRollup` 計數的理由見死路節)。`mergeStateStatus: BLOCKED` 聚合三種
  成因(CI 還在跑／required check 失敗／protection 真的擋),**正解相反**,而舊分流表一律解成第三種
  → 把「再等 90 秒就會自己消失」的阻塞誤診成權限問題並導向 `--admin`(＝讓沒跑完測試的變更進
  default)。krepo PR #127 實地踩到、#129 二度發生;#129 那輪答對是 agent **自行繞過分流表**多查
  一步——**正解可推導卻沒被編碼**,那正是要寫進去的理由。
- **2026-08-15 等 CI 刻意不封頂**(同批)。`gh pr checks --watch` 跑到 check 收斂為止,agent 全程
  在場、使用者隨時可中斷即是上限。**不封頂是兩害相權**:macOS 無 `timeout`/`gtimeout`,包一層就是
  exit 127——整段沒跑卻回一個看起來像通過的碼,比不封頂更糟。
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

- **2026-08-17 `planner-brief.md` 進 prompt 標為待驗 → 2026-08-18 成對實驗判定「保留」**。
  E2 實測(Sonnet,A/B 各 2 次):阻斷級 findings 兩臂**零差異**——樓層模型自己就抓得到最嚴重那條;
  但 5.7／5.5／5.4 三條 A 臂 5.5/6、B 臂 **0/6**。⇒ **brief 買到的是覆蓋面,不是核心 finding**。
  ⚠️ 首跑因 fixture 給 5.7 留了旁路而作廢,判準在重跑前寫死;矩陣與嚴重度刻度的附帶發現見該
  skill 的 evals.md。

- **2026-08-17 非 canonical remote 的殘留只列訊號、不發刪除指令**。病灶:候選來自 `branch -r`
  (列**所有** remote)、組 cleanup-cmd 卻只剝 canonical 前綴 → `fork/x` 傳給只認 canonical 的
  `cleanup-stale-branch.sh`,永遠 `verdict: STOP`。**否決「把 remote 一起傳過去」**:它把「刪別人
  repo 上的 branch」變成可照抄的一行,與 SKILL remote 假設(不擅自對 fork 動作)衝突;實地
  (pilot-api 5 支殘留全在同事 fork、一支還是那 repo 的 `main`)採用的是 `git remote remove fork`
  ——那個能力方向本身就是錯的。**否決「不列入偵測」**:會丟掉使用者確實想要的訊號。

- **2026-08-17 foreign 訊號另立一段,不在 stale/squash 兩段各留分支**。那些 ref 屬於另一個 repo,
  「是否已併入我的 default」不構成處置依據;集中也避免訊號分裂——同批發現 squash 段的
  `${remotes_un//origin\//}` 是**全域替換**且對 `fork/x` 無效,帶前綴的名字在 `$2 == b` 比對就
  `continue`,實測(owner 相同、SHA 相符、條件全齊)**整段不印、連 `skipped:` 都沒有**,是靜默漏報
  而非「被 owner 檢查擋住」。

<!-- 2026-08-19 歸檔:deep-plan／deep-review 的實驗結論七條。機制已固化在
     claude/skills/deep-plan/(SKILL.md、evals.md、field-log.md)與 deep-review/evals.md,
     STATUS.md「進行中」也已寫明「結論散在決策節與該 skill 的 evals.md／field-log.md,
     此處不重述」。此處保存的是當初的實驗數據與被否決的路。 -->

## deep-plan／deep-review 實驗結論(2026-08-17～08-18)

- **2026-08-17 `deep-plan` 用「並行 N 個 fresh reviewer」,否決「一個 reviewer 迭代多輪」**。
  這不是採樣次數的取捨,是避開一個實地量到的失效:**同一 session 連續審修訂版本會累積正當化**。
  實地(krepo 孤兒告警計畫)——該 reviewer 第一、二輪都指出「這類 finding 移到 deferred 後不會發
  通知」,接著接受作者「跟既有 pre-listing 豁免一致」的類比,**最後一輪還建議加測試把那個行為釘死**;
  同一份計畫給兩個 fresh reviewer,兩個都在第一條 finding 判它阻斷。
- **2026-08-17 由「累積正當化」推出 `deep-plan` 的兩條 body 規則**(承上條)。每輪都有作者的解釋在旁,
  疑慮被回應一次、被類比一次就鬆一次 ⇒ ①**NEVER resume reviewer**:fresh context 是機制、不是優化
  (與 deep-review「不把上輪 findings 傳給 subagent」同形狀但**理由不同**——那裡防洩題,這裡防立場
  累積);②作者的解釋**絕不進 reviewer prompt**,那是傳染途徑。⚠️ 已知未封的殘留管道:「接受為
  trade-off」寫進 dossier 後,第二輪 reviewer 依 brief §4.4 會主動去讀它(2026-08-17 review 抓到,
  待處置)。
- **2026-08-17 `deep-plan` 不把 reviewer 的 verdict 當通過條件**。實地六次獨立審查有**三次**給了
  「修完這幾條就可以執行」的條件式 approve,而那三張 green light 全都會放行同一條阻斷級缺陷
  (一整類個體從此永久靜默)。**挖得淺的 reviewer 也會給條件式 approve,外觀與挖到底的完全一樣。**
  ⇒ 通過判定改看 findings 的處置狀態(修/駁+理由/接受+dossier 落點)與第二輪結果。**否決「用
  verdict 三態當 exit criteria」**——那正是被證偽的那個訊號。
- **2026-08-18 `/deep-review` 判 blocking 的五條裡,只有兩條進了 body**。逐條跑 TDD 後:
  **B2／B3 在 Sonnet 上真的紅** → 修;**B1／B4／B5 兩次以上實測皆未紅** → **不加規則**,只修
  「原文說錯或說不清」的部分。三條的不紅理由**各不相同、別混成一條**(B1 樓層模型自己先定目標
  repo;B4 它自己就只寫取捨事實;**B5 是既有全域 kernel 接住的**),逐字說詞在該 skill 的 `evals.md`。
  **判準**:診斷判 blocking 是「值得查」、不是「該進 body」;**「實地出過事」不等於「fixture 紅得起來」**。
  ⚠️ 這批踩出兩條 fixture 旁路,**都是補一個沒有旁路的臂之後才敢下結論**。
- **2026-08-18 E1／E3 跑完:N 的預設維持 2、2 輪上限維持**,但理由**不是判準說了算**。
  E1(4 個 i.i.d. reviewer,巢狀子集算 N=1..4):阻斷級聯集 N=2→5.00、N=3→6.00 ⇒ 判準的
  「沒有新增就維持 2」**條件不成立**,而它沒定義有新增時該調到多少 ⇒ **不自行改預設**。
  多出來的**全是嚴重度分歧、不是新問題**(核心那條 4/4 全中且判阻斷,四臂結論一致)。
  E3:第一輪 9 條**零重述**;(b)處置引入 3 條 >(c)沒挖到的 2 條 ⇒ 上限合理。⚠️ 唯一阻斷
  落在 (c),而判準要求「(c) 佔多數**且**含阻斷」——**這格判準沒定義,不事後補**。
- **2026-08-18 P4 的 fixture 死於「計畫沒被 commit 成檔案」,而那條規則現在已經在了**。
  兩半都沒了:計畫原文從未落成檔案(session 已逝),repo 也已 merge 且缺陷在落地前就修掉
  (修法還明文寫進 commit message)。**否決「拿現況重建」**——會製造 dp1 v1 那個旁路
  (答案寫在 fixture 裡就量不到);**否決「重寫一份等價計畫」**——重寫的人知道答案,會磨掉難點。
  ⇒ 改 standing recipe。根因是當時沒有「計畫落成檔案」這條規則,Step 0 現在強制它、落點是
  **目標 repo**,照現行 SOP 跑 artifact 自然存在。⚠️ 登記時 hash 取**第一輪當下**那顆。
- **2026-08-18 §6 的子類檢查不是一次性的**(E3 第二輪的實質產出)。第一輪把「一格混了兩種子類」
  修在 kind 層,第二輪 2/2 重疊指出**限縮後的那一格自己也可能是混的**(純等待裡還有「永久不會
  回來」的第三類),reviewer 逐字:「同一種問題換個位置重新出現」。⇒ **每收窄一次判準,新的那一格
  都要重問一次同樣的問題**——這是第一輪的抽樣(不論 N 多大)到不了的,它要先有那個處置才存在。

## 事件記錄（event-time）

- **D-20260820-pilot-before-architecture · ** **2026-08-20 分片計畫四版全部不通過,退回「pilot 設計」**。四輪第三方審查、**29 條 findings、25 條
  真陽性**,而**沒有一條打中診斷**(「無界內容放進有上限的檔」四輪皆未被質疑)——全部落在
  **在沒有量測的情況下反覆選架構**:v1 時間分片(歸因被推翻)→v2 加死路(800B 上限與「不刪」自我
  抵銷)→v3 縮範圍(只買 31 天)→v4 event log(過早選定,且漏評「一 record 一檔＋Git history」)。
  ⇒ 產出改為四臂 pilot 設計,見 `docs/plans/2026-08-20-dossier-governance-problem-v5.md`。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260820-eval-fixtures-use-tags · ** **2026-08-20 eval fixture 的永久錨點一律用 annotated tag,不用 branch**。為保存而 push branch
  **會被 merge 收尾自己抵消**——標準動作就是刪 remote branch。實測:8/19 為登記 P4 而 push
  `docs/announcement-api-plan`,隔天計畫 merge 後 `fetch --prune` 直接印 `[deleted]`,當時若沒
  另打 tag,`5cf20c7` 已無任何 ref 包住、P4 會**第二次**死於同一死因。理由寫進 tag message
  (拿到該 repo 的人不必有 dotfiles 也讀得到),eval 的 setup 寫 `checkout <tag>` 而非 hash。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-rules-at-runtime · ** **2026-08-19 規則要放在「執行當下讀得到」的檔,不是放在記錄它的檔**。`deep-plan` 的 ship 提醒
  區塊與 P4 核對原本只寫在 `field-log.md`,而該檔**刻意不從 SKILL.md 連結** ⇒ 實地漏過一次
  (krepo-mops-announcement 的計畫在 field-log 建立**一小時後**執行,機制已存在卻讀不到)。
  已補進 SKILL.md 的 Step 3b／Step 6。**「runtime 不需要知道自己被記錄」對紀錄的內容成立,
  對「要附一個區塊」這個動作不成立**——後者是 runtime 必須執行的步驟。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-p4-fixture-threshold · ** **2026-08-19 P4 fixture 汰換驗證 FAIL,刻意不改用較寬的原始門檻**。第三方建議換成 dotfiles 內的
  `c567204`,跑前先登記判準「抓到且判阻斷」;結果 Sonnet A 抓到但判**高**、B 沒抓到 ⇒ 未達標,
  維持 `5cf20c7`。⚠️ 原始 krepo 版門檻其實是「阻斷**或高**」、是登記 announcement 那份時我收緊的
  ——**用原門檻 A 會過,但事後挑對自己有利的門檻正是這套紀律要防的事**。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-evidence-orphan-xref · ** **2026-08-19 分層證據檔的節級孤兒改由 `tests/xref-gate.py` 反向守門**,不放 ship-state.sh。
  歸檔孤兒的觸發條件是「檔案在 `docs/archive/`」,**放寬成檔級也恆綠**(STATUS.md 節頭提了
  檔名,整檔永遠有入邊)——失效只發生在節級。首掃 12 節中 **5 節孤兒**。三個刻意的邊界:
  ①**只在全 repo 掃描跑**(files 子集的 inbound 不完整,會把有人指的節報成孤兒);
  ②指到內文不算接上,要**指名節名**;③`claude/known-hazards.md` **不納入**(實測同樣 8/9
  無入邊,但它的慣例是單一檔級指標涵蓋全節,改逐節要動 always-on 檔——獨立決定)。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-dead-end-exit-modes · ** **2026-08-19 死路的兩種離場方式分開處置**:翻案 → 比照被推翻的決策(留原文+失效標記,
  證據節一併留);不再適用 → 兩邊同一次 commit 一起刪。⚠️ 同批量到**分層的 byte 效益是負的**
  ——四條移出約 1.5KB 證據、補回約 1.1KB 指標句,全檔淨 **+130**。分層買的是「證據有家、
  可機檢」,**不是空間**。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-deep-plan-use-criterion · ** **2026-08-19 `deep-plan` 的使用判準:看「會不會產生無法從 diff 反推的宣稱」**,不看 repo 或變更大小。
  首次真實執行的 3/9「會 ship 的缺陷」**全落在文件宣稱層、零條純程式碼**⇒ 值得跑的是 skill body／
  契約檔／`testing-contract.md`／共用 fixture 這類「寫錯一個為什麼、測試照樣全綠」的地方;`scripts/`
  的機械邏輯**測試就是 oracle**,事後 `/deep-review` 更便宜。⚠️ dotfiles 命中率系統性偏高(文件即產品)
  ——那是「在這裡該用」的理由,**不是外推到一般 repo 的理由**。逐次紀錄見
  `claude/skills/deep-plan/field-log.md`「累積結論」。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-no-single-round-deep-plan · ** **2026-08-19 撤回自己提的「deep-plan 小變更走單輪」**(零 diff,不記就消失)。E3(受控)與首次真實
  執行都量到**第二輪有第一輪拿不到的產出、含唯一阻斷級**;加上 E1 已證 N=2 是下限 ⇒ **4 次 reviewer
  執行是這個設計的地板,成本降不下來**,剩下唯一槓桿是模型層級(已記 backlog)。附帶看清第二輪的
  真實職能:它找到的多半不是原計畫的問題,**是處置新寫進去的論證**。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-handoff-active-mtime · ** **2026-08-19 handoff `active:` 清單的時戳取 mtime,而 `created:` 格式維持 date-only**。
  同日多份 active 只印 `0d` 完全平手(可重建的量測:80 份 archive 兩兩取 `[mtime, consume]` 交集,
  不同 slug 重疊窗 23 對、其中 created 同日 5 對)。**mtime 買到的只有同日的時分解析度**——
  `created` 並非「首次蓋錨點」而是**最後一次**(W2 每輪跑、W3 原樣貼入;81 份實測與 mtime 日期
  0 份不一致),所以改 created 帶時分那條路買不到東西,還要讓 `date_to_epoch` 多養一種格式。
  ⇒ created 與 EXPIRED 判定一律不動,mtime 只用於顯示與排序。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260819-handoff-no-ranking · ** **2026-08-19 撤回「在 handoff SKILL.md R1 補一句依更新時間排序」**(同批)。R1 現行契約是
  「多份 → 列給使用者選」,補排序等於給出排名、可能誘使 agent 直接挑第一份——**那是行為誘因的
  改動**,依本檔既有的證據門檻要成對實驗才動,而本次沒有觀察到相關失效。改為只補 `:133`
  **既有欄位列舉**(漏一欄是敘述不完整,與誘因無關),格式權威新增在腳本檔頭。
  ⚠️ 這兩件事先前被併成一句「不改 SKILL.md、格式權威在檔頭」,**那個前提是假的**:`:133`
  本來就在列舉欄位,而檔頭當時根本沒有 active 行格式。拆開後才各自成立。
> `deep-plan`／`deep-review` 的實驗結論七條(08-17～08-18:並行 fresh reviewer、累積正當化、
> verdict 不當通過條件、五條 blocking 只兩條進 body、E1／E3、P4 fixture、§6 子類)已歸檔至
> `docs/archive/decisions-2026-08.md`「deep-plan／deep-review 實驗結論(2026-08-17～08-18)」。
> 機制在各 skill 的 `SKILL.md`／`evals.md`／`field-log.md`,歸檔保存的是實驗數據與被否決的路。

  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260817-read-only-allowlist-global · ** **2026-08-17 唯讀 allowlist 放全機隊層,否決 project-scoped**。50 份 transcript 統計出 16 條唯讀規則
  (自家 skill 狀態腳本、`shellcheck`、`crontab -l`、`shasum`)。`.claude/settings.json` 被本 repo
  `.gitignore` 第 2 行擋掉、是 machine-local 的,而 dotfiles 在 14 台上都要跑 `tests/run.sh`——放那裡
  等於只有這台生效。⚠️ 頻率最高的幾個**刻意不放行**:`uv run pytest`(1073 次)、`awk`(199)、`gh api`／
  `curl`／`ssh`／`docker exec` 全是任意程式碼執行(`awk` 有 `system()`,不算唯讀工具);`verify-tests.sh`
  同理——它轉呼各 repo 的測試框架。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260817-tests-run-allowlist · ** **2026-08-17 `Bash(./tests/run.sh)` 明知放大仍保留**。相對路徑進 user 層＝「當前 repo 說了算」。
  仍保留的理由:**那道權限提示擋不住它看起來擋得住的東西**——提示只顯示指令字串、不顯示腳本內容,
  有沒有它你都是依「我剛叫它跑測試」按核准,安全訊號的差額接近零;且實測全機只有 2 個 `tests/run.sh`
  (本 repo 與 ml-env),`~/Projects` 20 個 remote 全在自有 org。**復活條件:哪天 clone 外部 repo 進來
  就重看這兩行**——clone 的當下沒人會回頭讀 allowlist,那是它唯一的殘留風險。

  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260815-dossier-backlog-lifecycle · ** **2026-08-15 dossier 與 backlog 依生命週期分家,不動門檻**。技術債＋已知缺口是**待辦**
  ——只壓得短、條目不會少,直到做掉為止,量體門檻對它無效(實測佔 STATUS.md 47%、26 條無一
  已解決,近 25 次 commit 有 8 次落在門檻 98–99.8%)。**否決兩條「讓門檻」的路**(治理計畫的
  ④ 軟目標結構下限出口、⑤ per-repo 覆寫,兩條都卡在「多寬才算合理」無非任意答案),改**縮小
  dossier 管轄範圍**:兩節移入 `docs/backlog.md`。④⑤ 因此降級為**暫不需要**(非否決),
  復活條件是分家後的 dossier 又長期貼門檻。代價與未驗證面見
  `docs/plans/2026-08-14-dossier-governance.md`「v2 追記」。

  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260813-no-codex-project-skill · ** **2026-08-13 不建 Codex 版 project skill,等真實 RED**。既然 Codex 已可 ship,直覺下一步是把
  Claude 的 `project` workflow 複製一份給它;不做的理由是 `codex/AGENTS.md` 改後已指向
  **repo 既有的 shipping skill**,複製等於製造第二份會漂移的 pressure-tested 邏輯(同
  `/project log 包裝 /uap` 那條死路的形狀)。**觸發:Codex 端出現真的走不動的情境**——屆時再做,
  且優先重用同一套 mutation 腳本而非另寫。
> 以下六條為 2026-08-14 從「已知缺口」**歸位**——它們記的是「決定先不做、理由是什麼、什麼條件
> 下重議」,那是決策語意。放在缺口節會永久滯留(缺口沒有出口),放這裡才吃得到歸檔判準。
> 標的日期是原始事件日,推導與實測數字沉 git history(歸位前的全文在 STATUS.md 的 git log)。

  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260811-symmetric-rules-as-signal · ** **2026-08-11「規則的對稱面／使用點」不補文字原則,要做就訊號化**。文字是最易被跳過的那層
  ——實證:Step 2 抓到 `add -A` 例外的使用點缺口純屬偶然,同 session 的 #43 走過同一個 Step 2
  仍漏兩條 blocking。訊號化的形狀＝偵測變更集含契約檔時印對稱面候選、不判語意(同 `dossier-flag`)。
  **做不成 exit-code gate**:規則是語意抽象出來的,機器不知道要 grep 什麼。
  **2026-08-15 又一個實例**:`stat -c` 先於 `-f` 的順序在 `codex-runtime-hygiene.sh` 與
  `tests/run.sh:3758` 都有明文註解,卻仍漏了 `:4199` 這個使用點——**文字原則確實接不住**。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260810-collaborator-notes-wait-red · ** **2026-08-10「另一個寫入者的筆記可能被蒸餾壓掉」暫不動規則**。協作者把粗胚寫進「進行中」,
  那正好是會被收斂的一節,而 Step 2 的前提「此刻 session 記憶還在」**對別人寫的東西不成立**。
  **觸發條件:觀察到一次真的被壓掉,才動規則**——同族先例(ship-state 的行號診斷)也是猜錯兩次才加。
  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260809-generated-docs-no-churn · ** **2026-08-09 `Generated docs never win` 是存量違例,記著但不 churn**。已上線卻從未測過
  (G5 隨 OpenWiki 一起 DEFER),屬 `No failing scenario, no instruction` 的存量違例——**不刪,
  也不為它補 eval**。(2026-08-14 補:OpenWiki 官方定位確認為 derived 層,與 dossier 正交,此條不動。)

  - 日期來源:migration-entry
  - 放棄:見原文
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **D-20260820-legacy-plans-record-only · 2026-08-20 舊版 plans 只作紀錄，不作設計參考**:多版舊計畫的整體架構已實證無法落地；保留檔案只為保存失敗紀錄，不代表仍是候選方案。未變動的 legacy plan blob 因此不進 `find` 候選，也不作 xref source；本次使用者明確指定的 goals 文件例外。
  - 日期來源:direct
  - 放棄:把 frozen legacy plans 當作 routed canonical reference
  - 重議:只有使用者明確重新指定某一份舊計畫為需求來源
  - 關聯:docs/plans/2026-08-20-doc-governance-goals.md;docs/plans/2026-08-20-doc-governance-implementation-plan.md

- **D-20260820-trusted-doc-scanner · 2026-08-20 shipping 只執行受信任的文件治理 scanner**:全機隊的 `ship-state.sh` 不執行受檢 repo 自帶的 Python；先以 byte-for-byte 比對確認 target core 與 dotfiles 受信任版本一致，再由受信任版本讀 target config 並掃描 target root。缺檔或 mismatch 一律 BROKEN／STOP。
  - 日期來源:direct
  - 放棄:直接執行 target repo 的 `scripts/doc-governance.py`；只靠 target 自己宣告 checksum
  - 重議:scanner 需要支援多個並存 schema version，且能建立由受信任端維護的版本 allowlist
  - 關聯:claude/skills/project/scripts/ship-state.sh;tests/test_doc_governance.py

- **D-20260820-u-3295d617a292 · 2026-08-20 治理面邊界校正基線**:原本的 `governance_surface` 只量到 `detect_doc_governance`，漏掉 trusted-core 路徑、STOP 輸出與 `check_repo` 接線。以 immutable `cf99d37` 重建八段完整邊界後，基線由 49,649 bytes 校正為 52,061 bytes（差額 2,412）；上限同步校正為 52,087，保留原本 26-byte headroom。這是量測邊界修正，不把本輪修復增加的 bytes 納入基線。
  - 日期來源:direct
  - 放棄:維持算錯的 49,675 上限；把整支 `ship-state.sh` 納入而稀釋 doc integration 訊號；以本輪修復後大小倒推新上限
  - 重議:治理接線改成單一可獨立計量模組，或八段 marker 無法再完整涵蓋實際執行路徑
  - 關聯:.doc-governance.json;claude/skills/project/scripts/ship-state.sh;cf99d37a5f67d8ce45721db7f2abecbd2f021de5

- **D-20260820-implementation-plan-scope-erratum · 2026-08-20 implementation plan 範圍勘誤**:凍結的 implementation plan 同時把 `docs/dead-ends.md` 列在修改清單與「刻意不改」，實際交付有修改該檔。plan 保持 write-once，不就地竄改；本 record 作為 canonical 勘誤，真實範圍以已提交 diff 為準。
  - 日期來源:direct
  - 放棄:修改已標 implemented 的 plan；假裝兩個互斥清單都正確
  - 重議:plan lifecycle 改為允許結案後的結構化 errata block
  - 關聯:docs/plans/2026-08-20-doc-governance-implementation-plan.md;docs/dead-ends.md

- **D-20260820-governance-surface-budget-policy · 2026-08-20 治理面預算採圓整級距**:治理面上限由貼身的 52,087 bytes 改為 65,536 bytes。一次性完成驗收的量體 ratchet 已達成「新機制不得靠提高預算逃避收斂」的目的；把它原樣留作維護上限，會讓 correctness fix 在只剩數 bytes 時被自身 gate 阻擋。後續 correctness／safety 修復可移到下一個二進位圓整級距；新增能力仍須說明量體成本，禁止只補當前 patch 所需的 N bytes。`governance-ratio` 保持資訊值，不作共同 blocking，因為增加 Markdown 分母會在治理面沒有簡化時放寬 gate。
  - 日期來源:direct
  - 放棄:維持貼身 headroom；讓 correctness fix 受一次性驗收 ratchet 阻擋；以 ratio 作可被分母成長稀釋的 blocking gate
  - 重議:治理面逼近 64 KiB，或能建立不受 corpus 分母操弄的相對複雜度指標
  - 關聯:.doc-governance.json;docs/document-governance.md;D-20260820-u-3295d617a292

- **D-20260821-removal-axis-incomplete-fix · 2026-08-21 刪除軸兩條繞道判為「上一次修復不完整」而非新一輪審查**:原 finding 的根因是「immutability 的判定主體＝目前還存在的檔案」,而 `git rm --cached`(取消追蹤、檔案留在 working tree)與「branch 內建立後才凍結」是同一根因的另外兩個入口,不是新缺陷。本批累積 diff 觸及 skill body／always-on 契約／eval,依 deep-review 的 skill-authoring batch 規定只跑一次診斷 review、不進修復循環,故不開第八輪;完成證據取 repo 自己的機制(deterministic suite 紅轉綠＋逐 call site 突變＋修前同情境靜默),不取「再審一輪零 finding」。修復仍交 codex、主 agent 只做機械復驗,維持作者／審查分離——本批動的是 gate 自身。
  - 日期來源:direct
  - 放棄:開第八輪 deep-review;主 agent 自行改 gate;把兩條繞道當新 finding 另起輪次
  - 重議:同一根因出現第三個入口,或完成判定需要行為 eval 而非 red-to-green 支撐
  - 關聯:M-20260821-immutability-removal-axis-closed;scripts/doc-governance.py;docs/testing-contract.md

- **D-20260822-drop-superseded-dossier-plans · 2026-08-22 刪除八份已被否決的 dossier 治理計畫,並同步移出 `legacy_plan_blobs`**:`dossier-governance-problem` 五版與 `dossier-sharded-architecture` 三版是「在沒有量測的情況下反覆選架構」的產物(見 D-20260820-pilot-before-architecture),真正交付的是 `docs/plans/2026-08-20-doc-governance-goals.md` 與同日的 implementation plan。凍結紀錄的價值在於保存「當初為何這樣決定」,而這八份的推導已完整壓進上述決策 record;留在 working tree 只會讓 `docs/plans/` 的可讀性被八份同名不同版稀釋。**刪除是有意識的決定,不是繞過 immutability gate**:gate 的作用正是逼出這一步——要刪就得同時把條目移出 `legacy_plan_blobs`,而那是 governance surface 上看得見的變更。內容並未消失,git history 仍可取回。**`docs/plans/2026-08-14-dossier-governance.md` 刻意保留**:`docs/archive/decisions-2026-08.md` 有兩筆不可變 record 以 xref 指標指向它的「DROP」與「v2 追記」兩節,刪掉即 xref 斷鏈且無法修補指標端。
  - 日期來源:direct
  - 放棄:全部保留為凍結紀錄;或刪檔卻不動 `legacy_plan_blobs`(會讓每次 ship 都紅);或為了刪 08-14 而竄改 history record
  - 重議:出現需要回溯這八份原文的具體問題,且 git history 取回不敷使用
  - 關聯:D-20260820-pilot-before-architecture;.doc-governance.json;docs/plans/2026-08-20-doc-governance-goals.md
- **D-20260822-rollout-checklist · 2026-08-22 rollout checklist 納入治理面預算**:`docs/doc-governance-rollout.md`
  同時列入 `project-doc` class 與 `governance_surface`。規範性 prose（怎麼搬 record、怎麼改 STATUS、什麼不得做）
  若放在預算外，治理面上限就量不到它，等於留下「把 prose 搬去別檔」的旁路——上限存在的目的正是量這一類量體。
  代價是 headroom 由 4,782 降到 1,338 bytes；依 D-20260820-governance-surface-budget-policy，後續 correctness
  fix 可移到下一個二進位級距，本次不提高上限。
  - 日期來源:direct
  - 放棄:只當 project-doc 不計 bytes（省 headroom 但讓上限失去意義）;或塞進 `docs/document-governance.md`（同樣計入，但把逐 repo 一次性程序與常駐規範混在一起）
  - 重議:治理面因 correctness fix 撞上 65,536 時，先檢查本檔是否已被實際 rollout 用過、能否縮成程序骨架
  - 關聯:D-20260820-governance-surface-budget-policy;docs/doc-governance-rollout.md;docs/plans/2026-08-20-doc-governance-implementation-plan.md

- **D-20260822-rollout-gate-replacement · 2026-08-22 用可數的 canary 門檻取代 fleet rollout 前的 steady-state gate**:`docs/plans/2026-08-20-doc-governance-implementation-plan.md`(frozen,不就地改)「Phase 6 第 4 點」與「§6 完成判定」末條的「dotfiles 連續 10 次 ship 無人工 compaction 才推機隊」由本 record 取代。**取代的只有 steady-state 那半**;同句的「新增 decision/dead end/milestone 落到正確月份 shard」原樣保留為 blocking(`event-month/file mismatch`,已有 oracle,不需要 10 次 ship 才驗得到)。原門檻的風險控制意圖有效——治理成本會乘上 repo 數——失效的是 acceptance criterion:全 repo 找不到 ship、人工介入或 compaction 的定義,因此不可數,實際效果是無限期 veto。連當初拿來說明它未達成的證據也是錯的:本 repo 走 squash merge,`git log --merges` 數不到已接受的工作;以 `gh pr list` 對 merge commit,採用 commit `9d3e891` 之後的 qualifying ship 是 2 次(PR 124、125),不是 0。新門檻:batch 1 明確定位為 controlled canary(第二個 pilot),**現在即可開始**,不等 steady-state 證據;batch 2/3 才要求。qualifying ship 逐次記入 `docs/rollout-ledger.md`:repo、commit、lifecycle 操作類型、第一次 audit rc 與 finding codes、人工介入分類、最後 audit 結果、governance surface bytes 變化。總數維持 10,但 canary 自己必須貢獻數次 post-cutover ship,不得全由 dotfiles 湊滿;樣本須覆蓋不同 lifecycle 操作,不能是十顆 review-fix commit。任一次判定為真正 compaction 即暫停擴張並記 root cause;月份 mismatch 永遠直接阻斷。canary 期間另收集「不知道標題」的真實 `find` query——rollout 本身不會自然產生 `B-20260821-debt-27`／`B-20260821-debt-28` 的 ranking 證據,不收就只能繼續對 dotfiles 自己的語料過擬合。治理面預算不預先二選一:checklist 回填先分類,會造成錯誤、遺漏或不可回復 migration 的修正屬 correctness,新範例與便利功能屬 capability;撞線時先消重複,仍放不下的 correctness fix 才依 `D-20260820-governance-surface-budget-policy` 升級距,不替所有 rollout 回填預先取得豁免。
  - 日期來源:direct
  - 放棄:維持原門檻(不可數,且會把 27/28 的證據來源鎖死在 dotfiles 語料);直接刪除門檻不換口徑(等於為了讓這批過關而調鬆判準,與 `governance_max_bytes` 的 hard rule 同型);把 ship 計數建在 `git log --merges`(squash merge 下恆為 0);把 ledger 併進 history 或 backlog(生命週期不同:它既非 event-time 記錄,也不是未結案待辦)
  - 重議:canary cutover 後首次 ship 就需要人工介入;或 ledger 累積到 10 次仍無法分類某次介入屬 lifecycle 或 compaction(表示定義仍不可操作,須先修定義再談 batch 2/3)
  - 關聯:B-20260822-debt-30;D-20260820-governance-surface-budget-policy;D-20260822-rollout-checklist;docs/rollout-ledger.md;docs/doc-governance-rollout.md

- **D-20260822-external-reference-targets · 2026-08-22 跨 repo 指標改為可宣告，核心不再把它判成壞指標**:canary rollout(`krepo-mops-major-news`)第一次 `audit --shadow` 撞到——4 條指向兄弟 repo 的指標被判 broken(`kb-repo-bootstrap.md` 在 krepo-common、`krepo/CLAUDE.md`、`docs/shared/kb-repo-bootstrap.md`),而其中一條落在 immutable history(`docs/archive/status-20260812-phase2.md:463`)。history 是 append-only,改它本身就是 finding ⇒ **該 repo 沒有任何合法路徑可以走到 `audit --ship` 全綠**,不是遷移沒做完,是核心缺一個表達方式。dotfiles 自己沒有兄弟 repo 指標,這個面因此從未現形。核心新增 `external_reference_targets`:exact target 字串清單,解析失敗且命中宣告即略過;**宣告本身受審**——目標其實存在於本 repo 內 → finding(否則等於靜音一條真的該檢查的指標),沒有任何 reference 用到 → finding(suppression 不得活得比它的指標久)。三顆守門逐一中性化,全套 66 tests 各恰紅一條對應測試。治理面 65,564 撞上 65,536(超 28 bytes):依 `D-20260822-rollout-gate-replacement` 先查重複,`docs/doc-governance-rollout.md` 與 `docs/document-governance.md` 無實質重疊、沒有可消的重複;而壓縮既有 prose 擠出 28 bytes 正是 `docs/rollout-ledger.md` 定義的 `compaction`,會觸發暫停擴張。故判為 correctness fix,依 `D-20260820-governance-surface-budget-policy` 升至下一個二進位級距 131,072(現 66,301)。
  - 日期來源:direct
  - 放棄:prefix／glob 形式的宣告(一條 `docs/` 就讓整棵樹靜音,與「宣告本身受審」互斥);改寫 repo 端指標(archive 那條在 append-only 檔裡,最多解 3/4);把無法解析的 target 一律降級成 note(會連真正壞掉的指標一起放掉——本次 canary 正好抓到 5 條真的壞的);壓縮既有 prose 以避開升級距(那是 compaction,且 D-20260820 已明文禁止只補當前 patch 所需的 N bytes)
  - 重議:出現第二種需要宣告的形狀(例如整個兄弟 repo 的目錄樹都要引用),或某個 repo 的宣告清單長到難以逐條維護
  - 關聯:D-20260820-governance-surface-budget-policy;D-20260822-rollout-gate-replacement;D-20260822-rollout-checklist;docs/document-governance.md;docs/doc-governance-rollout.md

- **D-20260822-portable-deep-plan · 2026-08-22 deep-plan 採單一跨 runtime 核心，停止 runtime telemetry**:Claude Code 與 Codex 共用 `claude/skills/deep-plan/` 的同一份 `SKILL.md` 與 reviewer brief，`codex/skills/deep-plan` 只作 symlink；frontmatter 收斂為 Agent Skills 共同的 `name`／`description`，平台差異只留在 fresh-subagent adapter（Claude Code 建立新 Agent；Codex `spawn_agent` 明列 `fork_turns:none`）。理由是 deep-plan 的目標是隔離式查證與兩輪 gate，不是綁定某個 invocation/tool API；複製兩套正文會讓 epistemic contract 漂移。舊版在任意 target repo review 期間寫 field-log inbox、植入 ship reminder，屬 skill 自己的實驗資料而非使用者要求的 review artifact，且曾因反向寫入 dotfiles 卡住另一個 writer，故 portable runtime 不再自動蒐集；歷史 field log 保留，只允許另行授權的 skill-authoring 實驗更新。
  - 日期來源:direct
  - 放棄:維護 Claude/Codex 兩份 workflow；在共用 frontmatter 保留 Claude-only 欄位；讓一般 review session 繼續替 skill 蒐集 telemetry
  - 重議:任一 runtime 無法透過 symlink discovery 或 relative reference 載入共用 skill；或出現需要 runtime 專屬 workflow、不能由薄 adapter 表達的 failing behavior eval
  - 關聯:claude/skills/deep-plan/SKILL.md;claude/skills/deep-plan/evals.md;claude/skills/deep-plan/field-log.md;codex/skills/deep-plan

- **D-20260822-portable-project-skill · 2026-08-22 project 採共用核心與雙薄入口**:`project` 的
  spec／log／transfer lifecycle、授權表、STOP 與 git mutation 只保留在
  `claude/skills/project/references/`、`scripts/`；Claude Code 與 Codex 各有自己的薄 `SKILL.md`，Codex
  的 references/scripts 以 symlink 指回 canonical core。理由是 side-effect workflow 必須 explicit-only，
  但 Claude 要在 SKILL frontmatter 用 `disable-model-invocation`，Codex 的標準 frontmatter 不接受該欄位、
  改由 `agents/openai.yaml` policy 表達；整包 symlink 會迫使其中一端違反自己的 metadata contract。
  helper command 由執行中的 script directory 動態產生，不再寫死 `~/.claude`；PR body 也不寫死產品 attribution。
  target repo 的 doc-governance 先驗 target core，再由 skill directory 的 shared trusted helper 執行；templates 同樣從 shared link 解析。commit、
  branch 與 PR title 一律以 target repo contract 優先，Conventional 只在無規定時 fallback。
  - 日期來源:direct
  - 放棄:複製一份 Codex shipping workflow（會讓 pressure-tested 授權表漂移）；整包 symlink（無法同時滿足兩端 explicit-only metadata）；在 Codex frontmatter 保留 Claude-only 欄位
  - 重議:任一 runtime 無法追蹤 nested references/scripts symlink；或 behavior eval 證明薄入口不足以正規化 invocation arguments
  - 關聯:D-20260813-no-codex-project-skill;D-20260822-portable-deep-plan;claude/skills/project/references/pressure-tests.md;codex/skills/project
