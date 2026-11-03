---
skill: implement-issue
issue: 224
pr: 238
area: agents
paths: scripts/agents/git-quiet.sh, scripts/agents/test-git-quiet.sh, scripts/test-update.sh
date: 2026-11-03
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** Corrí `git checkout a93c574` en el worktree de la rama mientras corría una tanda de suites en segundo plano: la tanda quedó con resultados dudosos y la repetí entera (tiempo perdido). Para correr `red.sh` sobre un commit viejo usé después un worktree aparte. No hice force push; el rojo viejo no se tocó. El caso nuevo de `GIT_CONFIG_COUNT` tuvo su propio rojo (`8041bfd`); el check de `test-update.sh` no tiene rojo porque ya pasaba.
**Decisions not covered:** (1) Un helper que devuelve 1 a propósito choca con el ERR trap de `tap.sh` (que hereda el subshell): el test del verde necesitó `trap - ERR` dentro del `$( )`, y el rojo no podía llevarlo (forma prohibida), así que el cuerpo del test cambió entre rojo y verde con los mismos ids. El skill no dice cómo testear una función que aborta. (2) Cuántos bloques de rojo poner en el PR cuando hay un segundo ciclo de rojo por una review: dejé el de `a93c574` como bloque y describí el segundo en texto.
**What the review found:** Bloque del rojo de otro PR (#216) pegado en el cuerpo; helper que pisaba `GIT_CONFIG_COUNT` no numérico; `test-update.sh` sin check; comentario desactualizado.
**Proposal:** En implement-issue, aclarar que un rojo de una función que devuelve 1 debe probarse sin `return` status (por salida/valor) y que el verde puede agregar `trap - ERR` en el subshell; y avisar de no cambiar de commit en el worktree con tests corriendo (usar `git worktree add --detach` para `red.sh` sobre un sha viejo).
