# shellcheck shell=bash
# TAP 14 helper for the kit's tests (ADR-002 D6, issue #151). It is sourced, not run:
#
#   . "$ROOT/scripts/agents/tap.sh"
#   tap_begin "$0"                       # writes "# file: <path of the script from the repo root>"
#   tap_at_exit 'rm -rf "$TMP"'          # instead of trap ... EXIT, which would replace the helper's
#   tap_assertions has_line no_line      # functions whose failing status is a failed case, not a crash
#   tap_ok    "literal id" ["description"]
#   tap_fail  "literal id" ["description"]
#   tap_check $? "literal id" ["description"]   # 0 is ok, anything else is not ok
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
# Unexpected errors (ADR-002 D6: a crash is never a failed assertion). A command that fails is an unexpected
# error, and the run ends with "Bail out!" (exit 1), unless the test shows that it looks at the failure:
#   - the next command reads the status: it has $? in it ("rc=$?", "[ $? -eq 2 ]", "tap_check $? ..."); or
#   - the command is in a condition or after ||, && or ! (bash does not call the ERR trap there).
# A failure that the next command does not read ("s=$(python3 x.py)" followed by a comparison of $s, or
# a bare failing command before tap_ok or tap_done) bails out: it is a crash in a setup step, never an assertion.
# When the status is read straight by tap_check ("<command>; tap_check $? ..."), the command has to be an
# assertion, which is what can fail a case: test, [, [[, grep, egrep, fgrep, diff and cmp (with status 1: a status
# of 2 or more is a usage error or a file that could not be read) and the functions the test declares with
# tap_assertions (a helper that wraps one of those). A program under test that fails there ("python3 x.py;
# tap_check $? ...") bails out: its status cannot be told from a crash. Capture its output with the failure
# declared ("out=$(prog) || true", "prog || rc=$?") and compare the output, or read the status into a
# variable and compare it with test. Under set -e any failure bails out, with no exceptions. Status 126 and 127
# (a command that cannot run) always bail out. Left out of reach: a failure inside "a && b; tap_check $?" when
# a is the one that fails, a crash in the middle of a pipeline, and a program whose exit status the test
# compares with a number on purpose ("prog; [ $? -eq 2 ]": a crash with that number looks like the behaviour).
#
# A test runs in the same shell as this file, so it could still read _TAP_PATH or write to fd 8: it is
# not a sandbox, only a path that the test has no reason to touch.

_TAP_BASE=0
_TAP_FAILED=0
_TAP_IDS=()
_TAP_VERDICTS=()
_TAP_DESCS=()
_TAP_REPS=()
_TAP_DONE=0
_TAP_BAILED=0
_TAP_AT_EXIT=""
_TAP_PATH=""
_TAP_ASSERT=" "      # the functions declared with tap_assertions, between spaces
_TAP_PEND=""         # the command that failed and that no later command has read yet
_TAP_PEND_RC=0
_TAP_PEND_AT=""      # "line N of <script>" of that command
_TAP_READ=""         # the command whose failure the last command read (with $?)
_TAP_READ_RC=0
_TAP_READ_AT=""
_TAP_WRAP=""        # the declared function that just returned non-zero (the ERR trap reports what ran inside it)

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
  trap - EXIT ERR DEBUG
  if [ "$_TAP_DONE" -eq 0 ]; then
    _tap_bail "the script ended with status $rc before tap_done"
    [ "$rc" -ne 0 ] || rc=1
  fi
  [ -z "$_TAP_AT_EXIT" ] || eval "$_TAP_AT_EXIT"
  exit "$rc"
}

_tap_on_err() {
  local rc=$1 line=$2 file=$3 cmd=$4
  [ -z "$_TAP_WRAP" ] || { cmd=$_TAP_WRAP; _TAP_WRAP=""; }
  # Under set -e any failure is unexpected. A command that does not exist or cannot run (126, 127) is
  # never a status the test checks. Any other failure waits for the next command (_tap_on_debug).
  case $- in *e*) _tap_bail "unexpected error (status $rc) at line $line of $file"; exit 1 ;; esac
  case $rc in 126|127) _tap_bail "unexpected error (status $rc) at line $line of $file"; exit 1 ;; esac
  _TAP_PEND=$cmd; _TAP_PEND_RC=$rc; _TAP_PEND_AT="line $line of $file"
}

