#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2319,SC2181  # out lo asigna tap_run; el $ de los JSON es texto
# Tests del evento de aprendizaje y el store del proyecto (#324, ADR-007 D2, D3, D6): el validador del evento v1,
# la escritura que respeta `.barrilete/learning.json` (local o la rama agents/learning), `rules_ref` y el task_end
# que deja task_events.py cuando la tarea de `bk` terminó.
# No toca la red: el remoto es un repo bare local.
# Uso: bash scripts/agents/test-learning.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-learning-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
export PYTHONDONTWRITEBYTECODE=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset BK_TASK_DIR BK_HARNESS BK_MODEL BK_PROVIDER BARRILETE_MODEL BARRILETE_PROVIDER CLAUDECODE CLAUDE_PROJECT_DIR   # cada caso pone los suyos
out=""

# --- un proyecto "proyecto" con su remoto, en la rama de trabajo claude/9-algo ---
git init -q --bare -b main "$TMP/proyecto.git"
git clone -q "$TMP/proyecto.git" "$TMP/proyecto" 2>/dev/null
P="$TMP/proyecto"
mkdir -p "$P/scripts" "$P/.barrilete"
cp -R "$RAIZ/scripts/agents" "$P/scripts/"
rm -rf "$P/scripts/agents/__pycache__"
git -C "$P" switch -q -c main
git -C "$P" add -A && git -C "$P" commit -qm base && git -C "$P" push -q origin main 2>/dev/null
git -C "$P" switch -q -c claude/9-algo
L="scripts/agents/learning.py"

# ev.py resume un store: `ev.py file <ruta>` o `ev.py ref <repo> <ref>` (el events.jsonl de esa rama). Imprime "n=<líneas>"
# (con `ref`, también "commits=<n>" de la rama) y por evento "<kind> <outcome> <claves ordenadas>" y sus campos "k=v". Sin store imprime n=0: un caso falla, no un crash.
cat >"$TMP/ev.py" <<'EOF'
import json, os, subprocess, sys
if sys.argv[1] == "file":
    lines = open(sys.argv[2], encoding="utf-8").read().splitlines() if os.path.exists(sys.argv[2]) else []
else:
    r = subprocess.run(["git", "-C", sys.argv[2], "cat-file", "-p", sys.argv[3] + ":events.jsonl"], capture_output=True, text=True)
    lines = r.stdout.splitlines() if r.returncode == 0 else []
    c = subprocess.run(["git", "-C", sys.argv[2], "rev-list", "--count", sys.argv[3]], capture_output=True, text=True)
    print("commits=%s" % (c.stdout.strip() if c.returncode == 0 else 0))
print("n=%d" % len(lines))
for l in lines:
    try:
        e = json.loads(l)
    except ValueError:
        print("json-roto"); continue
    print(e.get("kind"), e.get("outcome"), ",".join(sorted(e)))
    for k in sorted(e):
        print("%s=%s" % (k, e[k]))
EOF
ev() { cd "$TMP" || exit 2; tap_run out 0 python3 "$TMP/ev.py" "$@"; cd "$P" || exit 2; }
EVL="$P/.barrilete/learning/events.jsonl"

