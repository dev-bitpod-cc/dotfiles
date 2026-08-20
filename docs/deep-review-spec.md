# deep-review skill 規格書（需求層蒸餾快照）

> **快照基準**：deep-review skill @ commit 22ae336（2026-07-21）。
> **定位**：clean-room 重寫實驗（見文末附錄）產出的需求層蒸餾——描述**目標、硬需求、環境事實**，
> 不描述實作機制。**Non-normative**：skill 演進不回寫本檔（避免 double-source；**唯一例外＝『本條已被推翻，見 X』的失效標記**——不回寫等於讓被推翻的條文以現況之姿被讀，比 double-source 更危險；
> 實作的單一權威恆為 `claude/skills/deep-review/`）。
> **用途**：skill 的第一份需求層文件；重大重構或移交時的規格參照；附錄記錄「只活在實作裡」的知識缺口。

## 任務

為 Claude Code 設計並撰寫一個名為 `deep-review` 的 skill。交付物：

1. 完整的 `SKILL.md`（含 frontmatter：name、description、user-invocable、argument-hint、allowed-tools）
2. 若設計需要支援檔案（腳本、reference 文件），為每一個寫出**規格**：檔名、職責、
   介面（引數 / 輸出格式 / exit code 契約）、為何需要它。

## 目標

深度 code review：結合專案 CLAUDE.md 慣例與架構知識，對 diff 或指定模組進行多維度審查。
不只看 diff 表面——讀周圍程式碼、理解架構、比對專案慣例、評估整體性（code 是否像一次寫成）。

使用方式：使用者跑 `/deep-review [modes] [target]`，或以中文觸發詞（「審查」「幫我看 code」等）觸發。

## 功能需求

### F1 審查範圍判定
- 引數可指定：檔案/目錄路徑、commit range（`X..Y`、`HEAD~N`、hash）
- 無引數時需自動判定合理範圍（working tree 有變更？branch 領先主分支？都沒有？）
- 需支援「全庫稽核」語意（審整個 repo，非 diff）
- 存在「無法自動判定合理範圍」的狀態；該狀態下的行為見 H6

### F2 多輪迭代
- Review → 使用者（或自動）修復 → 再 review，直到通過或達上限
- 需能偵測「這是第幾輪」，且該偵測要能跨 session 存活（見 E1）

### F3 autofix 模式
- 引數含 `autofix` 時：自動執行 review → fix → 驗證 → commit 循環，直到通過或達上限
- 上限輪數需設計並說明理由；達上限須停止並輸出報告，不可無限循環

### F4 autocodex 模式（第三方審查）
- 引數含 `autocodex` 時：主審查通過後，交給本機的 Codex CLI（OpenAI 的獨立 reviewer）
  再做一輪第三方審查循環：codex 出 findings → 逐條獨立驗證 → 修真問題 → 再審，直到收斂或達上限
- `autocodex` 與 `autofix` 正交，可單獨或組合使用

### F5 跨 repo
- 一個 session 可能同時改了多個 repo；skill 需支援一次審查多個 repo，
  且包含跨 repo 一致性檢查（介面契約兩端、env vars、API schema、文件同步）
- repo 清單來自 session 記憶 + 使用者確認，不掃描檔案系統找 repo

### F6 審查維度
至少涵蓋：正確性、安全性、架構一致性、專案慣例（CLAUDE.md）、韌性（error handling）、
效能、測試、整體性/cohesion、跨檔案契約、跨 repo 一致性（多 repo 時）。
變更若含 shell/git/CLI 指令（含文件裡夾的指令），需逐條對照工具真實行為驗證語意，
不接受「看起來合理」。

### F7 報告
- 需區分嚴重度，並定義哪些等級 blocking（阻擋通過）、哪些不 blocking
- 通過報告需含可轉交第三方 reviewer 的資訊（repo、commit 範圍）
- 報告首要讀者是「負責修復的 agent」，其次才是人

## 硬需求（Hard requirements — 違反即設計不合格）

- **H1 審查者與作者分離**：主 agent 通常就是變更的作者，有 confirmation bias。
  code-quality 判斷不可由主 agent 做；主 agent 只做 orchestration 與修復。
  需定義「無法分離時」的降級行為（明確告知 + 標註風險，非默默降級）。
- **H2 迭代紀律**：每輪修復後必須 commit 才進下一輪；最終通過後 squash 成乾淨 commit。
  squash 的 reset 目標必須是**固定 hash**，且 **NEVER a moving ref, NEVER HEAD~N**
  （context 壓縮或跨 session 後仍須正確，見 E1）。
  > 本條原寫「reset 目標必須恆等於『本次審查的起點』」，**2026-08-06 已推翻**（見附錄與
  > STATUS.md）：目標改為由審查起點往上掃 subject 求得，只收攏 review 產生的 commit。
  > 「固定 hash、不用 moving ref」的部分未變，仍是硬需求。
- **H3 Branch 保護**：autofix 產生的 commit 絕不可落在 default branch 上；
  需在第一個 commit 前處理。NEVER push、NEVER merge（使用者明說才做）。
