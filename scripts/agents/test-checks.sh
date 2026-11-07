#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2319,SC2181  # out lo asigna tap_run; los backticks y el $ de los cuerpos de PR son texto
# Tests de los checks de las reglas (#287, ADR-006 D8): verify.py corre scripts/agents/checks/<id> de cada entrada de
# .barrilete/checks.json, y el primer check, pr-metadata, compara el cuerpo del PR con lo que pasó en la rama.
# No toca la red ni GitHub: un `gh` falso en el PATH hace de GitHub y los repos son locales.
# Un check que falla sale con 3 (1 y 2 quedan para un crash, ver tap.sh); verify.py sale con 1 si algo falla,
# y por eso acá lo que falla se mira en lo que imprime: el nombre del check y el fail_message de su regla.
# Uso: bash scripts/agents/test-checks.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-checks-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset BASE
out=""
leer() { [ -f "$1" ] && cat "$1"; }  # el contenido, o nada si el archivo no existe (un caso falla, no un crash)

# --- un proyecto: remoto con main, y una rama claude/7-algo con dos commits (el rojo y el verde) ---
git init -q --bare -b main "$TMP/remoto.git"
git clone -q "$TMP/remoto.git" "$TMP/p" 2>/dev/null
P="$TMP/p"
mkdir -p "$P/scripts" "$P/docs" "$P/.barrilete"
cp -R "$RAIZ/scripts/agents" "$P/scripts/"
printf '{"docs": [], "sensitive": [], "verify": [{"name": "eco", "always": true, "run": "echo hola"}]}\n' >"$P/docs/agents-map.json"
git -C "$P" switch -q -c main
git -C "$P" add -A && git -C "$P" commit -qm base && git -C "$P" push -q origin main 2>/dev/null
git -C "$P" remote set-head origin main
BASE_SHA=$(git -C "$P" rev-parse HEAD)
git -C "$P" switch -q -c claude/7-algo
printf '#!/usr/bin/env bash\ntap_check $? "caso uno"\ntap_check $? "caso dos"\n' >"$P/scripts/agents/test-x.sh"
git -C "$P" add -A && git -C "$P" commit -qm rojo; RED=$(git -C "$P" rev-parse --short=10 HEAD)
echo verde >"$P/impl.txt"
git -C "$P" add -A && git -C "$P" commit -qm verde

# --- un `gh` falso: GH_MODE=pr da el PR de $GH_JSON; none, "no hay PR para la rama"; otro valor, un error de gh ---
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/bin/sh
case "$GH_MODE" in
  pr) cat "$GH_JSON" ;;
  none) echo 'no pull requests found for branch "claude/7-algo"' >&2; exit 1 ;;
  *) echo 'gh: HTTP 401: Bad credentials' >&2; exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
export GH_JSON="$TMP/pr.json"
pr() { # pr <número> <cuerpo>: el PR que devuelve el gh falso
  python3 -c 'import json,sys; print(json.dumps({"number": int(sys.argv[1]), "body": sys.argv[2]}))' "$1" "$2" >"$GH_JSON"
}
cuerpo() { # cuerpo <red> <commits> <caso> <cierra>: un cuerpo de PR con su bloque rojo, ${2} commits y el caso fallido ${3}
  printf '## What changes\nx\n\n## How to test it\n\n<details><summary>Red before implementing</summary>\n\nred commit: %s\n\nstack: bash\nformat: junit\nfailing cases:\n%s</details>\n\n%s commits.\n\n%s\n' "$1" "${3:+- $3
}" "$2" "$4"
}
BIEN=$(cuerpo "$RED" 2 "scripts/agents/test-x.sh::caso uno" "Closes #7")
# verify.py sale con 1 si algo falla y tap_run toma 1 y 2 por un crash: rc.py lo corre, imprime todo y agrega `rc=<estado>`.
# Un crash de verify.py (traceback) lo frena tap_no_traceback, y cada caso busca además lo que solo imprime el código correcto.
cat >"$TMP/rc.py" <<'EOF'
import subprocess, sys
r = subprocess.run(sys.argv[1:], capture_output=True, text=True)
sys.stdout.write(r.stdout + r.stderr)
print("rc=%d" % r.returncode)
EOF

