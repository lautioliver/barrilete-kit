---
skill: implement-issue
issue: 218
pr: 240
area: agents
paths: AGENTS.md, AGENTS.es.md, profiles/small/AGENTS.md, profiles/small/AGENTS.es.md, .claude/skills/implement-issue, .claude/skills/plan-feature
date: 2026-11-04
skill_sha: 09798fd35d4d278d6c4a88b01cc3b7f4b9f9430c
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** correcciones sobre un PR existente: sin red/green (docs, `no tests:` ya justificado en el PR). Corrí `/implement-issue` en modo corrección, no hubo `/code-review` nuevo sobre el delta (solo texto de reglas). El primer intento de correr test-init y test-i18n juntos superó el timeout de 10 min; los volví a correr por separado y enteros.
**Decisions not covered:** en el perfil chico no se instala `docs/decisions/`, así que cité la ruta del ADR del kit con "en el kit"; la skill no dice cómo citar un ADR del kit en un perfil que no lo trae. También: si las referencias bare `ADR-003` de las skills debían cambiar (lo hice, por consistencia con la respuesta 4).
**What the review found:** la regla estaba dentro del bloque TODO/Examples de AGENTS (se perdería al completarlo) y pegada al TODO en el perfil chico; el cuerpo del PR decía "119 líneas" refiriéndose a una skill no tocada. Mi implementación anterior no lo vio.
**Proposal:** que `verify.py` tenga timeout/aviso de duración (i18n tarda ~9 min) y que implement-issue sugiera correr los tests largos en background por separado.
