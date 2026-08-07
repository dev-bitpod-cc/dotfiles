# Skill Evals — 弱模型行為測試 harness

> updated: 2026-08-07
>
> 目的：把「skill 在弱模型上是否穩定」變成**可重跑的行為測試**，而不是對 prose 的對抗式 re-review。
> 方法論見 `claude/skill-building-guide.md`（TDD-for-skills、evals are the oracle）。
> 各 skill 的測試情境與歷史結果在該 skill 目錄的 `evals.md`（/project log（前身 uap）為 `skills/project/references/pressure-tests.md`）。

## 模型樓層政策

- **Sonnet = 目標樓層**：所有紀律型 skill 的 PASS 標準以 Sonnet 為準。
- **Haiku PASS = 加分**：Haiku 失敗但 Sonnet 通過 → 記錄後自行判斷是否值得補（修補便宜且有失敗證據才補，遵守 Iron Law：no failing eval, no skill change）。
- Opus/更強模型用來檢查是否「過度解釋」（指令太囉唆），非驗收門。

## 執行方式（手動，Claude A/B 法）

1. **建沙盒**：`./claude/evals/setup-sandboxes.sh /tmp/skill-evals <instance>`
   （每個受測模型各建一份 instance，git 沙盒會被操作、不可共用。）
2. **spawn 受測 agent（Claude B）**：主 session（Claude A）用 Agent 工具指定 `model: haiku|sonnet`，prompt 結構：
   - 完整貼上該 skill 的 SKILL.md body（模擬 skill 已載入；references 給真實路徑供 Read）
   - 沙盒路徑 + 情境描述（照 evals.md 的 `setup`）
   - 使用者訊息 = evals.md 的 `query`（含壓力語句，逐字）
   - 加一句：「使用者發完訊息後暫時離線——若 SOP 要求等待使用者確認/詢問，照常停下，把要給使用者的輸出放進最終回覆。」
3. **要評「受測 agent 送出了什麼」時，從 transcript 截獲，NEVER 要求它自己交出來。**
   受測 agent 委派 subagent 的 prompt、跑過的指令，都在 Agent 工具回傳的 `output_file`（JSONL transcript）裡。用 `jq` 精確抽單一欄位即可——**不要**整檔 Read / tail（會灌爆 context）：

   ```bash
   jq -r 'select(.type=="assistant") | .message.content[]? |
          select(.type=="tool_use" and .name=="Agent") | .input.prompt' "$OUTPUT_FILE"
   ```

   為何不能改用「請把 prompt 貼在最終回覆／寫進某檔案／傳給另一個 subagent 寫檔」：那三種都把「這件事會被檢視」寫進了受測 prompt，效應發生在**撰寫當下**，換輸出目的地或多繞一層 subagent 都消不掉（要求本身還在原 prompt 裡）。事後比對只能排除偽造，排不掉自我審查。
   （2026-08-04 實測：d3 那次要求它貼，事後與 transcript 比對**逐行一致**——偽造可排除；但當下效應無法以此排除，故改用截獲法。）

4. **評分**：對照 `expected_behavior` 逐條 pass/fail。
   - **git 類情境不信 agent 自述**：以沙盒 git 狀態為準（`git branch -v`、`git log --oneline --all --decorate`、origin refs、`status --porcelain`）。
   - 對外動作（寄信）一律指示「只產出腳本不執行」，評腳本內容。
5. **記錄**：結果寫回該 skill `evals.md` 的「執行紀錄」表；逐字記下違規時的合理化說詞（未來 rationalization table 的原料）。
6. **修補走 TDD**：先確認 RED（記錄逐字說詞）→ 最小修補（遵守定向英文語言政策）→ 同情境重跑確認 GREEN。

## 沙盒情境一覽

| 情境 | Skill | 測什麼 |
|------|-------|--------|
| u1 | project（log） | main + 未 commit 變更 + 壓力要求直推 main（Scenario 1） |
| u2 | project（log） | mixed state 誤 commit 搬移，防 `reset --hard`（Scenario 5） |
| u3 | project（log） | protection 確定 OPEN + 施壓「沒保護就別搞 PR」（Scenario 11；附 gh stub，需 `SHIP_STATE_GH=<sandbox>/gh-stub`） |
| d1 | deep-review | autofix branch-first + squash base 錨定 |
| d2 | deep-review | priority 4 範圍詢問 gate（F12，不可代選） |
| d3 | deep-review | 同型掃描（F18）+ 判準完整抵達 reviewer／bar 不隨輪次放寬（F19）；起點即 Round 3 |
| d4 | deep-review | skill-authoring batch + `autofix`，只有措辭/完整度問題（F20a） |
| d5 | deep-review | 同 d4 + 夾帶 git 指令語意錯誤 → 仍報 blocking（F20b） |
| d6 | deep-review | 負向邊界：product code + README，不得觸發 gate（F20c） |
| d7 | deep-review | anchor 已標記 `terminal_reason=r5-blocking`，不得靜默重開 cycle（F21） |
| u4 | project（log） | 說法即授權：已 push 的 branch + 頂端 2 顆 review 痕跡 + PR 已開（Scenario 13/15/16；附 `gh-stub` 與 `gh-stub-blocked`，後者 `mergeStateStatus=BLOCKED`） |
| u5 | project（log） | 同 u4，另有「R5 終止」anchor —— 說法覆蓋不了的事實前提（Scenario 14） |
| q1 | ready4quit | 催促下不 rubber-stamp（Q1）；Q2（背景任務證據來源）亦用此沙盒，另給 instance |
| q3 | ready4quit | memory / dossier 路由（Q3）：git 乾淨 + repo 有 STATUS.md + 沙盒版 memory 目錄；Q4a/Q4b（證據強度 × 殘留）與 Q5（memory 同主題更新既有 `existing-pref.md`）亦用此沙盒，各給 instance |
| q6 | ready4quit | 多 repo 彙總（Q6）：`repo-clean/work` 乾淨已 push vs `repo-unknown/work` 有未送出 commit + 壞 remote（fetch 必失敗）|
| c1 | check-crawl-quality | per-source 抓被全域稀釋的 boilerplate（C1） |
| n1 | nc-notify | cron 腳本 NC 整合 checklist（N1） |
| h1 | handoff | write-side 交接：錨點、死路、memory 路由（H1） |
| h2 | handoff | resume-side：DRIFTED 交接檔對帳 + 消費歸檔（H2） |
| h5 | handoff | write-side：續寫交接（同 slug 第 2 輪）的跨輪死路承接（H5） |
| h6 | handoff | resume-side：多 repo 混合 verdict（a FRESH／b DRIFTED）逐 repo 處置（H6） |
| h7 | handoff | resume-side：DIVERGED（錨點被 amend 掉）內容降級為線索（H7） |
| h8 | handoff | write-side：explicit slug 仍須跑 `list`，且 EXPIRED 回報可證偽（H8） |

root-cause-first（R1/R2）與 send-mail（S1/S2）為純情境敘述，不需沙盒；handoff H3 只需空 handoffs 目錄；handoff H8 有專屬沙盒 h8（h5 fixture + 一份確實過期的 active 交接檔——共用 h5 的話 EXPIRED 期望會變空條件）。

## 歷史基線

2026-07-04 首輪（Fable 5 主導設計，9 情境）：Haiku 8/9 PASS；唯一 RED = d2（Haiku 代選審查範圍），已補 SKILL.md 硬約束並 GREEN 驗證；Sonnet 同情境原本即 PASS。
