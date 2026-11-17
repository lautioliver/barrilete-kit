---
skill: implement-issue
issue: 334
pr: 336
area: infra
paths: .claude/skills/project-status/status.sh, .claude/skills/project-status/test-status.sh, docs/agents-map.json, CHANGELOG.md
date: 2026-11-17
skill_sha: 3e8ba9fcda14f96510c76f987f4cb3e9d6cbb456
model: opus
role: session
---
**Deviations:** El checkout principal estaba en la rama de otra sesión (#324), así que trabajé en un worktree con `prepare.sh --worktree`. El `git pull` que corrí antes de verlo falló sin tocar nada. Para el SC2164 del `cd` del setup usé `# shellcheck disable` con el motivo: un `cd … || exit` es una forma prohibida en el rojo.
**Decisions not covered:** Sumé una entrada `project-status` en `verify` de `docs/agents-map.json` (no es ruta sensible), para que un cambio en `agents_map.py` corra el test de `status.sh`. No existía ningún test de `project-status`: este es el primero.
**What the review found:** `/code-review` encontró que el primer verde escondía las fallas. Un `python3` que fallaba (sin `agents_map.py` o con el mapa roto) se leía como "no hay migraciones" y dejaba un traceback por PR. Un `gh pr diff` que fallaba también se contaba como "sin migraciones". Y corría un `python3` por PR. Hizo falta un segundo par rojo/verde. Faltaban también la entrada del CHANGELOG y la de `verify`.
**Proposal:** `project-status` podría tener un caso para cada sección que lee de GitHub, con el mismo `gh` falso: hoy solo Migrations tiene test.
