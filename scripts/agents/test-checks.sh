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
unset BASE CLAUDECODE BK_TASK_DIR BK_HARNESS   # verify.py los lee para el evento check_run: cada caso los pone a mano
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
  python3 -c 'import json,sys; print(json.dumps({"number": int(sys.argv[1]), "body": sys.argv[2], "url": "https://github.com/lautioliver/barrilete-kit/pull/" + sys.argv[1]}))' "$1" "$2" >"$GH_JSON"
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
GH_MODE=none PATH="$TMP/bin:$PATH" tap_run out 4 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -qi 'not verified' <<<"$out"; tap_check $? "pr-metadata: sin PR abierto dice que no verificó"
[ "$TAP_RC" = 4 ]; tap_check $? "pr-metadata: sin PR abierto sale con 4 (no verificó), distinto de 0 (verificó y está bien)"
tap_no_traceback "$out"
# 2. Un error de gh (sin red, sin login, otro texto de gh) no es un PR que no cumple: no verificó (4), con lo que dijo gh.
# Salir con 3 mandaría al agente a arreglar un cuerpo que no tiene nada de malo.
GH_MODE=roto PATH="$TMP/bin:$PATH" tap_run out 4 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'Bad credentials' <<<"$out"; tap_check $? "pr-metadata: un error de gh no verificó y muestra lo que dijo gh"
[ "$TAP_RC" = 4 ]; tap_check $? "pr-metadata: un error de gh sale con 4 (no verificó), no con 3 (el cuerpo no cumple)"
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

# 7c. Un sha de solo dígitos no es una cantidad de commits; y lo que viene después del bloque rojo no son casos.
pr 12 "$(cuerpo "1234567" 2 "" "Closes #7")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 3 python3 scripts/agents/checks/pr-metadata --base origin/main
grep -q 'body says 1234567 commits' <<<"$out"; [ $? -eq 1 ]; tap_check $? "commits: el sha del red commit, aunque sean solo dígitos, no se lee como una cantidad de commits"
pr 12 "$(printf '%s\n\n## Notes\n- see foo::bar\n' "$BIEN")"
GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out 0 python3 scripts/agents/checks/pr-metadata --base origin/main
[ "$TAP_RC" = 0 ]; tap_check $? "casos: un - x::y después del bloque rojo no se toma por un caso fallido"

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
grep -q 'check:' <<<"$out"; [ $? -eq 1 ]; tap_check $? "verify.py: sin manifiesto no corre ningún check de reglas"
grep -q 'hola' <<<"$out"; tap_check $? "verify.py: sin manifiesto sigue corriendo los checks del mapa"

# --- de punta a punta (condición de éxito 2 de D11): la regla con check llega por rules.lock, corre en verify.py y frena ---
git init -q -b main "$TMP/reglas"
printf -- '- id: pr-metadata\n  description: x\n' >"$TMP/reglas/classes.yml"
mkdir -p "$TMP/reglas/rules"
printf -- '---\nid: numeros-ok\nstatus: accepted\norigin: observed\napplies_to: [implementer]\nscope: "*"\nclasses: [pr-metadata]\nseverity: fix\naccepted: 2026-11-01\ncheck: pr-metadata\nfail_message: "El cuerpo del PR no coincide con la rama: regeneralo y, si no podés, escalá."\n---\nRegenerá los números del PR.\n' >"$TMP/reglas/rules/numeros-ok.md"
git -C "$TMP/reglas" add -A && git -C "$TMP/reglas" commit -qm r; SHAR=$(git -C "$TMP/reglas" rev-parse HEAD)
printf 'repo=o/reglas\nsha=%s\n' "$SHAR" >"$P/.barrilete/rules.lock"
printf '{ "project": "mi-proyecto", "mode": "full" }\n' >"$P/.agent-kit.json"
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

