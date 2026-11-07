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

# 6e. Toma de un candado stale (#267, review del PR #268): dos agentes que lo ven stale no pueden quedar los dos con claimed.
# Un date falso (el claim lo llama después de ver el estado y antes de reemplazar) deja que el agente B tome el candado
# justo en ese hueco; A, que ya lo vio stale, no tiene que borrarle el candado recién tomado a B.
unset WORKTREE_LOCK_PID
cat >"$GDIR/agent-lock" <<LK
pid=$MUERTO
start=Thu Jan  1 00:00:00 1970
agent=agente-viejo
since=2026-01-01T00:00:00Z
LK
mkdir -p "$TMP/fake"
ORIG_PATH=$PATH
cat >"$TMP/fake/date" <<FD
#!/usr/bin/env bash
if [ ! -f "$TMP/fake/ya" ]; then
  : >"$TMP/fake/ya"
  PATH="$ORIG_PATH" WORKTREE_LOCK_PID=$$ WORKTREE_LOCK_AGENT=agente-b "$LOCK" claim "$TMP/wt" >"$TMP/fake/b.out"
fi
PATH="$ORIG_PATH" exec date "\$@"
FD
chmod +x "$TMP/fake/date"
PATH="$TMP/fake:$ORIG_PATH" WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=agente-a "$LOCK" claim "$TMP/wt" >"$TMP/fake/a.out"
grep -qx claimed "$TMP/fake/b.out"; tap_check $? "candado stale: el agente que llega en el hueco toma el candado (claimed)"
grep -q '^held: agente-b' "$TMP/fake/a.out"; tap_check $? "candado stale: el agente que lo vio stale no pisa al que ya lo tomó (held)"
leer; grep -qx 'agent=agente-b' <<<"$LK"; tap_check $? "candado stale: el candado queda del agente que lo tomó primero"

# 6f. Un claim que muere antes de ln/mv no deja agent-lock.XXXXXX en el directorio git.
rm -f "$GDIR/agent-lock"
# Este date falso le manda TERM al claim (el proceso que lo llamó, o su padre si es el subshell de $(…)) y sigue.
cat >"$TMP/fake/date" <<FD
#!/usr/bin/env bash
for p in \$PPID \$(ps -o ppid= -p \$PPID); do
  case \$(ps -o args= -p \$p) in *" claim "*) kill -TERM \$p ;; esac
done
sleep 1
PATH="$ORIG_PATH" exec date "\$@"
FD
tap_run out 143 env PATH="$TMP/fake:$ORIG_PATH" WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=agente-a "$LOCK" claim "$TMP/wt"
sobras=$(find "$GDIR" -maxdepth 1 -name 'agent-lock.*' | wc -l | tr -d ' ')
[ "$sobras" = 0 ]; tap_check $? "claim interrumpido: no deja agent-lock.XXXXXX en el directorio git"
rm -f "$GDIR"/agent-lock.* "$GDIR/agent-lock"

# 6g. /orchestrate: prepare.sh toma el candado como (pid del orquestador, su nombre) y los subagentes comparten ese pid:
# el orquestador lo suelta antes de lanzar, y entonces el subagente (otro nombre, mismo pid) puede tomarlo.
export WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=orquestador
tap_run out 0 "$LOCK" claim "$TMP/wt"
tap_run out 0 "$LOCK" release "$TMP/wt"
export WORKTREE_LOCK_AGENT=implementer-267
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx claimed <<<"$out"; tap_check $? "orquestador: soltado el candado, el subagente (mismo pid) lo toma"
rm -f "$GDIR/agent-lock"

