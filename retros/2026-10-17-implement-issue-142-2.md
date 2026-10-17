---
skill: implement-issue
issue: 142
pr: 144
area: docs
paths: scripts/agents/check-docs.py, scripts/agents/test-i18n.sh, scripts/test-init.sh
skill_sha: 5b87389249c36f6477068eb6850a69d2252a26e1
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 3a7e8277a739835896f3f5e0c8aab2d856cb398a
---
**Deviations:** extra round after the reviewer. CI failed once on test-renames (my test wrote the old `tipo:` label literally): verify.py does not run test-renames, so I only saw it in CI; I should have run scripts/test-*.sh locally.
**Decisions not covered:** how strict the labels parser guard should be: chose a line-by-line whitelist of the supported shape rather than counting items.
**What the review found:** a warning naming the wrong marker, and a comment promising more than the guard detected.
**Proposal:** add test-renames.sh to the verify map so verify.py catches it before CI.
