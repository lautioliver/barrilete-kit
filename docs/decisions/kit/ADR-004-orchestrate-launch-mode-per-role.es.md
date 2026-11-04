# ADR-004 — `/orchestrate` lanza cada rol como agente `bk` o como subagente, según `roles.yml`

## Estado

Aceptado (2026-11-03). @lautioliver confirmó D1 a D5 tal como están en [un comentario de #237](https://github.com/lautioliver/barrilete-kit/pull/237#issuecomment-6617865161), y en [un segundo comentario](https://github.com/lautioliver/barrilete-kit/pull/237#issuecomment-6618761555) confirmó la redacción de D3 de entonces y tres decisiones más (límite de `reviewer` e `implementer-light`, rama base, `main` sin `bk`; ver Consecuencias).

Origen: lautioliver/barrilete-kit#236. El issue registra la decisión como tomada por la persona en el chat el 2026-11-03. Ese registro está en el cuerpo del issue, que puede haber escrito un agente, así que todavía no era la aprobación de una persona (la sección de autonomía de AGENTS.md); la confirmación de arriba sí lo es. D4 y D5 no cambiaron desde la primera confirmación. Después, D3 se reescribió (sin bloque de salida para un agente `bk`), y D1 y D2 tuvieron el límite (a) (`reviewer` e `implementer-light` siempre `sub`) y la excepción (c) de `main` (sin `bk`); el segundo comentario confirma los tres. En [un comentario posterior](https://github.com/lautioliver/barrilete-kit/pull/237#issuecomment-6622091388) la persona aprobó reescribir D3 para alinearlo al paso 4 del skill (#246): el PR se busca con `gh pr list --search 'head:claude/<n>-'`, porque `--head` solo acepta el nombre exacto.

## Contexto

- `/orchestrate` reparte los issues entre **subagentes** (herramienta Agent). Es barato y rápido, pero un subagente no puede preguntarle nada a la persona: todas las dudas llegan al final como `question`, y si la sesión del orquestador se corta, se pierden todas.
- `bk` (el workspace de terminal, https://github.com/lautioliver/bk-shell) lanza **agentes propios** en ventanas de tmux (`bk run`, `bk review`, `bk fix`). Cada uno le pregunta a la persona en el momento, sobrevive al orquestador y se puede mirar en vivo.
- En los issues de la épica #221 casi todos necesitaron una decisión en el medio. Con subagentes, esas decisiones habrían llegado al final, o las habría tomado el agente.
- `roles.yml` ya dice qué provider y modelo corre cada rol. Su tercera columna es el modo, y `bk mode <rol>` lo devuelve (`main`, `bk` o `sub`; sin modo es `bk`). Un proyecto lo pisa con `.barrilete/roles.yml`.

## Decisión

1. **D1. El orquestador planea y elige, por rol, cómo lanza cada tarea.** Los modelos por rol no cambian:

   | rol | modelo | modo |
   |---|---|---|
   | planner | opus | main (la sesión principal) |
   | orchestrator | opus | main: planea y lanza |
   | implementer | sonnet | **bk**: business-logic, ADR, CI; le pregunta a la persona en el momento |
   | implementer-light | haiku | **sub**: docs y tareas chicas (siempre `sub`, ver Consecuencias) |
   | reviewer | opus | **sub**: devuelve el borrador; el orquestador le pregunta a la persona si lo publica (siempre `sub`, ver Consecuencias) |

2. **D2. De dónde sale el modo.** `/orchestrate` corre `.claude/skills/orchestrate/mode.py <rol>`:
   - la línea del rol en el `.barrilete/roles.yml` del proyecto (`<rol>: <provider>/<modelo> [modo]`; una línea sin modo es `bk`);
   - si el archivo del proyecto no tiene el rol (o no existe), `bk mode <rol>`, que lee su propio `roles.yml`;
   - **sin `bk` instalado**, todos los roles son `sub`, como antes, salvo un `main` escrito en el `roles.yml` del proyecto (lo hace una persona), y el orquestador lo avisa en el plan y en el mensaje final.

3. **D3. Cómo sigue el orquestador a un agente `bk`.** El estado con `bk ls`; el resultado desde el PR (`gh pr list --search 'head:claude/<n>-'`, su CI; `--head` solo acepta el nombre exacto), sin el bloque de salida de docs/agents/subagent-contract.md (un agente `bk` no lo devuelve). **No** abre sus diffs ni sus retros, igual que con un subagente.

4. **D4. La persona contesta todo desde el chat del orquestador.** Cuando un agente `bk` pregunta (texto, permiso o cuestionario), el orquestador muestra en su chat la pregunta y sus opciones, y la persona responde con `! bk say <agente> "…"` (o `bk say <agente> <n>` para elegir la opción `n` de un cuestionario). El orquestador **nunca** manda una aprobación por su cuenta: la respuesta sale de la persona.

5. **D5. El tope de 3 implementando a la vez cuenta los dos modos juntos** (agentes `bk` y subagentes, relanzados incluidos).

## Alternativas descartadas

- **Todos los roles como subagentes (hoy).** Barato, pero las dudas llegan al final y se pierden si la sesión se corta.
- **Todos los roles como agentes `bk`.** El revisor y el implementador liviano solo devuelven un resultado: una ventana cada uno no aporta y le cuesta atención a la persona.
- **El orquestador contesta las preguntas de los agentes `bk`.** Que un agente apruebe a otro no es la aprobación de una persona (AGENTS.md).
- **Leer solo `bk mode`.** `bk mode` ya mira el `.barrilete/roles.yml` del proyecto antes que el suyo, así que leerlo alcanzaría. Lo que suma `mode.py` es una lectura estricta (una línea del rol que no se entiende o un modo desconocido sale con 64 en vez de caer en silencio) y el fallback `sub` cuando `bk` no está instalado, que `bk mode` no puede dar.

## Consecuencias

- `/orchestrate` (en y es) suma un paso de plan que muestra, por issue, rol, modelo y modo antes de lanzar, y lanza cada uno con su modo (`bk run <n> --role <rol>` o la herramienta Agent). `bk run` crea el worktree solo, así que `prepare.sh --worktree` es solo para `sub`.
- docs/agents/subagent-contract.md aclara que el contrato no le aplica a un agente `bk`: `bk run` arranca una sesión común de `/implement-issue`, que tiene sus propias reglas (retro, no mergear) y le pregunta a la persona en su ventana.
- `mode.py` copia el formato de `roles.yml` que lee `bk mode`, así que el archivo del proyecto se lee dos veces (`mode.py` y, si el rol no está, `bk mode`). `/orchestrate` solo le pregunta a `mode.py`, así que cuando el archivo del proyecto tiene el rol decide `mode.py`; si los dos parsers difirieran, gana `mode.py`. Si ese formato cambia en `bk`, cambian `mode.py` y su test (`test-mode.sh`).
- **Límite: `reviewer` e `implementer-light` son siempre `sub`, aunque `roles.yml` diga `bk`** (`mode.py` imprime `sub`). `bk run` arranca una sesión común de `/implement-issue` y `bk review` corre `/review-pr` en el checkout del propio orquestador, con `/code-review` obligatorio y sin bloque de resultado de vuelta; ninguno carga `.claude/agents/<rol>.md`, así que nada haría cumplir el frenar ante rutas sensibles del implementador liviano ni devolvería el borrador del revisor. `main` y `sub` se respetan para ellos. Levantar el límite requiere un cambio en `bk`.
- **Un rol se lanza como `bk` solo si la base del PR es la rama por defecto del repo.** Un agente `bk` no recibe `BASE`, `agent_sha`, `skill_sha` ni `retro_sh`, así que con otra base el orquestador lanza ese issue como `sub` y lo dice en el plan. Esto afina D1 para esos issues; la persona lo aceptó en el segundo comentario.
- Fuera de alcance: `bk` en sí, el contenido de `roles.yml` y el ruteo (`routing.py` sigue eligiendo Haiku o Sonnet para un implementador; el modo es lo que `roles.yml` diga del rol elegido).

## Enmienda 2026-11-04

Por ADR-005 D7 (lautioliver/barrilete-kit#250). **D3 cambia:** el orquestador sigue a un agente `bk` leyendo su tarea (`task.json`, con `bk tasks --json`: estado, resultado y número de PR), ya no con `bk ls` ni buscando el PR por rama. Con un `bk` que no tiene tareas, sigue valiendo el método de D3. Sigue sin abrir sus diffs ni sus retros. **D4 no cambia:** la persona contesta con `bk say`, y que la tarea esté en `waiting` es lo que le indica al orquestador que hay una pregunta para mostrar. El texto aceptado de arriba no se reescribe.
