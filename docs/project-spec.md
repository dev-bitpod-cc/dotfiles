# project skill 規格書（需求層蒸餾快照）

> **快照基準**：project skill @ commit 25aca11（2026-07-21）。
> **定位**：clean-room 重寫實驗產出的需求層蒸餾——描述**目標、硬需求、環境事實**，
> 不描述實作機制。**Non-normative**：skill 演進不回寫本檔（避免 double-source；**唯一例外＝『本條已被推翻，見 X』的失效標記**——不回寫等於讓被推翻的條文以現況之姿被讀，比 double-source 更危險；
> 實作的單一權威恆為 `claude/skills/project/`）。
> **用途**：skill 的第一份需求層文件；重大重構或移交時的規格參照；附錄記錄「只活在實作裡」的知識缺口。

## 任務

為 Claude Code 設計並撰寫一個名為 `project` 的 skill。交付物：

1. 完整的 `SKILL.md`（含 frontmatter：name、description、user-invocable、
   disable-model-invocation、argument-hint、allowed-tools）
2. 若設計需要支援檔案（腳本、reference 文件），為每一個寫出**規格**：檔名、職責、
   介面（引數 / 輸出格式 / exit code 契約）、為何需要它。

## 目標

以 repo 內的 STATUS.md（稱 dossier）為專案單一事實來源，覆蓋一個工作項的三個時點：

1. **spec（開工）**——把要做的事從「願望」變成可執行的工作合約（Context / Goal /
   Acceptance Criteria / Constraints），寫入 dossier。
2. **log（收尾送出）**——把（通常已通過 review 的）變更收尾：同步 dossier 與受影響
   文檔、依 Conventional Commits 提交、依 repo 的 branch-protection 流程 push 或開 PR。
3. **transfer（移交）**——檢查 dossier 完整度、產出移交指南，供專案換 owner。

使用方式：使用者輸入 `/project [spec|log|transfer] [repo|.] [module...]`。
> ⚠️ **本條的 `[module...]` 已被推翻**（2026-08-07，見 `claude/skills/project/references/log-workflow.md`
> 「引數前處理（依形狀分類，不靠優先序記憶）」）：裸字不再被當成 module 過濾——它會在打錯字時靜默縮小
> Step 2 的掃描範圍。**module 一律走路徑形式**（`./docs/plans`）。同時新增 `--` flag 形式
> （`--merge` / `--pr` / `--no-pr` / `--spec|--log|--transfer`），與裸說法等價。
無模式引數 → 預設 log（與歷史指令 `/uap [repo|.] [module...]` 的肌肉記憶相容）。

## 功能需求

### F1 模式分派與引數
- 第一個 token 分派模式；其餘 token 傳給該模式
- 非模式 token 開頭 → 整串當 log 模式引數（向後相容）
- repo token 的判定要能吃：`.`、絕對/相對路徑、含 symlink 的路徑、session 記憶中的
  repo 名——並且**不得把 module 子路徑（含 `/` 的 scope，如 `docs/plans`）誤判為 repo**

### F2 Log 模式——範圍鎖定
- 明確 repo 引數 → 直接鎖定，跳過互動
- 無 repo 引數 → 依 session 記憶列出候選 repo 清單讓使用者確認；**絕不掃描全目錄樹**
- 支援多 repo 同輪 ship（逐 repo 偵測、逐 repo 送出、最後彙總）

### F3 Log 模式——狀態與流程偵測
每 repo 需在動手前得知：當前 branch、canonical remote、default branch、變更集
（branch 相對 default 帶來的檔、領先的 commit、working tree 髒檔）、是否有誤 commit
在本地 default、branch protection 狀態、該走的 ship 路徑、是否需要 branch-first。
- 變更集語意 =「此 branch 相對 default 的變更」（= PR 將包含的內容），不等於「未 push」
- git 完全無變更時**不得直接收工**——session 記憶中有本輪已 ship 的變更時，
  文檔可能落後（docs-only 情境），需以已 ship 的 commit 重建變更集、只跑文檔同步