# --- lo que verify.py dice cuando un check no pudo verificar, cuando dos reglas comparten check y con --pr ---
GH_MODE=none PATH="$TMP/bin:$PATH" verify 0
grep -q 'not verified *check:pr-metadata' <<<"$out"; tap_check $? "verify.py: un check que no pudo verificar sale como not verified, no como ok"
grep -q 'All verified' <<<"$out"; [ $? -eq 1 ]; tap_check $? "verify.py: con un check sin verificar no dice All verified"
grep -q 'was not verified' <<<"$out"; tap_check $? "verify.py: con un check sin verificar avisa que no se puede decir que el cambio está verificado"

printf '{"checks": [{"id": "mal-check", "rule": "regla-a", "fail_message": "mensaje de a"}, {"id": "mal-check", "rule": "regla-b", "fail_message": "mensaje de b"}]}\n' >"$P/.barrilete/checks.json"
rm -f "$TMP/mal-check.args"
verify 1
grep -q 'regla-a.*mensaje de a' <<<"$out"; tap_check $? "verify.py: dos reglas con el mismo check: se muestra el mensaje de la primera"
grep -q 'regla-b.*mensaje de b' <<<"$out"; tap_check $? "verify.py: dos reglas con el mismo check: se muestra el mensaje de la segunda"
n=$(grep -c 'args:' "$TMP/mal-check.args"); [ "$n" = 1 ]; tap_check $? "verify.py: dos reglas con el mismo check lo corren una sola vez"

manifiesto mal-check
rm -f "$TMP/mal-check.args"
GH_MODE=pr PATH="$TMP/bin:$PATH" verify 0 --pr 7
[ ! -e "$TMP/mal-check.args" ]; tap_check $? "verify.py --pr: no corre los checks de las reglas (miran el PR de la rama del checkout, no el pedido)"
grep -q 'Skipped.*rule checks' <<<"$out"; tap_check $? "verify.py --pr: dice que salteó los checks de las reglas"
grep -q 'All verified' <<<"$out"; [ $? -eq 1 ]; tap_check $? "verify.py --pr: con los checks de las reglas salteados no dice All verified"
grep -q 'not verified' <<<"$out"; tap_check $? "verify.py --pr: con los checks de las reglas salteados los da por no verificados"

# --- verify.py deja un evento check_run por cada check que corre (#323, fase 0 de #321) ---
EV="$P/.barrilete/learning/events.jsonl"
# ev.py resume el registro: "n=<líneas>", y por evento "raw <línea>", "<rule_id> <outcome> <claves ordenadas>"
# (o "json-roto") y sus metadatos. Sin registro imprime n=0: un caso falla, no un crash.
cat >"$TMP/ev.py" <<'EOF'
import json, os, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines() if os.path.exists(sys.argv[1]) else []
print("n=%d" % len(lines))
for l in lines:
    print("raw " + l)
    try:
        e = json.loads(l)
    except ValueError:
        print("json-roto"); continue
    print(e.get("rule_id"), e.get("outcome"), ",".join(sorted(e)))
    for k in ("task_id", "harness", "model", "project", "branch", "check", "v", "kind"):
        if k in e: print("%s=%s" % (k, e[k]))
EOF
eventos() { cd "$TMP" || exit 2; tap_run out 0 python3 "$TMP/ev.py" "$EV"; }

