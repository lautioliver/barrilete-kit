#!/usr/bin/env bash
# shellcheck disable=SC2016  # the bodies of bash -c are single-quoted on purpose: they expand inside the child shell
# Tests of red.sh (ADR-002): every case of corpus/ is run through red.sh, and so are the cases that
# the corpus cannot express (usage, the `red` section, the report path, timeouts, the trusted checkout).
#
# A corpus case is a directory:
#   meta        expect=<exit code of red.sh> format=junit|tap exit=<exit code of the runner> source=<how the fixture was made>
#               optional: says=<text red.sh must print>, timeout=<s>, sleep=<s the runner stays alive>, note=
#   base/       the files of the parent commit
#   red/        the files the red commit adds or changes
#   report.xml  | report.tap   what the runner wrote to {out} (absent: it wrote nothing)
#   output.txt  what the runner printed
# The runner is simulated: it prints output.txt, copies the report to {out} and exits with `exit`.
# The reports of pytest, vitest and jest are real output; the rest is written by hand (see `source`).
#
# Usage: bash .claude/skills/implement-issue/test-red.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/../../.." && pwd)
CORPUS="$HERE/corpus"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-red-XXXXXX")" && pwd)
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/tmp"
mkdir -p "$TMPDIR"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
failures=0
ok() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }
check() { # check <description> <command...>
  local d=$1; shift
  if "$@"; then ok "$d"; else fail "$d"; fi
}

# The runner of the corpus: prints the output, writes the report to {out} and exits.
cat >"$TMP/fake-run.sh" <<'EOF'
#!/usr/bin/env bash
case_dir=$1 out=$2 code=$3 pause=$4
cat "$case_dir/output.txt" 2>/dev/null
for r in "$case_dir"/report.xml "$case_dir"/report.tap; do [ -f "$r" ] && cp "$r" "$out"; done
[ "$pause" != 0 ] && sleep "$pause"
exit "$code"
EOF

# install_kit <repo>: red.sh and what it needs, in the layout of an installed project.
install_kit() {
  mkdir -p "$1/.claude/skills/implement-issue" "$1/scripts/agents" "$1/docs"
  cp "$HERE/red.sh" "$1/.claude/skills/implement-issue/red.sh"
  cp "$KIT/scripts/agents/red_report.py" "$1/scripts/agents/"
}

# write_map <repo> <json of the red section>
write_map() { printf '{"red": %s}\n' "$2" >"$1/docs/agents-map.json"; }

new_repo() { # new_repo <dir>
  rm -rf "$1"; mkdir -p "$1"; git -C "$1" init -q; git -C "$1" config commit.gpgsign false
}
# The JS fixtures of the corpus end in .fixture so that no project runner collects them: the test gives them back their name.
restore_fixtures() { find "$1" -name '*.fixture' -type f | while IFS= read -r f; do mv "$f" "${f%.fixture}"; done; }
commit_all() { git -C "$1" add -A && git -C "$1" commit -q --allow-empty -m "$2"; }

# run_red <repo> [args]: red.sh of that repo, output in $TMP/out, exit code in $code
run_red() {
  local repo=$1; shift
  (cd "$repo" && "$repo/.claude/skills/implement-issue/red.sh" "$@") >"${OUT:-$TMP/out}" 2>&1
  code=$?
}
show() { sed 's/^/       /' "${OUT:-$TMP/out}"; }
meta() { grep "^$2=" "$1/meta" | head -1 | cut -d= -f2-; }

