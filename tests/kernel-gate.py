#!/usr/bin/env python3
"""kernel-gate.py — agent contract 的 managed block 完整性掃描器。

為何需要它：契約的 kernel 必須在三處**逐字**存在——repo 根 `AGENTS.md`（給任何 clone 到
這個 repo 的 agent）、`claude/CLAUDE.md`（部署為全域 Claude 規則）、`codex/AGENTS.md`
（部署為全域 Codex 指引）。三份都得自足：純指標方案（「去讀 ./AGENTS.md」）已被實測證偽
——規則不在 always-on context 就不生效（claude/skills/handoff/evals.md 的 H6 首跑，
同一輪 repo-a 的 commit 落在 main、repo-b 才開 branch，因為規則只存在於延遲載入的檔案裡）。

三份自足的代價是複本會漂移，而 skill-building-guide 明列「same fact stated in N places」
是 red flag。**這支 gate 就是把那個代價換成機檢**：漂移即紅。形狀同 xref-gate——把原本
只靠散文維持的不變式變成機械守門。

用法：
    kernel-gate.py --root <dir>

輸出契約（tests/run.sh 依賴，勿改）：
    exit 0 — 掃描完成。**stdout 只放 blocking findings**，空輸出即通過。
    exit 2 — scanner 自身／參數／I/O 失敗。

    兩者不可混用：tests/run.sh 是 `set -uo pipefail`（無 -e），scanner 死掉時空 stdout
    會被判成「乾淨」，gate 靜默變成永遠綠。
"""

import argparse
import os
import re
import sys

# 帶 kernel block 的四個檔。⚠️ Phase 3 會把 codex/AGENTS.md 改名為 codex/global-guidance.md，
# 屆時這裡要同步——名字寫死是刻意的：漏改會讓 gate 找不到檔而判紅，比靜默略過安全。
#
# root CLAUDE.md 為什麼也要有一份：2026-08-10 實測，Claude Code **自動載入 root CLAUDE.md、
# 但不自動載入 root AGENTS.md**（後者只在 agent 剛好探索 repo 時才被 cat 到）。只放在
# AGENTS.md 的話，「修個 typo 並 commit」這類任務整輪都不會讀到契約。
KERNEL_FILES = ("AGENTS.md", "CLAUDE.md", "claude/CLAUDE.md", "codex/AGENTS.md")

# 只有契約檔帶 portable block（權威矩陣 + working discipline）——那層不進全域檔，
# 因為全域檔服務所有 repo、不該替別的 repo 宣告它的文件權威。
PORTABLE_FILE = "AGENTS.md"

MIN_RULE_LINES = 8   # safety floor 6 + fallback conventions 2

# 逐字複本的意義在於「規則只寫一次」。這些字串是規則本體的指紋——出現在 block 之外，
# 代表有人又抄了一份（複本一旦落在 gate 管不到的地方，漂移就回來了）。
CANARIES = ("git add -A", "--no-local", "git switch -c", "`perf`, `ci`")


def marker_re(name, kind):
    # 版本只掛在 start（`:start v1`）——end 不帶版本，否則同一個 block 有兩個要同步的
    # 版本號，改版時漏改一邊就變成「marker 不成對」這種看不出真因的紅。
    suffix = r" v\d+" if kind == "start" else ""
    return re.compile(r"<!-- agent-contract:%s:%s%s -->" % (re.escape(name), kind, suffix))


def extract(text, name):
    """回傳 (block_body, findings)。markers 異常時 body 為 None。"""
    starts = list(marker_re(name, "start").finditer(text))
    ends = list(marker_re(name, "end").finditer(text))
    if len(starts) != 1 or len(ends) != 1:
        return None, ["%s block 的 marker 不是各恰一次（start=%d end=%d）"
                      % (name, len(starts), len(ends))]
    if starts[0].start() > ends[0].start():
        return None, ["%s block 的 start marker 在 end 之後" % name]
    return text[starts[0].end():ends[0].start()], []


