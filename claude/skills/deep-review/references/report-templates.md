# Deep Review 報告模板

## 目錄

- 報告模板 — 未通過（單 repo）
- 報告模板 — 未通過（多 repo）
- 報告模板 — 通過（含第三方審查資訊、Commit/squash 建議）
- 報告模板 — Autofix 終止（R5 未通過）
- 報告模板 — Codex 第三方審查通過（含 Completeness 深井、False Positive 記錄）
- 報告模板 — Codex 第三方審查終止（C3 仍有 true positive）
- 報告模板 — Codex 第三方審查 blocked（救援階梯走完仍無報告）

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
補丁痕跡、重複邏輯、抽象不一致等（**恆常評估，不分輪次**——判斷依據是 code 本身，非 commit 次數）。

### 修復計畫
{由 subagent 根據本次具體問題產出，不是固定文字}

**建議修復順序**：
1. 先處理根因 A — {具體做法、影響範圍}
2. 再處理根因 B — {具體做法}
3. 獨立問題逐一修正

{若結構性問題已深到補丁補不動}
> **建議退一步重寫**：{區塊} 的抽象已被反覆修補侵蝕，建議重新設計後從頭寫過。

修完後，先 commit（如 `fix: address review findings`），再執行下一輪 `/deep-review`。
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
（同單 repo 格式）

### 修復計畫
（同單 repo 格式）

修完後，逐 repo commit（如 `fix: address review findings`），再執行下一輪 `/deep-review`。
最終通過後，squash 成乾淨的 commit。
```

## 報告模板 — 通過

```markdown
## Deep Review — Round {N} — 審查通過

**範圍**: {模式} — {檔案數} 個檔案，{增/刪行數}
{多 repo 時列出各 repo}
{autofix 時}**測試 baseline**: {pass|fail|skip}{fail 時必加：——審查前測試已紅，本次所有 fix commits 為 `UNVERIFIED-BY-TESTS(baseline-red)`、未經測試驗證；skip 時註明無測試框架}
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
{若有多筆 review fix commit（如 fix: address review findings）}
主 agent 執行 squash：跑 `~/.claude/skills/deep-review/scripts/review-anchor.sh squash-cmd --repo <r>`，把 `squash-cmd:` 整行照抄執行（腳本已解析出固定 hash 並驗過存在性與祖先關係；回 `verdict: STOP` 就停下交使用者，勿自行湊 hash、勿用會移動的 ref）。reset 後重新 commit。**message 依 `squash-preserve:` 分流**：無 preserve → 採原始功能變更的語意（如 `feat: 新增 X 功能`）；有 preserve → 新 commit 只是相對保留 commit 的增量，message 描述該增量（如 `fix: 修正 X 的邊界處理`），**不得沿用被保留 commit 的 subject**。兩者都不用 `fix: address review findings`，格式遵循專案 Conventional Commits 慣例。`verdict: WARNING`（無 commit 可 squash）→ 跳過 reset 與 commit，**但仍要跑 `clear`**（審查已完成，anchor 殘留會讓下一場被誤判成續跑）。
{squash-cmd 印 `squash-preserve:`（保留下來、將與新 commit 並存的既有語意 commit）或 `squash-note:`（被隔開、未納入本次 squash 的 review 樣式 commit）時，在此轉述該行讓使用者知悉}
{若只有一筆 commit + clean working tree}
可以直接 push。

### 第三方審查資訊
{列出每個涉及的 repo，方便使用者轉交第三方 reviewer}

| Repo | 模式 | Commit 範圍 | 變更摘要 |
|------|------|-------------|----------|
| `repo-a` | diff | `abc1234..def5678` | {一句話：主要改了什麼} |
| `repo-b` | baseline | `∅..222bbbb` | {一句話：主要改了什麼} |

{模式欄填 diff / baseline（codex_base_mode）；commit 範圍用 `base..head` 格式，base 取審查起點（Step 1 判定的 base commit，baseline 模式為 empty-tree 以 `∅` 表示），head 取最終 commit}
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
{autofix 時}**測試 baseline**: {pass|fail|skip}{fail 時必加：——審查前測試已紅，全部 fix commits 為 `UNVERIFIED-BY-TESTS(baseline-red)`}

### 修復軌跡

| 輪次 | 問題數 | 修復數 | 根因與前輪重複？ | 說明 |
|------|--------|--------|------------------|------|
| R1 | {N} | {N} | — | {一句話：主要修了什麼} |
| R2 | {N} | {N} | {是/否：{同一條規則的另一個實例？修 R1 引入的？還是全新根因}} | {一句話} |
| R3 | {N} | {N} | {是/否 + 一句} | {一句話} |
| R4 | {N} | {N} | {是/否 + 一句} | {一句話} |
| R5 | {N} | — | {是/否 + 一句} | 未自動修復 |

### 收斂失敗分析
{為什麼四輪修不完——是修 A 引入 B？結構性問題反覆觸發？還是同一條規則的實例每輪只修一個？}
{必須落到下方「續跑分流」表的其中一列，並寫明判斷依據；只描述現象不給分流等於沒交付}

