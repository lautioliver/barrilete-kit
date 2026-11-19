---
skill: implement-issue
issue: 365
pr: 367
area: docs
paths: scripts/agents/bitacora_add.py, scripts/agents/test-bitacora-add.sh, .claude/skills/bitacora, docs/agents/bitacora.md, CHANGELOG.md
date: 2026-11-19
skill_sha: 7fe49d2d1ce2184e3a28f4aaa34a6fcd9570a9a9
model: opus
role: session
---
**Deviations:** el trabajo se partió en dos sesiones (handoff de bk después del verde). El bloque del rojo que el handoff decía que estaba en ~/Downloads no estaba: se regeneró con red.sh desde un worktree temporal en el commit del rojo. Un primer test-init corrió con los casos nuevos de la auto-revisión todavía en rojo y dio Bail out!; se volvió a correr después del verde (143/143). Dos commits locales se rehicieron (reset --soft, sin push) porque el título del de test pasaba de 72 caracteres.
**Decisions not covered:** cómo detectar una portada que perdió su marcador de meses sin tomarla por una bitácora de antes (se usa `main class="wrap temas"`, que solo escribe la portada); cuándo un `add --new` sobre un tema existente es un reintento (el tema enlaza solo a este mes y la página del mes no lo tiene). Se dejaron como propuesta en el PR: bitacora-anterior.html, la regla de --date, los enlaces viejos, «front page»; como pregunta: el corte en la primera entrada nueva vs «desde el mes siguiente» y el mes según el reloj local (husos horarios).
**What the review found:** /code-review encontró 4: reintento de add --new cortado rechazado con 64 aunque los docs decían que repetirlo lo terminaba (arreglado); husos horarios bloquean add (pregunta en el PR); --date del mes anterior entra a principio de mes, contra «solo el mes en curso» (docs corregidos a «el mes más nuevo»); portada sin marcador de meses daba un aviso que nombraba otro marcador (arreglado). Los docs se escribieron prometiendo más de lo que el código hacía en dos de los cuatro.
**Proposal:** en implement-issue, después de escribir los docs, pedir contrastar cada afirmación de comportamiento nueva («repetirlo lo termina», «solo el mes en curso») con un caso del test o con el código antes de /code-review. Y que el handoff guarde el bloque del rojo dentro del repo de trabajo o en el archivo del handoff, no en ~/Downloads.
