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

> 較舊條目已歸檔至 `docs/archive/decisions-2026-08.md`（機制皆已固化在 skill／腳本／tests／CLAUDE.md，從程式碼可反推；歸檔保存的是「當初為什麼這樣決定」）。

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
> 2026-08-05 該批與 handoff skill 那條已歸檔至 `docs/archive/milestones-2026-08.md`。

- ✅ 2026-08-06 squash/merge 決策改造:deep-review 收尾只壓 review 機械 commit(語意 commit
  保留,`squash-preserve:`/`squash-note:` 攤開)、round 改頂端連續段、merge 壓不壓改關鍵字分流
  + Step 4 第 1 題(`AskUserQuestion`)、review 痕跡偵測下沉 `ship-state.sh`(`review-residue:`)。
- ✅ 2026-08-06 上批的兩場 review 收斂(主審 R1–R5→終止→人工修→R1–R4 通過;codex C1–C3):跨
  Step 時序契約(Step 1 的 hash 是語意 commit 邊界、不得重算)、照抄行 shell quoting(路徑與
  ref 名過 `shq` + `--` terminator)、`--force-with-lease` 帶 expected SHA,以及一條**會
  `rm -rf` 掉整個 repo** 的測試防護漏洞。codex 7 條 findings 全 TP、零誤判。647 PASS。

## 已知缺口

- **證據標註 = backlog,無 RED 不進 brief**:待觀察失效為「finding 建立在未查證推論、fixer 誤信」,
  至今零觀察;日後出現再加標註版(零風險、可測),而非授權外部存取。全紀錄見 deep-review `evals.md`。

- **deep-review anchor 跨批次會 stale,`squash-cmd` 因而指向錯誤目標**:anchor 只在 autofix 的
  `record` 寫入,走「codex 第三方審查」觸發詞路徑(非 autofix)時不 record,`squash-cmd` 遂讀到
  **上一批**的 anchor。2026-08-05 實遇:本批 3 顆 commit,腳本卻給出會壓掉 5 顆(含已 merge 的
  #38/#39)的 reset 目標。**腳本行為正確**(照 anchor 算),缺的是「anchor 屬於哪一批」。
  2026-08-06 更新:原本的 `warning:` 行已隨 squash 改算法移除,但**防線反而變強**——subject 掃描
  會停在第一顆語意 commit,跨批次的舊語意 commit 不再被壓;殘餘風險縮小為「上一批的 review fix
  commit 也一併被收進本批 squash」。可能解:`squash-cmd` 偵測 anchor 已併入 default 或不在當前
  branch 歷史時改判 STOP——**`codex-next` 已有這道檢查**(8/06 補審已 squash 的那批時兩次正確判
  「anchor 已非 HEAD 祖先」拒發 range),剩下的是移植;處置＝`record --mode branch-diff --base main`。

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
