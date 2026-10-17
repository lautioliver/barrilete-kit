#!/usr/bin/env bash
# shellcheck disable=SC2016  # los backticks de Markdown y los regex de los tests van entre comillas simples a propósito
# Tests de routing.py y cleanup.sh con un gh falso y un repo local (no usa GitHub).
# Uso: bash .claude/skills/orchestrate/test-orchestrate.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$AQUI/../../.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-orchestrate-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
# Uso: <condición>; tap_check $? "descripción"
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

# gh falso: cada issue es un JSON en $GH_ISSUES/<n>.json.
mkdir -p "$TMP/bin" "$TMP/issues"
export GH_ISSUES="$TMP/issues"
cat >"$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "repo view"*) echo o/r ;;
  api\ repos/o/r/issues/*) f="$GH_ISSUES/${2##*/}.json"; [ -f "$f" ] && cat "$f" || exit 1 ;;
  "pr list --head "*) f="$GH_ISSUES/pr-${4//\//_}.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
  *) echo "gh falso: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
issue() { # issue <n> <estado> <labels separados por coma> <cuerpo>
  python3 - "$@" >"$TMP/issues/$1.json" <<'PY'
import json, sys
n, estado, labels, cuerpo = sys.argv[1:5]
print(json.dumps({"number": int(n), "state": estado, "title": f"Issue {n}",
                  "labels": [{"name": l} for l in labels.split(",") if l], "body": cuerpo}))
PY
}

# Proyecto con un mapa que marca src/auth/** y src/pagos/** como sensibles.
P="$TMP/proj"
mkdir -p "$P/docs"
git init -q -b main "$P"
printf '{"sensitive": [{"type": "auth", "paths": ["src/auth/**"]}, {"type": "dinero", "paths": ["?src/pagos/**"]}, {"type": "dependencias", "paths": ["?package.json", "?*.lock"]}, {"type": "infra", "paths": ["?Dockerfile"]}]}\n' >"$P/docs/agents-map.json"
mkdir -p "$P/scripts"; cp -R "$RAIZ/scripts/agents" "$P/scripts/"
(cd "$P" && git add -A && git commit -qm base)

ruteo() { (cd "$P" && python3 "$AQUI/routing.py" "$1" 2>&1); }

