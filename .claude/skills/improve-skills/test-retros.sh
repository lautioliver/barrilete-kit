#!/usr/bin/env bash
# Tests de retro.sh y signals.sh contra un remoto local (no usa GitHub).
# Uso: bash .claude/skills/improve-skills/test-retros.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$AQUI/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-retros-XXXXXX")
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
RAMA=agents/retros
RAMA_VIEJA=agentes/retros
# Uso: <condición>; tap_check $? "descripción"
igual() { [ "$1" = "$2" ]; }
es() { test "$@"; }

# gh falso: los scripts no pueden depender de GitHub para las retros.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 1\n' >"$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
# Aislado de la config de git de quien corre los tests (rama por defecto, firma, hooks globales…).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export PATH="$TMP/bin:$PATH" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

git init -q --bare -b main "$TMP/remoto.git"
clonar() {
  git clone -q "$TMP/remoto.git" "$1" 2>/dev/null
  mkdir -p "$1/.claude/skills"
  cp -R "$RAIZ/.claude/skills/improve-skills" "$RAIZ/.claude/skills/implement-issue" "$RAIZ/.claude/skills/review-pr" "$1/.claude/skills/"
}
clonar "$TMP/a"
(cd "$TMP/a" && git add -A && git commit -qm base && git push -q origin HEAD:main 2>/dev/null)
clonar "$TMP/b"; (cd "$TMP/b" && git fetch -q && git reset -q --hard origin/main)

retro() { # retro <clon> <skill> <issue> <texto>
  cat >"$TMP/r.md" <<MD
---
skill: $2
issue: $3
pr: 99
area: docs
paths: docs/README.md
---
**Desvíos:** $4
MD
  (cd "$TMP/$1" && "$AQUI/retro.sh" "$TMP/r.md")
}
archivos() { git --git-dir="$TMP/remoto.git" ls-tree -r --name-only "$RAMA" -- retros/ 2>/dev/null; }

# 1. Crea un archivo con el frontmatter completo, pushea, y no toca la rama ni el índice.
(cd "$TMP/a" && git switch -q -c claude/1-algo && echo x >sucio.txt && git add sucio.txt)
retro a implement-issue 1 "primera" >/dev/null 2>"$TMP/err" || true
igual "$(archivos | wc -l | tr -d " ")" 1; tap_check $? "retro.sh pushea un archivo a <RAMA>" "retro.sh pushea un archivo a $RAMA"
f=$(archivos | head -1)
grep -Eq '^retros/[0-9]{4}-[0-9]{2}-[0-9]{2}-implement-issue-1\.md$' <<<"$f"; tap_check $? "el nombre es AAAA-MM-DD-<skill>-<n>.md"
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$f" 2>/dev/null)
for campo in skill issue pr area paths skill_sha date model role; do
  grep -Eq "^$campo: .+" <<<"$c"; tap_check $? "el frontmatter tiene <campo>" "el frontmatter tiene $campo"
done
grep -q '^model: unknown$' <<<"$c" && grep -q '^role: session$' <<<"$c"; tap_check $? "sin modelo ni rol se guardan como desconocido y sesion"
! grep -q '^agent_sha:' <<<"$c"; tap_check $? "una retro sin rol de subagente no lleva agent_sha"
sha=$(cd "$TMP/a" && git log -1 --format=%h -- .claude/skills/implement-issue/SKILL.md)
sha=$(cd "$TMP/a" && git log -1 --format=%H -- .claude/skills/implement-issue/SKILL.md)
grep -q "^skill_sha: $sha$" <<<"$c"; tap_check $? "skill_sha es el commit completo del último cambio del SKILL.md"
igual "$(cd "$TMP/a" && git branch --show-current)" claude/1-algo; tap_check $? "la rama actual no cambió"
igual "$(cd "$TMP/a" && git diff --cached --name-only)" sucio.txt; tap_check $? "el índice no cambió"