- **H4 修復後驗證**：commit 前須跑該 repo 的測試；測試失敗不 commit、不進下一輪。
  需定義「repo 無測試框架」與「測試環境壞掉」的行為。
- **H5 Findings 獨立驗證**：收到 codex findings 後逐條讀原始碼獨立判定
  true positive / false positive / context-dependent，不預設對錯，只修真問題。
- **H6 範圍不可代選**：當自動判定落到「沒有明確合理範圍」時，必須問使用者，
  NEVER pick a scope yourself——審錯範圍浪費整輪執行。
- **H7 每輪獨立視角**：不把上一輪 review 報告傳給下一輪 reviewer，避免錨定。

## 環境事實（Environmental facts — 實戰得來，設計必須容納）

- **E1 Context 會被壓縮**：長 session 中主 agent 的對話記憶會被 summarize；
  「記在腦中」的 hash、輪次、狀態都可能遺失。任何跨輪/跨 session 必須正確的 state，
  不能只靠 model 記憶。
- **E2 大 diff 撞 context 上限**：變更檔數多時，單一 reviewer subagent 吃不下完整 diff；
  且把 diff 內容經主 agent context 轉手一次會雙倍花費 token、零資訊增益。
- **E3 Codex CLI 行為**：
  - headless exec 模式可用、以 exit code 判成敗；執行耗時數分鐘，適合背景執行
  - 經 plugin broker 路徑（`codex:rescue`）呼叫會靜默卡死，不可使用
  - repo review 只接受 repo root，不接受子目錄
  - prompt 加料（focus 指示、context 檔）會讓其行為不穩，固定短 prompt 是已知穩定做法
  - 以 `bun install -g` 安裝 codex 會與 brew 版本 split-brain；本機以 brew cask 管理
- **E4 Completeness 深井**：對抗式 reviewer（含 codex）對「完整度類」問題
  （更多測試、更多 edge case、更多文件、措辭更清楚）每輪換角度都能再撈一批，沒有底。
  若當 blocking 處理，循環永不收斂。設計必須有閘攔住這類 findings。
- **E5 Model 手算 git range 會錯**：讓 model 自己組 `X..Y`、記 last-reviewed HEAD、
  算 merge-base，在多輪循環中遲早出錯（尤其 E1 之後）。
- **E6 使用者的 git 紀律**（全域 CLAUDE.md）：Conventional Commits；
  NEVER push / merge on your own。

## 撰寫規範

- 先讀 `~/.dotfiles/claude/skill-building-guide.md`，遵循其結構與語言政策
  （硬約束用英文、程序步驟用繁中、description 中英並列）
- Skill 面向的執行者是 Claude Code agent 本身；寫給 agent 讀，不是寫給人的教學文

---

## 附錄：已知缺口（clean-room 比對實證，2026-07-21）

> 實驗方法：以本規格讓一個禁讀現有實作的 subagent 從零重寫 skill，再與現有實作比對。
> 下列機制是 clean-room 版**未能從本規格推導出**的現有實作知識——代表這些知識
> 「只活在實作裡」，本規格（需求層）尚未涵蓋。未來補進需求層或重大重構時優先確認：

1. **C2+ 增量 range 及其安全論證**——codex 第二輪起只審 `<上輪 codex HEAD>..HEAD` 增量
   （C1 已全審變更集前段，C2+ 只需驗新修復），兼顧 anti-HEAD~1 與額度成本。
   本規格未表達「重複全審的成本約束」這一需求。
2. **Path 模式的 codex 範圍擴大告知**——codex 只收 repo root，path scope 的 codex 階段
   實際審整個 repo，須明告使用者、不偽裝成只審了子目錄。規格未涵蓋「宣稱範圍與
   實際範圍不一致時的誠實義務」。
3. **Preflight runtime hygiene 檢查**——孤兒 broker / stale state 的告知性檢查
  （非阻擋）。規格 E3 只列了坑本身，未表達「進入 codex 階段前的環境自檢」需求。
4. **多 remote 時的 base 選擇提示**——多個 remote 存在時 base 偵測有歧義，
   非 autofix 模式應提示使用者指定。
5. **Empty-tree 全庫 baseline 機制**——全庫稽核以 git empty-tree 為 diff base 的具體語意
   （empty-tree 非 commit，不可作 reset 目標）。
6. **進度 checklist 儀式**——執行前複製 checklist 進回應逐項打勾（對抗長流程漏步驟）。

另：clean-room 版在「squash 錨點語意」上做出與現有實作不同的合法設計
（scope_base 與 squash_anchor 分離、只收攏審查產生的 commits），暴露本規格 H2
「本次審查的起點」一詞的歧義——2026-07-21 已拍板維持現狀（anchor = 審查範圍起點，
squash 範圍恆等審查範圍）並在 squash-cmd 加壓掉前警告。
**2026-08-06 該拍板已被推翻**：改採與此處 clean-room 版相近的設計（squash base 由 subject
掃描求得、只收攏 review 產生的 commits，語意 commit 保留），故本段記錄的是**當時**的結論，
勿據此判斷現行實作；現況讀 `claude/skills/deep-review/`，理由以
`scripts/doc-governance.py find '2026-08-06 squash 範圍與審查範圍解耦'` 定位 canonical record。
