# 里程碑歸檔 — 2026-08

> 從 `STATUS.md`「已完成(里程碑)」節歸檔（2026-08-06，總量治理；判準同決策節——已 ship
> 並固化在 skill / 腳本 / tests 者才搬出）。保留原文，不重寫。

- ✅ 2026-08-05 上兩批 git 紀律的第三方審查修復(3 blocking + 1 minor,全判 TP):`add -A`
  例外(禁令側與 `deep-review/SKILL.md` 使用點**兩處都寫**前置條件)、codex 自有 branch-first、
  STOP 與混檔技法的順序銜接、`clone --no-local` 補齊參數。
- ✅ 2026-08-05 跨 agent 所有權模型明文化(全域 `CLAUDE.md` 新增「跨 Agent 工作分配」節):
  writer 不限／ship 單一入口(現行 authority、非永久)／review 三層污染邊界／one writer per
  work item。查證發現「codex 只碰 `codex/`」**任何檔案皆無明文**——是慣例非規則,故本次寫的
  是**正面授權而非解除限制**;順帶補上 Claude 側缺失的 staging 紀律(三次 `git add -A` 誤收
  正是 Claude 在 ship 時犯的,規矩卻先前只立在 codex 端)。
- ✅ 2026-08-05 `codex/AGENTS.md` 補 Git discipline 節(never push/merge、禁廣義 staging、
  混檔拆分後乾淨 clone 驗證、ship 不自行實作)——補上 `danger-full-access` 下的持久 git 契約缺口。
- ✅ 2026-08-05 dossier 決策節 2026-07 歸檔至 `docs/archive/decisions-2026-07.md`:23 條原文
  搬出,24556→16444 bytes(-33%)、268→188 行,低於建議目標 20889;死路與技術債刻意不歸檔。
- ✅ 2026-08-05 repo-review 移植輪次上限的收斂診斷(codex 撰寫、Claude 代 ship):依根因重複/
  震盪 vs 各輪不同且前案仍修復來分類,禁止單憑上限推論架構問題;evals F21+tests 契約 gate。(565)
- ✅ 2026-08-05 deep-review 第三方回饋落地 + 輪次隱蔽缺口結案(#40):終止報告根因重複欄、
  R5 措辭修正;codex 三輪 4/4 TP 全修。外部取證判準同日撤除,見決策節。(564)
- ✅ 2026-08-05 codex repo-review 移植同批治理(#39):reviewer-brief 判準下沉、stage-neutral
  prompt 模板、pass 位置 orchestration-private(範圍比 deep-review 側更廣);evals F19/F20。
- ✅ 2026-08-05 deep-review 審查偏誤治理(#38):根因在**提問端**(主 agent 自行放寬 prompt),
  修法為判準下沉+白名單契約+輪次隱蔽;驗證三層與 codex 九條 findings 見其 `evals.md`。(547→564)

- ✅ 2026-08-06 handoff skill 優化:拿 archive 52 份實檔做統計,補上兩個高頻卻無規則的使用
  模式——同 slug 多輪續寫(約 40%)的死路承接、多 repo 錨點(27%)的逐 repo 對帳;`anchors`
  改記 toplevel 絕對路徑、`list` 補 path/title、新增 `find-predecessor` 子指令。H5/H6/H7
  三情境在 Sonnet 全 GREEN。第三方審查共兩個 cycle:merge 前 C1/C2/C3 抓 12 條(2 條屬 SSH
  工作項)、merge 後補審 `find-predecessor` 那批又抓 5 條(active 誤剝前綴、字典序選到 legacy
  舊檔、契約與實作不符、缺 eval、frontmatter 誤讀正文),末輪 No findings。`./tests/run.sh`
  592 PASS。

- ✅ 2026-08-06 squash/merge 決策改造:deep-review 收尾只壓 review 機械 commit(語意 commit
  保留,`squash-preserve:`/`squash-note:` 攤開)、round 改頂端連續段、merge 壓不壓改關鍵字分流
  + Step 4 第 1 題(`AskUserQuestion`)、review 痕跡偵測下沉 `ship-state.sh`(`review-residue:`)。
- ✅ 2026-08-06 上批的兩場 review 收斂(主審 R1–R5→終止→人工修→R1–R4 通過;codex C1–C3):跨
  Step 時序契約(Step 1 的 hash 是語意 commit 邊界、不得重算)、照抄行 shell quoting(路徑與
  ref 名過 `shq` + `--` terminator)、`--force-with-lease` 帶 expected SHA,以及一條**會
  `rm -rf` 掉整個 repo** 的測試防護漏洞。codex 7 條 findings 全 TP、零誤判。647 PASS。

