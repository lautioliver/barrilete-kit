---
skill: implement-issue
issue: 246
pr: 251
area: infra
paths: .claude/skills/orchestrate, docs/decisions/kit/ADR-004, README.md, README.es.md
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: session
---
**Deviations:** `verify.py` was not re-run in full after the last docs-only commit (it takes ~15 min); I re-ran check-docs and the two orchestrate tests instead. After the red commit I edited two red-era tests (D3 case, two old mode tests); stated in the PR.
**Decisions not covered:** a test helper that runs `grep` on a possibly missing `.es.md` sibling crashes under `--lang es` (status 2 = Bail out); use the existing `ninguna`/`cada` helpers instead of ad-hoc greps.
**What the review found:** a stray `)` left by my own edit in SKILL step 4 (en/es), a duplicated sentence in the READMEs, and the skill not documenting the new stderr line. All fixed; the `--search` ambiguity was left as the issue requested.
**Proposal:** a `bk`-style shortcut to run only the `--lang es` copy of a single test would save the 6-minute i18n loop.
