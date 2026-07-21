---
name: repo-review
description: Review committed diffs in one or more local Git repositories with fresh-context subagents, immutable ranges, concrete findings, and an optional safety-bounded autofix loop. Use for low-bias code review, multi-repo or HEAD~N..HEAD review, findings with file references, or explicitly requested repo-review autofix.
---

# Repo Review

Review committed changes with reproducible inputs and low bias. Report findings by default. Modify files only when the user explicitly requests autofix.

## Resolve Inputs

Restate the effective repositories, mode, range, scope, focus, `max_subagents`, `include_worktree`, `max_rounds`, `commit_each_round`, and handoff before reviewing. Use defaults for omitted optional inputs; do not ask the caller to supply optional focus, context files, flags, or tests.

- Default to `mode=review` and `include_worktree=false`.
- Enter autofix only for `repo-review autofix`, `mode=autofix`, or an equivalent explicit request.
- Map `last commit` to `HEAD~1..HEAD`, `last N commits` to `HEAD~N..HEAD`, and a vague request or `review again` without a newer explicit range to `HEAD~1..HEAD`.
- Treat `scope` as a repository, module, or path limit. Treat `focus` as a priority without excluding correctness unless the user makes it exclusive.
- Treat `max_subagents` as a strict upper bound and reduce the reviewer count when the diff or available concurrency needs fewer.
- In autofix, default `max_rounds` to `3`, clamp it to `1..5`, and count review passes rather than fix attempts. Default `commit_each_round` to `true`; disable commits only by explicit request or when the environment cannot commit, and state the context-growth tradeoff.
- For `handoff=claude`, append a table containing each repo, its final review range, and a one-line summary. If uncommitted autofix edits remain, use `<base>..HEAD + working tree`.

## Establish Canonical Context

Resolve the bundled `scripts/review-context.sh` relative to this `SKILL.md`; do not look for it in the target repo. For every committed review, run:

```text
scripts/review-context.sh <repo-path> <base..head> [--autofix]
```

Use `--autofix` only in autofix mode. Treat the helper as canonical for the repo root, requested refs, immutable object IDs, current HEAD and branch state, ancestry and merge base, worktree and autofix safety, review range, guidance paths, changed files, stat, baseline status, and next-round policy. Use model judgment for findings.

After resolution, use immutable object IDs in subagent prompts, diffs, checkpoint ranges, reports, and handoffs. Never allow moving refs to drift across rounds.

- If a default or last-N range fails only because the repository has too few parents, rerun with `4b825dc642cb6eb9a060e54bf8d69288fbee4904..HEAD` and label it an empty-tree baseline. Do not hide an unrelated invalid explicit ref with this fallback.
- If the base is not an ancestor of the head and the request means branch-introduced changes, rerun from the helper-reported merge base to the resolved head and state the anchored range. Stop when there is no merge base. Preserve the original two-point endpoint comparison only when explicitly requested, and warn about reverse-side deletions.
- If the helper cannot run, fall back to root and subtree `AGENTS.md` or `CLAUDE.md`, plus directly referenced review guidance such as `code_review.md`, and state the degraded context setup.

## Read Applicable Guidance

Read applicable guidance before review. The helper discovers paths from the current worktree. When `head-is-current:no`, independently inspect the resolved head with `git ls-tree` and read the historical guidance with `git show <resolved-head>:<path>`. Discover guidance that exists only in the historical tree as well as historical versions of current paths; do not let current, newly added, changed, or deleted guidance leak across revisions.

## Delegate The First Pass

When this skill is explicitly invoked or the user requests subagents, use fresh-context subagents when available. If unavailable, state the fallback and perform a narrow local review.

- Small diff: use up to two reviewers, split between correctness/security and tests/integration/deploy/configuration.
- Medium diff: use up to three or four reviewers with distinct module or concern ownership.
- Large diff: partition by repo, coherent module, or roughly 8–12 changed files.
- Multi-repo diff: assign at least one reviewer per repo when the concurrency cap permits, and add a cross-repo contract pass when interfaces, schemas, release order, or shared configuration interact.

Respect `max_subagents` and actual concurrency over these sizing defaults. Avoid duplicate broad scopes; overlap only at critical interfaces or security boundaries.

