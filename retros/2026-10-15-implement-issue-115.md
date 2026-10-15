---
skill: implement-issue
issue: 115
pr: 135
area: docs
paths: .claude/agents, .claude/skills, scripts/agents/test-agents.sh, .claude/skills/orchestrate/test-orchestrate.sh
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
date: 2026-10-15
model: sonnet
role: implementer
agent_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Deviations:** TDD inverted: translated first, then saw which Spanish-grep tests broke and adapted them; no red commit (PR says "no test" and lists the failures). /code-review first ran in the orchestrator checkout (HEAD there) and returned empty; had to rerun passing the branch name.
**Decisions not covered:** the issue says 3 PRs but the parity switch can only turn on in the last one; English literals for PR/issue template headings were chosen ahead of PR 3. .es.md agent siblings get loaded by Claude Code as duplicate agents: not addressed.
**What the review found:** English commit-description rule vs Spanish AGENTS.md, template literal mismatch until PR 3, duplicate agent names. None fixable inside this PR.
**Proposal:** the skill should say that /code-review in a worktree needs the branch or path explicitly; and an ADR/issue to decide where agent .es.md siblings live.
