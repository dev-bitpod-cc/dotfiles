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

Use `--autofix` only for the clean starting gate before the first edit in autofix mode. Treat the helper as canonical for the repo root, requested refs, immutable object IDs, current HEAD and branch state, ancestry and merge base, worktree and autofix safety, review range, guidance paths, changed files, stat, baseline status, and next-round policy. Use model judgment for findings.

After resolution, use immutable object IDs in subagent prompts, diffs, checkpoint ranges, reports, and handoffs. Never allow moving refs to drift across rounds.

- If a default or last-N range fails only because the repository has too few parents, rerun with `4b825dc642cb6eb9a060e54bf8d69288fbee4904..HEAD` and label it an empty-tree baseline. Do not hide an unrelated invalid explicit ref with this fallback.
- If the base is not an ancestor of the head and the request means branch-introduced changes, rerun from the helper-reported merge base to the resolved head and state the anchored range. Stop when there is no merge base. Preserve the original two-point endpoint comparison only when explicitly requested, and warn about reverse-side deletions.
- If the helper cannot run, fall back to root and subtree `AGENTS.md` or `CLAUDE.md`, plus directly referenced review guidance such as `code_review.md`, and state the degraded context setup.

## Read Applicable Guidance

Read applicable guidance before review. The helper discovers paths from the current worktree. When `head-is-current:no`, independently inspect the resolved head with `git ls-tree` and read the historical guidance with `git show <resolved-head>:<path>`. Discover guidance that exists only in the historical tree as well as historical versions of current paths; do not let current, newly added, changed, or deleted guidance leak across revisions.

Resolve the bundled `references/reviewer-brief.md` relative to this `SKILL.md`. Read it completely before delegation and use it when verifying findings. Require every reviewer to read the same file directly; do not paraphrase its bar.

## Delegate The First Pass

When this skill is explicitly invoked or the user requests subagents, use fresh-context subagents when available. With Codex collaboration tools, set `fork_turns="none"`; never rely on the default fork behavior. If the surface cannot create a no-history reviewer, state the degraded fallback and perform a narrow local review instead of claiming a fresh-context pass.

- Small diff: use up to two reviewers, split between correctness/security and tests/integration/deploy/configuration.
- Medium diff: use up to three or four reviewers with distinct module or concern ownership.
- Large diff: partition by repo, coherent module, or roughly 8–12 changed files.
- Multi-repo diff: assign at least one reviewer per repo when the concurrency cap permits, and add a cross-repo contract pass when interfaces, schemas, release order, or shared configuration interact.

Respect `max_subagents` and actual concurrency over these sizing defaults. Avoid duplicate broad scopes; overlap only at critical interfaces or security boundaries.

Treat the pass number, pass cap, passes remaining, stop conditions, prior findings, prior conclusions, and fix summaries as orchestration-private state. Never expose them through reviewer prompts, task names, role names, checkpoint messages, or other reviewer-visible metadata. Use stage-neutral task names based only on the assigned module or concern. Do not ask reviewers to verify fixes, judge convergence, limit their search to newly introduced issues, or infer quality from prior review activity.

Construct every reviewer prompt from this fixed, stage-neutral template. Replace only the braced fields and omit the mixed-context block when it does not apply; do not add workflow history or a stage-specific preamble:

```text
You are an independent code reviewer with no prior context on this change.
Perform this bounded review yourself; do not delegate or run an autofix loop.

Repositories:
{For each assigned repo: path; immutable resolved-base..resolved-head; applicable
guidance paths or none; diff stat.}
Assigned scope: {bounded files or concerns}
Reviewer criteria: {absolute path to references/reviewer-brief.md}

Read the repository guidance and reviewer criteria completely before judging.
Collect the committed diff yourself with read-only Git commands and review the
complete assigned cumulative change. Return findings in the criteria's format.

{Mixed context: mode plus staged, unstaged, and untracked path manifest. Inspect
these paths too and keep worktree-only findings separate when include_worktree=true.}
```

Give reviewers no additional context beyond the template fields. Do not paste the full diff. When `include_worktree=true` or a no-checkpoint autofix pass includes accumulated edits, fill the mixed-context block with the effective mode and a status-derived manifest; for no-checkpoint autofix, review the original range plus accumulated edits. Let reviewers obtain committed and worktree diffs with read-only Git commands.

The main agent must not perform an equivalent whole-diff first pass before delegation. After subagents return, inspect only enough source to verify plausible findings, deduplicate them, resolve contradictions, and calibrate severity. Re-derive conclusions from code rather than defending patch intent.

