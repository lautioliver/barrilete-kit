---
skill: implement-issue
issue: 157
pr: 160
area: docs
paths: .claude/skills/implement-issue/SKILL.md, .claude/skills/implement-issue/SKILL.es.md, .claude/skills/review-pr/SKILL.md, .claude/skills/review-pr/SKILL.es.md, .claude/agents/implementer.md, .claude/agents/implementer-light.md, .claude/agents/reviewer.md, .claude/i18n/agents/implementer.es.md, .claude/i18n/agents/implementer-light.es.md, .claude/i18n/agents/reviewer.es.md, docs/agents/subagent-contract.md, docs/agents/subagent-contract.es.md
skill_sha: e2fea7e23d5849f4d4108796eaffbf3d1baba088
date: 2026-10-17
model: haiku
role: implementer-light
agent_sha: 37b007a181fdbaec3233a2eabb71bda500ec2514
---
**Deviations:** No tests (docs only), declared as `no tests:` in the PR. Two `/code-review` runs; the first found wording I had introduced wrong (relative retro path after `cd`, Spanish contract naming `refs/review/` while the Spanish reviewer uses `refs/revision/`, a trust rationale attributed to `cd`, bash red without the non-zero exit rule). All fixed in follow-up commits. Did not touch `red.sh`. `/code-review` was run twice; the second run's findings were addressed in the last commit.

**Decisions not covered:** Whether the Spanish translation of the ref name `refs/revision/` stays: `test-orchestrate.sh` encodes it, so I kept it. Whether `AGENTS.md` ("They work only in their worktree") should be aligned with the reviewer's exception: left for a person, since it is a rule document.

**What the review found:** Not fixed, out of this issue: (1) `red.sh` accepts a capitalized `Expected`/`Received` or `expected … to` anywhere in the output, so an arbitrary error line can count as an assertion (epic #148). (2) `reviewer.md` line 20 says to delete the worktree but gives no `git worktree remove` command (pre-existing). (3) The red-recognition rule is copied into six files; a single source would avoid drift.

**Proposal:** Put the red.sh recognition rule in one place and link to it. Give the reviewer an explicit worktree removal command.
