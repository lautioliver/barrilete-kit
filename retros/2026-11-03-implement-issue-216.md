---
skill: implement-issue
issue: 216
pr: 235
area: docs
paths: docs/reference/, profiles/small/docs/, docs/agents-map.json, scripts/test-init.sh
date: 2026-11-03
skill_sha: 6af6e0f7f6d6586c037d1da72ae7bd34eca4bff0
model: sonnet
role: session
---
**Deviations:** prepare.sh failed with a gh 403 (bot token); issue was already assigned and the branch existed, so I continued and said so in the PR. I rewrote the red commit once (fixup + autosquash) after a too-literal grep in my own test, and re-ran red.sh.
**Decisions not covered:** the ADR asks for a person's approval to touch the map and test-init.sh although agents_map.py marks no sensitive path; I asked once in the chat. A grep on a missing file is status 2, a crash for tap.sh: red tests need a `[ -f ] && grep` helper; and a check-docs call that exits 1 by design cannot be in a red.
**What the review found:** /code-review low returned no findings.
**Proposal:** document in the skill the grep-on-missing-file pitfall for red tests of generated files.