# 1. Regla de ruteo (decisión 2 de la épica #33).
issue 1 open "type:docs,area:docs" "Corregir un link del README."
s=$(ruteo 1); es "$(head -1 <<<"$s")" = haiku; tap_check $? "type:docs sin riesgo → haiku"
issue 2 open "type:task" "Ordenar los scripts."
s=$(ruteo 2); es "$(head -1 <<<"$s")" = haiku; tap_check $? "type:task sin riesgo → haiku"
issue 3 open "type:bug" "Arreglar el contador."
s=$(ruteo 3); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "type:bug → sonnet"
grep -q "type:bug" <<<"$s"; tap_check $? "el motivo nombra el tipo"
grep -q "^reason: " <<<"$s" && ! grep -q "^motivo: " <<<"$s"; tap_check $? "la salida de routing.py usa la clave reason:"
issue 4 open "type:feature" "Algo nuevo."
s=$(ruteo 4); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "type:feature → sonnet"
issue 5 open "type:docs,business-logic" "Aclarar la regla de reembolsos."
s=$(ruteo 5); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "business-logic → sonnet aunque sea type:docs"
issue 6 open "type:task,breaking-change" "Renombrar un campo."
s=$(ruteo 6); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "breaking-change → sonnet aunque sea type:task"
issue 7 open "type:task" "Ordenar \`src/auth/sesion.ts\` y sus tests."
s=$(ruteo 7); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "una ruta sensible nombrada en el texto → sonnet"
grep -q "src/auth/sesion.ts" <<<"$s" && grep -q "auth" <<<"$s"; tap_check $? "el motivo nombra la ruta y el tipo sensible"
issue 8 open "type:docs" "Documentar la carpeta src/pagos/ (sin tocar código)."
s=$(ruteo 8); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "una carpeta sensible sin backticks también cuenta"
issue 9 open "" "Sin labels."
s=$(ruteo 9); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "sin type: → sonnet"
issue 20 open "type:task" "Actualizar lodash en package.json."
s=$(ruteo 20); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "una ruta sensible sin barra (package.json) → sonnet"
issue 21 open "type:task" "Ajustar el Dockerfile."
s=$(ruteo 21); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "Dockerfile nombrado → sonnet"
issue 22 open "type:task" "Regenerar yarn.lock."
s=$(ruteo 22); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "un archivo que coincide con *.lock → sonnet"
issue 23 open "type:docs" "Documentar la carpeta src/auth"
s=$(ruteo 23); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "una carpeta sensible sin barra final → sonnet"
issue 24 open "type:bug,type:docs" "Doble tipo."
s=$(ruteo 24); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "con un type: pesado además del liviano → sonnet"
issue 26 open "type:task" "Revisar ./src/auth/sesion.ts"
s=$(ruteo 26); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "una ruta sensible con ./ adelante → sonnet"
issue 27 open "type:docs" "Ver https://github.com/o/r/blob/main/src/auth/sesion.ts"
s=$(ruteo 27); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "una ruta sensible dentro de un link → sonnet"
issue 28 open "type:task" "Ajustar el dockerfile."
s=$(ruteo 28); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "una ruta sensible en minúscula (dockerfile) → sonnet"
issue 25 open "type:docs" "Explicar el package manager y la arquitectura."
s=$(ruteo 25); es "$(head -1 <<<"$s")" = haiku; tap_check $? "palabras sueltas que no son rutas sensibles no cambian el ruteo"
mkdir -p "$TMP/sin-repo"; printf '#!/bin/sh\necho "no git remotes found" >&2; exit 1\n' >"$TMP/sin-repo/gh"; chmod +x "$TMP/sin-repo/gh"
s=$(cd "$P" && PATH="$TMP/sin-repo:$PATH" python3 "$AQUI/routing.py" 1 2>&1); c=$?
! es "$c" -eq 0 && grep -qi "repo" <<<"$s"; tap_check $? "si gh no encuentra el repo, lo dice (no un 404 del issue)"
mv "$P/docs/agents-map.json" "$TMP/mapa.json"
s=$(ruteo 1); es "$(head -1 <<<"$s")" = sonnet; tap_check $? "sin mapa no se pueden descartar rutas sensibles → sonnet"
mv "$TMP/mapa.json" "$P/docs/agents-map.json"
(cd "$P" && python3 "$AQUI/routing.py" 999 >/dev/null 2>&1); c=$?
! es "$c" -eq 0; tap_check $? "un issue que no existe sale con error"

# 2. cleanup.sh: worktrees de issues cerrados, sin pisar trabajo ni retros pendientes.
WT="$TMP/proj-wt"
for n in 10 11 12 13; do git -C "$P" worktree add -q -b "claude/$n-x" "$WT/$n" 2>/dev/null; done
issue 10 closed "type:task" "Cerrado y limpio."
issue 11 open "type:task" "Abierto."
issue 12 closed "type:task" "Cerrado con cambios sin commitear."
issue 13 closed "type:task" "Cerrado y limpio, el segundo."
echo sucio >"$WT/12/sucio.txt"

s=$(cd "$P" && "$AQUI/cleanup.sh" 2>&1); c=$?
tap_check $c "cleanup.sh sin --delete termina bien"
grep -q "$WT/10" <<<"$s" && grep -q "$WT/13" <<<"$s"; tap_check $? "lista los worktrees de issues cerrados"
! grep -q "$WT/11" <<<"$s"; tap_check $? "no lista los de issues abiertos"
grep -q "$WT/12.*uncommitted" <<<"$s"; tap_check $? "avisa que el de #12 tiene cambios sin commitear"
es -d "$WT/10"; tap_check $? "sin --delete no borra nada"

# Con una retro pendiente no borra ninguno.
mkdir -p "$P/.git/pending-retros"; echo r >"$P/.git/pending-retros/x.md"
s=$(cd "$P" && "$AQUI/cleanup.sh" --delete 2>&1); c=$?
! es "$c" -eq 0 && es -d "$WT/10" && grep -q "pending-retros" <<<"$s"; tap_check $? "con retros pendientes no borra y dice por qué"
rm -rf "$P/.git/pending-retros"
# Las pendientes del directorio viejo (0.9, retros-pendientes) también cuentan.
mkdir -p "$P/.git/retros-pendientes"; echo r >"$P/.git/retros-pendientes/x.md"
s=$(cd "$P" && "$AQUI/cleanup.sh" --delete 2>&1); c=$?
! es "$c" -eq 0 && es -d "$WT/10"; tap_check $? "con retros pendientes en el directorio viejo tampoco borra"
rm -rf "$P/.git/retros-pendientes"

