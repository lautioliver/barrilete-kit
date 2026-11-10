#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2319,SC2016  # out lo asigna tap_run; el $? de una aserción es el de la aserción; los backticks de las reglas son texto
# Tests de scripts/agents/sync-rules (#286, ADR-006 D7): genera las reglas por rol, AGENTS.md y classes.yml desde
# barrilete-rules en el SHA de .barrilete/rules.lock. Usa repos git locales: no toca la red.
# Salida: 0 ok; 3 hay un problema (regla inválida, check ausente, clone que falla, --check distinto); 64 uso inválido.
# El 1 y el 2 quedan para un crash (un traceback de Python sale con 1): tap_run los toma como crash, no como un caso fallido.
# Uso: bash scripts/agents/test-sync-rules.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
SYNC="$RAIZ/scripts/agents/sync-rules"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-sync-rules-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
out=""

regla() { # regla <id> <status> <applies_to> <scope> <texto> [extra del frontmatter]
  mkdir -p "$TMP/rules/rules"
  printf -- '---\nid: %s\nstatus: %s\norigin: observed\napplies_to: %s\nscope: %s\nclasses: []\nseverity: %s\naccepted: 2026-11-01\n%s---\n%s\n\n## Por qué\nPorque sí.\n' \
    "$1" "$2" "$3" "$4" "${7:-fix}" "${6:+$6
}" "$5" >"$TMP/rules/rules/$1.md"
}
# El repo de reglas, con dos versiones: v1 y v2 (cambia el texto de impl-uno).
git init -q -b main "$TMP/rules"
printf -- '- id: pr-metadata\n  description: el cuerpo del PR miente\n- id: stale-docs\n  description: docs viejas\n' >"$TMP/rules/classes.yml"
regla impl-uno accepted "[implementer]" '"*"' "Regla uno v1 del implementer."
regla rev-uno accepted "[reviewer]" '"*"' "Regla del reviewer."
regla todos accepted '"*"' '"*"' "Regla general para todos."
regla vieja deprecated "[implementer]" '"*"' "Regla retirada que no entra."
regla propuesta proposed "[implementer]" '"*"' "Regla propuesta que no entra."
regla solo-otro accepted "[implementer]" "[otro-proyecto]" "Regla de otro proyecto."
regla solo-mio accepted "[implementer]" "[mi-proyecto]" "Regla de mi proyecto."
regla con-check accepted "[implementer]" '"*"' "Regla con check." $'check: pr-metadata\nfail_message: "El PR miente: corregilo o escalá."\n' block
regla vieja-con-check deprecated "[implementer]" '"*"' "Regla retirada con check." $'check: viejo-check\nfail_message: "retirada"\n' block
regla otro-con-check accepted "[implementer]" "[otro-proyecto]" "Regla de otro proyecto con check." $'check: otro-check\nfail_message: "de otro"\n' block
git -C "$TMP/rules" add -A && git -C "$TMP/rules" commit -qm v1
SHA1=$(git -C "$TMP/rules" rev-parse HEAD)
regla impl-uno accepted "[implementer]" '"*"' "Regla uno v2 del implementer."
git -C "$TMP/rules" add -A && git -C "$TMP/rules" commit -qm v2
SHA2=$(git -C "$TMP/rules" rev-parse HEAD)

proyecto() { # proyecto <dir> <sha>: un proyecto con agentes en en y es, AGENTS en en y es y un check
  local p=$1
  rm -rf "$p"; mkdir -p "$p/.barrilete" "$p/.claude/agents" "$p/.claude/i18n/agents" "$p/docs/agents" "$p/scripts/agents/checks"
  printf 'repo=o/rules\nsha=%s\n' "$2" >"$p/.barrilete/rules.lock"
  printf '{ "project": "mi-proyecto", "mode": "full" }\n' >"$p/.agent-kit.json"
  for r in implementer reviewer; do
    printf -- '---\nname: %s\n---\nTexto propio del %s.\n' "$r" "$r" >"$p/.claude/agents/$r.md"
    printf -- '---\nname: %s\n---\nTexto propio (es) del %s.\n' "$r" "$r" >"$p/.claude/i18n/agents/$r.es.md"
  done
  printf '# AGENTS\n\nTexto propio de AGENTS.\n' >"$p/AGENTS.md"; printf '# AGENTS es\n\nTexto propio de AGENTS es.\n' >"$p/AGENTS.es.md"
  printf '# vieja\n- id: vieja-clase\n' >"$p/docs/agents/classes.yml"
  printf '#!/bin/sh\nexit 0\n' >"$p/scripts/agents/checks/pr-metadata"; chmod +x "$p/scripts/agents/checks/pr-metadata"
  printf '#!/usr/bin/env python3\n' >"$p/scripts/agents/verify.py"  # sin verify.py (el perfil chico) los checks no corren
}
reglas() { # reglas <archivo>: las líneas `- ...` entre los marcadores ("" si no hay sección)
  sed -n '/<!-- rules:begin/,/<!-- rules:end -->/p' "$1" | grep '^- ' || true
}
sync() { tap_run out "$1" "$SYNC" --root "$P" --url "$TMP/rules" "${@:2}"; }

