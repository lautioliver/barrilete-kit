#!/usr/bin/env bash
# Tests de mode.py: de dónde lee /orchestrate el modo de cada rol (kit/ADR-004, #236).
# Uso: bash .claude/skills/orchestrate/test-mode.sh
# shellcheck disable=SC2016,SC2154  # el printf del bk falso lleva $1 literal; `out` lo asigna tap_run
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$AQUI/../../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-mode-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""

# bk falso: "bk mode <rol>" contesta lo que dice el archivo global del test (siempre bk, para distinguirlo del proyecto).
mkdir -p "$TMP/bin" "$TMP/nobin" "$TMP/proj/.barrilete" "$TMP/vacio"
printf '#!/bin/sh\n[ "$1" = mode ] && [ "$2" = implementer-light ] && echo sub && exit 0\n[ "$1" = mode ] && echo bk && exit 0\nexit 1\n' >"$TMP/bin/bk"
chmod +x "$TMP/bin/bk"
ln -s "$(command -v python3)" "$TMP/nobin/python3"
PATH_ORIG=$PATH
export PATH="$TMP/bin:$PATH_ORIG"
M="$AQUI/mode.py"

cat >"$TMP/proj/.barrilete/roles.yml" <<'Y'
# roles del proyecto
planner: claude/opus main
implementer: claude/sonnet sub
reviewer:    claude/opus    main   # con espacios y comentario
orchestrator: claude/opus
Y

# 1. Con modo: manda el archivo del proyecto, no bk.
tap_run out 0 python3 "$M" implementer --root "$TMP/proj"
[ "$out" = sub ]; tap_check $? "mode: con modo en roles.yml del proyecto, lo lee"
tap_run out 0 python3 "$M" reviewer --root "$TMP/proj"
[ "$out" = main ]; tap_check $? "mode: tolera espacios y un comentario al final"

# 2. Sin modo: el default es bk.
tap_run out 0 python3 "$M" orchestrator --root "$TMP/proj"
[ "$out" = bk ]; tap_check $? "mode: un rol sin modo es bk"

# 3. Un rol que no está en el archivo del proyecto: lo resuelve bk (su archivo global).
tap_run out 0 python3 "$M" implementer-light --root "$TMP/proj"
[ "$out" = sub ]; tap_check $? "mode: un rol que no está en el proyecto lo resuelve bk mode"
tap_run out 0 python3 "$M" implementer --root "$TMP/vacio"
[ "$out" = bk ]; tap_check $? "mode: sin .barrilete/roles.yml en el proyecto, lo resuelve bk mode"

# 4. Sin bk instalado: todo es sub, y lo avisa.
export PATH="$TMP/nobin"
tap_run out 0 python3 "$M" implementer --root "$TMP/proj"
export PATH="$PATH_ORIG"
grep -qx "sub" <<<"$out"; tap_check $? "mode: sin bk instalado, todo es sub"
grep -q "bk is not installed" <<<"$out"; tap_check $? "mode: sin bk instalado, avisa en stderr"

# 5. Un modo mal escrito no es "sin modo": falla en vez de lanzar una ventana bk sin que nadie lo note.
printf 'reviewer: claude/opus subagent\n' >"$TMP/proj/.barrilete/roles-typo.yml"
mkdir -p "$TMP/typo/.barrilete"; cp "$TMP/proj/.barrilete/roles-typo.yml" "$TMP/typo/.barrilete/roles.yml"
tap_run out 64 python3 "$M" reviewer --root "$TMP/typo"
[ "$TAP_RC" = 64 ] && grep -q "subagent" <<<"$out"; tap_check $? "mode: un modo desconocido falla (exit 64) y lo nombra"

tap_done
