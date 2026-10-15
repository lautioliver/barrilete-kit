#!/usr/bin/env bash
# Tests de install.py de punta a punta: un repo existente con todos los choques (README, AGENTS.md,
# CLAUDE.md, settings.json con hooks propios, docs.yml propio, labels propios con un `gh` falso,
# .md con links rotos, .sh que no pasa shellcheck) y una plantilla local con dos versiones.
# Uso: bash scripts/test-install.sh
# shellcheck disable=SC2016  # los fixtures llevan $1 y backticks literales
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-install-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
unset BASE AGENT_KIT_TEMPLATE

# La plantilla tal como está en el árbol, con una versión etiquetada (v0.1.0).
P="$TMP/plantilla"
mkdir -p "$P"
(cd "$RAIZ" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf -) | (cd "$P" && tar -xf -)
(cd "$P" && git init -q -b main && echo 0.1.0 >VERSION && git add -A && git commit -qm v0.1.0 && git tag v0.1.0) >/dev/null 2>&1

# `gh` falso: solo `gh label list`, con los labels de $TMP/labels.json (o falla si no existe).
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "$1 $2" = "label list" ] && [ -f "$FAKE_LABELS" ] && { cat "$FAKE_LABELS"; exit 0; }
echo "gh: not logged in" >&2; exit 1
SH
chmod +x "$TMP/bin/gh"
export FAKE_LABELS="$TMP/labels.json"
cat >"$FAKE_LABELS" <<'JSON'
[
  {"name": "bug", "color": "d73a4a", "description": "Something isn't working"},
  {"name": "mi-label", "color": "00ff00", "description": "propio del proyecto"},
  {"name": "TYPE:Bug", "color": "123456", "description": "mayúsculas distintas"}
]
JSON