# Si no puede leer un issue, no lo da por "nada que limpiar": lo dice y sale con error.
mkdir -p "$WT"; git -C "$P" worktree add -q -b claude/14-x "$WT/14" 2>/dev/null
s=$(cd "$P" && "$AQUI/cleanup.sh" 2>&1); c=$?
! es "$c" -eq 0 && grep -q "#14" <<<"$s"; tap_check $? "si no puede leer el estado de un issue, lo dice y sale con error"
git -C "$P" worktree remove "$WT/14"; git -C "$P" branch -q -D claude/14-x

# Un worktree que no se puede borrar (bloqueado) se reporta y el script sale con error.
git -C "$P" worktree lock "$WT/13"
s=$(cd "$P" && "$AQUI/cleanup.sh" --delete 2>&1); c=$?
! es "$c" -eq 0 && grep -q "could not remove.*$WT/13" <<<"$s" && ! es -d "$WT/10"; tap_check $? "un worktree que no se puede borrar se reporta, y los demás se borran"
git -C "$P" worktree unlock "$WT/13"

s=$(cd "$P" && "$AQUI/cleanup.sh" --delete 2>&1); c=$?
tap_check $c "cleanup.sh --delete termina bien"

# Ramas de issues cerrados: se decide por el estado del PR en GitHub (sirve con squash y rebase).
# cleanup.sh solo las lista, sin fetch: borrar una rama (local o remota) lo decide la persona.
git init -q --bare -b main "$TMP/remoto.git"; git -C "$P" remote add origin "$TMP/remoto.git"
git -C "$P" push -q origin main 2>/dev/null; git -C "$P" remote set-head origin main
pr() { printf '[{"number": %s, "state": "%s"}]\n' "$2" "$3" >"$TMP/issues/pr-claude_$1-x.json"; } # pr <n> <pr> <estado>
for n in 15 16 17 18 19 20; do git -C "$P" branch "claude/$n-x" main; (cd "$P" && git switch -q "claude/$n-x" && git commit -q --allow-empty -m "r$n" && git push -q origin "claude/$n-x" 2>/dev/null && git switch -q main); done
(cd "$P" && git switch -q claude/19-x && git commit -q --allow-empty -m "sin pushear" && git switch -q main)
git -C "$P" branch -q -D claude/20-x   # solo existe en el remoto
for n in 15 16 18 19 20; do issue "$n" closed "type:task" "Cerrado."; done; issue 17 open "type:task" "Abierto."
pr 15 115 CLOSED; pr 16 116 MERGED; pr 17 117 OPEN; pr 19 119 CLOSED; pr 20 120 CLOSED   # 18: sin PR
antes=$(git -C "$P" for-each-ref --format='%(refname) %(objectname)' refs/remotes)
s=$(cd "$P" && "$AQUI/cleanup.sh" 2>&1)
grep -q "claude/15-x.*closed without merging" <<<"$s" && grep -q "claude/20-x.*closed without merging" <<<"$s"; tap_check $? "lista las ramas de PRs cerrados sin mergear, también las que solo están en el remoto"
! grep -q "claude/16-x" <<<"$s" && ! grep -q "claude/17-x" <<<"$s"; tap_check $? "no lista la de un PR mergeado (aunque sea squash) ni la de un issue abierto"
grep -q "claude/18-x.*without a PR" <<<"$s" && grep -q "claude/19-x.*unpushed" <<<"$s"; tap_check $? "avisa de la rama sin PR y de la que tiene commits sin pushear"
grep -q "git push origin --delete" <<<"$s"; tap_check $? "dice cómo borrar las ramas a mano (sin gh --delete-branch)"
es "$(git -C "$P" for-each-ref --format='%(refname) %(objectname)' refs/remotes)" = "$antes"; tap_check $? "listar no hace fetch ni toca las refs remotas"
(cd "$P" && "$AQUI/cleanup.sh" --delete >/dev/null 2>&1)
git -C "$P" rev-parse -q --verify claude/15-x >/dev/null && git --git-dir="$TMP/remoto.git" rev-parse -q --verify claude/15-x >/dev/null && git --git-dir="$TMP/remoto.git" rev-parse -q --verify claude/20-x >/dev/null; tap_check $? "--delete no borra ramas (ni locales ni remotas): eso lo decide la persona"
! es -d "$WT/10" && ! es -d "$WT/13"; tap_check $? "--delete borra los worktrees limpios de issues cerrados"
es -d "$WT/11" && es -f "$WT/12/sucio.txt"; tap_check $? "--delete no toca el abierto ni el que tiene cambios"
git -C "$P" rev-parse -q --verify claude/10-x >/dev/null; tap_check $? "--delete deja la rama (solo saca el worktree)"

