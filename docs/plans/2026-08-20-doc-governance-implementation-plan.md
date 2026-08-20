# 文檔治理實作計劃

- 日期：2026-08-20
- 狀態：implemented
- 工作項：doc-governance
- 種類：implementation
- 需求來源：`docs/plans/2026-08-20-doc-governance-goals.md`
- 規劃限制：本計劃未沿用 `docs/plans/` 下其他舊計劃；舊計劃只作凍結紀錄，不進搜尋候選或 xref source；本次明確指定的 goals 文件除外

## 1. 要交付的結果

這次不再擴張 `STATUS.md` 的壓縮規則，也不把同一套 bytes 門檻套到全部 Markdown。要交付的是一套
repo-resident 的文檔路由與生命週期機制：

1. `STATUS.md` 只保存**現在仍有效的工作狀態**，完成項不再累積於其中。
2. 決策、死路、里程碑寫進按月自動分片的 canonical history；分片由日期決定，不再等撞門檻後人工挑內容搬家。
3. 所有 canonical 文檔以同一支 repo 內腳本做分類、section-level 搜尋、交叉引用與生命週期檢查；不依賴本機索引、Claude 專用能力或 Codex 專用能力。
4. always-on 與 skill body 這類會真的進 context 的內容才有硬預算；archive、plan、reference、eval 等按需內容不設總量上限，改守「可定位、可檢索、生命週期明確」。
5. 同一工作項只保留一份可編輯計劃；以 git history 保存修訂，不再用 `v2`、`v3` 等完整複本表達版本。
6. dotfiles 先成為完整 pilot；只有通過 deterministic tests 與 Claude Code／Codex 行為 eval 後，才分批帶到其他 repo。

## 2. 已選定的架構

### 2.1 唯一解析核心

新增 `scripts/doc-governance.py`，只用 Python standard library，所有功能從 repo 內 tracked files 即時計算，
不讀 home directory、不讀 machine-local cache，也不需要網路。

腳本包含四個 subcommand：

| 指令 | 用途 | stdout／exit contract |
|---|---|---|
| `find <query>` | 將 Markdown 以 logical entry 為單位搜尋 | 最多 5 筆定位欄位＋短摘錄；有結果 0、無結果 1、執行錯誤 2 |
| `audit` | 分類、結構、plan lifecycle、history schema、xref、orphan 與預算檢查 | stdout 只放 blocking findings；乾淨 0、有 finding 1、scanner 錯誤 2 |
| `report` | 印全家族 bytes、檔數、loaded surface、governance surface 與各類 top files | 成功 0、執行錯誤 2；不因體積本身回 1 |
| `record-path` | 依 type/date/slug 算出 history shard 與穩定 ID | 只印建議 path、ID 與 heading，不修改檔案 |

所有 subcommand 都接受 `--root <repo>`，省略時以 cwd 的 git toplevel 為 root。`audit` 另有三個互斥 mode：

- `audit --shadow`：照常印 `doc-flag:`，content finding 仍回 0；scanner/config error 保持 exit 2。
- `audit --ship`：首行固定為 `doc-governance: OK|FINDINGS|BROKEN`，後續 finding 固定以 `doc-flag:` 開頭；
  OK=0、FINDINGS=1、BROKEN=2，供 `ship-state.sh` 不重新解讀文字。
- `audit --check xref`：只跑 forward xref 與 config 宣告 `requires_inbound` 的 reverse checks，保留
  `tests/xref-gate.py` compatibility contract。

`find` 的文件單位不是整檔：一般文檔用 H1 前言／H2 section，config 標為 `top_level_bullet` 的既有
archive 則以每個頂層 bullet 及其續行為一個 logical entry。這讓現有 68KB 月檔可以回傳一條決策，而不是
把整檔送進 context。正規化採 NFKC＋casefold；英文／數字用 word token，CJK 用相鄰雙字 token。
計分順序固定為：stable ID exact match、heading/title exact phrase、heading/title token、
metadata alias/tag、body token。平手以 tracked path、line number 排序。這使結果可由 fixture 固定，
不需要 embedding、LLM 或不可攜的全文索引。

每筆結果首行固定為
`path:line type=<type> event_date=<date|unknown> section=<heading|file-preamble> — <entry-title>`，下一行才是
bounded excerpt。parser 在第一個 H2 之前仍建立 logical entries，`section` 明寫 `file-preamble`，不得留空或
拿 H1 冒充 H2；有 H2 時回實際 H2 原文。這個 contract 讓使用者不開整檔也能定位，並讓 fixture 可直接斷言
「無 H2 祖先」不是解析失敗。

