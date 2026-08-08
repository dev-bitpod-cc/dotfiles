#!/usr/bin/env python3
"""xref-gate.py — 交叉引用完整性掃描器。

為何是 gate 而不只是慣例：repo 的規範網靠「唯一權威」這個不變式維持——同一主題只有一處
定義，其他地方寫「見 `X 檔`「Y 節」，此處不重述」。那個不變式**全靠散文**，沒有任何檢查。
指標斷掉的後果不是不整潔：claude/CLAUDE.md 明文要求「勿憑記憶重組」，而指標斷掉時，
重組就是唯一選擇。2026-08-08 首次掃描實測：1 條真死指標（節名與內文皆不存在）、
2 條指向 repo 內有兩份同名檔的基名引用（reviewer-brief.md 有 Claude 端與 Codex 端兩份，
那是「review 刻意隔離」下故意不同的兩套判準，指錯即破壞 blind review）。

用法：
    xref-gate.py --root <dir> [files...]     # files 省略 → 在 root 下遞迴掃 *.md

輸出契約（tests/run.sh 依賴，勿改）：
    exit 0 — 掃描完成。**stdout 只放 blocking findings**，空輸出即通過。
    exit 2 — scanner 自身／參數／I/O 失敗。

    兩者不可混用：tests/run.sh 是 `set -uo pipefail`（無 -e），scanner 因解碼失敗或參數
    錯誤而死時，空 stdout 會被判成「乾淨」——gate 靜默變成永遠綠。內容問題（死指標、
    解析失敗、逃出 root）一律 exit 0 + stdout，只有「scanner 跑不動」才 exit 2。
"""

import argparse
import os
import re
import sys

# 引用句型：`<路徑>`「<節名>」（含『』變體）。節名上限 80 字元——超過的幾乎必然是整段引文，
# 不是指標；下限不在這裡管（normalize 後才判，見 SECTION_MIN）。
#
# ⚠️ **本 pattern 分不出「使用」與「提及」**：文件裡討論一條（尤其是壞掉的）引用時，寫法與
# 真正的指標一模一樣，於是會被當成真指標而判紅。2026-08-08 實地：把死指標當例子寫進
# STATUS.md 的 spec，gate 立刻咬自己。兩條出路——放進 code fence（source 端排除），
# 或在路徑與引號之間插字改寫成「`X.md` 的「Y」」。**不要為此放寬 pattern**：能區分兩者的
# 唯一訊號就是 fence，而放寬會讓真指標從縫隙漏掉。
REF_RE = re.compile(r"`([^`\n]+?\.(?:md|sh))`[「『]([^」』\n]{1,80})[」』]")

# fence：opener 縮排上限 3 格（4 格以上是 indented code block，不是 fence）。
FENCE_RE = re.compile(r"^(?P<indent> {0,3})(?P<fence>`{3,}|~{3,})(?P<info>.*)$")

COMMENT_RE = re.compile(r"<!--.*?-->", re.S)

HEADING_RE = re.compile(r"^#{1,6}\s+(.*)$")

# normalize 後的節名下限。空字串是任何字串的子字串（恆假綠）；長度 1 幾乎必然命中。
# 實測現有最短節名是「說法表」（3 字），下限 2 不誤傷任何存量引用。
SECTION_MIN = 2

# ~/ 前綴映射：repo 的 symlink 等價事實（ensure-codex-skills.sh / ensure-codex-guidance.sh
# 建立這些連結）。長前綴在前——比對取第一個命中。
TILDE_MAP = (
    ("~/.claude/skills/", "claude/skills/"),
    ("~/.codex/skills/", "codex/skills/"),
    ("~/.dotfiles/", ""),
)

SKIP_DIRS = {".git", "node_modules", ".venv", "__pycache__"}


