<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-08)

---

## 進行中

(無進行中工作項——dossier 機制加固已於 2026-08-08 完成,見里程碑)

---

## 關鍵決策(附理由)

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。**歸檔判準**：已固化且不再影響現行方向 → 歸檔；仍在生效的一律不歸檔（死路＝防重工、技術債＝未解決，移出 always-on 即失效）。超標時**優先歸檔、不要為幾百 bytes 去壓無關舊條目**——那個動作重複幾次本身就是訊號。

- **2026-08-08 xref gate 只保障 dotfiles,但它服務的規範是全域的——這個不對稱要講明**:
  `tests/run.sh` 只跑本 repo,故「唯一權威」指標的機械守門僅及於 dotfiles;而同批改的
  `ship-state.sh`(append-only 偵測)與 dossier 規範(失效標記)**跨 repo 生效**。
  故不得說「其他 repo 零影響」(它們未來的 `/project log` 行為確實變了),也不得說
  「失效標記已有守門」(其他 repo 的指標沒人掃)。**不擴大到 `ship-state.sh --repo` 的理由**:
  其他 repo 的引用可能指向 repo 外(如 `~/Projects/...`),需要另一套外部路徑政策;
  規範已要求指標寫成 gate 可解析的形狀,將來擴大時零回填。
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
- **2026-08-08 散佈憑證變更的三條紀律**(全機隊改 SSH 身分與 key 檔名時實地得出):
  ①**`cp` 不 `mv`**——新舊並存,任一步失敗都不斷線;遠端拉 dotfiles 靠的正是 GitHub SSH,
  認證改壞又散佈出去就拉不到修正,只剩 `ssh <host>`(內網 CA cert)進去手改。
  ②**散佈前提是變更已進 `origin/main`**——遠端 `dotsync` 拉的是 main,本地 branch 未 push
  時散佈等於空轉(實地踩過一次,以為散完了其實什麼都沒變)。
  ③**先散一台走完全程再放其餘**——挑最有代表性的那台(這次是 db01:remote 最多、唯一有
  `insteadOf`、且有 krepo 可驗依賴路徑),不是挑最安全的。
- **2026-08-08 跨機隊的破壞性收尾,要把前提檢查放進每台自己的執行裡**:刪 14 台的舊 key 時,
  每台先自檢「config 指向新檔名／新檔存在／兩個身分認得對」三道,任一不成立即跳過該台、
  零刪除。**判準:前提由執行端當場驗,不由發起端事先假設**——發起端的「我剛剛驗過了」
  在並行散佈裡是舊資訊。形狀同 `cleanup-stale-branch.sh` 的執行當下重驗。
- **2026-08-08 key 檔名要反映**所有**角色,不只最顯眼那個**:原提議把個人 key 改叫 `id_github_me`
  (對稱於 Host `github-me`),使用者指出它同時是各主機 `authorized_keys` 的 fallback 私鑰,
  故定為 `id_personal`。**判準:命名跟著角色集合走,不跟著最常用的那個場景走**——叫 `id_github_*`
  會讓後來的人以為「不用 GitHub 就能刪」,而那把 key 是 CA cert 失效時進遠端機器的唯一後路。
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
- **「/project log 包裝/並存 /uap」**:disable-model-invocation 下無法鏈式呼叫,只能複製
  pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,直接取代。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:實證 general-rag-cs 的已消費
  STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] R4 non-blocking 餘一項:**新增 prose 的中文半形標點與既有全形混排**。2026-08-08 未做——
  「新增 prose」指哪一批已不可考,純風格、無失敗案例,且該日又寫入大量中文 prose(移動標靶)。
  要做就一次全檔統一,不要逐批追。其餘三項(Transfer 模式 commit 歸屬、evals/README 路徑基準、
  handoff evals H4 排序)已於 2026-08-08 修畢。
- [x] dossier 訊號 R5 non-blocking 五項——2026-08-08 全數修畢:sections 標題行計入所屬節
  (加總 == 檔案 bytes,附斷言且經突變驗證);SKILL 的「唯一的例外」補上第二個(使用者明說不動);
  最長行 flag 補「風格訊號、非硬門檻」的處置時機;S12 fixture 的巨型單行改寫明 >1000 bytes
  (原寫 >800 生不出它自己要求的最長行 flag);**條目作用域與 ✅ 掃描改端錨定**——原為子字串比對,
  `## 進行中(已完成 M1)` 會被當里程碑節而恆誤報(兩條斷言各自經突變驗證)
