---
skill: implement-issue
issue: 229
pr: 285
area: infra
paths: scripts/install.py, scripts/grow.py, scripts/update.py, scripts/test-update.sh, scripts/test-install.sh, CHANGELOG.md
date: 2026-11-07
skill_sha: 9bcbd75445af645960c9ec3d2b48fae01ff067cf
model: sonnet
role: session
---
**Deviations:** `red.sh` ran while I edited the green code in the same worktree (it validated the commit, so no harm, but it was a race I should not create). I ran test-update.sh and verify.py in the background, which made the cycle slow (about 10 min per run).
**Decisions not covered:** (1) Renaming `[Sin publicar]` to `[2.0.0]` without touching `VERSION`: update.py only shows numbered sections, so it was needed for the note to reach projects. (2) Fixed the test-update fixture (empty CHANGELOG in the test template) instead of loosening the assertions, because the real CHANGELOG now carries the 2.0.0 text.
**What the review found:** `/code-review`: 6 findings, none fixed (nameless entry and invalid JSON same as update.py, copies by design, CHANGELOG without Sin publicar asked by the issue, exit code 0 same as update.py). Real regression came from my own CHANGELOG change: 3 test-update cases (96, 100, 102) failed; confirmed the base passed 103/103 before fixing.
**Proposal:** the skill could say to run the full test-update.sh after touching CHANGELOG.md, since the fixture copies the real one.