rm -rf "$P/.barrilete/learning"
manifiesto ok-check mal-check
verify 1
eventos
grep -qx 'r-ok-check pass .*' <<<"$out"; tap_check $? "check_run: un check que pasa deja outcome pass con su regla"
grep -qx 'r-mal-check fail .*' <<<"$out"; tap_check $? "check_run: un check que falla deja outcome fail con su regla"
grep -qx 'n=2' <<<"$out"; tap_check $? "check_run: una línea por check, nada más"
grep -qx 'kind=check_run' <<<"$out"; tap_check $? "check_run: el evento dice kind check_run"
grep -qx 'v=1' <<<"$out"; tap_check $? "check_run: el evento lleva la versión 1 del esquema (ADR-007)"
grep -qx 'project=remoto' <<<"$out"; tap_check $? "check_run: el evento lleva el proyecto, el nombre del repo"
grep -qx 'model=unknown' <<<"$out"; tap_check $? "check_run: sin BK_MODEL el modelo es unknown"
grep -q '^branch=' <<<"$out"; [ $? -eq 1 ]; tap_check $? "check_run: el evento no lleva la rama (no está en la tabla de ADR-007)"
grep -q '^check=' <<<"$out"; [ $? -eq 1 ]; tap_check $? "check_run: el evento no lleva el id del check (no está en la tabla de ADR-007)"
grep -q '^raw .*arreglá' <<<"$out"; [ $? -eq 1 ]; tap_check $? "check_run: el evento no lleva el fail_message"
grep -q '^raw .*no se cumple' <<<"$out"; [ $? -eq 1 ]; tap_check $? "check_run: el evento no lleva la salida del check"
grep -qx 'r-mal-check fail harness,kind,model,outcome,project,rule_id,ts,v' <<<"$out"; tap_check $? "check_run: sin BK_TASK_DIR ni rules.lock, solo los obligatorios de ADR-007 y la regla"

rm -rf "$P/.barrilete/learning"
verify 0 --list
[ ! -e "$EV" ]; tap_check $? "check_run: verify.py --list no registra nada"

rm -rf "$P/.barrilete/learning"
printf '{"checks": [{"id": "mal-check", "rule": "regla-a", "fail_message": "a"}, {"id": "mal-check", "rule": "regla-b", "fail_message": "b"}]}\n' >"$P/.barrilete/checks.json"
verify 1
eventos
grep -qx 'regla-b fail .*' <<<"$out"; tap_check $? "check_run: dos reglas con el mismo check dejan un evento por regla"
grep -qx 'regla-a fail .*' <<<"$out"; tap_check $? "check_run: dos reglas con el mismo check: también la primera"
grep -qx 'n=2' <<<"$out"; tap_check $? "check_run: dos reglas con el mismo check: dos eventos, ni uno más"

rm -rf "$P/.barrilete/learning"
mkdir -p "$TMP/tarea"; printf '{"id": "323-implementer", "status": "in_progress"}\n' >"$TMP/tarea/task.json"
manifiesto ok-check
BK_TASK_DIR="$TMP/tarea" CLAUDECODE=1 verify 0
eventos
grep -qx 'task_id=323-implementer' <<<"$out"; tap_check $? "check_run: con BK_TASK_DIR lleva el id de la tarea (ADR-005)"
grep -qx 'harness=claude-code' <<<"$out"; tap_check $? "check_run: dentro de Claude Code (CLAUDECODE=1) lleva harness claude-code"
rm -rf "$P/.barrilete/learning"
BK_HARNESS=codex CLAUDECODE=1 verify 0
eventos
grep -qx 'harness=codex' <<<"$out"; tap_check $? "check_run: BK_HARNESS manda sobre lo que se deduce del entorno"
rm -rf "$P/.barrilete/learning"
BK_HARNESS=Codex_X CLAUDECODE=1 verify 0
eventos
grep -qx 'harness=unknown' <<<"$out"; tap_check $? "check_run: un BK_HARNESS inválido no se reemplaza por claude-code: el harness es unknown"
rm -rf "$P/.barrilete/learning"
mkdir -p "$TMP/tarea-sin-json"
BK_TASK_DIR="$TMP/tarea-sin-json" verify 0
eventos
grep -q '^task_id=' <<<"$out"; [ $? -eq 1 ]; tap_check $? "check_run: sin task.json legible no se inventa un task_id"

rm -rf "$P/.barrilete/learning"
manifiesto pr-metadata
GH_MODE=none PATH="$TMP/bin:$PATH" verify 0
eventos
grep -qx 'r-pr-metadata skipped .*' <<<"$out"; tap_check $? "check_run: un check que no pudo verificar (sale con 4) deja skipped"

