#!/usr/bin/env bash
# Tests de la rama base sin configurar (<BASE_BRANCH> en la plantilla sin inicializar):
# agents_map.py, verify.py y prepare.sh usan la rama por defecto del remoto y avisan.
# Uso: bash scripts/agents/test-base.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-base-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
# Uso: <condición>; tap_check $? "descripción"
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
unset BASE
# Solo aplica a la plantilla sin inicializar: el init reemplaza el primer marcador por la rama base.
# shellcheck disable=SC2050  # la comparación es constante hasta que el init la cambia
if [ "<BASE_BRANCH>" != "<BASE_""BRANCH>" ]; then tap_skip_all "La rama base ya está configurada: estos tests no aplican."; fi

# Remoto cuya rama por defecto es "trunk" (para no confundirla con un "main" fijo).
git init -q --bare "$TMP/remoto.git"; git -C "$TMP/remoto.git" symbolic-ref HEAD refs/heads/trunk
git clone -q "$TMP/remoto.git" "$TMP/p" 2>/dev/null
mkdir -p "$TMP/p/scripts" "$TMP/p/docs"
cp -R "$RAIZ/scripts/agents" "$TMP/p/scripts/"
printf '{"docs": [], "sensitive": [], "verify": [{"name": "eco", "always": true, "run": "echo {base}"}]}\n' >"$TMP/p/docs/agents-map.json"
(cd "$TMP/p" && git switch -q -c trunk && git add -A && git commit -qm base && git push -q origin trunk 2>/dev/null \
  && git remote set-head origin trunk && git switch -q -c claude/1-algo && echo x >nuevo.txt && git add nuevo.txt && git commit -qm x)