- [ ] **「tests/stub 有覆蓋、實戰未驗」一組**(遇到對應情境時順手確認即可,不必專程做):
  SessionStart hook 落後提醒(真實落後的 clone);autocodex exec 的 resume 分支(exit 4 救援階梯,
  三輪實跑皆一次成功、只有 stub 覆蓋,F15(b) 待真實空報告);review-anchor 的 stale STOP 與
  codex-next 冪等(F16 b/c,待 autofix 迭代中真的 rebase/重試);repo-review 新契約(F16–F18 規格
  覆蓋,待多輪 autofix 確認弱模型不會退回每輪帶 `--autofix`)
- [x] hook matcher 僅 `startup`——2026-08-07 已擴為 `startup|clear|compact|resume`,tests 第 16 節覆蓋
- [x] 測試節那行待補 git-hygiene 的新教訓——2026-08-07 已補。**目標檔是 repo 根的 `CLAUDE.md`
  (第 133 行、單行 5.6KB),不是原記的 `claude/CLAUDE.md`**(後者的測試節講的是「何時該寫測試」)。
  順帶補上該行從未索引到的 **SessionStart hook 守門**——`git-hygiene` 先前也完全沒有細節,
  等於這兩塊的覆蓋範圍讀不出來
- [ ] Scenario 11 的「merge 但無 PR」分支只在 SKILL body 一行指標帶到 ship-paths,GREEN 實測中
  弱模型未展開讀——非違規故未補;重現才加明示(Iron Law)
- [ ] pressure-tests S8/S9/S12 沙盒未納入 `claude/evals/setup-sandboxes.sh`;S10(transfer
  credentials)與 S12(dossier 三 flag 蒸餾紀律)連首輪實測都還沒跑
- [x] `claude/evals/*.sh` 已於 2026-08-08 納入全部四個 gate(shellcheck / `bash -n` / 全形標點 /
  heredoc)。納入時該檔本來就是乾淨的,零 findings——**便宜的守門要趁乾淨時加**,等它長歪再加
  就得先還債。該檔全靠 heredoc 灌 fixture、內容常是 prose,正是「反引號寫在 body 字面」的高風險區
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
> 2026-08-05／08-06 各批已歸檔至 `docs/archive/milestones-2026-08.md`。

- ✅ 2026-08-07 deep-review skill-authoring one-shot gate + R5 terminal state（#51，665 PASS）
- ✅ 2026-08-07 ship 說法語法：說法即授權、merge 預設保留、`review-terminal` STOP、merge 受阻分流（#52，672 PASS）
- ✅ 2026-08-07 squash-merge 殘留偵測 + `cleanup-stale-branch.sh` 安全清除（#53，699 PASS）
- ✅ 2026-08-07 Scenario 15 補測：`BLOCKED` 不得自動 `--admin`，正反兩向 PASS（#54）
- ✅ 2026-08-07 ready4quit 強化 + 四輪第三方審查修復：證據語彙拆兩軸（強度 × 殘留）、Step 2 memory/dossier 雙出口、背景任務證據來源改 `tasks/` 且 liveness 不得由 `.output` 推斷、`git-hygiene.sh` 補遠端事實與多 remote 一致性、hook 增報 worktree 雙寫入者；**eval 從零 GREEN 到 8 條 PASS**，其中 Q4a/Q5 是 eval 自己抓出、四輪第三方審查都沒看到的規格缺口（#59，754 PASS；Q4c 未驗見「已知缺口」）
- ✅ 2026-08-07 `brewup`/`sysup` 從 rc alias 抽成 `scripts/*.sh`（雙平台單一來源，消除兩份複本的漂移風險）+ 新增 `brewfix` 復原入口；`all-up.sh` 改直接呼叫腳本、去掉 `bash -ic`（`no job control` 雜訊隨之消失）；`ensure-rc-source.sh` 增舊 alias 清理（**刪行而非 unalias**——14 台巡檢實測 rc 內 alias 與 source 的相對順序因機器而異，macmini 反向，`unalias` 會多數生效少數靜默失效）（787 PASS）

