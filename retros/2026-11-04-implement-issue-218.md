---
skill: implement-issue
issue: 218
pr: 240
area: docs
paths: AGENTS.md, AGENTS.es.md, profiles/small/AGENTS.md, profiles/small/AGENTS.es.md, .claude/skills/plan-feature, .claude/skills/implement-issue, profiles/small/.claude/skills/implement-issue
date: 2026-11-04
skill_sha: 021112fa07b6438f7c8f732630b0a672094e0353
model: haiku
role: session
---
**Deviations:** no red commit: the change is documentation and skill text with no behavior to test, so the PR carries `no tests: <reason>`. `/code-review` was first launched before the commit, so it reviewed an empty range; I ran it again on the committed range. `verify.py` reports lint, typecheck and tests as not configured, and the PR says so.
**Decisions not covered:** the skill does not say what an empty `contexts` map means (the kit ships it empty). ADR-003 D7 covers only an empty glossary, so I wrote the rule as the issue states it and left the open question in the PR. I also did not add the gate to the "Must ask first" list, which is an autonomy change.
**What the review found:** `/code-review` flagged the empty-map case as undecided, the gate missing from the autonomy list, the rule being in force before the enforcement issues (A2 to A6) land, and that the small-profile `implement-issue` does not say where `depends_on` lives. All four are questions for a person; none was changed in this PR.
**Proposal:** when an ADR adds a rule that depends on a data structure the kit ships empty, the skill or the ADR should say what the empty state means, in the same PR that adds the rule.
