---
skill: implement-issue
issue: 224
pr: 238
area: agents
paths: scripts/test-install.sh, scripts/test-update.sh, scripts/agents/test-git-quiet.sh, .claude/skills/*/test-*.sh
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** sin red propio para la tercera review: los cuatro puntos son cambios solo de tests (git -C, unset de GIT_CONFIG_PARAMETERS, c=0 sobrante) y un número en el cuerpo; lo dije en el PR. No hubo que reescribir el commit rojo, sin force push.
**Decisions not covered:** GIT_CONFIG_PARAMETERS lo traté como parte de la decisión de la persona sobre GIT_CONFIG_* (así lo pidió el pedido); no lo extendí a los otros cuatro tests.
**What the review found:** cuerpo con 12/12 viejo tras sumar un caso; limpieza incompleta del entorno heredado; checks de config leyendo el .git/config del cwd.
**Proposal:** `verify.py` y las seis suites tardan varios minutos; correrlas una sola vez por pasada (con y sin la variable) duplicó el tiempo. Una regla "recontá los casos antes de escribir N/N en el cuerpo" evitaría el 12/12 viejo.
