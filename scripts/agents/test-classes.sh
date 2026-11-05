#!/usr/bin/env bash
# shellcheck disable=SC2016  # los backticks y corchetes de los regex y del Markdown son literales
# Tests de ADR-006 fase 0 (#259): docs/agents/classes.yml y la clase en cada hallazgo de review-pr.
# El check de check-docs.py corre sobre una copia del repo (el helper de Python), así no toca el working tree.
# Uso: bash scripts/agents/test-classes.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-classes-XXXXXX")
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""

CLASES="$RAIZ/docs/agents/classes.yml"
SKILL_EN="$RAIZ/.claude/skills/review-pr/SKILL.md"
SKILL_ES="$RAIZ/.claude/skills/review-pr/SKILL.es.md"

# Copia el repo una sola vez y, por cada mutación, la aplica in situ, corre check-docs.py, guarda la salida en
# $TMP/out-<nombre> ("RC=<n>" y la salida) y la deshace. Termina siempre con 0.
PY='
import os, re, shutil, subprocess, sys
raiz, tmp = sys.argv[1], sys.argv[2]
dst = os.path.join(tmp, "r"); shutil.rmtree(dst, ignore_errors=True); os.makedirs(dst)
files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=raiz, capture_output=True, text=True).stdout.split("\0")
for f in files:
    if f and os.path.isfile(os.path.join(raiz, f)):
        os.makedirs(os.path.dirname(os.path.join(dst, f)) or dst, exist_ok=True)
        shutil.copy2(os.path.join(raiz, f), os.path.join(dst, f))
subprocess.run(["git", "init", "-q", "-b", "main"], cwd=dst, check=True)
subprocess.run(["git", "add", "-A"], cwd=dst, check=True)
subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"], cwd=dst, check=True)
YML = "docs/agents/classes.yml"
SK = [".claude/skills/review-pr/SKILL.md", ".claude/skills/review-pr/SKILL.es.md"]
def edit(path, fn):
    p = os.path.join(dst, path)
    if os.path.exists(p):
        t = open(p, encoding="utf-8").read(); open(p, "w", encoding="utf-8").write(fn(t))
def skills(fn):
    for s in SK: edit(s, fn)
MUT = {
 "none": lambda: None,
 "drop-class": lambda: edit(YML, lambda t: re.sub(r"- id: stale-docs\n(  .*\n)*", "", t)),
 "rename-tag": lambda: skills(lambda t: t.replace("[stale-docs]", "[made-up-class]")),
 "add-link": lambda: skills(lambda t: t + "\nSee [architecture](../../../README.md) and [x] and [todo].\n"),
 "drop-file": lambda: os.remove(os.path.join(dst, YML)),
 "bold-tag": lambda: skills(lambda t: t + "\n**[stale-doc]** file:line: x\n"),
 "bare-tag": lambda: skills(lambda t: t + "\n[typo] file:line: x\n"),
 "spaced-tag": lambda: skills(lambda t: t + "\n` [typo] file:line: x`\n"),
 "quoted-id": lambda: edit(YML, lambda t: t.replace("- id: stale-docs", "- id: \"stale-docs\"")),
 "dup-id": lambda: edit(YML, lambda t: t + "- id: stale-docs\n  description: again\n"),
 "no-desc": lambda: edit(YML, lambda t: re.sub(r"(- id: stale-docs\n)  description: .*\n", r"\1", t)),
 "other-listed": lambda: edit(YML, lambda t: t + "- id: other\n  description: reserved\n"),
 "bad-indent": lambda: edit(YML, lambda t: t.replace("  description: a doc, skill", "    description: a doc, skill")),
}
for name, fn in MUT.items():
    saved = {}
    for f in [YML] + SK:
        p = os.path.join(dst, f)
        if os.path.exists(p): saved[p] = open(p, "rb").read()
    fn()
    r = subprocess.run([sys.executable, "scripts/agents/check-docs.py"], cwd=dst, capture_output=True, text=True)
    open(os.path.join(tmp, "out-" + name), "w").write("RC=%d\n%s\n%s\n" % (r.returncode, r.stdout, r.stderr))
    for p, b in saved.items(): open(p, "wb").write(b)
    if not os.path.exists(os.path.join(dst, YML)): pass
'

IDS="pr-metadata ci-claim undecided-decision test-cannot-fail stale-docs wrong-command text-code-mismatch uncovered-case unhandled-input"

# 1. classes.yml existe y trae las clases que hoy adivina bk learn, cada una con descripción.
for id in $IDS; do
  grep -q "^- id: $id\$" "$CLASES" 2>/dev/null; tap_check $? "classes.yml: trae la clase" "classes.yml: trae la clase $id"
