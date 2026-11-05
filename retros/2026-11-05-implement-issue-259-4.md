---
skill: implement-issue
issue: 259
pr: 262
area: agents
paths: scripts/agents/check-docs.py, scripts/agents/test-classes.sh, scripts/test-init.sh, .claude/skills/review-pr
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** the `--lang es` case in `test-init.sh` has no red of its own: a nested test that fails ends with a `Bail out!`, which `red.sh` rejects, so it was added in a green commit and its evidence is a manual run of the old test in an `--lang es` install. Published red commits with forbidden forms were not rewritten (told to leave history); the new red avoids them.
**Decisions not covered:** how to write a red for a verdict tool that exits 1 (check-docs.py) without `tap_run ... 1`: a single `python3 -c` runner that prints the output and `RC=<n>` and ends with 0, plus a `second marker:` case that proves the tool reached its summary. The skill describes the runner only for the #182 shape. Also: shellcheck SC2319 fired on `$?` after a `[ ]` only because a later `n=$(cmd <<<"$out")` existed in the file (found by bisecting the file by lines); a `while read` loop avoided it. The failure showed up in a nested test-tap.sh case (test-install.sh's shellcheck of the installed kit), not in verify's shellcheck entry.
**What the review found:** /code-review: finding lines are validated only if they mention file:line, non-class brackets on those lines are false positives, the strict YAML reader is a subset, a bad description was reported twice (fixed), `--lang es` runs only for the full profile (not fixed), the weak base-run comparison (documented). Third independent review: the installed-in-Spanish layout (SKILL.md in Spanish, no SKILL.es.md) that the test chose by file name.
**Proposal:** implement-issue step 3 could say how to red-test a tool whose verdict is exit 1 (the runner plus second marker shape) and that tests that run in an installed project need a `--lang es` pass in `test-init.sh`.
