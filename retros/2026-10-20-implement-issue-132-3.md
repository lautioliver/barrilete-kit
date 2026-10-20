---
skill: implement-issue
issue: 132
pr: 185
area: infra
paths: .claude/skills/implement-issue, scripts/agents/test-agents.sh, .claude/skills/improve-skills/test-retros.sh
skill_sha: 72dbfebc4af4d40e32cb6d5fa423bd1484b5561a
date: 2026-10-20
model: sonnet
role: implementer
agent_sha: da74fb6d0df623d9015f3d067b2b5c5fe6d9f0b4
---
**Deviations:** extra review round. My first red commit used forbidden forms (`|| true` in a substitution, `bash -c` with several programs, a `(cd && ...)` chain) that I had not checked against the list in step 3. The red was valid by luck of the check. I amended my unpushed second red commit once, because the documented command still used `<file>` and crashed instead of failing.
**Decisions not covered:** how a test runs a documented multi-program command without `tap_run` refusing it: write it to a script file and run it with `tap_run out 0 bash file`, with a comment saying why.
**What the review found:** fence with text on the closing line, forbidden test forms, a vacuous contract assertion, and a no-arguments retro.sh pointer that still ran the worktree copy. A shellcheck SC2016 also failed in CI after the round (I ran only `verify.py` pieces, not shellcheck on the new lines).
**Proposal:** run shellcheck on the changed test files before pushing, and re-read the forbidden-forms list before writing a red test.
