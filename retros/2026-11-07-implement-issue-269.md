---
skill: implement-issue
issue: 269
pr: 282
area: docs
paths: scripts/agents/check-docs.py, scripts/agents/test-classes.sh, CHANGELOG.md
date: 2026-11-07
skill_sha: da5949abe3ed0fed29aa083488f521ab3d37d48e
model: opus
role: session
---
**Deviations:** el segundo rojo (b9faabe) se intentó primero antes de commitear el arreglo principal y `red.sh` lo rechazó (fallaban también los casos del primer rojo); se reordenó: fix, rojo nuevo, fix. Se commiteó mientras corría un `verify.py` en el mismo worktree (el handoff de ws 4 ya lo advertía); se cortó y se volvió a correr. `n=$(n_errores_nuevos)` hizo que shellcheck 0.11 marcara SC2319 en todo el archivo (25 líneas viejas); se resolvió con una función que deja el valor en una variable.
**Decisions not covered:** punto 6 del issue (sugerencias fuera por elección) y si hacer #269 con la enmienda de ADR-006 en camino: se preguntó a la persona (puntos 1–5, nada del 6). El criterio "pasa en instalaciones --lang en/es" no lo cubre ningún test ni `verify.py` (`test-init.sh` no corre `test-classes.sh`): se verificó a mano con `install.py --template` y un `gh` falso.
**What the review found:** `/code-review` (10): la misma clase de error escrita de otra forma (`- ID:`, comentario, dos espacios, `"yes"` citado) seguía dando 2+ errores o culpando a la skill; guardas nuevas sin caso (`actual[0]`, `legible=False` en OSError); comentario sobre la función equivocada, awk duplicado, `mutar bad-utf8` repetido y CHANGELOG que nombraba un cambio a `classes.yml` inexistente. Arreglé el ejemplo (comillas) y no la clase hasta que el review lo marcó.
**Proposal:** en implement-issue, una línea: "un rojo nuevo después de un fix va después del commit del fix: `red.sh` exige que solo fallen casos del commit". Y que `verify.py` (o el mapa) corra `test-classes.sh` en una instalación `--lang es`, ya que el issue lo pedía como criterio y nada lo chequea.
