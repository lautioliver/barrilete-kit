---
skill: implement-issue
issue: 233
pr: 278
area: infra
paths: scripts/update.py, scripts/test-update.sh, CHANGELOG.md
skill_sha: da5949abe3ed0fed29aa083488f521ab3d37d48e
date: 2026-11-07
model: haiku
role: implementer-light
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** (1) My first two commits had no `Co-Authored-By` trailer; I rebuilt them before pushing, which changed the red sha, so I re-ran the red at the new red commit (b30b5dc). The final block carries that sha. (2) I first ran `red.sh bash` with HEAD on the fix commit: it was rejected (no executed case), as it should be, because red.sh validates HEAD. I re-ran it with the red commit checked out and returned to the branch. (3) `/code-review` was not run: the orchestrator forbids invoking it (it moves its checkout), so I did a bug pass by hand and wrote `no code-review` in self-review. (4) verify.py ran for several minutes; lint, typecheck and tests are not configured, so they are not verified, and the PR says so.

**Decisions not covered:** (a) ADR-002 D8 says the next 1.x also prints the update.py warning. #226 is still unreleased (the CHANGELOG section is `[Sin publicar]` and VERSION is 1.1.0), so this PR replaces the 1.x text in update.py with the 2.0.0 error instead of keeping both. I left it for the reviewer in the PR, not as a question, because the issue asks for the 2.0.0 text. (b) The issue says "the same text as red.sh", so update.py prints the exact text with no `warning:` prefix, on stderr, exit 0. (c) I amended the CHANGELOG bullets of #226 and #227 to match the code.

**What the review found:** nothing from `/code-review` (not run). Bug pass by hand: nothing blocking. A `tap` entry with no `name` prints `red stack 'None'`, as the old warning did; that is pre-existing and out of scope.

**Proposal:** the issue said "Blocked by #226: el aviso de 1.x tiene que haber salido". That assumed the 1.x warning had shipped, but it is only in the unreleased section. When an issue says "blocked by" an unreleased change, the implementer should check the release state and say so in the issue, not assume it.
