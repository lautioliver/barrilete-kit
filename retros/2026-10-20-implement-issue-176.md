---
skill: implement-issue
issue: 176
pr: 179
area: docs
paths: .claude/skills/implement-issue, .claude/skills/review-pr, .claude/agents, .claude/i18n/agents, docs/guides/red-per-runner, README, docs/try-the-template
skill_sha: 11a4784c1ce6b94f1cb0fd52550b4c1d8ea13c55
date: 2026-10-20
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** /code-review not run (forbidden by the orchestrator brief); bug pass by hand. First push failed CI (docs) because I wrote `red-per-runner.es.md` in the Spanish skills: test-init with --lang es deletes the suffix. verify.py did not catch it locally in its short steps; only test-init.sh did.
**Decisions not covered:** reviewer reads the skill from "$root" (trusted), not the PR checkout as the issue literally said. Dropped the agents_map modules.md point with a reason.
**What the review found:** nothing (no code-review).
**Proposal:** in .es.md files, reference sibling docs without the `.es` suffix; say so in update-docs or check-docs so it fails locally.
