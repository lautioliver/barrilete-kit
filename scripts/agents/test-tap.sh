#!/usr/bin/env bash
# Tests of the TAP helper (scripts/agents/tap.sh, ADR-002 D6, issue #151): format, plan, Bail out!,
# the output file out of the test's reach, and that the kit's own tests use it.
# Usage: bash scripts/agents/test-tap.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-tap-XXXXXX")" && pwd -P)
# shellcheck source=scripts/agents/tap.sh
. "$ROOT/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit 'rm -rf "$TMP"'
# Usage: <condition>; check $? "literal id" ["description"]
check() { tap_check "$@"; }

# Runs a test script that sources the helper. $1 is its body (after the helper is loaded).
# Leaves $TMP/rc (exit code), $TMP/stdout, $TMP/stderr and, if $2 is "file", $TMP/tap (the TAP file).
run_tap() {
  {
    printf '#!/usr/bin/env bash\nset -uo pipefail\n. "%s/scripts/agents/tap.sh"\ntap_begin "$0"\n' "$ROOT"
    printf '%s\n' "$1"
  } >"$TMP/t.sh"
  rm -f "$TMP/tap"
  if [ "${2:-}" = "file" ]; then
    (cd "$ROOT" && TAP_OUT="$TMP/tap" bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"); echo $? >"$TMP/rc"
  else
    (cd "$ROOT" && env -u TAP_OUT bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"); echo $? >"$TMP/rc"
  fi
}
rc() { cat "$TMP/rc"; }
has() { grep -qxF -- "$1" "$2" 2>/dev/null; }
# Usage: count <regex> <file>: how many lines match (0 if the file does not exist).
count() { local n; n=$(grep -c -- "$1" "$2" 2>/dev/null); echo "${n:-0}"; }
# Usage: line_of <regex> <file>: the number of the first line that matches (0 if none).
line_of() { local n; n=$(grep -n -- "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1); echo "${n:-0}"; }
nogrep() { ! grep -q -- "$1" "$2" 2>/dev/null; }
has_bail() { grep -q "^Bail out!" "$TMP/tap" 2>/dev/null; }
has_cleaned() { grep -q "^cleaned" "$TMP/stderr" 2>/dev/null; }

# 1. Format and plan, in the file.
run_tap 'tap_ok "creates the branch"
tap_ok "assigns the issue"
tap_done' file
has "ok 1 - creates the branch" "$TMP/tap"; check $? "writes ok N - id for a passing case"
has "ok 2 - assigns the issue" "$TMP/tap"; check $? "numbers the cases from 1, in order"
has "1..2" "$TMP/tap"; check $? "writes the plan 1..N with the number of cases"
[ "$(count '^1\.\.' "$TMP/tap")" -eq 1 ]; check $? "writes a single plan"
[ "$(rc)" -eq 0 ]; check $? "exits with 0 when every case passes"
[ ! -s "$TMP/stdout" ]; check $? "writes nothing to stdout when it has an output file"

run_tap 'tap_ok "first"
tap_fail "second"
tap_ok "third"
tap_done' file
has "not ok 2 - second" "$TMP/tap"; check $? "writes not ok N - id for a failing case"
has "1..3" "$TMP/tap"; check $? "the plan counts the failing cases too"
[ "$(rc)" -eq 1 ]; check $? "exits with 1 when a case fails"
has "FAIL - second" "$TMP/stderr"; check $? "reports a failing case on stderr as FAIL - id, for the CI log"

run_tap 'true; tap_check $? "passes by status"
false; tap_check $? "fails by status"
tap_done' file
has "ok 1 - passes by status" "$TMP/tap" && has "not ok 2 - fails by status" "$TMP/tap"; check $? "tap_check turns a status into ok or not ok"
[ "$(rc)" -eq 1 ]; check $? "a failing command that the test checks with its status is not an unexpected error"
nogrep '^Bail out!' "$TMP/tap" && has "ok 1 - passes by status" "$TMP/tap"; check $? "a checked failure does not emit Bail out!"

# 2. The script of the cases: # file: before them.
run_tap 'tap_ok "x"
tap_done' file
grep -q '^# file: ' "$TMP/tap" 2>/dev/null; check $? "writes a # file: line"
[ "$(line_of '^# file: ' "$TMP/tap")" -gt 0 ] && [ "$(line_of '^# file: ' "$TMP/tap")" -lt "$(line_of '^ok 1' "$TMP/tap")" ]; check $? "the # file: line comes before the cases"
git init -q "$TMP/repo" && mkdir -p "$TMP/repo/sub"
printf '#!/usr/bin/env bash\n. "%s/scripts/agents/tap.sh"\ntap_begin "$0"\ntap_ok "x"\ntap_done\n' "$ROOT" >"$TMP/repo/sub/test-demo.sh"
(cd "$TMP/repo" && TAP_OUT="$TMP/tap2" bash sub/test-demo.sh)
has "# file: sub/test-demo.sh" "$TMP/tap2"; check $? "the # file: path is relative to the repository root"

# 3. Description: not compared, apart from the id.
run_tap 'v=42
tap_fail "literal id" "varies with $v"
tap_done' file
has "not ok 1 - literal id" "$TMP/tap"; check $? "the id is the whole text of the case line"
has "# desc: varies with 42" "$TMP/tap" && has "not ok 1 - literal id" "$TMP/tap" && nogrep '^not ok.*42' "$TMP/tap"; check $? "the description goes in its own line, not in the case line"
has '# desc: varies with 42' "$TMP/tap"; check $? "the description line is a # desc: comment"

# 4. Without an output file the TAP goes to stdout (a person running the test).
run_tap 'tap_ok "by hand"
tap_done'
has "ok 1 - by hand" "$TMP/stdout" && has "1..1" "$TMP/stdout"; check $? "without TAP_OUT, writes the TAP to stdout"

# 5. The path stays out of the test's reach, and its stdout cannot inject cases.
run_tap 'echo "path=[${TAP_OUT:-unset}]" >&2
echo "ok 99 - injected"
echo "not ok 98 - injected"
echo "1..99"
tap_ok "real"
tap_done' file
has "path=[unset]" "$TMP/stderr"; check $? "the test does not see TAP_OUT after loading the helper"
nogrep injected "$TMP/tap" && has "ok 1 - real" "$TMP/tap"; check $? "lines that the test prints on stdout do not reach the TAP file"
[ "$(count '^ok \|^not ok ' "$TMP/tap")" -eq 1 ]; check $? "only the cases of the helper are in the file"
run_tap 'echo "$TAP_OUT" >&2; tap_done' file
[ -s "$TMP/tap" ]; check $? "the helper wrote to the file it was given"

# 6. Bail out! on an unexpected error.
run_tap 'set -e
tap_ok "before"
false
tap_ok "after"
tap_done' file
has_bail; check $? "an unexpected error under set -e emits Bail out!"
[ "$(rc)" -ne 0 ]; check $? "an unexpected error under set -e exits non-zero"
has "ok 1 - before" "$TMP/tap" && nogrep '^1\.\.' "$TMP/tap"; check $? "a bailed run has no plan"
has "ok 1 - before" "$TMP/tap" && ! has "ok 2 - after" "$TMP/tap"; check $? "nothing runs after the error"

run_tap 'tap_ok "before"
echo "$undefined_variable" >/dev/null
tap_ok "after"
tap_done' file
has_bail; check $? "an unbound variable emits Bail out!"
[ "$(rc)" -ne 0 ]; check $? "an unbound variable exits non-zero"

run_tap 'tap_ok "before"
exit 3' file
has_bail; check $? "leaving before tap_done emits Bail out!"
[ "$(rc)" -eq 3 ]; check $? "leaving before tap_done keeps the exit code"

run_tap 'tap_ok "before"
exit 0' file
has_bail; check $? "an exit 0 before tap_done is still a Bail out!"
[ "$(rc)" -ne 0 ]; check $? "an exit 0 before tap_done is turned into a failure"

run_tap 'tap_at_exit "echo cleaned >&2"
tap_ok "x"
false || exit 5' file
has_cleaned; check $? "the at-exit command also runs when the run bails out"
run_tap 'tap_at_exit "echo cleaned >&2"
tap_ok "x"
tap_done' file
has_cleaned && [ "$(rc)" -eq 0 ]; check $? "the at-exit command runs at the end of a normal run"

# 7. Ids are literal and unique.
run_tap 'tap_ok "same"
tap_ok "same"
tap_done' file
has_bail && [ "$(rc)" -ne 0 ]; check $? "a repeated id emits Bail out! (red.sh rejects ambiguous names)"
run_tap 'tap_ok "line one
line two"
tap_done' file
has_bail && [ "$(rc)" -ne 0 ]; check $? "an id with a newline emits Bail out! (it could inject a line)"
run_tap 'tap_ok ""
tap_done' file
has_bail && [ "$(rc)" -ne 0 ]; check $? "an empty id emits Bail out!"
run_tap 'tap_ok "fixes #12"
tap_done' file
has 'ok 1 - fixes \#12' "$TMP/tap"; check $? "a # in the id is escaped, as TAP 14 asks"

# 8. A script with nothing to run.
run_tap 'tap_skip_all "does not apply here"' file
has "1..0 # SKIP does not apply here" "$TMP/tap" && [ "$(rc)" -eq 0 ]; check $? "tap_skip_all writes 1..0 # SKIP and exits with 0"

# 9. The kit's own tests use the helper (what the issue migrates).
SCRIPTS=$(cd "$ROOT" && find scripts .claude -name 'test-*.sh' ! -name test-tap.sh ! -name test-red.sh | sort)
n=0; sin=""
for s in $SCRIPTS; do n=$((n + 1)); grep -q 'agents/tap\.sh' "$ROOT/$s" || sin="$sin $s"; done
[ -z "$sin" ] && [ "$n" -ge 11 ]; check $? "every test-*.sh of the kit loads tap.sh (missing:${sin:- none})"
propios=""
for s in $SCRIPTS; do grep -qE '^(ok|falla|fail)\(\)' "$ROOT/$s" && propios="$propios $s"; done
[ -z "$propios" ]; check $? "no test-*.sh defines its own ok()/falla()/fail() (still:${propios:- none})"
dinamicos=""
for s in $SCRIPTS; do
  grep -nE 'tap_(ok|fail) "[^"]*\$|tap_check [^ ]+ "[^"]*\$' "$ROOT/$s" | grep -vE 'tap_(ok|fail) "\$[0-9@*]"|tap_check [^ ]+ "\$[0-9@*]"' >"$TMP/dyn" && dinamicos="$dinamicos $s:$(head -1 "$TMP/dyn" | cut -d: -f1)"
done
[ -z "$dinamicos" ]; check $? "the id of each case is a literal, never built at run time (first offender:${dinamicos:- none})"

tap_done
