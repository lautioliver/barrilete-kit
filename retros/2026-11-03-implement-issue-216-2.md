---
skill: implement-issue
issue: 216
pr: 235
area: docs
paths: scripts/test-init.sh, docs/llms.txt, docs/llms.es.txt, docs/agents-map.json
date: 2026-11-03
skill_sha: 6af6e0f7f6d6586c037d1da72ae7bd34eca4bff0
model: sonnet
role: session
---
**Deviations:** none. Rewrote the red commit (reset to base, cherry-pick, re-apply the green as a patch) because the review changed the red; pushed only this branch with `--force-with-lease` pinned to the old sha.
**Decisions not covered:** red.sh from `origin/main` via `git archive` needs `docs/agents-map.json` extracted too (it reads the map from its own ROOT); the skill's command only archives the skill dir. Also: the small profile's llms.txt has no line-9 rule, so the exception applies only to docs/llms*.txt.
**What the review found:** grep to the left of `&&`/`||` in the red (7 checks); approval not recorded in a comment; llms.txt rule contradicted by listing TODO templates (the person decided an explicit exception, ADR-003 D7).
**Proposal:** add `docs/agents-map.json` (and `scripts/agents`) to the `git archive` line in the Retro/red section so red.sh from main works out of the box; mention that test-init.sh takes ~6 min, so run it in background.
