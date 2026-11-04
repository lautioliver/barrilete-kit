---
skill: implement-issue
issue: 217
pr: 241
area: agents
paths: scripts/agents/check-docs.py, scripts/agents/agents_map.py, scripts/agents/test-agents.sh, scripts/test-update.sh
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** `/code-review` was not rerun this round (the 2nd review's suggestions were applied one by one, each checked against the test suites). The test-update.sh case (project: glossary check is a warning) has no red commit: check-docs.py exits 1 on findings, a program expected to fail is forbidden in a red (tap_run with a status other than 0 bails), and the bash helper `check()` that allows it lives in test-agents.sh only. The `contexts: null` case also has no red (a crash is not a failed case, ADR-002 D6). Both are said in the PR. I first wrote a second case (missing glossary in a project) that bailed because removing the glossary also breaks unrelated links; I dropped it, the link case covers the same code path.
**Decisions not covered:** how to tell "kit" from "project" in check-docs: I reused `scripts/init-template.sh` existence, as the ADR index check does. Moving `minimo()` in test-agents.sh to create that file so its existing cases keep testing the kit's error.
**What the review found:** the 2nd review's items (warning in projects, contexts null, empty name, readable merge, missing full-profile test, stale body). llms.txt in --small and the destinos_de/enlaza duplication were left as notes in the PR body.
**Proposal:** implement-issue's red section could say how to red a verdict tool (exit 1 on findings) when the test file has no `check()`-style helper; today the guide forbids the only form that works, and the agent has to give up the red and say so. Also, running test-update.sh/verify.py takes 10+ minutes: say so in the skill so agents run them in the background from the start. `timeout` does not exist on macOS.
