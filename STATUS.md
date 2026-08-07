<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——內網主機(清單見 `scripts/inventory.conf`,現 14 台)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-08-07)

---

## 進行中

### todo:GitHub 多身分收斂——讓標準 URL 直接可用(2026-08-06 記錄,未開工)

**Context**:krepo 拆出 `krepo-common` 後,依賴要寫成 git URL。原本沿用本家的
`git@github-work:...`,但 **`github-work` 是本機 SSH alias、不是真實主機名**——寫進 repo
等於要求每個消費者的機器都有同名 alias,而接手者撞到的會是一個「看起來像網路錯誤、
實際上是少了一段 SSH 設定」的失敗。krepo 端已改標準 `git@github.com:`(已 ship),
但**機器端的多身分配置還沒收斂**,現在靠 `insteadOf` 撐著,那是多加一層改寫機制、不是簡化。

**Goal**:標準 URL(`git@github.com:`)在每台機器上都直接可用,`insteadOf` 整層移除。

**現況盤點**(2026-08-06 實測):

| 機器 | `github-work` | 個人(`github.com`) |
|---|---:|---|
| 工作 mac | **28** | **2**(`isdotgd`、`.dotfiles`) |
| db01 | 全部 | **0** |
| 個人 MacBook | 也有工作 repo | 少數幾個 |

**關鍵事實:三台機器的主要身分都是「工作」**——個人 MacBook 上也處理工作 repo,
而公司開發機不會 clone 個人 repo。所以**沒有機器差異**,不需要 host-local 覆蓋
(`ssh/config` 的 `Include ~/.ssh/config.local` 機制留著備用即可)。

**方案**(共用設定,三台一致):

```
# 工作帳號 (jjshen-eland) = 預設 = 標準寫法
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_github_work
    AddKeysToAgent yes
    IdentitiesOnly yes

# 私人帳號,少數 repo 明示
Host github-me
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_github
    AddKeysToAgent yes
    IdentitiesOnly yes
```

⚠️ **`IdentitiesOnly yes` 一行都不能少**(現行兩個 block 本來就有,照抄即可)。少了它,
ssh 會把 agent 裡的 key **逐一送給 GitHub**,而 GitHub 接受第一把有效的——於是認到**錯誤
帳號**。這會直接打掉 AC 1 與 AC 5,且**失敗長相是「連得上但權限不對」**,比連不上更難查
(連不上至少當場知道)。同理 `User git` 與 `HostName` 也照現行寫法保留,不要只留 IdentityFile。

- **`github-work` 整條刪除**——`github.com` 就是工作,不需要第二條路徑
- 工作 repo 的 remote 全部改標準 `git@github.com:`(機械替換,見下)
- 個人 repo 改 `git@github-me:`(工作 mac 只有 2 個)
- **移除 mac 與 db01 的 `insteadOf`**(2026-08-06 為了讓 krepo 能拉依賴而暫設在各自的
  `~/.gitconfig`;它們是這次收斂要消滅的對象,不是終態)

剩下的唯一 alias 是 `github-me`,**不可約**——GitHub 一把 SSH key 只能綁一個帳號,
兩個身分就必須有一種區分方式。

**AC**:

1. 三台機器上 `git clone git@github.com:elandcomtw/...` 直接成功,無 URL 改寫
2. `gh repo clone` 也對(⚠️ **`gh` 完全不看 SSH alias**,這是 alias 方案永遠解不掉的一半,
   只有「讓 `github.com` 就是工作身分」能解)
3. `~/.gitconfig` 內無任何 `insteadOf`,`ssh/config` 內無 `github-work`
4. 三台機器上 `cd ~/Projects/krepo && uv sync` 都能拉到 `krepo-common`
5. 個人 repo(`isdotgd`、`dotfiles`)在改用 `github-me` 後仍可 push

**遷移順序**(順序錯會鎖住存取):

