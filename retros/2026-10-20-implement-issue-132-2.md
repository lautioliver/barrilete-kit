---
skill: implement-issue
issue: 132
pr: 185
area: infra
paths: .claude/skills/orchestrate, .claude/skills/implement-issue, .claude/agents, docs/agents/subagent-contract.md, scripts/agents/test-agents.sh
skill_sha: 72dbfebc4af4d40e32cb6d5fa423bd1484b5561a
date: 2026-10-20
model: sonnet
role: implementer
agent_sha: da74fb6d0df623d9015f3d067b2b5c5fe6d9f0b4
---
**Deviations:** no /code-review (forbidden under /orchestrate), bug pass by hand. I ran the retro with the orchestrator's retro.sh, as the issue asks. After the red commit I fixed my own tests in a separate commit (the .es.md siblings do not exist in a --lang es install; test-i18n caught it), which I only found because verify.py ran i18n, which takes about 330 s and hit the 600 s foreground limit on the first run.
**Decisions not covered:** the third criterion mentions profiles/small of implement-issue; the real small profile has no retro step and DELETEs improve-skills/orchestrate/agents, so nothing changed there. The red test for the behavioral criterion extracts the documented command from SKILL.md (otherwise it would pass at red). Labels: the red block I pasted first was truncated and the labels check failed; fixed by pasting the full pr-block.md.
**What the review found:** nothing (hand pass).
**Proposal:** tests that grep es siblings should say in the SKILL how to guard for --lang es installs; and verify.py's i18n step is slow enough to need a background run.
