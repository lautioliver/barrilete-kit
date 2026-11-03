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
**Deviations:** `prepare.sh` failed with a 403 (the bot token cannot read the issue through it), so I read the issue with `gh issue view --json` and carried on with the branch that already existed. The PR has `no tests: docs only`.
**Decisions not covered:** the issue asks the implementer to write concrete values (warning text, `update.py` behaviour, rename of `tap.sh`, fate of #208/#210) that no comment approved. I proposed one default each and asked once in the chat before writing. The skill does not say what to do with the follow-up issues of an epic: I used `create-issue` and asked for a "yes" on the batch.
**What the review found:** `/code-review` returned 7 findings, all about `red_report.py`, `tap.sh`, `test-install.sh` and `test-tap.sh`, none in my diff (two ADR files). It looks like it reviewed a different range than the one I passed, so I fixed nothing and said so in the PR.
**Proposal:** `implement-issue` could say that when the issue is a decision with open values, the single question of step 2 has to list those values with a recommended default. And `/code-review` run from a forked agent should print the range it reviewed so a mismatch like this one is visible.
