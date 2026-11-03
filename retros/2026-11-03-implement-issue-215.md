---
skill: implement-issue
issue: 215
pr: 223
area: none
paths: profiles/small/docs, docs/decisions/kit/ADR-003-minimal-ddd-glossary-and-contexts.md
date: 2026-11-03
skill_sha: 6af6e0f7f6d6586c037d1da72ae7bd34eca4bff0
model: sonnet
role: session
---
**Deviations:** none. Docs-only correction round: no red (`no tests:` in the PR), no new `/code-review` (3 text edits).
**Decisions not covered:** the skill does not say how to run the init `--small` to check docs; I used a `git archive` copy in a scratch dir (the init rewrites files in place).
**What the review found:** the first round forgot the four small-profile indices; the ADR-003 line has to be added wherever ADR-002 is listed (grep the sibling ADR across profiles).
**Proposal:** when adding a docs index entry, grep for the previous ADR's name in `profiles/` too.