# Runs before every command of the test (not inside its functions). $1 is the command about to run.
_tap_on_debug() {
  local last=$1 cmd=$2 pend
  case $cmd in _tap_*) return 0 ;; esac
  if [ -n "$_TAP_PEND" ]; then
    pend=$_TAP_PEND; _TAP_PEND=""
    # bash 3.2 calls the ERR trap for "! a | b" too: the status that reaches the next command is 0 there.
    [ "$last" -ne 0 ] || return 0
    case $cmd in
      *\$\?*|*\$\{\?*) _TAP_READ=$pend; _TAP_READ_RC=$_TAP_PEND_RC; _TAP_READ_AT=$_TAP_PEND_AT ;;
      *)
        _tap_bail "unexpected error (status $_TAP_PEND_RC) at $_TAP_PEND_AT: $(_tap_flat "$pend") failed and nothing read its status (a crash is not an assertion)"
        exit 1 ;;
    esac
  else
    case $cmd in tap_*) ;; *) _TAP_READ="" ;; esac
  fi
}

# Usage: _tap_assertion <command> <status>: is that failing command an assertion, whose failure is a failed case?
_tap_assertion() {
  local word=${1%% *}
  case $word in
    test|'['|'[['|grep|egrep|fgrep|diff|cmp) [ "$2" -eq 1 ] ;;
    *) case $_TAP_ASSERT in *" $word "*) return 0 ;; esac; return 1 ;;
  esac
}

trap '_tap_on_exit' EXIT
trap '_tap_on_err $? "$LINENO" "$0" "$BASH_COMMAND"' ERR
trap '_tap_on_debug "$?" "$BASH_COMMAND"' DEBUG

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

# Usage: tap_assertions <function>...: functions whose failing status is a failed case (see "Unexpected errors").
# Each one is wrapped, so that its failure is reported under its own name and not under the command inside it.
tap_assertions() {
  local f
  for f in "$@"; do
    _TAP_ASSERT="$_TAP_ASSERT$f "
    eval "_tap_orig_$(declare -f "$f")"
    eval "$f() { _tap_orig_$f \"\$@\"; local rc=\$?; [ \$rc -eq 0 ] || _TAP_WRAP=$f; return \$rc; }"
  done
}

# Usage: _tap_flush: writes the held cases (numbered after the ones already in the file) and forgets them.
_tap_flush() {
  local i n=0 esc d
  for ((i = 0; i < ${#_TAP_IDS[@]}; i++)); do
    n=$((_TAP_BASE + i + 1))
    esc=${_TAP_IDS[$i]//\\/\\\\}
    esc=${esc//#/\\#}
    _tap_line "${_TAP_VERDICTS[$i]} $n - $esc"
    d=${_TAP_DESCS[$i]}
    while [ -n "$d" ]; do
      _tap_line "# desc: ${d%%$'\n'*}"
      case $d in *$'\n'*) d=${d#*$'\n'} ;; *) d="" ;; esac
    done
  done
  _TAP_BASE=$((_TAP_BASE + ${#_TAP_IDS[@]}))
  _TAP_IDS=(); _TAP_VERDICTS=(); _TAP_DESCS=(); _TAP_REPS=()
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

tap_ok() { _tap_case "ok" "$@"; }
tap_fail() { _tap_case "not ok" "$@"; }
tap_check() {
  local status=$1; shift
  if [ "$status" -ne 0 ] && [ -n "$_TAP_READ" ] && ! _tap_assertion "$_TAP_READ" "$_TAP_READ_RC"; then
    _tap_bail "unexpected error (status $_TAP_READ_RC) at $_TAP_READ_AT: $(_tap_flat "$_TAP_READ") is not an assertion: its status cannot be told from a crash (compare its output, or read the status and compare it with test)"
    exit 1
  fi
  _TAP_READ=""
  if [ "$status" -eq 0 ]; then _tap_case "ok" "$@"; else _tap_case "not ok" "$@"; fi
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