# ---------------------------------------------------------------- the corpus
# One case: its lines (ok / FAIL) go to $TMP/res/<name>.txt, so that the cases can run in parallel.
run_case() {
  local c=$1 name expect fmt rc says tmo pause repo code
  name=$(basename "$c")
  expect=$(meta "$c" expect); fmt=$(meta "$c" format); rc=$(meta "$c" exit)
  says=$(meta "$c" says); tmo=$(meta "$c" timeout); pause=$(meta "$c" sleep)
  repo="$TMP/w/$name"
  new_repo "$repo"
  [ -d "$c/base" ] && cp -R "$c/base/." "$repo/"
  restore_fixtures "$repo"
  install_kit "$repo"
  printf '{"red": [{"name": "tests", "when": ["**"], "format": "%s", "run": "bash %s %s {out} %s %s"%s}]}\n' \
    "$fmt" "$TMP/fake-run.sh" "$c" "$rc" "${pause:-0}" "${tmo:+, \"timeout\": $tmo}" >"$repo/docs/agents-map.json"
  commit_all "$repo" base
  [ -d "$c/red" ] && cp -R "$c/red/." "$repo/"
  restore_fixtures "$repo"
  commit_all "$repo" red
  local OUT="$TMP/res/$name.out"
  run_red "$repo"
  if [ "$code" -ne "$expect" ]; then
    echo "FAIL - corpus $name: red.sh exited with $code, expected $expect"; show
  elif [ -n "$says" ] && ! grep -qF -- "$says" "$OUT"; then
    echo "FAIL - corpus $name: the output lacks the text of its says= line"; show
  else
    echo "ok   - corpus $name -> $expect"
  fi
}
mkdir -p "$TMP/res"
n=0
for c in "$CORPUS"/*/; do
  c=${c%/}; n=$((n + 1))
  run_case "$c" >"$TMP/res/$(basename "$c").txt" 2>&1 &
  [ $((n % 8)) -eq 0 ] && wait
done
wait
for c in "$CORPUS"/*/; do cat "$TMP/res/$(basename "${c%/}").txt"; done
failures=$((failures + $(cat "$TMP"/res/*.txt | grep -c '^FAIL - ')))
check "the corpus has cases ($n)" test "$n" -ge 100

# ---------------------------------------------------------------- the PR block
repo="$TMP/w/pytest-assert"
run_red "$repo"
block=$(sed -n 's/^Block for .*: //p' "$TMP/out")
sha=$(git -C "$repo" rev-parse HEAD)
check "red: a valid red prints the block path" test -f "$block"
b=$(cat "$block" 2>/dev/null)
check "block: uses the English literal Red before implementing" grep -q '<summary>Red before implementing</summary>' <<<"$b"
check "block: red commit is the sha of HEAD" grep -qx "red commit: $sha" <<<"$b"
check "block: stack and format lines" bash -c 'grep -qx "stack: tests" <<<"$1" && grep -qx "format: junit" <<<"$1"' _ "$b"
check "block: failing cases as file::name" grep -qx -- '- test_new.py::test_total' <<<"$b"
check "block: it lists only the failed case" test "$(grep -c '^- ' <<<"$b")" -eq 1
check "block: closes the details" grep -q '^</details>' <<<"$b"

# ---------------------------------------------------------------- usage and the red section
repo="$TMP/w/pytest-assert"
run_red "$repo" -- bash -c 'exit 1'
check "usage: red.sh -- <command> is gone (exit 64)" test "$code" -eq 64
check "usage: it says where the command is declared" grep -q 'agents-map.json' "$TMP/out"
run_red "$repo" a b
check "usage: two stacks (exit 64)" test "$code" -eq 64
run_red "$repo" nosuch
check "an unknown stack exits with 2 and lists the stacks" bash -c 'test "$1" -eq 2 && grep -q "tests" "$2"' _ "$code" "$TMP/out"

r="$TMP/w/nosection"; new_repo "$r"; install_kit "$r"; printf '{"docs": []}\n' >"$r/docs/agents-map.json"
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
check "D1: no red section -> exit 2 with a guide" bash -c 'test "$1" -eq 2 && grep -q "no .red. section" "$2" && grep -q "gotestsum" "$2" && grep -q "no text fallback" "$2"' _ "$code" "$TMP/out"

bad_map() { # bad_map <description> <json of the red section> <text expected>
  local r="$TMP/w/badmap"; new_repo "$r"; install_kit "$r"; write_map "$r" "$2"
  echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
  run_red "$r"
  if [ "$code" -eq 2 ] && grep -qF -- "$3" "$TMP/out"; then ok "$1"; else fail "$1 (exit $code)"; show; fi
}
bad_map "map: run without {out} is rejected" '[{"name":"t","when":["**"],"run":"true","format":"tap"}]' '{out}'
bad_map "map: unknown format is rejected" '[{"name":"t","when":["**"],"run":"true {out}","format":"text"}]' '"junit" or "tap"'
bad_map "map: no when is rejected" '[{"name":"t","run":"true {out}","format":"tap"}]' '`when`'
bad_map "map: timeout must be a positive number" '[{"name":"t","when":["**"],"run":"true {out}","format":"tap","timeout":"soon"}]' '`timeout`'
bad_map "map: zero timeout is rejected" '[{"name":"t","when":["**"],"run":"true {out}","format":"tap","timeout":0}]' '`timeout`'
bad_map "map: duplicate names are rejected" '[{"name":"t","when":["**"],"run":"true {out}","format":"tap"},{"name":"t","when":["**"],"run":"true {out}","format":"tap"}]' 'unique `name`'
bad_map "map: a stack name with a space is rejected (it ends up in the path of {out})" '[{"name":"my tests","when":["**"],"run":"true {out}","format":"tap"}]' 'letters, digits'
bad_map "map: a stack name with a shell metacharacter is rejected" '[{"name":"a;b","when":["**"],"run":"true {out}","format":"tap"}]' 'letters, digits'
bad_map "map: a stack that matches no changed file" '[{"name":"t","when":["src/**"],"run":"true {out}","format":"tap"}]' 'no `red` entry matches'

# ---------------------------------------------------------------- the commit
r="$TMP/w/dirty"; cp -R "$TMP/w/pytest-assert" "$r"; echo "# x" >>"$r/test_old.py"
run_red "$r"
check "a tracked file changed after the red commit -> exit 2" bash -c 'test "$1" -eq 2 && grep -q "uncommitted" "$2"' _ "$code" "$TMP/out"

r="$TMP/w/rootcommit"; new_repo "$r"; install_kit "$r"; write_map "$r" '[{"name":"t","when":["**"],"run":"true {out}","format":"tap"}]'
commit_all "$r" only
run_red "$r"
check "a red commit without parent -> exit 2" bash -c 'test "$1" -eq 2 && grep -q "no parent" "$2"' _ "$code" "$TMP/out"

# ---------------------------------------------------------------- several stacks, the choice of stack
r="$TMP/w/two-stacks"; new_repo "$r"; install_kit "$r"
mkdir -p "$TMP/py" "$TMP/tp"; cp "$CORPUS/pytest-assert/"{report.xml,output.txt} "$TMP/py/"; cp "$CORPUS/tap-new-script/"{report.tap,output.txt} "$TMP/tp/"
python3 - "$r/docs/agents-map.json" "$TMP/fake-run.sh" "$TMP/py" "$TMP/tp" <<'EOF'
import json, sys
out, fake, py, tp = sys.argv[1:5]
json.dump({"red": [
    {"name": "py", "when": ["**/*.py"], "format": "junit", "run": f"bash {fake} {py} {{out}} 1 0"},
    {"name": "sh", "when": ["**/*.sh"], "format": "tap", "run": f"bash {fake} {tp} {{out}} 1 0"}]}, open(out, "w"))
