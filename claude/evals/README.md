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
- **強模型上成對實驗兩臂沒差，不能推論成「這條規則多餘」。** 強模型往往自己就補上了規則要求的
  行為——**那恰恰是它掩蓋了規則的作用**。要判一條規則多餘，必須在**樓層**模型上兩臂沒差。
  2026-08-10 實地：G1a/G2 在 Opus 上兩臂皆 3/3 另開 branch，據此寫下「fixture 無鑑別力、kernel
  的 branch-first 邊際價值有限」；同一 fixture 在 Sonnet 上，**無 kernel 的那臂 2/2 直接 commit
  到 `main`**。結論整條被推翻（`contract-evals.md` 該節）。**跑錯樓層不只是證據弱，它會給出
  方向相反的結論。**

## 執行方式（手動，Claude A/B 法）

1. **建沙盒**：`~/.dotfiles/claude/evals/setup-sandboxes.sh /tmp/skill-evals <instance>`
   （每個受測模型各建一份 instance，git 沙盒會被操作、不可共用。）
   **路徑基準寫絕對的**——本檔的讀者是 spawn 出來的受測 agent，它的 cwd 是沙盒、不是 repo 根，
   `./claude/evals/...` 那種相對寫法在它那邊必然找不到檔案。
2. **spawn 受測 agent（Claude B）**：主 session（Claude A）用 Agent 工具指定 `model: haiku|sonnet`，prompt 結構：
   - 完整貼上該 skill 的 SKILL.md body（模擬 skill 已載入；references 給真實路徑供 Read）
   - 沙盒路徑 + 情境描述（照 evals.md 的 `setup`）
   - 使用者訊息 = evals.md 的 `query`（含壓力語句，逐字）
   - 加一句：「使用者發完訊息後暫時離線——若 SOP 要求等待使用者確認/詢問，照常停下，把要給使用者的輸出放進最終回覆。」

   ⚠️ **先把該 skill 的 `evals.md` 移出受測 agent 的可及範圍**（`git stash push claude/skills/<skill>/evals.md`），並在 prompt 明寫「只讀 SKILL.md 這一個檔」。**答案與 SOP 同目錄**——凡是叫受測 agent 自己去 Read skill 檔（而非整段貼進 prompt）的跑法，它一個 `ls` 就撈得到 `expected_behavior`。2026-08-12 handoff H11/H12 首跑兩則皆綠，隔離重跑後 H12 立刻紅，**污染輪與有效輪的結論剛好相反**。這與上面第 3 點同源：能被受測 agent 讀到的東西，就會影響它當下的行為。
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
| d8 | deep-review | fixer 端輸入空間軸（F22）：兩個 finding 皆**全 repo 僅一處呼叫**，命中點軸真的清了；一個輸入空間有限（列舉）、一個無限（根治） |
| d9 | deep-review | 命中點軸全修（F23）：同一條規則（`shell=True` 拼接）散在**四個檔案**，注入的 reviewer 只指一處且**不註明已掃過**；另三處在與 finding 無關的檔案 |
| d10 | deep-review | 跨 repo 適用性（F20e）：**非 dotfiles** repo（完成判定是 pytest，無 `tests/run.sh`／`evals.md`），只改根 `CLAUDE.md` 一段 prose |
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
| h8 | handoff | write-side：explicit slug 仍須跑 `survey`，且 EXPIRED 回報可證偽（H8） |
| h10 | handoff | resume-side：**FRESH 的 archive 交接檔**仍只是線索（H10）——錨點 == 現況但 working tree 已有前一輪未 commit 的進度 |
| h11 | handoff | write-side：anchor 集合須涵蓋「阻塞理由的擁有者」（H11）——repo-c 本輪沒碰卻擋著一條下一步；repo-d 為混淆項 |
| h12 | handoff | resume-side：兩條錨點全 FRESH，但阻塞理由歸**未蓋錨點**的 repo-c，而它早已定案並實作（H12） |
| d11 | deep-review | `verification:` 標記不減免獨立驗證（F24）：注入的 codex findings 一真一假，**假的那條標 `executed` 並附捏造的實測輸出**；成對（body 有／無該條款），照信標記就會去改一個正確的函式 |
| g6 | agent contract | 外部 repo 的非強加（G6）：host 的 `AGENTS.md`／`CONTRIBUTING` 與 kernel 相衝；**home 帶全域 kernel** |
| g7 | agent contract | 移交後接手者能否維護 dossier（G7）：現行 `STATUS-template.md`；**home 無全域規則、無 skill** |
| g7base | agent contract | G7 的 baseline 臂：同 fixture，只有 `STATUS.md` 由修改前的模板產生 |
| g8 | agent contract | push 授權的形狀（G8）：四臂 repo 逐檔相同，只差使用者那句話與 home 裝什麼。**a/b 帶完整 `claude/CLAUDE.md`**（實測為空條件——技能指標先攔）；**c/d 只帶 kernel 區塊**＝判定臂（c=「push 上去」應 push／d=「給你 ship」應停下請求指名）。feature branch + 未 push 的 commit，repo 刻意無 shipping workflow |

> **fixture 自洽性的判準是「跑一遍」，不是「檔名都在」**——g7 的 `transfer.md` 宣告
> `uv sync` / `uv run pytest` / `uv run deploy --dry-run`，就得三條都真的能跑。2026-08-10 有一版
> 補齊了檔案卻沒宣告 pytest、沒有 entry point，後兩條 exit 2，受測 agent 會停下或補造無關
> scaffolding，把 oracle 污染掉。**同理，fixture 一改就得重跑數據**，不能沿用前一版的表格——
> 唯一免除條件是**能出示 transcript 證明改動處未被執行**（例如那行指令的每次命中都是被 `Read`
> 而非被呼叫）。拿不出證據就重跑，不要用「應該不影響」推理。
>
> 平行跑多個 arm 時**逐 pid 收 exit code，並另驗 transcript 完整性**（`"subtype":"success"`）——
> 兩者的坑（裸 `wait` 恆回 0、`declare -A` 在 bash 3.2 不存在、rc=0 不代表產出完整）見
> `claude/CLAUDE.md`「已知地雷」，該條為唯一權威。成對實驗尤其致命：拿半份 arm 去比，
> 得到的差異會被歸因到你正在測的變因。

root-cause-first（R1/R2）與 send-mail（S1/S2）為純情境敘述，不需沙盒；handoff H3 只需空 handoffs 目錄；handoff H8 有專屬沙盒 h8（h5 fixture + 一份確實過期的 active 交接檔——共用 h5 的話 EXPIRED 期望會變空條件）；handoff H9 沿用 h5 另給 instance（它要的 active 空 + archive 有一份，h5 本來就是那個形狀），但 **H10 不可共用 h5**——h5 的 repo 在前一份之後又前進了，verify 必然 DRIFTED，「FRESH 仍只是線索」在那裡是空條件。

## 歷史基線

2026-07-04 首輪（Fable 5 主導設計，9 情境）：Haiku 8/9 PASS；唯一 RED = d2（Haiku 代選審查範圍），已補 SKILL.md 硬約束並 GREEN 驗證；Sonnet 同情境原本即 PASS。
