---
name: repo-review
description: Subagent-assisted code review for one or more local git repositories from committed diffs, with optional autofix review loops. Use when the user wants a fresh, low-bias code review, asks to review multiple repos or commit ranges, requests HEAD~N..HEAD review, invokes repo-review for findings with file references, or asks repo-review to autofix findings.
---

# Multi-Repo Code Review

Use this workflow to keep reviews narrow, reproducible, and low-bias. Explicit `repo-review` invocation means the user wants the subagent review workflow when subagents are available.

## Modes And Inputs

- `review` mode is the default. It reports findings only and does not edit files.
- `autofix` mode is opt-in when the prompt includes `repo-review autofix`, `mode=autofix`, or an equivalent explicit request. It runs review -> fix -> test -> next-round review until clean or the round limit is reached.
- `max_rounds` controls autofix review passes. Default to `3` when omitted; honor explicit values up to `5`. `max_rounds` counts review passes, so `max_rounds=3` allows R1 review, up to two fix/test cycles, and a final R3 review.
- `commit_each_round` controls autofix checkpoint commits. Default to `true` in `autofix` mode so each review round starts from a clean tree and a bounded branch diff. Honor `commit_each_round=false` only when the user explicitly requests no commits or the environment cannot commit; state that this degraded mode can grow review context across rounds.
- `range`, `scope`, `focus`, `max_subagents`, `include_worktree`, `commit_each_round`, and `handoff` are optional prompt-level inputs. Treat them as soft parameters and restate the effective values before acting.
- `handoff=claude` means the final passing report should include a concise third-party review handoff table with repo path, review range, and change summary. If autofix leaves uncommitted edits, write the range as `<base>..HEAD + working tree`.

## Workflow

1. Resolve mode, inputs, and review scope.
If the user provides a range, use it exactly and restate it in the review. If the user asks for `the last commit`, use `HEAD~1..HEAD`. If the user asks for `the last N commits`, use `HEAD~N..HEAD`. If the user says `review again`, prefer the newest explicitly requested range; otherwise fall back to `HEAD~1..HEAD` and state that choice. If the request is vague, default to `HEAD~1..HEAD` and state the range before listing findings.

2. Review committed content only by default.
Prefer `git diff <base>..<head>`, `git show <commit>:<path>`, and `git log --oneline`.
Include staged, unstaged, or working-tree changes only when the user explicitly asks for them, and state that scope change in the review.
In `autofix` mode, start from the requested committed range. After each fix/test cycle, commit by default and review `<base>..HEAD` in the next round. If commits are disabled, review the original range plus the accumulated working-tree diff and state the context-growth tradeoff.

3. Read applicable guidance before review.
Read root `AGENTS.md`, `CLAUDE.md`, or equivalent guidance first. Also read closer subtree guidance for changed files, and read referenced review docs such as `code_review.md` when an instruction file points to them.

4. Use subagents for the first review pass.
Spawn subagents when the user explicitly invoked `repo-review`, asked for subagents, or asked for parallel agent review, and the current Codex surface exposes subagent tools. Give subagents fresh, minimal context: repo path, exact range, applicable guidance, diff stat, assigned files or concerns, and output format. Do not pass patch intent, previous review conclusions, suspected findings, or the main thread's implementation history.

5. Assign bounded review scopes.
For small diffs, use two subagents: one for correctness/security risks and one for tests, integrations, deploy, and configuration. For medium diffs, use three to four subagents split by concern or module. For large diffs, split by repo, subsystem, or file batch so each subagent has a tractable scope, roughly 8-12 changed files or one coherent module. For multi-repo reviews, assign at least one subagent per repo, plus a cross-repo contract pass when interfaces or deployments interact. Avoid duplicate broad prompts; overlap only around critical interfaces, security boundaries, or cross-module behavior.

6. Keep the main agent unbiased.
The main agent coordinates ranges, guidance, and subagent scopes; it should not perform the same first-pass review over the whole diff before delegation. After subagents return, verify plausible findings against source, deduplicate, check severity, and report only concrete issues. If subagents are unavailable or not permitted by the current session, state that fallback and perform the narrow committed-diff review directly.

