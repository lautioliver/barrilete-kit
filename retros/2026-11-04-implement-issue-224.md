---
skill: implement-issue
issue: 224
pr: 238
area: agents
paths: scripts/agents/git-quiet.sh, scripts/agents/test-git-quiet.sh, scripts/test-install.sh, scripts/test-update.sh
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** none en el flujo. El arreglo de la limpieza de GIT_CONFIG_* en install/update no tiene rojo propio (aislamiento del test, decisión de la persona); lo probé a mano con el entorno contaminado. Un script mío vació `git-quiet.sh` (sed sobre un backup inexistente); lo vi en el diff y lo restauré desde git antes de commitear. Un `pkill` por patrón fue denegado; no lo repetí.
**Decisions not covered:** el skill no dice cómo declarar un segundo rojo (hubo dos más: `8041bfd`, `7bfdca5`) fuera del bloque estructurado; lo dejé en el texto del cuerpo y lo dejé como pregunta en el PR. Además `tap_status` solo corta con un crash: un status distinto de 0/esperado no falla el caso, hace falta un `tap_check` aparte para exigir el status.
**What the review found:** el `trap - ERR` + `; true` del verde escondía crashes del helper en la rama de abortar (comprobado por mutación antes y después del `echo`); octal con ceros adelante en `GIT_CONFIG_COUNT`; `git config --list` sin `-C` leía el cwd.
**Proposal:** documentar en `tap.sh` que `tap_status` no exige el status, y en implement-issue cómo declarar rojos adicionales. Probar mutaciones sobre helpers con caminos de error.
