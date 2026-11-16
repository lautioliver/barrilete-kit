#!/usr/bin/env bash
# Tests de prepare.sh contra un remoto local y un gh falso (no usa GitHub).
# Uso: bash .claude/skills/implement-issue/test-prepare.sh
set -uo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
PREPARAR="$AQUI/prepare.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-prepare-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$AQUI/../../../scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
# Uso: <condición>; tap_check $? "descripción"
es() { test "$@"; }

# gh falso: issues abiertos, sin bloqueos, sin épica ni comentarios. Registra cada llamada.
mkdir -p "$TMP/bin" "$TMP/issues"
export GH_LOG="$TMP/gh.log" GH_ISSUES="$TMP/issues"
cat >"$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
  "repo view"*) echo o/r ;;
  "api user"*) if [ -n "${GH_APP:-}" ]; then echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1; fi; echo yo ;;
  api\ repos/o/r/issues/*/dependencies/*) echo '[]' ;;
  api\ repos/o/r/issues/*/parent*) exit 1 ;;
  api\ repos/o/r/issues/*/comments*) ;;
  api\ repos/o/r/issues/*) cat "$GH_ISSUES/${2##*/}.json" ;;
  "issue edit"*) if [ -n "${GH_EDIT_FALLA:-}" ]; then echo "gh falso: issue edit falla" >&2; exit 3; fi ;;
  "pr list"*) r=$(sed -E 's/.*--head ([^ ]+).*/\1/' <<<"$*"); [ -f "$GH_ISSUES/pr-${r//\//_}" ] && cat "$GH_ISSUES/pr-${r//\//_}" ;;
  *) echo "gh falso: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
# Aislado de la config de git de quien corre los tests (firma de commits, hooks globales…).
unset BK_HUMAN GH_APP   # que el entorno de quien corre los tests no cambie el resultado
out=""   # lo reasigna tap_run
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# Ningún git de la prueba corre gc ni mantenimiento automático (#224): ver scripts/agents/git-quiet.sh.
# shellcheck source=/dev/null
. "$AQUI/../../../scripts/agents/git-quiet.sh"
git_quiet_env
cfg=$(git -C "$TMP" config --list 2>/dev/null)
grep -qxF gc.auto=0 <<<"$cfg"; tap_check $? "los git de la prueba no corren gc automático"
grep -qxF maintenance.auto=false <<<"$cfg"; tap_check $? "los git de la prueba no corren mantenimiento automático"
export PATH="$TMP/bin:$PATH" BASE=main GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
issue() { # issue <n> <título>
  printf '{"state":"open","title":"%s","labels":[],"assignees":[],"html_url":"u","body":"cuerpo"}\n' "$2" >"$TMP/issues/$1.json"
}
issue 36 "Hacer algo"; issue 37 "Otra cosa"; issue 38 "Solo mirar"; issue 40 "Sin worktree"; issue 41 "Con lock"

git init -q --bare -b main "$TMP/remoto.git"
git clone -q "$TMP/remoto.git" "$TMP/proj" 2>/dev/null
(cd "$TMP/proj" && git switch -q -c main && echo base >README.md && git add README.md && git commit -qm base && git push -q origin main 2>/dev/null)
WT="$TMP/proj-wt"
asignado() { grep -q "^issue edit $1 .*--add-assignee yo\( \|$\)" "$GH_LOG"; }
worktrees() { git -C "$TMP/proj" worktree list | wc -l | tr -d ' '; }

# 1. Issue nuevo: crea el worktree y la rama, y lo asigna. El checkout principal sucio no lo frena.
echo sucio >"$TMP/proj/sucio.txt"
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 36 --worktree 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "--worktree con un issue nuevo termina bien aunque el checkout principal esté sucio"
es -d "$WT/36"; tap_check $? "crea el worktree en ../<repo>-wt/<n>"
es "$(git -C "$WT/36" branch --show-current 2>/dev/null)" = "claude/36-hacer-algo"; tap_check $? "el worktree está en la rama claude/<n>-<descripcion>"
grep -qx "Worktree: $WT/36" <<<"$s"; tap_check $? "imprime la línea 'Worktree: <ruta>'"
grep -q "^New branch: claude/36-hacer-algo (from origin/main)" <<<"$s"; tap_check $? "dice que la rama es nueva y desde dónde sale"
asignado 36; tap_check $? "asigna el issue"
es "$(git -C "$TMP/proj" branch --show-current)" = main; tap_check $? "el checkout principal sigue en su rama"
rm -f "$TMP/proj/sucio.txt"

# 2. Worktree existente: lo retoma sin crear otro.
antes=$(worktrees)
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 36 --worktree 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "--worktree con un worktree existente termina bien"
es "$(worktrees)" = "$antes"; tap_check $? "no crea otro worktree"
grep -q "^Existing branch: claude/36-hacer-algo (resuming)" <<<"$s"; tap_check $? "dice que retoma la rama"
grep -qx "Worktree: $WT/36" <<<"$s"; tap_check $? "imprime la misma ruta al retomar"

