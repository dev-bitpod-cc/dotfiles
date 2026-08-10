# Global Codex Guidance

## Skill authoring

- Before creating or updating any Codex skill, use and fully read the system `$skill-creator` skill.
- Then read `~/.dotfiles/codex/skill-building-guide.md` for this dotfiles repository's required authoring, evaluation, validation, and rollout workflow.
- Treat behavior evals as the oracle. Add instructions only for observed failures or required safety contracts; do not chase prose completeness.
- Do not vendor OpenAI skill-building documentation. Fetch current official documentation only when a product-sensitive detail is unresolved.

## Repo contract precedence

Before starting work in any repo, look for a root `AGENTS.md` (then `CLAUDE.md`) — **if present, it is that
repo's authority on its own conventions**. The kernel below is your behavioural floor in **every** repo: the
safety floor is never relaxed by a repo's conventions (stricter rules stack on top), while fallback
conventions defer to whatever the repo itself mandates. Where a repo has no contract file, this is all of it.

<!-- agent-contract:kernel:start v1 -->
## Kernel

### Safety floor — never relaxed by any repo

- **NEVER commit onto the default branch** (`main`/`master`). If `HEAD` is on it — or detached — create a feature branch first: `git switch -c <type>/<slug>`. This holds regardless of protection state and regardless of which tooling is loaded.
- **NEVER push on your own.** Commit, then stop and report. An instruction to implement, fix, or "ship" does not authorize pushing.
- **NEVER merge on your own.** "push" or "open a PR" alone does NOT include merge. Only an explicit merge instruction does.
- **NEVER `git add -A` / `git add .` / `commit -a`.** Stage explicit paths.
- **If the working tree holds changes you did not make, STOP and report before staging, committing, or building on top of them.** Whether two sessions may share one tree is a dispatch decision made above you — never resolve it locally by guessing which changes are yours. Once authorized, explicit paths are still whole-file: stage verified hunks with `git add -p`.
- **Inspect `git diff --cached` before every commit.** After splitting a mixed file, verify from a clean clone — `git clone --no-local <repo> <tmpdir>`. "I checked the working tree" is not evidence.

### Fallback conventions — this repo's own convention wins where it has one

- Conventional Commits: `<type>: <short desc>`, type is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. **If this repo mandates another commit format, follow the repo.**
- Record non-obvious trade-offs, rejected alternatives, and dead ends **where this repo already keeps them**. Skip whenever the diff alone recovers the rationale — a rejected path leaves no trace in the diff, an added gate does. **If the repo has no such store, do NOT create one; list them in your report instead.**
<!-- agent-contract:kernel:end -->

## Division of labour

- Even with an explicit push instruction, NEVER push the default branch and NEVER open or merge a PR — those stay with the shipping agent, which runs the protection and dossier checks you do not.
- PR creation, squash, and dossier distillation belong to that workflow. Do not reimplement or approximate them; leave the work committed on your feature branch and hand off.
- Leave decision notes uncommitted and unformatted wherever the repo keeps them; the shipping agent distills them into the formal sections.
