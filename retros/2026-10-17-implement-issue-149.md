---
skill: implement-issue
issue: 149
pr: 156
area: docs
paths: docs/decisions/ADR-002-structured-red-validation*.md, docs/README*.md, docs/llms*.txt, profiles/small/docs
skill_sha: 5b87389249c36f6477068eb6850a69d2252a26e1
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 3a7e8277a739835896f3f5e0c8aab2d856cb398a
---
**Deviations:** /code-review ran from the orchestrator checkout (the forked skill uses the session cwd, not the worktree) and reviewed an empty diff; I reviewed by hand and said so in the PR. No red tests (docs only).
**Decisions not covered:** the init installs every non-kit ADR, so the profile small indexes (profiles/small/docs README and llms) also need the ADR-002 line, otherwise test-init.sh fails in chico mode. Also check-docs flags backticked paths that do not exist yet (future files) or that small mode lacks (agents-map.json): write them without backticks.
**What the review found:** nothing (empty diff). CI found the small-profile index and the missing-path problems; fixed in a second commit.
**Proposal:** run test-init.sh locally when a docs index changes; tell subagents that /code-review needs the worktree as cwd or an explicit path.
