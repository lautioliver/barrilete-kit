---
skill: implement-issue
issue: 259
pr: 262
area: agents
paths: scripts/agents/test-classes.sh, scripts/agents/check-docs.py, .claude/skills/review-pr, CHANGELOG.md
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** relaunched for the review of #262. The test fix (helper that hid check-docs.py's status) is a test-only change, so I did not do a separate red commit; I proved each case instead by mutating check-docs.py (a raise, class errors turned into warnings): the first bails out, the second gives 10 failing cases. I merged origin/main instead of rebasing to keep the red commit shas that the PR body cites. A forked /code-review run committed two commits (897efc7 test, e6d3a3a fix) in the worktree on its own.
**Decisions not covered:** whether a test that is no longer a red commit may use tap_run expecting 1 (the skill only forbids it in the red); I used it with tap_no_traceback. The skill does not say what to do about commits another process makes in the worktree meanwhile.
**What the review found:** /code-review medium: finding lines without the literal file:line are not validated, strict parser vs real YAML, CHANGELOG claim about update. Kept as known limits (the regex trigger is by design, update.py ships every kit file).
**Proposal:** a `mutar`-style helper (apply mutation, run one program, check status) in tap.sh would avoid every test rebuilding it.
