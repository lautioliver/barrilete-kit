#!/usr/bin/env bash
# shellcheck disable=SC2319  # "<condition>; tap_check $?" is the pattern of the tests (tap.sh)
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
# Ningún git de la prueba corre gc ni mantenimiento en segundo plano: un gc que empaqueta objetos sueltos mientras otro git
# clona o lee ese repo puede romperlo ("failed to copy file ... No such file or directory"), a veces y solo en el CI.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=gc.auto GIT_CONFIG_VALUE_0=0 GIT_CONFIG_KEY_1=maintenance.auto GIT_CONFIG_VALUE_1=false

# La plantilla tal como está en el árbol, en un repo con dos versiones etiquetadas.
P="$TMP/plantilla"
mkdir -p "$P"
(cd "$RAIZ" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | (cd "$P" && tar -xf -)
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
  cd "$D" || exit 1
  tap_run s 0 python3 scripts/update.py --template "$P"
  cd "$TMP" || exit 1
  [ "$TAP_RC" -eq 0 ] && grep -q "Línea nueva de la plantilla v0.2." "$D/.claude/skills/debug/SKILL.md" && con_flow_line "$D" \
    && ! [ -e "$D/.agent-kit/pending/.claude/settings.json" ]
  tap_check $? "[<modo> --flow-line] update.py conserva el statusLine y flow_line: true" "[$modo --flow-line] update.py conserva el statusLine y flow_line: true"
done
D="$TMP/flow-crece"
proyecto "$D" chico v0.1.0 "" --flow-line
cd "$D" || exit 1
tap_run s 0 env AGENT_KIT_TEMPLATE="$P" python3 scripts/grow.py
cd "$TMP" || exit 1
[ "$TAP_RC" -eq 0 ] && grep -q '"mode": "full"' "$D/.agent-kit.json" && con_flow_line "$D"
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
[ "$m" = "1 tap **/test-*.sh True" ]
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

tap_done
