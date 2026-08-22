---
name: deep-plan
description: Reviews an implementation plan before coding by sending it to independent fresh reviewers, verifying its claims against the target repository, and gating work on explicit finding dispositions plus a second review round. Use for 計畫審查, 開工前檢查, plan review, pre-implementation approval, or asking whether an existing plan is safe to start. Do not use to create a plan or review code already written.
---

# Deep Plan

在任何 code 尚未為這份計畫寫下之前，查證計畫是否建立在正確的 repo 事實、歷史、相依與完成判定上。

你是 orchestrator，不是 reviewer。你的工作是建立隔離、收攏證據、追蹤 finding 處置並執行 gate；不要先形成自己的計畫評分，也不要替 reviewer 重寫計畫。

## Hard contract

- **Every review pass uses fresh reviewers. NEVER resume, follow up, or reuse a reviewer. Fresh context is the mechanism, not an optimization.**
- **Parallel means N reviewer IDs exist before any reviewer result is awaited or consumed. Reviewer 1 finishing before reviewer 2 is created is a failed round, even if both are fresh, unless the runtime first returned an explicit parallel-capacity error and that refusal is preserved in the report.**
- **Reviewer verdicts are not approval.** 「修完即可執行」等條件式結論不承重；只看 typed findings、明確處置與第二輪結果。
- **Reviewers report; they never rewrite the plan.** 作者與 reviewer 必須分離。
- **Run at most two rounds in one review. NEVER add a third round to chase convergence.**
- **Reviewer prompts never contain prior findings, author explanations, round numbers, progress hints, or the plan text.** 只傳 artifact path、repo path 與 reviewer brief path。
- **Keep target repositories read-only during reviewer work.** 只允許讀檔、搜尋、唯讀 git 與測試／診斷；不得修改、建立、刪除或執行會改變 git state 的命令。
- **Do not mutate this skill, its evals, field logs, inboxes, or unrelated repositories while running a plan review.** Skill authoring telemetry 不屬於使用者的 review scope。

## Runtime adapter

使用目前 runtime 的 fresh-subagent primitive；workflow 與 reviewer prompt 保持相同。

- Claude Code：每次建立新的 `Agent`；不要用 resume／SendMessage 延續 reviewer。同一輪的 N 個 Agent 要在收取任何結果前全部 dispatch。
- Codex：以 `spawn_agent` 建立 reviewer，明確使用 `fork_turns: "none"`；不要用 follow-up 延續 reviewer。固定順序是 `spawn reviewer_a` → `spawn reviewer_b` → 確認已有 N 個 reviewer IDs → 才能 `wait_agent`。N>2 時先繼續 spawn 到 N。
- 同一輪預設 N=2。**Launch every reviewer before waiting for any reviewer. NEVER wait for reviewer 1 before creating reviewer 2.** 只有 runtime 明確拒絕並行時才可依序建立；每個 context 仍須互相獨立。
- 若 runtime 無法建立 fresh subagent，停止並回報；不要退化成 orchestrator 自己審。

不要把 runtime 名稱或 adapter 細節放進 reviewer prompt。它們是 orchestration 私有狀態。

## Progress contract

開始時建立並持續更新這份狀態：

```text
Deep Plan
- [ ] 計畫 artifact 與目標 repo 已確認
- [ ] 第一輪 fresh reviewers 已完成
- [ ] Findings 已彙整並逐條處置
- [ ] 第二輪 fresh reviewers 已完成
- [ ] Gate 與未驗證事項已回報
```

## 1. Confirm the artifact and scope

確認輸入是一份**尚未實作**的既有 plan/spec，並找出它真正要修改的所有 repo。若 code 已經寫下，停止 deep-plan，改走 code review；若使用者要你產生 plan，改走一般 planning workflow。

計畫必須是一個 reviewer 可讀的檔案：

- 已有 canonical plan → 直接使用，不複製、不另建 `-v2`／`-final`。
- 只存在於對話 → 遵循**目標 repo** 的 contract 與 docs conventions；有既定 plan 目錄時寫入該處，否則使用明確標示、不會隨 repo ship 的 scratch artifact。
- 用不會解譯 shell syntax 的檔案編輯能力落檔。**NEVER use shell heredocs, echo, or printf to write user-supplied plan text.**
- 計畫落點跟著目標 repo，不跟著目前 cwd。

只讀到足以辨識目標 repo、計畫類型與是否屬於「放行／攔下」判準變更的程度。不要先評分計畫。

預設 N=2；只有使用者明確要求更廣抽樣時才提高。多 repo 計畫交給同一組 reviewers，讓每個 reviewer 檢查跨 repo 一致性。

## 2. Launch round one

先把本 skill 目錄下的 [references/planner-brief.md](references/planner-brief.md) 解析成 reviewer 可讀的絕對路徑。若是從 worktree 測試本 skill，使用該 worktree 的實際路徑，不要誤用指向其他 checkout 的全域 symlink。

每個 reviewer 使用完全相同的 prompt，只替換以下三類 runtime 值：plan artifact 絕對路徑、目標 repo 絕對路徑清單、reviewer brief 絕對路徑。

