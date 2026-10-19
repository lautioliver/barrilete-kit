---
skill: implement-issue
issue: 152
pr: 171
area: infra
paths: scripts/agents/check-docs.py, scripts/init-template.sh, profiles/small, docs/guides, scripts/agents/test-agents.sh, scripts/test-init.sh
skill_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
date: 2026-10-19
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** no /code-review (the orchestrator forbade the Skill tool: it moves its HEAD); I reviewed the diff by hand with git. I opened the PR with an empty body once (a python one-liner truncated the file it read), so the labels check failed until `gh pr edit 171`.
**Decisions not covered:** a new test file for the red cases made old cases fail (the verify-coverage case of test-agents.sh and the project-tests loop of test-init.sh), and red.sh rejects any failing case the commit does not define. I put the cases in the existing test-agents.sh and changed the id of the old test-init.sh case. The skill does not say what to do when new tests break old cases that cover every test-*.sh. Also: ADR text cannot cite a path that the small profile does not ship (check-docs flags it in projects).
**What the review found:** no code-review; hand review found the small profile map used a weaker `run` than the kit's bash entry, fixed to reuse the kit one.
**Proposal:** in step 3, say that a new test-*.sh must be in the map (verify) and that the init test runs every project test: add the cases to an existing covered test file. Warn that verify.py's i18n step can take over 5 minutes and hang with parallel runs; run steps individually.
