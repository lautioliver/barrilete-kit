# ADR-002 — Validación estructurada del test en rojo

## Estado

Aceptado (2026-10-17)

Origen: épica lautioliver/barrilete-kit#148 e issue lautioliver/barrilete-kit#149. Decisiones D1–D10 aprobadas por @lautioliver en el chat (2026-10-17): D1–D7 y D10 según la recomendación, D8 opción (a) y D9 aprobada. Enmiendas de la revisión del PR lautioliver/barrilete-kit#156, decididas por @lautioliver en el chat, 2026-10-17: D11 (este ADR vive en `docs/decisions/kit/`), el perfil `--small` en D2, la regla por caso de D4 y la sección `red` confiable de D7. Donde una regla de abajo dice "decidido por @lautioliver en el chat, 2026-10-17", esa es la aprobación.

Refinamientos escritos en la revisión del PR lautioliver/barrilete-kit#156 y no decididos por separado por la persona: D2 (una lista de stacks con `name`/`when`, sin campo `report`, `{out}` dentro de `run`, sin `red.sh -- <command>`, `red.sh <stack>`, correr cada entrada cuyo `when` coincide, y sin coincidencia salir con 2); D3 (el exit code 64, los límites de 20 MB y UTF-8, el rechazo de `DOCTYPE` y las definiciones de saltado, TODO y abortado); D9 (la línea `stack:` obligatoria, que agrega un requisito al check del CI). Se aprueban al mergear el PR lautioliver/barrilete-kit#159, que los registra.

Correcciones de lautioliver/barrilete-kit#158 (enmendar este ADR lo aprobó @lautioliver en el chat, 2026-10-17; hacen las reglas más estrictas, corrigen texto, o hacen viable la comparación de nombres de D4 para jest, vitest y go): la regla de comparación de D4, dónde se escribe el TAP de D6, el detalle de D3 sobre `testsuite` y la redacción de D11.

Enmiendas de lautioliver/barrilete-kit#150, decididas por @lautioliver en el chat, 2026-10-17 (las tres decisiones abiertas de D4 que dejó la segunda revisión del PR lautioliver/barrilete-kit#159): las reglas de cargo (un atributo de test en el `fn` agregado, hasta dónde se recorta la ruta del módulo, workspaces y nextest), los tests parametrizados y de tabla (se comparan por nombre base) y los nombres que se arman al correr (un id literal en TAP; las plantillas de `it.each` con comodines).

Decidido por @lautioliver en el chat, 2026-10-17, en la revisión del PR lautioliver/barrilete-kit#164: en cargo, el atributo de test se lee en el archivo del commit en rojo, justo encima del `fn` agregado (git puede mostrarlo como línea de contexto cuando el test nuevo se inserta antes de otro con el mismo atributo; un `fn` sin el atributo, como un stub, sigue sin contar), lo que es más flojo que "en las líneas agregadas" y se aprueba como tal; D6 no se enmienda acá (el comportamiento más acotado de `ERR` en tap.sh se rediseña en lautioliver/barrilete-kit#165).

Refinamientos escritos al implementar lautioliver/barrilete-kit#150 y no decididos por separado por la persona. Solo hacen las reglas más estrictas o dicen cómo se lee la salida de un reporter; `scripts/agents/red_report.py` y el corpus son su detalle: una `failure` que no es un test cuenta como `error` (vitest reporta un archivo que no cargó como un caso con el nombre del archivo; gotestsum reporta un paquete que falló fuera de todo test como `TestMain`); se rechaza un `testsuite` que declara más `failures` o `errors` de los que traen sus casos, o que tiene un `error` o `failure` fuera de todo caso; en un paquete de go un archivo nuevo no vuelve nuevos todos los casos del paquete; no se asocia un `file` con el que terminan dos archivos del repositorio; `red.sh` rechaza cambios sin commitear en archivos versionados, porque valida el commit y no el árbol de trabajo; se rechaza un reporte con bytes NUL (UTF-16 sin BOM parece UTF-8); con `format: "tap"`, `red.sh` exporta `TAP_OUT` con la ruta de `{out}`. Se aprueban al mergear el PR de lautioliver/barrilete-kit#150.

