---
skill: implement-issue
issue: 191
pr: 195
area: infra
paths: scripts/init-template.sh, scripts/update.py, scripts/test-init.sh, scripts/test-update.sh, scripts/test-install.sh, docs/guides/red-per-runner.md
skill_sha: aa963263a1d5d108581d55612357817f2a207dca
date: 2026-10-21
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** no /code-review (forbidden under /orchestrate), bug pass by hand. Red.sh and verify.py take 10+ minutes: they ran as background jobs past the 600 s limit.
**Decisions not covered:** test-red.sh deleted whole in projects (instead of keeping non-corpus cases); the red verify entry is dropped from full-project maps. update.py now prunes folders left empty after deleting, because the corpus left 842 empty dirs.
**What the review found:** nothing (hand pass). The red had one case (update from 1.0.0) that I wrote assuming file deletion was enough; it failed after the green because of leftover empty directories, which was a real gap.
**Proposal:** the skill could say that red.sh/verify.py on this repo exceed the tool timeout and should be launched in the background from the start.
