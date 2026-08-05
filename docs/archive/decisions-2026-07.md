# 關鍵決策歸檔 — 2026-07

> 從 `STATUS.md`「關鍵決策(附理由)」節歸檔（2026-08-05，總量治理；做法與先例見
> `~/.claude/skills/project/references/dossier.md`）。
>
> 這些決策的**機制**多已固化在 skill / 腳本 / tests / CLAUDE.md 裡，從程式碼即可反推；
> 此處保存的是**當初為什麼這樣決定、否決了哪條路**——那部分永遠無法從 diff 反推，
> 所以歸檔而非刪除。
>
> 按需查閱，不進 always-on context。要追某個現行行為的理由時搜這裡。

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
- **2026-07-16 多主機工作流的五條奠基決策**(已固化,合併存查):**git 為唯一跨主機媒介**——
  `~/.claude/`(handoffs/memory)不跨機同步(衝突、錨點語意複雜化、敏感內容風險),krepo 已證
  repo-resident+git 可行;**/project 取代 /uap 而非並存**(雙入口=觸發混淆+double-source,
  disable-model-invocation 下無法鏈式呼叫、只能複製防護邏輯);**STATUS.md 即 dossier 載體,
  不新建 PROJECT.md**(尊重既有慣例、避免角色重疊);**不引入 Linear/外部 tracker**(缺的是
  慣例固化,不是新工具);**settings.json 以 opus[1m] 為共享 model 基線**(單機偏好不傳播全機隊)。
