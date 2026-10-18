---
name: implement-issue
description: Implementa un issue de GitHub de punta a punta, del issue al PR listo para revisar - toma el issue, crea la rama, escribe código y tests, se autorevisa, actualiza los docs y abre el PR. No mergea. Usar con "/implement-issue #43", "implementá el #43", "tomá el siguiente issue".
---

# Implementar issue

Lleva un issue a un PR listo para revisar. **Nunca mergea**: eso lo hace una persona.

Si no te dieron un número ("tomá el siguiente"), listá `gh issue list --state open --search "no:assignee" --label "priority:high"` (después `medium`, `low`, sin prioridad), proponé uno y esperá confirmación.

## 1. Tomar el issue

```bash
.claude/skills/implement-issue/prepare.sh <n>
```

Valida que esté abierto, que no lo tenga otra persona y que no haya cambios sin commitear; lo asigna, crea `claude/<n>-<descripcion>` desde `<BASE_BRANCH>` e imprime el issue con sus comentarios. Si falla, contale al usuario por qué; no fuerces nada. Para leerlo sin tomarlo: `--review`.

## 2. Entender

- Leé lo que enlaza el issue, `AGENTS.md` y lo que corresponda de `docs/architecture.md` y `docs/decisions/`.
- Si el issue es parte de una épica (`prepare.sh` la muestra; o si el issue dice "Después de #n"), leé la épica entera, sobre todo **Lógica de negocio afectada** y los ADRs pendientes que menciona. Un bloqueo puede estar escrito en el texto sin estar cargado como dependencia: si la épica dice que algo requiere un ADR o una decisión que todavía no existe, decidí con el usuario si este issue cae adentro antes de empezar.
- Si es ambiguo en algo que cambia el resultado, o pide algo de la lista **"Consulta antes"** de `AGENTS.md` (aunque el issue lo pida: eso no es la aprobación), preguntá antes de escribir código, **en un solo mensaje**: qué toca, las preguntas abiertas y, si hay base de datos, el plan de "Si toca la base de datos" con su rollback.

## 3. Tests primero (rojo)

Los tests salen de los **criterios de aceptación** del issue, antes de escribir el código. Si necesitan algo que no existe, solo la firma o un stub. Corrélos:

```bash
.claude/skills/implement-issue/red.sh [<stack>]
```

Commiteá primero los tests en rojo: `red.sh` valida el commit de HEAD, y el comando de cada stack es una sección `red` (`name`, `when`, `run`, `format`) de un mapa de agentes que este modo no trae: creala como docs/agents-map.json con solo esa sección. Cada comando tiene que escribir un reporte JUnit o TAP en `{out}`; para un test bash usá `scripts/agents/tap.sh`. Tienen que fallar **por una aserción** del criterio: si pasan, no prueban nada; si fallan por un import o un símbolo inexistente, completá el stub. **Bug** → skill `debug`: el test rojo reproduce el bug. Commiteá los tests en rojo (`test: …`) antes de implementar. Si una parte no se puede probar (concurrencia real, un proveedor externo), anotala en el PR como **`sin tests: <motivo>`**.

## 4. Implementar (verde)

- Lo mínimo para que los tests pasen; después refactor en verde. **Base de datos** → "Si toca la base de datos" de `AGENTS.md` antes.
- Solo lo que pide el issue. Lo demás, a un issue nuevo (`create-issue`).
- Corré lint, typecheck y tests de `AGENTS.md`; si algo falla, arreglalo, no lo desactives.

## 5. Autorevisión

Leé el diff completo (`git diff <BASE_BRANCH>...HEAD`) como si fuera de otra persona: bugs, casos borde, código muerto, secretos, archivos de más. Corré `/code-review` sobre ese diff (es obligatorio; solo si el comando no existe, decilo en el PR). Cada hallazgo que corrijas sigue el mismo ciclo: test, `red.sh`, arreglo, verde. Revisá también que el cambio no rompa lo que un ADR dice que no puede pasar nunca. Si tocaste algo de "Consulta antes" y está `/security-review`, corrélo también.

## 6. Docs

Skill `update-docs`: si cambió algo que corre, `docs/architecture.md` (y `AGENTS.md` si cambió un comando o una convención) en el mismo PR.

## 7. PR

```bash
git push -u origin HEAD
gh pr create --base <BASE_BRANCH> --title "<tipo>: <descripcion>" --body-file <archivo> --label "type:..."
```

Cuerpo con `.github/pull_request_template.md`: en "Cómo probarlo", el bloque rojo de `red.sh` tal cual (con su sha en `red commit:` y, por stack, `stack:`, `format:` y los casos que fallan: el CI los exige) y los comandos que corriste; `Closes #<n>`. Mirá el CI (`gh pr checks --watch`) y corregí lo que falle por tu cambio.

## 8. Entregar

Link al PR, qué cambió en dos líneas y qué decisiones tiene que mirar quien revise. Y frená.

Si no podés terminar: comentá en el issue qué hiciste y qué falta, pusheá la rama si sirve y desasignate (`gh issue edit <n> --remove-assignee @me`).