Give each subagent only the repo path, immutable range, applicable guidance, diff stat, bounded files or concerns, and required output shape. Do not paste the full diff or pass patch intent, suspected findings, prior conclusions, or implementation history. Let reviewers obtain the diff with read-only Git commands.

The main agent must not perform an equivalent whole-diff first pass before delegation. After subagents return, inspect only enough source to verify plausible findings, deduplicate them, resolve contradictions, and calibrate severity. Re-derive conclusions from code rather than defending patch intent.

## Apply The Finding Standard

Report only concrete issues that could cause a reader, operator, or executing agent to do the wrong thing. Treat correctness, security, regression, required-test, deploy/configuration, and broken cross-file or cross-repo contract findings as blocking. Ignore style unless it creates a material correctness or maintenance hazard.

For shell, Git, `gh`, SQL, and other executable snippets, verify real semantics, including empty arguments, two-dot versus three-dot ranges, missing upstreams, untracked files, cwd or repo ambiguity, placeholder expansion, escaping, and destructive behavior in mixed state.

For `SKILL.md`, README, runbook, and other operational prose, treat incorrect commands, contradictions, broken references, and stale operational facts as blocking. Treat clarity, extra examples, broader edge-case coverage, and general completeness as optional. Optional prose improvements must not drive an autofix loop.

Each finding must include severity, a precise file reference, the triggering behavior, and its concrete impact. Verify the reference against the reviewed revision. Order findings by severity and keep repository boundaries explicit.

When `include_worktree=true`, review staged, unstaged, and untracked content in addition to the committed range, state that expanded scope, and report worktree-only findings separately from committed-range findings.

## Run Review Mode

1. Resolve effective inputs and canonical context for every repo.
2. Read applicable guidance.
3. Delegate bounded fresh-context passes.
4. Verify and consolidate candidate findings.
5. Report findings first, followed by a short summary.

Do not edit files or create commits in review mode.

## Run Autofix Mode

Before any edit, require `autofix-safe:yes`, a clean starting worktree, current requested head, attached branch, and ancestor-safe range. If the helper reports `autofix-safe:no`, stop before editing or committing and report `autofix-reason`. If the requested head was not the original current HEAD, stop unless the user explicitly approves extending beyond that head or supplies a target branch.

Never stage or commit pre-existing or concurrent user changes. If ownership overlaps or becomes ambiguous, stop. Never push.

For each review pass `R1` through `R<max_rounds>`:

1. Rerun the helper and read current canonical context and guidance.
2. Spawn new fresh-context reviewers; do not reuse earlier prompts or conclusions.
3. Verify and consolidate findings. Stop clean when no blocking findings remain. Stop without another fix when this is the last allowed review pass.
4. Fix only verified blocking findings with minimal changes.
5. Before testing, record intentional edit paths and worktree status. Run relevant tests or checks. If none are discoverable, state that and perform reasonable static verification.
6. If tests fail or the environment blocks validation, do not commit; stop and report the blocker.
7. Recheck status, stage only verified intentional paths, and inspect the staged diff. Stop if a pre-existing or concurrent path would be included.
8. Keep only new untracked outputs that were absent before and are attributable to the recorded test command unstaged; list them without letting them block later committed-range review.
9. With `commit_each_round=true`, create a checkpoint such as `fix: R1 review fixes`. If the original resolved head was current HEAD, review `<resolved-base>..HEAD` next. Otherwise use only an explicitly approved target range.
10. With `commit_each_round=false`, review the original immutable range plus accumulated worktree edits, recompute that mixed context every round, and state that it can grow.

Also stop when validation is blocked, repository safety becomes ambiguous, or the same finding survives two fix attempts. Optional findings never justify another round.

Include checkpoint hashes, round history, fixes, tests, final status, stop reason, and remaining blocking findings in the final report. Squash review-fix checkpoints only when the final result is clean and the user explicitly requests polished history; otherwise leave them intact and report branch state.

## Output

Write in the user's language. List findings first and keep summaries brief. If a findings section is empty, write `No findings.`. Autofix and handoff reports may add their required history or table after that line.

Use this handoff shape when requested:

```markdown
### Third-party Review Handoff

| Repo | Review Range | Summary |
|------|--------------|---------|
| `/path/repo` | `abc123..def456` | One-line change summary |
```

When reviewing the last two commits, review commit-by-commit when useful and add a consolidated section only when their interaction matters. Use absolute file references when repo-relative paths would be ambiguous.