def fence_mask(lines):
    """回傳與 lines 等長的 bool list：True = 該行屬 fenced code block（含 fence 標記行）。

    已驗證的 CommonMark 子集，涵蓋三個實地踩過或審查指出的形狀：
      - closer 須與 opener **同字元且長度 >= opener**（否則 ```` 外層包 ``` 範例會提前關欄）
      - closer 後**只允許空白**（否則 fence 內的 ```text 會被當 closer）
      - opener 縮排**上限 3 格**（4 格以上是 indented code block）
    不處理 indented code block、HTML block——dotfiles 現況無此形狀，補了也無 fixture 可驗。
    """
    mask = [False] * len(lines)
    in_fence = False
    fch = ""
    flen = 0
    for i, line in enumerate(lines):
        m = FENCE_RE.match(line)
        if m:
            ch = m.group("fence")[0]
            n = len(m.group("fence"))
            if not in_fence:
                in_fence, fch, flen = True, ch, n
                mask[i] = True
                continue
            if ch == fch and n >= flen and m.group("info").strip() == "":
                in_fence = False
                mask[i] = True
                continue
            # 同字元但長度不足、或帶 info string —— 是 fence 內的一行，不是 closer
            mask[i] = True
            continue
        mask[i] = in_fence
    return mask


def comment_spans_per_line(text, lines):
    """回傳與 lines 等長的 list[list[(start, end)]]：每行落在 HTML comment 內的行內區間。

    以全文 offset 求 comment 區間再映射回行——comment 可跨行，也可與正文同行混排。
    未閉合的 <!-- 不視為 comment（CommonMark 如此）。
    """
    starts = []
    pos = 0
    for line in lines:
        starts.append(pos)
        pos += len(line) + 1  # splitlines 吃掉的換行
    out = [[] for _ in lines]
    for m in COMMENT_RE.finditer(text):
        cs, ce = m.span()
        for i, ls in enumerate(starts):
            le = ls + len(lines[i])
            if ce <= ls or cs >= le:
                continue
            out[i].append((max(cs, ls) - ls, min(ce, le) - ls))
    return out


def blank_out(line, spans):
    """把行內指定區間換成等長空白——保留欄位位置，讓混排行的非 comment 部分仍可比對。"""
    if not spans:
        return line
    chars = list(line)
    for s, e in spans:
        for j in range(s, min(e, len(chars))):
            chars[j] = " "
    return "".join(chars)


def norm(s):
    """剝 markdown 修飾與空白/括號後比對。

    必須剝 inline 修飾：ready4quit/SKILL.md 的原文是「覆蓋同一主題就**更新該檔**，不要建
    重複檔」，引用寫的是無修飾版——純字串比對會失配，把合法引用判紅（規劃期實地誤判過）。
    """
    s = re.sub(r"`+", "", s)
    s = re.sub(r"[*_~]+", "", s)
    s = re.sub(r"^#+", "", s)
    s = re.sub(r"[\s（）()【】\[\]「」『』]", "", s)
    return s


class Doc:
    """一份 md 的解析結果。source 與 target 的非正文排除規則**刻意不對稱**：

    - source 抽取：排 fence（fenced 內的引用是「示範怎麼寫」，如 report-templates.md 的
      報告模板範例），但**掃 HTML comment**（comment 內是真指標——krepo/STATUS.md 開頭
      comment 就寫著「量體門檻的豁免見 CLAUDE.md「dossier 量體門檻」」）。
    - target heading/body：**兩者皆排除**。節名或規則文字只存在於註解掉的模板／placeholder
      （STATUS-template.md 的 comment 滿是這種），不構成「該節存在」的證據 → 會假綠。
    """

    def __init__(self, path):
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        self.lines = text.splitlines()
        self.fence = fence_mask(self.lines)
        self.comments = comment_spans_per_line(text, self.lines)

    def source_lines(self):
        """(行號, 行內容) — 排 fence，保留 comment。"""
        for i, line in enumerate(self.lines):
            if not self.fence[i]:
                yield i + 1, line

    def target_lines(self):
        """行內容 — 排 fence 與 comment（comment 區間換成空白，保留同行其餘部分）。"""
        for i, line in enumerate(self.lines):
            if self.fence[i]:
                continue
            yield blank_out(line, self.comments[i])

    def has_section(self, section):
        want = norm(section)
        for line in self.target_lines():
            m = HEADING_RE.match(line)
            if m and want in norm(m.group(1)):
                return True
        return False

    def has_body(self, section):
        """逐行比對——整檔 normalize 成單一字串會移除換行，讓兩行的尾與首拼接成假命中。"""
        want = norm(section)
        return any(want in norm(line) for line in self.target_lines())


