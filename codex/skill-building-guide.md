# Codex Skill 撰寫與迭代流程

本檔只記錄這套 dotfiles 的 Codex authoring policy 與發布流程。OpenAI 的通用規格由 system `$skill-creator` 與當下官方文件負責；不要複製全文到 repo。

## 何時使用 skill

先選擇最小且正確的持久化層級：

- 單次需求：留在 prompt 或 thread context。
- Repo 慣例、測試指令、review 標準：放最接近適用範圍的 `AGENTS.md`。
- Codex runtime 設定：放 `.codex/config.toml` 或全域 config。
- 可重複的任務工作流、領域知識、scripts 或 references：建立 skill。
- 需要分發多個 skills、connectors、MCP 或 hooks：建立 plugin。

不要用 skill 取代本來應該 always-on 的 repo guidance，也不要建立與 system skill 重複觸發的本機副本。

## 必要流程

### 1. 定義行為契約

在寫 prose 前先列出：

- 使用者會怎麼要求：positive、paraphrased 與 negative trigger examples。
- Skill 要改善的 observed gap 或必須守住的 safety contract。
- 可觀察的成功標準、失敗模式、輸入、輸出與不在 scope 內的行為。
- Existing skill 的既有 defaults、scripts、metadata、evals 與相容性契約。

若無法寫成可觀察行為，不要先新增規則。

### 2. 讀官方 authoring 指令

完整讀取 system `$skill-creator`。只有在 skill location、metadata、triggering、plugin distribution 或其他產品行為可能已更新時，才用 `openai-docs` 取得 current official guidance。

不要把遠端官方文件下載成 repo 內的必要副本。需要可重現的本機契約時，將實際依賴的行為寫成 eval，而不是複製說明文件。

### 3. 先建立 eval oracle

- 先用無 skill 或舊版 skill 重現 gap，保留 raw prompt、artifact、trace 或輸出。
- 每個需要修正的行為先新增會失敗的 eval；純措辭或 completeness 建議不得成為 blocking oracle。
- 至少覆蓋 triggering、核心功能與主要 failure/safety path。
- 複雜或紀律型 skill 加入 pressure scenario；不要把預期答案洩漏給執行 agent。

Evals 是 source of truth。Skill review 的 blocking line 是「agent 照做是否會做錯事」，不是 prose 是否還能更完整。

### 4. 選擇最小實作

- High freedom：多種方法皆可時使用簡潔文字與 heuristics。
- Medium freedom：有偏好流程但允許情境調整時使用 pseudocode 或參數化 script。
- Low freedom：脆弱、具破壞性或要求一致性時使用少參數 deterministic script 與明確 gates。

將核心 workflow 留在 `SKILL.md`。重複產生或需要 deterministic reliability 的操作放 `scripts/`；詳細領域資料放 `references/`；輸出模板或素材放 `assets/`。References 保持一層深，避免同一事實在 body 與 reference 重複。

### 5. 建立或修改 skill

- 新 skill 使用 `$skill-creator` 提供的 `init_skill.py`，建立在 `~/.dotfiles/codex/skills/<name>/`，讓跨機散佈仍以 dotfiles 為 source of truth。
- Existing skill 直接修改原目錄，不重新初始化。
- Frontmatter 只放 `name` 與 `description`；將主要 use case、trigger words、scope 與 boundaries 前置到 description。
- Body 使用 imperative/infinitive instructions，單檔語言保持一致，只加入 Codex 不會可靠推導出的程序或領域資訊。
- 保持 `SKILL.md` 精簡且低於 500 行。不要在 skill 目錄新增 README、changelog 或 quick reference。
- 若有 `agents/openai.yaml`，先讀 `$skill-creator` 的 `references/openai_yaml.md`，再用 generator 重建，避免 UI metadata 漂移。

### 6. 驗證

依序執行：

1. 實跑新增或修改的 scripts，包含正常、錯誤與 destructive gate 路徑。
2. 執行 `$skill-creator/scripts/quick_validate.py <skill-dir>`。
3. 執行 skill 自己的 behavior evals 與 repo tests。
4. 檢查 `git diff`，確認沒有 placeholder、重複規則、無關檔案或 stale metadata。

Validation 失敗就修正並重跑；不能把失敗留給未來使用者處理。

### 7. Blind forward testing

對 substantial 或高風險修改使用 fresh-context subagents：

- Prompt 要像真實使用者請求，讓 agent 直接使用目標 skill 解題。
- 只提供 task-local raw artifacts；不要提供 suspected bug、預期答案、 intended fix 或前一輪結論。
- 每輪重建乾淨 fixture，避免前一輪產物污染下一輪。
- 主 agent 依 eval oracle 驗證行為，必要時新增 failing eval，再做最小修正。

若只有看到洩漏 context 的 agent 能通過，視為 skill 或測試設計仍不完整。

### 8. 收斂與發布

停止條件是 behavior evals、validation、repo tests 與必要 forward tests 通過。不要反覆 adversarial review prose 追求零措辭 findings，也不要讓每輪修正只增加 body 長度。

發布模型：

1. Source of truth 留在 `~/.dotfiles/codex/skills/` 與 `~/.dotfiles/codex/AGENTS.md`。
2. Review verified diff，再 commit 與 push。
3. 執行 `dotsync`；各主機在 pull 後由 ensure helpers 幂等建立 `~/.codex/skills/<name>` 與 `~/.codex/AGENTS.md` symlink。
4. 抽查至少本機與一台遠端的 symlink target、內容 revision 與 skill discovery。

除非使用者明確要求 ship，本機 authoring／validation 不自動 commit、push 或 dotsync。

## 發布前 Checklist

- Trigger examples、negative boundaries 與 behavior evals 已存在。
- `$skill-creator` 已完整讀取；產品敏感事實已用 current docs 驗證。
- `SKILL.md` 聚焦單一工作、低於 500 行、無重複 reference 內容。
- Scripts 已實跑，metadata、skill validation、repo tests 全綠。
- Complex changes 已通過 fresh-context forward testing。
- Diff 只含預期檔案，未混入使用者或測試產物。
- 若要散佈，commit、push、dotsync 與遠端抽查均有明確授權。
