---
skill: implement-issue
issue: 128
pr: 129
area: infra
paths: .claude/skills/improve-skills, .claude/skills/orchestrate, .claude/agents, docs/agents/subagent-contract.md, docs/decisions/ADR-001-language-labels-and-names-in-english.md
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
date: 2026-10-15
model: sonnet
role: implementer
agent_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** `/code-review` corrió dos veces: la primera en el checkout del orquestador (cwd del fork), sin diff; hubo que pasarle la rama como argumento. El test rojo quedó sobre todo en retro.sh; el de claves viejas con comillas y duplicadas se agregó después del code-review, con rojo propio por consola pero sin segundo bloque de red.sh.
**Decisiones no cubiertas:** consolidar dos ramas (un marcador por rama en consolidated.md de la nueva); `for the reviewer` con espacios, por pedido explícito. guardrails.py no hizo falta tocarlo: nunca frenó ramas no troncales.
**Lo que encontró la revisión:** skill_sha desconocido sin mapear, valores entre comillas en signals.sh, claves viejas y nuevas duplicadas, un `retros-pendientes` olvidado en orchestrate/SKILL.md.
**Propuesta:** que la skill diga que `/code-review` en un worktree necesita la rama como argumento, porque el fork corre en otro cwd.