# Issue cerrado al abrir el PR (costumbre de algunos proyectos): mientras el PR siga abierto, el worktree no se toca.
git -C "$P" worktree add -q -b claude/30-x "$WT/30" main 2>/dev/null
issue 30 closed "type:task" "Cerrado con el PR en revisión."; pr 30 130 OPEN
s=$(cd "$P" && "$AQUI/cleanup.sh" 2>&1)
! grep -q "$WT/30" <<<"$s"; tap_check $? "no lista el worktree de un issue cerrado con el PR abierto"
(cd "$P" && "$AQUI/cleanup.sh" --delete >/dev/null 2>&1)
es -d "$WT/30"; tap_check $? "--delete no saca el worktree de un PR abierto"

# Una rama de PR cerrado que todavía tiene worktree: git branch -D falla hasta sacarlo, así que
# los comandos para borrar ramas salen después de sacar los worktrees, y sin --delete lo avisa.
git -C "$P" worktree add -q -b claude/21-x "$WT/21" main 2>/dev/null
(cd "$WT/21" && git commit -q --allow-empty -m r21 && git push -q origin claude/21-x 2>/dev/null)
issue 21 closed "type:task" "Cerrado."; pr 21 121 CLOSED
s=$(cd "$P" && "$AQUI/cleanup.sh" 2>&1)
grep -q "claude/21-x.*--delete" <<<"$s"; tap_check $? "sin --delete avisa que la rama con worktree se borra después de --delete"
! grep -q "git branch -D claude/21-x" <<<"$s" && ! grep -q "push origin --delete claude/21-x" <<<"$s"; tap_check $? "sin --delete no da el comando de una rama con worktree (borraría la remota y fallaría la local)"
grep -q "git branch -D claude/15-x && git push origin --delete claude/15-x" <<<"$s"; tap_check $? "el comando borra primero la local y la remota solo si eso anduvo"
grep -q "git push origin --delete claude/15-x" <<<"$s"; tap_check $? "da el comando concreto de cada rama"
s=$(cd "$P" && "$AQUI/cleanup.sh" --delete 2>&1)
b=$(grep -n "Removed: $WT/21" <<<"$s" | cut -d: -f1); d=$(grep -n "git branch -D claude/21-x" <<<"$s" | cut -d: -f1)
es -n "$b" && es -n "$d" && es "$d" -gt "$b"; tap_check $? "--delete da los comandos de las ramas después de sacar los worktrees"
(cd "$P" && eval "$(grep "git branch -D claude/21-x" <<<"$s")" >/dev/null 2>&1) && ! git -C "$P" rev-parse -q --verify claude/21-x >/dev/null; tap_check $? "el comando que da cleanup.sh borra la rama (ya sin worktree)"

# 3. Lo que hace falta para correr en paralelo (criterios de #37).
! grep -q 'push -u' "$RAIZ/.claude/skills/implement-issue/SKILL.md"; tap_check $? "implement-issue pushea sin -u (el -u escribe .git/config y choca en paralelo)"
# shellcheck disable=SC2016  # the backtick and the $ are regex, not expansions
! grep -Eq 'pushe[aá] de nuevo[^`]*$|push again[^`]*$' "$RAIZ/.claude/skills/implement-issue/SKILL.md" && grep -q 'git push origin HEAD' "$RAIZ/.claude/agents/implementer.md"; tap_check $? "cada push dice git push origin HEAD (la rama no tiene upstream)"
M="$RAIZ/docs/agents-map.json"
for f in .claude/skills/implement-issue/SKILL.md .gitignore profiles/small/DELETE; do
  python3 -c "import json,sys; v=[x for x in json.load(open('$M'))['verify'] if x['name']=='orchestrate'][0]; sys.exit(0 if any(g.lstrip('?')=='$f' for g in v['when']) else 1)"
  tap_check $? "la verificación orchestrate del mapa corre cuando cambia <f>" "la verificación orchestrate del mapa corre cuando cambia $f"
