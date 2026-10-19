# shellcheck shell=bash
# TAP 14 helper for the kit's tests (ADR-002 D6, issue #151). It is sourced, not run:
#
#   . "$ROOT/scripts/agents/tap.sh"
#   tap_begin "$0"                       # writes "# file: <path of the script from the repo root>"
#   tap_at_exit 'rm -rf "$TMP"'          # instead of trap ... EXIT, which would replace the helper's
#   tap_run   out 64 prog args...        # runs a program that may fail: output in $out, status in $TAP_RC
#   c=0; out=$(trap - ERR; prog) || c=$?; tap_status "$c" 64    # the same, for a command line; tap_no_traceback "$out"
#   tap_ok    "literal id" ["description"]
#   tap_fail  "literal id" ["description"]
#   tap_check $? "literal id" ["description"]   # 0 is ok, 1 is not ok, any other status is a bail out
#   tap_skip  "literal id" "reason"       # a case that does not apply here: ok N - id # SKIP reason
#   tap_done                             # writes the plan 1..N and exits (1 if a case failed)
#   tap_skip_all "reason"                # for a script that does not apply: 1..0 # SKIP, exits 0
#
# The id is a literal, written in the source: red.sh compares only that name with the lines the red
# commit adds (ADR-002 D4). What varies at run time goes in the description, which is not compared
# and is written as a "# desc:" line. An id cannot be empty and cannot have a newline (the helper bails
# out). An id that repeats is the same case, not a new one (red.sh rejects an ambiguous name): a loop
# that checks the same thing for several inputs passes one literal id and the input as the description,
# and the case fails if any of them fails; each failing description is written under it.
#
# The cases are held until tap_done (or a bail out) and written then, in the order of their first call.
#
# Where the TAP goes. Under red.sh, TAP_OUT is the file it created ({out}): the helper opens it once,
# on fd 8 (a path that cannot be opened is a bail out with exit 2), and unsets the variable, so the test does not see the path and what it prints on stdout
# cannot inject cases. Without TAP_OUT (a person running the test, the docs CI) the TAP goes to
# stdout. Several scripts can write the same file: the numbering continues and the plan is rewritten
# at the end so the stream keeps a single 1..N. Each failing case is also printed on
# stderr as "FAIL - <id>", so a CI log shows it.
#
# Unexpected errors (ADR-002 D6: a crash is never a failed assertion). The helper turns on errtrace
# (set -E) and pipefail, so the ERR trap runs in functions, command and process substitutions, subshells
# and every element of a pipeline. Any command that fails is an unexpected error and the run ends with
# "Bail out!" (exit 1), except an assertion that fails with status 1: test, [, [[, ((, grep, egrep, fgrep,
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
#   - "trap - ERR", and "|| true" after a command or a substitution: bash 5 does not watch what runs under the
#     "||" (bash 3.2 still calls the trap inside a substitution), so the crash is hidden: use tap_run;
#   - a failure in the middle of "a && b" or "a || b", and in a condition (if, while, "!"): bash does not call the trap.
#     tap_check still bails out on any status other than 0 and 1, so a crash with status 2 there is seen; a crash with status 1
#     (a traceback) is not;
#   - "local x=$(prog)" hides the status of prog (a crash inside prog still bails out on bash 5);
#   - on bash 3.2 (macOS), a subshell "( cmd )" and a substitution "$( cmd )" with a single external command and no
#     redirection: bash 3.2 runs it with exec, the ERR trap never runs, and a crash there (for example
#     "[ \"$(python3 missing.py)\" = 3 ]" or "[ -z \"$(prog)\" ]") is a failed assertion or even a pass. Bash 5 forks and
#     sees it. A redirection ("$(prog 2>/dev/null)") or a second command forces the fork on 3.2 too.
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
_TAP_BAILFILE=""    # where a subshell leaves the reason of a bail out for the main shell (it cannot exit the script)
TAP_RC=0

if [ -n "${TAP_OUT:-}" ]; then
  _TAP_PATH=$TAP_OUT
  { exec 8>>"$_TAP_PATH"; } 2>/dev/null || { echo "Bail out! cannot open TAP_OUT ($_TAP_PATH)" >&2; exit 2; }
  _TAP_BASE=$(grep -c -E '^(not )?ok ' "$_TAP_PATH" 2>/dev/null || true)
  _TAP_BASE=${_TAP_BASE:-0}
else
  exec 8>&1
fi
unset TAP_OUT

_tap_line() { printf '%s\n' "$1" >&8; }