# 1. pr-metadata: sin PR abierto para la rama avisa y no falla (verify.py corre antes de abrirlo).
cd "$P" || exit 2
GH_MODE=none PATH="$TMP/bin:$PATH" tap_run out 0 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -qi 'not verified' <<<"$out"; tap_check $? "pr-metadata: sin PR abierto dice que no verificó"
tap_no_traceback "$out"
# 2. Un error de gh que no es "no hay PR" no se toma por un PR correcto: no verificó, y lo dice como falla (3).
GH_MODE=roto PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'Bad credentials' <<<"$out"; tap_check $? "pr-metadata: un error de gh falla y muestra lo que dijo gh"
tap_no_traceback "$out"

# 3. Un cuerpo que cumple pasa.
pr 12 "$BIEN"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 0 python3 scripts/agents/checks/pr-metadata --base origin/main
[ "$TAP_RC" = 0 ]; tap_check $? "pr-metadata: un cuerpo que cumple pasa"
grep -qi 'ok' <<<"$out"; tap_check $? "pr-metadata: un cuerpo que cumple lo dice"

# 4. El `red commit:` tiene que ser un commit de la rama (no el de la base ni uno que no existe).
pr 12 "$(cuerpo "${BASE_SHA:0:10}" 2 "" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q "${BASE_SHA:0:10}" <<<"$out"; tap_check $? "red commit: el de la base falla y nombra el sha"
pr 12 "$(cuerpo "deadbeef12" 2 "" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'deadbeef12' <<<"$out"; tap_check $? "red commit: un sha que no existe falla y lo nombra"

# 5. Los commits que dice el cuerpo son los de la rama.
pr 12 "$(cuerpo "$RED" 3 "scripts/agents/test-x.sh::caso uno" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q '3' <<<"$out"; tap_check $? "commits: el cuerpo dice 3 y la rama tiene 2: falla y nombra el 3"
grep -q '2' <<<"$out"; tap_check $? "commits: nombra también los 2 reales"

# 6. Cada caso del bloque rojo existe en el archivo de ese commit (los ids de tap son literales del fuente).
pr 12 "$(cuerpo "$RED" 2 "scripts/agents/test-x.sh::caso inventado" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'caso inventado.*name is not in' <<<"$out"; tap_check $? "casos: un caso que no está en el archivo del red commit falla y se nombra"
pr 12 "$(cuerpo "$RED" 2 "scripts/agents/no-esta.sh::caso uno" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'no-esta.sh does not exist' <<<"$out"; tap_check $? "casos: un archivo que no existe en el red commit falla y se nombra"

# 7. El número del issue: el del `Closes`/`Refs` es el de la rama, y no es el del PR mismo.
pr 12 "$(cuerpo "$RED" 2 "scripts/agents/test-x.sh::caso uno" "Closes #8")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'branch is for issue #7 and the body says #8' <<<"$out"; tap_check $? "issue: un Closes que no es el de la rama falla y nombra el número"
pr 12 "$(cuerpo "$RED" 2 "scripts/agents/test-x.sh::caso uno" "$(printf 'Closes #7\nCloses #12')")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'number of this PR itself' <<<"$out"; tap_check $? "issue: un Closes con el número del PR mismo falla"
pr 12 "$(cuerpo "$RED" 2 "scripts/agents/test-x.sh::caso uno" "Refs #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 0 python3 scripts/agents/checks/pr-metadata --base origin/main
[ "$TAP_RC" = 0 ]; tap_check $? "issue: un Refs con el número de la rama pasa"

