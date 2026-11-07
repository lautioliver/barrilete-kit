# shellcheck shell=bash
# TAP 14 helper for the kit's tests (ADR-002 D6, issue #151). It is sourced, not run:
#
#   . "$ROOT/scripts/agents/tap.sh"
#   tap_begin "$0"                       # the path of the script from the repo root (its `file` in JUnit, "# file:" in TAP)
#   tap_at_exit 'rm -rf "$TMP"'          # instead of trap ... EXIT, which would replace the helper's
#   tap_run   out 64 prog args...        # runs a program that may fail: output in $out, status in $TAP_RC
#   c=0; out=$(trap - ERR; prog) || c=$?; tap_status "$c" 64    # the same, for a command line; tap_no_traceback "$out"
#   tap_ok    "literal id" ["description"]
#   tap_fail  "literal id" ["description"]
#   tap_check $? "literal id" ["description"]   # 0 is ok, 1 is not ok, any other status is a bail out
#   tap_skip  "literal id" "reason"       # a case that does not apply here: a skipped testcase (TAP: ok N - id # SKIP reason)
#   tap_done                             # writes the report of the script and exits (1 if a case failed)
#   tap_skip_all "reason"                # for a script that does not apply: a testsuite with tests="0", exits 0
#
# The id is a literal, written in the source: red.sh compares only that name with the lines the red
# commit adds (ADR-002 D4). What varies at run time goes in the description, which is not compared
# and is written as a "# desc:" line (in JUnit, the system-out of the testcase). An id cannot be empty and cannot have a
# newline (the helper bails out). An id that repeats is the same case, not a new one (red.sh rejects an ambiguous name): a loop
# that checks the same thing for several inputs passes one literal id and the input as the description,
# and the case fails if any of them fails; each failing description is written under it.
#
# The cases are held until tap_done (or a bail out) and written then, in the order of their first call.
# Where this header says "Bail out!", "the plan" or "the numbering", it speaks of the TAP stream (without TAP_OUT, on stdout):
# in JUnit a bail out is an error testcase in the closed testsuite, and there is no plan or numbering.
#
# What it writes (ADR-002 D6, #225). With TAP_OUT, JUnit XML: when the script ends (tap_done, tap_skip_all or a bail out) it
# appends ONE closed <testsuite name= file= tests= failures= errors= skipped=> with a <testcase name=id file=> per case (a
# <failure> child for a failed one, <skipped> for tap_skip, the description in its <system-out>), and a bail out adds a
# testcase with an <error> child, so a crash is never a failed case. It does not write the root: several scripts append
# to the same file and the `run` of the entry wraps the testsuites in <testsuites>...</testsuites> at the end. An id that
# repeats is ONE testcase: a failure if any turn failed (a crash ends the script, and its error testcase counts for D3 anyway).
# TAP_FORMAT (ADR-002 D6, D8: 2.0.0 writes only JUnit): unset or "junit" is JUnit; any other value, tap included, writes
# no report and exits with 2 (fails closed). Without TAP_OUT the helper prints TAP on stdout, for people, and writes no file.
#
# Where the report goes. Under red.sh, TAP_OUT is the file it created ({out}): the helper opens it once,
# on fd 8 (a path that cannot be opened is a bail out with exit 2), and unsets the variable, so the test does not see the path and what it prints on stdout
# cannot inject cases. Without TAP_OUT (a person running the test, the docs CI) the TAP goes to
# stdout. Each failing case is also printed on stderr as "FAIL - <id>", so a CI log shows it.
#
# Unexpected errors (ADR-002 D6: a crash is never a failed assertion). The helper turns on errtrace
# (set -E) and pipefail, so the ERR trap runs in functions, command and process substitutions, subshells
# and every element of a pipeline. Any command that fails is an unexpected error and the run ends with
# a bail out (exit 1; an error testcase in JUnit, "Bail out!" in TAP), except an assertion that fails with status 1: test, [, [[, ((, grep, egrep, fgrep,
# diff and cmp. A failing assertion is what "<assertion>; tap_check $? ..." is for, wherever it runs (inside
# a function, an argument, a pipeline). So "[ "$(python3 x.py 2>&1)" = 3 ]", "python3 x.py | grep -q 3" and a
# setup function that crashes before its last command all bail out (on bash 3.2 a lone program in a substitution is
# the exception, see below). An assertion tool that fails with
# another status (2: a usage error, a file it could not read) bails out too, and so does a status 126 or 127.
# In a pipeline, an element other than the last one has to succeed (status 141, SIGPIPE, is the reader
# leaving early and is allowed). Bash does not call the ERR trap in a condition ("if cmd", "! cmd") or
# before || and &&: that is how a test says a failure is expected, and then the helper cannot tell a crash
# from the behaviour. A program that is expected to fail goes through tap_run, which compares its status
# with the one the test expects: any other status is a bail out when it is 1, 2, 126, 127 or 128 or more (a signal; what a crash gives) and
# is left to the test to compare otherwise. Under set -e any failure bails out, assertions included.
#
# What it cannot see. These are forms bash cannot tell from a crash. They are FORBIDDEN in the red commit (the
# implement-issue guide says so and review-pr flags them in the lines the red commit adds, ADR-002 D6); the kit's own
# tests accept them in their setup, where they are listed here:
#   - a program the test expects to fail with 1 or 2 (tap_run or tap_status with that status, "|| true"): a crash with
#     that same status looks like the behaviour. A tool whose failure is a verdict (check-docs.py exits 1 on findings)
#     is in this case; tap_no_traceback "$out" covers Python tools by their traceback;
#   - tap_status: its only idiom is "c=0; out=$(trap - ERR; prog) || c=$?; tap_status "$c" 64", which has the next two
#     forms in it. It is for the kit's own setup; a red uses tap_run;
#   - "trap - ERR", and "|| true" after a command or a substitution: bash 5 does not watch what runs under the
#     "||" (bash 3.2 still calls the trap inside a substitution), so the crash is hidden: use tap_run;
#   - tap_run around a shell function, "sh -c" or "bash -c" with several commands, or anything that runs more than one
#     program ("tap_run out 0 setup_fn"): tap_run turns the ERR trap off, so a crash before the last command is hidden.
#     tap_run refuses a function and a plain sh/bash -c script with ; & | or a newline; the safe form is a single program.
#     It does not see, for example, eval f, builtin eval, command eval, env bash -c, bash --norc -c, ksh -c, nice sh -c,
#     xargs sh -c, a backtick or a $(...) inside an sh -c script, or any other wrapper or substitution that runs more than
#     one program (a crash with status 2 is a valid red there on bash 3.2): they are forbidden too (#173);
#   - a failure in the middle of "a && b" or "a || b", and in a condition (if, while, "!"), whatever the status of the
#     crash: bash does not call the trap, and "|| c=$?", "|| :" or "!" consume the status. Only "a && b; tap_check $?"
#     passes the status on, and tap_check bails out on any status other than 0 and 1 (a status 1, a traceback, is not seen);
#   - "local x=$(prog)" hides the status of prog (a crash inside prog still bails out on bash 5);
#   - on bash 3.2 (macOS), a subshell "( cmd )", a substitution "$( cmd )" and a backtick substitution with a single
#     external command and no redirection: bash 3.2 runs it with exec, the ERR trap never runs, and a crash there (for
#     example "[ \"$(python3 missing.py)\" = 3 ]" or "[ -z \"`prog`\" ]") is a failed assertion or even a pass. Bash 5
#     forks and sees it. A redirection ("$(prog 2>/dev/null)") or a second command forces the fork on 3.2 too.
#
# The one accepted way to look at a nested test that ends with a Bail out! (#182): a runner script that ends with 0 and
# saves the nested status ("bash \"$1\"; echo $? >\"$2\"; exit 0"), run as "tap_run out 0 bash runner.sh nested.sh rc-file". It is accepted in
# the kit's own tests, and in a red commit (#189) only when the case checks, in separate tap_check (never grep && [ ]), a marker that
# only the code under test prints in "$out" and the saved status, and a second marker, printed by the nested test right before the
# step under test, that proves it got there (a nested crash before the step under test is not a failed case, and a crash in the step under test is accepted as a failed case): the check of the second marker passes in the red, so it is never a failing case, and red.sh rejects the red when it fails; red.sh recognizes it because its id starts with `second marker:`. Another case checks that
# the rc-file exists, so that a status file that was not written is not read as a failed assertion. Do not use it to
# hide the status of a program: tap_run on a single program, expecting 0, is still the rule.
#
# A test runs in the same shell as this file, so it could still read _TAP_PATH or write to fd 8: it is
# not a sandbox, only a path that the test has no reason to touch.

