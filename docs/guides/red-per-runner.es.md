# Comando del rojo por runner

> Entradas listas para copiar en la sección `red` de `docs/agents-map.json` (ADR-002, D2 y D10). `red.sh` corre cada entrada cuyo `when` coincide con un archivo del commit del rojo y acepta solo un reporte estructurado: JUnit XML o TAP.

Cada entrada tiene `name`, `when` (globs de los archivos de test), `run` (con `{out}`: `red.sh` lo reemplaza por el camino donde hay que escribir el reporte), `format` (`junit` o `tap`) y un `timeout` opcional en segundos. No hay campo `report`. Cambiá los caminos, los globs de test y el timeout por los del proyecto. `check-docs.py` valida la sección. Las entradas son ejemplos: lo que importa son las opciones del reporter del corpus (`.claude/skills/implement-issue/corpus/`), y go y cargo solo se probaron ahí contra la salida documentada de sus herramientas.

## bash (TAP)

Un test de bash carga `scripts/agents/tap.sh` y llama `tap_check $? "id literal"` en cada caso; el id es un literal escrito en el código y lo que varía va en la descripción. `run` tiene que hacer que el helper escriba en `{out}` a través de `TAP_OUT`, nunca redirigir stdout. `run-tests.sh` representa un script tuyo que corre los `test-*.sh`.

```json
{
  "name": "bash",
  "when": [
    "**/test-*.sh"
  ],
  "format": "tap",
  "run": "TAP_OUT={out} bash run-tests.sh",
  "timeout": 600
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

Instalá `cargo2junit`. `RUSTC_BOOTSTRAP=1` habilita la salida JSON en stable. `run` corre con `pipefail`, así que el código de salida de `cargo test` sobrevive al pipe. Un test necesita su atributo `#[test]` (o uno que termine en `test]`) justo arriba del `fn` agregado.

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

Agregá un perfil a `.config/nextest.toml`: `[profile.red.junit]` con `path = "junit.xml"`. nextest escribe el reporte en `target/nextest/red/`, así que `run` lo copia a `{out}` y conserva el código de salida de los tests.

```json
{
  "name": "cargo",
  "when": [
    "**/*.rs"
  ],
  "format": "junit",
  "run": "cargo nextest run --profile red; rc=$?; cp target/nextest/red/junit.xml {out}; exit $rc",
  "timeout": 1200
}
```

## Comprobarlo

Corré `python3 scripts/agents/check-docs.py` para validar la sección, después commiteá un test que falla y corré `.claude/skills/implement-issue/red.sh [<stack>]`: el código 0 es un rojo válido.