```bash
# 1. 先確認每台機器都有 ~/.ssh/id_github_work（個人 MacBook 也要，它也跑工作 repo）
# 2. 改 dotfiles 的 ssh/config，部署到各機器，驗證身分：
#    ssh -T git@github.com   → 應認到 jjshen-eland
#    ssh -T git@github-me    → 應認到 dev-bitpod-cc
#    ⚠️ 判準是「認到誰」不是「連得上」。認到錯帳號 → 八成是 IdentitiesOnly 沒設，
#       ssh 把 agent 裡的 key 逐一送出、GitHub 收了第一把有效的。
# 3. 身分驗證通過後才改 remote（第 2 步沒過就往下做，會把 remote 改成連不對身分的形式）：
for d in ~/Projects/*/ ~/.dotfiles; do
  url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
  case "$url" in
    git@github-work:*) git -C "$d" remote set-url origin "${url/github-work:/github.com:}" ;;
    git@github.com:dev-bitpod-cc/*) git -C "$d" remote set-url origin "${url/github.com:/github-me:}" ;;
  esac
done
# 4. 最後移除 insteadOf：git config --global --unset-all url.<...>.insteadOf
```

⚠️ **`.dotfiles` 自己的 remote 也要改**(它是個人 repo)——上面的迴圈已涵蓋,但要記得
那正是你正在編輯的 repo,改完先 `git remote -v` 確認再 push。

**風險與回退**:動的是憑證設定,改錯會讓所有 repo 存取一起失敗。回退指令**依「改動是否已
commit」分兩種**——`git checkout ssh/config` 只在**尚未 commit** 時有效;遷移一旦 commit
(而跨機部署的前提就是 commit + push),它從 HEAD 取回的還是新版,等於把壞設定又還原一次:

```bash
git revert <遷移 commit>                      # 已 commit(跨機部署後的常態)
git checkout <遷移前 commit> -- ssh/config    # 或只取回單檔
git checkout ssh/config                       # 僅限尚未 commit
```

⚠️ **但部署後才生效**——回退也要重新部署,別以為 git 操作完就完事了。

⚠️ **回退路徑本身會被這個變更弄壞**:遠端機器拉 dotfiles 走的正是 GitHub SSH。認證改壞又
已散佈出去,那些機器就**拉不到修正**——得 `ssh <host>`(內網 CA cert,不受此變更影響)進去
手動改 `~/.ssh/config`,或臨時加回 `insteadOf` 撐住。**先在一台機器驗過再散佈,不要一次
`dotsync` 全部。建議清醒時做,不要在深夜動**。

---

## 關鍵決策(附理由)

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。**歸檔判準**：已固化且不再影響現行方向 → 歸檔；仍在生效的一律不歸檔（死路＝防重工、技術債＝未解決，移出 always-on 即失效）。超標時**優先歸檔、不要為幾百 bytes 去壓無關舊條目**——那個動作重複幾次本身就是訊號。

- **2026-08-07 使用者拍板:GitHub 多身分收斂的 spec 定稿留在「進行中」,不移 `docs/plans/`**。
  代價已知且接受:它佔 always-on 內容約 24%,dossier 會持續貼近 300 行硬門檻、每次 ship 觸發
  尺寸 flag。**不要再提同一個搬移**——超標時改從其他節收斂,或如實把該 flag 標為「未處理(使用者
  已拍板保留)」。
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
- **2026-08-07 Step 4 從「逐批出題」改「說法即授權」,拆掉的守衛另補一道**:使用者實地回報「說了
  ship 還被問四次」是摩擦。改為送出說法(merge／bypass merge／只推 branch…)出現在本輪訊息裡就
  印完摘要做到底、零提問;沒說法才問一題。**但這拆掉的是「push 前你一定會看到摘要並有機會攔」**,
  故補上 `review-terminal:`——上一場審查若是 R5 終止收場(且 ancestry 涵蓋當前 HEAD)一律 STOP,
  說法覆蓋不了。**判準:移除一道 gate 時,先問它順帶接住了什麼,那些東西要各自有主。**
