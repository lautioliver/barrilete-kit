---
skill: implement-issue
issue: 122
pr: 131
area: infra
rutas: scripts/install.py, scripts/update.py, scripts/grow.py, scripts/agents/check-docs.py, scripts/test-install.sh, CHANGELOG.md, README.md
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
fecha: 2026-10-15
modelo: sonnet
rol: implementer
agente_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** ninguno en esta ronda (tests en rojo con red.sh y commit antes de corregir).
**Decisiones no cubiertas:** para el alcance de docs/ en check-docs usé la marca `installed: true` en `.agent-kit.json` en vez de sacar docs/ siempre, para no cambiar los proyectos creados con la plantilla. Un symlink va a pending sin escribir.
**Lo que encontró la revisión:** dos bloqueantes que mi /code-review no vio: LICENSE trasladado por update.py y escritura a través de un symlink. Ambos son de "qué pasa en el update siguiente" y "qué pasa con archivos que no son regulares": mi test solo recorría la instalación.
**Propuesta:** en la autorevisión de scripts que instalan/actualizan, probar siempre la segunda corrida (update) con repos sin los archivos que se saltean, y con symlinks.
