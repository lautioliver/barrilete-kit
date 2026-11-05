---
skill: implement-issue
issue: 259
pr: 262
area: agents
paths: scripts/agents/check-docs.py, scripts/agents/test-classes.sh, scripts/test-init.sh
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** none. The runner of the old red (`python3 -c` ending with 0) was replaced at the tip with `tap_run out 1`, allowed outside the red; the old red commit was not rewritten. A tmux window of an earlier session was still open idle in the worktree (bk ls showed it closed); I proceeded after checking it had no activity.
**Decisions not covered:** how to red-test a fix of a test helper (`con_errores_nuevos` counting warnings): used a unit case with synthetic output, since the failure only shows in an installed project; proved the real case by hand in en and es installs (28 cases fail with class errors as warnings). Cannot be shown by `red.sh` in the kit itself.
**What the review found:** /code-review: 7 findings, none fixed (heuristic coverage of tag lines, YAML subset corners, map entry not migrated by update.py, contract not mentioning the tag, test brittleness to message text, heading-based language detection): all by choice or out of scope.
**Proposal:** the skill could say that a test-helper fix with no kit-visible failure gets a synthetic-input unit case plus a by-hand mutation in an installed project; and that `bk ls` can show a closed task whose window is still open, so liveness should also be checked by process cwd.
