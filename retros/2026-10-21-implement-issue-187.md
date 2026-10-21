---
skill: implement-issue
issue: 187
pr: PENDING_PR
area: infra
paths: scripts/agents/test-agents.sh
skill_sha: aa963263a1d5d108581d55612357817f2a207dca
date: 2026-10-21
model: haiku
role: implementer-light
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** step 3 (red first) was not done: this is a refactor of two existing test lines (same ids, same meaning), so the PR says `no tests: ...` and the suite is the check. Step 5 `/code-review` was not run: the launch rules forbid the Skill tool, so the bug pass was done by hand (see PR).
**Decisions not covered:** the skill's suggested form `n=$(grep -c ...); [ "$n" -eq 0 ]` bails out on the normal pass path, because tap.sh does not treat a grep exit 1 inside an assignment as an assertion. The change used `grep -q PAT FILE; [ $? -eq 1 ]; tap_check $? ...` instead, checked on a clean file (ok), a file with the pattern (not ok) and a missing file (bail out), on bash 3.2.
**What the review found:** nothing (no /code-review run). By hand: the old `!` form turned a grep crash (status 2) into a pass; the new form bails out on it.
**Proposal:** tap.sh or the implement-issue guide could say that `x=$(grep ...)` is not an assertion, so an agent does not try the `grep -c` form first.
