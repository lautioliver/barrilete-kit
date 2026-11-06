---
skill: implement-issue
issue: 227
pr: 272
area: infra
paths: scripts/agents/red_report.py, scripts/agents/check-docs.py, .claude/skills/implement-issue/test-red.sh, .claude/skills/implement-issue/corpus, scripts/agents/test-agents.sh, docs/guides/red-per-runner.md
date: 2026-11-06
skill_sha: 6f844a45812360e09f983b50d163261b1ab85d24
model: opus
role: session
---
**Deviations:** verify.py ran in the background while I committed fixes on the same worktree, so its first result mixed two HEADs (an i18n failure that was already fixed); I had to run it again (~30 min). The PR opened with verify.py's shellcheck red: verify.py passes the deleted .sh to shellcheck (archivos_cambiados includes deletions); CI does not, and shellcheck over the existing changed files exits 0. Stated in the PR, not fixed (out of scope).
**Decisions not covered:** the issue said 28 TAP cases; there were 43 with format=tap (15 crash/legit/timeout used TAP only as their format). I decided which to delete (16, pure TAP parser) and which to convert (12 bash-helper rules as bash-*, 15 to junit). Asked the person: tap.sh TAP_FORMAT=tap goes to a separate issue; ADR-002 untouched. Converting old corpus fixtures exposed that they used `false; tap_check`, a crash since #165: the TAP replays had hidden it.
**What the review found:** /code-review: check-docs repeated the stack name, so it did not print red.sh's literal (the test grepped a substring); red.sh reported a bad name before the tap removal; dead parameter in defines(). Also out-of-scope items already in other issues (update.py warning #233, labels.yml #228, tap.sh TAP mode).
**Proposal:** verify.py should pass {files} with --diff-filter=AMR (deleted files cannot be checked). implement-issue could say: do not commit while verify.py is running on the same worktree.