# --- 1. El validador (D3): campos de la tabla, obligatorios, sin texto libre ---
cd "$P" || exit 2
valida() { printf '%s\n' "$@" >"$TMP/v.jsonl"; tap_run out 3 python3 "$L" validate "$TMP/v.jsonl"; }
BUENO='{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "task_id": "324-implementer", "pr": 12, "provider": "anthropic", "model": "claude-sonnet-5-5", "harness": "claude-code", "area": "infra", "role": "implementer", "kind": "check_run", "rule_id": "pr-metadata", "outcome": "pass", "evidence_ref": "https://github.com/o/r/pull/12", "rules_ref": "9abec4a99f6d.0123456789ab"}'
printf '%s\n' "$BUENO" >"$TMP/v.jsonl"
tap_run out 0 python3 "$L" validate "$TMP/v.jsonl"
grep -q '^ok: 1 event' <<<"$out"; tap_check $? "validador: un evento con todos los campos de la tabla es válido"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "model": "unknown", "harness": "unknown", "class": "stale-docs"}'
[ "$TAP_RC" -eq 3 ]; [ $? -eq 1 ]; tap_check $? "validador: model y harness unknown son válidos (D3)"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "model": "m", "harness": "pi", "class": "x", "nota": "el cliente pidió esto"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: un campo que no está en la tabla se rechaza"
grep -q 'nota' <<<"$out"; tap_check $? "validador: el rechazo de un campo de más lo nombra"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "harness": "pi", "class": "x"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: sin model se rechaza"
grep -q 'model' <<<"$out"; tap_check $? "validador: el rechazo sin model lo nombra"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "model": "m", "class": "x"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: sin harness se rechaza"
grep -q 'harness' <<<"$out"; tap_check $? "validador: el rechazo sin harness lo nombra"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "model": "el modelo dijo que el cliente quiere esto", "harness": "pi"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: texto libre dentro de un campo de la tabla se rechaza"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "model": "m", "harness": "pi", "outcome": "pass"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: un finding con outcome se rechaza"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "check_run", "model": "m", "harness": "pi", "rule_id": "r", "outcome": "completed"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: un check_run con un outcome de task_end se rechaza"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "task_end", "model": "m", "harness": "pi", "outcome": "cancelled"}'
[ "$TAP_RC" -eq 3 ]; [ $? -eq 1 ]; tap_check $? "validador: un task_end con un estado terminal de ADR-005 es válido"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "check_run", "model": "m", "harness": "pi", "rule_id": "r", "outcome": "pass", "rules_ref": "main"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: un rules_ref que no es <lock12>.<hash12> se rechaza"
valida '{"v": 0, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "model": "m", "harness": "pi"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: una versión que no es 1 se rechaza"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": "finding", "model": "m", "harness": "pi", "pr": true}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: un pr que no es un número se rechaza"
valida '{"v": 1, "ts": "2026-11-16T12:00:00Z", "project": "proyecto", "kind": ["finding"], "model": "m", "harness": "pi"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: un kind que no es texto (una lista) se rechaza, sin traceback"
tap_no_traceback "$out"
printf '\377\376\n' >"$TMP/v.jsonl"
tap_run out 3 python3 "$L" validate "$TMP/v.jsonl"
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: un archivo que no es UTF-8 sale con 3, sin traceback"
tap_no_traceback "$out"
valida "$BUENO" '{"v": 1}'
grep -q 'line 2' <<<"$out"; tap_check $? "validador: dice en qué línea está el evento roto"
grep -q 'line 1' <<<"$out"; [ $? -eq 1 ]; tap_check $? "validador: no marca la línea que está bien"
# Las líneas v0 de #323 (verify.py antes del v1) se toleran como heredadas: se cuentan aparte y no se marcan rotas.
V0='{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "numeros-del-pr", "outcome": "skipped", "branch": "claude/323-registrar-algo", "harness": "claude-code"}'
printf '%s\n' "$BUENO" "$V0" >"$TMP/v.jsonl"
tap_run out 0 python3 "$L" validate "$TMP/v.jsonl"
[ "$TAP_RC" -eq 0 ]; tap_check $? "validador: una línea v0 de check_run de #323 no se marca rota"
grep -q '^ok: 1 event(s), 1 legacy v0' <<<"$out"; tap_check $? "validador: la línea v0 se cuenta aparte, como heredada"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "nota": "texto"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: una línea v0 con un campo que v0 no tenía se rechaza"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "completed"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: una línea v0 con un outcome que v0 no tenía se rechaza"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "rule_id": "r", "outcome": "pass"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: una línea v0 sin check se rechaza"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "una rama con espacios"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: una línea v0 con texto libre en branch se rechaza"
valida '{"v": 1, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "main"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: una línea con la forma v0 pero v=1 no se cuenta como heredada"
valida '{"v": 7, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "main"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "validador: una línea con la forma v0 pero v=7 no se cuenta como heredada"

