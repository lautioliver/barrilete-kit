#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2319  # bash -c bodies are single-quoted on purpose; "test ...; tap_check $?" is the pattern of the other tests
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
# shellcheck source=/dev/null
. "$KIT/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
export TMPDIR="$TMP/tmp"
mkdir -p "$TMPDIR"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

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
    echo "corpus $name: red.sh exited with $code, expected $expect"; show
  elif [ -n "$says" ] && ! grep -qF -- "$says" "$OUT"; then
    echo "corpus $name: the output lacks the text of its says= line"; show
  else
    echo "ok corpus $name -> $expect"
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
for c in "$CORPUS"/*/; do
  name=$(basename "${c%/}")
  grep -q '^ok ' "$TMP/res/$name.txt"
  tap_check $? "every case of the corpus gives the exit code its meta file expects" "$name"
  grep -q '^ok ' "$TMP/res/$name.txt" || sed 's/^/  /' "$TMP/res/$name.txt" >&2
done
test "$n" -ge 100; tap_check $? "the corpus has at least 100 cases"
# the three spellings of a non-UTF-8 declaration that a regex on `encoding=` misses (spaces, tabs, a BOM before it)
enc=0
for name in junit-latin1-spaces-around-equals junit-latin1-tabs junit-latin1-after-bom; do grep -q '^ok ' "$TMP/res/$name.txt" || enc=1; done
tap_check $enc "an XML that declares an encoding other than UTF-8 is rejected however it is written"

# ---------------------------------------------------------------- the PR block
repo="$TMP/w/pytest-assert"
run_red "$repo"
block=$(sed -n 's/^Block for .*: //p' "$TMP/out")
sha=$(git -C "$repo" rev-parse HEAD)
test -f "$block"; tap_check $? "red: a valid red prints the block path"
b=$(cat "$block" 2>/dev/null)
grep -q '<summary>Red before implementing</summary>' <<<"$b"; tap_check $? "block: uses the English literal Red before implementing"
grep -qx "red commit: $sha" <<<"$b"; tap_check $? "block: red commit is the sha of HEAD"
grep -qx "stack: tests" <<<"$b" && grep -qx "format: junit" <<<"$b"; tap_check $? "block: stack and format lines"
grep -qx -- '- test_new.py::test_total' <<<"$b"; tap_check $? "block: failing cases as file::name"
test "$(grep -c '^- ' <<<"$b")" -eq 1; tap_check $? "block: it lists only the failed case"
grep -q '^</details>' <<<"$b"; tap_check $? "block: closes the details"

# ---------------------------------------------------------------- usage and the red section
repo="$TMP/w/pytest-assert"
run_red "$repo" -- bash -c 'exit 1'
test "$code" -eq 64; tap_check $? "usage: red.sh -- <command> is gone (exit 64)"
grep -q 'agents-map.json' "$TMP/out"; tap_check $? "usage: it says where the command is declared"
run_red "$repo" a b
test "$code" -eq 64; tap_check $? "usage: two stacks (exit 64)"
run_red "$repo" nosuch
test "$code" -eq 2 && grep -q "tests" "$TMP/out"; tap_check $? "an unknown stack exits with 2 and lists the stacks"

r="$TMP/w/nosection"; new_repo "$r"; install_kit "$r"; printf '{"docs": []}\n' >"$r/docs/agents-map.json"
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
test "$code" -eq 2 && grep -q "no .red. section" "$TMP/out" && grep -q "gotestsum" "$TMP/out" && grep -q "no text fallback" "$TMP/out"; tap_check $? "D1: no red section -> exit 2 with a guide"

bad_map() { # bad_map <json of the red section> <text expected>: 0 if red.sh rejects it with that text
  local r="$TMP/w/badmap"; new_repo "$r"; install_kit "$r"; write_map "$r" "$1"
  echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
  run_red "$r"
  [ "$code" -eq 2 ] && grep -qF -- "$2" "$TMP/out" && return 0
  show >&2
  return 1
}
bad_map '[{"name":"t","when":["**"],"run":"true","format":"tap"}]' '{out}'; tap_check $? "map: run without {out} is rejected"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"text"}]' '"junit" or "tap"'; tap_check $? "map: unknown format is rejected"
bad_map '[{"name":"t","run":"true {out}","format":"tap"}]' '`when`'; tap_check $? "map: no when is rejected"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"tap","timeout":"soon"}]' '`timeout`'; tap_check $? "map: timeout must be a positive number"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"tap","timeout":0}]' '`timeout`'; tap_check $? "map: zero timeout is rejected"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"tap"},{"name":"t","when":["**"],"run":"true {out}","format":"tap"}]' 'unique `name`'; tap_check $? "map: duplicate names are rejected"
bad_map '[{"name":"my tests","when":["**"],"run":"true {out}","format":"tap"}]' 'letters, digits'; tap_check $? "map: a stack name with a space is rejected (it ends up in the path of {out})"
bad_map '[{"name":"a;b","when":["**"],"run":"true {out}","format":"tap"}]' 'letters, digits'; tap_check $? "map: a stack name with a shell metacharacter is rejected"
bad_map '[{"name":"t","when":["src/**"],"run":"true {out}","format":"tap"}]' 'no `red` entry matches'; tap_check $? "map: a stack that matches no changed file"

# ---------------------------------------------------------------- the commit
r="$TMP/w/dirty"; cp -R "$TMP/w/pytest-assert" "$r"; echo "# x" >>"$r/test_old.py"
run_red "$r"
test "$code" -eq 2 && grep -q "uncommitted" "$TMP/out"; tap_check $? "a tracked file changed after the red commit -> exit 2"

r="$TMP/w/rootcommit"; new_repo "$r"; install_kit "$r"; write_map "$r" '[{"name":"t","when":["**"],"run":"true {out}","format":"tap"}]'
commit_all "$r" only
run_red "$r"
test "$code" -eq 2 && grep -q "no parent" "$TMP/out"; tap_check $? "a red commit without parent -> exit 2"

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
test "$code" -eq 0; tap_check $? "two stacks that match, both red -> exit 0"
test "$(grep -c "^stack: " <<<"$b")" -eq 2 && grep -q "^stack: py" <<<"$b" && grep -q "^stack: sh" <<<"$b"; tap_check $? "two stacks: one group per stack in the block"
test "$(grep -c '^red commit: ' <<<"$b")" -eq 1; tap_check $? "two stacks: red commit appears once"
run_red "$r" py
b=$(cat "$(sed -n 's/^Block for .*: //p' "$TMP/out")" 2>/dev/null)
test "$code" -eq 0 && test "$(grep -c "^stack: " <<<"$b")" -eq 1 && ! grep -q "stack \"sh\"" "$TMP/out"; tap_check $? "red.sh <stack> runs only that stack"
python3 - "$r/docs/agents-map.json" <<'EOF'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m["red"][1]["run"] = m["red"][1]["run"].replace(" 1 0", " 0 0"); json.dump(m, open(p, "w"))
EOF
git -C "$r" commit -q -a --amend --no-edit; run_red "$r"
test "$code" -eq 2; tap_check $? "two stacks: one is rejected, the whole red is rejected (exit 2)"
git -C "$r" commit -q --allow-empty -m "empty"; run_red "$r"
test "$code" -eq 2 && grep -q "no .red. entry matches" "$TMP/out"; tap_check $? "a red commit that changes no file matches no stack (exit 2)"

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
test "$first" -eq 0 -a "$code" -eq 0; tap_check $? "report path: a valid red twice"
! grep -q EXISTED "$log"; tap_check $? "report path: nothing existed at {out} before the run"
test "$(grep -c '^/' "$log")" -eq 2 -a "$(grep '^/' "$log" | sort -u | wc -l | tr -d ' ')" -eq 2; tap_check $? "report path: it is different in each run"
grep "^/" "$log" | grep -q "^$TMPDIR/"; tap_check $? "report path: it is under TMPDIR, not in the repo"

# an old report left by a previous run cannot be reused
r="$TMP/w/stale"; case_repo "$r" "exit 1 # {out}"
run_red "$r"
test "$code" -eq 2 && grep -q "not created in this run" "$TMP/out"; tap_check $? "a run that writes no report is rejected even if an old one exists elsewhere"

# D5: timeout applied with python, and the whole process group dies
r="$TMP/w/timeout"; case_repo "$r" "echo '$GOOD_XML' > {out}; sleep 30 & wait" 1
start=$(date +%s); run_red "$r"; end=$(date +%s)
test "$code" -eq 2 && grep -q "passed its timeout" "$TMP/out" && test "$((end - start))" -lt 15; tap_check $? "timeout: the run is killed (exit 2) well before it ends by itself"

r="$TMP/w/group"; flag="$TMP/late"; rm -f "$flag"
case_repo "$r" "(sleep 2; echo late > $flag) & exit 1"
run_red "$r"; sleep 3
test "$code" -eq 2 && ! test -e "$flag"; tap_check $? "process group: a background child cannot write after red.sh returns"

r="$TMP/w/timeout-conf"; case_repo "$r" "echo '$GOOD_XML' > {out}; exit 1" 7
grep -q '"timeout": 7' "$r/docs/agents-map.json"; tap_check $? "timeout: it is read from the entry"
run_red "$r"
test "$code" -eq 0; tap_check $? "timeout: a run that ends in time is judged normally"
grep -q 'timeout 7 s' "$TMP/out"; tap_check $? "timeout: the output says the timeout of the stack"

r="$TMP/w/default-timeout"; case_repo "$r" "echo '$GOOD_XML' > {out}; exit 1"
python3 - "$r/docs/agents-map.json" <<'EOF'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); del m["red"][0]["timeout"]; json.dump(m, open(p, "w"))
EOF
git -C "$r" commit -q -a --amend --no-edit; run_red "$r"
grep -q 'timeout 600 s' "$TMP/out"; tap_check $? "timeout: without the field it is 600 s"

# D3: a report larger than 20 MB is not read
r="$TMP/w/big"; case_repo "$r" "head -c 21000000 /dev/zero > {out}; exit 1"
run_red "$r"
test "$code" -eq 2 && grep -q "larger than 20 MB" "$TMP/out"; tap_check $? "a report larger than 20 MB is rejected without reading it"
r="$TMP/w/symlink"; case_repo "$r" "echo '$GOOD_XML' > $TMP/target.xml; ln -s $TMP/target.xml {out}; exit 1"
run_red "$r"
test "$code" -eq 2 && grep -q "not a regular file" "$TMP/out"; tap_check $? "a report that is a symbolic link is rejected"

# D2: stdout of the run is not the evidence: lines that look like TAP on stdout inject no case
r="$TMP/w/stdout"; new_repo "$r"; install_kit "$r"
python3 - "$r/docs/agents-map.json" <<'EOF'
import json, sys
json.dump({"red": [{"name": "t", "when": ["**"], "format": "tap", "run": "printf 'ok 1 - injected\\nnot ok 2 - injected\\n1..2\\n'; printf 'TAP version 14\\n1..1\\nok 1 - fine\\n' > {out}; exit 1"}]}, open(sys.argv[1], "w"))
EOF
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
test "$code" -eq 2 && grep -q "no failure" "$TMP/out"; tap_check $? "stdout of the run is not parsed: only {out} counts"

# D6: for format tap, TAP_OUT is the file red.sh created, so a helper that reads it writes there and not to stdout
r="$TMP/w/tapout"; new_repo "$r"; install_kit "$r"; rm -f "$TMP/tapout.flag"
python3 - "$r/docs/agents-map.json" "$TMP/tapout.flag" <<'EOF'
import json, sys
run = 'test "$TAP_OUT" = {out} && echo yes > ' + sys.argv[2] + "; printf 'TAP version 14\\n# file: a\\nnot ok 1 - x\\n1..1\\n' > {out}; exit 1"
json.dump({"red": [{"name": "t", "when": ["**"], "format": "tap", "run": run}]}, open(sys.argv[1], "w"))
EOF
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
test -f "$TMP/tapout.flag"; tap_check $? "format tap: TAP_OUT is exported with the path of {out}"

# D2: pipefail keeps the failing exit code of a pipeline
r="$TMP/w/pipefail"; case_repo "$r" "{ echo '$GOOD_XML' > {out}; exit 1; } | cat"
run_red "$r"
test "$code" -eq 0; tap_check $? "pipefail: a failing pipeline still counts as failing"

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
test "$code" -eq 0 && grep -q "stack \"trusted\"" "$TMP/out" && ! test -e "$TMP/pwned"; tap_check $? "trusted checkout: red.sh runs the red section of its own checkout, never the PR's"

# an unsafe TMPDIR is rejected before anything is created in it
r="$TMP/w/unsafe-tmpdir"; case_repo "$r" "echo '$GOOD_XML' > {out}; exit 1"; mkdir -p "$TMP/un safe"
(cd "$r" && TMPDIR="$TMP/un safe" .claude/skills/implement-issue/red.sh) >"$TMP/out" 2>&1; code=$?
test "$code" -eq 2 && grep -q "not safe" "$TMP/out" && test -z "$(ls "$TMP/un safe")"; tap_check $? "an unsafe TMPDIR is rejected and leaves nothing behind"

# ---------------------------------------------------------------- the kit's own `red` entry (docs/agents-map.json)
# The real entry, run on a repo with two changed tests: a script that dies before it sources tap.sh writes no TAP
# and must not hide behind the valid failure of the other one (D3: 0 errors); a script that is not a test is not run.
# The small profile installs this test with a map that has no red entry of the kit's: nothing to check there.
# In the kit itself (and in a full install) a missing or renamed `bash` entry is a failure, not a skip.
if ! grep -q '"mode"[[:space:]]*:[[:space:]]*"small"' "$KIT/.agent-kit.json" 2>/dev/null; then
  python3 -c 'import json,sys; sys.exit(0 if any(e.get("name") == "bash" for e in json.load(open(sys.argv[1])).get("red", [])) else 1)' "$KIT/docs/agents-map.json" 2>/dev/null
  tap_check $? "the map of the kit has its bash red entry"
  kit_repo() { # kit_repo <dir>: the kit's red entry, tap.sh and a base commit
    new_repo "$1"; install_kit "$1"
    cp "$KIT/scripts/agents/tap.sh" "$1/scripts/agents/"
    python3 - "$KIT/docs/agents-map.json" "$1/docs/agents-map.json" <<'PY'
import json, sys
json.dump({"red": json.load(open(sys.argv[1]))["red"]}, open(sys.argv[2], "w"))
PY
    printf 'old\n' >"$1/README"; commit_all "$1" base
  }
  good_test='ROOT=$(cd "$(dirname "$0")/../.." && pwd); . "$ROOT/scripts/agents/tap.sh"; tap_begin "$0"; test 2 -eq 3; tap_check $? "two equals three"; tap_done'
  dies_test='set -e; ROOT=$(cd "$(dirname "$0")/../.." && pwd); . "$ROOT/scripts/agents/new-helper.sh"; . "$ROOT/scripts/agents/tap.sh"; tap_begin "$0"; tap_done'
  r="$TMP/w/kit-two-scripts"; kit_repo "$r"
  printf '%s\n' "$good_test" >"$r/scripts/agents/test-foo.sh"; printf '%s\n' "$dies_test" >"$r/scripts/agents/test-bar.sh"
  commit_all "$r" red
  run_red "$r"
  test "$code" -eq 2; tap_check $? "kit red entry: a script that dies before tap.sh makes the run invalid even if another one fails"
  r="$TMP/w/kit-one-script"; kit_repo "$r"
  printf '%s\n' "$good_test" >"$r/scripts/agents/test-foo.sh"
  commit_all "$r" red
  run_red "$r"
  test "$code" -eq 0; tap_check $? "kit red entry: a test that fails with an assertion is a valid red"
  r="$TMP/w/kit-not-a-test"; kit_repo "$r"
  printf '%s\n' "$good_test" >"$r/scripts/agents/test-foo.sh"
  printf 'touch "%s/ran-fetch"\n' "$TMP" >"$r/scripts/fetch-latest-tag.sh"
  commit_all "$r" red
  run_red "$r"
  bash -c 'test "$1" -eq 0 && ! test -e "$2/ran-fetch"' _ "$code" "$TMP"; tap_check $? "kit red entry: a script that is not a test-*.sh is never run"
  r="$TMP/w/kit-spaces"; kit_repo "$r"; mkdir -p "$r/scripts/my dir"
  printf '%s\n' "$good_test" >"$r/scripts/my dir/test-foo.sh"
  commit_all "$r" red
  run_red "$r"
  test "$code" -eq 0; tap_check $? "kit red entry: a test in a path with spaces is run"
  reads_test="cat >/dev/null; $good_test"
  nodone_test='ROOT=$(cd "$(dirname "$0")/../.." && pwd); . "$ROOT/scripts/agents/tap.sh"; tap_begin "$0"; exit 0'
  r="$TMP/w/kit-reads-stdin"; kit_repo "$r"
  printf '%s\n' "$reads_test" >"$r/scripts/agents/test-a.sh"; printf '%s\n' "$dies_test" >"$r/scripts/agents/test-b.sh"
  commit_all "$r" red
  run_red "$r"
  test "$code" -eq 2; tap_check $? "kit red entry: a test that reads stdin does not stop the next scripts from running"
  r="$TMP/w/kit-dies-first"; kit_repo "$r"
  printf '%s\n' "$dies_test" >"$r/scripts/agents/test-a.sh"; printf '%s\n' "$good_test" >"$r/scripts/agents/test-b.sh"
  commit_all "$r" red
  run_red "$r"
  test "$code" -eq 2; tap_check $? "kit red entry: a script that dies before tap.sh is caught when it runs first"
  r="$TMP/w/kit-no-tap-done"; kit_repo "$r"
  printf '%s\n' "$good_test" >"$r/scripts/agents/test-a.sh"; printf '%s\n' "$nodone_test" >"$r/scripts/agents/test-b.sh"
  commit_all "$r" red
  run_red "$r"
  test "$code" -eq 2; tap_check $? "kit red entry: a script that exits 0 without tap_done makes the run invalid"
fi

# ---------------------------------------------------------------- the files of red.sh are in English
usage=$(cd "$TMP/w/pytest-assert" && .claude/skills/implement-issue/red.sh a b 2>&1) || true  # it exits with 64
grep -q "^Usage: red.sh" <<<"$usage"; tap_check $? "red.sh prints its usage in English"
! grep -Eqi 'Uso:|ej\.:|comando de test|módulo|Sale con|Ni a ' "$HERE/red.sh" "$KIT/scripts/agents/red_report.py"; tap_check $? "red.sh and red_report.py have no Spanish"

tap_done
