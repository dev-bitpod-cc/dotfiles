# Claude Skill 建立指南（摘要）

> **來源**（兩份，後者較新且為準）：
> 1. Anthropic "The Complete Guide to Building Skills for Claude"（PDF，2026/03 公開）
>    - 原始 PDF：`~/Projects/Documents/The-Complete-Guide-to-Building-Skill-for-Claude.pdf`
> 2. **官方 "Skill authoring best practices" 線上文件**（持續更新，規則以此為準）
>    - <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
>    - <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview>
>    - 本摘要擷取日期：**2026-06-02**
>
> 兩份衝突時以線上 best-practices 頁面為準（下方已標注差異）。修改 skill 前若距擷取日期已久，建議重抓線上頁面確認有無新變更。

## Skill 是什麼

一個資料夾，包含指令集，教 Claude 處理特定任務或工作流程。
核心機制：啟動時只預載各 skill 的 `name` + `description`（每個約 60 tokens）；任務相關時才讀 SKILL.md body；body 內引用的檔案再按需讀取（progressive disclosure）。

## 資料夾結構

```
your-skill-name/           # kebab-case，不可有空格/底線/大寫
├── SKILL.md               # 必要（大小寫敏感，不接受 skill.md / SKILL.MD）
├── scripts/               # 選用 - 可執行腳本（執行不載入 context，只吃 output tokens）
├── references/            # 選用 - 參考文件（按需載入）
└── assets/                # 選用 - 模板、字型、圖示
```

- 不要在 skill 資料夾內放 README.md；所有文件放 SKILL.md 或 references/

## YAML Frontmatter

### 驗證規則（硬性，違反無法上傳）

- `name`：**≤ 64 字元**，僅 lowercase 字母 / 數字 / hyphen，無 XML 角括號，不可含保留字 `anthropic` / `claude`，與資料夾同名
- `description`：**非空、≤ 1024 字元**，無 XML 角括號

### 選用欄位

```yaml
license: MIT
compatibility: Claude.ai, Claude Code   # 1-500 字元
allowed-tools: "Bash(python:*) WebFetch" # 限制工具存取
metadata:
  author: Name
  version: 1.0.0
```

### 命名慣例（線上頁面新增建議）

- **推薦 gerund 動名詞**（verb + -ing），清楚描述能力：`processing-pdfs`、`analyzing-spreadsheets`、`testing-code`
- 可接受替代：名詞短語（`pdf-processing`）、動作式（`process-pdfs`）
- 避免：模糊名（`helper`、`utils`、`tools`）、過度通用（`documents`、`data`）、保留字

### description 寫法（★ 觸發成敗關鍵）

結構：`[做什麼] + [何時使用 / 觸發詞]`。Claude 在 100+ skill 中靠這欄選擇要不要載入。

- **必須第三人稱**（線上頁面強制）。description 注入 system prompt，人稱不一致會破壞觸發判斷
  - ✅ `Processes Excel files and generates reports. Use when...`
  - ❌ `I can help you process Excel files` / `You can use this to...`
- 具體、含關鍵詞與觸發情境

好範例：
```yaml
description: Extract text and tables from PDF files, fill forms, merge documents.
  Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```
壞範例：`Helps with documents` / `Processes data`（太模糊、缺觸發詞）

## 三層 Progressive Disclosure

1. **YAML frontmatter**：永遠載入 system prompt，提供觸發判斷資訊（約 60 tokens/skill）
2. **SKILL.md body**：判斷相關時才載入，含核心指令（像 onboarding guide 的目錄）
3. **Linked files**（references/ 等）：按需探索載入；scripts 執行時不進 context

### Body 大小（★ 已從舊 PDF 的「5000 字」改為行數）

- **SKILL.md body 保持在 500 行以內**（線上頁面明確標準，取代舊「5,000 字」）
- 逼近上限就拆到 references/

### 引用結構規則（線上頁面新增）

- **引用只能一層深**：所有 reference 檔直接從 SKILL.md 連出。巢狀引用（A→B→C）會讓 Claude 只 `head -100` 預覽、讀到不完整資訊
- **> 100 行的 reference 檔開頭放 table of contents**，讓 Claude 預覽時看得到全貌
- 檔名要描述性（`form_validation_rules.md` 不是 `doc2.md`）；用 forward slash，不用 Windows 反斜線

## 三大 Use Case 類型

| 類型 | 用途 | 範例 |
|------|------|------|
| Document & Asset Creation | 產出一致高品質的文件/設計/程式碼 | frontend-design, docx, pptx |
| Workflow Automation | 多步驟流程、跨 MCP 協調 | skill-creator |
| MCP Enhancement | 為 MCP 工具加上工作流程知識 | sentry-code-review |

## 設計原則

### Concise is key（線上頁面置頂原則）

