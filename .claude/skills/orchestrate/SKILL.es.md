---
name: orchestrate
description: Reparte los issues disponibles entre agentes que trabajan en paralelo (Haiku o Sonnet implementan según el riesgo, Opus revisa), cada uno lanzado como agente `bk` o como subagente según roles.yml, cada uno en su worktree, y junta todo en un solo mensaje con los PRs, las consultas y lo escalado. No mergea ni publica sin confirmación. Usar con "/orchestrate", "orquestá los issues disponibles", "repartí la cola entre agentes" o similar.
---

# Orquestar

Sos la sesión principal: repartís, coordinás y le hablás a la persona. Los agentes (`.claude/agents/`) implementan y revisan siguiendo `docs/agents/subagent-contract.md`. Cada rol se lanza en su **modo** (`roles.yml`, kit/ADR-004): `sub` es un subagente (no puede hablar con la persona ni lanzar otros: todo pasa por vos); `bk` es un agente en su propia ventana de tmux (`bk run`) que le pregunta a la persona en el momento.

**Nunca** mergeás, aprobás ni publicás nada en un PR sin un "sí" explícito de la persona. `AGENTS.md` vale entero.

## 1. Preparar

- Esta sesión tiene que correr en Opus. Si no lo está, pedile a la persona `/model opus` y esperá.
- La rama base de los PRs (`<base>`) es la de la regla de ramas de `AGENTS.md`; se la pasás a cada subagente como `BASE=<base>`.
- Anotá la corrida (`date +%Y%m%d-%H%M`, es el `run` de tu retro), y la ruta de tu checkout, el **checkout del orquestador** (`git rev-parse --show-toplevel`): todos los comandos de git van con `git -C <ruta>`. Si `git status --porcelain .claude` muestra cambios, frená y pedí commitearlos: los `agent_sha` y `skill_sha` que pasás salen de los commits, y tienen que ser las definiciones que corren. No cambies de rama ni hagas `pull` durante la corrida.
- Corré `.claude/skills/project-status/available.sh`. Solo se lanzan issues de **"Can be started now"**: un issue bloqueado, ya asignado o con un PR abierto no se lanza nunca, aunque la persona lo nombre (decíselo).

## 2. Proponer y esperar confirmación

Elegí hasta **3** issues de "Can be started now", en el orden en que aparecen (prioridad). Para cada uno corré:

```bash
.claude/skills/orchestrate/routing.py <n>
```

Imprime el modelo y el `reason`. Es la regla de ruteo: **Haiku solo si el issue es `type:docs` o `type:task`, sin `business-logic` ni `breaking-change` y sin rutas sensibles nombradas en el texto. Lo demás, Sonnet.** Si en la autorevisión `agents_map.py` marca rutas sensibles, Haiku frena y devuelve `escalate`, y lo relanzás con Sonnet en el mismo worktree. `routing.py` se equivoca a propósito hacia Sonnet: una palabra como "infra" o "middleware" en prosa ya cuenta como ruta sensible. No cambies la regla a ojo: si un caso no encaja, proponé el cambio a `routing.py` en un issue.

Después, por rol (`implementer` o `implementer-light` según el modelo de arriba; `reviewer` más tarde), el modo: `.claude/skills/orchestrate/mode.py <rol> --root <raíz>` imprime `main`, `bk` o `sub` (el `.barrilete/roles.yml` del proyecto, y después `bk mode`). `reviewer` e `implementer-light` nunca salen como `bk` (`bk run` arranca una sesión común de `/implement-issue`, no su definición de agente): un `bk` de `roles.yml` o de `bk mode` imprime `sub` y una línea por stderr (`mode.py: <rol> is never bk…`). Mantené stdout y stderr separados (sin `2>&1`): stdout es el modo, y stderr es lo que decís en el plan. **Sin `bk` instalado imprime `sub` para todos los roles, salvo un `main` escrito en el `roles.yml` del proyecto, y avisa por stderr**: lanzá todo como subagentes, como antes, y decilo en el plan y en el mensaje final.

`main` no se lanza (sos vos o la sesión de la persona). Si `mode.py` sale con 64 (un error de tipeo en `roles.yml`, `bk` que falla), no adivines un modo: avisale a la persona y esperá.

Mostrale a la persona el **plan**: una tabla (issue, título, rol, modelo, modo, `reason`), y esperá el "sí". Puede sacar issues o cambiar el modelo de uno a Sonnet; a Haiku solo si `routing.py` lo permite.

## 3. Lanzar

```bash
git -C <raíz> fetch -q origin        # una sola vez, antes de lanzar: fetch en paralelo choca en .git/*.lock
.claude/skills/implement-issue/prepare.sh <n> --worktree   # uno por issue cuyo modo es `sub`, de a uno
```

