# Dossier 規範 — repo-resident 專案檔案的角色與生命週期

> 單一來源:本檔定義 STATUS.md(dossier)的章節語意、維護時機、與其他檔案的分工。
> 模板:`~/.dotfiles/claude/templates/STATUS-template.md`。

## 目錄

1. 檔案角色分工
2. STATUS.md 章節語意
3. 維護時機(誰在何時寫哪一節)
4. 跨主機接續(git 為唯一媒介)
5. 生命週期與反模式

## 1. 檔案角色分工

| 檔案 | 角色 | 讀者 | 變動頻率 |
|------|------|------|----------|
| `README.md` | 對外說明(是什麼、怎麼裝、怎麼用) | 外部使用者 | 低 |
| `CLAUDE.md` | 慣例與指令(架構、工具、規則) | AI agent | 低 |
| `STATUS.md` | **dossier**:狀態+spec+決策+死路+里程碑(**歷史**) | 未來的自己、AI、下一任 owner | 中 |
| `docs/backlog.md` | **待辦**:技術債 + 已知缺口(**未結案**) | 排下一步的自己 | 中 |
| `docs/plans/*.md` | 帶日期的設計文件(spec 定稿) | 設計討論的存檔 | 寫後不改 |
| `docs/transfer.md` | 移交指南(見 transfer-guide-template) | 接手的同事 | 移交前 |

**dossier 與 backlog 分家的判準是生命週期,不是主題**(2026-08-15 立)。dossier 收的是**歷史**——
決策、死路、里程碑發生後只會蒸餾或歸檔,**壓得動**,所以量體門檻(`scripts/ship-state.sh` 的
`DOSSIER_MAX_*` 常數)對它有效。backlog 收的是**未結案狀態**——你只能把字數壓短、條目數不會少,
**直到真的把它做掉**。把壓不動的東西關進「當次收斂」的門檻裡,每次 ship 都會在同一半內容上
反覆磨:實測 dotfiles 的 STATUS.md 有 47% 是這兩節、26 條無一已解決,8 次 commit 落在門檻的
98–99.8%,而 2026-08-14 的治理計畫已量到「不可歸檔存量 72%,在不違反自身判準的前提下達不到
建議目標」。分家把結構下限降到只剩死路一節,門檻因此重新變得可達。

- **`docs/backlog.md` 刻意沒有量體門檻**——在新檔重設一套等於把問題原樣搬過來。治理靠關閉與
  歸檔慣例(見該檔檔首),機械面只保留章節完整性檢查(`backlog-flag:`),因為「整節被誤刪」
  在沒有尺寸 flag 當第二道訊號時**更靜默**(2026-08-06 dossier 實地事故的同型)。
- **STATUS.md 保留那兩節的標題與一行指標**,不刪標題:簽章與章節完整性檢查因此零改動,
  未分家的 repo **零回填**——沒有 `docs/backlog.md` 就完全不觸發 backlog 訊號。
- **分家不是必做**。小型／低產出的 repo 兩節留在 STATUS.md 完全合理;會需要它的訊號是
  **待辦節長期佔住預算、而全檔反覆貼著門檻**。

**Naming is exclusive.** `STATUS.md` means the dossier and nothing else. Domain artifacts
(e.g. crawler-config checklists) MUST use another name (`CRAWL-CONFIG.md`). A file named
STATUS.md that is not a dossier will be mis-consumed by tooling and humans alike.
偵測面:`/project` 的 `ship-state.sh` 以雙訊號「簽章」判定(「進行中」章節 + 任一 dossier
專屬章節,缺一 → `dossier-flag: 簽章不符`),spec 模式遇之停下告知、不覆寫。

## 2. STATUS.md 章節語意

- **進行中**:每個工作項含 spec 區(Context / Goal / AC / Constraints)+ 進度 + 下一步。
  spec 區是給 AI 的工作合約——任務描述得夠清楚,agent 的工作就從「猜意圖」變成「執行合約」。
