#!/usr/bin/env bash
# Tests de red.sh con herramientas de test simuladas: cada caso imprime la salida típica
# de pytest o vitest/jest y sale con su código, sin instalarlas.
# Uso: bash .claude/skills/implement-issue/test-red.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-red-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"  # red.sh deja ahí la salida y el bloque del PR
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }

# rojo <código esperado> <descripción> <código de salida de la herramienta> <salida de la herramienta>
rojo() {
  printf '%s\n' "$4" >"$TMP/salida.txt"
  "$AQUI/red.sh" -- bash -c "cat '$TMP/salida.txt'; exit $3" >"$TMP/out" 2>&1
  local c=$?
  if [ "$c" -eq "$1" ]; then ok "$2"; else falla "$2 (salió con $c, esperado $1)"; sed 's/^/       /' "$TMP/out"; fi
}

# pytest
rojo 2 "pytest: ImportError (la función no existe)" 2 "ImportError while importing test module '/p/test_x.py'.
E   ImportError: cannot import name 'total' from 'app' (/p/app.py)
=========================== short test summary info ============================
ERROR test_x.py
!!!!!!!!!!!!!!!!!!!! Interrupted: 1 error during collection !!!!!!!!!!!!!!!!!!!!!
1 error in 0.05s"
rojo 2 "pytest: AttributeError en el módulo" 1 "    def test_t():
>       assert app.total([1, 2]) == 3
E       AttributeError: module 'app' has no attribute 'total'
=========================== short test summary info ============================
FAILED test_x.py::test_t - AttributeError: module 'app' has no attribute 'total'
1 failed in 0.02s"
rojo 2 "pytest: archivo de test inexistente" 4 "ERROR: file or directory not found: test_x.py

no tests ran in 0.00s"
rojo 2 "pytest: NameError" 1 "E       NameError: name 'total' is not defined
FAILED test_x.py::test_t - NameError: name 'total' is not defined"
rojo 0 "pytest: aserción que falla de verdad" 1 "    def test_t():
>       assert total([1, 2]) == 3
E       assert 0 == 3
E        +  where 0 = total([1, 2])
=========================== short test summary info ============================
FAILED test_x.py::test_t - assert 0 == 3
1 failed in 0.02s"

# pytest: el test corre pero falla antes de la aserción (FAILED no alcanza como evidencia).
rojo 2 "pytest: TypeError por firma incorrecta" 1 "    def test_t():
>       assert total([1, 2], 0) == 3
E       TypeError: total() takes 1 positional argument but 2 were given
=========================== short test summary info ============================
FAILED test_x.py::test_t - TypeError: total() takes 1 positional argument but 2 were given
1 failed in 0.02s"
rojo 2 "pytest: KeyError" 1 "    def test_t():
>       assert precios['total'] == 3
E       KeyError: 'total'
=========================== short test summary info ============================
FAILED test_x.py::test_t - KeyError: 'total'
1 failed in 0.02s"
rojo 2 "pytest: AttributeError sobre un objeto (símbolo inexistente)" 1 "    def test_t():
>       assert Carrito().total() == 3
E       AttributeError: 'Carrito' object has no attribute 'total'
=========================== short test summary info ============================
FAILED test_x.py::test_t - AttributeError: 'Carrito' object has no attribute 'total'
1 failed in 0.02s"

# pytest: rojos válidos que no traen "E   assert".
rojo 0 "pytest: pytest.raises que no se cumple" 1 "    def test_t():
        with pytest.raises(ValueError):
>           validar(-1)
E           Failed: DID NOT RAISE <class 'ValueError'>
=========================== short test summary info ============================
FAILED test_x.py::test_t - Failed: DID NOT RAISE <class 'ValueError'>
1 failed in 0.02s"
rojo 0 "pytest --tb=line: la aserción solo está en el resumen" 1 "/p/test_x.py:3: assert 0 == 3
=========================== short test summary info ============================
FAILED test_x.py::test_t - assert 0 == 3
1 failed in 0.02s"
rojo 0 "pytest con color: la línea E empieza con códigos ANSI" 1 "$(printf '\033[1m\033[31mE       assert 0 == 3\033[0m\nFAILED test_x.py::test_t - assert 0 == 3')"

# vitest / jest
rojo 2 "vitest: TypeError sobre undefined" 1 " FAIL  src/suma.test.ts > suma > suma dos números
TypeError: Cannot read properties of undefined (reading 'total')
 ❯ src/suma.test.ts:5:23
 × suma > suma dos números
 Test Files  1 failed (1)"
rojo 0 "vitest: aserción que falla de verdad" 1 " FAIL  src/suma.test.ts > suma > suma dos números
AssertionError: expected 0 to be 3 // Object.is equality

- Expected
+ Received

- 3
+ 0

 ❯ src/suma.test.ts:5:23
 Test Files  1 failed (1)"
rojo 2 "vitest: Cannot find module" 1 " FAIL  src/suma.test.ts [ src/suma.test.ts ]
Error: Cannot find module './suma' imported from /p/src/suma.test.ts
 Test Files  1 failed (1)"