- **2026-08-07 merge 預設改「保留語意 commit」,推翻昨天「≥2 顆就出選項問」**:昨天那條的理由是
  「壓不壓沒有預設值,不能猜」;使用者給了預設(不同目的的 commit 預設保留)之後,歧義本身消失,
  詢問的理由跟著消失。**那條規則從未實測就被推翻**,故無實測結論被推翻。review 痕跡則相反——
  **壓得掉的一律壓、不問**,它不是偏好而是不變式;唯一的自由度是「壓不壓得掉」(buried 壓不掉)。
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
- [ ] dossier 訊號 R5 non-blocking 未修(2026-07-29,皆非 blocking、無失敗案例):sections 百分比
  系統性略低於 100%(標題行不計);「唯一的例外」在 SKILL 與 S12 說法不一致;最長行 flag 缺「何時
  處置」;S12 fixture 規格內部不一致;條目作用域用子字串比對而非端錨定(「## 進行中(已完成 M1)」會誤掃)
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
- [ ] `claude/evals/setup-sandboxes.sh` 不在 shellcheck / `bash -n` / 全形標點 gate 範圍
  (第 1、1b、2 節只涵蓋 `scripts/`、`claude/scripts/`、`*/skills/*/scripts/`、functions/setup/tests)。
  2026-08-05 加 h5/h6/h7 沙盒時靠手動 `shellcheck` 才抓到:**unquoted heredoc(`<<EOF`)內的
  markdown 反引號會被當命令替換執行**(SC2006),而該檔全靠 heredoc 灌 fixture 內容。沙盒腳本
  繼續長大就值得納入 gate
- [ ] codex plugin 去留待定:實質只當傳輸管道,exec 接管後僅剩 `/codex:transfer` 獨有——
  exec 路徑跑穩數輪後重新評估 uninstall
- [ ] codex C2 轉交 findings 餘項(2026-07-21 代收):F6 skill-building-guide 的
  `$skill-creator/scripts/quick_validate.py` 路徑解析(context-dependent)。F5(多輪 autofix
  死鎖)已於 2026-08-03 判 true positive 並修復
- [ ] repo-review 新契約(起始 gate 一次 + 後續 ownership 檢查、mixed-context manifest)僅由
  evals F16–F18 規格覆蓋,**實戰未跑過**——下次真跑 autofix 多輪時確認弱模型不會退回每輪帶
  `--autofix`
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

- ✅ 2026-08-07 skill-authoring one-shot gate + R5 terminal state:deep-review 對 skill 類變更
  只跑一次診斷(severity 不放寬、blocking 照報,只是不進 autofix 循環),`force-skill-loop` 為
  唯一 escape hatch;`terminate`/`resume-after-terminal` 兩個子指令讓 R5 終止跨 session 可見。
  eval 沙盒補 d4–d7,四條行為 eval 在 Sonnet 實跑至 GREEN。665 PASS。

- ✅ 2026-08-07 ship 說法語法(說法即授權):Step 4 由逐批出題改為「說法出現即執行到底、零提問」,
  merge 預設保留語意 commit、review 痕跡壓得掉的一律壓;新增 `review-terminal:` 事實前提 STOP
  (說法覆蓋不了)與 merge 受阻的 `mergeStateStatus` 分流(`--admin` 只給「bypass merge」+`BLOCKED`)。
  沙盒補 u4/u5,三條行為 eval 在 Sonnet 實跑首輪全 PASS。672 PASS。

- ✅ 2026-08-07 squash-merge 殘留 branch 偵測與安全清除:`squash-merged-branches:` 訊號(headRefOid
  比對／fork 不採信／`scan: complete|partial`)+ `cleanup-stale-branch.sh`(三道前提、remote 走
  ls-remote 重驗 + lease 雙重比對),並修掉「當前 branch 的 remote 對應被列為可刪」的實地誤報。699 PASS。

## 已知缺口

- **祖先判定那條路徑的 `cleanup-cmd` remote 刪除仍是裸 `push --delete`**(無 lease、無執行當下
  重驗)。local 側的 `-d` 由 git 自己把關(未併入即拒),remote 側沒有等價保護——偵測後有人推過
  就會刪掉未併入的 commit,與本批修掉的 TOCTOU 同型。修法現成:改發 `cleanup-stale-branch.sh
  <repo> remote <branch> <sha>`。**刻意未收進本批**——會動到既有斷言的輸出形狀,且無實地失敗案例。

- **說法表把授權綁在字面 token,但「用 --admin」語意上更明確卻不在表上**(現行＝不接受,會要求
  使用者改說「bypass merge」)。設計 S15 eval 時撞到:原擬施壓句「加個 --admin 就過了」比 bypass
  merge 還明確,等於把授權塞進施壓句、正確答案自己變歧義。**張力**:收進表等於承認自然語言等價詞,
  而「不自行擴充等價詞」正是它擋 rationalization 的機制。無實地案例前不動。

- **buried 的 review 痕跡壓不掉,不變式只做到「壓得掉的一律壓」**:夾在語意 commit 中間時
  `reset --soft` 碰不到。**做得到但沒做**——`rebase -i` 配 `GIT_SEQUENCE_EDITOR` 是完全非互動的,
  把每顆 buried 標 `fixup` 折進前一顆語意 commit 即可(前一顆本就是它父節點,**衝突為零是結構保證**)。
  **代價才是沒做的理由**:語意 commit 的 hash 與內容都會變、「squash 絕不動語意 commit」從結構保證
  退成測試保證、多一條 rebase 回滾路徑、branch 首顆是 buried 時無目標;而實測多為 none/top-contiguous。

- **`ship-state.sh` 不檢查 feature branch 對「自己的 remote tracking ref」是否分岔**(只比對
  default)。分岔時 push 會被拒,prose 端有防線(`ship-paths.md` squash 步驟 0 的 fetch +
  `--is-ancestor`)但**無訊號**——2026-08-07 跑 eval 時由受測 agent 自行 `branch -vv` 才發現。
  補法＝一行 ancestry 檢查,形狀同 `review-terminal`;暫不補,無實地失敗案例。

- **證據標註 = backlog,無 RED 不進 brief**:待觀察失效為「finding 建立在未查證推論、fixer 誤信」,
  至今零觀察;日後出現再加標註版(零風險、可測),而非授權外部存取。全紀錄見 deep-review `evals.md`。

- **deep-review anchor 跨批次會 stale,`squash-cmd` 因而指向錯誤目標**:anchor 只在 autofix 的
  `record` 寫入,走「codex 第三方審查」觸發詞路徑(非 autofix)時不 record,`squash-cmd` 遂讀到
  **上一批**的 anchor(2026-08-05 實遇:本批 3 顆 commit,腳本卻給出會壓掉 5 顆的 reset 目標)。
  腳本行為正確,缺的是「anchor 屬於哪一批」。2026-08-06 squash 改 subject 掃描後**風險已大幅
  縮小**——會停在第一顆語意 commit,跨批次的舊語意 commit 不再被壓;殘餘只剩「上一批的 review
  fix commit 被收進本批 squash」。解法已知:`squash-cmd` 偵測 anchor 非當前 branch 祖先時改判
  STOP——**`codex-next` 已有這道檢查**,剩下的是移植;處置＝`record --mode branch-diff --base main`。

- **`/project log` Step 2 對「規則只寫了一半」無偵測能力**:2026-08-05 該步抓到 `add -A`
  例外的使用點缺口(條件只寫在禁令側、執行者讀的是 skill)純屬**偶然**——`CLAUDE.md` 的例外
  文字剛好點名 `deep-review/SKILL.md`,順著文字就找到了。**同一 session 的反證**:#43 走過
  同一個 Step 2(輕量路徑、快速核對),F2/F3 兩條 blocking 照樣漏出,由第三方審查才抓到。
  Step 2 沒有「規則的對稱面／使用點」概念。**不補文字原則**——與下條「同型掃描有原則無
  產出物」完全同型,實戰最易被跳過;日後復發才做**訊號化**(`ship-state.sh` 偵測變更集含
  `claude/CLAUDE.md`／`codex/AGENTS.md`／`skills/*/SKILL.md` 時印對稱面候選,不判語意),
  形狀同 `dossier-flag`。現有防線只有第三方審查。

- **同型掃描有文字原則、無產出物(機制不對稱)**:deep-review 對「測試」有機械化 gate
  (`verify-tests.sh` 的 exit code 契約),對「同型掃描」只有 `reviewer-brief.md` 與 SKILL.md
  的文字要求。2026-08-05 krepo 實戰回饋指出:連跑四輪修復時最容易被跳過的正是這類原則性
  敘述,且該次漏的就是它。**做不成 exit-code gate**——規則是語意抽象出來的,機器不知道要
  grep 什麼;可行的只有 checklist 化(要求 fixer 每輪在報告寫出「本輪抽象出的規則 + `rg`
  命中數」),但那會改動 fixer 每輪的報告格式,待單獨評估。終止報告新增的「根因與前輪
  重複?」欄只在**終止時**部分暴露此失效模式,太晚。

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
