---
skill: implement-issue
issue: 259
pr: 262
area: docs
paths: scripts/agents/check-docs.py, scripts/agents/test-classes.sh, .claude/skills/review-pr/SKILL.md, SKILL.es.md
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: session
---
**Deviations:** (1) Primero commiteé el rojo con avisos de shellcheck y un caso de mutación que no se aplicó (sed fallido); lo detecté antes de empujar y reescribí ese commit, que no estaba publicado. (2) Intenté `git push -f` y el hook lo frenó; no hacía falta, alcanzaba un push normal. (3) Un caso rojo "debe salir con 0" hacía `Bail out` en vez de fallar: lo rehíce con una mutación que sale con 1 antes y después del arreglo.
**Decisions not covered:** cómo escribir en rojo un caso donde check-docs debería dejar de fallar (tap_run no admite esperar 1 sin riesgo ni un 0 que hoy da 1). Otro agente (barrilete-dot[bot]) commiteó en el mismo worktree mientras trabajaba y reestructuró test-classes.sh: mi edición por script se aplicó a medias y no avisó; hay que releer el archivo antes de editar por reemplazo.
**What the review found:** /code-review (2ª pasada): CRLF/espacios en classes.yml y la línea 49 que aún pedía **file:line** (arreglados); contrato del subagente reviewer, ids solo en líneas de formato y entrada del mapa (no arreglados, explicados en el PR).
**Proposal:** que los reemplazos por script en tests usen `assert old in t` siempre; documentar en implement-issue el patrón de rojo "falla antes y después con 1".