### 2.2 Repo 內設定

新增 root `.doc-governance.json`，schema version 固定為 1。它只描述治理 metadata，不複製文檔內容，
因此不是第二份內容權威。必要欄位：

```json
{
  "schema": 1,
  "history_paths": {
    "decision": "docs/archive/decisions-{YYYY-MM}.md",
    "dead_end": "docs/archive/dead-ends-{YYYY-MM}.md",
    "milestone": "docs/archive/milestones-{YYYY-MM}.md"
  },
  "plan_dir": "docs/plans",
  "legacy_plan_blobs": {},
  "classes": [],
  "loaded_budgets": {},
  "governance_surface": []
}
```

`classes` 的每一項含 `name`、`mode`、path globs 與可選的 `unit`（預設 `h2`；既有月歸檔用
`top_level_bullet`）。`mode` 只有：

- `loaded`：每次 session 或每次 skill invoke 進 context；有 bytes/lines 預算。
- `active`：尚未結案的 canonical state；守 schema 與出口，不守總 bytes。
- `routed`：spec、reference、eval、plan 等按需 canonical content；守檢索與生命週期，不守總 bytes。
- `history`：只增的 canonical history；守穩定 ID、logical-entry schema 與 deterministic sharding。
- `derived`：可重建產物；每項必須宣告 rebuild command，且 audit 驗 drift。
- `governance`：本機制的 script、policy 與 integration surface；納入自身成本報表。

class 可另設 `requires_inbound: true`。只有 conclusion/evidence 生命週期綁在一起的 legacy evidence layer
使用它；history 與 archive 由搜尋器直接路由，不要求人工維護 inbound pointer。所有 tracked Markdown
必須恰好命中一個 class；零命中或多重命中都 blocking。非 Markdown 的治理腳本與設定由
`governance_surface` 明列並計量。

`legacy_plan_blobs` 的未變動檔只作凍結紀錄，預設不進 `find` 或 xref source；只有
`searchable_legacy_plans` 明列的當前需求來源可進搜尋，本 pilot 唯一例外是 goals 文件。

class 是檔案層分類，不等於 entry type。對 `top_level_bullet` 容器，parser 另輸出 `entry_shape`
（`dated`／`struck`／`checkbox`／`undated`）、最近的 H2 或 `file-preamble`、以及 entry-level type。
有 `D/X/M-*` stable ID 的新 record 以 prefix 決定 type；沒有 stable ID 的 legacy entry 只做保守推斷，
可標成 `legacy-decision`、`legacy-closed-debt`、`legacy-dead-end` 或 `legacy-unknown`。檔名只決定新 record 的
合法落點，不作 legacy type 的唯一證據。

### 2.3 Canonical history

不新增平行的 `docs/history/`。沿用已運行兩個月的 canonical shards：

- decision → `docs/archive/decisions-YYYY-MM.md`
- milestone → `docs/archive/milestones-YYYY-MM.md`
- dead end → `docs/archive/dead-ends-YYYY-MM.md`（第一個尚未存在的類型）

目前 `decisions-2026-07.md` 為 8,867 bytes，`decisions-2026-08.md` 為 68,354 bytes；後者有 28 次 commit、
numstat deletion 為 0，而 STATUS 只有兩行提到該檔。這證明「按月分片」已經完成，也證明分片本身沒有建立
可檢索性。新機制增加的是 logical-entry search、穩定 ID、事件當下直寫與 retrieval oracle，不把既有物理形狀
包裝成新交付。

現況可重現口徑是 117 個頂層 bullets：109 個 date-shaped records、2 個 struck records、5 個 checkbox
records、1 個 undated record；先前的 112 無法由自然 pattern 重現，不作 oracle。檔內另有 6 個 H2，其中
37 個 dated records（32%）位於第一個 H2 前、沒有 H2 祖先；「已結案技術債」H2 內有 34 個 dated records
與 5 個 checkbox records，另有一個空的「死路」H2。也就是 `decisions-2026-08.md` 是 legacy mixed
container，檔名不等於內容 type。

Phase 0 先把 logical-entry 計數契約固定：`report` 分開印 `dated_records`、`struck_records`、
`checkbox_records`、`undated_records`、`h2_sections`、`empty_h2_sections`、`file_preamble_entries` 與
`legacy_type_file_mismatches`。legacy mismatch 只報資訊；cutover 後帶 stable ID 的 record 若 prefix 對不到
檔案 family 則 blocking。測試不把含混的「條目數」硬編成單一數字，也不假設 H2 一定有 entry。

