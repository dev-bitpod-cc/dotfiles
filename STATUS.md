<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-07-22)

---

## 進行中

(暫無進行中工作項——bootstrap 路徑已於 2026-07-22 完成)

---

## 關鍵決策(附理由)

- **2026-07-22 bootstrap 豁免以「腳本判定」界定作用域,不寫成 prose 條款**:全新空 repo 的第一次 ship 需要一個 never-push-default 的例外(遠端零 branch 時無 default 可保護,且 GitHub 以**第一個被 push 的 branch** 為 default——照 branch-first 推 feature branch 會把 `feat/xxx` 變成遠端 default,事後只能人工進 settings 改)。但實證顯示這種豁免會**蔓延**:先前一次「空 repo 初始匯入」的 push 授權被延伸到後續 commit,導致 commit 直接落在 main。故豁免的成立條件定為 `ship-state.sh` 實測「遠端零 branch」——baseline 一 push 條件即永久為假,verdict 自動消失、branch-first 恢復 REQUIRED,**授權活在會自己失效的機器判定裡而非對話記憶裡**。使用者據此拍板「只修機制、不加 rationalization table 條款」(表已 7 列,加條款防不住記憶型蔓延)。
- **2026-07-22 ship-state.sh 破例碰網路(`ls-remote`),限縮在 `default: NONE` 分支**:「遠端零 branch」與「遠端有 branch 但本地定位不到 default」(未 fetch / default 名非 main|master)的正確處置**完全相反**(前者可建 baseline、後者絕不可推),而未 fetch 的 clone 下兩者的本地 ref 長得一模一樣——靠本地狀態無法分辨,猜錯就把 feature branch 推成遠端 default。此為檔頭「不 fetch」設計原則的顯性例外(比照 branch-first.sh 的唯讀慣例例外標注),正常路徑一次網路都不碰。反例已入 tests(遠端有 `trunk` 的未 fetch clone 必須 STOP)。
- **2026-07-21 Codex skill authoring 採「全域短入口 + dotfiles local-delta guide」**:`~/.codex/AGENTS.md` 只強制先讀 system `$skill-creator` 與 `~/.dotfiles/codex/skill-building-guide.md`，完整流程留在版控 guide，避免 always-on context 膨脹與 vendor 官方文件後失效；`codex/AGENTS.md` 由新 `ensure-codex-guidance.sh` 比照 skill 散佈機制幂等 symlink，既有實體檔先備份，setup/dotsync 皆會套用。repo-review 是首個 pilot：eval-first、重構去重、quick validation、fresh-context forward test，行為 eval 而非 prose 零 findings 為收斂 oracle。
- **2026-07-16 git 為唯一跨主機媒介**:不同步 `~/.claude/`(handoffs/memory)跨機——同步衝突、錨點的跨機語意複雜化、敏感內容風險;krepo STATUS.md 已證明 repo-resident + git 這條路可行。
- **2026-07-16 `/project` 取代 `/uap` 而非並存**:雙入口=觸發混淆+double-source;`disable-model-invocation` 使鏈式呼叫不可行,只能複製防護邏輯(違反 single-source 紀律)。防護內容原文搬遷。
- **2026-07-16 STATUS.md 為 dossier 載體,不新建 PROJECT.md**:尊重 krepo 自然湧現且活躍維護的慣例;uap(現 /project log)本就維護此檔;避免同 repo 兩個角色重疊的檔案。
- **2026-07-16 不引入 Linear / 外部 tracker**:痛點(任務規格、結果回寫、跨 session 延續)由 repo-resident 檔案+既有 skill 生態覆蓋;缺的是慣例固化,不是新工具。
- **2026-07-16 settings.json 以 `opus[1m]` 為共享 model 基線**:本機一次性模型偏好(如 Fable 5)不 commit、不傳播五台。
- **2026-07-17 無 protection repo 的兩難以「merge 最後一哩」解,不走分級直推**:保留 branch+PR 正規流程練肌肉記憶;卡點在 PR 開完後沒人接,不在流程本身——使用者明說 merge 即由 agent 接手(squash+清 branch+同步 default),不打破 never-push-default 鐵律(分級政策會)、也不強推 protection(儀式成本)。
- **2026-07-17 dossier 增設總量治理(compaction)規則**:krepo 實證爛帳模式——Session Log append-only 佔 360/598 行、「進行中」殘留 ✅ 項(皆 /project skill 上線前的舊產物,結構先於規範半年);原規範只防「新增垃圾」、不防「總量單調膨脹」→ dossier.md 加修剪規則(完成即移出、里程碑留一季+常青、翻案決策刪、**死路不刪**、>300 行當次收斂)+ log Step 2 衛生檢查。krepo 已依此收斂 599→201 行(elandcomtw/krepo PR #16)。
- **2026-07-17 dossier 記錄時點搬到事件當下**:/project「沒手感」根因是 skill 只在頭尾(spec/log)喚起,而決策/死路發生在過程中,等收尾 context 可能已壓縮——全域 CLAUDE.md 加即時記錄規則,log Step 2 從「回憶重建」降級為「核對補漏」。輕量判準與詢問收斂同理:儀式可減,Critical 不減。

- **2026-07-20 autocodex 傳輸層改 headless `codex exec`,不再走 codex plugin 的 codex:rescue**:F13(殭屍 job)/F14(split-brain)都是同一根因的下游症狀——plugin 等待端 `captureTurn` 只 await「僅由 broker 轉發 `turn/completed` 才 resolve」的 promise,無 timeout/輪詢、`handleExit` 也不 reject 它,而執行端 broker→app-server 為 detached 照跑完並落檔;**通知一斷即永久靜默等待**,codex 其實早有報告。斷線源不只 split-brain(SessionEnd hook 殺共享 broker、broker busy 時 `withAppServer` 另開 app-server、前景 rescue 撞 Bash 10 分上限),清孤兒無法根治。改以 `codex exec` 後完成訊號是「進程退出+報告落檔」兩個 OS 層級事實,15 分鐘雙訊號死亡偵測退役為 exit 契約(0/4/5/2)。**引數與儀式不變**(一行協議、C1–C3、深井閘、squash 耦合全保留)。plugin 暫留(保 `/codex:transfer` 與退路)。
- **2026-07-20 wrapper 的 range 驗證必須對照下游 repo-review 契約,不能只對照 git**:同一 bug class 在 codex 審查中出現三次(拼錯的 base、`∅` 顯示寫法、三點 range)——git 看來可容忍、下游 `review-context.sh` 明確拒絕,而放行的後果都一樣:codex 把錯誤寫進 report.md,報告非空 → wrapper 回 0 → 產出「成功但其實什麼都沒審」的報告。三點那條尤其值得記:它是主 agent R4 審查建議加的,還配了斷言把錯誤契約釘死,靠 codex 的下游視角才揪出。**跨腳本契約只能靠斷言釘死,stub 測不出來。**
- **2026-07-20 settings.json 撤銷 push-to-main 放行(防線對齊)**:prose 層「never push default」是最高紀律,harness 層卻有六條 `git push origin main` 變體明放行(8d85683/24df56c,早於後來的 PR 工作流紀律)——唯一能硬擋的層反向失守。選「移除」而非 `deny`:回到確認提示,保留使用者明示直推的場景。順帶依 2026-07-16 model 基線決策,本機 fable 偏好分流至 `~/.claude/settings.local.json`(untracked、優先級高於 settings.json),repo 基線維持 `opus[1m]`。
- **2026-07-20 skill 內 runtime 路徑慣例定為 `~/.claude/skills/...`**:該 symlink 由兩個 setup 腳本建立、指向 repo 實際位置,與 clone 路徑解耦;`~/.dotfiles/...` 僅用於描述原始碼位置(開發/編輯情境)。動機:deep-review 同檔混用兩式(codex 腳本走 ~/.dotfiles、review-state 走 ~/.claude),symlink 是 machine-local 前置條件卻無文件化慣例。已寫入 skill-building-guide 引用結構規則。
- **2026-07-21 skill 腳本下沉維持「git-唯讀+印解析完成指令」,不讓腳本直接 mutation**:review-anchor 的 squash/switch 都只印 `squash-cmd:`/`branch-cmd:` 整行供 model 照抄——守住 skill 腳本唯讀慣例(ship-state/review-state 明文),又消除 model 心算 hash 的錯誤面;state 檔寫入(.git/deep-review/)非 git 內容 mutation,有 codex-exec-review job 目錄先例。同批決策:不抽跨 skill 共用 lib(symlink 邊界破壞 skill 自包含性;review-anchor 刻意不自建 base 偵測,--base 由 review-state 輸出轉交,避免第三份 detect_base;翻案條件=出現第三份副本或副本需同步修改)。
- **2026-07-21 全域規則四處 carve-out(個人規則 vs agentic 工作流稽核結論)**:(1) bun/uv 限新專案與自有專案,既有 repo 尊重其 lockfile 對應工具+NEVER 引入第二套 lockfile;(2)「Uncertain? stop and ask」分流——自主執行取最合理解讀但假設必須落地 STATUS.md 並標待確認,不可逆/對外動作不在 fallback 內;(3) bug-fix 重現測試補可行性豁免(環境相依/一次性腳本 → 改記手動重現步驟,先重現再修順序不變);(4) commit types 補 perf/ci。
- **2026-07-21 deep-review 以 clean-room 重寫做低頻探針稽核;squash 語意維持「範圍恆等審查範圍」+壓掉前警告**:把 skill 蒸餾成需求層規格(`docs/deep-review-spec.md`,non-normative 快照、不隨 skill 回寫)讓禁讀實作的 subagent 重寫再比對——收斂處證明機制被需求逼出、分歧處即規格歧義、推導不出處即「只活在實作裡」的知識缺口(清單見 spec 附錄;C2+ 增量 range、path 模式範圍擴大告知等 6 項)。比對判準必須**不對稱**(新版讀來乾淨可能只是沒踩過坑,機制覆蓋以實戰版為基準);定位為 skill 迭代多輪後的**低頻探針**,非常規流程(成本約兩三輪 deep-review)。回流兩改進:tests-baseline 前置(record 記 pass/fail/skip,fail → 測試不做 gate、commit 標 UNVERIFIED-BY-TESTS——修掉「repo 測試本來就紅則 autofix 迴圈中段死鎖」缺口)、WIP snapshot(working-tree autofix 先把使用者未提交變更收成 `wip: pre-review snapshot`,revert 壞修復不誤傷原始工作、squash 終態不變)。squash **不採** cleanroom 雙錨點(scope_base/squash_anchor 分離保留既有 commit 歷史)——與 PR squash-merge 工作流重疊、改動面大;改於 squash-cmd 印「將壓掉 N 顆審查前既有 commit」警告(成本近零、語意不變)。
- **2026-07-21 PR1 誤掃入 codex-guidance 工作線後拍板 bundle 而非拆分**:autofix 迭代中 `git add -A` 把另一 session 留在 working tree 的 codex/ 整套工作掃進 branch(教訓:多 session 共用 working tree 時 commit 一律顯式路徑);拆分需對 tests/run.sh/CLAUDE.md/STATUS.md 三個混檔做 hunk 外科手術、且會動另一 session 的 in-flight 狀態,風險大於收益——拍板留在 branch、squash 時拆成兩顆語意 commit(check-crawl-quality/codex-guidance),codex C2/C3 對該批檔案的 findings 一併驗證處理(F3/F4 已修,F5/F6 記技術債轉交)。
- **2026-07-20 codex skill 散佈補 `ensure-codex-skills.sh`,比照 `ensure-rc-source.sh`**:`~/.codex/skills/repo-review` 停在 3/21 實體目錄、dotfiles 已到 7/17(15KB),autocodex 的一行協議實際跑到舊 skill。setup 的 `__codex_link_skills` 只在跑 setup 時作用,而 dotsync 不套用——缺的是散佈路徑,不是連結邏輯。

## 死路(試過但放棄——防重工)

- **「/project log 包裝/並存 /uap」**:`disable-model-invocation` 下無法鏈式呼叫,只能複製 pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,故直接取代。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:盤點實證 general-rag-cs 的已消費 STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] R4 non-blocking 建議未修:新增 prose 的中文半形標點與既有全形混排;Transfer 模式 commit 紀律歸屬未明示;evals/README 路徑基準寫法;handoff evals H4 排序
- [ ] hook matcher 僅 `startup`(resume/clear 不重測落後)——擴不擴待拍板
- [ ] pressure-tests S8/S9 的沙盒未納入 `claude/evals/setup-sandboxes.sh`(2026-07-17 首輪為 ad-hoc 建置)——補腳本化以利重跑;S10(transfer credentials,2026-07-21 新增)連首輪實測都還沒跑,transfer 模式的紀律驗收仍是紙上情境
- [ ] SessionStart hook 的落後提醒實際輸出未在真實落後 clone 驗過(tests 有覆蓋、實戰未見)——下次任一主機 clone 落後時順手確認
- [ ] autocodex exec 路徑的 **resume 分支**尚未實戰驗證:2026-07-20 同日 C1/C2/C3 三輪實跑皆一次成功(exit 0、282s/~200s/~90s,`--json` 首事件確實帶 `thread_id`、背景回叫如預期),故 exit 4 的救援階梯從未被真實觸發——只有 stub 覆蓋。下次遇到真實空報告時確認 resume 能救回,F15 子情境 (b) 才算 GREEN
- [ ] review-anchor 的 **stale STOP 與 codex-next 冪等**子情境(F16 b/c)已由 tests/run.sh 第 19 節釘死,但實戰(真實 autocodex 迭代中 rebase/重試)尚未驗過——下次 autocodex 實跑時順手確認
- [ ] codex plugin 去留待定:實質只當 codex:rescue 傳輸管道(22 筆歷史 job 全為 task-*,零 review;stopReviewGate 十個 workspace 全 false),exec 接管後僅剩 `/codex:transfer` 獨有——exec 路徑跑穩數輪後重新評估是否 uninstall
- [ ] codex C2 對 codex-guidance 工作線的兩條轉交 findings(2026-07-21,PR1 審查中代收):F5 repo-review SKILL.md 多輪 autofix 契約疑似死鎖(`commit_each_round=false` 累積 worktree 修改 × 每輪重跑 helper × helper 對 dirty tree 回 `autofix-safe:no`——傾向 true positive,需 helper 實際行為定奪);F6 codex/skill-building-guide.md 的 `$skill-creator/scripts/quick_validate.py` 是否由 codex runtime 解析路徑(照 shell 字面執行必失敗,context-dependent)
- [ ] /project 手感驗證(後半段):2026-07-17 已在 krepo 實測 log→merge 一輪(PR #16 dossier 收斂 + 總量治理衛生檢查首戰,多 repo 偵測/Step 4 gate/merge 最後一哩皆如預期);**剩 spec→實作(即時記錄)半段待驗**——即時 dossier 記錄的判斷準確度以該輪觀察為據(該規則尚無 pressure-test);mid-work re-spec 2026-07-21 研究後判**維持不改**(krepo c1addda 實戰中「對話直接編輯」catch-all 已把缺口升級 spec 做對、零失敗案例;Iron Law:no failing scenario, no instruction)——除非觀察到 agent 照過時 spec 執行、或擅自擴大範圍未問使用者,才回頭補程序＋RED eval

## 已完成(里程碑)

- ✅ **2026-07-22 /project 補上 bootstrap 路徑(全新空 repo 的第一次 ship)**:使用者回報「對新建的空 repo 直接說 merge 會歧義」,實測確認三缺口——空 remote 下兩支腳本雙雙 STOP 但**流程無出路**(agent 只能即興)、branch-first 在此會造成永久性錯誤 default、「Merge 最後一哩」的 trigger 假設 PR 已存在(新 repo 通常無 protection → DIRECT-PUSH → 從沒開過 PR)。`ship-state.sh` 新增 `detect_bootstrap()`(BOOTSTRAP verdict + note/scope/可照抄 cmd,遠端有 branch 或 detached 一律 STOP);ship-paths.md 新增〈Bootstrap〉節與「無 PR 可 merge 時」分支(不猜、依狀態給選項);SKILL.md 的 never-push-default 加機制門控例外句 + Step 1/5 接上;branch-first.sh STOP 訊息指路。tests 新增 4 情境(bootstrap/detached/遠端有 branch 反例/baseline 後失效),先 RED(5 紅)後 GREEN,全 suite exit 0。

- ✅ **2026-07-21 skills 下沉三部曲收官(PR #21/#22/#23)**:check-crawl-quality(掃描+扣分表下沉 `crawl-quality-scan.py`)→ project(resolve 子指令/branch-first.sh 首支 mutation 腳本/dossier 偵測門檻單一來源;clean-room 盲寫比對見 `docs/project-spec.md` 附錄)→ handoff(consume 子指令,consume-once 機械保證)。三 PR 皆 deep-review autofix+autocodex 全循環;dossier 簽章與 consume 已消費偵測各經三輪對抗收斂(啟發式偵測器的攻擊面逐輪遞窄,最終拍板邊界明文入 SKILL/註解);tests/run.sh 235→478 斷言全綠。

- ✅ **2026-07-21 deep-review prose 下沉腳本(跨輪記憶 → deterministic state)**:squash base hash 與 last-codex-HEAD 的「跨輪記住」prose 是 context 壓縮死穴(為此重複防禦三次 NEVER a moving ref / 不要 HEAD~1)——下沉為新 `review-anchor.sh`(record/show/squash-cmd/codex-next/clear,state 落 `.git/deep-review/anchor` per-worktree,消費前 cat-file+is-ancestor 雙驗,codex-next 原子化取 range+記 HEAD、同 HEAD 冪等、C3 上限強制)+新 `verify-tests.sh`(修復後驗證,exit 0/1/3/2;**`bun test` 無測試檔 rc=1**,以 stderr `0 test files matching` 映射 SKIP,bun 改版最壞退化 FAIL 保守向)+`review-state.sh` 增量(branch-first verdict/branch-cmd、continuity 警告、empty-tree 常數)。SKILL.md 瘦身為「呼叫腳本、照抄輸出」(374→371 行),model 全程不經手 hash。tests/run.sh 294 全綠(新 19/20 節皆先 RED 後 GREEN);evals 補 F16/F17,d1+d2 Sonnet 迴歸雙 PASS(沙盒 git 實查:squash parent==錨點、anchor 已 clear、priority 4 不代選);全域 CLAUDE.md codex 觸發段補 anchor 跨 session 恢復句。
- ✅ **2026-07-21 deep-review body 密度收斂(工作流稽核第二批)**:autocodex 機制層(preflight exit 語意、prompt 限制、進度查詢、exit 契約、救援階梯、死亡偵測退役根因)抽 `references/codex-protocol.md`(76 行,含 TOC),硬約束(NEVER codex:rescue、固定一行 prompt、不輪詢、at most ONE fresh retry、NEVER bun install)整塊英文留 body;body 401→374 行,「Codex 呼叫協議」節標題保留為全域 CLAUDE.md 觸發段錨點(兩端免同步)。驗收依 oracle 而非 prose re-review:d1/d2 沙盒 eval 改前 baseline 與改後各跑一輪 Sonnet 全 GREEN(d1 branch-first+squash 錨定+trailer+未 push、d2 priority 4 gate 不代選;皆以沙盒 git 狀態評分),tests/run.sh 233 全綠。
- ✅ **2026-07-20 autocodex 卡死根治——傳輸層改 headless `codex exec`**:讀 plugin v1.0.6 原始碼定位 F13/F14 的共同上游(等待端無 watchdog,通知一斷即永久靜默等待),改以進程退出+報告落檔為完成訊號,15 分鐘雙訊號死亡偵測退役為 exit 契約;新增 `codex-exec-review.sh` 與 `ensure-codex-skills.sh`(補 codex skill 散佈路徑,修 repo-review 停在 3/21 舊版)。主 agent R1–R5 + codex C1–C3(8 條 true positive 全修、C3 零 findings)、tests 233 全綠;**exec 路徑三輪實跑驗證通過,無卡死**。
- ✅ **2026-07-17 /project 摩擦修復 + 全機隊生效**(PR #1/#2):輕量路徑、詢問收斂、merge 最後一哩(PR #1/#2 即首戰實測,含 gh 雙帳號身分切換補救)、即時 dossier 記錄(全域 CLAUDE.md 規則);pressure-tests 新增 S8/S9 + 回歸 S1 Sonnet 全 PASS(git 實查)、tests 150/150;dotsync 14 台同步,多主機工作流(含 /project 三模式、pull 偵測 hook)全機隊生效。
- ✅ **2026-07-16 多主機工作流改造**(c673844):/project skill 取代 /uap、SessionStart pull 偵測 hook、dossier/transfer 模板、跨主機分流規則;deep-review autofix R1–R4(1嚴重5中等修畢)、沙盒 pressure-tests 5 情境 Sonnet 全 PASS。

## 已知缺口

- **Mac 上 `brewup` 會被 codex cask 掛死(Gatekeeper 首次執行核可)**:症狀是停在 `Linking Binary 'codex-aarch64-apple-darwin'` 後不動,Ctrl-C 才繼續。成因非 brew——codex cask 的第二個 artifact(Generated Completion)會實際執行 `codex completion bash/zsh/fish`,而 quarantine 過的新 binary 首次 exec 會彈出「codex-… 是網際網路下載的應用程式,確定要允許執行?」對話框,進程 0% CPU 停在 `_dyld_start` **同步等該對話框被回答**(kernel log:`ASP: Security policy would not allow process`);對話框常沒搶到焦點、被埋在其他視窗後,看起來就只是卡死。**解法:在對話框按允許**(已錯過/誤按取消 → 系統設定 → 隱私權與安全性 → 「仍要允許」),再 `brew reinstall --cask codex` 補完 completion 並清 `*.upgrading` 殘留(Ctrl-C 會讓 cask 裝一半)。**不要用 `xattr -d com.apple.quarantine` 或全域 `HOMEBREW_CASK_OPTS=--no-quarantine`**——核可即足夠(核可後 quarantine 屬性仍在、Gatekeeper 仍生效),那兩者是不必要的安全弱化。
  - **觸發條件**:僅在 codex **實際升版**時發生(對話框綁 binary CDHash 問一次,同版核可後不再問);codex 改版頻繁(0.144.1→0.144.5 僅隔數日),故每次升版重演。**順跑一次不代表免疫,只代表那次沒升 codex**(brewup 輸出無 `Upgrading codex` 那行)。僅 Mac(macmini/macs)受影響,Linux 三台無 Gatekeeper。
  - **`allup` 陷阱**:經 SSH 跑 brewup 時,對話框只會出現在該 Mac 的實體螢幕上,無人在機前就永遠沒人按 → 真正無限卡死(非逾時)。該 Mac 需先在本機核可過該版本。
- 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+ credentials 明文散於三台。

## 移交準備度

(個人 infra,暫無移交打算——平時留空)
