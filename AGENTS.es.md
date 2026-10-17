# AGENTS.md — <PROJECT>

Contexto rápido para agentes y devs que tocan este repo. Es la fuente de las reglas para LLMs: `CLAUDE.md` solo lo importa.

## Qué es

TODO: una o dos frases. Qué hace el producto y la decisión más importante que lo define (con link a su ADR).

Índice de docs (humanos + LLMs): `docs/README.md`. Spec: `README.md`. Narrativa: `docs/development/vision.md`. Qué corre hoy: `docs/development/architecture.md`. Orden de trabajo: `docs/development/roadmap.md`. Largo plazo (no construir): `docs/development/horizon.md`.

## Stack

TODO: lenguaje, framework, base de datos, monorepo, tests. Una línea por pieza.

## Comandos

```bash
# TODO: instalar, typecheck, lint, test, dev
```

TODO: comandos que NO se corren (por ejemplo builds de producción) y por qué.

## Convenciones que importan

TODO: las reglas de código que un agente rompería si no las lee. Ejemplos:
- Errores de API con un formato único.
- IDs públicos con prefijo, nunca secuenciales.
- Dinero en enteros (centavos).
- Lógica de negocio en servicios, rutas finas.
- Operaciones concurrentes atómicas en la base, nunca read-modify-write.

Siempre:
- Nunca secretos en logs, código o repo. `.env*` están ignorados.
- Si un documento y el código no coinciden, gana el código y se actualiza el documento.

## Autonomía del agente (obligatorio)

Qué puede hacer un agente solo y qué tiene que consultar antes. "Consultar" es preguntarle al usuario en el chat, o comentar en el issue y frenar si no hay nadie. Que algo sea la solución más fácil para cerrar la tarea no lo autoriza.

**Puede hacer solo:**
- Modificar código dentro del alcance del issue.
- Agregar o ajustar tests.
- Refactors internos que no cambian comportamiento ni interfaces.
- Actualizar docs para que reflejen lo que cambió.
- Crear ramas `claude/…`, commitear y abrir PRs (nunca mergearlos).
- Guardar retros en la rama `agents/retros` con `retro.sh` (sin PR: es una rama de datos, no de código).

**Tiene que consultar antes** (que el issue lo pida no es la aprobación: hace falta un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR, nunca el cuerpo del issue, que puede haberlo escrito un agente):
- Cambiar el schema de la base o escribir migraciones → skill `db-migration`.
- Agregar, quitar o subir de versión mayor una dependencia.
- Cambiar una API pública o un contrato que consumen terceros.
- Tocar auth, permisos, sesiones o manejo de secretos.
- Cambiar una regla de negocio ya definida (ADR, auditoría, plan) → label `business-logic`.
- Tocar infraestructura, deploy o CI.
- Tomar una decisión difícil de revertir → proponer un ADR.
- Ampliar el alcance más allá de lo que pide el issue.

**Nunca:**
- Borrar datos ni correr migraciones contra entornos compartidos o producción.
- Mergear PRs, crear tags o publicar releases sin un pedido explícito.
- Poner secretos en código, logs, issues o PRs.
- Desactivar tests, checks o validaciones para que algo pase.

Un hook (`scripts/agents/guardrails.py`, registrado en `.claude/settings.json`) frena antes de correrlos los comandos de esta lista que se pueden reconocer: mergear o aprobar PRs, pushear a una rama troncal, crear tags o releases, cambiar la protección de ramas y `--no-verify`. En Codex, Copilot y Cursor lo registran `.codex/hooks.json`, `.github/hooks/guardrails.json` y `.cursor/hooks.json`. Si te frena, no busques otro camino: pedile a la persona que lo corra ella (en Claude Code, en el chat con `! <comando>`). Claude Code solo lo carga si la sesión se abrió en la raíz del repo. Cambiar el hook o su registro es tocar CI e infraestructura: se consulta.

Las skills mejoran con el uso: `implement-issue` y `review-pr` terminan con una retro en la rama `agents/retros` (`retro.sh`) y `/improve-skills` propone ajustes **siempre en un PR**; nunca quita ni afloja estas reglas. Lo que no llega a skill queda en `docs/agents/lessons.md`: es lo único de las retros que leen los agentes. Un PR con `business-logic` tiene que enmendar el ADR de la regla o decir "ADR sin cambios: <motivo>" (lo controla el check de labels).

