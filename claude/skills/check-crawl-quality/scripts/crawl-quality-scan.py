#!/usr/bin/env python3
"""crawl-quality-scan.py — check-crawl-quality skill 的確定性掃描與計分引擎

用法：
    crawl-quality-scan.py <path|'glob'|db> [--content-field F] [--source-field F]
                          （glob 必須用引號包住——shell 先展開會變多個引數 exit 2）
                          [--sample-seed N]
                          [--classify pN=<noise|metadata|artifact|false-positive>]...
                          [--exempt <check-id>]...

職責：把 SKILL.md 兩維度（清潔度 / RAG 適用性）八項檢查的逐筆掃描、閾值比較、
扣分算術全部從 model 手上拿走——資料不進 agent context、同一輸入重跑輸出
bit-for-bit 相同（評分一致性）。model 只負責：覆核 4a 前綴分類（--classify 重跑）、
依資料集 context 豁免誤判項（--exempt 重跑）、把輸出渲染成報告。

輸出：帶前綴標籤的結構化文字（input: / source: / overview: / check-4x: /
check-4x@<source>:（該來源達扣分門檻）/ source-verdict: / check-error: /
ledger-*: / score: / verdict: / hint:），agent 直接判讀引用，不重算任何數字；
命中行附 sample="rid: 60字元摘" 取例。

exit code 契約：
    0 = 掃描完成（分數好壞都算成功）
    1 = 資料無法解析（偵測不到內容欄位、格式壞掉；stderr 附可用欄位/原因）
    2 = 用法錯誤（缺引數、路徑不存在、旗標值非法）

設計原則：
- 唯讀。檔案只讀不寫；SQLite 以 mode=ro URI 開啟（連 journal 都不會建）。
- 單項檢查獨立 try/except：某項失敗印 check-error: 行並繼續其他項，不整體中斷。
- stdlib-only（json/csv/sqlite3/re/glob/random/argparse），無第三方依賴；
  `uv run` 或任何 python3 皆可執行。
- 所有閾值/扣分常數集中於下方常數區，逐項附理由；SKILL.md 不重述數字（單一來源）。
"""

import argparse
import csv
import glob as globmod
import json
import random
import re
import sqlite3
import sys
from pathlib import Path

# ---------------- 常數（單一來源；SKILL.md 只引用不重述） ----------------

SAMPLE_SEED = 42          # 任意固定值；重點是固定——同輸入抽同一批（評分一致性）
SAMPLE_TIERS = [          # (總筆數上限, 抽樣數)；None = 全量
    (500, None),          # 小資料全掃，抽樣反而損訊
    (5000, 300),          # 中型抽 300：per-source 保底後仍有統計意義
    (float("inf"), 500),  # 大型封頂 500：再多對比例估計增益有限
]
MIN_PER_SOURCE = 20       # 每來源保底樣本——低於此 per-source 分析失去意義

PREFIX_LINES = 3          # 前綴取每筆前 3 行：nav 殘留常見長度，再長就進入正文
PREFIX_MIN_PCT = 10       # 前綴出現率 > 10% 才成 cluster（低於此屬偶然雷同）
PREFIX_FULLDOC_RATIO = 0.9  # 前綴長度 ≥ 內容 90% = 整篇重複，歸 4b 不歸 4a
FINGERPRINT_LEN = 200     # 4b 指紋長度：前 200 字元足以分辨，全長 hash 對近似重複過敏
DUP_GROUP_MIN = 4         # 相同指紋 > 3 筆才標記（2-3 筆常是合法轉載/公告重發）
LINK_DENSE_RATIO = 0.6    # 連結字元佔比 > 60% ≈ 導覽/目錄頁
THIN_NET_CHARS = 50       # 淨文字 < 50 字元 = 薄內容（不足以承載語義）
SHORT_RAW_CHARS = 50      # overview 的「極短」統計（原始長度）
KV_PREFIX_MIN_LINES = 2   # 前 10 行內 ≥ 2 行 key:value 才算 metadata 前綴（1 行常是誤中）
KV_SCAN_LINES = 10        # metadata 只看開頭：前 10 行之後的 key:value 多是正文表格
REDUNDANCY_MIN_LEN = 4    # 欄位值 < 4 字元太短，出現在正文屬巧合不算冗餘
OPENING_CHARS = 100       # 4h 開頭區分度取前 100 字元（≈ embedding 前段權重區）
UNDERSIZE_CHARS = 100     # chunk < 100 字元：缺乏語義
OVERSIZE_CHARS = 8000     # chunk > 8000 字元：超過 embedding 有效上下文
HUGE_CHARS = 100000       # > 100k：災難性大小，多半是解析錯誤
BLANK_RUN = 5             # 連續 > 5 空行 = 結構異常
LIST_DEEP_INDENT = 6      # 縮排 ≥ 6 空格 ≈ 第 4 層 list（> 3 層巢狀）

CLEAN_WEIGHT = 0.6        # 綜合分權重：清潔度 60% + RAG 40%（清潔問題影響全下游）
RAG_WEIGHT = 0.4

# 扣分表：check-id → (嚴重門檻%, 警告門檻%, 嚴重扣分, 警告扣分)
# 比例 > 嚴重門檻 → 扣嚴重分；≥ 警告門檻 → 扣警告分。
CLEAN_RULES = {
    "4a": (30, 10, 20, 10),   # noise 前綴
    "4b": (20, 5, 20, 10),    # 內容重複
    "4c": (15, 5, 15, 8),     # 連結密度
    "4d": (10, 3, 15, 8),     # 內容過短（空佔位+薄內容）
    "4e": (5, 1, 10, 5),      # web 殘留
    "4f": (10, 3, 10, 5),     # 結構異常
}
RAG_RULES = {
    # 4g-prefix 特例規則見 score_rag()：>50% 文件且 content 佔比 >20% → -20；僅文件比例高 → -10
    "4g-redundancy": (80, 50, 10, 5),
    # 4h-opening 特例規則見 score_rag()：區分度 <50% → -15；<70% → -8
    "4h-undersize": (10, 3, 10, 5),
    "4h-oversize": (5, 1, 10, 5),
    "4h-huge": (1, 1, 5, 5),
    "4h-selfcont": (30, 10, 15, 8),
}
G_PREFIX_DOCPCT = 50      # 4g metadata 混入：> 50% 文件共享 metadata 前綴才扣
G_PREFIX_RATIO = 20       # 且 metadata 佔 content > 20% 才升嚴重
H_OPENING_SEVERE = 50     # 開頭區分度 < 50% 嚴重
H_OPENING_WARN = 70       # < 70% 警告