# 7. Las docs dicen que el reviewer hace implementar en un worktree propio y qué hace el candado. Se busca por contenido
# (un proyecto instalado en español tiene el texto en español en el archivo sin .es y no tiene los .es.md).
# Si falta el archivo, el caso falla (el último comando es la aserción [ -f ]): no es un crash ni un return 1.
mencion() { # mencion <archivo> <texto en inglés> <texto en español>
  local f="$RAIZ/$1"
  if [ ! -f "$f" ]; then
    [ -f "$f" ]
  elif grep -qF -- "$2" "$f"; then
    :
  else
    grep -qF -- "$3" "$f"
  fi
}
# Un proyecto chico (mode: small) no tiene agentes: el init no instala el contrato, el reviewer ni review-pr.
CHICO=0
if [ -f "$RAIZ/.agent-kit.json" ] && grep -q '"mode": *"small"' "$RAIZ/.agent-kit.json"; then CHICO=1; fi
SIN="proyecto chico (mode: small): no tiene el contrato de subagentes, el reviewer ni review-pr"
if [ "$CHICO" = 1 ]; then tap_skip "contrato: nombra el candado agent-lock" "$SIN"; else mencion docs/agents/subagent-contract.md agent-lock agent-lock; tap_check $? "contrato: nombra el candado agent-lock"; fi
if [ "$CHICO" = 1 ]; then tap_skip "contrato: el implementer de un reviewer usa su worktree propio" "$SIN"; else mencion docs/agents/subagent-contract.md "own worktree" "worktree propio"; tap_check $? "contrato: el implementer de un reviewer usa su worktree propio"; fi
if [ "$CHICO" = 1 ]; then tap_skip "reviewer: hace implementar en un worktree propio" "$SIN"; else mencion .claude/agents/reviewer.md "own worktree" "worktree propio"; tap_check $? "reviewer: hace implementar en un worktree propio"; fi
if [ "$CHICO" = 1 ]; then tap_skip "review-pr: el implementer del reviewer usa un worktree propio" "$SIN"; else mencion .claude/skills/review-pr/SKILL.md "own worktree" "worktree propio"; tap_check $? "review-pr: el implementer del reviewer usa un worktree propio"; fi
if [ "$CHICO" = 1 ]; then tap_skip "contrato: pide fijar WORKTREE_LOCK_AGENT a cada subagente" "$SIN"; else mencion docs/agents/subagent-contract.md WORKTREE_LOCK_AGENT WORKTREE_LOCK_AGENT; tap_check $? "contrato: pide fijar WORKTREE_LOCK_AGENT a cada subagente"; fi

if [ "$CHICO" = 1 ]; then tap_skip "orchestrate: suelta el candado antes de lanzar al subagente" "$SIN"; else mencion .claude/skills/orchestrate/SKILL.md "worktree-lock.sh release" "worktree-lock.sh release"; tap_check $? "orchestrate: suelta el candado antes de lanzar al subagente"; fi
if [ "$CHICO" = 1 ]; then tap_skip "orchestrate: pasa WORKTREE_LOCK_AGENT a prepare.sh" "$SIN"; else mencion .claude/skills/orchestrate/SKILL.md WORKTREE_LOCK_AGENT WORKTREE_LOCK_AGENT; tap_check $? "orchestrate: pasa WORKTREE_LOCK_AGENT a prepare.sh"; fi
if [ "$CHICO" = 1 ]; then tap_skip "contrato: el orquestador suelta el candado de prepare.sh" "$SIN"; else mencion docs/agents/subagent-contract.md "orchestrator releases" "orquestador suelta"; tap_check $? "contrato: el orquestador suelta el candado de prepare.sh"; fi

