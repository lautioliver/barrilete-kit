#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2319  # bash -c bodies are single-quoted on purpose; "test ...; tap_check $?" is the pattern of the other tests
# Tests of red.sh (ADR-002): every case of corpus/ is run through red.sh, and so are the cases that
# the corpus cannot express (usage, the `red` section, the report path, timeouts, the trusted checkout).
#
# A corpus case is a directory:
#   meta        expect=<exit code of red.sh> format=junit exit=<exit code of the runner> source=<how the fixture was made>
#               optional: says=<text red.sh must print>, timeout=<s>, sleep=<s the runner stays alive>, note=
#   base/       the files of the parent commit
#   red/        the files the red commit adds or changes
#   report.xml  what the runner wrote to {out} (absent: it wrote nothing)
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
[ -f "$case_dir/report.xml" ] && cp "$case_dir/report.xml" "$out"
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
  code=0
  (trap - ERR; cd "$repo" && "$repo/.claude/skills/implement-issue/red.sh" "$@") >"${OUT:-$TMP/out}" 2>&1 || code=$?
}
show() { sed 's/^/       /' "${OUT:-$TMP/out}"; }
meta() { grep "^$2=" "$1/meta" | head -1 | cut -d= -f2- || true; }  # a key that is not there is empty

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

# 2.0.0 removed format "tap" (ADR-002 D8, #227): a stack with it exits with 2 and prints the literal line, and its run never starts.
tap_removed() { printf 'red stack '"'"'%s'"'"': format "tap" was removed in 2.0.0; use "junit" (docs/guides/red-per-runner.md)' "$1"; }
r="$TMP/w/tap-removed"; new_repo "$r"; install_kit "$r"
write_map "$r" "[{\"name\": \"mine\", \"when\": [\"**\"], \"format\": \"tap\", \"run\": \"touch $TMP/tap-removed-ran; bash $TMP/fake-run.sh $CORPUS/bash-new-script {out} 1 0\"}]"
cp -R "$CORPUS/bash-new-script/base/." "$r/"; commit_all "$r" base; cp -R "$CORPUS/bash-new-script/red/." "$r/"; commit_all "$r" red
run_red "$r"
test "$code" -eq 2; tap_check $? "227: a stack with format tap exits with 2 (2.0.0 removed it)"
grep -qxF "$(tap_removed mine)" "$TMP/out"; tap_check $? "227: a stack with format tap prints the literal line of ADR-002 D8"
test ! -e "$TMP/tap-removed-ran"; tap_check $? "227: the run of a stack with format tap never starts"
o=$(<"$TMP/out")
[[ "$o" != *'which 2.0.0 removes'* ]]; tap_check $? "227: the warning of 1.x is gone (2.0.0 rejects, it does not warn)"
r="$TMP/w/tap-removed-notrun"; new_repo "$r"; install_kit "$r"
write_map "$r" "[{\"name\": \"old\", \"when\": [\"**/*.nomatch\"], \"format\": \"tap\", \"run\": \"true {out}\"}, {\"name\": \"py\", \"when\": [\"**\"], \"format\": \"junit\", \"run\": \"bash $TMP/fake-run.sh $CORPUS/pytest-assert {out} 1 0\"}]"
cp -R "$CORPUS/pytest-assert/base/." "$r/"; commit_all "$r" base; cp -R "$CORPUS/pytest-assert/red/." "$r/"; commit_all "$r" red
run_red "$r"
test "$code" -eq 2; tap_check $? "227: a map with a tap stack is rejected even when that stack does not match the commit"
grep -qxF "$(tap_removed old)" "$TMP/out"; tap_check $? "227: the rejection of a tap stack that does not match names it with the literal line"

