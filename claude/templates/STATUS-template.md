<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
角色分工:README(對外說明)/ CLAUDE.md(慣例與指令)/ STATUS.md(本檔:狀態+決策+死路+債)
        / docs/plans/(帶日期的設計文件)/ docs/transfer.md(移交指南,見 transfer-guide-template)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
注意:本檔名專屬 dossier——領域產物(如爬蟲配置 checklist)請改用其他檔名(如 CRAWL-CONFIG.md)。
-->

# STATUS.md

<專案一句話定位>(更新日期:YYYY-MM-DD)

---

## 進行中

### 1. <工作項標題> <⏳/🆕>

<!-- spec 區:開工時填,是給 AI 的工作合約,也是未來 owner 的背景 -->
- **Context**:為什麼要做這件事
- **Goal**:做到什麼程度算完成
- **Acceptance Criteria**:怎麼驗證它真的好了
- **Constraints**:哪些東西不能碰、必須維持的邊界
- **進度**:目前做到哪(condensed;細節看 commit)
- **下一步**:<具體到能直接動手;跨主機接續時這裡就是交接點>

---

## 關鍵決策(附理由)

<!-- 沒有理由的決策會被未來的 session(或新 owner)翻案;一行一決策,新的在上 -->
- **YYYY-MM-DD <決策>**:<選了什麼、為什麼、放棄了什麼替代方案>

## 死路(試過但放棄——防重工)

<!-- dossier 最值錢的一節:未來最容易在這裡重蹈覆轍;真的沒有才寫「無」 -->
- **<嘗試>**:<為何放棄;若有實驗數據附上>

## 技術債

- [ ] <債項>:<影響範圍與償還時機建議>

## 已完成(里程碑)

- ✅ **YYYY-MM-DD <里程碑>**:<一句話成果;能對應 commit/PR 的附連結或 sha>

## 已知缺口

- <功能面或資料面的已知限制,尚無解決計畫者>

## 移交準備度

<!-- 平時可空;顯露「要上 production / 要移交」訊號時開始維護,/project transfer 會檢查 -->
- [ ] 關鍵決策與死路已補齊理由
- [ ] 環境建置步驟可由第三者重現(README 或 docs/)
- [ ] Credentials 與設定分離(.env.example 齊全、無硬編碼)
- [ ] 移交指南(docs/transfer.md)已建立