# --- 2. Store local (por defecto, D2): sin learning.json va al directorio ignorado del checkout principal ---
tap_run out 0 python3 "$L" emit check_run rule_id=r-uno outcome=pass
ev file "$EVL"
grep -qx 'n=1' <<<"$out"; tap_check $? "store local: sin learning.json, emit escribe en .barrilete/learning/events.jsonl"
grep -qx 'v=1' <<<"$out"; tap_check $? "store local: el evento es v1"
grep -qx 'project=proyecto' <<<"$out"; tap_check $? "store local: el evento lleva el proyecto, el nombre del repo"
grep -qx 'model=unknown' <<<"$out"; tap_check $? "emit: sin BK_MODEL el modelo es unknown, no se adivina"
grep -qx 'harness=unknown' <<<"$out"; tap_check $? "emit: sin harness conocido es unknown"
[ -z "$(git -C "$P" for-each-ref refs/heads/agents/learning 2>&1)" ]; tap_check $? "store local: no crea la rama agents/learning"
[ -z "$(git -C "$P" status --porcelain 2>&1)" ]; tap_check $? "store local: el registro no aparece como cambio"
BK_MODEL=claude-opus-5-5 BK_HARNESS=codex BK_PROVIDER=anthropic tap_run out 0 python3 "$L" emit check_run rule_id=r-dos outcome=fail
ev file "$EVL"
grep -qx 'model=claude-opus-5-5' <<<"$out"; tap_check $? "emit: BK_MODEL da el modelo"
grep -qx 'harness=codex' <<<"$out"; tap_check $? "emit: BK_HARNESS da el harness"
grep -qx 'provider=anthropic' <<<"$out"; tap_check $? "emit: BK_PROVIDER da el proveedor"
# bk exporta BARRILETE_MODEL y BARRILETE_PROVIDER (barrilete-workspace bin/bk): el kit los lee si no hay BK_*.
BARRILETE_MODEL=claude-sonnet-5-5 BARRILETE_PROVIDER=openai tap_run out 0 python3 "$L" emit check_run rule_id=r-bar outcome=pass
tail -n 1 "$EVL" >"$TMP/ult.jsonl"; ev file "$TMP/ult.jsonl"
grep -qx 'model=claude-sonnet-5-5' <<<"$out"; tap_check $? "emit: sin BK_MODEL, BARRILETE_MODEL da el modelo"
grep -qx 'provider=openai' <<<"$out"; tap_check $? "emit: sin BK_PROVIDER, BARRILETE_PROVIDER da el proveedor"
BK_MODEL=claude-opus-5-5 BARRILETE_MODEL=claude-haiku-5-5 BK_PROVIDER=anthropic BARRILETE_PROVIDER=openai tap_run out 0 python3 "$L" emit check_run rule_id=r-ambas outcome=pass
tail -n 1 "$EVL" >"$TMP/ult.jsonl"; ev file "$TMP/ult.jsonl"
grep -qx 'model=claude-opus-5-5' <<<"$out"; tap_check $? "emit: BK_MODEL manda sobre BARRILETE_MODEL"
grep -qx 'provider=anthropic' <<<"$out"; tap_check $? "emit: BK_PROVIDER manda sobre BARRILETE_PROVIDER"
tap_run out 3 python3 "$L" emit check_run rule_id="con espacios" outcome=pass
[ "$TAP_RC" -eq 3 ]; tap_check $? "emit: un evento inválido sale con 3"
ev file "$EVL"
grep -qx 'n=4' <<<"$out"; tap_check $? "emit: un evento inválido no se escribe"
git -C "$P" worktree add -q "$TMP/wt" -b claude/9-wt 2>/dev/null
cd "$TMP/wt" || exit 2
tap_run out 0 python3 "$L" emit check_run rule_id=r-wt outcome=pass
cd "$P" || exit 2
ev file "$EVL"
grep -qx 'n=5' <<<"$out"; tap_check $? "store local: desde un worktree el evento va al checkout principal"
[ ! -e "$TMP/wt/.barrilete/learning/events.jsonl" ]; tap_check $? "store local: desde un worktree nada queda en el worktree"

# Sin origin, el proyecto es la carpeta: un nombre fuera de la forma de la tabla se limpia, no deja de escribir
mkdir -p "$TMP/mi proyecto ñ"
git init -q "$TMP/mi proyecto ñ"
cd "$TMP/mi proyecto ñ" || exit 2
tap_run out 0 python3 "$P/$L" emit check_run rule_id=r-carpeta outcome=pass
cd "$P" || exit 2
ev file "$TMP/mi proyecto ñ/.barrilete/learning/events.jsonl"
grep -qx 'n=1' <<<"$out"; tap_check $? "emit: sin origin y con una carpeta con espacios o ñ el evento se escribe igual"
grep -qx 'project=mi-proyecto-' <<<"$out"; tap_check $? "emit: lo que no entra en la forma del proyecto queda como -"

