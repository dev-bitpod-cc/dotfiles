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

- NEVER push and NEVER merge on your own. Commit, then stop and report. An instruction to implement, fix, or "ship" a change does not authorize pushing; only an explicit push/merge instruction does. Even then, NEVER push the default branch and NEVER open or merge a PR — those stay with the shipping agent, which runs the protection and dossier checks you do not.
- NEVER commit onto the default branch (`main`/`master`). If `HEAD` is on it, create a feature branch first — `git switch -c <type>/<slug>` — and commit there. This mirrors the branch-first rule the shipping workflow enforces; a commit stranded on the default branch has to be rescued later.
- NEVER stage unrelated changes. NEVER use `git add -A`, `git add .`, or `commit -a`. A working tree here is often shared with another agent session, and broad staging silently absorbs that session's in-flight work.
- If the working tree holds changes you did not make, STOP and report before staging, committing, or building on top of them. Whether two sessions may share one tree is a dispatch decision made above you — never resolve it locally by guessing which changes are yours.
- Once the user confirms it is safe to proceed on a mixed tree, explicit paths are necessary but NOT sufficient: `git add <path>` is still whole-file. When one file mixes your edits with another session's, stage verified hunks only (`git add -p`), or move the other session's sections out of the tree, commit yours, and restore them last. Splitting by directory alone is what let the third incident recur.
- Inspect `git diff --cached` before every commit. After splitting a mixed file, verify from a clean checkout — `git clone --no-local <repo> <tmpdir>` — because all three incidents in `~/.dotfiles` looked correct on disk and showed up only in a clean clone. "I checked the working tree" is not evidence.
- Follow Conventional Commits: `<type>: <short desc>`, where type is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.
- PR creation, squash, and dossier distillation belong to the shipping agent's workflow. Do not reimplement or approximate them; leave the work committed on your feature branch and hand off.
