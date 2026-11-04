---
skill: implement-issue
issue: 243
pr: 247
area: infra
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: haiku
role: session
---
**Deviations:**
- Un comando de limpieza mío borró el worktree de trabajo `barrilete-kit-wt/243`: calculé la ruta del worktree temporal con un `grep` que no encontró nada, la ruta quedó vacía y `git worktree remove --force .` se ejecutó sobre el worktree de trabajo. No se perdió ningún commit (estaba todo commiteado y en origin); el worktree se recreó desde el branch. Regla que incumplí: no ejecutar `worktree remove` con una ruta que no verifiqué.
- El commit rojo `4daac60` tenía un cambio ajeno al test (espacios en `const T`); lo corregí en un commit posterior, con la fórmula de que el commit rojo contenga solo tests.
- Un fake de `paginate` dejó el test de performance en rojo por una variable que el proceso hijo no veía (`COMMITS`); lo corregí inline antes de commitear.
- Cumplí la regla de parar antes de empujar el workflow (ruta `infra`); la aprobación llegó en el chat después y se cita en el PR.

**Decisions not covered:**
- Cómo tratar una línea `red commit:` no hex en un `<details>` extra: la implementé como error (antes se descartaba en silencio); la regla no estaba en el issue.
- El chequeo exige que el sha sea *un* commit del PR, no el que agrega los tests. El issue pedía lo primero; lo segundo queda como pregunta.
- `pulls/{n}/commits` devuelve 250 commits como máximo: un red commit más viejo daría falso positivo. No lo resolví; queda anotado en el PR.

**What the review found:**
- `/code-review` (7 hallazgos): aplicado el de línea no hex (con test de reproducción en commit propio); aplicado el de espacios en el test. Dejados como pregunta: el chequeo es más laxo que "el commit que agrega los tests", el límite de 250 commits, un segundo parser de `red commit:` que duplica `leerBloqueRojo`, y la aprobación de CI (que se resolvió en el chat).
- `/security-review` no corrí como skill; hice revisión manual del diff del job `labels` (`pull_request_target`): las únicas entradas del cuerpo son líneas `red commit:` que pasan un filtro hex, y el mensaje solo incluye ese hex. Sin permisos nuevos (`pull-requests: read` cubre `listCommits`).

**Proposal:**
- Antes de borrar o recrear un worktree, verificar que la ruta no esté vacía y que el `git worktree list` la muestre como esperado; no usar `--force` con rutas calculadas.
- En `implement-issue`, decir explícitamente que un commit rojo no debe incluir cambios de formato ajenos al test (el espacio en `const T` salió de un edit).
