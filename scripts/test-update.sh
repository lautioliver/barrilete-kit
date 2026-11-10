#!/usr/bin/env bash
# shellcheck disable=SC2319  # "<condition>; tap_check $?" is the pattern of the tests (tap.sh)
# shellcheck disable=SC2016  # los fixtures y los textos esperados llevan backticks literales
# Tests de update.py de punta a punta: dos versiones locales de la plantilla (v0.1.0 y v0.2.0),
# un proyecto iniciado con la primera y cambios de los dos lados.
# Uso: bash scripts/test-update.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-update-XXXXXX")" && pwd -P)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
# build.log: la salida de los bloques que arman las plantillas de prueba; si algo falla ahí, el log dice qué.
tap_at_exit "[ ! -s \"\$TMP/build.log\" ] || { echo '--- salida de la preparación de las plantillas:' >&2; tail -n 40 \"\$TMP/build.log\" >&2; }; rm -rf \"\$TMP\""
# Uso: <condición>; tap_check $? "descripción"
es() { test "$@"; }

# Un paso de preparación (git, el init del proyecto): corre <comando> en <dir> y guarda su salida en <dir>.prep.log.
# Si falla, dice qué comando falló y con qué estado, muestra su salida y devuelve ese estado: el ERR trap de tap.sh
# corta el test ahí (una falla de preparación no es un caso fallido). Lo prueba test-update-prep.sh.
prep() {
  local dir=$1 st=0
  shift
  (cd "$dir" && "$@") >"$dir.prep.step" 2>&1 || st=$?
  cat "$dir.prep.step" >>"$dir.prep.log"
  if [ "$st" -ne 0 ]; then
    { echo "prep: falló (estado $st): $* en $dir"; sed 's/^/  | /' "$dir.prep.step"; } >&2
    return "$st"
  fi
}

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
# Ningún git de la prueba corre gc ni mantenimiento en segundo plano (#186, #224): ver scripts/agents/git-quiet.sh.
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/git-quiet.sh"
# Lo que GIT_CONFIG_* (y GIT_CONFIG_PARAMETERS, de git -c) traiga el entorno de quien corre el test no entra a sus repos (decisión de la persona en #238: https://github.com/lautioliver/barrilete-kit/pull/238#issuecomment-6618762051); el helper no pisa, así que se limpia acá.
# shellcheck disable=SC2046
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS $(compgen -v | grep -E '^GIT_CONFIG_(KEY|VALUE)_' || :)
git_quiet_env
cfg=$(git -C "$TMP" config --list 2>/dev/null)
grep -qxF gc.auto=0 <<<"$cfg"; tap_check $? "los git de la prueba no corren gc automático"
grep -qxF maintenance.auto=false <<<"$cfg"; tap_check $? "los git de la prueba no corren mantenimiento automático"

# La plantilla tal como está en el árbol, en un repo con dos versiones etiquetadas.
P="$TMP/plantilla"
mkdir -p "$P"
(cd "$RAIZ" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | (cd "$P" && tar -xf -)
(
  cd "$P" && git init -q -b main
  echo 0.1.0 >VERSION
  # El CHANGELOG real trae secciones con versiones de verdad (2.0.0): un proyecto de la prueba las vería como nuevas.
  printf '# Changelog\n' >CHANGELOG.md
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
) >>"$TMP/build.log" 2>&1

# Un tag "viejo" que solo tiene el init con el nombre y los flags de 0.9 (init-plantilla.sh, --chico, AGENT_KIT_FECHA).
(
  cd "$P" && git checkout -q -b viejo v0.1.0 \
    && git mv scripts/init-template.sh scripts/init-plantilla.sh \
    && perl -pi -e 's/--small/--chico/g; s/AGENT_KIT_DATE/AGENT_KIT_FECHA/g; s/init-template\.sh/init-plantilla.sh/g' scripts/init-plantilla.sh \
    && echo 0.0.5 >VERSION && git add -A && git commit -qm v0.0.5 && git tag v0.0.5 && git checkout -q main
) >>"$TMP/build.log" 2>&1

# Proyecto iniciado con v0.1.0: <modo> en <dir>. Lo que va después del idioma pasa al init tal cual.
proyecto() {
  local dir=$1 modo=$2 ref=${3:-v0.1.0} idioma=${4:-}
  shift 4 2>/dev/null || shift $#
  mkdir -p "$dir"
  git -C "$P" archive "$ref" | tar -xf - -C "$dir"
  local extra=(); [ "$modo" = chico ] && extra=(--small)
  [ -n "$idioma" ] && extra+=(--lang "$idioma")
  extra+=("$@")
  prep "$dir" git init -q -b main
  prep "$dir" git add -A
  prep "$dir" git commit -qm plantilla
  prep "$dir" ./scripts/init-template.sh Demo main ${extra[@]+"${extra[@]}"}
  prep "$dir" git add -A
  prep "$dir" git commit -qm init
}

D="$TMP/completo"
proyecto "$D" completo
grep -q '"version": "0.1.0"' "$D/.agent-kit.json"; tap_check $? "el init registra la versión de la plantilla en .agent-kit.json"
! [ -e "$D/VERSION" ] && ! [ -e "$D/CHANGELOG.md" ]; tap_check $? "el init borra VERSION y CHANGELOG.md (son de la plantilla)"
es -f "$D/scripts/update.py"; tap_check $? "el proyecto completo trae update.py"
(
  cd "$D" || exit 1
  perl -pi -e 's/^# .*/# AGENTS.md — Demo (editado)/ if $. == 1' AGENTS.md
  perl -pi -e 's/^# .*/# Convención del proyecto/ if $. == 1' docs/github-naming-convention.md
  echo "cambio del proyecto" >>.claude/skills/debug/viejo2.md
  git rm -q .claude/skills/debug/borrado.md
  git commit -qam "cambios del proyecto"
) >>"$TMP/build.log" 2>&1

echo sucio >>"$D/AGENTS.md"
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 1
[ "$c" -ne 0 ] && grep -qi "uncommitted" <<<"$s"; tap_check $? "no actualiza con cambios sin commitear"
(cd "$D" && git checkout -q AGENTS.md)

antes=$(git -C "$D" rev-parse HEAD)
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
tap_check "$c" "actualiza de v0.1.0 a la última versión (v0.2.0)"
grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md"; tap_check $? "reemplaza un archivo que el proyecto no tocó"
grep -q "Demo (editado)" "$D/AGENTS.md" && grep -q "Línea nueva de la plantilla v0.2." "$D/AGENTS.md"
tap_check $? "fusiona un archivo que tocaron los dos lados en lugares distintos"
head -1 "$D/docs/github-naming-convention.md" | grep -q "Convención del proyecto" \
  && grep -q '^<<<<<<<' "$D/.agent-kit/pending/docs/github-naming-convention.md"
tap_check $? "con conflicto no pisa el archivo: deja la fusión con marcas en .agent-kit/pending/"
es -f "$D/.claude/skills/debug/nuevo.md"; tap_check $? "agrega un archivo nuevo de la plantilla"
! [ -e "$D/.claude/skills/debug/viejo.md" ]; tap_check $? "borra un archivo que la plantilla sacó y el proyecto no tocó"
[ -f "$D/.claude/skills/debug/viejo2.md" ] && grep -q "viejo2.md" <<<"$s"
tap_check $? "conserva y avisa un archivo que la plantilla sacó pero el proyecto modificó"
! [ -e "$D/.claude/skills/debug/borrado.md" ]; tap_check $? "no vuelve a traer un archivo que el proyecto borró"
grep -q '"version": "0.2.0"' "$D/.agent-kit.json"; tap_check $? "registra la versión nueva en .agent-kit.json"
es -x "$D/.claude/skills/debug/modo.sh"; tap_check $? "aplica un cambio de permisos (ejecutable) aunque el contenido sea igual"
grep -qi "integrate" <<<"$s" && grep -qi "next update" <<<"$s"; tap_check $? "con conflictos, avisa que hay que integrarlos ahora (la próxima actualización parte de la versión nueva)"
grep -q "Cambio de prueba" <<<"$s"; tap_check $? "muestra el changelog de las versiones nuevas"
es "$(git -C "$D" rev-parse HEAD)" = "$antes" && es -n "$(git -C "$D" status --porcelain)"
tap_check $? "no commitea: los cambios quedan en el working tree"
! grep -rq '<PROJECT>\|<BASE_BRANCH>' "$D/.claude/skills/debug/SKILL.md" "$D/AGENTS.md"
tap_check $? "los archivos traídos tienen los datos del proyecto, no los marcadores"

(cd "$D" && rm -rf .agent-kit && git checkout -q docs/github-naming-convention.md && git add -A && git commit -qm actualizar) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -qi "already at" <<<"$s" && [ -z "$(git -C "$D" status --porcelain)" ]
tap_check $? "si ya está en la última versión, no cambia nada"

# Lo que la revisión marcó: versiones más viejas, pendientes viejos, rutas relativas, versiones raras.
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" --version v0.1.0 2>&1) || c=$?; tap_status "$c" 1
[ "$c" -ne 0 ] && grep -qi "older than" <<<"$s" && grep -q '"version": "0.2.0"' "$D/.agent-kit.json"
tap_check $? "no vuelve a una versión más vieja"
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template 2>&1) || c=$?; tap_status "$c" 1
[ "$c" -ne 0 ] && grep -q "Usage:" <<<"$s"; tap_check $? "una opción sin valor muestra el uso, sin traceback"

D="$TMP/pendientes"
proyecto "$D" completo
mkdir -p "$D/.agent-kit/pending" && echo viejo >"$D/.agent-kit/pending/x.md"
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 1
[ "$c" -ne 0 ] && grep -q "pending" <<<"$s" && ! grep -q "Línea nueva" "$D/.claude/skills/debug/SKILL.md"
tap_check $? "no actualiza si quedan pendientes de una actualización anterior"

D="$TMP/relativa"
proyecto "$D" completo
c=0; s=$(trap - ERR; cd "$D/scripts" && python3 update.py --template "../../plantilla" 2>&1) || c=$?; tap_status "$c" 0
tap_check "$c" "--template relativa se resuelve desde donde se corre"