done
R="$RAIZ/.claude/agents/reviewer.md"
grep -Eq 'refs/(revision/<pr>-<sufijo>|review/<pr>-<suffix>)' "$R" && grep -Eq -- '-(revision-<pr>-<sufijo>|review-<pr>-<suffix>)' "$R"; tap_check $? "revisor: ref y worktree con sufijo único (dos revisiones del mismo PR no chocan)"
! grep -Eq 'retro[^.]*(desde el checkout principal|from the main checkout)' "$R" "$RAIZ/docs/agents/subagent-contract.md"; tap_check $? "la retro del revisor no depende del checkout principal del repo (podía estar en una rama vieja)"
grep -Eq "checkout del orquestador.*retro.sh|orchestrator's checkout.*retro.sh" "$R" && ! grep -Eq 'worktree de revisión.*retro.sh|review worktree.*retro.sh' "$R"; tap_check $? "revisor: corre el retro.sh del checkout del orquestador, no el del PR (no revisado)"
grep -q 'skill_sha' "$R" && grep -q 'skill_sha' "$AQUI/SKILL.md"; tap_check $? "orquestar le pasa skill_sha al revisor (la versión de review-pr que corrió)"
for a in implementer implementer-light; do
  grep -q 'skill_sha' "$RAIZ/.claude/agents/$a.md"; tap_check $? "<a>: escribe en la retro el skill_sha que le pasa el orquestador" "$a: escribe en la retro el skill_sha que le pasa el orquestador"
done
grep -qi 'frená.*\.claude\|\.claude.*frená\|stop.*\.claude\|\.claude.*stop' "$AQUI/SKILL.md"; tap_check $? "orquestar frena si su checkout tiene cambios en .claude/"
grep -Eq 'revisor.*agent_sha|agent_sha.*revisor|reviewer.*agent_sha|agent_sha.*reviewer' "$AQUI/SKILL.md" && grep -Eq "checkout del orquestador|orchestrator's checkout" "$AQUI/SKILL.md"; tap_check $? "orquestar le pasa al revisor agent_sha y el checkout del orquestador"
for a in implementer implementer-light reviewer; do
  grep -q 'agent_sha' "$RAIZ/.claude/agents/$a.md"; tap_check $? "<a>: escribe en la retro el agent_sha que le pasa el orquestador" "$a: escribe en la retro el agent_sha que le pasa el orquestador"
done
grep -q 'agent_sha' "$AQUI/SKILL.md"; tap_check $? "orquestar le pasa agent_sha a cada subagente"
grep -Eqi 'markdown crudo|raw markdown' "$R"; tap_check $? "revisor: el texto de la revisión va en Markdown crudo, sin entidades HTML"
grep -qi 'relanzado.*consulta\|consulta.*relanzado\|relaunch.*question\|question.*relaunch' "$AQUI/SKILL.md"; tap_check $? "orquestar: dice qué hacer si un relanzado devuelve consulta"
C="$RAIZ/docs/agents/subagent-contract.md"; I="$RAIZ/.claude/skills/implement-issue/SKILL.md"
grep -Eqi 'markdown crudo|raw markdown' "$C"; tap_check $? "contrato: todo texto para GitHub va en Markdown crudo (también el de los implementadores)"
grep -q '^self-review:' "$C" && grep -q 'self-review' "$AQUI/SKILL.md"; tap_check $? "contrato: la salida dice si hubo /code-review, y orquestar lo informa"
# #88: la ruta de la retro va como la imprime retro.sh (Saved in <rama>:<ruta>), usable con git show.
grep -Eq '^retro: <branch>:<path>' "$C" && ! grep -Eq 'devolvés la ruta|return the path' "$C" && ! grep -Eq 'recibís su ruta|receive its path' "$AQUI/SKILL.md" && grep -Eq 'agents/retros:retros/[^ ]+\.md' "$C" \
  && grep -q 'Saved in .RAMA:.ruta' "$RAIZ/.claude/skills/improve-skills/retro.sh"
