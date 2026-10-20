# Línea del flujo en la terminal

> `scripts/agents/flow.py` imprime, en una línea, en qué paso del flujo está la rama actual. No depende del agente: cualquier harness o ADE que pueda mostrar una línea de texto la puede mostrar.

```
plan ● ─ implement ─ ▸review ─ ● merge   #176 · PR #179 in review
```

Los dos ● son los nudos que quedan en manos de las personas: aprobar el plan y mergear. El paso sale de lo que ya existe, nadie lo escribe a mano:

| Qué hay | Paso |
|---|---|
| Una rama `<tipo>/<n>-…` (también `claude/<n>-…`) sin PR abierto, o con el PR en draft | implement |
| Un PR abierto de la rama | review |
| El PR aprobado (la review obligatoria o, si el repo no la pide, una aprobación sin cambios pedidos) | ● merge (esperando tu merge) |
| El PR mergeado | retro |
| El issue con `status:blocked` | ✖ blocked, sea cual sea el paso |
| Una rama troncal o sin número de issue | ningún paso marcado |

`/plan-feature` no deja rastro en git, así que el nudo del plan nunca es el paso actual. Lo que le pregunta a GitHub (`gh`) queda 30 segundos en caché en el directorio de git. Pasado ese tiempo, la línea sigue mostrando lo que tenía mientras un proceso de fondo lo refresca, así ningún prompt espera a la red. Sin `gh` o sin red, muestra lo que sabe git.

## Dónde mostrarla

| Dónde | Cómo | Qué usa |
|---|---|---|
| Claude Code | status line nativa | `--statusline` |
| GitHub Copilot CLI | su status line (experimental, detrás de un feature flag: revisá su documentación) | `--statusline` |
| Codex CLI, o cualquier agente en una terminal | barra de tmux o el prompt de la shell | `--format tmux` / `zsh` / `bash` |
| Cursor, VS Code, Windsurf, cualquier ADE | un panel de terminal que se redibuja solo | `--watch` |
| Una extensión o un dashboard | la dibuja a su manera | `--format json` |

La status line de Codex CLI solo acepta sus ítems propios, no un comando, así que ahí el camino es tmux o el prompt.

### Claude Code

`init-template.sh` pregunta si activarla cuando corre en una terminal; `--flow-line` o `--no-flow-line` contestan de antemano. La elección queda como `flow_line` en `.agent-kit.json`, y `update.py` y `grow.py` la mantienen. Para activarla después, a mano, en `.claude/settings.json` (compartido) o `.claude/settings.local.json` (solo vos):

```json
{
  "statusLine": {
    "type": "command",
    "command": "f=\"$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py\"; [ -f \"$f\" ] && exec python3 \"$f\" --statusline"
  }
}
```

### Prompt de la shell

```zsh
# ~/.zshrc
setopt prompt_subst
RPROMPT='$(f="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py"; [ -f "$f" ] && python3 "$f" --format zsh)'
```

```bash
# ~/.bashrc
flow_line() { local f; f="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py"; [ -f "$f" ] && python3 "$f" --format bash; }
PS1='$(flow_line)\n\w \$ '
```

Los formatos `zsh` y `bash` envuelven los colores para que la shell no los cuente como ancho y el cursor no se corra.

### tmux

tmux corta `#(…)` en el primer `)`, por eso la ruta va entre backticks y no con `$(…)`.

```tmux
# ~/.tmux.conf
set -g status-interval 5
set -g status-right-length 120
set -g status-right '#(cd "#{pane_current_path}" && f="`git rev-parse --show-toplevel 2>/dev/null`/scripts/agents/flow.py" && [ -f "$f" ] && python3 "$f" --format tmux)'
```

### Un panel en cualquier ADE

```bash
python3 scripts/agents/flow.py --watch      # se redibuja cada 5 s; --watch 2 para cada 2 s
```

### JSON

```bash
python3 scripts/agents/flow.py --format json
# {"brand": false, "branch": "claude/176-…", "issue": 176, "pr": 179, "step": "review", "note": null, "face": "working", "steps": [...], "text": "…"}
```

`step` es `implement`, `review`, `merge`, `retro`, `blocked` o `null`; `note` aclara un `implement`: `draft`, `closed` (PR cerrado sin merge) u `offline` (gh no contestó). Fuera de un repo de git imprime `null`.

## Colores

Tonos de la paleta del kit que se leen en terminal oscura y clara (contraste de al menos 3:1 en las dos; el ámbar y el azul de la marca no se leen sobre blanco, ni su gris sobre negro): ámbar para los nudos, azul para el paso actual, gris para el resto y rojo para blocked. `NO_COLOR=1` o `--format plain` los apaga. Lo demás es de la marca: ver [Las caritas de Barrilete](#las-caritas-de-barrilete).

## Las caritas de Barrilete

En el repo de la plantilla (con `.github/brand/`) la línea empieza con la carita de Barrilete del paso, los estados de `.github/brand/states/`, y `--watch` la dibuja grande al lado de lo que significa. `init-template.sh` borra esa carpeta, así que un proyecto muestra la línea sin caritas, como el resto de la marca.

| Carita | Estado | Paso |
|---|---|---|
| `(● ●)` | working | implement, review, retro |
| `(• • •)` | planning | ningún paso (rama troncal) |
| `(✕ ✕)` | blocked | blocked |
| `(^ ^)` | PR ready, boca ámbar | ● merge |

```
━━━┳━━     ━━┳━━━
 ╭─┸─────────┸─╮
 │ ┌─────────┐ │
 │ │  ^   ^  │ │   PR ready
 │ └─────────┘ │   claude/42-validar-qr
 ╰─────▆▆▆─────╯

plan ● ─ implement ─ review ─ ▸● merge   #42 · PR #50 waiting for your merge
```

`flow.py --face working|planning|blocked|ready` imprime la carita grande sola; el init la usa para despedirse. El JSON trae `face` para que una extensión la dibuje a su manera.

## Tests

`python3 -m unittest scripts/agents/test_flow.py` (corre con `verify.py` cuando cambia `flow.py`). Los casos de punta a punta usan un repo de git de verdad y un `gh` falso en el `PATH`.