# Sin frontmatter obligatorio, no publica.
printf '**Desvíos:** nada\n' >"$TMP/mal.md"
! (cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/mal.md" >/dev/null 2>&1); tap_check $? "rechaza una retro sin skill ni issue"

# 2. Dos retros desde clones desactualizados (y la misma skill e issue el mismo día) no se pisan.
retro b review-pr 1 "desde b" >/dev/null 2>&1 || true
retro a review-pr 1 "desde a" >/dev/null 2>&1 || true
igual "$(archivos | wc -l | tr -d " ")" 3; tap_check $? "tres retros en el remoto"

# 3 y 4. signals.sh muestra solo lo posterior a consolidated.md.
s=$(cd "$TMP/a" && "$AQUI/signals.sh" 2>&1)
grep -q primera <<<"$s" && grep -q "desde a" <<<"$s" && grep -q "desde b" <<<"$s"; tap_check $? "signals.sh sin consolidar muestra todas"
punta=$(sed -n 's/.*consolidate up to: \([0-9a-f]\{7,\}\).*/\1/p' <<<"$s" | head -1)
grep -Eq '^[0-9a-f]{40}$' <<<"$punta"; tap_check $? "signals.sh imprime el commit completo para consolidar"
(cd "$TMP/a" && "$AQUI/retro.sh" --consolidated deadbee https://example.test/pull/7 >/dev/null 2>&1); igual $? 64; tap_check $? "--consolidated rechaza un commit que no existe"
(cd "$TMP/a" && "$AQUI/retro.sh" --consolidated "$punta" https://example.test/pull/7 >/dev/null 2>&1) || true
cons=$(git --git-dir="$TMP/remoto.git" show "$RAMA:consolidated.md" 2>/dev/null)
grep -q "^consolidated-until: $punta" <<<"$cons" && grep -q "pull/7" <<<"$cons"; tap_check $? "consolidated.md guarda hasta dónde y el PR"
retro b implement-issue 2 "despues" >/dev/null 2>&1 || true
s=$(cd "$TMP/a" && "$AQUI/signals.sh" 2>&1)
grep -q despues <<<"$s" && ! grep -q primera <<<"$s"; tap_check $? "signals.sh después de consolidar muestra solo las nuevas"
grep -q "## CI failures" <<<"$s"; tap_check $? "signals.sh no falla sin gh"

# Ruta relativa desde una subcarpeta del repo.
mkdir -p "$TMP/a/docs"
printf -- '---\nskill: implement-issue\nissue: 3\n---\nrelativa\n' >"$TMP/a/docs/rel.md"
(cd "$TMP/a/docs" && ../.claude/skills/improve-skills/retro.sh rel.md >/dev/null 2>&1)
archivos | grep -q 'implement-issue-3\.md$'; tap_check $? "acepta una ruta relativa desde una subcarpeta"

# review-pr sin issue: alcanza con el PR.
printf -- '---\nskill: review-pr\nissue: sin issue\npr: 45\n---\nsin issue\n' >"$TMP/sin.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/sin.md" >/dev/null 2>&1)
archivos | grep -q 'review-pr-pr45\.md$'; tap_check $? "review-pr sin issue usa el número de PR"

# Carrera real: justo antes del push de a, b guarda otra retro. a tiene que reintentar.
real=$(command -v git)
mkdir -p "$TMP/shim"
cat >"$TMP/shim/git" <<SH
#!/usr/bin/env bash
if [ "\$1" = push ] && [ ! -f "$TMP/carrera" ]; then
  touch "$TMP/carrera"
  printf -- '---\nskill: implement-issue\nissue: 8\n---\nintrusa\n' >"$TMP/intrusa.md"
  (cd "$TMP/b" && PATH="$TMP/bin:\${PATH#$TMP/shim:}" "$AQUI/retro.sh" "$TMP/intrusa.md" >/dev/null 2>&1)
fi
exec "$real" "\$@"
SH
chmod +x "$TMP/shim/git"
printf -- '---\nskill: implement-issue\nissue: 9\n---\ncarrera\n' >"$TMP/carrera.md"
err=$(cd "$TMP/a" && PATH="$TMP/shim:$PATH" "$AQUI/retro.sh" "$TMP/carrera.md" 2>&1 >/dev/null)
archivos | grep -q 'implement-issue-8\.md$' && archivos | grep -q 'implement-issue-9\.md$'; tap_check $? "en una carrera se guardan las dos retros"
grep -q retrying <<<"$err"; tap_check $? "en una carrera reintenta"

# Un push que falla por otra razón no se reintenta, muestra el error y deja la retro a mano.
git clone -q "$TMP/remoto.git" "$TMP/c" 2>/dev/null
(cd "$TMP/c" && git remote set-url origin "$TMP/no-existe.git")
err=$(cd "$TMP/c" && "$AQUI/retro.sh" "$TMP/carrera.md" 2>&1 >/dev/null); cod=$?
! igual "$cod" 0 && ! grep -q retrying <<<"$err"; tap_check $? "sin acceso al remoto falla sin reintentar"
grep -q 'no-existe' <<<"$err"; tap_check $? "muestra el error de git"
ls "$TMP/c/.git/pending-retros/"*.md >/dev/null 2>&1; tap_check $? "deja la retro en .git/pending-retros"

# Sin remoto: guarda en la rama local.
git init -q "$TMP/d"; (cd "$TMP/d" && git commit -q --allow-empty -m base)
(cd "$TMP/d" && "$AQUI/retro.sh" "$TMP/carrera.md" >/dev/null 2>&1)
git -C "$TMP/d" ls-tree -r --name-only "$RAMA" 2>/dev/null | grep -q 'implement-issue-9\.md$'; tap_check $? "sin remoto guarda en la rama local"

# En un repo sin commits la retro no se pierde: se guarda o queda pendiente.
git init -q "$TMP/vacio"
(cd "$TMP/vacio" && "$AQUI/retro.sh" "$TMP/carrera.md" >/dev/null 2>&1)
git -C "$TMP/vacio" ls-tree -r --name-only "$RAMA" 2>/dev/null | grep -q 'implement-issue-9\.md$' \
  || ls "$TMP/vacio/.git/pending-retros/"*.md >/dev/null 2>&1; tap_check $? "en un repo sin commits la retro no se pierde"

# Revisión del PR #39.
# --consolidated solo acepta commits de la rama de retros.
otro=$(cd "$TMP/a" && git rev-parse HEAD)
(cd "$TMP/a" && "$AQUI/retro.sh" --consolidated "$otro" https://example.test/pull/8 >/dev/null 2>&1); igual $? 64; tap_check $? "--consolidated rechaza un commit que no es de <RAMA>" "--consolidated rechaza un commit que no es de $RAMA"

# Frontmatter con CRLF y comillas se acepta; sin cerrar se rechaza.
printf -- '---\r\nskill: "implement-issue"\r\nissue: 11\r\n---\r\ncrlf\r\n' >"$TMP/crlf.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/crlf.md" >/dev/null 2>&1)
archivos | grep -q 'implement-issue-11\.md$'; tap_check $? "acepta frontmatter con CRLF y comillas"
printf -- '---\nskill: implement-issue\nissue: 12\nsin cierre\n' >"$TMP/abierto.md"
! (cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/abierto.md" >/dev/null 2>&1); tap_check $? "rechaza un frontmatter sin cerrar"

# Con commit.gpgSign y una firma que falla, igual guarda (la rama de retros no se firma).
(cd "$TMP/a" && git config commit.gpgSign true && git config gpg.program false)
printf -- '---\nskill: implement-issue\nissue: 13\n---\nfirma\n' >"$TMP/firma.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/firma.md" >/dev/null 2>&1)
archivos | grep -q 'implement-issue-13\.md$'; tap_check $? "guarda aunque el repo exija firmar commits"
(cd "$TMP/a" && git config --unset commit.gpgSign && git config --unset gpg.program)

# En un worktree, la pendiente queda en el .git común (sobrevive a git worktree remove).
git -C "$TMP/c" worktree add -q "$TMP/cw" 2>/dev/null
printf -- '---\nskill: implement-issue\nissue: 14\n---\nworktree\n' >"$TMP/wt.md"
(cd "$TMP/cw" && "$AQUI/retro.sh" "$TMP/wt.md" >/dev/null 2>&1)
git -C "$TMP/c" worktree remove --force "$TMP/cw" 2>/dev/null
pend=$(find "$TMP/c/.git/pending-retros" -name "*implement-issue-14*.md" 2>/dev/null | head -1)
grep -q . <<<"$pend"; tap_check $? "en un worktree la pendiente sobrevive a git worktree remove"

# Reintentar una pendiente con éxito la borra y no duplica.
(cd "$TMP/c" && git remote set-url origin "$TMP/remoto.git")
(cd "$TMP/c" && "$AQUI/retro.sh" "$pend" >/dev/null 2>&1)
igual "$(archivos | grep -c 'implement-issue-14')" 1; tap_check $? "la pendiente reintentada se guarda una vez"
! [ -e "$pend" ]; tap_check $? "la pendiente reintentada se borra"

# Retros guardadas sin remoto siguen visibles (y se suben) cuando se agrega uno.
git init -q --bare -b main "$TMP/remoto-d.git"
(cd "$TMP/d" && git remote add origin "$TMP/remoto-d.git")
s=$(cd "$TMP/d" && "$AQUI/signals.sh" 2>&1)
grep -q 'implement-issue-9' <<<"$s"; tap_check $? "signals.sh ve las retros locales después de agregar un remoto"
printf -- '---\nskill: implement-issue\nissue: 15\n---\nd\n' >"$TMP/d.md"
(cd "$TMP/d" && "$AQUI/retro.sh" "$TMP/d.md" >/dev/null 2>&1)
git --git-dir="$TMP/remoto-d.git" ls-tree -r --name-only "$RAMA" 2>/dev/null | grep -q 'implement-issue-9'; tap_check $? "al agregar un remoto, las retros locales se suben"

# 5. Modelo, rol, agent_sha y skill orchestrate (#35).
"$AQUI/retro.sh" 2>/dev/null | grep -Eq '^model: .*haiku'; tap_check $? "retro.sh sin argumentos muestra el campo modelo"
"$AQUI/retro.sh" 2>/dev/null | grep -Eq '^role: .*implementer-light'; tap_check $? "retro.sh sin argumentos muestra el campo rol"

clonar "$TMP/g"; (cd "$TMP/g" && git fetch -q && git reset -q --hard origin/main)
mkdir -p "$TMP/g/.claude/agents"; echo "# implementador liviano" >"$TMP/g/.claude/agents/implementer-light.md"
(cd "$TMP/g" && git add .claude/agents && git commit -qm "agente liviano")
agsha=$(cd "$TMP/g" && git log -1 --format=%H -- .claude/agents/implementer-light.md)
printf -- '---\nskill: implement-issue\nissue: 35\nmodel: haiku\nrole: implementer-light\n---\nliviano\n' >"$TMP/liv.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/liv.md" >/dev/null 2>&1)
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'implement-issue-35' | head -1)" 2>/dev/null)
grep -q '^model: haiku$' <<<"$c" && grep -q '^role: implementer-light$' <<<"$c"; tap_check $? "guarda modelo y rol tal como vienen"
grep -q "^agent_sha: $agsha$" <<<"$c"; tap_check $? "un subagente guarda agent_sha del .claude/agents/<rol>.md"

