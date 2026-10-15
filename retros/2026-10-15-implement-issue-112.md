---
skill: implement-issue
issue: 112
pr: 124
area: docs
rutas: docs/decisions/ADR-001-idioma-labels-y-nombres-en-ingles.md, docs/decisions/README.md, docs/README.md, docs/llms.txt
skill_sha: 82077adefa605bf351a59e9bcdc4fc3adbeeb39b
fecha: 2026-10-15
modelo: sonnet
rol: implementador
agente_sha: baeed63244b476905bb4aa29877d709c541a48e5
---
**Desvíos:** sin test (solo docs). La primera corrida de /code-review revisó el checkout principal (origin/main == HEAD ahí) y devolvió vacío; hubo que repetirla indicando la ruta del worktree.
**Decisiones no cubiertas:** cómo distinguir ADRs del kit (marcador `Ámbito: kit`); check-docs.py marca como rotas las rutas futuras en backticks, sin mecanismo de exclusión.
**Lo que encontró la revisión:** el init aún copia el ADR; ADR-002 placeholder en el índice; campo Ámbito sin definir; ADR aceptado vs AGENTS.md aún sin alinear.
**Propuesta:** en el contrato, decir que /code-review como subagente necesita la ruta del worktree explícita.
