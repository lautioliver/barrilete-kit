---
skill: implement-issue
issue: 236
pr: 237
area: docs
paths: .claude/skills/orchestrate/mode.py, .claude/skills/orchestrate/test-mode.sh, .claude/skills/orchestrate/SKILL.md, docs/agents/subagent-contract.md, docs/decisions/kit/ADR-004-orchestrate-launch-mode-per-role.md
date: 2026-11-03
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** `/code-review` was not run in this correction round (bug pass by hand over `mode.py`, declared in the PR). One shell line of the review, the `--root` test, could not go in the red commit: a nested crash is a `Bail out!`, not a failed case, so it went with its fix in the green commit. A python edit script aborted halfway on one string mismatch ("Relanzás" vs "Relanzá") and I had to re-run the rest by hand; nothing was lost, but I checked what had already been applied before re-running.
**Decisions not covered:** the person confirmed D1–D5 "as they are" and the review asked to reword D2. I left D1–D5 untouched, put the clarification (parsed twice, `mode.py` wins) in Consequences, and left the D3 wording (it still cites the output block for a `bk` agent) as a question in the PR. The skill does not say what to do when a review fix collides with a confirmed decision. Also: how a new red commit relates to an old one (I stacked a third red commit, no force push).
**What the review found:** nothing I had missed in the first round except the contract text for `bk` agents, the hardcoded relaunch and the silent fallback in `mode.py` for a role line that does not parse. All came from reading `bk`'s real launch path, not from the tests.
**Proposal:** `red.sh` docs could say that a case which crashes (a missing path, a traceback) is rejected and goes with the fix, not the red. `verify.py` takes ~5 minutes (i18n 197 s): it would help to say so in step 7.
