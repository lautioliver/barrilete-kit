---
skill: implement-issue
issue: 121
pr: 125
area: area:infra
rutas: scripts/agentes/labels.py, scripts/agentes/test_labels.py, docs/convencion-nombres-github.md
skill_sha: 82077adefa605bf351a59e9bcdc4fc3adbeeb39b
fecha: 2026-10-15
modelo: sonnet
rol: implementador
agente_sha: baeed63244b476905bb4aa29877d709c541a48e5
---
## Qué salió bien
Ciclo rojo/verde limpio; la función quedó chica y testeada.

## Desvíos
- El issue pedía tocar CI/labels.yml/check-docs.py, pero ya aceptaban labels sin prefijo: no hizo falta tocarlos (dicho en el PR).
- El primer /code-review corrió contra el checkout principal (cwd reseteado) y devolvió diff vacío; hubo que repetirlo pasando la ruta del worktree.
- El primer sed de docs falló en macOS; usé python para editar.

## Sugerencias
La skill podría decir que /code-review en subagentes necesita la ruta explícita del worktree.