```text
你要審查的是一份尚未實作的 implementation plan，不是程式碼。請完整讀取計畫檔：
  {PLAN_ABSOLUTE_PATH}

計畫要修改的 repo（全程唯讀）：
  {REPO_ABSOLUTE_PATHS}

NEVER modify, create, or delete files in those repositories. NEVER run a git command that mutates state. Read-only inspection, search, history lookup, and non-mutating tests are allowed.

逐一把計畫對 repo 現況、歷史、相依與完成判定的宣稱拿回 repo 查證。不要採信計畫的自信措辭、行號或故事；查不到外部／production 事實時標為未驗證，不要擅自當真或當假。依語意關係找相依，不只搜尋同字串。

Read this reviewer contract completely before classifying findings:
  {BRIEF_ABSOLUTE_PATH}

Do NOT rewrite the plan. 你的產出只有 findings、查證結果與判斷。

輸出繁體中文：
1. 每條 finding 都包含：問題、層別（可查證／判斷）、嚴重度（阻斷／高／中／低）、查證依據（檔案:行號或命令與結果）。四欄都必填。
2. 已查證為真的宣稱清單。
3. 查不到、需要外部服務／production data／即時網路的宣稱清單。
4. 最後一句：目前是否建議開始執行。

直接回傳內容，不要寒暄。
```

若計畫改動告警、權限、豁免、過濾、SLA 或其他「誰被放行／攔下」的判準，在兩個唯讀段落之間加上：

```text
特別注意這份計畫改的是一組判準：請具體查出改完後哪些真實個體／情境會落入哪一格，尤其哪些原本會被攔下的東西會從此通過，以及其中是否混入不會自行恢復的子類。
```

其他類型不要追加。除此之外不得客製 reviewer 的焦點；獨立採樣的價值來自相同任務、不同 fresh context。

## 3. Synthesize without judging

按「指向同一件事」合併，不按嚴重度或措辭相似度合併：

- 保留每個 reviewer 的證據；多個來源互補時並列。
- 標出幾位 reviewer 獨立命中同一 finding。
- 單一 reviewer 的 finding 也完整保留，不自行降級。
- 合併「已查證為真」與「未驗證」清單。
- 層別與嚴重度沿用 reviewer 原值。兩位 reviewer 分類不同就如實並陳；欄位缺失標成「未分類」，交作者裁決。

**You are stitching, not filtering. NEVER reclassify, suppress, soften, or invent a finding.**

Gate 使用 reviewer contract 的共同定義：只有「可查證層」且嚴重度為阻斷／高／中的 finding 才是 blocking；判斷層與低級 finding 照列但不擋開工。

## 4. Obtain explicit dispositions

把第一輪結果交給計畫作者。每條 blocking finding 都必須明確落入一種處置：

| 處置 | 必要內容 |
|---|---|
| 修正 | 修改同一份 canonical plan；不得讓 reviewer 代寫，也不得另建 revision 檔 |
| 駁回 | 附可查證的 repo 證據，說明為何是 false positive |
| 接受為 trade-off | 寫明接受的代價與重新評估條件；放進 repo **既有**決策存放處 |

若 repo 沒有既有決策存放處，不要代建；把 trade-off 放在本次報告的獨立處置節，該節就是這次 review 的記錄。`noted`、看過了、沉默或 reviewer 的 conditional approval 都不是處置。

作者用「跟既有 X 一致」駁回，或想用測試把 finding 質疑的行為固定下來時，重新打開該 finding：查 X 當初的理由是否也適用於新情境。Established behavior 不是理由；shared reason 才是。

未取得必要處置前停止，不啟動第二輪。除非使用者已明確授權修改 plan，否則只呈現 findings 與所需決策，不替作者選處置。

## 5. Launch round two and apply the gate

處置完成後，用相同 N、相同 prompt、同一份已修訂 artifact 建立另一組全新 reviewers。第二輪 prompt 不得說它是第二輪，也不得要求確認修正；reviewer 可能從 repo 既有決策存放處讀到已接受的 trade-off，這是無法也不應封鎖的 repo evidence，不要宣稱 context 完全零污染。

第二輪 gate：

- 無 blocking finding → 通過，可開工。
- blocking findings 全部精確對應已接受且已記錄的 trade-offs → 通過，逐條列出殘留風險。
- 出現任何新的 blocking finding，或第一輪 finding 未取得有效處置 → 不通過。
- 低級或判斷層 findings 不擋通過，但必須留在報告。

兩輪後停止。若新的 blocking findings 集中在未取得的事實，先取得事實；事實真的改變後，可視為新的 review。若 findings 已在動 Goal、核心判準或架構，退回 spec／Goal 決策。**Fewer findings is not convergence evidence. Do not run a third round.**

## 6. Report

最終回報至少包含：

- `GO`／`NO-GO`，以及 gate 的直接理由。
- 合併後 findings：原始層別、嚴重度、重疊數、證據與處置。
- 已查證為真與未驗證的宣稱。
- 第二輪新 findings 與已接受的殘留風險。
- 若不通過，下一步是取得哪些事實或回到哪個 Goal/spec 決策。

不要附加 skill telemetry、field-log inbox 或與使用者計畫無關的 ship reminder。Behavior eval 與 field data 的更新屬於獨立的 skill-authoring 工作。