_TAP_SELF=${BASH_SOURCE[0]}
_TAP_BASE=0
_TAP_FAILED=0
_TAP_IDS=()
_TAP_VERDICTS=()
_TAP_DESCS=()
_TAP_REPS=()
_TAP_SKIPS=()
_TAP_DONE=0
_TAP_BAILED=0
_TAP_AT_EXIT=""
_TAP_PATH=""
_TAP_FMT=tap        # junit when there is a TAP_OUT (the only format of the report); tap is the stdout of a person
_TAP_FILE=""        # the path of the script, from tap_begin
_TAP_ERR_NAME="script error: did not finish"   # the name of the error testcase (JUnit): it says the script did not finish
_TAP_BAILFILE=""    # where a subshell leaves the reason of a bail out for the main shell (it cannot exit the script)
TAP_RC=0

if [ -n "${TAP_OUT:-}" ]; then
  case ${TAP_FORMAT:-junit} in
    junit) ;;
    *) echo "Bail out! TAP_FORMAT=${TAP_FORMAT} is not junit: 2.0.0 writes only JUnit, the helper writes no report" >&2; exit 2 ;;
  esac
  _TAP_PATH=$TAP_OUT
  { exec 8>>"$_TAP_PATH"; } 2>/dev/null || { echo "Bail out! cannot open TAP_OUT ($_TAP_PATH)" >&2; exit 2; }
  _TAP_FMT=junit
