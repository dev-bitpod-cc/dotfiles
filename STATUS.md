<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-03)

---

## 進行中

**lftp 納入標準工具鏈(取代 OpenSSH 內建 sftp)** — 實作完成待 ship(branch `feat/lftp-sftp-client`)

- Context:內網主機全走 SSH CA cert(`id_autogen` + cert),需要一個比 `/usr/bin/sftp`
  更堪用的互動式 SFTP client(續傳、mirror、並行、書籤)。
- 做了什麼:`lftp` 加入 mac/linux 兩支 setup 的 brew 清單與驗證區塊;新增版控的
  `lftprc`(root-level,循 `tmux.conf` symlink 慣例)+ 兩支 setup 的 symlink 部署步驟
  (mac 5.9 / linux 4.9),並 `touch ~/.lftprc.local`;CLAUDE.md 工具表與全域可用工具行同步。
- AC:`tests/run.sh` exit 0(526 pass);`lftp eagle03` 裸主機名走 sftp、put/get/rm
  往返 exit 0 且內容一致——**皆已實測通過**,遠端測試檔已確認清除。
- 待確認:`~/.lftprc` symlink 已在本機(macmini)就地建立;**其他主機需 push 後
  `dotsync` + 重跑 setup 才會生效**,尚未 push。

**本次踩到的坑(非顯而易見)**

- **lftp sftp backend 的 `ls <單一檔案>` 走 opendir,對非目錄一律報 "No such file"
  並回 exit 1**——上傳其實已成功,是驗證指令自己失敗,極易誤判成傳輸失敗而重試/回滾。
  列單一檔案要用 `cls -l <path>`(走 stat)。已就地寫進 `lftprc` 註解,因為踩點在使用時而非讀 dossier 時。

---

## 關鍵決策(附理由)

- **2026-08-03 codex 的決策發聲採「產原料寫進行中、ship 端蒸餾」,不讓 codex 學 dossier 規範**:
  #34 暴露 cross-agent 記錄斷點——codex 改 `codex/skills/`、Claude 端 ship,理由只能從 diff 反推。
  界線是原理性的:**機制(補 gate、加測試)反推無損,但否決的方案與死路在 diff 裡永遠沒有痕跡**
  ——走過的路才留下 diff。故 `codex/AGENTS.md` 只要求把推不到的那部分追加到 STATUS.md
  「進行中」(尺寸 flag 刻意不掃該節),不 commit 不管格式,蒸餾與章節語意留 ship 端;並帶
  「純機制改動免寫」免除條款(always-on context,無免除=每次小改都付儀式成本)。
- **2026-08-03 repo-review 多輪 autofix 死鎖以「gate 一次、之後查 ownership」解,不放寬 clean
  要求**:C2 轉交的 F5 判定為 **true positive**——`--autofix` 要求 clean worktree,而規範要求每輪
  rerun helper,R1 修完 worktree 必髒 → 第二輪必得 `autofix-safe:no`,契約自我封死。解法是
  `--autofix` 只當**首次編輯前的一次性起始 gate**,後續回合改跑不帶 flag 的 helper 並逐一比對
  dirty path 歸屬,遇 pre-existing/concurrent/未記錄即停。**反向解(放寬 clean 要求)會讓「絕不碰
  使用者變更」整條保證失效**——根因是判定時機錯置,不是判定太嚴。
- **2026-08-03 autofix 安全判定補 `base-not-commit`——tree base 的 ancestor 檢查回 `n/a` 不是
  `no`**:`HEAD~1^{tree}..HEAD` 這類 base 先前一路穿過 ancestor gate 拿到 `autofix-safe:yes`,
  等於在無法界定祖先關係的範圍上放行改檔+checkpoint。新判定置於 ancestor gate **之前**,條件
  `BASE_TYPE != commit && BASE_HASH != EMPTY_TREE`——刻意保留 empty-tree baseline 的既有豁免
  (該路徑語意明確且已有測試,一併擋掉會誤傷首次全 repo review)。
- **2026-08-03 Codex reviewer 的 fresh context 要顯式 `fork_turns=none`,不靠預設**:spawn 介面
  預設繼承全部 turns,規範只寫「用 fresh-context subagent」等於**spec 上宣稱 fresh、行為上帶著
  parent 的實作意圖與嫌疑清單**——delegate 的價值(獨立重推結論)當場歸零。介面無法建立無歷史
  reviewer 時一律明說降級,不得聲稱跑過 fresh-context pass。
