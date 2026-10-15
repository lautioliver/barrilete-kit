# Changelog

Cambios de la plantilla por versión. `scripts/actualizar.py` muestra las secciones nuevas al actualizar un proyecto. Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones: [SemVer](https://semver.org/lang/es/). Este archivo es de la plantilla: el init lo borra.

**Publicar una versión** (lo hace una persona): un PR que sube `VERSION` y agrega su sección acá; después del merge, `git tag vX.Y.Z` sobre ese commit y `git push origin vX.Y.Z`. Así `VERSION` en `main` coincide con el último tag.

## [Sin publicar]

- CI de docs limitado a los archivos del kit (#120): con `.agent-kit.json`, `check-docs.py` valida solo los `.md` del kit, `docs/`, `AGENTS.md` y `llms.txt`, y `docs.yml` corre shellcheck y los `*test-*.sh` solo sobre los scripts del kit (`check-docs.py --listar <glob>`). El CI del kit ya no cubre los tests propios del proyecto, el shellcheck de sus `.sh` ni sus `.md` fuera de `docs/`: quien los necesite tiene que correrlos en un workflow propio. Un archivo del kit que se agregue después del init (por ejemplo, una skill nueva) queda fuera de `archivos` hasta que se actualice. `check-docs.py` y `docs.yml` se actualizan juntos: el workflow nuevo con un `check-docs.py` viejo no anda.
- Barandas: `git push --repo <remoto> <rama troncal>` se frena (antes la rama se tomaba como remoto y el push pasaba) (#109).
- `limpiar.sh` no saca el worktree de un issue cerrado si su PR sigue abierto: hay proyectos que cierran el issue al abrir el PR (#109).
- El check de labels acepta "sin test" o "sin tests", con el motivo en la misma línea o en la siguiente (#109).

## [0.9.0] - 2026-10-09

Primera versión con número: desde acá, un proyecto puede traer las siguientes con `python3 scripts/actualizar.py`. También los proyectos creados antes, si tienen `.agent-kit.json` (sin fusionar: lo que modificaron queda entero en `.agent-kit/pendientes/`).

- Reglas para agentes (`AGENTS.md`), autonomía y rutas sensibles.
- Skills de issue a PR con TDD, revisión, épicas, bloqueos y retros.
- Orquestador con subagentes por modelo y asignación automática al equipo.
- Modo chico y `crecer.py` para pasar al completo.
- Barandas: un hook frena el merge y la aprobación de PRs, el push a ramas troncales, los tags, las releases, los cambios a la protección de ramas y `--no-verify` (#97). En Claude Code se carga si la sesión se abre en la raíz del repo.
- El mismo hook registrado para Codex, Copilot y Cursor, y una tabla de qué funciona en cada herramienta (#100). En Codex corre si confiás en el proyecto y aprobás el hook con `/hooks`; en Copilot de VS Code, solo con `chat.useClaudeHooks`. Fuera de Claude Code no está probado: lo dice su documentación.
- Actualizaciones: `VERSION`, este changelog y `scripts/actualizar.py` (#99). Reemplaza lo que el proyecto no tocó, borra lo que la plantilla sacó, fusiona lo que tocaron los dos lados y, si hay conflicto, deja la fusión en `.agent-kit/pendientes/` sin pisar los cambios del proyecto.
- Guía y formulario para probar la plantilla con una persona externa (#98). Son de la plantilla: el init los borra.
