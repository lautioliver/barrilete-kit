#!/usr/bin/env bash
# shellcheck disable=SC2319,SC2030,SC2031  # "<condition>; tap_check $?" is the tests pattern (tap.sh); the vars are set on purpose inside $( )
# Tests de scripts/agents/git-quiet.sh: los git de una prueba no corren gc ni mantenimiento automático,
# y el helper suma sus entradas a las que ya traiga GIT_CONFIG_COUNT sin pisarlas (#224).
# Uso: bash scripts/agents/test-git-quiet.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/git-quiet.sh"
# Uso: <condición>; tap_check $? "descripción"
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# Un repo vacío desde donde leer la config: git config --list sin -C también lee el .git/config del cwd (un gc.auto=0 de ahí taparía al helper).
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-git-quiet-XXXXXX")
# shellcheck disable=SC2016  # se expande al salir, no ahora
tap_at_exit 'rm -rf "$TMP"'
git init -q "$TMP"

# Sin entradas previas: el helper deja gc.auto en 0 y maintenance.auto en false para los git que lance.
cfg=$(unset GIT_CONFIG_COUNT; git_quiet_env; git -C "$TMP" config --list 2>/dev/null)
grep -qxF gc.auto=0 <<<"$cfg"; tap_check $? "sin entradas previas, los git no corren gc automático"
grep -qxF maintenance.auto=false <<<"$cfg"; tap_check $? "sin entradas previas, los git no corren mantenimiento automático"

# Con dos entradas que ya trae el entorno: se conservan, y las del helper van detrás (no las pisan).
cfg=$(export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=orquestador GIT_CONFIG_KEY_1=core.autocrlf GIT_CONFIG_VALUE_1=false; git_quiet_env; git -C "$TMP" config --list 2>/dev/null)
grep -qxF user.name=orquestador <<<"$cfg"; tap_check $? "las entradas de GIT_CONFIG_COUNT que ya trae el entorno se conservan"
grep -qxF core.autocrlf=false <<<"$cfg"; tap_check $? "la segunda entrada de GIT_CONFIG_COUNT que ya trae el entorno se conserva"
grep -qxF gc.auto=0 <<<"$cfg"; tap_check $? "con entradas previas, los git no corren gc automático"
grep -qxF maintenance.auto=false <<<"$cfg"; tap_check $? "con entradas previas, los git no corren mantenimiento automático"

# Con un GIT_CONFIG_COUNT que no es un número: el helper termina con 1, avisa con una sola línea en stderr y no lo pisa
# (git lo reportaría; un 0 mudo lo taparía). Idioma de tap.sh: el estado se captura y se exige 1; cualquier otra salida
# (un crash del helper) hace fallar el caso o termina la corrida con Bail out.
c=0; msg=$(export GIT_CONFIG_COUNT=abc; trap - ERR; git_quiet_env 2>&1 >/dev/null) || c=$?; tap_status "$c" 1
[ "$c" = 1 ]; tap_check $? "con un GIT_CONFIG_COUNT no numérico, el helper termina con 1"
[ "$msg" = "git_quiet_env: GIT_CONFIG_COUNT='abc' no es un número" ]; tap_check $? "con un GIT_CONFIG_COUNT no numérico, el helper avisa por qué aborta"
valor=$(export GIT_CONFIG_COUNT=abc; trap - ERR; git_quiet_env 2>/dev/null; echo "$GIT_CONFIG_COUNT")
[ "$valor" = abc ]; tap_check $? "con un GIT_CONFIG_COUNT no numérico, el helper no lo pisa"

# Con un GIT_CONFIG_COUNT con ceros adelante (010 son diez entradas, no ocho): el helper lo lee en base 10, suma las suyas detrás y conserva las diez.
cfg=$(export GIT_CONFIG_COUNT=010; for i in 0 1 2 3 4 5 6 7 8 9; do export "GIT_CONFIG_KEY_$i=x.k$i" "GIT_CONFIG_VALUE_$i=v$i"; done; git_quiet_env; git -C "$TMP" config --list 2>/dev/null)
grep -qxF x.k9=v9 <<<"$cfg"; tap_check $? "con un GIT_CONFIG_COUNT con ceros adelante, se conserva la última entrada previa"
grep -qxF gc.auto=0 <<<"$cfg"; tap_check $? "con un GIT_CONFIG_COUNT con ceros adelante, los git no corren gc automático"
grep -qxF maintenance.auto=false <<<"$cfg"; tap_check $? "con un GIT_CONFIG_COUNT con ceros adelante, los git no corren mantenimiento automático"

# "08" no es octal válido: sin base 10 la aritmética de bash falla ("value too great for base").
n=$(export GIT_CONFIG_COUNT=08; git_quiet_env 2>/dev/null; echo "$GIT_CONFIG_COUNT")
[ "$n" = 10 ]; tap_check $? "con un GIT_CONFIG_COUNT 08, el helper suma las suyas a las ocho previas"

tap_done
