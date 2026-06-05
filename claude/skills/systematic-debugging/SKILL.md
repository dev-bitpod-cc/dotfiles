---
name: systematic-debugging
description: "系統化除錯 — 先找 root cause 再動手，杜絕亂槍打鳥式修補。Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes. Chinese triggers：「這個 bug」「test 一直失敗」「為什麼會這樣」「怎麼修都修不好」「debug」「卡住了」. Includes multi-component evidence gathering and backward root-cause tracing."
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Edit
---

# Systematic Debugging

## Overview

亂槍打鳥式修補浪費時間又製造新 bug；快速補丁只是遮住底層問題。

**Core principle: ALWAYS find root cause before attempting fixes. Symptom fixes are failure.**

**Violating the letter of this process is violating the spirit of debugging.**

> 本 skill 與全域規則「Bug fix 一律先寫能重現的 test，再改」一致——Phase 4 的第一步就是建立失敗測試。

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

沒完成 Phase 1，就不能提出任何修法。

## 何時使用

任何技術問題都適用：測試失敗、生產 bug、非預期行為、效能問題、build 失敗、整合問題。

**尤其在以下情況不可略過：**
- 時間壓力下（緊急時最想用猜的）
- 「就改一個地方應該就好」看起來很明顯時
- 已經試過好幾個修法
- 前一個修法沒效
- 你其實還沒完全搞懂問題

簡單的 bug 也有 root cause；趕時間時系統化反而比 guess-and-check 快。

## 四個階段（必須依序完成，不可跳階）

### Phase 1：Root Cause 調查

**動任何修法之前：**

1. **仔細讀錯誤訊息** — 別跳過 warning，完整讀 stack trace，記下行號、檔案路徑、error code。訊息裡常常就藏著答案。
2. **穩定重現** — 能可靠觸發嗎？確切步驟是什麼？每次都發生嗎？不能重現 → 蒐集更多資料，不要用猜的。
3. **檢查近期變更** — `git diff`、近期 commit、新依賴、設定變動、環境差異。
4. **多元件系統先蒐證**（見下方）
5. **追資料流** — bad value 從哪來？誰用 bad value 呼叫它？一路往上追到源頭。詳見 `references/root-cause-tracing.md`。

#### 多元件邊界蒐證（爬蟲 → 清理 → 入庫、API → service → DB、pipeline 各階段）

提修法**之前**，先在每個元件邊界加診斷，跑一次看「在哪一層壞掉」：

```python
import logging
log = logging.getLogger("debug-probe")

# 邊界 1：抓取
log.info("fetch done: url=%s status=%s bytes=%d", url, resp.status_code, len(resp.content))

# 邊界 2：清理
log.info("clean done: in_len=%d out_len=%d dropped=%d", len(raw), len(cleaned), len(raw) - len(cleaned))

# 邊界 3：入庫前
log.info("pre-insert: rows=%d sample_keys=%s", len(records), list(records[0].keys()) if records else "EMPTY")
```

先跑一次蒐證、看清楚是哪一層斷掉，**再**深入那個元件——而不是一開始就猜。

### Phase 2：Pattern 分析

1. **找可運作的範例** — 同 codebase 裡類似但正常的 code 長怎樣？
2. **完整比對參考實作** — 若在套用某 pattern，把參考實作**整段讀完**，不要只掃過。
3. **列出每一個差異** — 正常 vs 壞掉之間，再小的差異都列出來，別假設「這個不可能有影響」。
4. **釐清依賴** — 它需要哪些元件、設定、環境、假設？

### Phase 3：假設與測試（科學方法）

1. **形成單一假設** — 寫下來：「我認為 root cause 是 X，因為 Y」。要具體。
2. **最小化測試** — 做能驗證假設的**最小**改動，一次只動一個變數，不要同時修多處。
3. **驗證再繼續** — 成功 → Phase 4；失敗 → 形成**新**假設，不要在舊修法上疊新修法。
4. **不懂就說不懂** — 「我不理解 X」，不要假裝懂，去查或求助。

### Phase 4：實作修復

1. **先建失敗測試** — 最簡重現，能自動化就自動化（`uv run pytest` / `bun test`），沒框架就寫一次性腳本。**修之前必須先有它**（對齊全域規則）。
2. **只實作單一修復** — 針對找到的 root cause，一次一個改動。不要「順手」重構、不要 bundle 其他改動。
3. **驗證修復** — 測試現在通過？沒弄壞其他測試？問題真的解決了？
4. **修法沒效時** — STOP。數一下試了幾次：
   - < 3 次 → 回 Phase 1，帶新資訊重新分析
   - **≥ 3 次 → 停下來質疑架構**（見下）
5. **3+ 次修復都失敗 → 質疑架構**
   - 徵兆：每修一次就在別處冒出新的共享狀態/耦合/問題；修法都需要「大改」才能做；每個修法在別處製造新症狀
   - 這**不是**假設失敗，而是**架構錯了**。停止，跟使用者討論「這個 pattern 根本上對嗎？是不是只是慣性在硬撐？」再決定是否重構，而非繼續補症狀。

## Red Flags — STOP and Follow Process

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Here are the main problems: [lists fixes without investigation]"
- Proposing solutions before tracing data flow
- **"One more fix attempt" (when already tried 2+)**
- **Each fix reveals a new problem in a different place**

**ALL of these mean: STOP. Return to Phase 1.**
**If 3+ fixes failed:** Question the architecture (Phase 4.5).

## 使用者在暗示你做錯了（注意這些 redirect）

- 「不是這樣嗎？」/「有嗎？」— 你沒驗證就假設了
- 「會 print 出來給我們看嗎？」— 你應該先加蒐證
- 「不要再猜了」— 你在沒搞懂前就提修法
- 「我們卡住了？」（帶挫折）— 你的方法行不通

**看到這些：STOP，回 Phase 1。**

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple issues have root causes too. The process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is FASTER than guess-and-check thrashing. |
| "Just try this first, then investigate" | The first fix sets the pattern. Do it right from the start. |
| "I'll write the test after confirming the fix works" | Untested fixes don't stick. Test-first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "Reference too long, I'll adapt the pattern" | Partial understanding guarantees bugs. Read it completely. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question the pattern, don't fix again. |

## Quick Reference

| Phase | 重點 | 完成判準 |
|-------|------|---------|
| 1. Root Cause | 讀錯誤、重現、查變更、邊界蒐證 | 搞懂 WHAT 與 WHY |
| 2. Pattern | 找正常範例、比對 | 找出差異 |
| 3. Hypothesis | 形成理論、最小測試 | 確認或換新假設 |
| 4. Implementation | 建測試、修復、驗證 | bug 解決、測試通過 |

## 當調查顯示「真的沒有 root cause」

若系統化調查後確認問題確實是環境/timing/外部因素：記錄調查過程、實作適當處理（retry、timeout、明確錯誤訊息）、加 monitoring/logging 供未來調查。**但：95% 的「沒有 root cause」其實是調查不完整。**

## 配套技術（references/）

- `references/root-cause-tracing.md` — 把 bug 沿 call stack 反向追到原始觸發點
- `references/defense-in-depth.md` — 找到 root cause 後，在多層加驗證讓 bug 結構上不可能發生
