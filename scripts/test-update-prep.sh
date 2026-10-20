#!/usr/bin/env bash
# shellcheck disable=SC2319  # "<condition>; tap_check $?" is the pattern of the tests (tap.sh)
# Test de la preparación de test-update.sh (#162): si un paso de preparación falla, el test se corta ahí y muestra
# qué comando falló y su salida. Corre una copia del kit en la que el init de la plantilla es un stub que imprime
# STUB-OUT-init y sale con 1: el primer proyecto de test-update.sh no se puede preparar.
# Uso: bash scripts/test-update-prep.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-update-prep-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

if [ -f "$RAIZ/scripts/test-update.sh" ] && [ -f "$RAIZ/scripts/init-template.sh" ]; then
  FAKE="$TMP/fake-kit"
  mkdir -p "$FAKE"
  (cd "$RAIZ" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | (cd "$FAKE" && tar -xf -)
  git -C "$FAKE" init -q
  printf '#!/usr/bin/env bash\necho STUB-OUT-init\nexit 1\n' >"$FAKE/scripts/init-template.sh"
  # The runner ends with 0 on purpose and saves the status of the nested test: the cases look at what it printed.
  # shellcheck disable=SC2016  # the runner expands its own arguments
  printf '#!/usr/bin/env bash\nbash "$1"\necho $? >"$2"\nexit 0\n' >"$TMP/runner.sh"
  out=""
  tap_run out 0 bash "$TMP/runner.sh" "$FAKE/scripts/test-update.sh" "$TMP/nested-rc"
  [[ $out == *Bail\ out!* && $out == *STUB-OUT-init* ]]
  tap_check $? "162: a preparation step that fails ends test-update.sh with a Bail out! that has the output of the step" "nested run: $(tail -c 400 <<<"$out")"
  [[ $out == *"init-template.sh Demo main"* ]]
  tap_check $? "162: the Bail out! says which command failed" "nested run: $(tail -c 400 <<<"$out")"
  [[ $out != *.agent-kit.json* && $out != *"FAIL - "* ]]
  tap_check $? "162: a preparation that fails is a Bail out! at that step, not a crash later, in the first check that reads what the step should have made" "nested run: $(tail -c 400 <<<"$out")"
  [[ $(<"$TMP/nested-rc") == 1 ]]
  tap_check $? "162: the nested test-update.sh ends with 1" "nested status: $(<"$TMP/nested-rc")"
else
  tap_skip "162: a preparation step that fails ends test-update.sh with a Bail out! that has the output of the step" "the project has no init-template.sh"
  tap_skip "162: the Bail out! says which command failed" "the project has no init-template.sh"
  tap_skip "162: a preparation that fails is a Bail out! at that step, not a crash later, in the first check that reads what the step should have made" "the project has no init-template.sh"
  tap_skip "162: the nested test-update.sh ends with 1" "the project has no init-template.sh"
fi
tap_done
