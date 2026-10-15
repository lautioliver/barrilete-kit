# Changelog

Cambios de la plantilla por versión. `scripts/update.py` muestra las secciones nuevas al actualizar un proyecto. Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones: [SemVer](https://semver.org/lang/es/). Este archivo es de la plantilla: el init lo borra.

**Publicar una versión** (lo hace una persona): un PR que sube `VERSION` y agrega su sección acá; después del merge, `git tag vX.Y.Z` sobre ese commit y `git push origin vX.Y.Z`. Así `VERSION` en `main` coincide con el último tag.

## [Sin publicar]

- **Ruptura: retros y contrato de salida de los subagentes en inglés** (#128, ADR-001 R-8). La rama de retros pasa de `agentes/retros` a `agents/retros`; las claves del frontmatter (`modelo`, `rol`, `agente_sha`, `rutas`, `fecha`, `corrida`) pasan a `model`, `role`, `agent_sha`, `paths`, `date`, `run`; `consolidado.md` pasa a `consolidated.md` y `.git/retros-pendientes/` a `.git/pending-retros/`. El bloque de salida de los subagentes cambia sus claves (`resultado` a `result`, `para el revisor` a `for the reviewer`, `consultas` a `questions`…) y sus valores (`consulta`, `escalar`, `soltado`, `bloqueantes` a `question`, `escalate`, `dropped`, `blockers`); `routing.py` imprime `reason:`. Transición: `retro.sh` solo escribe en `agents/retros`; `retro.sh` y `signals.sh` leen las dos ramas y normalizan claves y valores viejos, así `/improve-skills` cuenta el historial mezclado como un solo grupo; los datos viejos no se reescriben ni se borran, y una retro pendiente con formato viejo se acepta. En un proyecto 0.9, la rama vieja queda como está; si protegés ramas, permití pushear a `agents/retros`; no renombres la rama vieja a mano (`git push origin agentes/retros:agents/retros`): sus commits quedarían como ancestros de la nueva y `signals.sh` mostraría dos veces cada retro vieja. Tabla completa en el ADR-001.
- **Ruptura: archivos, rutas, claves, flags y labels en inglés** (#114, ADR-001 R-2 a R-4). El comportamiento no cambia: las barandas frenan lo mismo y los checks validan lo mismo; cambian los nombres y los mensajes de los scripts, que salen solo en inglés. Los proyectos creados con 0.9 los migran con `scripts/update.py` en el issue #116; la tabla vieja → nueva de abajo es su fuente. La prosa de los docs y las skills se traduce en #115 y sigue en español por ahora.
- `init-template.sh --lang en|es` (#113, ADR-001 R-1): con `es`, cada `X.md` se reemplaza por su `X.es.md`; con `en` (default), los `.es.md` se borran. Combina con `--small` y `releases`, y `language` queda en `.agent-kit.json` (`update.py` y `grow.py` lo reproducen). `check-docs.py` exige, con `"parity": true` en el mapa (apagado hasta que #115 traduzca; el init lo apaga en los proyectos), que cada `X.md` tenga su `X.es.md` con los mismos encabezados y bloques de código (`parity_ignore` lista las excepciones), y el job del mapa avisa si un PR cambia un idioma sin el otro. El contenido se traduce en #115.
- CI de docs limitado a los archivos del kit (#120): con `.agent-kit.json`, `check-docs.py` valida solo los `.md` del kit, `docs/`, `AGENTS.md` y `llms.txt`, y `docs.yml` corre shellcheck y los `*test-*.sh` solo sobre los scripts del kit (`check-docs.py --listar <glob>`). El CI del kit ya no cubre los tests propios del proyecto, el shellcheck de sus `.sh` ni sus `.md` fuera de `docs/`: quien los necesite tiene que correrlos en un workflow propio. Un archivo del kit que se agregue después del init (por ejemplo, una skill nueva) queda fuera de `archivos` hasta que se actualice. `check-docs.py` y `docs.yml` se actualizan juntos: el workflow nuevo con un `check-docs.py` viejo no anda.
- Instalador para proyectos existentes (#122): `install.py "Proyecto" main [releases] [--small] [--draft] [-- <opciones del init>]` (en `scripts/`) instala el kit en un repo que ya tiene código, sin pisar nada suyo y sin commitear. README y LICENSE no se tocan; `.gitignore` y `CLAUDE.md` reciben solo lo que falta; `.claude/settings.json` se fusiona (JSON) con el hook de barandas; un workflow con el mismo nombre se instala como `barrilete-<nombre>.yml`; `labels.yml` suma los labels del repo (`gh label list`) para que el sync no borre ninguno, y el instalador falla si no puede leerlos; `AGENTS.md`, `docs/README.md`, la plantilla de PR y `ISSUE_TEMPLATE/config.yml` quedan como los tiene el proyecto y la versión del kit va a `.agent-kit/pending/`. `.agent-kit.json` registra solo los archivos del kit, más `renames` (workflow instalado → nombre en el kit), que `update.py` aplica. `--lang` llega al init sin que el instalador lo conozca: va después de `--`.
- Barandas: `git push --repo <remoto> <rama troncal>` se frena (antes la rama se tomaba como remoto y el push pasaba) (#109).
- `limpiar.sh` no saca el worktree de un issue cerrado si su PR sigue abierto: hay proyectos que cierran el issue al abrir el PR (#109).
- El check de labels acepta "sin test" o "sin tests", con el motivo en la misma línea o en la siguiente (#109).

### Tabla de renombres (0.9 → nuevo)

Archivos y carpetas (lo que no está acá conserva su nombre):

| 0.9 | Nuevo |
|---|---|
| `scripts/agentes/` | `scripts/agents/` |
| `scripts/agentes/barandas.py`, `test_barandas.py` | `scripts/agents/guardrails.py`, `test_guardrails.py` |
| `scripts/agentes/mapa.py` | `scripts/agents/agents_map.py` |
| `scripts/agentes/verificar.py` | `scripts/agents/verify.py` |
| `scripts/agentes/equipo.py`, `test_equipo.py` | `scripts/agents/team.py`, `test_team.py` |
| `scripts/agentes/test-agentes.sh` | `scripts/agents/test-agents.sh` |
| `scripts/actualizar.py`, `crecer.py` | `scripts/update.py`, `grow.py` |
| `scripts/init-plantilla.sh`, `test-actualizar.sh` | `scripts/init-template.sh`, `test-update.sh` |
| `docs/mapa-agentes.json` | `docs/agents-map.json` |
| `docs/agentes/` (`contrato-subagentes.md`, `lecciones.md`) | `docs/agents/` (`subagent-contract.md`, `lessons.md`) |
| `docs/convencion-nombres-github.md` | `docs/github-naming-convention.md` |
| `docs/probar-la-plantilla.md` | `docs/try-the-template.md` |
| `docs/decisions/ADR-000-plantilla.md` | `docs/decisions/ADR-000-template.md` |
| `.github/equipo.json` | `.github/team.json` |
| `.github/hooks/barandas.json` | `.github/hooks/guardrails.json` |
| `.github/marca/` (`barrilete-oscuro.svg`, `dron-con-correa.svg`, `estados/{bloqueado,planificando,pr-listo,trabajando}.svg`) | `.github/brand/` (`barrilete-dark.svg`, `drone-on-leash.svg`, `states/{blocked,planning,pr-ready,working}.svg`) |
| `.github/workflows/desbloquear.yml` | `.github/workflows/unblock.yml` |
| `.github/ISSUE_TEMPLATE/4-auditoria.yml`, `5-prueba.yml` | `4-audit.yml`, `5-trial.yml` |
| `.claude/agents/implementador.md`, `implementador-liviano.md`, `revisor.md` | `implementer.md`, `implementer-light.md`, `reviewer.md` (el valor de `rol:` en las retros cambia igual) |
| `.claude/skills/crear-issue/` | `.claude/skills/create-issue/` |
| `.claude/skills/estado/` (`estado.sh`, `disponibles.sh`) | `.claude/skills/project-status/` (`status.sh`, `available.sh`; no se llamó `status` para no chocar con el `/status` de Claude Code) |
| `.claude/skills/mejorar-skills/` (`plantilla-retro.md`, `senales.sh`) | `.claude/skills/improve-skills/` (`retro-template.md`, `signals.sh`) |
| `.claude/skills/orquestar/` (`limpiar.sh`, `ruteo.py`, `test-orquestar.sh`) | `.claude/skills/orchestrate/` (`cleanup.sh`, `routing.py`, `test-orchestrate.sh`) |
| `.claude/skills/implement-issue/` (`preparar.sh`, `rojo.sh`, `test-preparar.sh`, `test-rojo.sh`) | `prepare.sh`, `red.sh`, `test-prepare.sh`, `test-red.sh` |
| `.claude/skills/plan-feature/planificar.py` | `.claude/skills/plan-feature/planner.py` |
| `perfiles/chico/` (`BORRAR`, `docs/convencion-nombres-github.md`, `.claude/skills/crear-issue/`) | `profiles/small/` (`DELETE`, `docs/github-naming-convention.md`, `.claude/skills/create-issue/`) |

Hay un archivo nuevo del kit: `scripts/test-renames.sh` (el init lo borra). Los hooks (`.claude/settings.json`, `.codex/hooks.json`, `.cursor/hooks.json`, `.github/hooks/guardrails.json`) apuntan a `scripts/agents/guardrails.py`: si el hook de un proyecto sigue apuntando a `scripts/agentes/barandas.py`, no encuentra el script y no frena nada (sale con 0), así que hay que actualizar los cuatro juntos.

Labels (con `aliases` en `.github/labels.yml`: el sync renombra sin perder los labels puestos en issues y PRs). Los valores de `type:` no cambian:

| 0.9 | Nuevo |
|---|---|
| `tipo:feature`, `bug`, `task`, `audit`, `docs` | `type:feature`, `bug`, `task`, `audit`, `docs` |
| `prioridad:critica`, `alta`, `media`, `baja` | `priority:critical`, `high`, `medium`, `low` |
| `estado:a-triar`, `necesita-info`, `bloqueado` | `status:triage`, `needs-info`, `blocked` |
| `logica-negocio` | `business-logic` |

Claves JSON:

| Archivo | 0.9 | Nuevo |
|---|---|---|
| `docs/agents-map.json` | `_ayuda`, `cuando`, `revisar`, `motivo`, `sensibles`, `tipo`, `rutas`, `verificar`, `nombre`, `siempre`, `correr`, `obligatorios`, `ignorar_check` | `_help`, `when`, `review`, `reason`, `sensitive`, `type`, `paths`, `verify`, `name`, `always`, `run`, `required`, `ignore_check` |
| `docs/agents-map.json` (valores) | verificaciones `preparar`, `agentes`, `rojo`, `orquestar`, `barandas`, `actualizar`, `migraciones`, `contrato-api`; tipos `dinero`, `dependencias`, `api-publica`; placeholder `{archivos}` | `prepare`, `agents`, `red`, `orchestrate`, `guardrails`, `update`, `migrations`, `api-contract`; `money`, `dependencies`, `public-api`; `{files}` |
| `.github/team.json` | `_ayuda`, `integrantes`, `nombre`, `activo` (`login` y `areas` no cambian) | `_help`, `members`, `name`, `active` |
| `.agent-kit.json` | `proyecto`, `rama_base`, `modo` (`chico`, `completo`), `fecha`, `archivos` (`releases` y `version` no cambian) | `project`, `base_branch`, `mode` (`small`, `full`), `date`, `files` |
| plan de `planner.py` | `epica`, `titulo`, `cuerpo`, `clave`, `bloqueado_por`, `motivo`, `asignado` (`issues` y `labels` no cambian) | `epic`, `title`, `body`, `key`, `blocked_by`, `reason`, `assignee` |

Flags, subcomandos, variables y marcadores:

| 0.9 | Nuevo |
|---|---|
| `init-plantilla.sh --chico`; `update.py` y `grow.py --plantilla` | `init-template.sh --small`; `--template` |
| `check-docs.py --listar`; `preparar.sh --revisar`; `limpiar.sh --borrar`; `planificar.py --borrador`; `retro.sh --consolidado` | `--list`; `prepare.sh --review`; `cleanup.sh --delete`; `planner.py --draft`; `--consolidated` |
| `equipo.py listar`, `agregar`, `quitar`, `pausar`, `activar`, `sugerir`; `--nombre`, `--forzar`, `--carga` | `team.py list`, `add`, `remove`, `pause`, `activate`, `suggest`; `--name`, `--force`, `--load` |
| `AGENT_KIT_PLANTILLA`, `AGENT_KIT_FECHA` | `AGENT_KIT_TEMPLATE`, `AGENT_KIT_DATE` |
| `<PROYECTO>`, `<RAMA_BASE>`, `<FECHA>`, `<REGLA_RAMAS>` | `<PROJECT>`, `<BASE_BRANCH>`, `<DATE>`, `<BRANCH_RULE>` |
| `<!-- plantilla:inicio/fin -->`, `<!-- marca:inicio/fin -->`, `<!-- releases:inicio/fin -->` | `<!-- template:start/end -->`, `<!-- brand:start/end -->`, `<!-- releases:start/end -->` |
| `# main: para la plantilla misma` (en `docs.yml` y `labels.yml`) | `# main: for the template itself` |
| `.agent-kit/pendientes/` | `.agent-kit/pending/` |
| skills `/orquestar`, `/crear-issue`, `/mejorar-skills`, `/estado` (y `skill:` en las retros) | `/orchestrate`, `/create-issue`, `/improve-skills`, `/project-status` |

Para quien migre (#116): `inicializar()` de `update.py` ya usa el init que tenga el tag de origen (`init-plantilla.sh` con `--chico` y `AGENT_KIT_FECHA` en 0.9), pero un `.agent-kit.json` con claves viejas todavía se rechaza con un aviso: lo migra #116. Los `aliases` de `labels.yml` cuentan como labels del kit para `labels.py` (no se copian como propios) y `labels.py` reconoce la marca vieja de la sección de propios.

Retros: `retro.sh` y `signals.sh` aceptan y normalizan los valores viejos de `skill:` (`orquestar`, `mejorar-skills`) y `rol:` (`implementador`, `implementador-liviano`, `revisor`) con una sola tabla (`.claude/skills/improve-skills/legacy-names.sh`), así una retro pendiente de 0.9 se guarda y el historial no se parte. Sin cambios en este PR: la rama `agentes/retros`, las claves del frontmatter, `consolidado.md`, `retros-pendientes/` y el bloque de salida de los subagentes (`resultado:`, `pr:`…, y el `motivo:` de `routing.py`). Su migración es el issue #128. Los textos del cuerpo del PR que validan los checks (`Rojo antes de implementar`, `Closes #n`, `sin test`, `ADR sin cambios:`) siguen igual hasta que #115 traduzca las plantillas.

Después del merge: correr el workflow Labels, revisar que los issues abiertos tengan `type:` y `status:` bien y volver a correr el check de labels de los PRs abiertos. Los worktrees y ramas creados antes del merge (por ejemplo, los de #115 y #116) tienen los hooks viejos o el script viejo: hay que rebasarlos o recrearlos, porque con la config nueva y sin `scripts/agents/guardrails.py` el hook sale con 0 y las barandas quedan apagadas sin aviso.

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