- **2026-07-29 剝 code fence 採 `\001` 哨兵前綴,不是丟棄也不是清空**:兩個下游各有硬要求
  ——條目 flag 要報行號故**行號須對齊原檔**(丟棄會讓 NR 全數位移);`dossier-sections:` 佔比
  要正確故**長度須保留真實**(清空會讓 fence 重的章節被低估到**排名倒轉**,實測 26KB 決策節
  報成 403 bytes 沉到 4.5KB 節後面,而該表正是要 agent 據以挑收斂對象)。**量長度前必須剝
  哨兵**,否則每 fenced 行虛胖 1 byte、短行多的 fence 讓單節佔比破 100%(實測 149%)。
- **2026-07-29 哨兵只中和「行首錨定」的 pattern,非錨定比對必須自行 skip 哨兵行**:
  `^##`/`^#{1,6}`/`^-` 三個家族靠前綴即失效,但「進行中含 ✅」用的是無錨點的 `/✅/`——
  圍欄內貼的測試輸出(滿是 ✅)照樣被看見。**且加哨兵反而製造新方向的誤報**:圍欄內的假
  標題原本會把 `in_sec` 關掉(歪打正著),哨兵讓它不再切節後,`in_sec` 一路開著把圍欄內的
  ✅ 全算進「進行中」。修法 `/^\001/ { next }`。**新增消費點時先問:我的 pattern 有錨點嗎?**
- **2026-07-29 大輸入的存在性比對一律 herestring,禁用 `printf | grep -q`**:`grep -q` 命中即
  退出,大輸入下上游 printf 吃 **SIGPIPE(141)**、pipefail 讓整條判偽——簽章偵測的 `!` 反轉後
  **正常的大 dossier 被誤報「簽章不符」**(該 flag 的處置是「停下、勿當 dossier 改」,等於整份
  檔案被拒絕處理)。小檔不發作故潛伏至今(115KB fixture 實測 rc=141)。完整現象、krepo 的同型
  前例、以及「守門測試命中點須在前段」已入 `claude/CLAUDE.md` 已知地雷。輸入恆小的三處
  remote/gh 比對不動(no failing scenario, no change)。
- **2026-07-23 macOS 凍結內建 CLI 的應對分兩層,不用 gnubin 取代**:互動/運維工具用 brew
  新版(rsync 入 setup-mac-env.sh,解 openrsync 旗標坑);skill 腳本/tests 只用 POSIX 確定性
  子集(LC_ALL=C 量 bytes),需要 GNU 行為顯式 gawk+command -v 檢查。gnubin PATH shadowing
  是隱形環境依賴——hooks/cron 的極簡 PATH 下 brew 路徑常缺席,靜默 fallback 回 BSD 版=
  門檻漂移換個地方發生。已入全域 CLAUDE.md 已知地雷。
- **2026-07-23 dossier 治理量測下沉三訊號,蒸餾留判斷層**:總量 bytes(風格不敏感後盾)、
  最長行 bytes(巨型單行早期糾正;macOS BSD awk 的 length 一律數 bytes,字元門檻跨平台
  不確定,故量 bytes)、決策/里程碑條目 bytes(一行化/結論體的機器面)。蒸餾內容判斷與
  傘狀雙重記載比對(語意匹配、誤報面大)不下沉。此為 evint「prose 下沉為腳本」方法論回打自身。
- **2026-07-22 殘留 branch 衛生訊號放 ship-state.sh,不放 /ready4quit**:/project log 高頻且
  merge 完當下即清掃時機;ready4quit 三檢查全是「未送出」方向,已 merge 殘留屬反方向;
  另建腳本=第三份 default 偵測副本。判定用本地 ref 不碰網路,cleanup-cmd 前置 fetch --prune;
  只印訊號不代刪。
- **2026-07-22 無 protection repo 改「PR 預設、直推降 escape hatch」**:u3 eval 實測「PR 可選」
  會讓 PR 行為上不存在(spec-behavior drift)。維持不開 protection——真理由是常態 bypass 會
  養成壞習慣(「開了會擋死自己」是錯的反對理由,已收回)。腳本 verdict 同步改印 PR——verdict
  是 model 照抄的東西,腳本與 prose 不一致=誘導破口。
- **2026-07-22 bootstrap 豁免以腳本判定界定作用域,不寫 prose 條款**:成立條件=ship-state
  實測「遠端零 branch」,baseline 一 push 條件即永久為假、豁免自動失效——授權活在會自己
  失效的機器判定裡,不在對話記憶(實證:prose 豁免曾蔓延到後續 commit 直落 main)。
- **2026-07-22 ship-state.sh 破例碰網路(ls-remote),限縮 default: NONE 分支**:「遠端零
  branch」(可建 baseline)與「有 branch 但定位不到 default」(絕不可推)處置完全相反,
  未 fetch 的 clone 下本地 ref 無法分辨;正常路徑零網路,反例已入 tests。
- **2026-07-21 Codex skill authoring 採全域短入口+dotfiles local-delta guide**:
  `~/.codex/AGENTS.md` 只強制先讀 system $skill-creator 與版控 guide,避免 always-on context
  膨脹;`ensure-codex-guidance.sh` 比照 skill 散佈機制幂等 symlink。
