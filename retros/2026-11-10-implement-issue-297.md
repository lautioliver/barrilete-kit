---
skill: implement-issue
issue: 297
pr: 298
area: agents
paths: .agent-kit.json, .barrilete/rules.lock, scripts/agents/sync-rules, scripts/agents/check-docs.py
date: 2026-11-10
skill_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
model: sonnet
role: session
---
**Deviations:** Antes de abrir el #299 no leí el resultado de la búsqueda de duplicados: ya existía #290. Se cerró como duplicado.
**Decisions not covered:** El flag `template: true` en `.agent-kit.json` y que `check-docs.py` lo lea fue decisión mía dentro de la opción a) que eligió la persona; quedó marcado en el cuerpo del PR para review.
**What the review found:** `/code-review low`: sin hallazgos. Tras rebasar sobre 2.0.0, `test-init`, `test-install` y `test-update` no se volvieron a correr (más de 10 min); el cuerpo del PR lo dice.
**Proposal:** Leer la búsqueda de duplicados antes de `gh issue create`.
