---
skill: implement-issue
issue: 170
pr: 172
area: infra
paths: scripts/agents/tap.sh, scripts/agents/test-tap.sh, scripts/agents/test-agents.sh, .claude/skills/implement-issue/SKILL.md, .claude/skills/review-pr/SKILL.md
skill_sha: 38f9ed97ea1209ea11fdf13744db36f1e018c076
date: 2026-10-19
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** no /code-review (the orchestrator told me not to use the Skill tool); I read my own diff. PR opened as a draft because blocker 1 is open and returned `question`.
**Decisions not covered:** two red probes (lone program in a substitution) cannot pass on bash 3.2; the skill does not say what to do with a red case that stays red by design. I kept them and asked.
**What the review found:** nothing (no code-review).
**Proposal:** red.sh only recognizes tap_ok/tap_fail/tap_check lines as case definitions, so a local wrapper (check $?) in a test-*.sh gives "not defined by a line this commit adds"; say so in the skill.
