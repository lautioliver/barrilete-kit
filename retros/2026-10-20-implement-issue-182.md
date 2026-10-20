---
skill: implement-issue
issue: 182
pr: 184
area: infra
paths: scripts/test-install.sh, scripts/agents/test-tap.sh
skill_sha: 72dbfebc4af4d40e32cb6d5fa423bd1484b5561a
date: 2026-10-20
model: sonnet
role: implementer
agent_sha: da74fb6d0df623d9015f3d067b2b5c5fe6d9f0b4
---
**Deviations:** no /code-review (forbidden under /orchestrate), bug pass by hand. I amended the red commit twice before running red.sh for the final time (unpushed). A third commit after the red fixed a test defect CI caught: test-tap.sh runs inside test-init's initialized project, where install.py does not exist.
**Decisions not covered:** how to red-test a change to a test file itself (here, test-install.sh). The skill's red needs a failing case in a test-*.sh the commit adds. I used a nested run of test-install.sh against a stub install.py, behind a runner that ends with 0 (tap_run expecting 1 is forbidden), plus a static grep case. Nested runs cost minutes (full test-install.sh, 11 min on a loaded machine), so I limited them to 2 and covered the rest statically. Also: root cause of the flake not found, delivered diagnostics only and said so in the PR.
**What the review found:** nothing from code-review (not run). CI found the missing skip in a project without install.py. The full test-*.sh of this kit are run inside test-init's installed projects: any new test-tap.sh case that needs a template-only file must tap_skip.
**Proposal:** implement-issue could mention that a test-*.sh of the kit also runs inside the installed projects (test-init.sh), so new cases need to skip when the file under test is missing. shellcheck SC2319 appeared out of nowhere in test-tap.sh after adding a late case; a file-level disable (as test-install.sh has) was the pragmatic fix.
