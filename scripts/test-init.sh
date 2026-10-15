#!/usr/bin/env bash
# Tests de init-template.sh sobre una copia de la plantilla, en modo completo y chico:
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
  extra=(); [ "$modo" = chico ] && extra=(--small)
  (cd "$p" && ./scripts/init-template.sh Demo main ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); afirmar $? "[$modo] el init termina bien"
  (cd "$p" && git add -A && git commit -qm init)

  ! [ -e "$p/scripts/test-init.sh" ]; afirmar $? "[$modo] el init borra este test (no sirve sin init-template.sh)"
  ! [ -e "$p/docs/try-the-template.md" ] && ! [ -e "$p/.github/ISSUE_TEMPLATE/5-trial.yml" ]
  afirmar $? "[$modo] el init borra la guía y el formulario de prueba (son de la plantilla, no del proyecto)"
  ! grep -rq 'try-the-template' "$p"/README*.md; afirmar $? "[$modo] el README del proyecto no enlaza la guía de prueba borrada"
  n=$(cd "$p" && git check-ignore .env .env.local scripts/agents/__pycache__ | wc -l | tr -d ' ')
  es "$n" = 3; afirmar $? "[$modo] .env, .env.local y __pycache__ están ignorados"
  ! (cd "$p" && git check-ignore -q .env.example); afirmar $? "[$modo] .env.example no está ignorado"

  echo "SECRET=x" >"$p/.env"
  if [ -f "$p/scripts/agents/verify.py" ]; then
    s=$(cd "$p" && python3 scripts/agents/verify.py --list 2>&1)
    ! grep -q '\.env\|__pycache__' <<<"$s"; afirmar $? "[$modo] verify.py no lista .env ni __pycache__"
  fi
  # Completo: el mapa trae TODO de ejemplo y check-docs falla a propósito hasta que el proyecto los completa;
  # lo que no puede fallar son los links, rutas ni índices. Chico: no tiene mapa y tiene que pasar entero.
  s=$(cd "$p" && python3 scripts/agents/check-docs.py 2>&1); c=$?
  # La salida tiene que ser la del check (un resumen), nunca un traceback: un traceback no menciona esos errores y el grep de abajo pasaría igual.
  ! grep -q Traceback <<<"$s" && grep -q '^Docs ' <<<"$s"; afirmar $? "[$modo] check-docs.py del proyecto recién creado termina con su resumen, sin Traceback"
  if [ "$modo" = chico ]; then es "$c" -eq 0; else ! grep -q 'missing path\|broken link\|missing from the index\|does not exist' <<<"$s"; fi
  afirmar $? "[$modo] check-docs.py del proyecto recién creado no marca links, rutas ni índices rotos"
  [ -f "$p/docs/decisions/README.md" ] && ! ls "$p"/docs/decisions/ADR-001-* >/dev/null 2>&1 && ! grep -rq 'ADR-001-language-labels' "$p/docs" "$p/README.md"
  afirmar $? "[$modo] el init no instala los ADRs del kit (Ámbito: kit) ni sus líneas en los índices"
  grep -q 'TODO:.*ADR-001' "$p/docs/README.md"; afirmar $? "[$modo] docs/README.md conserva el TODO del primer ADR del proyecto"
  es -z "$(cd "$p" && git status --porcelain)"; afirmar $? "[$modo] después de correr los scripts, git status queda limpio"
  if [ "$modo" = chico ]; then
    ! [ -e "$p/docs/agents-map.json" ]; afirmar $? "[$modo] el modo chico no tiene mapa (ni verificación init)"
  else
    ! grep -q '"name": "init"' "$p/docs/agents-map.json"; afirmar $? "[$modo] el init saca del mapa la verificación init (su test ya no existe)"
    ! grep -q 'ADR-001\|CHANGELOG' "$p/docs/agents-map.json"; afirmar $? "[$modo] el init saca del mapa lo que ignora de los archivos del kit (no debe ocultar el ADR-001 del proyecto)"
  fi
