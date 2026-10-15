#!/usr/bin/env bash
# Tests de init-plantilla.sh sobre una copia de la plantilla, en modo completo y chico:
# lo que AGENTS.md dice que está ignorado lo está, y los scripts de agentes no ensucian el árbol.
# Uso: bash scripts/test-init.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-init-XXXXXX")" && pwd -P)
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

# Copia de la plantilla tal como está en el árbol (incluye lo nuevo sin commitear, sin lo ignorado).
copiar() { # copiar <destino>
  mkdir -p "$1"
  (cd "$RAIZ" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf -) | (cd "$1" && tar -xf -)
  (cd "$1" && git init -q -b main && git add -A && git commit -qm plantilla)
}

for modo in completo chico; do
  p="$TMP/$modo"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--chico)
  (cd "$p" && ./scripts/init-plantilla.sh Demo main ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); afirmar $? "[$modo] el init termina bien"
  (cd "$p" && git add -A && git commit -qm init)

  ! [ -e "$p/scripts/test-init.sh" ]; afirmar $? "[$modo] el init borra este test (no sirve sin init-plantilla.sh)"
  ! [ -e "$p/docs/probar-la-plantilla.md" ] && ! [ -e "$p/.github/ISSUE_TEMPLATE/5-prueba.yml" ]
  afirmar $? "[$modo] el init borra la guía y el formulario de prueba (son de la plantilla, no del proyecto)"
  ! grep -rq 'probar-la-plantilla' "$p"/README*.md; afirmar $? "[$modo] el README del proyecto no enlaza la guía de prueba borrada"
  n=$(cd "$p" && git check-ignore .env .env.local scripts/agentes/__pycache__ | wc -l | tr -d ' ')
  es "$n" = 3; afirmar $? "[$modo] .env, .env.local y __pycache__ están ignorados"
  ! (cd "$p" && git check-ignore -q .env.example); afirmar $? "[$modo] .env.example no está ignorado"

  echo "SECRET=x" >"$p/.env"
  if [ -f "$p/scripts/agentes/verificar.py" ]; then
    s=$(cd "$p" && python3 scripts/agentes/verificar.py --listar 2>&1)
    ! grep -q '\.env\|__pycache__' <<<"$s"; afirmar $? "[$modo] verificar.py no lista .env ni __pycache__"
  fi
  (cd "$p" && python3 scripts/agentes/check-docs.py >/dev/null 2>&1); afirmar $? "[$modo] el proyecto recién creado pasa check-docs.py"
  ! grep -rlq '^Ámbito: kit$' "$p/docs/decisions" && ! grep -rq 'ADR-001-idioma-labels' "$p/docs" "$p/README.md"
  afirmar $? "[$modo] el init no instala los ADRs del kit (Ámbito: kit) ni sus líneas en los índices"
  grep -q 'TODO:.*ADR-001' "$p/docs/README.md"; afirmar $? "[$modo] docs/README.md conserva el TODO del primer ADR del proyecto"
  es -z "$(cd "$p" && git status --porcelain)"; afirmar $? "[$modo] después de correr los scripts, git status queda limpio"
  if [ "$modo" = chico ]; then
    ! [ -e "$p/docs/mapa-agentes.json" ]; afirmar $? "[$modo] el modo chico no tiene mapa (ni verificación init)"
  else
    ! grep -q '"nombre": "init"' "$p/docs/mapa-agentes.json"; afirmar $? "[$modo] el init saca del mapa la verificación init (su test ya no existe)"
  fi
done
grep -q '"nombre": "init"' "$RAIZ/docs/mapa-agentes.json"; afirmar $? "la plantilla sin inicializar conserva la verificación init"
[ -f "$RAIZ/docs/probar-la-plantilla.md" ] && grep -q 'probar-la-plantilla.md' "$RAIZ/README.md" \
  && grep -q '5-prueba.yml' "$RAIZ/docs/probar-la-plantilla.md"
afirmar $? "la plantilla trae la guía de prueba, enlazada desde el README, y la guía lleva al formulario"
# Los pasos del formulario son los de la guía, con el mismo número y nombre.
python3 - "$RAIZ" <<'PY'
import re, sys
raiz = sys.argv[1]
guia = re.findall(r"^(\d+)\. \*\*([^*:]+):?\*\*", open(f"{raiz}/docs/probar-la-plantilla.md", encoding="utf-8").read(), re.M)
form = re.findall(r"^ +- \"?(\d+)\. ([^\"\n]+)\"?$", open(f"{raiz}/.github/ISSUE_TEMPLATE/5-prueba.yml", encoding="utf-8").read(), re.M)
sys.exit(0 if guia and [(n, t.strip()) for n, t in guia] == [(n, t.strip()) for n, t in form] else 1)
PY
afirmar $? "los pasos del formulario de prueba coinciden con los de la guía"

# docs.yml (#101) y labels.yml (#103) corren en los pushes a main de la plantilla, y el init deja el filtro de cada modo.
# En chico, los workflows vienen de perfiles/chico/ y ya tienen [<RAMA_BASE>]: el loop no tiene nada que sacar.
# main/develop y chico se prueban en el loop de abajo; acá, solo el modo releases.
for w in docs labels; do
  grep -Eq '^    branches: \[main, <RAMA_BASE>\]$' "$RAIZ/.github/workflows/$w.yml"
  afirmar $? "la plantilla corre $w.yml en los pushes a main"
