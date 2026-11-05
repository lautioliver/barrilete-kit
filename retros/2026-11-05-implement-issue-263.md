---
skill: implement-issue
issue: 263
pr: 270
area: docs
paths: .claude/agents/reviewer.md, docs/decisions/kit/ADR-004-orchestrate-launch-mode-per-role.md, scripts/agents/test-agents.sh
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: session
---
**Deviations:** `/code-review low` returned empty output, taken as no findings and said so in the PR. The red had to be redone twice: `test-i18n.sh` crashes in red because it runs `test-agents.sh` nested (moved to the green commit), and a changed row of a loop test is rejected as an old test (reviewer got its own literal-id cases).
**Decisions not covered:** the issue says ADR-004 "D2" but the role table is D1; the amendment says D1. Asked for the business-logic approval before touching code: the issue body states the decision but a comment from the person was required.
**What the review found:** nothing (empty output from /code-review). verify.py caught a stale `'opus'` expectation in test-i18n.sh that the issue's list did not mention.
**Proposal:** implement-issue could say that a test row inside a loop cannot be the red and that a test that runs another test nested cannot go in the red commit. Also: macOS `sed -i` needs `''`, `timeout` does not exist.