bad_map() { # bad_map <json of the red section> <text expected>: 0 if red.sh rejects it with that text
  local r="$TMP/w/badmap"; new_repo "$r"; install_kit "$r"; write_map "$r" "$1"
  echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
  run_red "$r"
  [ "$code" -eq 2 ] && grep -qF -- "$2" "$TMP/out" && return 0
  show >&2
  return 1
}
bad_map '[{"name":"t","when":["**"],"run":"true","format":"junit"}]' '{out}'; tap_check $? "map: run without {out} is rejected"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"text"}]' 'has to be "junit"'; tap_check $? "map: unknown format is rejected"
bad_map '[{"name":"t","run":"true {out}","format":"junit"}]' '`when`'; tap_check $? "map: no when is rejected"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"junit","timeout":"soon"}]' '`timeout`'; tap_check $? "map: timeout must be a positive number"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"junit","timeout":0}]' '`timeout`'; tap_check $? "map: zero timeout is rejected"
bad_map '[{"name":"t","when":["**"],"run":"true {out}","format":"junit"},{"name":"t","when":["**"],"run":"true {out}","format":"junit"}]' 'unique `name`'; tap_check $? "map: duplicate names are rejected"
bad_map '[{"name":"my tests","when":["**"],"run":"true {out}","format":"junit"}]' 'letters, digits'; tap_check $? "map: a stack name with a space is rejected (it ends up in the path of {out})"
bad_map '[{"name":"a;b","when":["**"],"run":"true {out}","format":"junit"}]' 'letters, digits'; tap_check $? "map: a stack name with a shell metacharacter is rejected"
bad_map '[{"name":"t","when":["src/**"],"run":"true {out}","format":"junit"}]' 'no `red` entry matches'; tap_check $? "map: a stack that matches no changed file"

# ---------------------------------------------------------------- the commit
r="$TMP/w/dirty"; cp -R "$TMP/w/pytest-assert" "$r"; echo "# x" >>"$r/test_old.py"
run_red "$r"
test "$code" -eq 2 && grep -q "uncommitted" "$TMP/out"; tap_check $? "a tracked file changed after the red commit -> exit 2"

r="$TMP/w/rootcommit"; new_repo "$r"; install_kit "$r"; write_map "$r" '[{"name":"t","when":["**"],"run":"true {out}","format":"junit"}]'
commit_all "$r" only
run_red "$r"
test "$code" -eq 2 && grep -q "no parent" "$TMP/out"; tap_check $? "a red commit without parent -> exit 2"

# ---------------------------------------------------------------- the bash entry in JUnit (#225, ADR-002 D6)
# The `run` that these cases execute is the one the kit ships: it is read from docs/agents-map.json and from the small profile,
# not copied here (a copy can drift from the shipped string, and a quoting error in the shipped one would go unseen).
FULL_MAP="$KIT/docs/agents-map.json"; SMALL_MAP="$KIT/profiles/small/docs/agents-map.json"
# jrepo <name> [map]: a repo whose map has only the `bash` entry of that map (default: the kit's), with the real helper
jrepo() {
  local r="$TMP/w/$1"
  new_repo "$r"; install_kit "$r"; cp "$KIT/scripts/agents/tap.sh" "$r/scripts/agents/tap.sh"
  python3 - "${2:-$FULL_MAP}" "$r/docs/agents-map.json" <<'PYEOF'
import json, sys
entry = [e for e in json.load(open(sys.argv[1]))["red"] if e["name"] == "bash"][0]
json.dump({"red": [entry]}, open(sys.argv[2], "w"))
PYEOF
}
shead() { printf '#!/usr/bin/env bash\n. "$(dirname "$0")/agents/tap.sh"\ntap_begin "$0"\n'; }
# says <text>: does the output of the last run_red contain it? A function that is an assertion (status 1 when it does not)
says() { local t; t=$(<"$TMP/out"); [ "${t#*"$1"}" != "$t" ]; }
# block_has_line <line>: is it a whole line of the block that red.sh left for the PR?
block_has_line() {
  local b="" t l
  while IFS= read -r l; do case $l in "Block for "*": "*) b=${l##*: } ;; esac; done <"$TMP/out"
  t=$(<"$b"); [[ $'\n'"$t"$'\n' == *$'\n'"$1"$'\n'* ]]
}

for prof in full small; do
  map=$FULL_MAP; [ "$prof" = small ] && map=$SMALL_MAP
  jrepo "j-new-$prof" "$map"
  commit_all "$TMP/w/j-new-$prof" base
  { shead; printf 'tap_ok "passes"\n[ 1 -eq 2 ]; tap_check $? "new case fails"\ntap_done\n'; } >"$TMP/w/j-new-$prof/scripts/test-new.sh"
  commit_all "$TMP/w/j-new-$prof" red
  run_red "$TMP/w/j-new-$prof"
  test "$code" -eq 0; tap_check $? "225: the shipped bash entry gives a valid red with the real helper (exit 0)" "map: $prof"
  says 'test-new.sh::new case fails'; tap_check $? "225: the failing case of the shipped bash entry is listed as file::id" "map: $prof"
  block_has_line 'format: junit'; tap_check $? "225: the block of the shipped bash entry says format: junit" "map: $prof"
