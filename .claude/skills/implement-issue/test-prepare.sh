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
  "api user"*) echo yo ;;
  api\ repos/o/r/issues/*/dependencies/*) echo '[]' ;;
  api\ repos/o/r/issues/*/parent*) exit 1 ;;
  api\ repos/o/r/issues/*/comments*) ;;
  api\ repos/o/r/issues/*) cat "$GH_ISSUES/${2##*/}.json" ;;
  "issue edit"*) ;;
  "pr list"*) r=$(sed -E 's/.*--head ([^ ]+).*/\1/' <<<"$*"); [ -f "$GH_ISSUES/pr-${r//\//_}" ] && cat "$GH_ISSUES/pr-${r//\//_}" ;;
  *) echo "gh falso: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
# Aislado de la config de git de quien corre los tests (firma de commits, hooks globales…).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export PATH="$TMP/bin:$PATH" BASE=main GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
issue() { # issue <n> <título>
  printf '{"state":"open","title":"%s","labels":[],"assignees":[],"html_url":"u","body":"cuerpo"}\n' "$2" >"$TMP/issues/$1.json"
}
issue 36 "Hacer algo"; issue 37 "Otra cosa"; issue 38 "Solo mirar"; issue 40 "Sin worktree"; issue 41 "Con lock"

git init -q --bare -b main "$TMP/remoto.git"
git clone -q "$TMP/remoto.git" "$TMP/proj" 2>/dev/null
(cd "$TMP/proj" && git switch -q -c main && echo base >README.md && git add README.md && git commit -qm base && git push -q origin main 2>/dev/null)
WT="$TMP/proj-wt"
asignado() { grep -q "^issue edit $1 .*--add-assignee @me" "$GH_LOG"; }
worktrees() { git -C "$TMP/proj" worktree list | wc -l | tr -d ' '; }

# 1. Issue nuevo: crea el worktree y la rama, y lo asigna. El checkout principal sucio no lo frena.
echo sucio >"$TMP/proj/sucio.txt"
s=$(cd "$TMP/proj" && "$PREPARAR" 36 --worktree 2>&1); c=$?
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
s=$(cd "$TMP/proj" && "$PREPARAR" 36 --worktree 2>&1); c=$?
tap_check $c "--worktree con un worktree existente termina bien"
es "$(worktrees)" = "$antes"; tap_check $? "no crea otro worktree"
grep -q "^Existing branch: claude/36-hacer-algo (resuming)" <<<"$s"; tap_check $? "dice que retoma la rama"
grep -qx "Worktree: $WT/36" <<<"$s"; tap_check $? "imprime la misma ruta al retomar"

# 2b. El árbol limpio se valida sobre el worktree.
{ echo x >"$WT/36/pendiente.txt"; } 2>/dev/null
(cd "$TMP/proj" && "$PREPARAR" 36 --worktree >/dev/null 2>&1); c=$?
es "$c" -ne 0; tap_check $? "falla si el worktree tiene cambios sin commitear"
rm -f "$WT/36/pendiente.txt"

# 3. Rama en uso en otro worktree: falla con mensaje claro y no asigna.
git -C "$TMP/proj" worktree add -q -b claude/37-otra-cosa "$TMP/otro" origin/main 2>/dev/null
s=$(cd "$TMP/proj" && "$PREPARAR" 37 --worktree 2>&1); c=$?
es "$c" -ne 0; tap_check $? "falla si la rama está en otro worktree"
grep -q "another worktree.*$TMP/otro" <<<"$s"; tap_check $? "el mensaje dice en qué worktree está la rama"
! asignado 37; tap_check $? "no asigna si la rama está en otro worktree"
! [ -e "$WT/37" ]; tap_check $? "no crea el worktree si la rama está en otro"

# 4. --review no crea nada, en cualquier orden con --worktree.
for args in "--review --worktree" "--worktree --review"; do
  # shellcheck disable=SC2086  # se separan a propósito
  s=$(cd "$TMP/proj" && "$PREPARAR" 38 $args 2>&1); c=$?
  tap_check $c "<args> termina bien" "$args termina bien"
  ! [ -e "$WT/38" ] && ! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/38-solo-mirar; tap_check $? "<args> no crea worktree ni rama" "$args no crea worktree ni rama"
  grep -q "$WT/38" <<<"$s"; tap_check $? "<args> muestra el worktree propuesto" "$args muestra el worktree propuesto"
done
! asignado 38; tap_check $? "--review no asigna"

