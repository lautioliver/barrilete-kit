---
skill: implement-issue
issue: 264
pr: 283
area: infra
paths: scripts/agents/tap.sh, scripts/agents/red_report.py, scripts/agents/test-tap.sh, .claude/skills/implement-issue/test-red.sh, docs/guides/red-per-runner.md, docs/guides/red-per-runner.es.md, CHANGELOG.md
date: 2026-11-07
skill_sha: 9bcbd75445af645960c9ec3d2b48fae01ff067cf
model: opus
role: session
---
**Deviations:** (1) `verify.py` was killed by the harness after 10 minutes (exit 144) while running `i18n`; I ran the remaining checks of the map one by one with their own commands (`test-base.sh`, `test-renames.sh`, `test-tap.sh`, `test-i18n.sh`) and said so in the PR. (2) The first PR title was over 72 characters (the `pr-title` check would have failed); shortened with `gh pr edit` right after creating it. (3) Point 5 of the issue was already fixed by #277, so its case passes at the red commit: it is in the red commit as a regression guard, outside the failing list, and I checked by hand that it fails if the format check moves after the `exec`.
**Decisions not covered:** (1) Point 3 (`AMR` → `AMRC`) touches D6 of ADR-002 and the kit's `run` (D7): I left the options in a comment on the issue and used `Refs` instead of `Closes`, so the issue stays open until the person decides. The skill says what to do when the whole issue needs a decision, not when one of its points does. (2) The issue asked to write limit (8) (every `.sh` case read as a `tap.sh` id) in the cargo2junit section of the guide; I put it in the bash section, where it applies, and said so in the PR. (3) For the late bail I chose a second testsuite with only the error testcase (the cases are forgotten after the write) over the reviewer's `_TAP_BAILED=1`, which would hide the crash from the report when another case fails; the ADR allows it ("a closed testsuite, or an error testcase").
**What the review found:** `/code-review` (medium) found the ordering window the fix had left (the arrays were cleared after the write, and bash runs the TERM trap between commands), the header of `tap.sh` and both guides still saying "one closed testsuite", the CHANGELOG entry listed as a fix of unreleased code, a duplicated fixture between the two python scripts of `test-red.sh`, and that the red case only drove the bail-file branch. All fixed; the TERM route now has a deterministic guard (a `sed` shim sends TERM from inside `_tap_clean`). Two findings dismissed with reasons in the PR.
**Proposal:** `verify.py` from an agent session hits the 10-minute cap of a background command; the skill could say to run it detached (`nohup`/`setsid` with a done file) or per check. The skill could also say what to do when only one point of an issue needs the person: `Refs` plus a comment on the issue, and keep going with the rest.
