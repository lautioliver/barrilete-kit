---
skill: implement-issue
issue: 267
pr: 268
area: agents
paths: scripts/agents/worktree-lock.sh, scripts/agents/test-worktree-lock.sh, .claude/skills/implement-issue/prepare.sh, .claude/skills/implement-issue/test-prepare.sh, .claude/skills/review-pr/SKILL.md, .claude/skills/orchestrate/SKILL.md, .claude/agents/implementer*.md, .claude/agents/reviewer.md, docs/agents/subagent-contract.md
date: 2026-11-07
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: opus
role: session
---
**Deviations:** (1) The fixes for rounds 3 to 5 were spread over several sessions, and only the round 1 and 2 retros were saved; this one covers rounds 3 to 6. (2) Each round fixed the flow the reviewer reported (orchestrator, then review session, then `bk run`) and the next round found another launcher with the same hole. The class was "every launcher of an agent in a worktree releases or hands over the lock". The examples were fixed one at a time. (3) `bk run` was left out of the PR (#276) at the person's request.
**Decisions not covered:** in round 6, `prepare.sh` releases the lock on exit if it fails after taking it. It only releases a new lock: it reads `status` before the `claim`, and if the lock was already this agent's (`held`) it keeps it. This avoids an agent losing its own worktree because an assignment failed while resuming. The person chose to skip a 6th review and only make this fix.
**What the review found:** round 3: the subagent did not release on finishing, and the `release` command had no name. Round 4: the review session held the lock against the implementer it launched. Round 5: `bk run` without a name (#276), behavior cases that only checked the last output, `lstart` depending on TZ, the mutex never exercised, and the `prepare.sh` command without a path. Round 6 (no review): release when `prepare.sh` fails after taking the lock. I checked with a mutation that the "keeps its own lock" case fails if it always releases.
**Proposal:** when an issue adds a resource that someone claims and has to release (a lock, an assignment, a worktree), implement-issue could ask for a table of who takes it and who releases it, with one row per launcher (orchestrator, review session, `bk run`, a person), before the first red. In this PR each round of review found a missing row.
