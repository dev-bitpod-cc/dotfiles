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
| `STATUS.md` | **dossier**:狀態+spec+決策+死路+債 | 未來的自己、AI、下一任 owner | 中 |
| `docs/plans/*.md` | 帶日期的設計文件(spec 定稿) | 設計討論的存檔 | 寫後不改 |
| `docs/transfer.md` | 移交指南(見 transfer-guide-template) | 接手的同事 | 移交前 |

**Naming is exclusive.** `STATUS.md` means the dossier and nothing else. Domain artifacts
(e.g. crawler-config checklists) MUST use another name (`CRAWL-CONFIG.md`). A file named
STATUS.md that is not a dossier will be mis-consumed by tooling and humans alike.

## 2. STATUS.md 章節語意

- **進行中**:每個工作項含 spec 區(Context / Goal / AC / Constraints)+ 進度 + 下一步。
  spec 區是給 AI 的工作合約——任務描述得夠清楚,agent 的工作就從「猜意圖」變成「執行合約」。
- **關鍵決策(附理由)**:選了什麼、為什麼、放棄了什麼。沒有理由的決策會被未來 session 翻案。
- **死路**:試過但放棄的路 + 原因。dossier 最值錢的一節,防重工。
- **技術債**:欠什麼、影響範圍與償還時機,供排序。
- **已完成(里程碑)**:附日期與 commit/PR 對應。
- **已知缺口**:功能面或資料面的已知限制,尚無解決計畫者。
- **移交準備度**:輕量 checklist,平時可空;`/project transfer` 的檢查依據。

## 3. 維護時機

| 時機 | 動作 | 執行者 |
|------|------|--------|
| 開工(非 trivial 工作項) | spec 區寫入進行中章節 | `/project spec` 或對話中直接編輯 |
| 工作中發現死路/做出決策 | 對話一句話順手記入 | 主 agent(不需 skill) |
| ship 收尾 | 本次的決策/死路/債/里程碑同步;進行中項收斂 | `/project log`(Step 2) |
| 移交前 | 完整度檢查 + 產出移交指南 | `/project transfer` |

## 4. 跨主機接續(git 為唯一媒介)

Machine-local state (handoff, memory) does NOT travel between hosts. The repo does.

- 跨主機要延續的工作狀態 → 寫入 STATUS.md「進行中」的**下一步**,commit(WIP 走 feature branch)。push 屬對外動作,依全域規則由使用者確認(或走 `/project log` ship)——**未 push 前其他主機不可見,必須向使用者主動標示**。
- handoff(`~/.claude/handoffs/`)只服務**同主機**的 /clear 交接;跨機內容進 repo、handoff 留 pointer。
- 開工前的落後偵測由 SessionStart hook(`session-pull-check.sh`)負責——看到落後提醒先 pull。

## 5. 生命週期與反模式

STATUS.md 是**就地演化**的常駐檔:進行中項完成後移入里程碑、下一步隨進度改寫。
它的 git history 就是 audit trail。

**Anti-patterns(hard rules):**

- **NEVER commit a throwaway handoff file into the repo**(HANDOFF.md → commit → delete → commit
  churn)。Cross-host state goes into STATUS.md in place. The observed failure mode: a consumed
  "recovery" STATUS.md left rotting for months(general-rag-cs, frozen at a ✅ done state)。
- **NEVER let STATUS.md freeze while the repo moves on.** The hook reports staleness > 30 days;
  `/project log` reminds on ship. A stale dossier is worse than none — it asserts false state.
- **Do not duplicate what git already records.** 進度細節、diff、檔案清單留給 commit;
  STATUS.md 記 git 推不出來的東西:為什麼、放棄了什麼、還欠什麼。