日期欄位同樣分流，不能拿 H2 日期或檔名月份互相代填：

- legacy entry（無 stable ID）：標 `shard_semantics=archive_month`；`container_month` 取檔名，`batch_date`
  只取最近 H2 的歸檔批次日期，`event_date` 只取 entry title 自己的日期，取不到就保持 `unknown`。
- cutover 後 record（有 stable ID）：標 `shard_semantics=event_month`；ID 日期、title 日期與
  `event_date` 必須一致，且 `event_date` 的 `YYYY-MM` 必須等於 type 所映射的 shard 檔名月份。
- 同一個月檔可同時含原地保留的 archive-month legacy entries 與新寫入的 event-month records；stable ID
  是語意切點。既有 entry 不重分片、不改標題、不補 ID，避免把歸檔動作日期誤當事件日期。

新記錄繼續用頂層 bullet，與既有 archive 相容：

```markdown
## 事件記錄（event-time）

- **D-20260820-short-slug · 2026-08-20 決策標題**:結論與理由。
  - 日期來源:direct
  - 放棄:<替代方案與原因>
  - 重議:<條件;無則寫 none>
  - 關聯:<工作項、commit、PR 或其他 record ID;無則寫 none>
```

ID prefix 固定為 `D`（decision）、`X`（dead end）、`M`（milestone）。同 shard 內 ID 必須唯一；
`日期來源` 只有 `direct`、`migration-entry`、`migration-cutover`。每個新 shard 建立 H1 後固定建立上面的
event-time H2；對既有 shard 則在檔尾追加一次該 H2，之後的新 records 全部放在其下，避免直接 append 時錯誤
繼承最後一個 legacy H2。`record-path` 依 type/date 決定既有 archive path、stable ID 與固定 section，只計算
位置與模板，實際內容仍由 agent 使用正常檔案編輯工具寫入，避免腳本代替人做語意判斷。

history record commit 後保持 append-only。被推翻時不修改舊 record；新 record 的 `關聯` 寫
`supersedes:<old-id>`，搜尋器與 audit 從反向邊推導舊 record 已失效。歷史主題即使不再適用也不刪，因為它的
角色就是保存當時決策；只有尚未 commit 的誤寫可原地修正。

### 2.4 Active state 與 backlog

`STATUS.md` 新模板只保留：

- 專案定位
- `進行中`：每項仍有 Context / Goal / AC / Constraints / 進度 / 下一步／相關 record IDs
- `暫停中`：暫停理由與重啟條件
- `歷史入口`：固定指向 `docs/archive/` 與 `scripts/doc-governance.py find`
- `待辦入口`：有 `docs/backlog.md` 時指向它，沒有時明示未分家
- `移交準備度`

完成工作時，spec 從 `進行中` 移除，成果寫一條 `M-*` record；決策與死路在發生當下直接寫 `D-*`／`X-*`
record。因歷史不再留在 STATUS，STATUS 的長期下限只由仍在進行或暫停的工作決定，取消現有 300 行／24KB
週期性 compaction gate。

`docs/backlog.md` 保持未結案 canonical state，但每項新增 stable ID `B-YYYYMMDD-slug`。完成時刪除 backlog
條目並寫 `M-*`；放棄時刪除 backlog 條目並寫 `D-*`。不對 backlog 設 bytes 上限。

### 2.5 Plan lifecycle

每個 work item 只能有一份 plan：`docs/plans/YYYY-MM-DD-<work-item>.md`。檔首必要欄位為日期、狀態、
工作項、種類與需求來源。狀態只有：

- `draft`：可就地修訂。
- `approved`：可就地補實作查證與 reviewer 要求；仍是同一份計劃。
- `in-progress`：實作中只補實際偏差與驗證結果，不另開版本檔。
- `implemented`：凍結。
- `superseded`：凍結，並必須指向 replacement plan。

git history 是 draft／review 修訂史。只有工作目標真的改變、不能再視為同一 work item 時才新增另一份 plan；
舊 plan 標 `superseded`。`audit` 對同一 work item 出現兩份非終態 plan 判 blocking，並對 `-v[0-9]+`、
`-final`、`-revised` 這類新檔名判 blocking。既有 `docs/plans/` 全部列為 legacy，不要求回填 metadata，
也不改寫內容；`.doc-governance.json` 以 `path → git blob OID` 明列 cutover 當下的 legacy plans。blob 未變時
豁免 metadata/lifecycle，任何舊檔一被編輯、OID 改變就退出豁免並必須補齊新 schema。新檔與 untracked plan
從來不在 allowlist，不能假冒 legacy。

