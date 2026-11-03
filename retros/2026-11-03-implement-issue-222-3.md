---
skill: implement-issue
issue: 222
pr: 230
area: none
paths: docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md
date: 2026-11-03
skill_sha: 6af6e0f7f6d6586c037d1da72ae7bd34eca4bff0
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** `/code-review` not run: the diff is two ADR files and the review points were applied by hand (`no code-review: docs only`). No red commit (`no tests:` docs). I broke the en file once (duplicated `## Context` while rewriting a paragraph with a slice by index); `check-docs.py` caught it before the push.
**Decisions not covered:** the skill says nothing about applying a second review that needs a person's decision: I wrote the decision only after the person's comment existed and cited it. Rules I added (kit-entry recognition in `update.py`, `red.sh` check that every diff test file appears in the report, `TAP_FORMAT` name) are marked "pending approval" in the ADR and listed in the PR body instead of being presented as decided.
**What the review found:** the reviewer found real contradictions between ADR text and code (`tap.sh` EXIT trap already reports an early `exit`; stdout under `red.sh`), i.e. an ADR that describes code must be checked against `tap.sh`, not just against the earlier review.
**Proposal:** in implement-issue, say that when a review asks for a person's decision, the agent waits for the comment link and cites it, and that ADR text about existing scripts is verified against the script.