else
  exec 8>&1
fi
unset TAP_OUT TAP_FORMAT

_tap_line() { printf '%s\n' "$1" >&8; }

# Usage: _tap_flat <text>: the text in one line.
_tap_flat() { local t=$1; t=${t//$'\r'/ }; printf '%s' "${t//$'\n'/ }"; }

_tap_bail() {
  [ "$_TAP_BAILED" -eq 0 ] || return 0
  _TAP_BAILED=1
  if [ "$_TAP_FMT" = junit ]; then
    _tap_junit_suite "$(_tap_flat "$1")"
  else
    _tap_flush
    _tap_line "Bail out! $(_tap_flat "$1")"
  fi
  [ -z "$_TAP_PATH" ] || echo "Bail out! $(_tap_flat "$1")" >&2
}

_tap_on_exit() {
  local rc=$?
  [ "${BASH_SUBSHELL:-0}" -eq 0 ] || return 0
  trap - EXIT ERR
  if [ -n "$_TAP_BAILFILE" ] && [ -s "$_TAP_BAILFILE" ]; then
    _tap_bail "$(cat "$_TAP_BAILFILE")"
    rc=1
  elif [ "$_TAP_DONE" -eq 0 ]; then
    _tap_bail "the script ended with status $rc before tap_done"
    [ "$rc" -ne 0 ] || rc=1
  fi
  [ -z "$_TAP_BAILFILE" ] || rm -f "$_TAP_BAILFILE"
  [ -z "$_TAP_AT_EXIT" ] || eval "$_TAP_AT_EXIT"
  exit "$rc"
}

# Usage: _tap_crash <message>: ends the run. It leaves the reason in a file and stops the main shell, which is
# the only way that works from a substitution, a pipeline element or a process substitution (they cannot exit
# the script): the EXIT trap of the main shell writes the Bail out! once.
_tap_crash() {
  [ -z "$_TAP_BAILFILE" ] || printf '%s' "$1" >"$_TAP_BAILFILE"
  kill -TERM "$$" 2>/dev/null
  exit 1
}

# The ERR trap: $1 status, $2 line, $3 script, $4 the command that failed, $5 the status of each element of its pipeline.
_tap_on_err() {
  local rc=$1 line=$2 file=$3 cmd=$4 ps=$5 s n=0 i=0 last word where
  # The helper's own commands are not the test's business.
  # Only the functions that this file defines: a test helper that happens to be named tap_* is the test's own.
  [ "${BASH_SOURCE[1]:-}" != "$_TAP_SELF" ] || return 0
  where="at line $line of $file: $(_tap_flat "$cmd")"
  case $- in *e*) _tap_crash "unexpected error (status $rc) $where" ;; esac
  # shellcheck disable=SC2086  # the statuses are words
  set -- $ps
  n=$#
  last=$rc
  if [ "$n" -gt 1 ]; then
    for s in "$@"; do
      i=$((i + 1))
      if [ "$i" -lt "$n" ]; then
        case $s in 0|141) ;; *) _tap_crash "unexpected error (status $s) in a pipeline $where" ;; esac
      else
        last=$s
      fi
    done
  fi
  [ "$last" -ne 0 ] || return 0
  word=${cmd%% *}
  case $word in
    test|'['|'[['|'(('|grep|egrep|fgrep|diff|cmp) [ "$last" -eq 1 ] && return 0 ;;
  esac
  _tap_crash "unexpected error (status $last) $where: it is not an assertion, so a crash cannot be told from a failed case (a program that is expected to fail goes through tap_run)"
}