## Apply The Finding Standard

Apply `references/reviewer-brief.md` without changing its threshold between passes. Verify each finding against the reviewed revision, order findings by severity, and keep repository boundaries explicit. Optional observations never drive an autofix loop.

When `include_worktree=true`, review staged, unstaged, and untracked content in addition to the committed range, state that expanded scope, and report worktree-only findings separately from committed-range findings.

## Run Review Mode

1. Resolve effective inputs and canonical context for every repo.
2. Read applicable guidance.
3. Delegate bounded fresh-context passes.
4. Verify and consolidate candidate findings.
5. Report findings first, followed by a short summary.

Do not edit files or create commits in review mode.

## Run Autofix Mode

Before the first edit, run the helper with `--autofix` and require `autofix-safe:yes`, a clean starting worktree, current requested head, attached branch, and ancestor-safe range. If the starting gate reports `autofix-safe:no`, stop before editing or committing and report `autofix-reason`. If the requested head was not the original current HEAD, stop unless the user explicitly approves extending beyond that head or supplies a target branch.

After the starting gate passes, run later helper calls without `--autofix`. Recheck that HEAD is current, the branch is attached, and the base remains ancestor-safe. Compare every dirty path with the recorded intentional edits and test outputs: with checkpoint commits, allow only attributable new untracked test artifacts; without checkpoint commits, also allow accumulated intentional edits. Stop before another edit or commit when any path is pre-existing, concurrent, unrecorded, or otherwise ownership-ambiguous.

Never stage or commit pre-existing or concurrent user changes. If ownership overlaps or becomes ambiguous, stop. Never push.

For each review pass `R1` through `R<max_rounds>`:

1. Rerun the helper without `--autofix` after R1, read current canonical context and guidance, and apply the later-round ownership checks above.
2. Spawn new fresh-context reviewers with stage-neutral task names and the fixed template; do not reuse earlier reviewers, prompts, or conclusions.
3. Verify and consolidate findings. Stop clean when no blocking findings remain.
4. Before any edit, privately compare the current pass with `max_rounds`. If this is the last allowed review pass and blocking findings remain, stop immediately and report them; do not edit, test, stage, or create another checkpoint.
5. Otherwise, fix only verified blocking findings with minimal changes.
6. Sweep semantic dependencies affected by each fix, by relationship rather than matching text: condition to message, comment, or docstring; criterion to guard self-test; operational fact to its authoritative status artifact; and capability to user-facing documentation. Update only applicable in-scope dependents.
7. Before expanding an enumeration, ask whether an external system, extension, plugin, database catalog, or third-party API can add members. For an externally extensible set, prefer an available structural invariant over adding only the currently missing member; retain enumeration for repository-defined closed sets.
8. Before testing, record intentional edit paths and worktree status. Run relevant tests or checks. If none are discoverable, state that and perform reasonable static verification.
9. If tests fail or the environment blocks validation, do not commit; stop and report the blocker.
10. With `commit_each_round=true`, recheck status, stage only verified intentional paths, and inspect the staged diff. Stop if a pre-existing or concurrent path would be included. With `commit_each_round=false`, do not stage or commit.
11. Keep only new untracked outputs that were absent before and are attributable to the recorded test command unstaged; list them without letting them block later committed-range review.
12. With `commit_each_round=true`, create a stage-neutral checkpoint such as `fix: address review findings`; keep the pass-to-checkpoint mapping in orchestration state for the final report. If the original resolved head was current HEAD, review `<resolved-base>..HEAD` next. Otherwise use only an explicitly approved target range.
13. With `commit_each_round=false`, review the original immutable range plus accumulated worktree edits, recompute that mixed context every round, and state that it can grow.

Also stop when validation is blocked, repository safety becomes ambiguous, or the same finding survives two fix attempts. Optional findings never justify another round.

Include checkpoint hashes, round history, fixes, tests, final status, stop reason, and remaining blocking findings in the final report. When the pass cap is reached, compare each pass's root causes before diagnosing the stop: repeated rules, reintroduced failures, or back-and-forth changes indicate failed or oscillating convergence; distinct verified roots whose predecessors remain fixed indicate bounded healthy progress. Do not infer an architectural problem or recommend a rewrite from the cap alone. State the evidence for the classification and recommend a matching next step instead of blindly restarting the same autofix loop.

Squash review-fix checkpoints only when the final result is clean and the user explicitly requests polished history; otherwise leave them intact and report branch state.

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
