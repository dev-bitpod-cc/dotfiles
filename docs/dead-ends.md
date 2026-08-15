# 死路 — 完整推導與證據

`STATUS.md`「死路(試過但放棄——防重工)」各條的**推導過程、實測數字、eval 編號與事故細節**。
結論本體在 STATUS.md（always-on），本檔是**想重走那條路時**才需要讀的那一半。

## 分工

| 問題 | 權威 |
|---|---|
| 這條路能不能走、為什麼不能 | `STATUS.md`「死路(試過但放棄——防重工)」 |
| 當初怎麼判的、跑了什麼、數字是多少、什麼條件下結論會翻 | **本檔** |

**本檔是延遲載入的。** 凡是「動手之前就必須知道」的判準留在 STATUS.md ——
死路的價值在於**你沒想到要查的時候擋住你**，規則不在 always-on context 就不生效。
本檔存在的目的是**省下重新評估與重跑實驗的時間**，不是承接判準。

> 切分模式與先例見 `claude/known-hazards.md`「分工」——該檔對 `claude/CLAUDE.md`
> 的「已知地雷」做的是同一件事（always-on 留規則、按需留案例），比例約 1:1。

---

## mc 當遠端檔案管理器

放棄理由是**協定層而非偏好**：

- mc 的 `sftp://` VFS 走內建 libssh2，**不支援 OpenSSH 使用者憑證**，而內網主機一律
  cert 認證（`id_autogen-cert.pub`，principal `jjshen`），等於主要路徑不通。
- 可用的 `fish://` 雖外呼真 ssh 能吃 cert，但每個操作起一次遠端 shell，且 macOS 還要
  處理 F1–F10 被 Mission Control 攔截、subshell 不繼承 cwd。
- 同樣需求 `lftp` 的 sftp backend 預設就外呼 `ssh -a -x`（已實測 `set -a` 確認），
  cert 與 `~/.ssh/config` alias 原生生效，無這些摩擦。

**結論會翻的條件**：libssh2 支援 OpenSSH cert 之後才值得重評，否則結論不變。

## worktree 的 SKILL.md 複製到主 checkout

想在合併前跑「需要 skill 真的被載入」的驗證時（如 ready4quit Q4c 要開新 session 觸發
`/ready4quit`）會很想這麼做。放棄理由三條：

1. 主 checkout 有其他 writer。
2. `brewup` 會在 pull 前丟棄未提交改動，那份複製隨時被吃掉。
3. 最要命的是**「測的到底是哪一版」變得不可考**——與這些 skill 自己在防的「證據對不上
   結論」完全同型。

**正解**：先合併、主 checkout pull 之後再驗。

## 依外部提案改 handoff 的 W1

2026-08-12 收到一份提案，診斷「W1 的『涉及』被讀成『我改過的 repo』」是實地事故（交接檔
漏 anchor 擋著下一步的 repo）的根因，並提議在寫入端加判準。

**跑了三輪 eval（H11 兩輪 + 最忠實的 H11b 變體）全部 GREEN 而放棄**——H11b 裡 Sonnet 只
anchor「唯一會解封下一步的外部依賴」、主動排除已交割的 repo，那正是提案想寫進 W1 的判準。
依 Iron Law（no failing eval, no skill change）不改 body；真正紅的是讀取端（H12），修補
因此落在 R3。

H11/H11b 已留為迴歸哨兵並在 `evals.md` 標明不對應任何條款。日後若寫入端事故復發，
**先讓 fixture 紅起來再動 W1**，不要憑實地印象直接改。

## 無 observed RED 的明示規則

2026-08-13 一天內加了兩條、當天全撤（同形狀第三次；先例是 2026-08-05 的外部取證條款）。
**共同形狀：RED 來源本身證明了規則不必要**，判準是**成對實驗**：

| 撤掉的規則 | eval | 為什麼不必要 |
|---|---|---|
| 「不要照抄 dotfiles 檔名」 | d10 | baseline 臂一樣做對——既有規則「該 repo 的機制」本來就接得住 |
| 「`verification:` 欄不減免獨立驗證」 | d11 / F24 | 同上，既有規則「逐條獨立驗證、不預設 findings 正確」接得住 |

②在撤除前當天確實**實地觸發過**（codex 標假的 `executed`），看起來像該留；正確的問法是
**既有規則接不接得住**。保留的只有「把 body 陳述錯的事實改對」那半（修正錯誤陳述不需 RED）。

撤下的情境留成**回歸測試**、在 `evals.md` 標明不對應任何 body 條款，防反向放寬。
逐條細節見 `deep-review/evals.md` 執行紀錄。

