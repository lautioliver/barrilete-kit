---
skill: implement-issue
issue: 113
pr: 130
area: infra
rutas: scripts/init-template.sh, scripts/agents/check-docs.py, scripts/agents/agents_map.py, scripts/update.py, scripts/grow.py, scripts/test-init.sh, scripts/test-update.sh, scripts/agents/test-i18n.sh, .github/workflows/docs.yml, docs/agents-map.json
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
fecha: 2026-10-15
modelo: sonnet
rol: implementer
agente_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** red.sh solo corrió test-init.sh; los rojos de test-i18n.sh y de test-update.sh se vieron corriendo el script a mano contra el código sin cambios (red.sh acepta un solo comando). Los tests de update los escribí después del código y tuve que revertir el cambio a mano para ver el rojo.
**Decisiones no cubiertas:** el repo no tiene ningún .es.md, así que exigir hermanos de entrada rompía el CI: el check de paridad se activa con el primer X.es.md. profiles/ está en ignore_check pero necesita paridad: agregué la clave parity_ignore al mapa. El comentario del issue pedía "Documentación" en la salida de check-docs, que ya está en inglés: exigí "^Docs ".
**Lo que encontró la revisión:** /code-review, la primera vez, revisó el checkout principal y no el worktree (diff vacío): hay que pasarle el diff explícito con `git -C`. Hallazgos reales: el DELETE del perfil chico no se llevaba el hermano .es.md (volvía con --lang es), cercos ~~~ y de 4 backticks mal contados, detección de --lang por grep demasiado laxa. Descarté tres (huérfanos, modo chico sin mapa, aviso de X.es.md nuevo).
**Propuesta:** en implement-issue, decir cómo correr /code-review desde un subagente con worktree (pasar el diff). Un red.sh que acepte varios comandos.