### 2.6 可觀察的「找得到」

完成定義不是「檔案還在」，而是同時滿足三層：

1. **全量結構檢查**：每個 canonical Markdown 的標題查詢都必須在 `find` top 1 找回自己；每個新 H2／
   top-level record 的 stable ID 都必須 exact hit。
2. **語意代理 eval**：`tests/fixtures/doc-governance/retrieval.tsv` 至少各含 decision、dead end、milestone、
   backlog、plan、policy、skill、reference、eval、archive 一題；預期 path＋heading 必須在 top 5。
3. **雙 agent 行為 eval**：Claude Code 與 Codex 各跑三個 clean-room 情境，僅給 repo 與自然語言問題；
   必須自行發現 repo 內搜尋入口、引用正確 canonical path/entry，且不得整批讀 archive。

`find` 預設最多 5 筆、每筆摘錄最多 240 bytes、總 stdout 上限 8 KiB。機械掃描可讀全部 tracked docs，
但只有有限結果進 agent context，這就是 token 成本與存量解耦的邊界。

## 3. 逐階段實作

### Phase 0 — 先立 RED oracle

在任何 skill 或治理行為改動前完成：

1. 依 repo 規定，實作者先完整使用 system `$skill-creator`，再讀 `claude/skill-building-guide.md`；因本計劃
   會修改 `project` 與 `deep-plan` skill，behavior eval 是 oracle。
2. 新增 `tests/test_doc_governance.py` 與 `tests/fixtures/doc-governance/`：
   - fixture A：只有 `STATUS.md`，沒有 backlog/dead-ends/archive。
   - fixture B：完整 family，含合法與孤兒 section。
   - fixture C：同 work item 的兩份 active plans。
   - fixture D：中文／英文混合 heading、nested fence、HTML comment、相對引用與 `~/` mapping。
   - fixture E：unclassified、multi-class、invalid JSON、讀取失敗。
3. 將現有 `tests/run.sh` 第 1d 節的 xref RED/GREEN cases 移入 Python test module；搬完前兩邊並跑，
   確認新 parser 對現有契約完全等價，再刪舊 fixture block。
4. 先用現行 repo 跑五條 retrieval baseline；Claude Code 與 Codex 都只收到自然語言問題，不給檔名／路徑：
   - 「為什麼 remote branch 清理不能直接用 `push --delete`？」預期命中
     `docs/archive/decisions-2026-08.md` 中 2026-08-07 expected-SHA 決策。
   - 「dossier 的量體訊號為什麼從 STATUS 總量擴到 always-on？」預期同一次 top-5 同時命中
     `decisions-2026-07.md` 的量測下沉決策與 `decisions-2026-08.md` 的 always-on 量體決策。
   - 「大型輸入做存在性檢查為什麼不能使用 `printf | grep -q`？」預期命中
     `docs/archive/decisions-2026-07.md` 的 herestring 決策。
   - 「為什麼 `git add -A` 的唯一例外是 deep-review WIP snapshot？」預期命中
     `docs/archive/decisions-2026-08.md` 第一個 H2 之前的 2026-08-05 entry；結果的 `section` 必須是
     `file-preamble`，不能空白。
   - 「為什麼『進行中含 ✅』只檢查 list item、不檢查表格或續行？」預期命中
     `docs/archive/decisions-2026-08.md` 的「已結案技術債（2026-08-10 歸檔）」entry；這題刻意測
     query 沒有檔名線索、且內容 type 與 `decisions-*` 檔名不一致。
5. 每題記錄正確 path/entry 命中與否、agent 開過的檔案、送入 context 的 bytes、搜尋步數；這是舊機制 baseline。
   無論現況命中或失敗都保留結果，不以「新指令還不存在」代替現況量測。
6. 把同五題加入 `tests/fixtures/doc-governance/retrieval.tsv`，再用尚不存在的 `find` 跑出 deterministic RED；
   另補 decision、dead end、milestone、backlog、plan、policy、skill、reference、eval、archive 各類 coverage。
7. 在 `claude/evals/doc-governance-evals.md` 寫三組 behavior baseline：
   - 查一條只在 archive、STATUS 沒有 entry pointer 的舊決策理由。
   - `/project log` 收尾時有 decision、dead end、milestone 各一條。
   - `/deep-plan` reviewer 要求修訂同一 work item 的 plan。
