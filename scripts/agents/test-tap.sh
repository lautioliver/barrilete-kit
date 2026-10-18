#!/usr/bin/env bash
# Tests of the TAP helper (scripts/agents/tap.sh, ADR-002 D6, issue #151): format, plan, Bail out!,
# the output file out of the test's reach, and that the kit's own tests use it.
# Usage: bash scripts/agents/test-tap.sh
# shellcheck disable=SC2016  # the scripts under test are written in single quotes on purpose
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-tap-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
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
  { run_tap_child "$@"; } 2>/dev/null
}
run_tap_child() {
  if [ "${2:-}" = "dir" ]; then
    (cd "$ROOT" && TAP_OUT="$TMP" bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"); echo $? >"$TMP/rc"
  elif [ "${2:-}" = "file" ]; then
    (cd "$ROOT" && TAP_OUT="$TMP/tap" bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"); echo $? >"$TMP/rc"
  else
    (cd "$ROOT" && env -u TAP_OUT bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"); echo $? >"$TMP/rc"
  fi
}
rc_is() { [ "$(cat "$TMP/rc")" -eq "$1" ]; }
rc_not() { [ "$(cat "$TMP/rc")" -ne "$1" ]; }
# Usage: count_is <n> <regex> <file>
count_is() { [ "$(count "$2" "$3")" -eq "$1" ]; }
has() { grep -qxF -- "$1" "$2" 2>/dev/null; }
# Usage: count <regex> <file>: how many lines match (0 if the file does not exist).
count() { local n; n=$(grep -c -- "$1" "$2" 2>/dev/null); echo "${n:-0}"; }
# Usage: line_of <regex> <file>: the number of the first line that matches (0 if none).
line_of() { local n; n=$(grep -n -- "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1); echo "${n:-0}"; }
before_cases() { local f; f=$(line_of '^# file: ' "$TMP/tap"); [ "$f" -gt 0 ] && [ "$f" -lt "$(line_of '^ok 1' "$TMP/tap")" ]; }
empty() { [ ! -s "$1" ]; }
nonempty() { [ -s "$1" ]; }
nogrep() { ! grep -q -- "$1" "$2" 2>/dev/null; }
has_msg() { grep -q -- "$1" "$TMP/stderr" 2>/dev/null; }
has_bail() { grep -q "^Bail out!" "$TMP/tap" 2>/dev/null; }
has_cleaned() { grep -q "^cleaned" "$TMP/stderr" 2>/dev/null; }
# The helpers above are assertions: a failing status of theirs is a failed case, not a crash (tap.sh, "Unexpected errors").
tap_assertions rc_is rc_not count_is has before_cases empty nonempty nogrep has_msg has_bail has_cleaned

# 1. Format and plan, in the file.
run_tap 'tap_ok "creates the branch"
tap_ok "assigns the issue"
tap_done' file
has "ok 1 - creates the branch" "$TMP/tap"; check $? "writes ok N - id for a passing case"
has "ok 2 - assigns the issue" "$TMP/tap"; check $? "numbers the cases from 1, in order"
has "1..2" "$TMP/tap"; check $? "writes the plan 1..N with the number of cases"
count_is 1 '^1\.\.' "$TMP/tap"; check $? "writes a single plan"
rc_is 0; check $? "exits with 0 when every case passes"
empty "$TMP/stdout"; check $? "writes nothing to stdout when it has an output file"

run_tap 'tap_ok "first"
tap_fail "second"
tap_ok "third"
tap_done' file
has "not ok 2 - second" "$TMP/tap"; check $? "writes not ok N - id for a failing case"
has "1..3" "$TMP/tap"; check $? "the plan counts the failing cases too"
rc_is 1; check $? "exits with 1 when a case fails"
has "FAIL - second" "$TMP/stderr"; check $? "reports a failing case on stderr as FAIL - id, for the CI log"

run_tap 'true; tap_check $? "passes by status"
[ 1 -eq 0 ]; tap_check $? "fails by status"
tap_done' file
has "ok 1 - passes by status" "$TMP/tap" && has "not ok 2 - fails by status" "$TMP/tap"; check $? "tap_check turns a status into ok or not ok"
rc_is 1; check $? "a failing command that the test checks with its status is not an unexpected error"
nogrep '^Bail out!' "$TMP/tap" && has "ok 1 - passes by status" "$TMP/tap"; check $? "a checked failure does not emit Bail out!"

# 2. The script of the cases: # file: before them.
run_tap 'tap_ok "x"
tap_done' file
grep -q '^# file: ' "$TMP/tap" 2>/dev/null; check $? "writes a # file: line"
before_cases; check $? "the # file: line comes before the cases"
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

run_tap 'tap_fail "by hand failing" "input 7"
tap_done'
has "FAIL - by hand failing" "$TMP/stderr"; check $? "without TAP_OUT a failing case is also reported on stderr as FAIL - id"

# 5. The path stays out of the test's reach, and its stdout cannot inject cases.
run_tap 'echo "path=[${TAP_OUT:-unset}]" >&2
echo "ok 99 - injected"
echo "not ok 98 - injected"
echo "1..99"
tap_ok "real"
tap_done' file
has "path=[unset]" "$TMP/stderr"; check $? "the test does not see TAP_OUT after loading the helper"
nogrep injected "$TMP/tap" && has "ok 1 - real" "$TMP/tap"; check $? "lines that the test prints on stdout do not reach the TAP file"
count_is 1 '^ok \|^not ok ' "$TMP/tap"; check $? "only the cases of the helper are in the file"
run_tap 'echo "$TAP_OUT" >&2; tap_done' file
nonempty "$TMP/tap"; check $? "the helper wrote to the file it was given"

# 6. Bail out! on an unexpected error.
run_tap 'set -e
tap_ok "before"
false
tap_ok "after"
tap_done' file
has_bail; check $? "an unexpected error under set -e emits Bail out!"
rc_not 0; check $? "an unexpected error under set -e exits non-zero"
has "ok 1 - before" "$TMP/tap" && nogrep '^1\.\.' "$TMP/tap"; check $? "a bailed run has no plan"
has "ok 1 - before" "$TMP/tap" && ! has "ok 2 - after" "$TMP/tap"; check $? "nothing runs after the error"

run_tap 'tap_ok "before"
echo "$undefined_variable" >/dev/null
tap_ok "after"
tap_done' file
has_bail; check $? "an unbound variable emits Bail out!"
rc_not 0; check $? "an unbound variable exits non-zero"

run_tap 'tap_ok "before"
exit 3' file
has_bail; check $? "leaving before tap_done emits Bail out!"
rc_is 3; check $? "leaving before tap_done keeps the exit code"

run_tap 'tap_ok "before"
exit 0' file
has_bail; check $? "an exit 0 before tap_done is still a Bail out!"
rc_not 0; check $? "an exit 0 before tap_done is turned into a failure"

run_tap 'tap_at_exit "echo cleaned >&2"
tap_ok "x"
false || exit 5' file
has_cleaned; check $? "the at-exit command also runs when the run bails out"
run_tap 'tap_at_exit "echo cleaned >&2"
tap_ok "x"
tap_done' file
has_cleaned && rc_is 0; check $? "the at-exit command runs at the end of a normal run"

# 7. Ids are literal; an id that repeats is the same case (a loop over inputs).
run_tap 'for x in a b c; do tap_ok "same thing" "input $x"; done
tap_ok "other"
tap_done' file
has "ok 1 - same thing" "$TMP/tap" && has "ok 2 - other" "$TMP/tap" && has "1..2" "$TMP/tap"; check $? "an id that repeats is one case, not one per call"
run_tap 'for x in a b c; do if [ "$x" = b ]; then tap_fail "same thing" "input $x"; else tap_ok "same thing" "input $x"; fi; done
tap_ok "other"
tap_done' file
has "not ok 1 - same thing" "$TMP/tap" && has "# desc: input b" "$TMP/tap" && nogrep "input a" "$TMP/tap"; check $? "a repeated id fails if one repetition fails, and lists only the failing inputs"
rc_is 1; check $? "a failing repetition makes the script exit with 1"
run_tap 'tap_fail "same thing" "input a"
tap_ok "same thing" "input b"
tap_done' file
has "not ok 1 - same thing" "$TMP/tap"; check $? "a later passing repetition does not hide a failure"
run_tap 'tap_ok "first"
tap_ok "second"
tap_ok "first"
tap_done' file
has "ok 1 - first" "$TMP/tap" && has "ok 2 - second" "$TMP/tap" && has "1..2" "$TMP/tap"; check $? "the cases are numbered in the order of their first call"
run_tap 'tap_ok "line one
line two"
tap_done' file
has_bail && rc_not 0; check $? "an id with a newline emits Bail out! (it could inject a line)"
run_tap 'tap_ok ""
tap_done' file
has_bail && rc_not 0; check $? "an empty id emits Bail out!"
run_tap 'tap_ok "fixes #12"
tap_done' file
has 'ok 1 - fixes \#12' "$TMP/tap"; check $? "a # in the id is escaped, as TAP 14 asks"

# 7b. Several scripts, one stream: the numbering continues and there is a single plan at the end.
printf '#!/usr/bin/env bash\n. "%s/scripts/agents/tap.sh"\ntap_begin "$0"\ntap_ok "a"\ntap_ok "b"\ntap_done\n' "$ROOT" >"$TMP/one.sh"
printf '#!/usr/bin/env bash\n. "%s/scripts/agents/tap.sh"\ntap_begin "$0"\ntap_fail "c"\ntap_done\n' "$ROOT" >"$TMP/two.sh"
rm -f "$TMP/tap3"; (cd "$ROOT" && TAP_OUT="$TMP/tap3" bash "$TMP/one.sh"; TAP_OUT="$TMP/tap3" bash "$TMP/two.sh") 2>/dev/null || true
has "ok 2 - b" "$TMP/tap3" && has "not ok 3 - c" "$TMP/tap3"; check $? "a second script writing the same file continues the numbering"
count_is 1 '^1\.\.' "$TMP/tap3" && [ "$(tail -1 "$TMP/tap3")" = "1..3" ]; check $? "two scripts in one file leave a single plan, at the end, with the total"
count_is 2 '^# file: ' "$TMP/tap3"; check $? "each script writes its own # file: line"

# 8. A script with nothing to run.
run_tap 'tap_skip_all "does not apply here"' file
has "1..0 # SKIP does not apply here" "$TMP/tap" && rc_is 0; check $? "tap_skip_all writes 1..0 # SKIP and exits with 0"

# 8b. Fail closed: a TAP_OUT that cannot be opened is an error, never a green run with nothing recorded.
run_tap 'tap_ok "x"
tap_done' dir
rc_not 0; check $? "a TAP_OUT that cannot be opened exits non-zero"
has_msg "TAP_OUT"; check $? "a TAP_OUT that cannot be opened says so on stderr"
run_tap 'tap_ok "x"
tap_done' file
rc_is 0; check $? "a TAP_OUT that can be opened still works"

# 8c. An unexpected failure without set -e: a command that does not exist or cannot run is never a checked status.
run_tap 'tap_ok "before"
command_that_does_not_exist_here 2>/dev/null
tap_ok "after"
tap_done' file
has_bail && rc_not 0; check $? "a command that does not exist emits Bail out! even without set -e"
run_tap 'tap_ok "before"
kill -TERM $$
tap_ok "after"
tap_done' file
has_bail && rc_not 0; check $? "a script killed by a signal emits Bail out!"

# 8d. A merged case that passes does not show the description of its first repetition only.
run_tap 'for x in a b c; do tap_ok "looped" "input $x"; done
tap_ok "single" "only one"
tap_done' file
nogrep "input a" "$TMP/tap" && has "# desc: only one" "$TMP/tap"; check $? "a passing case with repetitions has no description, one with a single call keeps it"

# 8e. A bail out leaves no plan from an earlier script in the stream.
printf '#!/usr/bin/env bash\n. "%s/scripts/agents/tap.sh"\ntap_begin "$0"\ntap_ok "d"\nexit 4\n' "$ROOT" >"$TMP/three.sh"
rm -f "$TMP/tap4"; (cd "$ROOT" && TAP_OUT="$TMP/tap4" bash "$TMP/one.sh"; TAP_OUT="$TMP/tap4" bash "$TMP/three.sh") 2>/dev/null || true
has_bail4() { grep -q '^Bail out!' "$TMP/tap4" 2>/dev/null; }
tap_assertions has_bail4
has_bail4 && nogrep '^1\.\.' "$TMP/tap4"; check $? "a bail out removes the plan an earlier script wrote"

# 8f. A crash is never an assertion (ADR-002 D6, issue #165). Without set -e a command that fails with 1 or 2 looks
# like a status the test checks on purpose, so the helper looks at what consumes the status: an assertion
# (test, [, [[, grep, diff, cmp, or a function declared with tap_assertions) may fail a case; anything else
# that fails and is read straight by tap_check, or not read at all, is a Bail out!.
run_tap 'python3 -c "raise SystemExit(1)" 2>/dev/null
tap_check $? "a setup step that crashes with status 1"
tap_done' file
has_bail && rc_not 0 && nogrep '^not ok' "$TMP/tap"; tap_check $? "a program that crashes with 1 and is read by tap_check emits Bail out!, not a failed case"
run_tap 'python3 /nonexistent/missing-script.py 2>/dev/null
tap_check $? "a script that does not exist yet"
tap_done' file
has_bail && rc_not 0 && nogrep '^not ok' "$TMP/tap"; tap_check $? "a program that crashes with 2 and is read by tap_check emits Bail out!, not a failed case"
run_tap 's=$(python3 -c "raise SystemExit(1)" 2>/dev/null)
[ "$s" = expected ]
tap_check $? "compares the output of a step that crashed"
tap_done' file
has_bail && rc_not 0 && nogrep '^not ok' "$TMP/tap"; tap_check $? "a setup step that crashes and nobody checks emits Bail out! before the assertion"
run_tap 'tap_ok "before"
python3 -c "raise SystemExit(1)" 2>/dev/null
tap_done' file
has_bail && rc_not 0; tap_check $? "a failing command right before tap_done emits Bail out!"
run_tap 'tap_ok "before"
python3 -c "raise SystemExit(1)" 2>/dev/null
tap_ok "after"
tap_done' file
has_bail && nogrep '^1\.\.' "$TMP/tap"; tap_check $? "a failing command that nothing reads emits Bail out! and leaves no plan"

run_tap '[ a = b ]; tap_check $? "test fails"
grep -q zzz /dev/null; tap_check $? "grep finds nothing"
[[ a = b ]]; tap_check $? "double brackets fail"
tap_done' file
has "not ok 1 - test fails" "$TMP/tap" && has "not ok 2 - grep finds nothing" "$TMP/tap" && has "not ok 3 - double brackets fail" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a failing test, grep or [[ is a failed case, not a Bail out!"
rc_is 1; tap_check $? "a failed assertion still exits with 1"
run_tap 'test 1 -eq abc 2>/dev/null
tap_check $? "syntax error of test"
tap_done' file
has_bail && nogrep '^not ok' "$TMP/tap"; tap_check $? "test failing with status 2 (a usage error) emits Bail out!"
run_tap 'grep -q x /nonexistent/file 2>/dev/null
tap_check $? "grep on a missing file"
tap_done' file
has_bail && nogrep '^not ok' "$TMP/tap"; tap_check $? "grep failing with status 2 (it could not read) emits Bail out!"

run_tap 'is_there() { [ -f "$1" ]; }
tap_assertions is_there
is_there /nonexistent/file; tap_check $? "a declared assertion function fails"
tap_done' file
has "not ok 1 - a declared assertion function fails" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a function declared with tap_assertions can fail a case"
run_tap 'wraps() { python3 -c "raise SystemExit(1)" 2>/dev/null; }
tap_assertions wraps
wraps; tap_check $? "a declared function that ends in a program"
tap_done' file
has "not ok 1 - a declared function that ends in a program" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a declared function is an assertion whatever command runs inside it"
run_tap 'crashes() { python3 -c "raise SystemExit(1)" 2>/dev/null; }
crashes; tap_check $? "an undeclared function"
tap_done' file
has_bail && nogrep '^not ok' "$TMP/tap"; tap_check $? "a function that is not declared as an assertion emits Bail out! when it fails"

run_tap 'python3 -c "raise SystemExit(3)" 2>/dev/null; [ $? -eq 3 ]; tap_check $? "exits with 3"
python3 -c "raise SystemExit(3)" 2>/dev/null; rc=$?; [ "$rc" -eq 3 ]; tap_check $? "keeps the status in a variable"
python3 -c "raise SystemExit(1)" 2>/dev/null || true
tap_ok "a failure the test declares expected with || true"
tap_done' file
has "ok 1 - exits with 3" "$TMP/tap" && has "ok 2 - keeps the status in a variable" "$TMP/tap" && has "ok 3 - a failure the test declares expected with || true" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a status the test reads itself with its status variable, or declares expected with a trailing true, is not an error"
rc_is 0; tap_check $? "a run whose failures are all declared exits with 0"
run_tap 'if python3 -c "raise SystemExit(1)" 2>/dev/null; then tap_fail "x"; else tap_ok "else branch"; fi
tap_done' file
has "ok 1 - else branch" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a command in an if condition is the test's own business"

# 9. The kit's own tests use the helper (what the issue migrates).
SCRIPTS=$(cd "$ROOT" && find scripts .claude -name 'test-*.sh' ! -name test-tap.sh | sort)
n=0; sin=""
for s in $SCRIPTS; do n=$((n + 1)); grep -q 'agents/tap\.sh' "$ROOT/$s" || sin="$sin $s"; done
[ -z "$sin" ] && [ "$n" -ge 1 ]; check $? "every test-*.sh of the kit loads tap.sh" "missing:${sin:- none}"
propios=""
for s in $SCRIPTS; do grep -qE '^(ok|falla|fail)\(\)' "$ROOT/$s" && propios="$propios $s"; done
[ -z "$propios" ]; check $? "no test-*.sh defines its own ok()/falla()/fail()" "still:${propios:- none}"
dinamicos=""
# test-tap.sh is checked too: its own wrapper is check $?, so that call is looked at as well.
for s in $SCRIPTS scripts/agents/test-tap.sh; do
  grep -nE '(tap_(ok|fail)|tap_check [^ ]+|check \$\?) "[^"]*\$' "$ROOT/$s" | grep -vE '(tap_(ok|fail)|tap_check [^ ]+|check \$\?) "\$\{?[A-Za-z0-9_@*]+\}?"' >"$TMP/dyn" && dinamicos="$dinamicos $s:$(head -1 "$TMP/dyn" | cut -d: -f1)"
done
[ -z "$dinamicos" ]; check $? "the id of each case is a literal, never built at run time" "first offender:${dinamicos:- none}"
# tap_begin runs before any cd of the script: with a relative $0 it would resolve from the wrong folder.
tarde=""
for s in $SCRIPTS; do
  b=$(grep -n '^tap_begin ' "$ROOT/$s" | head -1 | cut -d: -f1) || true  # no match: no line
  c=$(grep -n '^cd ' "$ROOT/$s" | head -1 | cut -d: -f1) || true
  [ -z "$c" ] || [ "${b:-999999}" -lt "$c" ] || tarde="$tarde $s"
done
[ -z "$tarde" ]; check $? "tap_begin comes before the first cd of each test" "after the cd:${tarde:- none}"

tap_done
