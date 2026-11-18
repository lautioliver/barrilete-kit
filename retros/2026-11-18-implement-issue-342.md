---
skill: implement-issue
issue: 342
pr: 347
area: infra
paths: scripts/agents/learning.py, scripts/agents/test-learning.sh, docs/agents/learning-event.md, docs/agents/learning-event.es.md, CHANGELOG.md
date: 2026-11-18
skill_sha: 27a1947ee312dc9fbbcf418c7af4aa075868ae73
model: opus
role: session
---
**Deviations:** reescribí dos veces el commit del rojo antes de implementar (agregué casos de evidence_ref de la misma clase: fragmento con clave=valor, ;jsessionid=, %3F) y volví a correr red.sh cada vez. El primer arreglo del patrón v0 `branch` fue demasiado laxo ("lo que git acepta sin espacios": dejaba pasar `password=hunter2`, comillas, `..`, invisibles); lo encontró /code-review y no mi propio repaso de entradas hostiles.
**Decisions not covered:** BK_HARNESS="" → claude-code (lo decidió Lautaro en el chat). Qué campos son "propios del evento" para emit: los saqué de lo que manda el adaptador de workspace (ts, class, role, pr, area, evidence_ref) más rule_id y outcome; dentro de una tarea bk, role y pr no. Unifiqué en 64 cualquier campo ajeno en emit (antes, uno fuera de la tabla daba 3).
**What the review found:** 8 hallazgos. Arreglados con su rojo: role/pr pisables en una tarea bk (rules_ref de otro rol), guarda solo en la CLI y no en evento(), códigos de salida distintos para campos ajenos, rama v0 demasiado laxa, `v` muerto en _valor. Descartados: task_id v0 (el ADR-005 fija el slug) y raiz_principal en un submódulo (es anterior al cambio). Queda abierto, como pregunta en el PR: un secreto dentro del path de una URL; necesita una lista de URLs permitidas y es una decisión sobre el ADR-007 D3.
**Proposal:** cuando un arreglo afloja un validador para tolerar datos viejos, probar en el rojo también qué NO tiene que pasar (texto libre que entra por el patrón nuevo), no solo los casos que tienen que pasar.
