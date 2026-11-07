---
skill: implement-issue
issue: 287
pr: 294
area: infra
paths: scripts/agents/verify.py, scripts/agents/checks/pr-metadata, scripts/agents/sync-rules, scripts/agents/test-checks.sh, docs/agents-map.json
date: 2026-11-07
skill_sha: 7efef22daf2a854a44d247ed515623cdc106037d
model: sonnet
role: session
---
**Deviations:** none de fondo. Las reglas de la red (sin `tap_run` esperando 1 o 2) obligaron a envolver `verify.py` en un `rc.py` que imprime `rc=<n>`; lo dejé dicho en el test.
**Decisions not covered:** (a) qué hace `pr-metadata` si `gh` falla: elegí salir con 4 (no verificó) y que `verify.py` no diga "All verified"; lo dejé como pregunta en el PR. (b) el manifiesto `.barrilete/checks.json` como archivo generado. Las preguntas de diseño (manifiesto, regla, alcance) se hicieron antes de escribir código.
**What the review found:** `/code-review` encontró 6 cosas reales: regex de commits que leía un sha de solo dígitos, bloque rojo sin cerrar, `ok` y "All verified" sin haber leído el PR, ids de check repetidos, `--pr` y el exit de un error de `gh`. Mis mutaciones a mano las habían dejado pasar porque dos chequeos se tapaban entre sí al nombrar el mismo valor.
**Proposal:** al probar mutaciones, cada caso tiene que depender de una sola cosa: si dos chequeos nombran el mismo valor en su mensaje, el test pasa aunque se borre uno. Conviene decirlo en la regla de "rojo que falla si se borra lo chequeado". Y un check que puede no verificar necesita un estado propio (ni ok ni falla).
