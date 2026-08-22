# 死路歸檔 — 2026-08

## 事件記錄（event-time）

- **X-20260819-archive-sort-key · ** **讓 handoff 的 archive 排序也改用 mtime**(2026-08-19 否決):歸檔前綴＝**消費時刻**、
  mtime＝**最後寫入**,audit trail 要前者、active 清單要後者,**兩邊刻意用不同鍵、不是不一致**。
  推導與那個不精確的初始理由見 `docs/dead-ends.md`「handoff archive 排序改用 mtime」。
  - 日期來源:migration-entry
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260819-p4-wait-superseded · 2026-08-19** **B-20260819-debt-04 · ** [ ] ~~**P4 待實例化**~~(取代原本的「P4 需 krepo fixture」)。原 fixture 已判過期且
  不可重建(理由見 `claude/skills/deep-plan/evals.md`「P4 的 fixture 與過期風險」)。**觸發條件**:下一次在真實 repo
  跑完 `/deep-plan`、且第一輪抓到判準類阻斷級 finding 時,當場登記計畫檔路徑、**第一輪當下**的
  commit hash、逐條證據位置。⚠️ hash 取錯時點(ship 後)整個 eval 就作廢——那正是本次死掉的原因之一。
  **2026-08-19 已核對過一次真實執行(dotfiles handoff mtime 計畫),兩個 AND 條件都不成立(非判準類、
  第一輪最高只到「高」)⇒ 未登記**。這一格等的是「判準類 + 阻斷級」的合流,不是「下一次跑到就算」;
  逐條理由見 `claude/skills/deep-plan/evals.md`「P4 的 fixture 與過期風險」。
  - 日期來源:migration-entry
  - 放棄:原等待狀態已被實例化取代
  - 重議:見原文
  - 關聯:B-20260819-debt-04

