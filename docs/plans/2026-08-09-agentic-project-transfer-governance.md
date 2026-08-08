# Agentic 專案治理與移交可攜性——討論筆記

> **計畫參考，非定稿 spec**（2026-08-09）。本文件整理一輪關於 `CLAUDE.md`、
> `STATUS.md`／dossier、OpenWiki 與 `/project transfer` 的討論，供後續 Claude Code 規劃使用。
> **OpenWiki 是否引入仍待評估**；本文只定義評估邊界，不預設採用，也不授權安裝、生成 Wiki、
> 改寫既有治理檔或建立自動更新流程。

## 背景與問題

目前的 repo-resident 治理由以下內容組成：

- `CLAUDE.md`：Agent 慣例、指令、安全邊界與工作流。
- `STATUS.md`：專案 dossier；保存進行中 spec、狀態、決策理由、死路、技術債、已知缺口與移交準備度。
- `docs/plans/`、`docs/archive/`：定稿設計與需保留的歷史證據。
- `/project transfer`：移交前完整度檢查、credentials 盤點與 `docs/transfer.md` 產出流程。

討論的核心不是「能否多放一份 Wiki」，而是：經過這套個人化 agentic workflow 維護的 repo，
移交給另一個人或另一個 agentic engineering 團隊時，能否在**不依賴原 owner 的聊天記憶、
machine-local state、私人 skills 或口頭補充**的前提下獨立接管。

## 目前共識

### 1. `STATUS.md` 就是 dossier

在現行規範中兩者不是兩套系統。`STATUS.md` 是 dossier 的 repo-resident 實體；它記錄的是
程式碼與 Git history 無法可靠反推的意圖、理由、死路和未完成狀態。

### 2. 三種知識必須分層，不能互相冒充權威

| 層 | 適合承載的內容 | 性質 |
|---|---|---|
| Policy | 安全規則、權限邊界、工程慣例、必要命令 | 人工維護、具約束力 |
| Intent / State | 當前工作、決策理由、死路、債、缺口、下一步 | 人工維護、具時效與責任 |
| Derived Knowledge | 架構、模組關係、資料流、程式入口、repo 導航 | 可由來源重建、不可覆蓋前兩層 |

OpenWiki 若採用，只適合第三層。它可以減少手工維護 repo map、元件說明與導航資訊的成本，
但不能可靠生成「為何不選另一方案」「目前真正做到哪裡」「哪條規則是授權邊界」等事實。

### 3. 移交困難的主因不是檔案數量，而是隱含依賴與權威重疊

對接手方最危險的失效模式包括：

- 不知道 `STATUS.md` 是現況、歷史紀錄還是強制規格。
- 不知道 generated docs 是否可以刪除、重建或覆寫。
- `CLAUDE.md`、`STATUS.md`、設計文件與 Wiki 對同一件事說法不同，卻沒有衝突判準。
- repo 只有沿用原 owner 的 Claude Code slash commands 或私人 skills 才能安全維護。
- OpenWiki 更新需要特定模型、API key、成本或 CI，但這些依賴沒有交代。
- 新 Agent 把所有文件一併塞入 context，反而增加過期資訊與規則衝突。

Agentic 團隊同樣會受這些問題影響；Agent 擅長讀 repo-resident 文件，不代表它能自行猜出哪份文件
才是權威。

## 建議的可攜終態

以下是概念模型，不代表目前已決定新增或改名任何檔案：

```text
README.md
  人類入口：專案用途、建置、執行與驗證

AGENTS.md（或等價的工具中立入口）
  Agent 入口：必要規則、主要命令、文件權威與衝突順序

CLAUDE.md
  Claude Code 專屬薄層；不要成為其他 Agent 無法取得的唯一工程契約

STATUS.md
  尚未完成的工作、仍生效的決策、死路、技術債、缺口與移交狀態

openwiki/（僅在評估後決定採用時）
  可重建的架構與程式碼導航；不是 policy，也不是 project state

docs/
  穩定設計文件、移交指南與需長期保存的歷史證據
```

最少應存在一份簡短、明確的權威矩陣，概念如下：

```markdown
## Documentation authority

- Runtime behavior: source code and tests
- Engineering rules: the repo's agent policy entry point
- Current work and unresolved decisions: STATUS.md
- Architecture navigation: generated wiki, if present
- Generated documentation cannot override the sources above
```

這是**依內容領域分工**，不是用一條全域順位粗暴宣稱某檔永遠勝過另一檔。

## `STATUS.md` 的移交目標

應保留 dossier，但移交前要把它整理成接手快照，而非 append-only 工作日誌。接手者應能從首屏或
明確的「進行中」區域快速回答：

- 目前目標與實際進度是什麼？
- 下一個可執行步驟是什麼？
- 驗收與驗證命令是什麼？
- 目前有哪些 blocker、技術債與已知缺口？
- 哪些決策仍然有效，哪些路已試過而不應重做？
- 哪些操作仍依賴原 owner、特定帳號或外部授權？

