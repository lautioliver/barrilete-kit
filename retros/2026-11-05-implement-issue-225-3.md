---
skill: implement-issue
issue: 225
pr: 255
area: infra
paths: scripts/agents/tap.sh, scripts/agents/red_report.py, scripts/agents/test-tap.sh, .claude/skills/implement-issue/test-red.sh
date: 2026-11-05
skill_sha: 8f2bf8fad83a8ae9d2c3ea0a7b81aca57c2bead2
model: sonnet
role: session
---
**Deviations:** `/code-review` not run on this round (a fix round of the 3rd review); I read the diff by hand. I did not re-run the whole `verify.py` after the last commit (a one-line shellcheck directive): only shellcheck on the three files. The red block of round 4 was run with `TAP_FORMAT=tap` in the environment, because `main`'s `red.sh` does not export it yet and the red commit sits on top of the new `tap.sh`.
**Decisions not covered:** how to add a red for a fix round when the original red commit must not be rewritten: a second red commit on top, a second `<details>` block in the PR. The skill only describes the first red. Also, the red of a PR that changes the helper itself cannot be validated by the trusted `red.sh` without an env workaround.
**What the review found:** the 3rd review: missing `business-logic` label, `missing_test_files` O(tree) per case, U+FFFE/U+FFFF, a subshell + tr + iconv per value (7.1 s to 1.85 s for 500 cases), the error testcase name, the AMR hint, 73-char title. All fixed or written down as limits (cargo2junit, `.sh` from other producers).
**Proposal:** say in `implement-issue` how a fix round adds its red (a new commit and block) and that `verify.py shellcheck` runs everything (it took more than 10 minutes here); a way to run one check.