D="$TMP/rara"
proyecto "$D" completo
(cd "$D" && perl -pi -e 's/"version": "0.1.0"/"version": "0.1.0-rc.1"/' .agent-kit.json && git commit -qam rc) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q '"version": "0.2.0"' "$D/.agent-kit.json"; tap_check $? "una versión con sufijo (0.1.0-rc.1) no rompe a mitad de camino"

D="$TMP/posterior"
proyecto "$D" completo posterior
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
grep -q "cambiado v0.2" "$D/.claude/skills/debug/cambiado.md" && ! [ -e "$D/.agent-kit/pending/.claude/skills/debug/cambiado.md" ]
tap_check $? "un proyecto creado desde main después del tag: lo que no tocó se reemplaza, no va a pendientes"

# --lang (#113): update.py y grow.py reproducen el init en el idioma registrado.
for modo in completo chico; do
  D="$TMP/es-$modo"
  proyecto "$D" "$modo" v0.1.0 es
  grep -qx "Hola v0.1" "$D/.claude/skills/debug/lang.md" && grep -q '"language": "es"' "$D/.agent-kit.json"
  tap_check $? "[<modo> --lang es] el init instala la versión .es.md y registra language: es" "[$modo --lang es] el init instala la versión .es.md y registra language: es"
  c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
  [ "$c" -eq 0 ] && grep -qx "Hola v0.2" "$D/.claude/skills/debug/lang.md" && ! [ -e "$D/.claude/skills/debug/lang.es.md" ] \
    && grep -q '"language": "es"' "$D/.agent-kit.json"
  tap_check $? "[<modo> --lang es] update.py reinstala en español, sin traer los .es.md" "[$modo --lang es] update.py reinstala en español, sin traer los .es.md"
