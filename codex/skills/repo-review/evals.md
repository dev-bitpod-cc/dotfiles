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

### F11 — Historical-only guidance is discovered

```json
{
  "query": "Use repo-review. Review /path/repo from old-base..old-head.",
  "setup": "old-head is not current HEAD. It contains a subtree AGENTS.md that was later deleted, while current HEAD contains a different replacement guidance file.",
  "expected_behavior": [
    "Inspect the resolved historical tree instead of relying only on guidance paths discovered from the current worktree.",
    "Read the subtree AGENTS.md that exists at old-head and apply it to files under that subtree.",
    "Do not apply the current replacement guidance to the historical review."
  ]
}
```

### F12 — Reviewer sizing respects max_subagents

```json
{
  "query": "Use repo-review. Review /path/repo from HEAD~1..HEAD. max_subagents=1",
  "setup": "The diff is small, for which the normal sizing guidance would use two reviewers.",
  "expected_behavior": [
    "Restate max_subagents=1 as the effective strict upper bound.",
    "Spawn no more than one review subagent.",
    "Give that reviewer a combined bounded scope rather than silently ignoring one concern area."
  ]
}
```

### F13 — Worktree findings remain distinguishable

```json
{
  "query": "Use repo-review. Review /path/repo from HEAD~1..HEAD. include_worktree=true",
  "setup": "The committed range contains one changed file and the worktree contains an unrelated staged change plus an untracked file.",
  "expected_behavior": [
    "State that staged, unstaged, and untracked content was added to the committed review scope.",
    "Pass include_worktree=true plus a staged, unstaged, and untracked path manifest to each assigned reviewer without pasting the full diff.",
    "Keep committed-range findings separate from worktree-only findings.",
    "Do not imply that a worktree-only issue exists in the immutable committed range."
  ]
}
```

### F14 — Clean result is required before squash

```json
{
  "query": "Use repo-review autofix. Review /path/repo from HEAD~2..HEAD and polish the commit history.",
  "setup": "The final allowed review pass still has one verified blocking finding.",
  "expected_behavior": [
    "Stop at the round limit and report the remaining blocking finding.",
    "Do not squash review-fix checkpoint commits while the final result is not clean.",
    "Report the current branch and checkpoint state."
  ]
}
```

### F15 — No-findings wording coexists with autofix history

```json
{
  "query": "Use repo-review autofix. Review /path/repo from HEAD~1..HEAD.",
  "setup": "R1 finds and fixes a bug; tests pass and R2 has no findings.",
  "expected_behavior": [
    "Use No findings. for the empty R2 findings section.",
    "Still include the required autofix round history, fixes, tests, checkpoint hashes, and final status.",
    "Do not interpret No findings. as requiring the entire response to contain no other text."
  ]
}
```

### F16 — Fresh reviewers inherit no parent history

```json
{
  "query": "Use repo-review. Review /path/repo from HEAD~1..HEAD.",
  "setup": "The parent conversation contains implementation intent and suspected findings that must not bias reviewers. The current Codex spawn interface defaults to inheriting all turns unless configured otherwise.",
  "expected_behavior": [
    "Spawn Codex review subagents with fork_turns=none instead of relying on the default fork behavior.",
    "Pass only the bounded review context allowed by the skill.",
    "If the available surface cannot create a no-history reviewer, state the degraded fallback instead of claiming a fresh-context pass."
  ]
}
```

### F17 — Arbitrary tree base blocks autofix

```json
{
  "query": "Use repo-review autofix. Review /path/repo from HEAD~1^{tree}..HEAD.",
  "setup": "The worktree is clean and HEAD is current, but the base resolves to a non-empty-tree tree object rather than a commit.",
  "expected_behavior": [
    "Resolve the base as a tree without treating it as ancestor-safe.",
    "Report autofix-safe=no with reason base-not-commit.",
    "Do not edit or create a checkpoint commit; continue to allow the documented empty-tree baseline."
  ]
}
```

### F18 — Later autofix rounds validate owned dirty state

```json
{
  "query": "Use repo-review autofix. Review /path/repo from HEAD~1..HEAD.",
  "setup": "The clean starting gate passed. After R1, either commit_each_round=false leaves intentional tracked edits or tests leave a previously absent untracked coverage artifact.",
  "expected_behavior": [
    "Use --autofix only for the clean starting gate and use normal context resolution in later dirty rounds.",
    "Continue only when every dirty path is an intentional accumulated edit or an attributable recorded test artifact.",
    "Pass the original range, mixed-context mode, and accumulated-edit manifest to fresh reviewers when commit_each_round=false.",
    "Stop before editing or committing if a pre-existing, concurrent, or otherwise unowned dirty path appears."
  ]
}
```
