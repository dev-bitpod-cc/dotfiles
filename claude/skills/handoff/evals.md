# Handoff — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**。
> 沙盒建置：`claude/evals/setup-sandboxes.sh`（h1 / h2 / h5 / h6 / h7 情境；h3 只需空 handoffs 目錄）；手動執行見 `claude/evals/README.md`。
> 沙盒版目錄對應：prompt 中明給「handoff 目錄用 <sandbox>/handoffs、memory 目錄用 <sandbox>/memory」，腳本用真實路徑。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 |
|---|-----------|------|
| T1 | `幫我寫交接檔，我等下要 /clear` | ✅ 觸發（write mode） |
| T2 | `接續上次的工作` / `接續交接 <slug>` | ✅ 觸發（resume mode） |
| T3 | `幫我記住這個偏好` | ❌ 不觸發（→ memory） |
| T4 | `可以 quit 了嗎，收尾一下` | ❌ 不觸發（→ /ready4quit） |
| T5 | `幫我 ship 這次變更` | ❌ 不觸發（→ /project log） |

---

## B. Functional tests

### H1 — write-side：交接檔品質與路由（沙盒 h1）

```json
{
  "skills": ["handoff"],
  "query": "context 快滿了，我要 /clear 之後開新 session 接著做。幫我把交接處理好。",
  "setup": "repo 有未 commit 的半成品 validate_order()；敘事脈絡含：死路（decimal.Decimal 全面改寫已放棄，因外部 API 全是 float）、決策（math.isclose，理由 float== 地雷）、durable 規則（使用者說金額欄位以後一律用分為單位的 int）、下一步含不存在的 orders.py（陷阱）",
  "expected_behavior": [
    "跑 handoff-anchor.sh anchors 蓋錨點，frontmatter 含 created + anchor 行（機器可驗證）",
    "dirty>0 → 報告提醒未 commit 內容不受錨點保護、建議先 commit（ship 指 /project log），不代為 commit",
    "死路一節完整（decimal 嘗試 + 放棄理由）；決策附理由",
    "orders.py 實際檢查過，標「待新建/規劃中」而非當既有檔案寫",
    "durable 規則路由到 memory 檔（交接檔僅留指標），不塞交接檔正文",
    "不貼整份 diff/檔案內容快照（指向 commit 與路徑即可）",
    "順跑 list 做 housekeeping、收尾提醒 /handoff resume <slug>"
  ]
}
```

> 2026-07-06 baseline（Sonnet，無 skill）：內容品質意外地好——死路含「不要重試」、決策附理由、自行抓到 orders.py 不存在。
> 但：**無錨點**（未記 HEAD sha）、貼整份 `git diff` 快照（快照本身會失效）、durable 規則只寫進交接檔（未路由 memory）、無任何生命週期概念。
> → skill 的 delta 定位：機器可驗證的錨點 + 生命週期 + 路由，而非 prose 品質。

### H2 — resume-side：DRIFTED 交接檔的對帳與消費（沙盒 h2）

```json
{
  "skills": ["handoff"],
  "query": "接續上次的工作，交接檔在 <sandbox>/handoffs/order-fetch-hardening.md，照著把剩下的做完。",
  "setup": "交接檔錨點記錄 commit1（utils.py + requests、下一步=加 retry + timeout 參數化）；repo 已前進 commit2：utils.py 改名 http_client.py、requests 換 httpx、retry 已完成——只剩 timeout 參數化仍有效",
  "expected_behavior": [
    "動工前先跑 handoff-anchor.sh verify（有輸出證據），不逐條重跑底層 git",
    "判 DRIFTED 後讀中間 commits 對帳：辨識 retry 已被做掉（不重做）、requests 決策已被推翻（不回退 httpx）",
    "只執行仍有效的項目（timeout 參數化），並向使用者報告落差",
    "完成對帳後以 handoff-anchor.sh consume 歸檔交接檔（時戳前綴落 archive/）——不手打 mkdir/mv 序列、不留在 active 目錄、不就地標 done",
    "不 push（CLAUDE.md 既有規則）"
  ]
}
```

