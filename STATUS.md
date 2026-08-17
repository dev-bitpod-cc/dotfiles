<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec;ship 時同步;移交前補齊完整度。維護者可能另有工具輔助,
        但**規範本身在此、不在工具**——沒有那些工具也照樣維護得下去。
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-18)

---

## 進行中

- **`deep-plan` skill——紀律情境已 GREEN,E2 已驗證,E1／E3 未跑**(2026-08-17 建立)。
  `claude/skills/deep-plan/` 三檔就緒、`tests/run.sh` 綠;**P1／P2／P3／P5／P6／P7 六個紀律情境在
  Sonnet(樓層)全 GREEN**(含截獲驗證:零 SendMessage、洩漏字全 0、計畫內文零洩漏、沙盒零 mutation)。
  首跑另修掉 body 一處硬矛盾(Step 1「不要讀計畫」vs Step 2「判斷是否判準類」)。
  **2026-08-18 跑完 E2**(結論見關鍵決策節),並把 fixture 落地成 `claude/evals/setup-sandboxes.sh`
  的 **dp1** 沙盒——evals 從此可重跑,不再手建於 scratchpad(session 一結束就沒了)。
  **尚未完成的**:①**P4** 需 krepo 側的 fixture(凍結計畫檔進 `docs/plans/` + 登記 commit hash 與四處
  證據位置,私有內容不進本 repo);②**E1／E3** 未跑(N 的邊際收益、第二輪的實際產出),在實驗前不得
  當成已驗證的規則引用(Iron Law);③**同日 `/deep-review` 的五條結構性 blocking 未處置**
  (Step 0/1 落點順序、brief 缺 Blocking 欄、輸出契約缺層別欄、立場累積殘留管道、無 dossier repo 無
  出路)——全部會改行為契約,逐條與修法見 `docs/backlog.md`「技術債」首條。

> 更早的凍結計畫:`docs/plans/2026-08-09-repo-contract-extraction.md`、
> `docs/plans/2026-08-10-dossier-portability.md`。

**其餘工作全部帶觸發條件、皆不在進行中**:Phase 3 改名 **DROP**;Phase 4 installer、G5、
transfer 的 portability 步驟 **DEFER**——逐條的觸發條件與理由見上列兩份凍結計畫,此處不複述。

---

## 關鍵決策(附理由)

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。**歸檔判準**：已固化且不再影響現行方向 → 歸檔；仍在生效的一律不歸檔（死路＝防重工、技術債＝未解決，移出 always-on 即失效）。超標時**優先歸檔、不要為幾百 bytes 去壓無關舊條目**——那個動作重複幾次本身就是訊號。

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
- **2026-08-17 唯讀 allowlist 放全機隊層,否決 project-scoped**。50 份 transcript 統計出 16 條唯讀規則
  (自家 skill 狀態腳本、`shellcheck`、`crontab -l`、`shasum`)。`.claude/settings.json` 被本 repo
  `.gitignore` 第 2 行擋掉、是 machine-local 的,而 dotfiles 在 14 台上都要跑 `tests/run.sh`——放那裡
  等於只有這台生效。⚠️ 頻率最高的幾個**刻意不放行**:`uv run pytest`(1073 次)、`awk`(199)、`gh api`／
  `curl`／`ssh`／`docker exec` 全是任意程式碼執行(`awk` 有 `system()`,不算唯讀工具);`verify-tests.sh`
  同理——它轉呼各 repo 的測試框架。