Decidido por @lautioliver en el chat, 2026-10-17, en la revisión del PR lautioliver/barrilete-kit#164 (lo registra lautioliver/barrilete-kit#166): la sección `red` propia del kit en agents-map.json, con la entrada `bash` para sus `test-*.sh`, se agrega en lautioliver/barrilete-kit#164 para que el repo tenga un rojo que funcione cuando ese PR se mergee, en vez de esperar a lautioliver/barrilete-kit#152, #153 y #154. D7 trata un cambio en `red` como sensible, y esta es su aprobación. La entrada corre solo los `test-*.sh` que el commit agrega o cambia y, después de cada script, comprueba que dejó su línea `# file:` en `{out}`: si no la dejó (murió antes de cargar `tap.sh`), agrega un `Bail out!`, de modo que un error de carga en un script nunca queda tapado por una falla válida de otro (D3). `red_report.py` interpreta un reporte JUnit como UTF-8 sea cual sea su declaración, y rechaza la declaración de otra codificación escrita como sea (espacios o tabulaciones alrededor de `=`, un BOM antes).

Estado de la implementación: `red.sh`, `scripts/agents/red_report.py` (lautioliver/barrilete-kit#150), `tap.sh` (lautioliver/barrilete-kit#163) y la entrada `red` propia del kit ya implementan D1, D3, D4 y D5, y `red.sh` ya no recibe un comando. También están la validación de las entradas `red` en check-docs.py (D2), el valor por defecto del `init` en modo completo, el mapa mínimo del perfil chico y la guía por runner (`docs/guides/red-per-runner.es.md`) (lautioliver/barrilete-kit#152). Todavía faltan el bloque estructurado del PR y la migración de los proyectos existentes (`update`): hasta que entren los otros issues de la épica, un checkout cuyo docs/agents-map.json no tiene sección `red` recibe el rechazo con guía de D1. Esta nota la saca la enmienda que cierra lautioliver/barrilete-kit#154 (los proyectos no editan los ADRs de `kit/`, así que quedaría vieja).

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
   - **stdout y el exit code.** `run` se ejecuta con `bash -o pipefail -c`. `red.sh` no captura stdout. `format: "tap"` es el TAP del helper de D6, y `run` debe hacer que el helper escriba en `{out}`, nunca redirigir stdout (`bash tests/run.sh > {out}`): por stdout, un test que imprime líneas `ok`/`not ok` mete casos en el flujo. Un productor de TAP que solo puede escribir por stdout (`node --test`, `prove`) se convierte a JUnit. Con `pipefail`, un pipeline como `cargo test | cargo2junit > {out}` conserva el exit code de falla.
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
   - **La regla.** Un caso fallido es válido si (1) se puede asociar a un archivo (tabla de abajo), (2) ese archivo está en el diff y (3) el nombre del caso, sin sus parámetros (`test_x[1]` es `test_x`), aparece como identificador entero, en una línea agregada por el diff en ese archivo que define el test (`def`, `fn`, `func`, `it(`/`test(`, o la línea de caso de `tap.sh`), nunca en un comentario. Identificador entero: `test_parse` no coincide con un `def test_parse_empty` agregado, y una mención en un comentario o una llamada no cuenta. Para `it(`/`test(`, donde el nombre es un string, el literal entero: `it('parses')` coincide solo con una línea que tenga el literal `'parses'` (o `"parses"`), nunca con `it('parses empty input')`. En un archivo que el diff agrega, califica cada caso. Un caso cuyo cuerpo cambió pero cuyo nombre no aparece en una línea agregada que lo define se rechaza: se acepta rechazar de más, el objetivo es fallar cerrado.
   - **El nombre que se compara.** Es el nombre que aparece en el código, así que el reporter tiene que darlo así: jest-junit con `titleTemplate="{title}"` (su valor por defecto, `"{classname} {title}"`, antepone el nombre del `describe`); vitest, el último segmento del nombre, después del último ` > `; go, el primer segmento de un subtest (`TestX/case` compara `TestX`, el único con una línea `func`; una fila de tabla agregada a un `TestX` viejo que falla se rechaza: la fila no es una línea `func`, así que no se distingue de las filas viejas, y el rojo debe agregar un `TestX` nuevo). Las opciones exactas se verifican con el corpus de lautioliver/barrilete-kit#150.
   - **Tests parametrizados y de tabla** (decidido por @lautioliver en el chat, 2026-10-17). El nombre que se compara es el nombre base, sin el sufijo `[...]` de pytest ni el `/...` de go (`test_p[1-2]` es `test_p`, `TestX/row` es `TestX`). La definición del test base tiene que estar en las líneas agregadas. Un test parametrizado nuevo pasa. Una fila nueva en un test viejo se rechaza (sale con 2): se falla cerrado, porque la fila no se distingue de las filas viejas.
   - **Nombres ambiguos.** El nombre se compara sin su `describe` ni su clase, así que un nombre que aparece más de una vez entre los casos del reporte de ese archivo (`it('works')` en `describe('A')` y en `describe('B')`, `TestA::test_x` y `TestB::test_x`) es ambiguo: `red.sh` sale con 2 y dice que se renombre el test. Los casos de un mismo test parametrizado (misma clase, mismo nombre base) no son ambiguos. En go, `package x_test` y un test interno con el mismo nombre dan el mismo `classname`: el mismo nombre completo dos veces en un paquete es ambiguo.
   - **Nombres que se arman al correr** (decidido por @lautioliver en el chat, 2026-10-17). TAP: el helper de D6 recibe como primer argumento un id literal del caso, y `red.sh` compara solo ese id; la parte que varía (una variable de un bucle) va en una descripción que no se compara. `it.each` de jest y vitest: el título del código, con sus marcadores (`%s`, `$x`, `${...}`) como comodines, tiene que coincidir con el nombre entero, y la línea de la plantilla tiene que estar agregada (si la tabla ocupa varias líneas, la que la cierra, que trae el título).
   - **Fallar cerrado.** Un caso fallido que no se puede asociar a un archivo agregado o cambiado por el diff hace que `red.sh` salga con 2 y diga qué opción del reporter falta. No hay excepción por runner.
   - **Por formato.**

     | Runner | Reporter | Archivo de un caso |
     |---|---|---|
     | bash | TAP del helper de D6 | la línea de comentario `# file: <ruta>` que precede a los casos de ese script |
     | pytest | `--junitxml={out} -o junit_family=xunit1` (el `xunit2` por defecto no trae `file`) | el atributo `file` |
     | jest | `jest-junit` con `addFileAttribute=true` y `titleTemplate="{title}"` | el atributo `file` |
     | vitest | `--reporter=junit --outputFile={out}` | `classname`, que es la ruta del archivo |
     | go | `gotestsum --junitfile {out}` | `classname` es la ruta de import del paquete: se convierte en directorio con la línea `module` de `go.mod`, y el nombre tiene que aparecer en una línea agregada de un archivo `*_test.go` de ese directorio |
     | cargo | `cargo2junit` o `nextest` (`junit`) | `classname` es una ruta de módulo, no un archivo: se asocia a uno (decidido por @lautioliver en el chat, 2026-10-17). Se descarta el nombre del crate; `a::b::tests` se asocia a `src/a/b.rs` o `src/a/b/mod.rs`, y se descartan los segmentos finales de a uno (un `mod tests` en línea vive en el archivo de su padre) hasta encontrar un archivo, sin pasar de la raíz del crate: `src/lib.rs`, `src/main.rs` o `tests/<binario>.rs`. Los workspaces se resuelven con los miembros del `Cargo.toml` raíz. Con nextest, el crate y el binario salen del id del binario en `classname` y la ruta del módulo sale del nombre. El identificador entero tiene que aparecer en una línea `fn` agregada de ese archivo, con un atributo de test encima: `#[test]`, o uno que termine en `test]` como `#[tokio::test]` (un `fn` sin él, por ejemplo un stub, no cuenta); y el archivo tiene que estar en el diff. Si no se resuelve a un archivo, `red.sh` sale con 2. El corpus verifica el `classname` exacto que escribe cada reporter |

     Cualquier otro runner sigue la misma regla: si da `file`, o un `classname` que es una ruta, se usa; si no, hay que configurar el reporter para que lo dé, o el rojo se rechaza.
   - **TAP.** Un solo flujo para toda la corrida, con un único plan; el helper escribe `# file: <ruta>` antes de los casos de cada script. Un `not ok` sin un `# file:` antes no se puede asociar: sale con 2. El id de un caso es el texto de su línea `ok N - <id>` con los escapes de TAP 14 deshechos (`\#` es `#`, `\\` es `\`), y `red.sh` lo compara con el primer argumento literal de `tap_ok`, `tap_fail` o `tap_check` en una línea agregada: una línea que solo menciona el id (un `echo`, una variable) no define el caso. Lo que varía al correr va en líneas `# desc:`, que no se comparan (`not ok 3 - lang-installs`, y después `# desc: installs fr`); un id repetido es un solo caso.

5. **D5. Timeout: 600 s por defecto, configurable con `"timeout"` (en segundos) en cada entrada de `red`.** Cubre la corrida completa, no cada caso. Se aplica con Python, porque `timeout` no existe en macOS. `run` arranca en su propio grupo de procesos, y al vencer el timeout `red.sh` mata todo el grupo, no solo al hijo, para que ningún runner siga escribiendo en `{out}`. Tras un timeout, `red.sh` sale con 2.

6. **D6. Los tests del kit usan la misma regla que exige.** Un helper, scripts/agents/tap.sh (lo crea lautioliver/barrilete-kit#151), escribe TAP 14: `ok N - x`, `not ok N - x`, `# file: <script>` antes de los casos de cada script, un único plan `1..N`, y `Bail out!` ante un error inesperado vía `trap ERR`. El helper escribe en un archivo que crea `red.sh` (`{out}`), nunca por stdout: así un test que imprime líneas `ok`/`not ok` por accidente no puede meter casos. Un test corre en el mismo shell que `tap.sh`, así que puede ver la ruta: una escritura deliberada en el archivo no queda cerrada, y lautioliver/barrilete-kit#151 debería mantener la ruta fuera del alcance del test donde pueda. Cómo recibe el helper la ruta (argumento o variable) se decide en lautioliver/barrilete-kit#151. Los 12 `test-*.sh` migran a él. `red.sh` toma un `Bail out!` como error.

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

11. **D11. Los ADRs del kit que los proyectos instalan viven en `docs/decisions/kit/`** (decidido por @lautioliver en el chat, 2026-10-17). Este ADR es `docs/decisions/kit/ADR-002-…`. Los ADRs propios del proyecto van en `docs/decisions/`, numerados desde `ADR-001` sin saltos, con independencia de los números del kit (viven en otra carpeta, así que las dos numeraciones no chocan). `check-docs.py` lee las dos carpetas, el índice lista cada ADR con su ruta, y dos ADRs con el mismo número en carpetas distintas no se confunden. El init conserva `docs/decisions/kit/` en el idioma de la instalación, como el resto de los docs. Un proyecto no debería editar los ADRs de `kit/` (es una recomendación, no algo que `check-docs.py` exija): si necesita otra regla, escribe un ADR propio que refiera al del kit. Una mención `ADR-NNN` sin carpeta se resuelve contra las dos carpetas, así que es ambigua cuando el mismo número existe en las dos; el kit cita los suyos como `kit/ADR-002`.

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

- Un rojo se acepta solo con evidencia que un agente no puede falsear por accidente con un mensaje en la salida; el revisor puede compararla. Un test que escribe a propósito el archivo del reporte queda fuera del alcance del parser: lo atrapan el bloque de D7 y la corrida del revisor.
- Cuesta trabajo inicial por proyecto: configurar el reporter. Se alivia con valores por defecto en el `init` para bash y ejemplos listos para copiar del `agents-map.json` por runner.
- Habrá rechazos falsos (un runner mal configurado no genera el reporte, o la regla por caso es más estricta que el cambio): los mensajes dicen qué configurar. Se acepta rechazar de más: fallar cerrado es el objetivo.
- Afuera: cobertura, mutation testing, reintentar tests flaky y validar el verde (eso lo sigue haciendo el CI del proyecto).
- Lo que cambia está en el resto de la épica lautioliver/barrilete-kit#148: el helper TAP y la migración de los 12 tests, `red.sh` con su parser (scripts/agents/red_report.py, lo crea lautioliver/barrilete-kit#150) y su corpus, la sección `red` y su validación, el bloque estructurado del PR y el check de `labels.yml`, la migración de los proyectos existentes (los scripts de actualización y de crecimiento, el instalador y el CHANGELOG) y la prueba de punta a punta.
