# shellcheck shell=bash
# TAP 14 helper for the kit's tests (ADR-002 D6, issue #151). It is sourced, not run:
#
#   . "$ROOT/scripts/agents/tap.sh"
#   tap_begin "$0"                       # writes "# file: <path of the script from the repo root>"
#   tap_at_exit 'rm -rf "$TMP"'          # instead of trap ... EXIT, which would replace the helper's
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
# Unexpected errors: with set -e a failing command emits "Bail out!" (ERR trap) and exits 1; leaving
# the script in any other way before tap_done (set -u, an exit, a crash) also emits it from the EXIT
# trap. Without set -e a failing command is the test's business (it checks its status with $?), except
# status 126 and 127, a command that cannot run: that bails out too. A command that crashes with status 1
# (a traceback in a setup step) cannot be told from a status the test checks on purpose, so it shows
# up as the failure of the next case, not as a Bail out!. That is narrower than ADR-002 D6 says.
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
  trap - EXIT ERR
  if [ "$_TAP_DONE" -eq 0 ]; then
    _tap_bail "the script ended with status $rc before tap_done"
    [ "$rc" -ne 0 ] || rc=1
  fi
  [ -z "$_TAP_AT_EXIT" ] || eval "$_TAP_AT_EXIT"
  exit "$rc"
}

_tap_on_err() {
  local rc=$1
  # Under set -e any failure is unexpected. Without it a failing command is usually a status the test
  # checks, except a command that does not exist or cannot run (126, 127): nobody checks for that.
  case $- in *e*) ;; *) case $rc in 126|127) ;; *) return 0 ;; esac ;; esac
  _tap_bail "unexpected error (status $rc) at line $2 of $3"
  exit 1
}

trap '_tap_on_exit' EXIT
trap '_tap_on_err $? $LINENO "$0"' ERR

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
