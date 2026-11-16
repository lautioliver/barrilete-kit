---
skill: implement-issue
issue: 290
pr: 327
area: infra
paths: scripts/init-template.sh, scripts/update.py, scripts/agents/test-sync-rules.sh, scripts/test-init.sh, scripts/test-update.sh, scripts/test-install.sh, docs/decisions/kit/ADR-006-rules-store-for-agents.md
date: 2026-11-16
skill_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
model: opus
role: session
---
**Deviations:** el handoff decía "traer main con merge" y después correr `red.sh`, pero `red.sh` compara el commit rojo con su primer parent: con el merge, el rojo quedaba debajo del arreglo de #316 y un caso viejo roto lo invalidaba. Con el OK de Lautaro hice rebase local (la rama no estaba pusheada). Después junté los casos del code-review en el mismo rojo, porque un segundo rojo fallaba también en un caso del primero y `red.sh` lo rechazaba. Mis dos primeras redacciones del ADR rompieron `test-init.sh`: nombré `install.py` y la ruta `docs/agents/classes.yml`, que no existe en el modo chico.
**Decisions not covered:** agregué la variable de entorno `AGENT_KIT_NO_RULES_SYNC` para que el init no toque la red adentro de update.py ni de las suites. `install.py` no cambió porque ya manda a pending todo archivo que el repo tiene.
**What the review found:** 10 hallazgos. Los importantes: un agente nuevo del kit llegaba con el sha del kit; el init clonaba el repo de reglas en cada test y en cada update; un caso nuevo no podía fallar porque el error de sync-rules ya contenía la palabra buscada. Arreglados con un rojo nuevo y mutaciones.
**Proposal:** que implement-issue diga qué hacer con un rojo local cuando hay que traer main: rebase si no está pusheado, porque con merge `red.sh` no puede validar. Y que avise que los ADR de docs/decisions/kit viajan al proyecto, así que pasan por test-init (caso 21 y check-docs del modo chico).