done
n=$(awk '/^  description: ./ {n++} END {print n+0}' "$CLASES")
total=$(grep -c '^- id: ' "$CLASES")
[ "$n" = "$total" ]; tap_check $? "classes.yml: cada clase tiene una descripción"

# 2. review-pr (en y es) fija el formato de cada hallazgo: la clase al principio, una sola, y [other] si no encaja.
for par in "en:$SKILL_EN" "es:$SKILL_ES"; do
  lang=${par%%:*}; f=${par#*:}
  if [ ! -f "$f" ]; then  # a project installed in a single language has no .es.md siblings
    tap_skip "review-pr: versión que no existe en este proyecto" "$lang: no existe $f"
    continue
  fi
  grep -q '\[stale-docs\]' "$f" 2>/dev/null; tap_check $? "review-pr: el ejemplo de hallazgo lleva la clase [stale-docs]" "review-pr ($lang): el ejemplo de hallazgo lleva la clase [stale-docs]"
  grep -q 'docs/agents/classes.yml' "$f" 2>/dev/null; tap_check $? "review-pr: remite a docs/agents/classes.yml" "review-pr ($lang): remite a docs/agents/classes.yml"
  grep -q '\[other\]' "$f" 2>/dev/null; tap_check $? "review-pr: usa [other] si ninguna clase encaja" "review-pr ($lang): usa [other] si ninguna clase encaja"
  if [ "$lang" = en ]; then
    grep -q '`\[class\] file:line: …`' "$f" 2>/dev/null; tap_check $? "review-pr: fija el formato [clase] file:line: …" "review-pr ($lang): fija el formato [class] file:line: …"
    grep -q 'one class per finding' "$f" 2>/dev/null; tap_check $? "review-pr: una sola clase por hallazgo" "review-pr ($lang): una sola clase por hallazgo"
  else
    grep -q '`\[clase\] file:line: …`' "$f" 2>/dev/null; tap_check $? "review-pr: fija el formato [clase] file:line: …" "review-pr ($lang): fija el formato [clase] file:line: …"
    grep -q 'una sola clase por hallazgo' "$f" 2>/dev/null; tap_check $? "review-pr: una sola clase por hallazgo" "review-pr ($lang): una sola clase por hallazgo"
  fi
done

# 3. check-docs.py: los ids que nombra la skill existen en classes.yml, y classes.yml está bien formado.
tap_run out 0 python3 -c "$PY" "$RAIZ" "$TMP"
o() { out=$(cat "$TMP/out-$1" 2>/dev/null); }
o none
[[ $out != *"the class ["* && $out != *"classes.yml"* ]]; tap_check $? "check-docs: el repo tal cual no marca errores de clases en review-pr"
o drop-class
grep -q 'review-pr.*stale-docs.*classes.yml' <<<"$out"; tap_check $? "check-docs: falla si la skill nombra una clase que classes.yml no tiene"
o rename-tag
grep -q 'review-pr.*made-up-class.*classes.yml' <<<"$out"; tap_check $? "check-docs: falla con un id inventado en la skill"
o add-link
[[ $out != *"the class ["* ]]; tap_check $? "check-docs: un enlace o un [x] de la skill no se toma por una clase"
o drop-file
grep -q 'review-pr.*classes.yml.*missing' <<<"$out"; tap_check $? "check-docs: falla si la skill remite a un classes.yml que no existe"
o bold-tag
grep -q 'the class \[stale-doc\]' <<<"$out"; tap_check $? "check-docs: valida un [id] en negrita en una línea de hallazgo"
o bare-tag
grep -q 'the class \[typo\]' <<<"$out"; tap_check $? "check-docs: valida un [id] sin code span en una línea de hallazgo"
o spaced-tag
grep -q 'the class \[typo\]' <<<"$out"; tap_check $? "check-docs: valida un [id] en code span con espacio previo"
o quoted-id
grep -q 'classes.yml:[0-9]*:.*unexpected' <<<"$out"; tap_check $? "check-docs: falla con un id entre comillas en classes.yml"
o dup-id
grep -q 'classes.yml:[0-9]*:.*duplicate' <<<"$out"; tap_check $? "check-docs: falla con un id duplicado en classes.yml"
o no-desc
grep -q 'classes.yml:[0-9]*:.*description' <<<"$out"; tap_check $? "check-docs: falla con una clase sin descripción"
o other-listed
grep -q 'classes.yml:[0-9]*:.*reserved' <<<"$out"; tap_check $? "check-docs: falla si classes.yml lista other"
o bad-indent
grep -q 'classes.yml:[0-9]*:.*unexpected' <<<"$out"; tap_check $? "check-docs: falla con otra indentación en classes.yml"

tap_done
