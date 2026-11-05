---
skill: implement-issue
issue: 147
pr: 271
area: infra
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh, CHANGELOG.md
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: session
---
**Deviations:** `git push origin` fue rechazado (el token de GitHub App no tiene el permiso `workflows` y el cambio toca `labels.yml`); la persona pusheó por SSH con su credencial y recién ahí abrí el PR. Una primera corrida de `verify.py` quedó en un estado intermedio (rojo commiteado) y la repetí sobre el final. Un monitor mío con `pgrep -f` se autodetectaba y nunca terminaba; lo paré.
**Decisions not covered:** qué es "un título" en la línea siguiente (lo definí como `#`..`######` + espacio y lo confirmó la persona); sin `business-logic` porque es un check de CI y no una regla de un ADR. La skill no dice qué hacer cuando el push falla por permisos de workflows.
**What the review found:** `/code-review`: la lista de formas de línea siguiente era una lista negra incompleta (`owner/repo#n`, filas de tabla), falso positivo con un motivo que empieza con `#123`, `lineas` frágil al sacar el strip de `\r`, umbral de 200 ms flaky (un pico de 431 ms en frío) y mensaje engañoso si el hijo crashea. Arreglé todo menos el escaneo de `Closes` del primer job (otro job, fuera de alcance).
**Proposal:** en implement-issue, avisar desde el paso 2 que si el cambio toca `.github/workflows/` el push con la App va a fallar y pedir a la persona el push desde el principio.
