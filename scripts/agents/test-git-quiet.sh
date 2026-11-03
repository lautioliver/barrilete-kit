#!/usr/bin/env bash
# shellcheck disable=SC2319  # "<condition>; tap_check $?" is the pattern of the tests (tap.sh)
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

# Sin entradas previas: el helper deja gc.auto y maintenance.auto en 0 para los git que lance.
cfg=$(unset GIT_CONFIG_COUNT; git_quiet_env; git config --list 2>/dev/null)
grep -qxF gc.auto=0 <<<"$cfg"; tap_check $? "sin entradas previas, los git no corren gc automático"
grep -qxF maintenance.auto=false <<<"$cfg"; tap_check $? "sin entradas previas, los git no corren mantenimiento automático"

# Con dos entradas que ya trae el entorno: se conservan, y las del helper van detrás (no las pisan).
cfg=$(export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=orquestador GIT_CONFIG_KEY_1=core.autocrlf GIT_CONFIG_VALUE_1=false; git_quiet_env; git config --list 2>/dev/null)
grep -qxF user.name=orquestador <<<"$cfg"; tap_check $? "las entradas de GIT_CONFIG_COUNT que ya trae el entorno se conservan"
grep -qxF core.autocrlf=false <<<"$cfg"; tap_check $? "la segunda entrada de GIT_CONFIG_COUNT que ya trae el entorno se conserva"
grep -qxF gc.auto=0 <<<"$cfg"; tap_check $? "con entradas previas, los git no corren gc automático"
grep -qxF maintenance.auto=false <<<"$cfg"; tap_check $? "con entradas previas, los git no corren mantenimiento automático"

tap_done