EOF
mkdir -p "$r/scripts"
printf 'x\n' >"$r/test_old.py"; printf 'x\n' >"$r/scripts/test-calc.sh"; commit_all "$r" base
cp -R "$CORPUS/pytest-assert/red/." "$r/"; mkdir -p "$r/scripts"; cp -R "$CORPUS/tap-new-script/red/." "$r/"
commit_all "$r" red
run_red "$r"
b=$(cat "$(sed -n 's/^Block for .*: //p' "$TMP/out")" 2>/dev/null)
check "two stacks that match, both red -> exit 0" test "$code" -eq 0
check "two stacks: one group per stack in the block" bash -c 'test "$(grep -c "^stack: " <<<"$1")" -eq 2 && grep -q "^stack: py" <<<"$1" && grep -q "^stack: sh" <<<"$1"' _ "$b"
check "two stacks: red commit appears once" test "$(grep -c '^red commit: ' <<<"$b")" -eq 1
run_red "$r" py
b=$(cat "$(sed -n 's/^Block for .*: //p' "$TMP/out")" 2>/dev/null)
check "red.sh <stack> runs only that stack" bash -c 'test "$1" -eq 0 && test "$(grep -c "^stack: " <<<"$2")" -eq 1 && ! grep -q "stack \"sh\"" "$3"' _ "$code" "$b" "$TMP/out"
python3 - "$r/docs/agents-map.json" <<'EOF'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m["red"][1]["run"] = m["red"][1]["run"].replace(" 1 0", " 0 0"); json.dump(m, open(p, "w"))
EOF
git -C "$r" commit -q -a --amend --no-edit; run_red "$r"
check "two stacks: one is rejected, the whole red is rejected (exit 2)" bash -c 'test "$1" -eq 2' _ "$code"
git -C "$r" commit -q --allow-empty -m "empty"; run_red "$r"
check "a red commit that changes no file matches no stack (exit 2)" bash -c 'test "$1" -eq 2 && grep -q "no .red. entry matches" "$2"' _ "$code" "$TMP/out"