> 2026-07-06 baseline（Sonnet，無 skill）：對帳部分意外地好——自發比對錨點 sha、辨識 retry 已完成、沿用 httpx 不回退。
> 但：**消費後就地更新交接檔**（加 `status: done` / `closed` 欄位留在 active 目錄，理由逐字：「沒有刪除，而是就地更新……方便後續追溯這個決策為何變了」）——失效檔案永久堆積，正是要杜絕的。且 verify 是自發行為、無 SOP 保證可重複。
> → Red Flags 已針對「就地標 done for traceability」逐字反制（traceability lives in archive/）。

### H4 — write-side：跨主機接續的分流（machine-local 限定）

```json
{
  "skills": ["handoff"],
  "query": "幫我寫交接檔，我明天會在 db01 那台機器上接續這個工作。",
  "setup": "當前主機非 db01；repo 有 STATUS.md（dossier）與未 commit 的 WIP；下一步明確（如對 batch endpoint 加 429 backoff）",
  "expected_behavior": [
    "辨識跨主機情境：實質下一步寫入 repo STATUS.md「進行中」章節（就地更新）並 commit（docs commit、feature branch——Critical 的唯一例外）",
    "交接檔僅留 pointer + 跨機提醒，不重複實質內容",
    "不 push；主動標示「未 push 前 db01 不可見」",
    "不在 repo 內新增一次性交接檔（HANDOFF.md）"
  ]
}
```

> 2026-07-16 實測（Sonnet，/project cutover 驗證輪，沙盒 git 實查）：PASS——詳細紀錄見 `../project/references/pressure-tests.md` Scenario 7 註記。

### H3 — resume-side：零交接檔（空 handoffs 目錄）

```json
{
  "skills": ["handoff"],
  "query": "接續上次的工作，把剩下的做完。",
  "setup": "handoffs 目錄存在但為空；agent 為全新 session、無先前記憶",
  "expected_behavior": [
    "跑 handoff-anchor.sh list（有輸出證據）確認零份 active",
    "明說沒有交接檔、請使用者指路——不憑空猜測工作內容、不亂翻目錄開始做事"
  ]
}
```

### H5 — write-side：續寫交接的內容承接（沙盒 h5）

> 依據：52 份實檔中 14 份是同一 slug（`evint-mvp-sprint` 7/22–7/27 共 14 輪），另 4 個 slug 各 2–3 輪
> ——約 40% 的交接檔屬多輪工作線，而「整檔覆寫」讓前輪死路沒有任何機制會被讀到。

```json
{
  "skills": ["handoff"],
  "query": "幫我寫交接檔，我等下要 /clear。handoff 目錄用 <sandbox>/handoffs、repo 在 <sandbox>/work。",
  "setup": "active 目錄空、archive/ 有前一份同工作線交接檔（order-pipeline-hardening，含兩條跨輪仍有效的死路：threading 併發打外部 API 被 per-key 限流打回、pydantic v2 遷移被 legacy 相依擋住）；repo 有 STATUS.md，其死路節刻意只有無關的 tenacity 一條；本輪進度：timeout 參數化已 commit、metrics WIP 未 commit。agent 為新 session，前一份不在 context",
  "expected_behavior": [
    "偵測到這是續寫（同工作線已有前一份），不當首輪處理",
    "讀 archive 最近一份，兩條跨輪死路必須有著落——沉澱進 STATUS.md 死路節（主路徑）或帶進新交接檔皆可，但不得雙雙消失",
    "沉澱進 dossier 者不在交接檔重複貼一次，只留指標 + 本輪增量",
    "跑 anchors 蓋錨點；dirty>0 → 提醒 metrics WIP 不受錨點保護、不代為 commit",
    "不把 archive 的前一份撈回 active，也不 append 到舊檔"
  ]
}
```

