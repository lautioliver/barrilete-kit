---
skill: implement-issue
issue: 324
pr: 338
area: infra
paths: scripts/agents/learning.py, scripts/agents/verify.py, scripts/agents/task_events.py, scripts/init-template.sh, scripts/update.py, scripts/test-init.sh, docs/agents/learning-event.md, docs/decisions/kit/ADR-007-per-project-learning.md
date: 2026-11-17
skill_sha: 27a1947ee312dc9fbbcf418c7af4aa075868ae73
model: opus
role: session
---
**Deviations:** la mutación de init se cortó y su salida se perdió en un handoff; se rehízo en esta sesión. Los bloques de red.sh también se perdieron y se regeneraron en worktrees detached (61 y 3 casos, iguales a los registrados).
**Decisions not covered:** los nombres de las variables de entorno los fijó la persona en el issue (`BK_MODEL`, `BK_PROVIDER`), pero `bk` exporta `BARRILETE_MODEL` y `BARRILETE_PROVIDER`. El review lo marcó como bug; se dejó como pregunta en el PR y no se cambió, porque contradice una decisión de la persona. Tampoco se decidió qué hacer con las líneas v0 de #323 en los stores existentes.
**What the review found:** `/code-review` encontró que un nombre de carpeta con espacios o ñ (sin origin) invalidaba todos los eventos; que `push` reintentaba cinco veces cualquier rechazo y daba un motivo equivocado; que un `learning.json` inválido en `push` salía con 1 y no con 3; que `verify.py` se caía con un AGENTS.md que no es UTF-8; y un caso vacío en test-checks. La mutación M1/M2 mostró que dos casos 324 de test-init cortaban la suite con `Bail out!` en vez de fallar como casos (corrían `check-ignore` y `emit` fuera de `tap_run`). Todo se arregló con un caso que falla si se revierte el arreglo.
**Proposal:** implement-issue podría pedir que la mutación se corra antes del primer push y que su salida se guarde fuera del scratchpad: dos veces se perdió evidencia entre sesiones. Al fijar nombres de variables que produce otra herramienta (bk), chequearlos contra su código antes de escribir el rojo.
