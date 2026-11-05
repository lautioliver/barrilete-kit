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

# Copia el repo, aplica una mutación y corre check-docs.py. Imprime "RC=<n>" y la salida; termina siempre con 0.
# Mutaciones: none · drop-class <id> (saca la clase de classes.yml) · rename-tag <viejo> <nuevo> (cambia la etiqueta en las dos skills).
PY='
import os, re, shutil, subprocess, sys
raiz, tmp, mut = sys.argv[1], sys.argv[2], sys.argv[3]
dst = os.path.join(tmp, "r"); shutil.rmtree(dst, ignore_errors=True); os.makedirs(dst)
files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=raiz, capture_output=True, text=True).stdout.split("\0")
for f in files:
    if f and os.path.isfile(os.path.join(raiz, f)):
        os.makedirs(os.path.dirname(os.path.join(dst, f)) or dst, exist_ok=True)
        shutil.copy2(os.path.join(raiz, f), os.path.join(dst, f))
def edit(path, fn):
    p = os.path.join(dst, path)
    if os.path.exists(p):
        t = open(p, encoding="utf-8").read(); open(p, "w", encoding="utf-8").write(fn(t))
if mut == "drop-class":
    cid = sys.argv[4]
    edit("docs/agents/classes.yml", lambda t: re.sub(r"- id: %s\n(  .*\n)*" % re.escape(cid), "", t))
elif mut == "rename-tag":
    for s in ("SKILL.md", "SKILL.es.md"):
        edit(".claude/skills/review-pr/" + s, lambda t: t.replace("[" + sys.argv[4] + "]", "[" + sys.argv[5] + "]"))
elif mut == "add-link":
    for s in ("SKILL.md", "SKILL.es.md"):
        edit(".claude/skills/review-pr/" + s, lambda t: t + "\nSee [architecture](../../../README.md) and [x] and [todo].\n")
elif mut == "drop-file":
    os.remove(os.path.join(dst, "docs/agents/classes.yml"))
subprocess.run(["git", "init", "-q", "-b", "main"], cwd=dst, check=True)
subprocess.run(["git", "add", "-A"], cwd=dst, check=True)
subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"], cwd=dst, check=True)
r = subprocess.run([sys.executable, "scripts/agents/check-docs.py"], cwd=dst, capture_output=True, text=True)
print("RC=%d" % r.returncode); print(r.stdout); print(r.stderr)
'

out=""
IDS="pr-metadata ci-claim undecided-decision test-cannot-fail stale-docs wrong-command text-code-mismatch uncovered-case unhandled-input"

# 1. classes.yml existe y trae las clases que hoy adivina bk learn, cada una con descripción.
for id in $IDS; do
  grep -q "^- id: $id\$" "$CLASES" 2>/dev/null; tap_check $? "classes.yml: trae la clase" "classes.yml: trae la clase $id"
done
n=$(awk '/^  description: ./ {n++} END {print n+0}' "$CLASES")
[ "$n" = 9 ]; tap_check $? "classes.yml: cada clase tiene una descripción"

# 2. review-pr (en y es) pide la clase al principio de cada hallazgo, con ids de classes.yml, y [other] si no encaja.
for par in "en:$SKILL_EN" "es:$SKILL_ES"; do
  lang=${par%%:*}; f=${par#*:}
  grep -q '\[stale-docs\]' "$f" 2>/dev/null; tap_check $? "review-pr: el ejemplo de hallazgo lleva la clase [stale-docs]" "review-pr ($lang): el ejemplo de hallazgo lleva la clase [stale-docs]"
  grep -q 'docs/agents/classes.yml' "$f" 2>/dev/null; tap_check $? "review-pr: remite a docs/agents/classes.yml" "review-pr ($lang): remite a docs/agents/classes.yml"
  grep -q '\[other\]' "$f" 2>/dev/null; tap_check $? "review-pr: usa [other] si ninguna clase encaja" "review-pr ($lang): usa [other] si ninguna clase encaja"
done

# 3. check-docs.py: los ids que nombra la skill existen en classes.yml.
tap_run out 0 python3 -c "$PY" "$RAIZ" "$TMP" none
grep -q '^RC=0$' <<<"$out"; tap_check $? "check-docs: el repo tal cual pasa con las clases de review-pr"
tap_run out 0 python3 -c "$PY" "$RAIZ" "$TMP" drop-class stale-docs
grep -q 'review-pr.*stale-docs.*classes.yml' <<<"$out"; tap_check $? "check-docs: falla si la skill nombra una clase que classes.yml no tiene"
tap_run out 0 python3 -c "$PY" "$RAIZ" "$TMP" rename-tag stale-docs made-up-class
grep -q 'review-pr.*made-up-class.*classes.yml' <<<"$out"; tap_check $? "check-docs: falla con un id inventado en la skill"
tap_run out 0 python3 -c "$PY" "$RAIZ" "$TMP" add-link
grep -q '^RC=0$' <<<"$out"; tap_check $? "check-docs: un enlace o un [x] de la skill no se toma por una clase"
tap_run out 0 python3 -c "$PY" "$RAIZ" "$TMP" drop-file
grep -q 'review-pr.*classes.yml.*missing' <<<"$out"; tap_check $? "check-docs: falla si la skill remite a un classes.yml que no existe"

tap_done
