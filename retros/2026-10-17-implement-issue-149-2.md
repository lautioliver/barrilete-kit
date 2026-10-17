---
skill: implement-issue
issue: 149
pr: 156
area: docs
paths: docs/decisions/kit/, scripts/agents/check-docs.py, scripts/agents/test-i18n.sh, scripts/test-init.sh, docs/README.md, docs/llms.txt
skill_sha: e2fea7e23d5849f4d4108796eaffbf3d1baba088
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 37b007a181fdbaec3233a2eabb71bda500ec2514
---
**Deviations:** none. The review round followed the skill (red tests first, green, /code-review, verify.py, PR body update).
**Decisions not covered:** how a red.sh entry with no `-- <command>` is picked (decided: `red` array with `when` globs, `red.sh <stack>`), and one group per stack in the PR block; both flagged for the reviewer. The repo was renamed (barrilete-kit) while the remote still says agent-kit-template, so which name to cite in an installed ADR was not covered.
**What the review found:** /code-review found 8: multi-stack block ambiguity, a TODO contradiction in D3, the ADR describing things that do not exist yet, a kit/ ADR with an Ambito line not warned about. Four fixed, four left as documentation limits.
**Proposal:** the init-installed docs test forbids install.py, #122 and epic #33; say so in the skill for docs that are installed, so an ADR is not written with them first. Also a zsh note: `echo =====` fails in zsh.