- **關鍵決策(附理由)**:選了什麼、為什麼、放棄了什麼。沒有理由的決策會被未來 session 翻案。
- **死路**:試過但放棄的路 + 原因。dossier 最值錢的一節,防重工。
- **技術債**:欠什麼、影響範圍與償還時機,供排序。**已分家的 repo 只留一行指標**,
  條目寫進 `docs/backlog.md`「技術債」。
- **已完成(里程碑)**:附日期與 commit/PR 對應。
- **已知缺口**:功能面或資料面的已知限制,尚無解決計畫者。**已分家的 repo 同技術債**,
  條目寫進 `docs/backlog.md`「已知缺口」。
  ⚠️ 對一條缺口做出「決定先不做＋重議條件」的決議時,**那是決策語意,搬回關鍵決策節**——
  待辦沒有出口、決策有(2026-08-14 已有六條這樣歸位過)。
- **移交準備度**:輕量 checklist,平時可空;`/project transfer` 的檢查依據。

## 3. 維護時機

| 時機 | 動作 | 執行者 |
|------|------|--------|
| 開工(非 trivial 工作項) | spec 區寫入進行中章節 | `/project spec` 或對話中直接編輯 |
| 工作中發現死路/做出決策 | 對話一句話順手記入 | 主 agent(不需 skill) |
| 工作中發現債/缺口 | 記入 backlog(未分家的 repo 記入 STATUS.md 對應節) | 主 agent(不需 skill) |
| 償還債/補上缺口 | backlog 條目**整條移除**,成果一行寫進里程碑 | 動手當下 |
| ship 收尾 | 本次的決策/死路/里程碑同步;進行中項收斂 | `/project log`(Step 2) |
| 移交前 | 完整度檢查 + 產出移交指南 | `/project transfer` |

記錄時點:**事件當下 > 收尾補記**——決策/死路/坑在發生當下就地寫入(working tree 即可、不需 commit,收尾由 `/project log` 一起送出)。Do NOT defer dossier notes to ship time: context may be compacted before then — a decision not written down when made is a decision lost. ship 收尾的 Step 2 因此是「核對補漏」而非重建。

## 4. 跨主機接續(git 為唯一媒介)

Machine-local state (handoff, memory) does NOT travel between hosts. The repo does.

- 跨主機要延續的工作狀態 → 寫入 STATUS.md「進行中」的**下一步**,commit(WIP 走 feature branch)。push 屬對外動作,依全域規則由使用者確認(或走 `/project log` ship)——**未 push 前其他主機不可見,必須向使用者主動標示**。
- handoff(`~/.claude/handoffs/`)只服務**同主機**的 /clear 交接;跨機內容進 repo、handoff 留 pointer。
- 開工前的落後偵測由 SessionStart hook(`session-pull-check.sh`)負責——看到落後提醒先 pull。

## 5. 生命週期與反模式

STATUS.md 是**就地演化**的常駐檔:進行中項完成後移入里程碑、下一步隨進度改寫。
它的 git history 就是 audit trail。

**總量治理(compaction)**——各節單調成長,靠修剪維持訊號密度;`/project log` Step 2 順手檢查
(偵測訊號與門檻常數的單一來源是 `scripts/ship-state.sh` 的 dossier 偵測,本檔只講語意與處置,
下文門檻數字為當前值的說明性引用、以腳本為準):

- 「進行中」項完成即移入里程碑(一行化);⏸️ 項保留但須註明暫停原因與重啟條件。
- **傘狀工作項中途蒸餾**:「進行中」的長工作項若含多個逐一 ship 的子里程碑(如 MVP 衝刺的
  M1/M2/…)——子里程碑 merge 當次,其進度敘事就地收斂為 1–3 行(結果+關鍵指標+PR/commit 指向),
  全史沉 git history;里程碑節已有對應條目時,「進行中」不得保留該子里程碑的全量敘事(雙重記載)。
  不等傘收攏才蒸餾(實證:evint 的 MVP 傘下 M1–M6 已 merge,全量敘事滯留「進行中」與里程碑雙重記載)。