# ---------------------------------------------------------------- the report path, the timeout, the process group, the size
case_repo() { # case_repo <dir> <run>: a repo whose red commit adds test_new.py; the stack runs <run>
  local r=$1; new_repo "$r"; install_kit "$r"
  python3 - "$r/docs/agents-map.json" "$2" "${3:-600}" <<'EOF'
import json, sys
out, run, tmo = sys.argv[1:4]
json.dump({"red": [{"name": "t", "when": ["**/*.py"], "format": "junit", "run": run, "timeout": int(tmo)}]}, open(out, "w"))
EOF
  printf 'def test_old():\n    assert True\n' >"$r/test_old.py"; commit_all "$r" base
  printf 'def test_new():\n    assert False\n' >"$r/test_new.py"; commit_all "$r" red
}
GOOD_XML='<testsuites><testsuite name="p" tests="1" failures="1"><testcase classname="test_new" name="test_new" file="test_new.py"><failure message="x"/></testcase></testsuite></testsuites>'

# D2/D3: the path of the report is new in every run, and nothing exists there before the run
r="$TMP/w/path"; log="$TMP/path.log"; : >"$log"
case_repo "$r" "[ -e {out} ] && echo EXISTED >>$log; echo {out} >>$log; echo '$GOOD_XML' > {out}; exit 1"
run_red "$r"; first=$code
run_red "$r"
check "report path: a valid red twice" test "$first" -eq 0 -a "$code" -eq 0
check "report path: nothing existed at {out} before the run" bash -c '! grep -q EXISTED "$1"' _ "$log"
check "report path: it is different in each run" test "$(grep -c '^/' "$log")" -eq 2 -a "$(grep '^/' "$log" | sort -u | wc -l | tr -d ' ')" -eq 2
check "report path: it is under TMPDIR, not in the repo" bash -c 'grep "^/" "$1" | grep -q "^$2/"' _ "$log" "$TMPDIR"

# an old report left by a previous run cannot be reused
r="$TMP/w/stale"; case_repo "$r" "exit 1 # {out}"
run_red "$r"
check "a run that writes no report is rejected even if an old one exists elsewhere" bash -c 'test "$1" -eq 2 && grep -q "not created in this run" "$2"' _ "$code" "$TMP/out"

# D5: timeout applied with python, and the whole process group dies
r="$TMP/w/timeout"; case_repo "$r" "echo '$GOOD_XML' > {out}; sleep 30 & wait" 1
start=$(date +%s); run_red "$r"; end=$(date +%s)
check "timeout: the run is killed (exit 2) well before it ends by itself" bash -c 'test "$1" -eq 2 && grep -q "passed its timeout" "$2" && test "$3" -lt 15' _ "$code" "$TMP/out" "$((end - start))"

r="$TMP/w/group"; flag="$TMP/late"; rm -f "$flag"
case_repo "$r" "(sleep 2; echo late > $flag) & exit 1"
run_red "$r"; sleep 3
check "process group: a background child cannot write after red.sh returns" bash -c 'test "$1" -eq 2 && ! test -e "$2"' _ "$code" "$flag"

r="$TMP/w/timeout-conf"; case_repo "$r" "echo '$GOOD_XML' > {out}; exit 1" 7
check "timeout: it is read from the entry" grep -q '"timeout": 7' "$r/docs/agents-map.json"
run_red "$r"
check "timeout: a run that ends in time is judged normally" test "$code" -eq 0
check "timeout: the output says the timeout of the stack" grep -q 'timeout 7 s' "$TMP/out"

r="$TMP/w/default-timeout"; case_repo "$r" "echo '$GOOD_XML' > {out}; exit 1"
python3 - "$r/docs/agents-map.json" <<'EOF'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); del m["red"][0]["timeout"]; json.dump(m, open(p, "w"))
EOF
git -C "$r" commit -q -a --amend --no-edit; run_red "$r"
check "timeout: without the field it is 600 s" grep -q 'timeout 600 s' "$TMP/out"

# D3: a report larger than 20 MB is not read
r="$TMP/w/big"; case_repo "$r" "head -c 21000000 /dev/zero > {out}; exit 1"
run_red "$r"
check "a report larger than 20 MB is rejected without reading it" bash -c 'test "$1" -eq 2 && grep -q "larger than 20 MB" "$2"' _ "$code" "$TMP/out"
r="$TMP/w/symlink"; case_repo "$r" "echo '$GOOD_XML' > $TMP/target.xml; ln -s $TMP/target.xml {out}; exit 1"
run_red "$r"
check "a report that is a symbolic link is rejected" bash -c 'test "$1" -eq 2 && grep -q "not a regular file" "$2"' _ "$code" "$TMP/out"

