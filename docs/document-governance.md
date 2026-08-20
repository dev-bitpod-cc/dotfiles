# Governance: `.doc-governance.json`

## Model

Each non-ignored Markdown, including untracked, is `loaded`, `active`, `routed`, `history`, `derived`, or
`governance`. Only loaded is size-limited; others need location/retrieval/lifecycle. History is append-only;
derived has rebuild; `requires_inbound` is evidence-only.

## CLI

- `find <query>`: H1 preamble/H2 (history: top bullet), five 240-byte hits max, `file-preamble` without H2,
  stdout ≤8 KiB, hit/miss/error 0/1/2.
- `audit [--shadow|--ship]`: clean/findings/error 0/1/2; shadow findings 0; ship starts
  `doc-governance: OK|FINDINGS|BROKEN`; xref findings/error 0/2.
- `report`: measure; `record-path`: path/ID/heading.

`--root`: Git toplevel default. No network/index; find is pointer-free; xrefs checked.

## Lifecycle

New history: `docs/archive/{decisions,dead-ends,milestones}-YYYY-MM.md` / `## 事件記錄（event-time）`;
`D/X/M-YYYYMMDD-slug`; title/ID/shard dates match; metadata `日期來源`/`放棄`/`重議`/`關聯`.
Committed records are immutable; reversal adds `supersedes:<ID>`.

`STATUS.md`: active, restartable paused, history/backlog routes, transfer readiness. Backlog: open `B-*` only;
removal needs a citing D/X/M record.

One plan/work item: edit `draft/approved/in-progress`; freeze `implemented/superseded`. Superseded needs
`取代計畫: <path>`. No `-v2/-final/-revised`. Legacy blobs are frozen and excluded from `find`, except
config-listed requirement sources.

## Surface budget

`governance_max_bytes` is a maintenance ceiling, not a correctness ratchet. Correctness and safety fixes may
move it to the next round binary tier; new capabilities must justify their surface cost. Never add only the
bytes needed by the current patch. `governance-ratio` stays informational because growing the Markdown
denominator would otherwise loosen the gate without simplifying governance.
