#!/usr/bin/env bash
# Tests de update.py de punta a punta: dos versiones locales de la plantilla (v0.1.0 y v0.2.0),
# un proyecto iniciado con la primera y cambios de los dos lados.
# Uso: bash scripts/test-update.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-update-XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
es() { test "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t

# La plantilla tal como está en el árbol, en un repo con dos versiones etiquetadas.
P="$TMP/plantilla"
mkdir -p "$P"
(cd "$RAIZ" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf -) | (cd "$P" && tar -xf -)
(
  cd "$P" && git init -q -b main
  echo 0.1.0 >VERSION
  for f in viejo viejo2 borrado cambiado; do echo "$f v0.1" >".claude/skills/debug/$f.md"; done
  echo "echo modo" >.claude/skills/debug/modo.sh && chmod 644 .claude/skills/debug/modo.sh
  echo "Hello v0.1" >.claude/skills/debug/lang.md && echo "Hola v0.1" >.claude/skills/debug/lang.es.md
  git add -A && git commit -qm v0.1.0 && git tag v0.1.0
  # Un commit después del tag, sin cambiar VERSION: así nace un proyecto creado desde main.
  echo "cambiado posterior" >.claude/skills/debug/cambiado.md
  git commit -qam posterior && git branch posterior
  echo 0.2.0 >VERSION
  printf '\n## 0.2.0\n\n- Cambio de prueba.\n' >>CHANGELOG.md
  echo "Línea nueva de la plantilla v0.2." >>.claude/skills/debug/SKILL.md
  echo "Línea nueva de la plantilla v0.2." >>AGENTS.md
  perl -pi -e 's/^# .*/# Plantilla v0.2/ if $. == 1' docs/github-naming-convention.md
  echo "nuevo v0.2" >.claude/skills/debug/nuevo.md
  echo "borrado v0.2" >.claude/skills/debug/borrado.md
  git rm -q .claude/skills/debug/viejo.md .claude/skills/debug/viejo2.md
  echo "cambiado v0.2" >.claude/skills/debug/cambiado.md
  echo "Hello v0.2" >.claude/skills/debug/lang.md && echo "Hola v0.2" >.claude/skills/debug/lang.es.md
  chmod 755 .claude/skills/debug/modo.sh
  git add -A && git commit -qm v0.2.0 && git tag v0.2.0
) >/dev/null 2>&1

# Un tag "viejo" que solo tiene el init con el nombre y los flags de 0.9 (init-plantilla.sh, --chico, AGENT_KIT_FECHA).
(
  cd "$P" && git checkout -q -b viejo v0.1.0 \
    && git mv scripts/init-template.sh scripts/init-plantilla.sh \
    && perl -pi -e 's/--small/--chico/g; s/AGENT_KIT_DATE/AGENT_KIT_FECHA/g; s/init-template\.sh/init-plantilla.sh/g' scripts/init-plantilla.sh \
    && echo 0.0.5 >VERSION && git add -A && git commit -qm v0.0.5 && git tag v0.0.5 && git checkout -q main
) >/dev/null 2>&1

# Proyecto iniciado con v0.1.0: <modo> en <dir>.
proyecto() {
  local dir=$1 modo=$2 ref=${3:-v0.1.0} idioma=${4:-}
  mkdir -p "$dir"
  git -C "$P" archive "$ref" | tar -xf - -C "$dir"
  local extra=(); [ "$modo" = chico ] && extra=(--small)
  [ -n "$idioma" ] && extra+=(--lang "$idioma")
  (cd "$dir" && git init -q -b main && git add -A && git commit -qm plantilla \
    && ./scripts/init-template.sh Demo main ${extra[@]+"${extra[@]}"} && git add -A && git commit -qm init) >/dev/null 2>&1
}

D="$TMP/completo"
proyecto "$D" completo
grep -q '"version": "0.1.0"' "$D/.agent-kit.json"; afirmar $? "el init registra la versión de la plantilla en .agent-kit.json"
! [ -e "$D/VERSION" ] && ! [ -e "$D/CHANGELOG.md" ]; afirmar $? "el init borra VERSION y CHANGELOG.md (son de la plantilla)"
es -f "$D/scripts/update.py"; afirmar $? "el proyecto completo trae update.py"
(
  cd "$D" || exit 1
  perl -pi -e 's/^# .*/# AGENTS.md — Demo (editado)/ if $. == 1' AGENTS.md
  perl -pi -e 's/^# .*/# Convención del proyecto/ if $. == 1' docs/github-naming-convention.md
  echo "cambio del proyecto" >>.claude/skills/debug/viejo2.md
  git rm -q .claude/skills/debug/borrado.md
  git commit -qam "cambios del proyecto"
) >/dev/null 2>&1

echo sucio >>"$D/AGENTS.md"
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -ne 0 ] && grep -qi "uncommitted" <<<"$s"; afirmar $? "no actualiza con cambios sin commitear"
(cd "$D" && git checkout -q AGENTS.md)