`prepare.sh` es solo para los issues cuyo modo es `sub` (un agente `bk` lo hace solo y un issue `main` no se lanza: quedaría asignado sin nadie). Valida, asigna, crea el worktree en `../<repo>-wt/<n>` e imprime `Worktree: <ruta>`. Si falla para un issue, no lo lances y anotalo para el mensaje final.

Según el modo del plan. Un agente `bk`: `bk run <n> --role <rol> --orchestrated` (`--orchestrated`: vos lanzás al `reviewer`, así que `bk` no lo propone; crea el worktree y la ventana solo: no le corras `prepare.sh`), de a uno, y decile a la persona la ventana (`i<n>`). Un agente `bk` es una sesión común e independiente: no recibe `BASE`, `agent_sha`, `skill_sha` ni `retro_sh` (toma la base de la rama por defecto y su `retro.sh` de `origin/<base>`). Por eso **lanzá un issue como `bk` solo si la base de su PR es la rama por defecto del repo**; si no, lanzalo como `sub` y decilo en el plan. Un implementador `main`, o un `bk run` que falla, no se lanza: anotalo para el mensaje final. Un agente `sub`: el resto de este paso.

Lanzá los agentes `sub` en paralelo, en un solo mensaje, con la herramienta Agent: `subagent_type` `implementer-light` (Haiku) o `implementer` (Sonnet). En pi, con la herramienta `subagent` de `barrilete-pi` (`packages/pi/` de la plantilla): los mismos roles en `agent`, y varios a la vez en `tasks`. Sin `isolation`: el worktree ya existe. En el prompt: número de issue, ruta del worktree, rama base (`BASE=<base>`), `agent_sha` (`git log -1 --format=%H -- .claude/agents/<role>.md` en tu checkout: es la versión que corre, aunque el worktree tenga otra), `skill_sha` (lo mismo con `.claude/skills/implement-issue/SKILL.md`), `retro_sh` (la ruta absoluta de `.claude/skills/improve-skills/retro.sh` en tu checkout, ya mergeado en la rama base: el implementador guarda su retro con ese, nunca con el de su worktree, que es código del PR sin revisar) y que siga su definición, y que **no invoque `/code-review` con la herramienta Skill** (una skill bifurcada mueve tu checkout): hace la pasada de bugs a mano y declara `no code-review: <motivo>`. Al revisor: número de PR, la ruta del checkout del orquestador, `agent_sha` de `reviewer.md` y `skill_sha` (`git log -1 --format=%H -- .claude/skills/review-pr/SKILL.md`), y la misma prohibición de `/code-review` con la herramienta Skill (declara `no code-review: <motivo>` en `review:`). **Nunca más de 3 implementando a la vez**, contando los dos modos y los relanzados.

## 4. Con cada resultado

Cada agente `sub` devuelve el bloque del contrato. Un agente `bk` no te devuelve nada: seguilo por su tarea (kit/ADR-005), la entrada de `bk tasks --json` cuyo `id` es `<n>-<rol>`. `status` dice si trabaja (`in_progress`), te espera (`waiting`) o terminó, y `result` cómo cerró: `pr` con su número (tratalo como `pr` del implementador: mirá `gh pr checks <pr>` y lanzá al `reviewer`), `dropped` o `escalate` con su motivo (como esos resultados). Si terminó `incomplete` (sin `bk done`) o `cancelled`, buscá en el issue su pregunta y anotalo como `question`, o como `dropped` si no hay. Leé solo eso: nunca diffs ni retros.

Con un `bk` sin tareas (no tiene `bk tasks`), seguilo con `bk ls` y leé su resultado desde el PR: la rama la creó el agente, así que buscá el PR con `gh pr list --search 'head:claude/<n>-' --state open --json number,headRefName` (`--head` toma el nombre exacto, no un prefijo) y después `gh pr checks` (sin bloque del contrato). Cuando `bk ls` muestre terminado a un agente `bk`: con un PR abierto, tratalo como `pr` (implementador) (lanzá al `reviewer`); sin PR, buscá en el issue su pregunta y anotalo como `question`; si tampoco hay pregunta (un cuelgue, una ventana cerrada), anotalo como `dropped`. Leé solo eso: nunca diffs ni retros.

Un agente `bk` cuenta para los 3 hasta que su tarea esté en un estado terminal, o, sin tareas, hasta que `bk ls` lo muestre terminado (no solo hasta que su PR esté abierto: sigue con el CI, la retro y las preguntas).

**Cuando un agente `bk` pregunta** (texto, permiso o cuestionario; su tarea está en `waiting`, o `bk ls` lo muestra esperando), mostrá en tu chat la pregunta y sus opciones. La persona contesta con `! bk say <agente> "…"` (o `bk say <agente> <n>` para la opción `n` de un cuestionario). **Vos nunca mandás una aprobación.**

