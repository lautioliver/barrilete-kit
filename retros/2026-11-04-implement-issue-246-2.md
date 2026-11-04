---
skill: implement-issue
issue: 246
pr: 251
area: agents
paths: .claude/skills/orchestrate/test-mode.sh, .claude/skills/orchestrate/SKILL.md, docs/decisions/kit/ADR-004-orchestrate-launch-mode-per-role.md, README.md
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** the earlier session was cut by a tmux restart; I resumed with the two unpushed commits, checked them against the published review (4 "to fix" + suggestions, all covered) and then found two verify failures the previous commits did not have: shellcheck SC2319 in `test-mode.sh`, and a one-off `tap` failure (case 139). I did not add the `business-logic` label the review suggested: it needs the ADR-amendment line, which is a decision for the person.
**Decisions not covered:** the PR branch is behind `main`; I pushed without force and did not rebase (it would need a force push). Whether a one-off failure of `test-tap.sh` under load counts as flaky: I re-ran it on the branch and on `main` and both passed (138 cases).
**What the review found:** stdout/stderr were merged in the tests, `2>/dev/null` in the SKILL hid the warning the plan needs, forbidden forms (`grep &&`, `! grep`) in the red, and a stale ADR Status sentence. The previous commits fixed these but shipped shellcheck warnings because `verify.py` had not been run to the end.
**Proposal:** shellcheck 0.11 raises SC2319 on every `[ ]; tap_check $?` of a file as soon as one top-level `x=$(cmd)` appears before a `$?`; put the capture inside a helper function (`split_run`) and use `awk` for counts, since `grep -c` with 0 matches makes `tap.sh` bail out. Worth a line in `docs/agents/lessons.md`. Also: `verify.py` takes ~10 minutes (i18n 587s) and a foreground call times out: run it in the background.
