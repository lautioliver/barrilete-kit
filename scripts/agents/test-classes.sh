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

# Los archivos del repo (commiteados y sin commitear, sin los ignorados) que existen: en un proyecto instalado el init borró
# algunos que git todavía lista, y tar fallaría con ellos.
COPIAR='
import os, shutil, subprocess, sys
src, dst = sys.argv[1:]
lista = subprocess.run(["git", "ls-files", "-z", "-co", "--exclude-standard"], cwd=src, capture_output=True, check=True).stdout
for rel in filter(None, lista.decode().split("\0")):
    de = os.path.join(src, rel)
    if os.path.lexists(de):
        a = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(a), exist_ok=True)
        shutil.copy2(de, a, follow_symlinks=False)
'

# Copia del repo con lo commiteado y lo que está en el working tree (la misma que test-agents.sh y test-i18n.sh).
copia() {
  rm -rf "$TMP/r"
  mkdir -p "$TMP/r"
  tap_run _ 0 python3 -c "$COPIAR" "$RAIZ" "$TMP/r"
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
 "crlf-bad-tag": lambda: (edit(YML, lambda t: t.replace("\n", " \r\n")), skills(lambda t: t.replace("[stale-docs]", "[made-up-class]"))),
 "upper-tag": lambda: skills(lambda t: t + "\n`[Stale-Doc] file:line: x`\n"),
 "snake-tag": lambda: skills(lambda t: t + "\n`[stale_doc] file:line: x`\n"),
 "spaced-id": lambda: skills(lambda t: t + "\n`[ made-up ] file:line: x`\n"),
 "bom-yml": lambda: edit(YML, lambda t: "\ufeff" + t),
 "bad-utf8": lambda: open(YML, "ab").write(b"# \xff\n"),
 "quoted-desc": lambda: edit(YML, lambda t: t.replace("description: a doc, skill", "description: \"a doc, skill")),
 "ref-link": lambda: skills(lambda t: t + "\n- [x] file:line: hecho, ver [texto][ref] y [ ] pendiente\n"),
 "bad-indent": lambda: edit(YML, lambda t: t.replace("  description: a doc, skill", "    description: a doc, skill")),
}
MUT[name]()
'

# check-docs.py sale con 1 cuando encuentra algo (su veredicto): un solo programa que lo corre y escribe su salida y `RC=<estado>`,
# así tap_run lo espera con 0 y un fallo del runner (no del check) corta la corrida.
RUN='
import subprocess, sys
r = subprocess.run([sys.executable, "scripts/agents/check-docs.py"], capture_output=True, text=True)
sys.stdout.write(r.stdout + r.stderr + "\nRC=%d\n" % r.returncode)
'

