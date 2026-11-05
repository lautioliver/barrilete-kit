#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2319  # out lo asigna tap_run; el $? de una aserción es el de la aserción
# Tests de scripts/agents/worktree-lock.sh (#267): un worktree tiene un solo dueño vivo.
# El candado vive en el directorio git del worktree (no en el árbol de trabajo), así que nunca se commitea.
# Uso: bash scripts/agents/test-worktree-lock.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
LOCK="$RAIZ/scripts/agents/worktree-lock.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-worktree-lock-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "kill \$VIVO 2>/dev/null; rm -rf \"\$TMP\""
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

git init -q -b main "$TMP/proj" && git -C "$TMP/proj" commit -q --allow-empty -m base
git -C "$TMP/proj" worktree add -q -b rama "$TMP/wt" 2>/dev/null
GDIR=$(git -C "$TMP/wt" rev-parse --absolute-git-dir)

# Un proceso vivo que hace de "otro agente" y un pid que ya no existe.
sleep 300 &
VIVO=$!
sleep 0 &
MUERTO=$!
wait "$MUERTO"
export WORKTREE_LOCK_AGENT=agente-a
out=""
# Contenido del candado en $LK ("" si no existe): sin leer un archivo que falta, que sería un crash y no un caso fallido.
leer() { LK=""; if [ -f "$GDIR/agent-lock" ]; then LK=$(cat "$GDIR/agent-lock"); fi; }

# 1. Sin candado: lo toma y lo escribe en el directorio git, no en el árbol de trabajo.
export WORKTREE_LOCK_PID=$VIVO
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx "claimed" <<<"$out"; tap_check $? "sin candado: claim dice claimed"
[ -f "$GDIR/agent-lock" ]; tap_check $? "sin candado: el candado queda en el directorio git del worktree"
n=$(git -C "$TMP/wt" status --porcelain | wc -l | tr -d ' ')
[ "$n" = 0 ]; tap_check $? "sin candado: el candado no aparece en git status (no se commitea)"
leer; grep -qx "pid=$VIVO" <<<"$LK"; tap_check $? "sin candado: el candado guarda el pid del dueño"
leer; grep -qx 'agent=agente-a' <<<"$LK"; tap_check $? "sin candado: el candado guarda el nombre del agente"

# 2. El mismo dueño vuelve a tomarlo (retoma su propio worktree).
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx "claimed" <<<"$out"; tap_check $? "mismo dueño: claim dice claimed"

# 3. Otro agente vivo lo tiene: avisa quién y no lo pisa.
export WORKTREE_LOCK_PID=$$ WORKTREE_LOCK_AGENT=agente-b
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -q '^held: agente-a' <<<"$out"; tap_check $? "dueño vivo: claim dice held y quién lo tiene"
grep -q "pid $VIVO" <<<"$out"; tap_check $? "dueño vivo: el mensaje incluye el pid del dueño"
leer; grep -qx "pid=$VIVO" <<<"$LK"; tap_check $? "dueño vivo: el candado no se pisa"
tap_run out 0 "$LOCK" status "$TMP/wt"
grep -q '^held: agente-a' <<<"$out"; tap_check $? "dueño vivo: status dice held"

# 4. Dueño muerto: el candado se ignora y se reemplaza.
cat >"$GDIR/agent-lock" <<LK
pid=$MUERTO
start=Thu Jan  1 00:00:00 1970
agent=agente-viejo
since=2026-01-01T00:00:00Z
LK
tap_run out 0 "$LOCK" status "$TMP/wt"
grep -qx "stale" <<<"$out"; tap_check $? "dueño muerto: status dice stale"
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx "claimed" <<<"$out"; tap_check $? "dueño muerto: claim lo reemplaza"
leer; grep -qx 'agent=agente-b' <<<"$LK"; tap_check $? "dueño muerto: el candado nuevo es del agente nuevo"

# 5. El pid está vivo pero es otro proceso (el sistema lo reutilizó): hora de inicio distinta, candado viejo.
cat >"$GDIR/agent-lock" <<LK
pid=$VIVO
start=Thu Jan  1 00:00:00 1970
agent=agente-viejo
since=2026-01-01T00:00:00Z
LK
tap_run out 0 "$LOCK" status "$TMP/wt"
grep -qx "stale" <<<"$out"; tap_check $? "pid reutilizado: status dice stale"

# 6. Sin candado, status dice free.
rm -f "$GDIR/agent-lock"
tap_run out 0 "$LOCK" status "$TMP/wt"
grep -qx "free" <<<"$out"; tap_check $? "sin candado: status dice free"

