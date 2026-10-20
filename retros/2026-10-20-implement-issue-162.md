---
skill: implement-issue
issue: 162
pr: 186
area: infra
paths: scripts/test-update.sh
skill_sha: 72dbfebc4af4d40e32cb6d5fa423bd1484b5561a
date: 2026-10-20
model: sonnet
role: implementer
agent_sha: da74fb6d0df623d9015f3d067b2b5c5fe6d9f0b4
---
**Deviations:** no /code-review (forbidden under /orchestrate), bug pass by hand. The PR says Refs, not Closes: the flaky failure was never reproduced (8 parallel full runs plus 150 chico preps on macOS, 0 failures), so the root cause is unproven.
**Decisions not covered:** how to red-test a change to a test file's own setup. I put the helper stub (prep) and two cases inside test-update.sh itself. The first red was rejected because the stub did not create the log, so grep on a missing file exited 2 (a crash): a stub has to leave every file the assertions read, so they fail with status 1. The full test takes minutes under load (red.sh and verify took 4+ min each), and the guide does not say a flaky-cause issue can end with only the visibility half done.
**What the review found:** nothing (no code-review run).
**Proposal:** in step 3, note that a stub must create the files and outputs the assertions read, since a missing file is a crash and not a red. For flaky issues, say what to do when the cause cannot be reproduced.