antes=$(git -C "$D" rev-parse HEAD)
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
afirmar "$c" "actualiza de v0.1.0 a la última versión (v0.2.0)"
grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md"; afirmar $? "reemplaza un archivo que el proyecto no tocó"
grep -q "Demo (editado)" "$D/AGENTS.md" && grep -q "Línea nueva de la plantilla v0.2." "$D/AGENTS.md"
afirmar $? "fusiona un archivo que tocaron los dos lados en lugares distintos"
head -1 "$D/docs/github-naming-convention.md" | grep -q "Convención del proyecto" \
  && grep -q '^<<<<<<<' "$D/.agent-kit/pending/docs/github-naming-convention.md"
afirmar $? "con conflicto no pisa el archivo: deja la fusión con marcas en .agent-kit/pending/"
es -f "$D/.claude/skills/debug/nuevo.md"; afirmar $? "agrega un archivo nuevo de la plantilla"
! [ -e "$D/.claude/skills/debug/viejo.md" ]; afirmar $? "borra un archivo que la plantilla sacó y el proyecto no tocó"
[ -f "$D/.claude/skills/debug/viejo2.md" ] && grep -q "viejo2.md" <<<"$s"
afirmar $? "conserva y avisa un archivo que la plantilla sacó pero el proyecto modificó"
! [ -e "$D/.claude/skills/debug/borrado.md" ]; afirmar $? "no vuelve a traer un archivo que el proyecto borró"
grep -q '"version": "0.2.0"' "$D/.agent-kit.json"; afirmar $? "registra la versión nueva en .agent-kit.json"
es -x "$D/.claude/skills/debug/modo.sh"; afirmar $? "aplica un cambio de permisos (ejecutable) aunque el contenido sea igual"
grep -qi "integrate" <<<"$s" && grep -qi "next update" <<<"$s"; afirmar $? "con conflictos, avisa que hay que integrarlos ahora (la próxima actualización parte de la versión nueva)"
grep -q "Cambio de prueba" <<<"$s"; afirmar $? "muestra el changelog de las versiones nuevas"
es "$(git -C "$D" rev-parse HEAD)" = "$antes" && es -n "$(git -C "$D" status --porcelain)"
afirmar $? "no commitea: los cambios quedan en el working tree"
! grep -rq '<PROJECT>\|<BASE_BRANCH>' "$D/.claude/skills/debug/SKILL.md" "$D/AGENTS.md"
afirmar $? "los archivos traídos tienen los datos del proyecto, no los marcadores"

(cd "$D" && rm -rf .agent-kit && git checkout -q docs/github-naming-convention.md && git add -A && git commit -qm actualizar) >/dev/null 2>&1
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -qi "already at" <<<"$s" && [ -z "$(git -C "$D" status --porcelain)" ]
afirmar $? "si ya está en la última versión, no cambia nada"

# Lo que la revisión marcó: versiones más viejas, pendientes viejos, rutas relativas, versiones raras.
s=$(cd "$D" && python3 scripts/update.py --template "$P" --version v0.1.0 2>&1); c=$?
[ "$c" -ne 0 ] && grep -qi "older than" <<<"$s" && grep -q '"version": "0.2.0"' "$D/.agent-kit.json"
afirmar $? "no vuelve a una versión más vieja"
s=$(cd "$D" && python3 scripts/update.py --template 2>&1); c=$?
[ "$c" -ne 0 ] && grep -q "Usage:" <<<"$s"; afirmar $? "una opción sin valor muestra el uso, sin traceback"

D="$TMP/pendientes"
proyecto "$D" completo
mkdir -p "$D/.agent-kit/pending" && echo viejo >"$D/.agent-kit/pending/x.md"
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -ne 0 ] && grep -q "pending" <<<"$s" && ! grep -q "Línea nueva" "$D/.claude/skills/debug/SKILL.md"
afirmar $? "no actualiza si quedan pendientes de una actualización anterior"

D="$TMP/relativa"
proyecto "$D" completo
s=$(cd "$D/scripts" && python3 update.py --template "../../plantilla" 2>&1); c=$?
afirmar "$c" "--template relativa se resuelve desde donde se corre"

D="$TMP/rara"
proyecto "$D" completo
(cd "$D" && perl -pi -e 's/"version": "0.1.0"/"version": "0.1.0-rc.1"/' .agent-kit.json && git commit -qam rc) >/dev/null 2>&1
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q '"version": "0.2.0"' "$D/.agent-kit.json"; afirmar $? "una versión con sufijo (0.1.0-rc.1) no rompe a mitad de camino"

D="$TMP/posterior"
proyecto "$D" completo posterior
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
grep -q "cambiado v0.2" "$D/.claude/skills/debug/cambiado.md" && ! [ -e "$D/.agent-kit/pending/.claude/skills/debug/cambiado.md" ]
afirmar $? "un proyecto creado desde main después del tag: lo que no tocó se reemplaza, no va a pendientes"

