# Comando del rojo por runner

> Entradas listas para copiar en la sección `red` de `docs/agents-map.json` (ADR-002, D2 y D10). `red.sh` corre cada entrada cuyo `when` coincide con un archivo del commit del rojo y acepta solo un reporte estructurado: JUnit XML.

Cada entrada tiene `name`, `when` (globs de los archivos de test), `run` (con `{out}`: `red.sh` lo reemplaza por el camino donde hay que escribir el reporte), `format` (`junit`) y un `timeout` opcional en segundos. No hay campo `report`. Cambiá los caminos, los globs de test y el timeout por los del proyecto. El `when` de una entrada tiene que coincidir solo con los archivos que corre ese runner: `red.sh` toma cada archivo de test del commit del rojo que `when` abarca (por los nombres de todos los runners de referencia: `test-*.sh`, `test_*.py`, `*.spec.ts`…) como un archivo que esa entrada tenía que correr, así que una entrada de jest con `**/*.ts` falla con un `e2e/x.spec.ts` de Playwright que jest nunca corrió ("not in the report"), y una entrada con `when: **` falla con un `test-x.sh` que solo corre la entrada bash. `check-docs.py` valida la sección. Las entradas son ejemplos: lo que importa son las opciones del reporter. Se probaron contra el corpus de regresión del repo del kit (`.claude/skills/implement-issue/corpus/` allá; no se instala en los proyectos), y go y cargo solo contra la salida documentada de sus herramientas.

**`format: "tap"` salió en 2.0.0** (ADR-002, D8). Un mapa con una entrada en `format: "tap"` se rechaza, aunque esa entrada no coincida con el commit: `red.sh` sale con 2 antes de correr nada y `check-docs.py` lo informa como error, los dos con `red stack '<name>': format "tap" was removed in 2.0.0; use "junit" (docs/guides/red-per-runner.md)`. Pasá la entrada a una de JUnit de la lista de abajo. El check de CI del cuerpo del PR (`labels.yml`) también rechaza un bloque del rojo con `format: tap`: después de pasar la entrada, volvé a correr `red.sh` y pegá el bloque nuevo. `update.py` reemplaza solo la entrada `bash` del kit; nunca convierte, borra ni reescribe otra entrada `tap`: la conserva y te lo dice al final de su resumen.

## bash (JUnit desde `tap.sh`)

Un test de bash carga `scripts/agents/tap.sh` y llama `tap_check $? "id literal"` en cada caso; el id es un literal escrito en el código y lo que varía va en la descripción. Límite conocido: todo caso de un archivo `.sh` en un reporte JUnit se lee como un id de `tap.sh`, así que otro productor (shunit2 con un reporter JUnit) se rechaza como "not defined by a line this commit adds". Esta es la entrada que el kit trae en el `docs/agents-map.json` por defecto. Corre solo los `test-*.sh` que el commit del rojo agrega o cambia, cada uno con `TAP_OUT=$tmp` (el helper agrega ahí un `<testsuite file="<script>">` cerrado con un `<testcase>` por caso y un testcase con `<error>` si hay un crash, o un segundo testsuite con solo ese testcase `<error>` si el crash llega después de `tap_done`; `red.sh` además exporta `TAP_FORMAT=junit`), y al final envuelve los testsuites en `<testsuites>` en `{out}`. El helper nunca escribe la raíz, así que varios scripts pueden compartir el archivo. Un script que muere antes de cargar `tap.sh` no deja testsuite, y `red.sh` rechaza el rojo porque ese archivo de test del diff no está en el reporte: la entrada no necesita ningún `grep` sobre `{out}`. Sin `TAP_OUT` (una persona corriendo el test) el helper imprime TAP por stdout.

```json
{
  "name": "bash",
  "when": [
    "**/test-*.sh"
  ],
  "format": "junit",
  "run": "rc=0; tmp=$(mktemp); trap 'rm -f \"$tmp\"' EXIT; while IFS= read -r -d '' t; do TAP_OUT=$tmp bash \"$t\" </dev/null || rc=1; done < <(git diff -z --name-only --diff-filter=AMRC HEAD^ HEAD -- ':(glob)**/test-*.sh'); { echo '<testsuites>'; cat \"$tmp\"; echo '</testsuites>'; } >{out}; exit $rc",
  "timeout": 1800
}
```

## pytest

Hace falta `junit_family=xunit1`: el `xunit2` por defecto no tiene el atributo `file`, y sin él `red.sh` no sabe a qué archivo pertenece un caso fallido.

```json
{
  "name": "pytest",
  "when": [
    "**/test_*.py",
    "**/*_test.py"
  ],
  "format": "junit",
  "run": "python3 -m pytest --junitxml={out} -o junit_family=xunit1",
  "timeout": 600
}
```