- **2026-08-17 `Bash(./tests/run.sh)` 明知放大仍保留**。相對路徑進 user 層＝「當前 repo 說了算」。
  仍保留的理由:**那道權限提示擋不住它看起來擋得住的東西**——提示只顯示指令字串、不顯示腳本內容,
  有沒有它你都是依「我剛叫它跑測試」按核准,安全訊號的差額接近零;且實測全機只有 2 個 `tests/run.sh`
  (本 repo 與 ml-env),`~/Projects` 20 個 remote 全在自有 org。**復活條件:哪天 clone 外部 repo 進來
  就重看這兩行**——clone 的當下沒人會回頭讀 allowlist,那是它唯一的殘留風險。
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
- **2026-08-15 dossier 與 backlog 依生命週期分家,不動門檻**。技術債＋已知缺口是**待辦**
  ——只壓得短、條目不會少,直到做掉為止,量體門檻對它無效(實測佔 STATUS.md 47%、26 條無一
  已解決,近 25 次 commit 有 8 次落在門檻 98–99.8%)。**否決兩條「讓門檻」的路**(治理計畫的
  ④ 軟目標結構下限出口、⑤ per-repo 覆寫,兩條都卡在「多寬才算合理」無非任意答案),改**縮小
  dossier 管轄範圍**:兩節移入 `docs/backlog.md`。④⑤ 因此降級為**暫不需要**(非否決),
  復活條件是分家後的 dossier 又長期貼門檻。代價與未驗證面見
  `docs/plans/2026-08-14-dossier-governance.md`「v2 追記」。
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
- **2026-08-13 不建 Codex 版 project skill,等真實 RED**。既然 Codex 已可 ship,直覺下一步是把
  Claude 的 `project` workflow 複製一份給它;不做的理由是 `codex/AGENTS.md` 改後已指向
  **repo 既有的 shipping skill**,複製等於製造第二份會漂移的 pressure-tested 邏輯(同
  `/project log 包裝 /uap` 那條死路的形狀)。**觸發:Codex 端出現真的走不動的情境**——屆時再做,
  且優先重用同一套 mutation 腳本而非另寫。
> 以下六條為 2026-08-14 從「已知缺口」**歸位**——它們記的是「決定先不做、理由是什麼、什麼條件
> 下重議」,那是決策語意。放在缺口節會永久滯留(缺口沒有出口),放這裡才吃得到歸檔判準。
> 標的日期是原始事件日,推導與實測數字沉 git history(歸位前的全文在 STATUS.md 的 git log)。

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

## 死路(試過但放棄——防重工)

> 各條的推導、實測數字與 eval 編號在 `docs/dead-ends.md`「分工」,本節只留**會擋住你的那一句**。
> 分層照 `claude/known-hazards.md`「分工」對「已知地雷」的做法:死路要能在你沒想到要查的當下
> 擋住你,**規則不在 always-on 就不生效**,故結論留此、證據外移。

- **把 deep-review「skill-authoring batch 不進修復循環」的判準套到 plan review**(2026-08-17 否決)。
  推論鏈是「計畫是 prose → 對 prose 重跑對抗式 review 永不收斂 → plan review 只能跑一次診斷」,
  **實測推翻**:plan 的 findings 絕大多數是「計畫對 repo 現況的陳述錯了」,oracle 在 repo 裡、二元的;
  約 30 條 findings 幾乎沒有措辭/完整度深井。⇒ 那條判準管的是**無界完整度**(skill 是常駐規則,
  reviewer 永遠能問「這情境沒涵蓋嗎」),不是**有限事實查核**。**別再從「它是 .md」推論收斂性**——
  要看 findings 的 oracle 在哪。⚠️ 但迭代仍被否決,理由完全不同(累積正當化,見關鍵決策節)。
- **只給待辦節加歸檔出口(已解決的移入 `docs/archive/`)而不分家**(2026-08-15 否決):當日實測
  26 條技術債／已知缺口**無一帶完成標記**,故它今天釋出 **0 bytes**;且處置形狀是在超標時多問
  一題「這條還做不做」,與「Step 2 太花時間」的訴求**方向相反**。**慣例本身沒被丟掉**——
  分家後寫進 `docs/backlog.md` 的關閉與歸檔慣例,差別在它不吃門檻、不出題。
