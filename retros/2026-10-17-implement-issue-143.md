---
skill: implement-issue
issue: 143
pr: 146
area: docs
paths: .github/workflows/labels.yml, docs/agents-map.json, scripts/agents/, .claude/skills/, .claude/agents/, docs/
skill_sha: 5b87389249c36f6477068eb6850a69d2252a26e1
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 3a7e8277a739835896f3f5e0c8aab2d856cb398a
---
**Deviations:** split in two PRs (#145 CI, #146 fixes). Worked on a second branch off main in the same worktree for the CI PR. The red block of #146 is a run of six test scripts together, not one command.
**Decisions not covered:** (1) the placeholder rule was applied to `no tests: <reason>` too, not only to `sin tests`, because the issue lists both literals. (2) what `FAIL:` formats red.sh accepts (FAIL - / FAIL: plus FALLA/FALLO). (3) how the reviewer avoids running PR code: kit scripts from the trusted checkout, and the red commit only runs if it just adds tests. (4) `/code-review origin/main...HEAD` from a subagent gives an empty diff (it reviews the session checkout): I had to run it by branch name; the skill now says so.
**What the review found:** #145: test slicing of the job to end of file, missing CRLF/comment cases, substring match in the map check (fixed); `no tests: TODO`-style fillers still pass (left: not approved). #146: retro.sh only dropped `<...>`, review-pr isolation claim was stronger than reality (fixed).
**Proposal:** a helper that runs `/code-review` with the right range; verify.py should run the renames test with the init's removal in mind (it is optional via `?`, but the new `when` globs make it fire in projects).