# Los hermanos en español existen solo en un proyecto instalado en inglés.
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "agent-lock" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): nombra el candado agent-lock"; else tap_skip "contrato (es): nombra el candado agent-lock" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "worktree propio" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): el implementer de un reviewer usa su worktree propio"; else tap_skip "contrato (es): el implementer de un reviewer usa su worktree propio" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/i18n/agents/reviewer.es.md" ]; then grep -qF -- "worktree propio" "$RAIZ/.claude/i18n/agents/reviewer.es.md"; tap_check $? "reviewer (es): hace implementar en un worktree propio"; else tap_skip "reviewer (es): hace implementar en un worktree propio" "no existe .claude/i18n/agents/reviewer.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/skills/review-pr/SKILL.es.md" ]; then grep -qF -- "worktree propio" "$RAIZ/.claude/skills/review-pr/SKILL.es.md"; tap_check $? "review-pr (es): el implementer del reviewer usa un worktree propio"; else tap_skip "review-pr (es): el implementer del reviewer usa un worktree propio" "no existe .claude/skills/review-pr/SKILL.es.md en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "WORKTREE_LOCK_AGENT" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): pide fijar WORKTREE_LOCK_AGENT a cada subagente"; else tap_skip "contrato (es): pide fijar WORKTREE_LOCK_AGENT a cada subagente" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi

if [ -f "$RAIZ/.claude/skills/orchestrate/SKILL.es.md" ]; then grep -qF -- "worktree-lock.sh release" "$RAIZ/.claude/skills/orchestrate/SKILL.es.md"; tap_check $? "orchestrate (es): suelta el candado antes de lanzar al subagente"; else tap_skip "orchestrate (es): suelta el candado antes de lanzar al subagente" "no existe SKILL.es.md de orchestrate en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "orquestador suelta" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): el orquestador suelta el candado de prepare.sh"; else tap_skip "contrato (es): el orquestador suelta el candado de prepare.sh" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi

# 8. El candado tiene que cubrir el trabajo del subagente (#267, 2.ª review del PR #268): el orquestador lo suelta antes
# de lanzar, así que el subagente lo toma con su propio nombre al empezar (worktree-lock.sh claim). Sin eso, el worktree
# queda libre justo mientras se trabaja.
export WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=implementer-267
tap_run out 0 "$LOCK" claim "$TMP/wt"
# El subagente comparte el pid con el orquestador: al terminar suelta con su nombre, y el siguiente agente de la sesión
# (la ronda de arreglos del reviewer, un relanzamiento) puede tomarlo. Sin soltar, el pid sigue vivo y daría held.
tap_run out 0 "$LOCK" release "$TMP/wt"
export WORKTREE_LOCK_AGENT=orquestador
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx claimed <<<"$out"; tap_check $? "subagente que suelta el candado: el siguiente agente de la sesión lo toma"
rm -f "$GDIR/agent-lock"
if [ "$CHICO" = 1 ]; then
  tap_skip "implementer: toma el candado al empezar" "$SIN"
  tap_skip "implementer-light: toma el candado al empezar" "$SIN"
  tap_skip "orchestrate: dice que el subagente toma el candado" "$SIN"
  tap_skip "contrato: el subagente toma el candado con su nombre" "$SIN"
  tap_skip "implementer: suelta el candado al terminar" "$SIN"
  tap_skip "implementer-light: suelta el candado al terminar" "$SIN"
  tap_skip "orchestrate: suelta en nombre del subagente si no lo soltó" "$SIN"
  tap_skip "contrato: el release lleva WORKTREE_LOCK_AGENT con el nombre" "$SIN"
  tap_skip "prepare.sh: la ayuda del release lleva WORKTREE_LOCK_AGENT con el nombre" "$SIN"
  tap_skip "implementer: ante held devuelve solo question" "$SIN"
