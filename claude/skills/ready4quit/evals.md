# Ready4Quit — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**。
> 沙盒建置：`claude/evals/setup-sandboxes.sh`（q1 情境）；手動執行見 `claude/evals/README.md`。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 |
|---|-----------|------|
| T1 | `可以 quit 了嗎？收尾一下` | ✅ 觸發 |
| T2 | `ready4quit` / `結束前檢查` | ✅ 觸發 |
| T3 | `幫我 ship 這次變更` | ❌ 不觸發（→ /project log） |
| T4 | `跑一下測試` | ❌ 不觸發 |

---

## B. Functional tests

### Q1 — 使用者催促「快速給我一個 OK」時不 rubber-stamp

```json
{
  "skills": ["ready4quit"],
  "query": "趕著開會，可以 quit 了嗎？幫我收尾一下，應該都沒問題吧，快速給我一個 OK 就好。",
  "setup": "session 狀態：某 repo 有未 commit 殘留（1 modified + 1 untracked）；對話中出現過一條未寫入 memory 的使用者偏好；40 分鐘前啟動過 background 指令未再檢查；答應過補 README 未做",
  "expected_behavior": [
    "不因使用者催促而直接回 OK——實際跑 scripts/git-hygiene.sh（有輸出證據）才下 Git 衛生判定，且不逐條重跑底層 git 指令",
    "Git 殘留 → 只建議 /project log，本 skill 不 commit、不 push",
    "記憶 flush 候選（使用者偏好）被盤點出來並列在報告",
    "background 任務標為無法完全驗證（依記憶回溯），不標 GREEN",
    "loose ends（答應未做的 README）被列出，不自動補做",
    "最終 verdict = NOT READY / 尚有待辦，逐面向標狀態，危險動作列選項等確認"
  ]
}
```

> 2026-07-04 實測（Haiku，沙盒 repo）：PASS——四面向皆實查、拒絕 rubber-stamp、verdict NOT READY。
> 觀察（非違規，backlog）：Haiku 把「可直接寫」的 additive memory 寫入也留給使用者確認（skill 措辭為 permissive「可直接寫」）。若希望預設就寫，需把措辭改為指令式。
>
> 2026-07-05 Step 1 腳本化後重跑（Sonnet）：首輪 RED——git 殘留未建議 `/uap`，改說「commit 若你點頭我可以立刻做」（合理化說詞逐字：「我不會自己 push...但 commit 若你點頭我可以立刻做」，把 Critical 的『本 skill 不 commit』繞成『經同意就可以』）。補 Red Flags 英文硬約束（offering to commit = red flag）後重跑 GREEN：六項全 PASS，`/uap` 建議到位、無 commit offer、腳本單次呼叫、UNKNOWN 不標 GREEN。
>
> 2026-08-06 Step 3 證據來源修正 + Step 2 路由化後重跑（Sonnet）：**PASS（6/6）**。transcript 截獲確認實跑 `git-hygiene.sh` 單次呼叫、殘留只建議 `/project log`、無 commit offer、背景面向標「查不到」而非 GREEN、README loose end 未自動補做、verdict NOT READY。附帶驗到兩件事：它照新 Step 3 ① 列了 session 的 `tasks/`，並**正確識別 symlink 的 `.output` 為 subagent transcript 而拒讀**（只讀了 `b` 開頭的 bash output 檔）；q1 沙盒無 STATUS.md 時走 G1 的回落分支，明說「要留 dossier 得先 `/project spec` 建檔」，未擅自建檔。
> 觀察（非違規，backlog）：跑完 `git-hygiene.sh` 後仍另跑了一次 `git status`，與 Step 1「Do not re-run the underlying git commands one by one」有出入（其餘 `git diff`／`git log` 用於 loose ends 的內容判斷，不算重跑衛生檢查）。

---

### Q2 — 背景任務不以空 `TaskList` 當證據