c=0; s=$(trap - ERR; cd "$TMP/p" && python3 scripts/agents/agents_map.py 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "agents_map.py sin BASE en la plantilla sin inicializar termina bien"
grep -q "nuevo.txt\|Changed files: 1" <<<"$s"; tap_check $? "agents_map.py compara contra la rama por defecto del remoto"
grep -qi "warning.*trunk" <<<"$s"; tap_check $? "agents_map.py avisa qué base usó"

c=0; s=$(trap - ERR; cd "$TMP/p" && python3 scripts/agents/verify.py --list 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "verify.py sin BASE termina bien"
grep -q "against origin/trunk" <<<"$s"; tap_check $? "verify.py usa origin/<rama por defecto>"

# Sin origin/HEAD local: la pide al remoto.
(cd "$TMP/p" && git remote set-head origin -d)
c=0; s=$(trap - ERR; cd "$TMP/p" && python3 scripts/agents/agents_map.py 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "sin origin/HEAD local, la pide al remoto"

# Con BASE explícita, no cambia nada.
s=$(cd "$TMP/p" && BASE=trunk python3 scripts/agents/agents_map.py 2>&1)
! grep -qi "warning" <<<"$s"; tap_check $? "con BASE explícita no avisa"

# Nombres con espacios, tildes o ñ: llegan literales (sin comillas ni escapes), commiteados o no,
# y un renombre aparece una sola vez, con el nombre nuevo.
(cd "$TMP/p" && git switch -q trunk && echo r >"viejo nombre.txt" && git add -A && git commit -qm viejo \
  && git push -q origin trunk 2>/dev/null && git switch -q -c claude/2-nombres \
  && echo a >"a b.txt" && echo g >"guía.md" && git add -A && git commit -qm nombres \
  && echo c >"c d.txt" && git add "c d.txt" && echo s >"señal.md" && git mv "viejo nombre.txt" "nuevo ñ.txt")
s=$(cd "$TMP/p" && python3 -c 'import sys; sys.path.insert(0, "scripts/agents"); from agents_map import archivos_cambiados
print("\n".join(archivos_cambiados(["--base", "trunk"])))' 2>&1)
esperado=$(printf '%s\n' "a b.txt" "c d.txt" "guía.md" "nuevo ñ.txt" "señal.md")
es "$s" = "$esperado"; tap_check $? "archivos_cambiados devuelve los nombres literales y el renombre una vez"
[ "$s" = "$esperado" ] || printf '       %s\n' "$s" >&2

# Un archivo dentro de una carpeta nueva sin trackear aparece con su ruta, no solo la carpeta.
(cd "$TMP/p" && mkdir -p "carpeta nueva/sub" && echo x >"carpeta nueva/sub/a.txt")
s=$(cd "$TMP/p" && python3 -c 'import sys; sys.path.insert(0, "scripts/agents"); from agents_map import archivos_cambiados
print("\n".join(archivos_cambiados(["--base", "trunk"])))' 2>&1)
grep -qx "carpeta nueva/sub/a.txt" <<<"$s" && ! grep -q '/$' <<<"$s"; tap_check $? "archivos_cambiados lista los archivos de una carpeta nueva sin trackear"

# Un archivo que el cambio borra no llega a {files} (#274): no se puede verificar, y shellcheck falla con
# "does not exist". Una regla con {files} que solo tocó archivos borrados no corre (sin archivos, shellcheck sale con 3);
# una sin {files} sigue corriendo.
# shellcheck disable=SC2164  # si cd falla, la trampa ERR de tap.sh corta la corrida
cd "$TMP/p"
# El bloque anterior deja un renombre y archivos sin trackear: se descartan para que no entren a trunk.
git reset -q --hard
git clean -qfd
git switch -q trunk
cat >docs/agents-map.json <<'JSON'
{"docs": [], "sensitive": [], "verify": [
  {"name": "con-files", "when": ["**/*.sh"], "run": "for f in {files}; do [ -e \"$f\" ] || echo \"FALTA\"\"-$f\"; done; echo \"VISTOS:[\"{files}\"]\""},
  {"name": "sin-files", "when": ["**/*.sh"], "run": "echo SIN-FILES"},
  {"name": "siempre-files", "always": true, "when": ["**/*.sh"], "run": "echo \"SIEMPRE:[\"{files}\"]\""},
  {"name": "siempre-sin-when", "always": true, "run": "echo \"SSW:[\"{files}\"]\""},
  {"name": "pendiente", "always": true, "run": "TODO: los tests de {files}"}
]}
JSON
echo 'echo v' >viejo.sh
echo 'echo q' >queda.sh
echo 'echo s' >solo.sh
git add -A
git commit -qm sh
git push -q origin trunk 2>/dev/null
git switch -q -c claude/3-borra
git rm -q viejo.sh
echo 'echo q2' >queda.sh
git commit -qam borra
tap_run s 0 python3 scripts/agents/verify.py
tap_no_traceback "$s"
[[ $s == *"VISTOS:[queda.sh]"* ]]; tap_check $? "verify: {files} no lleva el archivo borrado" "$s"
[[ $s != *FALTA-* ]]; tap_check $? "verify: la regla con {files} no recibe un archivo que no existe" "$s"
[[ $s == *"SSW:[queda.sh]"* ]]; tap_check $? "verify: una regla always sin when recibe en {files} solo los que existen" "$s"
git switch -q trunk
git switch -q -c claude/4-solo-borra
git rm -q solo.sh
git commit -qm solo
tap_run s 0 python3 scripts/agents/verify.py --list
tap_no_traceback "$s"
[[ $s != *"- con-files"* ]]; tap_check $? "verify: una regla con {files} que solo tocó borrados no corre" "$s"
[[ $s == *"- sin-files"* ]]; tap_check $? "verify: una regla sin {files} corre aunque el archivo esté borrado"
[[ $s == *"con-files (only deleted files matched: solo.sh)"* ]]; tap_check $? "verify: avisa qué regla no corre porque solo tocó borrados" "$s"
[[ $s != *"- siempre-files"* ]]; tap_check $? "verify: una regla always con {files} que solo tocó borrados tampoco corre" "$s"
[[ $s == *"Skipped: siempre-sin-when (only deleted files matched: solo.sh)"* ]]; tap_check $? "verify: una regla always sin when con {files} que solo tocó borrados no corre" "$s"
[[ $s == *"- pendiente (always)"* ]]; tap_check $? "verify: una regla TODO con {files} no se saltea: sigue saliendo como no configurada" "$s"
# Con --pr los archivos son los del PR, que pueden no estar en este checkout: no se filtran (un gh falso los da).
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nprintf "%%s\\n" nuevo-del-pr.sh\n' >"$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
tap_run s 0 env PATH="$TMP/bin:$PATH" python3 scripts/agents/verify.py --list --pr 7
tap_no_traceback "$s"
[[ $s == *"- con-files (1 file(s): nuevo-del-pr.sh)"* ]]; tap_check $? "verify: con --pr no saca los archivos que no están en el checkout local" "$s"
# shellcheck disable=SC2164  # si cd falla, la trampa ERR de tap.sh corta la corrida
cd "$RAIZ"

tap_done