# 5. Sin --worktree, como hoy: cambia la rama del checkout principal y no crea worktrees.
antes=$(worktrees)
s=$(cd "$TMP/proj" && "$PREPARAR" 40 2>&1); c=$?
tap_check $c "sin --worktree termina bien"
es "$(git -C "$TMP/proj" branch --show-current)" = claude/40-sin-worktree; tap_check $? "sin --worktree cambia la rama del checkout principal"
[ "$(worktrees)" = "$antes" ] && ! grep -q '^Worktree:' <<<"$s"; tap_check $? "sin --worktree no crea ni menciona worktrees"
tail -2 <<<"$s" | head -1 | grep -qx "New branch: claude/40-sin-worktree (from origin/main)"; tap_check $? "sin --worktree la salida termina como hoy"
git -C "$TMP/proj" switch -q main
echo sucio >"$TMP/proj/sucio.txt"
(cd "$TMP/proj" && "$PREPARAR" 41 >/dev/null 2>&1); c=$?
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
(cd "$TMP/proj" && "$PREPARAR" 41 --worktree >/dev/null 2>&1); c=$?
tap_check $c "reintenta git fetch si falla por un lock"
rm -f "$TMP/bin/git"

# 7. Hallazgos de /code-review.
issue 42 "Huerfano"; issue 43 "Desde worktree"; issue 44 "Sin fetch"
(cd "$TMP/proj" && "$PREPARAR" 42 --worktree >/dev/null 2>&1)
rm -rf "$WT/42"
s=$(cd "$TMP/proj" && "$PREPARAR" 42 --worktree 2>&1); c=$?
tap_check $c "retoma aunque la carpeta del worktree se haya borrado a mano"
es -d "$WT/42"; tap_check $? "vuelve a crear la carpeta del worktree borrado"

s=$(cd "$TMP/proj" && "$PREPARAR" 36 2>&1); c=$?
es "$c" -ne 0; tap_check $? "sin --worktree falla si la rama está en un worktree"
grep -q "another worktree" <<<"$s"; tap_check $? "sin --worktree dice en qué worktree está la rama"
es "$(grep -c "^issue edit 36 " "$GH_LOG")" -eq 2; tap_check $? "sin --worktree no asigna si la rama está en un worktree"

s=$(cd "$WT/36" && "$PREPARAR" 43 --worktree 2>&1); c=$?
tap_check $c "--worktree funciona corriendo desde otro worktree"
grep -qx "Worktree: $WT/43" <<<"$s"; tap_check $? "desde otro worktree, el nuevo va al lado del checkout principal"

(cd "$TMP/proj" && "$PREPARAR" ../44 --worktree >/dev/null 2>&1); c=$?
es "$c" -eq 64 && ! grep -q 'issues/\.\.' "$GH_LOG"; tap_check $? "rechaza un número de issue inválido sin llamar a gh"

git -C "$TMP/proj" remote set-url origin "$TMP/no-existe.git"
(cd "$TMP/proj" && "$PREPARAR" 44 --worktree >/dev/null 2>&1); c=$?
es "$c" -ne 0 && ! asignado 44; tap_check $? "con --worktree no asigna si no pudo crear el worktree"
git -C "$TMP/proj" remote set-url origin "$TMP/remoto.git"

# 8. Hallazgos de la revisión del PR #40.
issue 45 "Con config bloqueada"; issue 46 "Worktree bloqueado"
touch "$TMP/proj/.git/config.lock"
(cd "$TMP/proj" && "$PREPARAR" 45 --worktree >/dev/null 2>&1); c=$?
rm -f "$TMP/proj/.git/config.lock"
tap_check $c "--worktree no necesita escribir .git/config (otro agente puede tenerlo bloqueado)"

git -C "$TMP/proj" worktree add -q -b claude/46-worktree-bloqueado "$TMP/bloqueado" origin/main 2>/dev/null
git -C "$TMP/proj" worktree lock "$TMP/bloqueado"; rm -rf "$TMP/bloqueado"
for args in "--worktree" ""; do
  # shellcheck disable=SC2086  # vacío a propósito
  s=$(cd "$TMP/proj" && "$PREPARAR" 46 $args 2>&1); c=$?
  es "$c" -eq 1 && grep -q "CANNOT TAKE #46: .*locked" <<<"$s"; tap_check $? "<args>: un worktree bloqueado y sin carpeta da un error claro" "${args:-sin --worktree}: un worktree bloqueado y sin carpeta da un error claro"
done
! asignado 46; tap_check $? "no asigna si la rama está en un worktree bloqueado sin carpeta"

# 9. #41: se retoma la rama del issue aunque el título se haya editado.
issue 50 "Titulo viejo"
(cd "$TMP/proj" && "$PREPARAR" 50 >/dev/null 2>&1 && git commit -q --allow-empty -m trabajo && git switch -q main)
issue 50 "Titulo nuevo"
s=$(cd "$TMP/proj" && "$PREPARAR" 50 2>&1); c=$?
es "$c" -eq 0 && es "$(git -C "$TMP/proj" branch --show-current)" = claude/50-titulo-viejo \
  && ! git -C "$TMP/proj" show-ref -q --verify refs/heads/claude/50-titulo-nuevo && grep -q "^Existing branch: claude/50-titulo-viejo" <<<"$s"
