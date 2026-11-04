---
skill: implement-issue
issue: 236
pr: 237
area: agents
paths: .claude/skills/orchestrate/SKILL.md, .claude/skills/orchestrate/test-orchestrate.sh, .claude/skills/orchestrate/test-mode.sh, AGENTS.md
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** `no code-review: bug pass by hand` (round 4 of a PR already reviewed three times). The first `verify.py` run failed on i18n because I only ran the English tree: the new helper used `| grep -c` under `pipefail`, which bails under `--lang es`. Fixed in a separate commit, no history rewritten. Also lost time with `Monitor` loops using `pgrep -f` that matched themselves.
**Decisions not covered:** how to handle the same forbidden idiom (`!`/`||` around grep) in older cases of the file that were never in a red: left as is and noted in the PR. Fixing the helper under the red rules: `tap.sh` also bails on a `$(grep)` inside arithmetic, so the safe form is `[ "$(grep -Ec …)" = 0 ] || …`.
**What the review found:** the previous red hid two forbidden forms that pass when a file is missing; `gh pr list --head` does not take a prefix; AGENTS.md contradicted the ADR on which roles can be `bk`.
**Proposal:** in implement-issue step 7, say that for text tests `verify.py` i18n (about 4-5 min) is the one that catches `--lang es` breakage, so run it before pushing; and warn that `pipeline | grep -c` is a crash under `tap.sh` when nothing matches.