# --- 3. Store branch (D2): la rama agents/learning, sin tocar la rama de trabajo ---
rm -rf "$P/.barrilete/learning"
printf '{"store": "branch"}\n' >"$P/.barrilete/learning.json"
git -C "$P" add .barrilete/learning.json && git -C "$P" commit -qm store
H=$(git -C "$P" rev-parse HEAD 2>&1)
tap_run out 0 python3 "$L" emit check_run rule_id=r-rama outcome=pass
ev ref "$P" refs/heads/agents/learning
grep -qx 'n=1' <<<"$out"; tap_check $? "store branch: el evento queda en agents/learning"
grep -qx 'rule_id=r-rama' <<<"$out"; tap_check $? "store branch: es el evento que se emitió"
[ "$(git -C "$P" rev-parse HEAD 2>&1)" = "$H" ]; tap_check $? "store branch: la rama de trabajo no se mueve"
[ "$(git -C "$P" symbolic-ref --short HEAD 2>&1)" = claude/9-algo ]; tap_check $? "store branch: sigue en la rama de trabajo"
[ -z "$(git -C "$P" status --porcelain 2>&1)" ]; tap_check $? "store branch: ni el índice ni el árbol cambian"
[ ! -e "$EVL" ]; tap_check $? "store branch: no escribe el archivo local"
tap_run out 0 python3 "$L" emit check_run rule_id=r-rama2 outcome=fail
ev ref "$P" refs/heads/agents/learning
grep -qx 'n=2' <<<"$out"; tap_check $? "store branch: el segundo evento se suma al primero"
grep -qx 'commits=2' <<<"$out"; tap_check $? "store branch: un commit por escritura, en línea"
git -C "$TMP/wt" merge -q claude/9-algo 2>/dev/null
cd "$TMP/wt" || exit 2
tap_run out 0 python3 "$L" emit check_run rule_id=r-rama-wt outcome=pass
cd "$P" || exit 2
ev ref "$P" refs/heads/agents/learning
grep -qx 'n=3' <<<"$out"; tap_check $? "store branch: desde un worktree escribe en la misma rama"
[ -z "$(git -C "$TMP/proyecto.git" for-each-ref refs/heads/agents/learning 2>&1)" ]; tap_check $? "store branch: emit no sube nada al remoto"
tap_run out 0 python3 "$L" push
ev ref "$TMP/proyecto.git" refs/heads/agents/learning
grep -qx 'n=3' <<<"$out"; tap_check $? "push: sube agents/learning al remoto"
# Otro clon escribe y sube; este escribe también: el push junta los dos lados, no pisa ninguno
git clone -q "$TMP/proyecto.git" "$TMP/otro" 2>/dev/null
git -C "$TMP/otro" switch -q main 2>/dev/null
git -C "$P" push -q origin claude/9-algo:main 2>/dev/null
git -C "$TMP/otro" pull -q 2>/dev/null
cd "$TMP/otro" || exit 2
tap_run out 0 python3 "$L" emit check_run rule_id=r-otro outcome=pass
tap_run out 0 python3 "$L" push
cd "$P" || exit 2
tap_run out 0 python3 "$L" emit check_run rule_id=r-local outcome=pass
tap_run out 0 python3 "$L" push
ev ref "$TMP/proyecto.git" refs/heads/agents/learning
grep -qx 'n=5' <<<"$out"; tap_check $? "push: con el remoto adelante junta las dos historias"
grep -qx 'rule_id=r-otro' <<<"$out"; tap_check $? "push: conserva el evento del otro clon"
grep -qx 'rule_id=r-local' <<<"$out"; tap_check $? "push: suma el evento local"
tap_run out 0 python3 "$L" push
ev ref "$TMP/proyecto.git" refs/heads/agents/learning
grep -qx 'n=5' <<<"$out"; tap_check $? "push: otra vez sin eventos nuevos no duplica nada"
# Un rechazo que no es una carrera (un hook del remoto) no se reintenta: sale con 1 y dice lo que dijo git
printf '#!/bin/sh\necho "hook: agents/learning no se acepta acá" >&2\nexit 1\n' >"$TMP/proyecto.git/hooks/pre-receive"
chmod +x "$TMP/proyecto.git/hooks/pre-receive"
tap_run out 0 python3 "$L" emit check_run rule_id=r-hook outcome=pass
tap_run out 1 python3 "$L" push
[ "$TAP_RC" -eq 1 ]; tap_check $? "push: un rechazo del remoto sale con 1"
grep -q 'no se acepta acá' <<<"$out"; tap_check $? "push: un rechazo del remoto muestra el motivo que dio git"
grep -q 'kept moving' <<<"$out"; [ $? -eq 1 ]; tap_check $? "push: un rechazo del remoto no se confunde con una carrera"
rm -f "$TMP/proyecto.git/hooks/pre-receive"

printf '{"store": "nube"}\n' >"$P/.barrilete/learning.json"
tap_run out 3 python3 "$L" emit check_run rule_id=r-nube outcome=pass
[ "$TAP_RC" -eq 3 ]; tap_check $? "learning.json: un store desconocido es un error"
grep -q 'learning.json' <<<"$out"; tap_check $? "learning.json: el error nombra el archivo"
printf '{"store": "nube"}\n' >"$P/.barrilete/learning.json"
tap_run out 3 python3 "$L" push
[ "$TAP_RC" -eq 3 ]; tap_check $? "push: un learning.json inválido sale con 3, como en emit (1 es una falla de git)"
git -C "$P" checkout -q -- .barrilete/learning.json