def resolve(target, src_path, root):
    """回傳 (絕對路徑 or None, 理由)。理由非 None 時即為 finding 說明。"""
    if target.startswith("~/"):
        for prefix, repl in TILDE_MAP:
            if target.startswith(prefix):
                cand = os.path.join(root, repl + target[len(prefix):])
                break
        else:
            return None, None  # 其他 ~/ 是 repo 外引用（~/.ssh、~/Projects…），跳過、不是錯誤
        cands = [cand]
    else:
        # 純基名與相對路徑走同一條：先試引用檔所在目錄，再試 root。
        # **不做全 repo 同名搜尋**——repo 內有兩份 reviewer-brief.md（Claude 端／Codex 端
        # 刻意隔離的兩套判準），模糊搜尋會讓指標指到錯的那份而毫無警訊。
        cands = []
        for c in (os.path.join(os.path.dirname(src_path), target),
                  os.path.join(root, target)):
            if c not in cands:  # 引用檔位於 root 時兩者相同，訊息不重複印
                cands.append(c)
    for c in cands:
        if os.path.isfile(c):
            rp = os.path.realpath(c)
            if os.path.commonpath([rp, os.path.realpath(root)]) != os.path.realpath(root):
                return None, "解析後逃出 --root（%s）" % rp
            return rp, None
    return None, "檔案不存在（試過：%s）" % "、".join(
        os.path.relpath(c, root) for c in cands
    )


def scan(files, root):
    findings = []
    cache = {}
    for src in sorted(files):
        try:
            doc = Doc(src)
        except (OSError, UnicodeDecodeError) as exc:
            raise RuntimeError("讀取失敗 %s: %s" % (src, exc))
        rel = os.path.relpath(src, root)
        for lineno, line in doc.source_lines():
            for m in REF_RE.finditer(line):
                target, section = m.group(1), m.group(2)
                here = "%s:%d: `%s`「%s」" % (rel, lineno, target, section)
                if len(norm(section)) < SECTION_MIN:
                    findings.append("%s — 節名 normalize 後不足 %d 字，無法比對（空字串是任何字串的子字串，會恆假綠）" % (here, SECTION_MIN))
                    continue
                path, why = resolve(target, src, root)
                if why:
                    findings.append("%s — %s" % (here, why))
                    continue
                if path is None:
                    continue  # repo 外引用，不歸本 gate 管
                if path not in cache:
                    try:
                        cache[path] = Doc(path)
                    except (OSError, UnicodeDecodeError) as exc:
                        raise RuntimeError("讀取失敗 %s: %s" % (path, exc))
                tgt = cache[path]
                if tgt.has_section(section):
                    continue
                # 節名不中 → 退一步比對內文：引用一條規則而非節名是合法寫法
                if tgt.has_body(section):
                    continue
                findings.append(
                    "%s — 目標檔的 heading 與內文皆無此字串（節名改過？權威搬家？）" % here
                )
    return findings


def collect(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if f.endswith(".md"):
                out.append(os.path.join(dirpath, f))
    return out


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("files", nargs="*")
    try:
        args = ap.parse_args(argv)
    except SystemExit:
        return 2  # 參數錯誤走 scanner 失敗，不得冒充零命中
    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print("--root 不是目錄：%s" % root, file=sys.stderr)
        return 2
    files = [os.path.abspath(f) for f in args.files] or collect(root)
    missing = [f for f in files if not os.path.isfile(f)]
    if missing:
        print("輸入檔不存在：%s" % "、".join(missing), file=sys.stderr)
        return 2
    try:
        findings = scan(files, root)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    for f in findings:
        print(f)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
