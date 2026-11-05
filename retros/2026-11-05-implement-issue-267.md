---
skill: implement-issue
issue: 267
pr: 268
area: infra
paths: scripts/agents/worktree-lock.sh, .claude/skills/implement-issue/prepare.sh, docs/agents/subagent-contract.md, docs/agents-map.json
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: session
---
**Deviations:** (1) El primer rojo tenía un test que buscaba "own worktree" por nombre de archivo (SKILL.md, reviewer.md, contrato): fallaba en un proyecto instalado con --lang es; lo detectó test-i18n.sh en verify.py, no yo antes. Es la misma clase de error que le habían marcado al PR #262. (2) La entrada nueva del mapa listaba un .es.md sin `?`: falló otra vez en i18n. (3) Un caso rojo con helper (mencion_es) fue rechazado por red.sh porque el id literal no estaba en la línea que agrega el commit; lo reescribí con if/else. (4) Cambié el criterio del issue (el candado no se borra al terminar; se ignora si el pid murió, y agregué release).
**Decisions not covered:** cómo identificar al dueño cuando los subagentes comparten el proceso claude (pid + nombre de agente por env); cómo probar en rojo un caso que debe salir 1 (se hizo con salida que siempre es 0 y aserciones sobre el texto).
**What the review found:** /code-review: subagentes del mismo proceso comparten pid, toma no atómica, prepare.sh no fallaba cerrado, doble claim, sin release, fallback de dueño. Se arreglaron con rojo primero salvo el .es del mapa (lo cubría test-i18n).
**Proposal:** que implement-issue diga, en el paso del rojo, que los tests de docs buscan por contenido y se saltean si falta el .es.md (hoy solo está implícito); y correr test-i18n.sh antes de pedir review cuando se tocan docs o tests de docs.