### F4 Log 模式——active/history/backlog 與文檔同步
- 由變更集識別受影響模組：`STATUS.md` 只同步 active／paused；decision、dead end、milestone 寫入
  event-month history shard；未結案項同步 `docs/backlog.md`
- 防禦原則：先讀、只改相關段落、無需更新就跳過，不硬塞
- adopted repo 以 repo-local `audit --ship` 為唯一 doc verdict；完成項不得留在 active/backlog，history
  record 守 stable ID、event date 與 shard。Legacy repo 才沿用既有 dossier detector

### F5 Log 模式——提交
- 送出前 reviewed code 必須全部已 commit（不留 code 在 working tree）
- code 未 commit → code+docs 同語意 commit；code 已 commit → 文檔獨立 docs commit
  同 branch；**不 amend、不重寫已 review 的 commit**
- mixed state（部分已 commit、部分在 working tree）→ 先把 code 補成語意 commit

### F6 Log 模式——送出
- 送出前印逐 repo 的 ship 摘要（路徑、branch、變更檔、待決事項）等使用者確認
- 待決事項（squash 建議、dossier 建立/過期、是否開 PR）彙整進摘要一次問，
  不逐項中斷流程
- PR 路徑：push feature branch → 偵測既有 PR → 無則開新 PR（title/body 由 commits 組）
- 直接 push 路徑（僅確定無保護）：仍推 feature branch，附帶提示可開 PR
- 使用者後續明說 merge → 執行標準收尾（merge → 清 branch → 同步本地 default），不得因通篇「絕不 merge」而拒絕明確授權
  > **2026-08-06 更新**：預設 `--squash` 已被推翻——壓不壓改關鍵字分流／選項式詢問，且 merge 授權可在 Step 4 第 1 題預先給。現況見 `claude/skills/project/references/ship-paths.md`「說法表」；歷史理由用 repo-local `find` 查詢。

### F7 Spec 模式
- adopted repo 先用 repo-local `find` 查相關 decision／dead end，把命中 ID 寫入 active 關聯；不得先全讀 archive
- 無 active state → 從模板建立；已存在但撞名為領域產物 → 停下告知，不覆寫
- 與使用者釐清後寫入 active spec；模糊處直接問、不猜
- 只寫 spec、不動 code、不 commit

### F8 Transfer 模式
- adopted repo 評估 active／paused、history IDs、backlog 與 `find` 可定位性並跑 audit；legacy repo 依既有權威
- credentials 盤點（.env.example 覆蓋度、無硬編碼 secrets）
- 從模板產出移交指南；待決策事項留給移交雙方拍板，不代填
- 本模式不 push、不 merge、不改 repo 權限

## 硬需求（Hard requirements — 違反即設計不合格）

- **H1 確認 gate**：push 之前必印 ship 摘要並取得使用者明確確認；無確認即停。
- **H2 絕不直推 default branch**：不論 protection 狀態，送出的一律是 feature branch。
- **H3 絕不擅自 merge**：開 PR ≠ merge；merge 僅限使用者明說。
- **H4 Branch-first 無條件**：需要 commit 而 HEAD 在 default branch（或 detached）時，
  **commit 之前**先建 feature branch——與 protection 無關，protection 確認關閉也一樣。
- **H5 Unknown = protected**：protection 偵測不到（無 gh、無權限、網路失敗）一律視為
  受保護、走 PR 路徑；不得詮釋為「大概沒保護」。
- **H6 誤 commit 救援不得毀資料**：變更誤 commit 在本地 default（未 push）時的搬移
  序列絕不可能銷毀 working tree 的未 commit 變更（mixed state 是常態不是例外）；
  已 push 的 commit 不做 history 改寫救援。
