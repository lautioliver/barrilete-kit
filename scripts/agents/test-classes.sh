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

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

# Copia del repo con lo commiteado y lo que está en el working tree (la misma que test-agents.sh y test-i18n.sh).
copia() {
  rm -rf "$TMP/r" || true
  mkdir -p "$TMP/r"
  (cd "$RAIZ" && git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null || true) | tar -xf - -C "$TMP/r"
  (cd "$TMP/r" && git init -q && git add -A && git commit -qm base)
}

# Una mutación por nombre, aplicada in situ sobre la copia (el directorio actual): un solo programa, sin shell.
MUT='
import os, re, sys
name = sys.argv[1]
YML = "docs/agents/classes.yml"
SK = [".claude/skills/review-pr/SKILL.md", ".claude/skills/review-pr/SKILL.es.md"]
def edit(path, fn):
    if os.path.exists(path):
        t = open(path, encoding="utf-8").read(); open(path, "w", encoding="utf-8").write(fn(t))
def skills(fn):
    for s in SK: edit(s, fn)
MUT = {
 "none": lambda: None,
 "drop-class": lambda: edit(YML, lambda t: re.sub(r"- id: stale-docs\n(  .*\n)*", "", t)),
 "rename-tag": lambda: skills(lambda t: t.replace("[stale-docs]", "[made-up-class]")),
 "add-link": lambda: skills(lambda t: t + "\nSee [architecture](../../../README.md) and [x] and [todo].\n"),
 "drop-file": lambda: os.remove(YML),
 "bold-tag": lambda: skills(lambda t: t + "\n**[stale-doc]** file:line: x\n"),
 "bare-tag": lambda: skills(lambda t: t + "\n[typo] file:line: x\n"),
 "spaced-tag": lambda: skills(lambda t: t + "\n` [typo] file:line: x`\n"),
 "quoted-id": lambda: edit(YML, lambda t: t.replace("- id: stale-docs", "- id: \"stale-docs\"")),
 "dup-id": lambda: edit(YML, lambda t: t + "- id: stale-docs\n  description: again\n"),
 "no-desc": lambda: edit(YML, lambda t: re.sub(r"(- id: stale-docs\n)  description: .*\n", r"\1", t)),
 "other-listed": lambda: edit(YML, lambda t: t + "- id: other\n  description: reserved\n"),
 "bad-indent": lambda: edit(YML, lambda t: t.replace("  description: a doc, skill", "    description: a doc, skill")),
}
MUT[name]()
'

# Deshace la mutación anterior, aplica <nombre> y corre check-docs.py en la copia: su salida queda en $out y su
# estado en $TAP_RC. Con <esperado> 0 el repo tal cual tiene que pasar; con 1, la mutación tiene que hacerlo fallar.
mutar() {
  local nombre=$1 esperado=$2
  out=""
  cd "$TMP/r" || return 1
  tap_run _ 0 git checkout -q -- .
  tap_run _ 0 python3 -c "$MUT" "$nombre"
  tap_run out "$esperado" python3 scripts/agents/check-docs.py
  tap_no_traceback "$out"
  cd "$RAIZ" || return 1
}


# 1. classes.yml existe y trae las clases que hoy adivina bk learn, cada una con descripción.
total=$(grep -c '^- id: ' "$CLASES" 2>/dev/null || true)
n=$(awk '/^  description: ./ {n++} END {print n+0}' "$CLASES" 2>/dev/null || true)
grep -q '^- id: stale-docs$' "$CLASES" 2>/dev/null; tap_check $? "classes.yml: trae la clase stale-docs que usa el ejemplo de review-pr"
[ "$total" != 0 ]; tap_check $? "classes.yml: existe y lista al menos una clase"
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
# Cada caso mira el estado de salida de check-docs.py (0 el repo tal cual, 1 cada mutación) y lo que dice.
copia
mutar none 0
[ "$TAP_RC" -eq 0 ]; tap_check $? "check-docs: el repo tal cual sale con 0"
[[ $out != *"the class ["* && $out != *"classes.yml"* ]]; tap_check $? "check-docs: el repo tal cual no marca errores de clases en review-pr"
mutar drop-class 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 si la skill nombra una clase que classes.yml no tiene"
grep -q 'review-pr.*stale-docs.*classes.yml' <<<"$out"; tap_check $? "check-docs: dice qué clase de la skill falta en classes.yml"
mutar rename-tag 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con un id inventado en la skill"
grep -q 'review-pr.*made-up-class.*classes.yml' <<<"$out"; tap_check $? "check-docs: dice qué id inventado hay en la skill"
mutar add-link 0
[ "$TAP_RC" -eq 0 ]; tap_check $? "check-docs: un enlace o un [x] de la skill no hace fallar el check"
[[ $out != *"the class ["* ]]; tap_check $? "check-docs: un enlace o un [x] de la skill no se toma por una clase"
mutar drop-file 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 si la skill remite a un classes.yml que no existe"
grep -q 'review-pr.*classes.yml.*missing' <<<"$out"; tap_check $? "check-docs: dice que falta classes.yml"
mutar bold-tag 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con un [id] en negrita desconocido"
grep -q 'the class \[stale-doc\]' <<<"$out"; tap_check $? "check-docs: valida un [id] en negrita en una línea de hallazgo"
mutar bare-tag 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con un [id] sin code span desconocido"
grep -q 'the class \[typo\]' <<<"$out"; tap_check $? "check-docs: valida un [id] sin code span en una línea de hallazgo"
mutar spaced-tag 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con un [id] desconocido en code span con espacio"
grep -q 'the class \[typo\]' <<<"$out"; tap_check $? "check-docs: valida un [id] en code span con espacio previo"
mutar quoted-id 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con un id entre comillas en classes.yml"
grep -q 'classes.yml:[0-9]*:.*unexpected' <<<"$out"; tap_check $? "check-docs: dice la línea del id entre comillas"
mutar dup-id 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con un id duplicado en classes.yml"
grep -q 'classes.yml:[0-9]*:.*duplicate' <<<"$out"; tap_check $? "check-docs: dice la línea del id duplicado"
mutar no-desc 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con una clase sin descripción"
grep -q 'classes.yml:[0-9]*:.*description' <<<"$out"; tap_check $? "check-docs: dice qué clase no tiene descripción"
mutar other-listed 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 si classes.yml lista other"
grep -q 'classes.yml:[0-9]*:.*reserved' <<<"$out"; tap_check $? "check-docs: dice que other está reservada"
mutar bad-indent 1
[ "$TAP_RC" -eq 1 ]; tap_check $? "check-docs: sale con 1 con otra indentación en classes.yml"
grep -q 'classes.yml:[0-9]*:.*unexpected' <<<"$out"; tap_check $? "check-docs: dice la línea con otra indentación"

tap_done
