<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec;ship 時同步;移交前補齊完整度。維護者可能另有工具輔助,
        但**規範本身在此、不在工具**——沒有那些工具也照樣維護得下去。
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-10)

---

## 進行中

(無進行中工作項——契約層與 dossier 可攜性兩批已收斂,見里程碑。凍結計畫:
`docs/plans/2026-08-09-repo-contract-extraction.md`、`docs/plans/2026-08-10-dossier-portability.md`)

**剩餘工作全部帶觸發條件、皆不在進行中**:①**Phase 3 改名 DROP**——Codex 進生產線再議;
②**Phase 4 installer DEFER**——觸發是「出現第一個**自己有權安裝契約**的移交 repo」,**不是**
「外部 repo」(那正是不得 apply 的對象);③**G5 DEFER**——隨 generated-docs 工具一起;
④**transfer 的 portability 步驟 DEFER**——真實移交當下依實況寫,之後回灌模板
(n=1 的一次性工作寫進 skill,成本高於手做,且自動化「剝除」比正解「具名保留」差)。

---

## 關鍵決策(附理由)

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。**歸檔判準**：已固化且不再影響現行方向 → 歸檔；仍在生效的一律不歸檔（死路＝防重工、技術債＝未解決，移出 always-on 即失效）。超標時**優先歸檔、不要為幾百 bytes 去壓無關舊條目**——那個動作重複幾次本身就是訊號。

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
- **2026-08-10 模板可攜性的判準:「規範本身在此、不在工具」**——形狀不是設計出來的,是 krepo 現場
  自行收斂的檔頭(krepo 全清、krepo-common 半清,**兩次獨立手動偏離就是 RED**)。**但 G7 實測證明
  死指標並沒有弄壞接手者**(baseline 3/3 全綠:agent 根本不追那條「規範全文」)——所以這是**衛生修復
  不是行為修復**,正當性來自「交出去的檔含指向不存在位置的引用」。**先跑 baseline 才知道這件事**:
  否則會帶著錯理由改、還會多加不需要的補充行。全文見 `docs/plans/2026-08-10-dossier-portability.md`
  「W0 — G7：transfer clean-room eval（先跑，它是 W1 的 oracle）」。
- **2026-08-10 branch-first 是 Claude Code 產品原生的,所以輕量 fixture 量不到 kernel 的邊際效果**:
  G1a/G2 成對實驗兩臂皆 3/3 另開 branch,唯一差異是命名。**這是 fixture 無鑑別力,不是 H6 被推翻**
  ——H6 是高負載情境(多 repo／resume／指令競爭),要重現得先有帶負載的 fixture(目前沒有)。
  **推論:kernel 的 branch-first 對 Claude 邊際價值有限,真正不可取代的是 Codex 與協作者的 clean
  clone。** 相對地 C2(決策紀錄過濾器)沒有原生對應,G4/G4b 因此**有**鑑別力且 2/2 GREEN。
  情境全文見 `claude/evals/contract-evals.md`「G1a / G2 — kernel 對 branch-first 的邊際效果」。
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
- **2026-08-08 xref gate 只保障 dotfiles,但它服務的規範是全域的——這個不對稱要講明**:
  `tests/run.sh` 只跑本 repo,故「唯一權威」指標的機械守門僅及於 dotfiles;而同批改的
  `ship-state.sh`(append-only 偵測)與 dossier 規範(失效標記)**跨 repo 生效**。
  故不得說「其他 repo 零影響」(它們未來的 `/project log` 行為確實變了),也不得說
  「失效標記已有守門」(其他 repo 的指標沒人掃)。**不擴大到 `ship-state.sh --repo` 的理由**:
  其他 repo 的引用可能指向 repo 外(如 `~/Projects/...`),需要另一套外部路徑政策;
  規範已要求指標寫成 gate 可解析的形狀,將來擴大時零回填。
