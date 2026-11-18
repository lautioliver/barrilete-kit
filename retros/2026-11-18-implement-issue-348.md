---
skill: implement-issue
issue: 348
pr: 354
area: infra
paths: scripts/agents/learning.py, scripts/agents/test-learning.sh, docs/decisions/kit/ADR-007-per-project-learning.md, docs/agents/learning-event.md
date: 2026-11-18
skill_sha: 27a1947ee312dc9fbbcf418c7af4aa075868ae73
model: sonnet
role: implementer
agent_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
---
**Deviations:** none. No agent_sha or skill_sha came in the task, so retro.sh fills them in. I used the orchestrator-side checkout's retro.sh (no retro_sh was given).
**Decisions not covered:** the strictest reading of owner, repo, sha and path (written in the PR). The skill says nothing about testing a regex against catastrophic backtracking: the test needs an alarm wrapper because macOS ignores RLIMIT_CPU, and a hang is not a failed case.
**What the review found:** /code-review found 5 points, 3 fixed. Hostile input of 300 KB exceeds the Linux per-argument limit (fixed, 100 KB). A repo made only of dots passed (fixed with a red case). The trailing-newline `$` is now `\Z`. Left as is on purpose: the local path class is as permissive as before (the decision said so). My own mutations found two guards with no case (300-char path, local path class) before the review.
**Proposal:** red.sh docs could say that a mutation that makes the test hang shows as a bail, not a failing case, when the guard is a hostile-input one.
