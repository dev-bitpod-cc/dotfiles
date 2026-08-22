# 文檔治理 rollout checklist（逐 repo 採用程序）

dotfiles pilot 遷移相的可重複執行版；量測與設計理由見
`docs/plans/2026-08-20-doc-governance-implementation-plan.md`「Phase 3 — 沿用 archive shards 並一次遷移 STATUS」，
機制本體見 `docs/document-governance.md`「Lifecycle」。一次一 repo、一條 feature branch。
批次序：只有 `STATUS.md` 的 repo → 有 archive 無 backlog 的 repo → 其餘。

## 0. 前置：trusted core

開 feature branch。`scripts/doc-governance.py` 從 dotfiles byte-for-byte 複製，與 `.doc-governance.json`
一起 commit 在 target repo——shipping 先比對 core 再執行，不一致或只有其一皆 BROKEN。symlink 與全域 skill
不算採用：接手者 clone 該 repo 就要能跑。

**同一步把 core 加進該 repo 的 lint／format 排除，理由寫在排除條目旁**：它是 byte-pinned 的 vendored
檔，照 linter 建議改一個 byte 就判 BROKEN，所以 lint 它只會產生沒人能處理的噪音。漏了這步，CI 會在
PR 階段才擋下來（canary 實測 9 條 finding 全落在該檔）。

## 1. shadow 掃描與分類

先 `audit --shadow` 取分類現況與檢索基線。classes 對著該 repo 現有 canonical paths 寫；每個 tracked
Markdown 恰好落在一個 class（`unclassified`、`multi-class`、class glob 無匹配都是 findings）。
`loaded` budget 只給真的進 context 的檔。

xref findings 先分三類：真的壞掉的指標（修）、遷移本身會清掉的（略過）、指向兄弟 repo 的（宣告進
`external_reference_targets`）。**第三類必須在遷移前宣告完**——history 是 append-only，落在 archive 裡的
跨 repo 指標事後改不動，只剩宣告一條路。

## 2. history 遷移

沿用既有 archive shard，不建平行 history root。逐條：type 由來源 section 定，`event_date` 取 title 第一個
ISO 日期並據其 `YYYY-MM` 選 shard，標 `日期來源:migration-entry`；無日期才用 cutover date 標
`migration-cutover`。每個 shard 先在 EOF 追加一次 `## 事件記錄（event-time）` 再放 records——直接 append 會
錯誤繼承最後一個 legacy H2。ID 與 heading 由 `record-path` 產生，補齊 `日期來源`／`放棄`／`重議`／`關聯`。

無日期的條目：cutover date 要**寫進 record 標題**（`- **ID** · YYYY-MM-DD 原文…`），只標
`日期來源:migration-cutover` 不夠——gate 的 event_date 是從標題讀的。

來源節裡不是 entry 的東西（blockquote、粗體群組標題）要各自指定落點：節級 prose 進新 shard 的
preamble，群組標記進各條 `關聯`。**逐塊數過再搬**，否則它們會靜默併進前一條 entry 的 body。

條目自身已宣告結案（`[x]`／刪除線）的技術債不能留在 governed backlog section——寫成 `M-*` record。

legacy entry 原地不動；其 type/file mismatch 只列資訊，新 schema 只約束 cutover 後的 record。
evidence layer 與 human guide 不搬。

## 3. STATUS cutover

同一 commit 內把 `STATUS.md` 改成 active-only schema（`status_schema` 的 required／forbidden headings），
並把指向已搬 section 的 inbound reference 改指新 record 或既有 archive section；無落點的舊節名進
`xref_section_aliases`。全 repo xref／orphan audit 過了才 commit。

修壞掉的指標前**先確認它是不是拆分殘留**——從母 repo 拆出來的指標會掉 repo 前綴，長得像壞掉的
本地指標，實際上目標還在母 repo（第一次 rollout 的 6 條裡有 5 條是這種）。目標 heading 帶前導
emoji 時，節名要連 emoji 一起抄（比對是 startswith）。target repo 若有自己的 doc-path 守門，用**它
自己的 allowlist 慣例**處理跨 repo 路徑，不要把指標改含糊來讓它過。

## 4. backlog 與 plan

backlog 條目原文不改，只補 `B-YYYYMMDD-slug`，並以 `governed_sections` 宣告哪些 section 只放未結案條目。
既有 plans 全列 legacy：`git rev-parse HEAD:<path>` 的 blob OID 寫進 `legacy_plan_blobs` 換得 metadata 與
lifecycle 豁免；OID 一變就退出豁免、必須補齊五個必要欄位。

## 5. 遷移驗證

以來源每個 top-level entry 的 normalized text hash 建 pre/post manifest，確認每條恰有一個落點；補上的 ID 與
metadata 行先從 hash 排除，否則合法補充會被誤判成內容漂移。數量不等、token 遺失或重複即停止。
manifest 放 temp。收尾要 `audit --ship` 印 `doc-governance: OK`、該 repo 測試全綠，並寫一條 `M-*` record。

## Hard rules（不得放寬）

- NEVER distill, reword, or re-date a migrated entry — migration moves bytes, not judgement.
- NEVER back-fill stable IDs into legacy entries, and NEVER re-shard them by container month.
- NEVER copy the dotfiles config verbatim; per-repo canonical paths win.
- NEVER commit a half cutover — records moved with pointers left behind is a broken repo, not progress.
- NEVER raise `governance_max_bytes` to make a rollout pass.
- NEVER commit the migration manifest.
