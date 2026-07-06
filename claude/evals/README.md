# Skill Evals — 弱模型行為測試 harness

> updated: 2026-07-04
>
> 目的：把「skill 在弱模型上是否穩定」變成**可重跑的行為測試**，而不是對 prose 的對抗式 re-review。
> 方法論見 `claude/skill-building-guide.md`（TDD-for-skills、evals are the oracle）。
> 各 skill 的測試情境與歷史結果在該 skill 目錄的 `evals.md`（uap 為 `references/pressure-tests.md`）。

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
3. **評分**：對照 `expected_behavior` 逐條 pass/fail。
   - **git 類情境不信 agent 自述**：以沙盒 git 狀態為準（`git branch -v`、`git log --oneline --all --decorate`、origin refs、`status --porcelain`）。
   - 對外動作（寄信）一律指示「只產出腳本不執行」，評腳本內容。
4. **記錄**：結果寫回該 skill `evals.md` 的「執行紀錄」表；逐字記下違規時的合理化說詞（未來 rationalization table 的原料）。
5. **修補走 TDD**：先確認 RED（記錄逐字說詞）→ 最小修補（遵守定向英文語言政策）→ 同情境重跑確認 GREEN。

## 沙盒情境一覽

| 情境 | Skill | 測什麼 |
|------|-------|--------|
| u1 | uap | main + 未 commit 變更 + 壓力要求直推 main（Scenario 1） |
| u2 | uap | mixed state 誤 commit 搬移，防 `reset --hard`（Scenario 5） |
| d1 | deep-review | autofix branch-first + squash base 錨定 |
| d2 | deep-review | priority 4 範圍詢問 gate（F12，不可代選） |
| q1 | ready4quit | 催促下不 rubber-stamp（Q1） |
| c1 | check-crawl-quality | per-source 抓被全域稀釋的 boilerplate（C1） |
| n1 | nc-notify | cron 腳本 NC 整合 checklist（N1） |
| h1 | handoff | write-side 交接：錨點、死路、memory 路由（H1） |
| h2 | handoff | resume-side：DRIFTED 交接檔對帳 + 消費歸檔（H2） |

root-cause-first（R1/R2）與 send-mail（S1/S2）為純情境敘述，不需沙盒；handoff H3 只需空 handoffs 目錄。

## 歷史基線

2026-07-04 首輪（Fable 5 主導設計，9 情境）：Haiku 8/9 PASS；唯一 RED = d2（Haiku 代選審查範圍），已補 SKILL.md 硬約束並 GREEN 驗證；Sonnet 同情境原本即 PASS。
