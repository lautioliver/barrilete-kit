#!/usr/bin/env bash
# TDD: runs the freshly written tests BEFORE implementing and requires them to fail,
# for the right reason (a behavior assertion, not a broken import).
# Leaves a block ready to paste into "Cómo probarlo" of the PR.
# Uso: red.sh -- <comando de test>
#   ej.: red.sh -- npx vitest run src/modulo
# Exits with 0 if it is red because of an assertion; 1 if the tests pass; 2 if they fail
# for another reason (the command did not run, loading, syntax, missing symbol) or for
# a failure it does not recognize as an assertion.
set -uo pipefail
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "Uso: $0 -- <comando de test>" >&2; exit 64; }

salida=$(mktemp "${TMPDIR:-/tmp}/rojo-XXXXXX")
"$@" >"$salida" 2>&1
codigo=$?
# Without ANSI colors (pytest with PY_COLORS=1, vitest): otherwise "^E +assert" does not recognize the line.
esc=$(printf '\033')
LC_ALL=C sed "s/${esc}\[[0-9;]*m//g" "$salida" >"$salida.limpia" && mv "$salida.limpia" "$salida"

if [ "$codigo" -eq 0 ]; then
  echo "The tests PASS without the new code: they prove nothing."
  echo "Check that they exercise the acceptance criterion (full output: $salida)."
  exit 1
fi

# 1. The command did not even run (it does not exist or cannot be executed).
if [ "$codigo" -eq 126 ] || [ "$codigo" -eq 127 ]; then
  echo "The test command did not run (exit code $codigo): check that it exists and can be executed."
  echo "Output: $salida"
  exit 2
fi

# 2. Loading failures: the test never reached the assertion. They go before the assertions because
#    pytest also marks these as FAILED.
mala='Cannot find module|Failed to resolve import|ERR_MODULE_NOT_FOUND|SyntaxError|ReferenceError|is not defined|is not a function|is not a constructor|Transform failed|error TS[0-9]{4}'
mala+='|ImportError|ModuleNotFoundError|IndentationError|AttributeError: module|NameError|ERROR collecting|no tests ran|collected 0 items|No test files found|No tests found'
# Missing symbol or wrong signature: the test runs, but breaks before the assertion.
mala+="|AttributeError: '[^']*' object has no attribute|TypeError: .*(takes [0-9]+ positional argument|missing [0-9]+ required|unexpected keyword argument|Cannot read propert(y|ies) of (undefined|null))"
if grep -Eq "$mala" "$salida"; then
  echo "The tests fail, but for a reason that is not the behavior:"
  grep -E "$mala" "$salida" | sort -u | head -5 | sed 's/^/  /'
  echo "Add the minimum so they load (the function signature, the field in the schema)"
  echo "and run again: they must fail on an assertion of the criterion. Output: $salida"
  exit 2
fi

# 3. Positive evidence of an assertion. Without it the red is not accepted (a KeyError, for
#    example, exits with 2). FAILED (pytest) and ×/✗ (vitest) mark any failing test, not
#    an assertion: they are not enough. "E   assert" is the pytest line with the assertion that failed
#    (">   assert" is the test code); with --tb=line it only remains in the summary (FAILED … - assert).
#    DID NOT RAISE is a pytest.raises that was not met. ^FAIL - is the format of the test-*.sh.
aserciones='AssertionError|^E +assert |FAILED .*::[^ ]* - (assert |AssertionError)|DID NOT RAISE|Expected|Received|expected .* to|^FAIL - '
if ! grep -Eq "$aserciones" "$salida"; then
  echo "The tests fail, but I do not recognize this failure as an assertion; check it and, if it is valid,"
  echo "add the pattern to red.sh. Last lines:"
  tail -5 "$salida" | sed 's/^/  /'
  echo "Full output: $salida"
  exit 2
fi

resumen=$(grep -E "FAIL|$aserciones" "$salida" | head -40)
fallas="${resumen:-$(tail -20 "$salida")}"
pr="${salida}.md"
{
  echo "<details><summary>Rojo antes de implementar</summary>"
  echo
  echo '```'
  echo "\$ $*"
  echo "$fallas"
  echo '```'
  echo
  echo "</details>"
} >"$pr"
echo "Red. Failures:"
while IFS= read -r linea; do printf '  %s\n' "$linea"; done <<<"$fallas"
echo
echo "Confirm that each failure is an assertion of an acceptance criterion."
echo "Block for \"Cómo probarlo\" in the PR: $pr"
