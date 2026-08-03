# Global Codex Guidance

## Skill authoring

- Before creating or updating any Codex skill, use and fully read the system `$skill-creator` skill.
- Then read `~/.dotfiles/codex/skill-building-guide.md` for this dotfiles repository's required authoring, evaluation, validation, and rollout workflow.
- Treat behavior evals as the oracle. Add instructions only for observed failures or required safety contracts; do not chase prose completeness.
- Do not vendor OpenAI skill-building documentation. Fetch current official documentation only when a product-sensitive detail is unresolved.

## Decision notes

- If the repo has a `STATUS.md`, append non-obvious trade-offs, rejected alternatives, and dead ends to its 「進行中」 section before you finish. Leave them uncommitted and unformatted; the shipping agent distills them into the formal sections.
- Skip this whenever the diff alone recovers the rationale. Only reasoning that reading the code cannot reproduce earns a note — a rejected path leaves no trace in the diff, an added gate does.
