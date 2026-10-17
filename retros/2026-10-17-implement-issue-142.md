---
skill: implement-issue
issue: 142
pr: 144
area: docs
paths: scripts/agents/check-docs.py, scripts/agents/test-i18n.sh, scripts/test-init.sh, CHANGELOG.md, .github/workflows/labels.yml
skill_sha: 5b87389249c36f6477068eb6850a69d2252a26e1
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 3a7e8277a739835896f3f5e0c8aab2d856cb398a
---
**Deviations:** /code-review first ran on the orchestrator checkout (empty diff) because the forked skill does not inherit the worktree cwd; had to rerun with explicit `git -C <worktree>` in the args. Fixes to vacuous tests cannot be red; verified the manual.es.md one by mutating the init.
**Decisions not covered:** the issue listed two items already fixed in main (labels.yml ~103 comment, try-the-template text); I verified and said so in the PR. Two suggestions changed CI behavior and were excluded by the orchestrator's approval scope.
**What the review found:** a duplicate warning for Scope: kit vs the new sibling check (fixed), and a misleading n=0 fallback in test-init (fixed); parser limits accepted and documented in the PR. A first small-mode regression (NameError, no map) was caught by test-init, not by me beforehand.
**Proposal:** implement-issue should say that code-review as a subagent needs the worktree path in its args. Also: red.sh over a 2-minute test blocks the foreground; suggest running it in background.
