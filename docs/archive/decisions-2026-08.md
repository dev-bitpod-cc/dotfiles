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
