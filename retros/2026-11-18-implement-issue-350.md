---
skill: implement-issue
issue: 350
pr: 352
area: agents
paths: scripts/agents/worktree-lock.sh, scripts/agents/test-worktree-lock.sh, .claude/skills/implement-issue/SKILL.md, .claude/skills/implement-issue/SKILL.es.md, docs/agents/subagent-contract.md, docs/agents/subagent-contract.es.md
date: 2026-11-18
skill_sha: 7eee093de4c14fd3475f7f9319d21b9f0df8b475
model: opus
role: session
---
**Deviations:** three new cases in `test-worktree-lock.sh` looked only for the English phrase in `implement-issue/SKILL.md`. In a project installed with `--lang es` that file is the Spanish one, so `test-init.sh` (which runs the installed project's tests) failed in CI after ~11 minutes. Locally `verify.py` passed because it never runs the suite against an `es` install. Fixed in 443adf2 by accepting either phrase (`grep -qF -e <en> -e <es>`, the same idea as the `mencion` helper) and tested by copying `SKILL.es.md` over `SKILL.md`. The work was split across two sessions with a `bk handoff`; this second session only had to close CI, verify, retro and release.
**Decisions not covered:** none new. `check:pr-metadata` cannot run before the PR exists; it ran after and passed.
**What the review found:** `/code-review` raised 9 findings and 8 were fixed. The one left open is that the lock should be released by the mechanism on its own (for example, a timeout for idle owners). That needs a decision and its own issue.
**Proposal:** in `implement-issue`, when a test checks the text of a file that is installed per language (`SKILL.md`, docs), say that it must accept both languages or use `mencion`, or else run `test-init.sh` locally before the PR when you change tests that read skills. The `--lang es` path is only covered in CI, and that takes ~12 minutes.
