---
skill: implement-issue
issue: 154
pr: 174
area: infra
paths: scripts/update.py, scripts/grow.py, scripts/install.py, scripts/test-update.sh, scripts/test-install.sh, CHANGELOG.md, README.md, docs/decisions/kit/ADR-002-structured-red-validation.md
skill_sha: 11a4784c1ce6b94f1cb0fd52550b4c1d8ea13c55
date: 2026-10-19
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** No /code-review: the orchestrator forbade invoking it through the Skill tool, so I reviewed by hand and said so in the PR. I rewrote the red commit twice (wrong test expectations, then a helper name that matched the renames check) and re-proved the red each time at the red commit with a detached checkout, because red.sh validates HEAD. Opened the PR with priority:high copied from the issue and the labels check rejected it (priority is issue-only); fixed with gh pr edit.
**Decisions not covered:** (1) `python3 prog` is not an assertion tool for tap.sh, so a test cannot assert via the exit code of a python one-liner: I print a value and compare it with `[`. The skill says this in general but a worked example for "inspect JSON" would have saved a red-validation cycle (10 min each). (2) Running test-*.sh through red.sh takes about 10 minutes and exceeds the 600 s foreground limit: I ran it in the background and polled with a bounded for-loop. (3) Whether grow should merge a modified small map (chose: project keys win over the full map). (4) For install, kept the kit map in pending and added only `red` to the project's, rather than silently dropping the kit's other sections.
**What the review found:** nothing from an automated review (not run). Own findings: the first red had two cases that failed for the wrong reason (glob pattern and an exact-string compare against an init-generated list); caught because the green run still failed them.
**Proposal:** add to the implement-issue guide a short "JSON assertions in a bash red" example (print a field, compare with `[`), a note that red.sh takes several minutes for the kit's own tests, and say in the PR step that PRs must not carry priority: labels.
