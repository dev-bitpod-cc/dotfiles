---
name: repo-review
description: Review one or more local git repositories from committed diffs only. Use when the user wants a fresh-session code review, asks to review multiple repos in parallel, wants review findings without prior-review bias, or wants commit-range / HEAD~N..HEAD review with root guidance files read first.
---

# Multi-Repo Code Review

Use this workflow to keep reviews narrow, reproducible, and low-bias.

## Workflow

1. Read each target repo's root instructions first.
If present, read `CLAUDE.md`, `AGENTS.md`, or equivalent root guidance before reviewing code.

2. Review committed content only.
Prefer `git diff <base>..<head>`, `git show <commit>:<path>`, and `git log --oneline`.
Do not rely on working tree state unless the user explicitly asks for unstaged or uncommitted changes.

3. Treat each repo as an independent review unit.
For multi-repo review, gather commit range, diff stat, and key files for each repo separately.
Parallelize inspection when tools allow it, then merge findings at the end.

4. Re-derive conclusions from code.
Do not defend patch intent. Do not reuse earlier review conclusions unless the user explicitly asks to compare with a previous review.
If the user says `review again`, prefer the newest requested commit range or the latest commits rather than repeating an older range.

5. Prioritize real findings.
Focus on bugs, behavioral regressions, missing tests, deployment breakage, security gaps, and mismatches between code paths.
Ignore style unless it causes a real maintenance or correctness problem.

## Default Review Shape

For each repo:
- Identify the exact review range.
- Read the smallest set of files needed to verify behavior.
- Check whether tests exist for the changed behavior.
- Verify user-facing paths, deploy paths, and configuration wiring when infra or frontend code changes.

For the final output:
- List findings first, ordered by severity.
- Include file references and concrete reasoning.
- Keep summaries brief.
- If there are no findings, say `No findings.`

## Prompt Patterns

Use or adapt these request shapes in a new session:

```text
Use multi-repo-code-review.
Review these repos in parallel using committed diffs only:
- /path/repo-a: <base>..<head>
- /path/repo-b: <base>..<head>
Read each repo's root guidance file first.
Report only concrete findings with file references. If none, say No findings.
```

```text
Use multi-repo-code-review.
Review /path/repo from HEAD~2..HEAD.
Do not use prior review conclusions. Re-derive everything from code only.
```

## Notes

- If the user asks for `the last two commits`, review commit-by-commit when useful, then add a consolidated section only if cross-commit interaction matters.
- If later fixes exist beyond an earlier reviewed range, switch to the newer requested range instead of repeating stale findings.
- When repo roots differ, keep file references absolute and keep repo boundaries explicit in the final report.
