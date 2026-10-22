---
skill: implement-issue
issue: 181
pr: 196
area: docs
paths: scripts/agents/flow.py, scripts/init-template.sh, scripts/install.py, scripts/update.py, scripts/grow.py, scripts/test-init.sh, scripts/test-install.sh, scripts/test-update.sh
skill_sha: aa963263a1d5d108581d55612357817f2a207dca
date: 2026-10-22
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** no /code-review (forbidden by the launcher; the implementation was already reviewed twice by Opus on #183). The green commit is a `git checkout 39ec598 -- .`, not an incremental TDD cycle. The red commit's tests are not the verbatim ones of the old branch: they had to be rewritten for red.
**Decisions not covered:** a python assertion in a bash test (`python3 - <<PY assert ...`) bails out under tap.sh instead of failing a case, so in the red it has to catch AssertionError and print ok/bad, then `[ "$r" = ok ]`. The same for `tap_status`/`|| c=$?` (forbidden): use `cd "$D"; tap_run s 0 python3 ...; cd "$TMP"`. A stub of init-template.sh that accepts the flag was needed so the init case fails on an assertion and not on a crash. test_flow.py is not seen by the bash-only red.sh.
**What the review found:** no code-review run here.
**Proposal:** add to implement-issue step 3 (or docs/guides/red-per-runner.md) the recipe for python assertions and for running a program in another cwd with tap_run in a bash red.
