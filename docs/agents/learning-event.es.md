# Evento de aprendizaje (v1)

Lo que un proyecto registra para que `bk learn` pueda medir si sus reglas sirven. Las decisiones están en el [ADR-007](../decisions/kit/ADR-007-per-project-learning.md); esta página es cómo las lleva a cabo el kit. El código es `scripts/agents/learning.py`.

## Dónde va

`.barrilete/learning.json` del checkout principal elige el store (ADR-007 D2), también desde un worktree: una copia vieja en un worktree no abre un segundo store. `init`, `install` y `update` lo traen con `local`:

```json
{"store": "local"}
```

| store | dónde | sale de la máquina |
|---|---|---|
| `local` (también sin el archivo) | `.barrilete/learning/events.jsonl` del checkout principal, también desde un worktree. La carpeta trae su propio `.gitignore` y el `.gitignore` de la raíz también la ignora. | no |
| `branch` | la rama de datos `agents/learning`: cada escritura es un commit de plumbing en la rama local, sin tocar la rama de trabajo, el índice ni el árbol. `learning.py push` la sube y junta las líneas si el remoto avanzó. | solo con `push` |

`agents/learning` se escribe sin PR y solo con `learning.py`, como `agents/retros` con `retro.sh`. En un repo público sus datos son públicos.

## El evento

Una línea JSON por evento, solo con los campos de la tabla del ADR-007 D3. Obligatorios: `v`, `ts`, `project`, `kind`, `model` y `harness`.

| campo | forma |
|---|---|
| `v` | `1` |
| `ts` | `AAAA-MM-DDTHH:MM:SS[.ffffff]Z` (UTC) |
| `project` | el nombre del repo (el de `origin`, o si no la carpeta del checkout principal; lo que no es letra, número, `.`, `_` o `-` queda como `-`) |
| `task_id` | el id del ADR-005 (`244-implementer`) |
| `pr` | un número positivo |
| `provider`, `harness`, `area`, `role`, `class`, `rule_id`, `outcome` | slug: minúsculas, números y guiones |
| `model` | un id de modelo sin espacios (`claude-sonnet-5-5`, `openai/gpt-4o`) |
| `kind` | `check_run`, `task_end`, `deviation` o `finding` |
| `evidence_ref` | una ruta local (`[A-Za-z0-9._~/-]`, hasta 300), o solo una de estas URLs de `https://github.com/<owner>/<repo>/`: `pull/<n>` o `issues/<n>` (con `#issuecomment-<n>` o `#discussion_r<n>` opcional), `blob/<sha>/<ruta>` (con `#L<n>` o `#L<n>-L<m>` opcional; la ruta en esa clase, sin `..`, hasta 300) y `commit/<sha>`. `<sha>` son de 7 a 40 dígitos hexadecimales en minúscula; `<owner>` tiene hasta 39 letras, números o `-`, sin empezar con `-`; `<repo>` tiene hasta 100 de `[A-Za-z0-9._-]`, nunca solo puntos. Cualquier otra URL se rechaza: `push` publica el store, y en las otras viaja un webhook o un token (ADR-007 D3). Nunca la evidencia misma |
| `rules_ref` | `<12 hex>.<12 hex>` (abajo) |

- `class`: en `finding`, un id de `classes.yml`; en `deviation`, el tipo del desvío como slug (`guardrail-block`, `user-correction`…), que D5 conecta con una clase por la lista `deviations` de `classes.yml` (ADR-007 D3 y D5). El validador solo revisa que sea un slug.
- `outcome`: `pass`, `fail` o `skipped` en `check_run`; `completed`, `failed`, `incomplete` o `cancelled` en `task_end`; no va en `deviation` ni en `finding`.
- Un campo que no está en la tabla, o uno con texto libre, hace inválido el evento y no se escribe nada. El error nombra el campo, nunca su valor.
- `model` sale de `BK_MODEL` (o, si no está, de `BARRILETE_MODEL`, que exporta `bk`); `harness`, de `BK_HARNESS` (o, si no está o está vacío, `claude-code` con `CLAUDECODE=1`; uno no vacío e inválido es `unknown`); `provider`, de `BK_PROVIDER` (o `BARRILETE_PROVIDER`). Sin un modelo o un harness conocidos el evento dice `unknown`: el emisor nunca adivina.
- Las líneas v0 de #323 (el `check_run` de `verify.py` antes del v1, con `check` y `branch`) no se migran: `validate` las cuenta aparte como heredadas y no las marca rotas, siempre que tengan exactamente esa forma. Su `branch` tiene los caracteres de un nombre de rama (letras, también `ñ`, números, `.`, `_`, `/`, `@`, `+`, `#` y `-`, sin `..`), como lo escribía v0; su `task_id`, el del ADR-005.
- Con `BK_TASK_DIR` (un agente `bk`, ADR-005) lleva además `task_id`, `role` y `pr` cuando `task.json` los tiene, y `rules_ref`.

### rules_ref

`<primeros 12 del SHA de rules.lock>.<primeros 12 del sha256 de las secciones generadas>`: el bloque de reglas de `AGENTS.md` y el de `.claude/agents/<rol>.md`. Si no se volvió a correr `sync-rules`, cambia la segunda mitad y la medición sabe qué versión tenía el agente. Sin `rules.lock` no va.

## Quién escribe

| kind | quién | cuándo |
|---|---|---|
| `check_run` | `verify.py` | cada check de regla de `.barrilete/checks.json` que corre |
| `task_end` | `task_events.py` | el `Stop` que sigue a `bk done`, cuando `task.json` ya es terminal; uno por tarea |
| `deviation`, `finding` | `bk learn` (barrilete-workspace) | todavía no en el kit |

Escribir nunca frena el trabajo: si el evento no se puede escribir, `verify.py` y el hook siguen.

## Comandos

```bash
python3 scripts/agents/learning.py validate .barrilete/learning/events.jsonl   # 3 y la línea de cada evento roto; cuenta aparte las v0 heredadas
python3 scripts/agents/learning.py emit check_run rule_id=pr-metadata outcome=pass   # solo ts, pr, area, role, class, rule_id, outcome y evidence_ref (en una tarea bk no role ni pr, que vienen de task.json); 64 con cualquier otro
python3 scripts/agents/learning.py push                                        # solo store branch; 1 si git lo rechaza (con el motivo de git), 3 con un learning.json inválido
python3 scripts/agents/learning.py rules-ref implementer
```
