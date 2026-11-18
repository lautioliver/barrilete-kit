---
skill: implement-issue
issue: 349
pr: 353
area: infra
paths: scripts/agents/checks/pr-metadata, scripts/agents/test-checks.sh, CHANGELOG.md
date: 2026-11-18
skill_sha: 27a1947ee312dc9fbbcf418c7af4aa075868ae73
model: sonnet
role: implementer
agent_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
---
**Deviations:** the first launch returned `question` because the worktree lock was held by the orchestrator's own name (`agent`, taken by `prepare.sh --worktree`); the orchestrator released it and relaunched me. Two ordinary `verify.py` runs hit the 120 s tool timeout (the `tap` stack takes about 3 minutes) and I read the result from the background output. A first `verify.py` showed `tap` failing once on test-install.sh:139 (not mine, passes on main and on my branch alone; probably load from other sessions).
**Decisions not covered:** how to match JS exactly like `red_report` without importing it: a regex with an optional backslash before each character. I kept a local copy of `JS_EXT` instead of importing `red_report`; I did not add a drift test. Other languages are now searched as written, without unescaping (`red_report` defines no escapes for them).
**What the review found:** `/code-review` (7 findings, 0 fixed, all classified): non-sh/js languages no longer unescape (intended: `red_report` accepts only identifiers there); case-sensitive extension (same as `red_report`); `JS_EXT` duplicated (noted in the PR); the regex is a substring search (documented limit of the check); `it.each` placeholders are not matched (pre-existing, outside the issue, noted in the PR); the comment above the fixture line sits after the heredoc (cosmetic); the CHANGELOG order (fine).
**Proposal:** `orchestrate` could release the lock under the name `prepare.sh` used (`agent`) or tell the subagent the lock name; and a note in the contract that `verify.py` needs a background run.
