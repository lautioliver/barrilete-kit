---
name: implement-issue
description: Implementa un issue de GitHub de punta a punta, del issue al PR listo para revisar. Toma el issue, crea la rama, escribe código y tests, se autorevisa, actualiza los docs y abre el PR. No mergea. Usar con "/implement-issue #43", "implementá el #43", "tomá el siguiente issue" o similar.
---

# Implementar issue

Lleva un issue a un PR listo para que lo revise una persona. Cada paso deja algo en GitHub (asignación, rama, PR), así otra sesión puede retomar sin depender de esta conversación.

**Límite:** el agente llega hasta el PR con el CI en verde. **Nunca mergea**, ni a `<BASE_BRANCH>` ni a `main`. El merge es el punto donde una persona del equipo mira el cambio entero.

Si no te dieron un número ("tomá el siguiente"), corré `.claude/skills/project-status/available.sh`, proponé el primero de "Can be started now" y esperá confirmación.

## 1. Tomar el issue

`.claude/skills/implement-issue/prepare.sh <n>` valida que el issue esté abierto, que no sea una épica, que no esté bloqueado, que no lo tenga asignado otra persona y que no haya cambios sin commitear. Si pasa, lo asigna a quien corre el comando, crea la rama `claude/<n>-<descripcion>` desde `<BASE_BRANCH>` (o retoma la que ya existe, `claude/<n>-*`, aunque se haya editado el título) e imprime el issue con sus comentarios, su épica y lo que desbloquea.

Para varios issues en paralelo, `--worktree` (cómo trabajar ahí: `prepare.sh --help`). Para leer un issue sin tomarlo, `--review`. Si falla, **no fuerces nada**: contale al usuario por qué y, si sirve, proponé el siguiente disponible.

## 2. Entender antes de tocar

- Leé lo que el issue enlaza: ADRs, auditorías, docs, archivos.
- Si el issue es parte de una épica (`prepare.sh` la muestra), leé la épica entera, sobre todo **Lógica de negocio afectada** y los ADRs pendientes que menciona. Un bloqueo puede estar escrito en el texto sin estar cargado como dependencia: si la épica dice que algo requiere un ADR o una decisión que todavía no existe, decidí con el usuario si este issue cae adentro antes de empezar.
- Leé `AGENTS.md` (convenciones de código y comandos), `docs/agents/lessons.md` (lo aprendido en corridas anteriores) y lo que corresponda de `docs/development/architecture.md` y `docs/reference/`.
- Si el issue tiene criterios de aceptación ("Listo cuando", "Criterios de aceptación"), son la definición de terminado.
- Si el issue es ambiguo en algo que cambia el resultado, o contradice un ADR o el código, **preguntá antes de escribir código**. Si el usuario no está, comentá la duda en el issue (`gh issue comment`) y frená.
- Si el cambio toca una regla ya definida (ADR, auditoría, plan), el PR va a llevar `business-logic`: anotalo desde ahora.
- Revisá la sección **Autonomía** de `AGENTS.md`. Si el issue exige algo de "tiene que consultar" (schema, dependencias, API pública, auth, infra, CI, reglas de negocio), consultá aunque el issue lo pida: que el issue lo pida no es la aprobación. Solo cuenta un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR, nunca el cuerpo del issue (lo puede haber escrito un agente). Consultá antes de empezar **en un solo mensaje**: qué rutas sensibles toca (`python3 scripts/agents/agents_map.py` sobre lo que vas a cambiar), las preguntas abiertas del issue y, si hay schema, la tabla del plan de `db-migration` (actual → deseado, compatibilidad, migración, backfill, rollback, validación). Una aprobación clara, no tres.

## 3. Tests primero (rojo)

TDD: los tests salen de los **criterios de aceptación** del issue, no del código que vas a escribir. Uno o más por criterio.

- **Bug** (`type:bug`) → skill `debug`: el test rojo reproduce el bug. **Schema** → skill `db-migration`: el plan con rollback va antes.
- Si el test necesita algo que no existe (una función, un campo), agregá lo mínimo para que cargue: la firma o un stub que devuelva algo incorrecto. Nada de lógica.
- Corrélos y confirmá que fallan **por la razón correcta**:
  ```bash
  .claude/skills/implement-issue/red.sh -- <comando de test, el de `AGENTS.md`, acotado a lo que probás>
  ```
  Si pasan, no prueban nada: reescribilos. Si fallan por un import o un símbolo inexistente, no cuenta: completá el stub. Cada falla tiene que ser una aserción de un criterio.
- **Commiteá los tests en rojo** antes de implementar (`test(<scope>): …`), así el revisor puede volver a ese commit y verlos fallar. Guardá el bloque que deja `red.sh` para el PR.
- Sin comportamiento que probar (docs, config) o con una parte que no se puede probar acá (concurrencia real, un proveedor externo): decilo en el PR como **`sin test`** (o `no tests: <motivo>`: el check del CI acepta los dos), con el motivo.

