# ADR-006 — Store de reglas para los agentes (`barrilete-rules`)

## Estado

Aceptado (2026-11-05). @lautioliver lo aprobó al mergear lautioliver/barrilete-kit#257 el 2026-11-05, D1 a D12 tal como están en d89240a. Las preguntas abiertas siguen abiertas: se deciden en el issue de la fase que las necesita.

Enmendado (2026-11-07): el principio al inicio de Decisión, D2, D7, D8 y D11 (los checks se implementan en el kit, las dos condiciones de éxito y el check `pr-metadata` en la fase 2), aprobado por @lautioliver en el PR #<PR>. Lo decidió @lautioliver en el chat de la sesión barrilete-kit-46 el 2026-11-07; origen: lautioliver/barrilete-kit#280.

Origen: lautioliver/barrilete-kit#256 y una propuesta de la persona del 2026-11-04 ("store de reglas generales para agentes").

Decidido por @lautioliver en el chat:
- (2026-11-04) Las reglas son generales, versionables y, cuando se puede, verificables con un check.
- (2026-11-05) El store **reemplaza** a los dos sistemas de hoy (D1). Vive en un repo separado y público, `lautioliver/barrilete-rules` (D2). Los desvíos quedan en un jsonl local con el `task_id` de ADR-005 (D5). El check de una regla corre dentro de `verify.py` (D8). El kit consume las reglas con versión fija y `sync-rules` (D7).

El resto (los campos, la lista de clases, dónde se inyectan, la medición y las fases) son refinamientos que escribió un agente y la persona no decidió por separado. Se aprueban al aceptar este ADR o se cambian en la revisión de su PR.

## Contexto

Hoy hay dos sistemas de lecciones que no se hablan:

- **Kit**: docs/agents/lessons.md. Solo lo escribe `/improve-skills` a partir de las retros, por PR y con un máximo de 40 líneas, y lo lee `implement-issue`.
- **`bk learn`** (barrilete-workspace). Lee transcripts y reviews cada ~2 min y guarda desvíos en un vault de Obsidian. Cuando un patrón se repite 3 veces en 14 días, propone una lección. La persona la acepta y la regla pasa a un `INDEX.md` que se importa desde el `CLAUDE.md` global de la persona: le llega a todas las sesiones de todos los proyectos.

Lo que se midió el 2026-11-05 con `bk learn effect`:

- **Las reglas en texto no mueven los desvíos.** Las dos reglas del implementer aceptadas el 2026-11-01 siguen igual en 44 rondas de review: de 0,14 a 0,18 y de 0,14 a 0,16 hallazgos de su clase por ronda.
- **La clase de cada hallazgo de review la adivina una expresión regular.** De 138 hallazgos, 68 (49%) cayeron en "otro hallazgo". Sin una clase confiable no se pueden conectar desvíos, reglas y hallazgos, ni proponer reglas buenas, ni medir.
- **Las reglas llegan al lugar equivocado.** Una regla del implementer ocupa contexto en cualquier chat. Cuando el rol corre como subagente del orquestador (ADR-004), no recibe un `SessionStart` propio, así que nada que se inyecte por hook le llega.

## Decisión

barrilete-rules es la fuente de verdad de las políticas reutilizables de Barrilete. Su formato es independiente de los agentes y herramientas que las consumen. barrilete-kit es su primer consumidor y proporciona mecanismos concretos para aplicarlas y verificarlas.

1. **D1. Un solo sistema de reglas.** `barrilete-rules` reemplaza a docs/agents/lessons.md del kit y a las lecciones de `bk learn`, incluidos el `INDEX.md` y su import en el `CLAUDE.md` global. Al terminar la transición (D11):
   - `lessons.md` desaparece;
   - `/improve-skills` y `bk learn` proponen reglas al store en vez de escribir lecciones;
   - el vault queda solo para leer: desvíos, patrones y medición.

2. **D2. El repo `lautioliver/barrilete-rules`, público.** Tiene dos cosas:
   - `rules/<id>.md`: una regla por archivo;
   - `classes.yml`: la lista de clases (D4).

   No guarda checks: una regla solo declara `check: <id>` y su `fail_message`, y el check se implementa en el kit (D8). `classes.yml` tiene una sola fuente, `barrilete-rules`: la copia del kit, `docs/agents/classes.yml`, la genera `sync-rules` desde la fase 2 (D7, D11), y hasta entonces sigue provisoria. Nunca guarda desvíos (D5). Una regla se acepta mergeando el PR que la agrega o la pasa a `accepted`, así que siempre la revisa una persona, como hoy en `/improve-skills`.