# Un archivo donde va la carpeta: no se puede escribir el registro ni siendo root (chmod no frena a root)
rm -rf "$P/.barrilete/learning"; echo no-es-carpeta >"$P/.barrilete/learning"
manifiesto ok-check mal-check
verify 1
grep -q 'could not record' <<<"$out"; tap_check $? "check_run: si no puede escribir el registro lo avisa"
[ "$(grep -c 'could not record' <<<"$out")" -eq 1 ]; tap_check $? "check_run: con dos checks que no pudo registrar, el aviso sale una sola vez"
grep -q 'FAILED *check:mal-check' <<<"$out"; tap_check $? "check_run: sin poder escribir el registro, verify.py sigue igual"
rm -f "$P/.barrilete/learning"

# El registro se ignora solo, aunque el .gitignore del proyecto no tenga la línea (el de $P no la tiene)
manifiesto ok-check
verify 0
st=$(git -C "$P" status --porcelain -uall 2>&1)
grep -q 'learning' <<<"$st"; [ $? -eq 1 ]; tap_check $? "check_run: el registro no aparece como cambio aunque el .gitignore del proyecto no lo ignore"

# Desde un worktree (un agente de /orchestrate o de bk), el registro va al checkout principal: el worktree se borra
rm -rf "$P/.barrilete/learning"
git -C "$P" worktree add -q --detach "$TMP/wt" HEAD 2>/dev/null
mkdir -p "$TMP/wt/.barrilete" "$TMP/wt/scripts/agents/checks"
cp "$P/.barrilete/checks.json" "$TMP/wt/.barrilete/"; cp "$P/scripts/agents/checks/ok-check" "$TMP/wt/scripts/agents/checks/"
cd "$TMP/wt" || exit 2
BASE=main tap_run out 0 python3 "$TMP/rc.py" python3 scripts/agents/verify.py
cd "$TMP" || exit 2
tap_no_traceback "$out"
eventos
grep -qx 'r-ok-check pass .*' <<<"$out"; tap_check $? "check_run: desde un worktree, el evento queda en el checkout principal"
[ ! -e "$TMP/wt/.barrilete/learning/events.jsonl" ]; tap_check $? "check_run: desde un worktree, nada queda dentro del worktree"
grep -q '^branch=' <<<"$out"; [ $? -eq 1 ]; tap_check $? "check_run: con HEAD suelto (el worktree está en --detach) el evento no lleva rama"
git -C "$P" worktree remove --force "$TMP/wt"

# Si verify.py muere a mitad de camino, los checks que ya terminaron quedan registrados
rm -rf "$P/.barrilete/learning"
printf '#!/bin/sh
p=$PPID
case "$(ps -o comm= -p "$p")" in *sh) p=$(ps -o ppid= -p "$p") ;; esac
kill -TERM $p
sleep 5
' >"$P/scripts/agents/checks/corta"
chmod +x "$P/scripts/agents/checks/corta"
manifiesto ok-check corta
cd "$P" || exit 2
BASE=main tap_run out 0 python3 "$TMP/rc.py" python3 scripts/agents/verify.py
cd "$TMP" || exit 2
eventos
grep -qx 'r-ok-check pass .*' <<<"$out"; tap_check $? "check_run: un check que terminó queda registrado aunque verify.py muera después"
rm "$P/.barrilete/checks.json"

