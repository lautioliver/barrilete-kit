---
skill: implement-issue
issue: 114
pr: 127
area: area:infra
rutas: scripts/agents/, scripts/*.py, scripts/init-template.sh, .claude/skills/, .claude/agents/, .github/workflows/, .github/labels.yml, docs/agents-map.json, hooks de las 4 herramientas, CHANGELOG.md
skill_sha: 82077adefa605bf351a59e9bcdc4fc3adbeeb39b
fecha: 2026-10-15
modelo: sonnet
rol: implementer
agente_sha: baeed63244b476905bb4aa29877d709c541a48e5
---
**Desvíos:** `/code-review` corrió dos veces: la primera, lanzada como skill forkeada, usó el cwd de la sesión (el checkout del orquestador) y revisó otro rango; la segunda, con la rama nombrada y el worktree en el argumento, sí. El check `shellcheck` de `verify.py` falla en un PR que renombra `.sh` (le pasa los nombres viejos): lo corrí a mano sobre `git ls-files '*.sh'`.
**Decisiones no cubiertas:** el ADR da ejemplos y no la lista de renombres. Decidí: todo archivo, carpeta, clave JSON, flag, variable de entorno, placeholder y marcador va en inglés; quedan fuera los datos persistidos de las retros (rama `agentes/retros`, frontmatter, `consolidado.md`) y los textos del PR que validan los workflows (`Rojo antes de implementar`, `sin test`), porque dependen de #115 y de una migración propia. Tampoco traduje las descripciones de los tests. La skill de estado quedó `project-status` (no `status`) por el choque con el `/status` de Claude Code, que lo marcó la autorevisión, no yo.
**Lo que encontró la revisión:** `/status` chocaba con el built-in; `update.py`/`grow.py` fallaban con `KeyError` ante un `.agent-kit.json` de 0.9; un `usar estado` quedó en una descripción de skill (mi regex de nombres viejos solo miraba backticks y `/`). Los 5 restantes no se corrigieron (explicado en el PR).
**Propuesta:** (1) la skill implement-issue debería decir que `/code-review` forkeado revisa el cwd de la sesión y que, en un worktree, hay que pasarle la rama y la ruta. (2) Para issues de renombre masivo, escribir primero el test de "ningún archivo menciona el nombre viejo" con una tabla vieja → nueva fue la mejor guía: conviene sugerirlo en la skill. (3) `verify.py` debería filtrar de `{files}` los archivos que ya no existen. (4) Un `perl -pi` sobre `$files` sin split en zsh no itera: usar `while read`.
