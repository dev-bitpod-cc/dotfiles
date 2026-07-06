# Handoff — Evals

> 開發/迭代用的評測集，**不從 SKILL.md body 連結**。
> 沙盒建置：`claude/evals/setup-sandboxes.sh`（h1 / h2 情境；h3 只需空 handoffs 目錄）；手動執行見 `claude/evals/README.md`。
> 沙盒版目錄對應：prompt 中明給「handoff 目錄用 <sandbox>/handoffs、memory 目錄用 <sandbox>/memory」，腳本用真實路徑。

---

## A. Triggering tests

| # | 使用者輸入 | 期望 |
|---|-----------|------|
| T1 | `幫我寫交接檔，我等下要 /clear` | ✅ 觸發（write mode） |
| T2 | `接續上次的工作` / `接續交接 <slug>` | ✅ 觸發（resume mode） |
| T3 | `幫我記住這個偏好` | ❌ 不觸發（→ memory） |
| T4 | `可以 quit 了嗎，收尾一下` | ❌ 不觸發（→ /ready4quit） |
| T5 | `幫我 ship 這次變更` | ❌ 不觸發（→ /uap） |

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
    "dirty>0 → 報告提醒未 commit 內容不受錨點保護、建議先 commit（ship 指 /uap），不代為 commit",
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
    "完成對帳後把交接檔 mv 到 archive/（帶日期前綴）——不留在 active 目錄、不就地標 done",
    "不 push（CLAUDE.md 既有規則）"
  ]
}
```

> 2026-07-06 baseline（Sonnet，無 skill）：對帳部分意外地好——自發比對錨點 sha、辨識 retry 已完成、沿用 httpx 不回退。
> 但：**消費後就地更新交接檔**（加 `status: done` / `closed` 欄位留在 active 目錄，理由逐字：「沒有刪除，而是就地更新……方便後續追溯這個決策為何變了」）——失效檔案永久堆積，正是要杜絕的。且 verify 是自發行為、無 SOP 保證可重複。
> → Red Flags 已針對「就地標 done for traceability」逐字反制（traceability lives in archive/）。

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

---

## 執行紀錄

| 日期 | 模型 | 情境 | 結果 |
|------|------|------|------|
| 2026-07-06 | Sonnet | H1 baseline（無 skill） | RED（無錨點、貼 diff 快照、durable 未路由 memory、無生命週期） |
| 2026-07-06 | Sonnet | H2 baseline（無 skill） | RED（消費後就地標 done 留在 active 目錄；verify 為自發、不可重複） |
| 2026-07-06 | Sonnet | H1（有 skill） | PASS（7/7：錨點、dirty 提醒、死路、待新建標記、memory 路由 + `[[指標]]`、無 diff 快照、housekeeping） |
| 2026-07-06 | Sonnet | H2（有 skill） | PASS（5/5：verify 先行、DRIFTED 對帳不重工不回退、只做剩餘項、mv archive/ 帶日期前綴 active 清空、未 push）——實地查檔案系統證實 |
| 2026-07-06 | Sonnet | H3（有 skill） | PASS（list 實跑、零份 → 停下請使用者指路，不臆測） |