# 2b. El árbol limpio se valida sobre el worktree.
{ echo x >"$WT/36/pendiente.txt"; } 2>/dev/null
c=0; (trap - ERR; cd "$TMP/proj" && "$PREPARAR" 36 --worktree >/dev/null 2>&1) || c=$?; tap_status "$c" 1
es "$c" -ne 0; tap_check $? "falla si el worktree tiene cambios sin commitear"
rm -f "$WT/36/pendiente.txt"

# 3. Rama en uso en otro worktree: falla con mensaje claro y no asigna.
git -C "$TMP/proj" worktree add -q -b claude/37-otra-cosa "$TMP/otro" origin/main 2>/dev/null
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 37 --worktree 2>&1) || c=$?; tap_status "$c" 1
es "$c" -ne 0; tap_check $? "falla si la rama está en otro worktree"
grep -q "another worktree.*$TMP/otro" <<<"$s"; tap_check $? "el mensaje dice en qué worktree está la rama"
! asignado 37; tap_check $? "no asigna si la rama está en otro worktree"
! [ -e "$WT/37" ]; tap_check $? "no crea el worktree si la rama está en otro"

# 4. --review no crea nada, en cualquier orden con --worktree.
for args in "--review --worktree" "--worktree --review"; do
  c=0
  # shellcheck disable=SC2086  # se separan a propósito
  s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 38 $args 2>&1) || c=$?; tap_status "$c" 0
  tap_check $c "<args> termina bien" "$args termina bien"
  ! [ -e "$WT/38" ] && ! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/38-solo-mirar; tap_check $? "<args> no crea worktree ni rama" "$args no crea worktree ni rama"
  grep -q "$WT/38" <<<"$s"; tap_check $? "<args> muestra el worktree propuesto" "$args muestra el worktree propuesto"
done
! asignado 38; tap_check $? "--review no asigna"

# 5. Sin --worktree, como hoy: cambia la rama del checkout principal y no crea worktrees.
antes=$(worktrees)
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 40 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "sin --worktree termina bien"
es "$(git -C "$TMP/proj" branch --show-current)" = claude/40-sin-worktree; tap_check $? "sin --worktree cambia la rama del checkout principal"
[ "$(worktrees)" = "$antes" ] && ! grep -q '^Worktree:' <<<"$s"; tap_check $? "sin --worktree no crea ni menciona worktrees"
tail -2 <<<"$s" | head -1 | grep -qx "New branch: claude/40-sin-worktree (from origin/main)"; tap_check $? "sin --worktree la salida termina como hoy"
git -C "$TMP/proj" switch -q main
echo sucio >"$TMP/proj/sucio.txt"
c=0; (trap - ERR; cd "$TMP/proj" && "$PREPARAR" 41 >/dev/null 2>&1) || c=$?; tap_status "$c" 1
[ "$c" -ne 0 ] && ! asignado 41; tap_check $? "sin --worktree, el checkout principal sucio sigue frenando"
rm -f "$TMP/proj/sucio.txt"

# 6. git fetch se reintenta si falla por un lock de .git.
cat >"$TMP/bin/git" <<SH
#!/usr/bin/env bash
if [ "\$1" = fetch ] && [ ! -e "$TMP/lock-ya" ]; then
  touch "$TMP/lock-ya"
  echo "fatal: Unable to create '$TMP/proj/.git/shallow.lock': File exists." >&2; exit 128
fi
exec $(command -v git) "\$@"
SH
chmod +x "$TMP/bin/git"
c=0; (trap - ERR; cd "$TMP/proj" && "$PREPARAR" 41 --worktree >/dev/null 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "reintenta git fetch si falla por un lock"
rm -f "$TMP/bin/git"

# 7. Hallazgos de /code-review.
issue 42 "Huerfano"; issue 43 "Desde worktree"; issue 44 "Sin fetch"
(cd "$TMP/proj" && "$PREPARAR" 42 --worktree >/dev/null 2>&1)
rm -rf "$WT/42"
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 42 --worktree 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "retoma aunque la carpeta del worktree se haya borrado a mano"
es -d "$WT/42"; tap_check $? "vuelve a crear la carpeta del worktree borrado"

c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 36 2>&1) || c=$?; tap_status "$c" 1
es "$c" -ne 0; tap_check $? "sin --worktree falla si la rama está en un worktree"
grep -q "another worktree" <<<"$s"; tap_check $? "sin --worktree dice en qué worktree está la rama"
es "$(grep -c "^issue edit 36 " "$GH_LOG")" -eq 2; tap_check $? "sin --worktree no asigna si la rama está en un worktree"