# 6b. La identidad es pid + nombre de agente: los subagentes de un mismo proceso claude comparten el pid.
rm -f "$GDIR/agent-lock"
export WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=agente-a
tap_run out 0 "$LOCK" claim "$TMP/wt"
export WORKTREE_LOCK_AGENT=agente-b
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -q '^held: agente-a' <<<"$out"; tap_check $? "mismo pid y otro nombre de agente: claim dice held"
leer; grep -qx 'agent=agente-a' <<<"$LK"; tap_check $? "mismo pid y otro nombre de agente: el candado no se pisa"
export WORKTREE_LOCK_AGENT=agente-a
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx "claimed" <<<"$out"; tap_check $? "mismo pid y mismo nombre: claim dice claimed"

# 6c. release: solo el dueño suelta el candado.
export WORKTREE_LOCK_AGENT=agente-b
tap_run out 0 "$LOCK" release "$TMP/wt"
grep -q '^held: agente-a' <<<"$out"; tap_check $? "release de otro agente: dice held"
leer; grep -qx 'agent=agente-a' <<<"$LK"; tap_check $? "release de otro agente: no suelta el candado"
export WORKTREE_LOCK_AGENT=agente-a
tap_run out 0 "$LOCK" release "$TMP/wt"
grep -qx "released" <<<"$out"; tap_check $? "release del dueño: dice released"
tap_run out 0 "$LOCK" status "$TMP/wt"
grep -qx "free" <<<"$out"; tap_check $? "release del dueño: el worktree queda free"
tap_run out 0 "$LOCK" release "$TMP/wt"
grep -qx "free" <<<"$out"; tap_check $? "release sin candado: dice free"

# 6d. Sin WORKTREE_LOCK_PID, el dueño es el ancestro claude más cercano (un bash que se llama claude).
unset WORKTREE_LOCK_PID
rm -f "$GDIR/agent-lock"
mkdir -p "$TMP/bin"
ln -s "$(command -v bash)" "$TMP/bin/claude"
cat >"$TMP/ancestro.sh" <<AN
echo \$\$ >"$TMP/ancestro.pid"
"$LOCK" claim "$TMP/wt" >/dev/null
AN
tap_run out 0 "$TMP/bin/claude" "$TMP/ancestro.sh"
leer; grep -qx "pid=$(cat "$TMP/ancestro.pid")" <<<"$LK"; tap_check $? "sin WORKTREE_LOCK_PID: el dueño es el ancestro claude"

# 7. Las docs dicen que el reviewer hace implementar en un worktree propio y qué hace el candado. Se busca por contenido
# (un proyecto instalado en español tiene el texto en español en el archivo sin .es y no tiene los .es.md).
mencion() { # mencion <archivo> <texto en inglés> <texto en español>
  local f="$RAIZ/$1"
  if [ ! -f "$f" ]; then return 1; fi
  if grep -qF -- "$2" "$f"; then return 0; fi
  grep -qF -- "$3" "$f"
}
mencion docs/agents/subagent-contract.md agent-lock agent-lock; tap_check $? "contrato: nombra el candado agent-lock"
mencion docs/agents/subagent-contract.md "own worktree" "worktree propio"; tap_check $? "contrato: el implementer de un reviewer usa su worktree propio"
mencion .claude/agents/reviewer.md "own worktree" "worktree propio"; tap_check $? "reviewer: hace implementar en un worktree propio"
mencion .claude/skills/review-pr/SKILL.md "own worktree" "worktree propio"; tap_check $? "review-pr: el implementer del reviewer usa un worktree propio"
mencion docs/agents/subagent-contract.md WORKTREE_LOCK_AGENT WORKTREE_LOCK_AGENT; tap_check $? "contrato: pide fijar WORKTREE_LOCK_AGENT a cada subagente"

# Los hermanos en español existen solo en un proyecto instalado en inglés.
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "agent-lock" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): nombra el candado agent-lock"; else tap_skip "contrato (es): nombra el candado agent-lock" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "worktree propio" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): el implementer de un reviewer usa su worktree propio"; else tap_skip "contrato (es): el implementer de un reviewer usa su worktree propio" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/i18n/agents/reviewer.es.md" ]; then grep -qF -- "worktree propio" "$RAIZ/.claude/i18n/agents/reviewer.es.md"; tap_check $? "reviewer (es): hace implementar en un worktree propio"; else tap_skip "reviewer (es): hace implementar en un worktree propio" "no existe .claude/i18n/agents/reviewer.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/skills/review-pr/SKILL.es.md" ]; then grep -qF -- "worktree propio" "$RAIZ/.claude/skills/review-pr/SKILL.es.md"; tap_check $? "review-pr (es): el implementer del reviewer usa un worktree propio"; else tap_skip "review-pr (es): el implementer del reviewer usa un worktree propio" "no existe .claude/skills/review-pr/SKILL.es.md en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "WORKTREE_LOCK_AGENT" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): pide fijar WORKTREE_LOCK_AGENT a cada subagente"; else tap_skip "contrato (es): pide fijar WORKTREE_LOCK_AGENT a cada subagente" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi

tap_done