- **X-20260819-handoff-mtime-fallback-test · ** **替 handoff active 行的「mtime 讀不到」降級路徑寫測試**(2026-08-19 放棄):**沒有可執行的
  構造方式**,防禦碼保留並以註解標明不可達,**不寫測試也不列驗收**。⚠️ 連帶:`0` 不能靠 `date`
  失敗來判缺值,`date -r 0` 會**成功**回 1970-01-01。
  推導見 `docs/dead-ends.md`「handoff mtime 降級路徑的測試」。
  - 日期來源:migration-entry
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260817-plan-review-skill-batch-rule · ** **把 deep-review「skill-authoring batch 不進修復循環」的判準套到 plan review**(2026-08-17 否決)。
  **別從「它是 .md」推論收斂性——要看 findings 的 oracle 在哪**:plan 的 findings 是「計畫對 repo
  現況的陳述錯了」,oracle 在 repo 裡、二元的,那條判準管的是**無界完整度**、不是有限事實查核。
  ⚠️ 但迭代仍被否決,理由完全不同(累積正當化,見關鍵決策節)。
  推論鏈與實測數字見 `docs/dead-ends.md`「deep-review 判準套到 plan review」。
  - 日期來源:migration-entry
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260815-backlog-archive-without-split · ** **只給待辦節加歸檔出口(已解決的移入 `docs/archive/`)而不分家**(2026-08-15 否決):釋出 **0 bytes**,
  且處置形狀是在超標時多問一題,與「Step 2 太花時間」的訴求**方向相反**。**慣例本身沒被丟掉**——
  分家後寫進 `docs/backlog.md`「關閉與歸檔慣例」,差別在它不吃門檻、不出題。
  實測數字見 `docs/dead-ends.md`「只給待辦節加歸檔出口」。
  - 日期來源:migration-entry
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260815-ci-rollup-jq · ** **拿 `gh pr view --json statusCheckRollup` ＋ jq 計數判 CI 狀態**(2026-08-15 否決,改用
  `gh pr checks --required` 的 exit code):rollup 單筆**沒有 `isRequired`**,必要與非必要 check
  分不開 → 空等或誤停,**正是本次要修的誤診換個方向**;另有同名多筆與混型別兩坑。三條理由與
  翻案條件見 `docs/dead-ends.md`「rollup ＋ jq 計數判 CI 狀態」。
  - 日期來源:migration-entry
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-direnv-gh-token · 2026-08-20** **用 direnv(`.envrc` 注入 `GH_TOKEN`)解 gh 雙帳號**:direnv hook 掛在 zsh precmd 上,而
  `ship-state.sh`／`gh pr create` 都是 agent 的一次性 Bash 呼叫,**precmd 不觸發**。**推廣:靠
  rc／prompt hook 的方案對 agent 執行路徑一律無效。**
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-midnight-commander-sftp · 2026-08-20** **mc(Midnight Commander)當遠端檔案管理器**:協定層否決——mc 的 `sftp://` VFS 走內建 libssh2、
  **不支援 OpenSSH 使用者憑證**,而內網主機一律 cert 認證,主要路徑不通。同樣需求用 `lftp`。
  **libssh2 支援 cert 之前,重評都是白費**。實測欄位與翻案條件見
  `docs/dead-ends.md`「mc 當遠端檔案管理器」。
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-copy-worktree-skill · 2026-08-20** **手動把 worktree 的 SKILL.md 複製到主 checkout,以繞過 `~/.claude/skills` symlink**:主 checkout
  有其他 writer、`brewup` 會丟棄未提交改動,而最要命的是**「測的到底是哪一版」變得不可考**
  ——與這些 skill 自己在防的「證據對不上結論」同型。**正解是先合併、主 checkout pull 之後再驗。**
  三條被排除的替代路見 `docs/dead-ends.md`「worktree 的 SKILL.md 複製到主 checkout」。
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-handoff-w1-external-diagnosis · 2026-08-20** **依外部提案的診斷改 `handoff` 的 W1(anchor 集合判準)**:三輪 eval 全部 GREEN 而放棄
  (依 Iron Law:no failing eval, no skill change)。**這條的價值在於「實地確實在寫入端失手,但
  fixture 重現不了」是兩件事,後者才是改 body 的門檻**。日後事故復發,**先讓 fixture 紅起來再動 W1**。
  三輪的逐條說詞見 `docs/dead-ends.md`「依外部提案改 handoff 的 W1」。
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260813-no-observed-red-rule · ** **無 observed RED 的明示規則**(2026-08-13 兩條當天全撤,同形狀第三次;2026-08-14 第四次改成
  **先跑成對實驗再決定**,零差異故沒寫)。**共同形狀:RED 來源本身證明了規則不必要**——
  **「觀察到失效面」≠「需要新規則」**,正確的問法是**既有規則接不接得住**,判準是成對實驗。
  例外只有「把 body 陳述錯的事實改對」那半(修正錯誤陳述不需 RED)。四次的逐條經過、eval 編號
  與那個被推翻的診斷見 `docs/dead-ends.md`「無 observed RED 的明示規則」。
  - 日期來源:migration-entry
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-narrow-known-gap · 2026-08-20** **收窄「已知缺口」定義(加上「我方」主體)**:G10 成對實驗,驗收批次 control 僅 **1/4** 落缺口
  (門檻 ≥3/4)→ 不改。**真正的發現是行為不穩定**——同一 fixture／query／模型,pilot 兩輪全落缺口、
  驗收四輪只有一輪落,**多數行為在兩批間反轉**。候選臂確實引用了收窄定義,所以不是定義沒用,
  而是 baseline 多數輪次也做對。⚠️ 連帶推翻 G9 留下的「節名歧義」假設(顯形率僅 1/4)。
  數據見 `claude/evals/contract-evals.md`「G10」。
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-global-routing-tree · 2026-08-20** **把 krepo 的「新東西該寫進哪一個檔」決策樹上收成全域規則**:G9 成對探測,兩臂各 4 輪
  **零差異**。**候選那臂還更糟**——為適配本 repo 加的「狀態類不走三題」成了跳過判準的逃生口,
  受測 agent 逐字引用它繞開決策樹。⚠️ 起念的理由「always-on 在回漲、沒人知道新內容該不該
  進去」**查證後不成立**(+2783 bytes 四筆都該在 always-on)——**又一次憑推論指認失效面**。
  數據見 `claude/evals/contract-evals.md`「G9」。
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260814-negative-status-delta · ** **拿「STATUS.md 負增量」當「被 flag 逼著壓縮」的代理指標**:2026-08-14 用過,結論全錯——
  多數負增量是拆分搬移與完成項移出,且該 repo 的量體 flag 早有明文豁免。**正解:數 flag 實際
  處置的 commit,並先查該 repo 自己的契約檔有無豁免**——量體訊號不分辨「誰讓它變小」。
  29 次負增量的實際分解見 `docs/dead-ends.md`「STATUS.md 負增量當壓縮代理」。
  - 日期來源:migration-entry
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-project-log-wrap-uap · 2026-08-20** **「/project log 包裝/並存 /uap」**:disable-model-invocation 下無法鏈式呼叫,只能複製
  pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,直接取代。
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-portable-dossier-copy · 2026-08-20** **在移交出去的 repo 內放一份 dossier 規範精簡版**:①**非自動載入的檔不會被讀**(G1b 實測);
  ②散到 N 個 repo 後零機械守門,規範一改就全部 stale 而沒人會發現,最壞是**交出去的東西主動教錯**;
  ③常駐檔會腐爛。**正解是既有落點**:STATUS.md 檔頭註解 + 該 repo 的 `CLAUDE.md`。
  G1b 實測與三條理由的展開見 `docs/dead-ends.md`「移交出去的 repo 內放 dossier 規範精簡版」。
  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260820-one-time-handoff-file · 2026-08-20** **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:實證 general-rag-cs 的已消費
  STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

  - 日期來源:migration-cutover
  - 放棄:原條目所述方案
  - 重議:見原文
  - 關聯:STATUS.md cutover