c=0; s=$(trap - ERR; cd "$WT/36" && "$PREPARAR" 43 --worktree 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "--worktree funciona corriendo desde otro worktree"
grep -qx "Worktree: $WT/43" <<<"$s"; tap_check $? "desde otro worktree, el nuevo va al lado del checkout principal"

c=0; (trap - ERR; cd "$TMP/proj" && "$PREPARAR" ../44 --worktree >/dev/null 2>&1) || c=$?; tap_status "$c" 64
es "$c" -eq 64 && ! grep -q 'issues/\.\.' "$GH_LOG"; tap_check $? "rechaza un número de issue inválido sin llamar a gh"

git -C "$TMP/proj" remote set-url origin "$TMP/no-existe.git"
c=0; (trap - ERR; cd "$TMP/proj" && "$PREPARAR" 44 --worktree >/dev/null 2>&1) || c=$?; tap_status "$c" 1
es "$c" -ne 0 && ! asignado 44; tap_check $? "con --worktree no asigna si no pudo crear el worktree"
git -C "$TMP/proj" remote set-url origin "$TMP/remoto.git"

# 8. Hallazgos de la revisión del PR #40.
issue 45 "Con config bloqueada"; issue 46 "Worktree bloqueado"
touch "$TMP/proj/.git/config.lock"
c=0; (trap - ERR; cd "$TMP/proj" && "$PREPARAR" 45 --worktree >/dev/null 2>&1) || c=$?; tap_status "$c" 0
rm -f "$TMP/proj/.git/config.lock"
tap_check $c "--worktree no necesita escribir .git/config (otro agente puede tenerlo bloqueado)"

git -C "$TMP/proj" worktree add -q -b claude/46-worktree-bloqueado "$TMP/bloqueado" origin/main 2>/dev/null
git -C "$TMP/proj" worktree lock "$TMP/bloqueado"; rm -rf "$TMP/bloqueado"
for args in "--worktree" ""; do
  # shellcheck disable=SC2086  # vacío a propósito
  c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 46 $args 2>&1) || c=$?; tap_status "$c" 1
  es "$c" -eq 1 && grep -q "CANNOT TAKE #46: .*locked" <<<"$s"; tap_check $? "<args>: un worktree bloqueado y sin carpeta da un error claro" "${args:-sin --worktree}: un worktree bloqueado y sin carpeta da un error claro"
done
! asignado 46; tap_check $? "no asigna si la rama está en un worktree bloqueado sin carpeta"

# 9. #41: se retoma la rama del issue aunque el título se haya editado.
issue 50 "Titulo viejo"
(cd "$TMP/proj" && "$PREPARAR" 50 >/dev/null 2>&1 && git commit -q --allow-empty -m trabajo && git switch -q main)
issue 50 "Titulo nuevo"
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 50 2>&1) || c=$?; tap_status "$c" 0
es "$c" -eq 0 && es "$(git -C "$TMP/proj" branch --show-current)" = claude/50-titulo-viejo \
  && ! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/50-titulo-nuevo && grep -q "^Existing branch: claude/50-titulo-viejo" <<<"$s"
tap_check $? "sin --worktree, con el título editado, retoma la rama existente y no crea otra"
git -C "$TMP/proj" switch -q main

issue 51 "Antes"
(cd "$TMP/proj" && "$PREPARAR" 51 --worktree >/dev/null 2>&1)
issue 51 "Despues"
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 51 --worktree 2>&1) || c=$?; tap_status "$c" 0
es "$c" -eq 0 && grep -qx "Worktree: $WT/51" <<<"$s" && es "$(git -C "$WT/51" branch --show-current)" = claude/51-antes
tap_check $? "con --worktree, con el título editado, retoma el worktree existente"

issue 52 "Dos ramas"
git -C "$TMP/proj" branch claude/52-una main; git -C "$TMP/proj" branch claude/52-otra main
for args in "--worktree" ""; do
  # shellcheck disable=SC2086  # vacío a propósito
  c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 52 $args 2>&1) || c=$?; tap_status "$c" 1
  es "$c" -eq 1 && grep -q "claude/52-una" <<<"$s" && grep -q "claude/52-otra" <<<"$s"
  tap_check $? "<args>: con dos ramas claude/<n>-*, falla y las lista" "${args:-sin --worktree}: con dos ramas claude/<n>-*, falla y las lista"
done
! asignado 52; tap_check $? "con dos ramas del issue no asigna"

issue 53 "Titulo distinto"
git clone -q "$TMP/remoto.git" "$TMP/otro-clon" 2>/dev/null
(cd "$TMP/otro-clon" && git switch -q -c claude/53-remota origin/main && git commit -q --allow-empty -m remota \
  && git push -q origin claude/53-remota && git switch -q -c claude/530-otra origin/main && git push -q origin claude/530-otra) 2>/dev/null
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 53 --worktree 2>&1) || c=$?; tap_status "$c" 0
es "$c" -eq 0 && es "$(git -C "$WT/53" branch --show-current)" = claude/53-remota \
  && es "$(git -C "$WT/53" log -1 --format=%s)" = remota
tap_check $? "una rama claude/<n>-* que solo está en origin se retoma (y claude/<n>0-* no cuenta)"