{**先看上表「根因重複」欄再下判斷——達上限本身不區分兩種相反情況**：各輪根因**重複**（同規則的實例逐輪擠、或修 A 引入 B）→ 真的越補越亂，屬收斂失敗。各輪根因**皆不重複**、且每條都有 reviewer 實證 → 屬**健康收斂**，只是變更本身複雜；此時分流傾向第一列（人工修完或換視角），**不要**建議結構性重寫——那是對後者過度保守。}

### 剩餘問題
（同未通過格式，按根因分組）

### Branch 狀態處置

目前 branch 上有 {N} 個 review fix commit（`fix: address review findings`）。

{根據剩餘問題的性質選擇建議}
- 若建議重寫 → 執行 `~/.claude/skills/deep-review/scripts/review-anchor.sh squash-cmd --repo <r>`，把 `squash-cmd:` 整行照抄執行（`reset --soft` 到腳本算出的 squash base——**它通常不等於上方 `anchor:` 那行的 hash**，兩者不同是正常的，見 SKILL.md 錨點段）把 review 產生的修補收回 index，帶著它們重新設計 {區塊}，再重新 commit。**保留下來的語意 commit 仍在 branch 上**（reset 不會回到「什麼都沒做」的起點）。**腳本回 `verdict: STOP` 就停下交使用者，勿自行湊 hash**——它擋的是 hash 已 GC 或已非 HEAD 祖先（review 期間 rebase／換 branch）的情況，硬 reset 會把不屬於本次審查的 commits 一併攤進 index
- 若可繼續修 → 保留現有 commit，在此基礎上繼續人工修復，完成後 squash（同樣照 `squash-cmd` 輸出）

### 續跑分流

**本批變更的第 {cycle} 個 review 週期**（取 `review-anchor.sh record` 的 `cycle:` 行；未印即第 1 個）。

{勾選其中一列，並說明為何是這列——不可全列照抄}

| 剩餘問題的樣子 | 建議行動 |
|---|---|
| 有界、具體、彼此無關 | 人工修完再跑一次（變更集已不同，輪次重新計數合理）。**同一 reviewer 已跑滿五輪時，換視角常比再跑一輪划算**——剩下的是局部行為問題（補一個值、加一條守門）不代表該由同一雙眼睛再看：可人工修完後跑 `autocodex`，或照最後一列的 (b) 直接把 `base..head` 交外部 reviewer |
| 結構性：每輪修 A 就冒出 B | 照 `review-anchor.sh squash-cmd` 輸出 reset（目標取 `squash-cmd:` 行，**不是 `anchor:` 行**；STOP 就停，勿自湊 hash），帶著變更重新設計 {區塊}，別在補丁上疊補丁 |
| 收斂震盪：同一區塊來回、方向反覆 | 由使用者拍板固定一個方向再跑；不拍板則再跑幾輪結果相同 |
| 只剩深井／建議等級 | 判定為通過（走通過模板 + Non-blocking follow-up），不應進入此終止報告 |
| 難以判定，且 `cycle` ≥ 2 | **換視角而非換輪次**。注意：**此刻直接跑 `/deep-review autocodex` 到不了 codex 階段**——SKILL.md Step 6 只在主 agent 審查通過後才進入，而現在的前提就是還有 blocking findings。兩條可行路徑：(a) 人工修掉剩餘 blocking → 主審通過後才跑 `autocodex`；(b) 不經 deep-review，直接把 `base..head`（取 `review-anchor.sh show`）交給外部 reviewer |

**再跑一次 `/deep-review autofix` 不是預設下一步**——同 reviewer 對同一批 code 再開一輪多半挖出同類型的東西，且輪次上限會隨新一場 review 重置。先照上表分流，再決定要不要續跑。
```

## 報告模板 — Codex 第三方審查通過

```markdown
## Codex 第三方審查 — 通過

**審查範圍**:
{每個 repo 的路徑和 commit range}

### Codex 審查軌跡

| 輪次 | 範圍 | Findings | True Positive | 修復 | 說明 |
|------|------|----------|---------------|------|------|
| C1 | 全量稽核 `∅..HEAD` | {N} | {N} | {N} | {一句話：主要修了什麼，或「全為 false positive」} |
| C2 | 增量 `<C1 HEAD>..HEAD` | {N} | {N} | — | 無 blocking findings |

{兩模式皆 C1 = 全審（diff 範圍 `<起點>..HEAD`、baseline `<empty-tree>..HEAD`）、C2+ = 增量 `<上輪 codex HEAD>..HEAD`，讓使用者一眼看出只在 C1 全審一次}
{若 C1 即無 true positive}
| C1 | {範圍} | {N} | 0 | — | 全為 false positive，無需修復 |