# 8. Falsos rechazos y falsos verdes que encontró el review (#294): cada caso falla si se borra lo que chequea.
cd "$P" || exit 1
CASO="scripts/agents/test-x.sh::caso uno"
chequear() { GH_MODE=pr PATH="$TMP/bin:$PATH" tap_run out "$1" python3 scripts/agents/checks/pr-metadata --base origin/main; }
# 8a. Un "N commits" que habla de otra cosa (un cherry-pick) no es la cantidad de commits del PR.
pr 12 "$(printf '%s\n\nCherry-pick de 9 commits de #280.\n' "$BIEN")"
chequear 0
[ "$TAP_RC" = 0 ]; tap_check $? "commits: 'cherry-pick de 9 commits de #280' no se lee como la cantidad de commits del PR"
pr 12 "$(printf '%s\n\n(9 commits sobre origin/main)\n' "$BIEN")"
chequear 3
grep -q 'body says 9 commits' <<<"$out"; tap_check $? "commits: '(9 commits sobre origin/main)' sigue contando como afirmación del PR"
# 8b. Las formas de cerrar un issue que GitHub entiende.
pr 12 "$(cuerpo "$RED" 2 "$CASO" "Closes: #7")"
chequear 0
[ "$TAP_RC" = 0 ]; tap_check $? "issue: 'Closes: #7' (con dos puntos) se reconoce como el issue de la rama"
pr 12 "$(cuerpo "$RED" 2 "$CASO" "Closes lautioliver/barrilete-kit#7")"
chequear 0
[ "$TAP_RC" = 0 ]; tap_check $? "issue: 'Closes owner/repo#7' se reconoce como el issue de la rama"
pr 12 "$(cuerpo "$RED" 2 "$CASO" "Closes https://github.com/lautioliver/barrilete-kit/issues/7")"
chequear 0
[ "$TAP_RC" = 0 ]; tap_check $? "issue: 'Closes <url del issue>' se reconoce como el issue de la rama"
# 8c. Un caso escrito entre backticks es el mismo caso.
pr 12 "$(cuerpo "$RED" 2 "\`$CASO\`" "Closes #7")"
chequear 0
[ "$TAP_RC" = 0 ]; tap_check $? "casos: un caso entre backticks se busca sin los backticks"
# 8d. El bloque rojo termina con la lista de casos: lo que sigue después de una línea en blanco no son casos.
pr 12 "$(printf '## How to test it\n\nred commit: %s\n\nfailing cases:\n- %s\n\nNotas:\n- ver foo::bar\n\n2 commits.\n\nCloses #7\n' "$RED" "$CASO")"
chequear 0
[ "$TAP_RC" = 0 ]; tap_check $? "casos: una lista con '::' después de la lista de casos y una línea en blanco no son casos"
# 8e. Una rama sin <tipo>/<n>-: el issue no se chequea y se dice siempre, también cuando el cuerpo falla por otra cosa.
git -C "$P" switch -q -c sin-numero
pr 12 "$(cuerpo "$RED" 3 "$CASO" "Closes #7")"
chequear 3
grep -q 'issue was not checked' <<<"$out"; tap_check $? "issue: en una rama sin número se avisa que no se chequeó el issue aunque el cuerpo falle"
git -C "$P" switch -q claude/7-algo

# 9. Tercera vuelta del review (#294).
# 9a. Varios issues tras un keyword; y una referencia a otro repo no es el issue de la rama.
pr 12 "$(cuerpo "$RED" 2 "$CASO" "Closes #30, #7")"
chequear 0
[ "$TAP_RC" = 0 ]; tap_check $? "issue: 'Closes #30, #7' reconoce el segundo issue de la lista"
pr 12 "$(cuerpo "$RED" 2 "$CASO" "Refs otro/repo#7")"
chequear 3
grep -q 'needs Closes #7' <<<"$out"; tap_check $? "issue: 'Refs otro/repo#7' (otro repo) no cuenta como el issue de la rama"
# 9b. Los casos también se escriben con * y con 1. y un path vacío no vale.
pr 12 "$(cuerpo "$RED" 2 "" "Closes #7" | sed 's|^failing cases:$|failing cases:\n* scripts/agents/test-x.sh::no existe\n|')"
chequear 3
grep -q 'no existe' <<<"$out"; tap_check $? "casos: un caso con * se lee y, si no está en el archivo, falla"
pr 12 "$(cuerpo "$RED" 2 "" "Closes #7" | sed 's|^failing cases:$|failing cases:\n1. scripts/agents/test-x.sh::no existe\n|')"
chequear 3
grep -q 'no existe' <<<"$out"; tap_check $? "casos: un caso con 1. se lee y, si no está en el archivo, falla"
pr 12 "$(cuerpo "$RED" 2 "::caso uno" "Closes #7")"
chequear 3
grep -q 'no file path' <<<"$out"; tap_check $? "casos: un caso con el path vacío falla y dice que no tiene path"

tap_done
