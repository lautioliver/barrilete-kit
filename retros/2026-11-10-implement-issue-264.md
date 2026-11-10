---
skill: implement-issue
issue: 264
pr: 283
area: agents
paths: scripts/agents/tap.sh, scripts/agents/red_report.py, CHANGELOG.md, scripts/agents/update.py
date: 2026-11-10
skill_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
model: sonnet
role: session
---
**Deviations:** El PR #293 (AMRC, mismo issue) se separó de #283 porque toca el texto de D6 de ADR-002 y una ruta sensible; se pidió aprobación a la persona en el issue. Tras publicarse 2.0.0 hubo que rebasar ambos y mover las entradas de CHANGELOG de la versión a `[Sin publicar]`; el cuerpo de los PR citaba SHAs de rojo que el rebase destruyó y el check `labels` falló hasta corregirlos.
**Decisions not covered:** Dónde va la entrada de CHANGELOG cuando la versión se publica mientras el PR está abierto. Qué hacer con los pushes forzados que el hook frena (se le pidió a la persona). Varios PR del mismo issue crean el mismo encabezado `## [Sin publicar]` y el segundo en mergear conflicta.
**What the review found:** `/code-review medium`: 7 hallazgos, el principal una ventana entre escribir la suite y vaciar los arrays de `tap.sh`; el caso que lo cuidaba no cubría el orden de vaciado hasta que se agregó un test con trap DEBUG. Abierto sin issue: un TERM entre vaciar y escribir pierde los casos de `tap.sh`.
**Proposal:** Después de rebasar, regenerar el SHA del rojo y los números del cuerpo del PR antes del push, no después; el check de labels lo detecta pero tarda un ciclo de CI.