# Repo existente con todos los choques.
repo() { # repo <dir>
  local u=$1
  mkdir -p "$u" && cd "$u" || return 1
  git init -q -b main
  printf '# Mi app\n' >README.md
  printf 'MIT mía\n' >LICENSE
  printf 'node_modules\n.env\n' >.gitignore
  printf '# Reglas de mi app\n\nusar tabs\n' >AGENTS.md
  printf '# Claude de mi app\n\nregla propia\n' >CLAUDE.md
  mkdir -p .claude .github/workflows .github/ISSUE_TEMPLATE docs notas src
  cat >.claude/settings.json <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo mi-hook"}]}
    ],
    "PostToolUse": [
      {"matcher": "Edit", "hooks": [{"type": "command", "command": "echo post"}]}
    ]
  },
  "model": "sonnet"
}
JSON
  printf 'name: CI propio\non: push\njobs: {}\n' >.github/workflows/docs.yml
  printf 'name: Otro\non: push\njobs: {}\n' >.github/workflows/ci.yml
  printf 'mi plantilla de PR\n' >.github/pull_request_template.md
  printf 'blank_issues_enabled: true\n' >.github/ISSUE_TEMPLATE/config.yml
  printf '# Docs de mi app\n' >docs/README.md
  printf '# Guía\n\n[roto](nada.md)\n' >docs/guia.md
  printf '# Roto\n\n[no existe](nada.md)\n' >notas/roto.md
  printf '# Notas\n\n[tampoco](../otra.md) y `src/falta.sh`\n' >NOTAS.md
  printf '#!/bin/bash\nrm $1\n' >src/borrar.sh
  printf '#!/bin/bash\necho "falla a propósito"; exit 1\n' >src/test-propio.sh
  git add -A && git commit -qm "repo existente"
}
U="$TMP/usuario"
(repo "$U") >/dev/null 2>&1
HEAD0=$(git -C "$U" rev-parse HEAD)
instalar() { (cd "$U" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" "$@" 2>&1); }

# --- Rechazos: no escriben nada. ---
echo sucio >>"$U/README.md"
s=$(instalar Demo main --template "$P"); c=$?
[ "$c" -ne 0 ] && grep -qi "uncommitted" <<<"$s" && ! [ -e "$U/.agent-kit.json" ]
afirmar $? "no instala con cambios sin commitear"
git -C "$U" checkout -q README.md

s=$(instalar Demo main --template "$P" --opcion-rara); c=$?
[ "$c" -ne 0 ] && grep -qi "unknown option" <<<"$s" && es -z "$(git -C "$U" status --porcelain)"
afirmar $? "una opción desconocida falla (para pasarle opciones al init va después de --)"

mv "$FAKE_LABELS" "$FAKE_LABELS.off"
s=$(instalar Demo main --template "$P"); c=$?
[ "$c" -ne 0 ] && grep -qi "label" <<<"$s" && es -z "$(git -C "$U" status --porcelain)"
afirmar $? "si no puede leer los labels del repo (gh falla) no instala: el sync los borraría"
mv "$FAKE_LABELS.off" "$FAKE_LABELS"

# --- --draft: muestra el plan y no escribe. ---
s=$(instalar Demo main --template "$P" --draft); c=$?
es "$c" -eq 0 && es -z "$(git -C "$U" status --porcelain)" && ! [ -e "$U/.agent-kit" ] && ! [ -e "$U/.agent-kit.json" ]
afirmar $? "--draft no escribe nada"
grep -q 'barrilete-docs.yml' <<<"$s" && grep -q 'AGENTS.md' <<<"$s"
afirmar $? "--draft muestra el plan (el workflow renombrado y lo que queda pendiente)"

# --- Instalación. ---
s=$(instalar Demo main --template "$P"); c=$?
es "$c" -eq 0; afirmar $? "instala en un repo existente (salida: $(tail -1 <<<"$s"))"
es "$(git -C "$U" rev-parse HEAD)" = "$HEAD0"; afirmar $? "no commitea"
es "$(cat "$U/README.md")" = "# Mi app" && es "$(cat "$U/LICENSE")" = "MIT mía"
afirmar $? "README y LICENSE quedan como estaban"
es "$(cat "$U/AGENTS.md")" = "$(printf '# Reglas de mi app\n\nusar tabs')"; afirmar $? "AGENTS.md del proyecto no se toca"
for f in AGENTS.md docs/README.md .github/pull_request_template.md .github/ISSUE_TEMPLATE/config.yml; do
  es -f "$U/.agent-kit/pending/$f" && ! cmp -s "$U/$f" "$U/.agent-kit/pending/$f"
  afirmar $? "la versión del kit de $f queda en .agent-kit/pending/ y la del proyecto no se toca"
done
grep -q 'blank_issues_enabled: true' "$U/.github/ISSUE_TEMPLATE/config.yml" && grep -q 'mi plantilla de PR' "$U/.github/pull_request_template.md"
afirmar $? "la plantilla de PR y config.yml del proyecto siguen siendo las suyas"
grep -q 'AGENTS.md' <<<"$s" && grep -q '.agent-kit/pending' <<<"$s"
afirmar $? "el resumen dice qué quedó pendiente de integrar"

grep -qi 'just before merging' <<<"$s" && grep -q 'labels.py' <<<"$s"
afirmar $? "el resumen dice que hay que volver a correr labels.py justo antes de mergear (los labels creados en el medio)"

# .gitignore y CLAUDE.md.
es "$(grep -cxF '.env' "$U/.gitignore")" = 1 && grep -qxF 'node_modules' "$U/.gitignore" \
  && grep -qxF '# barrilete' "$U/.gitignore" && grep -qxF '.agent-kit/' "$U/.gitignore" && grep -qxF '__pycache__' "$U/.gitignore"
afirmar $? ".gitignore conserva lo suyo y agrega solo lo que falta en un bloque # barrilete"
grep -q 'regla propia' "$U/CLAUDE.md" && grep -qx '@AGENTS.md' "$U/CLAUDE.md"
afirmar $? "CLAUDE.md conserva lo suyo y agrega @AGENTS.md"

# settings.json: fusión JSON.
python3 - "$U/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
pre = s["hooks"]["PreToolUse"]
cmds = [h["command"] for g in pre for h in g["hooks"]]
assert "echo mi-hook" in cmds, cmds
assert sum("guardrails.py" in c for c in cmds) == 1, cmds
assert s["hooks"]["PostToolUse"][0]["hooks"][0]["command"] == "echo post"
assert s["model"] == "sonnet"
PY
afirmar $? "settings.json conserva sus hooks y su configuración, y agrega el hook de guardrails una vez"

# Workflows.
grep -q 'CI propio' "$U/.github/workflows/docs.yml" && grep -q 'Docs' "$U/.github/workflows/barrilete-docs.yml" \
  && es -f "$U/.github/workflows/ci.yml"
afirmar $? "el docs.yml propio no se pisa: el del kit va como barrilete-docs.yml"
es -f "$U/.github/workflows/labels.yml" && ! [ -e "$U/.github/workflows/barrilete-labels.yml" ]
afirmar $? "un workflow que no choca conserva su nombre"

# Labels.
python3 - "$U/.github/labels.yml" <<'PY'
import re, sys
nombres = re.findall(r'^- name:\s*"?(.*?)"?\s*$', open(sys.argv[1], encoding="utf-8").read(), re.M)
bajos = [n.lower() for n in nombres]
assert len(bajos) == len(set(bajos)), "repetidos: %s" % nombres
assert "mi-label" in nombres and "bug" in nombres and "type:bug" in bajos, nombres
PY
afirmar $? "labels.yml = labels del kit + los del repo, sin repetir (ni por mayúsculas)"
grep -q 'mi-label' <<<"$s" && grep -qi 'github default\|default' <<<"$s"
afirmar $? "el resumen cuenta los labels del repo que conservó (y avisa de los por defecto de GitHub)"

# .agent-kit.json: solo lo del kit.
python3 - "$U" <<'PY'
import json, sys
u = sys.argv[1]
k = json.load(open(u + "/.agent-kit.json"))
f = k["files"]
for propio in ("README.md", "LICENSE", "NOTAS.md", "notas/roto.md", "src/borrar.sh", "src/test-propio.sh",
               "AGENTS.md", "CLAUDE.md", ".gitignore", ".claude/settings.json", ".github/workflows/docs.yml",
               ".github/workflows/ci.yml", "docs/README.md", ".github/pull_request_template.md",
               ".github/labels.yml"):
    assert propio not in f, propio + " no es del kit"
for kit in (".github/workflows/barrilete-docs.yml", ".claude/skills/debug/SKILL.md", "scripts/agents/check-docs.py"):
    assert kit in f, kit
assert k["project"] == "Demo" and k["base_branch"] == "main" and k["version"] == "0.1.0", k
assert k["renames"] == {".github/workflows/docs.yml": ".github/workflows/barrilete-docs.yml"}, k.get("renames")
PY
afirmar $? ".agent-kit.json tiene solo los archivos del kit, con los renombres"
! [ -e "$U/scripts/install.py" ] && ! [ -e "$U/scripts/test-install.sh" ] && ! [ -e "$U/scripts/init-template.sh" ]
afirmar $? "no instala el instalador ni el init (son de la plantilla)"

# El CI del kit pasa con el código del usuario (con lo instalado ya commiteado: los scripts miran `git ls-files`).
(cd "$U" \
  && git add -A && git commit -qm "instala barrilete") >/dev/null 2>&1
s2=$(cd "$U" && python3 scripts/agents/check-docs.py 2>&1); c=$?
# Con el mapa de ejemplo (TODO) el check falla a propósito hasta que el proyecto lo completa: lo que no
# puede fallar son los .md del usuario, ni las rutas del kit que acaba de instalar.
! grep -q 'roto.md\|NOTAS.md\|guia.md' <<<"$s2" && ! grep -q 'Traceback\|matches no file\|broken link\|missing path' <<<"$s2"
afirmar $? "en un repo instalado check-docs.py no revisa los .md del usuario (NOTAS.md, docs/guia.md) y no marca rutas ni links rotos del kit"
lista=$(cd "$U" && python3 scripts/agents/check-docs.py --list '*.sh')
! grep -q '^src/' <<<"$lista" && grep -q 'scripts/agents/test-base.sh' <<<"$lista"
afirmar $? "la lista de scripts del CI no incluye los .sh del usuario"
lista=$(cd "$U" && python3 scripts/agents/check-docs.py --list '*test-*.sh')
! grep -q 'src/test-propio.sh' <<<"$lista"; afirmar $? "el CI no corre los test-*.sh del usuario"
(cd "$U" && python3 scripts/agents/check-docs.py --list '*.sh' | xargs shellcheck) >/dev/null 2>&1
afirmar $? "shellcheck pasa sobre los scripts del kit instalados"

# Reinstalar: se frena (ya hay .agent-kit.json).
s=$(instalar Demo main --template "$P"); c=$?
[ "$c" -ne 0 ] && grep -q 'update.py' <<<"$s"; afirmar $? "en un repo ya instalado falla y apunta a update.py"

# update.py después de instalar: respeta los renombres y no pisa lo del usuario.
(
  cd "$P" && echo 0.2.0 >VERSION && echo "# cambio de la plantilla v0.2" >>.github/workflows/docs.yml \
    && echo "Línea nueva v0.2." >>.claude/skills/debug/SKILL.md && git add -A && git commit -qm v0.2.0 && git tag v0.2.0
) >/dev/null 2>&1
rm -rf "$U/.agent-kit/pending"
s=$(cd "$U" && python3 scripts/update.py --template "$P" 2>&1); c=$?
es "$c" -eq 0; afirmar $? "update.py funciona después de instalar (salida: $(tail -1 <<<"$s"))"
grep -q 'cambio de la plantilla v0.2' "$U/.github/workflows/barrilete-docs.yml" && grep -q 'CI propio' "$U/.github/workflows/docs.yml" \
  && ! grep -q 'cambio de la plantilla' "$U/.github/workflows/docs.yml"
afirmar $? "update.py actualiza barrilete-docs.yml y no toca el docs.yml del usuario"
grep -q 'Línea nueva v0.2.' "$U/.claude/skills/debug/SKILL.md" && es "$(head -1 "$U/AGENTS.md")" = "# Reglas de mi app"
afirmar $? "update.py trae lo nuevo del kit y deja el AGENTS.md del usuario"

# Opciones para el init, después de --: se las pasa sin conocerlas (--small, y --lang cuando se mergee #113).
# Una plantilla sin tags (el instalador usa la rama por defecto): no hay base para update.py, así que no registra versión.
P2="$TMP/plantilla-sin-tags"
git clone -q --no-tags "$P" "$P2" >/dev/null 2>&1
U2="$TMP/usuario-chico"
(repo "$U2") >/dev/null 2>&1
s=$(cd "$U2" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "$P2" -- --small 2>&1); c=$?
es "$c" -eq 0 && grep -q '"mode": "small"' "$U2/.agent-kit.json"
afirmar $? "lo que va después de -- llega al init (--small deja mode small)"
grep -q '"version": null' "$U2/.agent-kit.json"
afirmar $? "instalado desde la rama por defecto (sin tag) no registra una versión que no es la suya"
# grow.py también aplica los renombres: no deja el docs.yml del kit en pending ni toca el del usuario.
(cd "$U2" && rm -rf .agent-kit/pending && git add -A && git commit -qm "instala barrilete chico") >/dev/null 2>&1
s=$(cd "$U2" && python3 scripts/grow.py --template "$P2" 2>&1); c=$?
es "$c" -eq 0 && ! [ -e "$U2/.agent-kit/pending/.github/workflows/docs.yml" ] && grep -q 'CI propio' "$U2/.github/workflows/docs.yml"
afirmar $? "grow.py respeta los renombres del instalador (el docs.yml del kit no va a pending)"
s=$(cd "$U2" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "$P" -- --nada 2>&1); c=$?
es "$c" -ne 0; afirmar $? "una opción que el init rechaza hace fallar la instalación"

# Casos borde (revisión): un archivo donde el kit espera una carpeta, un workflow con la otra extensión,
# un labels.yml propio, un hook de barandas que ya está con otro comando, y la rama base inválida.
U3="$TMP/usuario-borde"
(
  repo "$U3" && printf 'no soy una carpeta\n' >scripts-ejemplo && mv scripts-ejemplo scripts
  cat >.claude/settings.json <<'JSON'
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "python3 scripts/agents/guardrails.py", "timeout": 5}]}]}}
JSON
  printf 'name: Labels propio\non: push\njobs: {}\n' >.github/workflows/unblock.yaml
  mkdir -p .github && printf -- '- name: "solo-mio"\n  color: "ABCDEF"\n  description: ""\n' >.github/labels.yml
  git add -A && git commit -qm borde
) >/dev/null 2>&1
s=$(cd "$U3" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "$P" 2>&1); c=$?
es "$c" -eq 0 && es -f "$U3/.agent-kit.json"; afirmar $? "[borde] un archivo donde el kit espera una carpeta no deja la instalación a medias (salida: $(tail -1 <<<"$s"))"
es "$(cat "$U3/scripts")" = "no soy una carpeta" && es -f "$U3/.agent-kit/pending/scripts/update.py"
afirmar $? "[borde] lo que no cabe queda en .agent-kit/pending/ y el archivo del proyecto no se toca"
es -f "$U3/.github/workflows/barrilete-unblock.yml" && es -f "$U3/.github/workflows/unblock.yaml" && ! [ -e "$U3/.github/workflows/unblock.yml" ]
afirmar $? "[borde] un workflow con la otra extensión (.yaml) cuenta como el mismo nombre"
es "$(grep -c 'solo-mio' "$U3/.github/labels.yml")" = 1 && grep -q 'mi-label' "$U3/.agent-kit/pending/.github/labels.yml" \
  && grep -q 'labels.yml' <<<"$s" && grep -qi 'before the first sync' <<<"$s"