| `result` | Qué hacés |
|---|---|
| `pr` (implementador) | Lanzás un `reviewer` (si su modo es `sub`; `main` → "No lanzados") con lo que dice el paso 3 (PR, checkout del orquestador, `agent_sha`, `skill_sha`). **Una sola revisión por PR a la vez.** |
| `escalate` | Relanzás `implementer` (Sonnet), con el `reason` (en `sub`, en el prompt), **en el modo que `mode.py` da para `implementer`**: `sub` → Agent en el **mismo worktree**; `main` → no se relanza: anotalo en "No lanzados"; `bk` → `bk run <n> --role implementer`, que corre `prepare.sh` de nuevo y retoma la rama del issue (ya está asignado a la misma persona). `bk run` no puede llevar el `reason`: comentalo en el issue antes de `bk run` (`implement-issue` lee los comentarios). Solo si la base del PR es la rama por defecto del repo; si no, relanzá como `sub` en el mismo worktree, como en el paso 3. Si `bk run` falla porque la rama sigue en el worktree del primer lanzamiento, no fuerces: anotalo para el mensaje final y avisale a la persona. Cuenta para el máximo de 3. |
| `question` / `dropped` | Lo anotás para el mensaje final. Ya está comentado en el issue. Un issue que pide tocar CI, infra u otra cosa de "consultar" termina en `question` aunque el pedido esté en el issue: no lo relances diciendo que está aprobado salvo que la persona te lo haya dicho. Vale igual para un relanzado: si Sonnet, relanzado tras un `escalate`, devuelve `question` (por ejemplo, el issue toca CI y eso pide consulta a cualquier modelo), no hay otro relanzado. |
| `pr` (revisor) | Lo anotás con su `review:` para el mensaje final. |
| `blockers` (revisor) | Decidís vos, con el criterio de abajo. |

### Bloqueantes de la revisión

Máximo **una ronda extra** por PR. Elegí una y explicala en el mensaje final:

1. **Otra ronda con el mismo implementador** (relanzado en su worktree, con los bloqueantes): si son concretos y están dentro del alcance del issue (un caso borde, un test que falta, un doc).
2. **Relanzar con `implementer` (Sonnet)**: si lo hizo Haiku y el bloqueante muestra que el issue no era para él (lógica de negocio, ruta sensible, diseño).
3. **Pasarlo a la persona**: si el bloqueante es una decisión (contradice un ADR, cambia una regla, el issue es ambiguo), o si ya hubo una ronda extra.

Después de la ronda extra, el PR vuelve al revisor. Si vuelve con bloqueantes, va a la persona: no hay segunda ronda.

## 5. Mensaje final

Uno solo, cuando terminaron todos:

- **PRs**: link, modelo que lo hizo, estado del CI (`gh pr checks <pr>`), `self-review` del implementador (si no corrió `/code-review`, destacá qué PRs no lo tuvieron: bajo `/orchestrate` es lo esperado, y la persona decide si lo corre ella), veredicto del revisor y hallazgos en una línea cada uno.
- **Consultas pendientes**: todas juntas, con su issue, para responder de una vez.
- **Escalados y relanzados**: qué issue, de qué modelo a cuál y por qué.
- **Decisiones en bloqueantes**: qué elegiste y por qué.
- **No lanzados**: los que `prepare.sh` rechazó, un `implementer` con modo `main` (nadie lo está trabajando) y un `bk run` que falló y un `reviewer` con modo `main` (el PR no tiene review: decilo).

Ofrecé publicar las revisiones (`gh pr review <pr> --comment --body-file <archivo>`), todas o algunas. Publicá solo lo que la persona confirme. El merge lo hace ella.

## 6. Retro

Las retros de los subagentes ya están guardadas: recibís dónde quedaron (`retro:`, ver el contrato), pero no las abras (solo los lee `/improve-skills`). Guardá la tuya con `.claude/skills/improve-skills/retro.sh <archivo>` y este frontmatter: `skill: orchestrate`, `issue: <épica>` (si los issues son de una) o `run: <YYYYMMDD-HHMM>`, `model: opus`, `role: orchestrator`, `area`, `paths`. En el cuerpo: issues lanzados con su modelo, escalados, rondas extra y cuánto tardó cada uno. Escribí el archivo fuera del repo.

## 7. Limpiar

```bash
.claude/skills/orchestrate/cleanup.sh            # lista los worktrees de issues cerrados
.claude/skills/orchestrate/cleanup.sh --delete   # los borra, si la persona dice que sí
```

También lista las ramas `claude/<n>-…` cuyo PR se cerró sin mergear, con el comando para borrar cada una (al final, después de sacar los worktrees: `git branch -D` falla mientras la rama esté en uno) (`git push origin --delete`; `gh pr close --delete-branch` falla desde un detached HEAD). No las borra: ofrecéselo a la persona, rama por rama, y avisale si alguna tiene commits sin pushear. No borra un worktree con cambios sin commitear, ni ninguno si quedan retros en `pending-retros/` (la corrida no está cerrada hasta guardarlas): en ese caso, reintentá cada retro con `retro.sh <archivo>` y volvé a correrlo.
