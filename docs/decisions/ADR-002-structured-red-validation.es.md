# ADR-002 — Validación estructurada del test en rojo

## Estado

Aceptado (2026-10-17)

Origen: épica #148 e issue #149. Decisiones D1–D10 aprobadas por @lautioliver en el chat (2026-10-17): D1–D7 y D10 según la recomendación, D8 opción (a) y D9 aprobada.

## Contexto

- `red.sh` (paso 3 de `implement-issue`, la tabla de TDD de `review-pr`) decide si un test falla "por la razón correcta" con regex sobre la salida del runner: una lista de errores de carga, una lista de patrones de aserción, y todo lo demás se rechaza.
- El texto libre no escala: cualquier runner nuevo, idioma o forma de crash cae en el lado equivocado. En #146, dos rondas intentaron aceptar más formatos con listas de crashes y en las dos el revisor encontró casos que pasaban como rojo válido.
- No hay timeout, y no distingue las fallas de los tests nuevos de un test viejo que ya estaba roto.
- El bloque que va al PR es texto libre que el revisor no puede comparar con nada.
- Los 12 `test-*.sh` del kit definen cada uno su `ok()`/`fail()`, y el CI de docs mira solo el código de salida.
- El formato no está documentado en ningún lado (prueba de punta a punta de #115).

## Decisión

1. **D1. La única evidencia es un reporte estructurado (JUnit XML o TAP).** Sin reporte, `red.sh` sale con 2 y explica cómo configurar el reporter. No hay respaldo de texto: es justo el agujero que hay que cerrar.
2. **D2. El proyecto declara cómo obtener el reporte en una sección `red` de `docs/agents-map.json`, por stack.** Forma: `{"run": "...", "format": "junit"|"tap", "report": "{out}"}`. `red.sh` reemplaza `{out}` por una ruta temporal propia, la borra antes de correr y exige que se haya creado en esta corrida, así no se puede reusar un reporte viejo. `check-docs.py` valida la sección.
3. **D3. Un rojo es válido solo si se cumple todo a la vez:** exit code distinto de 0; el reporte existe, se generó en esta corrida y se parsea; se ejecutó al menos 1 caso; hay al menos 1 `failure` (una aserción); **0** `error`; ningún caso abortado; ningún timeout ni señal (exit code mayor que 128). El exit code solo nunca alcanza.
4. **D4. Cada caso fallido tiene que estar en un archivo de test que agrega o cambia el commit en rojo.** Se controla por `file`/`classname` en JUnit, o por el nombre del script en TAP. Si no, un test viejo roto "probaría" el TDD de cualquier PR.
5. **D5. Timeout: 600 s por defecto, configurable con `"timeout"` en `red`.** Se aplica con Python, porque `timeout` no existe en macOS. Si se pasa, `red.sh` sale con 2.
6. **D6. Los tests del kit usan la misma regla que exige.** Un helper scripts/agents/tap.sh (a crear en #148) (TAP 14: `ok N - x`, `not ok N - x`, `1..N`, y `Bail out!` ante un error inesperado vía `trap ERR`) y los 12 `test-*.sh` migran a él. `red.sh` toma un `Bail out!` como error.
7. **D7. El revisor lo verifica de nuevo.** El bloque del PR lleva el sha del commit en rojo, el formato y la lista de casos con `failure`. El revisor vuelve a correr el `red.sh` del **checkout confiable** en ese commit y compara las listas. Si no coinciden, es un hallazgo a corregir. Mantiene la regla del punto 8 aprobada en #146: el revisor corre solo los tests del PR, no otro código del PR.
8. **D8. Entra antes de v1.0, como cambio que rompe compatibilidad, sin modo texto.** La épica #148 bloquea #91. Un proyecto sin sección `red` recibe un rechazo con una guía para agregarla; no hay modo de transición. Cambiarlo después de `v1.0.0` sería una ruptura.
9. **D9. El check del CI también exige estructura.** Además del título `Red before implementing` del bloque, `labels.yml` exige las líneas `format:` y `red commit:` y al menos un caso. Va en el mismo PR que D7. El CI es ruta sensible: aprobado por @lautioliver en el chat (2026-10-17).
10. **D10. Runners de referencia:** bash (TAP), pytest (`--junitxml`), vitest y jest (reporter `junit`), go (`gotestsum --junitfile`) y cargo (`cargo2junit` o `nextest`). Se documentan y prueban en el corpus. Cualquier otro runner sigue las reglas genéricas de D1–D5.

Seguridad del parser: el parser en Python (scripts/agents/red_report.py (a crear en #148)) no ejecuta nada de lo que lee. Usa `xml.etree` sin entidades externas y rechaza los reportes de más de 20 MB.

## Alternativas descartadas

- **Un reporte estructurado, o el texto como respaldo (D1).** El respaldo de texto es el agujero que #146 no pudo cerrar.
- **Una variable de entorno que el proyecto lee para la ruta del reporte (D2).** No queda declarado en ningún lado, `check-docs.py` no puede validarlo y `red.sh` no controla la ruta.
- **No controlar que las fallas sean de tests nuevos (D4).** Un test viejo roto volvería válido el rojo de cualquier PR.
- **Solo un timeout fijo (D5).** Algunas suites son legítimamente más lentas que otras.
- **Dejar los tests del kit como están y aceptar `FAIL - ` como TAP "de hecho" (D6).** El kit no se validaría con la regla que exige.
- **Entrar en 1.1 con un período de transición y un modo con aviso (D8).** Mantiene vivo el camino del texto, justo lo que D1 quita, y una ruptura después de v1.0 cuesta más.

## Consecuencias

- Un rojo se acepta solo con evidencia que un agente no puede falsear con un mensaje en la salida; el revisor puede compararla.
- Cuesta trabajo inicial por proyecto: configurar el reporter. Se alivia con valores por defecto en el `init` para bash y ejemplos listos para copiar del `agents-map.json` por runner.
- Habrá rechazos falsos (un runner mal configurado no genera el reporte): los mensajes dicen qué configurar. Se acepta rechazar de más: fallar cerrado es el objetivo.
- Afuera: cobertura, mutation testing, reintentar tests flaky y validar el verde (eso lo sigue haciendo el CI del proyecto).
- Lo que cambia está en el resto de la épica #148: el helper TAP y la migración de los 12 tests, `red.sh` con `red_report.py` y su corpus, la sección `red` y su validación, el bloque estructurado del PR y el check de `labels.yml`, la migración de proyectos (`update.py`, `grow.py`, `install.py`, CHANGELOG) y la prueba de punta a punta.
