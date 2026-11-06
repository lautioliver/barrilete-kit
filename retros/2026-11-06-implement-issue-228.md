---
skill: implement-issue
issue: 228
pr: 275
area: infra
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh, CHANGELOG.md, docs/README.md, profiles/small/docs/README.md, .claude/skills/implement-issue/red.sh
date: 2026-11-06
skill_sha: da5949abe3ed0fed29aa083488f521ab3d37d48e
model: opus
role: session
---
**Deviations:** I started #228 while #272 (#227) was still open, on top of `main`, without checking the order between the two first. The issue said "Blocked by #226" only, but the epic (ADR-002 D8) says the CI rejection and the removal in `red.sh` ship together. `/code-review` was the one that noticed: on `main`, `red.sh` still printed `format: tap` blocks that the new check rejected. Because of that, I stopped `verify.py` once (~10 min wasted), held the PR until #272 merged, rebased (two CHANGELOG conflicts) and ran `red.sh` again for the new SHAs. The first rejection message ("run red.sh again") did not get the author out of the loop; it was fixed with its own red.
**Decisions not covered:** how to split the doc lines that #272 was already changing (I left them to #272 to avoid conflicts, and only touched what it did not). Whether to record "#228 blocked by #227" after the fact: asked, the person said yes.
**What the review found:** 9 findings from `/code-review`: the order with #272 (the real one), the message without a way out, a duplicated case; the rest resolved by #272 or already decided (ADR unchanged, CHANGELOG mixing 1.x/2.0.0).
**Proposal:** in step 2 of implement-issue, when the issue belongs to an epic with a staged rollout (1.x/2.0.0), check whether the issues of the same step that touch the other side (tool vs CI) are merged; if not, mark the blocker before starting, not after the self-review.