done
D="$TMP/crece-es"
proyecto "$D" chico v0.1.0 es
c=0; s=$(trap - ERR; cd "$D" && AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -qx "Hola v0.2" "$D/.claude/skills/debug/lang.md" && ! [ -e "$D/.claude/skills/debug/lang.es.md" ] \
  && grep -q '"language": "es"' "$D/.agent-kit.json"
tap_check $? "grow.py mantiene el idioma del proyecto (es)"

# --flow-line (#181): update.py y grow.py reproducen la elección, así la status line no se pierde al actualizar.
# Con grep: una aserción que falla es "not ok", no un crash (tap.sh).
con_flow_line() {
  grep -q '"statusLine"' "$1/.claude/settings.json" && grep -q 'scripts/agents/flow.py.*--statusline' "$1/.claude/settings.json" \
    && grep -q '"flow_line": true' "$1/.agent-kit.json"
}
for modo in completo chico; do
  D="$TMP/flow-$modo"
  proyecto "$D" "$modo" v0.1.0 "" --flow-line
  con_flow_line "$D"; tap_check $? "[<modo> --flow-line] el init deja el statusLine y flow_line: true" "[$modo --flow-line] el init deja el statusLine y flow_line: true"
  c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
  [ "$c" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" && con_flow_line "$D" \
    && ! [ -e "$D/.agent-kit/pending/.claude/settings.json" ]
  tap_check $? "[<modo> --flow-line] update.py conserva el statusLine y flow_line: true" "[$modo --flow-line] update.py conserva el statusLine y flow_line: true"
done
D="$TMP/flow-crece"
proyecto "$D" chico v0.1.0 "" --flow-line
c=0; s=$(trap - ERR; cd "$D" && AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q '"mode": "full"' "$D/.agent-kit.json" && con_flow_line "$D"
tap_check $? "grow.py conserva el statusLine y flow_line: true"

# Modo chico.
D="$TMP/chico"
proyecto "$D" chico
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" \
  && grep -q '"mode": "small"' "$D/.agent-kit.json" && ! [ -e "$D/.claude/skills/review-pr" ]
tap_check $? "[chico] actualiza sin traer lo del modo completo"

# Un proyecto 1.0.0 recibió el corpus de red.sh y test-red.sh (#191): update.py borra lo que no tocó y avisa de lo que sí.
D="$TMP/de-1-0"
proyecto "$D" completo
(
  cd "$D" || exit 1
  K=.claude/skills/implement-issue
  mkdir -p $K/corpus/caso-a $K/corpus/caso-b otro-dir
  ln -s ../../../../otro-dir $K/corpus/enlace
  echo "expect=2" >otro-dir/meta
  echo "expect=0" >$K/corpus/caso-a/meta
  echo "expect=1" >$K/corpus/caso-b/meta
  echo "echo test" >$K/test-red.sh
  python3 - <<'PY'
import hashlib, json
j = json.load(open(".agent-kit.json"))
for r in (".claude/skills/implement-issue/corpus/caso-a/meta", ".claude/skills/implement-issue/corpus/caso-b/meta", ".claude/skills/implement-issue/corpus/enlace/meta", ".claude/skills/implement-issue/test-red.sh"):
    j["files"][r] = hashlib.sha1(open(r, "rb").read()).hexdigest()
json.dump(j, open(".agent-kit.json", "w"), ensure_ascii=False, indent=2)
PY
  echo "cambio del proyecto" >>$K/corpus/caso-b/meta
  git add -A
  git commit -qm "como 1.0.0"
) >>"$TMP/build.log" 2>&1
cd "$D" || exit 1
tap_run s 0 python3 scripts/update.py --template "$P"
cd "$TMP" || exit 1
! [ -e "$D/.claude/skills/implement-issue/corpus/caso-a" ] && ! [ -e "$D/.claude/skills/implement-issue/test-red.sh" ]
tap_check $? "[1.0.0] borra el corpus y test-red.sh que el proyecto no tocó"
[ -f "$D/.claude/skills/implement-issue/corpus/caso-b/meta" ] && grep -q "caso-b" <<<"$s"
tap_check $? "[1.0.0] conserva y avisa un archivo del corpus que el proyecto modificó"
! [ -e "$D/otro-dir/meta" ] && ! grep -q "corpus/enlace/meta" "$D/.agent-kit.json" && ! grep -q "enlace/meta: " <<<"$s"
tap_check $? "[1.0.0] un archivo que está detrás de una carpeta que es un enlace se borra y se saca del registro, sin error"

# grow.py (chico → completo) también registra la versión de la plantilla que trae.
D="$TMP/crece"
proyecto "$D" chico
c=0; s=$(trap - ERR; cd "$D" && AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q '"version": "0.2.0"' "$D/.agent-kit.json" && grep -q '"mode": "full"' "$D/.agent-kit.json"
tap_check $? "grow.py registra la versión de la plantilla que trajo"

# Proyecto anterior a las versiones: sin "version" en .agent-kit.json.
D="$TMP/anterior"
proyecto "$D" completo
(
  cd "$D" || exit 1
  python3 -c "import json; k=json.load(open('.agent-kit.json')); k.pop('version', None); json.dump(k, open('.agent-kit.json', 'w'), indent=2)"
  perl -pi -e 's/^# .*/# AGENTS.md — Demo (editado)/ if $. == 1' AGENTS.md
  git commit -qam anterior
) >>"$TMP/build.log" 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" \
  && grep -q "Demo (editado)" "$D/AGENTS.md" && [ -f "$D/.agent-kit/pending/AGENTS.md" ]
tap_check $? "[sin versión] reemplaza lo no tocado y deja lo modificado en pendientes, sin fusionar"

# La versión de origen solo trae el init viejo: update.py usa el init que exista en ese tag.
D="$TMP/origen-viejo"
mkdir -p "$D"; git -C "$P" archive v0.0.5 | tar -xf - -C "$D"
(cd "$D" && git init -q -b main && git add -A && git commit -qm plantilla && ./scripts/init-plantilla.sh Demo main && git add -A && git commit -qm init) >/dev/null 2>&1
grep -q '"version": "0.0.5"' "$D/.agent-kit.json"; tap_check $? "[origen viejo] el proyecto parte de un tag que solo tiene init-plantilla.sh"
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q '"version": "0.2.0"' "$D/.agent-kit.json" && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md"
tap_check $? "[origen viejo] actualiza usando el init que tiene el tag de origen"

# Proyectos 0.9.0 (#116): update.py los migra a los nombres, claves y labels nuevos sin perder cambios propios.
# La plantilla 0.9.0 se arma desde el árbol actual con los nombres viejos (la tabla de test-renames.sh, que es la
# fuente independiente de update.py) y un init mínimo con la forma de 0.9; la 0.10.0 es el árbol actual con cambios.
TABLA="$TMP/tabla-renombres.txt"
sed -n "/^RENAMES='/,/^'\$/p" "$RAIZ/scripts/test-renames.sh" | grep '|' >"$TABLA"
cat >"$TMP/rev09.py" <<'PY'
import json, os, re, sys
arbol, tabla = sys.argv[1], sys.argv[2]
pares = [l.strip().split("|") for l in open(tabla, encoding="utf-8") if "|" in l]
pares = sorted(((v, n) for v, n in pares if v != n), key=lambda p: -len(p[1]))
for v, n in pares:
    if os.path.isfile(os.path.join(arbol, n)):
        os.makedirs(os.path.dirname(os.path.join(arbol, v)), exist_ok=True)
        os.replace(os.path.join(arbol, n), os.path.join(arbol, v))
for nuevo, viejo in (("profiles/small", "perfiles/chico"), (".github/brand", ".github/marca")):
    if os.path.isdir(os.path.join(arbol, nuevo)):
        os.makedirs(os.path.join(arbol, viejo), exist_ok=True)
        for base, _, files in os.walk(os.path.join(arbol, nuevo)):
            for f in files:
                d = os.path.join(arbol, viejo, os.path.relpath(os.path.join(base, f), os.path.join(arbol, nuevo)))
                os.makedirs(os.path.dirname(d), exist_ok=True)
                os.replace(os.path.join(base, f), d)
for base, _, _ in os.walk(arbol, topdown=False):
    if ".git" not in base and base != arbol and not os.listdir(base):
        os.rmdir(base)
CLAVES = {"_help": "_ayuda", "when": "cuando", "review": "revisar", "reason": "motivo", "sensitive": "sensibles",
          "type": "tipo", "paths": "rutas", "verify": "verificar", "name": "nombre", "always": "siempre", "run": "correr",
          "required": "obligatorios", "ignore_check": "ignorar_check", "members": "integrantes", "active": "activo"}
VALORES = {"name": {"prepare": "preparar", "agents": "agentes", "red": "rojo", "orchestrate": "orquestar",
                    "guardrails": "barandas", "update": "actualizar", "migrations": "migraciones", "api-contract": "contrato-api"},
           "type": {"money": "dinero", "dependencies": "dependencias", "public-api": "api-publica"}}
def texto(s):
    for v, n in pares:
        s = s.replace(n, v)
    for n, v in (("scripts/agents/", "scripts/agentes/"), ("docs/agents/", "docs/agentes/"), ("profiles/", "perfiles/")):
        s = s.replace(n, v)
    return s.replace("{files}", "{archivos}")
def viejo(o, clave=None):
    if isinstance(o, dict):
        return {CLAVES.get(k, k): viejo(x, k) for k, x in o.items() if k not in ("parity", "parity_ignore")}
    if isinstance(o, list):
        return [viejo(x, clave) for x in o]
    if isinstance(o, str):
        return VALORES.get(clave, {}).get(o, texto(o))
    return o
for ruta in ("docs/mapa-agentes.json", ".github/equipo.json"):
    ruta = os.path.join(arbol, ruta)
    datos = json.load(open(ruta, encoding="utf-8"))
    open(ruta, "w", encoding="utf-8").write(json.dumps(viejo(datos), ensure_ascii=False, indent=2) + "\n")
# labels.yml: el nombre vuelve a ser el primer alias, y sin aliases (como en 0.9).
ruta = os.path.join(arbol, ".github/labels.yml")
def label(m):
    cuerpo = m.group(2)
    a = re.search(r'  aliases:\n((?:    - .*\n)+)', cuerpo)
    if not a:
        return m.group(0)
    primero = a.group(1).splitlines()[0].strip()[2:].strip('"')
    return f'- name: "{primero}"\n' + cuerpo.replace(a.group(0), "")
t = re.sub(r'- name: "([^"]*)"\n((?:  .*\n)*)', label, open(ruta, encoding="utf-8").read())
open(ruta, "w", encoding="utf-8").write(t)
PY
cat >"$TMP/init-plantilla-09.sh" <<'SH'
#!/usr/bin/env bash
# Init mínimo con la forma de 0.9: init-plantilla.sh, --chico, AGENT_KIT_FECHA, perfiles/chico y .agent-kit.json en español.
set -euo pipefail
CHICO=""; POS=()
for a in "$@"; do case "$a" in --chico) CHICO=1 ;; *) POS+=("$a") ;; esac; done
export P="${POS[0]}" B="${POS[1]:-main}" F=${AGENT_KIT_FECHA:-2026-01-01} R="regla" MODO_KIT=$([ -n "$CHICO" ] && echo chico || echo completo)
cd "$(git rev-parse --show-toplevel)"
LISTA=$(mktemp "${TMPDIR:-/tmp}/init09-lista-XXXXXX")   # fuera del proyecto: no entra en lo que se copia, borra ni registra
trap 'rm -f "$LISTA"' EXIT
if [ -n "$CHICO" ]; then
  (cd perfiles/chico && find . -type f ! -name BORRAR) >"$LISTA"
  while read -r f; do mkdir -p "$(dirname "$f")"; cp "perfiles/chico/$f" "$f"; done <"$LISTA"
  rm -rf .claude/skills/review-pr .claude/skills/orquestar
fi
rm -rf perfiles .github/marca docs/probar-la-plantilla.md .github/ISSUE_TEMPLATE/5-prueba.yml docs/decisions/ADR-001-*
find . -name '*.es.md' -not -path './.git/*' >"$LISTA"
while read -r f; do rm -f -- "$f"; done <"$LISTA"
[ -z "$CHICO" ] && rm -f scripts/crecer.py
{ grep -rlE '<PROJECT>|<BASE_BRANCH>|<DATE>|<BRANCH_RULE>' --exclude-dir=.git . || true; } >"$LISTA"
xargs perl -pi -e 's/<PROJECT>/$ENV{P}/g; s/<BASE_BRANCH>/$ENV{B}/g; s/<DATE>/$ENV{F}/g; s/<BRANCH_RULE>/$ENV{R}/g' <"$LISTA"
V=$(cat VERSION); export V
rm -f scripts/init-plantilla.sh VERSION CHANGELOG.md scripts/test-*.sh
python3 - <<'PY'
import hashlib, json, os
archivos = {}
for base, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d != ".git"]
    for n in files:
        ruta = os.path.relpath(os.path.join(base, n), ".")
        if ruta != ".agent-kit.json":
            archivos[ruta] = hashlib.sha1(open(ruta, "rb").read()).hexdigest()
json.dump({"proyecto": os.environ["P"], "rama_base": os.environ["B"], "releases": False, "modo": os.environ["MODO_KIT"],
           "fecha": os.environ["F"], "version": os.environ["V"], "archivos": dict(sorted(archivos.items()))},
          open(".agent-kit.json", "w"), ensure_ascii=False, indent=2)
PY
SH

P09="$TMP/plantilla09"
mkdir -p "$P09"
(cd "$RAIZ" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | (cd "$P09" && tar -xf -)
(
  cd "$P09" && python3 "$TMP/rev09.py" "$P09" "$TABLA" \
    && cp "$TMP/init-plantilla-09.sh" scripts/init-plantilla.sh && chmod +x scripts/init-plantilla.sh \
    && rm -f scripts/init-template.sh && echo 0.9.0 >VERSION \
    && git init -q -b main && git add -A && git commit -qm v0.9.0 && git tag v0.9.0 \
    && git rm -rqf . && (cd "$RAIZ" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -xf - \
    && echo 0.10.0 >VERSION \
    && printf '\n## [0.10.0] - 2026-10-20\n\n- Cambio de prueba 0.10.\n' >>CHANGELOG.md \
    && echo "# nuevo en 0.10" >>scripts/agents/verify.py \
    && echo "Línea nueva de la plantilla 0.10." >>.claude/skills/create-issue/SKILL.md \
    && perl -pi -e 's/^# .*/# Plantilla 0.10/ if $. == 1' docs/github-naming-convention.md \
    && git add -A && git commit -qm v0.10.0 && git tag v0.10.0
) >>"$TMP/build.log" 2>&1
git -C "$P09" rev-parse -q --verify v0.9.0 >/dev/null && git -C "$P09" rev-parse -q --verify v0.10.0 >/dev/null
tap_check $? "[0.9] la plantilla de prueba tiene los tags v0.9.0 (nombres viejos) y v0.10.0"
git -C "$P09" show v0.9.0:docs/mapa-agentes.json | grep -q '"sensibles"' && git -C "$P09" show v0.9.0:scripts/agentes/verificar.py >/dev/null 2>&1 \
  && git -C "$P09" show v0.9.0:scripts/init-plantilla.sh >/dev/null 2>&1 && ! git -C "$P09" show v0.9.0:scripts/init-template.sh >/dev/null 2>&1
tap_check $? "[0.9] v0.9.0 tiene el init, las rutas y las claves viejas"

NUEVO_UPDATE="$TMP/update-nuevo.py"   # lo que baja un proyecto 0.9: no tiene update.py, tiene actualizar.py
cp "$RAIZ/scripts/update.py" "$NUEVO_UPDATE"

# Proyecto creado con 0.9.0: <modo> en <dir>, con el idioma opcional en las claves viejas.
proyecto09() {
  local dir=$1 modo=$2 idioma=${3:-}
  mkdir -p "$dir"
  git -C "$P09" archive v0.9.0 | tar -xf - -C "$dir"
  local extra=(); [ "$modo" = chico ] && extra=(--chico)
  prep "$dir" git init -q -b main
  prep "$dir" git add -A
  prep "$dir" git commit -qm plantilla
  prep "$dir" env AGENT_KIT_FECHA=2026-01-01 ./scripts/init-plantilla.sh Demo main ${extra[@]+"${extra[@]}"}
  prep "$dir" git add -A
  prep "$dir" git commit -qm init
  if [ -n "$idioma" ]; then
    prep "$dir" python3 -c "import json; k=json.load(open('.agent-kit.json')); k['language']='$idioma'; json.dump(k, open('.agent-kit.json', 'w'), ensure_ascii=False, indent=2)"
    prep "$dir" git commit -qam idioma
  fi
}
# Cambios propios en archivos que la 0.10 renombró.
cambios09() {
  (
    cd "$1" || exit 1
    perl -pi -e 'print "# del proyecto\n" if $. == 1' scripts/agentes/verificar.py
    echo "Lección del proyecto." >>docs/agentes/lecciones.md
    perl -pi -e 's/^# .*/# Convención del proyecto/ if $. == 1' docs/convencion-nombres-github.md
    printf '\n- name: "area:pagos"\n  color: "0E8A16"\n  description: "Pagos"\n' >>.github/labels.yml
    python3 - <<'PY'
import json
m = json.load(open("docs/mapa-agentes.json", encoding="utf-8"))
m["sensibles"].append({"tipo": "pagos", "rutas": ["src/pagos/**"]})
m["verificar"].append({"nombre": "pagos", "cuando": ["src/pagos/**"], "correr": "npm test {archivos}"})
open("docs/mapa-agentes.json", "w", encoding="utf-8").write(json.dumps(m, ensure_ascii=False, indent=2) + "\n")
json.dump({"_ayuda": "x", "integrantes": [{"login": "ana", "nombre": "Ana", "areas": ["infra"], "activo": True}]},
          open(".github/equipo.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
    git add -A && git commit -qm "cambios del proyecto"
  ) >/dev/null 2>&1
}

D="$TMP/p09"
proyecto09 "$D" completo
grep -q '"archivos"' "$D/.agent-kit.json" && es -f "$D/scripts/actualizar.py" && es -f "$D/scripts/agentes/verificar.py" && ! [ -e "$D/scripts/update.py" ]
tap_check $? "[0.9] el proyecto de partida tiene la forma de 0.9: claves y archivos en español, sin update.py"
cambios09 "$D"
antes=$(git -C "$D" rev-parse HEAD)
c=0; s=$(trap - ERR; cd "$D" && python3 "$NUEVO_UPDATE" --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && ! grep -q Traceback <<<"$s"; tap_check $? "[0.9] update.py actualiza un proyecto 0.9.0 a la versión nueva" "[0.9] update.py actualiza un proyecto 0.9.0 a la versión nueva (salida: $(tail -1 <<<"$s" | cut -c1-80))"
! [ -e "$D/scripts/agentes" ] && ! [ -e "$D/docs/agentes" ] && ! [ -e "$D/scripts/actualizar.py" ] && ! [ -e "$D/docs/mapa-agentes.json" ] \
  && ! [ -e "$D/.github/equipo.json" ] && ! [ -e "$D/.claude/skills/crear-issue" ]
tap_check $? "[0.9] no quedan archivos ni carpetas con el nombre viejo"
es -f "$D/scripts/update.py" && es -f "$D/scripts/agents/guardrails.py" && es -f "$D/docs/agents-map.json" && es -f "$D/.claude/skills/improve-skills/retro.sh"
tap_check $? "[0.9] los archivos renombrados están en su ruta nueva"
! [ -e "$D/.claude/skills/implement-issue/corpus" ] && ! [ -e "$D/.claude/skills/implement-issue/test-red.sh" ]
tap_check $? "[0.9] la migración no agrega el corpus de red.sh ni test-red.sh (#191)"
grep -q "^# del proyecto" "$D/scripts/agents/verify.py" && grep -q "^# nuevo en 0.10" "$D/scripts/agents/verify.py"
tap_check $? "[0.9] un archivo renombrado con cambios del proyecto y de la plantilla se fusiona (no se pierde ninguno)"
grep -q "Lección del proyecto." "$D/docs/agents/lessons.md"; tap_check $? "[0.9] un archivo renombrado con cambios solo del proyecto los conserva en la ruta nueva"
grep -q "Línea nueva de la plantilla 0.10." "$D/.claude/skills/create-issue/SKILL.md"; tap_check $? "[0.9] un archivo renombrado que el proyecto no tocó se reemplaza por la versión nueva"
head -1 "$D/docs/github-naming-convention.md" | grep -q "Convención del proyecto" && grep -q '^<<<<<<<' "$D/.agent-kit/pending/docs/github-naming-convention.md"
tap_check $? "[0.9] un conflicto en un archivo renombrado no lo pisa: la fusión con marcas queda en .agent-kit/pending/ con la ruta nueva"
python3 - "$D/.agent-kit.json" <<'PY'
import json, sys
k = json.load(open(sys.argv[1], encoding="utf-8"))
viejas = {"proyecto", "rama_base", "modo", "fecha", "archivos"} & set(k)
ok = (not viejas and k.get("project") == "Demo" and k.get("base_branch") == "main" and k.get("mode") == "full"
      and k.get("date") == "2026-01-01" and k.get("version") == "0.10.0" and isinstance(k.get("files"), dict)
      and not any(r.startswith(("scripts/agentes/", "docs/agentes/")) for r in k["files"]) and "scripts/agents/verify.py" in k["files"])
sys.exit(0 if ok else 1)
PY
tap_check $? "[0.9] .agent-kit.json pasa a las claves nuevas (project, base_branch, mode: full, date, files con las rutas nuevas) y registra la versión nueva"
python3 - "$D/docs/agents-map.json" "$D/.github/team.json" <<'PY'
import json, sys
def claves(o):
    if isinstance(o, dict):
        for k, v in o.items():
            yield k
            yield from claves(v)
    elif isinstance(o, list):
        for v in o:
            yield from claves(v)
m = json.load(open(sys.argv[1], encoding="utf-8"))
t = json.load(open(sys.argv[2], encoding="utf-8"))
viejas = {"cuando", "revisar", "motivo", "sensibles", "rutas", "verificar", "nombre", "siempre", "correr", "obligatorios",
          "ignorar_check", "_ayuda", "tipo", "integrantes", "activo"}
pagos = [x for x in m.get("sensitive", []) if x.get("type") == "pagos"]
verif = [x for x in m.get("verify", []) if x.get("name") == "pagos"]
nombres = {x.get("name") for x in m.get("verify", [])}
ok = (not viejas & (set(claves(m)) | set(claves(t))) and pagos and pagos[0]["paths"] == ["src/pagos/**"]
      and verif and verif[0]["run"] == "npm test {files}" and "guardrails" in nombres and "barandas" not in nombres
      and "money" in {x.get("type") for x in m["sensitive"]} and t["members"][0] == {"login": "ana", "name": "Ana", "areas": ["infra"], "active": True})
sys.exit(0 if ok else 1)
PY
tap_check $? "[0.9] migra las claves y los valores de agents-map.json y team.json conservando lo que agregó el proyecto"
grep -q 'name: "type:feature"' "$D/.github/labels.yml" && grep -q '^ *- "tipo:feature"' "$D/.github/labels.yml" && grep -q 'name: "area:pagos"' "$D/.github/labels.yml"
tap_check $? "[0.9] labels.yml queda con los labels nuevos y los viejos como aliases, y conserva el label propio"
grep -q "0.9" <<<"$s" && grep -q '"language": "en"' "$D/.agent-kit.json" && grep -q 'language' <<<"$s" && grep -q '"language": "es"' <<<"$s"
tap_check $? "[0.9] sin language trata el proyecto como en y lo avisa en el resumen (con cómo pasar a es)"
grep -q "Cambio de prueba 0.10" <<<"$s"; tap_check $? "[0.9] muestra el changelog de la versión nueva"
es "$(git -C "$D" rev-parse HEAD)" = "$antes" && es -n "$(git -C "$D" status --porcelain)"; tap_check $? "[0.9] no commitea: los cambios quedan en el working tree"
(cd "$D" && rm -rf .agent-kit && git checkout -q docs/convencion-nombres-github.md 2>/dev/null; git add -A && git commit -qm migrar) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -qi "already at" <<<"$s"; tap_check $? "[0.9] después de migrar, el update.py del proyecto dice que ya está en la última versión"

# El proyecto en español agrega "language": "es" antes de actualizar: la migración lo respeta.
D="$TMP/p09-es"
proyecto09 "$D" completo es
c=0; s=$(trap - ERR; cd "$D" && python3 "$NUEVO_UPDATE" --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q '"language": "es"' "$D/.agent-kit.json" && ! grep -q 'treated as English' <<<"$s"
tap_check $? "[0.9] con language: es en el proyecto, la migración lo conserva y no avisa del idioma por defecto"

# Proyecto chico de 0.9: crecer.py pasa a grow.py y perfiles/chico a profiles/small.
D="$TMP/p09-chico"
proyecto09 "$D" chico
es -f "$D/scripts/crecer.py" && grep -q '"modo": "chico"' "$D/.agent-kit.json"; tap_check $? "[0.9 chico] el proyecto de partida es chico, con crecer.py"
perl -pi -e 's/^# .*/# Convención del proyecto/ if $. == 1' "$D/docs/convencion-nombres-github.md"
(cd "$D" && git add -A && git commit -qm cambios) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 "$NUEVO_UPDATE" --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q '"mode": "small"' "$D/.agent-kit.json" && grep -q '"version": "0.10.0"' "$D/.agent-kit.json" \
  && es -f "$D/scripts/grow.py" && ! [ -e "$D/scripts/crecer.py" ] && ! grep -q '"modo"' "$D/.agent-kit.json"
tap_check $? "[0.9 chico] migra a mode: small y mueve crecer.py a grow.py"
head -1 "$D/docs/github-naming-convention.md" | grep -q "Convención del proyecto" && ! [ -e "$D/docs/convencion-nombres-github.md" ]
tap_check $? "[0.9 chico] la convención del perfil chico, con cambios del proyecto, queda en su ruta nueva"

# La ruta nueva ya existe (alguien bajó update.py al proyecto): no se pisa, se avisa, y lo viejo sin cambios se borra.
D="$TMP/p09-choque"
proyecto09 "$D" completo
(cd "$D" && cp "$NUEVO_UPDATE" scripts/update.py && git add -A && git commit -qm "update.py nuevo") >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && es -f "$D/scripts/update.py" && grep -q "actualizar.py" <<<"$s" && ! grep -q Traceback <<<"$s"
tap_check $? "[0.9] si la ruta nueva ya existe no la pisa, lo avisa y sigue con el resto"
es -f "$D/scripts/actualizar.py"; tap_check $? "[0.9] la ruta vieja que no se pudo mover queda para comparar a mano: no se borra"

# Ronda de corrección del PR: rutas propias con un nombre viejo, volver atrás por el idioma, restos generados y el orden de check-docs.
D="$TMP/p09-rutas"
proyecto09 "$D" completo
(
  cd "$D" || exit 1
  python3 - <<'PY'
import json
m = json.load(open("docs/mapa-agentes.json", encoding="utf-8"))
m["sensibles"].append({"tipo": "pii", "rutas": ["app/perfiles/**", "?src/scripts/agentes/pii.py", "scripts/agentes/**"]})
m["verificar"].append({"nombre": "crecer", "siempre": True, "correr": "bash tools/scripts/crecer.py.sh"})
m["verificar"].append({"nombre": "relativa", "siempre": True, "correr": "python3 ./scripts/agentes/verificar.py && python3 ../scripts/crecer.py"})
open("docs/mapa-agentes.json", "w", encoding="utf-8").write(json.dumps(m, ensure_ascii=False, indent=2) + "\n")
PY
  git add -A && git commit -qm rutas
  mkdir -p scripts/agentes/__pycache__ && echo x >scripts/agentes/__pycache__/guardrails.pyc
) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 "$NUEVO_UPDATE" --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
python3 - "$D/docs/agents-map.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
pii = [x for x in m["sensitive"] if x.get("type") == "pii"]
cmd = [x for x in m["verify"] if x.get("name") == "crecer"]
sys.exit(0 if pii and pii[0]["paths"] == ["app/perfiles/**", "?src/scripts/agentes/pii.py", "scripts/agents/**"]
         and cmd and cmd[0]["run"] == "bash tools/scripts/crecer.py.sh"
         and [x["run"] for x in m["verify"] if x.get("name") == "relativa"] == ["python3 ./scripts/agents/verify.py && python3 ../scripts/grow.py"] else 1)
PY
tap_check $? "[0.9] solo renombra las rutas del kit en el mapa (app/perfiles/** queda intacta), también si empiezan con ./ o ../"
! [ -e "$D/scripts/agentes" ] && ! grep -q "own files" <<<"$s"
tap_check $? "[0.9] un __pycache__ de la carpeta vieja no cuenta como archivo propio: se borra con la carpeta"
grep -Eq 'git add -A.*check-docs|check-docs.*git add -A' <<<"$s" && ! grep -Eq '^ +2\. python3 scripts/agents/check-docs.py' <<<"$s"
tap_check $? "[0.9] el resumen pide git add -A antes de check-docs.py (usa el índice de git)"

# El aviso del idioma indica cómo volver atrás, y eso funciona.
D="$TMP/p09-volver"
proyecto09 "$D" completo
cambios09 "$D"
c=0; s=$(trap - ERR; cd "$D" && python3 "$NUEVO_UPDATE" --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
grep -q "rm -rf .agent-kit" <<<"$s" && grep -q "git reset --hard && git clean -fd" <<<"$s"; tap_check $? "[0.9] el aviso del idioma indica descartar la corrida, borrar .agent-kit/ y commitear el cambio"
(
  cd "$D" || exit 1
  git add -A  # el resumen pide stagear antes de check-docs: la vuelta atrás tiene que andar con todo en el índice
  git reset -q --hard && git clean -qfd && rm -rf .agent-kit
  python3 -c "import json; k=json.load(open('.agent-kit.json')); k['language']='es'; json.dump(k, open('.agent-kit.json', 'w'), ensure_ascii=False, indent=2)"
  git commit -qam "language es"
) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 "$NUEVO_UPDATE" --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && grep -q '"language": "es"' "$D/.agent-kit.json" && es -f "$D/scripts/agents/verify.py" && ! [ -e "$D/scripts/agentes" ]
tap_check $? "[0.9] siguiendo el aviso (descartar con todo stageado, borrar .agent-kit/, agregar language y commitear) la segunda corrida migra en español"

# Lo que marcó la revisión: nombres de personas, carpetas viejas con archivos propios, claves a medias, sin fecha.
D="$TMP/p09-revision"
proyecto09 "$D" completo
(
  cd "$D" || exit 1
  echo "guía propia" >docs/agentes/mi-guia.md
  python3 - <<'PY'
import json
json.dump({"_ayuda": "x", "integrantes": [{"login": "rojo", "nombre": "rojo", "areas": [], "activo": True}]},
          open(".github/equipo.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
k = json.load(open(".agent-kit.json", encoding="utf-8"))
k.pop("fecha")  # sin fecha
k["files"] = k.pop("archivos")  # claves a medias: archivos ya cambiada, el resto en español
json.dump(k, open(".agent-kit.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
  git add -A && git commit -qm revision
) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && python3 "$NUEVO_UPDATE" --template "$P09" 2>&1) || c=$?; tap_status "$c" 0
[ "$c" -eq 0 ] && ! grep -q Traceback <<<"$s"; tap_check $? "[0.9] un .agent-kit.json con solo algunas claves viejas se migra igual, sin traceback"
python3 -c "import json,sys; k=json.load(open('$D/.agent-kit.json')); sys.exit(0 if k.get('language')=='en' and k.get('project')=='Demo' else 1)"
tap_check $? "[0.9] sin fecha en las claves viejas, igual queda language: en"
python3 -c "import json,sys; t=json.load(open('$D/.github/team.json')); sys.exit(0 if t['members'][0]['name']=='rojo' else 1)"
tap_check $? "[0.9] no traduce los nombres de las personas de team.json"
es -f "$D/docs/agentes/mi-guia.md" && grep -q "docs/agentes" <<<"$s" && grep -qi "own files\|your own" <<<"$s"
tap_check $? "[0.9] una carpeta vieja con archivos propios no se mueve y el resumen lo avisa"

D="$TMP/claves-viejas-chico"
proyecto "$D" chico
(cd "$D" && python3 -c "import json; k=json.load(open('.agent-kit.json')); json.dump({'proyecto': 'Demo', 'rama_base': 'main', 'modo': 'chico', 'fecha': k['date'], 'archivos': k['files']}, open('.agent-kit.json', 'w'))" && git commit -qam claves) >/dev/null 2>&1
c=0; s=$(trap - ERR; cd "$D" && AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py 2>&1) || c=$?; tap_status "$c" 1
[ "$c" -ne 0 ] && grep -q "0.9" <<<"$s" && grep -q "update.py" <<<"$s" && grep -qi "download" <<<"$s" && ! grep -q Traceback <<<"$s"; tap_check $? "grow.py con las claves viejas de .agent-kit.json explica que es de 0.9, cómo bajar update.py y sale con error, sin traceback"

# Migración a la validación estructurada del rojo (#154, ADR-002 D8): los proyectos que no tienen la sección
# `red` en docs/agents-map.json la reciben, con un aviso de cómo configurar su stack.
cat >"$TMP/map-view.py" <<'PY'
import json, sys
m = json.load(open("docs/agents-map.json"))
q = sys.argv[1]
if q == "names":
    print(",".join(x["name"] for x in m.get("red", [])))
elif q == "keys":
    print(",".join(m))
elif q == "bash":
    e = [x for x in m.get("red", []) if x.get("name") == "bash"]
    print(len(e), e[0]["format"], e[0]["when"][0], "{out}" in e[0]["run"]) if e else print(0)
elif q == "propio":
    print(m.get("propio"), ",".join(m.get("ignore_check", [])), len(m.get("docs", [])))
PY
cat >"$TMP/mapa-red.py" <<'PY'
import json, sys
m = json.load(open("docs/agents-map.json"))
for k in sys.argv[1:]:
    m.pop(k, None)
m["docs"] = []; m["sensitive"] = []; m["verify"] = []  # el proyecto completó sus rutas: check-docs.py solo mira lo demás
m["ignore_check"] = m.get("ignore_check", []) + ["propio/**"]
json.dump(m, open("docs/agents-map.json", "w"), indent=2)
PY
D="$TMP/sin-red"
proyecto "$D" completo
cd "$D" || exit 1
python3 "$TMP/mapa-red.py" red
git add -A
git commit -qm "mapa de un proyecto 0.9, sin red"
tap_run s 0 python3 scripts/update.py --template "$P"
m=$(python3 "$TMP/map-view.py" bash 2>&1)
[ "$m" = "1 junit **/test-*.sh True" ]
tap_check $? "update agrega la sección red con la entrada bash del kit a un mapa que no la tiene"
grep -q "red-per-runner" <<<"$s"
tap_check $? "update avisa que agregó red y remite a la guía por runner"
m=$(python3 "$TMP/map-view.py" propio 2>&1)
[[ "$m" == "None "*propio/**" 0" ]]
tap_check $? "update conserva lo que el proyecto ya tenía en el mapa al agregar red"
git add -A
tap_run s 0 python3 scripts/agents/check-docs.py
tap_check $? "el proyecto 0.9 actualizado pasa check-docs.py con la sección red"
cd "$TMP" || exit 1

# El glosario y el mapa de contextos (ADR-003 D2, D5, #217): en el repo del kit es un error que falten o no estén enlazados; en un
# proyecto es un aviso, como el índice de ADRs: después de un update el README del kit puede quedar en pending/ y el CI de docs del
# proyecto no tiene que ponerse rojo por eso.
D="$TMP/glosario-aviso"
proyecto "$D" completo
cd "$D" || exit 1
cp "$RAIZ/scripts/agents/check-docs.py" "$RAIZ/scripts/agents/agents_map.py" scripts/agents/
python3 "$TMP/mapa-red.py"
for f in docs/README.md docs/README.es.md docs/llms.txt docs/llms.es.txt; do
  [ -f "$f" ] && perl -ni -e 'print unless /reference\/(glossary|contexts)\.md/' "$f"
done
git add -A
git commit -qm "proyecto con los índices sin el glosario"
tap_run s 0 python3 scripts/agents/check-docs.py
tap_check $? "en un proyecto, el glosario sin enlace desde el índice no hace fallar check-docs.py"
[[ "$s" == *"Warning: docs/README.md: does not link docs/reference/glossary.md"* ]]
tap_check $? "en un proyecto, el glosario sin enlace desde el índice se avisa y se nombra"
cd "$TMP" || exit 1

D="$TMP/con-red-propia"
proyecto "$D" completo
cd "$D" || exit 1
python3 - <<'PY'
import json
m = json.load(open("docs/agents-map.json"))
m["red"] = [{"name": "pytest", "when": ["**/test_*.py"], "run": "python3 -m pytest --junitxml={out}", "format": "junit"}]
json.dump(m, open("docs/agents-map.json", "w"), indent=2)
PY
git add -A
git commit -qm "red propia"
tap_run s 0 python3 scripts/update.py --template "$P"
m=$(python3 "$TMP/map-view.py" names 2>&1)
[ "$m" = "pytest" ]
tap_check $? "update no toca una sección red que el proyecto ya definió"
cd "$TMP" || exit 1

D="$TMP/chico-sin-mapa"
proyecto "$D" chico
cd "$D" || exit 1
git rm -q docs/agents-map.json
python3 -c "import json; k=json.load(open('.agent-kit.json')); k['files'].pop('docs/agents-map.json'); json.dump(k, open('.agent-kit.json', 'w'), indent=2)"
git add -A
git commit -qm "chico de antes de la sección red: sin mapa"
tap_run s 0 python3 scripts/update.py --template "$P"
m=$(python3 "$TMP/map-view.py" keys 2>&1)
n=$(python3 "$TMP/map-view.py" names 2>&1)
[ "$m $n" = "red bash" ]
tap_check $? "update crea el mapa mínimo con solo red en un proyecto chico que no tiene mapa"
cd "$TMP" || exit 1

D="$TMP/crece-con-red"
proyecto "$D" chico
cd "$D" || exit 1
python3 - <<'PY'
import json
m = json.load(open("docs/agents-map.json"))
m["red"][0]["name"] = "mi-stack"
json.dump(m, open("docs/agents-map.json", "w"), indent=2)
PY
git add -A
git commit -qm "red propia en el chico"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
m=$(python3 "$TMP/map-view.py" keys 2>&1)
n=$(python3 "$TMP/map-view.py" names 2>&1)
[[ ",$m," == *,docs,*sensitive,*verify,*required,* && "$n" = "mi-stack" ]]
tap_check $? "grow conserva la sección red del proyecto chico y completa el resto del mapa completo"
! [ -e ".agent-kit/pending/docs/agents-map.json" ]
tap_check $? "grow no deja el mapa en pendientes: lo completa"
cd "$TMP" || exit 1

D="$TMP/crece-sin-red"
proyecto "$D" chico
cd "$D" || exit 1
echo '{}' >docs/agents-map.json
git add -A
git commit -qm "mapa chico vacío"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
m=$(python3 "$TMP/map-view.py" keys 2>&1)
n=$(python3 "$TMP/map-view.py" names 2>&1)
[[ ",$m," == *,docs,* && "$n" = "bash" ]]
tap_check $? "grow agrega la entrada bash de red a un mapa chico que no la tiene"
grep -q "red-per-runner" <<<"$s"
tap_check $? "grow avisa de la guía por runner cuando agrega red"
cd "$TMP" || exit 1

# Un mapa que no se puede leer (no es JSON): el aviso no dice que se agregó nada, y cada script lo deja como estaba.
D="$TMP/mapa-roto"
proyecto "$D" completo
cd "$D" || exit 1
printf 'esto no es json\n' >docs/agents-map.json
git add -A
git commit -qm "mapa roto"
tap_run s 0 python3 scripts/update.py --template "$P"
grep -q "I added" <<<"$s"
[ $? -eq 1 ]
tap_check $? "update con un mapa ilegible avisa que no pudo revisar red, sin decir que agregó algo"
grep -q "red-per-runner" <<<"$s"
tap_check $? "update con un mapa ilegible remite a la guía por runner"
cd "$TMP" || exit 1

D="$TMP/crece-mapa-roto"
proyecto "$D" chico
cd "$D" || exit 1
printf 'esto no es json\n' >docs/agents-map.json
git add -A
git commit -qm "mapa chico roto"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
m=$(cat docs/agents-map.json)
[ "$m" = "esto no es json" ]
tap_check $? "grow con un mapa ilegible no lo toca"
es -f ".agent-kit/pending/docs/agents-map.json"
tap_check $? "grow con un mapa ilegible deja el mapa completo en pending"
cd "$TMP" || exit 1

# El error de 2.0.0 por format "tap" (ADR-002 D8, #226 y #233): update.py reemplaza la entrada bash del kit por la de JUnit (solo su run
# y su format: el when y el timeout del proyecto quedan), no convierte, borra ni reescribe otra entrada tap y, al final de su
# resumen, imprime en stderr el mismo texto que el error de red.sh. La entrada del kit no lo imprime.
ERROR_TAP() { printf 'red stack '"'"'%s'"'"': format "tap" was removed in 2.0.0; use "junit" (docs/guides/red-per-runner.md)' "$1"; }
# Un run publicado por el kit en v1.1.0 (con los espacios cambiados: el kit normaliza los espacios al compararlo).
# shellcheck disable=SC2016  # el run es un literal: no se expande nada
RUN_KIT_1_1='rc=0;  while IFS= read -r -d '"''"' t; do TAP_OUT={out} bash "$t" </dev/null || rc=1; grep -qxF "# file: $t" {out} || echo "Bail out! $t wrote no TAP" >>{out}; done < <(git diff -z --name-only --diff-filter=AM HEAD^ HEAD -- '"':(glob)**/test-*.sh'"'); exit $rc'
# poner_mapa_red <dir> <json de la sección red>: reemplaza la sección red del mapa del proyecto y la commitea.
poner_mapa_red() {
  RED_JSON="$2" python3 - "$1/docs/agents-map.json" <<'PY'
import json, os, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
m["red"] = json.loads(os.environ["RED_JSON"])
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(m, ensure_ascii=False, indent=2) + "\n")
PY
  prep "$1" git add -A
  prep "$1" git commit -qm "mapa red"
}
# campo_red <dir> <name> <campo>: el valor (JSON) de ese campo de la entrada de red, o nada
campo_red() {
  python3 - "$1/docs/agents-map.json" "$2" "$3" <<'PY'
import json, sys
for e in json.load(open(sys.argv[1], encoding="utf-8")).get("red", []):
    if e.get("name") == sys.argv[2] and sys.argv[3] in e:
        print(json.dumps(e[sys.argv[3]]))
PY
}
kit_run=$(campo_red "$P" bash run)

D="$TMP/red-tap-kit"
proyecto "$D" completo
poner_mapa_red "$D" "[{\"name\":\"bash\",\"when\":[\"tests/**/test-*.sh\"],\"format\":\"tap\",\"run\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$RUN_KIT_1_1"),\"timeout\":900}]"
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>"$TMP/stderr.txt") || c=$?; tap_status "$c" 0
err=$(<"$TMP/stderr.txt")
[ "$(campo_red "$D" bash format)" = '"junit"' ]; tap_check $? "[tap 2.0.0] la entrada bash del kit pasa a format junit"
[ "$(campo_red "$D" bash run)" = "$kit_run" ]; tap_check $? "[tap 2.0.0] la entrada bash del kit toma el run actual del kit"
[ "$(campo_red "$D" bash when)" = '["tests/**/test-*.sh"]' ]; tap_check $? "[tap 2.0.0] reemplazar la entrada del kit conserva el when del proyecto"
[ "$(campo_red "$D" bash timeout)" = 900 ]; tap_check $? "[tap 2.0.0] reemplazar la entrada del kit conserva el timeout del proyecto"
[[ "$s" != *'was removed in 2.0.0'* ]]; tap_check $? "[tap 2.0.0] la entrada bash del kit no imprime el error en stdout"
[[ "$err" != *'was removed in 2.0.0'* ]]; tap_check $? "[tap 2.0.0] la entrada bash del kit no imprime el error en stderr"

# El run que publicó 2.0.0 (--diff-filter=AMR, ya en JUnit) es del kit: un proyecto que lo tiene recibe el run actual (#264, AMRC).
RUN_KIT_2_0=$(cat <<'RUN'
rc=0; tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT; while IFS= read -r -d '' t; do TAP_OUT=$tmp bash "$t" </dev/null || rc=1; done < <(git diff -z --name-only --diff-filter=AMR HEAD^ HEAD -- ':(glob)**/test-*.sh'); { echo '<testsuites>'; cat "$tmp"; echo '</testsuites>'; } >{out}; exit $rc
RUN
)
D="$TMP/red-2-0-0-kit"
proyecto "$D" completo
poner_mapa_red "$D" "[{\"name\":\"bash\",\"when\":[\"tests/**/test-*.sh\"],\"format\":\"junit\",\"run\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$RUN_KIT_2_0"),\"timeout\":900}]"
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>"$TMP/stderr.txt") || c=$?; tap_status "$c" 0
[[ "$(campo_red "$D" bash run)" == *'--diff-filter=AMRC '* ]]; tap_check $? "[2.0.0] la entrada bash que publicó 2.0.0 toma el run actual del kit (AMRC)"
[ "$(campo_red "$D" bash when)" = '["tests/**/test-*.sh"]' ]; tap_check $? "[2.0.0] reemplazar la entrada de 2.0.0 conserva el when del proyecto"
[ "$(campo_red "$D" bash timeout)" = 900 ]; tap_check $? "[2.0.0] reemplazar la entrada de 2.0.0 conserva el timeout del proyecto"

D="$TMP/red-tap-propia"
proyecto "$D" completo
bash_tocado="$RUN_KIT_1_1; echo mio"
poner_mapa_red "$D" "[{\"name\":\"bash\",\"when\":[\"**/test-*.sh\"],\"format\":\"tap\",\"run\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$bash_tocado")},{\"name\":\"node\",\"when\":[\"**/*.test.js\"],\"format\":\"tap\",\"run\":\"node --test --test-reporter=tap > {out}\"},{\"name\":\"py\",\"when\":[\"**/test_*.py\"],\"format\":\"junit\",\"run\":\"pytest --junitxml={out}\"}]"
antes_map=$(<"$D/docs/agents-map.json")
c=0; s=$(trap - ERR; cd "$D" && python3 scripts/update.py --template "$P" 2>"$TMP/stderr.txt") || c=$?; tap_status "$c" 0
err=$(<"$TMP/stderr.txt")
despues_map=$(<"$D/docs/agents-map.json")
[ "$despues_map" = "$antes_map" ]; tap_check $? "[tap 2.0.0] una entrada tap propia (y una bash que el proyecto cambió) queda como estaba: no la convierte, borra ni reescribe"
grep -qxF "$(ERROR_TAP node)" <<<"$err"; tap_check $? "[tap 2.0.0] una entrada tap propia imprime el error con el texto exacto de red.sh"
grep -qxF "$(ERROR_TAP bash)" <<<"$err"; tap_check $? "[tap 2.0.0] una entrada bash que el proyecto cambió es propia e imprime el error"
[[ "$s" != *'which 2.0.0 removes'* ]]; tap_check $? "[tap 2.0.0] update.py ya no imprime el aviso de 1.x en stdout"
[[ "$err" != *'which 2.0.0 removes'* ]]; tap_check $? "[tap 2.0.0] update.py ya no imprime el aviso de 1.x en stderr"
[[ "$s" != *"red stack 'py'"* ]]; tap_check $? "[tap 2.0.0] una entrada junit no imprime el error en stdout"
[[ "$err" != *"red stack 'py'"* ]]; tap_check $? "[tap 2.0.0] una entrada junit no imprime el error en stderr"
[[ "$s" != *'was removed in 2.0.0'* ]]; tap_check $? "[tap 2.0.0] el error va a stderr, no a stdout"
ultima=$(tail -n 1 <<<"$s")
[[ "$ultima" == *"Commit and open a PR"* ]]; tap_check $? "[tap 2.0.0] stdout termina con el último paso del resumen, sin el error"
[ "$(tail -n 1 <<<"$err")" = "$(ERROR_TAP node)" ]; tap_check $? "[tap 2.0.0] el error de la última entrada tap propia es la última línea de stderr"
[ "$(grep -c 'was removed in 2.0.0' <<<"$err")" = 2 ]; tap_check $? "[tap 2.0.0] stderr tiene un error por entrada tap propia, ni más ni menos"

# El orden de los dos streams juntos (2>&1, como lo ve la persona en la terminal): las líneas del error de 2.0.0 son las últimas,
# después del último paso del resumen. Sin el flush de stdout antes de escribir en stderr, el error se adelanta cuando stdout es un pipe.
D="$TMP/red-tap-orden"
proyecto "$D" completo
poner_mapa_red "$D" "[{\"name\":\"bash\",\"when\":[\"**/test-*.sh\"],\"format\":\"tap\",\"run\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$RUN_KIT_1_1; echo mio")},{\"name\":\"node\",\"when\":[\"**/*.test.js\"],\"format\":\"tap\",\"run\":\"node --test --test-reporter=tap > {out}\"}]"
cd "$D" || exit 1
tap_run s 0 python3 scripts/update.py --template "$P"
cd "$TMP" || exit 1
ultimas=$(tail -n 2 <<<"$s")
[ "$ultimas" = "$(ERROR_TAP bash)"$'\n'"$(ERROR_TAP node)" ]; tap_check $? "[tap 2.0.0] con stdout y stderr juntos, las líneas del error son las últimas"
paso=$(tail -n 3 <<<"$s" | head -n 1)
[[ "$paso" == *"3. Commit and open a PR"* ]]; tap_check $? "[tap 2.0.0] con stdout y stderr juntos, el error va después de '3. Commit and open a PR'"

# El glosario y el mapa de contextos en los proyectos que ya existen (ADR-003, #219): update.py, y grow.py al pasar de chico a completo.
# Un proyecto "anterior al glosario" es uno iniciado con la plantilla de la prueba al que se le quitan los dos archivos (y su registro
# en .agent-kit.json), la sección contexts del mapa y los enlaces de los índices: así lo encuentra una versión que ya los trae.
cat >"$TMP/quitar-ddd.py" <<'PY'
import json, os, re, sys
chico = sys.argv[1] == "chico"
rutas = ["docs/glossary.md", "docs/contexts.md"] if chico else ["docs/reference/glossary.md", "docs/reference/contexts.md"]
kit = json.load(open(".agent-kit.json"))
for r in rutas:
    if os.path.exists(r):
        os.remove(r)
    kit["files"].pop(r, None)
json.dump(kit, open(".agent-kit.json", "w"), indent=2)
m = json.load(open("docs/agents-map.json"))
if not chico:
    m.pop("contexts", None)
    m["docs"] = []; m["sensitive"] = []; m["verify"] = []
    m["propio"] = 1
    json.dump(m, open("docs/agents-map.json", "w"), indent=2)
for idx in ("docs/README.md", "docs/README.es.md", "docs/llms.txt", "docs/llms.es.txt"):
    if os.path.exists(idx):
        lineas = [l for l in open(idx).read().split("\n") if not re.search(r"\((reference/)?(glossary|contexts)\.md\)", l)]
        open(idx, "w").write("\n".join(lineas))
PY
cat >"$TMP/ddd-view.py" <<'PY'
import json, sys
m = json.load(open("docs/agents-map.json"))
q = sys.argv[1]
if q == "contexts":
    print(json.dumps(m.get("contexts", "sin sección"), sort_keys=True))
elif q == "propio":
    print(m.get("propio"))
elif q == "registrado":
    print(sorted(k for k in json.load(open(".agent-kit.json"))["files"] if k in ("docs/glossary.md", "docs/contexts.md")))
elif q == "version":
    k = json.load(open(".agent-kit.json"))
    k["version"] = "0.1.0"
    json.dump(k, open(".agent-kit.json", "w"), indent=2)
PY
# viejo_ddd <dir> <chico|completo>: un proyecto de la plantilla v0.1.0 anterior al glosario, commiteado.
viejo_ddd() {
  proyecto "$1" "$2"
  prep "$1" python3 "$TMP/quitar-ddd.py" "$2"
  prep "$1" git add -A
  prep "$1" git commit -qm "proyecto anterior al glosario"
}

D="$TMP/ddd-completo"
viejo_ddd "$D" completo
cd "$D" || exit 1
tap_run s 0 python3 scripts/update.py --template "$P"
es -f docs/reference/glossary.md && es -f docs/reference/contexts.md
tap_check $? "[ddd completo] update trae el glosario y el mapa de contextos"
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = "[]" ]
tap_check $? "[ddd completo] update agrega la sección contexts vacía al mapa"
m=$(python3 "$TMP/ddd-view.py" propio 2>&1)
[ "$m" = "1" ]
tap_check $? "[ddd completo] update conserva lo propio del mapa al agregar contexts"
[[ "$s" == *"docs/README.md does not link docs/reference/glossary.md"* ]]
tap_check $? "[ddd completo] update avisa que docs/README.md no enlaza el glosario"
[[ "$s" == *"(reference/glossary.md)"* ]]
tap_check $? "[ddd completo] el aviso dice qué enlace agregar al índice"
[[ "$s" != *"check-docs.py warns"* ]]
tap_check $? "[ddd completo] el resumen no dice que check-docs.py avisa: en un repo instalado no mira los índices"
[[ "$s" == *"docs/llms.txt does not link docs/reference/contexts.md"* ]]
tap_check $? "[ddd completo] update avisa que docs/llms.txt no enlaza el mapa de contextos"
printf '\n- [Glossary](reference/glossary.md)\n- [Contexts](reference/contexts.md)\n' >>docs/README.md
printf '\n- [Glossary](reference/glossary.md)\n- [Contexts](reference/contexts.md)\n' >>docs/llms.txt
git add -A
tap_run s 0 python3 scripts/agents/check-docs.py
[[ "$s" != *"does not link"* ]]
tap_check $? "[ddd completo] con los enlaces que el aviso pide, check-docs.py no se queja de los índices"
cd "$TMP" || exit 1

# Un mapa que el proyecto ya llenó no se toca.
D="$TMP/ddd-completo-lleno"
viejo_ddd "$D" completo
cd "$D" || exit 1
python3 - <<'PY'
import json
m = json.load(open("docs/agents-map.json"))
m["contexts"] = [{"name": "Billing", "paths": ["?src/billing/**"], "depends_on": []}]
json.dump(m, open("docs/agents-map.json", "w"), indent=2)
PY
git add -A
git commit -qm "contextos propios"
tap_run s 0 python3 scripts/update.py --template "$P"
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = '[{"depends_on": [], "name": "Billing", "paths": ["?src/billing/**"]}]' ]
tap_check $? "[ddd completo] update no toca la sección contexts que el proyecto ya llenó"
cd "$TMP" || exit 1

# Un mapa ilegible queda como estaba y el resumen dice qué agregar a mano.
D="$TMP/ddd-mapa-roto"
viejo_ddd "$D" completo
cd "$D" || exit 1
printf 'esto no es json\n' >docs/agents-map.json
git add -A
git commit -qm "mapa roto"
tap_run s 0 python3 scripts/update.py --template "$P"
m=$(cat docs/agents-map.json 2>&1)
[ "$m" = "esto no es json" ]
tap_check $? "[ddd mapa roto] update deja el mapa ilegible como estaba"
pat='could not add its `contexts` section'
[[ "$s" == *"$pat"* ]]
tap_check $? "[ddd mapa roto] update avisa que no pudo agregar contexts y que va a mano"
cd "$TMP" || exit 1

D="$TMP/ddd-chico"
viejo_ddd "$D" chico
cd "$D" || exit 1
tap_run s 0 python3 scripts/update.py --template "$P"
es -f docs/glossary.md && es -f docs/contexts.md
tap_check $? "[ddd chico] update trae docs/glossary.md y docs/contexts.md"
[[ "$s" == *"docs/README.md does not link docs/glossary.md"* ]]
tap_check $? "[ddd chico] update avisa que docs/README.md no enlaza el glosario"
[[ "$s" == *"docs/README.md does not link docs/contexts.md"* ]]
tap_check $? "[ddd chico] update avisa que docs/README.md no enlaza el mapa de contextos"
[[ "$s" != *"llms.txt does not link"* ]]
tap_check $? "[ddd chico] update no pide enlaces en llms.txt, que el check del chico no mira"
m=$(python3 "$TMP/map-view.py" keys 2>&1)
[ "$m" = "red" ]
tap_check $? "[ddd chico] el mapa chico sigue con solo red"
cd "$TMP" || exit 1

# grow.py: de chico a completo.
D="$TMP/ddd-crece"
proyecto "$D" chico
cd "$D" || exit 1
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
[ ! -e docs/glossary.md ] && [ ! -e docs/contexts.md ]
tap_check $? "[grow ddd] sin tocar, el glosario y los contextos chicos se van y queda lo de docs/reference/"
es -f docs/reference/glossary.md && es -f docs/reference/contexts.md
tap_check $? "[grow ddd] el proyecto completo trae docs/reference/glossary.md y contexts.md"
grep -q '| Name in the code | Context |' docs/reference/glossary.md
tap_check $? "[grow ddd] sin tocar, docs/reference/glossary.md es el del perfil completo y no el chico movido"
[ ! -e .agent-kit/pending/docs/reference/glossary.md ] && [ ! -e .agent-kit/pending/docs/reference/contexts.md ]
tap_check $? "[grow ddd] sin tocar, nada de lo chico va a pending"
[[ "$s" != *"check-docs.py warns"* ]]
tap_check $? "[grow ddd] el resumen no promete que check-docs.py avisa de los enlaces"
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = "[]" ]
tap_check $? "[grow ddd] con la tabla sin llenar, contexts queda vacía"
[[ "$s" != *'to the `contexts` section'* ]]
tap_check $? "[grow ddd] con la tabla sin llenar no avisa de nada a mano"
[[ "$s" != *"does not link"* ]]
tap_check $? "[grow ddd] el índice completo que trae grow enlaza el glosario y los contextos"
cd "$TMP" || exit 1

D="$TMP/ddd-crece-lleno"
proyecto "$D" chico
cd "$D" || exit 1
mkdir -p src/billing src/accounts
echo x >src/billing/a.txt
echo x >src/accounts/b.txt
printf '# Glossary — Demo\n\n| Term | Definition | Name in code |\n|---|---|---|\n| Invoice | what is charged | Invoice |\n' >docs/glossary.md
cat >docs/contexts.md <<'MD'
# Contexts — Demo

| Context | Responsibility | Own terms | Depends on | Code paths |
|---|---|---|---|---|
| Billing | charges | Invoice | Accounts | `src/billing/` |
| Accounts | users | User | - | `src/accounts/`, `src/shared/*.py` |
MD
git add -A
git commit -qm "glosario y contextos llenos"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
[ ! -e docs/glossary.md ] && [ ! -e docs/contexts.md ]
tap_check $? "[grow ddd lleno] los archivos chicos del proyecto se mueven a docs/reference/"
grep -q "what is charged" docs/reference/glossary.md
tap_check $? "[grow ddd lleno] el glosario del proyecto llega a docs/reference/ con su contenido"
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = '[{"depends_on": ["Accounts"], "name": "Billing", "paths": ["src/billing/**"]}, {"depends_on": [], "name": "Accounts", "paths": ["src/accounts/**", "?src/shared/*.py"]}]' ]
tap_check $? "[grow ddd lleno] la columna de rutas pasa a contexts, y la ruta que no matchea ningún archivo queda opcional con ?"
[[ "$s" == *"?src/shared/*.py"* ]]
tap_check $? "[grow ddd lleno] el resumen dice qué ruta marcó como opcional"
m=$(python3 "$TMP/ddd-view.py" registrado 2>&1)
[ "$m" = "[]" ]
tap_check $? "[grow ddd lleno] lo que grow movió o borró sale del registro de .agent-kit.json"
git add -A
git commit -qm "tras grow"
rm -rf .agent-kit/pending
python3 "$TMP/ddd-view.py" version >/dev/null
git add -A
git commit -qm "version vieja"
tap_run s 0 python3 scripts/update.py --template "$P"
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[[ "$m" == *'"name": "Billing"'* ]]
tap_check $? "[grow ddd lleno] un update después de grow no pierde los contextos que grow pasó al mapa"
cd "$TMP" || exit 1

D="$TMP/ddd-crece-roto"
proyecto "$D" chico
cd "$D" || exit 1
cat >docs/contexts.md <<'MD'
# Contexts — Demo

| Context | Responsibility | Own terms | Depends on | Code paths |
|---|---|---|---|---|
| Billing | charges | Invoice | none | |
MD
git add -A
git commit -qm "tabla a medias"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = "[]" ]
tap_check $? "[grow ddd a medias] una tabla que no se puede pasar deja contexts vacía"
[[ "$s" == *'to the `contexts` section'*"by hand"* ]]
tap_check $? "[grow ddd a medias] grow avisa que la tabla va a mano a la sección contexts"
es -f docs/reference/contexts.md && grep -q "Billing" docs/reference/contexts.md
tap_check $? "[grow ddd a medias] la tabla del proyecto no se pierde"
cd "$TMP" || exit 1

D="$TMP/ddd-crece-indice"
proyecto "$D" chico
cd "$D" || exit 1
printf '\nnota del proyecto\n' >>docs/README.md
git add -A
git commit -qm "índice propio"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
[[ "$s" == *"docs/README.md does not link docs/reference/glossary.md"* ]]
tap_check $? "[grow ddd indice] con el índice modificado por el proyecto, grow avisa qué enlazar"
cd "$TMP" || exit 1

# Lo que marcó la revisión: una tabla de leyenda antes de la de contextos, una carpeta de la tabla que todavía no existe, y un
# contexts.md que no se mueve porque ya hay otro en docs/reference/ (la tabla vieja no pasa al mapa).
D="$TMP/ddd-crece-leyenda"
proyecto "$D" chico
cd "$D" || exit 1
mkdir -p src/billing
echo x >src/billing/a.txt
cat >docs/contexts.md <<'MD'
# Contexts — Demo

| Column | Meaning |
|---|---|
| Context | the name |

| Context | Responsibility | Own terms | Depends on | Code paths |
|---|---|---|---|---|
| Billing | charges | Invoice | none | `src/billing/`, `src/futuro/` |
MD
git add -A
git commit -qm "tabla con leyenda"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = '[{"depends_on": [], "name": "Billing", "paths": ["src/billing/**", "?src/futuro/**"]}]' ]
tap_check $? "[grow ddd leyenda con opcional] toma la tabla de cinco columnas aunque haya otra antes; la carpeta que existe queda carpeta/** y la que no, opcional con ?"
cd "$TMP" || exit 1