P="$TMP/p"; proyecto "$P" "$SHA1"

# 1. Una corrida genera la sección de cada rol entre marcadores: exactamente sus reglas, `- <texto> (`<id>`)` por id.
# Un archivo sin sección da una lista vacía, que no es la esperada: ningún caso pasa en vacío.
sync 0
IMPL_V1=$'- Regla con check. (`con-check`) validated by `verify.py`: pr-metadata\n- Regla uno v1 del implementer. (`impl-uno`)\n- Regla de mi proyecto. (`solo-mio`)'
[ "$(reglas "$P/.claude/agents/implementer.md")" = "$IMPL_V1" ]; tap_check $? "implementer: recibe sus reglas, y solo las de su rol, accepted y de su proyecto"
[ "$(reglas "$P/.claude/agents/reviewer.md")" = '- Regla del reviewer. (`rev-uno`)' ]; tap_check $? "reviewer: recibe solo su regla"
[ "$(reglas "$P/.claude/i18n/agents/implementer.es.md")" = "$IMPL_V1" ]; tap_check $? "implementer (es): recibe las mismas reglas, sin traducir"
grep -q 'Texto propio del implementer.' "$P/.claude/agents/implementer.md"; tap_check $? "implementer: lo que está fuera de los marcadores se conserva"

# 3. Las generales (applies_to *) van a AGENTS.md y AGENTS.es.md, no a los agentes.
[ "$(reglas "$P/AGENTS.md")" = '- Regla general para todos. (`todos`)' ]; tap_check $? "AGENTS.md: recibe solo las reglas generales"
[ "$(reglas "$P/AGENTS.es.md")" = '- Regla general para todos. (`todos`)' ]; tap_check $? "AGENTS.es.md: recibe solo las reglas generales"
grep -q 'Texto propio de AGENTS.' "$P/AGENTS.md"; tap_check $? "AGENTS.md: lo propio se conserva"

