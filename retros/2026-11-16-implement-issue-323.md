---
skill: implement-issue
issue: 323
pr: 328
area: infra
paths: scripts/agents/verify.py, scripts/agents/test-checks.sh, .gitignore, AGENTS.md, CHANGELOG.md
date: 2026-11-16
skill_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
model: opus
role: session
---
**Deviations:** dos rojos en el mismo PR (el original y el de los hallazgos del code-review), los dos en el cuerpo. En el rojo, la primera versión del lector de eventos crasheaba si el archivo no existía (Bail out); se arregló antes del commit del rojo.
**Decisions not covered:** un evento por regla y no por check; no incluir `pr` (verify.py no lo conoce sin red); escribir en el checkout principal desde un worktree. Nada de esto lo decía el issue y está en el PR para la review.
**What the review found:** /code-review (medium) encontró 9 hallazgos y se arreglaron 8. Los que importaban: desde un worktree el registro se perdía con el worktree; si el .gitignore no tenía la línea, el log aparecía como cambio; con un BK_HARNESS inválido quedaba claude-code; un task_id inventado a partir del nombre de la carpeta; el registro solo al final, que perdía todo si se cortaba la corrida; y el caso con chmod 555, que no frena a root. El diseño inicial no pensó en los worktrees, aunque son justo donde corren los agentes que se quieren medir.
**Proposal:** que implement-issue pregunte, para todo lo que escriba archivos locales, «¿qué pasa si esto corre en un worktree de agente?».