- 決策條目記「選了什麼、為什麼、放棄了什麼」的**結論**;推導過程、eval 數字演進、迭代史沉
  git history。過季且不再影響現行方向的決策 → 合併壓縮或歸檔(同里程碑規則)。
- 被推翻的決策**保留原文並標記失效**,不刪、不就地改寫;**死路不刪**(防重工的本體,
  只在確認不再適用時移除)。格式:

  ```markdown
  - ~~**YYYY-MM-DD <原決策>**:<原決策原文>~~
    **已失效(YYYY-MM-DD)**:<推翻理由>;現行決策見 `<path>`「<section>」。
  ```

  刪除線劃在**原決策**上,不是劃在失效通知上(那個視覺語意變成「這則通知被劃掉」)。四條硬規則:
  ①原決策文字保留——就地改寫會讓「曾經怎麼想、為什麼改」消失,而那正是防止**第三次**翻案的
  東西(先例:`docs/project-spec.md` 檔首早已自行採用失效標記,理由同此:不回寫等於讓被推翻的
  條文以現況之姿被讀);②推翻理由另寫,不併進原文;③現行決策須有獨立條目或明確權威指標;
  ④指標須寫成 `` `path`「section」 `` 形狀——dotfiles 的 `tests/xref-gate.py` 掃得到,
  **其他 repo 目前無此 gate**(規範全域生效、機械保障僅 dotfiles),形狀一致是將來擴大時零回填。
- 全檔 > 300 行**或 > 24KB** 是硬訊號,當次 ship 就收斂,不留待「下次再整理」。量測已下沉腳本
  (條目/最長行 bytes、**超標條目行號**、**建議收斂目標**、超標時的**各節佔比**)——flag 出現即
  當次處置、照 flag 訊息做。兩個判斷腳本替不了:
  - **手段**:條目超標不必然是話太多,更常是**粒度過粗**(一條記了多個決策)。
    **If an entry covers more than one decision, split it — compression is the wrong tool.**
    (實證:krepo 2026-07-28 一條 1,544B 決策條壓兩輪都不過,拆成兩條後各約 420B 自然達標)
  - **收斂對象**:動手前先看 `dossier-sections:`,別憑印象猜哪節肥
    (實證:krepo 2026-07-29 憑印象挑里程碑節開刀,一輪 PR 只省 905B——真正的大戶是決策 30%+進行中 25%)。
- 存量 STATUS.md 若有規範外章節(如 Session Log):精華蒸餾進決策/死路/里程碑,
  全文歸檔 `docs/archive/`(先例:krepo 2026-07-17 收斂,599→~210 行)。

**Anti-patterns(hard rules):**

- **NEVER leave a ✅-done item under 進行中** — done means moved to 里程碑, one line.
- **NEVER write mega-line prose** — a 2,000-char single line defeats the line gate, diff
  readability, and review(observed: evint 117 lines / 38.7KB read as "small" by `wc -l`).
  The script flags it; if wrapping alone would clear the flag, the entry needs distillation,
  not wrapping.
- **NEVER add an append-only log section (Session Log etc.) to a dossier** — that is what
  git history is for; observed failure: krepo's Session Log grew to 60% of the file.

- **NEVER commit a throwaway handoff file into the repo**(HANDOFF.md → commit → delete → commit
  churn)。Cross-host state goes into STATUS.md in place. The observed failure mode: a consumed
  "recovery" STATUS.md left rotting for months(general-rag-cs, frozen at a ✅ done state)。
- **NEVER let STATUS.md freeze while the repo moves on.** The hook reports staleness > 30 days;
  `/project log` reminds on ship. A stale dossier is worse than none — it asserts false state.
- **Do not duplicate what git already records.** 進度細節、diff、檔案清單留給 commit;
  STATUS.md 記 git 推不出來的東西:為什麼、放棄了什麼、還欠什麼。
