---
skill: implement-issue
issue: 220
pr: 301
area: docs
paths: .claude/skills/review-pr/SKILL.md, .claude/skills/review-pr/SKILL.es.md, .claude/agents/reviewer.md, .claude/i18n/agents/reviewer.es.md
skill_sha: e610f5b
date: 2026-11-09
model: haiku
role: implementer-light
agent_sha: a98b342
---
**Deviations:** sin tests ejecutables (cambio de texto): `no tests:` con motivo, en vez de rojo. No se pidió `/code-review` con permiso explícito, pero se corrió (`code-review` skill sobre `origin/main...<rama>`). Los `agent_sha`/`skill_sha` no me los dio el orquestador: son los blobs de `origin/main` (implementer-light.md, implement-issue/SKILL.md), no necesariamente los que se ejecutaron. `retro_sh` tampoco llegó: usé el `retro.sh` del checkout principal (en `main`).
**Decisions not covered:** una dependencia entre contextos aprobada por ADR pero no declarada en `depends_on` no tiene regla en la fila: queda sin marcar y el mapa puede quedar desactualizado. Lo dejo como pregunta para la persona, no lo decidí.
**What the review found:** `/code-review` encontró 4 hallazgos en la fila: no hay método para detectar una dependencia nueva (se aclaró: comparar con `depends_on`), la falta de regla para `depends_on` tras un ADR (queda para la persona), la cita de ADR-003 para "no bloqueante" (se corrigió a D6, D7) y el caso de `contexts` vacío (se agregó, AGENTS.md). `verify.py`: lint, typecheck y tests sin configurar en el mapa de la plantilla.
**Proposal:** el issue dice "una fila" y describe dos reglas; conviene partirlas en dos filas al escribirlas, o dejarlo así. Y el mapa de la plantilla no tiene comandos de lint, typecheck ni tests.