逐輪進度、diff 摘要、已完成細節與長篇推導應沉入 Git history、定稿設計或 archive；不能因為
接手而刪除仍具防重工價值的死路與理由。

## OpenWiki 評估邊界（尚未決定採用）

若進入試點，OpenWiki 必須先被約束為 optional acceleration layer：

- 不安裝 OpenWiki，仍可建置、測試、部署及修改專案。
- `openwiki/` 若存在，必須可刪除並由明確命令重建。
- 關鍵規則、狀態、決策與安全邊界不得只存在於 Wiki。
- 文件須標明生成命令、版本／provider、credential 需求、成本承擔者與更新 owner。
- 自動更新只產生待審查變更，不因「自動生成」而取得 auto-merge 權力。
- 先建立 `.openwikiignore` 的 read boundary，再允許任何 repo 掃描；敏感 dotfiles repo 不宜作為
  第一個無防護試點。
- 需要觀察多輪 update 是否造成無意義重寫、過期資訊殘留、規則摘要失真、重複文件或不可接受的
  token／時間成本。

建議先選中型、非敏感 repo 做 shadow-mode A/B；在有行為證據以前，不刪減既有 canonical 文件。

## `/project transfer` 現況與缺口

現行 Transfer 模式已涵蓋：

1. dossier 完整度檢查；
2. `.env.example`／硬編碼 secrets／credentials 交付盤點；
3. 產出 `docs/transfer.md`；
4. QA、repo 權限、owner 切換與移交決策。

這是正式移交的良好骨架，但目前不足以單獨證明 agentic portability。現行模板的必讀入口固定為
`STATUS.md`、`CLAUDE.md`、`README.md`，尚未明確檢查：

- 是否存在工具中立的 Agent 入口。
- 文件權威矩陣與衝突處理規則。
- generated artifacts 的清單、重建方式、必要性與 owner。
- 不使用原 owner 私人 skills 時，repo 是否仍可維護。
- OpenWiki 若存在，其 optional／non-authoritative 契約與持續成本。
- 接手方能否從 clean clone、零聊天歷史完成第一個真實變更。

因此建議把 `/project transfer` 放在流程後段使用：

```text
portability cleanup
        ↓
clean-room takeover eval
        ↓
/project transfer
        ↓
接手方 QA 與待決策事項拍板
        ↓
/project log 提交移交文件
        ↓
人工完成權限與 owner 切換
```

尚無實際接手方時，不應為了「看起來準備好了」就提早產生一份很快過期的 `docs/transfer.md`；
先做 portability audit 或演練較合適。實際接手人／團隊已知時，再由 `/project transfer` 產出正式包。

## 建議的 clean-room takeover eval

以乾淨 clone、無原 session 對話、無 machine-local memory、無原 owner 私人 skill 為起點，交給另一個
Agent 或接手方一個中等規模的真實工作項，驗證它能否自行：

1. 找到應修改的位置與相關架構說明。
2. 找到且遵守必要工程規則與安全邊界。
3. 判讀當前狀態、有效決策、死路與已知缺口。
4. 安裝依賴並跑通建置、測試或核心 E2E。
5. 完成一個小變更並交付可 review 的結果。
6. 正確說出各文件的權威範圍；若有 Wiki，不把它當成 policy 或即時狀態。

建議量測：找檔正確率、規則遵守率、需向原 owner 追問的問題數、錯誤／過期引用、完成時間、
context/token 成本，以及 generated docs 的 diff noise。只針對實際失敗補規則或工具，不追求文件
表面完備。

## 後續規劃應回答的問題

1. 工具中立 Agent 入口要採 `AGENTS.md`、既有檔案的薄索引，或其他形狀？權威內容如何避免複製？
2. `/project transfer` 應直接擴充、增加 readiness/audit 模式，還是只調整 transfer template？
3. 哪些 portability 判準能做 deterministic gate，哪些必須以行為 eval 判斷？
4. clean-room fixture 如何保證拿不到原 owner 的 machine-local state，又能執行真實建置與測試？
5. `STATUS.md` 的接手首屏是否需要固定 schema，如何避免與現有 dossier 章節雙重記載？
6. 若試點 OpenWiki，選哪個非敏感 repo、哪些路徑必須 ignore、採用何種 provider 與成本上限？
7. OpenWiki 的成功／停止條件是什麼？若評估不通過，如何零殘留回退？

## 非目標與未決事項

- **尚未決定引入 OpenWiki。**
- 尚未決定修改 `/project transfer` skill 或模板。
- 尚未決定建立 `AGENTS.md`，也未決定搬移或刪減既有 `CLAUDE.md` 內容。
- 本輪不安裝工具、不執行 Wiki 生成、不建立 CI、不改 credentials 或 repo 權限。
- 不要求接手團隊沿用原 owner 的個人 workflow；是否採用應由移交雙方決定。
- 不以新增更多散文規則作為完成標準；行為 eval 才是可攜性是否成立的 oracle。
