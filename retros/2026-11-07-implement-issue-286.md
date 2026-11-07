---
skill: implement-issue
issue: 286
pr: 289
area: infra
paths: scripts/agents/sync-rules, scripts/agents/test-sync-rules.sh, .barrilete/rules.lock, docs/agents-map.json, AGENTS.md, docs/agents/classes.yml
date: 2026-11-07
skill_sha: 9bcbd75445af645960c9ec3d2b48fae01ff067cf
model: sonnet
role: session
---
**Deviations:** none de fondo. La sesión se cortó y se retomó con un handoff; verify.py, test-init.sh y red.sh se corrieron de nuevo en la segunda parte.
**Decisions not covered:** (a) `classes.yml` deja de ser provisional: corregí las frases en AGENTS, docs/README y llms.txt (en y es). (b) `rules.lock` con `project=` opcional porque el kit no tiene `.agent-kit.json`. Las dejé como preguntas en el PR.
**What the review found:** todavía sin review.
**Proposal:** el `nohup`/`setsid` para correr comandos largos falla en macOS (no hay `setsid`; con `nohup bash -c` la tarea se cortó sin dejar `exit=`). Correr directo con `run_in_background` y escribir `exit=` al final funcionó. Conviene decirlo en implement-issue.
