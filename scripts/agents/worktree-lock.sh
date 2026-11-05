#!/usr/bin/env bash
# Un worktree tiene un solo dueño vivo (#267). El candado vive en el directorio git del worktree
# (<gitdir>/agent-lock), no en el árbol de trabajo: nunca entra a git status ni a un commit.
# Uso: worktree-lock.sh claim <worktree>    toma el candado: imprime "claimed" o "held: <agente> (pid N, since T)…"
#      worktree-lock.sh status <worktree>   imprime "free", "stale" (dueño muerto) o "held: …"
#      worktree-lock.sh release <worktree>  el dueño lo suelta: "released", "free" o "held: …" si es de otro
# Sale con 0 en esos casos (lo que pasó va en la salida; prepare.sh decide); 64 si el uso es inválido.
# El dueño es el par (pid, agente): los subagentes de un mismo proceso claude comparten el pid, así que cada uno
# fija su nombre en WORKTREE_LOCK_AGENT. Sin nombre: el de BK_TASK_DIR, o "agent".
# Entorno: WORKTREE_LOCK_PID (pid del dueño; por defecto el claude más cercano entre los ancestros, si no el
#          ancestro más cercano que no sea un shell, si no $PPID), WORKTREE_LOCK_AGENT.
set -uo pipefail
if [ $# -ne 2 ] || { [ "$1" != claim ] && [ "$1" != status ] && [ "$1" != release ]; }; then
  echo "Usage: $0 claim|status|release <worktree>" >&2; exit 64
fi
cmd=$1; wt=$2
gdir=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || { echo "$0: $wt is not a git worktree" >&2; exit 64; }
lock="$gdir/agent-lock"

inicio() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }

# Pid del agente que corre esto: el claude más cercano entre los ancestros (prepare.sh lo corre un shell hijo suyo);
# sin claude (otro agente: node, codex…), el ancestro más cercano que no es un shell; al final, $PPID.
dueno() {
  [ -n "${WORKTREE_LOCK_PID:-}" ] && { echo "$WORKTREE_LOCK_PID"; return; }
  local p=$PPID n=0 c b libre=""
  while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$n" -lt 12 ]; do
    c=$(ps -o comm= -p "$p" 2>/dev/null); b=${c##*/}; b=${b#-}
    case "$b" in
      claude*) echo "$p"; return ;;
      bash|sh|zsh|dash|ksh|fish|env|sleep|prepare.sh|worktree-lock.sh) ;;
      *) [ -z "$libre" ] && libre=$p ;;
    esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); n=$((n + 1))
  done
  echo "${libre:-$PPID}"
}
campo() { sed -n "s/^$1=//p" "$lock" | head -1; }

# Deja en E: free | stale | held, y el dueño del candado en l_pid, l_start, l_agent y l_since.
l_pid=""; l_start=""; l_agent=""; l_since=""; E=free
estado() {
  l_pid=""; l_start=""; l_agent=""; l_since=""
  [ -f "$lock" ] || { E=free; return; }
  l_pid=$(campo pid); l_start=$(campo start); l_agent=$(campo agent); l_since=$(campo since)
  case "$l_pid" in ''|*[!0-9]*) E=stale; return ;; esac
  kill -0 "$l_pid" 2>/dev/null || { E=stale; return; }
  # El pid puede haberlo reutilizado otro proceso: la hora de inicio tiene que ser la misma.
  [ "$(inicio "$l_pid")" = "$l_start" ] || { E=stale; return; }
  E=held
}

agente=${WORKTREE_LOCK_AGENT:-}
if [ -z "$agente" ] && [ -n "${BK_TASK_DIR:-}" ]; then agente=$(basename "$BK_TASK_DIR"); fi
agente=${agente:-agent}
mio=$(dueno)

estado
ajeno=""
if [ "$E" = held ] && { [ "$l_pid" != "$mio" ] || [ "$l_agent" != "$agente" ]; }; then ajeno=1; fi
if [ -n "$ajeno" ]; then
  echo "held: ${l_agent:-agent} (pid $l_pid, since ${l_since:-?}); another agent is working in $wt. Use your own worktree (prepare.sh <n> --worktree) and do not share it."
  exit 0
fi

case "$cmd" in
  status)
    if [ "$E" = held ]; then echo "held: ${l_agent:-agent} (pid $l_pid, since ${l_since:-?})"; else echo "$E"; fi
    ;;
  release)
    if [ "$E" = held ]; then rm -f "$lock"; echo released; else echo "$E"; fi
    ;;
  claim)
    # Se escribe completo en un temporal y se toma con ln, que falla si el candado ya existe: dos agentes que llegan
    # a la vez no pueden ganar los dos, y nadie ve un candado a medio escribir.
    tmp=$(mktemp "$gdir/agent-lock.XXXXXX") || { echo "$0: could not write in $gdir" >&2; exit 64; }
    printf 'pid=%s\nstart=%s\nagent=%s\nsince=%s\n' "$mio" "$(inicio "$mio")" "$agente" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$tmp"
    if [ "$E" = held ]; then mv -f "$tmp" "$lock"; echo claimed; exit 0; fi   # el mismo dueño la renueva
    [ "$E" = stale ] && rm -f "$lock"
    if ln "$tmp" "$lock" 2>/dev/null; then
      rm -f "$tmp"; echo claimed
    else
      rm -f "$tmp"; estado
      echo "held: ${l_agent:-agent} (pid ${l_pid:-?}, since ${l_since:-?}); another agent is working in $wt. Use your own worktree (prepare.sh <n> --worktree) and do not share it."
    fi
    ;;
esac
