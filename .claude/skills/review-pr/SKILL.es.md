---
name: review-pr
description: Revisa un PR como lo haría un segundo par de ojos del equipo, con el foco en lo que una revisión genérica no mira - reglas de negocio, ADRs, docs desactualizados, autonomía del agente, tests faltantes y rutas sensibles. Usar con "/review-pr <n>", "revisá el PR #n". Idealmente desde una sesión distinta de la que implementó.
---

# Revisar un PR

Un agente que genera código necesita a otro que lo cuestione. Esta revisión la hace **una sesión distinta** de la que implementó, si se puede: quien escribió el código tiende a leer lo que quiso escribir.

**No aprueba ni mergea.** Su salida es una lista de hallazgos para la persona que va a decidir el merge.

## 1. Contexto

```bash
gh pr view <n>                       # título, cuerpo, labels, issue que cierra
gh pr diff <n>
gh pr checks <n>
cd <root> && python3 scripts/agents/agents_map.py --pr <n>
```

`<root>` es el checkout de confianza: el de tu propia sesión, en la rama base (no en la del PR), o el del orquestador si te lanzó. El revisor corre siempre los scripts del kit (`red.sh`, `agents_map.py`, `retro.sh`) desde el checkout de confianza, en la rama base. No corre `verify.py`: lo cubre el CI, y `verify.py` ejecuta los `run` del mapa del PR. Corre los tests del PR en el worktree de revisión, en el commit en rojo y en la punta, sabiendo que son código del PR: es inevitable para comprobar el TDD. El commit en rojo puede tener tests, fixtures y stubs. Nunca corre otro código del PR (scripts, hooks, instaladores).

Leé el issue que cierra (y su épica, si tiene): la revisión es contra lo que se pidió, no contra lo que el PR dice que hace.

## 2. Revisión de código

`/code-review` es obligatorio, para bugs, regresiones y casos borde. Antes, `git fetch origin` (la base local puede estar atrasada y meter en la revisión archivos que no son del PR), y corrélo sobre el diff del PR: `/code-review origin/<base>...<head>`, donde `<base>` es la base del PR (`gh pr view <n> --json baseRefName -q .baseRefName`) y `<head>` su punta **por nombre** (la ref que bajaste, como `refs/revision/<pr>-<sufijo>`, o la rama del PR): `HEAD` es el checkout de la sesión, no el del PR, y el diff sale vacío. Un diff vacío no es motivo para saltearlo: arreglá el rango. Solo si el comando `/code-review` no existe en tu sesión, hacé esa pasada a mano y decilo en la revisión.

## 3. Lo propio del proyecto

