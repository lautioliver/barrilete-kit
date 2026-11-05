#!/usr/bin/env bash
# Un worktree tiene un solo dueño vivo (#267). El candado vive en el directorio git del worktree
# (<gitdir>/agent-lock), no en el árbol de trabajo: nunca entra a git status ni a un commit.
# Uso: worktree-lock.sh claim <worktree>    toma el candado: imprime "claimed" o "held: <agente> (pid N, desde T)"
#      worktree-lock.sh status <worktree>   imprime "free", "stale" (dueño muerto) o "held: …"
# Sale con 0 en esos casos (lo que pasó va en la salida; prepare.sh decide); 64 si el uso es inválido.
# Entorno: WORKTREE_LOCK_PID (pid del dueño; por defecto el claude más cercano entre los ancestros, o $PPID),
#          WORKTREE_LOCK_AGENT (nombre; por defecto el de BK_TASK_DIR, o "agent").
set -uo pipefail
if [ $# -ne 2 ] || { [ "$1" != claim ] && [ "$1" != status ]; }; then echo "Usage: $0 claim|status <worktree>" >&2; exit 64; fi
cmd=$1; wt=$2
gdir=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || { echo "$0: $wt is not a git worktree" >&2; exit 64; }
lock="$gdir/agent-lock"

inicio() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }

# Pid del agente que corre esto: el claude más cercano entre los ancestros (prepare.sh lo corre un shell hijo suyo).
dueno() {
  [ -n "${WORKTREE_LOCK_PID:-}" ] && { echo "$WORKTREE_LOCK_PID"; return; }
  local p=$PPID n=0 c
  while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$n" -lt 12 ]; do
    c=$(ps -o comm= -p "$p" 2>/dev/null)
    case "${c##*/}" in claude*) echo "$p"; return ;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); n=$((n + 1))
  done
  echo "$PPID"
}
campo() { sed -n "s/^$1=//p" "$lock" | head -1; }

# Deja en E: free | stale | held, y el dueño del candado en l_pid, l_start, l_agent y l_since.
l_pid=""; l_start=""; l_agent=""; l_since=""; E=free
estado() {
  [ -f "$lock" ] || { E=free; return; }
  l_pid=$(campo pid); l_start=$(campo start); l_agent=$(campo agent); l_since=$(campo since)
  case "$l_pid" in ''|*[!0-9]*) E=stale; return ;; esac
  kill -0 "$l_pid" 2>/dev/null || { E=stale; return; }
  # El pid puede haberlo reutilizado otro proceso: la hora de inicio tiene que ser la misma.
  [ "$(inicio "$l_pid")" = "$l_start" ] || { E=stale; return; }
  E=held
}

estado; e=$E
mio=$(dueno)
if [ "$e" = held ] && [ "$l_pid" != "$mio" ]; then
  echo "held: ${l_agent:-agent} (pid $l_pid, since ${l_since:-?}); another agent is working in $wt. Use your own worktree (prepare.sh <n> --worktree) and do not share it."
  exit 0
fi
if [ "$cmd" = status ]; then
  [ "$e" = held ] && echo "held: ${l_agent:-agent} (pid $l_pid, since ${l_since:-?})" || echo "$e"
  exit 0
fi
agente=${WORKTREE_LOCK_AGENT:-}
[ -z "$agente" ] && [ -n "${BK_TASK_DIR:-}" ] && agente=$(basename "$BK_TASK_DIR")
printf 'pid=%s\nstart=%s\nagent=%s\nsince=%s\n' "$mio" "$(inicio "$mio")" "${agente:-agent}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$lock"
echo claimed
