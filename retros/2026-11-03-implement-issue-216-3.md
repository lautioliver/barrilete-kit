---
skill: implement-issue
issue: 216
pr: 235
area: docs
paths: scripts/test-init.sh
date: 2026-11-03
skill_sha: 6af6e0f7f6d6586c037d1da72ae7bd34eca4bff0
model: sonnet
role: session
---
**Deviations:** `red.sh` of main needs `docs/agents-map.json` next to the extracted script, so I extracted that file too from main (the base's map, not the branch's). Also ran `/implement-issue` as "apply review" without a fresh `/code-review`: the change was two test lines.
**Decisions not covered:** how to rewrite a red commit that already has code on top (used `git commit --fixup` + `rebase --autosquash` onto main, no `-i`). Split the review-rule case from the `required` case instead of keeping one id; so the red block ids changed.
**What the review found:** a `grep -F` of a bare substring (`contexts.md`) matched an ADR link already on main, so the case could not fail; the exact-link form fixes it. Checked by deleting the line (mutation).
**Proposal:** in implement-issue, say that `red.sh` from `git archive` also needs `docs/agents-map.json`, and add "prove a new presence check by deleting what it protects" to the self-review.