done

# an edited old script: the case that fails has to be defined by an added line (.sh in JUnit is read like the helper's TAP)
jrepo j-old
{ shead; printf 'tap_ok "old case"\ntap_done\n'; } >"$TMP/w/j-old/scripts/test-old.sh"
commit_all "$TMP/w/j-old" base
{ shead; printf 'tap_ok "old case"\n[ 1 -eq 2 ]; tap_check $? "added case"\ntap_done\n'; } >"$TMP/w/j-old/scripts/test-old.sh"
commit_all "$TMP/w/j-old" red
run_red "$TMP/w/j-old"
test "$code" -eq 0; tap_check $? "225: in JUnit a failing case defined by an added line of an old .sh is accepted (exit 0)"
says 'test-old.sh::added case'; tap_check $? "225: in JUnit the case of an added line of an old .sh is listed"
jrepo j-old2
{ shead; printf '[ 1 -eq 2 ]; tap_check $? "old broken case"\ntap_done\n'; } >"$TMP/w/j-old2/scripts/test-old.sh"
commit_all "$TMP/w/j-old2" base
{ shead; printf '[ 1 -eq 2 ]; tap_check $? "old broken case"\n[ 1 -eq 2 ]; tap_check $? "added case"\ntap_done\n'; } >"$TMP/w/j-old2/scripts/test-old.sh"
commit_all "$TMP/w/j-old2" red
run_red "$TMP/w/j-old2"
test "$code" -eq 2; tap_check $? "225: in JUnit an old failing case of a .sh is rejected (exit 2)"
says 'old broken case'; tap_check $? "225: in JUnit the rejected old case is named"
says 'not defined by a line this commit adds'; tap_check $? "225: in JUnit the old case is rejected by D4, not by something else"

# a test file of the diff that left nothing in the report makes the red fail, even next to a valid failure
jrepo j-missing
commit_all "$TMP/w/j-missing" base
{ shead; printf '[ 1 -eq 2 ]; tap_check $? "new case fails"\ntap_done\n'; } >"$TMP/w/j-missing/scripts/test-a.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/w/j-missing/scripts/test-b.sh"
commit_all "$TMP/w/j-missing" red
run_red "$TMP/w/j-missing"
test "$code" -eq 2; tap_check $? "225: a test file of the red diff that left nothing in the report makes red.sh exit 2"
says 'test-b.sh'; tap_check $? "225: red.sh names the test file that left nothing in the report"
jrepo j-missing2
mkdir -p "$TMP/w/j-missing2/src"; printf 'x = 1\n' >"$TMP/w/j-missing2/src/helper.py"; printf 'x\n' >"$TMP/w/j-missing2/README.md"
commit_all "$TMP/w/j-missing2" base
{ shead; printf '[ 1 -eq 2 ]; tap_check $? "new case fails"\ntap_done\n'; } >"$TMP/w/j-missing2/scripts/test-a.sh"
printf 'y = 2\n' >"$TMP/w/j-missing2/src/helper.py"; printf 'y\n' >"$TMP/w/j-missing2/README.md"
commit_all "$TMP/w/j-missing2" red
run_red "$TMP/w/j-missing2"
test "$code" -eq 0; tap_check $? "225: code and docs in the red diff are not test files (no check on them)"

# a script that ran and left no case (tap_skip_all) is a script that ran: it is not "left nothing in the report"
jrepo j-skipall
commit_all "$TMP/w/j-skipall" base
{ shead; printf '[ 1 -eq 2 ]; tap_check $? "new case fails"\ntap_done\n'; } >"$TMP/w/j-skipall/scripts/test-a.sh"
{ shead; printf 'tap_skip_all "needs docker"\n'; } >"$TMP/w/j-skipall/scripts/test-b.sh"
commit_all "$TMP/w/j-skipall" red
run_red "$TMP/w/j-skipall"
test "$code" -eq 0; tap_check $? "225: in JUnit a script of the red diff that ran with tap_skip_all is not rejected as not run (exit 0)"

