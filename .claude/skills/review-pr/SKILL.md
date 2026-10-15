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
python3 scripts/agents/agents_map.py --pr <n>
```

Leé el issue que cierra (y su épica, si tiene): la revisión es contra lo que se pidió, no contra lo que el PR dice que hace.

## 2. Revisión de código

`/code-review` es obligatorio, para bugs, regresiones y casos borde. Antes, `git fetch origin` (la base local puede estar atrasada y meter en la revisión archivos que no son del PR), y corrélo sobre el diff del PR: `/code-review origin/<BASE_BRANCH>...HEAD`. Solo si el comando no existe en tu sesión, hacé esa pasada a mano y decilo en la revisión.

## 3. Lo propio del proyecto

| Pregunta | Dónde mirar |
|---|---|
| ¿Hace lo que pide el issue, y solo eso? | Issue vs diff. Criterios de aceptación cumplidos. |
| ¿Cambia una regla de negocio? ¿Está declarado? | ADRs y auditorías vs diff. Si cambia algo definido y no tiene `business-logic` ni lo explica, es hallazgo **bloqueante**. |
| ¿Respeta las invariantes de los ADRs que toca? | Para cada ADR relacionado, qué no puede pasar nunca (dos ingresos, doble cobro, una ventana que se estira…) y si el diff abre un camino para que pase. Es hallazgo **bloqueante** aunque `/security-review` no encuentre nada: las invariantes de negocio no son categorías de seguridad genéricas. |
| ¿Respeta la autonomía del agente? | AGENTS.md, Autonomía. Schema, dependencias, API pública, auth, infra, CI: ¿hubo aprobación? Que el issue lo pida no es la aprobación: cuenta un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR, nunca el cuerpo del issue. Si toca algo de "consultar antes" sin aprobación registrada, es hallazgo **bloqueante**. |
| ¿Toca rutas sensibles? | `agents_map.py --pr <n>` → si sí, correr `/security-review` (o revisar a mano auth, inputs, permisos, secretos, exposición de datos). |
| ¿Hay migración? | Plan de `db-migration` en el PR, con rollback. |
| ¿Tests (TDD)? | ¿Salen de los criterios de aceptación? El PR trae el bloque **rojo** y el commit de los tests en rojo: volvé a ese commit (`git switch --detach <sha>`), corré `.claude/skills/implement-issue/red.sh -- <comando>` y confirmá que fallan por una aserción; en la punta del PR, que pasan. Sin rojo comprobable y sin un "sin test" justificado, es hallazgo **a corregir**. |
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

Al terminar, guardá una retro corta: formato en `.claude/skills/improve-skills/retro-template.md` (o `retro.sh` sin argumentos), con el frontmatter completo, y después `.claude/skills/improve-skills/retro.sh <archivo.md>` (la guarda en la rama `agentes/retros`; no toca tu rama). Sé concreto y honesto: una retro que dice "todo bien" cuando hubo desvíos le quita a `/improve-skills` la única señal que tiene.