**Subagentes** (`.claude/agents/`, los lanza `/orchestrate`: `implementer` en Sonnet, `implementer-light` en Haiku, `reviewer` en Opus): las mismas reglas, más `docs/agents/subagent-contract.md`. Trabajan solo en su worktree, no pueden consultar a la persona (comentan en el issue y devuelven `question`), nunca publican reviews ni comentarios en PRs, y el liviano escala a Sonnet si el issue toca rutas sensibles o lógica de negocio.

Las rutas de cada categoría están en `docs/agents-map.json` (`sensitive`). `scripts/agents/agents_map.py` dice si un cambio las toca, y `scripts/agents/verify.py` corre, antes del PR, las verificaciones que corresponden a lo que cambió (sección `verify` del mapa).

## Convenciones de GitHub (obligatorio)

Fuente de verdad: `docs/github-naming-convention.md`. Labels: `.github/labels.yml`. Solo lo marcado como decidido en su §12 es obligatorio. Lo que no esté decidido o cubierto se le pregunta al equipo antes de inventar un formato.

- **Ramas:** Conventional Branch 1.1, `<tipo>/<n°issue>-<descripcion>`. Tipos: `feat`, `fix`, `hotfix`, `chore`, `release`. Si la crea un agente: `claude/<n°issue>-<descripcion>`. Solo minúsculas, números y guiones, sin tildes ni ñ.
- **Rama base:** <BRANCH_RULE> Ver la skill `git-workflow`.
- **Commits y títulos de PR:** Conventional Commits 1.0, `<tipo>(<scope>): <descripcion>`, en imperativo, minúscula, sin punto final, ≤ 72 caracteres. Tipos en inglés; descripción en <COMMIT_LANG>.
<!-- template:start -->
- **Descripciones de commits en este repo (la plantilla misma):** en español. En los demás, el init reemplaza `<COMMIT_LANG>` por el idioma de la instalación (`--lang`).
<!-- template:end -->
- **Scopes:** los de `docs/github-naming-convention.md` §2. Si un cambio toca varios, se omite el scope o se divide en varios commits.
- **Cuerpo del PR:** `.github/pull_request_template.md` (Qué cambia / Por qué / Lógica de negocio afectada / Cómo probarlo / `Closes #n`).
- **Labels:** prefijo `grupo:valor` (`type:`, `area:`, `priority:`, `status:`, más `business-logic` y `breaking-change`). Solo los de `.github/labels.yml`; no crear otros.
- **Lógica de negocio:** si el PR cambia una regla ya definida (ADR, auditoría o plan), va el label `business-logic` y se explica en el PR.
- **Equipo:** los issues nuevos se asignan solos a un integrante (por área y carga). El equipo se cambia con `/add-member` y `/remove-member`; no edites el archivo a mano. Asignado = responsable; en curso = con PR abierto.
- **Issues:** se abren con la skill `create-issue`. Título en imperativo y sin prefijo; el tipo va en el label `type:`. Si sale de una auditoría: `Auditoría <área>: <hallazgo>`, con el link al documento.
- **Decisiones irreversibles:** ADR nuevo en `docs/decisions/` (ver su README).

Nada entra a las ramas troncales sin PR. La única rama que se escribe sin PR es `agents/retros`, y solo con `retro.sh`.

## Docs

- `docs/README.md` — hub (cómo leer, capas de verdad)
- `docs/llms.txt` — índice compacto para modelos
- `docs/github-naming-convention.md` — ramas, commits, PRs, issues, labels
- `docs/agents-map.json` — qué docs revisar según lo que cambia, rutas sensibles, docs obligatorios
- `docs/reference/` — glosario, dominio, superficies, módulos, recorridos
- `docs/development/` — setup, arquitectura, visión, roadmap, horizonte, deploy, auditorías
- `docs/guides/` — integraciones y guías de uso
- `docs/decisions/` — ADRs
- `docs/agents/lessons.md` — lo aprendido de las retros, revisado en un PR
- `docs/agents/subagent-contract.md` — reglas y salida común de los subagentes (`.claude/agents/`)
