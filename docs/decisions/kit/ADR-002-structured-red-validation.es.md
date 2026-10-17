# ADR-002 — Validación estructurada del test en rojo

## Estado

Aceptado (2026-10-17)

Origen: épica lautioliver/barrilete-kit#148 e issue lautioliver/barrilete-kit#149. Decisiones D1–D10 aprobadas por @lautioliver en el chat (2026-10-17): D1–D7 y D10 según la recomendación, D8 opción (a) y D9 aprobada. Enmiendas de la revisión del PR lautioliver/barrilete-kit#156, decididas por @lautioliver en el chat, 2026-10-17: D11 (este ADR vive en `docs/decisions/kit/`), el perfil `--small` en D2, la regla por caso de D4 y la sección `red` confiable de D7. Donde una regla de abajo dice "decidido por @lautioliver en el chat, 2026-10-17", esa es la aprobación.

Refinamientos escritos en la revisión del PR lautioliver/barrilete-kit#156 y no decididos por separado por la persona: D2 (una lista de stacks con `name`/`when`, sin campo `report`, `{out}` dentro de `run`, sin `red.sh -- <command>`, `red.sh <stack>`); D3 (el exit code 64, los límites de 20 MB y UTF-8, el rechazo de `DOCTYPE` y las definiciones de saltado, TODO y abortado); D9 (la línea `stack:` obligatoria, que agrega un requisito al check del CI). Se aprueban al mergear el PR lautioliver/barrilete-kit#158, que los registra.

Correcciones de lautioliver/barrilete-kit#158 (enmendar este ADR lo aprobó @lautioliver en el chat, 2026-10-17; solo hacen las reglas más estrictas o corrigen texto): la regla de comparación de D4, dónde se escribe el TAP de D6, el detalle de D3 sobre `testsuite` y la redacción de D11.

Estado de la implementación: este ADR registra el objetivo. Hasta que entren los issues de la épica, `red.sh` sigue funcionando con las reglas de texto que tiene hoy, y todavía no existen la sección `red`, `tap.sh`, `red_report.py` ni el bloque estructurado del PR. Esta nota la saca la enmienda que cierra lautioliver/barrilete-kit#154 (los proyectos no editan los ADRs de `kit/`, así que quedaría vieja).

## Contexto