# a renamed test is a test the run runs (the file is named by its new path)
for prof in full small; do
  map=$FULL_MAP; [ "$prof" = small ] && map=$SMALL_MAP
  jrepo "j-rename-$prof" "$map"
  { shead; printf 'tap_ok "old case"\ntap_ok "another old case"\ntap_ok "a third old case"\ntap_done\n'; } >"$TMP/w/j-rename-$prof/scripts/test-old.sh"
  commit_all "$TMP/w/j-rename-$prof" base
  git -C "$TMP/w/j-rename-$prof" mv scripts/test-old.sh scripts/test-renamed.sh
  { shead; printf 'tap_ok "old case"\ntap_ok "another old case"\ntap_ok "a third old case"\n[ 1 -eq 2 ]; tap_check $? "renamed case"\ntap_done\n'; } >"$TMP/w/j-rename-$prof/scripts/test-renamed.sh"
  commit_all "$TMP/w/j-rename-$prof" red
  run_red "$TMP/w/j-rename-$prof"
  test "$code" -eq 0; tap_check $? "225: a renamed test is run by the shipped bash entry: the red is valid (exit 0)" "map: $prof"
  says 'test-renamed.sh::renamed case'; tap_check $? "225: the failing case of a renamed test is listed" "map: $prof"
done

# a test file by its name under another runner is a test file when the entry's `when` matches it
r="$TMP/w/j-pytest"; new_repo "$r"; install_kit "$r"
mkdir -p "$TMP/jp"; cp "$CORPUS/pytest-assert/"{report.xml,output.txt} "$TMP/jp/"
write_map "$r" "[{\"name\": \"py\", \"when\": [\"**/*.py\"], \"format\": \"junit\", \"run\": \"bash $TMP/fake-run.sh $TMP/jp {out} 1 0\"}]"
cp -R "$CORPUS/pytest-assert/base/." "$r/"; commit_all "$r" base
cp -R "$CORPUS/pytest-assert/red/." "$r/"; printf 'def test_other_new():\n    assert True\n' >"$r/test_not_in_report.py"; mkdir -p "$r/__tests__"; printf 'it("x", () => {})\n' >"$r/__tests__/x.js"; commit_all "$r" red
run_red "$r"
test "$code" -eq 2; tap_check $? "225: a pytest file (test_*.py) of the diff that is not in the report makes red.sh exit 2"
says 'test_not_in_report.py'; tap_check $? "225: red.sh names the pytest file that is not in the report"
out_text=$(<"$TMP/out")
[ "${out_text#*__tests__/x.js}" = "$out_text" ]; tap_check $? "225: a file the entry's when does not match is not checked (when intersects the patterns)"
r="$TMP/w/j-spec"; new_repo "$r"; install_kit "$r"
write_map "$r" "[{\"name\": \"js\", \"when\": [\"**\"], \"format\": \"junit\", \"run\": \"bash $TMP/fake-run.sh $TMP/jp {out} 1 0\"}]"
mkdir -p "$r/src/__tests__"; echo x >"$r/a"; commit_all "$r" base
printf 'it("x", () => {})\n' >"$r/src/a.spec.ts"; printf 'it("y", () => {})\n' >"$r/src/__tests__/b.js"; commit_all "$r" red
run_red "$r"
says 'a.spec.ts'; tap_check $? "225: a *.spec.* file of the diff is a test file"
says '__tests__/b.js'; tap_check $? "225: a __tests__/ file of the diff is a test file"

# what red.sh gives the run: TAP_OUT and TAP_FORMAT (junit, the only format left)
r="$TMP/w/env-junit"; new_repo "$r"; install_kit "$r"
write_map "$r" "[{\"name\": \"e\", \"when\": [\"**\"], \"format\": \"junit\", \"run\": \"printf '%s|%s' \\\"\${TAP_FORMAT-unset}\\\" \\\"\${TAP_OUT-unset}\\\" >$TMP/env-junit.txt; true {out}\"}]"
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
[ "$(cut -d'|' -f1 "$TMP/env-junit.txt" 2>/dev/null)" = junit ]; tap_check $? "225: red.sh exports TAP_FORMAT=junit to an entry with format junit"
grep -q '|.*report\.' "$TMP/env-junit.txt" 2>/dev/null; tap_check $? "225: red.sh exports TAP_OUT (the path of {out}) to an entry with format junit"