8. Claude Code 與 Codex 各跑 baseline 並保存評分，只把已觀察到的失敗寫進 skill 指令，不為假想情境加規則。

Phase 0 驗收：新 unit/retrieval tests 因缺實作而 RED；既有 `./tests/run.sh` 仍維持原基線，不得先改 oracle
讓現行輸出看似通過。五條真實查詢另形成 sizing gate：若現行兩個 agent 已全數命中，新 scorer 仍必須縮短
搜尋步數或減少進 context 的 bytes，否則只保留 bounded logical-entry extraction，不增加沒有行為收益的 ranking
heuristic；若任一現況查詢失敗，新 `find` 必須將五題全部提升到 top-5 才能繼續 Phase 2。

### Phase 1 — 實作 scanner、分類與搜尋

新增／修改：

- 新增 `.doc-governance.json`：列出 dotfiles 目前全部文檔 class；old plans 歸 `legacy-plan` routed class。
  `legacy_plan_blobs` 只以 `git rev-parse HEAD:<path>` 取得 blob OID，不讀舊計劃內容。
- 新增 `scripts/doc-governance.py`：完成 config validation、tracked-file discovery、Markdown parser、logical-entry
  index、legacy entry shape/type/date provenance、`find`、`report` 與前三項 audit（classification、loaded budget、
  governance surface）。第一個 H2 前的 bullets 必須歸入 `file-preamble`；空 H2 只進結構報表，不生成假 entry。
- 新增 `docs/document-governance.md`：只寫資料模型、CLI contract、生命週期與 rollout；演算法細節留在 script
  docstring/tests，不在文檔再複製。
- 修改 `tests/run.sh`：在 shellcheck/bash gate 後呼叫 `python3 tests/test_doc_governance.py`，保留 exit code。
- 修改 `docs/testing-contract.md`：新增對應節號、RED/GREEN fixture 及刻意 false negatives。

loaded budget 在 dotfiles pilot 固定為：

- root `AGENTS.md`：8 KiB。
- root `CLAUDE.md`：12 KiB。
- `claude/CLAUDE.md`：20 KiB。
- 任一 `SKILL.md`：500 行且 24 KiB；兩者任一超過即 blocking。

Phase 1 會先讓目前超標檔案以具名 finding 顯示，但不立刻接進 ship verdict；直到 Phase 4 完成內容搬移前，
`audit --shadow` 只報表不回 1。Phase 4 一次切成 blocking，不留下永久 allowlist。

### Phase 2 — 合併 xref 與 ship 的重複解析

1. 將 `tests/xref-gate.py` 的 fence/comment/path/heading/inbound graph 邏輯移入 `scripts/doc-governance.py`。
2. `tests/xref-gate.py` 暫時保留為 thin compatibility wrapper，轉呼叫 `doc-governance.py audit --check xref`，
   保留「stdout 只放 findings；scanner error exit 2」契約。
3. `ship-state.sh` 新增 `detect_doc_governance`：
   - target repo 有 `.doc-governance.json` 與 `scripts/doc-governance.py` 時，執行 repo-local `audit --ship`。
   - 未採用者繼續走現有 `detect_dossier`／`detect_backlog`／`detect_always_on`，輸出完全不變。
   - repo 宣告採用但腳本或 config 缺一時輸出 `doc-governance: BROKEN` 並令 ship verdict STOP；不得靜默退回 legacy。
4. dotfiles 採新路徑後，從 `ship-state.sh` 刪除只服務本 repo 的 archive orphan/xref 重複掃描；legacy dossier
   detector 暫留給未採用 repo。
5. 把 `tests/run.sh` 現有 dossier、backlog、always-on、archive orphan fixtures 分成：legacy contract 與 adopted
   contract。兩組都要守，避免 rollout 期間未採用 repo 被強迫回填。

Phase 2 驗收：現有 xref 全部 case 等價；adopted repo 只有一套 Markdown parser；無 config repo 的輸出與改動前一致；
config broken 必須 fail closed。

### Phase 3 — 沿用 archive shards 並一次遷移 STATUS

