---
skill: implement-issue
issue: 153
pr: 168
area: infra
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh, .claude/skills/implement-issue/SKILL.md, .claude/skills/review-pr/SKILL.md, .claude/agents/reviewer.md
skill_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
date: 2026-10-18
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** /code-review not run via the Skill tool (orchestrator rule); I reviewed the diff by hand. A network interruption cut the run midway; resumed from the commits.
**Decisions not covered:** the red had to go in the existing test-labels-check.sh (a new test file would not match the labels-check `when`), so I added a temp JS helper and one tap_check per case; the old valid bodies were updated in the green commit, since in the red commit they still passed. `timeout` does not exist on macOS, so perf cases use perl alarm.
**What the review found:** nothing from an automated review; verify.py passed (lint/typecheck/tests not configured).
**Proposal:** the skill could say that old tests whose fixtures the new rule invalidates are updated in the green commit, not the red one.
