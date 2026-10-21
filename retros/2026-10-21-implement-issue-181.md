---
skill: implement-issue
issue: 181
pr: 183
area: agents
paths: scripts/agents/flow.py, scripts/init-template.sh, scripts/install.py, docs/guides/flow-line.md
skill_sha: aa963263a1d5d108581d55612357817f2a207dca
date: 2026-10-21
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** no red commit (the person is deciding how to handle it); tests in the same commit as the fix. No /code-review (forbidden by the launcher); hand pass.
**Decisions not covered:** docs/guides is deleted by the small profile, so the guide test has to expect the guide only in the full mode. A leer() shared by the cache and the numeric busy mark could not be made dict-only; the check went into a cache-specific helper.
**What the review found:** nothing from my hand pass beyond the above (the first run of the new test-init case bailed out on the small mode).
**Proposal:** none.