else
  mencion .claude/agents/implementer.md "worktree-lock.sh claim" "worktree-lock.sh claim"; tap_check $? "implementer: toma el candado al empezar"
  mencion .claude/agents/implementer-light.md "worktree-lock.sh claim" "worktree-lock.sh claim"; tap_check $? "implementer-light: toma el candado al empezar"
  mencion .claude/skills/orchestrate/SKILL.md "worktree-lock.sh claim" "worktree-lock.sh claim"; tap_check $? "orchestrate: dice que el subagente toma el candado"
  mencion docs/agents/subagent-contract.md "worktree-lock.sh claim" "worktree-lock.sh claim"; tap_check $? "contrato: el subagente toma el candado con su nombre"
  mencion .claude/agents/implementer.md "worktree-lock.sh release" "worktree-lock.sh release"; tap_check $? "implementer: suelta el candado al terminar"
  mencion .claude/agents/implementer-light.md "worktree-lock.sh release" "worktree-lock.sh release"; tap_check $? "implementer-light: suelta el candado al terminar"
  mencion .claude/skills/orchestrate/SKILL.md "on its behalf" "en su nombre"; tap_check $? "orchestrate: suelta en nombre del subagente si no lo soltó"
  mencion docs/agents/subagent-contract.md "WORKTREE_LOCK_AGENT=<name> scripts/agents/worktree-lock.sh release" "WORKTREE_LOCK_AGENT=<nombre> scripts/agents/worktree-lock.sh release"; tap_check $? "contrato: el release lleva WORKTREE_LOCK_AGENT con el nombre"
  mencion .claude/skills/implement-issue/prepare.sh "WORKTREE_LOCK_AGENT=<name> worktree-lock.sh release" "WORKTREE_LOCK_AGENT=<nombre> worktree-lock.sh release"; tap_check $? "prepare.sh: la ayuda del release lleva WORKTREE_LOCK_AGENT con el nombre"
  mencion .claude/agents/implementer.md "return \`question\` (" "devolvé \`question\` ("; tap_check $? "implementer: ante held devuelve solo question"
fi
if [ -f "$RAIZ/.claude/i18n/agents/implementer.es.md" ]; then grep -qF -- "worktree-lock.sh claim" "$RAIZ/.claude/i18n/agents/implementer.es.md"; tap_check $? "implementer (es): toma el candado al empezar"; else tap_skip "implementer (es): toma el candado al empezar" "no existe .claude/i18n/agents/implementer.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/i18n/agents/implementer-light.es.md" ]; then grep -qF -- "worktree-lock.sh claim" "$RAIZ/.claude/i18n/agents/implementer-light.es.md"; tap_check $? "implementer-light (es): toma el candado al empezar"; else tap_skip "implementer-light (es): toma el candado al empezar" "no existe .claude/i18n/agents/implementer-light.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/skills/orchestrate/SKILL.es.md" ]; then grep -qF -- "worktree-lock.sh claim" "$RAIZ/.claude/skills/orchestrate/SKILL.es.md"; tap_check $? "orchestrate (es): dice que el subagente toma el candado"; else tap_skip "orchestrate (es): dice que el subagente toma el candado" "no existe .claude/skills/orchestrate/SKILL.es.md en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "worktree-lock.sh claim" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): el subagente toma el candado con su nombre"; else tap_skip "contrato (es): el subagente toma el candado con su nombre" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/i18n/agents/implementer.es.md" ]; then grep -qF -- "worktree-lock.sh release" "$RAIZ/.claude/i18n/agents/implementer.es.md"; tap_check $? "implementer (es): suelta el candado al terminar"; else tap_skip "implementer (es): suelta el candado al terminar" "no existe .claude/i18n/agents/implementer.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/i18n/agents/implementer-light.es.md" ]; then grep -qF -- "worktree-lock.sh release" "$RAIZ/.claude/i18n/agents/implementer-light.es.md"; tap_check $? "implementer-light (es): suelta el candado al terminar"; else tap_skip "implementer-light (es): suelta el candado al terminar" "no existe .claude/i18n/agents/implementer-light.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/skills/orchestrate/SKILL.es.md" ]; then grep -qF -- "en su nombre" "$RAIZ/.claude/skills/orchestrate/SKILL.es.md"; tap_check $? "orchestrate (es): suelta en nombre del subagente si no lo soltó"; else tap_skip "orchestrate (es): suelta en nombre del subagente si no lo soltó" "no existe .claude/skills/orchestrate/SKILL.es.md en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "WORKTREE_LOCK_AGENT=<nombre> scripts/agents/worktree-lock.sh release" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): el release lleva WORKTREE_LOCK_AGENT con el nombre"; else tap_skip "contrato (es): el release lleva WORKTREE_LOCK_AGENT con el nombre" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/i18n/agents/implementer.es.md" ]; then grep -qF -- "devolvé \`question\` (" "$RAIZ/.claude/i18n/agents/implementer.es.md"; tap_check $? "implementer (es): ante held devuelve solo question"; else tap_skip "implementer (es): ante held devuelve solo question" "no existe .claude/i18n/agents/implementer.es.md en este proyecto"; fi