# Un agent_sha explícito (el que pasa el orquestador) se respeta, aunque el checkout tenga otro.
printf -- '---\nskill: implement-issue\nissue: 75\nmodel: sonnet\nrole: implementer\nagent_sha: 0123456789abcdef0123456789abcdef01234567\n---\nexplicito\n' >"$TMP/expl.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/expl.md" >/dev/null 2>&1)
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'implement-issue-75' | head -1)" 2>/dev/null)
grep -q '^agent_sha: 0123456789abcdef0123456789abcdef01234567$' <<<"$c" && igual "$(grep -c '^agent_sha:' <<<"$c")" 1; tap_check $? "un agent_sha explícito se guarda tal cual, una sola vez"

printf -- '---\nskill: review-pr\npr: 46\nmodel: opus\nrole: reviewer\n---\nrev\n' >"$TMP/rev.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/rev.md" >/dev/null 2>&1)
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'review-pr-pr46' | head -1)" 2>/dev/null)
grep -q '^agent_sha: unknown$' <<<"$c"; tap_check $? "si el archivo del agente no existe, agent_sha es unknown"

printf -- '---\nskill: orchestrate\nissue: 33\nmodel: opus\nrole: orchestrator\n---\nepica\n' >"$TMP/orq.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/orq.md" >/dev/null 2>&1)
archivos | grep -Eq 'retros/[0-9]{4}-[0-9]{2}-[0-9]{2}-orchestrate-33\.md$'; tap_check $? "orchestrate con issue de la épica se guarda como orquestar-<n>"

