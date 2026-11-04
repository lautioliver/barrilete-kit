---
skill: implement-issue
issue: 225
pr: 255
area: infra
paths: scripts/agents/tap.sh, scripts/agents/red_report.py, docs/agents-map.json, scripts/agents/test-tap.sh, .claude/skills/implement-issue/test-red.sh
date: 2026-11-04
skill_sha: eebc5b81b1f369c46b9e237b22ddf848160eeb11
model: sonnet
role: session
---
**Deviations:** the red commit was rewritten three times (a test that crashed instead of failing, a red commit that was empty because I wrote the file before the base commit, a harness bug on bash 5). I touched `red_report.py` although the issue comment said red.sh does not change (the ADR D4/D6 need it). The `test-init.sh` cases are not in the red commit: the bash entry would run it and it runs `test-tap.sh` expecting 0, which crashes the red. Several full test runs were done in parallel and one `timeout` corpus case flaked under load.
**Decisions not covered:** whether the file-presence check and the `.sh` D4 rule apply to every JUnit entry (I applied them, as the ADR says over-rejecting is accepted); applying `second marker:` to JUnit; leaving the `tap`-format file check and the copies in update.py/install.py/grow.py to later issues.
**What the review found:** invalid UTF-8 in the XML, a temp file left behind on a kill, chained greps in test-agents.sh (fixed); false rejects of test-like files, `second marker:` for other runners, `.sh` rule for other shell styles (explained in the PR). CI then found two things local runs did not: an unset `$2` under `set -u` on bash 5 in test-tap.sh, and test-update.sh still expecting the kit's entry as `tap`.
**Proposal:** the skill should say that a red commit which changes `test-tap.sh` cannot also change `test-init.sh`, and that a green change of the kit's entry means running test-update/test-install too (verify.py does not run them). Also: `sed -i` on macOS needs a suffix (`-i.bak`); `-i -E` leaves a `...-E` file.