trap '_tap_on_exit' EXIT
trap 'exit 143' TERM  # a crash in a subshell stops the script with it; the EXIT trap then reports and exits with 1
trap '_tap_on_err "$?" "$LINENO" "$0" "$BASH_COMMAND" "${PIPESTATUS[*]}"' ERR
set -E -o pipefail
_TAP_BAILFILE=$(mktemp "${TMPDIR:-/tmp}/tap-bail-XXXXXX") || _TAP_BAILFILE=""
: >"${_TAP_BAILFILE:-/dev/null}"

# Usage: _tap_rel <script>: its path from the repo root (as written in the diff), or as given.
_tap_rel() {
  local d b top
  d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return; }
  b=$(basename "$1")
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || { printf '%s' "$1"; return; }
  top=$(cd "$top" && pwd -P)
  if [ "$d" = "$top" ]; then printf '%s' "$b"; else printf '%s/%s' "${d#"$top"/}" "$b"; fi
}

tap_begin() {
  _TAP_FILE=$(_tap_rel "${1:?tap_begin needs the path of the script}")
  [ "$_TAP_FMT" != tap ] || _tap_line "# file: $_TAP_FILE"
}

# Usage: _tap_xml <text>: leaves in $_X the text as XML character data or attribute value: &, <, >, " and a tab (as &#9;, because an
# attribute value read back would turn a raw tab into a space and the id would no longer match its source line) are escaped.
# No subshell and no process per value: _tap_clean takes the characters XML 1.0 forbids out of the whole suite at once.
# The replacements go through variables: bash 5.2 reads an & in a bare replacement as the matched text.
_tap_xml() {
  local t=$1 amp='&amp;' lt='&lt;' gt='&gt;' quot='&quot;' tab='&#9;'
  t=${t//&/"$amp"}; t=${t//</"$lt"}; t=${t//>/"$gt"}; t=${t//\"/"$quot"}; t=${t//$'\t'/"$tab"}
  _X=$t
}

# Usage: _tap_clean: filters stdin to stdout without the C0 control characters XML 1.0 forbids, the bytes that are not UTF-8 and
# U+FFFE and U+FFFF (valid UTF-8, not allowed in XML). Called once per testsuite.
_tap_clean() {
  LC_ALL=C tr -d '\000-\010\013\014\016-\037' | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; } | LC_ALL=C sed -e $'s/\357\277\276//g' -e $'s/\357\277\277//g'
}