# the second marker, in JUnit (the kit's bash entry is JUnit now)
jmarker() { # jmarker <name> <second marker: pass|failure|skipped> [<id prefix, e.g. "182: ">]
  local r="$TMP/w/$1" t="$TMP/m-$1"
  new_repo "$r"; install_kit "$r"; mkdir -p "$t" "$r/scripts"
  local child=""
  case $2 in failure) child='<failure message="x"/>' ;; skipped) child='<skipped message="x"/>' ;; esac
  printf '<testsuites><testsuite name="scripts/new.sh" file="scripts/new.sh" tests="2" failures="1"><testcase name="runner prints its marker" file="scripts/new.sh"><failure message="x"/></testcase><testcase name="%ssecond marker: the nested test reached the step under test" file="scripts/new.sh">%s</testcase></testsuite></testsuites>\n' "${3:-}" "$child" >"$t/report.xml"
  write_map "$r" "[{\"name\": \"sh\", \"when\": [\"**/*.sh\"], \"format\": \"junit\", \"run\": \"bash $TMP/fake-run.sh $t {out} 1 0\"}]"
  printf 'x\n' >"$r/scripts/old.sh"; commit_all "$r" base
  printf '# runner prints its marker\ntap_ok "runner prints its marker"\ntap_ok "%ssecond marker: the nested test reached the step under test"\n' "${3:-}" >"$r/scripts/new.sh"; commit_all "$r" red
  run_red "$r"
}
jmarker jm-failure failure
test "$code" -eq 2; tap_check $? "225: JUnit: a red where the case of the second marker failed is rejected (exit 2)"
says 'second marker'; tap_check $? "225: JUnit: the rejection of a failed second marker names the second marker"
jmarker jm-skipped skipped
test "$code" -eq 2; tap_check $? "225: JUnit: a red where the case of the second marker was skipped is rejected (exit 2)"
says 'second marker'; tap_check $? "225: JUnit: the rejection of a skipped second marker names the second marker"
jmarker jm-pass pass
test "$code" -eq 0; tap_check $? "225: JUnit: a red where the case of the second marker passes is accepted (exit 0)"
jmarker jm-failure-numbered failure "182: "
test "$code" -eq 2; tap_check $? "211: JUnit: a red where the case \"<N>: second marker: …\" (id with the issue number first) failed is rejected (exit 2)"
jmarker jm-skipped-numbered skipped "182: "
test "$code" -eq 2; tap_check $? "211: JUnit: a red where the case \"<N>: second marker: …\" was skipped is rejected (exit 2)"

# ---------------------------------------------------------------- several stacks, the choice of stack
r="$TMP/w/two-stacks"; new_repo "$r"; install_kit "$r"
mkdir -p "$TMP/py" "$TMP/tp"; cp "$CORPUS/pytest-assert/"{report.xml,output.txt} "$TMP/py/"; cp "$CORPUS/bash-new-script/"{report.xml,output.txt} "$TMP/tp/"
python3 - "$r/docs/agents-map.json" "$TMP/fake-run.sh" "$TMP/py" "$TMP/tp" <<'EOF'
import json, sys
out, fake, py, tp = sys.argv[1:5]
json.dump({"red": [
    {"name": "py", "when": ["**/*.py"], "format": "junit", "run": f"bash {fake} {py} {{out}} 1 0"},
    {"name": "sh", "when": ["**/*.sh"], "format": "junit", "run": f"bash {fake} {tp} {{out}} 1 0"}]}, open(out, "w"))
EOF
mkdir -p "$r/scripts"
printf 'x\n' >"$r/test_old.py"; printf 'x\n' >"$r/scripts/test-calc.sh"; commit_all "$r" base
cp -R "$CORPUS/pytest-assert/red/." "$r/"; mkdir -p "$r/scripts"; cp -R "$CORPUS/bash-new-script/red/." "$r/"
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