# --- 4. rules_ref (D6): <12 del SHA de rules.lock>.<12 del sha256 de las secciones generadas que lee el rol> ---
printf '{"store": "local"}\n' >"$P/.barrilete/learning.json"
printf 'repo=o/barrilete-rules\nsha=9abec4a99f6d1dfc7f1d879e9f20427db60500e0\n' >"$P/.barrilete/rules.lock"
mkdir -p "$P/.claude/agents"
bloque() { printf 'antes\n<!-- rules:begin o/barrilete-rules@9abec4a (generated) -->\n## Rules\n- %s\n<!-- rules:end -->\ndespués\n' "$1"; }
bloque "regla común" >"$P/AGENTS.md"
bloque "regla del implementer" >"$P/.claude/agents/implementer.md"
bloque "regla del reviewer" >"$P/.claude/agents/reviewer.md"
tap_run out 0 python3 "$L" rules-ref implementer
R1=$out
grep -qx '9abec4a99f6d\.[0-9a-f]\{12\}' <<<"$R1"; tap_check $? "rules_ref: son 12 del SHA del lock, un punto y 12 hex"
tap_run out 0 python3 "$L" rules-ref reviewer
[ "${out:-vacío}" != "${R1:-vacío}" ]; tap_check $? "rules_ref: cada rol tiene su hash (lee su propia sección)"
printf 'otra cosa fuera del bloque\n' >>"$P/.claude/agents/implementer.md"
tap_run out 0 python3 "$L" rules-ref implementer
[ "${out:-vacío}" = "${R1:-nada}" ]; tap_check $? "rules_ref: un cambio fuera de la sección generada no lo cambia"
bloque "regla vieja del implementer" >"$P/.claude/agents/implementer.md"
tap_run out 0 python3 "$L" rules-ref implementer
[ "${out:-vacío}" != "${R1:-vacío}" ]; tap_check $? "rules_ref: una sección generada distinta da otro hash (el agente corrió con otra versión)"
bloque "regla común vieja" >"$P/AGENTS.md"
bloque "regla del implementer" >"$P/.claude/agents/implementer.md"
tap_run out 0 python3 "$L" rules-ref implementer
[ "${out:-vacío}" != "${R1:-vacío}" ]; tap_check $? "rules_ref: el bloque de AGENTS.md también cuenta"
bloque "regla común" >"$P/AGENTS.md"
mkdir -p "$TMP/tarea"
printf '{"id": "324-implementer", "project": "proyecto", "role": "implementer", "status": "in_progress", "pr": 12, "seq": 1, "created": "2026-11-16T10:00:00.000Z"}\n' >"$TMP/tarea/task.json"
: >"$TMP/tarea/events.jsonl"
rm -rf "$P/.barrilete/learning"
BK_TASK_DIR="$TMP/tarea" tap_run out 0 python3 "$L" emit check_run rule_id=r-tarea outcome=pass
ev file "$EVL"
grep -qx "rules_ref=$R1" <<<"$out"; tap_check $? "emit: con BK_TASK_DIR lleva el rules_ref del rol de la tarea"
grep -qx 'task_id=324-implementer' <<<"$out"; tap_check $? "emit: con BK_TASK_DIR lleva el task_id"
grep -qx 'role=implementer' <<<"$out"; tap_check $? "emit: con BK_TASK_DIR lleva el rol"
grep -qx 'pr=12' <<<"$out"; tap_check $? "emit: con BK_TASK_DIR lleva el pr de la tarea"
rm -f "$P/.barrilete/rules.lock"; rm -rf "$P/.barrilete/learning"
tap_run out 0 python3 "$L" emit check_run rule_id=r-sin-lock outcome=pass
ev file "$EVL"
grep -qx 'n=1' <<<"$out"; tap_check $? "rules_ref: sin rules.lock el evento igual se escribe"
grep -q '^rules_ref=' <<<"$out"; [ $? -eq 1 ]; tap_check $? "rules_ref: sin rules.lock el evento no lo lleva"

