<!--
移交指南模板 — /project transfer 使用
位置慣例:填完後放 <repo>/docs/transfer.md 並 commit(本體不含機密,可上 git)。
Credentials 一律分離:一切 secrets / tokens / 連線字串放獨立檔(如 tmp/transfer-credentials.md,
必須在 .gitignore 內),以私訊/密碼管理器交付,絕不進 git。本模板中以 <見 credentials 檔> 指涉。
完整度前置:移交前先跑 /project transfer 檢查 STATUS.md 的決策/死路/債是否補齊——
接手者最需要的就是「為什麼這樣設計、哪些路試過不通」。
-->

# <專案名> 移交指南

> 目的:讓 <接手者> 能自行建立完整環境、通過 QA、正式接手 owner。
> 移交人:<name>|接手者:<name>|目標日:YYYY-MM-DD

---

## 0. 待決策事項(移交前雙方確認)

<!-- 每項決策:選項攤開、拍板後打勾。範例列常見六類,依專案增刪 -->

| 編號 | 決策 | 選項 | 決定 |
|------|------|------|------|
| D1 | API key / LLM 來源 | 自申請 / 走 gateway / 共用既有 | ☐ |
| D2 | 資料庫存取範圍 | 唯讀帳號範圍、schema 界線 | ☐ |
| D3 | 向量庫 / 其他儲存存取方式 | token 類型、RBAC 範圍 | ☐ |
| D4 | 外部服務帳號 | 誰申請、誰核准 | ☐ |
| D5 | Repo 權限模式 | fork / collaborator / transfer ownership | ☐ |
| D6 | QA 通過後的合併與切換 | 誰 review、誰 merge、何時切 owner | ☐ |

## 1. 系統全貌

- **架構一句話**:<repo 組成、依賴的中央資源(DB/向量庫/gateway)>
- **必讀**:`STATUS.md`(決策與死路)、`CLAUDE.md`(慣例)、`README.md`(安裝)
- **正在進行 / 未完成**:<指向 STATUS.md 進行中章節>

## 2. 環境建置

<!-- 目標:接手者不需要移交人在場就能跑起來;每步附驗證指令 -->

1. <clone / fork 步驟>
2. <依賴安裝:uv sync / bun install>
3. <.env 設定:對照 .env.example;值 → 見 credentials 檔>
4. <中央資源連線驗證指令>
5. <起服務 + 冒煙測試指令>

## 3. QA 驗收標準

<!-- 接手者「懂了」的客觀判準,不是「看過了」 -->

- [ ] <核心流程 E2E 跑通:具體指令與預期輸出>
- [ ] <測試套件全綠:uv run pytest / bun test>
- [ ] <能獨立完成一個小變更並過 review(建議出一個真實小 issue)>

## 4. 合併與 owner 切換

1. QA 產出以 <commit / patch / PR> 形式交付,由 <移交人> review 後 merge(依 D6)
2. Repo 權限調整:<接手者升 admin / transfer;移交人降權或留顧問>
3. 排程 / cron / 部署權限清點:<列出誰家機器上有什麼會繼續跑>
4. STATUS.md 補一筆關鍵決策:「YYYY-MM-DD owner 移交 <A> → <B>」

## 5. 已知風險與求助路徑

- <上線中的服務有哪些、掛了先看哪>
- <移交人可支援的期限與聯絡方式>
