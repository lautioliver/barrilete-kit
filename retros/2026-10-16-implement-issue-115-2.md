---
skill: implement-issue
issue: 115
pr: 140
area: docs
paths: .github/, scripts/init-template.sh, scripts/agents/check-docs.py, profiles/small/
skill_sha: 9239a3bd21f59a8cafe3dab91a72edd2074c910d
date: 2026-10-16
model: sonnet
role: implementer
agent_sha: 3a7e8277a739835896f3f5e0c8aab2d856cb398a
---
**Deviations:** split into two stacked PRs (#140 CI and templates, #141 small profile, R-6, checks) as the orchestrator allowed. Two PRs for the same issue, so one retro covers both. #141 uses the old Spanish red-block title because pull_request_target runs main's labels workflow until #140 merges.
**Decisions not covered:** the issue says the issue forms' sibling is `1-bug.es.yml` next to the file; GitHub offers every .yml in ISSUE_TEMPLATE as a form, so I put the Spanish ones in `.github/i18n/ISSUE_TEMPLATE/` (same pattern as the agents) and amended ADR-001 R-1 with approval marked as pending. Needs a person's yes. English alias for "sin test" requires a colon (`no tests: <reason>`), otherwise any "no test coverage" phrase would pass the check.
**What the review found:** /code-review runs in the session cwd, not in the worktree: the first run reviewed an empty diff; passing branch refs and the worktree path worked. Real findings: a stale Spanish literal in an English skill, labels.es.yml not compared with labels.yml. CI found test-renames.sh, which verify.py does not run unless that file changes.
**Proposal:** implement-issue / the orchestrator should tell subagents to pass explicit refs to /code-review (origin/<base>...<branch>) since it forks in the main checkout. verify.py's map could run test-renames.sh when labels or .github files change.