# H3「一現象一維度」路由拍板：
# - 前綴軸：cluster 分類決定唯一去向（noise→4a、metadata/artifact→4g、false-positive→不扣）；
#   4b 指紋、4g KV 掃描、4h 開頭一律先剝 cluster 前綴。
# - 重複軸：重複文件扣 4b；4h 開頭區分度排除 dup-group 非首筆。
# - 尺寸軸（有意重疊，非違反）：空/薄文件同時見於 4d（清潔＝爬取/清理品質）與
#   4h-undersize（RAG＝embedding 語義量）——量測不同現象，視為兩個發現；
#   拍板理由見 docs/check-crawl-quality-spec.md 附錄。

TEXT_SUFFIXES = (".json", ".jsonl", ".md", ".txt", ".csv")  # 檔案輸入白名單（sqlite 另判）
CONTENT_FIELD_CANDIDATES = ["content", "text", "body", "markdown"]
SOURCE_FIELD_CANDIDATES = ["source", "category"]
META_FIELD_KEYS = ["title", "author", "date", "subject"]
CHUNK_FIELD_KEYS = ["split_index", "chunk_index", "chunk_id", "part"]

MD_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]*)\)")
KV_LINE_RE = re.compile(r"^\s*[\w一-鿿][\w一-鿿 ]{0,23}\s*[:：]\s*\S|^\[[^\]]{1,24}\]\s")
FENCE_RE = re.compile(r"```.*?```", re.S)
HEADING_RE = re.compile(r"^(#{1,6})\s")
# 4e 殘留 pattern（在剝除 code fence 後掃描；<br> 可接受故不列）
ARTIFACT_PATTERNS = [
    ("html-tag", re.compile(r"<(div|span|script|table|iframe|form|button)\b|</[a-z]")),
    ("js", re.compile(r"javascript:|onclick|window\.|document\.|function\(")),
    ("js-md-link", re.compile(r"\[[^\]]*\]\(javascript:")),
    ("css", re.compile(r"\{(color|display|margin)\s*:")),
    ("encoded-entity", re.compile(r"&amp;|&lt;|&gt;|&#\d|\\u00")),
    ("pdf-binary", re.compile(r"\A%PDF|endstream|endobj")),
    ("ui-text", re.compile(r"^\s*(Download PDF|Share this|Back to top|Read more|Click here|Subscribe)\s*$", re.M | re.I)),
]
# 非首 chunk 以這些接續語開頭 → 分割點不佳
CONTINUATION_WORDS = ["此外", "另外", "其", "該", "However", "Furthermore", "Additionally", "It ", "This ", "These "]

CLASSIFY_VALUES = ("noise", "metadata", "artifact", "false-positive")
# --exempt 的合法 check-id（與 ledger 的扣分鍵一一對應；未知值 exit 2，不可 silent no-op）
VALID_EXEMPTS = frozenset(list(CLEAN_RULES) + list(RAG_RULES) + ["4g-prefix", "4h-opening"])