done
grep -q '"name": "init"' "$RAIZ/docs/agents-map.json"; afirmar $? "la plantilla sin inicializar conserva la verificación init"
[ -f "$RAIZ/docs/try-the-template.md" ] && grep -q 'try-the-template.md' "$RAIZ/README.md" \
  && grep -q '5-trial.yml' "$RAIZ/docs/try-the-template.md"
afirmar $? "la plantilla trae la guía de prueba, enlazada desde el README, y la guía lleva al formulario"
# Los pasos del formulario son los de la guía, con el mismo número y nombre.
python3 - "$RAIZ" <<'PY'
import re, sys
raiz = sys.argv[1]
guia = re.findall(r"^(\d+)\. \*\*([^*:]+):?\*\*", open(f"{raiz}/docs/try-the-template.md", encoding="utf-8").read(), re.M)
form = re.findall(r"^ +- \"?(\d+)\. ([^\"\n]+)\"?$", open(f"{raiz}/.github/ISSUE_TEMPLATE/5-trial.yml", encoding="utf-8").read(), re.M)
sys.exit(0 if guia and [(n, t.strip()) for n, t in guia] == [(n, t.strip()) for n, t in form] else 1)
PY
afirmar $? "los pasos del formulario de prueba coinciden con los de la guía"

# docs.yml (#101) y labels.yml (#103) corren en los pushes a main de la plantilla, y el init deja el filtro de cada modo.
# En chico, los workflows vienen de profiles/small/ y ya tienen [<BASE_BRANCH>]: el loop no tiene nada que sacar.
# main/develop y chico se prueban en el loop de abajo; acá, solo el modo releases.
for w in docs labels; do
  grep -Eq '^    branches: \[main, <BASE_BRANCH>\]$' "$RAIZ/.github/workflows/$w.yml"
  afirmar $? "la plantilla corre $w.yml en los pushes a main"
done
p="$TMP/ramas-releases"
copiar "$p"
(cd "$p" && ./scripts/init-template.sh Demo develop releases >/dev/null 2>&1); afirmar $? "[completo develop releases] el init termina bien"
for w in docs labels; do
  grep -qxF "    branches: [main, develop, 'release/**']" "$p/.github/workflows/$w.yml" && ! grep -q 'for the template itself' "$p/.github/workflows/$w.yml"
  afirmar $? "[completo develop releases] $w.yml corre en los pushes a [main, develop, 'release/**']"
done