printf -- '---\nskill: orchestrate\nrun: 20261008-1530\nmodel: opus\nrole: orchestrator\n---\ncorrida\n' >"$TMP/corr.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/corr.md" >/dev/null 2>&1)
archivos | grep -Eq 'retros/[0-9]{4}-[0-9]{2}-[0-9]{2}-orchestrate-20261008-1530\.md$'; tap_check $? "orquestar sin épica se identifica con run: AAAAMMDD-HHMM"

printf -- '---\nskill: orchestrate\nrun: ayer\npr: 47\n---\nmal formada\n' >"$TMP/corr-mal.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/corr-mal.md" >/dev/null 2>&1)
archivos | grep -Eq 'retros/[0-9]{4}-[0-9]{2}-[0-9]{2}-orchestrate-pr47\.md$'; tap_check $? "corrida mal formada cae al pr y la retro se nombra prN"

printf -- '---\nskill: implement-issue\nrun: 20261008-1530\n---\ncorrida fuera de orquestar\n' >"$TMP/corr-ii.md"
! (cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/corr-ii.md" >/dev/null 2>&1); tap_check $? "run: solo vale con skill orchestrate: implement-issue sin issue ni pr se rechaza"

# Campos vacíos y espacios al final (revisión de #46).
printf -- '---\nskill: implement-issue\nissue: 61\nmodel:\nrole:\n---\nvacios\n' >"$TMP/vacios.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/vacios.md" >/dev/null 2>&1)
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'implement-issue-61' | head -1)" 2>/dev/null)
grep -q '^model: unknown$' <<<"$c" && grep -q '^role: session$' <<<"$c" && ! grep -Eq '^(model|role):$' <<<"$c"; tap_check $? "modelo y rol vacíos se guardan como desconocido y sesion"