- **X-20260821-clone-origin-head-baseline · 2026-08-21 在 clone 內驗刪除類檢查時沿用 clone 自己的 `origin/HEAD`**:`git clone` 會把 `origin/HEAD` 指向被 clone 的那條 branch,於是 `immutability_base` 取到的是 feature branch head 而不是 `merge-base(HEAD, origin/main)`。後果是**方向相反的假綠/假紅**:branch 內建立的檔案變成「baseline 就已存在」,連修復前的舊程式碼也會紅,量出假的「已經修好」;反之站在 feature branch 上跑又會取到真 merge-base。復驗前必須先 `git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main` 並把實際 baseline commit 印出來對照。
  - 日期來源:direct
  - 放棄:直接在 clone 的預設 branch 佈局上量刪除類檢查
  - 重議:baseline 解析改為顯式參數而非從 remote HEAD 推導
  - 關聯:scripts/doc-governance.py;M-20260821-immutability-removal-axis-closed

- **X-20260821-inbound-shard-false-red · 2026-08-21 拿有 inbound reference 的 history shard 驗 immutability**:刪掉 `docs/archive/dead-ends-2026-08.md` 這種被 STATUS.md 與 `docs/dead-ends.md` 指到的 shard,audit 會噴十幾條 finding——但其中絕大多數是 xref 斷鏈,**immutability 那一條被淹沒**,「有紅」因此不構成「有守門」。要證明 immutability 真的在守,必須另造一個沒有任何 inbound reference 的 in-branch shard(合成 shard 需備齊 stable ID、事件記錄節與 `日期來源`,否則過不了前置的乾淨 audit),刪除後**恰好只剩那一條 finding**。
  - 日期來源:direct
  - 放棄:用既有的高引用 shard 當刪除類檢查的樣本
  - 重議:audit 輸出改為可依 check 分類篩選,能直接斷言單一檢查是否命中
  - 關聯:scripts/doc-governance.py;M-20260821-immutability-removal-axis-closed

- **X-20260822-doc-h1-token-signal · 2026-08-22 用文件 H1 當弱訊號提升程序型文件召回——量到淨零,不採用**:假設是程序型文件的 section 標題多半是結構性的(「0. 前置」「2. history 遷移」),主題詞只出現在 H1 與 body,所以把文件自己的 H1 token 以 60 分權重(介於 title 200 與 body 20 之間)加進每條 entry 的計分。**單獨量 hit@5 12→13,但疊在 per-file cap 上仍是 13/20**——逐題比對發現它修好一題(rollout checklist 那題)、同時弄丟一題(`claude/CLAUDE.md` 的並行寫入規則那題),淨零。理由是 H1 對「文件是什麼」有用,但對 always-on 這種 H1 泛泛的檔反而稀釋。依「成對實驗兩臂零差異就撤」不採用,程式碼未進版本庫。
  - 日期來源:direct
  - 放棄:先留著等更多語料再判(留著就是把未經證實的權重塞進計分,下次量測會分不出是誰的貢獻)
  - 重議:第三份語料進來後重跑同一組 query,若 H1 訊號在多個語料上一致為正
  - 關聯:M-20260822-retrieval-source-diversity;B-20260821-debt-27
