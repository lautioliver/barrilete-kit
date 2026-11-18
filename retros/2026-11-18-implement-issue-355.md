---
skill: implement-issue
issue: 355
pr: 358
area: infra
paths: scripts/agents/checks/pr-metadata, scripts/agents/red_report.py, scripts/agents/test-checks.sh, CHANGELOG.md
date: 2026-11-18
skill_sha: 7fe49d2d1ce2184e3a28f4aaa34a6fcd9570a9a9
model: opus
role: session
---
**Deviations:** the first red used the id `test.each con \$name…`, which test-tap.sh rejects (no `$` in an id, even escaped); it only showed up in `verify.py` (tap), after the green. The red commit was rewritten before the push (format-patch, amend, red.sh again, git am with one conflict). One new case (`suma 1 extra`) was wrong: `%s` absorbs `1 extra`, which is correct; it was changed to `otra suma 1`. Another (`pide y x`) collided with the fixture `'%s…%sx'`, which accepts any name ending in x.
**Decisions not covered:** reusing `red_report.title_matches` would have brought its regex backtracking into pr-metadata (4 placeholders against 500 chars: 8 s). I asked the person; they chose to make it linear in red_report in the same PR.
**What the review found:** /code-review (medium): describe.each groups with placeholders were still rejected (the same class, one level up); JS names were split on `::` (red_report splits only on ` > `); the timeout case did not reach the middle-pieces loop; the parts generator was hard to read. All fixed with cases. A mutation then showed that groups also accepted it.each titles (M7 survived), and one more case was added.
**Proposal:** implement-issue could say to run `bash scripts/agents/test-tap.sh` (or the `tap` verify) before the red commit when a test-*.sh changes: its id rules (`$` in a literal) are not in the list of forbidden forms of the red, and finding it after the green means rewriting the red commit.