- **2026-08-08 散佈憑證變更的三條紀律**(全機隊改 SSH 身分與 key 檔名時實地得出):
  ①**`cp` 不 `mv`**——新舊並存,任一步失敗都不斷線;遠端拉 dotfiles 靠的正是 GitHub SSH,
  認證改壞又散佈出去就拉不到修正,只剩 `ssh <host>`(內網 CA cert)進去手改。
  ②**散佈前提是變更已進 `origin/main`**——遠端 `dotsync` 拉的是 main,本地 branch 未 push
  時散佈等於空轉(實地踩過一次,以為散完了其實什麼都沒變)。
  ③**先散一台走完全程再放其餘**——挑最有代表性的那台(這次是 db01:remote 最多、唯一有
  `insteadOf`、且有 krepo 可驗依賴路徑),不是挑最安全的。
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
- **在移交出去的 repo 內放一份 dossier 規範精簡版(`docs/dossier.md`)**:2026-08-10 設計時提出並否決。
  ①**G1b 實測非自動載入的檔不會被讀**,它與 `AGENTS.md` 同一失效面;②散到 N 個 repo 後零機械守門
  (`kernel-gate.py` 只守 dotfiles 四檔),規範一改就全部 stale 而**沒人會發現**——最壞是接手者的
  agent 照舊版把刪除線劃在失效通知上,**交出去的東西主動教錯**;③常駐檔會腐爛(`docs/transfer.md`
  不腐爛正因它移交前才生成)。**正解是既有落點**:STATUS.md 自己的檔頭註解 + 該 repo 的 `CLAUDE.md`。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:實證 general-rag-cs 的已消費
  STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] **handoff 的 `dirty=N` 敘述會在 W2→W3 之間過期**(2026-08-09 H5 迴歸復發,首跑即記過)。
  W2 蓋錨點後 W3 才把跨輪死路沉澱進 repo 的 STATUS.md,working tree 檔數增加而錨點與交接檔敘述
  都停在蓋錨點當下 → 寫出「`dirty=1` 就是上述**兩個**未 commit 檔案」。**同批 H8 同 fixture 同模型
  卻主動講清落差**——行為分歧已達動規則的證據門檻。傾向**改順序而非加告誡**:W3 的 dossier 沉澱
  移到 W2 之前(predecessor 在 W1 已定出,可行),dirty 在蓋錨點當下即為最終值,過期的可能從流程
  消失;配一條 H5 oracle(用 8/09 的逐字錯誤當 RED)。未做——本輪任務是迴歸驗證。
- [ ] **G 系列 eval 除 G7 baseline 外都跑在 Opus 上,不符樓層政策**(`claude/evals/README.md` 明訂
  Sonnet 才是 PASS 門檻、Opus 非驗收門)。G7 baseline 已補跑 Sonnet(2/2,結論不變)——它是唯一
  改變過決策的結果,故優先補。其餘(G1a/G1b/G2/G4/G4b/G6)現況只證明「強模型上成立」,要當驗收
  證據需在 Sonnet 重跑。fixture 已可一鍵重建(`setup-sandboxes.sh` 的 `make_g6`/`make_g7`)。
- [ ] R4 non-blocking 餘一項:**新增 prose 的中文半形標點與既有全形混排**。2026-08-08 未做——
  「新增 prose」指哪一批已不可考,純風格、無失敗案例,且該日又寫入大量中文 prose(移動標靶)。
  要做就一次全檔統一,不要逐批追。其餘三項(Transfer 模式 commit 歸屬、evals/README 路徑基準、
  handoff evals H4 排序)已於 2026-08-08 修畢。
- [x] dossier 訊號 R5 non-blocking 五項——2026-08-08 全數修畢(細節在 tests,可反推)
- [ ] **「tests/stub 有覆蓋、實戰未驗」一組**(遇到對應情境時順手確認即可,不必專程做):
  SessionStart hook 落後提醒(真實落後的 clone);autocodex exec 的 resume 分支(exit 4 救援階梯,
  三輪實跑皆一次成功、只有 stub 覆蓋,F15(b) 待真實空報告);review-anchor 的 stale STOP 與
  codex-next 冪等(F16 b/c,待 autofix 迭代中真的 rebase/重試);repo-review 新契約(F16–F18 規格
  覆蓋,待多輪 autofix 確認弱模型不會退回每輪帶 `--autofix`)
- [x] hook matcher 僅 `startup`——2026-08-07 已擴為 `startup|clear|compact|resume`,tests 第 16 節覆蓋
- [x] 測試節那行待補 git-hygiene 的新教訓——2026-08-07 已補。留一條:**目標檔是 repo 根的
  `CLAUDE.md`**,不是 `claude/CLAUDE.md`(後者的測試節講的是「何時該寫測試」)
- [ ] Scenario 11 的「merge 但無 PR」分支只在 SKILL body 一行指標帶到 ship-paths,GREEN 實測中
  弱模型未展開讀——非違規故未補;重現才加明示(Iron Law)
- [ ] pressure-tests S8/S9/S12 沙盒未納入 `claude/evals/setup-sandboxes.sh`;S10(transfer
  credentials)與 S12(dossier 三 flag 蒸餾紀律)連首輪實測都還沒跑
- [x] `claude/evals/*.sh` 已於 2026-08-08 納入全部四個 gate,納入時零 findings——
  **便宜的守門要趁乾淨時加**,等它長歪再加就得先還債
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
> 2026-08-05～08-08 各批已歸檔至 `docs/archive/milestones-2026-08.md`。

