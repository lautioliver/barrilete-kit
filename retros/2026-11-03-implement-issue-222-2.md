---
skill: implement-issue
issue: 222
pr: 230
area: infra
paths: docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md
date: 2026-11-03
skill_sha: 6af6e0f7f6d6586c037d1da72ae7bd34eca4bff0
model: sonnet
role: session
---
**Deviations:** `no tests:` (docs only). `/code-review` not rerun on this correction (docs-only second commit; the first run was in the original PR); I reviewed the diff by hand. Did not comment on #225 or edit it: left to the person.
**Decisions not covered:** how `tap_skip_all` is written in JUnit (`tests="0"` plus `<system-out>`) and the exact shape of the "script that does not finish" rule were not in the review or the skill; written in the ADR and flagged in the PR as new rules for the person to approve. The skill does not say what to do with a review's suggestion that conflicts with a count in another issue (#225 says 15 `test-*.sh`, the repo has 14).
**What the review found:** 6 points and 4 suggestions on the ADR (self-contradicting D2 example, JUnit guard missing for dead scripts, TAP rules left only in a tag, D1/D2 vs D8, skip in JUnit, missing follow-up issue). All applied except point 6, which is a draft awaiting the person.
**Proposal:** `review-pr` could check counts that the text repeats (`12`, `14`, `15`) against the repo.
