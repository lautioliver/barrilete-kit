---
skill: implement-issue
issue: 288
pr: 312
area: infra
paths: scripts/agents/sync-rules, scripts/agents/test-sync-rules.sh, .github/workflows/docs.yml, docs/agents/lessons.md, AGENTS.md, ADR-006
date: 2026-11-10
skill_sha: c1a6db9a7189f6eb8e02ec415f31c31a3971d933
model: sonnet
role: session
---
**Deviations:** (1) I did not run verify.py after the last test fix, but ran test-init.sh by hand instead. (2) The first push was rejected: the agent's GitHub App token has no `workflows` permission, so a person pushed it. (3) I ran a mutation check with `git checkout <file>` and reverted my own uncommitted edit of docs/llms.txt; I noticed and redid it.
**Decisions not covered:** the format of the check line ("validated by `verify.py`: <check>" after the id); what to do with update.py's lecciones.md rename and the renames table in test-renames.sh once the template stops shipping the file; the new step 6 of improve-skills (proposes a rule in barrilete-rules).
**What the review found:** /code-review: the CI test grepped comments of docs.yml (fixed with a mutation check); the rest were design remarks, explained in the PR. CI found what I did not: test-init runs test-sync-rules.sh inside a freshly initialised project, where the template-only cases (docs.yml step, lessons.md absence) fail. I only ran verify.py, which does not include test-init.
**Proposal:** verify.py (or the skill) should run test-init.sh when a test under scripts/agents/ changes, or the skill should say that tests of the kit run also inside an init'd project and need a template guard. Also: say in the skill that a push touching .github/workflows needs a person when the token is a GitHub App.
