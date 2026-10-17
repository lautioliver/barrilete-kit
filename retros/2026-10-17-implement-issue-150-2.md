---
skill: implement-issue
issue: 150
pr: 164
area: agents
paths: profiles/small/.claude/skills/implement-issue/SKILL.md, scripts/agents/red_report.py, scripts/test-init.sh
skill_sha: 6ec12861eb3ff04c0eefa85556d90a5816edd083
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 6ec12861eb3ff04c0eefa85556d90a5816edd083
---
**Deviations:** /code-review not run (orchestrator told me not to use the Skill tool); reviewed by hand. Took over an interrupted round: most items were already committed, so I verified each against code and finished the rest.
**Decisions not covered:** the small profile ships no agents map, so the red docs there cannot cite docs/agents-map.json as an existing path; I said to create it.
**What the review found:** CI docs failed on test-init small mode (check-docs missing path) caused by the earlier doc migration; a try to add a DOCTYPE handler via XMLParser.parser failed (C XMLParser has no .parser on 3.9), reverted since NUL rejection already closes the bypass.
**Proposal:** verify.py runs test-init for ~10 min with no progress output; a per-step progress line would help.