# 10. Hallazgos de /code-review de #41.
issue 54 "Solo remota sin worktree"
(cd "$TMP/otro-clon" && git switch -q -c claude/54-remota origin/main && git commit -q --allow-empty -m r54 \
  && git push -q origin claude/54-remota) 2>/dev/null
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 54 2>&1) || c=$?; tap_status "$c" 0
es "$c" -eq 0 && es "$(git -C "$TMP/proj" branch --show-current)" = claude/54-remota && es "$(git -C "$TMP/proj" log -1 --format=%s)" = r54
tap_check $? "sin --worktree, una rama que solo está en origin se retoma"
git -C "$TMP/proj" switch -q main

issue 55 "Reabierto"
(cd "$TMP/otro-clon" && git switch -q -c claude/55-vieja origin/main && git push -q origin claude/55-vieja) 2>/dev/null
echo MERGED >"$TMP/issues/pr-claude_55-vieja"
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 55 --worktree 2>&1) || c=$?; tap_status "$c" 0
es "$c" -eq 0 && es "$(git -C "$WT/55" branch --show-current)" = claude/55-reabierto
tap_check $? "una rama cuyo PR ya se mergeó o cerró no se retoma: el issue reabierto arranca una nueva"

issue 56 "Sin remoto"
git -C "$TMP/proj" remote set-url origin "$TMP/no-existe.git"
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" 56 2>&1) || c=$?; tap_status "$c" 1
git -C "$TMP/proj" remote set-url origin "$TMP/remoto.git"
es "$c" -ne 0 && ! asignado 56 && ! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/56-sin-remoto
tap_check $? "si no puede consultar las ramas de origin, falla sin asignar ni crear una rama nueva"

# Plantilla sin inicializar (BASE=<BASE_BRANCH>) y sin BASE: usa la rama por defecto del remoto y avisa.
# Después del init la base ya está configurada (puede ser develop, que este remoto no tiene) y estos
# casos no aplican. El init reemplaza el primer marcador; el segundo está partido para que no lo toque.
# shellcheck disable=SC2050  # constante hasta que el init la cambia
if [ "<BASE_BRANCH>" = "<BASE_""BRANCH>" ]; then
  issue 47 "Sin base"
  git -C "$TMP/remoto.git" symbolic-ref HEAD refs/heads/main
  git -C "$TMP/proj" remote set-head origin -d 2>/dev/null
  c=0; s=$(trap - ERR; cd "$TMP/proj" && env -u BASE "$PREPARAR" 47 --worktree 2>&1) || c=$?; tap_status "$c" 0
  tap_check $c "sin BASE, en la plantilla sin inicializar, toma el issue igual"
  grep -q "^New branch: claude/47-sin-base (from origin/main)" <<<"$s"; tap_check $? "sin BASE usa la rama por defecto del remoto"
  grep -qi "warning.*main" <<<"$s"; tap_check $? "sin BASE avisa qué base usó"
fi

# --help explica --worktree (salió de implement-issue/SKILL.md) sin tocar GitHub ni el repo.
: >"$GH_LOG"
c=0; s=$(trap - ERR; cd "$TMP/proj" && "$PREPARAR" --help 2>&1) || c=$?; tap_status "$c" 0
tap_check $c "--help termina bien"
grep -q "git worktree remove" <<<"$s" && grep -q "fails without assigning" <<<"$s" && grep -q "git -C" <<<"$s"; tap_check $? "--help explica cómo trabajar en el worktree"
! [ -s "$GH_LOG" ]; tap_check $? "--help no llama a gh"

# BK_HUMAN (#231): quien lanzó al agente es la persona responsable, aunque el token sea de otra identidad.
issue 60 "Con persona responsable"
cd "$TMP/proj" || exit 2
export BK_HUMAN=lautioliver
tap_run out 0 "$PREPARAR" 60 --worktree
tap_check $? "BK_HUMAN: toma el issue con la persona definida"
grep -q "^issue edit 60 .*--add-assignee lautioliver\( \|$\)" "$GH_LOG"; tap_check $? "BK_HUMAN: asigna el issue a esa persona y no a @me"
grep -qx "Assigned to @lautioliver." <<<"$out"; tap_check $? "BK_HUMAN: dice a quién asignó"
unset BK_HUMAN


