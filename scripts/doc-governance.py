#!/usr/bin/env python3
from __future__ import annotations
import argparse
from collections import Counter
from dataclasses import dataclass, field
import datetime as dt
import fnmatch
from functools import cache
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import unicodedata
CONFIG_NAME = '.doc-governance.json'
MODES = {'loaded', 'active', 'routed', 'history', 'derived', 'governance'}
FINAL_PLAN_STATES = {'implemented', 'superseded'}
ACTIVE_PLAN_STATES = {'draft', 'approved', 'in-progress'}
PLAN_STATES = FINAL_PLAN_STATES | ACTIVE_PLAN_STATES
FENCE_RE = re.compile('^(?P<indent> {0,3})(?P<fence>`{3,}|~{3,})(?P<info>.*)$')
HEADING_RE = re.compile('^(#{1,6})\\s+(.*)$')
TOP_BULLET_RE = re.compile('^([-+*])\\s+(.*)$')
COMMENT_RE = re.compile('<!--.*?-->', re.S)
DATE_RE = re.compile('(?<!\\d)(\\d{4}-\\d{2}-\\d{2})(?!\\d)')
STABLE_ID_RE = re.compile('\\b([DXM])-(\\d{8})-([a-z0-9][a-z0-9-]*)\\b')
DECLARED_ID_RE = re.compile('^\\s*(?:\\*\\*)?(?P<id>[DXMB]-\\d{8}-[a-z0-9][a-z0-9-]*)\\b')
REF_RE = re.compile('(?:(?:`(?P<quoted>[^`\\n]+?\\.(?:md|sh))`|(?P<bare>[A-Za-z0-9_./~-]+?\\.(?:md|sh)))|(?P<local>(?<![A-Za-z0-9_\\u4e00-\\u9fff])見(?:上方|下方|本檔|本節)?))[「『](?P<section>[^」』\\n]{1,80})[」』]')
SECTION_MIN = 2
EVENT_SECTION = '事件記錄（event-time）'
MAX_RESULTS = 5
MAX_EXCERPT_BYTES = 240
MAX_STDOUT_BYTES = 8192
TILDE_MAP = (('~/.claude/skills/', 'claude/skills/'), ('~/.codex/skills/', 'codex/skills/'), ('~/.dotfiles/', ''))
METRICS = ('dated_records', 'struck_records', 'checkbox_records', 'undated_records', 'h2_sections', 'empty_h2_sections', 'file_preamble_entries', 'legacy_type_file_mismatches')

class ScannerError(RuntimeError):
  pass

@dataclass
class DocClass:
  name: str
  mode: str
  paths: list[str]
  unit: str = 'h2'
  requires_inbound: bool = False
  governed_sections: tuple[str, ...] = ()

@dataclass
class Config:
  root: Path
  raw: dict
  classes: list[DocClass]

  @property
  def history_paths(self):
    return self.raw['history_paths']

@dataclass
class Document:
  root: Path
  rel: str
  path: Path
  text: str
  lines: list[str]
  visible: list[str]
  doc_class: DocClass | None = None

  @classmethod
  def from_text(cls, root, rel, text, doc_class=None):
    path = root / rel
    lines = text.splitlines()
    return cls(root=root, rel=rel, path=path, text=text, lines=lines, visible=visible_lines(text), doc_class=doc_class)

  @classmethod
  def read(cls, root, rel, doc_class=None):
    path = root / rel
    try:
      text = path.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError) as exc:
      raise ScannerError(f'read {rel}: {exc}') from exc
    return cls.from_text(root, rel, text, doc_class)

  def visible_line(self, index):
    return self.visible[index]

  def source_lines(self):
    masked = fence_mask(self.lines)
    for index, line in enumerate(self.lines):
      if line and not masked[index]:
        yield (index + 1, line)

  def target_lines(self):
    for index in range(len(self.lines)):
      line = self.visible_line(index)
      if line:
        yield line

  def has_section(self, section):
    wanted = xref_norm(section)
    return any((match := HEADING_RE.match(line)) and xref_norm(match.group(2)).startswith(wanted) for line in self.target_lines())

  def has_body(self, section):
    wanted = xref_norm(section)
    return any(not HEADING_RE.match(line) and wanted in xref_norm(line) for line in self.target_lines())

  def h2_sections(self):
    for index in range(len(self.lines)):
      line = self.visible_line(index)
      match = HEADING_RE.match(line)
      if match and match.group(1) == '##':
        yield (index + 1, match.group(2).strip())

@dataclass
class Entry:
  path: str
  line: int
  title: str
  body: str
  visible_body: str
  section: str
  entry_type: str
  event_date: str = 'unknown'
  shape: str = 'section'
  stable_id: str | None = None
  doc_class: DocClass | None = None
  metadata: dict[str, str] = field(default_factory=dict)
  closed: bool = False

