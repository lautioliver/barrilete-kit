---
skill: implement-issue
issue: 231
pr: 234
area: infra
paths: .claude/skills/implement-issue/prepare.sh, .claude/skills/implement-issue/test-prepare.sh, .claude/skills/project-status/available.sh
date: 2026-11-03
skill_sha: eea654e4ab951ef517188bf876a94bbedde4b5f1
model: sonnet
role: session
---
**Deviations:** the App-token cases (criteria 1 and 3) are in the green commit, not the red: prepare.sh exits 1 there and the red rules forbid expecting status 1. The red covers a user token with BK_HUMAN set. prepare.sh was run first and failed with a 403 (gh was the bot's), so the branch and assignment already existed.
**Decisions not covered:** BK_HUMAN wins over the token user; no normalization of "@" or case. Not documented in AGENTS.md.
**What the review found:** /code-review flagged a "out of scope changes" finding that was false (stale local origin/main); the rest were hardening I left out and explained in the PR.
**Proposal:** say in implement-issue that a bug whose failure mode is exit 1 cannot be a red, and what to do (test it in the green commit, or make the red hit a path that exits 0). Fetch origin/<base> before /code-review.
