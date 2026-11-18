---
skill: implement-issue
issue: 343
pr: 344
area: infra
paths: scripts/agents/bitacora_add.py, scripts/agents/test-bitacora-add.sh, .claude/skills/bitacora, docs/agents/bitacora.md, profiles/small/DELETE
date: 2026-11-18
skill_sha: 3e8ba9fcda14f96510c76f987f4cb3e9d6cbb456
model: opus
role: session
---
**Deviations:** El primer filtro de la entrada fue una lista negra con regex (`<script`, `\son…=`, `javascript:`). /code-review la evadió de tres formas (`<img/src=x/onerror=…>`, un `>` dentro de comillas, `jav&#x61;script:`); se cambió por una lista permitida revisada con HTMLParser después de decodificar las entidades. El test nuevo exigía SKILL.es.md y en un proyecto instalado no existe: lo vio test-init, que corre los tests del proyecto instalado, no el test en la plantilla. Dos referencias rotas en --small (un link a docs/agents/bitacora.md y el test que nadie corre) salieron recién con test-init y la revisión.
**Decisions not covered:** El nombre del script nuevo (el issue pedía que no quedara bitacora.py), la ruta docs/bitacora.html y el código de salida de find (3) se le preguntaron a la persona antes del rojo. Sin preguntar: el diseño se copia al crear la página (las entradas no lo reescriben), --small lleva el skill pero no el test, no hay lock entre dos add simultáneos y pi no suma un comando con nombre; todo va en el PR para que lo mire la persona.
**What the review found:** /code-review medium dio 10 hallazgos: XSS en 3 variantes, CRLF que duplicaba la sección y dejaba el archivo en 65, modo 0600 por mkstemp, ids reservados (theme-*, structure), --small con el test huérfano, el hub de docs sin el skill y el CHANGELOG que decía "sin red". Se arreglaron 9 con su rojo (4d63935); el cierre implícito de HTML5 quedó acotado por la lista permitida y explicado en el PR.
**Proposal:** implement-issue podría decir que todo filtro de HTML o de rutas que arme un agente sea una lista permitida desde el primer commit, nunca una lista negra con regex. Y que un test nuevo de la plantilla que lea archivos `.es.md` pase test-init antes de pedir review.