tap_check $? "sin --worktree, con el título editado, retoma la rama existente y no crea otra"
git -C "$TMP/proj" switch -q main

issue 51 "Antes"
(cd "$TMP/proj" && "$PREPARAR" 51 --worktree >/dev/null 2>&1)
issue 51 "Despues"
s=$(cd "$TMP/proj" && "$PREPARAR" 51 --worktree 2>&1); c=$?
es "$c" -eq 0 && grep -qx "Worktree: $WT/51" <<<"$s" && es "$(git -C "$WT/51" branch --show-current)" = claude/51-antes
tap_check $? "con --worktree, con el título editado, retoma el worktree existente"

issue 52 "Dos ramas"
git -C "$TMP/proj" branch claude/52-una main; git -C "$TMP/proj" branch claude/52-otra main
for args in "--worktree" ""; do
  # shellcheck disable=SC2086  # vacío a propósito
  s=$(cd "$TMP/proj" && "$PREPARAR" 52 $args 2>&1); c=$?
  es "$c" -eq 1 && grep -q "claude/52-una" <<<"$s" && grep -q "claude/52-otra" <<<"$s"
  tap_check $? "<args>: con dos ramas claude/<n>-*, falla y las lista" "${args:-sin --worktree}: con dos ramas claude/<n>-*, falla y las lista"
done
! asignado 52; tap_check $? "con dos ramas del issue no asigna"

issue 53 "Titulo distinto"
git clone -q "$TMP/remoto.git" "$TMP/otro-clon" 2>/dev/null
(cd "$TMP/otro-clon" && git switch -q -c claude/53-remota origin/main && git commit -q --allow-empty -m remota \
  && git push -q origin claude/53-remota && git switch -q -c claude/530-otra origin/main && git push -q origin claude/530-otra) 2>/dev/null
s=$(cd "$TMP/proj" && "$PREPARAR" 53 --worktree 2>&1); c=$?
es "$c" -eq 0 && es "$(git -C "$WT/53" branch --show-current)" = claude/53-remota \
  && es "$(git -C "$WT/53" log -1 --format=%s)" = remota
tap_check $? "una rama claude/<n>-* que solo está en origin se retoma (y claude/<n>0-* no cuenta)"

# 10. Hallazgos de /code-review de #41.
issue 54 "Solo remota sin worktree"
(cd "$TMP/otro-clon" && git switch -q -c claude/54-remota origin/main && git commit -q --allow-empty -m r54 \
  && git push -q origin claude/54-remota) 2>/dev/null
s=$(cd "$TMP/proj" && "$PREPARAR" 54 2>&1); c=$?
es "$c" -eq 0 && es "$(git -C "$TMP/proj" branch --show-current)" = claude/54-remota && es "$(git -C "$TMP/proj" log -1 --format=%s)" = r54
tap_check $? "sin --worktree, una rama que solo está en origin se retoma"
git -C "$TMP/proj" switch -q main

issue 55 "Reabierto"
(cd "$TMP/otro-clon" && git switch -q -c claude/55-vieja origin/main && git push -q origin claude/55-vieja) 2>/dev/null
echo MERGED >"$TMP/issues/pr-claude_55-vieja"
s=$(cd "$TMP/proj" && "$PREPARAR" 55 --worktree 2>&1); c=$?
es "$c" -eq 0 && es "$(git -C "$WT/55" branch --show-current)" = claude/55-reabierto
tap_check $? "una rama cuyo PR ya se mergeó o cerró no se retoma: el issue reabierto arranca una nueva"

issue 56 "Sin remoto"
git -C "$TMP/proj" remote set-url origin "$TMP/no-existe.git"
s=$(cd "$TMP/proj" && "$PREPARAR" 56 2>&1); c=$?
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
  s=$(cd "$TMP/proj" && env -u BASE "$PREPARAR" 47 --worktree 2>&1); c=$?
  tap_check $c "sin BASE, en la plantilla sin inicializar, toma el issue igual"
  grep -q "^New branch: claude/47-sin-base (from origin/main)" <<<"$s"; tap_check $? "sin BASE usa la rama por defecto del remoto"
  grep -qi "warning.*main" <<<"$s"; tap_check $? "sin BASE avisa qué base usó"
fi

# --help explica --worktree (salió de implement-issue/SKILL.md) sin tocar GitHub ni el repo.
: >"$GH_LOG"
s=$(cd "$TMP/proj" && "$PREPARAR" --help 2>&1); c=$?
tap_check $c "--help termina bien"
grep -q "git worktree remove" <<<"$s" && grep -q "fails without assigning" <<<"$s" && grep -q "git -C" <<<"$s"; tap_check $? "--help explica cómo trabajar en el worktree"
! [ -s "$GH_LOG" ]; tap_check $? "--help no llama a gh"

echo
tap_done
echo "Todos los tests pasan."