# D2: stdout of the run is not the evidence: lines that look like TAP on stdout inject no case
r="$TMP/w/stdout"; new_repo "$r"; install_kit "$r"
python3 - "$r/docs/agents-map.json" <<'EOF'
import json, sys
json.dump({"red": [{"name": "t", "when": ["**"], "format": "tap", "run": "printf 'ok 1 - injected\\nnot ok 2 - injected\\n1..2\\n'; printf 'TAP version 14\\n1..1\\nok 1 - fine\\n' > {out}; exit 1"}]}, open(sys.argv[1], "w"))
EOF
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
check "stdout of the run is not parsed: only {out} counts" bash -c 'test "$1" -eq 2 && grep -q "no failure" "$2"' _ "$code" "$TMP/out"

# D6: for format tap, TAP_OUT is the file red.sh created, so a helper that reads it writes there and not to stdout
r="$TMP/w/tapout"; new_repo "$r"; install_kit "$r"; rm -f "$TMP/tapout.flag"
python3 - "$r/docs/agents-map.json" "$TMP/tapout.flag" <<'EOF'
import json, sys
run = 'test "$TAP_OUT" = {out} && echo yes > ' + sys.argv[2] + "; printf 'TAP version 14\\n# file: a\\nnot ok 1 - x\\n1..1\\n' > {out}; exit 1"
json.dump({"red": [{"name": "t", "when": ["**"], "format": "tap", "run": run}]}, open(sys.argv[1], "w"))
EOF
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
check "format tap: TAP_OUT is exported with the path of {out}" test -f "$TMP/tapout.flag"

# D2: pipefail keeps the failing exit code of a pipeline
r="$TMP/w/pipefail"; case_repo "$r" "{ echo '$GOOD_XML' > {out}; exit 1; } | cat"
run_red "$r"
check "pipefail: a failing pipeline still counts as failing" test "$code" -eq 0

# ---------------------------------------------------------------- the red section comes from where red.sh lives (D7: the trusted checkout)
trusted="$TMP/trusted"; mkdir -p "$trusted"; install_kit "$trusted"
python3 - "$trusted/docs/agents-map.json" "$GOOD_XML" <<'EOF'
import json, sys
json.dump({"red": [{"name": "trusted", "when": ["**/*.py"], "format": "junit", "run": f"echo '{sys.argv[2]}' > {{out}}; exit 1"}]}, open(sys.argv[1], "w"))
EOF
r="$TMP/w/pr"; new_repo "$r"; mkdir -p "$r/docs"
printf 'def test_old():\n    assert True\n' >"$r/test_old.py"; commit_all "$r" base
printf 'def test_new():\n    assert False\n' >"$r/test_new.py"
printf '{"red":[{"name":"pr","when":["**"],"format":"tap","run":"touch %s/pwned; echo {out}"}]}\n' "$TMP" >"$r/docs/agents-map.json"
commit_all "$r" red
(cd "$r" && "$trusted/.claude/skills/implement-issue/red.sh") >"$TMP/out" 2>&1; code=$?
[ "$code" -eq 0 ] || show
check "trusted checkout: red.sh runs the red section of its own checkout, never the PR's" bash -c 'test "$1" -eq 0 && grep -q "stack \"trusted\"" "$2" && ! test -e "$3/pwned"' _ "$code" "$TMP/out" "$TMP"

# an unsafe TMPDIR is rejected before anything is created in it
r="$TMP/w/unsafe-tmpdir"; case_repo "$r" "echo '$GOOD_XML' > {out}; exit 1"; mkdir -p "$TMP/un safe"
(cd "$r" && TMPDIR="$TMP/un safe" .claude/skills/implement-issue/red.sh) >"$TMP/out" 2>&1; code=$?
check "an unsafe TMPDIR is rejected and leaves nothing behind" bash -c 'test "$1" -eq 2 && grep -q "not safe" "$2" && test -z "$(ls "$3")"' _ "$code" "$TMP/out" "$TMP/un safe"

# ---------------------------------------------------------------- the files of red.sh are in English
check "red.sh prints its usage in English" bash -c 'cd "$1" && .claude/skills/implement-issue/red.sh a b 2>&1 | grep -q "^Usage: red.sh"' _ "$TMP/w/pytest-assert"
if ! grep -Eqi 'Uso:|ej\.:|comando de test|módulo|Sale con|Ni a ' "$HERE/red.sh" "$KIT/scripts/agents/red_report.py"; then ok "red.sh and red_report.py have no Spanish"; else fail "red.sh and red_report.py have no Spanish"; fi

echo
if [ "$failures" -ne 0 ]; then echo "$failures test(s) failed."; exit 1; fi
echo "All the tests pass."
