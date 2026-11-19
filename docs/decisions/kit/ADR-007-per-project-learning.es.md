# ADR-007 — Aprendizaje por proyecto

## Estado

Propuesto (2026-11-16). Se acepta al mergear el PR de lautioliver/barrilete-kit#322. Reemplaza a ADR-006 en D1 (la parte del vault), D5, D6 y D10; el resto de ADR-006 sigue vigente.

Origen: lautioliver/barrilete-kit#322, épica lautioliver/barrilete-kit#321 y la propuesta de la persona del 2026-11-15 ("aprendizaje por proyecto").

Decidido por @lautioliver en el chat (2026-11-16):
- Un ADR nuevo en vez de enmendar ADR-006.
- Los datos viven en el proyecto, donde el proyecto elija: `local` (por defecto) o una rama de datos (D2).
- Un mínimo de 20 rondas por celda (regla × modelo × harness) antes de dar veredicto (D5).
- El benchmark compartido queda en el horizonte y no se construye (ver Horizonte).
- El ruteo de harness por área es una feature aparte (lautioliver/barrilete-kit#326): acá solo se suma el campo `area` al evento.
- El evento lleva solo metadatos: nunca prompts, código ni texto de transcripts o de personas.

El resto (la lista de campos, los valores de `outcome`, el formato de `rules_ref` y cómo se toma UHP) son refinamientos que escribió un agente y la persona no decidió por separado. Se aprueban al aceptar este ADR o se cambian en la revisión de su PR.

Enmendado en lautioliver/barrilete-kit#324 (2026-11-17), decidido por @lautioliver: la celda de D5 no lleva rol (regla × modelo × harness, como arriba; aprobado en el chat del 2026-11-17, registrado en https://github.com/lautioliver/barrilete-kit/pull/338#issuecomment-6963224944), y D6 fija el formato de `rules_ref` (comentario del 2026-11-16 en #324).

Enmendado en lautioliver/barrilete-kit#348 (2026-11-18), decidido por @lautioliver en el chat (registrado en https://github.com/lautioliver/barrilete-kit/issues/348#issuecomment-6968066532): D3 limita `evidence_ref` a una ruta local más las URLs de GitHub de la lista de D3, en lugar de cualquier URL sin credenciales ni query.

Enmendado en lautioliver/barrilete-kit#345 (2026-11-18), decidido por @lautioliver en el chat (registrado en https://github.com/lautioliver/barrilete-kit/issues/345#issuecomment-6988907723): en D3, `class` de un `deviation` es el tipo del desvío y todos los desvíos van al store; en D5, los desvíos cuentan por el mapeo tipo → clase de `classes.yml`. ADR-006 D4 no cambia: las clases de desvío de `classes.yml` son las que reciben tipos por ese mapeo.

## Contexto

ADR-006 unificó las reglas en `barrilete-rules`, pero dejó los datos de aprendizaje afuera de los proyectos:

- **Los desvíos viven en el vault de Obsidian de la persona** (ADR-006 D1 y D5). Lo que aprenden los agentes de un proyecto queda en una máquina: el equipo no lo ve y otro dev no lo tiene.
- **Faltan los cortes que importan.** El 53% de los 395 desvíos no tiene modelo, y ninguno tiene `harness` ni `class`. `bk learn` solo lee los transcripts de Claude Code.
- **La medición miraba otra cosa.** `effect.py` medía las lecciones del vault, no las reglas de `barrilete-rules` (lo arregla lautioliver/barrilete-workspace#10). La etiqueta `[clase]` no se reconocía cuando el hallazgo arranca con `#n: `: 18 de 48 hallazgos cayeron en `other`.
- **Los checks no dejaban registro.** `verify.py` corría los checks de `.barrilete/checks.json` sin guardar si pasaban o fallaban. lautioliver/barrilete-kit#323 agrega el evento `check_run` con un esquema v0, a la espera de este ADR.
- **Las propuestas van directo al store general** (ADR-006 D6). Una regla que solo tiene sentido en un proyecto tiene que pasar por un repo público.
- **La medición no corta por modelo ni por harness** (ADR-006 D10). La misma regla puede servir con un modelo y no con otro, y el mínimo de rondas quedó como pregunta abierta.

## Decisión

1. **D1. El store de cada proyecto es la fuente; el vault es una vista personal.** Reemplaza a ADR-006 D1 en lo que dice del vault. `barrilete-rules` sigue siendo el único sistema de reglas. Los datos de aprendizaje (desvíos, hallazgos, corridas de checks, cierres de tarea) se escriben en el store del proyecto (D2). El vault pasa a ser una vista que `bk learn` puede armar desde los stores para la persona: nada lo lee como fuente. Los eventos que ya están en el vault no se migran: se siguen leyendo como fuente heredada hasta la fase 3 de la épica (lautioliver/barrilete-workspace#12).

2. **D2. El proyecto elige dónde viven sus datos.** `.barrilete/learning.json` dice `{"store": "local"}` o `{"store": "branch"}`. Sin el archivo, `local`.
   - **`local`**: `.barrilete/learning/events.jsonl` del checkout principal (también si el agente trabaja en un worktree). La carpeta lleva su propio `.gitignore`, así que nunca entra a un commit. No sale de la máquina.
   - **`branch`**: la rama de datos `agents/learning`, como `agents/retros`: se escribe sin PR y solo con su script. El equipo comparte la historia, y los datos tienen la visibilidad del repo: en un repo público son públicos.

3. **D3. Un solo evento para todos los adaptadores.** Reemplaza a ADR-006 D5. Cada línea del store es un evento con estos campos:

   | campo | valores | para qué |
   |---|---|---|
   | `v` | `1` | versión del esquema; el `check_run` de #323 es `v: 0` |
   | `ts` | ISO 8601, UTC | cuándo |
   | `project` | nombre del repo | de qué proyecto, si una vista junta varios |
   | `task_id` | id de ADR-005 (`244-implementer`) | enlaza con la tarea, cuando hay `BK_TASK_DIR` |
   | `pr` | número | el PR del que sale el evento, cuando hay uno |
   | `provider` | `anthropic` · `openai`… | comparar proveedores |
   | `model` | `claude-sonnet-5-5`… | **obligatorio** |
   | `harness` | `claude-code` · `codex` · `copilot` · `cursor` · `pi` | **obligatorio**: el mismo modelo se porta distinto según dónde corre |
   | `area` | el label `area:` del issue | para el ruteo por área (#326) |
   | `role` | `implementer` · `reviewer`… | a qué rol le llega la regla |
   | `kind` | `deviation` · `finding` · `check_run` · `task_end` | qué pasó |
   | `class` | en `finding`, id de `classes.yml`; en `deviation`, el tipo del desvío (abajo) | conecta desvío, regla y hallazgo (ADR-006 D4) |
   | `rule_id` | id de la regla | la regla mapeada, si la hay |
   | `outcome` | depende de `kind` (abajo) | el resultado |
   | `evidence_ref` | ruta local o una URL permitida (abajo) | dónde está la evidencia, nunca la evidencia |
   | `rules_ref` | ver D6 | qué versión de las reglas recibió el agente |

   - **`evidence_ref`:** una ruta local, o solo una de estas URLs, todas de `https://github.com/<owner>/<repo>/`: `pull/<n>` o `issues/<n>` con un `#issuecomment-<n>` o `#discussion_r<n>` opcional; `blob/<sha>/<ruta>` con un `#L<n>` o `#L<n>-L<m>` opcional; `commit/<sha>`. `<sha>` es hexadecimal (minúscula, de 7 a 40 dígitos). Cualquier otra URL se rechaza (en las otras viaja un webhook o un token, y `push` publica el store).
   - **`class` en `deviation`:** el tipo del desvío como slug, no un id de `classes.yml`. Por ejemplo, `guardrail-block` o `user-correction`; la lista completa es la del adaptador de Claude Code (`bk learn`, `lib/deviations.py` de barrilete-workspace). Un tipo se conecta con su clase por el mapeo de D5.
   - **Todos los desvíos van al store**, también las correcciones, los rechazos y las interrupciones de la persona (`user-correction`, `user-denied`, `interrupt`, `plan-correction`): el evento guarda el tipo, nunca lo que la persona escribió.
   - **Obligatorios:** `v`, `ts`, `project`, `kind`, `model` y `harness`. El resto va cuando se conoce. Quien emite no adivina: si no puede saber el modelo o el harness, escribe `unknown`, y el reporte los cuenta aparte.
   - **`outcome`:** en `check_run`, `pass`, `fail` o `skipped` (el check no pudo verificar), como en el v0 de #323. En `task_end`, los estados terminales de ADR-005 D3: `completed`, `failed`, `incomplete` o `cancelled`. En `deviation` y `finding` no va.
   - **Sin campos de texto.** El esquema no tiene campos de texto libre, y un evento con un campo que no está en la tabla se rechaza (lo prueba un test en lautioliver/barrilete-kit#324). Nunca entran prompts, código, texto de transcripts o de personas, nombres de clientes ni secretos: el evento se tiene que poder auditar sin ver nada del negocio.
   - El contrato de ADR-005 no cambia: los eventos de aprendizaje no son eventos de tarea. `task_end` es el hecho de que la tarea terminó, copiado al store para medir; `events.jsonl` de la tarea sigue siendo el de ADR-005.

4. **D4. Las propuestas van primero al proyecto.** Reemplaza a ADR-006 D6. `bk learn` y `/improve-skills` proponen la regla en `.barrilete/rules/` del proyecto, en `proposed`, por un PR al proyecto: aceptarla es mergearlo. Una regla llega a `barrilete-rules` solo si alguien la promueve a mano, con un PR a ese repo. Nada escribe solo en un repo, y un proyecto no expone nada por tener reglas propias.

5. **D5. Se miden las reglas que el proyecto aplica, por celda.** Reemplaza a ADR-006 D10 y responde su pregunta abierta sobre las rondas.
   - Las reglas medidas son las que el proyecto recibe: las del SHA de `.barrilete/rules.lock` que le aplican (las mismas que filtra `sync-rules`) y las de `.barrilete/rules/`.
   - Una celda es regla × modelo × harness. Por celda se miden los hallazgos de las `classes` de la regla por ronda de review, antes y después de `accepted`, y la tasa de fallo de su check si tiene.
   - **Desvíos, por el mapeo de `classes.yml`.** Cada clase de `barrilete-rules` lleva una lista opcional `deviations` con los tipos de desvío que le corresponden, y un tipo cae en una sola clase como máximo. Por celda se miden también los desvíos de los tipos mapeados a las `classes` de la regla, por tarea (`task_end`), aparte de los hallazgos por ronda. Un tipo sin clase se guarda en el store pero no se mide. Los valores del mapeo se cargan con un PR a `barrilete-rules`, no en este ADR.
   - **Mínimo de 20 rondas por celda.** Con menos, el reporte dice "poca muestra" y no da veredicto.
   - Una regla sin efecto con muestra suficiente tiene las mismas tres salidas que en ADR-006, y elige la persona: pasa a check, se reescribe más concreta o pasa a `deprecated`.

6. **D6. Canary de carga: `rules_ref`.** Cada evento de un agente registra qué versión de las reglas recibió: el SHA de `barrilete-rules` de `rules.lock` y un hash corto de las secciones generadas que leyó (`.claude/agents/<rol>.md` y el bloque de `AGENTS.md`). Si un agente corrió con secciones viejas (no se volvió a correr `sync-rules`), se ve en el evento, y la medición atribuye el resultado a la versión que el agente tuvo de verdad. El formato, fijado en #324: `<primeros 12 del SHA de rules.lock>.<primeros 12 del sha256 del bloque de reglas de AGENTS.md y el de .claude/agents/<rol>.md>`. Va solo en los eventos de un agente `bk` (`BK_TASK_DIR`), y nunca sin `rules.lock`.

7. **D7. Compatible con UHP, no dependiente.** Del Unified Harness Protocol se toma el vocabulario, no el formato:
   - los estados de la tarea: `completed`, `failed`, `incomplete`, `cancelled` (ya en ADR-005);
   - códigos estables con prefijo para traducir una clase o una regla: `barrilete_<id>` con `_` en vez de `-` (`barrilete_pr_metadata`);
   - lo propio va en la metadata.

   No se adopta su servidor ni su formato de stream: los harness que se usan no hablan UHP y los desvíos salen de hooks, `verify.py`, reviews y PRs. Si algún harness habla UHP, traducir su stream a este evento es directo. Se revisa cuando eso pase.

## Qué no cambia

- De ADR-006: D2 (el repo `barrilete-rules`), D3 (el formato de una regla), D4 (las clases y la etiqueta del reviewer), D7 (`rules.lock` y `sync-rules`), D8 (los checks en `verify.py`), D9 (la inyección en la definición del agente), D11 (las fases de esa transición) y D12 (`rules_checked`).
- ADR-005 entero.

## Horizonte (no se construye)

- **Fase 5 de la épica: benchmark compartido, opt-in, solo conteos.** Un proyecto podría exportar, si quiere, conteos por clase, modelo, proveedor, harness y rol, la tasa por ronda, la tasa de fallo de cada check y los ids de las reglas generales. Nunca saldrían texto, prompts, código, evidencia, el nombre del proyecto o del repo, las reglas propias, PRs, issues ni personas. Serviría para responder "¿qué modelo deja más docs desactualizadas?" sin que ningún proyecto muestre cómo trabaja. Para construirlo tiene que pasar al roadmap y llevar su propio ADR.
- **El ruteo de harness por área** (#326): este ADR solo deja el campo `area` en el evento.

Esto queda acá y no en el horizonte del proyecto (horizon.md): en el kit ese archivo es la plantilla que `init` copia a cada proyecto nuevo, y lo que diga del kit les llegaría a todos.

## Preguntas abiertas

- **¿`unknown` alcanza para `model` y `harness`, o un emisor que no los conoce no emite?** D3 propone `unknown`. Se confirma en #324, cuando se vea cuántos eventos llegan así.

## Alternativas descartadas

- **Enmendar ADR-006.** La persona eligió un ADR nuevo: los cambios tocan cuatro decisiones y el principio de dónde viven los datos.
- **Solo la rama de datos.** El equipo compartiría la historia, pero choca con la privacidad: en un repo público los datos serían públicos. Queda como opción (D2).
- **Solo local.** Lo más privado, pero cada dev ve solo lo suyo. Es el valor por defecto, no la única opción.
- **Seguir en el vault.** Los datos de un proyecto quedan en la máquina de una persona.
- **Adoptar el formato de UHP.** Es joven, de un solo actor y cambia seguido (5 versiones en ~10 semanas); no ahorra adaptadores.
- **Medir por regla sola, sin cortar por modelo ni harness.** Mezcla modelos que se portan distinto y esconde una regla que sirve con uno y no con otro.
- **Construir el benchmark ahora.** El cuello de botella es medir bien dentro del proyecto (fase 0), no compartir.

## Consecuencias

- **Se gana:**
  - los datos de aprendizaje viven con el repo y el proyecto elige quién los ve;
  - un evento con la misma forma para todos los harness;
  - medir por modelo, harness y rol, con un mínimo que evita veredictos con poca muestra;
  - saber qué versión de las reglas tuvo cada agente.
- **Cuesta:**
  - un adaptador por harness (Claude Code, Codex, Copilot, Cursor, pi);
  - dos caminos de store para mantener;
  - cortar por celda divide las rondas: muchas celdas van a decir "poca muestra" por un tiempo.
- **Riesgo:** que se filtre texto al store. Lo frena el esquema sin campos de texto y el test que rechaza campos de más.
- **Issues de la épica #321** (ya abiertos):
  - **kit** #324: el evento v1 y el store (D2, D3, D6); #325: los adaptadores de Codex, Copilot, Cursor y pi (toca hooks: hay que preguntar antes);
  - **barrilete-workspace** lautioliver/barrilete-workspace#11: el adaptador de Claude Code; #12: las propuestas al proyecto (D4) y la alerta de stream callado; #13: el reporte por celda (D5); #14: un A/B con tareas del git.
- **Lo que pide la enmienda de #345** (lautioliver/barrilete-rules#7, #363 y lautioliver/barrilete-workspace#20): en `barrilete-rules`, la lista `deviations` en `classes.yml`, que su validador la acepte y los valores del mapeo; en el kit (#363), que `check-docs.py` acepte la lista en la copia generada, para poder subir `rules.lock` al SHA que la trae; en `bk learn effect` (#13), contar los desvíos mapeados por tarea.