def run_git(root, args, *, allow_failure=False):
  proc = subprocess.run(['git', '-C', str(root), *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
  if proc.returncode and (not allow_failure):
    raise ScannerError(f"git {' '.join(args)}: {proc.stderr.strip()}")
  return proc.stdout

def resolve_root(value):
  if value:
    root = Path(value).expanduser().resolve()
    if not root.is_dir():
      raise ScannerError(f'--root not directory: {root}')
    return root
  proc = subprocess.run(['git', 'rev-parse', '--show-toplevel'], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
  if proc.returncode:
    raise ScannerError('no git toplevel from cwd')
  return Path(proc.stdout.strip()).resolve()

def validate_relpath(value, label):
  path = Path(value)
  if path.is_absolute() or '..' in path.parts:
    raise ScannerError(f'config {label} escapes root: {value}')

def need(condition, message):
  if not condition:
    raise ScannerError('config ' + message)

def load_config(root, *, optional=False):
  path = root / CONFIG_NAME
  if not path.is_file():
    if optional:
      return None
    raise ScannerError(f'config missing: {CONFIG_NAME}')
  try:
    raw = json.loads(path.read_text(encoding='utf-8'))
  except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
    raise ScannerError(f'config parse: {exc}') from exc
  need(isinstance(raw, dict), 'root must be object')
  need(raw.get('schema') == 1, 'schema must be 1')
  history = raw.get('history_paths')
  need(isinstance(history, dict) and set(history) == {'decision', 'dead_end', 'milestone'}, 'history_paths invalid')
  for kind, pattern in history.items():
    need(isinstance(pattern, str) and '{YYYY-MM}' in pattern, f'history_paths.{kind} needs {{YYYY-MM}}')
    validate_relpath(pattern.replace('{YYYY-MM}', '2000-01'), f'history_paths.{kind}')
  need(isinstance(raw.get('classes'), list), 'classes must be list')
  classes = []
  names = set()
  for index, item in enumerate(raw['classes']):
    need(isinstance(item, dict), f'classes[{index}] must be object')
    name, mode, paths = (item.get('name'), item.get('mode'), item.get('paths'))
    need(isinstance(name, str) and name and name not in names, f'classes[{index}] name invalid')
    need(mode in MODES, f'class {name} mode invalid: {mode}')
    need(mode != 'derived' or isinstance(item.get('rebuild'), str) and item['rebuild'].strip(), f'class {name} needs rebuild')
    need(isinstance(paths, list) and paths and all(isinstance(p, str) for p in paths), f'class {name} paths invalid')
    for pattern in paths:
      validate_relpath(pattern, f'class {name} path')
    unit = item.get('unit', 'h2')
    need(unit in {'h2', 'top_level_bullet'}, f'class {name} unit invalid: {unit}')
    governed_sections = item.get('governed_sections')
    if governed_sections is not None:
      need(isinstance(governed_sections, list) and bool(governed_sections) and all(isinstance(section, str) and section for section in governed_sections), f'class {name} governed_sections invalid')
    if name == 'backlog':
      need(governed_sections is not None, 'class backlog needs governed_sections')
    names.add(name)
    classes.append(DocClass(name=name, mode=mode, paths=paths, unit=unit, requires_inbound=bool(item.get('requires_inbound', False)), governed_sections=tuple(governed_sections or ())))
  legacy = raw.get('legacy_plan_blobs', {})
  need(isinstance(legacy, dict) and all(isinstance(rel, str) and isinstance(blob, str) for rel, blob in legacy.items()), 'legacy_plan_blobs must be string map')
  for rel in legacy:
    validate_relpath(rel, 'legacy_plan_blobs path')
  searchable = raw.get('searchable_legacy_plans', [])
  need(isinstance(searchable, list) and all(isinstance(rel, str) for rel in searchable) and set(searchable) <= set(legacy), 'searchable_legacy_plans invalid')
  for rel in searchable:
    validate_relpath(rel, 'searchable_legacy_plans path')
  plan_dir = raw.get('plan_dir', 'docs/plans')
  need(isinstance(plan_dir, str) and plan_dir, 'plan_dir invalid')
  validate_relpath(plan_dir, 'plan_dir')
  budgets = raw.get('loaded_budgets', {})
  need(isinstance(budgets, dict), 'loaded_budgets must be object')
  for pattern, rule in budgets.items():
    need(isinstance(pattern, str) and pattern, 'loaded_budgets pattern invalid')
    validate_relpath(pattern, 'loaded_budgets pattern')
    need(isinstance(rule, dict) and bool(rule) and set(rule) <= {'bytes', 'lines'} and all(type(value) is int and value > 0 for value in rule.values()), f'loaded_budgets.{pattern} invalid')
  external = raw.get('external_reference_targets', [])
  need(isinstance(external, list) and all((isinstance(item, str) and item for item in external)), 'external_reference_targets invalid')
  for target in external:
    validate_relpath(target, 'external_reference_targets entry')
  status = raw.get('status_schema')
  if status is not None:
    allowed = {'path', 'required_headings', 'forbidden_headings', 'stale_days'}
    need(isinstance(status, dict) and bool(status) and set(status) <= allowed, 'status_schema invalid')
    if 'path' in status:
      need(isinstance(status['path'], str) and status['path'], 'status_schema.path invalid')
      validate_relpath(status['path'], 'status_schema.path')
    for key in ('required_headings', 'forbidden_headings'):
      if key in status:
        need(isinstance(status[key], list) and all(isinstance(item, str) and item for item in status[key]), f'status_schema.{key} invalid')
    if 'stale_days' in status:
      need(type(status['stale_days']) is int and status['stale_days'] > 0, 'status_schema.stale_days invalid')
  need(isinstance(raw.get('governance_surface', []), list), 'governance_surface must be list')
  return Config(root=root, raw=raw, classes=classes)

def tracked_markdown(root, *, xref=False):
  patterns = ['*.md', '*.sh'] if xref else ['*.md']
  output = run_git(root, ['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', *patterns])
  return sorted(item for item in output.split('\x00') if item and (root / item).is_file())

def missing_tracked_markdown(root):
  output = run_git(root, ['ls-files', '-z', '--cached', '--', '*.md'])
  return sorted(item for item in output.split('\x00') if item and not (root / item).is_file())

def indexed_markdown(root):
  output = run_git(root, ['ls-files', '-z', '--cached', '--', '*.md'])
  return sorted(item for item in output.split('\x00') if item)

def matching_classes(rel, config):
  return [cls for cls in config.classes if any(fnmatch.fnmatchcase(rel, pattern) for pattern in cls.paths)]

def fence_mask(lines):
  mask = [False] * len(lines)
  in_fence = False
  fence_char = ''
  fence_len = 0
  for index, line in enumerate(lines):
    match = FENCE_RE.match(line)
    if not match:
      mask[index] = in_fence
      continue
    char = match.group('fence')[0]
    length = len(match.group('fence'))
    if not in_fence:
      in_fence, fence_char, fence_len = (True, char, length)
      mask[index] = True
    elif char == fence_char and length >= fence_len and (not match.group('info').strip()):
      in_fence = False
      mask[index] = True
    else:
      mask[index] = True
  return mask

def visible_lines(text):
  clean = COMMENT_RE.sub(lambda match: re.sub('[^\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]', ' ', match.group()), text)
  lines = clean.splitlines()
  masked = fence_mask(lines)
  return ['' if masked[index] else line for index, line in enumerate(lines)]

def strip_markdown(value):
  value = re.sub('^\\[[ xX]\\]\\s*', '', value)
  value = value.strip().strip('~')
  value = re.sub('[*_`]', '', value)
  return re.sub('\\s+', ' ', value).strip()

def first_date(value):
  match = DATE_RE.search(value)
  return match.group(1) if match else 'unknown'

def declared_id(value, prefixes):
  match = DECLARED_ID_RE.match(value)
  if not match or match.group('id')[0] not in prefixes:
    return (None, None)
  return (match.group('id'), match)

def declared_ids(doc, prefixes, sections=None):
  entries, _ = parse_top_level_entries(doc)
  return {
    entry.stable_id
    for entry in entries
    if entry.stable_id and entry.stable_id[0] in prefixes and (sections is None or any(section_matches(entry.section, section) for section in sections))
  }

def parse_metadata(lines):
  metadata = {}
  for line in lines:
    match = re.match('^\\s{2,}-\\s*([^:：]+)[:：]\\s*(.*)$', line)
    if match:
      metadata[match.group(1).strip()] = match.group(2).strip()
  return metadata

def infer_legacy_type(doc, section, shape):
  if '技術債' in section:
    return 'legacy-closed-debt'
  if '死路' in section:
    return 'legacy-dead-end'
  h1 = next((match.group(2) for index in range(len(doc.lines)) if (match := HEADING_RE.match(doc.visible_line(index))) and match.group(1) == '#'), '')
  if '決策' in h1 and shape in {'dated', 'struck'}:
    return 'legacy-decision'
  return 'legacy-unknown'

def zero_metrics():
  return dict.fromkeys(METRICS, 0)

def parse_top_level_entries(doc):
  entries = []
  metrics = zero_metrics()
  section = 'file-preamble'
  section_has_entry = False
  seen_h2 = False
  index = 0
  while index < len(doc.lines):
    visible = doc.visible_line(index)
    heading = HEADING_RE.match(visible)
    if heading and heading.group(1) == '##':
      if seen_h2 and (not section_has_entry):
        metrics['empty_h2_sections'] += 1
      section = heading.group(2).strip()
      metrics['h2_sections'] += 1
      section_has_entry = False
      seen_h2 = True
      index += 1
      continue
    bullet = TOP_BULLET_RE.match(visible)
    if not bullet:
      index += 1
      continue
    start = index
    block = [doc.lines[index]]
    index += 1
    while index < len(doc.lines):
      candidate = doc.visible_line(index)
      if TOP_BULLET_RE.match(candidate):
        break
      candidate_heading = HEADING_RE.match(candidate)
      if candidate_heading and candidate_heading.group(1) in {'#', '##'}:
        break
      block.append(doc.lines[index])
      index += 1
    raw_title = bullet.group(2).strip()
    checkbox = bool(re.match('^\\[[ xX]\\]\\s*', raw_title))
    after_checkbox = re.sub('^\\[[ xX]\\]\\s*', '', raw_title)
    struck = after_checkbox.startswith('~~')
    title = strip_markdown(raw_title)
    if checkbox:
      shape = 'checkbox'
    elif struck:
      shape = 'struck'
    elif re.match('^\\d{4}-\\d{2}-\\d{2}\\b', title):
      shape = 'dated'
    else:
      shape = 'undated'
    metrics[f'{shape}_records'] += 1
    if section == 'file-preamble':
      metrics['file_preamble_entries'] += 1
    stable_id, stable_match = declared_id(raw_title, 'DXMB')
    event_date = first_date(title)
    visible_block = doc.visible[start:index]
    metadata = parse_metadata(visible_block[1:])
    closure_tail = raw_title[stable_match.end():] if stable_match else raw_title
    closure_tail = re.sub('^[\\s*_·:：.\\-]+', '', closure_tail)
    checked_closed = bool(re.match('^\\[[xX]\\]\\s*', closure_tail))
    closure_tail = re.sub('^\\[[ xX]\\]\\s*', '', closure_tail)
    struck_closed = closure_tail.startswith('~~')
    if stable_id:
      prefix = stable_id[0]
      entry_type = {'D': 'decision', 'X': 'dead_end', 'M': 'milestone', 'B': 'backlog'}[prefix]
    else:
      stable_id = None
      entry_type = infer_legacy_type(doc, section, shape)
      if entry_type not in {'legacy-decision', 'legacy-unknown'} and 'decisions-' in doc.rel:
        metrics['legacy_type_file_mismatches'] += 1
    entries.append(Entry(path=doc.rel, line=start + 1, title=title, body='\n'.join(block), visible_body='\n'.join(visible_block), section=section, entry_type=entry_type, event_date=event_date, shape=shape, stable_id=stable_id, doc_class=doc.doc_class, metadata=metadata, closed=checked_closed or struck_closed))
    section_has_entry = True
  if seen_h2 and (not section_has_entry):
    metrics['empty_h2_sections'] += 1
  return (entries, metrics)

def parse_h2_entries(doc):
  headings = []
  for index in range(len(doc.lines)):
    match = HEADING_RE.match(doc.visible_line(index))
    if match and match.group(1) in {'#', '##'}:
      headings.append((index, match.group(1), match.group(2).strip()))
  entries = []
  h1 = next((item for item in headings if item[1] == '#'), None)
  h2s = [item for item in headings if item[1] == '##']
  if h1:
    end = h2s[0][0] if h2s else len(doc.lines)
    body = '\n'.join(doc.lines[h1[0]:end])
    entries.append(Entry(path=doc.rel, line=h1[0] + 1, title=strip_markdown(h1[2]), body=body, visible_body='\n'.join(doc.visible[h1[0]:end]), section='file-preamble', entry_type=doc.doc_class.name if doc.doc_class else 'document', doc_class=doc.doc_class))
  elif doc.lines:
    end = h2s[0][0] if h2s else len(doc.lines)
    entries.append(Entry(path=doc.rel, line=1, title=Path(doc.rel).name, body='\n'.join(doc.lines[:end]), visible_body='\n'.join(doc.visible[:end]), section='file-preamble', entry_type=doc.doc_class.name if doc.doc_class else 'document', doc_class=doc.doc_class))
  for position, (index, _, title) in enumerate(h2s):
    end = h2s[position + 1][0] if position + 1 < len(h2s) else len(doc.lines)
    entries.append(Entry(path=doc.rel, line=index + 1, title=strip_markdown(title), body='\n'.join(doc.lines[index:end]), visible_body='\n'.join(doc.visible[index:end]), section=title, entry_type=doc.doc_class.name if doc.doc_class else 'document', doc_class=doc.doc_class))
  metrics = zero_metrics()
  metrics.update(h2_sections=len(h2s), file_preamble_entries=1 if entries else 0)
  return (entries, metrics)

def build_documents(config):
  documents = []
  classification = {}
  for rel in tracked_markdown(config.root):
    matches = matching_classes(rel, config)
    classification[rel] = matches
    documents.append(Document.read(config.root, rel, matches[0] if len(matches) == 1 else None))
  return (documents, classification)

def build_entries(documents):
  all_entries = []
  totals = zero_metrics()
  for doc in documents:
    if not doc.doc_class:
      continue
    if doc.doc_class.unit == 'top_level_bullet':
      entries, metrics = parse_top_level_entries(doc)
    else:
      entries, metrics = parse_h2_entries(doc)
    all_entries.extend(entries)
    for key, value in metrics.items():
      totals[key] += value
  return (all_entries, totals)

@cache
def search_norm(value):
  return ' '.join(unicodedata.normalize('NFKC', value).casefold().split())

@cache
def search_tokens(value):
  normalized = search_norm(value)
  tokens = set(re.findall('[a-z0-9]+(?:[-_./:][a-z0-9]+)*', normalized))
  for run in re.findall('[\\u3400-\\u9fff]+', normalized):
    if len(run) == 1:
      tokens.add(run)
    else:
      tokens.update((run[index:index + 2] for index in range(len(run) - 1)))
  if '✅' in normalized:
    tokens.add('✅')
  return tokens

def entry_score(entry, query, query_tokens):
  query_norm = search_norm(query)
  title_norm = search_norm(entry.title)
  body_norm = search_norm(entry.body)
  title_tokens = search_tokens(entry.title)
  body_tokens = search_tokens(entry.body)
  score = 0
  if query_norm == title_norm:
    score += 50000
  if entry.stable_id and query_norm == entry.stable_id.casefold():
    score += 100000
  if len(query_norm) >= 3 and query_norm in title_norm:
    score += 10000
  if len(query_norm) >= 5 and query_norm in body_norm:
    score += 2000
  title_hits = len(query_tokens & title_tokens)
  body_hits = len(query_tokens & body_tokens)
  score += title_hits * 200 + body_hits * 20
  if query_tokens and query_tokens <= title_tokens:
    score += 1000
  if query_tokens and query_tokens <= body_tokens:
    score += 500
  aliases = entry.metadata.get('別名', '') + ' ' + entry.metadata.get('標籤', '')
  score += len(query_tokens & search_tokens(aliases)) * 80
  asks_for_reason = any(marker in query_norm for marker in ('為什麼', '原因', '理由', 'why'))
  if score and asks_for_reason and entry.doc_class and (entry.doc_class.mode == 'history'):
    score += 800
  return score

def bounded_text(value, byte_limit):
  compact = re.sub('\\s+', ' ', value).strip()
  data = compact.encode('utf-8')
  if len(data) <= byte_limit:
    return compact
  clipped = data[:max(0, byte_limit - 3)]
  while clipped:
    try:
      return clipped.decode('utf-8') + '...'
    except UnicodeDecodeError:
      clipped = clipped[:-1]
  return '...'

def diversified(ranked, limit, per_file=2):
  # 一份檔案裡的條目數不該決定它拿幾個 slot：archive shard 動輒上百條，排序完直接
  # 切前 N 會讓它把其他來源整批洗掉（實測 20 題有 2 題 top-5 全同一份 shard）。
  # 先每檔取 per_file，額度用完再回填——cap 只調來源分布，NEVER 減少結果數。
  chosen, counts = [], {}
  for item in ranked:
    if counts.get(item[1], 0) >= per_file:
      continue
    counts[item[1]] = counts.get(item[1], 0) + 1
    chosen.append(item)
    if len(chosen) == limit:
      return chosen
  taken = {id(item) for item in chosen}
  for item in ranked:
    if id(item) in taken:
      continue
    chosen.append(item)
    if len(chosen) == limit:
      break
  return chosen

def cmd_find(config, query, limit):
  documents, _ = build_documents(config)
  excluded = hidden_legacy_plans(config)
  documents = [doc for doc in documents if doc.rel not in excluded]
  entries, _ = build_entries(documents)
  query_tokens = search_tokens(query)
  ranked = [(entry_score(entry, query, query_tokens), entry.path, entry.line, entry) for entry in entries]
  ranked = [item for item in ranked if item[0] > 0]
  ranked.sort(key=lambda item: (-item[0], item[1], item[2]))
  if not ranked:
    return 1
  output = bytearray()
  for _, _, _, entry in diversified(ranked, min(limit, MAX_RESULTS)):
    first = f'{entry.path}:{entry.line} type={entry.entry_type} event_date={entry.event_date} section={entry.section} — {entry.title}\n'
    excerpt = f'  {bounded_text(entry.body, MAX_EXCERPT_BYTES)}\n'
    candidate = (first + excerpt).encode('utf-8')
    if len(output) + len(candidate) > MAX_STDOUT_BYTES:
      break
    output.extend(candidate)
  sys.stdout.buffer.write(output)
  return 0

def class_findings(config, classification):
  findings = []
  for rel, matches in classification.items():
    if not matches:
      findings.append(f'unclassified: {rel}')
    elif len(matches) > 1:
      findings.append(f"multi-class: {rel} -> {','.join((cls.name for cls in matches))}")
  tracked = set(classification)
  for cls in config.classes:
    for pattern in cls.paths:
      if not any(fnmatch.fnmatchcase(rel, pattern) for rel in tracked):
        findings.append(f'class glob 無匹配: {cls.name}:{pattern}')
  return findings

def expected_history_path(config, entry_type, event_date):
  if event_date == 'unknown' or entry_type not in config.history_paths:
    return None
  return config.history_paths[entry_type].replace('{YYYY-MM}', event_date[:7])

def baseline_legacy_counts(config, entries, baseline):
  counts = Counter()
  if not baseline:
    return counts
  classes_by_path = {
    entry.path: entry.doc_class
    for entry in entries
    if entry.doc_class and entry.doc_class.mode == 'history'
  }
  for rel, doc_class in classes_by_path.items():
    text = ref_text(config.root, baseline, rel)
    if text is None:
      continue
    prior, _ = parse_top_level_entries(Document.from_text(config.root, rel, text, doc_class))
    counts.update((entry.path, entry.visible_body.rstrip()) for entry in prior if not entry.stable_id)
  return counts

def history_findings(config, entries, baseline):
  findings = []
  ids = {}
  supersedes = []
  legacy_counts = baseline_legacy_counts(config, entries, baseline)
  for entry in entries:
    if not entry.doc_class or entry.doc_class.mode != 'history':
      continue
    if not entry.stable_id:
      key = (entry.path, entry.visible_body.rstrip())
      existed_at_baseline = legacy_counts[key] > 0
      if existed_at_baseline:
        legacy_counts[key] -= 1
      if section_matches(entry.section, EVENT_SECTION) or (baseline and not existed_at_baseline):
        findings.append(f'history ID missing: {entry.path}:{entry.line}')
      continue
    if entry.stable_id in ids:
      findings.append(f'duplicate history ID: {entry.stable_id} at {ids[entry.stable_id].path}:{ids[entry.stable_id].line} and {entry.path}:{entry.line}')
    ids[entry.stable_id] = entry
    id_date = f'{entry.stable_id[2:6]}-{entry.stable_id[6:8]}-{entry.stable_id[8:10]}'
    if entry.event_date != id_date:
      findings.append(f'history date mismatch: {entry.path}:{entry.line} {entry.stable_id}')
    expected = expected_history_path(config, entry.entry_type, id_date)
    if expected and expected != entry.path:
      expected_family = config.history_paths[entry.entry_type].split('-')[0]
      actual_family = entry.path.split('-')[0]
      if expected_family != actual_family:
        label = 'type/file mismatch'
      else:
        label = 'event-month/file mismatch'
      findings.append(f'{label}: {entry.path}:{entry.line} expected {expected}')
    if not section_matches(entry.section, EVENT_SECTION):
      findings.append(f'new history record outside event-time section: {entry.path}:{entry.line}')
    source = entry.metadata.get('日期來源')
    if source not in {'direct', 'migration-entry', 'migration-cutover'}:
      findings.append(f'history 日期來源 missing/invalid: {entry.path}:{entry.line}')
    for target in re.findall('supersedes:([DXM]-\\d{8}-[a-z0-9-]+)', entry.visible_body):
      supersedes.append((entry, target))
  for entry, target in supersedes:
    if target not in ids:
      findings.append(f'supersedes target missing: {entry.path}:{entry.line} -> {target}')
  return findings

def file_blob(root, rel):
  return run_git(root, ['hash-object', '--', rel]).strip()

def ref_blob(root, ref, rel):
  output = run_git(root, ['ls-tree', ref, '--', rel], allow_failure=True).strip()
  match = re.match(r'^\d+\s+blob\s+([0-9a-f]+)\t', output)
  return match.group(1) if match else None

def ref_text(root, ref, rel):
  if not ref_blob(root, ref, rel):
    return None
  return run_git(root, ['show', f'{ref}:{rel}'])

def immutability_base(root):
  head = run_git(root, ['rev-parse', '--verify', 'HEAD^{commit}'], allow_failure=True).strip()
  if not head:
    return (None, 'immutability baseline unavailable: repository has no committed HEAD')
  branch = run_git(root, ['symbolic-ref', '--short', '-q', 'HEAD'], allow_failure=True).strip()
  remotes = run_git(root, ['remote'], allow_failure=True).splitlines()
  candidates = []
  for remote in remotes:
    remote_head = run_git(root, ['symbolic-ref', '--short', '-q', f'refs/remotes/{remote}/HEAD'], allow_failure=True).strip()
    candidates.extend([remote_head, f'{remote}/main', f'{remote}/master'])
  candidates.extend(['main', 'master'])
  for candidate in dict.fromkeys(item for item in candidates if item):
    target = run_git(root, ['rev-parse', '--verify', f'{candidate}^{{commit}}'], allow_failure=True).strip()
    current_feature = branch not in {'main', 'master'} and (candidate == branch or candidate.endswith('/' + branch))
    if not target or current_feature:
      continue
    base = run_git(root, ['merge-base', head, target], allow_failure=True).strip()
    if base:
      return (base, None)
  return (None, 'immutability baseline unavailable: no default branch base; immutability checks skipped')

def committed_markdown(root, baseline):
  refs = [baseline]
  refs.extend(run_git(root, ['rev-list', '--reverse', f'{baseline}..HEAD'], allow_failure=True).splitlines())
  markdown = set()
  for ref in refs:
    markdown.update(
      rel
      for rel in run_git(root, ['ls-tree', '-r', '--name-only', ref]).splitlines()
      if rel.endswith('.md')
    )
  return sorted(markdown)

def removed_immutable_findings(config, baseline):
  if not baseline:
    return []
  removed = set(committed_markdown(config.root, baseline)) - set(indexed_markdown(config.root))
  plan_dir = config.raw.get('plan_dir', 'docs/plans').rstrip('/') + '/'
  legacy = config.raw.get('legacy_plan_blobs', {})
  findings = []
  for rel in sorted(removed):
    if any(doc_class.mode == 'history' for doc_class in matching_classes(rel, config)):
      findings.append(f'history record file removed: {rel}')
    if rel.startswith(plan_dir):
      texts = committed_texts(config.root, rel, baseline)
      if any(plan_metadata(text).get('狀態') in FINAL_PLAN_STATES for text in texts):
        findings.append(f'frozen plan removed: {rel}')
    if rel in legacy:
      findings.append(f'legacy plan removed: {rel}')
  return findings

def committed_texts(root, rel, base):
  if not base:
    return []
  refs = []
  if ref_blob(root, base, rel):
    refs.append(base)
  revision = f'{base}..HEAD'
  refs.extend(run_git(root, ['rev-list', '--reverse', revision, '--', rel], allow_failure=True).splitlines())
  texts = []
  for ref in dict.fromkeys(refs):
    text = ref_text(root, ref, rel)
    if text is not None and text not in texts:
      texts.append(text)
  return texts

def history_append_findings(config, documents, baseline):
  findings = []
  for doc in documents:
    if doc.doc_class and doc.doc_class.mode == 'history':
      before = committed_texts(config.root, doc.rel, baseline)
      if any(doc.text != text and not doc.text.startswith(text) for text in before):
        findings.append(f'history not append-only: {doc.rel}')
  return findings

def plan_metadata(text):
  metadata = {}
  for line in visible_lines(text)[:20]:
    match = re.match('^-\\s*([^:：]+)[:：]\\s*(.+)$', line)
    if match:
      metadata[match.group(1).strip()] = match.group(2).strip()
  return metadata

def plan_findings(config, markdown, baseline):
  findings = []
  plan_dir = config.raw.get('plan_dir', 'docs/plans').rstrip('/') + '/'
  legacy = config.raw.get('legacy_plan_blobs', {})
  active = {}
  for rel in markdown:
    if not rel.startswith(plan_dir):
      continue
    expected_blob = legacy.get(rel)
    if expected_blob and file_blob(config.root, rel) == expected_blob:
      continue
    if re.search('(?:-v\\d+|-final|-revised)\\.md$', rel):
      findings.append(f'versioned plan filename: {rel}')
    try:
      text = (config.root / rel).read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError) as exc:
      raise ScannerError(f'read {rel}: {exc}') from exc
    meta = plan_metadata(text)
    required = {'日期', '狀態', '工作項', '種類', '需求來源'}
    missing = sorted(required - set(meta))
    if missing:
      findings.append(f"{rel}: missing plan metadata {','.join(missing)}")
      continue
    state = meta['狀態']
    if state not in PLAN_STATES:
      findings.append(f'{rel}: invalid plan status {state}')
      continue
    before = committed_texts(config.root, rel, baseline)
    if any(plan_metadata(text).get('狀態') in FINAL_PLAN_STATES and text != (config.root / rel).read_text(encoding='utf-8') for text in before):
      findings.append(f'closed plan mutation: {rel}')
    if state in ACTIVE_PLAN_STATES:
      active.setdefault(meta['工作項'], []).append(rel)
    if state == 'superseded' and '取代計畫' not in meta:
      findings.append(f'{rel}: superseded plan missing replacement')
  for work_item, paths in active.items():
    if len(paths) > 1:
      findings.append(f"duplicate active plan: {work_item} -> {','.join(sorted(paths))}")
  return findings

def budget_findings(config, documents):
  findings = []
  budgets = config.raw.get('loaded_budgets', {})
  for doc in documents:
    if not doc.doc_class or doc.doc_class.mode != 'loaded':
      continue
    matches = [(pattern, rule) for pattern, rule in budgets.items() if fnmatch.fnmatchcase(doc.rel, pattern)]
    if not matches:
      findings.append(f'loaded file missing budget: {doc.rel}')
      continue
    pattern, rule = max(matches, key=lambda item: len(item[0]))
    size = len(doc.text.encode('utf-8'))
    lines = len(doc.lines)
    if 'bytes' in rule and size > rule['bytes']:
      findings.append(f"loaded budget bytes: {doc.rel} {size}>{rule['bytes']}")
    if 'lines' in rule and lines > rule['lines']:
      findings.append(f"loaded budget lines: {doc.rel} {lines}>{rule['lines']}")
  return findings

def xref_norm(value):
  value = re.sub('`+', '', value)
  value = re.sub('[*_~]+', '', value)
  value = re.sub('^#+', '', value)
  return re.sub('[\\s（）()【】\\[\\]「」『』]', '', value)

def section_matches(heading, name):
  wanted = xref_norm(name)
  candidate = xref_norm(heading)
  if candidate.endswith(wanted):
    return True
  without_suffix = re.sub(r'\s*[（(【\[][^[\]（）()【】]*[）)】\]]\s*$', '', heading)
  return xref_norm(without_suffix).endswith(wanted)

def resolve_reference(target, source, root):
  if target.startswith('~/'):
    candidate = None
    for prefix, replacement in TILDE_MAP:
      if target.startswith(prefix):
        candidate = root / (replacement + target[len(prefix):])
        break
    if candidate is None:
      return (None, None)
    candidates = [candidate]
  else:
    candidates = []
    for candidate in (source.parent / target, root / target):
      if candidate not in candidates:
        candidates.append(candidate)
  resolved = [candidate.resolve() for candidate in candidates]
  inside = [candidate for candidate in resolved if candidate.is_relative_to(root)]
  found = next((candidate for candidate in inside if candidate.is_file()), None)
  if found:
    return (found, None)
  if not inside:
    return (None, f'解析後逃出 --root（{resolved[0]}）')
  tried = '、'.join((str(candidate.relative_to(root)) for candidate in inside))
  return (None, f'檔案不存在（試過：{tried}）')

def external_reference_targets(config):
  return set(config.raw.get('external_reference_targets', [])) if config else set()

def external_reference_findings(config, seen):
  findings = []
  for target in sorted(external_reference_targets(config)):
    if (config.root / target).is_file():
      findings.append(f'external reference target exists in repo: {target}')
    elif target not in seen:
      findings.append(f'external reference declaration unused: {target}')
  return findings

def xref_scan(root, files, *, full_scan, evidence_layers, skip_sources=None, section_aliases=None, alias_sources=None, external_targets=(), external_seen=None):
  findings = []
  cache = {}
  inbound = {}
  skipped = skip_sources or set()
  for rel in sorted(files):
    if rel in skipped:
      continue
    source = Document.read(root, rel)
    aliases = (section_aliases or []) if rel in (alias_sources or ()) else ()
    for lineno, line in source.source_lines():
      if rel.endswith('.sh') and not line.lstrip().startswith('#'):
        continue
      for match in REF_RE.finditer(line):
        target, section, local = (match.group('quoted') or match.group('bare') or rel, match.group('section'), bool(match.group('local')))
        here = f'{rel}:{lineno}: `{target}`「{section}」'
        if len(xref_norm(section)) < SECTION_MIN:
          findings.append(f'{here} — 節名 normalize 後不足 {SECTION_MIN} 字，無法比對')
          continue
        path, reason = resolve_reference(target, source.path, root)
        if reason:
          if target in external_targets:
            # Declared as living in a sibling repo: unresolvable here by design,
            # and the declaration itself is audited (exists-here / unused).
            if external_seen is not None:
              external_seen.add(target)
            continue
          findings.append(f'{here} — {reason}')
          continue
        if path is None:
          continue
        if path not in cache:
          cache[path] = Document.read(root, str(path.relative_to(root)))
        target_doc = cache[path]
        if target_doc.has_section(section):
          inbound.setdefault(path, set()).add(xref_norm(section))
        elif local or not target_doc.has_body(section):
          alias_matched = False
          target_rel = str(path.relative_to(root))
          for alias in aliases:
            if alias['from_path'] != target_rel:
              continue
            if xref_norm(alias['from_section']) not in xref_norm(section):
              continue
            alias_path = (root / alias['to_path']).resolve()
            if not alias_path.is_file():
              raise ScannerError(f"xref alias missing: {alias['to_path']}")
            if alias_path not in cache:
              cache[alias_path] = Document.read(root, alias['to_path'])
            alias_doc = cache[alias_path]
            if not alias_doc.has_section(alias['to_section']):
              raise ScannerError(f"xref alias section missing: {alias['to_path']}「{alias['to_section']}」")
            inbound.setdefault(alias_path, set()).add(xref_norm(alias['to_section']))
            alias_matched = True
            break
          if not alias_matched:
            findings.append(f'{here} — 目標檔的 heading 與內文皆無此字串（節名改過？權威搬家？）')
  if not full_scan:
    return findings
  for rel in evidence_layers:
    path = (root / rel).resolve()
    if not path.is_file():
      continue
    if path not in cache:
      cache[path] = Document.read(root, rel)
    wanted = inbound.get(path, set())
    for lineno, heading in cache[path].h2_sections():
      normalized = xref_norm(heading)
      if any(item in normalized for item in wanted):
        continue
      findings.append(f'{rel}:{lineno}: ## {heading} — 節級孤兒：無任何 md 以 `{rel}`「節名」指到它')
  return findings

def evidence_layers(config):
  if config is None:
    return ['docs/dead-ends.md']
  layers = []
  for cls in config.classes:
    if not cls.requires_inbound:
      continue
    for pattern in cls.paths:
      if not any(char in pattern for char in '*?['):
        layers.append(pattern)
  return layers

def unchanged_legacy_plans(config):
  if config is None:
    return set()
  legacy = config.raw.get('legacy_plan_blobs', {})
  unchanged = set()
  for rel, expected in legacy.items():
    path = config.root / rel
    if path.is_file() and file_blob(config.root, rel) == expected:
      unchanged.add(rel)
  return unchanged

def hidden_legacy_plans(config):
  return unchanged_legacy_plans(config) - set(config.raw.get('searchable_legacy_plans', []) if config else [])

def xref_section_aliases(config):
  if config is None:
    return []
  raw = config.raw.get('xref_section_aliases', [])
  if not isinstance(raw, list):
    raise ScannerError('config xref_section_aliases must be list')
  aliases = []
  required = {'from_path', 'from_section', 'to_path', 'to_section'}
  for item in raw:
    if not isinstance(item, dict) or set(item) != required or (not all((isinstance(item[key], str) and item[key] for key in required))):
      raise ScannerError('config xref_section_aliases item invalid')
    validate_relpath(item['from_path'], 'xref alias from_path')
    validate_relpath(item['to_path'], 'xref alias to_path')
    aliases.append(item)
  return aliases

def status_findings(config, documents):
  spec = config.raw.get('status_schema')
  if not spec:
    return []
  path = spec.get('path', 'STATUS.md')
  doc = next((item for item in documents if item.rel == path), None)
  if not doc:
    return [f'STATUS missing: {path}']
  headings = [heading for _, heading in doc.h2_sections()]
  findings = []
  for required in spec.get('required_headings', []):
    if not any(section_matches(item, required) for item in headings):
      findings.append(f'STATUS required heading missing: {required}')
  for forbidden in spec.get('forbidden_headings', []):
    if any(section_matches(item, forbidden) for item in headings):
      findings.append(f'STATUS historical heading remains: {forbidden}')
  active = paused = False
  block = []
  for line in doc.visible + ['## end']:
    heading = HEADING_RE.match(line)
    if heading and heading.group(1) == '##':
      if paused and block and '恢復條件' not in '\n'.join(block):
        findings.append(f'paused item missing restart condition: {path}')
      name = xref_norm(heading.group(2))
      active, paused = (section_matches(heading.group(2), '進行中'), '暫停中' in name)
      block = []
    elif active and re.match(r'^\s*[-+*]\s+.*✅', line):
      findings.append(f'STATUS active item marked complete: {path}')
    elif paused and TOP_BULLET_RE.match(line):
      if block and '恢復條件' not in '\n'.join(block):
        findings.append(f'paused item missing restart condition: {path}')
      block = [line]
    elif block:
      block.append(line)
  days = spec.get('stale_days')
  if days is not None:
    before = run_git(config.root, ['log', '-1', '--format=%ct', '--', path], allow_failure=True).strip()
    now = run_git(config.root, ['log', '-1', '--format=%ct'], allow_failure=True).strip()
    if before and now and (lag := (int(now) - int(before)) // 86400) > days:
      findings.append(f'STATUS stale: {lag} days>{days} at {path}')
  return findings

def backlog_findings(config, documents, entries, baseline):
  findings = []
  seen = {}
  for doc in documents:
    if not doc.doc_class or doc.doc_class.name != 'backlog':
      continue
    governed_sections = doc.doc_class.governed_sections
    backlog_entries, _ = parse_top_level_entries(doc)
    for entry in backlog_entries:
      if not any(section_matches(entry.section, section) for section in governed_sections):
        continue
      stable_id = entry.stable_id if entry.stable_id and entry.stable_id.startswith('B-') else None
      if not stable_id:
        findings.append(f'backlog ID missing: {doc.rel}:{entry.line}')
        continue
      if stable_id in seen:
        first_path, first_line = seen[stable_id]
        findings.append(f'duplicate backlog ID: {stable_id} at {first_path}:{first_line} and {doc.rel}:{entry.line}')
      else:
        seen[stable_id] = (doc.rel, entry.line)
      if entry.closed:
        findings.append(f'closed backlog item remains: {stable_id} at {doc.rel}:{entry.line}')
    before = committed_texts(config.root, doc.rel, baseline)
    if before:
      removed = set().union(*(
        declared_ids(Document.from_text(config.root, doc.rel, text, doc.doc_class), 'B', governed_sections)
        for text in before
      )) - set(seen)
      linked = {
        stable_id
        for entry in entries
        if entry.doc_class and entry.doc_class.mode == 'history'
        for stable_id in re.findall('B-\\d{8}-[a-z0-9-]+', entry.metadata.get('關聯', ''))
      }
      for stable_id in sorted(removed - linked):
        findings.append(f'backlog removal missing history relation: {stable_id}')
  return findings

def audit_findings(config):
  baseline, baseline_note = immutability_base(config.root)
  documents, classification = build_documents(config)
  entries, _ = build_entries(documents)
  markdown = tracked_markdown(config.root)
  xref_sources = tracked_markdown(config.root, xref=True)
  findings = []
  findings.extend(f'tracked markdown missing on disk: {rel}' for rel in missing_tracked_markdown(config.root))
  findings.extend(removed_immutable_findings(config, baseline))
  findings.extend(class_findings(config, classification))
  findings.extend(budget_findings(config, documents))
  findings.extend(history_findings(config, entries, baseline))
  findings.extend(history_append_findings(config, documents, baseline))
  findings.extend(plan_findings(config, markdown, baseline))
  findings.extend(status_findings(config, documents))
  findings.extend(backlog_findings(config, documents, entries, baseline))
  findings.extend(self_governance_findings(config))
  alias_sources = {rel for rel, matches in classification.items() if len(matches) == 1 and matches[0].mode == 'history'}
  external_seen = set()
  findings.extend(xref_scan(config.root, xref_sources, full_scan=True, evidence_layers=evidence_layers(config), skip_sources=hidden_legacy_plans(config), section_aliases=xref_section_aliases(config), alias_sources=alias_sources, external_targets=external_reference_targets(config), external_seen=external_seen))
  findings.extend(external_reference_findings(config, external_seen))
  return (sorted(set(findings)), [baseline_note] if baseline_note else [])

def cmd_audit(config, *, shadow, ship):
  findings, notes = audit_findings(config)
  if ship:
    print(f"doc-governance: {('FINDINGS' if findings else 'OK')}")
  for note in notes:
    print(f'doc-note: {note}')
  for finding in findings:
    print(f'doc-flag: {finding}')
  if findings and (not shadow):
    return 1
  return 0

def surface_bytes(config):
  total = 0
  rows = []
  for item in config.raw.get('governance_surface', []):
    if isinstance(item, str):
      rel, start, end = (item, None, None)
    elif isinstance(item, dict):
      rel, start, end = (item.get('path'), item.get('start'), item.get('end'))
    else:
      raise ScannerError('config governance_surface item invalid')
    if not isinstance(rel, str):
      raise ScannerError('config governance_surface path missing')
    validate_relpath(rel, 'governance_surface')
    path = config.root / rel
    try:
      data = path.read_bytes()
    except OSError as exc:
      raise ScannerError(f'governance surface read {rel}: {exc}') from exc
    if start is not None or end is not None:
      text = data.decode('utf-8')
      if not isinstance(start, str) or not isinstance(end, str):
        raise ScannerError(f'governance markers incomplete: {rel}')
      begin, finish = (text.find(start), text.find(end))
      if begin < 0 or finish < begin:
        raise ScannerError(f'governance markers missing: {rel}')
      data = text[begin:finish + len(end)].encode('utf-8')
    rows.append((rel, len(data)))
    total += len(data)
  return (total, rows)

def self_governance_findings(config):
  findings = []
  maximum = config.raw.get('governance_max_bytes')
  if maximum is not None:
    if not isinstance(maximum, int) or maximum < 1:
      raise ScannerError('config governance_max_bytes invalid')
    total, _ = surface_bytes(config)
    if total > maximum:
      findings.append(f'governance surface bytes: {total}>{maximum}')
  parsers = config.raw.get('markdown_parser_implementations', [])
  if not isinstance(parsers, list) or not all((isinstance(item, str) for item in parsers)):
    raise ScannerError('config markdown_parser_implementations invalid')
  if parsers and len(parsers) != 1:
    findings.append(f'markdown parser count: {len(parsers)}!=1')
  for rel in parsers:
    validate_relpath(rel, 'markdown parser implementation')
    if not (config.root / rel).is_file():
      findings.append(f'markdown parser missing: {rel}')
  return findings

def cmd_report(config):
  documents, classification = build_documents(config)
  _, metrics = build_entries(documents)
  by_class = {}
  for doc in documents:
    name = doc.doc_class.name if doc.doc_class else 'unclassified'
    count, size = by_class.get(name, (0, 0))
    by_class[name] = (count + 1, size + len(doc.text.encode('utf-8')))
  print('document-families:')
  for name, (count, size) in sorted(by_class.items()):
    print(f'  {name}: files={count} bytes={size}')
  print('logical-entry-shapes:')
  for key in METRICS:
    print(f'  {key}={metrics[key]}')
  surface, rows = surface_bytes(config)
  print(f'governance-surface: bytes={surface}')
  for rel, size in rows:
    print(f'  {rel}: bytes={size}')
  canonical = sum(len(doc.text.encode('utf-8')) for doc in documents)
  ratio = surface * 100 / canonical if canonical else 0
  print(f'canonical-markdown: bytes={canonical} governance-ratio={ratio:.2f}%')
  print('loaded-context:')
  loaded = [(len(doc.text.encode('utf-8')), len(doc.lines), doc.rel) for doc in documents if doc.doc_class and doc.doc_class.mode == 'loaded']
  for size, lines, rel in sorted(loaded, reverse=True):
    print(f'  {rel}: bytes={size} lines={lines}')
  classified = sum(1 for matches in classification.values() if len(matches) == 1)
  print(f'classification: exact={classified} total={len(classification)}')
  return 0

def slugify(value):
  normalized = unicodedata.normalize('NFKD', value).encode('ascii', 'ignore').decode('ascii')
  words = re.findall('[a-z0-9]+', normalized.casefold())
  return '-'.join(words) or 'u-' + hashlib.sha256(unicodedata.normalize('NFKC', value).encode()).hexdigest()[:12]

def cmd_record_path(config, kind, date, slug):
  try:
    parsed = dt.date.fromisoformat(date)
  except ValueError as exc:
    raise ScannerError(f'date must be YYYY-MM-DD: {date}') from exc
  prefix = {'decision': 'D', 'dead_end': 'X', 'milestone': 'M'}[kind]
  identifier = f'{prefix}-{parsed:%Y%m%d}-{slugify(slug)}'
  path = config.history_paths[kind].replace('{YYYY-MM}', f'{parsed:%Y-%m}')
  print(f'path={path}')
  print(f'id={identifier}')
  print(f'section={EVENT_SECTION}')
  print(f'heading=- **{identifier} · {parsed:%Y-%m-%d} {slug}**:')
  return 0

def build_parser():
  parser = argparse.ArgumentParser()
  parser.add_argument('--root')
  subparsers = parser.add_subparsers(dest='command', required=True)
  find_parser = subparsers.add_parser('find')
  find_parser.add_argument('query')
  find_parser.add_argument('--limit', type=int, default=MAX_RESULTS)
  audit_parser = subparsers.add_parser('audit')
  modes = audit_parser.add_mutually_exclusive_group()
  modes.add_argument('--shadow', action='store_true')
  modes.add_argument('--ship', action='store_true')
  modes.add_argument('--check', choices=['xref'])
  audit_parser.add_argument('files', nargs='*')
  subparsers.add_parser('report')
  record_parser = subparsers.add_parser('record-path')
  record_parser.add_argument('--type', required=True, choices=['decision', 'dead_end', 'milestone'])
  record_parser.add_argument('--date', required=True)
  record_parser.add_argument('--slug', required=True)
  return parser

def main(argv):
  parser = build_parser()
  try:
    args = parser.parse_args(argv)
    root = resolve_root(args.root)
    if args.command == 'audit' and args.check == 'xref':
      config = load_config(root, optional=True)
      if args.files:
        files = []
        for value in args.files:
          path = Path(value)
          if not path.is_absolute():
            path = Path.cwd() / path
          path = path.resolve()
          if not path.is_file():
            raise ScannerError(f'input missing: {path}')
          try:
            files.append(str(path.relative_to(root)))
          except ValueError as exc:
            raise ScannerError(f'input escapes --root: {path}') from exc
      else:
        files = tracked_markdown(root, xref=True) if config else sorted(str(path.relative_to(root)) for pattern in ('*.md', '*.sh') for path in root.rglob(pattern) if '.git' not in path.parts)
      alias_sources = {rel for rel in files if config and any(cls.mode == 'history' for cls in matching_classes(rel, config))}
      findings = xref_scan(root, files, full_scan=not args.files, evidence_layers=evidence_layers(config), skip_sources=hidden_legacy_plans(config), section_aliases=xref_section_aliases(config), alias_sources=alias_sources, external_targets=external_reference_targets(config))
      for finding in findings:
        print(finding)
      return 0
    config = load_config(root)
    if args.command == 'find':
      if args.limit < 1:
        raise ScannerError('--limit must exceed 0')
      return cmd_find(config, args.query, args.limit)
    if args.command == 'audit':
      return cmd_audit(config, shadow=args.shadow, ship=args.ship)
    if args.command == 'report':
      return cmd_report(config)
    if args.command == 'record-path':
      return cmd_record_path(config, args.type, args.date, args.slug)
    raise ScannerError(f'unknown command: {args.command}')
  except Exception as exc:
    print(f'doc-governance error: {exc}', file=sys.stderr)
    if 'args' in locals() and getattr(args, 'command', None) == 'audit' and getattr(args, 'ship', False):
      print('doc-governance: BROKEN')
    return 2
if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
