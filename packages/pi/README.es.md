# barrilete-pi

Barrilete Kit para [pi](https://github.com/badlogic/pi-mono): el mismo flujo que en Claude Code (planear, implementar, revisar, con los nudos humanos), sin depender de Claude Code. No copia el kit: reusa `.claude/skills/`, `.claude/agents/` y `scripts/agents/` del proyecto, así un proyecto funciona igual en cualquiera de los dos harness.

## Qué trae

| Pieza del kit | En pi |
|---|---|
| Skills (`.claude/skills/`) | Se suman al descubrimiento de pi: aparecen en el system prompt y como `/skill:<nombre>`. |
| `/plan-feature`, `/implement-issue <n>`, `/review-pr <n>`, `/orchestrate`, `/project-status`, `/improve-skills`, `/add-member`, `/remove-member` | Comandos con el mismo nombre. Cada uno carga el `SKILL.md` entero en el mensaje. |
| Subagentes (`.claude/agents/`) para `/orchestrate` | La herramienta `subagent` corre `implementer`, `implementer-light` y `reviewer` como procesos de pi aparte, cada uno en su worktree, y devuelve su bloque del contrato. |
| Barandas (`scripts/agents/guardrails.py`) | Cada comando bash del agente pasa por el mismo script antes de correr; si lo bloquea, pi no lo ejecuta y el agente lee por qué. |
| Línea del flujo (`scripts/agents/flow.py`) | En el footer de pi, actualizada al empezar la sesión y cuando el agente termina. |
| Estado de los agentes | Con `BARRILETE_STATUS_HOOK`, cada sesión le informa su estado a un comando tuyo (una barra de estado, un notificador) en el JSON de los hooks de Claude Code. |

Todo se prende solo dentro de un proyecto Barrilete (un repo git con `scripts/agents/guardrails.py`); en cualquier otra carpeta el paquete no hace nada.

## Instalación

Necesita `python3` y, para las skills y la línea del flujo, `gh`. Con el comando `barrilete` (pi viene incluido si no lo tenés):

```bash
npm i -g barrilete-pi
barrilete doctor                 # revisa pi, python3, gh, el proyecto y el login
barrilete home import-pi         # opcional: reusar tu login de pi en el home propio de barrilete
```

O como paquete de tu pi, o desde un clon del kit:

```bash
pi install npm:barrilete-pi      # todos tus proyectos (~/.pi/agent/settings.json)
pi install -l npm:barrilete-pi   # solo este proyecto (.pi/settings.json)
pi -e ./packages/pi              # desde un clon, una sesión sin instalar
```

Después abrilo en la raíz del proyecto y escribí `/plan-feature <idea>`.

## El comando barrilete

`barrilete` abre pi con este paquete cargado, sin instalarlo en tu pi ni editar su configuración. Por defecto usa un home propio, `~/.barrilete/agent` (`BARRILETE_HOME` lo mueve): su login, configuración y sesiones nunca tocan tu instalación de pi. El resto de las opciones le llegan a pi tal cual.

| Comando | Qué hace |
|---|---|
| `barrilete [opciones de pi]` | pi con barrilete-pi, en el home propio. |
| `barrilete --link [opciones de pi]` | Lo mismo, en tu home de pi (`~/.pi/agent`, o `PI_CODING_AGENT_DIR`): tu login, modelos y sesiones. |
| `barrilete home import-pi [--dry-run]` | Copia tu login de pi (`auth.json`, `0600`) y el modelo por defecto al home propio. Nunca sobrescribe, y no copia paquetes, extensiones ni sesiones. |
| `barrilete doctor` | Revisa pi, `python3`, `gh`, el proyecto, el login y el hook de estado. |

Con `import-pi` quedan dos copias del login: un proveedor que rota los refresh tokens puede cerrar la sesión de una de ellas. `--link` comparte una sola.

Usa el `pi` de tu PATH; si no hay, el que npm instaló junto al paquete.

## Estado de los agentes

Poné en `BARRILETE_STATUS_HOOK` un comando y cada sesión de pi le manda, por stdin, el mismo JSON que mandan los hooks de Claude Code (`session_id`, `hook_event_name`, `cwd`, `tool_name`): un script escrito para los hooks de Claude Code funciona tal cual.

| pi | Evento |
|---|---|
| Empieza / termina la sesión | `SessionStart` / `SessionEnd` |
| Llega un prompt | `UserPromptSubmit` |
| Corre una herramienta | `PreToolUse`, después `PostToolUse` (`PostToolUseFailure` si falló) |
| La herramienta `subagent` | `SubagentStart` y `SubagentStop`, uno por subagente |
| El agente termina | `Stop` (`StopFailure` si el modelo terminó en error) |

Las llamadas van en orden, una detrás de otra, así un evento atrasado nunca pisa el estado final. Un subagente no se informa a sí mismo: lo cuenta su orquestador. Por ejemplo, para ver los agentes de pi en un SketchyBar que ya escucha a Claude Code:

```bash
export BARRILETE_STATUS_HOOK="$HOME/.config/sketchybar/plugins/agent_hook.sh"
```

## Cómo funciona

- `extensions/skills.ts`: `resources_discover` devuelve las carpetas de skills del proyecto, y cada comando arma el mismo bloque `<skill>` que pi arma para `/skill:<nombre>`.
- `extensions/guardrails.ts`: en `tool_call` de `bash`, le manda a `guardrails.py` el JSON del hook de Claude Code y bloquea si sale con 2. Como los otros hooks, si falla deja pasar: es una baranda, la traba es la protección de ramas.
- `extensions/flow.ts`: `flow.py --format plain` en `ctx.ui.setStatus`.
- `extensions/subagents.ts` y `lib/subagents.ts`: la herramienta `subagent`. Lee el rol de `.claude/agents/<rol>.md` (la misma definición que corre Claude Code) y lanza `pi --mode json -p` en el worktree con el modelo y las herramientas del rol, traducidos (`Read` → `read`, `Glob` → `find`, `ls`; `Skill` no tiene equivalente), más notas sobre lo que cambia en pi (no hay `/code-review`, así que declara `no code-review`).
- `extensions/status.ts` y `lib/status.ts`: el estado de los agentes.
- `bin/barrilete.mjs`: el comando.

Si las barandas frenan un comando que la persona sí pidió, lo corre ella misma en pi con `!<comando>`: los comandos de shell propios del usuario no pasan por las barandas del agente.

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

## Tests

```bash
node --test packages/pi/test/*.test.ts
```

Corren las extensiones con un `pi` falso contra los scripts, skills y definiciones de agentes reales de este repo; los subagentes corren `test/fake-pi.mjs` en lugar del pi hijo, y el comando un `pi` falso en el PATH con `HOME` en una carpeta temporal (Node 23.6 o más nuevo, que corre TypeScript tal cual).

## Publicar

Publica una persona, después del merge, desde `packages/pi` en la rama base: subí `version` en `package.json`, revisá el contenido con `npm pack --dry-run` y corré `npm publish`. El paquete no tiene scope y es público.
