---
skill: implement-issue
issue: 231
pr: 234
area: agents
paths: .claude/skills/implement-issue/prepare.sh, .claude/skills/implement-issue/test-prepare.sh, .claude/skills/project-status/available.sh, docs/agents/subagent-contract.md, profiles/small
date: 2026-11-03
skill_sha: eea654e4ab951ef517188bf876a94bbedde4b5f1
model: sonnet
role: session
---
**Deviations:** resumed an existing PR (corrections round) instead of a fresh issue. The exit-64 cases (gh error shown, invalid login) are not in the red commit: `tap_status` is forbidden there, so they went in the green commit. I replaced an old passing assertion (no raw 403) because the review reversed that criterion.
**Decisions not covered:** the skill says nothing about a corrections round on an open PR: whether to rewrite the PR's red block (I added a new red commit and replaced the block with its sha). Also whether `/code-review` findings that come from a stale `origin/main` count: I ran `git fetch` and checked the real diff (11 files) before discarding them.
**What the review found:** invalid/empty `BK_HUMAN` (`@`) slipped through the emptiness check, and a leaked mktemp file; both fixed. Four findings (red_report.py, tap.sh, test-install.sh, ADR-003) were false, from a stale `origin/main`.
**Proposal:** in step 5, say to `git fetch origin <base>` before `/code-review origin/<base>...<branch>`, so a stale base does not produce findings about files the PR does not touch.