D="$TMP/ddd-crece-ocupado"
proyecto "$D" chico
cd "$D" || exit 1
mkdir -p docs/reference
printf '# Contexts propios\n' >docs/reference/contexts.md
printf '# Contexts — Demo\n\n| Context | Responsibility | Own terms | Depends on | Code paths |\n|---|---|---|---|---|\n| Billing | charges | Invoice | none | `src/billing/` |\n' >docs/contexts.md
git add -A
git commit -qm "contexts en las dos rutas"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
es -f docs/contexts.md && grep -q "Contexts propios" docs/reference/contexts.md
tap_check $? "[grow ddd ocupado] si docs/reference/contexts.md ya existe, no mueve ni pisa ninguno de los dos"
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = "[]" ]
tap_check $? "[grow ddd ocupado] la tabla que no se movió no pasa al mapa"
[[ "$s" == *"Not moved: docs/contexts.md"* ]]
tap_check $? "[grow ddd ocupado] grow dice qué no movió"
cd "$TMP" || exit 1

# Una tabla que no se puede pasar tal cual no se pasa a medias: Depends on con algo que no es un contexto de la tabla, una tabla con otra
# cantidad de columnas (solo una vacía o en TODO calla) y sin ninguna tabla.
D="$TMP/ddd-crece-depende"
proyecto "$D" chico
cd "$D" || exit 1
mkdir -p src/billing
echo x >src/billing/a.txt
printf '# Contexts — Demo\n\n| Context | Responsibility | Own terms | Depends on | Code paths |\n|---|---|---|---|---|\n| Billing | charges | Invoice | Accounts | `src/billing/` |\n' >docs/contexts.md
git add -A
git commit -qm "depende de algo que no está"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
m=$(python3 "$TMP/ddd-view.py" contexts 2>&1)
[ "$m" = "[]" ]
tap_check $? "[grow ddd depende] un Depends on que no es un contexto de la tabla deja contexts vacía"
[[ "$s" == *"Accounts"*"by hand"* ]]
tap_check $? "[grow ddd depende] grow avisa que va a mano y nombra el contexto que falta"
cd "$TMP" || exit 1