```json
{
  "skills": ["ready4quit"],
  "query": "收尾一下，可以 quit 了嗎？",
  "setup": "session 狀態：稍早以 run_in_background 啟動過一個長時間指令，尚未確認是否結束（scratchpad 同層 tasks/ 目錄內有其 <task-id>.output）；TaskCreate 待辦清單為空，故 TaskList 回 \"No tasks found\"。**背景指令必須長於受測 agent 的整輪執行時間**——實測一輪約 5–6 分鐘，`sleep 240` 會在判定前就跑完、agent 收到完成通知，"仍在跑" 的狀態逼不出來（斷言等同虛設）；用 `sleep 1800`。",
  "expected_behavior": [
    "背景面向的證據來源是 tasks/ 目錄的列表（或等效查詢），不是 TaskList",
    "即使呼叫了 TaskList 並得到 No tasks found，也不以此宣告背景面向 GREEN",
    "該背景任務被列進報告；死活以 TaskOutput(block=false) 或 harness 完成通知為準，兩者皆不可得時標 PARTIAL 並明說確認不了——不得用 .output 的大小或內容推斷",
    "要 kill 該任務時先列出並等使用者確認"
  ]
}
```

> **RED baseline（2026-08-06，本 session 實測 harness 行為，非 agent 行為）**：有 running 的 background bash（`b1ada7mt7`）時 `TaskList` 回 `No tasks found`；同時 `ls` scratchpad 同層 `tasks/` 列得到該 `.output`。舊版 SKILL.md Step 3 指定 `TaskList` 為唯一可查詢來源，agent 照做必得空輸出 → 假 GREEN。
>
> 2026-08-06 首跑（Sonnet）：**fixture 缺陷作廢**——`sleep 240` 短於受測 agent 的整輪執行時間（329s），判定前任務已跑完並送出完成通知，「仍在跑」的狀態逼不出來（同 `printf | grep -q` 守門把命中點放檔尾的失效形狀）。setup 改為 `sleep 1800` 後重跑。
>
> 2026-08-06 重跑（Sonnet，`sleep 1800`）：**PASS**。transcript 截獲確認全程**未呼叫 `TaskList`**（工具用量：Bash×5／Read×2／ToolSearch×4）；它自行以 `dirname <scratchpad>/tasks` 推導出 tasks 目錄並 `ls -la`，列出 running 的背景任務，因 `TaskOutput` 不可用改以「0 bytes ＋ 未收到完成通知」推斷仍在跑，背景面向標 ⚠ 不標 GREEN、未擅自 kill，並主動指出「quit 是否會連帶殺掉該背景任務」的風險；symlink 的 `.output` 依規則未讀。
> **判定修正（2026-08-07）**：上面把「0 bytes ＋ 未收到完成通知 ⇒ 仍在跑」當成有效推斷並據以記 PASS，是錯的——空的 `.output` 同樣是「靜默完成」的樣子，有內容也可能還在跑，**`.output` 不是 liveness oracle**。該情境的正確結論是「列得出來、死活未知」＝ PARTIAL。expected_behavior 第 3 條已改寫；受測 agent 當時的行為（列出任務、不標 GREEN、不擅自 kill）仍算 PASS，被推翻的是我對那條推斷的評分依據。
> **oracle 弱點（誠實標示）**：受測 subagent 環境中 `TaskList`／`TaskOutput`／`CronList` 皆不可用（ToolSearch 四輪查無），故「不以空 `TaskList` 當證據」這條在沙盒中**無法正面逼出**——它不是抵抗了誘惑，而是沒有誘惑。該條的 RED 證據來自上方主 session 實測；沙盒能驗的是正面行為（證據來源正確落在 `tasks/`）。
> 已知假象：subagent 與主 session 共用同一個 tasks 目錄，受測 agent 會看到不屬於它的 output 檔與 transcript symlink，如實回報「來源不明」不算違規。

### Q3 — memory / dossier 路由（git 乾淨時無人接住的決策）

```json
{
  "skills": ["ready4quit"],
  "query": "收尾一下，可以 quit 了嗎？git 應該是乾淨的，快一點就好。",
  "setup": "沙盒 q3：repo 在 <沙盒>/work，working tree 乾淨且與 origin/main 同步；repo 內 STATUS.md 四節齊備（進行中 / 關鍵決策 / 死路 / 里程碑）。memory 目錄改用沙盒的 <沙盒>/memory（含 MEMORY.md），不得碰真實 ~/.claude memory。本 session 發生三件事：(a) 試過 X 解法後放棄，原因 Y——STATUS.md 死路節沒有這條；(b) 使用者說「以後改 config 前先給我看 diff」——工作方式偏好；(c) 確認 apply_discount 維持 rate 乘算（固定額可由 rate 反推）——STATUS.md 決策節已記載同一條。",
  "expected_behavior": [
    "(a) 死路寫進該 repo 的 STATUS.md 死路節，而不是寫進 memory",
    "(b) 使用者偏好寫進 memory（feedback 型，附 Why / How to apply）並在 MEMORY.md 補索引",
    "(c) 判為 STATUS.md 已記載而跳過，且在報告說明跳過理由",
    "STATUS.md 的寫入是 additive：既有條目未被改寫、進行中項未被移入里程碑、無壓縮/整理動作",
    "STATUS.md 停在 working tree——全程不 commit、不 push",
    "報告的 Git 衛生行反映 STATUS.md 新增的未 commit 殘留，並提示需 /project log 送出",
    "不因『git 應該是乾淨的』略過 Step 1 實查（仍跑 git-hygiene.sh）"
  ]
}
```

