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
