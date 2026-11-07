---
skill: implement-issue
issue: 273
pr: 277
area: agents
paths: scripts/agents/tap.sh, scripts/agents/test-tap.sh, CHANGELOG.md
skill_sha: da5949abe3ed0fed29aa083488f521ab3d37d48e
date: 2026-11-07
model: haiku
role: implementer-light
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** round 2 of PR #277 (review fixes). Self-review: `/code-review` not invoked (the orchestrator forbids it, it moves its checkout); bug pass by hand, declared in the PR. The PR body's "How to test it" numbers were regenerated from this round's runs, but not the old mutation claims (`accept tap`, `no check`) from round 1: they were not rerun, so they were dropped from the body. verify.py's i18n step did not finish in this round (the run was still on it after about 15 minutes), so the body says so instead of claiming it.
**Decisions not covered:** whether the rejection of `TAP_FORMAT=tap` without `TAP_OUT` should be unconditional (the reviewer raised it; left as the issue asks: without TAP_OUT the stdout stays the same). The stdout case "writes nothing to stdout either" was kept with an id that says what it measures instead of being dropped.
**What the review found:** CHANGELOG missing the Ruptura entry and the #225 line still recommending `TAP_FORMAT=tap` (fixed). The "stdout does not reach the report" guarantee was only checked by a TAP-era case that was removed; added a JUnit case that fails under `exec 1>&8` after opening TAP_OUT (verified in an isolated copy). The PR body wrongly said that case always passed on main (fixed in the body).
**Proposal:** verify.py's i18n step ran for more than 15 minutes with a nested test-i18n.sh spawning repeatedly; worth a look by whoever owns test-i18n.sh. The red commit sha changes on every rebase: the body had to be rewritten with the new sha (e63a9db), so the reviewer could otherwise compare a stale block.
