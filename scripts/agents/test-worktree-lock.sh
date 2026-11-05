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

# 7. Las docs dicen que el reviewer puede implementar con worktree propio y qué hace el candado.
mencion() { # mencion <archivo> <texto>
  [ -f "$RAIZ/$1" ] && grep -qF -- "$2" "$RAIZ/$1"
}
mencion docs/agents/subagent-contract.md agent-lock; tap_check $? "contrato (en): nombra el candado agent-lock"
mencion docs/agents/subagent-contract.es.md agent-lock; tap_check $? "contrato (es): nombra el candado agent-lock"
mencion docs/agents/subagent-contract.md "own worktree"; tap_check $? "contrato (en): el implementer de un reviewer usa su own worktree"
mencion docs/agents/subagent-contract.es.md "worktree propio"; tap_check $? "contrato (es): el implementer de un reviewer usa su worktree propio"
mencion .claude/agents/reviewer.md "own worktree"; tap_check $? "reviewer (en): lanza el implementer en su own worktree"
mencion .claude/i18n/agents/reviewer.es.md "worktree propio"; tap_check $? "reviewer (es): lanza el implementer en su worktree propio"
mencion .claude/skills/review-pr/SKILL.md "own worktree"; tap_check $? "review-pr (en): el implementer del reviewer usa su own worktree"
mencion .claude/skills/review-pr/SKILL.es.md "worktree propio"; tap_check $? "review-pr (es): el implementer del reviewer usa su worktree propio"

tap_done
