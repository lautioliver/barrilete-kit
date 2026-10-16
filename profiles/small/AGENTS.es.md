# AGENTS.md — <PROJECT>

Contexto para agentes y personas que tocan este repo. `CLAUDE.md` solo importa este archivo.

## Qué es

TODO: una o dos frases. Qué hace y para quién.

Cómo está armado hoy: `docs/architecture.md`. Decisiones difíciles de revertir: `docs/decisions/`.

## Stack y comandos

TODO: lenguaje, framework, base de datos.

```bash
# TODO: instalar, lint, test, dev
```

## Convenciones de código

TODO: las reglas que un agente rompería si no las lee (formato de errores, dónde va la lógica, cómo se manejan fechas o dinero…).

## Autonomía del agente

**Puede solo:** cambiar código y tests dentro de lo que pide el issue, refactors internos, actualizar docs, abrir PRs (nunca mergearlos).

**Consulta antes** (que el issue lo pida no es la aprobación: hace falta un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR): cambiar el schema de la base, agregar o quitar dependencias, tocar auth o secretos, cambiar una API que usan otros, tocar deploy o CI, ampliar el alcance del issue.

**Nunca:** correr migraciones o borrar datos fuera de local, poner secretos en el repo, desactivar tests o checks para que algo pase, mergear PRs, crear tags o publicar releases sin un pedido explícito.

Un hook (`scripts/agents/guardrails.py`, en `.claude/settings.json`) frena antes de correrlos el merge, la aprobación de PRs, el push a ramas troncales, los tags, las releases y `--no-verify`. En Codex, Copilot y Cursor lo registran `.codex/hooks.json`, `.github/hooks/guardrails.json` y `.cursor/hooks.json`. Si te frena, no busques otro camino: pedile a la persona que lo corra ella (en Claude Code, con `! <comando>`). Cambiar el hook, el script o esos registros se consulta.

Rutas sensibles de este proyecto (TODO: completar): schema `…`, auth `…`, deploy `…`.

### Si toca la base de datos

Antes de escribir la migración, mostrá y hacé aprobar: schema actual → deseado, si el código desplegado sigue andando, cómo se completan los datos existentes y **cómo se vuelve atrás**. Borrar o renombrar columnas en uso va en dos PRs: primero lo nuevo, después sacar lo viejo.

## GitHub

Detalle en `docs/github-naming-convention.md`.

- **Rama:** <BRANCH_RULE> Nombres `<tipo>/<n°issue>-<descripcion>`; si la crea un agente, `claude/<n°issue>-<descripcion>`.
- **Commits y PRs:** `<tipo>: <descripcion>` en imperativo y minúscula, con la descripción en <COMMIT_LANG> (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`). Cuerpo del PR con `.github/pull_request_template.md` y `Closes #n`.
- **Labels:** un `type:` por issue y PR; `priority:` solo en issues. Solo los de `.github/labels.yml`.
- **Equipo:** los issues nuevos se asignan solos a un integrante (por área y carga). El equipo se cambia con `/add-member` y `/remove-member`; no edites el archivo a mano. Asignado = responsable; en curso = con PR abierto.
- **Issues:** con la skill `create-issue`. **Implementar:** `/implement-issue <n>`. **Bugs:** skill `debug`.

## Docs

- `docs/README.md` — índice
- `docs/architecture.md` — qué corre hoy (si no coincide con el código, gana el código y se corrige)
- `docs/decisions/` — ADRs
- `docs/github-naming-convention.md` — ramas, commits, PRs, labels