# 7b. Un sha que no es hexadecimal no llega a git, y lo que está en un bloque de código no es una afirmación del PR.
pr 12 "$(cuerpo "--upload-pack=x" 2 "" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'upload-pack.*not a hexadecimal sha' <<<"$out"; tap_check $? "red commit: un valor que no es un sha falla y se nombra"
pr 12 "$(cuerpo "${RED:0:3}" 2 "" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q "${RED:0:3}.*not a hexadecimal sha" <<<"$out"; tap_check $? "red commit: un prefijo de menos de 7 caracteres no se acepta como sha"
pr 12 "$(printf '%s\n\n```\nred commit: deadbeef12\n9 commits\nCloses #99\n```\n' "$BIEN")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 0 python3 scripts/agents/checks/pr-metadata --base origin/main
[ "$TAP_RC" = 0 ]; tap_check $? "bloque de código: lo que se cita ahí no se lee como afirmación del PR"

# 8. Sin bloque rojo y con `no tests:` no hay nada que comparar del rojo.
pr 12 "$(printf '## How to test it\nno tests: docs\n\n2 commits.\n\nCloses #7\n')"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 0 python3 scripts/agents/checks/pr-metadata --base origin/main
[ "$TAP_RC" = 0 ]; tap_check $? "pr-metadata: sin bloque rojo y con no tests: pasa"
cd "$TMP" || exit 2

# --- verify.py corre los checks del manifiesto ---
mkdir -p "$P/scripts/agents/checks"
for id in ok-check mal-check; do
  printf '#!/bin/sh\necho "args: $*" >> "%s/%s.args"\n' "$TMP" "$id" >"$P/scripts/agents/checks/$id"
done
printf 'exit 0\n' >>"$P/scripts/agents/checks/ok-check"
printf 'echo "el check mal-check no se cumple"\nexit 3\n' >>"$P/scripts/agents/checks/mal-check"
chmod +x "$P/scripts/agents/checks/ok-check" "$P/scripts/agents/checks/mal-check"
manifiesto() { # manifiesto <id>...: .barrilete/checks.json con una entrada por id (regla r-<id>, fail_message "arreglá <id>")
  local sep="" e=""
  for id in "$@"; do e="$e$sep{\"id\": \"$id\", \"rule\": \"r-$id\", \"fail_message\": \"arreglá $id o escalá\"}"; sep=","; done
  printf '{"checks": [%s]}\n' "$e" >"$P/.barrilete/checks.json"
}
verify() { # verify <rc esperado> [args de verify.py]: en $out, lo que imprimió; el estado se compara con el rc= del final
  cd "$P" || exit 2
  BASE=main tap_run out 0 python3 "$TMP/rc.py" python3 scripts/agents/verify.py "${@:2}"
  cd "$TMP" || exit 2
  tap_no_traceback "$out"
  grep -qx "rc=$1" <<<"$out"; tap_check $? "verify.py: el estado final es el esperado" "${2:-sin argumentos}: $(tail -1 <<<"$out")"
}

manifiesto ok-check
verify 0
grep -q 'ok *check:ok-check' <<<"$out"; tap_check $? "verify.py: corre el check del manifiesto y lo da por ok"
grep -q -- '--base origin/main' <<<"$(leer "$TMP/ok-check.args")"; tap_check $? "verify.py: le pasa al check la base con --base"

rm -f "$TMP/ok-check.args" "$TMP/mal-check.args"
manifiesto ok-check mal-check
verify 1
grep -q 'FAILED *check:mal-check' <<<"$out"; tap_check $? "verify.py: un check que falla sale como FAILED con su nombre"
grep -q 'r-mal-check' <<<"$out"; tap_check $? "verify.py: un check que falla nombra su regla"
grep -q 'arreglá mal-check o escalá' <<<"$out"; tap_check $? "verify.py: un check que falla muestra el fail_message de su regla"
grep -q 'ok *check:ok-check' <<<"$out"; tap_check $? "verify.py: un check que falla no impide correr los demás"

rm -f "$TMP/ok-check.args" "$TMP/mal-check.args"
verify 0 --list
grep -q 'check:mal-check' <<<"$out"; tap_check $? "verify.py --list muestra los checks del manifiesto"
[ ! -e "$TMP/mal-check.args" ]; tap_check $? "verify.py --list no corre los checks"

