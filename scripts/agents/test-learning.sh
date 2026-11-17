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
unset BK_TASK_DIR BK_HARNESS BK_MODEL BK_PROVIDER CLAUDECODE CLAUDE_PROJECT_DIR   # cada caso pone los suyos
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
tap_run out 3 python3 "$L" emit check_run rule_id="con espacios" outcome=pass
[ "$TAP_RC" -eq 3 ]; tap_check $? "emit: un evento inválido sale con 3"
ev file "$EVL"
grep -qx 'n=2' <<<"$out"; tap_check $? "emit: un evento inválido no se escribe"
git -C "$P" worktree add -q "$TMP/wt" -b claude/9-wt 2>/dev/null
cd "$TMP/wt" || exit 2
tap_run out 0 python3 "$L" emit check_run rule_id=r-wt outcome=pass
cd "$P" || exit 2
ev file "$EVL"
grep -qx 'n=3' <<<"$out"; tap_check $? "store local: desde un worktree el evento va al checkout principal"
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

tap_done
