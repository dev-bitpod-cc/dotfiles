# Deep Review 報告模板

## 報告模板 — 未通過（單 repo）

問題**按根因分組**，不按嚴重度排列。共享同一根因的問題放在一起，讓 fixer 一次解決而非逐條修補。

```markdown
## Deep Review — Round {N}

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
**整體評估**: {一句話總結}
**問題統計**: {N} 嚴重 / {N} 中等 / {N} 建議 (non-blocking)

### 亮點
- `file.py:50-80` — 做得好的地方

### 問題（Blocking）

#### 根因 A：{根因描述}
影響範圍：`file1.py:42`, `file2.py:88`, `file3.py:15`

- [嚴重] {問題描述} — {影響}
- [中等] {問題描述} — {影響}

#### 根因 B：{根因描述}
- [中等] `file4.ts:30` — {問題描述}

### 建議（Non-blocking）
- [建議] `file.ts:15` — {描述}

### 一致性檢查
跨檔案契約同步狀態 + 相關專案慣例是否符合。

### 整體性評估
{Round 2+ 輸出} 補丁痕跡、重複邏輯、抽象不一致等。

### 修復計畫
{由 subagent 根據本次具體問題產出，不是固定文字}

**建議修復順序**：
1. 先處理根因 A — {具體做法、影響範圍}
2. 再處理根因 B — {具體做法}
3. 獨立問題逐一修正

{Round 4+ 且仍有結構性問題}
> **建議退一步重寫**：{區塊} 已過多輪修補，建議重新設計後從頭寫過。

修完後，先 commit（如 `fix: R{N} review fixes`），再執行下一輪 `/deep-review`。
最終通過後，squash 成乾淨的 commit。
```

## 報告模板 — 未通過（多 repo）

```markdown
## Deep Review — Round {N}

**涉及 Repo**:
- `repo-a`：{N} 個檔案，+{N}/-{N}
- `repo-b`：{N} 個檔案，+{N}/-{N}

**整體評估**: {一句話總結}
**問題統計**: {N} 嚴重 / {N} 中等 / {N} 建議 (non-blocking)

### repo-a

#### 亮點
- ...

#### 問題
（同單 repo 格式，按根因分組）

### repo-b

#### 亮點
- ...

#### 問題
（同單 repo 格式，按根因分組）

### 跨 Repo 一致性
（subagent 獨立判斷的結果，主 agent 不加工）
- env var `X` 兩端處理方式是否一致
- 介面契約（port、路徑、schema）是否對齊
- 文件與實作是否同步

### 整體性評估
{Round 2+ 輸出}

### 修復計畫
（同單 repo 格式）

修完後，逐 repo commit（如 `fix: R{N} review fixes`），再執行下一輪 `/deep-review`。
最終通過後，squash 成乾淨的 commit。
```

## 報告模板 — 通過

```markdown
## Deep Review — Round {N} — 審查通過

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
{多 repo 時列出各 repo}
**整體評估**: {一句話正面總結}

### 亮點
- `file.py:50-80` — 做得好的地方

### 跨 Repo 一致性
{多 repo 時由 subagent 輸出}

### 建議（Non-blocking follow-up）
{若有建議等級的問題，列在此處供參考}
- [建議] `file.ts:15` — {描述}
{若無建議等級問題則省略此區塊}

### Commit 建議
{若有多筆 review fix commit（如 fix: R1/R2/R3 review fixes）}
主 agent 執行 squash：`git reset --soft <base>` 後重新 commit，message 採原始功能變更的語意（如 `feat: 新增 X 功能`），不用 `fix: review fixes`。格式遵循專案 Conventional Commits 慣例。
{若只有一筆 commit + clean working tree}
可以直接 push。

### 第三方審查資訊
{列出每個涉及的 repo，方便使用者轉交第三方 reviewer}

| Repo | Commit 範圍 | 變更摘要 |
|------|-------------|----------|
| `repo-a` | `abc1234..def5678` | {一句話：主要改了什麼} |
| `repo-b` | `111aaaa..222bbbb` | {一句話：主要改了什麼} |

{commit 範圍用 `base..head` 格式，base 取審查起點（Step 1 判定的 base commit），head 取最終 commit}
{單 repo 時表格只有一列}

{多 repo 時}
**Push 順序**：被依賴的 repo 先 push（例如 platform 定義 interface → deploy 消費 interface，則先 push platform）。錯序 push 可能造成 CI 失敗或部署短暫不一致。
{單 repo 時省略此段}

審查通過，可以提交了。
```

