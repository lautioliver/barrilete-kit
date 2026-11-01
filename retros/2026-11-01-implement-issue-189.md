---
skill: implement-issue
issue: 189
pr: 209
area: infra
paths: scripts/agents/tap.sh, scripts/agents/test-i18n.sh, scripts/agents/test-tap.sh, .claude/skills/implement-issue/SKILL.md, .claude/skills/implement-issue/SKILL.es.md, .claude/skills/review-pr/SKILL.md, .claude/skills/review-pr/SKILL.es.md
date: 2026-11-01
skill_sha: 46c877b75ec4d3b9a9946282df5f791f8674921c
model: haiku
role: session
---
**Deviations:** `/code-review` tardó mucho y no devolvió resultado hasta después de abrir el PR; se abrió con la revisión a mano y después llegó el informe, que se trató en el PR. El informe fue en `low`, no en el nivel por defecto. Se repitió un `sleep` en bucle con Monitor muchas veces para esperar, lo que gastó muchas llamadas.
**Decisions not covered:** la skill no dice qué hacer cuando la decisión ya está en el chat pero el issue dice "necesita su sí": tomé la respuesta de la persona en el chat como aprobación. Marqué el PR `business-logic` con "ADR unchanged" porque la regla que se afloja es de ADR-002 D6 y no se modificó el ADR.
**What the review found:** (1) el aviso de que la excepción no tenía aprobación era falso: estaba en el chat; (2) el encabezado de `tap.sh` se contradecía en una frase: corregido en commit aparte; (3) `red.sh` no verifica el marcador del runner, sólo la guía: queda como límite conocido; (4) la regla está en cinco archivos en dos idiomas y puede desviarse; (5-6) los tests de lint comprueban frases, no comportamiento.
**Proposal:** pedir al `review-pr`/`implement-issue` que, cuando un issue de tipo docs decide una regla, pregunte antes de empezar y quede registrado en el PR qué persona aprobó qué opción. Considerar un solo origen de la regla del rojo (guía) con los demás enlazados.