3. **D3. Una regla** es un archivo `rules/<id>.md`. Arriba lleva un frontmatter con los datos y abajo, en el cuerpo, la regla en una línea, el porqué y la evidencia.

   | campo | valores | para qué |
   |---|---|---|
   | `id` | slug (`pr-metadata`) | estable y sin choques entre PRs en paralelo; no usa números correlativos |
   | `status` | `proposed` · `accepted` · `deprecated` | solo `accepted` se inyecta (D9) |
   | `origin` | `observed` · `human` · `general` | `general` se acepta solo con `classes` o `check` |
   | `applies_to` | roles (`implementer`, `reviewer`…) o `*` | dónde se inyecta (D9) |
   | `scope` | `*` o repos (`barrilete-kit`) | una regla de un solo proyecto, como hoy "solo en barrilete-kit" |
   | `classes` | ids de `classes.yml` | qué hallazgos debería bajar; con eso se mide (D10) |
   | `check` | id de un check del kit (`scripts/agents/checks/<id>`, D8) | opcional; si está, la regla es su documentación |
   | `severity` | `block` · `fix` · `suggestion` | `block` exige `check`: una regla en texto no puede bloquear |
   | `accepted` | fecha ISO | desde cuándo se mide |
   | `examples` | opcional | casos `bad`/`good` |

4. **D4. Clases estables, y el reviewer etiqueta.** `classes.yml` lista las clases de hallazgo y desvío, con un id y una descripción: `pr-metadata`, `stale-docs`, `uncovered-case`, `test-cannot-fail`… La skill `review-pr` pide etiquetar cada hallazgo con su clase (`[stale-docs] …`), y `bk learn` usa la etiqueta. La expresión regular queda solo para las reviews viejas, sin etiqueta. Esta decisión es la base de todas las demás: sin clase confiable no hay forma de mapear un desvío a su regla, ni de proponer, ni de medir.

5. **D5. Los desvíos quedan locales, con `task_id`.** `bk learn` los sigue guardando en un jsonl local, nunca en un repo, porque son muchos y traen texto de transcripts y de la persona. Cada desvío lleva:
   - cuándo y de qué: `ts`, `class`;
   - quién: `model`, `harness`, `role`. Modelo y harness van por separado: "sonnet" y "codex" no son la misma clase de cosa;
   - dónde: `project`, `pr`, y el `task_id` de ADR-005 cuando el agente tenía `BK_TASK_DIR`;
   - `evidence` (ruta o URL) y `rule_id` si ya se mapeó.

   El contrato de ADR-005 no cambia: los desvíos no son eventos de la tarea.

6. **D6. Las propuestas son locales hasta que alguien abre el PR.** `bk learn` arma la propuesta (la regla en `proposed`, con evidencia y clase) en local. Aceptarla es abrir un PR a `barrilete-rules`. `/improve-skills` propone igual, desde las retros. Así nada se escribe solo en un repo, y las propuestas que se generan cada 2 minutos no ensucian el historial.

7. **D7. El kit consume una versión fija con `sync-rules`.**
   - `.barrilete/rules.lock` guarda el repo y el SHA.
   - `scripts/agents/sync-rules` lee esa versión y hace tres cosas:
     - genera las reglas `accepted` de cada rol en `.claude/agents/<rol>.md`, entre marcadores;
     - genera las de `applies_to: *` en `AGENTS.md`, que lee Codex;
     - verifica que cada `check: <id>` que declara una regla `accepted` exista en `scripts/agents/checks/<id>` del kit, y falla si alguno no está.
   - Actualizar las reglas es un PR al kit que cambia el lock, así que se ve qué entra.
   - El CI y `verify.py` corren sin red.
   - Un proyecto puede tener sus propias reglas en `.barrilete/rules/`, con el mismo formato, y `sync-rules` las suma a las del store.
   - **Condición de éxito 1:** se modifica una regla en barrilete-rules, se aprueba su PR, se actualiza `rules.lock` y se comprueba que el agente correspondiente recibe exactamente esa versión.

8. **D8. Los checks corren dentro de `verify.py`.** Un check tiene tres cosas:
   - `id`;
   - la regla a la que responde;
   - un `fail_message` que dice qué hacer y cuándo escalar, para que el agente no quede en un loop.

   Su implementación vive en el kit, en `scripts/agents/checks/<id>`: depende de `verify.py` y de las rutas del kit. La regla en `barrilete-rules` solo declara `check: <id>` y su `fail_message`.

   `verify.py` corre los checks de las reglas que aplican al proyecto. Si uno falla, el agente lo arregla como cualquier verify rojo: no hay un resultado nuevo en `bk done` (ADR-005 D4 no cambia). Un check del tipo `ci` que corra además en el workflow queda para después y lleva su propia aprobación, porque toca CI: esta enmienda no lo autoriza.

   **Condición de éxito 2:** una regla con check (`pr-metadata`) llega por `rules.lock`, corre en `verify.py` y frena a un agente cuyo PR no la cumple.

9. **D9. Las reglas se inyectan en la definición del agente, no por hook.** Las de un rol van en `.claude/agents/<rol>.md` (D7), que se carga tanto cuando el rol corre como agente `bk` como cuando corre como subagente. Las de `applies_to: *` van en `AGENTS.md`. El `CLAUDE.md` global de la persona deja de importar lecciones. Si la regla tiene `check`, el texto lo dice ("lo valida `verify.py`: <check>").