## 報告模板 — Autofix 終止（R5 未通過）

```markdown
## Deep Review — Autofix 終止（R5 未通過）

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
{多 repo 時列出各 repo}

### 修復軌跡

| 輪次 | 問題數 | 修復數 | 說明 |
|------|--------|--------|------|
| R1 | {N} | {N} | {一句話：主要修了什麼} |
| R2 | {N} | {N} | {一句話} |
| R3 | {N} | {N} | {一句話} |
| R4 | {N} | {N} | {一句話} |
| R5 | {N} | — | 未自動修復 |

### 收斂失敗分析
{為什麼三輪修不完——是修 A 引入 B？還是結構性問題反覆觸發？}

### 剩餘問題
（同未通過格式，按根因分組）

### Branch 狀態處置

目前 branch 上有 {N} 個 review fix commit（`fix: R1~R4 review fixes`）。

{根據剩餘問題的性質選擇建議}
- 若建議重寫 → `git reset --soft <base>` 回到起點，帶著所有變更重新設計 {區塊}，再重新 commit
- 若可繼續修 → 保留現有 commit，在此基礎上繼續人工修復，完成後 squash

### 建議下一步

{根據剩餘問題的性質給出具體建議}
- 若剩餘問題是結構性的 → 建議重寫哪個區塊、用什麼方式
- 若剩餘問題是收斂震盪 → 指出震盪的根源，建議固定哪個方向
- 若剩餘問題只是建議等級 → 應判定為通過（走通過模板 + Non-blocking follow-up），不應進入此終止報告

改完後可再跑 `/deep-review` 或 `/deep-review autofix`。
```

## 報告模板 — Codex 第三方審查通過

```markdown
## Codex 第三方審查 — 通過

**審查範圍**:
{每個 repo 的路徑和 commit range}

### Codex 審查軌跡

| 輪次 | Findings | True Positive | 修復 | 說明 |
|------|----------|---------------|------|------|
| C1 | {N} | {N} | {N} | {一句話：主要修了什麼，或「全為 false positive」} |
| C2 | {N} | {N} | — | 無 blocking findings |

{若 C1 即無 true positive}
| C1 | {N} | 0 | — | 全為 false positive，無需修復 |

### False Positive 記錄
{列出被判定為 false positive 的 findings 及理由，供使用者參考}
- [FP] {finding 描述} — {為何是 false positive}

### Commit 建議
{與通過報告相同——squash 所有 review fix commits（CC 階段 + codex 階段），message 採原始功能語意}

CC 審查 + Codex 第三方審查皆通過，可以提交了。
```

## 報告模板 — Codex 第三方審查終止（C3 仍有 true positive）

```markdown
## Codex 第三方審查 — 終止（C3 仍有 true positive）

**審查範圍**:
{每個 repo 的路徑和 commit range}

### Codex 審查軌跡

| 輪次 | Findings | True Positive | 修復 | 說明 |
|------|----------|---------------|------|------|
| C1 | {N} | {N} | {N} | {一句話} |
| C2 | {N} | {N} | {N} | {一句話} |
| C3 | {N} | {N} | — | 未自動修復 |

### 收斂失敗分析
{為什麼兩輪修不完——是修 A 引入 B？還是 codex 持續在不同角度發現新問題？}

### 剩餘 True Positive
{列出 C3 中被判定為 true positive 的 findings}
- [TP] `file.py:42` — {問題描述} — {影響}

### False Positive 記錄
- [FP] {finding 描述} — {為何是 false positive}

### 建議下一步
{具體建議：手動修復剩餘問題後可再跑 `/deep-review autocodex`}

### Branch 狀態
目前 branch 上有 CC 審查 fix commits + codex fix commits。修復剩餘問題後，一併 squash 成乾淨 commit。
```