# --- 5. task_end (D3): task_events.py lo deja en el Stop que sigue a `bk done`; nunca frena nada (ADR-005) ---
TE="$P/scripts/agents/task_events.py"
printf '{"hook_event_name": "Stop"}\n' >"$TMP/stop.json"
rm -rf "$P/.barrilete/learning"
printf '{"id": "324-implementer", "project": "proyecto", "role": "implementer", "status": "completed", "pr": 12, "seq": 3, "created": "2026-11-16T10:00:00.000Z", "closed": "2026-11-16T11:00:00.000Z"}\n' >"$TMP/tarea/task.json"
printf '{"seq": 3, "type": "task.completed"}\n' >"$TMP/tarea/events.jsonl"
cp "$TMP/tarea/task.json" "$TMP/task.antes"; cp "$TMP/tarea/events.jsonl" "$TMP/events.antes"
BK_TASK_DIR="$TMP/tarea" tap_run out 0 python3 "$TE" <"$TMP/stop.json"
ev file "$EVL"
grep -qx 'task_end completed .*' <<<"$out"; tap_check $? "task_end: el Stop de una tarea terminada deja task_end con su estado"
grep -qx 'task_id=324-implementer' <<<"$out"; tap_check $? "task_end: lleva el task_id"
grep -qx 'role=implementer' <<<"$out"; tap_check $? "task_end: lleva el rol"
grep -qx 'pr=12' <<<"$out"; tap_check $? "task_end: lleva el pr"
cmp -s "$TMP/tarea/task.json" "$TMP/task.antes"; tap_check $? "task_end: no toca el task.json de una tarea terminada (ADR-005)"
cmp -s "$TMP/tarea/events.jsonl" "$TMP/events.antes"; tap_check $? "task_end: no suma eventos a la tarea (ADR-005)"
BK_TASK_DIR="$TMP/tarea" tap_run out 0 python3 "$TE" <"$TMP/stop.json"
ev file "$EVL"
grep -qx 'n=1' <<<"$out"; tap_check $? "task_end: un segundo Stop no lo repite"
printf '{"id": "324-implementer", "project": "proyecto", "role": "implementer", "status": "failed", "seq": 2, "created": "2026-11-17T10:00:00.000Z"}\n' >"$TMP/tarea/task.json"
BK_TASK_DIR="$TMP/tarea" tap_run out 0 python3 "$TE" <"$TMP/stop.json"
ev file "$EVL"
grep -qx 'task_end failed .*' <<<"$out"; tap_check $? "task_end: una tarea nueva con el mismo id deja su propio task_end"
rm -rf "$P/.barrilete/learning"
printf '{"id": "325-implementer", "role": "implementer", "status": "in_progress", "seq": 1, "created": "2026-11-16T10:00:00.000Z"}\n' >"$TMP/tarea/task.json"
BK_TASK_DIR="$TMP/tarea" tap_run out 0 python3 "$TE" <"$TMP/stop.json"
[ ! -e "$EVL" ]; tap_check $? "task_end: una tarea que sigue abierta no deja task_end"
printf '{"id": "326-implementer", "role": "implementer", "status": "completed", "seq": 1, "created": "2026-11-16T10:00:00.000Z"}\n' >"$TMP/tarea/task.json"
tap_run out 0 python3 "$TE" <"$TMP/stop.json"
[ ! -e "$EVL" ]; tap_check $? "task_end: sin BK_TASK_DIR no escribe nada"
printf '{"store": "nube"}\n' >"$P/.barrilete/learning.json"
BK_TASK_DIR="$TMP/tarea" tap_run out 0 python3 "$TE" <"$TMP/stop.json"
[ -z "$out" ]; tap_check $? "task_end: si no puede escribir no dice nada ni frena (sale con 0)"
printf '{"store": "branch"}\n' >"$P/.barrilete/learning.json"
printf '{"id": "327-reviewer", "role": "reviewer", "status": "completed", "seq": 1, "created": "2026-11-16T10:00:00.000Z"}\n' >"$TMP/tarea/task.json"
BK_TASK_DIR="$TMP/tarea" tap_run out 0 python3 "$TE" <"$TMP/stop.json"
ev ref "$P" refs/heads/agents/learning
grep -qx 'task_id=327-reviewer' <<<"$out"; tap_check $? "task_end: con store branch va a agents/learning"

# --- 6. Ajustes de la review de #338 (#342) ---
# 6a. El store lo dice el learning.json del checkout principal, el mismo donde escribe el store local: un worktree con una
# copia vieja no reparte los eventos en dos stores.
printf '{"store": "local"}\n' >"$TMP/wt/.barrilete/learning.json"   # la copia vieja del worktree; el principal dice branch
rm -rf "$P/.barrilete/learning"
cd "$TMP/wt" || exit 2
tap_run out 0 python3 "$L" emit check_run rule_id=r-342-wt outcome=pass
cd "$P" || exit 2
ev ref "$P" refs/heads/agents/learning
grep -qx 'rule_id=r-342-wt' <<<"$out"; tap_check $? "342 store: desde un worktree manda el learning.json del checkout principal"
[ ! -e "$EVL" ]; tap_check $? "342 store: un learning.json viejo del worktree no abre un segundo store local"
printf '{"store": "local"}\n' >"$P/.barrilete/learning.json"
printf '{"store": "branch"}\n' >"$TMP/wt/.barrilete/learning.json"
git -C "$P" update-ref -d refs/heads/agents/learning
cd "$TMP/wt" || exit 2
tap_run out 0 python3 "$L" emit check_run rule_id=r-342-wt-local outcome=pass
cd "$P" || exit 2
[ -z "$(git -C "$P" for-each-ref refs/heads/agents/learning 2>&1)" ]; tap_check $? "342 store: con el principal en local, un worktree que dice branch no crea la rama"
ev file "$EVL"
grep -qx 'rule_id=r-342-wt-local' <<<"$out"; tap_check $? "342 store: con el principal en local, el evento del worktree va al store local"
git -C "$TMP/wt" checkout -q -- .barrilete/learning.json

