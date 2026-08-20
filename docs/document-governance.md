# 文檔治理契約

Adapter：`.doc-governance.json`。

## 資料模型

tracked Markdown 必須恰好分類一次：`loaded` 守 context 預算；`active` 未結案；`routed` 按需；`history` 只增；`derived` 須有 rebuild command；`governance` 計量機制本身。非 loaded 類守定位、檢索與生命週期，不守總量；`requires_inbound` 只給 evidence layer。

## CLI 契約

- `find <query>`：H1 preamble／H2；history 用頂層 bullet。最多五筆，含定位欄位與 240-byte 摘錄；無 H2 回 `file-preamble`。stdout ≤8 KiB；命中／miss／錯誤回 0／1／2。
- `audit [--shadow|--ship]`：一般模式 clean／finding／error 回 0／1／2；shadow finding 回 0；ship 印 `OK|FINDINGS|BROKEN`。
- `audit --check xref [files...]`：舊 gate 相容；finding 回 0，error 回 2。
- `report` 計量但不因體積失敗；`record-path` 只算 path／ID／heading。

`--root` 省略時取 git toplevel；只讀 tracked files，不依賴網路或本機索引。history 不以人工 pointer 代理；所有引用仍做 forward xref。

## 生命週期

新歷史只寫 `docs/archive/{decisions,dead-ends,milestones}-YYYY-MM.md` 的 `## 事件記錄（event-time）`，ID 為 `D/X/M-YYYYMMDD-slug`。title／ID／shard 日期須一致；metadata 含 `日期來源`、`放棄`、`重議`、`關聯`。已 commit 內容不改不刪；翻案另寫 `supersedes:<ID>` record。

`STATUS.md` 只留進行中、帶恢復條件的暫停項、history／backlog 入口與移交準備度。`docs/backlog.md` 只留未結案 `B-YYYYMMDD-slug`；移除時須有引用該 ID 的 D/X/M record。

plan 同 work item 唯一：`draft/approved/in-progress` 原檔修訂；`implemented/superseded` 凍結，後者指向 replacement；禁 `-v2/-final/-revised`。Legacy blobs 凍結且不進 `find`，config 明列需求來源才例外。
