# ADR-005 — Tareas y eventos para los agentes `bk`

## Estado

Aceptado (2026-11-04). @lautioliver lo aprobó en el chat el 2026-11-04, D1 a D9 tal como están en 0e1a7ca, sin cambios.

Origen: lautioliver/barrilete-kit#244. Decidido por @lautioliver en el chat (2026-11-04): el contrato vive en el kit y la implementación en `bk` (D1), el agente declara el cierre con `bk done` (D4), el traspaso a review se propone y no arranca solo (D6), y el plugin de barandas queda fuera (ver Alternativas). Decidido por @lautioliver en el chat, en la misma fecha, sobre las preguntas abiertas del borrador: `bk say` a una tarea ocupada se encola (D8), PostToolUse registra solo git y gh (D5), las tareas no se borran solas y su ubicación es conocida (D9), y Codex queda como pregunta abierta. El resto (ids, campos, estados intermedios, tipos de evento, la relación con ADR-004) son refinamientos que escribió un agente y la persona no decidió por separado: se aprueban al aceptar este ADR o se cambian en la revisión de su PR.

## Contexto

- Un agente `bk` es una ventana de tmux. `bk` sabe qué hace capturando su pantalla (`bk peek`) o leyendo sus transcripts; `/orchestrate` sigue su estado con `bk ls` y su resultado desde el PR (ADR-004, D3), y la persona le contesta escribiendo en su ventana (`bk say`, ADR-004 D4).
- Por eso el estado se adivina: un agente que espera a la persona y uno que trabaja se ven igual desde afuera. Un `bk run` repetido sobre el mismo issue lanza un segundo agente en el mismo worktree. Un agente que se cortó no deja dicho por qué, y el motivo de un bloqueo es prosa.
- El [Unified Harness Protocol](https://github.com/HarnessRouter/harnessrouter/tree/main/protocol) (UHP) resolvió el mismo problema para manejar harnesses por HTTP: la tarea es la unidad de trabajo, el ciclo de vida termina en un solo estado terminal, los eventos son hechos y no pantallas, los errores tienen código y hay una tarea por sesión a la vez. De UHP se toma el modelo, no el transporte.
- Los hooks del proyecto ya corren en cada sesión de Claude Code (`.claude/settings.json`) y de Codex (`.codex/hooks.json`), y un PreToolUse bloquea aun con `--dangerously-skip-permissions` (probado el 2026-11-04 en #244). Son el lugar donde emitir eventos sin depender de la pantalla.
- docs/agents/subagent-contract.md ya define un vocabulario de resultados (`pr`, `question`, `escalate`, `dropped`, `blockers`).

## Decisión

1. **D1. El contrato vive en el kit y lo implementa el orquestador.** Este ADR define los archivos y su formato, y el kit trae los hooks que escriben eventos. `bk` (u otro orquestador) crea las tareas, las lee y orquesta. El orquestador le pasa al agente la carpeta de su tarea en `BK_TASK_DIR`. **Sin `BK_TASK_DIR`, los hooks no escriben nada y salen con 0**, así que un proyecto sin `bk` funciona igual que hoy.

2. **D2. Una tarea por agente, con id estable.** El id es `<issue>-<rol>`, por ejemplo `244-implementer`, o `pr<n>-<rol>` cuando la tarea sale de un PR (`pr241-reviewer`). La carpeta de la tarea tiene `task.json` (el estado, la fuente de verdad) y `events.jsonl` (los hechos). **Lanzar una tarea cuyo id existe y no está en un estado terminal no lanza otro agente**: el orquestador devuelve la tarea que ya existe. Un worktree tiene una sola tarea activa a la vez.

3. **D3. Estados.**

   | estado | terminal | significa |
   |---|---|---|
   | `pending` | no | creada; espera que la persona la apruebe para arrancar (D6) |
   | `in_progress` | no | el agente trabaja |
   | `waiting` | no | el agente terminó su turno y espera a la persona (pregunta, permiso, cuestionario) |
   | `completed` | sí | el agente declaró un resultado (D4) |
   | `failed` | sí | el agente declaró que no puede seguir (D4) |
   | `incomplete` | sí | el agente terminó sin declarar el cierre; conviene retomarlo |
   | `cancelled` | sí | la persona lo paró (`bk stop`) |

   Un estado terminal no cambia nunca. `incomplete` no es `failed`: el primero suele valer la pena retomarlo y el segundo no. `cancelled` tampoco es `failed`: la persona pidió el corte, no hubo error. Lo que la tarea produjo antes de terminar se conserva.

4. **D4. El agente declara el cierre con `bk done`, con el vocabulario del contrato de subagentes.** `bk done pr <n>` y `bk done blockers` cierran en `completed`. `bk done dropped "<motivo>"` y `bk done escalate "<motivo>"` cierran en `failed`. `question` no cierra nada: un agente `bk` pregunta en su ventana, y eso es `waiting`. **El hook Stop no cierra la tarea**: en una sesión interactiva se dispara al final de cada turno, así que solo pasa la tarea a `waiting`. Si el proceso del agente termina sin `bk done`, el orquestador cierra la tarea en `incomplete`.

5. **D5. Eventos: un hecho por línea.** `events.jsonl` tiene una línea JSON por evento: `{"seq": n, "ts": "<ISO 8601>", "type": "<tipo>", …}`. `seq` empieza en 1 y crece sin huecos. El primer evento es `task.created`, y el último es el único evento terminal, que copia el `task.json` final. Tipos iniciales: `task.created`, `task.started`, `turn.waiting`, `commit` (`sha`), `pr.opened` (`pr`) y `task.completed`, `task.failed`, `task.incomplete`, `task.cancelled`. **El hook PostToolUse registra solo comandos `git` y `gh`**: los demás no generan eventos. El registro filtra en `sh` antes de arrancar Python, así que el resto de las llamadas a Bash no cargan su costo. **Un evento registra solo metadatos, nunca contenido**: ni argumentos, ni salida de herramientas, ni texto del modelo. `task.json` es la fuente de verdad, y `events.jsonl` sirve para seguir la tarea en vivo y entender después qué pasó.

6. **D6. El traspaso se propone y la persona lo aprueba.** Cuando una tarea cierra con `pr <n>`, el orquestador crea `pr<n>-reviewer` en `pending` y avisa. La tarea arranca recién cuando la persona la aprueba. El orquestador nunca aprueba por su cuenta, igual que en ADR-004 D4.

7. **D7. Cambia ADR-004 D3, no D4.** El orquestador sigue a un agente `bk` leyendo su `task.json`: estado, resultado y número de PR. Ya no usa `bk ls` ni busca el PR por rama. Sigue sin abrir sus diffs ni sus retros. D4 no cambia: la persona contesta con `bk say`, y `waiting` es lo que le dice al orquestador que hay una pregunta para mostrar. Cuando este ADR se acepte, ADR-004 suma una sección `## Enmienda` que remite a este D7.

8. **D8. `bk say` a una tarea ocupada se encola.** Si la tarea está en `in_progress`, el orquestador guarda el mensaje y lo escribe en la ventana cuando la tarea pasa a `waiting`. `bk say --now` lo escribe en el momento, por ejemplo para frenar al agente. En `waiting` el mensaje se escribe enseguida, como hoy.

9. **D9. Las tareas no se borran solas, y su ubicación es conocida.** Las tareas terminadas y sus eventos quedan hasta que la persona las borra (`bk tasks prune`). Para que siempre se sepa dónde están, la carpeta por defecto es `${XDG_STATE_HOME:-~/.local/state}/bk/tasks/<proyecto>/<id>/`, `task.json` guarda su propia ruta en `dir`, y `bk tasks` lista las tareas con su estado y su carpeta.

## Preguntas abiertas

Esta pregunta no está decidida y queda para el issue de implementación:

- **Codex**: su `hooks.json` acepta `PostToolUse` y `Stop` (los usa la config de Orca de la persona), pero no está probado que se disparen igual que en Claude Code. Se prueba cuando la persona instale `codex`; hasta entonces, el contrato aplica a Claude Code y Codex lo cumple solo si la prueba pasa.

## Alternativas descartadas

- **Seguir leyendo pantallas y transcripts.** Es el problema que motiva este ADR.
- **Adoptar UHP entero (HarnessRouter).** Hace falta un servidor y una clave de API, y no acepta la suscripción de Claude. Además, redirige `HOME`, así que el agente pierde `~/.claude` (las lecciones) y los hooks del repo, salvo que el repo esté en su carpeta de trabajo. Lo que sirve es el modelo. Por D1, otro orquestador, incluido uno UHP, puede implementar este contrato más adelante.
- **Que `bk` infiera el cierre** (hook Stop más el PR abierto): sigue adivinando. Decisión de la persona.
- **Traspaso automático al reviewer**: gasta tokens sin que la persona lo vea y encadena agentes sin pausa. Decisión de la persona.
- **Que los agentes se hablen directo** (estilo A2A): todo pasa por el orquestador y la persona, como en ADR-004.
- **Llevar las barandas a un plugin de Claude Code ahora**: se probó que funciona (#244), pero hoy solo hace falta con HarnessRouter y no cubre Codex. Queda pospuesto.

## Consecuencias

- Se gana: un estado confiable, sin lanzar dos agentes sobre el mismo issue, cierres con un motivo legible por máquina, traspasos explícitos y un contrato que sobrevive a un cambio de orquestador (herdr, UHP).
- Cuesta: un filtro en `sh` en cada llamada a Bash (D5), un paso más al final de `/implement-issue`, y una carpeta de tareas que crece hasta que la persona la limpia (D9).
- Issues que se abren al aceptarlo:
  - **bk-shell**: tareas en `bk run`, `bk review` y `bk fix` (D2, la idempotencia), `bk done` (D4), `incomplete` cuando el proceso termina, `pending` con aprobación (D6), la cola de `bk say` y `--now` (D8), `bk tasks` y `bk tasks prune` (D9), y que `bk ls`, el rail y la barra lean `task.json`.
  - **kit**: un hook nuevo en `scripts/agents/` que emite los eventos, registrado en `.claude/settings.json` y `.codex/hooks.json`. Tocar ese registro es tocar CI e infraestructura, y este ADR es la aprobación.
  - **kit**: `/implement-issue` y `/review-pr` (en y es) terminan con `bk done` cuando existe `BK_TASK_DIR`.
  - **kit**: la enmienda de ADR-004 (D7) y una nota en docs/agents/subagent-contract.md.
