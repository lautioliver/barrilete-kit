---
skill: implement-issue
issue: 116
pr: 137
area: infra
paths: scripts/update.py, scripts/grow.py, scripts/test-update.sh, CHANGELOG.md, README.md
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
date: 2026-10-15
model: sonnet
role: implementer
agent_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** el limite de sesion corto el trabajo con los tests escritos pero sin commitear; retome desde git status. `/code-review origin/main...HEAD` corrio en el checkout principal (cwd distinto al worktree) y devolvio vacio: hubo que pasarle un archivo de diff.
**Decisiones no cubiertas:** como probar contra un tag 0.9.0 sin depender de tags del repo en CI (fixture sintetico desde la tabla de test-renames.sh mas un init minimo, y una prueba aparte con el tag real); donde se baja update.py en un proyecto 0.9 (fuera del repo, por el chequeo de working tree limpio).
**Lo que encontró la revisión:** registro no actualizado cuando un movimiento queda bloqueado (el archivo se borraba), claves a medias, falta de fecha, nombres de personas traducidos en team.json, carpetas viejas con archivos propios, mensaje de grow.py sin el procedimiento.
**Propuesta:** que la skill diga que /code-review en un subagente necesita el worktree como cwd o un diff en archivo; el guardrail de tags frena hasta una prueba manual con tags en un script scratch.