# Deshace la mutación anterior, aplica <nombre> y corre check-docs.py en la copia: su salida queda en $out y su estado en $RC.
# Con un tercer argumento (sin-resumen) no exige el resumen ni la ausencia de traceback: el caso mira eso él mismo.
mutar() {
  local nombre=$1
  out=""
  cd "$TMP/r" || return 1
  tap_run _ 0 git checkout -q -- .
  tap_run _ 0 python3 -c "$MUT" "$nombre"
  tap_run out 0 python3 -c "$RUN"
  RC=${out##*RC=}
  cd "$RAIZ" || return 1
  [ "${2:-}" = sin-resumen ] && return 0
  tap_no_traceback "$out"
  # Un check-docs que no llega al resumen (se cayó antes) no es un caso fallido: lo dice este caso, que en un rojo válido pasa.
  [[ $out == *"Docs OK."* || $out == *"Docs with "* ]]; tap_check $? "second marker: check-docs llegó al resumen"
}


# El idioma de un review-pr/SKILL*.md. Con `init --lang es` el SKILL.md instalado es el texto en español y no queda SKILL.es.md.
idioma_de() { if grep -q 'Bloqueante' "$1"; then echo es; else echo en; fi; }
INST="$TMP/instalado-es"
mkdir -p "$INST"
if [ -f "$SKILL_ES" ]; then cp "$SKILL_ES" "$INST/SKILL.md"; fi

# 1. classes.yml existe y trae las clases que hoy adivina bk learn, cada una con descripción.
total=$(awk '/^- id: / {n++} END {print n+0}' "$CLASES" 2>/dev/null)
n=$(awk '/^  description: ./ {n++} END {print n+0}' "$CLASES" 2>/dev/null)
grep -q '^- id: stale-docs$' "$CLASES" 2>/dev/null; tap_check $? "classes.yml: trae la clase stale-docs que usa el ejemplo de review-pr"
[ "$total" != 0 ]; tap_check $? "classes.yml: existe y lista al menos una clase"
[ "$n" = "$total" ]; tap_check $? "classes.yml: cada clase tiene una descripción"

# 2. review-pr (en y es) fija el formato de cada hallazgo: la clase al principio, una sola, y [other] si no encaja.
for f in "$SKILL_EN" "$SKILL_ES" "$INST/SKILL.md"; do
  if [ ! -f "$f" ]; then  # a project installed in a single language has no .es.md siblings (the copy below exists only if there is a SKILL.es.md)
    if [ "$f" = "$INST/SKILL.md" ]; then continue; fi
    tap_skip "review-pr: versión que no existe en este proyecto" "no existe $f"
    continue
  fi
  lang=$(idioma_de "$f")
  etiqueta=$lang; if [ "$f" = "$INST/SKILL.md" ]; then etiqueta="$lang, instalado con --lang es"; fi
  grep -q '\[stale-docs\]' "$f" 2>/dev/null; tap_check $? "review-pr: el ejemplo de hallazgo lleva la clase [stale-docs]" "review-pr ($etiqueta): el ejemplo de hallazgo lleva la clase [stale-docs]"
  grep -q 'docs/agents/classes.yml' "$f" 2>/dev/null; tap_check $? "review-pr: remite a docs/agents/classes.yml" "review-pr ($etiqueta): remite a docs/agents/classes.yml"
  grep -q '\[other\]' "$f" 2>/dev/null; tap_check $? "review-pr: usa [other] si ninguna clase encaja" "review-pr ($etiqueta): usa [other] si ninguna clase encaja"
  n=$(awk '/\*\*(file|archivo):(line|línea)\*\*/ {n++} END {print n+0}' "$f" 2>/dev/null)
  [ "$n" = 0 ]; tap_check $? "review-pr: el hallazgo no se describe con **file:line** en negrita" "review-pr ($etiqueta): el hallazgo no se describe con **file:line** en negrita"
  grep -q '`\[stale-docs\] file:line: …`' "$f" 2>/dev/null; tap_check $? "review-pr: el ejemplo usa file:line como el formato" "review-pr ($etiqueta): el ejemplo usa file:line como el formato"
  grep -q '`\[pr-metadata\] PR: …`' "$f" 2>/dev/null; tap_check $? "review-pr: dice qué ubicación poner si el hallazgo no tiene archivo" "review-pr ($etiqueta): dice qué ubicación poner si el hallazgo no tiene archivo"
  if [ "$lang" = en ]; then
    grep -q '`\[class\] file:line: …`' "$f" 2>/dev/null; tap_check $? "review-pr: fija el formato [clase] file:line: …" "review-pr ($etiqueta): fija el formato [class] file:line: …"
    grep -q 'one class per finding' "$f" 2>/dev/null; tap_check $? "review-pr: una sola clase por hallazgo" "review-pr ($etiqueta): una sola clase por hallazgo"
  else
    grep -q '`\[clase\] file:line: …`' "$f" 2>/dev/null; tap_check $? "review-pr: fija el formato [clase] file:line: …" "review-pr ($etiqueta): fija el formato [clase] file:line: …"
    grep -q 'una sola clase por hallazgo' "$f" 2>/dev/null; tap_check $? "review-pr: una sola clase por hallazgo" "review-pr ($etiqueta): una sola clase por hallazgo"
  fi
done

# Un proyecto instalado con --lang es: SKILL.md ya es el español y se reconoce por su contenido, no por su nombre.
if [ -f "$INST/SKILL.md" ]; then
  [ "$(idioma_de "$INST/SKILL.md")" = es ]; tap_check $? "review-pr: un SKILL.md en español (instalado con --lang es) se reconoce por su contenido"
else
  tap_skip "review-pr: un SKILL.md en español (instalado con --lang es) se reconoce por su contenido" "no hay $SKILL_ES"
fi

# Hay errores nuevos: check-docs salió con 1 y dijo algo que el repo tal cual no decía (un proyecto nuevo ya sale con 1 por los TODO del mapa).
con_errores_nuevos() {
  local nuevos
  nuevos=$(awk 'NR==FNR {a[$0]; next} !($0 in a)' "$TMP/base.out" - <<<"$out" 2>/dev/null)
  [ "$RC" -eq 1 ] && [ -n "$nuevos" ]
}

# 3. check-docs.py: los ids que nombra la skill existen en classes.yml, y classes.yml está bien formado.
# Cada caso mira el estado de salida de check-docs.py (0 el repo tal cual, 1 cada mutación) y lo que dice.
copia
# En un proyecto recién inicializado check-docs.py sale con 1 por los TODO del mapa (test-init.sh corre este test ahí):
# el repo tal cual sale con 0 o solo por eso, y un enlace de más no cambia ese estado.
mutar none
BASE_RC=$RC
printf '%s\n' "$out" >"$TMP/base.out"
[[ $BASE_RC -eq 0 || $out == *"replace the example paths"* ]]; tap_check $? "check-docs: el repo tal cual sale con 0 (o solo por los TODO del mapa de un proyecto nuevo)"
[[ $out != *"the class ["* && $out != *"classes.yml"* ]]; tap_check $? "check-docs: el repo tal cual no marca errores de clases en review-pr"
mutar drop-class
con_errores_nuevos; tap_check $? "check-docs: sale con 1 si la skill nombra una clase que classes.yml no tiene"
grep -q 'review-pr.*stale-docs.*classes.yml' <<<"$out"; tap_check $? "check-docs: dice qué clase de la skill falta en classes.yml"
mutar rename-tag
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un id inventado en la skill"
grep -q 'review-pr.*made-up-class.*classes.yml' <<<"$out"; tap_check $? "check-docs: dice qué id inventado hay en la skill"
mutar add-link
[ "$RC" -eq "$BASE_RC" ]; tap_check $? "check-docs: un enlace o un [x] de la skill no hace fallar el check"
[[ $out != *"the class ["* ]]; tap_check $? "check-docs: un enlace o un [x] de la skill no se toma por una clase"
mutar drop-file
con_errores_nuevos; tap_check $? "check-docs: sale con 1 si la skill remite a un classes.yml que no existe"
grep -q 'review-pr/SKILL.*missing path.*classes.yml' <<<"$out"; tap_check $? "check-docs: dice que falta classes.yml"
mutar bold-tag
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un [id] en negrita desconocido"
grep -q 'the class \[stale-doc\]' <<<"$out"; tap_check $? "check-docs: valida un [id] en negrita en una línea de hallazgo"
mutar bare-tag
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un [id] sin code span desconocido"
grep -q 'the class \[typo\]' <<<"$out"; tap_check $? "check-docs: valida un [id] sin code span en una línea de hallazgo"
mutar spaced-tag
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un [id] desconocido en code span con espacio"
grep -q 'the class \[typo\]' <<<"$out"; tap_check $? "check-docs: valida un [id] en code span con espacio previo"
mutar quoted-id
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un id entre comillas en classes.yml"
grep -q 'classes.yml:[0-9]*:.*unexpected' <<<"$out"; tap_check $? "check-docs: dice la línea del id entre comillas"
mutar dup-id
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un id duplicado en classes.yml"
grep -q 'classes.yml:[0-9]*:.*duplicate' <<<"$out"; tap_check $? "check-docs: dice la línea del id duplicado"
mutar no-desc
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con una clase sin descripción"
grep -q 'classes.yml:[0-9]*:.*description' <<<"$out"; tap_check $? "check-docs: dice qué clase no tiene descripción"
mutar other-listed
con_errores_nuevos; tap_check $? "check-docs: sale con 1 si classes.yml lista other"
grep -q 'classes.yml:[0-9]*:.*reserved' <<<"$out"; tap_check $? "check-docs: dice que other está reservada"
mutar bad-indent
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con otra indentación en classes.yml"
grep -q 'classes.yml:[0-9]*:.*unexpected' <<<"$out"; tap_check $? "check-docs: dice la línea con otra indentación"

mutar crlf-bad-tag
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un id inventado y classes.yml en CRLF"
grep -q 'review-pr.*made-up-class' <<<"$out"; tap_check $? "check-docs: con classes.yml en CRLF y con espacios al final sigue validando los ids de la skill"
[[ $out != *"classes.yml:"* ]]; tap_check $? "check-docs: espacios y CRLF al final de línea en classes.yml no se leen como línea inesperada"

# El id de hallazgo es cualquier [..] que no sea un enlace ni una casilla: mayúsculas, guion bajo o espacios no se cuelan.
mutar upper-tag
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un [Id] en mayúsculas en una línea de hallazgo"
grep -q 'the class \[Stale-Doc\]' <<<"$out"; tap_check $? "check-docs: dice qué [Id] en mayúsculas hay en la skill"
mutar snake-tag
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un [id_con_guion_bajo] en una línea de hallazgo"
grep -q 'the class \[stale_doc\]' <<<"$out"; tap_check $? "check-docs: dice qué [id_con_guion_bajo] hay en la skill"
mutar spaced-id
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un [ id ] con espacios en una línea de hallazgo"
grep -q 'the class \[ made-up \]' <<<"$out"; tap_check $? "check-docs: dice qué [ id ] con espacios hay en la skill"
mutar ref-link
[ "$RC" -eq "$BASE_RC" ]; tap_check $? "check-docs: una casilla [x] o un enlace [texto][ref] en una línea de hallazgo no hace fallar el check"
[[ $out != *"the class ["* ]]; tap_check $? "check-docs: una casilla [x] o un enlace [texto][ref] en una línea de hallazgo no se toma por una clase"

# Un classes.yml con BOM se lee, con un byte que no es UTF-8 falla con un mensaje, y una descripción entre comillas no pasa.
mutar bom-yml
[ "$RC" -eq "$BASE_RC" ]; tap_check $? "check-docs: un classes.yml con BOM no hace fallar el check"
[[ $out != *"classes.yml:"* ]]; tap_check $? "check-docs: un BOM al principio de classes.yml no se lee como línea inesperada"
mutar bad-utf8 sin-resumen
[[ $out != *"Traceback"* ]]; tap_check $? "check-docs: un byte que no es UTF-8 en classes.yml no da un traceback"
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con un byte que no es UTF-8 en classes.yml"
grep -q 'classes.yml.*UTF-8' <<<"$out"; tap_check $? "check-docs: dice que classes.yml no es UTF-8"
mutar quoted-desc
con_errores_nuevos; tap_check $? "check-docs: sale con 1 con una descripción entre comillas en classes.yml"
grep -q 'classes.yml:[0-9]*:.*unexpected' <<<"$out"; tap_check $? "check-docs: dice la línea de la descripción entre comillas"
[[ $out != *"has no description"* ]]; tap_check $? "check-docs: una descripción entre comillas es un error, no también una clase sin descripción"

# Una skill que remite a un classes.yml que falta da un solo error por skill (el de rutas rotas), no dos.
mutar drop-file
skills_en_copia=("$RAIZ"/.claude/skills/review-pr/SKILL*.md)
n=$(grep -c 'review-pr/SKILL.*classes.yml' <<<"$out")
[ "$n" -eq "${#skills_en_copia[@]}" ]; tap_check $? "check-docs: un classes.yml que falta da un solo error por skill, no uno repetido"

tap_done