- ✅ 2026-08-07 待辦批次收尾：`ship-state.sh` 兩項硬化（remote 刪除改走 `cleanup-stale-branch.sh`，帶 ls-remote 重驗＋lease；新增 `branch-diverged` 訊號）＋**unquoted heredoc 反引號 gate**（第 1c 節，掃描器附 RED/GREEN 自檢；灌 `ssh/config` 那三處同批改 `echo + cat`，但**當時給的理由是錯的**，見決策節首條）＋ GitHub 多身分收斂本機完成 ＋ `migrate-github-remotes.sh`（822 PASS）
- ✅ 2026-08-08 **GitHub 多身分收斂 14 台全數上線、舊 key 已清**：`github-work` 與 `insteadOf` 整層消滅，key 檔名對齊 Host（`id_github_com` / `id_personal`）；48 條 remote 換寫、2 條 `insteadOf` 清除；db01 另驗 AC4（`krepo-common` 標準 URL 無改寫層直接可達）。執行紀律見決策節同日條目（#68，823 PASS）
- ✅ 2026-08-08 **dossier 機制加固**：新增 `tests/xref-gate.py` + 第 1d 節（13 條 fixture，含掃描器自檢）——把「唯一權威」從散文換成 gate；首次掃描實測抓出 1 條真死指標與 2 條指向雙份同名檔的基名引用，皆已修；`ship-state.sh` 的 append-only 偵測從單一字面擴為別名家族（附實際命中 heading，另有 3 條討論性章節的負向守門）；`dossier.md` 的決策生命週期從「直接刪」改為**保留原文 + 失效標記**，與 `docs/project-spec.md` 檔首早已自行採用的寫法收斂為一（850 PASS）

## 已知缺口

- **eval 的受測 subagent 拿不到 deferred tools,部分契約在沙盒中無法構造**:2026-08-07 實測——
  主 session 呼叫 `CronList` 得 `No scheduled jobs.`、`TaskOutput` schema 也載入;探針 subagent
  (`Tools: *`)對 `select:CronList,TaskOutput,TaskList` 一律得 `No matching deferred tools found`。
  故凡「該工具查得成」才成立的情境做不出來——ready4quit **Q4c**(`RECALLED + ✓` 的收斂措辭,需
  最低證據等級剛好是 RECALLED)因此無 GREEN 證據。symlink 前置已於 2026-08-07 合併後解除,但
  **手動驗證第二次嘗試仍無效**,且暴露原程序自身兩個錯:①`~/.dotfiles` 不能當 pwd(harness 持續
  往 `claude/settings.json` 寫 drift,Git 衛生恆為 ⚠);②**「全新且安靜的 session」自相矛盾**——
  沒有對話歷史時回憶型面向落 `PARTIAL` 而非 `RECALLED`,「安靜」給 ✓、「全新」卻毀掉 RECALLED。
  另有未證實的第三道障礙(單次觀察):`tasks/` 的孤兒條目讓背景面向被迫 PARTIAL,若為常態則本條
  結構性不可達。**v3 程序**(改用沙盒 repo、開場先做幾件唯讀的事製造可回憶歷史、跑前先 `ls`
  確認 `tasks/` 為空)見 `claude/skills/ready4quit/evals.md`——**別再照舊程序跑**。
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