printf -- '---\nskill: implement-issue\nissue: 62\nmodel: haiku \nrole: implementer-light \n---\nespacios\n' >"$TMP/esp.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/esp.md" >/dev/null 2>&1)
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'implement-issue-62' | head -1)" 2>/dev/null)
grep -q '^model: haiku$' <<<"$c" && grep -q '^role: implementer-light$' <<<"$c" && grep -q "^agent_sha: $agsha$" <<<"$c"; tap_check $? "espacios al final no se guardan en modelo/rol y no impiden agent_sha"

mkdir -p "$TMP/g/.claude/agents"; echo "# revisor" >"$TMP/g/.claude/agents/reviewer.md"
(cd "$TMP/g" && git add .claude/agents && git commit -qm "agente revisor")
revsha=$(cd "$TMP/g" && git log -1 --format=%H -- .claude/agents/reviewer.md)
printf -- '---\nskill: review-pr\npr: 63\nmodel: opus\nrole: reviewer \n---\nrev2\n' >"$TMP/rev2.md"
(cd "$TMP/g" && "$AQUI/retro.sh" "$TMP/rev2.md" >/dev/null 2>&1)
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'review-pr-pr63' | head -1)" 2>/dev/null)
grep -q "^agent_sha: $revsha$" <<<"$c"; tap_check $? "rol con espacio al final guarda agent_sha igual"

# La skill de improve-skills describe el agrupado por modelo y rol y el ruteo de orquestar.
S="$RAIZ/.claude/skills/improve-skills/SKILL.md"
grep -Eiq '(agrup|group)[^.]*model' "$S" && grep -Eiq '(agrup|group)[^.]*role' "$S"; tap_check $? "improve-skills describe cómo agrupa por modelo y rol"
grep -Eiq '(ruteo|routing)[^.]*orchestrate|orchestrate[^.]*(ruteo|routing)' "$S"; tap_check $? "improve-skills propone cambios en la regla de ruteo de orchestrate"
es "$(wc -l <"$S")" -le 120; tap_check $? "improve-skills/SKILL.md tiene como máximo 120 líneas"

# #88: lo que imprime retro.sh after "Saved in" es el campo retro: del contrato y abre la retro
# con git show (con remoto, desde origin/: retro.sh no crea la rama local).
valor=$(retro a review-pr 1 "formato" 2>/dev/null | sed -n 's/^Saved in \([^ ]*\).*/\1/p')
grep -Eq "^$RAMA:retros/[^ ]+\.md$" <<<"$valor" && git -C "$TMP/a" fetch -q origin "$RAMA" 2>/dev/null \
  && git -C "$TMP/a" show "origin/$valor" 2>/dev/null | grep -q '^skill: review-pr$'
tap_check $? "el valor de retro: (<rama>:<ruta>) abre la retro con git show origin/<valor>"
C="$RAIZ/docs/agents/subagent-contract.md"
grep -q 'git show origin/agents/retros:' "$C" && grep -q "local only" "$C" && grep -Eq '^retro: .*pending: ' "$C"
tap_check $? "el contrato dice cómo abrirla (origin/), qué hacer con el sufijo sin remoto y con una retro pendiente"

