<!--
STATUS.md — 專案 dossier(單一事實來源:repo 內、隨 git 跨主機、隨專案移交)
維護時機:開工寫 spec(/project spec 或對話);ship 時由 /project log 同步;移交前跑 /project transfer。
規範全文:~/.dotfiles/claude/skills/project/references/dossier.md
-->

# STATUS.md

個人 dotfiles——5 台主機(macmini/macs/eagle03/eagle06/db01)開發環境與 Claude Code 工作流(skills/hooks/templates)的單一來源(更新日期:2026-07-17)

---

## 進行中

(無——殘項見「技術債」)

---

## 關鍵決策(附理由)

- **2026-07-16 git 為唯一跨主機媒介**:不同步 `~/.claude/`(handoffs/memory)跨機——同步衝突、錨點的跨機語意複雜化、敏感內容風險;krepo STATUS.md 已證明 repo-resident + git 這條路可行。
- **2026-07-16 `/project` 取代 `/uap` 而非並存**:雙入口=觸發混淆+double-source;`disable-model-invocation` 使鏈式呼叫不可行,只能複製防護邏輯(違反 single-source 紀律)。防護內容原文搬遷。
- **2026-07-16 STATUS.md 為 dossier 載體,不新建 PROJECT.md**:尊重 krepo 自然湧現且活躍維護的慣例;uap(現 /project log)本就維護此檔;避免同 repo 兩個角色重疊的檔案。
- **2026-07-16 不引入 Linear / 外部 tracker**:痛點(任務規格、結果回寫、跨 session 延續)由 repo-resident 檔案+既有 skill 生態覆蓋;缺的是慣例固化,不是新工具。
- **2026-07-16 settings.json 以 `opus[1m]` 為共享 model 基線**:本機一次性模型偏好(如 Fable 5)不 commit、不傳播五台。
- **2026-07-17 無 protection repo 的兩難以「merge 最後一哩」解,不走分級直推**:保留 branch+PR 正規流程練肌肉記憶;卡點在 PR 開完後沒人接,不在流程本身——使用者明說 merge 即由 agent 接手(squash+清 branch+同步 default),不打破 never-push-default 鐵律(分級政策會)、也不強推 protection(儀式成本)。
- **2026-07-17 dossier 記錄時點搬到事件當下**:/project「沒手感」根因是 skill 只在頭尾(spec/log)喚起,而決策/死路發生在過程中,等收尾 context 可能已壓縮——全域 CLAUDE.md 加即時記錄規則,log Step 2 從「回憶重建」降級為「核對補漏」。輕量判準與詢問收斂同理:儀式可減,Critical 不減。

## 死路(試過但放棄——防重工)

- **「/project log 包裝/並存 /uap」**:`disable-model-invocation` 下無法鏈式呼叫,只能複製 pressure-tested 的 ship 防護邏輯——違反 single-source;功能上與「uap 強化」完全收斂,故直接取代。
- **repo 內放一次性交接檔(HANDOFF.md commit→刪除循環)**:盤點實證 general-rag-cs 的已消費 STATUS.md 腐爛數月——跨機狀態一律走 STATUS.md 就地更新,已明文禁止(dossier.md anti-patterns)。

## 技術債

- [ ] R4 non-blocking 建議未修:新增 prose 的中文半形標點與既有全形混排;Transfer 模式 commit 紀律歸屬未明示;evals/README 路徑基準寫法;handoff evals H4 排序
- [ ] `settings.json` permissions.allow 有多條 `git push origin main` 放行,與各 skill「never push default」紀律方向有張力——另案檢視
- [ ] hook matcher 僅 `startup`(resume/clear 不重測落後)——擴不擴待拍板
- [ ] pressure-tests S8/S9 的沙盒未納入 `claude/evals/setup-sandboxes.sh`(2026-07-17 首輪為 ad-hoc 建置)——補腳本化以利重跑
- [ ] SessionStart hook 的落後提醒實際輸出未在真實落後 clone 驗過(tests 有覆蓋、實戰未見)——下次任一主機 clone 落後時順手確認
- [ ] /project 手感驗證:在 1–2 個活躍專案 repo 用 /project spec 建 dossier,跑完整 spec→實作(即時記錄)→log→merge 一輪;即時 dossier 記錄的判斷準確度以此輪觀察為據(該規則尚無 pressure-test)

## 已完成(里程碑)

- ✅ **2026-07-17 /project 摩擦修復 + 全機隊生效**(PR #1/#2):輕量路徑、詢問收斂、merge 最後一哩(PR #1/#2 即首戰實測,含 gh 雙帳號身分切換補救)、即時 dossier 記錄(全域 CLAUDE.md 規則);pressure-tests 新增 S8/S9 + 回歸 S1 Sonnet 全 PASS(git 實查)、tests 150/150;dotsync 14 台同步,多主機工作流(含 /project 三模式、pull 偵測 hook)全機隊生效。
- ✅ **2026-07-16 多主機工作流改造**(c673844):/project skill 取代 /uap、SessionStart pull 偵測 hook、dossier/transfer 模板、跨主機分流規則;deep-review autofix R1–R4(1嚴重5中等修畢)、沙盒 pressure-tests 5 情境 Sonnet 全 PASS。

## 已知缺口

- **Mac 上 `brewup` 會被 codex cask 掛死(Gatekeeper 首次執行核可)**:症狀是停在 `Linking Binary 'codex-aarch64-apple-darwin'` 後不動,Ctrl-C 才繼續。成因非 brew——codex cask 的第二個 artifact(Generated Completion)會實際執行 `codex completion bash/zsh/fish`,而 quarantine 過的新 binary 首次 exec 會彈出「codex-… 是網際網路下載的應用程式,確定要允許執行?」對話框,進程 0% CPU 停在 `_dyld_start` **同步等該對話框被回答**(kernel log:`ASP: Security policy would not allow process`);對話框常沒搶到焦點、被埋在其他視窗後,看起來就只是卡死。**解法:在對話框按允許**(已錯過/誤按取消 → 系統設定 → 隱私權與安全性 → 「仍要允許」),再 `brew reinstall --cask codex` 補完 completion 並清 `*.upgrading` 殘留(Ctrl-C 會讓 cask 裝一半)。**不要用 `xattr -d com.apple.quarantine` 或全域 `HOMEBREW_CASK_OPTS=--no-quarantine`**——核可即足夠(核可後 quarantine 屬性仍在、Gatekeeper 仍生效),那兩者是不必要的安全弱化。
  - **觸發條件**:僅在 codex **實際升版**時發生(對話框綁 binary CDHash 問一次,同版核可後不再問);codex 改版頻繁(0.144.1→0.144.5 僅隔數日),故每次升版重演。**順跑一次不代表免疫,只代表那次沒升 codex**(brewup 輸出無 `Upgrading codex` 那行)。僅 Mac(macmini/macs)受影響,Linux 三台無 Gatekeeper。
  - **`allup` 陷阱**:經 SSH 跑 brewup 時,對話框只會出現在該 Mac 的實體螢幕上,無人在機前就永遠沒人按 → 真正無限卡死(非逾時)。該 Mac 需先在本機核可過該版本。
- 爬蟲配置類 STATUS.md 撞名(npm-cs/knowledge-builder):源頭在 general-rag-cs template,改名(CRAWL-CONFIG.md)需動 template 腳本——另開工作項。
- biz-chat 移交檔三台路徑漂移(tmp/ vs handoff/,皆已 gitignored)+ credentials 明文散於三台。

## 移交準備度

(個人 infra,暫無移交打算——平時留空)