## vitest

El reporter escribe el archivo de cada caso en `classname`. No hace falta nada más.

```json
{
  "name": "vitest",
  "when": [
    "**/*.test.ts",
    "**/*.test.tsx"
  ],
  "format": "junit",
  "run": "npx vitest run --reporter=junit --outputFile={out}",
  "timeout": 600
}
```

## jest

Instalá `jest-junit`. `JEST_JUNIT_TITLE='{title}'` deja el nombre como está en el código (el por defecto le antepone el nombre del `describe`); `JEST_JUNIT_ADD_FILE_ATTRIBUTE` escribe el archivo; `JEST_JUNIT_REPORT_TEST_SUITE_ERRORS` reporta como error un archivo de test que no cargó, así `red.sh` lo rechaza en vez de leer un reporte verde.

```json
{
  "name": "jest",
  "when": [
    "**/*.test.js",
    "**/*.test.ts"
  ],
  "format": "junit",
  "run": "JEST_JUNIT_OUTPUT_FILE={out} JEST_JUNIT_ADD_FILE_ATTRIBUTE=true JEST_JUNIT_TITLE='{title}' JEST_JUNIT_REPORT_TEST_SUITE_ERRORS=true npx jest --reporters=jest-junit",
  "timeout": 600
}
```

## go (gotestsum)

Instalá `gotestsum`. Una fila de tabla agregada a un test viejo que falla se rechaza: el rojo tiene que agregar una función `TestX` nueva.

```json
{
  "name": "go",
  "when": [
    "**/*_test.go"
  ],
  "format": "junit",
  "run": "gotestsum --junitfile {out} ./...",
  "timeout": 600
}
```

## cargo (cargo2junit)

Instalá `cargo2junit`. `RUSTC_BOOTSTRAP=1` habilita la salida JSON en stable. `run` corre con `pipefail`, así que el código de salida de `cargo test` sobrevive al pipe. Un test necesita su atributo `#[test]` (o uno que termine en `test]`) justo arriba del `fn` agregado. Límite conocido: cargo2junit no dice qué binario corrió un test, así que un caso de `tests/api.rs` se asocia a `src/lib.rs` y los tests de integración del commit del rojo no se "ven" (`red.sh` rechaza el rojo como "not in the report"). Usá nextest cuando el rojo toca `tests/`.

```json
{
  "name": "cargo",
  "when": [
    "**/*.rs"
  ],
  "format": "junit",
  "run": "RUSTC_BOOTSTRAP=1 cargo test -- -Z unstable-options --format json | cargo2junit > {out}",
  "timeout": 1200
}
```

## cargo (nextest)

Agregá un perfil a `.config/nextest.toml`: `[profile.red.junit]` con `path = "junit.xml"`. nextest escribe el reporte en `target/nextest/red/`, así que `run` lo copia a `{out}` y conserva el código de salida de los tests. El `rm -f` corre primero para que un build fallido no deje un reporte de una corrida anterior para copiar. Esta entrada está sin verificar: el comando, la ruta del perfil y la copia nunca se corrieron acá (el corpus del kit tiene solo un reporte de nextest escrito a mano).

```json
{
  "name": "cargo-nextest",
  "when": [
    "**/*.rs"
  ],
  "format": "junit",
  "run": "rm -f target/nextest/red/junit.xml; cargo nextest run --profile red; rc=$?; cp target/nextest/red/junit.xml {out}; exit $rc",
  "timeout": 1200
}
```

## Dependencias en un worktree nuevo

Un worktree nuevo no tiene `.venv` ni `node_modules`, y las entradas de arriba los necesitan (`.venv/bin/python`, `npx vitest`). El **implementador** los instala en su worktree antes del rojo (`python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`, `npm ci`). El **revisor** los instala en su worktree de revisión sin correr código del PR: `npm ci --ignore-scripts` (solo si el PR no cambia `package.json`, el lock ni `.npmrc`) o `python3 -m venv .venv && .venv/bin/pip install --only-binary=:all: -r requirements.txt` (solo si el PR no cambia `requirements*.txt`, `pyproject.toml` ni `setup.*`: pip no tiene `--ignore-scripts`, y una compilación desde fuente o `-e .` correría el backend de build del PR). Si el PR cambia esos archivos, no instala, lo marca, y la verificación del TDD queda sin comprobar hasta que decida una persona. Nunca corre el instalador ni los scripts del propio PR.

## Comprobarlo

Corré `python3 scripts/agents/check-docs.py` para validar la sección, después commiteá un test que falla y corré `.claude/skills/implement-issue/red.sh [<stack>]`: el código 0 es un rojo válido.