- ✅ 2026-08-10 dossier 可攜性收斂：G7 transfer clean-room eval（baseline 3/3、修後 2/2 全綠）＋ `STATUS-template.md` 全檔可攜化（5 增 5 刪，純置換）＋ 刪 `codex/AGENTS.md` 與 kernel C2 矛盾的全域斷言 ＋ Phase 3 DROP 四處清理 ＋ G6 非強加測試 2/2（956 PASS）
- ✅ 2026-08-09 handoff skill 收斂：錨點兩端完整性（unborn HEAD 的永久假 FRESH）＋ W1/R1 三指令下沉為 `survey` ＋ archive resume 的盲區與信任上限（889 PASS，eval 8/8）
- ✅ 2026-08-10 G1b 成對實驗：實測 root `CLAUDE.md` 自動載入、root `AGENTS.md` 不會（clean room 不帶全域檔）→ kernel 擴為四份逐字複本，並定案 installer 必須裝 kernel 本體而非 pointer（956 PASS）
- ✅ 2026-08-09 契約層抽取 Phase 2：repo 根 `AGENTS.md`（kernel：safety floor 6 + fallback conventions 2；portable：權威矩陣 + working discipline）＋ 三份 kernel 逐字複本 ＋ `tests/kernel-gate.py`（漂移／掏空／缺份／marker／canary／可攜性，含 10 條自檢 fixture）。`claude/CLAUDE.md` 與 `codex/AGENTS.md` 交出被 kernel 承接的條文（956 PASS；四個突變各驗過會紅，含真實 repo 改一個字的漂移）
- ✅ 2026-08-09 `brewup` 自我更新偵測：pull 換掉自己就 `exec` 新版重跑（`BREWUP_REEXEC` 迴圈防護），消掉「pull 進新版卻用舊版跑完」的一輪延遲。**這顆修正本身仍要被它修的 bug 咬最後一次**——各機第一次跑到的是修正前的 brewup，`dotsync` 不受影響（它以路徑逐支呼叫 helper）（944 PASS）
- ✅ 2026-08-09 `ensure-ssh-config.sh`：四份行內複本收斂成一支並接進 `brewup`，不在 inventory 的機器從此能自己跟上；加原子寫入＋完整性驗證＋**key 缺席守門**（擋自動重生把可用認證換成壞的）。過程被自己的測試抓到 `$(wc -c < 讀不到的檔)` 回空、`$(( ))` 當 0 的假綠（941 PASS）
- ✅ 2026-08-09 契約層抽取 Phase 1：`brewup` 補四個 ensure helper（補上「allup 走 brewup 而 helper 只掛 dotsync」的散佈窗口，含不誤報完成的兩層 warn）＋ branch-first 提升到 always-on ＋ 新增 `tests/run.sh` §18d 全隔離 fixture（902 PASS，兩個突變各驗過會紅）


## 已知缺口

- **eval 的受測 subagent 拿不到 deferred tools,部分契約在沙盒中無法構造**:2026-08-07 實測——
  主 session 的 `CronList`／`TaskOutput` 正常,探針 subagent(`Tools: *`)對同一批 `select:` 一律得
  `No matching deferred tools found`。凡「該工具查得成」才成立的情境因此做不出來,ready4quit
  **Q4c**(`RECALLED + ✓`,需最低證據等級剛好是 RECALLED)至今無 GREEN 證據。symlink 前置已解除,
  但手動驗證二度失敗,並暴露原程序自身兩個錯(`~/.dotfiles` 當 pwd 讓 Git 衛生恆 ⚠;「全新且安靜的
  session」自相矛盾——無對話歷史時回憶型面向只會落 PARTIAL)。**v3 程序見
  `claude/skills/ready4quit/evals.md`,別再照舊程序跑。**
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

- **缺口條目寫「解法已知、剩移植」時,那句本身也要有人去核對一次**——它讀起來像查證過的結論,
  實際上常是當時的推測,而後來的人會直接照做。2026-08-07 實例(deep-review anchor 跨批次 stale)
  核實後發現守門早就在、且照定義擋不到該風險,真正兜住的是另一個機制。**該缺口已消,留這條教訓。**

- **「規則的對稱面／使用點」與「同型掃描」都只有文字原則、無產出物**(兩者同型,合併記):
  Step 2 抓到 `add -A` 例外的使用點缺口純屬偶然(2026-08-05),同 session 的 #43 走過同一個 Step 2
  仍漏兩條 blocking;deep-review 對「測試」有 exit-code gate,對同型掃描只有文字要求,krepo 連跑
  四輪修復時漏的正是它。**共同結論:不補文字原則**——文字是最易被跳過的那層。要做就**訊號化**
  (如 `ship-state.sh` 偵測變更集含 `CLAUDE.md`／`AGENTS.md`／`SKILL.md` 時印對稱面候選,不判語意,
  形狀同 `dossier-flag`)。做不成 exit-code gate——規則是語意抽象出來的,機器不知道要 grep 什麼。
  現有防線只有第三方審查。

