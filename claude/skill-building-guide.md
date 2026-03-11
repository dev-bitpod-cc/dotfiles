# Claude Skill 建立指南（摘要）

> 來源：Anthropic "The Complete Guide to Building Skills for Claude"（2026/03 公開）
> 原始 PDF：`~/Projects/Documents/The-Complete-Guide-to-Building-Skill-for-Claude.pdf`

## Skill 是什麼

一個資料夾，包含指令集，教 Claude 處理特定任務或工作流程。

## 資料夾結構

```
your-skill-name/           # kebab-case，不可有空格/底線/大寫
├── SKILL.md               # 必要（大小寫敏感，不接受 skill.md / SKILL.MD）
├── scripts/               # 選用 - 可執行腳本
├── references/            # 選用 - 參考文件（按需載入）
└── assets/                # 選用 - 模板、字型、圖示
```

- 不要在 skill 資料夾內放 README.md
- 所有文件放 SKILL.md 或 references/

## YAML Frontmatter

```yaml
---
name: skill-name-in-kebab-case        # 必要，kebab-case，與資料夾同名
description: |                         # 必要，<1024 字元
  做什麼 + 何時觸發 + 關鍵能力。
  Use when user asks to [specific phrases].
license: MIT                           # 選用
compatibility: Claude.ai, Claude Code  # 選用，1-500 字元
allowed-tools: "Bash(python:*) WebFetch"  # 選用，限制工具存取
metadata:                              # 選用
  author: Name
  version: 1.0.0
  mcp-server: server-name
---
```

### 禁止事項
- frontmatter 內不可有 XML 角括號（`<` `>`）
- name 不可含 "claude" 或 "anthropic"（保留字）

### description 寫法

結構：`[做什麼] + [何時使用] + [關鍵能力]`

好的範例：
```yaml
description: Manages Linear project workflows including sprint planning,
  task creation, and status tracking. Use when user mentions "sprint",
  "Linear tasks", "project planning", or asks to "create tickets".
```

壞的範例：
```yaml
description: Helps with projects.              # 太模糊
description: Creates sophisticated systems.    # 缺觸發條件
```

## 三層 Progressive Disclosure

1. **YAML frontmatter**：永遠載入 system prompt，提供觸發判斷資訊
2. **SKILL.md body**：Claude 判斷相關時才載入，含完整指令
3. **Linked files**：references/ 等，按需探索載入

## 三大 Use Case 類型

| 類型 | 用途 | 範例 |
|------|------|------|
| Document & Asset Creation | 產出一致、高品質的文件/設計/程式碼 | frontend-design, docx, pptx |
| Workflow Automation | 多步驟流程、跨 MCP 協調 | skill-creator |
| MCP Enhancement | 為 MCP 工具加上工作流程知識 | sentry-code-review |

## 五種設計 Pattern

1. **Sequential Workflow** — 多步驟固定順序，步驟間有依賴，每步驗證
2. **Multi-MCP Coordination** — 跨多服務的階段式工作流程，階段間傳遞資料
3. **Iterative Refinement** — 初稿→品質檢查→修正循環→定稿
4. **Context-aware Tool Selection** — 根據情境選擇不同工具（決策樹）
5. **Domain-specific Intelligence** — 嵌入領域專業知識（如合規檢查）

## SKILL.md 撰寫最佳實踐

- 具體可執行，不要模糊（"validate the data" → 列出具體驗證指令和常見錯誤）
- 包含錯誤處理指引
- 清楚引用 bundled resources（`references/api-patterns.md`）
- 核心指令放 SKILL.md，詳細參考放 references/
- SKILL.md 保持在 5,000 字以內
- 關鍵指令放最上方，用 `## Important` / `## Critical` 標題

## 測試方法

### 1. Triggering Tests
- 明確任務應觸發、改述請求應觸發、無關主題不應觸發

### 2. Functional Tests
- 輸出正確、API 呼叫成功、錯誤處理正常、邊界情況覆蓋

### 3. Performance Comparison
- 對比有/無 skill 的 token 消耗、來回次數、失敗率

### Pro Tip
先在單一困難任務上反覆迭代直到成功，再將成功方法提取為 skill。

## 常見問題排解

| 問題 | 原因 | 解法 |
|------|------|------|
| Skill 不觸發 | description 太模糊或缺觸發詞 | 加入具體 trigger phrases |
| Skill 過度觸發 | description 太廣泛 | 加 negative triggers、限縮 scope |
| 指令未被遵循 | 指令太冗長/被埋沒/語意模糊 | 精簡、關鍵指令置頂、用明確語言 |
| Context 過大導致變慢 | SKILL.md 太大或同時啟用太多 skill | 移詳細內容到 references/、控制在 20-50 個 skill 內 |
| 上傳失敗 | SKILL.md 命名錯誤或 YAML 格式問題 | 確認大小寫、`---` 分隔符、name kebab-case |

## 迭代信號

- **Under-triggering**：加更多 keywords 到 description
- **Over-triggering**：加 negative triggers，更具體
- **Execution issues**：改善指令、加錯誤處理、考慮用腳本替代語言指令

## 發布

- GitHub 公開 repo + 清楚 README（repo 層級，非 skill 資料夾內）
- 組織可透過 admin 部署 workspace-wide skills
- API 使用：`/v1/skills` endpoint、`container.skills` 參數（需 Code Execution Tool beta）