1. 不建立新 history root。遷移器先為 `STATUS.md` 每個待搬 entry 建 manifest：type 由來源 section 決定，
   `event_date` 取 entry title 第一個 ISO 日期，依其 `YYYY-MM` 選 type 對應 shard，並標
   `日期來源:migration-entry`；title 無日期時才使用 cutover date `2026-08-20`，並標
   `日期來源:migration-cutover`。目前清單全落 2026-08，
   因此「關鍵決策」追加到 `docs/archive/decisions-2026-08.md`，「已完成」追加到
   `docs/archive/milestones-2026-08.md`。兩檔先在 EOF 各追加一次 `## 事件記錄（event-time）`，再放 records；
   不蒸餾、不改寫理由。
2. 新增 `docs/archive/dead-ends-2026-08.md`，把 STATUS 的死路結論依同一 event-date 規則附 stable ID 後搬入；已有
   `docs/dead-ends.md` evidence pointer 的條目保留 pointer，不複製 evidence body；新檔以 H1 加固定 event-time H2
   開始。
3. 既有 07／08 decision、milestone archive 原文不轉格式、不補 ID；parser 以 legacy top-level bullet
   logical entry 納入檢索，新 schema 只約束 cutover 後追加的記錄。legacy 的檔名/type mismatch、H2 batch date
   與 event date 不同只列資訊；新 stable-ID record 的 type/file 或 event-month/file mismatch 才 blocking。
4. 同一次 commit 將 `STATUS.md` 改成 active-only schema；所有原本指向三個舊 section 的 inbound references
   改指新 record 或既有 archive section。跑 full-repo xref/orphan audit，禁止只搬一側。
5. `docs/dead-ends.md` 與 `claude/known-hazards.md` 不搬、不重寫；前者保留 legacy evidence layer，後者保留
   檔級入口，兩者都納入 `find`。
6. `docs/backlog.md` 的現有條目原文不改，只機械補 stable ID；更新 template 後的新條目一開始就帶 ID。
7. 修改 `claude/templates/STATUS-template.md`、`claude/templates/BACKLOG-template.md`，並更新所有模板
   characterization tests。

遷移驗證另做一個 pre/post manifest：以原 section 每個 top-level entry 的 normalized text hash 為鍵，確認每條
在 type 對應的 archive shard 恰有一個 canonical 落點；補 stable ID 與 metadata 行先從 hash 中排除，避免合法
schema 補充被誤判內容漂移。manifest 放 temp directory，不 commit；數量不等、本文 token 遺失或重複都停止。

### Phase 4 — 更新權威規範與 runtime surfaces

修改：

- `AGENTS.md`：Documentation authority 改為 active state=`STATUS.md`、history=`docs/archive/`、
  plan=one mutable file per work item；加入一行雙 agent 都看得到的 `doc-find` 路由。
- `CLAUDE.md`：加入與 AGENTS 相同的短路由；把長期專案事實移到 `docs/repo-guide.md` 或既有按需文檔，
  不複製規則。
- 新增 `docs/repo-guide.md`：承接 root `CLAUDE.md` 中仍有用但不必每 session 載入的工具、平台、SSH 與運維細節；
  root `CLAUDE.md` 只留下 repo commands、硬規則與到本檔的路由。
- `claude/CLAUDE.md`：將 dated incidents 搬到 `claude/known-hazards.md`、skill authoring rationale 搬到既有
  guide，只保留跨 repo standing contract 與入口。
- `claude/skills/project/references/dossier.md`：重寫角色、記錄時機、record schema、supersede/remove 規則與 legacy fallback。
- `docs/project-spec.md`：F4/F7/F8 改成 active STATUS＋history record 的完成條件。
- `claude/skills/project/SKILL.md`：
  - spec 開工先用 `find` 查相關 decision/dead end，命中 ID 寫入 active item。
  - log Step 2 把 decision/dead end/milestone 寫入當月 shard，再移除 completed active item。
  - adopted repo 以 `audit --ship` 為唯一文檔 verdict；legacy repo 維持既有流程。
- `claude/skills/deep-plan/SKILL.md`：Step 0 建檔時寫 lifecycle fields；Step 4 永遠修改同一 plan；完成實作由
  `/project log` 將狀態改 `implemented`；禁止為 review revision 新建版本檔。
- `claude/skills/deep-review/SKILL.md`：不改 workflow 行為，只把 reviewer 可按需讀的說明與已由 tests 固定的
  rationale 移到新的一層 reference；Critical guardrails、執行步驟與 STOP 判準留在 body。新 reference 直接由
  SKILL.md 連出，超過 100 行時在檔首加目錄。
- `claude/evals/contract-evals.md` 與 `claude/skills/deep-plan/evals.md`：只修被新權威取代的 oracle/path，
  不刪歷史結果；新行為 oracle 以 Phase 0 的 eval 為準。

