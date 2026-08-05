# Global Codex Guidance

## Skill authoring

- Before creating or updating any Codex skill, use and fully read the system `$skill-creator` skill.
- Then read `~/.dotfiles/codex/skill-building-guide.md` for this dotfiles repository's required authoring, evaluation, validation, and rollout workflow.
- Treat behavior evals as the oracle. Add instructions only for observed failures or required safety contracts; do not chase prose completeness.
- Do not vendor OpenAI skill-building documentation. Fetch current official documentation only when a product-sensitive detail is unresolved.

## Decision notes

- If the repo has a `STATUS.md`, append non-obvious trade-offs, rejected alternatives, and dead ends to its 「進行中」 section before you finish. Leave them uncommitted and unformatted; the shipping agent distills them into the formal sections.
- Skip this whenever the diff alone recovers the rationale. Only reasoning that reading the code cannot reproduce earns a note — a rejected path leaves no trace in the diff, an added gate does.

## Git discipline

- NEVER push and NEVER merge on your own. Commit, then stop and report. An instruction to implement, fix, or "ship" a change does not authorize pushing; only an explicit push/merge instruction does.
- NEVER stage unrelated changes. NEVER use `git add -A`, `git add .`, or `commit -a`. A working tree here is often shared with another agent session, and broad staging silently absorbs that session's in-flight work.
- Explicit paths are necessary but NOT sufficient: `git add <path>` is still whole-file. When one file mixes your edits with another session's, stage verified hunks only (`git add -p`), or move the other session's sections out of the tree, commit yours, and restore them last. Splitting by directory alone is what let the third incident recur.
- Inspect `git diff --cached` before every commit. After splitting a mixed file, verify from a clean checkout (`git clone --no-local`) — all three incidents in `~/.dotfiles` looked correct on disk and were visible only from a clean clone, so "I checked the working tree" is not evidence.
- Follow Conventional Commits: `<type>: <short desc>`, where type is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.
- Branching, PR creation, squash, and dossier distillation belong to the shipping agent's workflow. Do not reimplement or approximate them; leave the work committed on the current branch and hand off.
