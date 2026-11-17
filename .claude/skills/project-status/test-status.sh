#!/usr/bin/env bash
# Tests de la sección Migrations de status.sh contra un remoto local y un gh falso (no usa GitHub).
# Uso: bash .claude/skills/project-status/test-status.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$AQUI/../../.." && pwd)
STATUS="$AQUI/status.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-status-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""

# gh falso: un repo o/r con un PR abierto (#7) cuyos archivos están en $GH_FILES.
mkdir -p "$TMP/bin"
export GH_FILES="$TMP/pr7-files"
cat >"$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "repo view"*defaultBranchRef.name*) echo main ;;
  "repo view"*) echo o/r ;;
  "api "*) echo '[]' ;;
  "pr list --limit 50"*) printf '%s\n' ${GH_PRS:-7} ;;
  "pr list"*) echo "  - #7 Un PR" ;;
  "pr diff 7 --name-only") cat "$GH_FILES" ;;
  "pr diff 8 --name-only") echo "gh falso: diff demasiado grande" >&2; exit 1 ;;
  "issue list"*label\ type:audit*) echo 0 ;;
  "issue list"*) ;;
  *) echo "gh falso: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
unset BASE
out=""   # lo reasigna tap_run
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/git-quiet.sh"
git_quiet_env
export PATH="$TMP/bin:$PATH" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

# Un proyecto instalado: trae su docs/agents-map.json y scripts/agents/agents_map.py.
git init -q --bare -b main "$TMP/remoto.git"
git clone -q "$TMP/remoto.git" "$TMP/proj" 2>/dev/null
mkdir -p "$TMP/proj/docs" "$TMP/proj/scripts/agents"
cp "$RAIZ/scripts/agents/agents_map.py" "$TMP/proj/scripts/agents/"
# shellcheck disable=SC2164  # si el cd falla, tap.sh corta la corrida (trap ERR)
cd "$TMP/proj"
git switch -q -c main
echo base >README.md
git add README.md
git commit -qm base
git push -q origin main 2>/dev/null

mapa() { # mapa <glob schema>: el agents-map.json del proyecto con esa sola ruta schema
  printf '{"sensitive": [{"type": "schema", "paths": ["%s"]}]}\n' "$1" >docs/agents-map.json
}

# 1. Una ruta con el prefijo ? (opcional) detecta el PR que toca migraciones, sin errores de grep.
mapa '?**/migrations/**'
echo db/migrations/001.sql >"$GH_FILES"
tap_run out 0 bash "$STATUS"
grep -qxF -- '- Open PRs with schema changes: #7' <<<"$out"; tap_check $? "una ruta schema con ? delante detecta el PR con migraciones"
case "$out" in
  *"grep:"*|*Traceback*) tap_fail "la sección Migrations no imprime errores de grep" ;;
  *) tap_ok "la sección Migrations no imprime errores de grep" ;;
esac

# 2. Sin ?, la ruta schema también detecta el PR.
mapa 'db/schema/**'
echo db/schema/tabla.sql >"$GH_FILES"
tap_run out 0 bash "$STATUS"
grep -qxF -- '- Open PRs with schema changes: #7' <<<"$out"; tap_check $? "una ruta schema sin ? detecta el PR que la toca"

# 3. * no cruza directorios, igual que agents_map.py.
mapa 'db/*.sql'
echo db/sub/tabla.sql >"$GH_FILES"
tap_run out 0 bash "$STATUS"
grep -qxF -- '_No open PR touches migrations._' <<<"$out"; tap_check $? "* no cruza directorios en las rutas schema"

# 4. Un PR que no toca una ruta schema no aparece.
mapa '?**/migrations/**'
echo docs/README.md >"$GH_FILES"
tap_run out 0 bash "$STATUS"
grep -qxF -- '_No open PR touches migrations._' <<<"$out"; tap_check $? "un PR sin rutas schema no aparece en Migrations"

# 5. Sin agents_map.py la sección no se puede verificar: lo dice, sin traceback, en vez de decir que no hay PRs.
mv scripts/agents/agents_map.py "$TMP/agents_map.py"
mapa '?**/migrations/**'
echo db/migrations/001.sql >"$GH_FILES"
tap_run out 0 bash "$STATUS"
grep -qF -- '_Not verified:' <<<"$out"; tap_check $? "sin agents_map.py la sección Migrations dice que no verificó"
case "$out" in
  *Traceback*|*"No open PR touches migrations"*) tap_fail "sin agents_map.py no hay traceback ni un falso sin migraciones" ;;
  *) tap_ok "sin agents_map.py no hay traceback ni un falso sin migraciones" ;;
esac
mv "$TMP/agents_map.py" scripts/agents/agents_map.py

# 6. Un PR cuyo diff no se puede leer se nombra, no se cuenta como sin migraciones.
GH_PRS="7 8" tap_run out 0 bash "$STATUS"
grep -qxF -- '- Could not read the files of: #8' <<<"$out"; tap_check $? "un PR cuyo diff falla se nombra en Migrations"
grep -qxF -- '- Open PRs with schema changes: #7' <<<"$out"; tap_check $? "con un diff que falla, los demás PRs se siguen revisando"

tap_done
