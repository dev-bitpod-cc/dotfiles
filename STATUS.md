<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-07-20)

---

## 進行中

(無——殘項見「技術債」)

---

## 關鍵決策(附理由)

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
- **2026-07-20 codex skill 散佈補 `ensure-codex-skills.sh`,比照 `ensure-rc-source.sh`**:`~/.codex/skills/repo-review` 停在 3/21 實體目錄、dotfiles 已到 7/17(15KB),autocodex 的一行協議實際跑到舊 skill。setup 的 `__codex_link_skills` 只在跑 setup 時作用,而 dotsync 不套用——缺的是散佈路徑,不是連結邏輯。

## 死路(試過但放棄——防重工)

- **「/project log 包裝/並存 /uap」**:`disable-model-invocation` 下無法鏈式呼叫,只能複製 pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,故直接取代。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:盤點實證 general-rag-cs 的已消費 STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] R4 non-blocking 建議未修:新增 prose 的中文半形標點與既有全形混排;Transfer 模式 commit 紀律歸屬未明示;evals/README 路徑基準寫法;handoff evals H4 排序
- [ ] deep-review body 密度收斂(工作流稽核第二批):401 行、內部交叉引用 6+ 處,自家 guide 的「指令被埋沒→未被遵循」風險型態;候選手術=autocodex 呼叫協議+exit 契約+救援階梯抽 references/(硬約束句留 body)。**觸發條件**(Iron Law:無 RED 不動):出現 deep-review 指令未被遵循的實際事件,或下次因他因要動其 body 時搭車。驗收 oracle=d1/d2 eval 重跑 GREEN+行數下降,不是 prose re-review
- [ ] hook matcher 僅 `startup`(resume/clear 不重測落後)——擴不擴待拍板
- [ ] pressure-tests S8/S9 的沙盒未納入 `claude/evals/setup-sandboxes.sh`(2026-07-17 首輪為 ad-hoc 建置)——補腳本化以利重跑
- [ ] SessionStart hook 的落後提醒實際輸出未在真實落後 clone 驗過(tests 有覆蓋、實戰未見)——下次任一主機 clone 落後時順手確認
- [ ] autocodex exec 路徑的 **resume 分支**尚未實戰驗證:2026-07-20 同日 C1/C2/C3 三輪實跑皆一次成功(exit 0、282s/~200s/~90s,`--json` 首事件確實帶 `thread_id`、背景回叫如預期),故 exit 4 的救援階梯從未被真實觸發——只有 stub 覆蓋。下次遇到真實空報告時確認 resume 能救回,F15 子情境 (b) 才算 GREEN
- [ ] codex plugin 去留待定:實質只當 codex:rescue 傳輸管道(22 筆歷史 job 全為 task-*,零 review;stopReviewGate 十個 workspace 全 false),exec 接管後僅剩 `/codex:transfer` 獨有——exec 路徑跑穩數輪後重新評估是否 uninstall
- [ ] 其他主機的 `~/.codex/skills` 仍是舊實體目錄,須 `dotsync` 後才收斂(本次僅修本機 macs)
- [ ] /project 手感驗證(後半段):2026-07-17 已在 krepo 實測 log→merge 一輪(PR #16 dossier 收斂 + 總量治理衛生檢查首戰,多 repo 偵測/Step 4 gate/merge 最後一哩皆如預期);**剩 spec→實作(即時記錄)半段待驗**——即時 dossier 記錄的判斷準確度以該輪觀察為據(該規則尚無 pressure-test)

## 已完成(里程碑)

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