### Completeness 深井（non-blocking）
{codex 指出但屬深井、非本輪修復觸及的問題（見 `reviewer-brief.md`「Completeness 深井」節）。含兩種來源：baseline 基線 backlog（僅 baseline 模式）與 prose artifact 深井（不分模式——skill/.md/runbook 的措辭清晰度、「還可以更完整」類）。列出供使用者排優先序，不阻擋通過}
- [Backlog] {finding 描述} — {baseline 完整度類別：a11y / edge case / 測試覆蓋 …}
- [Prose] {finding 描述} — {措辭/完整度類，非事實錯誤、非夾帶指令 misbehave、非 cross-ref 斷掉}
{若無深井項則省略此區塊；diff 模式仍可能有 prose 深井，勿因模式略過}

### False Positive 記錄
{列出被判定為 false positive 的 findings 及理由，供使用者參考}
- [FP] {finding 描述} — {為何是 false positive}

### Commit 建議
{與通過報告相同——squash base 之上的 review fix commits（主 agent 審查階段 + codex 階段）壓成一顆，message 依 `squash-preserve:` 分流（無 preserve → 原始功能語意；有 preserve → 描述相對保留 commit 的增量）；`squash-note:` 列出的未納入者不自行擴大 reset}

主 agent 審查 + Codex 第三方審查皆通過，可以提交了。
```

## 報告模板 — Codex 第三方審查終止（C3 仍有 true positive）

```markdown
## Codex 第三方審查 — 終止（C3 仍有 true positive）

**審查範圍**:
{每個 repo 的路徑和 commit range}

### Codex 審查軌跡

| 輪次 | 範圍 | Findings | True Positive | 修復 | 說明 |
|------|------|----------|---------------|------|------|
| C1 | 全量稽核 `∅..HEAD` | {N} | {N} | {N} | {一句話} |
| C2 | 增量 `<C1 HEAD>..HEAD` | {N} | {N} | {N} | {一句話} |
| C3 | 增量 `<C2 HEAD>..HEAD` | {N} | {N} | — | 未自動修復 |

{diff 模式：C1 範圍 `<起點>..HEAD`、C2+ 範圍 `<上輪 codex HEAD>..HEAD`（增量）}

### 收斂失敗分析
{先區分剩餘 true positive 的性質：}
- **修復震盪 / 修復本身有問題**（修 A 引入 B、或修復未修對）→ 這才是真正的收斂失敗，屬本終止報告。
- **Completeness 深井（不分模式）**（codex 持續換角度挖出新 completeness 問題，非本輪修復觸及——baseline 模式的既有基線 backlog，或任一模式下 prose artifact 的措辭/完整度 nits）→ **不應走終止報告**。改判定為通過，把深井項列入通過報告的「Completeness 深井（non-blocking）」。C2+ 本就只該驗增量修復；深井不阻擋通過。

### 剩餘 True Positive
{列出 C3 中被判定為 true positive 的 findings}
- [TP] `file.py:42` — {問題描述} — {影響}

### False Positive 記錄
- [FP] {finding 描述} — {為何是 false positive}

### 建議下一步
{具體建議：手動修復剩餘問題後可再跑 `/deep-review autocodex`}

### Branch 狀態
目前 branch 上有主 agent 審查 fix commits + codex fix commits。修復剩餘問題後，一併 squash 成乾淨 commit。
```

## 報告模板 — Codex 第三方審查 blocked（救援階梯走完仍無報告）

**與終止模板的分野**：終止＝codex 審完了但沒收斂（有 findings、修不完）；blocked＝codex **根本沒審成**（拿不到報告）。兩者不可混用——blocked 沒有 findings 可列，硬套終止模板的「剩餘 True Positive／收斂失敗分析」會捏造不存在的結論。

**主 agent 審查結論不受影響**：Step 1–5 的通過結論照常成立，本報告只說明第三方審查未能取得。

```markdown
## Codex 第三方審查 — blocked（未能取得審查結果）

**審查範圍**:
{每個 repo 的路徑和 commit range}

### 發生了什麼

| 嘗試 | 動作 | 結果 |
|------|------|------|
| 1 | `run --round C{N}` | exit {4/5}｜{報告空／環境錯誤說明} |
| 2 | `resume --job-dir {dir}` | {無產出／未執行（環境錯誤不重試）} |
| 3 | `run`（fresh 重試一次） | {無產出／未執行} |

**job 目錄**：`{job dir}`（events.jsonl / stderr.log / stderr-resume.log 保留現場供事後診斷）
{exit 5 的環境錯誤發生在 job 目錄建立之前，此欄填「未建立」；診斷資訊取腳本印在 stderr 的那行}

### 判定
第三方審查 blocked，**非**審查未通過。已依協議在一次 resume + 一次 fresh 重試後停止，不再消耗額度。

### 主 agent 審查結論（不受影響）
{一句話：Step 1–5 的結論與 fix commits 狀態}

### 建議下一步
- 環境錯誤（exit 5）→ 先修環境（codex 是否在 PATH／repo 與 range 是否正確），再重跑 `/deep-review autocodex`
- 連續兩次無產出 → 視為環境問題，手動跑一次 `codex-exec-review.sh run` 觀察 stderr.log 再決定
- 不想等 codex → 直接以主 agent 審查結論收尾，squash 現有 fix commits

### Branch 狀態
目前 branch 上有主 agent 審查 fix commits（若有）。可逕行 squash，或待第三方審查補做後一併處理。
```
