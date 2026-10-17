---
skill: implement-issue
issue: 151
pr: 163
area: infra
paths: scripts/agents/tap.sh, scripts/agents/test-tap.sh, scripts/test-*.sh, scripts/agents/test-*.sh, .claude/skills/*/test-*.sh, docs/agents-map.json
skill_sha: 6ec12861eb3ff04c0eefa85556d90a5816edd083
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 6ec12861eb3ff04c0eefa85556d90a5816edd083
---
**Deviations:** test-red.sh not migrated (the brief forbade touching it, the issue lists 12). Three tests were added or replaced after the red commit (several scripts in one stream, repeated id as one case) and were not seen red; the PR says so. The red block that red.sh printed first was a stale file from another run (same temp dir), so I rebuilt it from the red commit's files.
**Decisions not covered:** a literal id cannot be kept in loops, so repeated ids merge into one case (fails if any iteration fails). A blanket ERR trap breaks tests that check $? on purpose, so it only bails under set -e and the EXIT trap covers the rest. The skill does not say how a stub should behave so that red.sh sees FAIL lines: the stub's tap_fail printing FAIL - id worked. Multi-script streams need the path after load, so it stays in a non-exported variable.
**What the review found:** 9 findings, 3 fixed (dead echo after tap_done, FAIL line on stderr in stdout mode, nested-run diagnostics in test-init). Rest explained in the PR.
**Proposal:** the skill should say that a bash red can use a stub whose failure helper prints FAIL - lines, and warn that macOS has no timeout and bash 3.2 (no associative arrays, no mapfile).