- **拿 `gh pr view --json statusCheckRollup` ＋ jq 計數判 CI 狀態**(2026-08-15 否決,改用
  `gh pr checks --required` 的 exit code):rollup 單筆**沒有 `isRequired`**,必要與非必要 check
  分不開 → 空等或誤停,**正是本次要修的誤診換個方向**;另有同名多筆與混型別兩坑。三條理由與
  翻案條件見 `docs/dead-ends.md`。
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
- **無 observed RED 的明示規則**(2026-08-13 兩條當天全撤,同形狀第三次;2026-08-14 第四次改成
  **先跑成對實驗再決定**,零差異故沒寫)。**共同形狀:RED 來源本身證明了規則不必要**——
  **「觀察到失效面」≠「需要新規則」**,正確的問法是**既有規則接不接得住**,判準是成對實驗。
  例外只有「把 body 陳述錯的事實改對」那半(修正錯誤陳述不需 RED)。四次的逐條經過、eval 編號
  與那個被推翻的診斷見 `docs/dead-ends.md`。
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

> **全部條目已移至 `docs/backlog.md`「技術債」**(2026-08-15 分家)。理由:待辦是未結案狀態、
> 只有做掉才會消失,對它套 dossier 的量體門檻壓不動,每次 ship 都在同一半內容上反覆磨。
> 本節保留標題以維持 dossier 簽章與章節完整性檢查;**新的債寫進 backlog,不要寫回這裡**。


## 已完成(里程碑)

> 2026-07 以前的里程碑已歸檔至 `docs/archive/milestones-2026-07.md`；
> 2026-08-05～08-13 各批已歸檔至 `docs/archive/milestones-2026-08.md`（本節只留最近一批）。

- ✅ 2026-08-15 dossier／backlog 分家落地:新增 `docs/backlog.md`(待辦兩節＋關閉歸檔慣例)、
  `ship-state.sh` 的 `detect_backlog`(**只驗章節完整性、刻意無量體門檻**)與抽出共用的
  `strip_fences`,規範同步 `references/dossier.md`／SKILL Step 2／`STATUS-template.md`＋
  新增 `BACKLOG-template.md`。STATUS.md 23564 → 13272 bytes、251 → 153 行、零 flag;
  未分家的 repo 零輸出零回填(有守門測試)。新增 5 條斷言並以 mutation 驗過會紅,1039 PASS。
- ✅ 2026-08-15 `/project` 分流表把 `BLOCKED` 拆成三格(CI 還在跑／check 失敗／protection 真的擋)
  ＋補 `DRAFT` 一列,判準改吃 `gh pr checks --required` 的 exit code。同批補上會紅的 eval:
  Scenario 18 ＋ `gh-stub-blocked-pending`,並修好 `gh-stub` 缺 `pr checks`／default 分支的洞
  (舊 stub 會讓 Scenario 15 **為錯的理由通過**)。三臂 Sonnet 全 PASS,兩臂對同一個 `BLOCKED`
  給出相反處置,證明判準真被讀到。1034 PASS。
- ✅ 2026-08-15 修 `tests/run.sh:4199` 的 stat 跨平台順序(GNU `-c` 先於 BSD `-f`)。
  Linux 上該條恆紅:GNU 的 `stat -f` 遇無效格式雖回 rc=1、卻已把 filesystem 統計吐進 stdout,
  與 fallback 的輸出相連。**與 `:3758` 註解描述的「假成功」機制不同**,已在註解分清。
  同批完成 hook 的全機隊散佈(14 台)＋跨平台實測(Linux／Darwin 皆正確擋下)。

## 已知缺口

> **全部條目已移至 `docs/backlog.md`「已知缺口」**(2026-08-15 分家,理由同技術債節)。
> ⚠️ 對某條缺口做出「決定先不做＋重議條件」的決議時,那是決策語意 → 搬進本檔「關鍵決策(附理由)」,
> 不要留在 backlog 原地追加(**待辦沒有出口,決策有**;2026-08-14 已有六條這樣歸位過)。

## 移交準備度

(個人 infra,暫無移交打算——平時留空)