- `red.sh` (paso 3 de `implement-issue`, la tabla de TDD de `review-pr`) decide si un test falla "por la razón correcta" con regex sobre la salida del runner: una lista de errores de carga, una lista de patrones de aserción, y todo lo demás se rechaza.
- El texto libre no escala: cualquier runner nuevo, idioma o forma de crash cae en el lado equivocado. En lautioliver/barrilete-kit#146, dos rondas intentaron aceptar más formatos con listas de crashes y en las dos el revisor encontró casos que pasaban como rojo válido.
- No hay timeout, y no distingue las fallas de los tests nuevos de un test viejo que ya estaba roto.
- El bloque que va al PR es texto libre que el revisor no puede comparar con nada.
- Los 12 `test-*.sh` del kit definen cada uno su `ok()`/`fail()`, y el CI de docs mira solo el código de salida.
- El formato no está documentado en ningún lado (prueba de punta a punta de lautioliver/barrilete-kit#115).

## Decisión

1. **D1. La única evidencia es un reporte estructurado (JUnit XML o TAP).** Sin reporte, `red.sh` sale con 2 y explica cómo configurar el reporter. No hay respaldo de texto: es justo el agujero que hay que cerrar.

2. **D2. El proyecto declara cómo obtener el reporte en una sección `red` de agents-map.json.**
   - **Forma.** `red` es un arreglo, como `verify`. Cada entrada es un stack: `{"name": "...", "when": ["<glob de archivos de test>"], "run": "...", "format": "junit"|"tap", "timeout": 600}`. `timeout` es opcional (D5).
   - **No hay campo `report`.** `{out}` tiene que aparecer en `run`. `red.sh` lo reemplaza por una ruta temporal propia, borra el archivo antes de correr y exige que se haya creado en esta corrida, así no se puede reusar un reporte viejo. `check-docs.py` rechaza una entrada cuyo `run` no tenga `{out}`, cuyo `format` no sea `junit` ni `tap`, o que no tenga `when`.
   - **Qué entrada corre.** `red.sh` corre cada entrada cuyo `when` coincide con un archivo que cambia el commit en rojo (el diff de D4), una tras otra, y el rojo es válido solo si cada una lo es. Si ninguna coincide, sale con 2. `red.sh` ya no recibe un comando: `red.sh -- <comando>` desaparece, porque un comando escrito por el agente es un camino fuera de la evidencia declarada (D1, D8). `red.sh <stack>` corre solo la entrada con ese nombre, para las iteraciones del implementador.
   - **stdout y el exit code.** `run` se ejecuta con `bash -o pipefail -c`. `red.sh` no captura stdout. Para TAP, `run` debe hacer que el helper de D6 escriba en `{out}`, no redirigir stdout (`bash tests/run.sh > {out}`): por stdout, un test que imprime líneas `ok`/`not ok` mete casos en el flujo. Con `pipefail`, un pipeline como `cargo test | cargo2junit > {out}` conserva el exit code de falla.
   - **El perfil `--small`.** Declara `red` en un docs/agents-map.json mínimo que contiene solo la sección `red` (decidido por @lautioliver en el chat, 2026-10-17). Las herramientas que leen el mapa toman una sección ausente como vacía. Este ADR solo lo decide: el archivo y el código que lo lee corresponden a los issues de la sección `red` y del perfil, y al issue de migración.

3. **D3. Un rojo es válido solo si se cumple todo a la vez:**
   - el exit code de `run` es distinto de 0;
   - el reporte existe, se generó en esta corrida y se parsea;
   - se ejecutó al menos 1 caso;
   - hay al menos 1 `failure` (una aserción);
   - **0** `error`;
   - ningún caso abortado;
   - ningún timeout ni señal (un `returncode` negativo en Python, o un exit code mayor que 128).

   El exit code solo nunca alcanza. Definiciones:
   - **Failure y error, JUnit.** Un `testcase` con un hijo `failure` es una falla. Uno con un hijo `error` es un error.
   - **Failure y error, TAP.** Un `not ok` es una falla. Un `Bail out!` es un error. `not ok … # TODO` no es una falla: es una falla esperada. `ok … # TODO` es un pase inesperado y cuenta como caso ejecutado que pasa.
   - **Ejecutado.** Un caso se ejecutó si no está salteado. Salteado: un hijo `skipped` (JUnit), `# SKIP` o `not ok … # TODO` (TAP). Un reporte con solo casos salteados no tiene ningún caso ejecutado: sale con 2.
   - **Abortado.** JUnit: el XML está truncado o no se parsea, o el atributo `tests` de un `testsuite` no coincide con los `testcase` que contiene, contando los `testsuite` anidados (un `testsuite` sin atributo `tests` no se compara: sus casos igual cuentan; el `testsuites` raíz no se compara). TAP: no hay plan (`1..N` al principio o al final), el plan no coincide con la cantidad de casos, o el flujo termina sin el plan.
   - **Seguridad del parser.** Se rechaza el reporte si tiene un `<!DOCTYPE` (JUnit nunca lo necesita; también cierra la expansión de entidades internas en versiones viejas de expat), si pesa más de 20 MB o si no es UTF-8.
   - **Exit codes de `red.sh`.** 0: rojo válido. 1: los tests pasan (exit code 0 y un reporte sin falla ni error). 2: rechazado por cualquier otro motivo, incluido un `run` que sale con 0 con fallas en el reporte (inconsistente) y cualquier error interno. 64: uso incorrecto. `implement-issue`, `review-pr` y los tests de `red.sh` dependen de este contrato.

4. **D4. "Nuevo" se decide por caso de test, no por archivo, y cada caso fallido tiene que ser un caso que agrega o cambia el commit en rojo** (decidido por @lautioliver en el chat, 2026-10-17). Si no, un test viejo roto, incluso dentro de un archivo que toca el commit en rojo, "probaría" el TDD de cualquier PR.
   - **El diff.** El commit en rojo contra su primer padre. El commit en rojo es uno solo y contiene los tests (y los stubs, si hacen falta); el sha del bloque del PR (D7) es el de ese commit.
   - **La regla.** Un caso fallido es válido si (1) se puede asociar a un archivo (tabla de abajo), (2) ese archivo está en el diff y (3) el nombre del caso, sin sus parámetros (`test_x[1]` es `test_x`), aparece como identificador entero, en una línea agregada por el diff en ese archivo que define el test (`def`, `fn`, `func`, `it(`/`test(`, o la línea de caso de `tap.sh`), nunca en un comentario. Identificador entero: `test_parse` no coincide con un `def test_parse_empty` agregado, y una mención en un comentario o una llamada no cuenta. En un archivo que el diff agrega, califica cada caso. Un caso cuyo cuerpo cambió pero cuyo nombre no aparece en una línea agregada que lo define se rechaza: se acepta rechazar de más, el objetivo es fallar cerrado.
   - **El nombre que se compara.** Es el nombre que aparece en el código, así que el reporter tiene que darlo así: jest-junit con `titleTemplate="{title}"` (su valor por defecto, `"{classname} {title}"`, antepone el nombre del `describe`); vitest, el último segmento del nombre, después del último ` > `; go, el primer segmento de un subtest (`TestX/case` compara `TestX`, el único con una línea `func`; una fila de tabla agregada a un `TestX` viejo que falla se rechaza). Las opciones exactas se verifican con el corpus de lautioliver/barrilete-kit#150.
   - **Fallar cerrado.** Un caso fallido que no se puede asociar a un archivo agregado o cambiado por el diff hace que `red.sh` salga con 2 y diga qué opción del reporter falta.
   - **Por formato.**

     | Runner | Reporter | Archivo de un caso |
     |---|---|---|
     | bash | TAP del helper de D6 | la línea de comentario `# file: <ruta>` que precede a los casos de ese script |
     | pytest | `--junitxml={out} -o junit_family=xunit1` (el `xunit2` por defecto no trae `file`) | el atributo `file` |
     | jest | `jest-junit` con `addFileAttribute=true` y `titleTemplate="{title}"` | el atributo `file` |
     | vitest | `--reporter=junit --outputFile={out}` | `classname`, que es la ruta del archivo |
     | go | `gotestsum --junitfile {out}` | `classname` es la ruta de import del paquete: se convierte en directorio con la línea `module` de `go.mod`, y el nombre tiene que aparecer en una línea agregada de un archivo `*_test.go` de ese directorio |
     | cargo | `cargo2junit` o `nextest` (`junit`) | `classname` es una ruta de módulo, no un archivo: cargo solo se controla por archivo. El identificador entero tiene que aparecer en una línea `fn` agregada de un archivo `*.rs` del diff que coincida con `when`; no se compara el módulo, así que un `a::tests::it_works` roto pasa si el commit agrega un `it_works` en el módulo `b`. Límite conocido: usar nombres de test distintos en los proyectos con cargo |

     Cualquier otro runner sigue la misma regla: si da `file`, o un `classname` que es una ruta, se usa; si no, hay que configurar el reporter para que lo dé, o el rojo se rechaza.
   - **TAP.** Un solo flujo para toda la corrida, con un único plan; el helper escribe `# file: <ruta>` antes de los casos de cada script. Un `not ok` sin un `# file:` antes no se puede asociar: sale con 2.

5. **D5. Timeout: 600 s por defecto, configurable con `"timeout"` (en segundos) en cada entrada de `red`.** Cubre la corrida completa, no cada caso. Se aplica con Python, porque `timeout` no existe en macOS. `run` arranca en su propio grupo de procesos, y al vencer el timeout `red.sh` mata todo el grupo, no solo al hijo, para que ningún runner siga escribiendo en `{out}`. Tras un timeout, `red.sh` sale con 2.

6. **D6. Los tests del kit usan la misma regla que exige.** Un helper, scripts/agents/tap.sh (lo crea lautioliver/barrilete-kit#151), escribe TAP 14: `ok N - x`, `not ok N - x`, `# file: <script>` antes de los casos de cada script, un único plan `1..N`, y `Bail out!` ante un error inesperado vía `trap ERR`. El helper escribe en un archivo que crea `red.sh` (`{out}`), nunca por stdout: así un test que imprime líneas `ok`/`not ok` no puede meter casos. Cómo recibe el helper la ruta (argumento o variable) se decide en lautioliver/barrilete-kit#151. Los 12 `test-*.sh` migran a él. `red.sh` toma un `Bail out!` como error.

7. **D7. El revisor lo verifica de nuevo, con el `red` de la rama base.**
   - **El bloque.** El PR lleva, en "How to test it", exactamente esto (las líneas son literales, no se traducen; solo el título acepta también el `Rojo antes de implementar` en español):

     ```
     <details><summary>Red before implementing</summary>

     red commit: <sha del commit en rojo>

     stack: <nombre de la entrada de red>
     format: junit
     failing cases:
     - <file>::<name>
     - <file>::<name>

     </details>
     ```

     `red commit:` aparece una vez. Después hay un grupo (`stack:`, `format:`, `failing cases:`) por cada entrada de `red` que corrió (D2), así que un commit en rojo que toca dos stacks tiene dos grupos. `<file>` es el archivo de D4 (o el `classname` cuando el reporte no da archivo), `<name>` es el nombre del caso, un caso por línea.
   - **El control.** El revisor corre el `red.sh` del **checkout confiable** (la rama base) en ese commit, en su worktree de revisión, y compara, grupo por grupo (por `stack`), la lista de casos fallidos con la del bloque como conjunto: no importan el orden ni las repeticiones. Un stack sin grupo, o un grupo de un stack que no corrió, es una diferencia. Si no coinciden, es un hallazgo a corregir.
   - **De dónde sale `red`.** El `red.sh` del revisor lee la sección `red` del checkout confiable en la rama base, nunca del PR (decidido por @lautioliver en el chat, 2026-10-17). Si la leyera del commit en rojo, un PR podría poner en `run` cualquier comando y el revisor lo correría. Un PR que cambia la sección `red` es un cambio sensible: necesita la aprobación de una persona, como el CI, y mientras tanto el revisor valida con la sección de la base. Si la base todavía no tiene `red`, no hay nada en qué confiar y decide la persona.
   - Esto mantiene la regla del punto 8 aprobada en lautioliver/barrilete-kit#146: el revisor corre solo los tests del PR, no otro código del PR.

8. **D8. Entra antes de v1.0, como cambio que rompe compatibilidad, sin modo texto.** La épica lautioliver/barrilete-kit#148 bloquea lautioliver/barrilete-kit#91. Un proyecto sin sección `red` recibe un rechazo con una guía para agregarla; no hay modo de transición. Cambiarlo después de `v1.0.0` sería una ruptura.

9. **D9. El check del CI también exige estructura.** Además del título `Red before implementing` (o `Rojo antes de implementar`: el check acepta los dos), `labels.yml` exige la línea `red commit:` (un sha hexadecimal) y al menos un grupo con una línea `stack:`, una línea `format:` (`junit` o `tap`) y, bajo `failing cases:`, al menos una línea `- <file>::<name>`. Va en el mismo PR que D7. El CI es ruta sensible: aprobado por @lautioliver en el chat (2026-10-17).

10. **D10. Runners de referencia:** bash (TAP), pytest (`--junitxml`), vitest y jest (reporter `junit`), go (`gotestsum --junitfile`) y cargo (`cargo2junit` o `nextest`). Se documentan y prueban en el corpus. Cualquier otro runner sigue las reglas genéricas de D1–D5. Son los que tienen un reporter JUnit o TAP documentado en los stacks que usan hoy quienes usan el kit.

11. **D11. Los ADRs del kit que los proyectos instalan viven en `docs/decisions/kit/`** (decidido por @lautioliver en el chat, 2026-10-17). Este ADR es `docs/decisions/kit/ADR-002-…`. Los ADRs propios del proyecto van en `docs/decisions/`, numerados desde `ADR-001` sin saltos y sin choques con los números del kit. `check-docs.py` lee las dos carpetas, el índice lista cada ADR con su ruta, y dos ADRs con el mismo número en carpetas distintas no se confunden. El init conserva `docs/decisions/kit/` en el idioma de la instalación, como el resto de los docs. Un proyecto no debería editar los ADRs de `kit/` (es una recomendación, no algo que `check-docs.py` exija): si necesita otra regla, escribe un ADR propio que refiera al del kit. Una mención `ADR-NNN` sin carpeta se resuelve contra las dos carpetas; para evitar la ambigüedad cuando el proyecto tenga su propio `ADR-002`, el kit cita los suyos como `kit/ADR-002`.

## Alternativas descartadas

- **Un reporte estructurado, o el texto como respaldo (D1).** El respaldo de texto es el agujero que lautioliver/barrilete-kit#146 no pudo cerrar.
- **Una variable de entorno que el proyecto lee para la ruta del reporte (D2).** No queda declarado en ningún lado, `check-docs.py` no puede validarlo y `red.sh` no controla la ruta.
- **Un campo `report` junto a `run`, o una ruta fija (D2).** Si `report` fuera siempre `{out}` sería redundante, y si pudiera ser una ruta fija `red.sh` perdería el control de ella.
- **Solo el exit code, o el exit code más una búsqueda de texto (D3).** El exit code no distingue una aserción de un crash, y una búsqueda de texto es otra vez el agujero de D1.
- **No controlar que las fallas sean de tests nuevos (D4).** Un test viejo roto volvería válido el rojo de cualquier PR.
- **Nuevo por archivo en vez de por caso, o nuevo por correr los tests en el commit padre (D4).** Por archivo, un test viejo roto en un archivo que toca el commit en rojo pasaría. En el padre, la corrida falla abierta: si no carga, no se conoce ningún caso y todos parecerían nuevos.
- **Solo un timeout fijo (D5).** Algunas suites son legítimamente más lentas que otras.
- **Dejar los tests del kit como están y aceptar `FAIL - ` como TAP "de hecho" (D6).** El kit no se validaría con la regla que exige.
- **Que el revisor no verifique de nuevo y solo lea el bloque (D7).** El bloque es una afirmación del autor que nada respalda. **Que el revisor lea `red` del PR (D7)** deja que el PR elija el comando que corre el revisor.
- **Entrar en 1.1 con un período de transición y un modo con aviso (D8).** Mantiene vivo el camino del texto, justo lo que D1 quita, y una ruptura después de v1.0 cuesta más.
- **Controlar solo el título del bloque (D9).** Un bloque con el título y nada más pasaría, y el revisor no tendría nada para comparar.
- **Otros runners como referencia, o ninguno (D10).** Los runners se elegirían sin un motivo, o cada proyecto armaría su reporter solo y sin probarlo.
- **Numerar los ADRs del kit en la carpeta del proyecto (D11)**, renumerar en el init, o documentar un salto. Chocan con los números del proyecto y con los futuros ADRs del kit, y un archivo renumerado ya no coincide con lo que actualiza el kit.

## Consecuencias

- Un rojo se acepta solo con evidencia que un agente no puede falsear con un mensaje en la salida; el revisor puede compararla.
- Cuesta trabajo inicial por proyecto: configurar el reporter. Se alivia con valores por defecto en el `init` para bash y ejemplos listos para copiar del `agents-map.json` por runner.
- Habrá rechazos falsos (un runner mal configurado no genera el reporte, o la regla por caso es más estricta que el cambio): los mensajes dicen qué configurar. Se acepta rechazar de más: fallar cerrado es el objetivo.
- Afuera: cobertura, mutation testing, reintentar tests flaky y validar el verde (eso lo sigue haciendo el CI del proyecto).
- Lo que cambia está en el resto de la épica lautioliver/barrilete-kit#148: el helper TAP y la migración de los 12 tests, `red.sh` con su parser (scripts/agents/red_report.py, lo crea lautioliver/barrilete-kit#150) y su corpus, la sección `red` y su validación, el bloque estructurado del PR y el check de `labels.yml`, la migración de los proyectos existentes (los scripts de actualización y de crecimiento, el instalador y el CHANGELOG) y la prueba de punta a punta.
