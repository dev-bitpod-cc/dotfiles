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
