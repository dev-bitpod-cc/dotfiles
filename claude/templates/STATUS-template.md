<!--
STATUS.md — 專案 active state（repo 內、隨 git 跨主機、隨專案移交）。
本檔只回答「現在正在做什麼／暫停什麼」；decision、dead end、milestone 在發生當下寫入
`docs/archive/{decisions,dead-ends,milestones}-YYYY-MM.md` 的 event-time section。
維護時機：開工寫 spec；狀態改變時就地更新；完成時寫 milestone record 並移除 active item。
禁止新增 Session Log、變更紀錄、決策、死路、技術債、已完成等只增不減的歷史章節。
-->

# STATUS.md

<專案一句話定位>（更新日期：YYYY-MM-DD）

---

## 進行中

### 1. <工作項標題> <⏳/🆕>

- **Context**：為什麼要做這件事
- **Goal**：做到什麼程度算完成
- **Acceptance Criteria**：怎麼驗證它真的好了
- **Constraints**：哪些東西不能碰、必須維持的邊界
- **進度**：目前做到哪；附 branch、SHA、plan 或 record ID
- **下一步**：具體到能直接動手的交接點
- **關聯**：相關 `D-*`／`X-*`／`B-*` stable IDs；無則寫 none

## 暫停中

<!-- 每項必須寫「恢復條件」，不能只寫 paused。真的沒有就寫「目前無暫停項目」。 -->
- **<工作項>**：<為何暫停>；**恢復條件**：<可觀察條件>

## 歷史入口

- 決策：`docs/archive/decisions-YYYY-MM.md` 的 event-time section。
- 死路：`docs/archive/dead-ends-YYYY-MM.md` 的 event-time section。
- 里程碑：`docs/archive/milestones-YYYY-MM.md` 的 event-time section。
- 無路徑線索時執行 `scripts/doc-governance.py find <自然語言或 stable ID>`。

## 待辦入口

- 未結案項目以 `docs/backlog.md` 為 canonical state；用 `B-*` stable ID 定位。

## 移交準備度

<!-- 平時可空；顯露「要上 production／要移交」訊號時開始維護。 -->
- [ ] active／paused 狀態與下一步已更新
- [ ] 關鍵 decision／dead end 已寫入 history shard
- [ ] 環境建置步驟可由第三者重現（README 或 docs/）
- [ ] Credentials 與設定分離，程式碼內無硬編碼
- [ ] 移交指南（docs/transfer.md）已建立
