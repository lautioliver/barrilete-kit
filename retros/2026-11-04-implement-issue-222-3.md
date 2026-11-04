---
skill: implement-issue
issue: 222
pr: 230
area: docs
paths: docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md
date: 2026-11-04
skill_sha: eebc5b81b1f369c46b9e237b22ddf848160eeb11
model: sonnet
role: session
---
**Deviations:** no red commit (docs-only, `no tests:` stays in the PR); `/code-review` not rerun on prose edits. Retro saved from a base-branch copy of retro.sh.
**Decisions not covered:** the person said "the ADR fixes principles, not mechanics"; I kept one principle sentence per point (an `error` of a grouped case still counts for D3) instead of dropping the points entirely, since D3 already says it. I also touched the #150 refinement line (`TAP_OUT` for every entry) so it does not contradict D6.
**What the review found:** round 4 found that the rules written by the previous implementer (XML root, repeated id, test-file recognition per runner) assumed `red.sh` knew the runner, which it does not. Rules the reviewer offered as two options and the agent picked one were written as ADR rules; the person pulled them out to #225 as design questions. Also an approval status in the ADR/body that disagreed with the person's comment, because the comment was posted seconds before the review.
**Proposal:** when a review offers two options, write the question for the person (or the follow-up issue), not a rule in the ADR; check the timestamp of the person's comment against the review it approves.