- **Mac 上 brewup 會被 codex cask 掛死(Gatekeeper)**:2026-08-07 第三次發作。復原已有入口
  `brewfix`(唯讀診斷,`--fix` 才動手);機制、鑑別法、三條走不通的預防路徑全文見
  `claude/CLAUDE.md`「已知地雷」,**此處不重述**。**仍未解**:確切觸發條件未知且事後無法重現
  (同版本內容換路徑執行正常),要重現只能等該 cask 真正出新版。**未決**:預先設 xattr `0x0040`
  技術上可行,但前提已被負面結果動搖、代價卻是確定的(拿不到 tarball 簽章身分)——
  **用確定的代價換不確定的效果,暫不做**,優先靠已實證的復原路徑。

- **另一個寫入者的筆記可能在 ship 時被蒸餾壓掉**:協作者若把粗胚寫進 STATUS.md「進行中」,那正好是
  會被收斂的一節,而 `/project log` Step 2 的前提是「此刻 session 記憶還在」——**對別人寫的東西不成立**。
  可能後果:決策被當雙重記載壓掉,摘要還回報「已依 flag 收斂」。同族先例:`ship-state.sh` 的行號診斷
  就是因為多 session 並行時 agent 猜錯超標條目兩次才加的。**觸發條件:觀察到一次真的被壓掉,才動規則。**
- **`AGENTS.md` 的 `Generated docs never win` 是已上線但從未測過的規則**(G5 隨 OpenWiki 一起 DEFER)。
  它是 `No failing scenario, no instruction` 的存量違例——**記著,現在不刪也不為它 churn**。
- **`codex/AGENTS.md` 與 root `AGENTS.md` 同名不同角色**(前者是全域 Codex 指引的**來源檔**,由
  `ensure-codex-guidance.sh` 部署;後者是 repo-resident 契約)——正是
  `claude/skills/project/references/dossier.md`「1. 檔案角色分工」的 Naming is exclusive 擋的形狀。
  現行實害:`codex/skills/repo-review/scripts/review-context.sh` 沿改動路徑逐層收 `AGENTS.md`,
  改 `codex/**` 時兩份都被當 guidance 餵進 reviewer(重複但無害)。**改名方案已 DROP**(2026-08-10:
  Codex 不進生產線,價值近零而代價是全機隊 symlink 風險)——**此實害就這樣接受**。契約層本身的缺口
  已由 Phase 1–2 補上(見里程碑)。
- 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,
  改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+credentials 明文散於三台。
- **`agy`(Antigravity CLI)只手動裝在 macs,未寫進 `setup-mac-env.sh`**:2026-08-07 因 gemini-cli
  已於 2026-06-18 停服而改裝其後繼(`brew install --cask antigravity-cli`,binary 名 `agy`)。
  後果:新機器跑 setup 不會裝、macmini/m4mini 目前也沒有。該 cask 標 `auto_updates`,故 `brewup`
  不會升它(除非 `--greedy`)。**它沒有 `generate_completions_from_executable`,不會踩 codex 那個
  Gatekeeper 坑**,但首次執行仍會走核可流程——要裝就在該機 console 前跑一次。
- **兩部個人 MacBook 不在 `inventory.conf`**(一部公司、一部家中,經 VPN ssh 進 macs),`dotsync` /
  `allup` 都涵蓋不到,且**一次只能處理一部**。2026-08-09 已把 `~/.ssh/config` 的重生下沉成
  `ensure-ssh-config.sh` 並接進 `brewup`,所以**跟上一次之後就不必再手動補齊**;補齊程序(含
  「打 `brewup` 沒用、必須用絕對路徑繞過舊 alias」)見 repo 根 `CLAUDE.md`「系統更新與同步」。
  兩機狀態:[x] 家裡那部 2026-08-09 補齊(使用者回報,未由本 session 獨立複驗);[ ] 公司那部未查,
  走 `bootstrap` 那條路即可、**已不擋任何事**(原本卡的 Phase 3 已 DROP)。
  **加進 inventory 這條路今天不可用**:2026-08-09 查 tailnet 沒有它們;且常離線的筆電會讓每次
  dotsync 都帶 ❌,訊號被稀釋。**待確認是刻意(終端設備不入清單)還是缺口。**

## 移交準備度

(個人 infra,暫無移交打算——平時留空)