def read(root, rel):
    path = os.path.join(root, rel)
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def scan(root):
    findings = []
    bodies = {}

    for rel in KERNEL_FILES:
        try:
            text = read(root, rel)
        except FileNotFoundError:
            findings.append("%s: 檔案不存在——kernel 需要在三處逐字存在" % rel)
            continue
        body, errs = extract(text, "kernel")
        findings.extend("%s: %s" % (rel, e) for e in errs)
        if body is None:
            continue
        bodies[rel] = body

        # canary：規則本體不得在 block 之外再出現一份
        outside = text[:text.index("<!-- agent-contract:kernel:start")] + \
            text[text.index("<!-- agent-contract:kernel:end"):]
        for canary in CANARIES:
            if canary in outside:
                findings.append("%s: 規則指紋 %r 出現在 kernel block 之外——又抄了一份？"
                                % (rel, canary))

    if len(bodies) == len(KERNEL_FILES):
        # 條目數下限：三份都缺 block 時「空 == 空」會通過，這條是防那個假綠的關鍵
        rules = [ln for ln in bodies[KERNEL_FILES[0]].splitlines() if ln.startswith("- ")]
        if len(rules) < MIN_RULE_LINES:
            findings.append("kernel block 只有 %d 條規則行（<%d）——內容被掏空？"
                            % (len(rules), MIN_RULE_LINES))
        ref = bodies[KERNEL_FILES[0]]
        for rel in KERNEL_FILES[1:]:
            if bodies[rel] != ref:
                findings.append("%s 的 kernel block 與 %s 不是逐字相同——複本已漂移"
                                % (rel, KERNEL_FILES[0]))

    # 契約檔的 portable block：存在、非空、且不與 kernel 巢狀
    try:
        text = read(root, PORTABLE_FILE)
    except FileNotFoundError:
        findings.append("%s: 檔案不存在" % PORTABLE_FILE)
    else:
        body, errs = extract(text, "portable")
        findings.extend("%s: %s" % (PORTABLE_FILE, e) for e in errs)
        if body is not None:
            if not body.strip():
                findings.append("%s: portable block 是空的" % PORTABLE_FILE)
            if "agent-contract:kernel" in body:
                findings.append("%s: kernel block 巢狀在 portable 之內——兩者必須並列"
                                % PORTABLE_FILE)
        findings.extend(portability(text))

    return findings


# 只掃兩個 managed block：那才是會被複製到別的 repo 的部分。`## Repo specifics` 刻意在
# block 之外，本 repo 那節本來就會寫到 dotsync／~/.dotfiles，掃它只會製造假紅。
PRIVATE_TOKENS = ("~/.dotfiles", "~/.claude", "~/.codex", "/Users/",
                  "/project", "/deep-review", "/ready4quit", "/handoff",
                  "ship-state.sh", "dotsync")
# 「見 `X`「Y」」形狀的指標：在 dotfiles 內 xref-gate 會判它活著，安裝到別的 repo 卻是死的
# ——既有 gate 看不見的假綠。契約檔一律不得依賴這種跨檔指標。
XREF_SHAPE = re.compile(r"`[^`\n]+?\.(?:md|sh)`[「『]")


def portability(text):
    out = []
    for name in ("kernel", "portable"):
        body, _ = extract(text, name)
        if body is None:
            continue
        for token in PRIVATE_TOKENS:
            if token in body:
                out.append("%s: %s block 含私人路徑 %r——安裝到別的 repo 就是死的"
                           % (PORTABLE_FILE, name, token))
        if XREF_SHAPE.search(body):
            out.append("%s: %s block 含跨檔指標句型——契約必須自足"
                       % (PORTABLE_FILE, name))
    return out


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root", required=True)
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print("--root 不是目錄：%s" % root, file=sys.stderr)
        return 2
    try:
        findings = scan(root)
    except OSError as exc:
        print("掃描失敗：%s" % exc, file=sys.stderr)
        return 2
    for f in findings:
        print(f)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
