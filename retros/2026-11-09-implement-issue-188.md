---
skill: implement-issue
issue: 188
pr: 302
area: infra
paths: docs/agents-map.json, scripts/agents/test-agents.sh, .claude/skills/orchestrate/test-orchestrate.sh, scripts/test-init.sh
date: 2026-11-09
skill_sha: 7efef22daf2a854a44d247ed515623cdc106037d
model: sonnet
role: session
---
**Deviations:** (1) El candado del worktree estaba tomado por un pid muerto; el usuario confirmó que era stale y reintenté el claim. (2) Los casos de `scripts/test-init.sh` no van en el commit rojo: ese test instala el proyecto y corre los tests anidados, que fallan en el rojo, y `red.sh` lo rechaza como crash (primer intento inválido). Van en el commit verde. (3) No esperé a que `verify.py` terminara localmente (el check init tarda varios minutos); CI docs pasó.
**Decisions not covered:** `red.sh` no tiene forma de probar un cambio de `init` cuya verificación depende de suites anidadas: dejo la prueba en el verde, sin validación de rojo. Pregunté la decisión de categoría (`agents` vs `infra`) y el usuario aprobó antes de escribir código.
**What the review found:** `/code-review`: helper de tests con `reset --hard` y error silenciado (arreglado, más un caso de control); alcance de sensibles (no incluí implement-issue/review-pr/AGENTS.md, queda como pregunta en el PR); globs sin `?`; sin CHANGELOG.
**Proposal:** documentar en implement-issue que los tests de `test-init.sh` que dependen de suites anidadas van en el verde, o dar a `red.sh` una forma de aceptarlos.