afirmar $? "[borde] con un labels.yml propio, el combinado queda en pending y el resumen avisa que hay que integrarlo antes del primer sync"
es "$(grep -c 'guardrails.py' "$U3/.claude/settings.json")" = 1
afirmar $? "[borde] el hook de barandas que ya estaba (con otro comando) no se duplica"
! [ -e "$U3/.github/workflows/labels.yml" ] && ! [ -e "$U3/.github/workflows/barrilete-labels.yml" ] \
  && es -f "$U3/.agent-kit/pending/.github/workflows/labels.yml" && grep -qi 'not installed' <<<"$s"
afirmar $? "[borde] con un labels.yml propio el workflow de sync (delete-other-labels) no se instala activo: va a pending y el resumen lo explica"
# LICENSE: un proyecto sin LICENSE no recibe la del kit en el siguiente update.
U5="$TMP/usuario-sin-licencia"
(repo "$U5" && git rm -q LICENSE && git commit -qm "sin licencia") >/dev/null 2>&1
s=$(cd "$U5" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "$P" 2>&1); c=$?
(cd "$U5" && rm -rf .agent-kit/pending && git add -A && git commit -qm instala) >/dev/null 2>&1
(cd "$P" && echo 0.3.0 >VERSION && echo "# v0.3" >>.claude/skills/debug/SKILL.md && git add -A && git commit -qm v0.3.0 && git tag v0.3.0) >/dev/null 2>&1
s=$(cd "$U5" && python3 scripts/update.py --template "$P" 2>&1); c2=$?
es "$c" -eq 0 && es "$c2" -eq 0 && ! [ -e "$U5/LICENSE" ]
afirmar $? "update.py no agrega el LICENSE del kit a un proyecto instalado que no lo tenía"
# CLAUDE.md como symlink a AGENTS.md: no se escribe a través del link.
U6="$TMP/usuario-symlink"
(repo "$U6" && rm CLAUDE.md && ln -s AGENTS.md CLAUDE.md && git add -A && git commit -qm link) >/dev/null 2>&1
s=$(cd "$U6" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "$P" 2>&1); c=$?
es "$c" -eq 0 && [ -L "$U6/CLAUDE.md" ] && ! grep -q '@AGENTS.md' "$U6/AGENTS.md" && grep -qi 'symlink' <<<"$s"
afirmar $? "CLAUDE.md symlink: no se escribe a través del link y el resumen lo avisa"
# .github es un archivo: la instalación no queda a medias (también para labels.yml).
U7="$TMP/usuario-github-archivo"
(mkdir -p "$U7" && cd "$U7" && git init -q -b main && echo x >.github && echo hi >a.txt && git add -A && git commit -qm x) >/dev/null 2>&1
s=$(cd "$U7" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "$P" 2>&1); c=$?
es "$c" -eq 0 && es -f "$U7/.agent-kit.json" && es "$(cat "$U7/.github")" = x
afirmar $? "[borde] .github como archivo no deja la instalación a medias (salida: $(tail -1 <<<"$s"))"
U4="$TMP/usuario-base"
(repo "$U4") >/dev/null 2>&1
s=$(cd "$U4" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo releases --template "$P" 2>&1); c=$?
es "$c" -ne 0 && grep -qi "base branch" <<<"$s" && es -z "$(git -C "$U4" status --porcelain)"
afirmar $? "[borde] una rama base que no es main ni develop falla antes de tocar nada"
s=$(cd "$U4" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "--upload-pack=touch $TMP/inyectado" 2>&1); c=$?
es "$c" -ne 0 && ! [ -e "$TMP/inyectado" ]; afirmar $? "[borde] un --template que empieza con - no se toma como opción de git"

# Fuera de un repo git, o dentro de la plantilla: error claro.
mkdir -p "$TMP/vacio"
s=$(cd "$TMP/vacio" && PATH="$TMP/bin:$PATH" python3 "$RAIZ/scripts/install.py" Demo main --template "$P" 2>&1); c=$?
[ "$c" -ne 0 ] && grep -qi "git repo" <<<"$s"; afirmar $? "fuera de un repo git falla con un mensaje claro"

if [ "$fallas" -eq 0 ]; then echo "Todos los tests pasan."; else echo "$fallas fallas."; exit 1; fi
