# 里程碑歸檔 — 2026-08

> 從 `STATUS.md`「已完成(里程碑)」節歸檔（2026-08-06，總量治理；判準同決策節——已 ship
> 並固化在 skill / 腳本 / tests 者才搬出）。保留原文，不重寫。

- ✅ 2026-08-05 上兩批 git 紀律的第三方審查修復(3 blocking + 1 minor,全判 TP):`add -A`
  例外(禁令側與 `deep-review/SKILL.md` 使用點**兩處都寫**前置條件)、codex 自有 branch-first、
  STOP 與混檔技法的順序銜接、`clone --no-local` 補齊參數。
- ✅ 2026-08-05 跨 agent 所有權模型明文化(全域 `CLAUDE.md` 新增「跨 Agent 工作分配」節):
  writer 不限／ship 單一入口(現行 authority、非永久)／review 三層污染邊界／one writer per
  work item。查證發現「codex 只碰 `codex/`」**任何檔案皆無明文**——是慣例非規則,故本次寫的
  是**正面授權而非解除限制**;順帶補上 Claude 側缺失的 staging 紀律(三次 `git add -A` 誤收
  正是 Claude 在 ship 時犯的,規矩卻先前只立在 codex 端)。
- ✅ 2026-08-05 `codex/AGENTS.md` 補 Git discipline 節(never push/merge、禁廣義 staging、
  混檔拆分後乾淨 clone 驗證、ship 不自行實作)——補上 `danger-full-access` 下的持久 git 契約缺口。
- ✅ 2026-08-05 dossier 決策節 2026-07 歸檔至 `docs/archive/decisions-2026-07.md`:23 條原文
  搬出,24556→16444 bytes(-33%)、268→188 行,低於建議目標 20889;死路與技術債刻意不歸檔。
- ✅ 2026-08-05 repo-review 移植輪次上限的收斂診斷(codex 撰寫、Claude 代 ship):依根因重複/
  震盪 vs 各輪不同且前案仍修復來分類,禁止單憑上限推論架構問題;evals F21+tests 契約 gate。(565)