**2026-08-14 第四次，但這次流程贏了。**「已決議暫不做屬決策節、不是已知缺口」這條判準，在寫進
`dossier.md` **之前**先建 u6 沙盒跑成對實驗（`project/references/pressure-tests.md` Scenario 17），
v2 四輪兩臂零差異——baseline 自己就把現況缺陷放缺口、把決定不修放決策並交叉引用，判準因此沒寫。
前三次都是寫了才撤，這次是**先測再決定**；差別在於前三次有「實地出過事」的印象在推，這次刻意
先讓 fixture 說話。⚠️ 順帶推翻了自己的診斷：實測顯示 Sonnet 分類分得很清楚，所以缺口節那 8 條
的滯留**不是寫入時分錯**，較可能是「先寫成缺口、後來做了決定卻在原地追加而沒搬家」——新假設
待測，情境設計見該 Scenario 尾。

## STATUS.md 負增量當壓縮代理

2026-08-14 調查「dossier flag 一直觸發」時用過，結論全錯。把「STATUS.md 變小」一律當成
「被 flag 逼著壓縮」，於是 krepo 的 29 次負增量被讀成 29 次痛。實際分解：

| 成因 | 例 |
|---|---|
| 拆分搬移 | `-48431` 史料歸檔、`-5763` 歸檔重訊史料（cutover 後第一批分割） |
| 正常生命週期 | `-1055` 兩項驗收全綠、該項收出進行中 |
| **真由 flag 驅動** | 只有 `-630` 與 `-779` 兩次，且都是**條目** flag、不是量體 |

而它的量體 flag 早在 2026-07-31 就明文豁免（該 repo 的契約檔裡有一節叫「dossier 量體門檻」，
理由是「為門檻加工一個即將被切開的東西是無效工」）。代理指標差點導出「krepo 需要一次性
整頓」這個**被該豁免條款指名為無效工**的結論。

**正解**：數 flag 實際處置的 commit，並先查該 repo 自己的契約檔有無豁免——量體訊號本身
不分辨「誰讓它變小」。

## 移交出去的 repo 內放 dossier 規範精簡版

2026-08-10 設計時提出並否決（`docs/dossier.md` 形態）。三條理由：

1. **G1b 實測非自動載入的檔不會被讀**，它與 `AGENTS.md` 同一失效面。
2. 散到 N 個 repo 後零機械守門（`kernel-gate.py` 只守 dotfiles 四檔），規範一改就全部
   stale 而**沒人會發現**——最壞是接手者的 agent 照舊版把刪除線劃在失效通知上，
   **交出去的東西主動教錯**。
3. 常駐檔會腐爛（`docs/transfer.md` 不腐爛正因它移交前才生成）。

**正解是既有落點**：STATUS.md 自己的檔頭註解 + 該 repo 的 `CLAUDE.md`。

## rollup ＋ jq 計數判 CI 狀態

2026-08-15 拆 `/project` 分流表的 `BLOCKED` 時提出並否決（原方案：
`gh pr view --json statusCheckRollup` 加兩條 jq 計數，一條數「未 COMPLETED」、一條數
`FAILURE`）。改用 `gh pr checks --required` 的 exit code（0 全綠／8 pending／其他非零 失敗）。

三條理由，前兩條實測、第三條未測：

1. **rollup 單筆沒有 `isRequired`**。實測欄位只有 `__typename` / `completedAt` / `conclusion` /
   `detailsUrl` / `name` / `startedAt` / `status` / `workflowName`。於是必要與非必要 check 分不開，
   造成**雙向誤判**：非必要 check 還在跑 → 空等；非必要 check 失敗 → 誤停。**那正是本批要修的
   誤診，只是換了個方向。** `--required` 這一項在 rollup 上做不到，這條單獨就足以否決。
2. **同名 check 會有多筆**。krepo PR #129 的 rollup 有兩筆 `unit-tests`（workflow run
   `31823269093` 與 `31823359889`），**merge 完成後仍是兩筆**——被取代的 run 不會從清單消失，
   任何純計數法都必須自己去重。
3. **rollup 是混型別的**（key list 含 `__typename`）：GitHub Actions 的 check run 用
   `status`/`conclusion`，legacy commit status 用 `state`/`context`。若如此，
   `select(.status != "COMPLETED")` 對後者**恆真** → 永遠判成「還在跑」。**此條未實測**
   （手邊沒有 legacy status 的 repo），但 `gh pr checks` 會正規化兩種型別，採用它就不必賭。

**結論會翻的條件**：GitHub 在 rollup 節點上補 `isRequired`（第 1 條消失）。屆時仍要處理第 2、3 條。
