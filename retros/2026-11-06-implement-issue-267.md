---
skill: implement-issue
issue: 267
pr: 268
area: agents
paths: scripts/agents/worktree-lock.sh, scripts/agents/test-worktree-lock.sh, .claude/agents/implementer*.md, .claude/skills/orchestrate/SKILL.md, docs/agents/subagent-contract.md
date: 2026-11-06
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: session
---
**Deviations:** `/code-review` on the diff and a mutation check of the new cases were not run in this round; the red was checked with `red.sh` (8 doc cases fail before the fix) and the fix was small (docs plus a header comment). The retro was saved after the PR summary, not before.
**Decisions not covered:** how a `/orchestrate` subagent keeps the lock after the orchestrator releases it. I chose that the subagent claims it with its own name as its first step, over transferring ownership, because both share the pid and `claim` already handles it. `release` without the mutex: left as is, with the reason in the header.
**What the review found:** the 2nd review found the orchestrator released the lock and nobody took it again, so the lock did not cover the work (the #262 situation). The previous round's test only proved that the subagent *could* claim, not that anything made it claim.
**Proposal:** when a fix is "someone must do X", the test should check the instruction that makes the actor do X (agent definition, contract), not only that X is possible.