always-on 的共用路由以 marker block 管理，擴充 `tests/kernel-gate.py` 驗 AGENTS/CLAUDE 兩份逐字一致，避免
雙 agent 規則漂移。完成內容搬移後關閉 `--shadow`，loaded budget 與 plan lifecycle 正式 blocking。

`ship-state.sh` 讀 `audit --ship` 的 exit code而不是 grep 文案：1 時設定 `doc_stop=1` 並繼續收集其他摘要訊號，
2 時設定 `doc_stop=1` 且標 BROKEN；最終 verdict 統一由既有 verdict 組裝點讓 `doc_stop` 優先成為 STOP，
避免前段印 STOP、後段又印可送出的 verdict。

### Phase 5 — 治理面自我收斂

1. `report` 將下列列為 governance surface：`.doc-governance.json`、`scripts/doc-governance.py`、
   `docs/document-governance.md`、`ship-state.sh` 的 integration block、`tests/xref-gate.py` wrapper。
2. 完成後 governance surface 必須不高於需求書量到的 49,675 bytes；若超過，先刪已被新核心取代的 legacy
   parsing/prose，不得提高預算過關。
3. `tests/xref-gate.py` wrapper 只保留一個 release；12 repo 全採用後另開工作項刪除。legacy dossier fallback
   同理，這次不提早移除。
4. `report` 每次都印治理面 bytes 與 canonical Markdown bytes 的比例，但比例只是資訊；唯一 blocking 是
   49,675-byte 初始上限與重複 parser 數必須為 1。

### Phase 6 — 雙 agent 驗證與 rollout

1. 在乾淨 clone 跑 `./tests/run.sh`，以 exit code 判定。
2. 執行 Phase 0 的三個 clean-room eval：Claude Code 與 Codex 各三次，共六次；每次都是 fresh context。
3. 通過條件：六次都找到 repo-local 入口、六次都引用正確 canonical entry、零次全量讀 archive；
   deterministic retrieval corpus 100% top-5，title self-query 100% top-1。
4. dotfiles pilot 連續 10 次 `/project log` 不出現人工 compaction，且新增 decision/dead end/milestone 都落到
   正確月份 shard；未達成前不推到機隊。
5. rollout 分三批，每個 repo 各自 feature branch／PR：
   - 一個只有 `STATUS.md`、無其他 family 的 repo。
   - 一個有 archive 但無 backlog/dead-ends 的 repo。
   - 其餘 repo，保留各自現有 canonical paths，以 `.doc-governance.json` adapter 分類，不強迫補齊 family。
6. 每批先跑 `audit --shadow` 取得分類與 retrieval corpus，再做 active/history migration；不得用 dotfiles config
   直接覆蓋 per-repo 慣例。
7. 其他 repo 的 script/config 必須 commit 在該 repo，接手者只 clone 該 repo 就能執行；不得只靠 dotfiles
   symlink 或全域 skill。

## 4. 精確檔案清單

### 新增

- `.doc-governance.json`
- `scripts/doc-governance.py`
- `docs/document-governance.md`
- `docs/repo-guide.md`
- `docs/archive/dead-ends-2026-08.md`
- `tests/test_doc_governance.py`
- `tests/fixtures/doc-governance/` 下的 synthetic repos 與 `retrieval.tsv`
- `claude/evals/doc-governance-evals.md`
- `claude/skills/deep-review/references/modes-and-scope.md`
- `claude/skills/project/references/log-workflow.md`

### 修改

- `AGENTS.md`
- `CLAUDE.md`
- `claude/CLAUDE.md`
- `STATUS.md`
- `docs/backlog.md`
- `docs/archive/decisions-2026-08.md`
- `docs/archive/milestones-2026-08.md`
- `docs/project-spec.md`
- `docs/testing-contract.md`
- `claude/templates/STATUS-template.md`
- `claude/templates/BACKLOG-template.md`
- `claude/skills/project/SKILL.md`
- `claude/skills/project/references/dossier.md`
- `claude/skills/project/scripts/ship-state.sh`
- `claude/skills/deep-plan/SKILL.md`
- `claude/skills/deep-review/SKILL.md`
- `claude/skills/deep-review/evals.md`
- `claude/evals/contract-evals.md`
- `docs/dead-ends.md`
- `tests/run.sh`
- `tests/xref-gate.py`
- `tests/kernel-gate.py`

### 刻意不改