Context window 是公共財。**預設 Claude 已經很聰明**，只加它沒有的 context。逐句自問：「Claude 真的需要這段解釋嗎？這段值得它的 token 成本嗎？」

### 設定適當的自由度（degrees of freedom）

依任務脆弱度匹配指令具體程度：

| 自由度 | 用法 | 時機 |
|--------|------|------|
| **High**（文字指令） | 給方向，信任 Claude 找路 | 多種做法皆可、依情境決策（如 code review） |
| **Medium**（pseudocode / 帶參數腳本） | 偏好模式 + 容許變化 | 有偏好寫法、設定影響行為 |
| **Low**（固定腳本、少參數） | 精確護欄、「照這指令別改」 | 操作脆弱、一致性關鍵（如 DB migration） |

類比：窄橋（兩側懸崖）給精確指令；開闊地（無危險）給大方向。

### 五種設計 Pattern（PDF）

1. Sequential Workflow　2. Multi-MCP Coordination　3. Iterative Refinement
4. Context-aware Tool Selection　5. Domain-specific Intelligence

## SKILL.md 撰寫最佳實踐

- 具體可執行，不要模糊（"validate the data" → 列出具體指令與常見錯誤）
- 關鍵指令置頂，用 `## Important` / `## Critical`
- **一致術語**：同一概念全程用同一詞（別混用 endpoint/URL/route）
- **避免 time-sensitive 資訊**：不要寫「2025/08 前用舊 API」；改用 `## Old patterns`（`<details>` 折疊）保存歷史
- **別給太多選項**：給一個預設 + escape hatch，不要「可以用 A 或 B 或 C 或…」
- 清楚標示 bundled resource 是**執行**（"Run `x.py`"）還是**當參考讀**（"See `x.py` for the algorithm"）

### Workflow 與 feedback loop（線上頁面強調）

- 複雜任務拆成清楚步驟；特別複雜的給 **checklist** 讓 Claude 複製進回應逐項勾選
- **Feedback loop 模式**：`run validator → fix errors → repeat`，大幅提升品質
- **critical / 破壞性操作要有 validation step**：plan → **validate** → execute → verify，產出可機器驗證的中間檔（如 `changes.json`）

## 含可執行腳本的 Skill（進階）

- **Solve, don't punt**：腳本自己處理錯誤（FileNotFound / Permission），不要丟回給 Claude
- **無 voodoo constants**：每個常數註解理由（`REQUEST_TIMEOUT = 30  # slow connections`），不要 `TIMEOUT = 47`
- 預製腳本優於即時生成（更可靠、省 token、一致）
- **明確列依賴**（`pip install pypdf`），別假設已安裝
- **MCP 工具用 fully-qualified 名稱**：`ServerName:tool_name`（如 `GitHub:create_issue`），否則多 server 時找不到工具
- 環境差異：claude.ai 可裝 npm/PyPI 套件；Claude API **無網路、不能 runtime 裝套件**

## 測試與迭代（線上頁面大幅擴充）

### Build evaluations FIRST（核心方法論）

寫 extensive 文件**之前**先建 eval，確保解決真問題而非想像問題：

1. **找 gap**：無 skill 跑代表性任務，記錄失敗
2. **建 eval**：針對 gap 做 ≥ 3 個情境
3. **建 baseline**：量測無 skill 的表現
4. **寫最小指令**：剛好補足 gap、通過 eval
5. **迭代**：跑 eval、對比 baseline、refine

eval 結構（JSON）：`{skills, query, files, expected_behavior[]}`。目前無內建 runner，需自建。

### 三種測試

1. **Triggering**：明確任務觸發、改述觸發、無關主題不觸發
2. **Functional**：輸出正確、API 成功、錯誤處理、邊界覆蓋
3. **跨模型**：**Haiku / Sonnet / Opus 都要測**（Opus 不需過度解釋，Haiku 可能需更多指引）

### Claude A / Claude B 迭代法

用一個 Claude（A）幫你寫 skill，另一個 fresh Claude（B）實際用 skill 做任務，觀察 B 的行為（探索順序、漏讀的引用、過度依賴或忽略的檔），把觀察帶回 A 改進。`name` / `description` 最關鍵——直接決定觸發。

## Skill 紀律測試（TDD-for-skills）

> 適用對象：**紀律強制型 skill**（要 agent 在壓力下仍遵守某規則，如 root-cause-first、verification-before-commit）。一般技術/參考型 skill 用上面的 eval-first 即可，本節是補強、不是取代——eval-first 確保「解決真問題」，本節確保「規則在壓力下不被合理化繞過」。

核心命題：**寫 skill = 對「流程文件」做 TDD**。沒先看過 agent 在無 skill 下失敗，你不知道 skill 該教什麼。

### RED → GREEN → REFACTOR 對應

