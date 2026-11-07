---
skill: implement-issue
issue: 274
pr: 279
area: infra
paths: scripts/agents/verify.py, scripts/agents/test-base.sh, CHANGELOG.md
date: 2026-11-07
skill_sha: da5949abe3ed0fed29aa083488f521ab3d37d48e
model: opus
role: session
---
**Deviations:** primero se intentó #273 (handoff), pero otra sesión (ws 4) ya lo estaba implementando en `~/barrilete-kit-wt/273` sin PR ni tarea bk: `prepare.sh` lo "reanudó" igual y no avisó que el worktree tenía procesos vivos. Se dejó y se pasó a #274. El primer rojo se rehizo: dos casos fallaban por el texto del comando que `verify.py` imprime (`--list` y el `$ cmd` del run contienen el marcador), no por lo que chequeaban; se vio al implementar, no al escribir el rojo.
**Decisions not covered:** qué hace una regla con `{files}` que solo tocó borrados (no corre y avisa) y si el filtro es global o por regla (global): las dos se preguntaron a la persona. `--pr` sin filtrar (el checkout local puede no tener los archivos del PR).
**What the review found:** `/code-review`: regla `always` con `{files}` vacío, falso pase con `--pr`, sin aviso de la regla salteada, fixture que arrastraba estado del bloque anterior de `test-base.sh`, un caso redundante, comentario viejo. `verify.py` encontró SC2164 en los `cd` nuevos, que además rompía el caso 139 de `test-tap.sh` (shellcheck sobre el kit instalado).
**Proposal:** `prepare.sh` debería frenar (o avisar) si el worktree que reanuda tiene procesos con cwd ahí o commits locales sin push recientes (relacionado con barrilete-workspace #1). En la guía del rojo: un marcador que se busca en la salida de `verify.py` no puede aparecer literal en el comando, que se imprime.
