<!--
STATUS.md — legacy repo dossier。只在 repo 尚未採用 .doc-governance.json +
scripts/doc-governance.py 時使用；adopted repo 改用 STATUS-template.md。
維護時機：開工寫 spec、ship 同步、移交前補齊。
禁止新增 Session Log／Change Log 等逐次追加章節；流水留在 git history。
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
- **進度**：目前做到哪；附 branch、SHA 或 plan
- **下一步**：具體到能直接動手的交接點

## 關鍵決策（附理由）

- **YYYY-MM-DD <決策>**：<選了什麼、理由、放棄的替代方案>

## 死路（試過但放棄）

- **<嘗試>**：<為何放棄；若有實驗數據附上>

## 技術債

- [ ] <債項>：<影響範圍與償還時機>

## 已完成（里程碑）

- ✅ **YYYY-MM-DD <里程碑>**：<一句話成果與 commit／PR>

## 已知缺口

- <功能或資料面的已知限制>

## 移交準備度

- [ ] 關鍵決策與死路已補齊理由
- [ ] 環境建置步驟可由第三者重現
- [ ] Credentials 與設定分離，程式碼內無硬編碼
- [ ] 移交指南（docs/transfer.md）已建立
