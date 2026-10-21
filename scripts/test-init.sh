#!/usr/bin/env bash
# shellcheck disable=SC2319  # "<condition>; tap_check $?" is the pattern of the tests (tap.sh)
# Tests de init-template.sh sobre una copia de la plantilla, en modo completo y chico:
# lo que AGENTS.md dice que está ignorado lo está, y los scripts de agentes no ensucian el árbol.
# Uso: bash scripts/test-init.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-init-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
# Uso: <condición>; tap_check $? "descripción"
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
unset BASE

# Copia de la plantilla tal como está en el árbol (incluye lo nuevo sin commitear, sin lo ignorado).
copiar() { # copiar <destino>
  mkdir -p "$1"
  (cd "$RAIZ" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | (cd "$1" && tar -xf -)
  (cd "$1" && git init -q -b main && git add -A && git commit -qm plantilla)
}

# Las claves del mapa del proyecto, o "(sin mapa)" si no existe: un archivo que falta es una aserción que falla, no un crash de python.
claves_mapa() {
  if [ -f "$1" ]; then python3 -c "import json, sys; print(sorted(json.load(open(sys.argv[1]))))" "$1"; else echo "(sin mapa)"; fi
}

for modo in completo chico; do
  p="$TMP/$modo"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--small)
  (cd "$p" && ./scripts/init-template.sh Demo main ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); tap_check $? "[<modo>] el init termina bien" "[$modo] el init termina bien"
  (cd "$p" && git add -A && git commit -qm init)

  ! [ -e "$p/scripts/test-init.sh" ]; tap_check $? "[<modo>] el init borra este test (no sirve sin init-template.sh)" "[$modo] el init borra este test (no sirve sin init-template.sh)"
  # Sin terminal y sin opción, la línea del flujo no se activa (#181), pero flow.py queda en los dos modos.
  [ -f "$p/scripts/agents/flow.py" ] && ! grep -q statusLine "$p/.claude/settings.json" \
    && python3 -c "import json,sys; sys.exit(json.load(open(sys.argv[1]))['flow_line'] is not False)" "$p/.agent-kit.json"
  tap_check $? "[<modo>] sin --flow-line no hay statusLine y .agent-kit.json registra flow_line: false" "[$modo] sin --flow-line no hay statusLine y .agent-kit.json registra flow_line: false"
  ! [ -e "$p/docs/try-the-template.md" ] && ! [ -e "$p/.github/ISSUE_TEMPLATE/5-trial.yml" ]
  tap_check $? "[<modo>] el init borra la guía y el formulario de prueba (son de la plantilla, no del proyecto)" "[$modo] el init borra la guía y el formulario de prueba (son de la plantilla, no del proyecto)"
  ! grep -rq 'try-the-template' "$p"/README*.md; tap_check $? "[<modo>] el README del proyecto no enlaza la guía de prueba borrada" "[$modo] el README del proyecto no enlaza la guía de prueba borrada"
  ! grep -q 'README.es.md\|lang:start' "$p/README.md"; tap_check $? "[<modo>] el README del proyecto no tiene el selector de idioma (lo borra el init)" "[$modo] el README del proyecto no tiene el selector de idioma (lo borra el init)"
  n=$(cd "$p" && git check-ignore .env .env.local scripts/agents/__pycache__ | wc -l | tr -d ' ')
  es "$n" = 3; tap_check $? "[<modo>] .env, .env.local y __pycache__ están ignorados" "[$modo] .env, .env.local y __pycache__ están ignorados"
  c=0; (trap - ERR; cd "$p" && git check-ignore -q .env.example) || c=$?; tap_status "$c" 1; es "$c" -ne 0; tap_check $? "[<modo>] .env.example no está ignorado" "[$modo] .env.example no está ignorado"

  echo "SECRET=x" >"$p/.env"
  if [ -f "$p/scripts/agents/verify.py" ]; then
    s=$(cd "$p" && python3 scripts/agents/verify.py --list 2>&1)
    ! grep -q '\.env\|__pycache__' <<<"$s"; tap_check $? "[<modo>] verify.py no lista .env ni __pycache__" "[$modo] verify.py no lista .env ni __pycache__"
  fi
  # Completo: el mapa trae TODO de ejemplo y check-docs falla a propósito hasta que el proyecto los completa;
  # lo que no puede fallar son los links, rutas ni índices. Chico: su mapa mínimo (solo red) y tiene que pasar entero.
  c=0; s=$(trap - ERR; cd "$p" && python3 scripts/agents/check-docs.py 2>&1) || c=$?; tap_status "$c" "$([ "$modo" = chico ] && echo 0 || echo 1)"
  # La salida tiene que ser la del check (un resumen), nunca un traceback: un traceback no menciona esos errores y el grep de abajo pasaría igual.
  ! grep -q Traceback <<<"$s" && grep -q '^Docs ' <<<"$s"; tap_check $? "[<modo>] check-docs.py del proyecto recién creado termina con su resumen, sin Traceback" "[$modo] check-docs.py del proyecto recién creado termina con su resumen, sin Traceback"
  if [ "$modo" = chico ]; then es "$c" -eq 0; else ! grep -q 'missing path\|broken link\|missing from the index\|does not exist' <<<"$s"; fi
  tap_check $? "[<modo>] check-docs.py del proyecto recién creado no marca links, rutas ni índices rotos" "[$modo] check-docs.py del proyecto recién creado no marca links, rutas ni índices rotos"
  [ -f "$p/docs/decisions/README.md" ] && ! ls "$p"/docs/decisions/ADR-001-* >/dev/null 2>&1 && ! grep -rq 'ADR-001-language-labels' "$p/docs" "$p/README.md"
  tap_check $? "[<modo>] el init no instala los ADRs del kit (Ámbito: kit) ni sus líneas en los índices" "[$modo] el init no instala los ADRs del kit (Ámbito: kit) ni sus líneas en los índices"
  grep -q 'TODO:.*ADR-001' "$p/docs/README.md"; tap_check $? "[<modo>] docs/README.md conserva el TODO del primer ADR del proyecto" "[$modo] docs/README.md conserva el TODO del primer ADR del proyecto"
  # Los ADRs del kit que se instalan (ADR-002) viven en docs/decisions/kit/: la numeración del proyecto en docs/decisions/ queda libre.
  [ -f "$p/docs/decisions/kit/ADR-002-structured-red-validation.md" ] && ! ls "$p"/docs/decisions/kit/*.es.md >/dev/null 2>&1 && ! ls "$p"/docs/decisions/ADR-002-* >/dev/null 2>&1
  tap_check $? "[<modo>] el init conserva docs/decisions/kit/ADR-002 (sin hermano .es.md) y no deja ADRs sueltos en docs/decisions/" "[$modo] el init conserva docs/decisions/kit/ADR-002 (sin hermano .es.md) y no deja ADRs sueltos en docs/decisions/"
  # #143: con base main, "neither to `main` nor to `main`" / "ni a `main` ni a `main`" no puede quedar: el reemplazo cambia la frase entera.
  # shellcheck disable=SC2016  # backticks de Markdown, literales
  ! grep -rEq 'nor to `main`|ni a `main` ni a `main`|neither to `main`|ni a `main` ni' --exclude-dir=.git "$p"; tap_check $? "[<modo>] con base main no queda 'ni a main ni a main' (ni 'neither to main nor to main')" "[$modo] con base main no queda 'ni a main ni a main' (ni 'neither to main nor to main')"
  # #143: lo que es del kit (su ADR-001, el instalador, la épica #33, el CHANGELOG del kit) no viaja a la documentación instalada.
  grep -rEn "kit's .ADR-001|ADR-001. del kit|install\.py|#122|[eé]pic(a)? #33|kit's .CHANGELOG|CHANGELOG.md. del kit|\-\-lang" --include='*.md' --include='*.py' --include='*.txt' "$p/docs" "$p/AGENTS.md" "$p/.claude/skills" "$p/.claude/agents" 2>/dev/null | grep -v '/test-[a-z-]*\.sh:' >"$TMP/kit-$modo.txt" || true  # no line is the good result
  es ! -s "$TMP/kit-$modo.txt"; tap_check $? "[<modo>] la documentación instalada no cita el ADR-001 del kit, install.py, #122, la épica #33 ni --lang" "[$modo] la documentación instalada no cita el ADR-001 del kit, install.py, #122, la épica #33 ni --lang"
  [ -s "$TMP/kit-$modo.txt" ] && sed 's/^/       /' "$TMP/kit-$modo.txt" | head -5
  es -z "$(cd "$p" && git status --porcelain)"; tap_check $? "[<modo>] después de correr los scripts, git status queda limpio" "[$modo] después de correr los scripts, git status queda limpio"
  if [ "$modo" = chico ]; then
    # #152: el modo chico declara el rojo en un mapa mínimo que solo tiene la sección red (decidido en el ADR-002, D2).
    k=$(claves_mapa "$p/docs/agents-map.json"); [ "$k" = "['red']" ]; tap_check $? "[<modo>] el modo chico deja un docs/agents-map.json mínimo con solo la sección red" "[$modo] el modo chico deja un docs/agents-map.json mínimo con solo la sección red"
    [ -f "$p/docs/agents-map.json" ] && ! grep -q '"name": "init"' "$p/docs/agents-map.json"; tap_check $? "[<modo>] el mapa mínimo del modo chico no trae la verificación init" "[$modo] el mapa mínimo del modo chico no trae la verificación init"
  else
    python3 -c "import json,sys; r=json.load(open('$p/docs/agents-map.json'))['red']; sys.exit(0 if r and all('{out}' in e['run'] and e['format'] in ('junit','tap') for e in r) else 1)" 2>/dev/null; tap_check $? "[<modo>] el mapa instalado trae la sección red por defecto (bash/TAP con {out})" "[$modo] el mapa instalado trae la sección red por defecto (bash/TAP con {out})"
    ! grep -q '^- docs/agents-map.json: red' <<<"$s"; tap_check $? "[<modo>] check-docs del proyecto recién creado no rechaza la sección red por defecto" "[$modo] check-docs del proyecto recién creado no rechaza la sección red por defecto"
    ! grep -q '"name": "init"' "$p/docs/agents-map.json"; tap_check $? "[<modo>] el init saca del mapa la verificación init (su test ya no existe)" "[$modo] el init saca del mapa la verificación init (su test ya no existe)"
    ! grep -q 'ADR-001\|CHANGELOG' "$p/docs/agents-map.json"; tap_check $? "[<modo>] el init saca del mapa lo que ignora de los archivos del kit (no debe ocultar el ADR-001 del proyecto)" "[$modo] el init saca del mapa lo que ignora de los archivos del kit (no debe ocultar el ADR-001 del proyecto)"
  fi
done
grep -q '"name": "init"' "$RAIZ/docs/agents-map.json"; tap_check $? "la plantilla sin inicializar conserva la verificación init"
[ -f "$RAIZ/docs/try-the-template.md" ] && grep -q 'try-the-template.md' "$RAIZ/README.md" \
  && grep -q '5-trial.yml' "$RAIZ/docs/try-the-template.md"
tap_check $? "la plantilla trae la guía de prueba, enlazada desde el README, y la guía lleva al formulario"
# Los pasos del formulario son los de la guía, con el mismo número y nombre.
python3 - "$RAIZ" <<'PY'
import re, sys
raiz = sys.argv[1]
guia = re.findall(r"^(\d+)\. \*\*([^*:]+):?\*\*", open(f"{raiz}/docs/try-the-template.es.md", encoding="utf-8").read(), re.M)
form = re.findall(r"^ +- \"?(\d+)\. ([^\"\n]+)\"?$", open(f"{raiz}/.github/i18n/ISSUE_TEMPLATE/5-trial.es.yml", encoding="utf-8").read(), re.M)
en = re.findall(r"^(\d+)\. \*\*([^*:]+):?\*\*", open(f"{raiz}/docs/try-the-template.md", encoding="utf-8").read(), re.M)
form_en = re.findall(r"^ +- \"?(\d+)\. ([^\"\n]+)\"?$", open(f"{raiz}/.github/ISSUE_TEMPLATE/5-trial.yml", encoding="utf-8").read(), re.M)
sys.exit(0 if guia and [(n, t.strip()) for n, t in guia] == [(n, t.strip()) for n, t in form] and [(n, t.strip()) for n, t in en] == [(n, t.strip()) for n, t in form_en] and [n for n, _ in en] == [n for n, _ in guia] else 1)
PY
tap_check $? "los pasos del formulario de prueba coinciden con los de la guía"

# docs.yml (#101) y labels.yml (#103) corren en los pushes a main de la plantilla, y el init deja el filtro de cada modo.
# En chico, los workflows vienen de profiles/small/ y ya tienen [<BASE_BRANCH>]: el loop no tiene nada que sacar.
# main/develop y chico se prueban en el loop de abajo; acá, solo el modo releases.
for w in docs labels; do
  grep -Eq '^    branches: \[main, <BASE_BRANCH>\]$' "$RAIZ/.github/workflows/$w.yml"
  tap_check $? "la plantilla corre <w>.yml en los pushes a main" "la plantilla corre $w.yml en los pushes a main"
done
p="$TMP/ramas-releases"
copiar "$p"
(cd "$p" && ./scripts/init-template.sh Demo develop releases >/dev/null 2>&1); tap_check $? "[completo develop releases] el init termina bien"
for w in docs labels; do
  grep -qxF "    branches: [main, develop, 'release/**']" "$p/.github/workflows/$w.yml" && ! grep -q 'for the template itself' "$p/.github/workflows/$w.yml"
  tap_check $? "[completo develop releases] <w>.yml corre en los pushes a [main, develop, 'release/**']" "[completo develop releases] $w.yml corre en los pushes a [main, develop, 'release/**']"
done

# #143: la frase "nunca mergea, ni a <base> ni a main": con base main la frase entera cambia; con otra base queda con las dos ramas.
for idioma in en es; do
  # shellcheck disable=SC2016  # backticks de Markdown, literales
  if [ "$idioma" = en ]; then con_main='not even to `main`'; con_otra='neither to `develop` nor to `main`'; else con_main='ni siquiera a `main`'; con_otra='ni a `develop` ni a `main`'; fi
  p="$TMP/lim-$idioma-main"; copiar "$p"
  (cd "$p" && ./scripts/init-template.sh Demo main --lang "$idioma" >/dev/null 2>&1)
  grep -qF "$con_main" "$p/.claude/skills/implement-issue/SKILL.md"; tap_check $? "[--lang <idioma>, base main] implement-issue dice '<con_main>' (la frase entera, no 'main' dos veces)" "[--lang $idioma, base main] implement-issue dice '$con_main' (la frase entera, no 'main' dos veces)"
  p="$TMP/lim-$idioma-develop"; copiar "$p"
  (cd "$p" && ./scripts/init-template.sh Demo develop --lang "$idioma" >/dev/null 2>&1)
  grep -qF "$con_otra" "$p/.claude/skills/implement-issue/SKILL.md"; tap_check $? "[--lang <idioma>, base develop] implement-issue conserva '<con_otra>'" "[--lang $idioma, base develop] implement-issue conserva '$con_otra'"
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
  # llms.txt no es Markdown: su hermano es llms.es.txt (#115), con la misma regla.
  echo "TXT-EN" >"$p/llms.txt"; echo "TXT-ES" >"$p/llms.es.txt"
  # Textos que el perfil chico edita con perl (docs/decisions/README y la plantilla del PR): sus hermanos .es.md reales no pueden pisar la edición.
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
  (cd "$p" && ./scripts/init-template.sh Demo "${base[@]}" "${args[@]}" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); tap_check $? "[<modo> --lang <idioma>] el init termina bien" "[$modo --lang $idioma] el init termina bien"
  es -z "$(find "$p" \( -name '*.es.md' -o -name '*.es.txt' \) -not -path '*/.git/*')"; tap_check $? "[<modo> --lang <idioma>] no queda ningún .es.md ni .es.txt" "[$modo --lang $idioma] no queda ningún .es.md ni .es.txt"
  if [ "$idioma" = es ]; then
    grep -qx SAMPLE-ES "$p/SAMPLE.md"; tap_check $? "[<modo> --lang es] SAMPLE.md es la versión .es.md" "[$modo --lang es] SAMPLE.md es la versión .es.md"
    grep -qx TXT-ES "$p/llms.txt"; tap_check $? "[<modo> --lang es] llms.txt es la versión llms.es.txt" "[$modo --lang es] llms.txt es la versión llms.es.txt"
    if [ "$modo" = chico ]; then esperado=SMALL-ES; else esperado=FULL-ES; fi
  else
    grep -qx SAMPLE-EN "$p/SAMPLE.md"; tap_check $? "[<modo> --lang en] SAMPLE.md queda en inglés" "[$modo --lang en] SAMPLE.md queda en inglés"
    grep -qx TXT-EN "$p/llms.txt"; tap_check $? "[<modo> --lang en] llms.txt queda en inglés" "[$modo --lang en] llms.txt queda en inglés"
    if [ "$modo" = chico ]; then esperado=SMALL-EN; else esperado=FULL-EN; fi
  fi
  grep -qx "$esperado" "$p/AGENTS.md"; tap_check $? "[<modo> --lang <idioma>] AGENTS.md es <esperado> (el perfil pisa al archivo completo, cada uno en su idioma)" "[$modo --lang $idioma] AGENTS.md es $esperado (el perfil pisa al archivo completo, cada uno en su idioma)"
  if [ "$modo" = chico ]; then ! [ -e "$p/DELETED.md" ]; tap_check $? "[<modo> --lang <idioma>] lo que borra el perfil chico no vuelve desde su hermano .es.md" "[$modo --lang $idioma] lo que borra el perfil chico no vuelve desde su hermano .es.md"; fi
  if [ "$modo" = chico ]; then
    # shellcheck disable=SC2016  # backticks de Markdown literales
    viejo1='el PR lleva el label `business-logic`'
    # shellcheck disable=SC2016
    viejo2='agregá el label `business-logic`'
    # shellcheck disable=SC2016
    viejo3='the PR carries the `business-logic` label'
    ! grep -qF "$viejo1" "$p/docs/decisions/README.md" && ! grep -qF "$viejo3" "$p/docs/decisions/README.md" && ! grep -qF "$viejo2" "$p/.github/pull_request_template.md"
    tap_check $? "[<modo> --lang <idioma>] los ajustes del perfil chico (label business-logic) valen también con el hermano .es.md" "[$modo --lang $idioma] los ajustes del perfil chico (label business-logic) valen también con el hermano .es.md"
  fi
  ! [ -e "$p/docs/try-the-template.md" ]; tap_check $? "[<modo> --lang <idioma>] el init sigue borrando la guía de prueba, también su versión .es.md" "[$modo --lang $idioma] el init sigue borrando la guía de prueba, también su versión .es.md"
  python3 -c "import json,sys; sys.exit(0 if json.load(open('$p/.agent-kit.json')).get('language') == '$idioma' else 1)"
  tap_check $? "[<modo> --lang <idioma>] .agent-kit.json registra language: <idioma>" "[$modo --lang $idioma] .agent-kit.json registra language: $idioma"
done
# Contenido real (#115), no pares de ejemplo. Los agentes: Claude Code carga todo .md de .claude/agents/, así que su
# versión en español vive en .claude/i18n/agents/ y cada name: tiene que aparecer una sola vez en .claude/agents/.
for idioma in en es; do
  p="$TMP/real-completo-$idioma"
  copiar "$p"
  (cd "$p" && ./scripts/init-template.sh Demo main --lang "$idioma" >/dev/null 2>&1); tap_check $? "[real completo --lang <idioma>] el init termina bien" "[real completo --lang $idioma] el init termina bien"
  nombres=$(grep -h '^name:' "$p"/.claude/agents/*.md); repetidos=$(sort <<<"$nombres" | uniq -d); sueltos=$(find "$p/.claude/agents" -name '*.es.md')
  if [ -z "$repetidos" ] && [ "$(wc -l <<<"$nombres" | tr -d ' ')" = 3 ] && [ -z "$sueltos" ]; then r=0; else r=1; fi
  tap_check $r "[real completo --lang <idioma>] cada name: aparece una sola vez en .claude/agents/ (3 agentes, ningún .es.md)" "[real completo --lang $idioma] cada name: aparece una sola vez en .claude/agents/ (3 agentes, ningún .es.md)"
  ! [ -e "$p/.claude/i18n" ]; tap_check $? "[real completo --lang <idioma>] no queda .claude/i18n" "[real completo --lang $idioma] no queda .claude/i18n"
  # La regla de la rama base (<BRANCH_RULE>) sigue el idioma de la instalación, en AGENTS.md y en la convención.
  if [ "$idioma" = en ]; then regla='Only permanent branch'; otra='Única rama permanente'; else regla='Única rama permanente'; otra='Only permanent branch'; fi
  if grep -q "$regla" "$p/AGENTS.md" && grep -q "$regla" "$p/docs/github-naming-convention.md" && ! grep -rq "$otra" "$p/AGENTS.md" "$p/docs"; then r=0; else r=1; fi
  tap_check $r "[real completo --lang <idioma>] <BRANCH_RULE> sale en el idioma de la instalación (AGENTS.md y la convención)" "[real completo --lang $idioma] <BRANCH_RULE> sale en el idioma de la instalación (AGENTS.md y la convención)"
  # #175: con el mapa completado (sin los TODO de ejemplo), check-docs pasa entero en los dos idiomas: ningún enlace nombra un .es.md que el init borra.
  out=""
  tap_run out 0 python3 - "$p" <<'PYEOF'
import re, subprocess, sys
p = sys.argv[1]
mapa = p + "/docs/agents-map.json"
t = open(mapa, encoding="utf-8").read()
t = t.replace('"TODO/', '"?TODO/')
t = re.sub(r'("run": ")TODO[^"]*', r'\1true', t)
open(mapa, "w", encoding="utf-8").write(t)
r = subprocess.run([sys.executable, "scripts/agents/check-docs.py"], cwd=p, capture_output=True, text=True)
print(r.stdout + r.stderr)
# 0 y 1 son el veredicto del check; cualquier otro código (un crash) sale tal cual y el test se detiene
sys.exit(r.returncode if r.returncode not in (0, 1) else 0)
PYEOF
  tap_no_traceback "$out"
  grep -q '^Docs OK\.' <<<"$out"; tap_check $? "[real completo --lang <idioma>] check-docs pasa con el mapa completado (ningún enlace a un .es.md borrado)" "[real completo --lang $idioma] check-docs pasa con el mapa completado (ningún enlace a un .es.md borrado)"
  if [ "$idioma" = es ]; then
    grep -q 'Sos el implementador' "$p/.claude/agents/implementer.md" && grep -q '^# Implementar issue' "$p/.claude/skills/implement-issue/SKILL.md"
    tap_check $? "[real completo --lang es] el agente y la skill quedan en español"
  else
    grep -q 'You are the implementer' "$p/.claude/agents/implementer.md" && grep -q '^# Implement an issue' "$p/.claude/skills/implement-issue/SKILL.md"
    tap_check $? "[real completo --lang en] el agente y la skill quedan en inglés"
  fi
done
# Plantillas de .github/ (#115, parte 3): la del PR y las de issue siguen el idioma de la instalación, igual que los labels.
# Los formularios de issue (.yml) no pueden tener su hermano al lado (GitHub carga cada .yml de ISSUE_TEMPLATE):
# el español vive en .github/i18n/ISSUE_TEMPLATE/<nombre>.es.yml y --lang es lo mueve (como los agentes).
for combinacion in "completo en" "completo es" "chico en" "chico es"; do
  read -r modo idioma <<<"$combinacion"
  p="$TMP/gh-$modo-$idioma"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--small)
  (cd "$p" && ./scripts/init-template.sh Demo main --lang "$idioma" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); tap_check $? "[<modo> --lang <idioma> .github] el init termina bien" "[$modo --lang $idioma .github] el init termina bien"
  if [ "$idioma" = en ]; then
    pr='## What changes'; otro='## Qué cambia'; bug='What happens'; label='Something does not work as defined'; otro_label='Algo no funciona como está definido'
  else
    pr='## Qué cambia'; otro='## What changes'; bug='Qué pasa'; label='Algo no funciona como está definido'; otro_label='Something does not work as defined'
  fi
  if grep -qF "$pr" "$p/.github/pull_request_template.md" && ! grep -qF "$otro" "$p/.github/pull_request_template.md"; then r=0; else r=1; fi
  tap_check $r "[<modo> --lang <idioma> .github] la plantilla del PR está en el idioma de la instalación" "[$modo --lang $idioma .github] la plantilla del PR está en el idioma de la instalación"
  if [ "$modo" = completo ]; then
    if grep -qF "$bug" "$p/.github/ISSUE_TEMPLATE/1-bug.yml"; then r=0; else r=1; fi
    tap_check $r "[<modo> --lang <idioma> .github] el formulario de bug está en el idioma de la instalación" "[$modo --lang $idioma .github] el formulario de bug está en el idioma de la instalación"
    if grep -qF "$label" "$p/.github/labels.yml" && ! grep -qF "$otro_label" "$p/.github/labels.yml"; then r=0; else r=1; fi
    tap_check $r "[<modo> --lang <idioma> .github] las descripciones de labels.yml están en el idioma de la instalación" "[$modo --lang $idioma .github] las descripciones de labels.yml están en el idioma de la instalación"
    n=$(cd "$p/.github/ISSUE_TEMPLATE" && printf '%s ' * )
    es "$n" = "1-bug.yml 2-feature.yml 3-task.yml 4-audit.yml config.yml "; tap_check $? "[<modo> --lang <idioma> .github] ISSUE_TEMPLATE queda con los 4 formularios y config.yml (sin 5-trial ni duplicados)" "[$modo --lang $idioma .github] ISSUE_TEMPLATE queda con los 4 formularios y config.yml (sin 5-trial ni duplicados)"
  else
    ! [ -e "$p/.github/ISSUE_TEMPLATE" ]; tap_check $? "[<modo> --lang <idioma> .github] el modo chico no tiene formularios de issue (los borra su DELETE)" "[$modo --lang $idioma .github] el modo chico no tiene formularios de issue (los borra su DELETE)"
  fi
  es -z "$(find "$p/.github" \( -name '*.es.*' -o -name i18n \) | head -1)"; tap_check $? "[<modo> --lang <idioma> .github] no queda ningún .es.* ni .github/i18n" "[$modo --lang $idioma .github] no queda ningún .es.* ni .github/i18n"
  # Los literales que lee el CI: el inglés es el vigente (los alias en español los acepta el workflow, no la plantilla).
  if [ "$idioma" = en ]; then
    grep -q 'Red before implementing' "$p/.github/pull_request_template.md" && grep -q 'no tests: <reason>' "$p/.github/pull_request_template.md"
    tap_check $? "[<modo> --lang en .github] la plantilla del PR nombra los literales ingleses del CI (Red before implementing, no tests)" "[$modo --lang en .github] la plantilla del PR nombra los literales ingleses del CI (Red before implementing, no tests)"
  fi
done
grep -q 'Audit <area>: <finding>' "$TMP/gh-completo-en/.github/ISSUE_TEMPLATE/4-audit.yml"; tap_check $? "[completo --lang en .github] el formulario de auditoría usa 'Audit <area>: <finding>'"
grep -q 'Auditoría <área>: <hallazgo>' "$TMP/gh-completo-es/.github/ISSUE_TEMPLATE/4-audit.yml"; tap_check $? "[completo --lang es .github] el formulario de auditoría conserva 'Auditoría <área>: <hallazgo>'"
# Los ajustes del perfil chico sobre la plantilla del PR valen en los dos idiomas (sin label business-logic).
if ! grep -q 'business-logic' "$TMP/gh-chico-en/.github/pull_request_template.md" && ! grep -q 'business-logic' "$TMP/gh-chico-es/.github/pull_request_template.md"; then r=0; else r=1; fi
tap_check $r "[chico .github] la plantilla del PR no pide el label business-logic, en inglés ni en español"
# En la plantilla sin inicializar, cada formulario tiene su hermano con los mismos type, id y labels.
python3 - "$RAIZ" <<'PY'
import glob, os, re, sys
raiz = sys.argv[1]
mal = []
for en in sorted(glob.glob(f"{raiz}/.github/ISSUE_TEMPLATE/[0-9]*.yml")):
    es = f"{raiz}/.github/i18n/ISSUE_TEMPLATE/{os.path.basename(en)[:-4]}.es.yml"
    if not os.path.exists(es):
        mal.append(f"falta {es}"); continue
    ids = lambda f: [re.sub(r"\s+", " ", x) for x in re.findall(r"^\s*(?:- )?(?:type|id|labels):.*$", open(f, encoding="utf-8").read(), re.M)]
    if ids(en) != ids(es):
        mal.append(f"{os.path.basename(en)}: type/id/labels distintos")
print("\n".join(mal)); sys.exit(1 if mal else 0)
PY
tap_check $? "cada formulario de issue tiene su hermano en español con los mismos type, id y labels"
# El perfil chico tiene su hermano en español (#115, parte 3): --small gana al archivo completo en los dos idiomas, cada uno en el suyo
# (las skills chicas, de 63, 32 y 20 líneas, no las completas).
for idioma in en es; do
  p="$TMP/real-chico-$idioma"
  copiar "$p"
  (cd "$p" && ./scripts/init-template.sh Demo main --small --lang "$idioma" >/dev/null 2>&1); tap_check $? "[real chico --lang <idioma>] el init termina bien" "[real chico --lang $idioma] el init termina bien"
  # #152: en los dos idiomas el proyecto chico trae el mapa mínimo (solo red) y check-docs lo acepta.
  k=$(claves_mapa "$p/docs/agents-map.json"); [ "$k" = "['red']" ]; tap_check $? "[real chico --lang <idioma>] docs/agents-map.json tiene solo la sección red" "[real chico --lang $idioma] docs/agents-map.json tiene solo la sección red"
  (cd "$p" && python3 scripts/agents/check-docs.py >/dev/null 2>&1); tap_check $? "[real chico --lang <idioma>] check-docs pasa con el mapa mínimo, sin agents_map.py" "[real chico --lang $idioma] check-docs pasa con el mapa mínimo, sin agents_map.py"
  hermano() { if [ "$idioma" = es ]; then case "$1" in *.md) echo "${1%.md}.es.md" ;; *.txt) echo "${1%.txt}.es.txt" ;; esac; else echo "$1"; fi; }
  for sk in implement-issue create-issue update-docs; do
    # El init reemplaza los marcadores (<BASE_BRANCH>…): se comparan con esa sustitución.
    cmp -s <(sed 's/<BASE_BRANCH>/main/g; s/<PROJECT>/Demo/g' "$RAIZ/profiles/small/$(hermano ".claude/skills/$sk/SKILL.md")") "$p/.claude/skills/$sk/SKILL.md"
    tap_check $? "[real chico --lang <idioma>] <sk> es la del perfil chico en ese idioma (contenido igual)" "[real chico --lang $idioma] $sk es la del perfil chico en ese idioma (contenido igual)"
  done
  # Los archivos del perfil que tienen hermano completo (AGENTS.md, docs/README.md, la convención, llms.txt) siguen siendo los suyos.
  for f in AGENTS.md docs/README.md docs/github-naming-convention.md docs/llms.txt docs/architecture.md; do
    # El init también reemplaza <DATE>, <BRANCH_RULE> y <COMMIT_LANG>: se compara el largo y el título.
    src="$RAIZ/profiles/small/$(hermano "$f")"
    if [ "$(wc -l <"$src" | tr -d ' ')" = "$(wc -l <"$p/$f" | tr -d ' ')" ] && [ "$(head -1 "$src" | sed 's/<PROJECT>/Demo/')" = "$(head -1 "$p/$f")" ]; then r=0; else r=1; fi
    tap_check $r "[real chico --lang <idioma>] <f> es el del perfil chico en ese idioma (mismo largo y título)" "[real chico --lang $idioma] $f es el del perfil chico en ese idioma (mismo largo y título)"
  done
  # Nada en el idioma equivocado: ni la regla de la rama base, ni las secciones de AGENTS.md que nombran las skills.
  if [ "$idioma" = en ]; then
    marcas='Qué es|Autonomía|Consulta antes|Única rama|Los PRs de trabajo|Cuerpo del PR|Convenci[oó]n de GitHub|Documentación de'
    grep -q '^## Agent autonomy' "$p/AGENTS.md" && grep -q 'Agent autonomy' "$p/.claude/skills/debug/SKILL.md"
    tap_check $? "[real chico --lang en] AGENTS.md tiene la sección que nombran las skills (Agent autonomy)"
  else
    marcas='What it is|Agent autonomy|Must ask first|Only permanent branch|Working PRs go|GitHub convention'
    grep -q '^## Autonomía del agente' "$p/AGENTS.md"; tap_check $? "[real chico --lang es] AGENTS.md tiene la sección Autonomía del agente"
  fi
  if grep -rEq "$marcas" "$p/AGENTS.md" "$p/docs" "$p/.claude/skills" 2>/dev/null; then r=1; else r=0; fi
  tap_check $r "[real chico --lang <idioma>] ningún archivo del perfil chico mezcla el otro idioma (AGENTS.md, docs/, skills)" "[real chico --lang $idioma] ningún archivo del perfil chico mezcla el otro idioma (AGENTS.md, docs/, skills)"
  if [ "$idioma" = en ]; then regla='Only permanent branch'; else regla='Única rama permanente'; fi
  grep -q "$regla" "$p/AGENTS.md" && grep -q "$regla" "$p/docs/github-naming-convention.md"; tap_check $? "[real chico --lang <idioma>] <BRANCH_RULE> sale en el idioma de la instalación" "[real chico --lang $idioma] <BRANCH_RULE> sale en el idioma de la instalación"
  # Los labels del perfil: nombres y colores iguales en los dos idiomas, descripciones en el idioma de la instalación.
  if [ "$idioma" = en ]; then d='Something does not work as it should'; else d='Algo no funciona como debería'; fi
  grep -qF "$d" "$p/.github/labels.yml"; tap_check $? "[real chico --lang <idioma>] las descripciones de labels.yml están en el idioma de la instalación" "[real chico --lang $idioma] las descripciones de labels.yml están en el idioma de la instalación"
  if [ "$idioma" = en ]; then
    # shellcheck disable=SC2016
    grep -qF 'the PR says so in "Business logic affected"' "$p/docs/decisions/README.md"; tap_check $? "[real chico --lang en] docs/decisions/README.md cita el encabezado vigente de la plantilla del PR"
  fi
  largos=$(wc -l <"$p/.claude/skills/implement-issue/SKILL.md" | tr -d ' ')/$(wc -l <"$p/.claude/skills/create-issue/SKILL.md" | tr -d ' ')/$(wc -l <"$p/.claude/skills/update-docs/SKILL.md" | tr -d ' ')
  if [ "$largos" = 63/32/20 ]; then r=0; else r=1; fi
  tap_check $r "[real chico --lang <idioma>] implement-issue, create-issue y update-docs tienen el largo del perfil (63, 32, 20)" "[real chico --lang $idioma] implement-issue, create-issue y update-docs tienen el largo del perfil (63, 32, 20)"
  ! [ -e "$p/.claude/agents" ] && ! [ -e "$p/.claude/i18n" ]; tap_check $? "[real chico --lang <idioma>] sin agentes ni .claude/i18n" "[real chico --lang $idioma] sin agentes ni .claude/i18n"
done
# R-6 (ADR-001): la descripción de los commits y de los títulos de PR sigue a --lang. <COMMIT_LANG> es el marcador; el kit
# se queda con descripciones en español (lo dice su AGENTS.md en un bloque template: que el init borra).
for combinacion in "completo en English" "completo es español" "chico en English" "chico es español"; do
  read -r modo idioma lengua <<<"$combinacion"
  p="$TMP/commitlang-$modo-$idioma"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--small)
  (cd "$p" && ./scripts/init-template.sh Demo main --lang "$idioma" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1); tap_check $? "[<modo> --lang <idioma> R-6] el init termina bien" "[$modo --lang $idioma R-6] el init termina bien"
  ! grep -rq '<COMMIT_LANG>' "$p" --exclude-dir=.git; tap_check $? "[<modo> --lang <idioma> R-6] no queda ningún <COMMIT_LANG> sin reemplazar" "[$modo --lang $idioma R-6] no queda ningún <COMMIT_LANG> sin reemplazar"
  grep -Eq "(description in|descripción en|descripcion en) $lengua" "$p/AGENTS.md"; tap_check $? "[<modo> --lang <idioma> R-6] AGENTS.md fija la descripción de los commits en <lengua>" "[$modo --lang $idioma R-6] AGENTS.md fija la descripción de los commits en $lengua"
  if [ "$idioma" = en ]; then titulo='Structured validation of the red test'; else titulo='Validación estructurada del test en rojo'; fi
  k="$p/docs/decisions/kit/ADR-002-structured-red-validation.md"
  [ -f "$k" ] && grep -qF "$titulo" "$k" && ! ls "$p"/docs/decisions/kit/*.es.md >/dev/null 2>&1
  tap_check $? "[<modo> --lang <idioma>] docs/decisions/kit/ADR-002 queda en el idioma de la instalación y sin .es.md" "[$modo --lang $idioma] docs/decisions/kit/ADR-002 queda en el idioma de la instalación y sin .es.md"
  if [ "$modo" = completo ]; then
    grep -Eq "(is written in|se escribe en) $lengua" "$p/docs/github-naming-convention.md" && grep -Eq "(the description in|descripción en) $lengua" "$p/.claude/skills/git-workflow/SKILL.md"
    tap_check $? "[<modo> --lang <idioma> R-6] la convención y la skill git-workflow dicen <lengua>" "[$modo --lang $idioma R-6] la convención y la skill git-workflow dicen $lengua"
  fi
  if [ "$modo" = completo ]; then
    # La línea que sigue al bloque DECIDED de la convención es en blanco (si no, la regla siguiente se vuelve parte de la cita).
    n=$(grep -nE '(is written in|se escribe en) ' "$p/docs/github-naming-convention.md" | head -1 | cut -d: -f1)
    if [ -n "$n" ] && [ -z "$(sed -n "$((n + 1))p" "$p/docs/github-naming-convention.md")" ]; then r=0; else r=1; fi; tap_check $r "[<modo> --lang <idioma> R-6] después del bloque DECIDED de la convención queda una línea en blanco" "[$modo --lang $idioma R-6] después del bloque DECIDED de la convención queda una línea en blanco"
  fi
  ! grep -rq 'the template itself\|la plantilla misma' "$p/AGENTS.md" "$p/docs" "$p/.claude/skills" 2>/dev/null; tap_check $? "[<modo> --lang <idioma> R-6] el aviso del kit (descripciones en español en este repo) no llega al proyecto" "[$modo --lang $idioma R-6] el aviso del kit (descripciones en español en este repo) no llega al proyecto"
done
if grep -q '<COMMIT_LANG>' "$RAIZ/AGENTS.md" && grep -q '<COMMIT_LANG>' "$RAIZ/AGENTS.es.md" && grep -q '<COMMIT_LANG>' "$RAIZ/docs/github-naming-convention.md" && grep -q '<COMMIT_LANG>' "$RAIZ/.claude/skills/git-workflow/SKILL.md"; then r=0; else r=1; fi
tap_check $r "la plantilla trae el marcador <COMMIT_LANG> donde se fija el idioma de los commits (AGENTS en/es, convención, git-workflow)"
if grep -q 'template:start' "$RAIZ/AGENTS.md" && grep -qi 'in Spanish' "$RAIZ/AGENTS.md" \
  && grep -qi 'in Spanish' "$RAIZ/docs/github-naming-convention.md" && grep -qi 'in Spanish' "$RAIZ/.claude/skills/git-workflow/SKILL.md"; then r=0; else r=1; fi
tap_check $r "el kit dice, en un bloque template:, que sus commits van en español (AGENTS.md, convención y git-workflow: quien lea solo la skill o la convención también lo sabe)"

# El proyecto instalado tiene un solo idioma: un docs/*.es.md propio no activa la paridad (interruptor parity).
p="$TMP/lang-propio"
copiar "$p"
(cd "$p" && ./scripts/init-template.sh Demo >/dev/null 2>&1 && git add -A && git commit -qm init)
grep -q '"parity": false' "$p/docs/agents-map.json"; tap_check $? "[completo] el init deja parity apagado en el mapa del proyecto"
! grep -q 'CLAUDE.md' <(python3 -c "import json; print(json.load(open('$p/docs/agents-map.json'))['parity_ignore'])"); tap_check $? "[completo] el init saca CLAUDE.md del parity_ignore del proyecto (es ruido de la plantilla)"
printf '# Guía\n' >"$p/docs/manual.es.md"
c=0; s=$(trap - ERR; cd "$p" && python3 scripts/agents/check-docs.py 2>&1) || c=$?; tap_status "$c" 1; tap_no_traceback "$s"
[ -f "$p/docs/manual.es.md" ] && ! grep -q 'manual' <<<"$s"; tap_check $? "[completo] un docs/manual.es.md propio no hace fallar el CI de docs del proyecto"
# Un .yml del perfil chico gana a su hermano completo, cualquiera sea el archivo (no solo labels.yml).
p="$TMP/yml-general"
copiar "$p"
echo "FULL-ES" >"$p/.github/foo.es.yml"; echo "FULL-EN" >"$p/.github/foo.yml"; echo "SMALL-EN" >"$p/profiles/small/.github/foo.yml"
(cd "$p" && git add -A && git commit -qm foo && ./scripts/init-template.sh Demo main --small --lang es >/dev/null 2>&1)
grep -qx SMALL-EN "$p/.github/foo.yml" && ! [ -e "$p/.github/foo.es.yml" ]; tap_check $? "[chico --lang es] un .yml del perfil gana a su hermano .es.yml completo (regla general, no solo labels.yml)"
p="$TMP/lang-default"
copiar "$p"; con_pares "$p"
(cd "$p" && ./scripts/init-template.sh Demo >/dev/null 2>&1); tap_check $? "[sin --lang] el init termina bien"
grep -qx SAMPLE-EN "$p/SAMPLE.md" && python3 -c "import json,sys; sys.exit(0 if json.load(open('$p/.agent-kit.json')).get('language') == 'en' else 1)"
tap_check $? "[sin --lang] el idioma por defecto es en y queda registrado"
for malo in "--lang fr" "--lang" "--lang="; do
  p="$TMP/lang-malo"; rm -rf "$p"; copiar "$p"
  c=0
  # shellcheck disable=SC2086  # $malo se parte a propósito en opción y valor
  s=$(trap - ERR; cd "$p" && ./scripts/init-template.sh Demo $malo 2>&1) || c=$?; tap_status "$c" 1
  [ "$c" -ne 0 ] && grep -q -- '--lang' <<<"$s" && [ -e "$p/scripts/init-template.sh" ]
  tap_check $? "el init rechaza '<malo>' con un mensaje sobre --lang y sin tocar nada" "el init rechaza '$malo' con un mensaje sobre --lang y sin tocar nada"
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
    tap_check $? "[<modo>, base <base>] <w>.yml corre en los pushes a <esperado>" "[$modo, base $base] $w.yml corre en los pushes a $esperado"
  done
  # Un test del proyecto instalado que falla o se cae corta la corrida: tap_run muestra el final de su salida
  # (las líneas FAIL) en el Bail out!, y una falla que no se repite (#77) se puede investigar con el log del CI.
  # El primer test anidado que falla corta toda la corrida (falla cerrada, ADR-002): el tap_ok de abajo no puede fallar.
  while read -r t; do
    tap_run salida 0 bash "$p/$t"
  done < <(cd "$p" && git ls-files '*test-*.sh')
  tap_ok "[<modo>, base <base>] los test-*.sh del proyecto instalado pasan todos" "[$modo, base $base] los test-*.sh del proyecto instalado pasan todos"
done

# check-docs.py falla si AGENTS.md dice que algo está ignorado y no lo está.
p="$TMP/completo"
c=0; s=$(trap - ERR; cd "$p" && python3 scripts/agents/check-docs.py 2>&1) || c=$?; tap_status "$c" 1; tap_no_traceback "$s"
! grep -q 'is ignored, but' <<<"$s"; tap_check $? "check-docs.py no se queja si lo que AGENTS.md dice ignorado lo está"
# Una frase que dice que algo NO está ignorado no es una afirmación de que lo esté.
cp "$p/AGENTS.md" "$TMP/AGENTS.md"
# shellcheck disable=SC2016  # backticks de Markdown literales
echo '- `dist/` no está ignorado: se commitea.' >>"$p/AGENTS.md"
# shellcheck disable=SC2016  # backticks de Markdown literales
echo '- `build/` is not ignored: it is committed.' >>"$p/AGENTS.md"
c=0; s=$(trap - ERR; cd "$p" && python3 scripts/agents/check-docs.py 2>&1) || c=$?; tap_status "$c" 1; tap_no_traceback "$s"
! grep -q 'dist/\|build/' <<<"$s"; tap_check $? "check-docs.py no se queja de una frase que dice que algo no está ignorado"
cp "$TMP/AGENTS.md" "$p/AGENTS.md"
(cd "$p" && git rm -q .gitignore)
c=0; s=$(trap - ERR; cd "$p" && python3 scripts/agents/check-docs.py 2>&1) || c=$?; tap_status "$c" 1
[ "$c" -ne 0 ] && grep -q 'AGENTS.md.*\.env.*ignored' <<<"$s"; tap_check $? "check-docs.py falla si AGENTS.md dice que .env* está ignorado y no lo está"
# Una línea que afirma una cosa y niega otra: la negación no tapa la afirmación.
grep -Ev 'ignorad|ignored' "$TMP/AGENTS.md" >"$p/AGENTS.md"
# shellcheck disable=SC2016  # backticks de Markdown literales
echo '- `.env*` están ignorados; `dist/` no está ignorado.' >>"$p/AGENTS.md"
c=0; s=$(trap - ERR; cd "$p" && python3 scripts/agents/check-docs.py 2>&1) || c=$?; tap_status "$c" 1; tap_no_traceback "$s"
grep -q 'AGENTS.md.*\.env.*ignored' <<<"$s" && ! grep -q 'dist/' <<<"$s"; tap_check $? "check-docs.py valida la afirmación aunque la misma línea niegue otra cosa"

# La negación se decide por cada patrón, aunque la afirmación y la negación estén en la misma frase.
# Sin .gitignore: tiene que reclamar por .env* y nunca por dist/.
while IFS= read -r frase; do
  grep -Ev 'ignorad|ignored' "$TMP/AGENTS.md" >"$p/AGENTS.md"; printf -- '- %s\n' "$frase" >>"$p/AGENTS.md"
  c=0; s=$(trap - ERR; cd "$p" && python3 scripts/agents/check-docs.py 2>&1) || c=$?; tap_status "$c" 1; tap_no_traceback "$s"
  grep -q 'AGENTS.md.*\.env.*ignored' <<<"$s" && ! grep -q 'dist/' <<<"$s"; tap_check $? "check-docs.py valida .env* en: <frase>" "check-docs.py valida .env* en: $frase"
done <<'FRASES'
`.env*` está ignorado y `dist/` no está ignorado.
`dist/` no está ignorado, `.env*` sí está ignorado.
`.env*` no se commitea porque está ignorado.
`dist/` nunca está ignorado; `.env*` está ignorado.
Están ignorados: `.env*`.
`.env*` is ignored and `dist/` is not ignored.
`dist/` is not ignored, `.env*` is ignored.
`.env*` is never committed because it is ignored.
`dist/` is never ignored; `.env*` is ignored.
`dist/` isn't ignored, `.env*` is ignored.
Ignored: `.env*`.
FRASES

# La línea del flujo elegida en el init (#181): statusLine en .claude/settings.json, registrada para update.py y grow.py.
for modo in completo chico; do
  p="$TMP/flow-$modo"
  copiar "$p"
  extra=(); [ "$modo" = chico ] && extra=(--small)
  (cd "$p" && ./scripts/init-template.sh Demo main ${extra[@]+"${extra[@]}"} --flow-line >/dev/null 2>&1)
  tap_check $? "[<modo>] el init con --flow-line termina bien" "[$modo] el init con --flow-line termina bien"
  python3 - "$p" <<'PY'
import json, sys
p = sys.argv[1]
ajustes = json.load(open(f"{p}/.claude/settings.json"))
assert "scripts/agents/flow.py" in ajustes["statusLine"]["command"], ajustes
assert ajustes["statusLine"]["refreshInterval"] == 1, ajustes
assert ajustes["hooks"]["PreToolUse"], "the guardrails hook stays"
for evento, modo in (("UserPromptSubmit", "on"), ("Stop", "off")):
    assert any(h["command"].endswith("--busy " + modo) for g in ajustes["hooks"][evento] for h in g["hooks"]), evento
assert json.load(open(f"{p}/.agent-kit.json"))["flow_line"] is True
PY
  tap_check $? "[<modo>] --flow-line agrega el statusLine (cada 1 s) y los hooks --busy, conserva el de guardrails y registra flow_line: true" "[$modo] --flow-line agrega el statusLine (cada 1 s) y los hooks --busy, conserva el de guardrails y registra flow_line: true"
  # El comando del statusLine, corrido como lo corre Claude Code: en un proyecto no aparece la marca.
  (cd "$p" && git add -A && git commit -qm init && git checkout -qb claude/7-algo)
  cmd=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$p/.claude/settings.json")
  s=$(cd "$p" && printf '{"workspace":{"current_dir":"%s"}}' "$p" | NO_COLOR=1 PATH="/usr/bin:/bin" sh -c "$cmd" 2>&1)
  grep -q '▸implement' <<<"$s" && grep -q '#7' <<<"$s" && ! grep -q '(● ●)' <<<"$s"
  tap_check $? "[<modo>] el statusLine del proyecto muestra el paso y no la carita de la marca" "[$modo] el statusLine del proyecto muestra el paso y no la carita de la marca"
  # Con otro cwd (Claude Code puede correr el comando desde otro directorio) CLAUDE_PROJECT_DIR lleva al script; sin él, git rev-parse.
  s=$(cd "$TMP" && printf '{"workspace":{"current_dir":"%s"}}' "$p" | NO_COLOR=1 CLAUDE_PROJECT_DIR="$p" PATH="/usr/bin:/bin" sh -c "$cmd" 2>&1)
  grep -q '▸implement' <<<"$s" && grep -q 'CLAUDE_PROJECT_DIR' <<<"$cmd" && grep -q 'rev-parse --show-toplevel' <<<"$cmd"
  tap_check $? "[<modo>] el comando del statusLine prueba CLAUDE_PROJECT_DIR y después git rev-parse" "[$modo] el comando del statusLine prueba CLAUDE_PROJECT_DIR y después git rev-parse"
  # La guía de la línea del flujo nombra a Barrilete solo en bloques brand: el proyecto no los trae, y sus enlaces y anclas siguen sanos.
  python3 - "$p" "$modo" <<'PY'
import glob, subprocess, sys
p, modo = sys.argv[1:3]
guias = glob.glob(f"{p}/docs/guides/flow-line*.md")
assert bool(guias) == (modo == "completo"), "the guide stays in the full project and goes with docs/guides in the small one"
for g in guias:
    t = open(g, encoding="utf-8").read()
    assert "barrilete" not in t.lower() and "brand:" not in t, g
r = subprocess.run([sys.executable, "scripts/agents/check-docs.py"], cwd=p, capture_output=True, text=True)
assert "flow-line" not in r.stdout + r.stderr, r.stdout + r.stderr
PY
  tap_check $? "[<modo>] la guía flow-line del proyecto no menciona a Barrilete y check-docs no marca nada de ella" "[$modo] la guía flow-line del proyecto no menciona a Barrilete y check-docs no marca nada de ella"
done
p="$TMP/no-flow"
copiar "$p"
(cd "$p" && ./scripts/init-template.sh Demo main --no-flow-line >/dev/null 2>&1) && ! grep -q statusLine "$p/.claude/settings.json"
tap_check $? "--no-flow-line se acepta y no agrega el statusLine"

tap_done