# D2: stdout of the run is not the evidence: a failing testcase printed on stdout injects no case
r="$TMP/w/stdout"; new_repo "$r"; install_kit "$r"
python3 - "$r/docs/agents-map.json" <<'EOF'
import json, sys
run = "printf '<testsuite tests=\"1\"><testcase name=\"injected\" file=\"a\"><failure/></testcase></testsuite>\\n'; printf '<testsuite tests=\"1\"><testcase name=\"fine\" file=\"a\"/></testsuite>\\n' > {out}; exit 1"
json.dump({"red": [{"name": "t", "when": ["**"], "format": "junit", "run": run}]}, open(sys.argv[1], "w"))
EOF
echo a >"$r/a"; commit_all "$r" base; echo b >"$r/a"; commit_all "$r" red
run_red "$r"
test "$code" -eq 2 && grep -q "no failure" "$TMP/out"; tap_check $? "stdout of the run is not parsed: only {out} counts"

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
printf '{"red":[{"name":"pr","when":["**"],"format":"junit","run":"touch %s/pwned; echo {out}"}]}\n' "$TMP" >"$r/docs/agents-map.json"
commit_all "$r" red
(cd "$r" && "$trusted/.claude/skills/implement-issue/red.sh") >"$TMP/out" 2>&1; code=$?
[ "$code" -eq 0 ] || show
test "$code" -eq 0 && grep -q "stack \"trusted\"" "$TMP/out" && ! test -e "$TMP/pwned"; tap_check $? "trusted checkout: red.sh runs the red section of its own checkout, never the PR's"

# an unsafe TMPDIR is rejected before anything is created in it
r="$TMP/w/unsafe-tmpdir"; case_repo "$r" "echo '$GOOD_XML' > {out}; exit 1"; mkdir -p "$TMP/un safe"
code=0; (trap - ERR; cd "$r" && TMPDIR="$TMP/un safe" .claude/skills/implement-issue/red.sh) >"$TMP/out" 2>&1 || code=$?
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
  test "$code" -eq 0 && ! test -e "$TMP/ran-fetch"; tap_check $? "kit red entry: a script that is not a test-*.sh is never run"
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
c=0; usage=$(trap - ERR; cd "$TMP/w/pytest-assert" && .claude/skills/implement-issue/red.sh a b 2>&1) || c=$?; tap_status "$c" 64  # usage error
grep -q "^Usage: red.sh" <<<"$usage"; tap_check $? "red.sh prints its usage in English"
! grep -Eqi 'Uso:|ej\.:|comando de test|módulo|Sale con|Ni a ' "$HERE/red.sh" "$KIT/scripts/agents/red_report.py"; tap_check $? "red.sh and red_report.py have no Spanish"


# missing_test_files does not walk the tree once per case (a go or rust report can have thousands of passing cases)
cat >"$TMP/tree-count.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import red_report as rr


class Counting(set):
    walks = 0

    def __iter__(self):
        Counting.walks += 1
        return super().__iter__()


def run(when):
    Counting.walks = 0
    diff = rr.Diff.__new__(rr.Diff)
    diff.root, diff.commit, diff.status, diff.old_path, diff._added = ".", "x", {"pkg/a/a_test.go": "A"}, {}, {}
    diff._tree = Counting(["go.mod", "pkg/a/a_test.go", "pkg/b/y_test.go"])
    diff.read = lambda p: "module ex.com/m\n" if p == "go.mod" else None
    report = rr.Report()
    for i in range(200):
        report.cases.append(rr.Case(None, "ex.com/m/pkg/a", "TestA%d" % i, "pass"))
        report.cases.append(rr.Case("b/y_test.go", "", "TestB%d" % i, "pass"))
    missing = rr.missing_test_files(diff, {"when": when}, report)
    return Counting.walks, missing


walks, missing = run(["**/*_test.go"])
print("walks=ok" if walks <= 6 and missing == [] else "walks=%d missing=%s" % (walks, missing))
walks, missing = run(["**/*.nomatch"])
print("none=ok" if walks == 0 and missing == [] else "none=%d missing=%s" % (walks, missing))
PY
tap_run out 0 python3 -I "$TMP/tree-count.py" "$KIT/scripts/agents"
# shellcheck disable=SC2154  # tap_run leaves the output in $out
case $out in *"walks=ok"*) w=0 ;; *) w=1 ;; esac; tap_check "$w" "225: missing_test_files walks the tree a few times for 400 cases, not once per case"
case $out in *"none=ok"*) w=0 ;; *) w=1 ;; esac; tap_check "$w" "225: missing_test_files does not map a case when the diff has no test file for the entry"

tap_done