- **deep-review anchor 跨批次會 stale**(2026-08-07 核實後**改寫**,原記載有誤):anchor 只在 autofix
  的 `record` 寫入,走「codex 第三方審查」觸發詞路徑時不 record → 讀到**上一批**的 anchor(2026-08-05
  實遇:本批 3 顆卻給出會壓掉 5 顆的 reset 目標)。
  **原條目寫「解法＝把 codex-next 的祖先檢查移植給 squash-cmd」是誤記**:`cmd_squash_cmd` 一直
  都呼叫 `verify_hash_usable`(hash 存在 + `merge-base --is-ancestor`),與 `codex-next` 共用同一個
  函式,`tests/run.sh` 也早有「anchor 非 HEAD 祖先 → STOP」守門(自 #18 起)。
  **且那道檢查照定義擋不到殘餘風險**——同一條 branch 上連跑兩批時,舊 anchor 仍是 HEAD 祖先。
  真正兜住它的是 2026-08-06 的 subject 掃描(停在第一顆語意 commit)。無實地失敗案例,不再加工。
  **教訓:缺口條目寫「解法已知、剩移植」時,那句本身也要有人去核對一次**——它讀起來像已經
  查證過的結論,實際上是當時的推測,而後來的人(包括我)會直接照做。

- **「規則的對稱面／使用點」與「同型掃描」都只有文字原則、無產出物**(兩者同型,合併記):
  - *Step 2 對「規則只寫了一半」無偵測*:2026-08-05 抓到 `add -A` 例外的使用點缺口純屬**偶然**
    (`CLAUDE.md` 的例外文字剛好點名 `deep-review/SKILL.md`)。同 session 反證:#43 走過同一個
    Step 2,F2/F3 兩條 blocking 照樣漏出,由第三方審查才抓到。
  - *deep-review 的同型掃描*:對「測試」有機械化 gate(`verify-tests.sh` exit code 契約),對
    同型掃描只有 brief/SKILL 的文字要求。2026-08-05 krepo 實戰回饋:連跑四輪修復時最易被跳過
    的正是這類原則性敘述,且該次漏的就是它。
  **共同結論:不補文字原則**——文字是最易被跳過的那層。要做就做**訊號化/checklist 化**
  (如 `ship-state.sh` 偵測變更集含 `CLAUDE.md`／`AGENTS.md`／`SKILL.md` 時印對稱面候選,不判語意,
  形狀同 `dossier-flag`;或要求 fixer 每輪寫出「本輪抽象出的規則 + `rg` 命中數」)。做不成
  exit-code gate——規則是語意抽象出來的,機器不知道要 grep 什麼。現有防線只有第三方審查。

- **Mac 上 brewup 會被 codex cask 掛死(Gatekeeper)**:2026-08-07 第三次發作。**復原已有入口**:
  `brewfix`(`scripts/brewfix.sh`,預設唯讀、`--fix` 才動手)。機制、鑑別法、三條走不通的預防路徑
  (事後手動先跑／`--no-quarantine` 已從 Homebrew 6.x 移除／內建核可繼承只服務 `.app`)全文見
  `claude/CLAUDE.md`「已知地雷」,**此處不重述**。
  **仍未解的部分**:確切觸發條件未知且**事後無法重現**(同版本內容複製到新路徑執行正常,推測成功
  評估以 cdhash 快取、卡死記錄才以路徑為 key),要重現只能等真正出新版。**未決**:xattr 預先設
  `0x0040` 技術上可行(fetch 與 upgrade 之間有時間窗,propagate 只動 bit 8),但前提「首次核可流程確為
  主因」已被上述負面結果動搖,代價卻是確定的(拿不到 tarball 簽章身分、做不了 signer 比對)。
  **用確定的代價換不確定的效果——暫不做**,優先靠已實證的復原路徑。

- 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,
  改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+credentials 明文散於三台。
- **`agy`(Antigravity CLI)只手動裝在 macs,未寫進 `setup-mac-env.sh`**:2026-08-07 因 gemini-cli
  已於 2026-06-18 停服而改裝其後繼(`brew install --cask antigravity-cli`,binary 名 `agy`)。
  後果:新機器跑 setup 不會裝、macmini/m4mini 目前也沒有。該 cask 標 `auto_updates`,故 `brewup`
  不會升它(除非 `--greedy`)。**它沒有 `generate_completions_from_executable`,不會踩 codex 那個
  Gatekeeper 坑**,但首次執行仍會走核可流程——要裝就在該機 console 前跑一次。
- **使用者的個人 MacBook 不在 `inventory.conf`**(家中經 VPN ssh 進 macs),故 `dotsync` / `allup`
  都涵蓋不到。歷來如此、非本次造成——以前 `brewup` 自帶 `git pull` 讓它看起來像自動的。
  **2026-08-08 更正**:原記的手動指令 `git pull && ensure-rc-source.sh` **不會更新 `~/.ssh/config`**
  ——`ensure-rc-source.sh` 只補 rc 的 source 行、完全不碰 ssh(grep 命中 0)。所以那台的
  `~/.ssh/config` 自上次跑 `setup-mac-env.sh` 後就沒動過。要重生得自己灌:
  `{ echo "# 此檔案由 dotfiles setup 腳本產生"; cat ssh/config; } > ~/.ssh/config`。
  **它連 macs 的能力與 key 改名無關**:macs 的 `authorized_keys` 那把指紋 `SHA256:7QdI3DDka…`
  == `id_personal.pub`,而改名只改本地檔名、公鑰內容一個 byte 沒動;macs 的 sshd 另外吃 CA
  (`TrustedUserCAKeys`)。**待確認是刻意(終端設備不入清單)還是缺口**;納管走 `add-new-host.sh`
  ——但浮動 VPN IP 未必適合 inventory 的 `<alias> <ip>` 形式。
  **2026-08-08 全機隊完成 GitHub 身分收斂與 key 改名時,這台是唯一沒動到的**——它仍是舊
  `ssh/config`(有 `github-work`)、舊 key 檔名,**且那樣是可用的**(舊 config 配舊檔名自洽)。
  要跟上得手動:`cp` 出新檔名 → pull → 重生 `~/.ssh/config` → `migrate-github-remotes.sh --apply`
  → 驗兩個身分 → 才刪舊檔。**順序不可顛倒**,先重生 config 再 cp 就會斷 GitHub 認證。

## 移交準備度

(個人 infra,暫無移交打算——平時留空)