# 4. Las dos versiones: el agente recibe exactamente la del SHA del lock (condición 1 de D11).
[ "$(reglas "$P/.claude/agents/implementer.md")" = "$IMPL_V1" ]; tap_check $? "SHA del lock: con el lock en v1 no llega el texto de v2, aunque main ya lo tenga"
printf 'repo=o/rules\nsha=%s\n' "$SHA2" >"$P/.barrilete/rules.lock"
sync 0
IMPL_V2=${IMPL_V1//v1/v2}
[ "$(reglas "$P/.claude/agents/implementer.md")" = "$IMPL_V2" ]; tap_check $? "SHA del lock: al subir el lock a v2 el agente recibe exactamente v2 (la sección se reemplaza)"
n=$(grep -c '<!-- rules:begin' "$P/.claude/agents/implementer.md" || true); [ "$n" = 1 ]; tap_check $? "regenerar: queda un solo marcador de inicio"
grep -q "$SHA2" "$P/.claude/agents/implementer.md"; tap_check $? "el marcador dice el SHA con el que se generó"

# 5. classes.yml: la copia del kit sale de la de barrilete-rules.
grep -q 'id: stale-docs' "$P/docs/agents/classes.yml"; tap_check $? "classes.yml: la copia del kit trae las clases de barrilete-rules"
n=$(grep -c 'vieja-clase' "$P/docs/agents/classes.yml" || true); [ "$n" = 0 ]; tap_check $? "classes.yml: reemplaza la copia provisional"
grep -qi 'generated' "$P/docs/agents/classes.yml"; tap_check $? "classes.yml: avisa que está generada"

# 6. Idempotencia y --check (para el CI de la parte 3).
cp -R "$P" "$TMP/antes"
sync 0
diff -r "$TMP/antes" "$P" >/dev/null; tap_check $? "una segunda corrida no cambia nada"
sync 0 --check
[ "$TAP_RC" = 0 ]; tap_check $? "--check: lo generado coincide con el lock (sale 0)"
printf 'a mano\n' >>"$P/AGENTS.md"
sed -i.bak 's/Regla general para todos\./Regla EDITADA a mano./' "$P/AGENTS.md"; rm -f "$P/AGENTS.md.bak"
sync 3 --check
grep -q 'AGENTS.md' <<<"$out"; tap_check $? "--check: una sección editada a mano falla y nombra el archivo"
sync 0
[ "$(reglas "$P/AGENTS.md")" = '- Regla general para todos. (`todos`)' ]; tap_check $? "sin --check: regenera la sección y pisa la edición a mano"
grep -q 'a mano' "$P/AGENTS.md"; tap_check $? "sin --check: el texto propio fuera de los marcadores sobrevive"

# 7. Un check de una regla accepted tiene que existir en scripts/agents/checks/ del kit.
rm "$P/scripts/agents/checks/pr-metadata"
sync 3
grep -q 'pr-metadata' <<<"$out"; tap_check $? "check ausente: falla y nombra el check"
grep -q 'con-check' <<<"$out"; tap_check $? "check ausente: nombra la regla"
printf '#!/bin/sh\nexit 0\n' >"$P/scripts/agents/checks/pr-metadata"
sync 0
[ "$TAP_RC" = 0 ]; tap_check $? "check presente: sale 0"

# 8. Reglas propias del proyecto (.barrilete/rules/).
mkdir -p "$P/.barrilete/rules"
printf -- '---\nid: propia\nstatus: accepted\norigin: human\napplies_to: [implementer]\nscope: "*"\nclasses: []\nseverity: suggestion\naccepted: 2026-11-07\n---\nRegla propia del proyecto.\n' >"$P/.barrilete/rules/propia.md"
sync 0
[ "$(reglas "$P/.claude/agents/implementer.md")" = "$(printf '%s\n%s\n%s\n%s' '- Regla con check. (`con-check`) validated by `verify.py`: pr-metadata' '- Regla uno v2 del implementer. (`impl-uno`)' '- Regla propia del proyecto. (`propia`)' '- Regla de mi proyecto. (`solo-mio`)')" ]; tap_check $? "reglas propias: se suman a las del rol, en orden por id"
sed 's/^id: propia/id: impl-uno/' "$P/.barrilete/rules/propia.md" >"$P/.barrilete/rules/impl-uno.md"; rm "$P/.barrilete/rules/propia.md"
sync 3
grep -q 'impl-uno' <<<"$out"; tap_check $? "reglas propias: un id que choca con el de barrilete-rules falla y lo nombra"
rm -rf "$P/.barrilete/rules"

# 9. Sin .claude/agents (perfil chico) no falla: solo llegan las generales a AGENTS.md.
proyecto "$TMP/chico" "$SHA1"; rm -rf "$TMP/chico/.claude" "$TMP/chico/docs/agents" "$TMP/chico/AGENTS.es.md"
tap_run out 0 "$SYNC" --root "$TMP/chico" --url "$TMP/rules"
[ "$(reglas "$TMP/chico/AGENTS.md")" = '- Regla general para todos. (`todos`)' ]; tap_check $? "sin .claude/agents: sale bien y AGENTS.md recibe las generales"

# 10. El lock lo declara el repo; sin --url se arma https://github.com/<repo>.git (acá desviado a una carpeta local).
proyecto "$TMP/p2" "$SHA1"; mkdir -p "$TMP/gh/o"; cp -R "$TMP/rules" "$TMP/gh/o/rules.git"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$TMP/gh/.insteadOf" GIT_CONFIG_VALUE_0="https://github.com/" tap_run out 0 "$SYNC" --root "$TMP/p2"
[ "$(reglas "$TMP/p2/.claude/agents/implementer.md")" = "$IMPL_V1" ]; tap_check $? "sin --url: clona https://github.com/<repo>.git del lock"

# 11. Errores claros, sin traceback.
proyecto "$TMP/e" "$SHA1"; rm "$TMP/e/.barrilete/rules.lock"
tap_run out 3 "$SYNC" --root "$TMP/e" --url "$TMP/rules"
grep -q 'rules.lock' <<<"$out"; tap_check $? "sin rules.lock: falla y lo nombra"
tap_no_traceback "$out"
printf 'repo=o/rules\nsha=nope\n' >"$TMP/e/.barrilete/rules.lock"
tap_run out 3 "$SYNC" --root "$TMP/e" --url "$TMP/rules"
grep -q 'sha' <<<"$out"; tap_check $? "sha que no es un SHA: falla y dice sha"
printf 'repo=o/rules\nsha=%s\n' "0000000000000000000000000000000000000000" >"$TMP/e/.barrilete/rules.lock"
tap_run out 3 "$SYNC" --root "$TMP/e" --url "$TMP/rules"
grep -q '0000000' <<<"$out"; tap_check $? "SHA que no existe en el repo: falla y lo nombra"
tap_no_traceback "$out"
printf 'repo=o/rules\nsha=%s\n' "$SHA1" >"$TMP/e/.barrilete/rules.lock"
tap_run out 3 "$SYNC" --root "$TMP/e" --url "$TMP/no-existe"
grep -qi 'clone\|clonar' <<<"$out"; tap_check $? "clone que falla: falla y dice que no pudo clonar"
tap_no_traceback "$out"
tap_run out 64 "$SYNC" --root "$TMP/e" --nope
grep -qi 'usage\|uso' <<<"$out"; tap_check $? "opción desconocida: sale 64 con el uso"

# 12. Una regla mal formada frena la corrida y no deja los archivos a medias.
git -C "$TMP/rules" checkout -q -b mala "$SHA1"
printf -- '---\nid: rota\nstatus: aceptada\n---\nx\n' >"$TMP/rules/rules/rota.md"
git -C "$TMP/rules" add -A && git -C "$TMP/rules" commit -qm rota; SHAM=$(git -C "$TMP/rules" rev-parse HEAD)
proyecto "$TMP/m" "$SHAM"
cp -R "$TMP/m" "$TMP/m-antes"
tap_run out 3 "$SYNC" --root "$TMP/m" --url "$TMP/rules"
grep -q 'rota' <<<"$out"; tap_check $? "regla mal formada: falla y nombra la regla"
diff -r "$TMP/m-antes" "$TMP/m" >/dev/null; tap_check $? "regla mal formada: no escribe ningún archivo"
git -C "$TMP/rules" checkout -q main

# 13. El manifiesto de checks (#287, ADR-006 D8): .barrilete/checks.json lo escribe sync-rules y lo lee verify.py.
# Lista el check de cada regla accepted que aplica al proyecto, con su regla y su fail_message; nada más.
leer() { [ -f "$1" ] && cat "$1"; }  # el contenido, o nada si el archivo no existe (un caso falla, no un crash)
CHECKS_UNO=$(printf '%s\n' '{' '  "checks": [' '    {' '      "id": "pr-metadata",' '      "rule": "con-check",' '      "fail_message": "El PR miente: corregilo o escalá."' '    }' '  ]' '}')
proyecto "$TMP/c" "$SHA1"
tap_run out 0 "$SYNC" --root "$TMP/c" --url "$TMP/rules"
[ "$(leer "$TMP/c/.barrilete/checks.json")" = "$CHECKS_UNO" ]; tap_check $? "manifiesto: lista el check de la regla accepted con su regla y su fail_message, y ningún otro (ni retirada ni de otro proyecto)"
git init -q -b main "$TMP/rules0"
printf -- '- id: pr-metadata\n  description: x\n' >"$TMP/rules0/classes.yml"
regla0() { mkdir -p "$TMP/rules0/rules"; printf -- '---\nid: sin\nstatus: accepted\norigin: observed\napplies_to: [implementer]\nscope: "*"\nclasses: []\nseverity: fix\naccepted: 2026-11-01\n---\nRegla sin check.\n' >"$TMP/rules0/rules/sin.md"; }
regla0
git -C "$TMP/rules0" add -A && git -C "$TMP/rules0" commit -qm v0; SHA0=$(git -C "$TMP/rules0" rev-parse HEAD)
proyecto "$TMP/c0" "$SHA0"
tap_run out 0 "$SYNC" --root "$TMP/c0" --url "$TMP/rules0"
[ "$(leer "$TMP/c0/.barrilete/checks.json")" = "$(printf '%s\n' '{' '  "checks": []' '}')" ]; tap_check $? "manifiesto: sin reglas con check, la lista queda vacía"
printf '{"checks": []}\n' >"$TMP/c/.barrilete/checks.json"
tap_run out 3 "$SYNC" --root "$TMP/c" --url "$TMP/rules" --check
grep -q 'checks.json' <<<"$out"; tap_check $? "manifiesto: --check nombra checks.json si no es lo que da el lock"
tap_run out 0 "$SYNC" --root "$TMP/c" --url "$TMP/rules"
[ "$(leer "$TMP/c/.barrilete/checks.json")" = "$CHECKS_UNO" ]; tap_check $? "manifiesto: sin --check se regenera y pisa la edición a mano"
tap_run out 0 "$SYNC" --root "$TMP/c" --url "$TMP/rules" --check
[ "$TAP_RC" = 0 ]; tap_check $? "manifiesto: con el manifiesto al día --check sale 0"

# Una regla accepted con check y sin fail_message frena la corrida y no deja nada a medias (el agente no sabría qué hacer).
git init -q -b main "$TMP/rules1"
printf -- '- id: pr-metadata\n  description: x\n' >"$TMP/rules1/classes.yml"
mkdir -p "$TMP/rules1/rules"
printf -- '---\nid: sin-mensaje\nstatus: accepted\norigin: observed\napplies_to: [implementer]\nscope: "*"\nclasses: []\nseverity: block\naccepted: 2026-11-01\ncheck: pr-metadata\n---\nRegla con check y sin mensaje.\n' >"$TMP/rules1/rules/sin-mensaje.md"
git -C "$TMP/rules1" add -A && git -C "$TMP/rules1" commit -qm r1; SHA1B=$(git -C "$TMP/rules1" rev-parse HEAD)
proyecto "$TMP/c1" "$SHA1B"
tap_run out 3 "$SYNC" --root "$TMP/c1" --url "$TMP/rules1"
grep -q 'sin-mensaje' <<<"$out"; tap_check $? "manifiesto: una regla con check y sin fail_message falla y nombra la regla"
grep -q 'fail_message' <<<"$out"; tap_check $? "manifiesto: una regla con check y sin fail_message dice que falta fail_message"

# 14. Los checks solo importan donde corre verify.py: el perfil chico no lo trae (ni los scripts de checks) y la regla con check
# no debe frenar sync-rules ahí. Con verify.py, un check que falta sigue frenando.
proyecto "$TMP/v1" "$SHA1"; rm "$TMP/v1/scripts/agents/checks/pr-metadata"
tap_run out 3 "$SYNC" --root "$TMP/v1" --url "$TMP/rules"
grep -q 'pr-metadata' <<<"$out"; tap_check $? "checks: con verify.py, un check que falta frena sync-rules y se nombra"
proyecto "$TMP/v2" "$SHA1"; rm "$TMP/v2/scripts/agents/checks/pr-metadata" "$TMP/v2/scripts/agents/verify.py"
tap_run out 0 "$SYNC" --root "$TMP/v2" --url "$TMP/rules"
[ "$TAP_RC" = 0 ]; tap_check $? "checks: sin verify.py (perfil chico) la regla con check no frena sync-rules"
[ "$(leer "$TMP/v2/.barrilete/checks.json")" = "$(printf '%s\n' '{' '  "checks": []' '}')" ]; tap_check $? "checks: sin verify.py el manifiesto no lista ningún check"

# 15. El proyecto sale de .agent-kit.json y de ningún otro lado: un `project=` en rules.lock es un error que lo dice.
proyecto "$TMP/q" "$SHA1"
printf 'project=otro-proyecto\n' >>"$TMP/q/.barrilete/rules.lock"
tap_run out 3 "$SYNC" --root "$TMP/q" --url "$TMP/rules"
grep -q 'agent-kit.json' <<<"$out"; tap_check $? "rules.lock con project=: falla y manda a .agent-kit.json"
# el kit: su proyecto está en su .agent-kit.json (el kit se instala sin uno propio) y rules.lock no lo repite
# (solo en la plantilla: el init borra init-template.sh y escribe el .agent-kit.json del proyecto)
if [ -f "$RAIZ/scripts/init-template.sh" ]; then
  K="$RAIZ/.agent-kit.json"
  [ -f "$K" ] && grep -q '"project": "barrilete-kit"' "$K"; tap_check $? "el .agent-kit.json del kit dice project barrilete-kit"
  [ -f "$K" ] && grep -q '"template": true' "$K"; tap_check $? "el .agent-kit.json del kit dice template true"
fi
[ "$(grep -c '^project=' "$RAIZ/.barrilete/rules.lock" || true)" = 0 ]; tap_check $? "el rules.lock del kit no lleva project="

# 16. Una regla con check dice quién la valida (#288, ADR-006 D8): "validated by `verify.py`: <check>". Solo donde verify.py corre.
proyecto "$TMP/vb" "$SHA1"
tap_run out 0 "$SYNC" --root "$TMP/vb" --url "$TMP/rules"
IMPL_VB=$'- Regla con check. (`con-check`) validated by `verify.py`: pr-metadata\n- Regla uno v1 del implementer. (`impl-uno`)\n- Regla de mi proyecto. (`solo-mio`)'
[ "$(reglas "$TMP/vb/.claude/agents/implementer.md")" = "$IMPL_VB" ]; tap_check $? "validated by: la regla con check dice el check que la valida y las demás quedan como estaban"
[ "$(reglas "$TMP/vb/.claude/i18n/agents/implementer.es.md")" = "$IMPL_VB" ]; tap_check $? "validated by: la versión es del agente dice lo mismo"
proyecto "$TMP/vc" "$SHA1"; rm "$TMP/vc/scripts/agents/verify.py" "$TMP/vc/scripts/agents/checks/pr-metadata"
tap_run out 0 "$SYNC" --root "$TMP/vc" --url "$TMP/rules"
[ "$(reglas "$TMP/vc/.claude/agents/implementer.md")" = "${IMPL_V1/ validated by \`verify.py\`: pr-metadata/}" ]; tap_check $? "validated by: sin verify.py (perfil chico) nadie valida la regla y no lo dice"

# 17. El CI del kit corre sync-rules --check (#288): nadie edita a mano una sección generada. Sin rules.lock no hay nada que chequear.
WF="$RAIZ/.github/workflows/docs.yml"
grep -v '^[[:space:]]*#' "$WF" | grep -q 'python3 scripts/agents/sync-rules --check$'; tap_check $? "CI: docs.yml corre sync-rules --check"
grep -v '^[[:space:]]*#' "$WF" | grep -q 'if \[ -f \.barrilete/rules\.lock \]'; tap_check $? "CI: el paso de sync-rules solo corre si el proyecto tiene rules.lock"

# 18. docs/agents/lessons.md se fue (#288): las reglas viven en barrilete-rules. Quedan solo el historial (CHANGELOG, ADRs) y la migración de update.
[ ! -e "$RAIZ/docs/agents/lessons.md" ]; tap_check $? "lessons: docs/agents/lessons.md ya no existe"
[ ! -e "$RAIZ/docs/agents/lessons.es.md" ]; tap_check $? "lessons: docs/agents/lessons.es.md ya no existe"
tap_run restos 0 python3 -I -c '
import os, re, subprocess, sys
raiz = sys.argv[1]
skip = re.compile(r"^(CHANGELOG\.md|docs/decisions/.*|scripts/update\.py|scripts/test-update\.sh|scripts/test-renames\.sh|scripts/agents/test-sync-rules\.sh)$")
pat = re.compile("lessons(\\.es)?\\.md|MAX_LECCIONES")
files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=raiz, capture_output=True, text=True, check=True).stdout.split("\n")
for f in files:
    p = os.path.join(raiz, f)
    if f and not skip.match(f) and os.path.isfile(p) and pat.search(open(p, encoding="utf-8", errors="replace").read()):
        print(f)
' "$RAIZ"
[ -z "$restos" ]; tap_check $? "lessons: ningún archivo (salvo historial y migración) nombra lessons.md" "lessons: ningún archivo nombra lessons.md (quedan: ${restos//$'\n'/ })"

tap_done
