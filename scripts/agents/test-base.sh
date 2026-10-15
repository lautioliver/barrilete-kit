#!/usr/bin/env bash
# Tests de la rama base sin configurar (<BASE_BRANCH> en la plantilla sin inicializar):
# agents_map.py, verify.py y prepare.sh usan la rama por defecto del remoto y avisan.
# Uso: bash scripts/agents/test-base.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-base-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
unset BASE
# Solo aplica a la plantilla sin inicializar: el init reemplaza el primer marcador por la rama base.
# shellcheck disable=SC2050  # la comparación es constante hasta que el init la cambia
if [ "<BASE_BRANCH>" != "<BASE_""BRANCH>" ]; then echo "La rama base ya está configurada: estos tests no aplican."; exit 0; fi

# Remoto cuya rama por defecto es "trunk" (para no confundirla con un "main" fijo).
git init -q --bare "$TMP/remoto.git"; git -C "$TMP/remoto.git" symbolic-ref HEAD refs/heads/trunk
git clone -q "$TMP/remoto.git" "$TMP/p" 2>/dev/null
mkdir -p "$TMP/p/scripts" "$TMP/p/docs"
cp -R "$RAIZ/scripts/agents" "$TMP/p/scripts/"
printf '{"docs": [], "sensitive": [], "verify": [{"name": "eco", "always": true, "run": "echo {base}"}]}\n' >"$TMP/p/docs/agents-map.json"
(cd "$TMP/p" && git switch -q -c trunk && git add -A && git commit -qm base && git push -q origin trunk 2>/dev/null \
  && git remote set-head origin trunk && git switch -q -c claude/1-algo && echo x >nuevo.txt && git add nuevo.txt && git commit -qm x)

s=$(cd "$TMP/p" && python3 scripts/agents/agents_map.py 2>&1); c=$?
afirmar $c "agents_map.py sin BASE en la plantilla sin inicializar termina bien"
grep -q "nuevo.txt\|Changed files: 1" <<<"$s"; afirmar $? "agents_map.py compara contra la rama por defecto del remoto"
grep -qi "warning.*trunk" <<<"$s"; afirmar $? "agents_map.py avisa qué base usó"

s=$(cd "$TMP/p" && python3 scripts/agents/verify.py --list 2>&1); c=$?
afirmar $c "verify.py sin BASE termina bien"
grep -q "against origin/trunk" <<<"$s"; afirmar $? "verify.py usa origin/<rama por defecto>"

# Sin origin/HEAD local: la pide al remoto.
(cd "$TMP/p" && git remote set-head origin -d)
s=$(cd "$TMP/p" && python3 scripts/agents/agents_map.py 2>&1); c=$?
afirmar $c "sin origin/HEAD local, la pide al remoto"

# Con BASE explícita, no cambia nada.
s=$(cd "$TMP/p" && BASE=trunk python3 scripts/agents/agents_map.py 2>&1)
! grep -qi "warning" <<<"$s"; afirmar $? "con BASE explícita no avisa"

# Nombres con espacios, tildes o ñ: llegan literales (sin comillas ni escapes), commiteados o no,
# y un renombre aparece una sola vez, con el nombre nuevo.
(cd "$TMP/p" && git switch -q trunk && echo r >"viejo nombre.txt" && git add -A && git commit -qm viejo \
  && git push -q origin trunk 2>/dev/null && git switch -q -c claude/2-nombres \
  && echo a >"a b.txt" && echo g >"guía.md" && git add -A && git commit -qm nombres \
  && echo c >"c d.txt" && git add "c d.txt" && echo s >"señal.md" && git mv "viejo nombre.txt" "nuevo ñ.txt")
s=$(cd "$TMP/p" && python3 -c 'import sys; sys.path.insert(0, "scripts/agents"); from agents_map import archivos_cambiados
print("\n".join(archivos_cambiados(["--base", "trunk"])))' 2>&1)
esperado=$(printf '%s\n' "a b.txt" "c d.txt" "guía.md" "nuevo ñ.txt" "señal.md")
es "$s" = "$esperado"; afirmar $? "archivos_cambiados devuelve los nombres literales y el renombre una vez"
[ "$s" = "$esperado" ] || printf '       %s\n' "$s"

# Un archivo dentro de una carpeta nueva sin trackear aparece con su ruta, no solo la carpeta.
(cd "$TMP/p" && mkdir -p "carpeta nueva/sub" && echo x >"carpeta nueva/sub/a.txt")
s=$(cd "$TMP/p" && python3 -c 'import sys; sys.path.insert(0, "scripts/agents"); from agents_map import archivos_cambiados
print("\n".join(archivos_cambiados(["--base", "trunk"])))' 2>&1)
grep -qx "carpeta nueva/sub/a.txt" <<<"$s" && ! grep -q '/$' <<<"$s"; afirmar $? "archivos_cambiados lista los archivos de una carpeta nueva sin trackear"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
