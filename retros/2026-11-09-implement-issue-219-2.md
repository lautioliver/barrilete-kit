---
skill: implement-issue
issue: 219
pr: no PR
area: infra
paths: scripts/update.py, scripts/install.py, scripts/grow.py, scripts/test-update.sh, scripts/test-install.sh, CHANGELOG.md
skill_sha: 7efef22daf2a854a44d247ed515623cdc106037d
date: 2026-11-09
model: haiku
role: implementer-light
agent_sha: 96fd308065f1c623c92b2fbaabed40bd746e4180
---
**Deviations:** escalated before any change, so no red tests were written and red.sh, verify.py and /code-review were not run. The worktree is clean (nothing committed).

**Decisions not covered:** the issue (area:infra, type:task) asks to change update.py, install.py and grow.py so that existing projects receive docs/reference/glossary.md and contexts.md (or docs/glossary.md and docs/contexts.md in --small), and the map's contexts section. These scripts are the distribution contract that already installed projects run (curl from raw, update, grow). The map does not flag them as sensitive and no business rule is touched, but AGENTS.md "Must ask first" lists public contracts consumed by third parties and infrastructure. Escalated under rule 3 instead of deciding it. Also noted: the issue's --small target (profiles/small/docs/glossary.md) exists, but grow.py has no test file of its own (no test-grow.sh), so "casos en el grow" have to go in test-update.sh.

**What the review found:** not reached.

**Proposal:** for issues whose scripts are the installer/updater, mark them in the map or in labels so light implementers escalate before reading ~1400 lines of script. The issue body mentions "Blocked by #216, #217", both closed; the check of blockers passed.
