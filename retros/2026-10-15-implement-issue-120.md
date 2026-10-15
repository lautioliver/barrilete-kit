---
skill: implement-issue
issue: 120
pr: 126
area: infra
rutas: scripts/agentes/check-docs.py, .github/workflows/docs.yml, perfiles/chico/.github/workflows/docs.yml, scripts/agentes/test-agentes.sh
skill_sha: 82077adefa605bf351a59e9bcdc4fc3adbeeb39b
fecha: 2026-10-15
modelo: sonnet
rol: implementador
agente_sha: baeed63244b476905bb4aa29877d709c541a48e5
---
**Desvíos:** el primer `/code-review` corrió en el checkout del orquestador (el cwd del Skill no es el worktree) y dijo "diff vacío"; hubo que pasarle el diff como archivo. Un test mío falló en CI (test-init/test-base corren test-agentes.sh en un proyecto inicializado, donde check-docs falla por los TODO del mapa) y no lo vi local porque no corrí esos tests antes de pushear.
**Decisiones no cubiertas:** `--listar <glob>` en check-docs.py como fuente única de "archivos del kit" para el workflow; dejé `docs/**` entero dentro del alcance porque el issue lo pide, aunque el code-review lo marcó.
**Lo que encontró la revisión:** listados vacíos silenciosos si falla el script (pipe con xargs -r); manifiesto inválido con traceback; `--listar` sin glob caía al check completo. Todos corregidos con test rojo.
**Propuesta:** en la skill, decir que `/code-review` en un worktree necesita el diff explícito, y que los tests de un script compartido se corran también vía los tests que lo envuelven (test-init, test-actualizar) antes del push.