# Token de GitHub App (gh api user da 403), con y sin BK_HUMAN.
issue 61 "App con persona"; issue 62 "App sin persona"; issue 63 "Ya es de la persona"
printf '{"state":"open","title":"Ya es de la persona","labels":[],"assignees":[{"login":"lautioliver"}],"html_url":"u","body":"b"}\n' >"$TMP/issues/63.json"
export GH_APP=1 BK_HUMAN=lautioliver
tap_run out 0 "$PREPARAR" 61 --worktree
tap_check $? "token de App con BK_HUMAN: toma el issue"
grep -q "^issue edit 61 .*--add-assignee lautioliver\( \|$\)" "$GH_LOG"; tap_check $? "token de App con BK_HUMAN: asigna a la persona"
tap_run out 0 "$PREPARAR" 63 --worktree
tap_check $? "un issue asignado a BK_HUMAN no se ve como de otro"
unset BK_HUMAN
c=0; s=$(trap - ERR; "$PREPARAR" 62 --worktree 2>&1) || c=$?; tap_status "$c" 64
grep -q "BK_HUMAN" <<<"$s"; tap_check $? "token de App sin BK_HUMAN: el mensaje nombra la variable que falta"
grep -q "Resource not accessible" <<<"$s"; tap_check $? "token de App sin BK_HUMAN: muestra el error de gh junto al mensaje"
! grep -q "^issue edit 62" "$GH_LOG"; tap_check $? "token de App sin BK_HUMAN: no asigna"
! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/62-app-sin-persona; tap_check $? "token de App sin BK_HUMAN: no crea la rama"
unset GH_APP
tap_run out 0 "$PREPARAR" 62 --worktree
tap_check $? "token de usuario sin BK_HUMAN: se comporta como siempre"
grep -qx "Assigned to @yo." <<<"$out"; tap_check $? "token de usuario sin BK_HUMAN: asigna al usuario del token"

# BK_HUMAN normalizado (#231, review de #234): sin @ inicial y en minúsculas, como los logins de GitHub.
issue 64 "Persona con arroba y mayusculas"
: >"$GH_LOG"
export BK_HUMAN=@LautiOliver
tap_run out 0 "$PREPARAR" 64 --worktree
tap_check $? "BK_HUMAN con @ y mayúsculas: toma el issue"
grep -q "^issue edit 64 .*--add-assignee lautioliver\( \|$\)" "$GH_LOG"; tap_check $? "BK_HUMAN con @ y mayúsculas: asigna el login normalizado"
grep -qx "Assigned to @lautioliver." <<<"$out"; tap_check $? "BK_HUMAN con @ y mayúsculas: dice el login normalizado"
unset BK_HUMAN

# --help documenta BK_HUMAN.
tap_run out 0 "$PREPARAR" --help
grep -q "BK_HUMAN" <<<"$out"; tap_check $? "--help documenta BK_HUMAN"

# Un issue asignado a lautioliver lo toma BK_HUMAN=@LautiOliver (no se ve como de otro).
issue 65 "Ya es de la persona con arroba"
printf '{"state":"open","title":"Ya es de la persona con arroba","labels":[],"assignees":[{"login":"lautioliver"}],"html_url":"u","body":"b"}\n' >"$TMP/issues/65.json"
export BK_HUMAN=@LautiOliver
tap_run out 0 "$PREPARAR" 65 --worktree
tap_check $? "BK_HUMAN con @ y mayúsculas: un issue de esa persona no se ve como de otro"
unset BK_HUMAN

# BK_HUMAN que no es un login válido: corta con 64 antes de tocar nada.
issue 66 "Persona invalida"
export BK_HUMAN=@
c=0; s=$(trap - ERR; "$PREPARAR" 66 --worktree 2>&1) || c=$?; tap_status "$c" 64
grep -q "not a valid GitHub login" <<<"$s"; tap_check $? "BK_HUMAN inválido: dice que no es un login"
! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/66-persona-invalida; tap_check $? "BK_HUMAN inválido: no crea la rama"
unset BK_HUMAN

# #267: --worktree toma un candado en el directorio git del worktree (worktree-lock.sh) y retoma el de un dueño muerto.
issue 70 "Con candado"
sleep 300 &
DUENIO=$!
sleep 0 &
MUERTO=$!
wait "$MUERTO"
tap_at_exit "kill $DUENIO 2>/dev/null; rm -rf \"\$TMP\""
export WORKTREE_LOCK_PID=$DUENIO WORKTREE_LOCK_AGENT=agente-prepare
tap_run out 0 "$PREPARAR" 70 --worktree
GD=$(git -C "$WT/70" rev-parse --absolute-git-dir 2>/dev/null)
es -f "$GD/agent-lock"; tap_check $? "--worktree escribe el candado del worktree"
lk=""; if [ -f "$GD/agent-lock" ]; then lk=$(cat "$GD/agent-lock"); fi
grep -qx "pid=$DUENIO" <<<"$lk"; tap_check $? "el candado guarda el pid del agente que lo tomó"
grep -qx "agent=agente-prepare" <<<"$lk"; tap_check $? "el candado guarda el nombre del agente"
n=$(git -C "$WT/70" status --porcelain | wc -l | tr -d ' ')
es "$n" = 0; tap_check $? "el candado no ensucia el worktree"
printf 'pid=%s\nstart=Thu Jan  1 00:00:00 1970\nagent=agente-viejo\nsince=2026-01-01T00:00:00Z\n' "$MUERTO" >"$GD/agent-lock"
tap_run out 0 "$PREPARAR" 70 --worktree
lk=""; if [ -f "$GD/agent-lock" ]; then lk=$(cat "$GD/agent-lock"); fi
grep -qx "agent=agente-prepare" <<<"$lk"; tap_check $? "con un candado de un dueño muerto, retoma el worktree y lo reemplaza"
unset WORKTREE_LOCK_PID WORKTREE_LOCK_AGENT

