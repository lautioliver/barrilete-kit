---
skill: implement-issue
issue: 236
pr: 237
area: agents
paths: .claude/skills/orchestrate/SKILL.md, .claude/skills/orchestrate/SKILL.es.md, .claude/skills/orchestrate/test-orchestrate.sh, .claude/skills/orchestrate/test-mode.sh, docs/decisions/kit/ADR-004-orchestrate-launch-mode-per-role.md
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** no `/code-review` (declared in the PR, bug pass by hand: the changes are text plus a test helper). The red commit was amended twice before its first push (my own unpushed commit, not a pushed one): the first red was rejected by `red.sh` because I used the old `ambos` helper, whose `tap_check` line is not one the red commit adds; then the `--lang es` i18n test broke it; then a helper that returns 1 is a crash for `tap.sh`.
**Decisions not covered:** how to write red tests for a docs/SKILL text change that must also pass in an installation with `--lang es` (the init leaves Spanish as `X.md` with no `.es.md`). I used a `cada` helper that prints `ok` or the files that fail and compares it with `[ ... = ok ]`. The base-branch rule for `escalate` stayed in prose; the review offered `--base` in `mode.py`, left as a question.
**What the review found:** nothing from a tool; the 4 points of the third human/agent review, all applied.
**Proposal:** `implement-issue` step 3 could say that a red test over SKILL text has to work in `--lang es` installs (check with `scripts/agents/test-i18n.sh`, which takes ~8 min), and that a helper function must not return non-zero (print and compare). `verify.py` i18n is slow: run it once at the end, not per edit.