# Usage: _tap_flat <text>: the text in one line.
_tap_flat() { local t=$1; t=${t//$'\r'/ }; printf '%s' "${t//$'\n'/ }"; }

# Removes the plans that earlier scripts left in a shared file: a bailed stream has none.
_tap_strip_plans() {
  [ -n "$_TAP_PATH" ] || return 0
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/tap-XXXXXX") || return 0
  grep -v -E '^1\.\.' "$_TAP_PATH" >"$tmp" 2>/dev/null
  cat "$tmp" >"$_TAP_PATH"
  rm -f "$tmp"
}

_tap_bail() {
  [ "$_TAP_BAILED" -eq 0 ] || return 0
  _TAP_BAILED=1
  _tap_flush
  _tap_strip_plans
  _tap_line "Bail out! $(_tap_flat "$1")"
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

tap_begin() { _tap_line "# file: $(_tap_rel "${1:?tap_begin needs the path of the script}")"; }

tap_at_exit() { _TAP_AT_EXIT=$1; }

# Usage: _tap_flush: writes the held cases (numbered after the ones already in the file) and forgets them.
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
    '') _tap_bail "a case needs an id"; exit 1 ;;
    *$'\n'*|*$'\r'*) _tap_bail "the id of a case cannot have a newline: $(_tap_flat "$id")"; exit 1 ;;
  esac
  desc=$(_tap_flat "$desc")
  for ((i = 0; i < ${#_TAP_IDS[@]}; i++)); do
    [ "${_TAP_IDS[$i]}" = "$id" ] && { found=$i; break; }
  done
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
# (1 and 2, 126 and 127, and 128 or more, a signal; 141, SIGPIPE, is the reader of a pipe leaving early).
_tap_crash_status() {
  case $1 in
    1|2|126|127) return 0 ;;
    141) return 1 ;;
  esac
  [ "$1" -ge 128 ] 2>/dev/null
}

# Usage: tap_run <var> <expected status> <command> [args]: runs a program that is expected to fail (or to succeed),
# with its output in $var (stdout and stderr) and its status in $TAP_RC. It does not trip the ERR trap, since
# the test says what status it expects: a status that is not that one and is 1, 2, 126, 127 or 128 or more is what a crash gives (141, SIGPIPE, aside), so
# the run bails out; any other status is left to the test to compare ("[ "$TAP_RC" -eq 64 ]; tap_check $? ...").
tap_run() {
  local __var=${1:?tap_run needs a variable} __want=${2:?tap_run needs the expected status} __out
  shift 2
  TAP_RC=0
  __out=$(trap - ERR; "$@" 2>&1) || TAP_RC=$?
  printf -v "$__var" '%s' "$__out"
  [ "$TAP_RC" -eq "$__want" ] && return 0
  if _tap_crash_status "$TAP_RC"; then
    _tap_crash "unexpected status $TAP_RC from $(_tap_flat "$*") (expected $__want): a crash cannot be told from a failed case"
  fi
  return 0
}

# Usage: tap_status <status> <expected>: for a program that ran with its ERR trap off ("c=0; out=$(trap - ERR; prog) || c=$?"):
# the status it ended with against the one the test expects. A status that is not that one and is 1, 2, 126,
# 127 or 128 or more is what a crash gives (141, SIGPIPE, aside), so the run bails out; any other status is left to the test to compare.
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

# Usage: _tap_plan [skip reason]: leaves one plan, at the end of the stream, with every case of the file.
_tap_plan() {
  local plan
  if [ -n "$_TAP_PATH" ]; then
    local total tmp
    total=$(grep -c -E '^(not )?ok ' "$_TAP_PATH" 2>/dev/null || true)
    total=${total:-0}
    plan="1..$total"
    [ "$total" -ne 0 ] || [ -z "${1:-}" ] || plan="$plan # SKIP $(_tap_flat "$1")"
    tmp=$(mktemp "${TMPDIR:-/tmp}/tap-XXXXXX")
    { grep -v -E '^1\.\.' "$_TAP_PATH"; printf '%s\n' "$plan"; } >"$tmp" 2>/dev/null
    cat "$tmp" >"$_TAP_PATH"
    rm -f "$tmp"
  else
    plan="1..$_TAP_BASE"
    [ "$_TAP_BASE" -ne 0 ] || [ -z "${1:-}" ] || plan="$plan # SKIP $(_tap_flat "$1")"
    _tap_line "$plan"
  fi
}

tap_done() {
  _TAP_DONE=1
  _tap_flush
  _tap_plan
  if [ "$_TAP_FAILED" -ne 0 ]; then
    echo "$_TAP_FAILED test(s) failed." >&2
    exit 1
  fi
  exit 0
}

tap_skip_all() {
  _TAP_DONE=1
  _tap_flush
  _tap_line "# skip: $(_tap_flat "${1:-}")"
  _tap_plan "${1:-}"
  exit 0
}