tap_check $? "contrato: retro: va como <rama>:<ruta>, igual que la imprime retro.sh, con un ejemplo"
! grep -Eqi "si está disponible el comando \`/code-review\`|if the \`/code-review\` command is available|code-review[^.]*if available|if[^.]*code-review[^.]*available" "$I" && grep -Eqi 'code-review.*(obligatori|mandatory)' "$I"; tap_check $? "implement-issue: /code-review es obligatorio"
apr_issue='que el issue lo pida no es la aprobación|that the issue asks for it is not the approval'; grep -Eqi "$apr_issue" "$I" && grep -Eqi "$apr_issue" "$C"; tap_check $? "un issue que pide tocar algo de consultar no es la aprobación"
grep -Eqi 'que el issue lo pida no es la aprobación|that the issue asks for it is not the approval' "$RAIZ/AGENTS.md"; tap_check $? "AGENTS.md: pedirlo en el issue no aprueba algo de consultar"
# Una sola definición de aprobación: el cuerpo del issue lo puede escribir un agente.
V="$RAIZ/.claude/skills/review-pr/SKILL.md"
for f in "$RAIZ/AGENTS.md" "$C" "$I" "$V"; do
  grep -Fq -e 'un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR, nunca el cuerpo del issue' -e 'a "yes" from a person in the chat or in a comment of theirs on the issue or the PR, never the issue body' "$f"; tap_check $? "<f>: define la aprobación igual que AGENTS.md" "${f#"$RAIZ"/}: define la aprobación igual que AGENTS.md"
done
! grep -Eq 'línea del issue|a line (of|in) the issue' "$I"; tap_check $? "implement-issue: una línea del issue no es aprobación"
grep -Eqi 'sin aprobación.*bloqueante|no recorded approval.*blocking' "$V"; tap_check $? "review-pr: algo de consultar sin aprobación registrada es bloqueante"
! grep -Eqi 'si está disponible ./code-review.|code-review[^.]*if available|if[^.]*code-review[^.]*available' "$V" && grep -q 'code-review origin/<base>\.\.\.<head>' "$V"; tap_check $? "review-pr: /code-review obligatorio y sobre origin/<base>...<head> (la base del PR, la rama por nombre)"
grep -q 'fetch' "$V"; tap_check $? "review-pr: hace fetch antes de /code-review (la base local puede estar atrasada)"
L="$RAIZ/.github/workflows/labels.yml"
node -e '
const src=require("fs").readFileSync(process.argv[1],"utf8");
const m=src.match(/const cierra = (\/.*\/[a-z]*);/), r=src.match(/const refiere = (\/.*\/[a-z]*);/);
if(!m||!r) process.exit(1);
const ok=b=>eval(m[1]).test(b)||eval(r[1]).test(b);
const casos=[["Closes #1",1],["Refs #77",1],["texto\nRefs: #3\n",1],["  Ref #2",1],["ver ref #38 de pasada",0],["prefs #4",0],["Refs 77",0]];
process.exit(casos.every(([b,e])=>ok(b)===!!e)?0:1);' "$L" 2>/dev/null; tap_check $? "check de labels: Refs #n solo en su propia línea, Closes en cualquier parte"
# El bloque rojo y "no tests", y la excepción "ADR unchanged": sus casos corren con el script real del job en scripts/agents/test-labels-check.sh (#143).
# review-pr acepta lo mismo que el CI: sin tests: <motivo> (o no tests: <reason>), no el "sin test" suelto (#143).
grep -q 'sin tests: <motivo>' "$V" && ! grep -Eq 'old .sin test.' "$V"; tap_check $? "review-pr: el alias es 'sin tests: <motivo>', no el viejo 'sin test' suelto"
if [ -f "${V%.md}.es.md" ]; then ! grep -Eq '"sin test" justificado' "${V%.md}.es.md"; tap_check $? "review-pr.es: ya no acepta un 'sin test' suelto como justificación"; fi
if [ -d "$RAIZ/profiles/small" ]; then
  grep -Eqi 'que el issue lo pida no es la aprobación|that the issue asks for it is not the approval' "$RAIZ/profiles/small/AGENTS.md"; tap_check $? "chico: pedirlo en el issue no es la aprobación"
  ! grep -qi 'si está disponible ./code-review.' "$RAIZ/profiles/small/.claude/skills/implement-issue/SKILL.md"; tap_check $? "chico: /code-review obligatorio"
