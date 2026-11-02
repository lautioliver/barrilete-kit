---
skill: implement-issue
issue: 190
pr: 213
area: infra
paths: scripts/test-install.sh
date: 2026-11-02
skill_sha: 8eb190f6fbdaffc85968a0f40a02303ed62b3512
model: haiku
role: session
---
**Deviations:** ninguna de fondo. El `<BASE_BRANCH>` no estaba configurado: prepare.sh usó `main` con aviso. `verify.py` tarda más de 120 s y lo pasé a segundo plano; corrí dos veces (una por error de espera) sin consecuencias.

**Decisions not covered:** (1) no hacer un helper compartido de la config de gc: tres líneas repetidas en dos scripts; (2) no ampliar a `test-init.sh`, `test-prepare.sh`, `test-orchestrate.sh` y `test-retros.sh`, que también clonan repos locales: lo dejé anotado en el PR como pregunta; (3) el check del red verifica la configuración del entorno, no el comportamiento de un gc real (no hay forma barata de hacerlo rojo).

**What the review found:** `/code-review` (low): el `export GIT_CONFIG_COUNT` pisa un `GIT_CONFIG_COUNT` que ya traiga el entorno. No corregido: es el mismo patrón que `test-update.sh`, decisión para la persona.

**Proposal:** el red de un test de configuración de entorno es fácil de escribir mal: `git config --get` sale con 1 cuando no está seteado y `tap.sh` lo toma como crash. Usar `git config --list` + `grep -qxF` (ya lo hice). Vale una línea en la guía de red para bash.