- **2026-07-21 skill 腳本維持「git 唯讀+印解析完成指令」,不直接 mutation**:腳本只印
  squash-cmd/branch-cmd 供照抄,守唯讀慣例又消除 model 心算 hash 錯誤面;不抽跨 skill
  共用 lib(symlink 邊界破壞自包含;翻案條件=出現第三份副本或副本需同步修改)。
- **2026-07-21 deep-review 以 clean-room 重寫做低頻探針稽核**:蒸餾需求層規格讓禁讀實作的
  subagent 盲寫再比對——收斂處=機制被需求逼出、分歧處=規格歧義;比對判準不對稱(機制
  覆蓋以實戰版為基準)。squash 維持單錨點,改印「壓掉 N 顆既有 commit」警告(成本近零)。
- **2026-07-21 PR1 誤掃入他線工作後拍板 bundle 不拆分**:拆分需對三個混檔 hunk 外科手術且
  動另一 session in-flight 狀態,風險大於收益;教訓=多 session 共用 working tree 時 commit
  一律顯式路徑。
- **2026-07-21 全域規則四處 carve-out**:bun/uv 限新專案+自有專案(尊重既有 lockfile);
  Uncertain 自主執行取最合理解讀但假設必須落地標待確認(不可逆/對外不在 fallback 內);
  bug-fix 重現測試補可行性豁免(先重現再修順序不變);commit types 補 perf/ci。
- **2026-07-20 autocodex 傳輸層改 headless codex exec,不走 plugin broker**:plugin 等待端無
  watchdog,通知一斷即永久靜默等待(F13/F14 共同上游);exec 的完成訊號=進程退出+報告落檔
  兩個 OS 層級事實,雙訊號死亡偵測退役為 exit 契約。引數與儀式不變,plugin 暫留。
- **2026-07-20 wrapper 的 range 驗證必須對照下游契約,不能只對照 git**:同 bug class 三現
  (git 可容忍、下游 review-context 拒絕、報告非空→假成功);跨腳本契約只能靠斷言釘死,
  stub 測不出來。
- **2026-07-20 settings.json 撤銷 push-to-main 放行(防線對齊)**:prose 最高紀律與 harness
  明放行反向失守;選移除非 deny,保留使用者明示直推場景。本機 fable 偏好分流
  `~/.claude/settings.local.json`,repo 基線維持 opus[1m]。
- **2026-07-20 skill 內 runtime 路徑慣例=`~/.claude/skills/...`**:symlink 由 setup 建立、與
  clone 路徑解耦;`~/.dotfiles/...` 僅描述原始碼位置。已寫入 skill-building-guide。
- **2026-07-20 codex skill 散佈補 ensure-codex-skills.sh**:setup 的連結邏輯只在跑 setup 時
  作用而 dotsync 不套用——缺的是散佈路徑,不是連結邏輯。
- **2026-07-17 無 protection 兩難以「merge 最後一哩」解,不走分級直推**:卡點在 PR 開完
  沒人接,不在流程本身;使用者明說 merge 即 agent 接手(squash+清 branch+同步 default),
  不打破 never-push-default 鐵律、也不強推 protection。
- **2026-07-17 dossier 增設總量治理(compaction)規則**:krepo 實證 Session Log append-only
  佔全檔 60%;原規範只防「新增垃圾」不防「總量單調膨脹」→修剪規則+log Step 2 衛生檢查
  (krepo 已依此收斂 599→201 行)。
- **2026-07-17 dossier 記錄時點搬到事件當下**:skill 只在頭尾喚起而決策/死路發生在過程中,
  等收尾 context 可能已壓縮;全域規則加即時記錄,log Step 2 降級為「核對補漏」。
- **2026-07-16 git 為唯一跨主機媒介**:不同步 `~/.claude/`(handoffs/memory)跨機——同步
  衝突、錨點跨機語意複雜化、敏感內容風險;krepo 已證明 repo-resident+git 可行。
- **2026-07-16 /project 取代 /uap 而非並存**:雙入口=觸發混淆+double-source;
  disable-model-invocation 下鏈式呼叫不可行,只能複製防護邏輯(違反 single-source)。
- **2026-07-16 STATUS.md 為 dossier 載體,不新建 PROJECT.md**:尊重 krepo 自然湧現且活躍
  維護的慣例;避免同 repo 兩個角色重疊的檔案。
- **2026-07-16 不引入 Linear/外部 tracker**:痛點由 repo-resident 檔案+既有 skill 生態覆蓋;
  缺的是慣例固化,不是新工具。
- **2026-07-16 settings.json 以 opus[1m] 為共享 model 基線**:單機一次性模型偏好不 commit、
  不傳播全機隊。

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