| Pregunta | Dónde mirar |
|---|---|
| ¿Hace lo que pide el issue, y solo eso? | Issue vs diff. Criterios de aceptación cumplidos. |
| ¿Cambia una regla de negocio? ¿Está declarado? | ADRs y auditorías vs diff. Si cambia algo definido y no tiene `business-logic` ni lo explica, es hallazgo **bloqueante**. |
| ¿Respeta las invariantes de los ADRs que toca? | Para cada ADR relacionado, qué no puede pasar nunca (dos ingresos, doble cobro, una ventana que se estira…) y si el diff abre un camino para que pase. Es hallazgo **bloqueante** aunque `/security-review` no encuentre nada: las invariantes de negocio no son categorías de seguridad genéricas. |
| ¿Respeta la autonomía del agente? | AGENTS.md, Autonomía. Schema, dependencias, API pública, auth, infra, CI: ¿hubo aprobación? Que el issue lo pida no es la aprobación: cuenta un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR, nunca el cuerpo del issue. Si toca algo de "consultar antes" sin aprobación registrada, es hallazgo **bloqueante**. |
| ¿Toca rutas sensibles? | `agents_map.py --pr <n>` → si sí, correr `/security-review` (o revisar a mano auth, inputs, permisos, secretos, exposición de datos). |
| ¿Hay migración? | Plan de `db-migration` en el PR, con rollback. |
| ¿Tests (TDD)? | ¿Salen de los criterios de aceptación? El PR trae el bloque **rojo** estructurado (ADR-002 D7): `red commit: <sha>` y, por stack, `stack:`, `format:` y los casos que fallan `- <archivo>::<nombre>`. Volvé a ese sha en tu worktree de revisión, nunca en el checkout principal de la persona (`git switch --detach <sha>` ahí; si no tenés uno, creálo: `git fetch -q origin "+refs/pull/<n>/head:refs/revision/<n>-<sufijo>"` y `git worktree add --detach <ruta> refs/revision/<n>-<sufijo>`, con el `<sufijo>` elegido una vez (`date +%Y%m%d%H%M%S`); comprobá que `git -C <ruta> rev-parse HEAD` sea igual a `gh pr view <n> --json headRefOid -q .headRefOid`, o parate y decilo; al terminar, `git worktree remove <ruta>` y `git update-ref -d refs/revision/<n>-<sufijo>`), comprobá que el sha esté en el historial del PR y desde allí corré `<root>/.claude/skills/implement-issue/red.sh [<stack>]` **sin el argumento `<stack>`** (así corre todos los stacks cuyo `when` coincide, como el autor; `<stack>` es solo para repetir un stack una vez comparados los conjuntos) (el script y su sección `red` son los de confianza, de la rama base, nunca los del PR; los tests que corre son los del PR). Confirmá que fallan por una aserción y **comparé, stack por stack, los casos que fallan que imprime con los del bloque, como conjunto** (el orden y los repetidos no importan; un stack sin grupo, o un grupo de un stack que no corrió, es una diferencia). Si no coinciden, es hallazgo **a corregir**. En la punta del PR, que pasan. En un test bash, estas formas son los lugares donde `tap.sh` deja de ver un crash (mirá su encabezado) y están **prohibidas en el commit en rojo**: `|| true`, `trap - ERR`, `local x=$(prog)`, un `( prog )` solo, un `$( prog )` o unas comillas invertidas `` `prog` `` que son un único comando externo sin redirección (bash 3.2 nunca ve su crash), `tap_run` esperando 1 o 2, cualquier `tap_status`, `tap_run` alrededor de una función de shell, un `sh -c`/`bash -c` o cualquier cosa que corra más de un programa (`tap_run out 0 setup_fn`; `tap_run` rechaza una función y un script `sh`/`bash -c` simple con `;`, `&`, `|` o un salto de línea, pero no `eval f`, `builtin eval`, `env bash -c`, `bash --norc -c`, `ksh -c`, `xargs sh -c` ni una comilla invertida dentro de un script `sh -c`, que también están prohibidos), y cualquier programa, sea cual sea el estado de su crash, a la izquierda de `&&`/`||` o en la condición de un `if`/`while`/`!`. Si alguna aparece en las líneas que agrega el commit en rojo, es hallazgo **a corregir** (fuera del rojo, en la preparación de los tests del propio kit, se aceptan si están listadas en el encabezado de `tap.sh`). `tap_no_traceback` no es una de ellas: solo corta. Un `tap_skip` en el rojo no puede depender del resultado del código bajo prueba (la versión del shell sí). Comprobá también que ningún caso fallido del rojo se apoya en un programa que alguna de estas formas dejó caer. Si el PR cambia la sección `red` de `docs/agents-map.json`, es un cambio sensible que necesita la aprobación de una persona (como el CI): validá con la sección de la base y decilo; si la base todavía no tiene `red`, decide la persona. Sin rojo comprobable y sin un "sin tests: <motivo>" (o "no tests: <motivo>") justificado, es hallazgo **a corregir**. |
| ¿Docs al día? | `agents_map.py` marca docs **NOT MODIFIED**: ¿hacía falta tocarlos? ¿Lo nuevo contradice `architecture.md`? |
| ¿Convenciones? | Título, labels, cuerpo del PR, `Closes #n`, convenciones de código de AGENTS.md. |

## 4. Hallazgos

Cada hallazgo con: **archivo:línea**, qué está mal, por qué importa (qué falla y cuándo), y sugerencia. Clasificalos:

- **Bloqueante** — bug, regresión, regla de negocio cambiada sin declarar, seguridad, migración sin rollback, tests que faltan para lo central.
- **A corregir** — no rompe, pero no debería entrar así.
- **Sugerencia** — opcional.

No infles la lista: si no hay hallazgos de una categoría, decilo. Un PR sin hallazgos es un resultado válido.

## 5. Publicar

Mostrale los hallazgos al usuario. Publicarlos en el PR es un comentario visible para el equipo: **pedí confirmación** y después:

```bash
gh pr review <n> --comment --body-file <archivo>
```

Si te lanzó otro agente y no podés preguntarle al usuario, no publiques: devolvé los hallazgos y el borrador a quien te lanzó, que es quien le pide la confirmación.

Nunca `--approve`: aprobar es decisión de una persona. Si sos la sesión que implementó y te piden corregir, corregí en la misma rama y volvé a correr esta revisión.

## Retro

Al terminar, guardá una retro corta: formato en `.claude/skills/improve-skills/retro-template.md` (o `retro.sh` sin argumentos), con el frontmatter completo, y después, desde el checkout de confianza, `cd <root> && <root>/.claude/skills/improve-skills/retro.sh <archivo.md>` (`retro.sh` trabaja sobre el repo del directorio actual, así que el `cd` va primero; `<archivo.md>` tiene que ser una ruta absoluta, porque el `cd` cambia el directorio desde el que se resolvería una relativa) (la guarda en la rama `agents/retros`; no toca tu rama). Sé concreto y honesto: una retro que dice "todo bien" cuando hubo desvíos le quita a `/improve-skills` la única señal que tiene.