# Usage: _tap_junit_suite [<error message>] [<skip reason>]: appends the closed testsuite of this script to the file: its cases
# (held until now), an error testcase if there is a message (a bail out), and the reason in its system-out for tap_skip_all.
# It forgets the cases it wrote (like _tap_flush): a bail that arrives after tap_done (a >(…) that crashes while the suite
# is written) leaves a second testsuite with only its error testcase, never the cases again (#264).
_tap_junit_suite() {
  local err=${1:-} why=${2:-} i n=${#_TAP_IDS[@]} fails=0 skips=0 errs=0 f d id out=""
  _tap_xml "${_TAP_FILE:-$(_tap_rel "$0")}"; f=$_X
  [ -z "$err" ] || errs=1
  for ((i = 0; i < n; i++)); do
    if [ -n "${_TAP_SKIPS[$i]:-}" ]; then skips=$((skips + 1)); elif [ "${_TAP_VERDICTS[$i]}" = "not ok" ]; then fails=$((fails + 1)); fi
  done
  out="<testsuite name=\"$f\" file=\"$f\" tests=\"$((n + errs))\" failures=\"$fails\" errors=\"$errs\" skipped=\"$skips\">"$'\n'
  for ((i = 0; i < n; i++)); do
    _tap_xml "${_TAP_IDS[$i]}"; id=$_X; _tap_xml "${_TAP_DESCS[$i]}"; d=$_X
    out+="<testcase name=\"$id\" classname=\"$f\" file=\"$f\">"
    if [ -n "${_TAP_SKIPS[$i]:-}" ]; then
      _tap_xml "${_TAP_SKIPS[$i]}"; out+="<skipped message=\"$_X\"/>"
    elif [ "${_TAP_VERDICTS[$i]}" = "not ok" ]; then
      _tap_xml "${_TAP_DESCS[$i]%%$'\n'*}"; out+="<failure message=\"$_X\"/>"
    fi
    [ -z "$d" ] || out+="<system-out>$d</system-out>"
    out+="</testcase>"$'\n'
  done
  if [ "$errs" -eq 1 ]; then
    _tap_xml "$err"
    out+="<testcase name=\"$_TAP_ERR_NAME\" classname=\"$f\" file=\"$f\"><error message=\"$_X\"/></testcase>"$'\n'
  fi
  if [ -n "$why" ]; then _tap_xml "$why"; out+="<system-out>$_X</system-out>"$'\n'; fi
  out+="</testsuite>"
  out=$(printf '%s' "$out" | _tap_clean)
  _tap_line "$out"
  _TAP_IDS=(); _TAP_VERDICTS=(); _TAP_DESCS=(); _TAP_REPS=(); _TAP_SKIPS=()
}

tap_at_exit() { _TAP_AT_EXIT=$1; }

# Usage: _tap_flush: writes the held cases (numbered after the ones already written to stdout) and forgets them.
_tap_flush() {
  local i n=0 esc d
  for ((i = 0; i < ${#_TAP_IDS[@]}; i++)); do
    n=$((_TAP_BASE + i + 1))
    esc=${_TAP_IDS[$i]//\\/\\\\}
    esc=${esc//#/\\#}
    _tap_line "${_TAP_VERDICTS[$i]} $n - $esc${_TAP_SKIPS[$i]:+ # SKIP ${_TAP_SKIPS[$i]}}"
    d=${_TAP_DESCS[$i]}
    while [ -n "$d" ]; do
      _tap_line "# desc: ${d%%$'\n'*}"
      case $d in *$'\n'*) d=${d#*$'\n'} ;; *) d="" ;; esac
    done
  done
  _TAP_BASE=$((_TAP_BASE + ${#_TAP_IDS[@]}))
  _TAP_IDS=(); _TAP_VERDICTS=(); _TAP_DESCS=(); _TAP_REPS=(); _TAP_SKIPS=()
}

# Usage: _tap_case <ok|not ok> <id> [description]
_tap_case() {
  local verdict=$1 id=$2 desc=${3:-} i found=-1
  case $id in
    '') _tap_crash "a case needs an id" ;;
    *$'\n'*|*$'\r'*) _tap_crash "the id of a case cannot have a newline: $(_tap_flat "$id")" ;;
  esac
  desc=$(_tap_flat "$desc")
  for ((i = 0; i < ${#_TAP_IDS[@]}; i++)); do
    [ "${_TAP_IDS[$i]}" = "$id" ] && { found=$i; break; }
  done
  if [ "$found" -ge 0 ] && [ -n "${_TAP_SKIPS[$found]:-}" ]; then
    _tap_crash "a verdict on an id that was skipped with tap_skip: $(_tap_flat "$id")"
  fi
  if [ "$found" -lt 0 ]; then
    found=${#_TAP_IDS[@]}
    _TAP_IDS[found]=$id; _TAP_VERDICTS[found]="ok"; _TAP_DESCS[found]=""; _TAP_REPS[found]=1
  else
    _TAP_REPS[found]=$((_TAP_REPS[found] + 1))
    # A passing case that stands for several inputs does not show the first one only.
    [ "${_TAP_VERDICTS[$found]}" != "ok" ] || _TAP_DESCS[found]=""
  fi
  if [ "$verdict" = "not ok" ]; then
    if [ "${_TAP_VERDICTS[$found]}" = "ok" ]; then
      _TAP_VERDICTS[found]="not ok"; _TAP_DESCS[found]=""
      _TAP_FAILED=$((_TAP_FAILED + 1))
    fi
    [ -z "$desc" ] || _TAP_DESCS[found]="${_TAP_DESCS[$found]:+${_TAP_DESCS[$found]}$'\n'}$desc"
    { echo "FAIL - $id"; [ -z "$desc" ] || echo "       $desc"; } >&2
  elif [ "${_TAP_VERDICTS[$found]}" = "ok" ] && [ "${_TAP_REPS[$found]}" -eq 1 ]; then
    _TAP_DESCS[found]=$desc
  fi
}

# Usage: tap_skip <id> <reason>: a case that does not apply here ("ok N - id # SKIP reason"), visible in the stream.
tap_skip() {
  local j
  for ((j = 0; j < ${#_TAP_IDS[@]}; j++)); do
    [ "${_TAP_IDS[$j]}" != "${1:-}" ] || _tap_crash "tap_skip on an id that already has a verdict: $(_tap_flat "$1")"
  done
  _tap_case "ok" "${1:?tap_skip needs an id}" "SKIP: $(_tap_flat "${2:-}")"
  local i
  for ((i = 0; i < ${#_TAP_IDS[@]}; i++)); do
    [ "${_TAP_IDS[$i]}" != "$1" ] || _TAP_SKIPS[i]=$(_tap_flat "${2:-}")
  done
}
tap_ok() { _tap_case "ok" "$@"; }
tap_fail() { _tap_case "not ok" "$@"; }
tap_check() {
  local status=${1:?tap_check needs the status}; shift
  # A failed assertion ends with 1: any other status is a crash or a usage error (it could come from the left of
  # a "&&", where bash does not call the ERR trap), and it is never a failed case.
  case $status in
    0) _tap_case "ok" "$@" ;;
    1) _tap_case "not ok" "$@" ;;
    *) _tap_crash "tap_check got status $status at $(_tap_flat "${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?}"): only 0 and 1 are the result of an assertion, anything else is a crash or a usage error" ;;
  esac
}

# Usage: _tap_crash_status <status>: whether the status is what a crash gives and not a result a test compares
# (1 and 2, 126 and 127, and 128 or more, a signal, 141 included: here the reader is the substitution, which reads
# everything, so a SIGPIPE can only be the program dying on its own).
_tap_crash_status() {
  case $1 in
    1|2|126|127) return 0 ;;
  esac
  [ "$1" -ge 128 ] 2>/dev/null
}

# Usage: _tap_out_detail <output>: what to show of a program's output in a Bail out!: its FAIL lines (and their indented
# detail lines) if it has any, the first 20; else its last 10 lines. It cuts on line boundaries.
_tap_out_detail() {
  local line n=0 kept=0 fails="" lines=() start i
  while IFS= read -r line; do
    lines[n]=$line
    n=$((n + 1))
    case $line in
      FAIL*|"       "[!\ ]*) if [ "$kept" -lt 20 ]; then fails="$fails$line"$'\n'; kept=$((kept + 1)); fi ;;
    esac
  done <<<"$1"
  if [ "$kept" -gt 0 ]; then printf '%s' "$fails"; return 0; fi
  start=0
  if [ "$n" -gt 10 ]; then start=$((n - 10)); fi
  for ((i = start; i < n; i++)); do printf '%s\n' "${lines[$i]}"; done
}

# Usage: tap_run <var> <expected status> <command> [args]: runs a program that is expected to fail (or to succeed),
# with its output in $var (stdout and stderr) and its status in $TAP_RC. It does not trip the ERR trap, since
# the test says what status it expects: a status that is not that one and is 1, 2, 126, 127 or 128 or more is what a crash gives, so
# the run bails out; any other status is left to the test to compare ("[ "$TAP_RC" -eq 64 ]; tap_check $? ...").
tap_run() {
  local __var=${1:?tap_run needs a variable} __want=${2:?tap_run needs the expected status} __out
  shift 2
  # tap_run turns the ERR trap off: a function or a script with several commands would hide a crash before its last one.
  [ "$(type -t "${1:?tap_run needs a command}")" != function ] || _tap_crash "tap_run on a shell function ($1): a crash inside it would be hidden, run a single program"
  case ${1##*/} in
    sh|bash|dash|zsh)
      case " $2 " in *" -c "*|*" -"[a-z]*c" "*) case ${3:-} in *\;*|*"&"*|*"|"*|*$'\n'*) _tap_crash "tap_run on $1 -c with more than one command: a crash before the last one would be hidden, run a single program" ;; esac ;; esac ;;
  esac
  TAP_RC=0
  __out=$(trap - ERR; "$@" 2>&1) || TAP_RC=$?
  printf -v "$__var" '%s' "$__out"
  [ "$TAP_RC" -eq "$__want" ] && return 0
  if _tap_crash_status "$TAP_RC"; then
    _tap_crash "unexpected status $TAP_RC from $(_tap_flat "$*") (expected $__want): a crash cannot be told from a failed case. Its output: $(_tap_flat "$(_tap_out_detail "$__out")")"
  fi
  return 0
}

# Usage: tap_status <status> <expected>: for a program that ran with its ERR trap off ("c=0; out=$(trap - ERR; prog) || c=$?"):
# the status it ended with against the one the test expects. A status that is not that one and is 1, 2, 126,
# 127 or 128 or more is what a crash gives, so the run bails out; any other status is left to the test to compare.
tap_status() {
  local got=${1:?tap_status needs the status} want=${2:?tap_status needs the expected status}
  [ "$got" = "$want" ] && return 0
  if _tap_crash_status "$got"; then
    _tap_crash "unexpected status $got (expected $want) at $(_tap_flat "${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?}"): a crash cannot be told from a failed case"
  fi
  return 0
}

# Usage: tap_no_traceback <output>: a Python traceback in the output of a tool is a crash, whatever its status was.
tap_no_traceback() {
  case ${1:-} in *"Traceback (most recent call last)"*) _tap_crash "a Python traceback in the output of a program (a crash is not an assertion)" ;; esac
  return 0
}

# Usage: _tap_plan [skip reason]: writes the plan at the end of the TAP stream on stdout, with every case of the script.
_tap_plan() {
  local plan="1..$_TAP_BASE"
  [ "$_TAP_BASE" -ne 0 ] || [ -z "${1:-}" ] || plan="$plan # SKIP $(_tap_flat "$1")"
  _tap_line "$plan"
}

tap_done() {
  _TAP_DONE=1
  if [ "$_TAP_FMT" = junit ]; then
    _tap_junit_suite
  else
    _tap_flush
    _tap_plan
  fi
  if [ "$_TAP_FAILED" -ne 0 ]; then
    echo "$_TAP_FAILED test(s) failed." >&2
    exit 1
  fi
  exit 0
}

tap_skip_all() {
  _TAP_DONE=1
  if [ "$_TAP_FMT" = junit ]; then
    _tap_junit_suite "" "$(_tap_flat "${1:-}")"
  else
    _tap_flush
    _tap_line "# skip: $(_tap_flat "${1:-}")"
    _tap_plan "${1:-}"
  fi
  exit 0
}
