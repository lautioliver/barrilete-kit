---
skill: implement-issue
issue: 219
pr: 304
area: infra
paths: scripts/update.py, scripts/install.py, scripts/grow.py, scripts/test-update.sh, scripts/test-install.sh, README.md, CHANGELOG.md
date: 2026-11-09
skill_sha: 7efef22daf2a854a44d247ed515623cdc106037d
model: sonnet
role: implementer
agent_sha: bbfec5a28a711b2fac66560de0ad5b5777dca4d7
---
**Deviations:** none from the skill. Two red commits (the second one for the /code-review findings), so the PR carries two red blocks. The launch prompt gave no agent_sha/skill_sha, so they are left out for retro.sh to fill.
**Decisions not covered:** (1) A glossary of the repo in another path: the kit's goes to pending (withheld) instead of being installed next to it; the issue only says "avisa y no lo pisa". (2) grow.py: an untouched small glossary/contexts is deleted and the full template takes its place; only a project-edited one is moved (the formats differ, a moved template would be a worse file). (3) Link warnings in update.py also for installed repos, even though check-docs.py skips them there. (4) The issue says check-docs.py "va a fallar" without the link, but since #217 it only warns in projects; I wrote it in the PR.
**What the review found:** /code-review gave 9 findings; 4 were real behaviors (legend table before the contexts table, folder with trailing slash that does not exist yet, stale table fed to the map when the file is not moved, vendored glossaries counted as the repo's), fixed with a second red commit; the rest were style or deliberate (same copy-in-three-scripts convention). verify.py also caught SC2016 in my new test cases, which I missed because I ran only the test files.
**Proposal:** step 7 says to run verify.py last; with test-update.sh taking ~4 minutes, run shellcheck on the touched test files right after writing them. Also worth noting in the skill that red.sh takes minutes for the kit's own test-*.sh and runs in a copy, so editing the worktree meanwhile is safe.
