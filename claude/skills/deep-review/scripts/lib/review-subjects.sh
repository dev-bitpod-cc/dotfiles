#!/usr/bin/env bash
#
# review-subjects.sh — deep-review 循環機械產生的 commit subject（單一來源）
#
# 誰用（三個消費者，跨兩個 skill——改這裡務必三個都驗）：
#   review-anchor.sh  squash base 掃描（跳過這些 subject，停在第一顆語意 commit）
#   review-state.sh   round 偵測（只數修復輪，使用者自己的 fix: 不算）
#   ../../../project/scripts/ship-state.sh   review-residue 偵測（/project log Step 4 的
#                     squash 出題依據；跨 skill source，缺席時降級 UNKNOWN）
#
# 為何必須單一來源：三處各留一份必然漂移，而漂移的後果不對稱且都難察覺——
#   squash 端漏認 → 掃描被舊格式 commit 擋下、只壓到一半；
#   round 端多認 → 每個 review 週期白吃一輪 R5 預算（branch 現在會保留語意 commit，
#     使用者自己的 fix: 會長期留著，計入就是持續灌水）；
#   **review-residue 端多認 → 唯一不可回復的方向**：使用者手寫的 `fix: …` 被當成 review
#     痕跡出成 squash 選項，使用者一句「好」就 reset 掉自己的 commit，Step 5 接著
#     `--force-with-lease` 覆寫 remote。放寬 pattern 前先想清楚這條。
#
# 格式為 ERE 的 alternation（無錨點），呼叫端自行加 `^(...)$`——各家取的字串來源不同
# （%s 全行 vs 其他），錨點留給呼叫端決定才不會綁死。
#
# 現行格式不編輪號（中性化，見 `../../references/modes-and-scope.md`「迭代紀律：每輪修復後 commit」）；舊 R{N} / codex R{N} 樣式一併認——
# 歷史 branch 上仍有舊 commit，漏認會讓兩端同時判錯。

# shellcheck disable=SC2034  # 本檔只定義變數供 source 端消費，檔內不使用即為預期

# 修復輪產生的 commit（= 一輪一顆，round 偵測的計數對象）
REVIEW_FIX_ALT='fix: address (review|external review) findings|fix: R[0-9]+ review fixes|fix: codex [RC][0-9]+ fixes'

# review 前置產生、但不代表任何一輪修復的 commit（squash 要收，round 不能算）
REVIEW_WIP_ALT='wip: pre-review snapshot'

# squash 掃描的完整集合
REVIEW_SUBJECT_ALT="${REVIEW_FIX_ALT}|${REVIEW_WIP_ALT}"