def die_usage(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(2)


def die_data(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def pct(n, d):
    return 100.0 * n / d if d else 0.0


def fpct(v):
    return f"{v:.1f}%"


# ---------------- 載入 ----------------

def clean_label(s):
    """會進輸出行的標籤（來源名等）——摺疊空白（含換行，防偽造 score:/ledger 行）。
    不截斷：標籤同時是 per-source 的 identity，截斷會把前綴相同的不同來源合併。"""
    return re.sub(r"\s+", " ", str(s)).strip()


def norm_record(raw, idx, content_field, source_field):
    content = raw.get(content_field)
    if not isinstance(content, str):
        # 混 schema 資料集（部分檔用 content、部分用 body）以候選欄位遞補，
        # 不得靜默變成空內容——那會產生假的 empty/thin findings
        for cand in CONTENT_FIELD_CANDIDATES:
            v = raw.get(cand)
            if isinstance(v, str):
                content = v
                break
    if not isinstance(content, str):
        content = "" if content is None else str(content)
    source = None
    for key in ([source_field] if source_field else []) + SOURCE_FIELD_CANDIDATES:
        if key and isinstance(raw.get(key), str) and raw[key]:
            source = clean_label(raw[key])
            break
    meta = {k: raw[k] for k in META_FIELD_KEYS
            if isinstance(raw.get(k), str) and len(raw[k]) >= REDUNDANCY_MIN_LEN}
    chunk_idx = None
    for key in CHUNK_FIELD_KEYS:
        v = raw.get(key)
        if v is not None:
            try:
                chunk_idx = int(v)
            except (TypeError, ValueError):
                chunk_idx = None
            break
    # rid 前綴載入序號保證全域唯一——合併資料集常見各來源 id 各自從 1 起跳，
    # 裸用原始 id 會跨來源碰撞、污染 per-source 計數（rid 僅出現在 sample= 取例行）
    rid = f"{idx}:{raw.get('id') or raw.get('url') or 'rec'}"
    return {"id": rid, "content": content, "source": source or "(all)",
            "meta": meta, "chunk_idx": chunk_idx}


def detect_content_field(dicts, override):
    if override:
        hit = sum(1 for d in dicts if isinstance(d.get(override), str))
        if hit == 0:  # 旗標打錯 = 用法錯誤（exit 2），與 --source-field 同語意
            keys = sorted({k for d in dicts[:20] for k in d})
            die_usage(f"--content-field {override} 在資料中不存在（可用欄位：{', '.join(keys)}）")
        return override
    for cand in CONTENT_FIELD_CANDIDATES:
        hit = sum(1 for d in dicts if isinstance(d.get(cand), str))
        if hit >= max(1, len(dicts) // 2):
            return cand
    keys = sorted({k for d in dicts[:20] for k in d})
    die_data(f"偵測不到內容欄位（候選 {'/'.join(CONTENT_FIELD_CANDIDATES)} 皆未命中）；"
             f"可用欄位：{', '.join(keys)}——用 --content-field 指定")


def load_json_file(path):
    try:
        with open(path, encoding="utf-8-sig") as f:  # utf-8-sig：容忍 BOM
            if Path(path).suffix == ".jsonl":
                # JSONL 首字元也是 { ——必須依副檔名分流，走整檔 json.load 會 Extra data
                return [json.loads(line) for line in f if line.strip()]
            head = f.read(1)
            while head and head.isspace():  # 跳過前導空白/換行再 sniff，合法 JSON 不得誤判 JSONL
                head = f.read(1)
            f.seek(0)
            if head == "[" or head == "{":
                data = json.load(f)
                if isinstance(data, dict):
                    lists = [v for v in data.values() if isinstance(v, list)]
                    if len(lists) == 1:
                        data = lists[0]
                    else:
                        die_data(f"{path}: JSON dict 無法定位記錄陣列")
                if not isinstance(data, list):
                    die_data(f"{path}: JSON 頂層不是陣列")
                return [d for d in data if isinstance(d, dict)]
            return [json.loads(line) for line in f if line.strip()]
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        die_data(f"{path}: JSON 解析失敗（{e}）")
    except OSError as e:
        die_data(f"{path}: 無法讀取（{e}）")


def load_sqlite(path, content_field, source_field):
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)  # 唯讀：不建 journal、不碰原始資料
    try:
        tables = [r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        for table in tables:
            cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")')]
            cand = ([content_field] if content_field else CONTENT_FIELD_CANDIDATES)
            content_col = next((c for c in cand if c in cols), None)
            if not content_col:
                continue  # 非內容表（輔助表）不驗旗標——多表 DB 的常態
            if source_field and source_field not in cols:
                die_usage(f"{path}: --source-field {source_field} 不在內容表 {table} 欄位中"
                          f"（可用欄位：{', '.join(cols)}）")
            source_col = next((c for c in ([source_field] if source_field else []) + SOURCE_FIELD_CANDIDATES
                               if c in cols), None)
            meta_cols = [c for c in META_FIELD_KEYS if c in cols]
            chunk_cols = [c for c in CHUNK_FIELD_KEYS if c in cols]
            select = ["rowid", f'"{content_col}"'] + [f'"{c}"' for c in ([source_col] if source_col else []) + meta_cols + chunk_cols]
            # ORDER BY rowid：載入順序固定為插入序，不依賴 sqlite 內部掃描序（決定性）
            rows = conn.execute(f'SELECT {", ".join(select)} FROM "{table}" ORDER BY rowid').fetchall()
            recs = []
            for row in rows:
                raw = {"id": row[0], content_col: row[1]}
                offset = 2
                if source_col:
                    raw[source_col] = row[offset]
                    offset += 1
                for j, c in enumerate(meta_cols):
                    raw[c] = row[offset + j]
                for j, c in enumerate(chunk_cols):
                    raw[c] = row[offset + len(meta_cols) + j]
                recs.append(raw)
            return recs, content_col
        if content_field:  # 指定了旗標但全表未命中 = 旗標打錯（exit 2），不是資料問題
            die_usage(f"{path}: --content-field {content_field} 不在任何資料表中"
                      f"（表：{', '.join(tables) or '無'}）")
        die_data(f"{path}: 找不到含內容欄位的資料表（表：{', '.join(tables) or '無'}）")
    except sqlite3.Error as e:
        die_data(f"{path}: SQLite 開啟/讀取失敗（{e}）")
    finally:
        conn.close()


def load_records(target, content_field, source_field):
    """回傳 (records, input_type)。records 已 norm、載入順序即固定順序（決定性）。"""
    is_glob = any(ch in target for ch in "*?[")
    paths = sorted(globmod.glob(target)) if is_glob else [target]
    if not paths or not Path(paths[0]).exists():
        die_usage(f"路徑不存在：{target}")
    p0 = Path(paths[0])

    def is_sqlite(p):
        if not p.is_file():
            return False
        if p.suffix in (".db", ".sqlite", ".sqlite3"):
            return True
        with open(p, "rb") as fh:
            return fh.read(16).startswith(b"SQLite format 3")

    sqlite_hits = [p for p in map(Path, paths) if is_sqlite(p)]
    if sqlite_hits:
        if len(paths) > 1:  # 多檔 glob 只吞第一個 DB = 靜默資料遺失——明確拒絕
            die_usage(f"{target}: glob 匹配含 SQLite 的多個檔案——一次只支援單一 DB，請直接指定檔名")
        raws, cfield = load_sqlite(sqlite_hits[0], content_field, source_field)
        if not raws:  # sqlite 分支提前 return，0 筆檢查須在此做（否則下游除零）
            die_data(f"{sqlite_hits[0]}: 資料表讀到 0 筆記錄")
        recs = [norm_record(r, i, cfield, source_field) for i, r in enumerate(raws)]
        return recs, "sqlite"

    if is_glob:  # glob 展開套用與目錄掃描相同的白名單——不支援類型當文字吞入會污染統計
        bad = [p for p in paths if Path(p).is_file() and Path(p).suffix not in TEXT_SUFFIXES]
        if bad:
            die_usage(f"glob 匹配到不支援的檔案類型：{', '.join(bad[:5])}"
                      f"（支援：{', '.join(TEXT_SUFFIXES)}；SQLite 請直接指定檔名）")

    files = []
    for p in paths:
        p = Path(p)
        if p.is_dir():
            files += sorted(x for x in p.rglob("*") if x.suffix in TEXT_SUFFIXES)
        else:
            files.append(p)
    raws, text_recs, itype = [], [], "json"
    for f in files:
        if f.suffix in (".json", ".jsonl"):
            raws += load_json_file(f)
        elif f.suffix == ".csv":
            try:
                with open(f, encoding="utf-8-sig") as fh:
                    raws += list(csv.DictReader(fh))
            except (csv.Error, UnicodeDecodeError) as e:
                die_data(f"{f}: CSV 解析失敗（{e}）")
            except OSError as e:
                die_data(f"{f}: 無法讀取（{e}）")
            itype = "csv"
        else:  # md/txt：一檔一筆，來源 = 相對第一層子目錄
            rel = f.relative_to(p0) if p0.is_dir() and f.is_relative_to(p0) else f
            src = clean_label(rel.parts[0]) if len(rel.parts) > 1 else "(root)"
            try:
                text = f.read_text(encoding="utf-8", errors="replace")
            except OSError as e:
                die_data(f"{f}: 無法讀取（{e}）")
            text_recs.append({"id": str(f), "content": text,
                              "source": src, "meta": {}, "chunk_idx": None})
            itype = "text"
    recs = list(text_recs)
    if raws:
        # --source-field 打錯必須大聲失敗——靜默退回自動偵測會讓 per-source 分析整個失效
        if source_field and not any(isinstance(r.get(source_field), str) and r[source_field] for r in raws):
            keys = sorted({k for r in raws[:20] for k in r})
            die_usage(f"--source-field {source_field} 在資料中不存在（可用欄位：{', '.join(keys)}）")
        cfield = detect_content_field(raws, content_field)
        recs += [norm_record(r, i, cfield, source_field) for i, r in enumerate(raws)]
    elif content_field or source_field:
        die_usage("--content-field/--source-field 僅適用結構化輸入（json/jsonl/csv/sqlite），"
                  "md/txt 目錄無欄位可指定")
    if not recs:
        die_data(f"{target}: 讀到 0 筆記錄")
    return recs, itype


# ---------------- 抽樣 ----------------

def stratified_sample(records, seed):
    total = len(records)
    target = next(t for cap, t in SAMPLE_TIERS if total <= cap)
    if target is None or target >= total:
        return records
    by_source = {}
    for r in records:
        by_source.setdefault(r["source"], []).append(r)
    # 保底與上限衝突（來源數 × 保底 > 上限）→ 上限優先（成本控制），保底降為均分額
    floor_cap = MIN_PER_SOURCE
    if sum(min(MIN_PER_SOURCE, len(rs)) for rs in by_source.values()) > target:
        floor_cap = max(1, target // len(by_source))
    # 比例分配 → 不足保底者拉到保底，差額從最大來源扣回（總數守恆）
    alloc = {s: round(target * len(rs) / total) for s, rs in by_source.items()}
    drift = target - sum(alloc.values())
    for s in sorted(by_source, key=lambda s: -len(by_source[s])):
        if drift == 0:
            break
        alloc[s] += 1 if drift > 0 else -1
        drift += -1 if drift > 0 else 1
    for s, rs in sorted(by_source.items()):
        floor = min(floor_cap, len(rs))
        if alloc[s] < floor:
            deficit = floor - alloc[s]
            alloc[s] = floor
            for big in sorted(by_source, key=lambda x: -alloc[x]):
                if big == s or deficit == 0:
                    continue
                take = min(deficit, max(0, alloc[big] - floor_cap))
                alloc[big] -= take
                deficit -= take
    # 終端保險：來源數 > target 時保底 1 也會超額——由大到小輪流遞減（允許歸零），
    # 上限恆成立（成本控制契約優先於保底）
    excess = sum(alloc.values()) - target
    if excess > 0:
        # 排除哪些來源由 seed 決定（tiebreak 用 seeded 亂數）——固定名稱序會永遠
        # 犧牲同一批來源形成盲區；同 seed 仍可重現（獨立 Random 不動抽樣主 rng）
        tie_rng = random.Random(seed)
        tie = {s: tie_rng.random() for s in sorted(alloc)}
        order = sorted(alloc, key=lambda s: (-alloc[s], tie[s], s))
        i = 0
        while excess > 0:
            s = order[i % len(order)]
            if alloc[s] > 0:
                alloc[s] -= 1
                excess -= 1
            i += 1
    rng = random.Random(seed)
    sampled = []
    for s in sorted(by_source):
        rs = by_source[s]
        n = min(alloc[s], len(rs))
        sampled += rs if n >= len(rs) else rng.sample(rs, n)
    return sampled


# ---------------- 檢查 ----------------

def net_text(content):
    t = FENCE_RE.sub(" ", content)
    t = MD_LINK_RE.sub(lambda m: m.group(1), t)
    t = re.sub(r"^#{1,6}\s+|^\s*[-*+]\s+|[!*_`>|]", " ", t, flags=re.M)
    return re.sub(r"\s+", " ", t).strip()


def first_lines(content, n):
    return content.split("\n")[:n]


def detect_clusters(sampled):
    """4a：共享前綴 cluster。回傳 [{id, key, docs(list), heuristic}]（排序固定）。"""
    groups = {}
    for r in sampled:
        key = "\n".join(first_lines(r["content"], PREFIX_LINES))
        if key.strip():
            groups.setdefault(key, []).append(r)
    clusters = []
    for key, docs in groups.items():
        if pct(len(docs), len(sampled)) <= PREFIX_MIN_PCT:
            continue
        avg_len = sum(len(d["content"]) for d in docs) / len(docs)
        if len(key) >= PREFIX_FULLDOC_RATIO * avg_len:
            continue  # 前綴≈全文 → 整篇重複，4b 的守備範圍
        lines = [ln for ln in key.split("\n") if ln.strip()]
        kv_n = sum(1 for ln in lines if KV_LINE_RE.match(ln))
        redundant = sum(1 for d in docs
                        if any(v in key for v in d["meta"].values()))
        if redundant > len(docs) / 2:
            heuristic = "artifact"
        elif kv_n >= min(2, len(lines)):
            heuristic = "metadata"
        else:
            heuristic = "noise"
        clusters.append({"key": key, "docs": docs, "heuristic": heuristic})
    clusters.sort(key=lambda c: (-len(c["docs"]), c["key"]))
    for i, c in enumerate(clusters):
        c["id"] = f"p{i + 1}"
    return clusters


def check_all(sampled, clusters, classify):
    """執行 4b-4h，回傳 findings dict（各 check 的計數與樣本；單項失敗不中斷）。"""
    n = len(sampled)
    f = {"n": n, "errors": []}

    def run(check_id, fn):
        try:
            fn()
        except Exception as e:  # 單項失敗記錄後繼續（不讓一項壞掉廢掉整份報告）
            f["errors"].append((check_id, f"{type(e).__name__}: {e}"))

    cluster_class = {c["id"]: classify.get(c["id"], c["heuristic"]) for c in clusters}
    prefix_keys = [c["key"] for c in clusters]

    def strip_prefix(content):
        for k in prefix_keys:
            if content.startswith(k):
                return content[len(k):]
        return content

    def c4b():
        groups = {}
        for r in sampled:
            fp = re.sub(r"\s+", " ", strip_prefix(r["content"]))[:FINGERPRINT_LEN]
            groups.setdefault(fp, []).append(r)
        f["dup_groups"] = sorted(([fp, rs] for fp, rs in groups.items()
                                  if len(rs) >= DUP_GROUP_MIN),
                                 key=lambda g: (-len(g[1]), g[0]))
        f["dup_docs"] = sum(len(g[1]) for g in f["dup_groups"])
    run("4b", c4b)

    def c4c():
        dense = []
        for r in sampled:
            c = r["content"]
            if not c:
                continue
            link_chars = sum(len(m.group(0)) for m in MD_LINK_RE.finditer(c))
            if link_chars / len(c) > LINK_DENSE_RATIO:
                dense.append(r)
        f["link_dense"] = dense
    run("4c", c4c)

    def c4d():
        f["empty"] = [r for r in sampled if not r["content"].strip()]
        f["thin"] = [r for r in sampled
                     if r["content"].strip() and len(net_text(r["content"])) < THIN_NET_CHARS]
    run("4d", c4d)

    def c4e():
        hits = {}
        docs_any = set()
        for r in sampled:
            stripped = FENCE_RE.sub(" ", r["content"])
            for name, rx in ARTIFACT_PATTERNS:
                if rx.search(stripped):
                    hits.setdefault(name, []).append(r)
                    docs_any.add(r["id"])
        f["artifacts"] = {k: hits[k] for k in sorted(hits)}
        f["artifact_docs"] = len(docs_any)
    run("4e", c4e)

    def c4f():
        anomalies = {"heading-jump": 0, "orphan-heading": 0, "deep-nesting": 0,
                     "blank-run": 0, "truncated": 0}
        docs_any = []
        for r in sampled:
            lines = r["content"].split("\n")
            found = set()
            prev_level, blanks, last_heading_body = None, 0, True
            for ln in lines:
                m = HEADING_RE.match(ln)
                if m:
                    level = len(m.group(1))
                    if prev_level is not None and level > prev_level + 1:
                        found.add("heading-jump")
                    if not last_heading_body:
                        found.add("orphan-heading")
                    prev_level, last_heading_body = level, False
                elif ln.strip():
                    last_heading_body = True
                blanks = blanks + 1 if not ln.strip() else 0
                if blanks > BLANK_RUN:
                    found.add("blank-run")
                if re.match(r"^\s{%d,}([-*+]|\d+\.)\s" % LIST_DEEP_INDENT, ln):
                    found.add("deep-nesting")
            if prev_level is not None and not last_heading_body:
                found.add("orphan-heading")
            tail = next((ln for ln in reversed(lines) if ln.strip()), "")
            if re.search(r"\[[^\]]*(\]\([^)]*)?$", tail):
                found.add("truncated")
            for a in found:
                anomalies[a] += 1
            if found:
                docs_any.append(r)
        f["structure"] = anomalies
        f["structure_docs"] = docs_any
    run("4f", c4f)

    def c4g():
        kv_docs, ratio_map = [], {}
        for r in sampled:
            # H3：cluster 前綴的計分去向由分類決定（noise→4a、metadata→下方顯式併入），
            # KV 掃描一律在剝除 cluster 前綴後進行，不得重複計入
            content = strip_prefix(r["content"])
            head = first_lines(content, KV_SCAN_LINES)
            kv_lines = [ln for ln in head if KV_LINE_RE.match(ln)]
            if len(kv_lines) >= KV_PREFIX_MIN_LINES:
                kv_docs.append(r)
                ratio_map[r["id"]] = pct(sum(len(ln) + 1 for ln in kv_lines), len(content))
        # metadata 分類的 cluster docs 併入（H3：4a 只留 noise，metadata 歸 4g）
        for c in clusters:
            if cluster_class[c["id"]] == "metadata":
                for r in c["docs"]:
                    if r["id"] not in ratio_map:
                        kv_docs.append(r)
                        ratio_map[r["id"]] = pct(len(c["key"]) + 1, len(r["content"]))
        f["meta_prefix_docs"] = kv_docs
        f["meta_prefix_ratios"] = ratio_map
        f["meta_prefix_ratio"] = (sum(ratio_map.values()) / len(ratio_map)) if ratio_map else 0.0

        base_docs = [r for r in sampled if r["meta"]]
        red_docs = [r for r in base_docs
                    if any(v in "\n".join(first_lines(r["content"], KV_SCAN_LINES))
                           for v in r["meta"].values())]
        # artifact 分類的 cluster docs 併入冗餘（內容重複了獨立欄位）
        seen_base = {r["id"] for r in base_docs}
        seen_red = {r["id"] for r in red_docs}
        for c in clusters:
            if cluster_class[c["id"]] == "artifact":
                for r in c["docs"]:
                    if r["id"] not in seen_base:
                        seen_base.add(r["id"])
                        base_docs.append(r)
                    if r["id"] not in seen_red:
                        seen_red.add(r["id"])
                        red_docs.append(r)
        f["redundancy"] = (red_docs, base_docs)
    run("4g", c4g)

    def c4h():
        # H3 重複軸：重複文件已扣 4b，開頭區分度只留每組首筆——相同開頭不再重複壓低 RAG 分
        dup_extra = {r["id"] for _, rs in f.get("dup_groups", []) for r in rs[1:]}
        pairs = []
        for r in sampled:
            if r["id"] in dup_extra:
                continue
            # H3 前綴軸：先剝 4a cluster 前綴再算開頭（metadata 前綴由下行 KV 剝除）
            content = strip_prefix(r["content"])
            body = "\n".join(ln for ln in first_lines(content, KV_SCAN_LINES)
                             if not KV_LINE_RE.match(ln))
            rest = content.split("\n")[KV_SCAN_LINES:]
            body = re.sub(r"\s+", " ", "\n".join([body] + rest))[:OPENING_CHARS]
            pairs.append((r, body))
        f["openings"] = pairs
        f["opening_uniq"] = pct(len({o for _, o in pairs}), len(pairs)) if pairs else 100.0
        f["undersize"] = [r for r in sampled if len(r["content"]) < UNDERSIZE_CHARS]
        f["oversize"] = [r for r in sampled if OVERSIZE_CHARS < len(r["content"]) <= HUGE_CHARS]
        f["huge"] = [r for r in sampled if len(r["content"]) > HUGE_CHARS]
        chunked = [r for r in sampled if r["chunk_idx"] is not None]
        if chunked:
            non_first = [r for r in chunked if r["chunk_idx"] > 0]
            bad = [r for r in non_first
                   if any(r["content"].lstrip().startswith(w) for w in CONTINUATION_WORDS)]
            f["selfcont"] = (bad, non_first)
        else:
            f["selfcont"] = None
    run("4h", c4h)

    return f


# ---------------- 計分 ----------------

def tier_deduction(rule, p):
    severe_pct, warn_pct, severe_ded, warn_ded = rule
    if p > severe_pct:
        return float(severe_ded)
    if p >= warn_pct:
        return float(warn_ded)
    return 0.0


def weighted_deduction(check_id, rules, global_pct_v, per_source_pct, shares):
    """全域與 per-source 取較嚴重者；per-source 按佔比加權、保底半額。回傳 (ded, driver)。"""
    ded = tier_deduction(rules[check_id], global_pct_v)
    driver = "global"
    for s, sp in sorted(per_source_pct.items()):
        sded = tier_deduction(rules[check_id], sp)
        if sded <= 0:
            continue
        w = max(sded * shares[s] / 100.0, sded / 2.0)
        if w > ded:
            ded, driver = w, s
    return ded, driver


DISPLAY_LABEL_CHARS = 60  # 來源顯示上限——identity 不截斷（計分用），顯示截斷防輸出膨脹


def build_display(names):
    """identity → 有界顯示標籤；截斷後互撞的以穩定序號消歧（sorted 順序，決定性）。"""
    stems = {}
    for name in sorted(names):
        if len(name) > DISPLAY_LABEL_CHARS:
            stems.setdefault(name[:DISPLAY_LABEL_CHARS], []).append(name)
    disp = {}
    for name in names:
        if len(name) <= DISPLAY_LABEL_CHARS:
            disp[name] = name
        else:
            stem = name[:DISPLAY_LABEL_CHARS]
            group = stems[stem]
            disp[name] = f"{stem}…" if len(group) == 1 else f"{stem}…#{group.index(name) + 1}"
    return disp


def fmt_samples(docs, k=2):
    """命中行的 verbatim 取例（No example, no finding 的履行面）：最多 k 筆、每筆 60 字元。"""
    out = []
    for r in docs[:k]:
        excerpt = re.sub(r"\s+", " ", r["content"]).strip()[:60]
        out.append(f'{r["id"]}: {excerpt}' if excerpt else f'{r["id"]}: (空)')
    return " | ".join(out)


def per_source_pcts(sampled, flagged_ids):
    by_source, hit = {}, {}
    for r in sampled:
        by_source[r["source"]] = by_source.get(r["source"], 0) + 1
        if r["id"] in flagged_ids:
            hit[r["source"]] = hit.get(r["source"], 0) + 1
    return {s: pct(hit.get(s, 0), c) for s, c in by_source.items()}


# ---------------- 主流程 ----------------

def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("input", nargs="?")
    ap.add_argument("--content-field")
    ap.add_argument("--source-field")
    ap.add_argument("--sample-seed", type=int, default=SAMPLE_SEED)
    ap.add_argument("--classify", action="append", default=[],
                    metavar="pN=CLASS", help="覆核 4a cluster 分類後重跑")
    ap.add_argument("--exempt", action="append", default=[],
                    metavar="CHECK-ID", help="context 豁免：該項不扣分仍報告（如 4e）")
    args = ap.parse_args()
    if not args.input:
        die_usage("缺少輸入路徑：crawl-quality-scan.py <path|glob|db>")

    classify = {}
    for spec in args.classify:
        if "=" not in spec:
            die_usage(f"--classify 格式須為 pN=CLASS：{spec}")
        cid, cls = spec.split("=", 1)
        if cls not in CLASSIFY_VALUES:
            die_usage(f"--classify 類別須為 {'/'.join(CLASSIFY_VALUES)}：{spec}")
        classify[cid] = cls
    exempts = set(args.exempt)
    bad_exempts = sorted(exempts - VALID_EXEMPTS)
    if bad_exempts:
        die_usage(f"--exempt 未知 check-id：{', '.join(bad_exempts)}"
                  f"（合法值：{', '.join(sorted(VALID_EXEMPTS))}）")

    records, itype = load_records(args.input, args.content_field, args.source_field)
    sampled = stratified_sample(records, args.sample_seed)
    n = len(sampled)
    print(f"input: type={itype} records={len(records)} sampled={n} seed={args.sample_seed}")

    by_source_all, by_source_sampled = {}, {}
    for r in records:
        by_source_all[r["source"]] = by_source_all.get(r["source"], 0) + 1
    for r in sampled:
        by_source_sampled[r["source"]] = by_source_sampled.get(r["source"], 0) + 1
    shares = {s: pct(c, len(records)) for s, c in by_source_all.items()}
    disp = build_display(list(by_source_all))
    for s in sorted(by_source_all):
        print(f"source: {disp[s]} records={by_source_all[s]} share={fpct(shares[s])} sampled={by_source_sampled.get(s, 0)}")

    lens = sorted(len(r["content"]) for r in sampled)
    q = lambda p: lens[int(p * (len(lens) - 1))] if lens else 0
    links_avg = sum(len(MD_LINK_RE.findall(r["content"])) for r in sampled) / n
    n_empty = sum(1 for r in sampled if not r["content"].strip())
    n_short = sum(1 for r in sampled if len(r["content"]) < SHORT_RAW_CHARS)
    print(f"overview: len min={lens[0]} p25={q(0.25)} median={q(0.5)} p75={q(0.75)} max={lens[-1]} "
          f"empty={n_empty} short={n_short} links-avg={links_avg:.1f}")

    clusters = detect_clusters(sampled)
    unknown_classify = sorted(set(classify) - {c["id"] for c in clusters})
    if unknown_classify:  # 打錯 pN 必須大聲失敗——silent no-op 會讓 agent 以為已改判
        die_usage(f"--classify 引用不存在的 cluster id：{', '.join(unknown_classify)}"
                  f"（本次偵測到：{', '.join(c['id'] for c in clusters) or '無'}）")
    cluster_class = {c["id"]: classify.get(c["id"], c["heuristic"]) for c in clusters}
    for c in clusters:
        cls = cluster_class[c["id"]]
        mark = "confirmed" if c["id"] in classify else "heuristic"
        sample = " | ".join(ln for ln in c["key"].split("\n") if ln.strip())[:80]
        print(f'check-4a: cluster {c["id"]} docs={len(c["docs"])} pct={fpct(pct(len(c["docs"]), n))} '
              f'class={cls}({mark}) sample="{sample}"')
    if not clusters:
        print("check-4a: none")

    f = check_all(sampled, clusters, classify)
    for i, (fp, rs) in enumerate(f.get("dup_groups", [])):
        print(f'check-4b: dup-group g{i + 1} docs={len(rs)} pct={fpct(pct(len(rs), n))} sample="{fp[:60]}"')
    if not f.get("dup_groups"):
        print("check-4b: none")
    if f.get("link_dense"):
        print(f'check-4c: link-dense docs={len(f["link_dense"])} pct={fpct(pct(len(f["link_dense"]), n))} '
              f'sample="{fmt_samples(f["link_dense"])}"')
    else:
        print("check-4c: none")
    d4_docs = f.get("empty", []) + f.get("thin", [])
    d4_sample = f' sample="{fmt_samples(d4_docs)}"' if d4_docs else ""
    print(f'check-4d: empty={len(f.get("empty", []))} thin={len(f.get("thin", []))} '
          f'pct={fpct(pct(len(d4_docs), n))}{d4_sample}')
    for s in sorted(by_source_sampled):
        se = sum(1 for r in f.get("empty", []) if r["source"] == s)
        if by_source_sampled[s] and pct(se, by_source_sampled[s]) > 50:
            print(f"source-verdict: {disp[s]} 空佔位 >50%，該來源整體不適合納入")
    for name, rs in f.get("artifacts", {}).items():
        print(f'check-4e: {name} docs={len(rs)} pct={fpct(pct(len(rs), n))} sample="{fmt_samples(rs)}"')
    if not f.get("artifacts"):
        print("check-4e: none")
    if f.get("structure_docs"):
        detail = " ".join(f"{k}={v}" for k, v in f["structure"].items() if v)
        n_struct = len(f["structure_docs"])
        print(f'check-4f: docs={n_struct} pct={fpct(pct(n_struct, n))} {detail} '
              f'sample="{fmt_samples(f["structure_docs"])}"')
    else:
        print("check-4f: none")
    mp = f.get("meta_prefix_docs", [])
    mp_sample = f' sample="{fmt_samples(mp)}"' if mp else ""
    print(f'check-4g: metadata-prefix docs={len(mp)} pct={fpct(pct(len(mp), n))} '
          f'content-ratio={fpct(f.get("meta_prefix_ratio", 0.0))}{mp_sample}')
    red_docs, red_base_docs = f.get("redundancy", ([], []))
    if red_base_docs:
        print(f'check-4g: field-redundancy docs={len(red_docs)}/{len(red_base_docs)} '
              f'pct={fpct(pct(len(red_docs), len(red_base_docs)))} sample="{fmt_samples(red_docs)}"')
    else:
        print("check-4g: field-redundancy SKIP（無獨立 metadata 欄位）")
    print(f'check-4h: opening-uniqueness={fpct(f.get("opening_uniq", 100.0))}')
    for key, label in (("undersize", "undersize"), ("oversize", "oversize")):
        rs = f.get(key, [])
        tail = f' sample="{fmt_samples(rs)}"' if rs else ""
        print(f"check-4h: {label} docs={len(rs)} pct={fpct(pct(len(rs), n))}{tail}")
    if f.get("huge"):
        print(f'check-4h: huge docs={len(f["huge"])} pct={fpct(pct(len(f["huge"]), n))}'
              f'（>100k 字元，疑解析錯誤）sample="{fmt_samples(f["huge"])}"')
    if f.get("selfcont") is None:
        print("check-4h: self-containment SKIP（無 chunk 欄位）")
    else:
        bad, non_first = f["selfcont"]
        sc_sample = f' sample="{fmt_samples(bad)}"' if bad else ""
        print(f"check-4h: self-containment bad={len(bad)}/{len(non_first)} "
              f"pct={fpct(pct(len(bad), len(non_first)))}{sc_sample}")
    for cid, msg in f["errors"]:
        print(f"check-error: {cid} 未執行成功（{msg}）——該項不計分，分數偏樂觀")

    # ---- 扣分帳目（統一管線：文件集 → per-source 門檻行 → 加權 → 統一註記）----
    # 橫切規則（H3 路由、sample=、豁免註記、per-source 可見度）只在這條管線履行一次，
    # 不逐 check 手寫——新增檢查項時加進 items 表即可。
    def uniq_docs(groups):
        seen, out = set(), []
        for rs in groups:
            for r in rs:
                if r["id"] not in seen:
                    seen.add(r["id"])
                    out.append(r)
        return out

    noise_docs = uniq_docs([c["docs"] for c in clusters if cluster_class[c["id"]] == "noise"])
    dup_docs = uniq_docs([rs for _, rs in f.get("dup_groups", [])])
    art_docs = uniq_docs(list(f.get("artifacts", {}).values()))

    ledger_clean, ledger_rag, psrc_lines = [], [], []

    def annotate(cid, label, detail, ded):
        """統一豁免/扣分註記——被豁免的扣分一律留 0 分帳目行，任何維度都不靜默。"""
        target = ledger_clean if cid in CLEAN_RULES else ledger_rag
        if cid in exempts:
            if ded > 0:
                target.append(f"{cid} 0（{label} {detail}，已豁免 --exempt）")
            return 0.0
        if ded > 0:
            target.append(f"{cid} -{ded:.1f}（{label} {detail}）")
        return ded

    def score_item(cid, label, docs, rules):
        ids = {r["id"] for r in docs}
        gp = pct(len(ids), n)
        sp_map = per_source_pcts(sampled, ids)
        if len(by_source_sampled) > 1:  # 單一來源時 per-source 行只是全域行的複本
            for s in sorted(sp_map):
                if tier_deduction(rules[cid], sp_map[s]) > 0:
                    psrc_lines.append(f"check-{cid}@{disp[s]}: pct={fpct(sp_map[s])}（達扣分門檻）")
        ded, driver = weighted_deduction(cid, rules, gp, sp_map, shares)
        return annotate(cid, label, f"{fpct(gp)}，driver={disp.get(driver, driver)}", ded)

    clean, rag = 100.0, 100.0
    for cid, label, docs in [("4a", "noise 前綴", noise_docs),
                             ("4b", "內容重複", dup_docs),
                             ("4c", "連結密度", f.get("link_dense", [])),
                             ("4d", "內容過短", d4_docs),
                             ("4e", "web 殘留", art_docs),
                             ("4f", "結構異常", f.get("structure_docs", []))]:
        clean -= score_item(cid, label, docs, CLEAN_RULES)
    for cid, label, docs in [("4h-undersize", "chunk 過短", f.get("undersize", [])),
                             ("4h-oversize", "chunk 過長", f.get("oversize", [])),
                             ("4h-huge", "災難性大小", f.get("huge", []))]:
        rag -= score_item(cid, label, docs, RAG_RULES)

    # 特例規則項：規則形狀不同（無法走 tier 表迴圈），但 per-source 可見度與
    # 加權取嚴與標準項一致——小來源的嚴重問題不得被全域稀釋（F2）
    def by_src(docs):
        m = {}
        for r in docs:
            m.setdefault(r["source"], []).append(r)
        return m

    def score_special(cid, label, global_detail, global_ded, per_source):
        """per_source: {source: (detail, ded)}——@source 門檻行 + 同一套佔比加權保底半額。"""
        if len(by_source_sampled) > 1:
            for s in sorted(per_source):
                det, sded = per_source[s]
                if sded > 0:
                    psrc_lines.append(f"check-{cid}@{disp[s]}: {det}（達扣分門檻）")
        ded, driver = global_ded, "global"
        for s in sorted(per_source):
            sded = per_source[s][1]
            if sded <= 0:
                continue
            w = max(sded * shares[s] / 100.0, sded / 2.0)
            if w > ded:
                ded, driver = w, s
        return annotate(cid, label, f"{global_detail}，driver={disp.get(driver, driver)}", ded)

    def prefix_ded(docpct, ratio):
        if docpct > G_PREFIX_DOCPCT:
            return 20.0 if ratio > G_PREFIX_RATIO else 10.0
        return 0.0

    ratio_map = f.get("meta_prefix_ratios", {})
    mp_pct = pct(len(mp), n)
    mp_ratio = f.get("meta_prefix_ratio", 0.0)
    ps = {}
    for s, rs in by_src(mp).items():
        docpct_s = pct(len(rs), by_source_sampled.get(s, 0))
        ratio_s = sum(ratio_map.get(r["id"], 0.0) for r in rs) / len(rs)
        ps[s] = (f"docs={fpct(docpct_s)} content-ratio={fpct(ratio_s)}",
                 prefix_ded(docpct_s, ratio_s))
    rag -= score_special("4g-prefix", "metadata 混入",
                         f"docs={fpct(mp_pct)} content-ratio={fpct(mp_ratio)}",
                         prefix_ded(mp_pct, mp_ratio), ps)

    if red_base_docs:
        rp = pct(len(red_docs), len(red_base_docs))
        red_by_s = by_src(red_docs)
        ps = {}
        for s, base_rs in by_src(red_base_docs).items():
            rp_s = pct(len(red_by_s.get(s, [])), len(base_rs))
            ps[s] = (f"pct={fpct(rp_s)}", tier_deduction(RAG_RULES["4g-redundancy"], rp_s))
        rag -= score_special("4g-redundancy", "欄位冗餘", fpct(rp),
                             tier_deduction(RAG_RULES["4g-redundancy"], rp), ps)

    def opening_ded(u):
        return 15.0 if u < H_OPENING_SEVERE else (8.0 if u < H_OPENING_WARN else 0.0)

    uniq = f.get("opening_uniq", 100.0)
    op_by_s = {}
    for r, o in f.get("openings", []):
        op_by_s.setdefault(r["source"], []).append(o)
    ps = {}
    for s, os_ in op_by_s.items():
        u_s = pct(len(set(os_)), len(os_))
        ps[s] = (f"opening-uniqueness={fpct(u_s)}", opening_ded(u_s))
    rag -= score_special("4h-opening", "開頭區分度", fpct(uniq), opening_ded(uniq), ps)

    if f.get("selfcont"):
        bad, non_first = f["selfcont"]
        cp = pct(len(bad), len(non_first))
        bad_by_s = by_src(bad)
        ps = {}
        for s, nf in by_src(non_first).items():
            cp_s = pct(len(bad_by_s.get(s, [])), len(nf))
            ps[s] = (f"pct={fpct(cp_s)}", tier_deduction(RAG_RULES["4h-selfcont"], cp_s))
        rag -= score_special("4h-selfcont", "自足性差", fpct(cp),
                             tier_deduction(RAG_RULES["4h-selfcont"], cp), ps)

    clean_i, rag_i = max(0, int(clean + 0.5)), max(0, int(rag + 0.5))
    composite = int(CLEAN_WEIGHT * clean_i + RAG_WEIGHT * rag_i + 0.5)
    for line in psrc_lines:
        print(line)
    for line in ledger_clean:
        print(f"ledger-clean: {line}")
    for line in ledger_rag:
        print(f"ledger-rag: {line}")
    print(f"score: clean={clean_i} rag={rag_i} composite={composite}"
          f"（清潔 {int(CLEAN_WEIGHT * 100)}% + RAG {int(RAG_WEIGHT * 100)}%）")
    bands = [(90, "優良（90-100）：可直接用於 RAG"),
             (70, "尚可（70-89）：有改善空間，不影響大部分查詢"),
             (50, "需改善（50-69）：會影響檢索品質"),
             (0, "嚴重（<50）：需要重新處理")]
    print(f"verdict: {next(t for th, t in bands if composite >= th)}")
    if clusters:
        print("hint: 覆核 check-4a 各 cluster 分類與範例；不同意用 "
              "--classify pN=<noise|metadata|artifact|false-positive> 重跑；"
              "context 豁免（如技術站 HTML 為正文）用 --exempt <check-id> 重跑")


if __name__ == "__main__":
    main()