| TDD 概念 | Skill 版本 |
|---------|-----------|
| 寫失敗測試 | 設計 pressure scenario（施壓情境） |
| 看它失敗（RED） | 無 skill 跑情境，**逐字記下** agent 的違規與合理化說詞 |
| 最小實作（GREEN） | 寫剛好針對那些說詞的 skill，別加假想內容 |
| 測試通過 | 有 skill 跑同情境，agent 遵守 |
| Refactor | agent 找到新藉口 → 補明確反制 → 重測直到滴水不漏 |

**Iron Law（同 TDD）：沒有失敗測試就不寫 skill。** 對新 skill 與既有 skill 的修改都適用。

### Pressure scenario 怎麼設計

施壓型別，越疊越能逼出真實行為：
- **時間壓力**：「客戶在線上等，五分鐘內要修好」
- **沉沒成本**：「你已經花兩小時改這塊了」
- **權威**：「資深說直接改那行就好」
- **疲勞**：「這是今天第八個 bug 了」

紀律型 skill 至少疊 **3 種壓力** 一起測。成功判準：agent 在最大壓力下仍遵守規則。

### Rationalization table 與 Red flags 的寫法

把 baseline 測出來的**每一句藉口**收進表，逐句給 reality 反制。這是 skill 抵抗合理化的主力——**保留英文原文**（agent 的內在藉口多以英文出現，比對最準）：

```markdown
| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. The test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
```

再附一個 **Red Flags** 自檢清單，讓 agent 容易自我察覺「我正要違規」：

```markdown
## Red Flags — STOP
- 還沒搞懂就提修法
- "One more fix attempt"（已試 2+ 次）
全部代表：STOP，回到流程起點。
```

### 補洞三原則

1. **明確封死每個 loophole**：不只說規則，要點名禁止的繞法（「Don't keep it as reference. Don't look at it. Delete means delete.」）
2. **先講 letter=spirit**：開頭放「Violating the letter of the rules is violating the spirit」，斷掉「我遵守精神就好」整類藉口
3. **description 也納入違規徵兆**：把「快要違規時的症狀」寫進觸發詞

## 常見問題排解

| 問題 | 原因 | 解法 |
|------|------|------|
| 不觸發 | description 模糊或缺觸發詞 | 加具體 trigger phrases、確認第三人稱 |
| 過度觸發 | description 太廣 | 加 negative trigger、限縮 scope |
| 指令未被遵循 | 太冗長/被埋沒/語意模糊 | 精簡、置頂、用 MUST 等強語氣 |
| Context 過大變慢 | SKILL.md > 500 行或同時啟用太多 skill | 移到 references/、控制 skill 數量 |
| 上傳失敗 | 命名錯誤或 YAML 問題 | 確認大小寫、`---`、name 規則 |

## 發布前 Checklist（線上頁面）

**核心品質**：description 具體含觸發詞且第三人稱 ／ body < 500 行 ／ 細節在獨立檔 ／ 無 time-sensitive 資訊 ／ 術語一致 ／ 範例具體 ／ 引用一層深 ／ workflow 步驟清楚
**程式與腳本**：腳本自己解決不 punt ／ 顯式錯誤處理 ／ 無 voodoo constants ／ 列依賴 ／ forward slash ／ critical 操作有驗證 ／ 含 feedback loop
**測試**：≥ 3 個 eval ／ Haiku+Sonnet+Opus 都測 ／ 真實情境測過 ／ 納入團隊回饋

## 撰寫語言政策（定向英文）★ 維護本檔與所有 skill 時一律遵循

官方範例 SKILL.md body 與指令以英文撰寫，因英文觸發/指令遵循較穩。但**全部翻英文是過度工程**——那 80% 的描述性內容在 Claude 4.x 下中英等效，卻拉高你維護非母語硬規則的出錯風險。故採**定向英文**：把英文用在「斷然」最有價值處，把繁中留在「你要常改」處。

| 內容類型 | 語言 | 理由 |
|---------|------|------|
| 硬約束 / 否定句 / 紀律強制塊（Iron Law、rationalization table、red flags） | **英文** | 祈使句、否定的遵循率英文最穩；這些是 pressure-test 調出來的英文話術 |
| 程序步驟 / 領域 SOP / 概念解說 | **繁中** | 純資訊傳遞中英等效，繁中維護成本低 |
| 觸發詞 / description | **中英關鍵字並列** | 你的觸發語境是中文，但補英文擴大覆蓋 |
| 面向使用者的輸出 | **繁中** | 與全域語言設定一致；不受指令語言影響 |

**檔案內一致性**：同一檔案中英混雜會輕微分散注意力——上述分層是「依內容性質」切，不是隨意混。紀律塊整塊英文、流程整塊繁中。

> 未來任何 CC 編輯本檔、CLAUDE.md、或任何 skill 時，預設套用此政策。CLAUDE.md 另有一行 always-on 的精簡版 meta-rule 作為提醒入口。
