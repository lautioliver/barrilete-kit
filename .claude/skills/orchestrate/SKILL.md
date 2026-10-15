---
name: orchestrate
description: Reparte los issues disponibles entre subagentes que trabajan en paralelo (Haiku o Sonnet implementan según el riesgo, Opus revisa), cada uno en su worktree, y junta todo en un solo mensaje con los PRs, las consultas y lo escalado. No mergea ni publica sin confirmación. Usar con "/orchestrate", "orquestá los issues disponibles", "repartí la cola entre agentes" o similar.
---

# Orquestar

Sos la sesión principal: repartís, coordinás y le hablás a la persona. Los subagentes (`.claude/agents/`) implementan y revisan siguiendo `docs/agents/subagent-contract.md`; no pueden lanzar otros subagentes ni hablar con la persona, así que todo pasa por vos.

**Nunca** mergeás, aprobás ni publicás nada en un PR sin un "sí" explícito de la persona. `AGENTS.md` vale entero.

## 1. Preparar

- Esta sesión tiene que correr en Opus. Si no lo está, pedile a la persona `/model opus` y esperá.
- La rama base de los PRs (`<base>`) es la de la regla de ramas de `AGENTS.md`; se la pasás a cada subagente como `BASE=<base>`.
- Anotá la corrida (el `run` de tu retro, `date +%Y%m%d-%H%M`) para tu retro, y la ruta de tu checkout, el **checkout del orquestador** (`git rev-parse --show-toplevel`): todos los comandos de git van con `git -C <ruta>`. Si `git status --porcelain .claude` muestra cambios, frená y pedí commitearlos: los `agent_sha` y `skill_sha` que pasás salen de los commits, y tienen que ser las definiciones que corren. No cambies de rama ni hagas `pull` durante la corrida.
- Corré `.claude/skills/project-status/available.sh`. Solo se lanzan issues de **"Can be started now"**: un issue bloqueado, ya asignado o con un PR abierto no se lanza nunca, aunque la persona lo nombre (decíselo).

## 2. Proponer y esperar confirmación

Elegí hasta **3** issues de "Can be started now", en el orden en que aparecen (prioridad). Para cada uno corré:

```bash
.claude/skills/orchestrate/routing.py <n>
```

Imprime el modelo y el `reason`. Es la regla de la épica #33, decisión 2: **Haiku solo si el issue es `type:docs` o `type:task`, sin `business-logic` ni `breaking-change` y sin rutas sensibles nombradas en el texto. Lo demás, Sonnet.** Si en la autorevisión `agents_map.py` marca rutas sensibles, Haiku frena y devuelve `escalate`, y lo relanzás con Sonnet en el mismo worktree. `routing.py` se equivoca a propósito hacia Sonnet: una palabra como "infra" o "middleware" en prosa ya cuenta como ruta sensible. No cambies la regla a ojo: si un caso no encaja, proponé el cambio a `routing.py` en un issue.

Mostrale a la persona una tabla (issue, título, modelo, reason) y esperá el "sí". Puede sacar issues o cambiar el modelo de uno a Sonnet; a Haiku solo si `routing.py` lo permite.

## 3. Lanzar

```bash
git -C <raíz> fetch -q origin        # una sola vez, antes de lanzar: fetch en paralelo choca en .git/*.lock
.claude/skills/implement-issue/prepare.sh <n> --worktree   # uno por issue, de a uno
```

`prepare.sh` valida, asigna, crea el worktree en `../<repo>-wt/<n>` e imprime `Worktree: <ruta>`. Si falla para un issue, no lo lances y anotalo para el mensaje final.

Lanzá los subagentes en paralelo, en un solo mensaje, con la herramienta Agent: `subagent_type` `implementer-light` (Haiku) o `implementer` (Sonnet). Sin `isolation`: el worktree ya existe. En el prompt: número de issue, ruta del worktree, rama base (`BASE=<base>`), `agent_sha` (`git log -1 --format=%H -- .claude/agents/<role>.md` en tu checkout: es la versión que corre, aunque el worktree tenga otra), `skill_sha` (lo mismo con `.claude/skills/implement-issue/SKILL.md`) y que siga su definición. Al revisor: número de PR, la ruta del checkout del orquestador, `agent_sha` de `reviewer.md` y `skill_sha` (`git log -1 --format=%H -- .claude/skills/review-pr/SKILL.md`). **Nunca más de 3 implementando a la vez**, contando los relanzados.

## 4. Con cada resultado

Cada subagente devuelve el bloque del contrato. Leé solo eso: nunca diffs ni retros.

| `result` | Qué hacés |
|---|---|
| `pr` (implementador) | Lanzás un `reviewer` con lo que dice el paso 3 (PR, checkout del orquestador, `agent_sha`, `skill_sha`). **Una sola revisión por PR a la vez.** |
| `escalate` | Relanzás `implementer` (Sonnet) en el **mismo worktree**, con el `reason`. Cuenta para el máximo de 3. |
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

- **PRs**: link, modelo que lo hizo, estado del CI (`gh pr checks <pr>`), `self-review` del implementador (si no corrió `/code-review`, destacalo), veredicto del revisor y hallazgos en una línea cada uno.
- **Consultas pendientes**: todas juntas, con su issue, para responder de una vez.
- **Escalados y relanzados**: qué issue, de qué modelo a cuál y por qué.
- **Decisiones en bloqueantes**: qué elegiste y por qué.
- **No lanzados**: los que `prepare.sh` rechazó.

Ofrecé publicar las revisiones (`gh pr review <pr> --comment --body-file <archivo>`), todas o algunas. Publicá solo lo que la persona confirme. El merge lo hace ella.

## 6. Retro

Las retros de los subagentes ya están guardadas: recibís dónde quedaron (`retro:`, ver el contrato), pero no las abras (solo los lee `/improve-skills`). Guardá la tuya con `.claude/skills/improve-skills/retro.sh <archivo>` y este frontmatter: `skill: orchestrate`, `issue: <épica>` (si los issues son de una) o `run: <YYYYMMDD-HHMM>`, `model: opus`, `role: orchestrator`, `area`, `paths`. En el cuerpo: issues lanzados con su modelo, escalados, rondas extra y cuánto tardó cada uno. Escribí el archivo fuera del repo.

## 7. Limpiar

```bash
.claude/skills/orchestrate/cleanup.sh            # lista los worktrees de issues cerrados
.claude/skills/orchestrate/cleanup.sh --delete   # los borra, si la persona dice que sí
```

También lista las ramas `claude/<n>-…` cuyo PR se cerró sin mergear, con el comando para borrar cada una (al final, después de sacar los worktrees: `git branch -D` falla mientras la rama esté en uno) (`git push origin --delete`; `gh pr close --delete-branch` falla desde un detached HEAD). No las borra: ofrecéselo a la persona, rama por rama, y avisale si alguna tiene commits sin pushear. No borra un worktree con cambios sin commitear, ni ninguno si quedan retros en `retros-pendientes/` (la corrida no está cerrada hasta guardarlas): en ese caso, reintentá cada retro con `retro.sh <archivo>` y volvé a correrlo.
