---
skill: implement-issue
issue: 276
pr: 284
area: infra
paths: scripts/agents/test-worktree-lock.sh, docs/agents/subagent-contract.md, .claude/skills/implement-issue, .claude/skills/orchestrate, .claude/skills/review-pr
date: 2026-11-07
skill_sha: 3f92233e5771a1e862351de53ec980fe3134e18d
model: sonnet
role: session
---
**Deviations:** I took the issue without a comment from a person approving the option: the decision comment was written by an agent with the person's login, and the person had decided in the chat. I went ahead and said so in the report. The PR uses `Refs`, not `Closes`, because the code of #276 lives in barrilete-workspace (opened as barrilete-workspace#5).
**Decisions not covered:** whether a PR that only documents what another repo will do can close the issue (it does not). Where to test a protocol that spans two repos: I modeled the `bk` side with the real `worktree-lock.sh` and env vars.
**What the review found:** no `/code-review` run (docs and test change, bug pass by hand). `test-init.sh` found a miss that `verify.py` did not run: the small profile installs `implement-issue` without the `bk` part, so a doc case without the CHICO skip failed there.
**Proposal:** `verify.py` does not run `test-init.sh` for a change to a test that the init installs; a test of docs that the small profile edits should be checked against an `init --small` copy before the PR.