# 6b. BK_HARNESS vacío cuenta como no definido (como en v0, decidido por @lautioliver en el chat de #342): manda CLAUDECODE=1.
BK_HARNESS="" CLAUDECODE=1 tap_run out 0 python3 "$L" emit check_run rule_id=r-342-vacio outcome=pass
tail -n 1 "$EVL" >"$TMP/ult.jsonl"; ev file "$TMP/ult.jsonl"
grep -qx 'harness=claude-code' <<<"$out"; tap_check $? "342 harness: BK_HARNESS vacío con CLAUDECODE=1 es claude-code"
BK_HARNESS="no válido" CLAUDECODE=1 tap_run out 0 python3 "$L" emit check_run rule_id=r-342-invalido outcome=pass
tail -n 1 "$EVL" >"$TMP/ult.jsonl"; ev file "$TMP/ult.jsonl"
grep -qx 'harness=unknown' <<<"$out"; tap_check $? "342 harness: BK_HARNESS no vacío e inválido sigue siendo unknown"

# 6c. La rama de una línea v0 es la que escribió verify.py de #323: cualquier nombre de rama que git acepta, sin espacios.
printf '%s\n' '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "fix/9-a@b+c#d"}' >"$TMP/v.jsonl"
tap_run out 0 python3 "$L" validate "$TMP/v.jsonl"
grep -q '1 legacy v0' <<<"$out"; tap_check $? "342 v0: una rama con @, + o # es una línea heredada, no rota"
printf '%s\n' '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "feat/9-año"}' >"$TMP/v.jsonl"
tap_run out 0 python3 "$L" validate "$TMP/v.jsonl"
grep -q '1 legacy v0' <<<"$out"; tap_check $? "342 v0: una rama con letras fuera de ASCII es una línea heredada"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "rama\tcon tab"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 v0: una rama con un tab sigue rota"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "a:b"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 v0: una rama con un caracter que git no acepta sigue rota"

# 6d. evidence_ref no lleva query, ni credenciales en la URL, ni query dentro del fragmento: push publica el store.
rm -rf "$P/.barrilete/learning"
tap_run out 3 python3 "$L" emit finding class=x evidence_ref='https://github.com/o/r/pull/1?token=abc'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 evidence_ref: una URL con query se rechaza"
tap_run out 3 python3 "$L" emit finding class=x evidence_ref='https://u:tok@github.com/o/r/pull/1'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 evidence_ref: una URL con usuario y clave se rechaza"
tap_run out 3 python3 "$L" emit finding class=x evidence_ref='https://github.com/o/r/pull/1#access_token=abc?x=1'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 evidence_ref: un fragmento con query se rechaza"
tap_run out 3 python3 "$L" emit finding class=x evidence_ref='https://example.com/cb#access_token=abc'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 evidence_ref: un fragmento con clave=valor se rechaza"
tap_run out 3 python3 "$L" emit finding class=x evidence_ref='https://example.com/app;jsessionid=abc/x'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 evidence_ref: un parámetro de path con clave=valor se rechaza"
tap_run out 3 python3 "$L" emit finding class=x evidence_ref='https://example.com/a/token=abc'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 evidence_ref: un = en el path, sin ; ni ?, se rechaza"
tap_run out 3 python3 "$L" emit finding class=x evidence_ref='https://example.com/x%3Ftoken%3Dabc'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 evidence_ref: una query codificada con % se rechaza"
[ ! -e "$EVL" ]; tap_check $? "342 evidence_ref: ninguno de los rechazados se escribe"
tap_run out 0 python3 "$L" emit finding class=x evidence_ref='https://github.com/o/r/pull/12#issuecomment-6963224944'
[ "$TAP_RC" -eq 0 ]; tap_check $? "342 evidence_ref: una URL con fragmento sin query sigue valiendo"
tap_run out 0 python3 "$L" emit deviation class=x evidence_ref='~/.claude/projects/p/s.jsonl'
[ "$TAP_RC" -eq 0 ]; tap_check $? "342 evidence_ref: una ruta local sigue valiendo"

