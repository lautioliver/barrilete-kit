#!/usr/bin/env bash
# Tests of the TAP helper (scripts/agents/tap.sh, ADR-002 D6, issue #151): format, plan, Bail out!,
# the output file out of the test's reach, and that the kit's own tests use it.
# Usage: bash scripts/agents/test-tap.sh
# shellcheck disable=SC2016,SC2319  # the scripts under test are written in single quotes on purpose; "<condition>; tap_check $?" is the pattern of the tests
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
# Leaves $TMP/rc (exit code), $TMP/stdout, $TMP/stderr and, if $2 is "tap", $TMP/tap: the TAP stream the helper
# prints on stdout when there is no TAP_OUT (what a person running the test sees). "junit" writes the JUnit file
# to $TMP/tap instead, the report of red.sh; "dir" points TAP_OUT at a folder; "fmt=<x>" sets TAP_FORMAT.
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
    (trap - ERR; cd "$ROOT" || exit; env -u TAP_FORMAT TAP_OUT="$TMP" bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"; echo $? >"$TMP/rc")
  elif [ "${2:-}" = "tap" ]; then
    # without TAP_OUT the TAP stream is on stdout: the cases of the stream read it from $TMP/tap
    (trap - ERR; cd "$ROOT" || exit; env -u TAP_FORMAT -u TAP_OUT bash "$TMP/t.sh" >"$TMP/tap" 2>"$TMP/stderr"; echo $? >"$TMP/rc")
  elif [ "${2:-}" = "junit" ]; then
    # TAP_OUT without TAP_FORMAT: the helper writes JUnit XML (the testsuite fragment of one script) to the file
    (trap - ERR; cd "$ROOT" || exit; env -u TAP_FORMAT TAP_OUT="$TMP/tap" bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"; echo $? >"$TMP/rc")
  elif case "${2:-}" in fmt=*) true ;; *) false ;; esac; then
    (trap - ERR; cd "$ROOT" || exit; TAP_FORMAT="${2#fmt=}" TAP_OUT="$TMP/tap" bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"; echo $? >"$TMP/rc")
  else
    (trap - ERR; cd "$ROOT" || exit; env -u TAP_OUT bash "$TMP/t.sh" >"$TMP/stdout" 2>"$TMP/stderr"; echo $? >"$TMP/rc")
  fi
}
rc_is() { [ "$(cat "$TMP/rc")" -eq "$1" ]; }
rc_not() { [ "$(cat "$TMP/rc")" -ne "$1" ]; }
# Usage: count_is <n> <regex> <file>
count_is() { [ "$(count "$2" "$3")" -eq "$1" ]; }
has() { grep -qxF -- "$1" "$2" 2>/dev/null; }
# Usage: count <regex> <file>: how many lines match (0 if the file does not exist).
count() { local n; n=$(grep -c -- "$1" "$2" 2>/dev/null || true); echo "${n:-0}"; }
# Usage: line_of <regex> <file>: the number of the first line that matches (0 if none).
line_of() { local n; n=$(grep -n -- "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1 || true); echo "${n:-0}"; }
before_cases() { local f; f=$(line_of '^# file: ' "$TMP/tap"); [ "$f" -gt 0 ] && [ "$f" -lt "$(line_of '^ok 1' "$TMP/tap")" ]; }
empty() { [ ! -s "$1" ]; }
nonempty() { [ -s "$1" ]; }
nogrep() { ! grep -q -- "$1" "$2" 2>/dev/null; }
has_msg() { grep -q -- "$1" "$TMP/stderr" 2>/dev/null; }
has_bail() { grep -q "^Bail out!" "$TMP/tap" 2>/dev/null; }
has_cleaned() { grep -q "^cleaned" "$TMP/stderr" 2>/dev/null; }

# 1. Format and plan, in the TAP stream on stdout.
run_tap 'tap_ok "creates the branch"
tap_ok "assigns the issue"
tap_done' tap
has "ok 1 - creates the branch" "$TMP/tap"; check $? "writes ok N - id for a passing case"
has "ok 2 - assigns the issue" "$TMP/tap"; check $? "numbers the cases from 1, in order"
has "1..2" "$TMP/tap"; check $? "writes the plan 1..N with the number of cases"
count_is 1 '^1\.\.' "$TMP/tap"; check $? "writes a single plan"
rc_is 0; check $? "exits with 0 when every case passes"

run_tap 'tap_ok "first"
tap_fail "second"
tap_ok "third"
tap_done' tap
has "not ok 2 - second" "$TMP/tap"; check $? "writes not ok N - id for a failing case"
has "1..3" "$TMP/tap"; check $? "the plan counts the failing cases too"
rc_is 1; check $? "exits with 1 when a case fails"
has "FAIL - second" "$TMP/stderr"; check $? "reports a failing case on stderr as FAIL - id, for the CI log"

run_tap 'true; tap_check $? "passes by status"
[ 1 -eq 0 ]; tap_check $? "fails by status"
tap_done' tap
has "ok 1 - passes by status" "$TMP/tap" && has "not ok 2 - fails by status" "$TMP/tap"; check $? "tap_check turns a status into ok or not ok"
rc_is 1; check $? "a failing command that the test checks with its status is not an unexpected error"
nogrep '^Bail out!' "$TMP/tap" && has "ok 1 - passes by status" "$TMP/tap"; check $? "a checked failure does not emit Bail out!"

# 2. The script of the cases: # file: before them.
run_tap 'tap_ok "x"
tap_done' tap
grep -q '^# file: ' "$TMP/tap" 2>/dev/null; check $? "writes a # file: line"
before_cases; check $? "the # file: line comes before the cases"
git init -q "$TMP/repo" && mkdir -p "$TMP/repo/sub"
printf '#!/usr/bin/env bash\n. "%s/scripts/agents/tap.sh"\ntap_begin "$0"\ntap_ok "x"\ntap_done\n' "$ROOT" >"$TMP/repo/sub/test-demo.sh"
(cd "$TMP/repo" && bash sub/test-demo.sh >"$TMP/tap2")
has "# file: sub/test-demo.sh" "$TMP/tap2"; check $? "the # file: path is relative to the repository root"

# 3. Description: not compared, apart from the id.
run_tap 'v=42
tap_fail "literal id" "varies with $v"
tap_done' tap
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

# 5. The path stays out of the test's reach (the test does not see TAP_OUT after the helper opened the file).
run_tap 'echo "path=[${TAP_OUT:-unset}]" >&2
tap_ok "real"
tap_done' junit
has "path=[unset]" "$TMP/stderr"; check $? "the test does not see TAP_OUT after loading the helper"

# 6. Bail out! on an unexpected error.
run_tap 'set -e
tap_ok "before"
false
tap_ok "after"
tap_done' tap
has_bail; check $? "an unexpected error under set -e emits Bail out!"
rc_not 0; check $? "an unexpected error under set -e exits non-zero"
has "ok 1 - before" "$TMP/tap" && nogrep '^1\.\.' "$TMP/tap"; check $? "a bailed run has no plan"
has "ok 1 - before" "$TMP/tap" && ! has "ok 2 - after" "$TMP/tap"; check $? "nothing runs after the error"

run_tap 'tap_ok "before"
echo "$undefined_variable" >/dev/null
tap_ok "after"
tap_done' tap
has_bail; check $? "an unbound variable emits Bail out!"
rc_not 0; check $? "an unbound variable exits non-zero"

run_tap 'tap_ok "before"
exit 3' tap
has_bail; check $? "leaving before tap_done emits Bail out!"
rc_is 3; check $? "leaving before tap_done keeps the exit code"

run_tap 'tap_ok "before"
exit 0' tap
has_bail; check $? "an exit 0 before tap_done is still a Bail out!"
rc_not 0; check $? "an exit 0 before tap_done is turned into a failure"

run_tap 'tap_at_exit "echo cleaned >&2"
tap_ok "x"
false || exit 5' tap
has_cleaned; check $? "the at-exit command also runs when the run bails out"
run_tap 'tap_at_exit "echo cleaned >&2"
tap_ok "x"
tap_done' tap
has_cleaned && rc_is 0; check $? "the at-exit command runs at the end of a normal run"

# 7. Ids are literal; an id that repeats is the same case (a loop over inputs).
run_tap 'for x in a b c; do tap_ok "same thing" "input $x"; done
tap_ok "other"
tap_done' tap
has "ok 1 - same thing" "$TMP/tap" && has "ok 2 - other" "$TMP/tap" && has "1..2" "$TMP/tap"; check $? "an id that repeats is one case, not one per call"
run_tap 'for x in a b c; do if [ "$x" = b ]; then tap_fail "same thing" "input $x"; else tap_ok "same thing" "input $x"; fi; done
tap_ok "other"
tap_done' tap
has "not ok 1 - same thing" "$TMP/tap" && has "# desc: input b" "$TMP/tap" && nogrep "input a" "$TMP/tap"; check $? "a repeated id fails if one repetition fails, and lists only the failing inputs"
rc_is 1; check $? "a failing repetition makes the script exit with 1"
run_tap 'tap_fail "same thing" "input a"
tap_ok "same thing" "input b"
tap_done' tap
has "not ok 1 - same thing" "$TMP/tap"; check $? "a later passing repetition does not hide a failure"
run_tap 'tap_ok "first"
tap_ok "second"
tap_ok "first"
tap_done' tap
has "ok 1 - first" "$TMP/tap" && has "ok 2 - second" "$TMP/tap" && has "1..2" "$TMP/tap"; check $? "the cases are numbered in the order of their first call"
run_tap 'tap_ok "line one
line two"
tap_done' tap
has_bail && rc_not 0; check $? "an id with a newline emits Bail out! (it could inject a line)"
run_tap 'tap_ok ""
tap_done' tap
has_bail && rc_not 0; check $? "an empty id emits Bail out!"
run_tap 'tap_ok "fixes #12"
tap_done' tap
has 'ok 1 - fixes \#12' "$TMP/tap"; check $? "a # in the id is escaped, as TAP 14 asks"

# 8. A script with nothing to run.
run_tap 'tap_skip "not here" "needs bash 4"
tap_ok "here"
tap_done' tap
has "ok 1 - not here # SKIP needs bash 4" "$TMP/tap" && has "ok 2 - here" "$TMP/tap" && rc_is 0; check $? "tap_skip writes ok N - id # SKIP reason and the run goes on"
run_tap 'tap_skip_all "does not apply here"' tap
has "1..0 # SKIP does not apply here" "$TMP/tap" && rc_is 0; check $? "tap_skip_all writes 1..0 # SKIP and exits with 0"

# 8b. Fail closed: a TAP_OUT that cannot be opened is an error, never a green run with nothing recorded.
run_tap 'tap_ok "x"
tap_done' dir
rc_not 0; check $? "a TAP_OUT that cannot be opened exits non-zero"
has_msg "TAP_OUT"; check $? "a TAP_OUT that cannot be opened says so on stderr"
run_tap 'tap_ok "x"
tap_done' junit
rc_is 0; check $? "a TAP_OUT that can be opened still works"

# 8c. An unexpected failure without set -e: a command that does not exist or cannot run is never a checked status.
run_tap 'tap_ok "before"
command_that_does_not_exist_here 2>/dev/null
tap_ok "after"
tap_done' tap
has_bail && rc_not 0; check $? "a command that does not exist emits Bail out! even without set -e"
run_tap 'tap_ok "before"
kill -TERM $$
tap_ok "after"
tap_done' tap
has_bail && rc_not 0; check $? "a script killed by a signal emits Bail out!"

# 8d. A merged case that passes does not show the description of its first repetition only.
run_tap 'for x in a b c; do tap_ok "looped" "input $x"; done
tap_ok "single" "only one"
tap_done' tap
nogrep "input a" "$TMP/tap" && has "# desc: only one" "$TMP/tap"; check $? "a passing case with repetitions has no description, one with a single call keeps it"

# 8f. A crash is never an assertion (ADR-002 D6, issue #165). Without set -e a command that fails with 1 or 2 looks
# like a status the test checks on purpose, so the helper tells them apart by the command: an assertion
# (test, [, [[, grep, diff, cmp) that fails with status 1 may fail a case; any other command that fails is a Bail out!.
run_tap 'python3 -c "raise SystemExit(1)" 2>/dev/null
tap_check $? "a setup step that crashes with status 1"
tap_done' tap
has_bail && rc_not 0 && nogrep '^not ok' "$TMP/tap"; tap_check $? "a program that crashes with 1 and is read by tap_check emits Bail out!, not a failed case"
run_tap 'python3 /nonexistent/missing-script.py 2>/dev/null
tap_check $? "a script that does not exist yet"
tap_done' tap
has_bail && rc_not 0 && nogrep '^not ok' "$TMP/tap"; tap_check $? "a program that crashes with 2 and is read by tap_check emits Bail out!, not a failed case"
run_tap 's=$(python3 -c "raise SystemExit(1)" 2>/dev/null)
[ "$s" = expected ]
tap_check $? "compares the output of a step that crashed"
tap_done' tap
has_bail && rc_not 0 && nogrep '^not ok' "$TMP/tap"; tap_check $? "a setup step that crashes and nobody checks emits Bail out! before the assertion"
run_tap 'tap_ok "before"
python3 -c "raise SystemExit(1)" 2>/dev/null
tap_done' tap
has_bail && rc_not 0; tap_check $? "a failing command right before tap_done emits Bail out!"
run_tap 'tap_ok "before"
python3 -c "raise SystemExit(1)" 2>/dev/null
tap_ok "after"
tap_done' tap
has_bail && nogrep '^1\.\.' "$TMP/tap"; tap_check $? "a failing command that nothing reads emits Bail out! and leaves no plan"

run_tap '[ a = b ]; tap_check $? "test fails"
grep -q zzz /dev/null; tap_check $? "grep finds nothing"
[[ a = b ]]; tap_check $? "double brackets fail"
tap_done' tap
has "not ok 1 - test fails" "$TMP/tap" && has "not ok 2 - grep finds nothing" "$TMP/tap" && has "not ok 3 - double brackets fail" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a failing test, grep or [[ is a failed case, not a Bail out!"
rc_is 1; tap_check $? "a failed assertion still exits with 1"
run_tap 'test 1 -eq abc 2>/dev/null
tap_check $? "syntax error of test"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap"; tap_check $? "test failing with status 2 (a usage error) emits Bail out!"
run_tap 'grep -q x /nonexistent/file 2>/dev/null
tap_check $? "grep on a missing file"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap"; tap_check $? "grep failing with status 2 (it could not read) emits Bail out!"

run_tap 'crashes() { python3 -c "raise SystemExit(1)" 2>/dev/null; }
crashes; tap_check $? "an undeclared function"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap"; tap_check $? "a function that is not declared as an assertion emits Bail out! when it fails"
run_tap 'has_file() { [ -f "$1" ]; }
has_file /nonexistent/file; tap_check $? "a helper that ends in test"
tap_done' tap
has "not ok 1 - a helper that ends in test" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a function whose failing command is an assertion fails the case, with nothing to declare"

# 8g. The crash can be anywhere: inside an argument, a pipeline, a function or a subshell. Each of these
# was a failed case (a valid red) while the helper only looked at the status of the assertion itself.
run_tap '[ "$(python3 /nonexistent/missing-script.py 2>/dev/null)" = 3 ]; tap_check $? "crash in a command substitution"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash inside the substitution of an assertion emits Bail out!"
run_tap 'python3 /nonexistent/missing-script.py 2>/dev/null | grep -q "^3$"; tap_check $? "crash at the head of a pipeline"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash at the head of a pipeline emits Bail out!"
run_tap 'grep -q x <<<"$(python3 -c "import nope" 2>/dev/null)"; tap_check $? "crash in a here-string"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash inside a here-string emits Bail out!"
run_tap 'grep -q x <(python3 /nonexistent/missing-script.py 2>/dev/null); tap_check $? "crash in a process substitution"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash inside a process substitution emits Bail out!"
run_tap 'diff <(python3 /nonexistent/missing-script.py 2>/dev/null) <(echo 3) >/dev/null; tap_check $? "crash in a diff argument"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash inside a diff argument emits Bail out!"
run_tap '[ "$(python3 -c "import nope" 2>/dev/null | wc -l)" -eq 3 ]; tap_check $? "crash before wc"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash before wc in a substitution emits Bail out!"
run_tap 'setup() { python3 -c "import nope" 2>/dev/null; [ -f /nonexistent ]; }
setup; tap_check $? "setup function"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash inside a function, before its last command, emits Bail out!"
run_tap 'setup() { python3 -c "import nope" 2>/dev/null; true; }
setup
[ -f /nonexistent/effect ]; tap_check $? "effect of a setup that crashed"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a setup function that crashes and returns 0 emits Bail out! instead of failing a later assertion"
run_tap '( python3 /nonexistent/missing-script.py 2>/dev/null; [ x = y ] ); tap_check $? "crash in a subshell"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "a crash inside a subshell emits Bail out!"
run_tap 'tap_ok "before"
( python3 /nonexistent/missing-script.py 2>/dev/null; : )
tap_ok "after"
tap_done' tap
has_bail && nogrep '^1\.\.' "$TMP/tap"; tap_check $? "a crash in a subshell leaves no plan"

# 8h. What stays a failed case: an assertion, wherever it runs, and a pipeline that ends in one.
run_tap 'printf "a\n" | grep -q b; tap_check $? "pipeline that does not match"
printf "a\n" | grep -q a; tap_check $? "pipeline that matches"
[ "$(printf 3)" = 4 ]; tap_check $? "substitution that works"
tap_done' tap
has "not ok 1 - pipeline that does not match" "$TMP/tap" && has "ok 2 - pipeline that matches" "$TMP/tap" && has "not ok 3 - substitution that works" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "an assertion that fails at the end of a pipeline, or on a substitution that works, is a failed case"

# 8i. tap_run: a program that is expected to fail, compared with the status the test expects.
run_tap 'tap_run out 64 python3 -c "print(\"hi\"); raise SystemExit(64)"
[ "$out" = hi ]; tap_check $? "output of a failing program"
[ "$TAP_RC" -eq 64 ]; tap_check $? "status of a failing program"
tap_done' tap
has "ok 1 - output of a failing program" "$TMP/tap" && has "ok 2 - status of a failing program" "$TMP/tap" && rc_is 0; tap_check $? "tap_run keeps the output and the status of a program that fails as expected"
run_tap 'tap_run out 64 python3 /nonexistent/missing-script.py
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "tap_run bails out when the program ends with 2 and the test expected another status"
run_tap 'tap_run out 0 python3 -c "raise SystemExit(1)"
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "tap_run bails out when the program ends with 1 and the test expected 0"
run_tap 'tap_run out 64 sh -c "exit 0"
[ "$TAP_RC" -eq 64 ]; tap_check $? "program that should have failed"
tap_done' tap
has "not ok 1 - program that should have failed" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "tap_run leaves a status that is not a crash code to the test: a failed case"
run_tap 'tap_run out 0 true
tap_run out 1 sh -c "exit 1"
tap_ok "fine"
tap_done' tap
rc_is 0; tap_check $? "tap_run accepts the status the test expected, 0 or not"

# 8j. tap_status and tap_no_traceback: the same rule for a command line that ran with its ERR trap off.
run_tap 'c=0; out=$(trap - ERR; sh -c "echo refused; exit 64") || c=$?; tap_status "$c" 64
[ "$out" = refused ]; tap_check $? "output of a refused command"
c=0; out=$(trap - ERR; sh -c "exit 0") || c=$?; tap_status "$c" 64
[ "$c" -eq 64 ]; tap_check $? "a command that should have refused"
tap_done' tap
has "ok 1 - output of a refused command" "$TMP/tap" && has "not ok 2 - a command that should have refused" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "tap_status keeps the expected status and leaves a status that is not a crash code to the test"
run_tap 'c=0; out=$(trap - ERR; python3 /nonexistent/missing-script.py 2>&1) || c=$?; tap_status "$c" 64
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "tap_status bails out when the status is 2 and the test expected another one"
run_tap 'tap_no_traceback "all good"
tap_no_traceback "Traceback (most recent call last):
  File x"
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "tap_no_traceback bails out when the output has a Python traceback"

run_tap 'if python3 -c "raise SystemExit(1)" 2>/dev/null; then tap_fail "x"; else tap_ok "else branch"; fi
tap_done' tap
has "ok 1 - else branch" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "a command in an if condition is the test's own business"

# 8k. #170: what the second review of #165 still got through (each of these was a valid red with status 2).
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
run_tap '[ "$(python3 /nonexistent/missing-script.py)" = 3 ]; tap_check $? "lone program in a substitution, no redirection"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a lone program in a substitution, with no redirection, emits Bail out!"
else tap_skip "170: a lone program in a substitution, with no redirection, emits Bail out!" "bash 3.2 runs a lone external command of a substitution with exec: its ERR trap never runs (forbidden in the red, see the header of tap.sh)"; fi
run_tap 'python3 -c "raise SystemExit(0)" | python3 /nonexistent/missing-script.py | grep -q 3; tap_check $? "crash in the middle of a pipeline"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a crash in the middle of a pipeline emits Bail out!"
run_tap 'out=$(python3 /nonexistent/missing-script.py); [ "$out" = 3 ]; tap_check $? "assigned substitution"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a crash in an assigned substitution emits Bail out!"
run_tap '[ "$(cd /tmp && python3 /nonexistent/missing-script.py)" = 3 ]; tap_check $? "cd then program"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a crash after a cd in a substitution emits Bail out!"
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
run_tap '[ -z "$(python3 /nonexistent/missing-script.py)" ]; tap_check $? "empty substitution"
tap_done' tap
has_bail && nogrep '^ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a crash whose output is empty is not a pass"
else tap_skip "170: a crash whose output is empty is not a pass" "bash 3.2 runs a lone external command of a substitution with exec: its ERR trap never runs (forbidden in the red, see the header of tap.sh)"; fi
run_tap 'python3 /nonexistent/missing-script.py >/dev/null && grep -q 3 /dev/null; tap_check $? "program then grep in an and-list"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: tap_check bails out on a status 2 from the left of an and-list"
run_tap 'tap_check 2 "status 2"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: tap_check bails out on any status other than 0 and 1"
run_tap 'tap_check 127 "status 127"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_check bails out on status 127"
run_tap 'tap_check 1 "failed"
tap_check 0 "passed"
tap_done' tap
has "not ok 1 - failed" "$TMP/tap" && has "ok 2 - passed" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "170: tap_check still takes 0 and 1"
run_tap 'tap_helper() { python3 -c "raise SystemExit(1)" 2>/dev/null; [ -f /nonexistent/out ]; }
tap_helper; tap_check $? "helper named tap_"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a test function named tap_* is not exempt from the ERR trap"
run_tap '_tap_mine() { python3 -c "raise SystemExit(1)" 2>/dev/null; [ -f /nonexistent/out ]; }
_tap_mine; tap_check $? "helper named _tap_"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a test function named _tap_* is not exempt from the ERR trap"
run_tap 'tap_run out 64 sh -c "kill -ABRT \$\$"
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_run bails out on a signal status (128 or more) that is not the expected one"
run_tap 'c=0; out=$(trap - ERR; sh -c "kill -SEGV \$\$") || c=$?; tap_status "$c" 64
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_status bails out on a signal status (128 or more) that is not the expected one"
run_tap 'tap_run out 0 sh -c "exit 141"
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_run bails out when the program itself dies of SIGPIPE (141)"
run_tap 'c=0; out=$(trap - ERR; sh -c "exit 141") || c=$?; tap_status "$c" 0
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_status bails out on 141 when another status was expected"
run_tap 'sh -c "kill -PIPE \$\$" | cat >/dev/null; tap_ok "reader of a pipeline left early"
tap_done' tap
has "ok 1 - reader of a pipeline left early" "$TMP/tap" && nogrep '^Bail out!' "$TMP/tap"; tap_check $? "170: the left side of a pipeline that dies of SIGPIPE is allowed"
run_tap 'python3 /nonexistent/missing-script.py 2>/dev/null
tap_ok "never"
tap_done' tap
nogrep 'or declare the failure expected' "$TMP/tap" && nogrep '|| true' "$TMP/tap" && has_bail; tap_check $? "170: the Bail out! message does not suggest || true"

# 8l. #170, extra round: forms whose crash tap_run or bash 3.2 cannot see.
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
run_tap '[ "`python3 /nonexistent/missing-script.py`" = 3 ]; tap_check $? "backtick substitution with a lone program"
tap_done' tap
has_bail && nogrep '^not ok' "$TMP/tap" && rc_not 0; tap_check $? "170: a lone program in a backtick substitution emits Bail out!"
else tap_skip "170: a lone program in a backtick substitution emits Bail out!" "bash 3.2 runs a lone external command of a substitution with exec: its ERR trap never runs (forbidden in the red, see the header of tap.sh)"; fi
run_tap 'setup() { python3 /nonexistent/missing-script.py 2>/dev/null; echo 4; }
tap_run out 0 setup
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_run refuses a shell function: a crash inside it would be hidden"
run_tap 'tap_run out 0 sh -c "python3 /nonexistent/missing-script.py; echo 4"
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_run refuses sh -c with more than one command"
run_tap 'tap_run out 0 bash -c "python3 /nonexistent/missing-script.py || echo 4"
tap_ok "never"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_run refuses bash -c with || in its script"
run_tap 'tap_run out 64 sh -c "exit 64"
[ "$TAP_RC" -eq 64 ]; tap_check $? "single command of sh -c"
tap_done' tap
has "ok 1 - single command of sh -c" "$TMP/tap" && rc_is 0; tap_check $? "170: tap_run still takes sh -c with a single command"
run_tap 'tap_ok "same id"
tap_skip "same id" "later"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: tap_skip bails out on an id that already has a verdict"
run_tap 'tap_skip "same id" "now"
tap_ok "same id"
tap_done' tap
has_bail && rc_not 0; tap_check $? "170: a verdict bails out on an id that was skipped"
formas=""
for f in .claude/skills/implement-issue/SKILL.md .claude/skills/implement-issue/SKILL.es.md .claude/skills/review-pr/SKILL.md .claude/skills/review-pr/SKILL.es.md; do
  [ -f "$ROOT/$f" ] || continue
  grep -q 'tap_run' "$ROOT/$f" || continue  # the small profile has its own guides, with no red section
  for t in '`prog`' 'tap_run out 0 setup_fn' 'sh -c'; do
    grep -qF -- "$t" "$ROOT/$f" || formas="$formas $f:$t"
  done
done
if [ -z "$formas" ]; then ok=0; else ok=1; fi; tap_check "$ok" "170: the guides forbid the backtick form and tap_run around a function or sh -c in the red" "missing:${formas:- none}"
sed -n '1,/^_TAP_BASE=/p' "$ROOT/scripts/agents/tap.sh" >"$TMP/header"
grep -qF '`prog`' "$TMP/header" && grep -qF 'setup_fn' "$TMP/header"; tap_check $? "170: the header of tap.sh lists the backtick form and tap_run around a function"
grep -qF 'in a red commit (#189) only when' "$TMP/header"; tap_check $? "189: the header of tap.sh says that the runner of #182 is accepted in a red commit"
grep -qF 'second marker' "$TMP/header"; tap_check $? "189: the header of tap.sh asks for a second marker that proves the nested test reached the step under test"
grep -qF 'the check of the second marker passes in the red' "$TMP/header"; tap_check $? "189: the header of tap.sh says that the check of the second marker passes in the red"
grep -qF 'before the step under test is not a failed case' "$TMP/header"; tap_check $? "211: the header of tap.sh says that a nested crash before the step under test is not a failed case"
grep -qF 'a crash in the step under test is accepted as a failed case' "$TMP/header"; tap_check $? "211: the header of tap.sh says that a crash in the step under test is accepted as a failed case"
grep -qF 'id starts with `second marker:`' "$TMP/header"; tap_check $? "211: the header of tap.sh names the id prefix of the case of the second marker"
grep -qF 'the rc-file exists' "$TMP/header"; tap_check $? "211: the header of tap.sh asks a case that checks that the rc-file exists"

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
# The forms bash cannot tell from a crash are forbidden in the red commit and reviewed (#170).
falta=""
for f in .claude/skills/implement-issue/SKILL.md .claude/skills/implement-issue/SKILL.es.md .claude/skills/review-pr/SKILL.md .claude/skills/review-pr/SKILL.es.md; do
  for t in 'local x=$(prog)' 'trap - ERR' '|| true' '( prog )' '$( prog )' 'tap_status' 'tap_run' '&&'; do
    [ -f "$ROOT/$f" ] || continue  # an installed project keeps one language
    grep -q 'tap_run' "$ROOT/$f" || continue  # the small profile has its own guides, with no red section
    grep -qF -- "$t" "$ROOT/$f" || falta="$falta $f:$t"
  done
done
[ -z "$falta" ]; tap_check $? "170: implement-issue and review-pr (en and es) list every form that cannot be told from a crash" "missing:${falta:- none}"
forms_doc() { local f="$ROOT/.claude/skills/$1"; [ ! -f "$f" ] || ! grep -q 'tap_run' "$f" || grep -qE "$2" "$f"; }
forms_doc implement-issue/SKILL.md "forbidden|prohib" && forms_doc implement-issue/SKILL.es.md "prohib"; tap_check $? "170: implement-issue forbids those forms in the red commit (en and es)"
forms_doc review-pr/SKILL.md "red commit adds|commit en rojo" && forms_doc review-pr/SKILL.es.md "commit en rojo"; tap_check $? "170: review-pr flags them in the lines the red commit adds (en and es)"
# A second status argument to tap_check takes the place of the id: it takes the second $? as the id and loses the literal one (#170).
perdidos=""
for s in $SCRIPTS scripts/agents/test-tap.sh; do
  grep -qE 'tap_check \$\? \$\?|check \$\? \$\?' "$ROOT/$s" && perdidos="$perdidos $s"
done
[ -z "$perdidos" ]; tap_check $? "170: no test passes the status twice to tap_check (the second one would be the id)" "still:${perdidos:- none}"
# tap_begin runs before any cd of the script: with a relative $0 it would resolve from the wrong folder.
tarde=""
for s in $SCRIPTS; do
  b=$(grep -n '^tap_begin ' "$ROOT/$s" | head -1 | cut -d: -f1 || true)  # no match: no line
  c=$(grep -n '^cd ' "$ROOT/$s" | head -1 | cut -d: -f1 || true)
  [ -z "$c" ] || [ "${b:-999999}" -lt "$c" ] || tarde="$tarde $s"
done
[ -z "$tarde" ]; check $? "tap_begin comes before the first cd of each test" "after the cd:${tarde:- none}"

# 8m. #173: the Bail out! of tap_run shows what the program printed, FAIL lines first (a nested test that fails).
run_tap 'tap_run out 0 python3 -c "print(\"short-mark\" + \"er-out\"); raise SystemExit(1)"
tap_ok "never"
tap_done' tap
grep -q '^Bail out!.*short-marker-out' "$TMP/tap"; tap_check $? "173: the Bail out! of tap_run includes a short output of the program"
run_tap 'tap_run out 0 python3 -c "print(\"FAIL - early \" + \"id\\n       early \" + \"detail\\n\" + \"ok filler\\n\" * 200); raise SystemExit(1)"
tap_ok "never"
tap_done' tap
grep -q '^Bail out!.*FAIL - early id.*early detail' "$TMP/tap"; tap_check $? "173: the Bail out! of tap_run includes the FAIL lines of a long output, not only its end"

# 8n. #182, #139: an install that fails in test-install.sh leaves install.py's output in the log. The kit is copied to
# a fake root whose install.py is a stub: it runs the real one (install-real.py) unless STUB_FAIL is one of its arguments
# or the name of the folder it runs in, and then it prints "STUB-OUT-<STUB_FAIL>" and ends with 1. The nested test
# bails out there, and its Bail out! has to carry that line. The runner ends with 0 on purpose: what the cases look at
# is what the nested test printed, not the status it ended with.
# An installed project has no install.py or test-install.sh (the installer removes them): there is nothing to look at.
if [ -f "$ROOT/scripts/install.py" ] && [ -f "$ROOT/scripts/test-install.sh" ]; then
  FAKE="$TMP/fake-kit"
  mkdir -p "$FAKE"
  (cd "$ROOT" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | (cd "$FAKE" && tar -xf -)
  git -C "$FAKE" init -q
  mv "$FAKE/scripts/install.py" "$FAKE/scripts/install-real.py"
  printf '%s\n' 'import os, runpy, sys' \
    'fail = os.environ.get("STUB_FAIL")' \
    'if fail and fail in sys.argv[1:] + [os.path.basename(os.getcwd())]:' \
    '    print("STUB-OUT-" + fail)' \
    '    sys.exit(1)' \
    'sys.argv[0] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "install-real.py")' \
    'runpy.run_path(sys.argv[0], run_name="__main__")' >"$FAKE/scripts/install.py"
  printf '#!/usr/bin/env bash\nbash "$1"\necho $? >"$2"\nexit 0\n' >"$TMP/runner.sh"
  out=""
  rm -f "$TMP/nested-rc"
  tap_run out 0 env STUB_FAIL=--draft bash "$TMP/runner.sh" "$FAKE/scripts/test-install.sh" "$TMP/nested-rc"
  [ -f "$TMP/nested-rc" ]; tap_check $? "211: the runner of #182 wrote the rc-file (--draft case)"
  grep -q '^Bail out!.*STUB-OUT---draft' <<<"$out" && [ "$(<"$TMP/nested-rc")" = 1 ]
  tap_check $? "182: test-install.sh shows the output of install.py when the --draft case fails" "nested run: $(tail -c 300 <<<"$out")"
  rm -f "$TMP/nested-rc"
  tap_run out 0 env STUB_FAIL=usuario-grow-ref bash "$TMP/runner.sh" "$FAKE/scripts/test-install.sh" "$TMP/nested-rc"
  [ -f "$TMP/nested-rc" ]; tap_check $? "211: the runner of #182 wrote the rc-file (preparation install case)"
  grep -q '^Bail out!.*STUB-OUT-usuario-grow-ref' <<<"$out" && [ "$(<"$TMP/nested-rc")" = 1 ]
  tap_check $? "139: test-install.sh shows the output of install.py when a preparation install fails" "nested run: $(tail -c 300 <<<"$out")"
  # A nested run is a whole test-install.sh (minutes), so only the draft case (#182) and the preparation install of the grow.py
  # case (#139) run. The rest are looked at in the source: an install.py call that is not one of the expected-to-fail
  # ones (status 1, where the test checks the message) goes through tap_run expecting 0, which shows its output when it fails.
  # Usage: install_offenders <test file> <out file>: the lines of the test that call install.py (or the instalar wrapper) in a
  # way that can hide its output. It ends with 0 on purpose: the last grep ends with 1 when it finds nothing.
  install_offenders() {
    grep -nE 'install\.py|instalar Demo' "$1" >"$2.all"
    grep -vE 'tap_run|tap_status "\$c" 1|^[0-9]+:(#|instalar\(\)|! \[ -e "\$U/scripts/install\.py"|  cd "\$P5" && rm -f scripts/install\.py)' "$2.all" >"$2"
    return 0
  }
  install_offenders "$ROOT/scripts/test-install.sh" "$TMP/offenders"
  if [ -s "$TMP/offenders" ]; then ok=1; else ok=0; fi; tap_check "$ok" "139: every install.py call of test-install.sh that must succeed goes through tap_run, which shows its output" "first offender: $(head -1 "$TMP/offenders")"
  # The guard has to see the calls through the instalar wrapper, and a line that only contains rm -f is not an exception.
  printf '%s\n' '# instalar Demo main: a comment' 'instalar() { (cd "$U" && python3 "$RAIZ/scripts/install.py" "$@" 2>&1); }' \
    'c=0; s=$(instalar Demo main --template "$P") || c=$?; tap_status "$c" 1' \
    'tap_run s 0 env python3 "$RAIZ/scripts/install.py" Demo main' \
    '! [ -e "$U/scripts/install.py" ] && ! [ -e "$U/scripts/test-install.sh" ]' \
    '  cd "$P5" && rm -f scripts/install.py scripts/test-install.sh && git init -q' \
    'es "$c" -eq 0; tap_check $? "update.py funciona despues de instalar"' >"$TMP/fixture-ok.sh"
  install_offenders "$TMP/fixture-ok.sh" "$TMP/fixture-ok.out"
  if [ -s "$TMP/fixture-ok.out" ]; then ok=1; else ok=0; fi; tap_check "$ok" "184: the guard accepts the expected-to-fail calls, the tap_run calls and the known exceptions" "flagged: $(head -1 "$TMP/fixture-ok.out")"
  printf '%s\n' 'c=0; s=$(instalar Demo main --template "$P"); tap_status "$c" 0' \
    'rm -f x; python3 "$RAIZ/scripts/install.py" Demo main; tap_status "$c" 0' >"$TMP/fixture-bad.sh"
  install_offenders "$TMP/fixture-bad.sh" "$TMP/fixture-bad.out"
  if [ "$(wc -l <"$TMP/fixture-bad.out")" -eq 2 ]; then ok=0; else ok=1; fi; tap_check "$ok" "184: the guard flags an instalar call that must succeed and an install.py call with an rm -f next to it" "flagged: $(tr '\n' ' ' <"$TMP/fixture-bad.out")"
else
  tap_skip "182: test-install.sh shows the output of install.py when the --draft case fails" "the project has no install.py"
  tap_skip "139: test-install.sh shows the output of install.py when a preparation install fails" "the project has no install.py"
  tap_skip "139: every install.py call of test-install.sh that must succeed goes through tap_run, which shows its output" "the project has no install.py"
  tap_skip "184: the guard accepts the expected-to-fail calls, the tap_run calls and the known exceptions" "the project has no install.py"
  tap_skip "184: the guard flags an instalar call that must succeed and an install.py call with an rm -f next to it" "the project has no install.py"
fi

# 9. JUnit XML in the file (ADR-002 D6, #225): one closed testsuite per script, appended to the file that the entry's run wraps in <testsuites>.
# xq <expression>: python evaluates it with `root` = the elements of the file wrapped in one root; true is 0, false (or a file that does not parse) is 1.
cat >"$TMP/xq.py" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
# Only a file that does not parse, or a case or suite that is not there, answers "no". Anything else (a typo in the
# expression: NameError, TypeError; a missing file) leaves with a traceback and a non-zero status, so that tap_run bails
# out and the red cannot take a crash for a failed assertion.
data = open(sys.argv[1], "rb").read()
try:
    root = ET.fromstring(b"<r>" + data + b"</r>")
except ET.ParseError:
    print("no")
    sys.exit(0)
suites = root.findall("testsuite")
cases = {c.get("name"): c for c in root.iter("testcase")}
try:
    print("yes" if eval(sys.argv[2]) else "no")
except (KeyError, IndexError):
    print("no")
PYEOF
xq() { tap_run XQ 0 python3 "$TMP/xq.py" "$TMP/tap" "$1"; [ "$XQ" = yes ]; }

run_tap 'tap_ok "creates the branch"
tap_fail "assigns the issue" "input 7"
tap_ok "labels it"
tap_done' junit
xq 'len(suites) == 1 and suites[0].get("tests") == "3" and len(cases) == 3'; tap_check $? "225: JUnit: one testsuite per script, with tests= the number of cases"
xq 'all(c.get("file") for c in cases.values()) and suites[0].get("file") and suites[0].get("file") == cases["labels it"].get("file")'; tap_check $? "225: JUnit: the testsuite and every testcase carry the file of the script"
xq 'cases["assigns the issue"].find("failure") is not None and cases["creates the branch"].find("failure") is None and suites[0].get("failures") == "1"'; tap_check $? "225: JUnit: a failed case has a failure child, a passing one has none, failures= counts them"
xq '"input 7" in (cases["assigns the issue"].findtext("system-out") or "") and "input 7" not in "".join(cases)'; tap_check $? "225: JUnit: the description goes in the system-out of the testcase, not in its name"
rc_is 1; tap_check $? "225: JUnit: exits with 1 when a case fails"
empty "$TMP/stdout"; tap_check $? "225: JUnit: writes nothing to stdout when it has an output file"
has "FAIL - assigns the issue" "$TMP/stderr"; tap_check $? "225: JUnit: a failing case is reported on stderr as FAIL - id"
nogrep '^ok \|^not ok \|^1\.\.\|^# file:' "$TMP/tap"; tap_check $? "225: JUnit: the file has no TAP lines"
# what the test prints on stdout never reaches the report (ADR-002 D6: a line of the test cannot inject a case). With
# "exec 1>&8" after the helper opens TAP_OUT, the echo below lands in the file and "injected" becomes a testcase.
run_tap 'echo "<testcase name=\"injected\"/>"
tap_ok "real case"
tap_done' junit
xq '"real case" in cases and "injected" not in cases'; tap_check $? "273: JUnit: what the test prints on stdout does not reach the file (no injected case)"

run_tap 'tap_ok "a"
tap_done' junit
rc_is 0; tap_check $? "225: JUnit: exits with 0 when every case passes"
xq 'suites[0].get("failures") in ("0", None) and suites[0].get("errors") in ("0", None)'; tap_check $? "225: JUnit: a passing run has no failures or errors"

run_tap 'tap_ok "a <b> & \"c\" '"'"'d'"'"'"
tap_done' junit
xq '"a <b> & \"c\" '"'"'d'"'"'" in cases'; tap_check $? "225: JUnit: an id with XML characters is escaped and comes back whole"

# bytes that are not UTF-8 in a description are dropped: the file stays well-formed XML
run_tap 'tap_fail "binary desc" "bad $(printf "\377\376") byte"
tap_done' junit
xq '"binary desc" in cases and cases["binary desc"].find("failure") is not None'; tap_check $? "225: JUnit: a description with bytes that are not UTF-8 still leaves a well-formed file"

# a repeated id (a loop) is one case: an error if any turn ended in an error (a bail out), else a failure if any failed
run_tap 'for i in 1 2 3; do
  if [ "$i" -eq 2 ]; then tap_fail "loop id" "turn $i"; else tap_ok "loop id" "turn $i"; fi
done
tap_done' junit
xq 'len(cases) == 1 and cases["loop id"].find("failure") is not None and suites[0].get("tests") == "1"'; tap_check $? "225: JUnit: a repeated id is one testcase, a failure if any turn failed"
run_tap 'set -e
for i in 1 2 3; do
  if [ "$i" -eq 1 ]; then tap_fail "loop id" "turn $i"; else tap_ok "loop id" "turn $i"; fi
done
false
tap_done' junit
xq 'any(c.find("error") is not None for c in root.iter("testcase")) and cases["loop id"].find("failure") is not None'; tap_check $? "225: JUnit: a crash after a failed turn leaves an error testcase next to the failure (an error is never hidden by grouping)"

# a bail out is an error testcase in a closed testsuite, and the cases before it stay
run_tap 'set -e
tap_ok "before"
false
tap_ok "after"
tap_done' junit
xq 'len(suites) == 1 and any(c.find("error") is not None for c in suites[0].iter("testcase")) and "before" in cases and "after" not in cases'; tap_check $? "225: JUnit: an unexpected error closes the testsuite with an error testcase and keeps the earlier cases"
xq 'suites[0].get("errors") == "1" and suites[0].get("tests") == str(len(list(suites[0].iter("testcase"))))'; tap_check $? "225: JUnit: after a bail out errors= and tests= match the testcase elements"
rc_not 0; tap_check $? "225: JUnit: an unexpected error exits non-zero"
run_tap 'tap_ok "before"
exit 3' junit
xq 'len(suites) == 1 and any(c.find("error") is not None for c in suites[0].iter("testcase"))'; tap_check $? "225: JUnit: leaving before tap_done leaves an error testcase in a closed testsuite"
rc_is 3; tap_check $? "225: JUnit: leaving before tap_done keeps the exit code"

# skipped cases
run_tap 'tap_ok "runs"
tap_skip "does not apply" "no docker here"
tap_done' junit
xq 'cases["does not apply"].find("skipped") is not None and cases["runs"].find("skipped") is None and suites[0].get("tests") == "2"'; tap_check $? "225: JUnit: tap_skip is a testcase with a skipped child"
xq '"no docker here" in ET.tostring(cases["does not apply"], encoding="unicode")'; tap_check $? "225: JUnit: the reason of tap_skip is in the testcase"
run_tap 'tap_skip_all "needs a network"' junit
xq 'len(suites) == 1 and suites[0].get("tests") == "0" and len(cases) == 0 and "needs a network" in (suites[0].findtext("system-out") or "")'; tap_check $? "225: JUnit: tap_skip_all is a closed testsuite with tests=0 and the reason in its system-out"
rc_is 0; tap_check $? "225: JUnit: tap_skip_all exits with 0"

# a tab in an id is written as &#9;: an attribute value read back by XML would turn a raw tab into a space and D4 would not find the id
TAB=$(printf '\t'); tabid="a${TAB}b"
run_tap "tap_ok \"$tabid\"
tap_done" junit
xq '"a\tb" in cases'; tap_check $? "225: JUnit: a tab in an id comes back as a tab (escaped, not normalized to a space)"

# a bail out inside a substitution is one bail out: the main shell does not write a second testsuite for the same script
run_tap 'tap_ok "before"
x=$(tap_ok "")
tap_done' junit
xq 'len(suites) == 1 and "before" in cases'; tap_check $? "225: JUnit: a bail out inside a substitution leaves one testsuite, not two"

# U+FFFE and U+FFFF are valid UTF-8 and not allowed in XML 1.0: they must not break the file
run_tap "tap_fail \"x\" \"\$(printf 'a\\357\\277\\276b\\357\\277\\277c')\"
tap_done" junit
xq 'len(suites) == 1 and "x" in cases and cases["x"].find("failure") is not None'; tap_check $? "225: JUnit: U+FFFE and U+FFFF in a description leave a well-formed file"

# the error testcase says it is the script that failed, and cannot be mistaken for an id of the test
run_tap 'set -e
false
tap_done' junit
xq 'any(c.get("name") == "script error: did not finish" and c.find("error") is not None for c in suites[0].iter("testcase"))'; tap_check $? "225: JUnit: the error testcase is named script error: did not finish"

# writing the file does not start a tr and an iconv per value: they run once over the suite (500 cases)
SHIMS="$TMP/shims"; mkdir -p "$SHIMS"; : >"$TMP/spawns.log"
REAL_TR=$(command -v tr); REAL_ICONV=$(command -v iconv)
printf '#!/bin/sh\necho tr >>"%s"\nexec "%s" "$@"\n' "$TMP/spawns.log" "$REAL_TR" >"$SHIMS/tr"
printf '#!/bin/sh\necho iconv >>"%s"\nexec "%s" "$@"\n' "$TMP/spawns.log" "$REAL_ICONV" >"$SHIMS/iconv"
chmod +x "$SHIMS/tr" "$SHIMS/iconv"
OLD_PATH=$PATH; PATH="$SHIMS:$PATH"
run_tap "$(awk 'BEGIN { for (i = 1; i <= 500; i++) printf "tap_ok \"case-%d\" \"description %d\"\n", i, i }')
tap_done" junit
PATH=$OLD_PATH
xq 'len(cases) == 500 and suites[0].get("tests") == "500"'; tap_check $? "225: JUnit: 500 cases leave 500 testcases"
[ "$(count . "$TMP/spawns.log")" -le 6 ]; tap_check $? "225: JUnit: tr and iconv run a few times for the whole suite, not once per value"

# several scripts share the file: each one appends its testsuite
run_tap 'tap_ok "first script"
tap_done' junit
printf '%s\n' '#!/usr/bin/env bash' ". \"$ROOT/scripts/agents/tap.sh\"" 'tap_begin "$0"' 'tap_ok "second script"' 'tap_done' >"$TMP/t2.sh"
tap_run SECOND 0 env -u TAP_FORMAT TAP_OUT="$TMP/tap" bash "$TMP/t2.sh"
xq 'len(suites) == 2 and "first script" in cases and "second script" in cases and suites[0].get("file") != suites[1].get("file")'; tap_check $? "225: JUnit: a second script appends its own testsuite to the same file"

# a bail that arrives after tap_done (a >(…) that crashes while the suite is being written leaves its reason in the bail file)
# does not write the suite a second time: the cases stay once, and the error goes in a testsuite of its own
run_tap 'tap_ok "x"
printf "late crash" >"$_TAP_BAILFILE"
tap_done' junit
xq 'sum(1 for c in root.iter("testcase") if c.get("name") == "x") == 1'; tap_check $? "264: JUnit: a bail after tap_done does not repeat the cases of the suite"
xq 'any(c.find("error") is not None for c in root.iter("testcase"))'; tap_check $? "264: JUnit: a bail after tap_done still leaves an error testcase"
rc_is 1; tap_check $? "264: JUnit: a bail after tap_done exits with 1"

# the real route: a child that dies while the suite is being written leaves its reason and sends TERM to the script, as
# _tap_crash does from a >(…). Here a sed shim does it once, from inside _tap_clean, so the TERM lands at a known point
# (bash runs the TERM trap when the substitution returns): the script ends through the TERM and EXIT traps.
SHIMS="$TMP/shims"; mkdir -p "$SHIMS"; rm -f "$TMP/fired"
printf '#!/bin/sh\nif [ ! -e "%s" ]; then : >"%s"; printf "late crash" >"$TAP_TEST_BAIL"; kill -TERM "$TAP_TEST_MAIN"; fi\nexec "%s" "$@"\n' "$TMP/fired" "$TMP/fired" "$(command -v sed)" >"$SHIMS/sed"
chmod +x "$SHIMS/sed"
OLD_PATH=$PATH; PATH="$SHIMS:$PATH"
run_tap 'tap_ok "x"
export TAP_TEST_BAIL=$_TAP_BAILFILE TAP_TEST_MAIN=$$
tap_done' junit
PATH=$OLD_PATH
[ -e "$TMP/fired" ]; tap_check $? "264: JUnit: the sed shim of the late crash ran (the TERM was sent while the suite was written)"
xq 'sum(1 for c in root.iter("testcase") if c.get("name") == "x") == 1'; tap_check $? "264: JUnit: a crash that sends TERM while the suite is written leaves the cases once"
xq 'any(c.find("error") is not None and c.find("error").get("message") == "late crash" for c in root.iter("testcase"))'; tap_check $? "264: JUnit: a crash that sends TERM while the suite is written leaves its error testcase"
rc_is 1; tap_check $? "264: JUnit: a crash that sends TERM while the suite is written exits with 1"

# the format: TAP_FORMAT. 2.0.0 writes only JUnit: junit is accepted, and any other value fails closed, tap included.
run_tap 'tap_ok "x"
tap_done' fmt=junit
xq '"x" in cases'; tap_check $? "225: TAP_FORMAT=junit writes JUnit"
run_tap 'tap_ok "x"
tap_done' fmt=tap
empty "$TMP/tap"; tap_check $? "273: TAP_FORMAT=tap writes no report"
rc_is 2; tap_check $? "273: TAP_FORMAT=tap exits with 2 (fails closed)"
has_msg 'TAP_FORMAT=tap'; tap_check $? "273: TAP_FORMAT=tap is named on stderr"
empty "$TMP/stdout"; tap_check $? "273: TAP_FORMAT=tap: stdout stays empty (the rejection is only on stderr)"
run_tap 'tap_ok "x"
tap_done' fmt=yaml
empty "$TMP/tap"; tap_check $? "225: an unknown TAP_FORMAT writes no report"
rc_is 2; tap_check $? "225: an unknown TAP_FORMAT exits with 2 (fails closed)"
has_msg 'TAP_FORMAT'; tap_check $? "225: an unknown TAP_FORMAT is named on stderr"
[ ! -e "$TMP/tap" ]; tap_check $? "264: an unknown TAP_FORMAT does not create TAP_OUT (the format is checked before the file is opened)"

# TAP_FORMAT, like TAP_OUT, is not left in the environment of the test: a fixture it starts decides its own format
run_tap 'echo "format=${TAP_FORMAT-unset} out=${TAP_OUT-unset}"
tap_ok "x"
tap_done' fmt=junit
has "format=unset out=unset" "$TMP/stdout"; tap_check $? "225: TAP_FORMAT and TAP_OUT are unset for the test once the helper has opened the file"

tap_done