rojo 2 "jest: No tests found" 1 "No tests found, exiting with code 1
Run with \`--passWithNoTests\` to exit with code 0"

# Los test-*.sh de la plantilla (ok/FAIL con afirmar)
rojo 0 "test-*.sh: una afirmación que falla" 1 "ok   - crea la rama
FAIL - asigna el issue

1 test(s) fallaron."

# Otros formatos de test-*.sh (#143): "FAIL: msg" en inglés y "FALLA - msg" / "FALLO: msg" en español.
rojo 0 "test-*.sh: FAIL: con dos puntos" 1 "ok   - crea la rama
FAIL: asigna el issue"
rojo 0 "test-*.sh: FALLA - en español" 1 "ok   - crea la rama
FALLA - asigna el issue"
rojo 0 "test-*.sh: FALLO: en español con dos puntos" 1 "FALLO: asigna el issue"
rojo 2 "test-*.sh: FAIL sin separador no se da por buena" 1 "FAIL asigna el issue"
rojo 2 "una línea FAIL: con un error de carga no es una aserción" 1 "FAIL: asigna el issue
ModuleNotFoundError: No module named 'x'"

# #143 (revisión): un FAIL: pelado lo imprimen automake y Bazel para cualquier falla (un crash, un error de carga): no es una aserción.
rojo 2 "automake: FAIL: <test> con el resumen de make check" 1 "FAIL: test_parser
============================================================================
# TOTAL: 1
# PASS:  0
# FAIL:  1"
rojo 2 "Bazel: FAIL: //src:parser_test (see test.log)" 1 "FAIL: //src:parser_test (see /x/testlogs/test.log)"
rojo 2 "un segfault con FAIL:" 1 "Segmentation fault (core dumped)
FAIL: test_parser"
# Errores de carga de un test bash (con cualquiera de los formatos): el script no corrió, no hay aserción.
for e in "bash: ./scripts/new.sh: No such file or directory" "./test.sh: line 4: foo: command not found" "./test.sh: line 4: syntax error near unexpected token" "./test.sh: line 9: x: unbound variable"; do
  rojo 2 "bash: '$e' con FAIL: no es rojo" 1 "$e
FAIL: asigna el issue"
  rojo 2 "bash: '$e' con FAIL - no es rojo" 1 "$e
FAIL - asigna el issue"
  rojo 2 "bash: '$e' con FALLÓ: no es rojo" 1 "$e
FALLÓ: asigna el issue"
done
# El resumen no se llena con palabras que empiezan con FALL (FALLBACK…): la falla real entra en el bloque.
{ for _ in $(seq 1 45); do echo "FALLBACK paso"; done; echo "FAIL - la falla real"; } >"$TMP/salida.txt"
s=$("$AQUI/red.sh" -- bash -c "cat '$TMP/salida.txt'; exit 1" 2>&1)
if grep -q 'la falla real' <<<"$s"; then ok "FALLBACK no desplaza la falla real del resumen"; else falla "FALLBACK no desplaza la falla real del resumen"; fi

# Cualquier herramienta
rojo 2 "comando inexistente (exit 127)" 127 "bash: comando-que-no-existe: command not found"
rojo 2 "comando sin permiso de ejecución (exit 126)" 126 "bash: ./test.sh: Permission denied"
rojo 2 "una falla desconocida no se da por buena" 1 "Segmentation fault (core dumped)"
rojo 1 "los tests pasan: no prueban nada" 0 "1 passed in 0.01s"

printf '%s\n' "Segmentation fault" >"$TMP/salida.txt"
s=$("$AQUI/red.sh" -- bash -c "cat '$TMP/salida.txt'; exit 1" 2>&1)
if grep -q "I do not recognize this failure as an assertion" <<<"$s"; then ok "una falla desconocida explica qué hacer"; else falla "una falla desconocida explica qué hacer"; fi

# La instalación en inglés no trae español en el uso ni en los comentarios de red.sh (#143).
s=$("$AQUI/red.sh" 2>&1); if grep -q '^Usage: .*red.sh -- <test command>' <<<"$s"; then ok "red.sh sin argumentos imprime el uso en inglés"; else falla "red.sh sin argumentos imprime el uso en inglés"; fi
if ! grep -Eqi 'Uso:|ej\.:|comando de test|módulo|Sale con|Ni a ' "$AQUI/red.sh"; then ok "red.sh no tiene español en su uso ni en sus comentarios"; else falla "red.sh no tiene español en su uso ni en sus comentarios"; grep -Ein 'Uso:|ej\.:|comando de test|módulo' "$AQUI/red.sh"; fi
if compgen -G "$TMP/red-*" >/dev/null; then ok "los archivos temporales de red.sh se llaman red-*"; else falla "los archivos temporales de red.sh se llaman red-*"; fi

# El bloque para el PR lleva el literal inglés que lee el CI (#115): "Red before implementing".
bloque=$(cat "$TMP"/*.md 2>/dev/null)
if grep -q '<summary>Red before implementing</summary>' <<<"$bloque" && ! grep -q 'Rojo antes de implementar' <<<"$bloque"; then ok "el bloque del PR usa el literal Red before implementing"; else falla "el bloque del PR usa el literal Red before implementing"; fi

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
