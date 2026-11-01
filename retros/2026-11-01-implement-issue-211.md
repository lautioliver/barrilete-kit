---
skill: implement-issue
issue: 211
pr: 212
area: infra
paths: scripts/agents/red_report.py, scripts/agents/tap.sh, .claude/skills/implement-issue, .claude/skills/review-pr, scripts/agents/test-*.sh
date: 2026-11-01
skill_sha: 35d3c5ea9eb9f1deeee344c65b9c79e989730415
model: sonnet
role: session
---
**Deviations:** I started the green after the person chose option (a) but their answer did not include an explicit "yes" to the ADR-002 D6 / business-logic change I had also asked for; I took choosing the option as approval and said so in the PR ("ADR unchanged"). The first PR body missed the literal "ADR unchanged: <reason>" and the labels check failed; fixed by editing the body.
**Decisions not covered:** a red whose failing case is an old line is rejected, so a corpus case (checked by an old generic loop id) cannot be the red: new behavior of red.sh had to be tested with an explicit new `tap_check` id. red.sh takes ~70 s and rejects edits to tracked files while it runs.
**What the review found:** /code-review: red.sh does not require the second-marker case to exist, match is case/whitespace sensitive, skipped case not covered, rc-file rule not enforced by red.sh. Not fixed (out of the issue's scope), explained in the PR.
**Proposal:** the skill could say that the labels check needs the literal "ADR unchanged: <reason>" in the PR body whenever business-logic is on.