manifiesto no-existe
verify 1
grep -q 'no-existe' <<<"$out"; tap_check $? "verify.py: un check del manifiesto sin script falla y lo nombra"

printf 'esto no es json\n' >"$P/.barrilete/checks.json"
verify 2
grep -q 'checks.json' <<<"$out"; tap_check $? "verify.py: un manifiesto roto nombra el archivo"

printf '#!/bin/sh\necho corrio >> "%s/fuera.args"\nexit 0\n' "$TMP" >"$P/scripts/agents/fuera"; chmod +x "$P/scripts/agents/fuera"
printf '{"nada": 1}\n' >"$P/.barrilete/checks.json"
verify 2
grep -q 'no "checks" list' <<<"$out"; tap_check $? "verify.py: un manifiesto sin lista checks sale con 2 y lo dice"
printf '{"checks": [{"id": "ok-check"}]}\n' >"$P/.barrilete/checks.json"
verify 2
grep -q 'needs "id", "rule" and "fail_message"' <<<"$out"; tap_check $? "verify.py: una entrada sin rule o sin fail_message sale con 2 y lo dice"
manifiesto "../fuera"
verify 2
grep -q 'fuera' <<<"$out"; tap_check $? "verify.py: un id de check que no es un slug (../) se rechaza y se nombra"
[ ! -e "$TMP/fuera.args" ]; tap_check $? "verify.py: un id con ../ no corre nada fuera de scripts/agents/checks"

rm "$P/.barrilete/checks.json"
verify 0
n=$(grep -c 'check:' <<<"$out" || true); [ "$n" = 0 ]; tap_check $? "verify.py: sin manifiesto no corre ningún check de reglas"
grep -q 'hola' <<<"$out"; tap_check $? "verify.py: sin manifiesto sigue corriendo los checks del mapa"

# --- de punta a punta (condición de éxito 2 de D11): la regla con check llega por rules.lock, corre en verify.py y frena ---
git init -q -b main "$TMP/reglas"
printf -- '- id: pr-metadata\n  description: x\n' >"$TMP/reglas/classes.yml"
mkdir -p "$TMP/reglas/rules"
printf -- '---\nid: numeros-ok\nstatus: accepted\norigin: observed\napplies_to: [implementer]\nscope: "*"\nclasses: [pr-metadata]\nseverity: fix\naccepted: 2026-11-01\ncheck: pr-metadata\nfail_message: "El cuerpo del PR no coincide con la rama: regeneralo y, si no podés, escalá."\n---\nRegenerá los números del PR.\n' >"$TMP/reglas/rules/numeros-ok.md"
git -C "$TMP/reglas" add -A && git -C "$TMP/reglas" commit -qm r; SHAR=$(git -C "$TMP/reglas" rev-parse HEAD)
printf 'repo=o/reglas\nsha=%s\nproject=mi-proyecto\n' "$SHAR" >"$P/.barrilete/rules.lock"
cd "$P" || exit 2
tap_run out 0 python3 scripts/agents/sync-rules --url "$TMP/reglas"
cd "$TMP" || exit 2
[ -f "$P/.barrilete/checks.json" ]; tap_check $? "de punta a punta: sync-rules deja el manifiesto con el check de la regla"
pr 12 "$(cuerpo "$RED" 5 "scripts/agents/test-x.sh::caso uno" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" verify 1
grep -q 'FAILED *check:pr-metadata' <<<"$out"; tap_check $? "de punta a punta: un PR con números que no son los de la rama frena en verify.py"
grep -q 'regeneralo y, si no podés, escalá' <<<"$out"; tap_check $? "de punta a punta: muestra el fail_message de la regla"
pr 12 "$BIEN"
GH_MODE=pr PATH="$TMP/bin:$PATH" verify 0
grep -q 'ok *check:pr-metadata' <<<"$out"; tap_check $? "de punta a punta: un PR que cumple pasa verify.py"

tap_done