fi
grep -q 'code-review.*origin/<base>\.\.\.<branch>' "$RAIZ/.claude/skills/implement-issue/SKILL.md"; tap_check $? "implement-issue corre /code-review sobre el diff de la rama, nombrada (origin/<base>...<branch>)"
(cd "$RAIZ" && git check-ignore -q .claude/worktrees/agente-x); tap_check $? ".claude/worktrees/ está ignorado (el aislamiento de Claude Code no ensucia el checkout)"
grep -qx '.claude/skills/orchestrate' "$RAIZ/profiles/small/DELETE" 2>/dev/null || ! [ -d "$RAIZ/profiles" ]; tap_check $? "el modo chico borra la skill orquestar"


# --- #143: lo que encontró la prueba de punta a punta de #115 (los dos idiomas: el .md y su hermano .es.md si existe) ---
# ambos <descripción> <regex> <archivo...>: el regex tiene que estar en cada archivo (y en su hermano en español, en la plantilla).
ambos() {
  local d="$1" re="$2" f x g r=0 vistos=" "; shift 2
  for f in "$@"; do
    x="${f/\/.claude\/agents\//\/.claude\/i18n\/agents\/}"   # los hermanos de los agentes viven en .claude/i18n/agents/
    for g in "$f" "${f%.md}.es.md" "${x%.md}.es.md"; do
      [ -f "$g" ] || continue
      case "$vistos" in *" $g "*) continue ;; esac; vistos="$vistos$g "
      grep -Eq -- "$re" "$g" || { r=1; echo "       falta en ${g#"$RAIZ"/}"; }
    done
  done
  tap_check $r "$d"
}
SK="$RAIZ/.claude/skills"; AG="$RAIZ/.claude/agents"
# 1. red.sh: el formato de las aserciones está dicho donde el implementador lo lee, con la sintaxis de red.sh.
ambos "implement-issue (paso 3) dice qué reconoce red.sh en un test bash: FAIL - " 'starts with `FAIL - `|empieza con `FAIL - `' "$SK/implement-issue/SKILL.md"
ambos "los implementadores nombran red.sh con su sintaxis (red.sh -- <test command>)" 'red\.sh -- <(test command|comando de test)>' "$AG/implementer.md" "$AG/implementer-light.md"
ambos "los implementadores dicen el formato FAIL - (el que red.sh reconoce)" '`FAIL - `' "$AG/implementer.md" "$AG/implementer-light.md"
for a in implementer implementer-light; do
  grep -q 'red\.sh -- <' "$AG/$a.md" && grep -q 'FAIL - ' "$AG/$a.md" && ! grep -q 'FAIL: ' "$AG/$a.md"; tap_check $? "<a>: la sintaxis red.sh -- <comando> y el formato FAIL - (sin prometer FAIL:)" "$a: la sintaxis red.sh -- <comando> y el formato FAIL - (sin prometer FAIL:)"
done
# 3. retro-template: agent_sha y skill_sha, que el contrato exige.
for t in retro-template.md retro-template.es.md; do
  [ -f "$SK/improve-skills/$t" ] || continue
  grep -q '^agent_sha:' "$SK/improve-skills/$t" && grep -q '^skill_sha:' "$SK/improve-skills/$t"; tap_check $? "<t> trae agent_sha y skill_sha" "$t trae agent_sha y skill_sha"