10. **D10. Se mide, y lo que no sirve se va.** `bk learn effect` mide, por regla, los hallazgos de sus `classes` por ronda de review antes y después de `accepted`. Una regla sin efecto después de un mínimo de rondas tiene tres destinos, y elige la persona:
    - pasa a check;
    - se reescribe más concreta;
    - pasa a `deprecated`.

    Cuando una regla gana un check, se mide también qué parte de las corridas del check falla.

11. **D11. La transición va por fases, y cada fase se mide antes de seguir.**

    | fase | qué cambia | qué sigue igual |
    |---|---|---|
    | 0 | `classes.yml` y la etiqueta del reviewer (D4) | todo lo demás |
    | 1 | se crea `barrilete-rules`; se migran las lecciones del vault (aceptadas y retiradas) y docs/agents/lessons.md (como `origin: human`) | el `INDEX.md` y `lessons.md` siguen funcionando |
    | 2 | `sync-rules`, la inyección por rol (D7, D9) y el primer check, `pr-metadata`, en `verify.py` (D8); se borran `lessons.md` y el import del `CLAUDE.md` global | `bk learn` sigue detectando |
    | 3 | `bk learn` y `/improve-skills` proponen al store (D6) | — |
    | 4 | los checks siguientes en `verify.py` y el check `ci` (con su propia aprobación) | — |

    La fase 2 cierra solo cuando las dos condiciones de éxito (D7, D8) se cumplen de punta a punta.

12. **D12. `rules_checked` en el self-review: es una declaración, no una prueba.** El campo `self-review:` del contrato de salida (docs/agents/subagent-contract.md) suma `rules_checked: [<id>…]`. Si el agente declaró una regla y el reviewer encuentra un hallazgo de su clase, ese desvío se marca como `declared`: pesa más y adelanta que la regla pase a check. Lo declarado nunca reemplaza a un check.

## Preguntas abiertas

- **¿Cuántas rondas sin efecto antes de decidir sobre una regla (D10)?** La propuesta es 20.
- **¿El vault conserva una vista de solo lectura de las reglas, o solo los desvíos?**
- **¿`bk learn` abre el PR de una propuesta solo, o lo abre la persona?** D6 dice "alguien"; la propuesta es que lo abra la persona desde `bk lessons`.

## Alternativas descartadas

- **Sumar el store como tercer sistema.** La persona lo descartó: empeora el problema que viene a resolver.
- **Las reglas dentro del kit (`agents/rules/`).** La persona eligió un repo separado. Con el kit, aceptar una regla era un PR al mismo repo; con el repo separado, hace falta el lock y `sync-rules` (D7).
- **Desvíos como evento de la tarea (ADR-005).** Ataba todo a la tarea, pero obligaba a enmendar ADR-005, y los desvíos de los chats sin tarea igual necesitaban otro lugar.
- **Un resultado nuevo en `bk done` cuando un check frena el PR.** Daba más información, pero enmendaba ADR-005. `verify.py` ya es la puerta antes del PR.
- **Submodule de git, o siempre la última versión.** El submodule complica los worktrees y a los agentes. Bajar siempre la última permite que una regla nueva rompa el CI de un proyecto sin aviso.
- **Inyectar las reglas por un hook `SessionStart`.** No le llega a un rol que corre como subagente.

## Consecuencias

- **Se gana:**
  - un solo lugar para las reglas, con historial y revisión;
  - reglas que llegan solo a su rol;
  - una clase confiable para conectar desvíos, reglas y hallazgos;
  - reglas que se pueden volver checks y una medición que decide qué queda.
- **Cuesta:**
  - un repo más;
  - un PR al kit cada vez que se actualizan las reglas;
  - una línea más por hallazgo en la plantilla de review;
  - mantener `classes.yml`.
- **Riesgo:** se pierde la regla que hoy llega a todas las sesiones de la persona, aunque no sean del kit. Las de `applies_to: *` siguen en `AGENTS.md`, pero solo en los proyectos que tienen el kit.
- **Issues que se abren al aceptarlo, uno por fase de D11:**
  - **kit**: `classes.yml` provisional y la etiqueta en `review-pr`, en en y es (fase 0);
  - **barrilete-rules**: crear el repo, el esquema y la migración (fase 1);
  - **kit**: `rules.lock`, `sync-rules`, la inyección en `.claude/agents/` y `AGENTS.md`, el primer check, `pr-metadata`, en `verify.py`, y borrar `lessons.md` (fase 2). Toca CI e infraestructura, y este ADR es la aprobación;
  - **bk (workspace y bk-shell)**: `bk learn` con clases y `task_id`, propuestas al store y `bk learn effect` sobre `classes` (fases 0 y 3);
  - **kit**: los checks siguientes en `verify.py` y `rules_checked` en el contrato de subagentes (fases 4 y D12).
