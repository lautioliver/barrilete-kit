---
skill: implement-issue
issue: 122
pr: 131
area: infra
rutas: scripts/install.py, scripts/test-install.sh, scripts/update.py, scripts/init-template.sh, docs/agents-map.json, docs/github-naming-convention.md, profiles/small, CHANGELOG.md
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
fecha: 2026-10-15
modelo: sonnet
rol: implementer
agente_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** `/code-review` lanzado con la herramienta Skill corre en el cwd de la sesión (el checkout principal, donde HEAD == origin/main) y devolvió `[]` por diff vacío; hubo que relanzarlo pasándole la ruta absoluta del worktree. Dos comandos largos (test-init ~100-250 s) superaron el timeout de 120 s y pasaron a background.
**Decisiones no cubiertas:** `--lang` se pasa con `--` (passthrough) en vez de conocerlo; el instalador no crea rama; el default de plantilla es el clon donde vive el script; los archivos fusionados/pendientes no se registran en `.agent-kit.json` (si no, `update.py` los reemplazaría con la versión pura del kit); `renames` en `.agent-kit.json` y `renombrar()` en `update.py`. Mis fixtures de test chocaron con la tabla de renombres (`limpiar.sh`) y con `git ls-files` (check-docs y agents_map miran lo trackeado: hay que commitear antes de probar el CI del kit).
**Lo que encontró la revisión:** 10 hallazgos; 7 reales: instalación a medias si un padre es un archivo, `.yaml` vs `.yml`, `git clone` sin `--`, labels.py sin comprobar/duplicado, rama base sin validar, hook duplicado con otro comando, `labels.yml` propio sin aviso. Un doc que menciona `scripts/install.py` en backticks rompió `check-docs` en los proyectos recién creados (el init borra el archivo): los docs que se instalan no deben citar con ruta archivos exclusivos de la plantilla.
**Propuesta:** en la skill (o el contrato), avisar que `/code-review` en subagentes necesita la ruta del worktree explícita; y que `check-docs` falla en proyectos instalados si un doc cita con ruta un archivo que el init borra.
