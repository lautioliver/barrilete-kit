#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2319,SC2181  # out lo asigna tap_run; el $ de los JSON es texto
# Tests del evento `deviation` que guardrails.py deja en el store del proyecto cuando frena un comando (#325, ADR-007 D3):
# lo que escribe con la entrada de cada harness (Claude Code, Codex, Copilot, Cursor) y que nunca cambia su salida.
# Corre el comando de cada hook tal cual está registrado (.claude/settings.json, .codex/hooks.json, .cursor/hooks.json,
# .github/hooks/guardrails.json). pi lo cubre packages/pi/test/extensions.test.ts.
# Uso: bash scripts/agents/test-guardrails-learning.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-guardrails-learning-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
export PYTHONDONTWRITEBYTECODE=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset BK_TASK_DIR BK_HARNESS BK_MODEL BK_PROVIDER BARRILETE_MODEL BARRILETE_PROVIDER BARRILETE_HARNESS CLAUDECODE CLAUDE_PROJECT_DIR
out=""

P="$TMP/proyecto"
mkdir -p "$P/scripts" "$P/.codex" "$P/.cursor" "$P/.github/hooks" "$P/.claude" "$P/.barrilete"
cp -R "$RAIZ/scripts/agents" "$P/scripts/"
rm -rf "$P/scripts/agents/__pycache__"
cp "$RAIZ/.codex/hooks.json" "$P/.codex/"
cp "$RAIZ/.cursor/hooks.json" "$P/.cursor/"
cp "$RAIZ/.github/hooks/guardrails.json" "$P/.github/hooks/"
cp "$RAIZ/.claude/settings.json" "$P/.claude/"
git init -q -b claude/9-algo "$P"
git -C "$P" add -A && git -C "$P" commit -qm base
EVL="$P/.barrilete/learning/events.jsonl"

# Corre el comando del hook (hooks-file, ruta de claves) con la entrada que ese harness manda. Deja stdout, stderr y el
# estado en $TMP/h.out, h.err, h.rc. Termina siempre con 0: el estado se compara con los archivos.
cat >"$TMP/hook.py" <<'PY'
import json, os, subprocess, sys
archivo, *ruta = sys.argv[1:-1]
entrada = sys.argv[-1]
cmd = json.load(open(archivo))
for k in ruta:
    cmd = cmd[int(k)] if k.isdigit() else cmd[k]
env = {k: v for k, v in os.environ.items() if k not in ("BK_HARNESS", "CLAUDECODE")}
if os.environ.get("HOOK_CLAUDECODE"):
    env["CLAUDECODE"] = "1"