- ✅ 2026-08-05 deep-review 第三方回饋落地 + 輪次隱蔽缺口結案(#40):終止報告根因重複欄、
  R5 措辭修正;codex 三輪 4/4 TP 全修。外部取證判準同日撤除,見決策節。(564)
- ✅ 2026-08-05 codex repo-review 移植同批治理(#39):reviewer-brief 判準下沉、stage-neutral
  prompt 模板、pass 位置 orchestration-private(範圍比 deep-review 側更廣);evals F19/F20。
- ✅ 2026-08-05 deep-review 審查偏誤治理(#38):根因在**提問端**(主 agent 自行放寬 prompt),
  修法為判準下沉+白名單契約+輪次隱蔽;驗證三層與 codex 九條 findings 見其 `evals.md`。(547→564)

- ✅ 2026-08-06 handoff skill 優化:拿 archive 52 份實檔做統計,補上兩個高頻卻無規則的使用
  模式——同 slug 多輪續寫(約 40%)的死路承接、多 repo 錨點(27%)的逐 repo 對帳;`anchors`
  改記 toplevel 絕對路徑、`list` 補 path/title、新增 `find-predecessor` 子指令。H5/H6/H7
  三情境在 Sonnet 全 GREEN。第三方審查共兩個 cycle:merge 前 C1/C2/C3 抓 12 條(2 條屬 SSH
  工作項)、merge 後補審 `find-predecessor` 那批又抓 5 條(active 誤剝前綴、字典序選到 legacy
  舊檔、契約與實作不符、缺 eval、frontmatter 誤讀正文),末輪 No findings。`./tests/run.sh`
  592 PASS。

- ✅ 2026-08-06 squash/merge 決策改造:deep-review 收尾只壓 review 機械 commit(語意 commit
  保留,`squash-preserve:`/`squash-note:` 攤開)、round 改頂端連續段、merge 壓不壓改關鍵字分流
  + Step 4 第 1 題(`AskUserQuestion`)、review 痕跡偵測下沉 `ship-state.sh`(`review-residue:`)。
- ✅ 2026-08-06 上批的兩場 review 收斂(主審 R1–R5→終止→人工修→R1–R4 通過;codex C1–C3):跨
  Step 時序契約(Step 1 的 hash 是語意 commit 邊界、不得重算)、照抄行 shell quoting(路徑與
  ref 名過 `shq` + `--` terminator)、`--force-with-lease` 帶 expected SHA,以及一條**會
  `rm -rf` 掉整個 repo** 的測試防護漏洞。codex 7 條 findings 全 TP、零誤判。647 PASS。


- ✅ 2026-08-07 deep-review skill-authoring one-shot gate + R5 terminal state（#51，665 PASS）
- ✅ 2026-08-07 ship 說法語法：說法即授權、merge 預設保留、`review-terminal` STOP、merge 受阻分流（#52，672 PASS）
- ✅ 2026-08-07 squash-merge 殘留偵測 + `cleanup-stale-branch.sh` 安全清除（#53，699 PASS）
- ✅ 2026-08-07 Scenario 15 補測：`BLOCKED` 不得自動 `--admin`，正反兩向 PASS（#54）
- ✅ 2026-08-07 ready4quit 強化 + 四輪第三方審查修復：證據語彙拆兩軸（強度 × 殘留）、Step 2 memory/dossier 雙出口、背景任務證據來源改 `tasks/` 且 liveness 不得由 `.output` 推斷、`git-hygiene.sh` 補遠端事實與多 remote 一致性、hook 增報 worktree 雙寫入者；**eval 從零 GREEN 到 8 條 PASS**，其中 Q4a/Q5 是 eval 自己抓出、四輪第三方審查都沒看到的規格缺口（#59，754 PASS；Q4c 未驗見「已知缺口」）
- ✅ 2026-08-07 `brewup`/`sysup` 從 rc alias 抽成 `scripts/*.sh`（雙平台單一來源，消除兩份複本的漂移風險）+ 新增 `brewfix` 復原入口；`all-up.sh` 改直接呼叫腳本、去掉 `bash -ic`（`no job control` 雜訊隨之消失）；`ensure-rc-source.sh` 增舊 alias 清理（**刪行而非 unalias**——14 台巡檢實測 rc 內 alias 與 source 的相對順序因機器而異，macmini 反向，`unalias` 會多數生效少數靜默失效）（787 PASS）
- ✅ 2026-08-07 待辦批次收尾：`ship-state.sh` 兩項硬化（remote 刪除改走 `cleanup-stale-branch.sh`，帶 ls-remote 重驗＋lease；新增 `branch-diverged` 訊號）＋**unquoted heredoc 反引號 gate**（第 1c 節，掃描器附 RED/GREEN 自檢；灌 `ssh/config` 那三處同批改 `echo + cat`，但**當時給的理由是錯的**，理由更正見 `docs/archive/decisions-2026-08.md`「符合已知地雷的形狀」）＋ GitHub 多身分收斂本機完成 ＋ `migrate-github-remotes.sh`（822 PASS）

- ✅ 2026-08-08 **GitHub 多身分收斂 14 台全數上線、舊 key 已清**：`github-work` 與 `insteadOf` 整層消滅，key 檔名對齊 Host（`id_github_com` / `id_personal`）；48 條 remote 換寫、2 條 `insteadOf` 清除；db01 另驗 AC4（`krepo-common` 標準 URL 無改寫層直接可達）。執行紀律見決策節同日條目（#68，823 PASS）
- ✅ 2026-08-08 **dossier 機制加固**：新增 `tests/xref-gate.py` + 第 1d 節（13 條 fixture，含掃描器自檢）——把「唯一權威」從散文換成 gate；首次掃描實測抓出 1 條真死指標與 2 條指向雙份同名檔的基名引用，皆已修；`ship-state.sh` 的 append-only 偵測從單一字面擴為別名家族（附實際命中 heading，另有 3 條討論性章節的負向守門）；`dossier.md` 的決策生命週期從「直接刪」改為**保留原文 + 失效標記**，與 `docs/project-spec.md` 檔首早已自行採用的寫法收斂為一（850 PASS）

- ✅ 2026-08-09 handoff skill 收斂：錨點兩端完整性（unborn HEAD 的永久假 FRESH）＋ W1/R1 三指令下沉為 `survey` ＋ archive resume 的盲區與信任上限（889 PASS，eval 8/8）
- ✅ 2026-08-09 `brewup` 自我更新偵測：pull 換掉自己就 `exec` 新版重跑（`BREWUP_REEXEC` 迴圈防護），消掉「pull 進新版卻用舊版跑完」的一輪延遲。**這顆修正本身仍要被它修的 bug 咬最後一次**——各機第一次跑到的是修正前的 brewup，`dotsync` 不受影響（它以路徑逐支呼叫 helper）（944 PASS）
- ✅ 2026-08-09 `ensure-ssh-config.sh`：四份行內複本收斂成一支並接進 `brewup`，不在 inventory 的機器從此能自己跟上；加原子寫入＋完整性驗證＋**key 缺席守門**（擋自動重生把可用認證換成壞的）。過程被自己的測試抓到 `$(wc -c < 讀不到的檔)` 回空、`$(( ))` 當 0 的假綠（941 PASS）
- ✅ 2026-08-09 契約層抽取 Phase 1：`brewup` 補四個 ensure helper（補上「allup 走 brewup 而 helper 只掛 dotsync」的散佈窗口，含不誤報完成的兩層 warn）＋ branch-first 提升到 always-on ＋ 新增 `tests/run.sh` §18d 全隔離 fixture（902 PASS，兩個突變各驗過會紅）

- ✅ 2026-08-10 dossier 可攜性收斂：G7 transfer clean-room eval（Sonnet；baseline **1/2 失敗**、修後 2/2）＋ `STATUS-template.md` 全檔可攜化（5 增 5 刪，純置換）＋ 刪 `codex/AGENTS.md` 與 kernel C2 矛盾的全域斷言 ＋ Phase 3 DROP 四處清理 ＋ G6 非強加測試 2/2（956 PASS）
- ✅ 2026-08-10 G1b 成對實驗：實測 root `CLAUDE.md` 自動載入、root `AGENTS.md` 不會（clean room 不帶全域檔）→ kernel 擴為四份逐字複本，並定案 installer 必須裝 kernel 本體而非 pointer（956 PASS）
- ✅ 2026-08-09 契約層抽取 Phase 2：repo 根 `AGENTS.md`（kernel：safety floor 6 + fallback conventions 2；portable：權威矩陣 + working discipline）＋ 三份 kernel 逐字複本 ＋ `tests/kernel-gate.py`（漂移／掏空／缺份／marker／canary／可攜性，含 10 條自檢 fixture）。`claude/CLAUDE.md` 與 `codex/AGENTS.md` 交出被 kernel 承接的條文（956 PASS；四個突變各驗過會紅，含真實 repo 改一個字的漂移）
- ✅ 2026-08-11 brewup 尾段提示 bun 全域套件落後:**只提示、不自動升**——`bun` 本體是 brew formula 跟著 `brew upgrade` 走,但 `bun install -g` 裝的(如 `wrangler`)會改變部署行為,而 brewup 由 `allup` 在整個機隊同時跑。判準是 **Current != Update** 而非「有表格列就亮」:`bun outdated` 對被 semver range 擋住的 major 也照列(實測 typescript Current/Update 同為 5.9.3、Latest 7.0.2),寬鬆判準會變恆真噪音。+9 斷言(975 PASS),含混合表逐列判斷,並以突變測試確認防線非假綠。
- ✅ 2026-08-11 全域 CLAUDE.md 已知地雷拆檔:`claude/CLAUDE.md` 29,020→23,704 bytes(最長行 1,386→993),實地事故/負面結果/鑑別法/修復序列移入 `claude/known-hazards.md`。**拆法與上一批不同**——上一批整節搬走,這批是**每條地雷內部拆**(留觸發形狀+靜默後果+正確寫法,搬案例與診斷),因為地雷是「動手當下要知道」而非「改 gate 時才需要」。最大宗是 cask/Gatekeeper 條 4,005→約 550 bytes(它其實是運維故障、不是寫程式會踩的雷,已有 `brewfix` 入口)。966 斷言全綠。
- ✅ 2026-08-11 測試 gate 契約拆檔:root `CLAUDE.md` 29,661→15,807 bytes(最長行 15,123→429),gate 的判準/反例/設計理由移入 `docs/testing-contract.md`(按 `tests/run.sh` 節號組織)。**留在 always-on 的是行為約束**——何時必跑、以 exit code 判綠紅、xref gate 的「不放寬 pattern」,搬走即落入 H6 失效模式。順帶把 exactly-one-place 的例外從「kernel replicas」一般化為「**必須 always-on 且讀者載入不同檔**」(決策節有為何不消除那處重複)。966 斷言全綠。
- ✅ 2026-08-11 deep-review 同型掃描兩軸拆分 + 產出物化：根因是 skill 自己發的**跨軸豁免**——`reviewer-brief` 的「已掃過、無其他命中，不必重掃」，但 reviewer 掃的是**命中點軸**、fixer 缺的是**輸入空間軸**。已收窄該句作用域、SKILL 拆成兩條軸並要求掃描先於編輯、五個終態報告必填「同型處置紀錄」（單一定義 + 五處引用，`tests/run.sh` 1f 守覆蓋率，含逐處抽離的 RED 自檢）。新增 **F22/d8**（輸入空間軸）與 **F23/d9**（命中點軸）：F22 首跑因 reviewer 自己撐開兩軸判 **INVALID**（空條件），改注入式 harness 後 5/6；F23 首跑 5/5——R1 一輪即四處全修（966 PASS）
- ✅ 2026-08-13 deep-review 加**相依軸**(誰依賴我要改的東西;依關係找、非 grep)、終止報告分流
  「根因重複」的兩種成因(變更上→重做設計／方法上→換掃描維度,後者重寫救不了)、同型處置紀錄兩軸→三軸。
  外部提案逐條驗證後採五退三;**F22 重跑 6/6**(相依端欄首驗,以實跑反例計分)。983 PASS。
- ✅ 2026-08-13 repo-review 取證契約強化(**Codex 撰寫,本 session 只 ship、未 review**):
  codex reviewer 的 sandbox 從 `-s read-only` 改為 permission profile(repo 仍唯讀,只開 job 目錄下的
  TMPDIR/uv/pytest cache),`--strict-config` 讓不支援 profile 的舊版**硬失敗、不靜默落回 danger-full-access**;
  job 目錄以 realpath 擋在受審 repo 之外。理由寫在 diff 註解裡,故不另記決策節。
  +5 斷言(合併後 980 PASS),斷言打真實 argv。
- ✅ 2026-08-13 Codex shipping 授權對齊:kernel push 條改為指向 repo 授權表、`codex/AGENTS.md`
  改為重用 repo 既有 shipping workflow(無則 commit 並停)、`claude/CLAUDE.md` 移除「只有 Claude
  能 ship」的過期 note。四份 kernel 維持 byte-identical(975 PASS;理由見決策節同日兩條)。
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

## 事件記錄（event-time）

- **M-20260819-deep-plan-real-run · ** ✅ 2026-08-19 `deep-plan` 首次真實執行完成(handoff mtime 那批):9→2 blocking 兩輪、3/9 會 ship,
  並建立 `field-log.md` 累積真實使用結果(與 evals 的受控紀錄分家)。
  - 日期來源:migration-entry
  - 放棄:none
  - 重議:none
  - 關聯:STATUS.md cutover

- **M-20260819-p4-instantiated · 2026-08-19** **B-20260818-debt-03 · ** [x] **P4 待實例化**(2026-08-18 加)——**2026-08-19 已實例化,本條關閉**。落點與 ground truth 見
  `claude/skills/deep-plan/evals.md`「✅ 2026-08-19 已實例化：krepo-mops-announcement 公告查詢 API」。
  ⚠️ 尚未決定是否改用 dotfiles 內的 `c567204`(在本 repo、不可變、可消除跨 repo 私有依賴);
  切換前須以**樓層模型**跑一次確認仍抓得到並判阻斷,不通過就維持現狀。原文如下:
  - 日期來源:migration-entry
  - 放棄:none
  - 重議:見原文
  - 關聯:B-20260818-debt-03

- **M-20260818-deep-plan-structural-fixes · ** ✅ 2026-08-18 `deep-plan` 五條結構性 blocking 處置完畢:新增情境 **P8–P12** 與沙盒
  **dp2／dp3／dp4／dp5**(dp5 為補上的判定臂)。body 改動:brief §3 加 Blocking 欄、輸出契約加必填
  「層別」、Step 3 加 `NEVER re-classify a finding yourself`、落點改跟目標 repo、修正 scratchpad
  落點的錯誤外推、揭露 dossier 這條已知殘留管道。八次 Sonnet 實跑(含回歸 P1/P3/P7),1046 PASS。
  - 日期來源:migration-entry
  - 放棄:none
  - 重議:none
  - 關聯:STATUS.md cutover

- **M-20260815-dossier-backlog-split · ** ✅ 2026-08-15 dossier／backlog 分家落地:新增 `docs/backlog.md`(待辦兩節＋關閉歸檔慣例)、
  `ship-state.sh` 的 `detect_backlog`(**只驗章節完整性、刻意無量體門檻**)與抽出共用的
  `strip_fences`,規範同步 `references/dossier.md`／SKILL Step 2／`STATUS-template.md`＋
  新增 `BACKLOG-template.md`。STATUS.md 23564 → 13272 bytes、251 → 153 行、零 flag;
  未分家的 repo 零輸出零回填(有守門測試)。新增 5 條斷言並以 mutation 驗過會紅,1039 PASS。
  - 日期來源:migration-entry
  - 放棄:none
  - 重議:none
  - 關聯:STATUS.md cutover

- **M-20260815-project-blocked-routing · ** ✅ 2026-08-15 `/project` 分流表把 `BLOCKED` 拆成三格(CI 還在跑／check 失敗／protection 真的擋)
  ＋補 `DRAFT` 一列,判準改吃 `gh pr checks --required` 的 exit code。同批補上會紅的 eval:
  Scenario 18 ＋ `gh-stub-blocked-pending`,並修好 `gh-stub` 缺 `pr checks`／default 分支的洞
  (舊 stub 會讓 Scenario 15 **為錯的理由通過**)。三臂 Sonnet 全 PASS,兩臂對同一個 `BLOCKED`
  給出相反處置,證明判準真被讀到。1034 PASS。
  - 日期來源:migration-entry
  - 放棄:none
  - 重議:none
  - 關聯:STATUS.md cutover

- **M-20260815-linux-stat-fix · ** ✅ 2026-08-15 修 `tests/run.sh:4199` 的 stat 跨平台順序(GNU `-c` 先於 BSD `-f`)。
  Linux 上該條恆紅:GNU 的 `stat -f` 遇無效格式雖回 rc=1、卻已把 filesystem 統計吐進 stdout,
  與 fallback 的輸出相連。**與 `:3758` 註解描述的「假成功」機制不同**,已在註解分清。
  同批完成 hook 的全機隊散佈(14 台)＋跨平台實測(Linux／Darwin 皆正確擋下)。

  - 日期來源:migration-entry
  - 放棄:none
  - 重議:none
  - 關聯:STATUS.md cutover

- **M-20260820-doc-governance-pilot · 2026-08-20 文件治理 dotfiles pilot 完成**:repo-local scanner、logical-entry find、event-time history、active/backlog/plan lifecycle、xref compatibility 與 shipping fail-closed 已落地。deterministic suite 22 tests、全 repo 1064 assertions、Claude Code／Codex clean-room eval 6/6 通過；governance surface 49,644 bytes，未提高 49,675-byte 上限。舊版 plans 僅保留為凍結紀錄，不進搜尋或 xref source。
  - 日期來源:direct
  - 放棄:沿用失敗舊 plan 架構，或以提高 self-budget 掩蓋治理面膨脹
  - 重議:deterministic corpus、雙 agent eval 或連續 ship pilot 出現實際 RED
  - 關聯:D-20260820-legacy-plans-record-only;docs/plans/2026-08-20-doc-governance-implementation-plan.md

- **M-20260820-doc-governance-review-fixes · 2026-08-20 文件治理首輪審查修復完成**:第三方實測提出的 17 條 blocking 全部先以 fixture 重現再修復，涵蓋未追蹤 Markdown、xref crash／節名邊界、bootstrap fail-closed、檢索 oracle 洩漏、legacy/adopted 分流、Unicode slug、可信 scanner 邊界與搬移後程序指標。deterministic suite 26 tests、全 repo 1071 assertions、G7 Sonnet 成對 eval 皆完整成功；governance surface 49,649 bytes，仍未提高 49,675-byte 上限。
  - 日期來源:direct
  - 放棄:執行受檢 repo 提供的 scanner，或以 target-side checksum／allowlist 擴大信任面
  - 重議:可信 core 需要支援獨立版本協商，或跨 repo schema 出現無法由版本庫端 fail-closed 表達的相容需求
  - 關聯:D-20260820-trusted-doc-scanner;docs/testing-contract.md
