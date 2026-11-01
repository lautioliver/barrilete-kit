# barrilete-pi

Barrilete Kit para [pi](https://github.com/badlogic/pi-mono): el mismo flujo que en Claude Code (planear, implementar, revisar, con los nudos humanos), sin depender de Claude Code. No copia el kit: reusa `.claude/skills/` y `scripts/agents/` del proyecto, así un proyecto funciona igual en cualquiera de los dos harness.

## Qué trae

| Pieza del kit | En pi |
|---|---|
| Skills (`.claude/skills/`) | Se suman al descubrimiento de pi: aparecen en el system prompt y como `/skill:<nombre>`. |
| `/plan-feature`, `/implement-issue <n>`, `/review-pr <n>`, `/project-status`, `/improve-skills`, `/add-member`, `/remove-member` | Comandos con el mismo nombre. Cada uno carga el `SKILL.md` entero en el mensaje. |
| Barandas (`scripts/agents/guardrails.py`) | Cada comando bash del agente pasa por el mismo script antes de correr; si lo bloquea, pi no lo ejecuta y el agente lee por qué. |
| Línea del flujo (`scripts/agents/flow.py`) | En el footer de pi, actualizada al empezar la sesión y cuando el agente termina. |

Todo se prende solo dentro de un proyecto Barrilete (un repo git con `scripts/agents/guardrails.py`); en cualquier otra carpeta el paquete no hace nada.

Todavía no: `/orchestrate` y los subagentes (pi no tiene subagentes propios; son la fase siguiente), así que la skill `orchestrate` queda fuera del descubrimiento.

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

Si las barandas frenan un comando que la persona sí pidió, lo corre ella misma en pi con `!<comando>`: los comandos de shell propios del usuario no pasan por las barandas del agente.

## Tests

```bash
node --test packages/pi/test/*.test.ts
```

Corren las extensiones con un `pi` falso contra los scripts y skills reales de este repo (Node 23.6 o más nuevo, que corre TypeScript tal cual).
