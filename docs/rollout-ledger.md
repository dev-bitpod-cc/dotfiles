<!--
rollout-ledger.md — 文檔治理 rollout 的 qualifying ship 計量器。判準與取代關係見
D-20260822-rollout-gate-replacement；逐 repo 採用程序見 docs/doc-governance-rollout.md。
-->

# Rollout ledger

文檔治理**放行 canary 之後其餘 repo** 所需的 steady-state 證據就在這裡累積。**沒記進來的 ship 不算數** — 這份 ledger 存在的理由，
正是原門檻「連續 10 次 ship 無人工 compaction」沒有計量器、因此不可數。

## 記法

一次 qualifying ship 一條 top-level bullet，欄位固定：

- **repo**：採用了治理核心的 repo。
- **branch**：送出這批的 feature branch。**刻意不記 merge 後的 sha** —— 條目必須寫在 commit 裡、而 commit
  必須早於 merge，rebase／squash 後的 default sha 在寫的當下不可知（第一次使用就撞到）。要回溯那顆 sha
  就去該 branch 的 PR；**不要用 `git log --merges` 數 ship**，它在 squash 流程恆為 0。
- **lifecycle 操作**：這次 ship 動到的治理面向 — 新增 record／backlog 開關／plan 狀態轉換／STATUS 更新／
  純程式碼。十顆同型的 review-fix 不構成樣本覆蓋。
- **first audit**：`audit --ship` 的**第一次**結果（rc 與 finding codes）。事後修完再跑的那次不是它。
- **人工介入**：`none`／`lifecycle`（照既有規則新增或搬動內容）／`compaction`（為了讓 audit 過而壓縮、
  裁剪或重組既有內容）。判為 `compaction` 即暫停擴張並記 root cause。
- **final audit**：收尾時的 rc。
- **surface bytes**：`report` 的 governance-surface 前後值。

## 計數狀態

- 目標：10 次 qualifying ship，且 canary repo 自己必須貢獻數次 post-cutover ship。
- 已記錄：4 次。
- ⚠️ 採用 commit `9d3e891` 之後、本 ledger 建立之前，dotfiles 已有 2 次 ship（PR 124、125）。兩者的
  first-audit 結果與人工介入分類**無法事後重建**，因此不計入 — 計數從本檔建立後的下一次 ship 起算。

## 記錄

- **dotfiles · `fix/external-reference-targets` · 2026-08-22**
  - **lifecycle 操作**：核心 correctness fix（跨 repo 指標可宣告）＋ 新增 `D-20260822-external-reference-targets`
    ＋ 治理面級距調整。非 review-fix。
  - **first audit**：`governance surface bytes: 65564>65536` —— correctness fix 讓治理面超出上限 28 bytes。
  - **人工介入**：`lifecycle`。依 `D-20260820-governance-surface-budget-policy` 升到下一個二進位級距
    （65,536 → 131,072）；**未壓縮或重組任何既有內容**。
    ⚠️ **這格是判斷邊界，第一次就出現**：若把「升級距」讀成 compaction，則本次應暫停擴張並記 root cause。
    判為 lifecycle 的理由是它動的是既有政策的釋壓閥、不是既有內容；壓縮 prose 擠出那 28 bytes 才是 compaction。
  - **final audit**：rc=0（`doc-governance: OK`）。
  - **surface bytes**：64,223 → 66,301（上限 65,536 → 131,072）。

- **krepo-mops-major-news · `chore/adopt-doc-governance` · 2026-08-22**
  - **lifecycle 操作**：**cutover ship**——採用 repo-local 治理，STATUS.md 的 46 條 entry 遷入
    history／backlog，新增 `M-20260822-doc-governance-adopted` 與 `B-20260822-claude-md-size`。
    ⚠️ **不計入 canary 的 post-cutover 樣本**：它是 cutover 本身，不是遷移後的日常 ship。
  - **first audit**：`FINDINGS × 19`（`--shadow` 基線；含 4 條跨 repo 指標與 9 條遷移工作）。
  - **人工介入**：`lifecycle`。遷移照 checklist 執行；跨 repo 指標以核心新增的
    `external_reference_targets` 宣告解決（見 `D-20260822-external-reference-targets`），
    **未壓縮或改寫任何既有內容**——46 條以 pre/post hash manifest 驗過各恰一個落點。
  - **final audit**：rc=0（`doc-governance: OK`），該 repo `uv run pytest` 677 passed 18 skipped。
  - **surface bytes**：n/a（新採用；該 repo 治理面 53,515／65,536）。
  - **送出時另需一次介入**：PR 的 required check 擋下——ruff 掃到剛複製進來的 trusted core，9 條全在該檔。
    處置是把它加進該 repo 的 `extend-exclude`（沿用其既有 vendored-file 慣例），**core 一個 byte 沒改**。
    仍判 `lifecycle`：它是採用一個新 repo 的前置設定，不是為了讓 audit 過而動既有內容。
    判準與 checklist 回填見 `D-20260822-vendored-core-lint-exclusion`。

- **dotfiles · `perf/retrieval-diversity-and-recall` · 2026-08-22**
  - **lifecycle 操作**：核心 ranking 變更（per-file cap）＋ 新增 `M-20260822-retrieval-source-diversity`、
    `X-20260822-doc-h1-token-signal`＋ 關閉 `B-20260821-debt-28`、改寫 `B-20260821-debt-27`。
  - **first audit**：rc=0。
  - **人工介入**：`none`。
  - **final audit**：rc=0（`doc-governance: OK`），`tests/run.sh` PASS=1098 FAIL=0。
  - **surface bytes**：68,150 → 68,941（上限 131,072，未動）。
  - ⚠️ **這次 ship 讓所有採用者的 core 失去同步**：canary 的 `ship-state.sh` 隨即印
    `doc-governance: BROKEN（trusted core mismatch）`。**核心一改，每個採用 repo 都欠一次 sync ship**
    ——這是 rollout 的常態成本，不是異常，見下一筆。

- **krepo-mops-major-news · `chore/sync-doc-governance-core` · 2026-08-22**
  - **lifecycle 操作**：**core sync ship**——把 trusted core 同步到上一筆的版本。無文檔變更。
    ✅ **這是 canary 的第一筆 post-cutover ship**，計入放行其餘 repo 所需的樣本。
  - **first audit**：`BROKEN（trusted core mismatch）`——由上一筆造成，非該 repo 的問題。
  - **人工介入**：`lifecycle`（照 `ship-state.sh` 訊息重新同步，一個 byte 都沒有自行修改）。
  - **final audit**：rc=0（`doc-governance: OK`）。
  - **surface bytes**：53,515 → 54,306（上限 65,536，未動）。
