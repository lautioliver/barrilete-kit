---
skill: implement-issue
issue: 211
pr: 212
area: agents
paths: docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md
date: 2026-11-02
skill_sha: 08b30f89fc480666f624ce1072e9d14f19f035ab
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** `/code-review` was not re-run in this round (docs-only change: two citations in the ADR paragraph). No red commit: the PR body carries `no tests: docs only, a citation in the ADR`. `verify.py` ran inside a command chained with `git push` and went to the background after the 120s timeout, so the push waited on it; I also started to `sleep` on it and the harness blocked that.
**Decisions not covered:** how to cite a person's approval in the ADR when the same paragraph already cites one comment: I kept the original citation (6573742553) and added the other two inline next to the phrase each one backs, in both languages. The skill does not say what to do with the PR body in a docs-only review round; I appended a "Third review" sentence to the business-logic paragraph and left the red block untouched.
**What the review found:** the third review of #212 asked only for the two citations (6573772548 for `<n>: second marker:`, 6562098812 of #209 for the crash exception). Nothing else.
**Proposal:** in implement-issue, say that `verify.py` takes several minutes (about 5 here) and should be run with `run_in_background` and not chained with `git push`; and say what to do with the PR body in a review round with no code.