# 6e. emit campo=valor solo pone los campos propios del evento; los del contexto (quién lo emite) no se pisan.
rm -rf "$P/.barrilete/learning"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass model=claude-opus-5-5
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: model no se pisa"
grep -q 'model' <<<"$out"; tap_check $? "342 emit: el rechazo nombra el campo"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass project=otro
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: project no se pisa"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass rules_ref=000000000000.000000000000
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: rules_ref no se pisa"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass harness=codex
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: harness no se pisa"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass provider=openai
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: provider no se pisa"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass task_id=1-implementer
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: task_id no se pisa"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass kind=finding
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: kind no se pisa"
tap_run out 64 python3 "$L" emit check_run rule_id=r outcome=pass v=1
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 emit: v no se pisa"
[ ! -e "$EVL" ]; tap_check $? "342 emit: un campo del contexto no escribe nada"
# Los que manda el adaptador de Claude Code (barrilete-workspace lib/learn_store.py) siguen pasando
tap_run out 0 python3 "$L" emit finding ts=2026-11-17T10:00:00Z class=stale-docs role=reviewer pr=12 area=infra evidence_ref=https://github.com/o/r/pull/12
[ "$TAP_RC" -eq 0 ]; tap_check $? "342 emit: ts, class, role, pr, area y evidence_ref se pueden poner"
tap_run out 0 python3 "$L" emit check_run rule_id=r-342 outcome=fail
[ "$TAP_RC" -eq 0 ]; tap_check $? "342 emit: rule_id y outcome se pueden poner"

# --- 7. Hallazgos del /code-review de #342 ---
# 7a. Dentro de una tarea `bk`, role y pr vienen de task.json (y rules_ref es el del rol): emit no los pisa.
printf '{"id": "342-implementer", "role": "implementer", "status": "in_progress", "pr": 7, "seq": 1, "created": "2026-11-17T10:00:00.000Z"}\n' >"$TMP/tarea/task.json"
rm -rf "$P/.barrilete/learning"
BK_TASK_DIR="$TMP/tarea" tap_run out 64 python3 "$L" emit finding class=x role=reviewer
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 review: en una tarea bk, emit no pisa el role de task.json"
BK_TASK_DIR="$TMP/tarea" tap_run out 64 python3 "$L" emit finding class=x pr=99
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 review: en una tarea bk, emit no pisa el pr de task.json"
[ ! -e "$EVL" ]; tap_check $? "342 review: en una tarea bk, un role o pr pisado no escribe nada"
# 7b. Un campo que emit no acepta sale siempre con 64, sea del contexto o no esté en la tabla.
tap_run out 64 python3 "$L" emit finding class=x nota=texto
[ "$TAP_RC" -eq 64 ]; tap_check $? "342 review: un campo fuera de la tabla en emit sale con 64, como uno del contexto"
# 7c. evento() desde Python tampoco deja pisar el contexto (verify.py y task_events.py lo llaman directo).
cat >"$TMP/pisar.py" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import learning
for campos in ({"model": "x"}, {"project": "otro"}, {"rules_ref": "000000000000.000000000000"}, {"nota": "t"}):
    try:
        learning.evento("finding", campos, ctx={"v": 1, "project": "p", "model": "m", "harness": "h"})
        print("pisado", sorted(campos))
    except learning.LearningError:
        print("rechazado", sorted(campos))
EOF
tap_run out 0 python3 "$TMP/pisar.py" "$P/scripts/agents"
grep -q '^pisado' <<<"$out"; [ $? -eq 1 ]; tap_check $? "342 review: evento() rechaza un campo del contexto o fuera de la tabla"
grep -q "^rechazado \['model'\]" <<<"$out"; tap_check $? "342 review: evento() rechaza model"
grep -q "^rechazado \['nota'\]" <<<"$out"; tap_check $? "342 review: evento() rechaza un campo fuera de la tabla"
# 7d. La rama v0 son los caracteres de un nombre de rama, no cualquier texto sin espacios.
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "password=hunter2"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 review: una rama v0 con = se rechaza"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "\"<script>\""}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 review: una rama v0 con comillas o <> se rechaza"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "a..b"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 review: una rama v0 con .. se rechaza"
valida '{"v": 0, "ts": "2026-11-16T03:21:14Z", "kind": "check_run", "check": "pr-metadata", "rule_id": "r", "outcome": "pass", "branch": "a​b"}'
[ "$TAP_RC" -eq 3 ]; tap_check $? "342 review: una rama v0 con un caracter invisible se rechaza"

tap_done