r = subprocess.run(["sh", "-c", cmd], input=entrada, text=True, capture_output=True, env=env, cwd=os.environ["HOOK_CWD"])
tmp = os.environ["HOOK_TMP"]
open(tmp + "/h.out", "w").write(r.stdout)
open(tmp + "/h.err", "w").write(r.stderr)
open(tmp + "/h.rc", "w").write(str(r.returncode))
PY
export HOOK_TMP="$TMP" HOOK_CWD="$P"
CMD='git push origin main'
hook() { rm -f "$EVL"; tap_run out 0 python3 "$TMP/hook.py" "$@"; }
campo() { python3 -c 'import json,sys
import os
l=[json.loads(x) for x in open(sys.argv[1]) if x.strip()] if os.path.exists(sys.argv[1]) else []
print(len(l), *(l[-1].get(sys.argv[2], "-") if l else ["-"],))' "$EVL" "$1"; }
IN_CLAUDE="{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"$CMD\"}, \"cwd\": \"$P\"}"
IN_COPILOT="{\"toolName\": \"bash\", \"toolArgs\": \"{\\\"command\\\": \\\"$CMD\\\"}\", \"cwd\": \"$P\"}"
IN_CURSOR="{\"hook_event_name\": \"beforeShellExecution\", \"command\": \"$CMD\", \"cwd\": \"$P\"}"

# --- Claude Code ---
HOOK_CLAUDECODE=1 hook "$P/.claude/settings.json" hooks PreToolUse 0 hooks 0 command "$IN_CLAUDE"
[ "$(cat "$TMP/h.rc")" = 2 ]; tap_check $? "claude-code: frena con 2"
[ "$(campo kind)" = "1 deviation" ]; tap_check $? "claude-code: un evento deviation"
[ "$(campo harness)" = "1 claude-code" ]; tap_check $? "claude-code: harness claude-code"
[ "$(campo class)" = "1 guardrail-block" ]; tap_check $? "claude-code: class guardrail-block"
[ "$(campo model)" = "1 unknown" ]; tap_check $? "claude-code: model unknown sin BK_MODEL"
tap_run out 0 python3 "$P/scripts/agents/learning.py" validate "$EVL"
[ "$TAP_RC" = 0 ]; tap_check $? "claude-code: el evento pasa el validador"

# --- Codex, Copilot y Cursor: el hook registrado pone su harness ---
hook "$P/.codex/hooks.json" hooks PreToolUse 0 hooks 0 command "$IN_CLAUDE"
[ "$(cat "$TMP/h.rc")" = 2 ]; tap_check $? "codex: frena con 2"
[ "$(campo harness)" = "1 codex" ]; tap_check $? "codex: harness codex"
[ "$(campo kind)" = "1 deviation" ]; tap_check $? "codex: un evento deviation"
tap_run out 0 python3 "$P/scripts/agents/learning.py" validate "$EVL"
[ "$TAP_RC" = 0 ]; tap_check $? "codex: el evento pasa el validador"

hook "$P/.github/hooks/guardrails.json" hooks preToolUse 0 bash "$IN_COPILOT"
[ "$(campo harness)" = "1 copilot" ]; tap_check $? "copilot: harness copilot"
[ "$(campo kind)" = "1 deviation" ]; tap_check $? "copilot: un evento deviation"
tap_run out 0 python3 "$P/scripts/agents/learning.py" validate "$EVL"
[ "$TAP_RC" = 0 ]; tap_check $? "copilot: el evento pasa el validador"

hook "$P/.cursor/hooks.json" hooks beforeShellExecution 0 command "$IN_CURSOR"
[ "$(cat "$TMP/h.rc")" = 0 ]; tap_check $? "cursor: sigue saliendo con 0"
[ "$(campo harness)" = "1 cursor" ]; tap_check $? "cursor: harness cursor"
[ "$(campo kind)" = "1 deviation" ]; tap_check $? "cursor: un evento deviation"
tap_run out 0 python3 "$P/scripts/agents/learning.py" validate "$EVL"
[ "$TAP_RC" = 0 ]; tap_check $? "cursor: el evento pasa el validador"

# --- model y harness del entorno mandan (bk los exporta) ---
BK_MODEL=openai/gpt-4o BK_HARNESS=codex hook "$P/.codex/hooks.json" hooks PreToolUse 0 hooks 0 command "$IN_CLAUDE"
[ "$(campo model)" = "1 openai/gpt-4o" ]; tap_check $? "BK_MODEL llega al evento"

# --- no deja evento si no frena ---
IN_OK="{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"git status\"}, \"cwd\": \"$P\"}"
hook "$P/.codex/hooks.json" hooks PreToolUse 0 hooks 0 command "$IN_OK"
[ ! -e "$EVL" ]; tap_check $? "un comando permitido no deja evento"

# --- no cambia lo que ve el agente: igual con el store roto y con el store bueno ---
hook "$P/.codex/hooks.json" hooks PreToolUse 0 hooks 0 command "$IN_CLAUDE"
cp "$TMP/h.err" "$TMP/bueno.err"; cp "$TMP/h.rc" "$TMP/bueno.rc"
printf '{"store": "nube"}\n' >"$P/.barrilete/learning.json"
hook "$P/.codex/hooks.json" hooks PreToolUse 0 hooks 0 command "$IN_CLAUDE"
[ "$(cat "$TMP/h.rc")" = 2 ]; tap_check $? "con el store roto sigue frenando con 2"
diff -q "$TMP/bueno.err" "$TMP/h.err" >/dev/null; tap_check $? "con el store roto el motivo es el mismo"
[ -s "$TMP/bueno.err" ]; tap_check $? "el motivo no está vacío"
rm -f "$P/.barrilete/learning.json"

tap_done