# Otro agente vivo tiene el worktree: prepare.sh se niega, dice quién lo tiene y no pisa el candado.
printf 'pid=%s\nstart=%s\nagent=agente-ajeno\nsince=2026-01-01T00:00:00Z\n' "$DUENIO" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$DUENIO" | sed 's/^ *//; s/ *$//')" >"$GD/agent-lock"
export WORKTREE_LOCK_PID=$$ WORKTREE_LOCK_AGENT=agente-intruso
c=0; s=$(trap - ERR; "$PREPARAR" 70 --worktree 2>&1) || c=$?; tap_status "$c" 1
es "$c" -ne 0; tap_check $? "un worktree con dueño vivo ajeno: prepare.sh se niega"
grep -q "in use.*agente-ajeno" <<<"$s"; tap_check $? "el mensaje dice que el worktree está en uso y por quién"
lk=$(cat "$GD/agent-lock")
grep -qx "agent=agente-ajeno" <<<"$lk"; tap_check $? "el candado del dueño vivo no se pisa"
unset WORKTREE_LOCK_PID WORKTREE_LOCK_AGENT

# Si prepare.sh falla después de tomar el candado (acá, al asignar), lo suelta: el worktree no queda tomado
# por un agente que no arrancó. Un candado que ya era suyo antes de correrlo (lo renovó) no se suelta.
issue 71 "Falla al asignar"
export WORKTREE_LOCK_PID=$DUENIO WORKTREE_LOCK_AGENT=agente-falla GH_EDIT_FALLA=1
tap_run out 3 "$PREPARAR" 71 --worktree
GD71=$(git -C "$WT/71" rev-parse --absolute-git-dir 2>/dev/null)
es -n "$GD71"; tap_check $? "falla al asignar: el worktree quedó creado"
es ! -e "$GD71/agent-lock"; tap_check $? "falla después de tomar el candado: prepare.sh lo suelta"
printf 'pid=%s\nstart=%s\nagent=agente-falla\nsince=2026-01-01T00:00:00Z\n' "$DUENIO" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$DUENIO" | sed 's/^ *//; s/ *$//')" >"$GD71/agent-lock"
tap_run out 3 "$PREPARAR" 71 --worktree
es -f "$GD71/agent-lock"; tap_check $? "falla con un candado que ya era suyo: no lo suelta"
unset WORKTREE_LOCK_PID WORKTREE_LOCK_AGENT GH_EDIT_FALLA