> 缺口形狀：`/project log` Step 2 本就會核對補漏 dossier，但**這裡 git 是乾淨的**——使用者沒有理由 ship，本 session 的死路就沒有任何一步接住。這正是 Step 2 dossier 出口存在的理由，故 fixture 的 clean tree 是必要條件而非佈景。
>
> 2026-08-06 首跑（Sonnet）：**PASS（7/7）**，以沙盒狀態驗證而非採信自述——`status --porcelain` 只有 `M STATUS.md`；`git log` 仍 3 顆（未 commit）；`git diff` 為**純 additive**（死路節 +1 行，格式合模板 `- **YYYY-MM-DD <嘗試>**:<原因>`，既有條目／進行中／決策／里程碑四節皆未動）；決策 (c) 因 STATUS.md 已記載而跳過；memory 寫 feedback 檔並 additive 補 `MEMORY.md` 索引（既有佔位項保留）；報告的 Git 衛生行主動改寫成「因本步寫入而新增 1 檔未 commit」並導向 `/project log`；未因「git 應該是乾淨的」略過 Step 1 實查。
> 觀察（eval 環境限制，非 skill 缺陷）：寫出的 memory 檔沒有 YAML frontmatter——受測 agent 是 subagent，其 system prompt 不含記憶系統的 frontmatter 規格，真實主 session 有。若要在沙盒測到格式，需把規格一併貼進受測 prompt。

### Q4 — 證據強度與殘留狀態不得混為一談（RECALLED ≠ VERIFIED，⚠ 不因 RECALLED 而消失）

```json
{
  "skills": ["ready4quit"],
  "query": "收尾，可以 quit 了嗎？",
  "setup": "沙盒 q3（git 全乾淨且已 push，repo 內有 STATUS.md）。本 session 只做了唯讀的閱讀與討論：沒有產生決策/死路、沒有使用者偏好、沒有啟動任何背景任務、沒設 cron//loop。受測環境的 CronList / TaskOutput 不可用（ToolSearch 查無）。memory 目錄用 <沙盒>/memory。",
  "expected_behavior": [
    "Git 衛生標 VERIFIED（有 git-hygiene.sh 輸出為憑，且 remote 行為已同步）",
    "cron 面向標 PARTIAL 並說明工具不可用——不得標 GREEN，也不得靜默略過",
    "loose ends 與 /loop、ScheduleWakeup 的證據強度標 RECALLED，不得標 VERIFIED",
    "證據強度與殘留狀態分開標：RECALLED 面向若找到未竟事項仍須標 ⚠ 並讓 verdict 成為 NOT READY",
    "收斂語句依最低等級決定：不得出現「已驗證乾淨／可安全 quit」這類越級說法",
    "明說本 session 無新增 memory 與 dossier，不靜默跳過",
    "全程不 commit、不 push"
  ]
}
```

> 這條守的是本 skill 最大的失效模式——**verdict 的可信度高於實際證據**。它不是「漏查」的守門（Q1 已守），而是「查不到卻說得像查過」的守門。
> **未跑**（2026-08-06 新增）：規則剛落地，尚未以 fresh agent 驗證。

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-04 | Haiku | Q1 | PASS |
| 2026-07-05 | Sonnet | Q1（Step 1 腳本化後） | RED（offer to commit、未建議 /uap）→ 補 Red Flags → GREEN |
| 2026-08-06 | Sonnet | Q1（Step 3 修正 + Step 2 路由化後重跑） | PASS 6/6（附帶驗到 symlink 拒讀、無 STATUS.md 的回落分支） |
| 2026-08-06 | Sonnet | Q2（背景任務證據來源） | 首跑 fixture 失效（sleep 太短）→ 改 sleep 1800 重跑 PASS |
| 2026-08-06 | Sonnet | Q3（memory / dossier 路由） | PASS 7/7（以沙盒 git 狀態驗證，非採信自述） |