# Claves y valores viejos (0.9) en una retro pendiente: se normalizan a los nuevos y se conserva agente_sha.
printf -- '---\nskill: orquestar\nissue: 33\nmodelo: haiku\nrol: implementador-liviano\nagente_sha: 1111111111111111111111111111111111111111\nrutas: docs/x.md\nfecha: 2026-01-02\n---\nvieja\n' >"$TMP/v1.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/v1.md" >/dev/null 2>&1); c=$?
tap_check "$c" "retro.sh acepta una retro con skill: orquestar (0.9)"
archivos | grep -Eq 'retros/[0-9-]+-orchestrate-33(-[0-9]+)?\.md$'; tap_check $? "la retro vieja se guarda como orchestrate-<n>"
r=$(for f in $(archivos | grep -E 'orchestrate-33'); do git --git-dir="$TMP/remoto.git" show "$RAMA:$f"; done)
r=$(grep -B9 -A1 '^agent_sha: 1111' <<<"$r")
grep -q '^skill: orchestrate$' <<<"$r" && grep -q '^role: implementer-light$' <<<"$r" && grep -q '^model: haiku$' <<<"$r"; tap_check $? "normaliza skill:, rol: y modelo: a las claves y valores nuevos"
grep -q '^agent_sha: 1111111111111111111111111111111111111111$' <<<"$r"; tap_check $? "conserva agente_sha al renombrar la clave"
grep -q '^paths: docs/x.md$' <<<"$r" && grep -q '^date: 2026-01-02$' <<<"$r"; tap_check $? "rutas: y fecha: pasan a paths: y date:"
! grep -Eq '^(modelo|rol|agente_sha|rutas|fecha):' <<<"$r"; tap_check $? "la retro guardada no conserva ninguna clave vieja"
printf -- '---\nskill: mejorar-skills\npr: 7\nmodelo: opus\nrol: revisor\n---\nvieja2\n' >"$TMP/v2.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/v2.md" >/dev/null 2>&1)
archivos | grep -q 'improve-skills-pr7'; tap_check $? "mejorar-skills se guarda como improve-skills"
r=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep -E 'improve-skills-pr7' | tail -1)" 2>/dev/null)
grep -q '^role: reviewer$' <<<"$r" && grep -q '^agent_sha: ' <<<"$r"; tap_check $? "revisor pasa a reviewer y registra agent_sha"
# Valores viejos de modelo/rol vacíos y de pr/area ("desconocido", "sesion", "orquestador", "sin PR", "ninguna").
printf -- '---\nskill: orquestar\ncorrida: 20261009-0900\npr: sin PR\narea: ninguna\nmodelo: desconocido\nrol: orquestador\n---\nvalores\n' >"$TMP/v3.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/v3.md" >/dev/null 2>&1)
archivos | grep -q 'orchestrate-20261009-0900'; tap_check $? "corrida: (0.9) se acepta como run:"
r=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep -E 'orchestrate-20261009-0900' | tail -1)" 2>/dev/null)
grep -q '^model: unknown$' <<<"$r" && grep -q '^role: orchestrator$' <<<"$r" && grep -q '^pr: no PR$' <<<"$r" && grep -q '^area: none$' <<<"$r" && grep -q '^run: 20261009-0900$' <<<"$r"; tap_check $? "desconocido, orquestador, sin PR y ninguna pasan a unknown, orchestrator, no PR y none"
# Una retro pendiente en el directorio viejo (retros-pendientes) se reintenta y se borra.
mkdir -p "$TMP/c/.git/retros-pendientes"; cp "$TMP/v1.md" "$TMP/c/.git/retros-pendientes/vieja-1.md"
(cd "$TMP/c" && "$AQUI/retro.sh" "$TMP/c/.git/retros-pendientes/vieja-1.md" >/dev/null 2>&1)
! [ -e "$TMP/c/.git/retros-pendientes/vieja-1.md" ]; tap_check $? "una pendiente del directorio viejo retros-pendientes se guarda y se borra"

# Revisión (code-review): skill_sha desconocido, valores entre comillas y claves viejas y nuevas juntas.
printf -- '---\nskill: implement-issue\nissue: 41\nskill_sha: desconocido\nmodelo: "desconocido"\nrol: '"'"'sesion'"'"'\nfecha: 2026-01-01\ndate: 2026-02-02\n---\ndup\n' >"$TMP/v4.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/v4.md" >/dev/null 2>&1)
r=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep -E 'implement-issue-41' | tail -1)" 2>/dev/null)
grep -q '^skill_sha: unknown$' <<<"$r" && grep -q '^model: unknown$' <<<"$r" && grep -q '^role: session$' <<<"$r"; tap_check $? "skill_sha desconocido y los valores entre comillas pasan a unknown y session"
igual "$(grep -c '^date:' <<<"$r")" 1; tap_check $? "una clave vieja y su nueva juntas no dejan claves duplicadas"

# Revisión de #129: area con y sin prefijo es el mismo grupo.
printf -- '---\nskill: implement-issue\nissue: 42\narea: area:docs\n---\narea\n' >"$TMP/v5.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/v5.md" >/dev/null 2>&1)
r=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep -E 'implement-issue-42' | tail -1)" 2>/dev/null)
grep -q '^area: docs$' <<<"$r"; tap_check $? "area: area:docs se guarda como area: docs"