done
p="$TMP/ramas-releases"
copiar "$p"
(cd "$p" && ./scripts/init-plantilla.sh Demo develop releases >/dev/null 2>&1); afirmar $? "[completo develop releases] el init termina bien"
for w in docs labels; do
  grep -qxF "    branches: [main, develop, 'release/**']" "$p/.github/workflows/$w.yml" && ! grep -q 'plantilla misma' "$p/.github/workflows/$w.yml"
  afirmar $? "[completo develop releases] $w.yml corre en los pushes a [main, develop, 'release/**']"
done

# Los test-*.sh que deja el init pasan en el proyecto nuevo (los corre el CI), con cualquier rama base.
for combinacion in "completo main" "chico main" "completo develop" "chico develop"; do
  read -r modo base <<<"$combinacion"
  p="$TMP/tests-$modo-$base"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--chico)
  (cd "$p" && ./scripts/init-plantilla.sh Demo "$base" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1 && git add -A && git commit -qm init)
  esperado="[main]"; [ "$base" = develop ] && esperado="[main, develop]"
  for w in docs labels; do
    grep -qxF "    branches: $esperado" "$p/.github/workflows/$w.yml" && ! grep -q 'plantilla misma' "$p/.github/workflows/$w.yml"
    afirmar $? "[$modo, base $base] $w.yml corre en los pushes a $esperado"
  done
  # Si uno falla, se muestran sus líneas FAIL: una falla que no se repite (#77) no se puede
  # investigar si el log del CI solo dice qué archivo falló.
  rotos=""
  while read -r t; do
    if ! salida=$(cd "$p" && bash "$t" 2>&1); then
      rotos+="$t "
      grep -E '^FAIL|fallaron' <<<"$salida" | sed "s|^|       [$modo, base $base] $t: |"
    fi
  done < <(cd "$p" && git ls-files '*test-*.sh')
  es -z "$rotos"; afirmar $? "[$modo, base $base] los test-*.sh del proyecto pasan${rotos:+ (fallan: $rotos)}"
done

# check-docs.py falla si AGENTS.md dice que algo está ignorado y no lo está.
p="$TMP/completo"
s=$(cd "$p" && python3 scripts/agentes/check-docs.py 2>&1)
! grep -q 'ignorad' <<<"$s"; afirmar $? "check-docs.py no se queja si lo que AGENTS.md dice ignorado lo está"
# Una frase que dice que algo NO está ignorado no es una afirmación de que lo esté.
cp "$p/AGENTS.md" "$TMP/AGENTS.md"
# shellcheck disable=SC2016  # backticks de Markdown literales
echo '- `dist/` no está ignorado: se commitea.' >>"$p/AGENTS.md"
s=$(cd "$p" && python3 scripts/agentes/check-docs.py 2>&1)
! grep -q 'dist/' <<<"$s"; afirmar $? "check-docs.py no se queja de una frase que dice que algo no está ignorado"
cp "$TMP/AGENTS.md" "$p/AGENTS.md"
(cd "$p" && git rm -q .gitignore)
s=$(cd "$p" && python3 scripts/agentes/check-docs.py 2>&1); c=$?
[ "$c" -ne 0 ] && grep -q 'AGENTS.md.*\.env.*ignorad' <<<"$s"; afirmar $? "check-docs.py falla si AGENTS.md dice que .env* está ignorado y no lo está"
# Una línea que afirma una cosa y niega otra: la negación no tapa la afirmación.
grep -v 'ignorad' "$TMP/AGENTS.md" >"$p/AGENTS.md"
# shellcheck disable=SC2016  # backticks de Markdown literales
echo '- `.env*` están ignorados; `dist/` no está ignorado.' >>"$p/AGENTS.md"
s=$(cd "$p" && python3 scripts/agentes/check-docs.py 2>&1)
grep -q 'AGENTS.md.*\.env.*ignorad' <<<"$s" && ! grep -q 'dist/' <<<"$s"; afirmar $? "check-docs.py valida la afirmación aunque la misma línea niegue otra cosa"

# La negación se decide por cada patrón, aunque la afirmación y la negación estén en la misma frase.
# Sin .gitignore: tiene que reclamar por .env* y nunca por dist/.
while IFS= read -r frase; do
  grep -v 'ignorad' "$TMP/AGENTS.md" >"$p/AGENTS.md"; printf -- '- %s\n' "$frase" >>"$p/AGENTS.md"
  s=$(cd "$p" && python3 scripts/agentes/check-docs.py 2>&1)
  grep -q 'AGENTS.md.*\.env.*ignorad' <<<"$s" && ! grep -q 'dist/' <<<"$s"; afirmar $? "check-docs.py valida .env* en: $frase"
done <<'FRASES'
`.env*` está ignorado y `dist/` no está ignorado.
`dist/` no está ignorado, `.env*` sí está ignorado.
`.env*` no se commitea porque está ignorado.
`dist/` nunca está ignorado; `.env*` está ignorado.
Están ignorados: `.env*`.
FRASES

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