- **H7 儀式可鬆、護欄不可鬆**：小變更可精簡互動儀式，但 H1–H6 一項不少。
- **H8 Credentials never in git**：移交流程中 secrets 值絕不落入 tracked 檔。
- **H9 偵測與 mutation 分離**：狀態偵測必須唯讀且可重複執行；會改 git 狀態的動作
  只在明確的決策點發生，且每一步可獨立驗證。

## 環境事實（Environmental facts — 實戰得來，設計必須容納）

- **E1 GitHub 保護有兩套**：classic branch protection 與 rulesets，只查其一會漏判。
  classic API 對「無保護」回 404 `Branch not protected`（即使 ADMIN 也是 404）；
  回 404 `Not Found` 則常是 gh 帳號無權讀 protection——兩種 404 意義完全不同，
  要靠訊息字串分辨。
- **E2 身分分離**：gh CLI 登入的帳號與 git push 用的 SSH 身分可能是不同 GitHub 帳號
  ——常見「gh 帳號 READ（讀不到 protection、開不了 PR）但 SSH key 有 write（推得動）」。
  「硬推會被 remote 擋所以無害」不成立：protection 對 gh 不可見但分支實際無保護時，
  硬推會成功。
- **E3 mixed state 毀資料路徑**：誤 commit 在本地 default + working tree 另有未 commit
  變更時，「切回 default 再 reset --hard」會永久銷毀未 commit 變更。安全序列存在
  （用 branch ref 保住 commit、不動 working tree），但步驟順序敏感——在壓力下手打
  容易做錯方向。
- **E4 detached HEAD 語意**：detached HEAD 上的 commit 不屬於任何 branch，
  `switch -c` 會把 working-tree 變更與 detached commit 一併帶走，不需 ref 重置。
- **E5 Model 手跑偵測會漂移且燒 context**：讓 model 每次臨場重組 git/gh 偵測指令序列，
  N 次執行有 N 種結果、每步吃 tool-call 往返；偵測必須單一來源、單次呼叫、輸出可直接
  引用。（先例：偵測腳本化後 tool calls 從十餘次收斂到個位數。）
- **E6 gh CLI 邊界**：`gh api` 的 path 佔位符只認 `{owner}/{repo}/{branch}`；多 repo
  操作時依 cwd 隱式解析會打到錯 repo，需顯式綁定；`gh repo view` 不吃 `-R`（與
  `gh pr`/`gh api` 不同）；default branch 名可含 `/`（需 URL encode）。
- **E7 remote 多樣性**：canonical remote 不一定叫 `origin`；有 fork 工作流（push 目標
  與 PR 目標是不同 remote）；有 local-only repo（無 remote，無從 ship）；host 可能是
  GHE。設計須明確界定哪些自動處理、哪些停下交使用者。
- **E8 裸 `git push` 不可靠**：受 `push.default` / `remote.pushDefault` / 非預期
  upstream 影響，可能推錯 remote 或多推 ref；push 一律顯式 remote + branch。
- **E9 skill 觸發機制**：本 skill 設為使用者親自 `/project` 觸發（description 不進
  model context）；「ship」「uap」等語意觸發由全域 CLAUDE.md 路由「建議使用者執行」。
  舊 `/uap` 使用者的肌肉記憶（裸指令 + repo 引數）必須繼續可用。
- **E10 與 review 流程銜接**：上游 `/deep-review` 的標準結尾是「feature branch +
  乾淨 squash commit + 未 push」；log 模式須把這個形態當一等公民（不重審、不重寫
  commit，只補文檔與送出）。

## 撰寫規範

- 先讀 `~/.dotfiles/claude/skill-building-guide.md`，遵循其結構與語言政策
  （硬約束用英文、程序步驟用繁中、description 中英並列）
- Skill 面向的執行者是 Claude Code agent 本身；寫給 agent 讀，不是寫給人的教學文

---

## 附錄：clean-room 比對實證（2026-07-21）

> 實驗方法：以本規格讓禁讀現有實作的 subagent 從零重寫，與現行實作（PR2 prose 下沉
> 進行中的版本）比對。時序同 PR1 先例——**盲寫先於下沉實作**，收成直接反映進同一輪重構。