### H6 — resume-side：多 repo 混合 verdict 的逐 repo 處置（沙盒 h6）

> 依據：14/52（27%）交接檔帶 2–3 條錨點，而 `verify` 的 `verdict:` 是全域聚合旗標
> ——任一 repo 非 FRESH 即 STALE-RISK，拿它一刀切會讓 FRESH repo 的下一步被無謂降級。

```json
{
  "skills": ["handoff"],
  "query": "接續上次的工作，交接檔在 <sandbox>/handoffs/gateway-and-order-hardening.md，照著把剩下的做完。",
  "setup": "兩條錨點：repo-a 未動（FRESH）、repo-b 已前進一個 commit（DRIFTED——下一步第 2 條 retry 已被做掉、決策「HTTP client 用 requests」已被換成 httpx）；聚合 verdict 為 STALE-RISK",
  "expected_behavior": [
    "動工前跑 handoff-anchor.sh verify（有輸出證據），不逐條重跑底層 git",
    "repo-a 判 FRESH → 下一步第 1 條（rate limit）照原計畫接續，**不因聚合 STALE-RISK 一併降級為線索**",
    "repo-b 判 DRIFTED → 讀中間 commit 對帳：retry 不重做、requests 決策不回退，只執行仍有效的 timeout 參數化",
    "向使用者報告落差（哪個 repo 漂移、哪幾條失效）後才動工",
    "完成後以 consume 歸檔，不留在 active、不就地標 done"
  ]
}
```

### H7 — resume-side：DIVERGED 的降級處置（沙盒 h7）

```json
{
  "skills": ["handoff"],
  "query": "接續上次的工作，交接檔在 <sandbox>/handoffs/csv-parser-rewrite.md。",
  "setup": "錨點的 HEAD 被 amend 掉、不在現行歷史上；改寫後 parser.py 已改用 stdlib csv 模組——交接檔的決策「先自己寫而不用 csv 模組」與下一步「加引號欄位支援」都已被現況推翻（csv 模組本來就支援引號）",
  "expected_behavior": [
    "verify 判 DIVERGED → 交接內容一律降級為線索，不照著「下一步」直接動手",
    "改對 repo 現況重建：辨識 parser.py 已改用 csv 模組、引號支援已隨之取得",
    "落差大 → 先報告並等指示；**NEVER 把 parser 改回自寫版本來迎合交接檔**（repo 才是事實）",
    "無 verify 輸出就不執行任何下一步"
  ]
}
```

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-06 | Sonnet | H1 baseline（無 skill） | RED（無錨點、貼 diff 快照、durable 未路由 memory、無生命週期） |
| 2026-07-06 | Sonnet | H2 baseline（無 skill） | RED（消費後就地標 done 留在 active 目錄；verify 為自發、不可重複） |
| 2026-07-06 | Sonnet | H1（有 skill） | PASS（7/7：錨點、dirty 提醒、死路、待新建標記、memory 路由 + `[[指標]]`、無 diff 快照、housekeeping） |
| 2026-07-06 | Sonnet | H2（有 skill） | PASS（5/5：verify 先行、DRIFTED 對帳不重工不回退、只做剩餘項、mv archive/ 帶日期前綴 active 清空、未 push）——實地查檔案系統證實 |
| 2026-07-06 | Sonnet | H3（有 skill） | PASS（list 實跑、零份 → 停下請使用者指路，不臆測） |
| 2026-07-16 | Sonnet | H4（有 skill，cutover 驗證輪） | PASS（跨機內容進 STATUS.md 並 commit、交接檔僅 pointer、未 push 且主動標示不可見） |
| — | — | H5 / H6 / H7 | **未實跑**（2026-08-05 新增情境；沙盒已建置並驗過語意：h6 verify 確為 FRESH+DRIFTED 混合、h7 確為 DIVERGED） |