# --lang (#113): con es, cada X.md se reemplaza por su X.es.md; con en (default), los .es.md se borran.
# Se prueba con pares de ejemplo agregados a la copia (el contenido real se traduce en #115).
con_pares() { # con_pares <copia>: pares de ejemplo en el repo, en el perfil chico y en un archivo que el init borra
  local p="$1"
  mkdir -p "$p/profiles/small"
  echo "SAMPLE-EN" >"$p/SAMPLE.md"; echo "SAMPLE-ES" >"$p/SAMPLE.es.md"
  echo "FULL-EN" >"$p/AGENTS.md"; echo "FULL-ES" >"$p/AGENTS.es.md"
  echo "SMALL-EN" >"$p/profiles/small/AGENTS.md"; echo "SMALL-ES" >"$p/profiles/small/AGENTS.es.md"
  echo "TRIAL-ES" >"$p/docs/try-the-template.es.md"
  # Textos que el perfil chico edita con perl: su hermano .es.md (copia del actual) no puede pisar la edición.
  cp "$p/docs/decisions/README.md" "$p/docs/decisions/README.es.md"
  cp "$p/.github/pull_request_template.md" "$p/.github/pull_request_template.es.md"
  # Un archivo que el perfil chico borra (DELETE) y su hermano: el hermano no puede volver como X.md con --lang es.
  echo "DEL-EN" >"$p/DELETED.md"; echo "DEL-ES" >"$p/DELETED.es.md"; echo "DELETED.md" >>"$p/profiles/small/DELETE"
  (cd "$p" && git add -A && git commit -qm pares)
}
for combinacion in "completo en" "completo es" "chico en" "chico es" "completo-releases es"; do
  read -r modo idioma <<<"$combinacion"
  p="$TMP/lang-$modo-$idioma"
  copiar "$p"; con_pares "$p"
  extra=(); [ "$modo" = chico ] && extra=(--small)
  base=(main); [ "$modo" = completo-releases ] && base=(develop releases)
  [ "$idioma" = en ] && args=(--lang en) || args=(--lang=es)
  (cd "$p" && ./scripts/init-template.sh Demo "${base[@]}" "${args[@]}" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); afirmar $? "[$modo --lang $idioma] el init termina bien"
  es -z "$(find "$p" -name '*.es.md' -not -path '*/.git/*')"; afirmar $? "[$modo --lang $idioma] no queda ningún .es.md"
  if [ "$idioma" = es ]; then
    grep -qx SAMPLE-ES "$p/SAMPLE.md"; afirmar $? "[$modo --lang es] SAMPLE.md es la versión .es.md"
    if [ "$modo" = chico ]; then esperado=SMALL-ES; else esperado=FULL-ES; fi
  else
    grep -qx SAMPLE-EN "$p/SAMPLE.md"; afirmar $? "[$modo --lang en] SAMPLE.md queda en inglés"
    if [ "$modo" = chico ]; then esperado=SMALL-EN; else esperado=FULL-EN; fi
  fi
  grep -qx "$esperado" "$p/AGENTS.md"; afirmar $? "[$modo --lang $idioma] AGENTS.md es $esperado (el perfil pisa al archivo completo, cada uno en su idioma)"
  if [ "$modo" = chico ]; then ! [ -e "$p/DELETED.md" ]; afirmar $? "[$modo --lang $idioma] lo que borra el perfil chico no vuelve desde su hermano .es.md"; fi
  if [ "$modo" = chico ]; then
    # shellcheck disable=SC2016  # backticks de Markdown literales
    viejo1='el PR lleva el label `business-logic`'
    # shellcheck disable=SC2016
    viejo2='agregá el label `business-logic`'
    ! grep -qF "$viejo1" "$p/docs/decisions/README.md" && ! grep -qF "$viejo2" "$p/.github/pull_request_template.md"
    afirmar $? "[$modo --lang $idioma] los ajustes del perfil chico (label business-logic) valen también con el hermano .es.md"
  fi
  ! [ -e "$p/docs/try-the-template.md" ]; afirmar $? "[$modo --lang $idioma] el init sigue borrando la guía de prueba, también su versión .es.md"
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$p/.agent-kit.json')).get('language') == '$idioma' else 1)"
  afirmar $? "[$modo --lang $idioma] .agent-kit.json registra language: $idioma"
done
# El proyecto instalado tiene un solo idioma: un docs/*.es.md propio no activa la paridad (interruptor parity).
p="$TMP/lang-propio"
copiar "$p"
(cd "$p" && ./scripts/init-template.sh Demo >/dev/null 2>&1 && git add -A && git commit -qm init)
grep -q '"parity": false' "$p/docs/agents-map.json"; afirmar $? "[completo] el init deja parity apagado en el mapa del proyecto"
printf '# Guía\n' >"$p/docs/manual.es.md"
s=$(cd "$p" && python3 scripts/agents/check-docs.py 2>&1)
! grep -q 'sibling\|headings\|code blocks' <<<"$s"; afirmar $? "[completo] un docs/manual.es.md propio no hace fallar el CI de docs del proyecto"
p="$TMP/lang-default"
copiar "$p"; con_pares "$p"
(cd "$p" && ./scripts/init-template.sh Demo >/dev/null 2>&1); afirmar $? "[sin --lang] el init termina bien"
grep -qx SAMPLE-EN "$p/SAMPLE.md" && python3 -c "import json,sys; sys.exit(0 if json.load(open('$p/.agent-kit.json')).get('language') == 'en' else 1)"
afirmar $? "[sin --lang] el idioma por defecto es en y queda registrado"
for malo in "--lang fr" "--lang" "--lang="; do
  p="$TMP/lang-malo"; rm -rf "$p"; copiar "$p"
  # shellcheck disable=SC2086  # $malo se parte a propósito en opción y valor
  s=$(cd "$p" && ./scripts/init-template.sh Demo $malo 2>&1); c=$?
  [ "$c" -ne 0 ] && grep -q -- '--lang' <<<"$s" && [ -e "$p/scripts/init-template.sh" ]
  afirmar $? "el init rechaza '$malo' con un mensaje sobre --lang y sin tocar nada"