# 9. Una sesión de review que hace implementar los arreglos (review-pr, #262) hace lo mismo que el orquestador: toma el
# candado con su nombre, lo suelta antes de lanzar, y el implementer (mismo pid, otro nombre) lo toma y lo suelta al terminar.
export WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=sesion-review
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx claimed <<<"$out"; tap_check $? "sesión de review: toma el candado con su nombre (claimed)"
tap_run out 0 "$LOCK" release "$TMP/wt"
grep -qx released <<<"$out"; tap_check $? "sesión de review: lo suelta antes de lanzar al implementer (released)"
export WORKTREE_LOCK_AGENT=implementer-268
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx claimed <<<"$out"; tap_check $? "sesión de review: el implementer (mismo pid, otro nombre) toma el candado (claimed)"
tap_run out 0 "$LOCK" release "$TMP/wt"
grep -qx released <<<"$out"; tap_check $? "sesión de review: el implementer lo suelta al terminar (released)"
export WORKTREE_LOCK_AGENT=sesion-review
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx claimed <<<"$out"; tap_check $? "sesión de review: tras soltar el implementer, la sesión toma el candado de nuevo"
rm -f "$GDIR/agent-lock"

# Docs de la sesión de review.
if [ "$CHICO" = 1 ]; then
  tap_skip "review-pr: la sesión fija WORKTREE_LOCK_AGENT al correr prepare.sh" "$SIN"
  tap_skip "review-pr: la sesión suelta el candado antes de lanzar al implementer" "$SIN"
  tap_skip "review-pr: la sesión suelta antes de lanzar al implementer, no después" "$SIN"
  tap_skip "contrato: la sesión de revisión suelta el candado como el orquestador" "$SIN"
  tap_skip "reviewer: el implementer del arreglo lleva su WORKTREE_LOCK_AGENT" "$SIN"
else
  mencion .claude/skills/review-pr/SKILL.md "WORKTREE_LOCK_AGENT=<your name> .claude/skills/implement-issue/prepare.sh" "WORKTREE_LOCK_AGENT=<tu nombre> .claude/skills/implement-issue/prepare.sh"; tap_check $? "review-pr: la sesión fija WORKTREE_LOCK_AGENT al correr prepare.sh"
  mencion .claude/skills/review-pr/SKILL.md "before launching the \`implementer\`" "antes de lanzar al \`implementer\`"; tap_check $? "review-pr: la sesión suelta antes de lanzar al implementer, no después"
  mencion .claude/skills/review-pr/SKILL.md "worktree-lock.sh release" "worktree-lock.sh release"; tap_check $? "review-pr: la sesión suelta el candado antes de lanzar al implementer"
  mencion docs/agents/subagent-contract.md "review session releases" "sesión de revisión suelta"; tap_check $? "contrato: la sesión de revisión suelta el candado como el orquestador"
  mencion .claude/agents/reviewer.md "WORKTREE_LOCK_AGENT" "WORKTREE_LOCK_AGENT"; tap_check $? "reviewer: el implementer del arreglo lleva su WORKTREE_LOCK_AGENT"