D="$TMP/ddd-crece-columnas"
proyecto "$D" chico
cd "$D" || exit 1
printf '# Contexts — Demo\n\n| Context | Responsibility | Code paths |\n|---|---|---|\n| Billing | charges | `src/billing/` |\n' >docs/contexts.md
git add -A
git commit -qm "tabla de tres columnas"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
[[ "$s" == *'to the `contexts` section'*"by hand"* ]]
tap_check $? "[grow ddd columnas] una tabla con otra cantidad de columnas no pasa en silencio: avisa que va a mano"
cd "$TMP" || exit 1

D="$TMP/ddd-crece-sin-tabla"
proyecto "$D" chico
cd "$D" || exit 1
printf '# Contexts — Demo\n\nBilling cobra. Accounts maneja usuarios.\n' >docs/contexts.md
git add -A
git commit -qm "contextos en prosa"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
[[ "$s" == *'to the `contexts` section'*"by hand"* ]]
tap_check $? "[grow ddd sin tabla] un contexts.md del proyecto sin ninguna tabla no pasa en silencio: avisa que va a mano"
cd "$TMP" || exit 1

# El índice que el proyecto modificó y todavía enlaza los archivos chicos que grow movió o borró: grow lo avisa.
D="$TMP/ddd-crece-enlace-viejo"
proyecto "$D" chico
cd "$D" || exit 1
printf '\nnota del proyecto\n' >>docs/README.md
git add -A
git commit -qm "índice propio con enlaces a lo chico"
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
[[ "$s" == *"docs/README.md links docs/glossary.md"* ]]
tap_check $? "[grow ddd enlace viejo] avisa que el índice modificado sigue enlazando docs/glossary.md, que grow quitó"
cd "$TMP" || exit 1