7. Re-derive conclusions from code.
Do not defend patch intent. Do not reuse earlier review conclusions unless the user explicitly asks to compare with a previous review.

8. Prioritize real findings.
Focus on bugs, behavioral regressions, missing tests, deployment breakage, security gaps, and mismatches between code paths.
Ignore style unless it causes a real maintenance or correctness problem.
Treat correctness, security, regressions, required test gaps, deploy breakage, and broken cross-file or cross-repo contracts as blocking. Treat purely stylistic suggestions as non-blocking.

## Autofix Loop

Use this loop only in `autofix` mode.

1. Run R1 with the normal subagent-first review workflow.
2. If there are no blocking findings, stop and report clean.
3. If blocking findings exist and the round limit has not been reached, fix only verified concrete findings. Keep edits minimal and preserve the existing codebase style.
4. Run the relevant tests or checks for the touched behavior. If no test command is discoverable, state that explicitly.
5. When tests pass, or when no relevant test command is discoverable and you have stated that, create a checkpoint commit by default before the next round, using a message such as `fix: R1 review fixes`. Never push. If tests fail or cannot run for an environment reason that blocks validation, stop instead of committing.
6. Start the next review round with fresh-context subagents. Recompute the diff and changed files from the fixed base to `HEAD`; do not reuse stale R1 prompts or previous reviewer conclusions.
7. If `commit_each_round=false`, skip checkpoint commits only by explicit request. Recompute the accumulated working-tree diff each round, keep the remaining rounds small, and report that context may grow because the tree is not checkpointed.
8. Stop when a review round has no blocking findings, `max_rounds` is reached, tests cannot run for a blocking environment reason, or the same finding survives two fix attempts.

Include all review-fix checkpoint commits in the final handoff summary. If the final result is clean and the user requested a polished commit history, squash review-fix commits into a meaningful final commit; otherwise leave commits intact and report the current branch state.

## Default Review Shape

For each repo:
- Identify the exact review range.
- State the exact review range when reporting findings.
- Gather diff stat, changed file list, and applicable guidance for subagent prompts.
- Use fresh-context subagents with bounded scopes for the first review pass when available.
- After subagents return, read only the files needed to verify plausible findings.
- Check whether tests exist for the changed behavior.
- Verify user-facing paths, deploy paths, and configuration wiring when infra or frontend code changes.

For the final output:
- List findings first, ordered by severity.
- Include file references and concrete reasoning.
- Keep summaries brief.
- If there are no findings, say `No findings.`
- In `autofix` mode, include the round history, fixes made, tests run, and final review result.
- In `autofix` mode, include the checkpoint commit hashes or state that commits were disabled.
- When `handoff=claude` or a third-party handoff is requested, include repo path, final review range, and a one-line change summary for each repo.

Use this handoff shape when requested:

```markdown
### Third-party Review Handoff

| Repo | Review Range | Summary |
|------|--------------|---------|
| `/path/repo` | `abc123..HEAD` | One-line change summary |
```

## Prompt Patterns

Use or adapt these request shapes in a new session:

```text
Use repo-review.
Review these repos in parallel using committed diffs only:
- /path/repo-a: <base>..<head>
- /path/repo-b: <base>..<head>
Spawn subagents with bounded repo/module scopes and read applicable guidance first.
Report only concrete findings with file references. If none, say No findings.
```

```text
Use repo-review.
Review /path/repo from HEAD~2..HEAD.
Use fresh-context subagents for the first pass.
Do not use prior review conclusions. Re-derive everything from code only.
```

```text
Use repo-review autofix.
Review /path/repo from HEAD~2..HEAD.
max_rounds=3
commit_each_round=true
handoff=claude
```

## Notes

- If the user asks for `the last two commits`, review commit-by-commit when useful, then add a consolidated section only if cross-commit interaction matters.
- If later fixes exist beyond an earlier reviewed range, switch to the newer requested range instead of repeating stale findings.
- When repo roots differ, keep file references absolute and keep repo boundaries explicit in the final report.