# Historial mixto: retros viejas en agentes/retros (claves y valores 0.9) y nuevas en agents/retros.
git init -q "$TMP/s"; mkdir -p "$TMP/s/.claude/skills"; cp -R "$RAIZ/.claude/skills/improve-skills" "$TMP/s/.claude/skills/"
SIG="$TMP/s/.claude/skills/improve-skills"
crear_rama() { # crear_rama <rama> <ruta> <contenido>
  blob=$(printf '%b' "$3" | git hash-object -w --stdin)
  rm -f "$TMP/s.idx"
  padre=$(git rev-parse -q --verify "refs/heads/$1" || true)
  [ -n "$padre" ] && GIT_INDEX_FILE="$TMP/s.idx" git read-tree "$padre"
  GIT_INDEX_FILE="$TMP/s.idx" git update-index --add --cacheinfo "100644,$blob,$2"
  c=$(git commit-tree "$(GIT_INDEX_FILE="$TMP/s.idx" git write-tree)" ${padre:+-p "$padre"} -m x)
  git update-ref "refs/heads/$1" "$c"
}
(cd "$TMP/s" && git commit -q --allow-empty -m base \
  && crear_rama "$RAMA_VIEJA" retros/2026-01-01-orquestar-5.md '---\nskill: orquestar\nissue: 5\nmodelo: opus\nrol: implementador\nrutas: a\nfecha: 2026-01-01\n---\nhistorial\n' \
  && crear_rama "$RAMA" retros/2026-02-01-orchestrate-6.md '---\nskill: orchestrate\nissue: 6\nmodel: opus\nrole: implementer\npaths: b\ndate: 2026-02-01\n---\nreciente\n')
s=$(cd "$TMP/s" && "$SIG/signals.sh" 2>&1)
grep -q historial <<<"$s" && grep -q reciente <<<"$s"; tap_check $? "signals.sh lee las retros de las dos ramas"
n=$(grep -c '^skill: orchestrate$' <<<"$s"); igual "$n" 2; tap_check $? "una retro vieja y una nueva cuentan como el mismo grupo (skill: orchestrate)"
n=$(grep -c '^role: implementer$' <<<"$s"); igual "$n" 2; tap_check $? "role: implementer agrupa las dos (rol: implementador es el mismo grupo)"
! grep -Eq '^(skill: orquestar|rol:|modelo:|rutas:|fecha:)' <<<"$s"; tap_check $? "signals.sh no muestra claves ni valores viejos"
grep -q '^model: opus$' <<<"$s" && grep -q '^paths: a$' <<<"$s" && grep -q '^date: 2026-01-01$' <<<"$s"; tap_check $? "signals.sh renombra las claves viejas al mostrar"
ptas=$(sed -n 's/.*consolidate up to[^:]*: \([0-9a-f]\{40\}\).*/\1/p' <<<"$s"); igual "$(wc -l <<<"$ptas" | tr -d ' ')" 2; tap_check $? "signals.sh imprime un commit para consolidar por cada rama"

