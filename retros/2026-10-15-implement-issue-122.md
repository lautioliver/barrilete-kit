---
skill: implement-issue
issue: 122
pr: 131
area: infra
paths: scripts/install.py, scripts/update.py, scripts/grow.py, scripts/agents/check-docs.py, scripts/test-install.sh, CHANGELOG.md
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
date: 2026-10-15
model: sonnet
role: implementer
agent_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** ninguno; tests en rojo con red.sh antes de corregir. Rebase sobre #129 sin conflictos y sobre #130 con dos triviales.
**Decisiones no cubiertas:** `withheld` registra todo lo que va a pending (update/grow solo lo saltan si el proyecto no tiene el archivo); `ref` pasa a ser la fuente de verdad (base de fusión y freno anti-downgrade) y `version` queda null si el destino es HEAD; en repos instalados se omite todo el índice de ADRs.
**Lo que encontró la revisión:** que lo que el instalador decide no instalar vuelve por update/grow, y que version null deja a update sin freno contra tags viejos. Mi autorevisión no probó la segunda corrida con plantillas con tag viejo.
**Propuesta:** en scripts instalador/actualizador, un test de ciclo completo (instalar, actualizar, crecer) debería ser parte del primer rojo.