# #330: ramas claude/<type>/<n>-<desc> con "agent_branch_type" (o AGENT_BRANCH_TYPE), --name y los dos formatos.
# Corre en "$TMP/proj" (el cd de arriba): cada prepare.sh va por tap_run, y lo que se compara es su salida.
issue_t() { # issue_t <n> <título> <label>
  printf '{"state":"open","title":"%s","labels":[{"name":"%s"}],"assignees":[],"html_url":"u","body":"cuerpo"}\n' "$2" "$3" >"$TMP/issues/$1.json"
}
rama_de() { sed -n 's/^New branch: \([^ ]*\).*/\1/p; s/^Existing branch: \([^ ]*\).*/\1/p; s/.*Proposed branch: \([^,)]*\).*/\1/p' <<<"$1" | head -1; }
issue_t 80 "Show past events of the org that finished" "type:bug"; issue_t 81 "Audit checkout: order detail says delivered" "type:audit"
issue_t 82 "Add the back side to the ticket design" "type:feature"; issue 83 "Make something"
issue_t 84 "Share error texts between the panel and the app" "type:task"
issue_t 85 "Rename every agent branch to carry its type before merging anything" "type:docs"
tap_run out 0 "$PREPARAR" 82 --review
es "$(rama_de "$out")" = "claude/82-add-the-back-side-to-the-ticket-design"; tap_check $? "sin la opción, la rama no lleva el tipo ni se poda (como siempre)"
export AGENT_BRANCH_TYPE=1
tap_run out 0 "$PREPARAR" 80 --review
es "$(rama_de "$out")" = "claude/fix/80-show-past-events-org-finished"; tap_check $? "con la opción, type:bug va como fix/ y conserva el verbo (puede ser el síntoma), sin relleno"
tap_run out 0 "$PREPARAR" 81 --review
es "$(rama_de "$out")" = "claude/audit/81-order-detail-says-delivered"; tap_check $? "una auditoría saca el prefijo 'Audit <área>:'"
tap_run out 0 "$PREPARAR" 82 --review
es "$(rama_de "$out")" = "claude/feat/82-back-side-ticket-design"; tap_check $? "type:feature va como feat/, sin el verbo inicial ni relleno"
tap_run out 0 "$PREPARAR" 83 --review
es "$(rama_de "$out")" = "claude/83-something"; tap_check $? "un issue sin type: no lleva tipo"
tap_run out 0 "$PREPARAR" 84 --review
es "$(rama_de "$out")" = "claude/chore/84-error-texts-panel-app"; tap_check $? "type:task va como chore/; 'between' y 'the' son relleno"
tap_run out 0 "$PREPARAR" 85 --review
es "$(rama_de "$out")" = "claude/docs/85-every-agent-branch-carry-its"; tap_check $? "la descripción llega a 30 caracteres sin cortar palabras"
export AGENT_BRANCH_TYPE=0
tap_run out 0 "$PREPARAR" 82 --review
es "$(rama_de "$out")" = "claude/82-add-the-back-side-to-the-ticket-design"; tap_check $? "AGENT_BRANCH_TYPE=0 apaga la opción"
unset AGENT_BRANCH_TYPE
# Desde .agent-kit.json, con el idioma de la instalación.
issue_t 86 "Mostrar error 409: idempotency en checkout" "type:feature"; issue_t 87 "PR 1 mergeado" "type:feature"
printf '{"language": "es", "agent_branch_type": true}\n' >"$TMP/proj/.agent-kit.json"
tap_run out 0 "$PREPARAR" 86 --review
es "$(rama_de "$out")" = "claude/feat/86-error-409-idempotency-checkout"; tap_check $? "con agent_branch_type en .agent-kit.json y language es, saca el verbo y el relleno en español"
tap_run out 0 "$PREPARAR" 87 --review
es "$(rama_de "$out")" = "claude/feat/87-pr-1-mergeado"; tap_check $? "en español solo saca la primera palabra si es un verbo (-ar/-er/-ir)"
printf '{"language": "es"}\n' >"$TMP/proj/.agent-kit.json"
tap_run out 0 "$PREPARAR" 87 --review
es "$(rama_de "$out")" = "claude/87-pr-1-mergeado"; tap_check $? "sin agent_branch_type en .agent-kit.json, la rama no lleva el tipo"
rm -f "$TMP/proj/.agent-kit.json"
# Una rama del issue en cualquier formato se retoma, con la opción o sin ella.
export AGENT_BRANCH_TYPE=1
issue_t 89 "Old branch" "type:bug"; git -C "$TMP/proj" branch claude/89-vieja main
tap_run out 0 "$PREPARAR" 89 --review
es "$(rama_de "$out")" = "claude/89-vieja"; tap_check $? "con la opción, retoma una rama del issue en el formato claude/<n>-…"
unset AGENT_BRANCH_TYPE
issue 90 "Typed branch"; git -C "$TMP/proj" branch claude/fix/90-con-tipo main
tap_run out 0 "$PREPARAR" 90 --review
es "$(rama_de "$out")" = "claude/fix/90-con-tipo"; tap_check $? "sin la opción, retoma una rama del issue en el formato claude/<type>/<n>-…"
git -C "$TMP/otro-clon" switch -q -c claude/feat/92-remota origin/main
git -C "$TMP/otro-clon" commit -q --allow-empty -m r92
git -C "$TMP/otro-clon" push -q origin claude/feat/92-remota 2>/dev/null
issue 92 "Remote typed"
tap_run out 0 "$PREPARAR" 92 --review
es "$(rama_de "$out")" = "claude/feat/92-remota"; tap_check $? "encuentra en origin una rama claude/<type>/<n>-…"
git -C "$TMP/proj" branch claude/fix/920-otra main
tap_run out 0 "$PREPARAR" 92 --review
es "$(rama_de "$out")" = "claude/feat/92-remota"; tap_check $? "claude/<type>/<n>0-… no es del issue <n>"
# --name: otra rama para el issue (el PR 2), aunque tenga una.
issue 91 "Two formats"; git -C "$TMP/proj" branch claude/91-una main
# Con una rama en cada formato no sabe cuál retomar (sale con 1, como cualquier otro "CANNOT TAKE").
git -C "$TMP/proj" branch claude/feat/91-otra main
c=0; s=$(trap - ERR; "$PREPARAR" 91 --worktree 2>&1) || c=$?; tap_status "$c" 1
grep -q "claude/91-una" <<<"$s"; tap_check $? "con una rama en cada formato, falla y nombra la de claude/<n>-…"
grep -q "claude/feat/91-otra" <<<"$s"; tap_check $? "con una rama en cada formato, nombra la de claude/<type>/<n>-…"
! asignado 91; tap_check $? "con una rama en cada formato, no asigna"
tap_run out 0 "$PREPARAR" 91 --worktree --name "Segunda parte"
es "$TAP_RC" -eq 0; tap_check $? "--name crea su rama aunque el issue tenga otra"
wl=""   # lo reasigna tap_run
tap_run wl 0 git -C "$TMP/proj" worktree list --porcelain
grep -qx "worktree $WT/91-segunda-parte" <<<"$wl"; tap_check $? "--name pone su worktree en ../<repo>-wt/<n>-<desc>"
grep -qx "branch refs/heads/claude/91-segunda-parte" <<<"$wl"; tap_check $? "--name nombra la rama claude/<n>-<desc>"
export AGENT_BRANCH_TYPE=1
tap_run out 0 "$PREPARAR" 80 --review --name=segunda
es "$(rama_de "$out")" = "claude/fix/80-segunda"; tap_check $? "--name=<desc> con la opción lleva el tipo y no poda la descripción"
unset AGENT_BRANCH_TYPE
issue 93 "Con worktree"
tap_run out 0 "$PREPARAR" 93 --worktree
tap_run out 0 "$PREPARAR" 93 --worktree --name "con worktree"
es "$TAP_RC" -eq 0; tap_check $? "--worktree --name con la rama ya en ../<repo>-wt/<n> termina bien"
grep -qx "Worktree: $WT/93" <<<"$out"; tap_check $? "--worktree --name con la rama que ya está en ../<repo>-wt/<n> la retoma ahí"
es ! -e "$WT/93-con-worktree"; tap_check $? "--worktree --name con la rama ya en ../<repo>-wt/<n> no crea otro worktree"
tap_run out 64 "$PREPARAR" 80 --name
es "$TAP_RC" -eq 64; tap_check $? "--name sin valor: uso inválido (64)"
tap_run out 64 "$PREPARAR" 80 --name --worktree
es "$TAP_RC" -eq 64; tap_check $? "--name seguido de otra opción: uso inválido (64)"
tap_run out 64 "$PREPARAR" 80 --name '!!!'
es "$TAP_RC" -eq 64; tap_check $? "--name sin letras ni números: uso inválido (64)"

