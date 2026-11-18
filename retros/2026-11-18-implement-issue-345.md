---
skill: implement-issue
issue: 345
pr: 360
area: docs
paths: docs/decisions/kit/ADR-007-per-project-learning.md, docs/decisions/kit/ADR-007-per-project-learning.es.md, docs/agents/learning-event.md, docs/agents/learning-event.es.md
date: 2026-11-18
skill_sha: 7fe49d2d1ce2184e3a28f4aaa34a6fcd9570a9a9
model: opus
role: session
---
**Deviations:** prepare.sh refused the main checkout because of an untracked docs/bitacora.html that was not mine. I used `--worktree` instead of touching it.
**Decisions not covered:** the issue left D5 open ("say whether it stays like that or a mapping is added"). I asked, and the person chose the mapping now, in classes.yml. That widened the amendment beyond the clarification in the title. The follow-up work (barrilete-rules schema, validator and values; bk learn effect) has no issue yet, and the ADR says so in Consequences. I recorded the three decisions in an issue comment before editing the ADR, because the issue body does not count as approval.
**What the review found:** nothing (/code-review low on a docs-only diff).
**Proposal:** when an issue leaves a decision open ("decide whether X or Y"), implement-issue could say to ask for it in the same message as the autonomy approval, not after reading the code. Here it took three rounds of questions.