# Consolidar las dos ramas: cada commit se marca en consolidated.md de la rama nueva, y signals.sh no repite lo consolidado.
viejo=$(git -C "$TMP/s" rev-parse "refs/heads/$RAMA_VIEJA"); nuevo=$(git -C "$TMP/s" rev-parse "refs/heads/$RAMA")
(cd "$TMP/s" && "$SIG/retro.sh" --consolidated "$viejo" https://example.test/pull/1 >/dev/null 2>&1); tap_check $? "--consolidated acepta un commit de la rama vieja"
(cd "$TMP/s" && "$SIG/retro.sh" --consolidated "$nuevo" https://example.test/pull/1 >/dev/null 2>&1); tap_check $? "--consolidated acepta un commit de la rama nueva"
cons=$(git -C "$TMP/s" show "$RAMA:consolidated.md" 2>/dev/null)
grep -q "^consolidated-until: $nuevo" <<<"$cons" && grep -q "^legacy-consolidated-until: $viejo" <<<"$cons"; tap_check $? "consolidated.md guarda el punto de cada rama sin pisar el otro"
git -C "$TMP/s" cat-file -e "$viejo" 2>/dev/null && igual "$(git -C "$TMP/s" rev-parse "refs/heads/$RAMA_VIEJA")" "$viejo"; tap_check $? "la rama vieja no se reescribe ni se agrega nada"
(cd "$TMP/s" && crear_rama "$RAMA_VIEJA" retros/2026-03-01-implement-issue-7.md '---\nskill: implement-issue\nissue: 7\n---\nllegoviejo\n' \
  && crear_rama "$RAMA" retros/2026-03-02-implement-issue-8.md '---\nskill: implement-issue\nissue: 8\n---\nllegonuevo\n')
s=$(cd "$TMP/s" && "$SIG/signals.sh" 2>&1)
grep -q llegoviejo <<<"$s" && grep -q llegonuevo <<<"$s" && ! grep -q historial <<<"$s" && ! grep -q reciente <<<"$s"; tap_check $? "signals.sh después de consolidar muestra solo lo posterior en las dos ramas"
# Un marcador viejo (consolidado.md con consolidado-hasta) de la rama vieja también se respeta.
git init -q "$TMP/s2"; mkdir -p "$TMP/s2/.claude/skills"; cp -R "$RAIZ/.claude/skills/improve-skills" "$TMP/s2/.claude/skills/"
(cd "$TMP/s2" && git commit -q --allow-empty -m base \
  && crear_rama "$RAMA_VIEJA" retros/2026-01-01-implement-issue-1.md '---\nskill: implement-issue\nissue: 1\n---\nanterior\n')
marca=$(git -C "$TMP/s2" rev-parse "refs/heads/$RAMA_VIEJA")
(cd "$TMP/s2" && crear_rama "$RAMA_VIEJA" consolidado.md "consolidado-hasta: $marca\npr: x\nfecha: 2026-01-02\n" \
  && crear_rama "$RAMA_VIEJA" retros/2026-01-03-implement-issue-2.md '---\nskill: implement-issue\nissue: 2\n---\nposterior\n')
s=$(cd "$TMP/s2" && "$TMP/s2/.claude/skills/improve-skills/signals.sh" 2>&1)
grep -q posterior <<<"$s" && ! grep -q anterior <<<"$s"; tap_check $? "signals.sh respeta el consolidado.md viejo de agentes/retros"
(cd "$TMP/s2" && "$TMP/s2/.claude/skills/improve-skills/retro.sh" --consolidated "$(git rev-parse "refs/heads/$RAMA_VIEJA")" https://example.test/pull/9 >/dev/null 2>&1)
s=$(cd "$TMP/s2" && "$TMP/s2/.claude/skills/improve-skills/signals.sh" 2>&1)
! grep -q 'consolidate up to: ' <<<"$s"; tap_check $? "signals.sh no ofrece consolidar ramas sin retros nuevas"

# #143: el template trae agent_sha y skill_sha; si se copia sin completar (<...>), retro.sh los reemplaza por los reales en vez de guardar el texto.
printf -- '---\nskill: implement-issue\nissue: 77\npr: 99\nmodel: sonnet\nrole: implementer\nagent_sha: <the agent_sha the orchestrator gave you>\nskill_sha: <the skill_sha the orchestrator gave you>\n---\n**Desvíos:** plantilla sin completar\n' >"$TMP/ph.md"
printf -- '---\nskill: implement-issue\nissue: 78\npr: 99\nmodel: sonnet\nrole: implementer\nagent_sha:\nskill_sha: (orchestrator value)\n---\n**Desvíos:** vacío y basura\n' >"$TMP/ph2.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/ph2.md" >/dev/null 2>&1)
c2=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'implement-issue-78\.md$')" 2>/dev/null)
grep -Eq '^agent_sha: ([0-9a-f]{40}|unknown)$' <<<"$c2" && grep -Eq '^skill_sha: ([0-9a-f]{40}|unknown)$' <<<"$c2"; tap_check $? "agent_sha vacío y skill_sha que no es un sha (texto suelto) tampoco se guardan: retro.sh pone los reales"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/ph.md" >"$TMP/ph.out" 2>&1)
c=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'implement-issue-77\.md$')" 2>/dev/null)
grep -Eq '^agent_sha: [0-9a-f]{40}$|^agent_sha: unknown$' <<<"$c" && grep -Eq '^skill_sha: [0-9a-f]{40}$|^skill_sha: unknown$' <<<"$c" && ! grep -Eq '^(agent_sha|skill_sha): <' <<<"$c"; tap_check $? "agent_sha y skill_sha sin completar (<...>) no se guardan: retro.sh pone los reales"
grep -q '^agent_sha:' "$AQUI/retro-template.md" && grep -q '^skill_sha:' "$AQUI/retro-template.md"; tap_check $? "el template de retro trae agent_sha y skill_sha"

# Un repo con objetos SHA-256: los 64 caracteres hexa que pasa el orquestador se conservan.
h64=$(printf 'a%.0s' $(seq 1 64)); h64b=$(printf 'b%.0s' $(seq 1 64))
printf -- '---\nskill: implement-issue\nissue: 79\npr: 99\nmodel: sonnet\nrole: implementer\nagent_sha: %s\nskill_sha: %s\n---\n**Desvíos:** sha-256\n' "$h64" "$h64b" >"$TMP/ph3.md"
(cd "$TMP/a" && "$AQUI/retro.sh" "$TMP/ph3.md" >/dev/null 2>&1)
c3=$(git --git-dir="$TMP/remoto.git" show "$RAMA:$(archivos | grep 'implement-issue-79\.md$')" 2>/dev/null)
grep -q "^agent_sha: $h64\$" <<<"$c3" && grep -q "^skill_sha: $h64b\$" <<<"$c3"; tap_check $? "agent_sha y skill_sha de 64 caracteres (SHA-256) se conservan"

echo
tap_done
echo "Todos los tests pasan."