# Los lectores reconocen el issue de claude/<type>/<n>-… y de claude/<n>-…, con la misma regla (la de flow.py).
# El perfil chico borra project-status, checks/ y labeler.yml, y su labels.yml no lee la rama (profiles/small/DELETE):
# se chequean los que están.
RAIZ="$AQUI/../../.."
DISP="$RAIZ/.claude/skills/project-status/available.sh"
F=$(sed -n 's/^RAMA_RE = re.compile(r"\(.*\)").*/\1/p' "$RAIZ/scripts/agents/flow.py")
n=$(python3 -c 'import re,sys; m=re.match(sys.argv[1], "claude/audit/64-x"); print(m.group(1) if m else "")' "$F"); es "$n" = 64; tap_check $? "flow.py lee el issue de claude/<type>/<n>-…"
if grep -q "pr.head.ref" "$RAIZ/.github/workflows/labels.yml"; then
  J=$(sed -n 's|.*const rama = pr.head.ref.match(/\(.*\)/);.*|\1|p' "$RAIZ/.github/workflows/labels.yml" | sed 's|\\/|/|g')
  es "$J" = "$F"; tap_check $? "labels.yml lee el issue de la rama con la regla de flow.py"
fi
if [ -e "$RAIZ/scripts/agents/checks/pr-metadata" ]; then
  P=$(sed -n 's/^BRANCH_ISSUE = re.compile(r"\(.*\)").*/\1/p' "$RAIZ/scripts/agents/checks/pr-metadata")
  es "$P" = "$F"; tap_check $? "pr-metadata lee el issue de la rama con la regla de flow.py"
fi
if [ -e "$DISP" ]; then
  A=$(sed -n 's/.*capture("\(.*\)")?.*/\1/p' "$DISP" | sed 's/(?<n>/(/; s/\[0-9\]/\\d/')
  es "$A" = "$F"; tap_check $? "available.sh lee el issue de la rama con la regla de flow.py"
  MAPEO=$(awk "/^MAPEO='/{f=1; sub(/^MAPEO='/, \"\"); print; next} f && /^ *\| group_by/{sub(/'\$/, \"\"); print; exit} f" "$DISP")
  m=$(jq -c "$MAPEO" <<<'[{"number":1,"headRefName":"claude/fix/60-x","body":"","closingIssuesReferences":[]},{"number":2,"headRefName":"claude/61-x","body":"","closingIssuesReferences":[]},{"number":3,"headRefName":"feat/62-x","body":"","closingIssuesReferences":[]},{"number":4,"headRefName":"claude/fix/x-63","body":"","closingIssuesReferences":[]}]')
  es "$m" = '{"60":[1],"61":[2],"62":[3]}'; tap_check $? "available.sh lee el issue de claude/<type>/<n>-…, claude/<n>-… y <type>/<n>-…"
fi
if [ -e "$RAIZ/.github/labeler.yml" ]; then
  [ "$(grep -cE "'\^claude/(feat|fix)/'" "$RAIZ/.github/labeler.yml")" = 2 ]; tap_check $? "labeler.yml pone el tipo de claude/<type>/…"
fi

tap_done
