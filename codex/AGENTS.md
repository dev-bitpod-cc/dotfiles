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
- **NEVER push without authorization for the push in front of you.** Implementing, fixing, or committing never carries it, and neither does approval given before this change existed. **Where a shipping workflow applies, its authorization table is the only source — NEVER extend it with synonyms of your own.** Where none applies, authorization is an instruction naming the action itself ("push", "open a PR"), or an affirmative answer to a confirmation you just presented. **A bare "ship it" / "送出" names an outcome, not an action — on its own it authorizes nothing**; present the confirmation and wait. Deciding for yourself which wording is close enough is the failure this rule exists to prevent. No authorization ever covers the default branch.
- **NEVER merge on your own.** "push" or "open a PR" alone does NOT include merge. Only an explicit merge instruction does.
- **NEVER `git add -A` / `git add .` / `commit -a`.** Stage explicit paths.
- **If the working tree holds changes you did not make, STOP and report before staging, committing, or building on top of them.** Whether two sessions may share one tree is a dispatch decision made above you — never resolve it locally by guessing which changes are yours. Once authorized, explicit paths are still whole-file: stage verified hunks with `git add -p`.
- **Inspect `git diff --cached` before every commit.** After splitting a mixed file, verify from a clean clone — `git clone --no-local <repo> <tmpdir>`. "I checked the working tree" is not evidence.

### Fallback conventions — this repo's own convention wins where it has one

- Conventional Commits: `<type>: <short desc>`, type is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. **If this repo mandates another commit format, follow the repo.**
- Record non-obvious trade-offs, rejected alternatives, and dead ends **where this repo already keeps them**. Skip whenever the diff alone recovers the rationale — a rejected path leaves no trace in the diff, an added gate does. **If the repo has no such store, do NOT create one; list them in your report instead.**
<!-- agent-contract:kernel:end -->

## Shipping

- With authorization in hand (see the kernel's push rule), follow **the repo's own shipping workflow** — its protection and dossier checks, its ship summary, its PR step. Use the repo's shipping skill when one exists.
- **No shipping workflow in the repo → commit on the feature branch and stop.** Do not assemble an approximation of one; the checks you would be skipping are the reason the workflow exists.
- Merge only on an explicit merge instruction. Without authorization, leave the work committed on the feature branch and report it.