done

# Los test-*.sh que deja el init pasan en el proyecto nuevo (los corre el CI), con cualquier rama base.
for combinacion in "completo main" "chico main" "completo develop" "chico develop"; do
  read -r modo base <<<"$combinacion"
  p="$TMP/tests-$modo-$base"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--small)
  (cd "$p" && ./scripts/init-template.sh Demo "$base" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1 && git add -A && git commit -qm init)
  esperado="[main]"; [ "$base" = develop ] && esperado="[main, develop]"
  for w in docs labels; do
    grep -qxF "    branches: $esperado" "$p/.github/workflows/$w.yml" && ! grep -q 'for the template itself' "$p/.github/workflows/$w.yml"
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
s=$(cd "$p" && python3 scripts/agents/check-docs.py 2>&1)
! grep -q 'is ignored, but' <<<"$s"; afirmar $? "check-docs.py no se queja si lo que AGENTS.md dice ignorado lo está"
# Una frase que dice que algo NO está ignorado no es una afirmación de que lo esté.
cp "$p/AGENTS.md" "$TMP/AGENTS.md"
# shellcheck disable=SC2016  # backticks de Markdown literales
echo '- `dist/` no está ignorado: se commitea.' >>"$p/AGENTS.md"
s=$(cd "$p" && python3 scripts/agents/check-docs.py 2>&1)
! grep -q 'dist/' <<<"$s"; afirmar $? "check-docs.py no se queja de una frase que dice que algo no está ignorado"
cp "$TMP/AGENTS.md" "$p/AGENTS.md"
(cd "$p" && git rm -q .gitignore)
s=$(cd "$p" && python3 scripts/agents/check-docs.py 2>&1); c=$?
[ "$c" -ne 0 ] && grep -q 'AGENTS.md.*\.env.*ignored' <<<"$s"; afirmar $? "check-docs.py falla si AGENTS.md dice que .env* está ignorado y no lo está"
# Una línea que afirma una cosa y niega otra: la negación no tapa la afirmación.
grep -v 'ignorad' "$TMP/AGENTS.md" >"$p/AGENTS.md"
# shellcheck disable=SC2016  # backticks de Markdown literales
echo '- `.env*` están ignorados; `dist/` no está ignorado.' >>"$p/AGENTS.md"
s=$(cd "$p" && python3 scripts/agents/check-docs.py 2>&1)
grep -q 'AGENTS.md.*\.env.*ignored' <<<"$s" && ! grep -q 'dist/' <<<"$s"; afirmar $? "check-docs.py valida la afirmación aunque la misma línea niegue otra cosa"

# La negación se decide por cada patrón, aunque la afirmación y la negación estén en la misma frase.
# Sin .gitignore: tiene que reclamar por .env* y nunca por dist/.
while IFS= read -r frase; do
  grep -v 'ignorad' "$TMP/AGENTS.md" >"$p/AGENTS.md"; printf -- '- %s\n' "$frase" >>"$p/AGENTS.md"
  s=$(cd "$p" && python3 scripts/agents/check-docs.py 2>&1)
  grep -q 'AGENTS.md.*\.env.*ignored' <<<"$s" && ! grep -q 'dist/' <<<"$s"; afirmar $? "check-docs.py valida .env* en: $frase"
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