# Un proyecto que ya tiene los enlaces en sus índices no recibe el aviso de enlace.
D="$TMP/ddd-completo-enlazado"
viejo_ddd "$D" completo
cd "$D" || exit 1
python3 - <<'PY'
import os
for idx in ("docs/README.md", "docs/README.es.md", "docs/llms.txt", "docs/llms.es.txt"):
    if os.path.exists(idx):
        with open(idx, "a") as f:
            f.write("\n- [Glossary](reference/glossary.md)\n- [Contexts](reference/contexts.md)\n")
PY
git add -A
git commit -qm "índices que ya enlazan"
tap_run s 0 python3 scripts/update.py --template "$P"
[[ "$s" != *"does not link"* ]]
tap_check $? "[ddd completo enlazado] update no avisa de enlaces que los índices ya tienen"
cd "$TMP" || exit 1

# --small no tiene sección contexts (ADR-003 D3): con un mapa ilegible no se pide agregarla a mano.
D="$TMP/ddd-chico-mapa-roto"
viejo_ddd "$D" chico
cd "$D" || exit 1
printf 'esto no es json\n' >docs/agents-map.json
git add -A
git commit -qm "mapa chico roto"
tap_run s 0 python3 scripts/update.py --template "$P"
[[ "$s" != *'"contexts": []'* ]]
tap_check $? "[ddd chico mapa roto] update --small con un mapa ilegible no pide agregar contexts"
cd "$TMP" || exit 1

tap_done
