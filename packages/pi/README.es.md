# barrilete-pi

Barrilete Kit para [pi](https://github.com/badlogic/pi-mono): el mismo flujo que en Claude Code (planear, implementar, revisar, con los nudos humanos), sin depender de Claude Code. No copia el kit: reusa `.claude/skills/` y `scripts/agents/` del proyecto, así un proyecto funciona igual en cualquiera de los dos harness.

## Qué trae

| Pieza del kit | En pi |
|---|---|
| Skills (`.claude/skills/`) | Se suman al descubrimiento de pi: aparecen en el system prompt y como `/skill:<nombre>`. |
| `/plan-feature`, `/implement-issue <n>`, `/review-pr <n>`, `/orchestrate`, `/project-status`, `/improve-skills`, `/add-member`, `/remove-member` | Comandos con el mismo nombre. Cada uno carga el `SKILL.md` entero en el mensaje. |
| Subagentes (`.claude/agents/`) para `/orchestrate` | La herramienta `subagent` corre `implementer`, `implementer-light` y `reviewer` como procesos de pi aparte, cada uno en su worktree, y devuelve su bloque del contrato. |
| Barandas (`scripts/agents/guardrails.py`) | Cada comando bash del agente pasa por el mismo script antes de correr; si lo bloquea, pi no lo ejecuta y el agente lee por qué. |
| Línea del flujo (`scripts/agents/flow.py`) | En el footer de pi, actualizada al empezar la sesión y cuando el agente termina. |

Todo se prende solo dentro de un proyecto Barrilete (un repo git con `scripts/agents/guardrails.py`); en cualquier otra carpeta el paquete no hace nada.

Todavía no: un lanzador `barrilete` con home propio, la integración con SketchyBar y la publicación en npm.

## Instalación

Necesita pi, `python3` y, para la línea del flujo, `gh`. Desde un clon del kit:

```bash
pi install ./packages/pi        # todos tus proyectos (~/.pi/agent/settings.json)
pi install -l ./packages/pi     # solo este proyecto (.pi/settings.json)
pi -e ./packages/pi             # probarlo en una sesión sin instalar
```

Después abrí pi en la raíz del proyecto y escribí `/plan-feature <idea>`.

## Cómo funciona

- `extensions/skills.ts`: `resources_discover` devuelve las carpetas de skills del proyecto, y cada comando arma el mismo bloque `<skill>` que pi arma para `/skill:<nombre>`.
- `extensions/guardrails.ts`: en `tool_call` de `bash`, le manda a `guardrails.py` el JSON del hook de Claude Code y bloquea si sale con 2. Como los otros hooks, si falla deja pasar: es una baranda, la traba es la protección de ramas.
- `extensions/flow.ts`: `flow.py --format plain` en `ctx.ui.setStatus`.
- `extensions/subagents.ts` y `lib/subagents.ts`: la herramienta `subagent`. Lee el rol de `.claude/agents/<rol>.md` (la misma definición que corre Claude Code) y lanza `pi --mode json -p` en el worktree con el modelo y las herramientas del rol, traducidos (`Read` → `read`, `Glob` → `find`, `ls`; `Skill` no tiene equivalente), más notas sobre lo que cambia en pi (no hay `/code-review`, así que declara `no code-review`).

## Subagentes

Lo que pide el contrato (`docs/agents/subagent-contract.md`) se mantiene en pi:

- **Barandas siempre prendidas.** El hijo carga solo este paquete (`--no-extensions -e <paquete>`), y sus barandas usan el `guardrails.py` del checkout del orquestador, nunca la copia del worktree, que es código del PR sin revisar.
- **No pueden lanzar otros subagentes.** Dentro de un subagente la herramienta no se registra.
- **Nunca más de 3 implementando a la vez.** La herramienta rechaza la llamada que se pasaría, contando los que ya corren.

Los modelos de los roles son alias (`opus`, `sonnet`, `haiku`). pi los resuelve como patrones entre tus modelos: con Anthropic, el último de cada familia. Para otro proveedor, mapealos:

```bash
export BARRILETE_MODELS="opus=openai/gpt-5,sonnet=openai/gpt-5-mini,haiku=openai/gpt-5-nano"
```

Como el hijo corre con `--no-extensions`, un proveedor que viene de una extensión tuya no está disponible para los subagentes: mapeá los roles a proveedores integrados.

Si las barandas frenan un comando que la persona sí pidió, lo corre ella misma en pi con `!<comando>`: los comandos de shell propios del usuario no pasan por las barandas del agente.

## Tests

```bash
node --test packages/pi/test/*.test.ts
```

Corren las extensiones con un `pi` falso contra los scripts, skills y definiciones de agentes reales de este repo; los subagentes corren `test/fake-pi.mjs` en lugar del pi hijo (Node 23.6 o más nuevo, que corre TypeScript tal cual).
