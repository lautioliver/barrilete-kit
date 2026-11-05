---
skill: implement-issue
issue: 225
pr: 255
area: agents
paths: scripts/agents/red_report.py, scripts/agents/tap.sh, .claude/skills/implement-issue/test-red.sh, scripts/agents/test-tap.sh, docs/agents-map.json
date: 2026-11-05
skill_sha: 1414944818cddbe457cf7d97704c620c85480536
model: sonnet
role: session
---
**Deviations:** red commit rewritten (authorized by the person in a PR comment) and pushed with --force-with-lease on this branch only. I also edited the ADR-002 D6 line about `--diff-filter=AM` (en and es) to say AMR: a literal sync of what the run does, flagged in the PR body. The sleep+cat wait was blocked and a `pgrep -f` monitor matched its own command line and never ended; I stopped them and reran verify to a file.
**Decisions not covered:** how to rebuild a red commit without `rebase -i` (reset to the parent, checkout the test files from the old commit, edit, commit, then bring the rest from a backup branch in separate commits). Cases in a loop must keep a literal id (a test checks it): what varies goes in the description argument.
**What the review found:** the missing `# file:` check for `tap` entries, forbidden forms in the red (`&&` after grep, `! grep`, `except Exception` in the Python helper), no test ran the shipped `run`. `/code-review` round 2 only repeated known points (accepted by ADR-002: over-rejecting test files, TAP_OUT/TAP_FORMAT for every entry, `run` wrap at the end).
**Proposal:** the skill could mention a recipe to rewrite a red commit with no interactive rebase, and say that `pgrep -f` in a monitor matches its own shell.