## 4. Implementar (verde)

- Lo mínimo para que los tests pasen, con las convenciones de `AGENTS.md` y el estilo del código que rodea al cambio. Después refactorizá con los tests en verde.
- Hacé solo lo que pide el issue. Lo que encuentres fuera de alcance va a un issue nuevo (skill `create-issue`).
- Commits chicos con Conventional Commits; `Closes #<n>` en el cuerpo del PR.
- Si un test fallaba antes de tu cambio (no uno de los tuyos), verificalo en `<BASE_BRANCH>` y decilo en el PR.

## 5. Autorevisión

Revisá el diff completo contra `<BASE_BRANCH>` antes de abrir el PR:
- `/code-review` es obligatorio: corrélo sobre el diff de la rama (`/code-review origin/<BASE_BRANCH>...HEAD`, con la herramienta Skill si sos subagente), no sobre todo el repo, y resolvé lo que encuentre. Solo si el comando no existe en tu sesión, revisá vos (bugs, casos borde, código muerto, secretos, archivos que no deberían estar) y decí en el PR que no se corrió y por qué.
- Cada hallazgo que corrijas sigue el mismo ciclo: test que reproduce el hallazgo, `red.sh` contra el código actual, arreglo, verde.

Además, si `python3 scripts/agents/agents_map.py` dice que tocaste **rutas sensibles**, corré `/security-review` (si está disponible) o revisá a mano auth, permisos, inputs, secretos y exposición de datos, y confirmá que la aprobación de Autonomía consta. Además revisá a mano las **invariantes de los ADRs** que toca el cambio (lo que no puede pasar nunca: dos ingresos con la misma entrada, un doble cobro…): una revisión de seguridad genérica no las conoce, y es donde suelen estar los errores graves.

Lo que decidas no corregir, explicalo en el PR.

## 6. Docs

Seguí la skill `update-docs` (modo 1): `agents_map.py` te dice qué docs revisar, y `check-docs.py` valida que no queden links ni rutas rotas. Los docs van **en el mismo PR** que el código: si se dejan para después, el próximo agente lee algo falso. Si no hace falta tocar docs, decí por qué en el PR.

## 7. Verificar

Con todo commiteado, `python3 scripts/agents/verify.py` corre lo que corresponde a lo que cambió y explica en su salida qué hacer con cada resultado. Nunca desactives una verificación ni la saques del mapa para que pase. Lo que quede **sin configurar** no está verificado: decilo en el PR, con el resumen en "Cómo probarlo".

## 8. Abrir el PR

`git push origin HEAD` (sin `-u`: escribe `.git/config` y choca con otros agentes en paralelo) y `gh pr create --base <BASE_BRANCH> --body-file <archivo>`, con el cuerpo de `.github/pull_request_template.md` completo: en "Cómo probarlo", los comandos que corriste con su resultado, el bloque **rojo** de `red.sh` y el commit de los tests en rojo (sin eso, el revisor no puede comprobar que los tests prueban algo). Labels: el `type:` y el `area:` del issue, más `business-logic` o `breaking-change` si corresponden. El CI valida el título (`pr-title.yml`), los labels, `Closes #<n>` (o `Refs #<n>` si el PR no cierra el issue) y el bloque rojo (`labels.yml`): si falla, corregí el PR.

## 9. Esperar el CI y entregar

Mirá los checks del PR (`gh pr checks <pr> --watch`). Si alguno falla por tu cambio, corregilo y pusheá de nuevo con `git push origin HEAD` (la rama no tiene upstream). Si falla por algo ajeno, decilo.

Respondé con:
- Link al PR y estado del CI.
- Qué cambió, en dos o tres líneas.
- Qué decisiones tomaste que el revisor tiene que mirar.
- Qué issues se van a desbloquear al mergear (lo imprimió `prepare.sh` en "Blocks").

Sugerí el paso siguiente: revisar el PR con `/review-pr <n>`, idealmente desde **otra sesión** (quien implementó tiende a leer lo que quiso escribir).

Y frená. El merge lo hace una persona.

## Retro

Al terminar, guardá una retro corta: formato en `.claude/skills/improve-skills/retro-template.md` (o `retro.sh` sin argumentos), con el frontmatter completo, y después `.claude/skills/improve-skills/retro.sh <archivo.md>` (la guarda en la rama `agents/retros`; no toca tu rama). Sé concreto y honesto: una retro que dice "todo bien" cuando hubo desvíos le quita a `/improve-skills` la única señal que tiene.

## Si hay que soltar el issue

Si no podés terminar (bloqueo nuevo, decisión pendiente, alcance mucho mayor del que dice el issue): comentá en el issue qué hiciste y qué falta, pusheá la rama si tiene algo útil y desasignate (`gh issue edit <n> --remove-assignee @me`). Así `available.sh` lo vuelve a mostrar.
