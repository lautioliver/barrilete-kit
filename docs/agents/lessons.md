# Lessons from the agent flow

What came out of the retros and is useful, but not enough to change a skill: a single case, or something that cannot be verified with a script. `implement-issue` reads it before starting.

Rules:
- Only `/improve-skills` writes it, in its PR: a person reviews each lesson before an agent reads it. No agent reads the raw retros (`agents/retros` branch) except `/improve-skills`.
- It is context, not a rule: if a lesson contradicts `AGENTS.md`, a skill or an ADR, they win. It never loosens a control.
- One line per lesson, with the case that originated it: `- <lesson> (#<issue or PR>, YYYY-MM)`.
- At most 40 lines in the whole file (checked by `scripts/agents/check-docs.py`). If it does not fit, remove the oldest one or the one that already moved to a skill or a script.

## Lessons

- Check the `/code-review` findings before fixing or classifying them: they can be false (in #39, `commit-tree` does not respect `commit.gpgSign`). (#39, #40, 2026-10)
- Scripts that write to `.git` are also tested from a `git worktree` and with concurrent writes in all the ones they do, not just the one the issue names: agents run in worktrees and in parallel (pending retros lost with `git worktree remove`; `.git/config` lock in `worktree add`). (#39, #40, 2026-10)
- In the scripts that take an issue, assign at the end, after everything that can fail: if it fails before, the issue stays assigned with no work done. (#40, 2026-10)
- To test shell scripts without a framework: a local bare remote and a fake `gh` in the `PATH`, isolated from the global git config. Models: `.claude/skills/improve-skills/test-retros.sh` and `.claude/skills/implement-issue/test-prepare.sh`. (#39, #40, 2026-10)