- 需求來源以外的既有 `docs/plans/*.md` 內容
- `docs/archive/decisions-2026-07.md`
- `docs/archive/milestones-2026-07.md`
- `docs/dead-ends.md`
- 其他 repo；rollout 前另取得各 repo 的修改與 push 授權

## 5. 測試矩陣

| 面向 | 必測案例 |
|---|---|
| Config | invalid schema、未知 mode、零命中、多重命中、glob 無匹配、路徑逃出 root |
| Markdown parser | nested fence、不同 fence 字元、HTML comment、H1 前言、H2/H3 邊界、第一個 H2 前的 bullet→`file-preamble`、空 H2、top-level bullet＋續行邊界、UTF-8 decode error |
| Search | stable ID、中文雙字、英文 casefold、heading/body 權重、deterministic tie、無 H2 時仍輸出完整定位欄位、limit 與 8 KiB 上限 |
| Xref | 現有第 1d 節全部 RED/GREEN、相對路徑、tilde mapping、section/body fallback、full-scan orphan |
| History | type→月份 path、legacy mixed container、四種 entry shape、H2 batch date 不冒充 event date、archive-month legacy 與 event-month new record、三種 prefix、duplicate ID、supersedes 指到不存在 ID、legacy mismatch 僅資訊、新 record type/month mismatch blocking |
| Plans | 同 work item 雙 active、合法 in-place revision、closed plan mutation、replacement pointer、legacy exemption |
| STATUS/backlog | active-only schema、done item 殘留、paused 缺 restart condition、backlog duplicate ID、完成後有 milestone record |
| Ship integration | adopted、legacy、宣告採用但缺 script/config、audit finding、audit scanner error、無 remote early return |
| Self-governance | loaded budget、skill 500 lines/24 KiB、route marker drift、governance surface >49,675 bytes |
| Portability | temp HOME、無網路、repo 路徑含空白、macOS/Linux Python、從 repo 外 cwd 執行 |

## 6. 完成判定

全部成立才算完成：

- `./tests/run.sh` exit 0，且新 Python suite 沒有 skip 掉核心案例。
- `scripts/doc-governance.py audit` exit 0；`report` 顯示 tracked Markdown 100% 恰好分類。
- `STATUS.md` 不再保存已完成歷史，原決策／死路／里程碑的 pre/post hash manifest 數量完全一致。
- 現有 07／08 archive、dead-end evidence 與 cutover 後的新 records 都能由 `find` 找到；forward xref 全有效，
  且只有 config 宣告 `requires_inbound` 的 evidence layer 接受 reverse orphan 判定。archive 不以人工 pointer
  當可檢索性代理。
- deterministic corpus 100% top-5；所有 canonical title self-query 100% top-1；無 H2 命中回 `file-preamble`，
  不留空 section。
- 五條 archive baseline 的新結果不得比現況增加搜尋步數或 context bytes；現況有 miss 時新結果必須全數命中，
  現況全中時則至少縮減其中一個成本軸，否則不宣稱 ranking heuristic 有收益。
- Claude Code／Codex clean-room eval 6/6 通過。
- 三份 always-on 與所有 `SKILL.md` 通過 loaded budget，沒有永久 exemption。
- governance surface ≤49,675 bytes，Markdown parser 只有一份實作。
- 同一 work item 無第二份 active plan；本計劃在實作完成時就地標為 `implemented`，不另建新版。
- dotfiles 連續 10 次 ship 無人工 compaction 後，才開始 fleet rollout。

## 7. 風險與 rollback

- **搜尋排序不足**：不改 canonical content；保留 `git grep` fallback，先補 retrieval fixture 再調權重。
- **STATUS 遷移漏項**：pre/post entry hash 不一致即停止，不 commit；已搬內容與原檔同一 commit，整批可 revert。
- **新 audit 阻斷日常 ship**：Phase 1–3 只用 `--shadow`；正式切換只在 dotfiles 全綠後。宣告採用後 scanner error
  fail closed，不能偷偷退回 legacy。
- **其他 repo 不相容**：未採用者保留 legacy detector；每個 repo 用自己的 config adapter，不改其 authority paths。
- **治理面再膨脹**：先刪重複 parser、compat prose 與已過 rollout 的 wrapper；不得調高 self-budget 掩蓋回歸。

Rollback 以 phase commit 為單位倒回；history migration commit 不與 parser prototype 混在一起。任何 rollback 都不得
只恢復 STATUS 而留下 history duplicate，或只刪 history 而留下新 pointers。