fi
if [ -f "$RAIZ/.claude/skills/review-pr/SKILL.es.md" ]; then grep -qF -- "WORKTREE_LOCK_AGENT=<tu nombre> .claude/skills/implement-issue/prepare.sh" "$RAIZ/.claude/skills/review-pr/SKILL.es.md"; tap_check $? "review-pr (es): la sesión fija WORKTREE_LOCK_AGENT al correr prepare.sh"; else tap_skip "review-pr (es): la sesión fija WORKTREE_LOCK_AGENT al correr prepare.sh" "no existe .claude/skills/review-pr/SKILL.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/skills/review-pr/SKILL.es.md" ]; then grep -qF -- "antes de lanzar al \`implementer\`" "$RAIZ/.claude/skills/review-pr/SKILL.es.md"; tap_check $? "review-pr (es): la sesión suelta antes de lanzar al implementer, no después"; else tap_skip "review-pr (es): la sesión suelta antes de lanzar al implementer, no después" "no existe .claude/skills/review-pr/SKILL.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/skills/review-pr/SKILL.es.md" ]; then grep -qF -- "worktree-lock.sh release" "$RAIZ/.claude/skills/review-pr/SKILL.es.md"; tap_check $? "review-pr (es): la sesión suelta el candado antes de lanzar al implementer"; else tap_skip "review-pr (es): la sesión suelta el candado antes de lanzar al implementer" "no existe .claude/skills/review-pr/SKILL.es.md en este proyecto"; fi
if [ -f "$RAIZ/docs/agents/subagent-contract.es.md" ]; then grep -qF -- "sesión de revisión suelta" "$RAIZ/docs/agents/subagent-contract.es.md"; tap_check $? "contrato (es): la sesión de revisión suelta el candado como el orquestador"; else tap_skip "contrato (es): la sesión de revisión suelta el candado como el orquestador" "no existe docs/agents/subagent-contract.es.md en este proyecto"; fi
if [ -f "$RAIZ/.claude/i18n/agents/reviewer.es.md" ]; then grep -qF -- "WORKTREE_LOCK_AGENT" "$RAIZ/.claude/i18n/agents/reviewer.es.md"; tap_check $? "reviewer (es): el implementer del arreglo lleva su WORKTREE_LOCK_AGENT"; else tap_skip "reviewer (es): el implementer del arreglo lleva su WORKTREE_LOCK_AGENT" "no existe .claude/i18n/agents/reviewer.es.md en este proyecto"; fi

# 10. La hora de inicio del dueño no depende de la zona horaria de quien mira: dos agentes con TZ distinto ven el mismo
# candado vivo (ps -o lstart sale en la hora local), no uno stale que se reemplaza.
export WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=agente-tz
export TZ=UTC
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx claimed <<<"$out"; tap_check $? "zona horaria: el candado se toma con TZ=UTC (claimed)"
export TZ=Asia/Tokyo
tap_run out 0 "$LOCK" status "$TMP/wt"
grep -q '^held: agente-tz' <<<"$out"; tap_check $? "zona horaria: con otro TZ el candado vivo sigue held, no stale"
unset TZ
rm -f "$GDIR/agent-lock"

# 11. El mutex de claim: con uno vivo, claim no pasa de largo (espera y sale con 64); con uno cuyo dueño murió, lo retira.
printf 'pid=%s\n' "$VIVO" >"$GDIR/agent-lock.mutex"
export WORKTREE_LOCK_PID=$VIVO WORKTREE_LOCK_AGENT=agente-mutex
tap_run out 64 "$LOCK" claim "$TMP/wt"
[ ! -f "$GDIR/agent-lock" ]; tap_check $? "mutex vivo: claim no toma el candado mientras otro claim está adentro"
rm -f "$GDIR/agent-lock.mutex"
printf 'pid=%s\n' "$MUERTO" >"$GDIR/agent-lock.mutex"
tap_run out 0 "$LOCK" claim "$TMP/wt"
grep -qx claimed <<<"$out"; tap_check $? "mutex muerto: claim retira el mutex de un dueño muerto y toma el candado (claimed)"
rm -f "$GDIR/agent-lock" "$GDIR/agent-lock.mutex"

tap_done
