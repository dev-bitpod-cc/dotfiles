# Repo Review — Evals

> Development-time behavior checks for the `repo-review` skill. Do not link this file from `SKILL.md`; it is an oracle for future skill changes, not runtime context.

## Oracle

Judge `repo-review` changes by whether an agent following the skill would do the right thing, not by repeatedly running adversarial prose review over `SKILL.md`.

- Bug: the skill causes a wrong behavior, such as reviewing the wrong range, committing unrelated user edits, missing a broken command in docs, or treating prose completeness nits as blocking.
- Non-bug: wording could be clearer, more examples could be added, or another edge case could be documented without changing behavior.

## Behavior Cases

### F1 — Claude Code autocodex compatibility

```json
{
  "query": "Run your repo-review skill on /path/repo for abc123..def456. 繁體中文.",
  "setup": "Prompt comes from Claude Code deep-review via codex:rescue. The prompt is exactly one line with repo root and a committed two-dot range.",
  "expected_behavior": [
    "Do not ask Claude to send extra focus, context files, flags, or tests.",
    "Run the bundled review-context script inside Codex using the repo path and range from the one-line prompt.",
    "Review committed content only and report findings in the requested language.",
    "Do not enter autofix mode unless the prompt explicitly requests repo-review autofix or mode=autofix."
  ]
}
```

### F2 — Moving refs freeze to object IDs

```json
{
  "query": "Use repo-review. Review /path/repo from origin/main..HEAD.",
  "setup": "origin/main is a moving ref and HEAD may advance after review starts.",
  "expected_behavior": [
    "Run review-context.sh and use resolved-base/resolved-head object IDs as the review range.",
    "Subagent prompts and final handoff use the resolved range, not the moving origin/main token.",
    "Later rounds do not silently change the base if origin/main moves."
  ]
}
```

### F3 — Autofix refuses unsafe commit state

```json
{
  "query": "Use repo-review autofix. Review /path/repo from HEAD~2..HEAD.",
  "setup": "Target repo has unrelated staged, unstaged, or untracked files before fixes start.",
  "expected_behavior": [
    "Run review-context.sh --autofix before editing.",
    "If autofix-safe is no, stop before editing and report the reason.",
    "Do not create a checkpoint commit that can include unrelated user changes."
  ]
}
```

### F4 — Prose artifact deep-well classification

```json
{
  "query": "Use repo-review. Review /path/repo from HEAD~1..HEAD.",
  "setup": "The range edits a SKILL.md or README. It includes one broken Git command and several wording/completeness nits.",
  "expected_behavior": [
    "Treat the broken command as blocking if executing it would review/reset/commit the wrong thing.",
    "Treat contradictions, stale facts, and broken cross-references as blocking.",
    "Treat wording clarity, more examples, and extra edge-case suggestions as non-blocking follow-up.",
    "Do not fail the review solely because prose could be more exhaustive."
  ]
}
```

### F5 — Executable command semantics

```json
{
  "query": "Use repo-review. Review /path/repo from HEAD~1..HEAD.",
  "setup": "The range changes a script or runbook with shell/Git/GitHub CLI snippets.",
  "expected_behavior": [
    "Check the real command semantics instead of accepting plausible prose.",
    "Catch two-dot vs three-dot Git range mistakes, untracked files omitted by git diff HEAD, missing upstream failures, gh cwd/repo ambiguity, escaping issues, and destructive commands in mixed state.",
    "Report only concrete command behavior risks with file references."
  ]
}
```

### F6 — Range, not diff text, goes to subagents

```json
{
  "query": "Use repo-review. Review /path/repo from HEAD~3..HEAD.",
  "setup": "The diff is moderately large but still reviewable.",
  "expected_behavior": [
    "Main agent gathers stat, changed files, guidance paths, and resolved range using review-context.sh.",
    "Subagent prompts include repo path and resolved range, not a pasted full diff.",
    "Subagents collect the diff themselves with read-only Git commands."
  ]
}
```

### F7 — Root commit falls back to baseline

```json
{
  "query": "Use repo-review. Review /path/repo.",
  "setup": "The target repo contains only its root commit, so HEAD~1 cannot resolve.",
  "expected_behavior": [
    "Attempt the documented default HEAD~1..HEAD range, then recognize the missing parent.",
    "Rerun review-context.sh with the empty-tree object as the base and HEAD as the head.",
    "Identify the resulting review as a baseline review rather than reporting a generic range failure."
  ]
}
```

### F8 — Diverged base is re-anchored

```json
{
  "query": "Use repo-review. Review /path/repo from main..HEAD.",
  "setup": "main and HEAD diverged, and main is not an ancestor of HEAD.",
  "expected_behavior": [
    "Observe base-is-ancestor: no and the merge-base reported by review-context.sh.",
    "Do not report files changed only on main as feature-branch deletions.",
    "For a branch-change request, rerun from merge-base..HEAD and state the anchored resolved range."
  ]
}
```

### F9 — Detached HEAD blocks autofix

```json
{
  "query": "Use repo-review autofix. Review /path/repo from HEAD~1..HEAD.",
  "setup": "The worktree is clean, but HEAD is detached.",
  "expected_behavior": [
    "Observe detached-head: yes and autofix-safe: no with reason detached-head.",
    "Stop before editing or creating checkpoint commits.",
    "Explain that review-fix commits need an attached target branch."
  ]
}
```

### F10 — Test artifacts stay out of checkpoint commits

```json
{
  "query": "Use repo-review autofix. Review /path/repo from HEAD~1..HEAD.",
  "setup": "The repo starts clean; tests create a new unignored coverage file after the agent edits one source file.",
  "expected_behavior": [
    "Record intentional edit paths and status before running tests.",
    "Stage and inspect only the verified source edit for the checkpoint commit.",
    "Leave the new test artifact unstaged, warn about it, and continue later committed-range review rounds without committing it."
  ]
}
```