# --lang (#113): update.py y grow.py reproducen el init en el idioma registrado.
for modo in completo chico; do
  D="$TMP/es-$modo"
  proyecto "$D" "$modo" v0.1.0 es
  grep -qx "Hola v0.1" "$D/.claude/skills/debug/lang.md" && grep -q '"language": "es"' "$D/.agent-kit.json"
  afirmar $? "[$modo --lang es] el init instala la versión .es.md y registra language: es"
  s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
  [ "$c" -eq 0 ] && grep -qx "Hola v0.2" "$D/.claude/skills/debug/lang.md" && ! [ -e "$D/.claude/skills/debug/lang.es.md" ] \
    && grep -q '"language": "es"' "$D/.agent-kit.json"
  afirmar $? "[$modo --lang es] update.py reinstala en español, sin traer los .es.md"
done
D="$TMP/crece-es"
proyecto "$D" chico v0.1.0 es
s=$(cd "$D" && AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py 2>&1); c=$?
[ "$c" -eq 0 ] && grep -qx "Hola v0.2" "$D/.claude/skills/debug/lang.md" && ! [ -e "$D/.claude/skills/debug/lang.es.md" ] \
  && grep -q '"language": "es"' "$D/.agent-kit.json"
afirmar $? "grow.py mantiene el idioma del proyecto (es)"

# Modo chico.
D="$TMP/chico"
proyecto "$D" chico
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" \
  && grep -q '"mode": "small"' "$D/.agent-kit.json" && ! [ -e "$D/.claude/skills/review-pr" ]
afirmar $? "[chico] actualiza sin traer lo del modo completo"

# grow.py (chico → completo) también registra la versión de la plantilla que trae.
D="$TMP/crece"
proyecto "$D" chico
s=$(cd "$D" && AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q '"version": "0.2.0"' "$D/.agent-kit.json" && grep -q '"mode": "full"' "$D/.agent-kit.json"
afirmar $? "grow.py registra la versión de la plantilla que trajo"

# Proyecto anterior a las versiones: sin "version" en .agent-kit.json.
D="$TMP/anterior"
proyecto "$D" completo
(
  cd "$D" || exit 1
  python3 -c "import json; k=json.load(open('.agent-kit.json')); k.pop('version', None); json.dump(k, open('.agent-kit.json', 'w'), indent=2)"
  perl -pi -e 's/^# .*/# AGENTS.md — Demo (editado)/ if $. == 1' AGENTS.md
  git commit -qam anterior
) >/dev/null 2>&1
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" \
  && grep -q "Demo (editado)" "$D/AGENTS.md" && [ -f "$D/.agent-kit/pending/AGENTS.md" ]
afirmar $? "[sin versión] reemplaza lo no tocado y deja lo modificado en pendientes, sin fusionar"

# La versión de origen solo trae el init viejo: update.py usa el init que exista en ese tag.
D="$TMP/origen-viejo"
mkdir -p "$D"; git -C "$P" archive v0.0.5 | tar -xf - -C "$D"
(cd "$D" && git init -q -b main && git add -A && git commit -qm plantilla && ./scripts/init-plantilla.sh Demo main && git add -A && git commit -qm init) >/dev/null 2>&1
grep -q '"version": "0.0.5"' "$D/.agent-kit.json"; afirmar $? "[origen viejo] el proyecto parte de un tag que solo tiene init-plantilla.sh"
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -eq 0 ] && grep -q '"version": "0.2.0"' "$D/.agent-kit.json" && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md"
afirmar $? "[origen viejo] actualiza usando el init que tiene el tag de origen"

# Proyecto 0.9 con las claves viejas de .agent-kit.json: error claro (la migración es el issue #116), sin traceback
# ni una actualización a medias que pierde el registro de archivos.
D="$TMP/claves-viejas"
proyecto "$D" completo
(cd "$D" && python3 -c "import json; k=json.load(open('.agent-kit.json')); json.dump({'proyecto': 'Demo', 'rama_base': 'main', 'modo': 'completo', 'fecha': k['date'], 'archivos': k['files']}, open('.agent-kit.json', 'w'))" && git commit -qam claves) >/dev/null 2>&1
s=$(cd "$D" && python3 scripts/update.py --template "$P" 2>&1); c=$?
[ "$c" -ne 0 ] && grep -q "0.9" <<<"$s" && ! grep -q Traceback <<<"$s"; afirmar $? "update.py con las claves viejas de .agent-kit.json explica que es de 0.9 y sale con error, sin traceback"
D="$TMP/claves-viejas-chico"
proyecto "$D" chico
(cd "$D" && python3 -c "import json; k=json.load(open('.agent-kit.json')); json.dump({'proyecto': 'Demo', 'rama_base': 'main', 'modo': 'chico', 'fecha': k['date'], 'archivos': k['files']}, open('.agent-kit.json', 'w'))" && git commit -qam claves) >/dev/null 2>&1
s=$(cd "$D" && AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py 2>&1); c=$?
[ "$c" -ne 0 ] && grep -q "0.9" <<<"$s" && ! grep -q Traceback <<<"$s"; afirmar $? "grow.py con las claves viejas de .agent-kit.json explica que es de 0.9 y sale con error, sin traceback"

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
