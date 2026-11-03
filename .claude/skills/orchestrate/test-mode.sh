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
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v python3)" >"$TMP/nobin/python3"
chmod +x "$TMP/nobin/python3"
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
export PATH="$TMP/bin:$PATH_ORIG"
grep -qx "sub" <<<"$out"; tap_check $? "mode: sin bk instalado, todo es sub"
grep -q "bk is not installed" <<<"$out"; tap_check $? "mode: sin bk instalado, avisa en stderr"

# 5. Un modo mal escrito no es "sin modo": falla en vez de lanzar una ventana bk sin que nadie lo note.
printf 'reviewer: claude/opus subagent\n' >"$TMP/proj/.barrilete/roles-typo.yml"
mkdir -p "$TMP/typo/.barrilete"; cp "$TMP/proj/.barrilete/roles-typo.yml" "$TMP/typo/.barrilete/roles.yml"
tap_run out 64 python3 "$M" reviewer --root "$TMP/typo"
[ "$TAP_RC" = 64 ] && grep -q "subagent" <<<"$out"; tap_check $? "mode: un modo desconocido falla (exit 64) y lo nombra"

# 6. Una línea del rol que no se entiende no es "el rol no está": falla (exit 64) en vez de caer en silencio a `bk mode`.
mkdir -p "$TMP/extra/.barrilete" "$TMP/vaciorol/.barrilete" "$TMP/norol/.barrilete"
printf 'implementer: claude/sonnet sub extra\n' >"$TMP/extra/.barrilete/roles.yml"
tap_run out 64 python3 "$M" implementer --root "$TMP/extra"
[ "$TAP_RC" = 64 ] && grep -q "implementer" <<<"$out"; tap_check $? "mode: una línea del rol con una palabra de más falla (exit 64) y nombra el rol"
printf 'implementer:\n' >"$TMP/vaciorol/.barrilete/roles.yml"
tap_run out 64 python3 "$M" implementer --root "$TMP/vaciorol"
[ "$TAP_RC" = 64 ] && grep -q "implementer" <<<"$out"; tap_check $? "mode: una línea del rol vacía falla (exit 64) y nombra el rol"
printf 'implementer-light: claude/haiku sub\nimplementerx: nada\n' >"$TMP/norol/.barrilete/roles.yml"
tap_run out 0 python3 "$M" implementer --root "$TMP/norol"
[ "$out" = bk ]; tap_check $? "mode: otro rol con prefijo parecido no cuenta como la línea del rol"

# 7. --root que no existe: exit 64, sin traceback.
tap_run out 64 python3 "$M" implementer --root "$TMP/no-existe"
[ "$TAP_RC" = 64 ] && ! grep -q "Traceback" <<<"$out"; tap_check $? "mode: un --root que no existe falla (exit 64) sin traceback"

# 8. bk que falla o que contesta algo fuera de main/bk/sub: exit 64.
mkdir -p "$TMP/badbin"
printf '#!/bin/sh\nexit 3\n' >"$TMP/badbin/bk"
printf '#!/bin/sh\necho subagent\n' >"$TMP/badbin/bk-raro"
chmod +x "$TMP/badbin/bk" "$TMP/badbin/bk-raro"
PATH="$TMP/badbin:$PATH_ORIG" tap_run out 64 python3 "$M" implementer --root "$TMP/vacio"
[ "$TAP_RC" = 64 ]; tap_check $? "mode: bk mode que falla da exit 64"
mkdir -p "$TMP/rarobin"; cp "$TMP/badbin/bk-raro" "$TMP/rarobin/bk"
PATH="$TMP/rarobin:$PATH_ORIG" tap_run out 64 python3 "$M" implementer --root "$TMP/vacio"
[ "$TAP_RC" = 64 ]; tap_check $? "mode: bk mode que contesta algo fuera de main, bk o sub da exit 64"

tap_done