done
# 4. La base del diff del /code-review es la del PR (o BASE), nunca origin/main fijo, y la rama va por nombre (no HEAD).
! grep -Eq 'code-review[^`]*(origin/main|\.\.\.HEAD)' "$I" "$V" "$C" "$AG"/*.md "$RAIZ"/.claude/i18n/agents/*.md 2>/dev/null; tap_check $? "ninguna skill ni agente fija origin/main ni ...HEAD en el /code-review"
grep -Eq 'code-review origin/<base>\.\.\.refs/(review|revision)/' "$R"; tap_check $? "revisor: /code-review sobre origin/<base>...refs/review/<pr>-<suffix> (su HEAD no es el de la sesión que lo lanzó)"
# 5. Una sola regla para saltear /code-review, y qué poner en self-review:.
ambos "una sola regla: /code-review se saltea solo si el comando no existe en la sesión, y se informa como 'no code-review: <reason>'" 'no code-review: <(reason|motivo)>' "$C" "$I" "$AG/implementer.md" "$AG/implementer-light.md"
ambos "la regla de saltear /code-review dice 'no existe en tu sesión' en la skill, el contrato y los agentes" 'does not exist in your session|no existe en tu sesión' "$C" "$I" "$V" "$AG/implementer.md" "$AG/implementer-light.md"
ambos "un diff vacío no es motivo para saltear /code-review (se arregla el rango)" 'empty diff|diff vacío' "$C" "$I"
# 8. El revisor no corre código del PR salvo los tests: los scripts del kit salen del checkout de confianza.
ambos "review-pr: agents_map.py y red.sh corren desde el checkout de confianza (<root>), no desde el worktree del PR" 'cd <root> && python3 scripts/agents/agents_map.py --pr <n>' "$V"
ambos "review-pr: red.sh del checkout de confianza, y lo único del PR que corre son sus tests" '<root>/.claude/skills/implement-issue/red\.sh --' "$V"
ambos "revisor: red.sh y agents_map.py del checkout del orquestador, no del worktree de revisión" '(root|raiz).*/\.claude/skills/implement-issue/red\.sh.*agents_map\.py' "$R"
# 8 (aprobado por @lautioliver): una sola regla de lo que corre el revisor, igual en el revisor, review-pr y el contrato.
ambos "revisor, review-pr y contrato: los scripts del kit (red.sh, agents_map.py, verify.py, retro.sh) salen del checkout de confianza, en la rama base" 'red\.sh.*agents_map\.py.*retro\.sh.*(trusted checkout, on the base branch|checkout de confianza, en la rama base)' "$R" "$V" "$C"
ambos "revisor, review-pr y contrato: el commit en rojo puede tener tests, fixtures y stubs, y no corre otro código del PR" '(red commit may contain tests, fixtures and stubs|commit en rojo puede tener tests, fixtures y stubs).*(never runs any other PR code|[Nn]unca corre otro código del PR)' "$R" "$V" "$C"
ambos "revisor, review-pr y contrato: los tests del PR corren en el worktree de revisión, en el commit en rojo y en la punta" '(red commit and at the tip|commit en rojo y en la punta)' "$R" "$V" "$C"
! grep -Eq 'only runs .retro.sh. there|solo corre .retro.sh. ahí|only adds tests|apenas agrega|solo agrega tests' "$R" "$V" "$C" "${C%.md}.es.md" "$RAIZ/.claude/i18n/agents/reviewer.es.md" 2>/dev/null; tap_check $? "ya no quedan las frases viejas (el revisor solo corre retro.sh; el commit en rojo solo agrega tests)"
ambos "revisor, review-pr y contrato: el revisor no corre verify.py (lo cubre el CI)" '(does not run `verify.py`|No corre `verify.py`)' "$R" "$V" "$C"
! grep -Eq 'red\.sh.*agents_map\.py.*verify\.py.*retro\.sh' "$R" "$V" "$C" "${C%.md}.es.md" "${V%.md}.es.md" "$RAIZ/.claude/i18n/agents/reviewer.es.md" 2>/dev/null; tap_check $? "ningún texto del revisor lista verify.py entre los scripts que corre"
grep -Eq 'checkout de confianza|trusted checkout' "$C" && grep -Eq 'run \(the reviewer is the exception|se corren \(el revisor es la excepción' "$C" "${C%.md}.es.md"; tap_check $? "contrato (viñeta 1): el revisor es la excepción de cd <worktree> && …"
ambos "review-pr (Retro): retro.sh del checkout de confianza por ruta absoluta" '<root>/\.claude/skills/improve-skills/retro\.sh' "$V"
ambos "implement-issue (paso 3): qué puede tener el commit en rojo" 'fixtures and stubs|fixtures y stubs' "$I"
# 7. Restos en español en la instalación en inglés.
CI="$SK/create-issue/SKILL.md"
if [ -f "$SK/create-issue/SKILL.es.md" ]; then
  ! grep -Eq 'Qué pasa|Qué debería' "$CI" && grep -q '## What happens' "$CI" && grep -q '## Qué pasa' "$SK/create-issue/SKILL.es.md"
else  # proyecto instalado: un solo idioma, sin mezclar
  grep -Eq '## (What happens|Qué pasa)' "$CI" && ! { grep -q 'What happens' "$CI" && grep -q 'Qué pasa' "$CI"; }
fi
tap_check $? "create-issue paso 6: los títulos del cuerpo salen de la plantilla en el idioma de la instalación"

tap_done
