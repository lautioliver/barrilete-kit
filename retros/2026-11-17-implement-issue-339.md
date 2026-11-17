---
skill: implement-issue
issue: 339
pr: 340
area: infra
paths: scripts/agents/bitacora.py, scripts/agents/bitacora/barrilete.css, scripts/agents/test-bitacora.sh, .claude/skills/improve-skills/legacy-names.sh, docs/agents/bitacora.md
date: 2026-11-17
skill_sha: 3e8ba9fcda14f96510c76f987f4cb3e9d6cbb456
model: opus
role: session
---
**Deviations:** Dos rojos de la revisión (a385609, 9500100) no son válidos para red.sh: al pasar el gh falso al formato de `gh api graphql`, un caso viejo ("el título del PR sale de gh") falla en el rojo sin cambiar su línea. Lo expliqué en el PR en vez de reescribir la historia. La primera versión de bitacora.py reimplementaba la lectura de retros (sin la tabla 0.9); la persona pidió unificarla en legacy-names.sh.
**Decisions not covered:** Que legacy-names.sh quite comillas y deje la primera clave repetida para todos (también retro.sh, que antes lo hacía aparte). Qué hacer con un pr: que no es un número común (hasta 9 cifras ASCII, si no cuenta como sin PR). Respetar GIT_SSH_COMMAND, GIT_SSH y core.sshCommand de la persona antes de forzar BatchMode. Sacar la inyección en el HTML de estado de Descargas del workspace (queda para que la persona lo confirme).
**What the review found:** /code-review: lectura de retros duplicada sin claves 0.9, ruta mostrada como issue, issue perdido en tarjetas con PR, traceback con UTF-8 inválido, gh pr list con tope de 1000 y llamado aunque no hubiera PRs, fetch sin timeout, texto antes del primer título perdido, casos 3 y 8 incompletos. Además, al buscar entradas hostiles: `"²".isdigit()` es True y rompía int().
**Proposal:** Que implement-issue avise que cambiar un fake compartido del test en el rojo hace fallar casos viejos y red.sh lo rechaza: cambiar el fake en un commit aparte (verde) antes del rojo.