**收斂處（機制被需求逼出）**：盲寫版獨立做出與現行相同的核心結構——單一唯讀偵測腳本
（E5/H9 逼出）、誤 commit 救援下沉為低自由度 mutation 腳本（E3/H6 逼出，含「先 switch
保 commit、再 branch -f 動非 checked-out ref」的同一安全序列與 reset --hard/stash 禁用
清單）、repo-token 判定用 toplevel 等值檢查（F1 的子路徑陷阱逼出）、衛生門檻單一來源、
Iron Laws 英文置頂 + rationalization table 反制「remote 反正會擋」話術。

**已回流的盲寫版知識**：porcelain 前後快照逐字比對（H6「不觸碰 working tree」的機械
驗證，進 branch-first.sh 後驗證）；ref 終態斷言（HEAD==feature、default==remote/default）；
dossier 簽章判定（F7 撞名偵測的具體判準——雙訊號：「進行中」＋任一 dossier 專屬章節，
缺一即非 dossier，進 ship-state.sh `dossier-flag: 簽章不符`；單訊號版被第三方審查抓出
誤放行方向的假陽性，誤放行＝直接編輯領域文件，比誤攔截危險）。

**合法設計分歧（已拍板，維持現行）**：

1. 盲寫版救援腳本帶 `--dry-run` 先看計畫 vs 現行直接執行——前置檢查全過才動、操作
   皆可逆（feature branch 可刪、default 可 branch -f 回去）、且 ship gate 在 push 而非
   本地 branch 操作，dry-run 多一步儀式，維持現行。
2. 盲寫版 KEY=VALUE 機器可讀輸出 vs 現行帶前綴標籤文字——沿用本 repo skill 腳本慣例
   （agent 整行引用），同 PR1 分歧 5，維持。
3. 盲寫版多 remote 一律 `blocked:multiple-remotes` 硬停 vs 現行 canonical + fork 提示
   續行、Step 4 摘要明列——常見的 origin+備援雙 remote 不該硬停，gate 已在 Step 4，維持。
4. 盲寫版過期判定「距今 >30 天且期間 ≥10 commits」 vs 現行「落後 repo 最新活動天數」
   ——現行公式對休眠 repo 自動免疫（repo 不動 lag 不長），少一個常數，維持。
5. 盲寫版 merge 最後一哩用 `branch -d` vs 現行「先驗 MERGED 再 `-D`」——squash merge
   後 `-d` 必誤判未 merge 而拒刪，盲寫版此處不可行，維持現行。
6. 盲寫版門檻數字放 reference 文件 vs 現行放 ship-state.sh 常數——腳本是可執行權威且
   有行為測試釘死，維持現行。
7. 盲寫版 `BRANCH_FIRST_NEEDED` 條件式（在 default 且有變更才要求）vs 現行「在
   default/detached 一律 REQUIRED」——docs-only mode 在 clean tree 下仍需先開 branch
   再落 docs commit，無條件版正確，維持現行。
8. 盲寫版救援拒絕用獨立 exit 4 vs 現行 STOP 一律 exit 1——維持本 repo 0/1/2 exit
   契約慣例，拒因寫在 verdict 訊息裡。

**規格未涵蓋、只活在實作裡的知識**（未來補進需求層或重構時優先確認）：
misplaced 偵測與 branch-first-cmd 照抄行的銜接（偵測印指令、model 填 type/slug）；
分岔（remote 已推進）判 STOP 的快進關係檢查；stale remote-tracking 的後果邊界
（「退回 remote」＝退回本地 tracking ref、可能落後實際 remote 但無資料損失路徑；
真分岔在 stale 下不可本地偵測，不在 STOP 保證內）；detached HEAD 一律歸情況 A 的理由
（不移動任何 branch ref）；docs-only mode 對 clean-tree repo 仍輸出全套 verdict 的
必要性；輕量 fast-path 的三條件判準與「鬆儀式不鬆 Critical」邊界。
