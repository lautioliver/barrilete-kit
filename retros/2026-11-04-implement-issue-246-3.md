---
skill: implement-issue
issue: 246
pr: 251
area: agents
paths: .claude/skills/orchestrate/test-orchestrate.sh
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: session
---
**Deviations:** the two test suggestions of round 2 (anchor the D3 cases to the bullet, narrow `2>/dev/null` to the mode.py paragraph) strengthen tests that already pass, so there was no red to run; I checked them by mutation (removing the command from D3, flipping the stderr text) instead. The PR body edit and the CI check were not done: the bot's gh token expired (HTTP 401) after a ~45 min verify.py.
**Decisions not covered:** how to cover "test strengthening with no failing case" in TDD; I committed the tests and showed the mutation by hand. Also what to do when the gh token expires after the push: I stopped and did not look for other credentials.
**What the review found:** round 2 found the red commit still holds forbidden forms (the person decided to keep it), a renamed red case (explained in the body), and the loose D3 and 2>/dev/null tests (fixed).
**Proposal:** verify.py took 2683s in i18n and 717s in renames with another session running at once; running verify in two worktrees at once is very slow. A slice-per-check timeout or a lock would help. The bot gh token lives ~1h, so a long verify can outlive it: refresh before gh calls.
