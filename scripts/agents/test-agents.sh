#!/usr/bin/env bash
# Tests de los subagentes (.claude/agents/) y de su validación en check-docs.py.
# Corre sobre una copia del repo (git archive), así no toca el working tree.
# Uso: bash scripts/agents/test-agents.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-agents-XXXXXX")
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
tap_at_exit "rm -rf \"\$TMP\""
# Uso: <condición>; tap_check $? "descripción"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
CONTRATO=docs/agents/subagent-contract.md
AGENTES=".claude/agents"

# Copia del repo con lo commiteado y lo que está en el working tree.
copia() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"
  (cd "$RAIZ" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | tar -xf - -C "$TMP/r"
  (cd "$TMP/r" && git init -q && git add -A && git commit -qm base)
}
check() { (cd "$TMP/r" && python3 scripts/agents/check-docs.py 2>&1); }
# check-docs sin errores de los subagentes. En un proyecto recién inicializado check-docs falla
# igual por los TODO del mapa, así que se mira solo lo de los subagentes.
sin_errores_agentes() { ! check | grep -q "$AGENTES\|subagent-contract"; }
frontmatter() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$1"; }

# 1. Los tres roles existen con su modelo y herramientas acotadas.
for par in implementer:sonnet implementer-light:haiku reviewer:opus; do
  rol=${par%%:*}; modelo=${par##*:}; f="$RAIZ/$AGENTES/$rol.md"
  fm=$(frontmatter "$f" 2>/dev/null)
  grep -qx "name: $rol" <<<"$fm"; tap_check $? "<rol>: existe con name: <rol>" "$rol: existe con name: $rol"
  grep -qx "model: $modelo" <<<"$fm"; tap_check $? "<rol>: model: <modelo>" "$rol: model: $modelo"
  grep -q "^tools: " <<<"$fm"; tap_check $? "<rol>: lista sus herramientas (tools:)" "$rol: lista sus herramientas (tools:)"
  grep -q "$CONTRATO" "$f" 2>/dev/null; tap_check $? "<rol>: remite al contrato de salida común" "$rol: remite al contrato de salida común"
done
! grep -q "Edit" <<<"$(frontmatter "$RAIZ/$AGENTES/reviewer.md" 2>/dev/null | grep '^tools:')"; tap_check $? "revisor: no puede editar código (Write solo para la revisión y la retro)"

# 2. El contrato de salida está en un solo lugar, con todos los resultados.
for r in pr question escalate dropped blockers; do
  grep -q "\`$r\`" "$RAIZ/$CONTRATO" 2>/dev/null; tap_check $? "el contrato define el resultado <r>" "el contrato define el resultado $r"
done
for k in result issue pr model role ci self-review summary "for the reviewer" questions reason retro; do
  grep -q "^$k: " "$RAIZ/$CONTRATO" 2>/dev/null; tap_check $? "el bloque de salida del contrato tiene la clave <k>" "el bloque de salida del contrato tiene la clave $k"
done
grep -Eq "agrega al final .review:.|adds .review:. at the end" "$RAIZ/$CONTRATO" 2>/dev/null; tap_check $? "el contrato dice que el revisor agrega review:"
! grep -Eq '^(resultado|modelo|rol|autorevision|resumen|para el revisor|consultas|motivo|revision):' "$RAIZ/$CONTRATO" 2>/dev/null; tap_check $? "el contrato no conserva claves de salida en español"
grep -q "retro.sh" "$RAIZ/$CONTRATO" 2>/dev/null; tap_check $? "el contrato dice que cada subagente guarda su retro con retro.sh"

# 3. El liviano dice exactamente cuándo escalar.
f="$RAIZ/$AGENTES/implementer-light.md"
grep -q "agents_map.py" "$f" 2>/dev/null && grep -Eq "rutas sensibles|sensitive paths" "$f" && grep -q "business-logic" "$f"
tap_check $? "implementer-light: escala por rutas sensibles (agents_map.py) o lógica de negocio"
f="$RAIZ/$AGENTES/implementer-light.md"
grep -q "agents_map.py.*error\|error.*agents_map.py" "$f" 2>/dev/null; tap_check $? "implementer-light: escala si agents_map.py no corre o sale con error"
grep -Eq "prioridad|take priority" "$f" 2>/dev/null; tap_check $? "implementer-light: dice qué tiene prioridad sobre consulta y soltado del contrato"
grep -q "BASE" "$RAIZ/$CONTRATO" 2>/dev/null; tap_check $? "el contrato dice cómo pasar BASE a los scripts"
f="$RAIZ/$AGENTES/reviewer.md"
! grep -q "FETCH_HEAD" "$f" 2>/dev/null && grep -q "headRefOid" "$f" 2>/dev/null; tap_check $? "revisor: trae el PR a una ref propia (no FETCH_HEAD) y comprueba headRefOid"

# 4. check-docs.py valida los subagentes.
copia
sin_errores_agentes; tap_check $? "check-docs no reporta errores en los subagentes del repo"
mkdir -p "$TMP/r/$AGENTES"
printf -- '---\nname: x\ndescription: d\ntools: Read\nmodel: gpt-4\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*model" <<<"$salida"; tap_check $? "check-docs rechaza un model que no es opus, sonnet ni haiku"
printf -- '---\nname: x\ndescription: d\nmodel: haiku\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*tools" <<<"$salida"; tap_check $? "check-docs rechaza un subagente sin tools"
printf -- '---\nname: x\ndescription: d\ntools: Read\nmodel: haiku\n---\nSin contrato.\n' >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*contract" <<<"$salida"; tap_check $? "check-docs rechaza un subagente que no remite al contrato"
printf -- '---\r\nname: x\r\ndescription: d\r\ntools: Read\r\nmodel: haiku\r\n---\r\nVer %s.\r\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
sin_errores_agentes; tap_check $? "check-docs acepta un subagente con fin de línea CRLF"
printf -- '---\nname: "x"\ndescription: d\ntools: Read\nmodel: "haiku"\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
sin_errores_agentes; tap_check $? "check-docs acepta valores entre comillas"

# 5. En un repo con .agent-kit.json, check-docs y los listados solo miran los archivos del kit.
copia
python3 - "$TMP/r" <<'PY'
import json, subprocess, sys
r = sys.argv[1]
archivos = subprocess.run(["git", "-C", r, "ls-files"], capture_output=True, text=True).stdout.split()
json.dump({"files": {a: "x" for a in archivos}}, open(r + "/.agent-kit.json", "w"))
PY
mkdir -p "$TMP/r/ajeno"
printf '# Ajeno\n\n[roto](no-existe.md)\n' >"$TMP/r/ajeno/README.md"
printf '#!/bin/sh\necho [ -z a ]\n' >"$TMP/r/ajeno/malo.sh"
printf '#!/bin/sh\nexit 1\n' >"$TMP/r/ajeno/test-propio.sh"
listar() { (cd "$TMP/r" && python3 scripts/agents/check-docs.py --list "$1" 2>/dev/null); }
# En un proyecto recién inicializado el check falla por los TODO del mapa: se mira solo lo ajeno.
salida=$(check); grep -q "^Docs\|^Warning" <<<"$salida" && ! grep -q "ajeno/README.md" <<<"$salida"; tap_check $? "con .agent-kit.json, un .md ajeno con link roto no falla el check"
lista=$(listar '*.sh'); grep -qx "scripts/agents/test-agents.sh" <<<"$lista"; tap_check $? "con .agent-kit.json, --list '*.sh' devuelve los scripts del kit"
! grep -q "^ajeno/" <<<"$lista"; tap_check $? "con .agent-kit.json, --list '*.sh' no devuelve los .sh ajenos"
lista=$(listar '*test-*.sh'); grep -qx "scripts/agents/test-agents.sh" <<<"$lista" && ! grep -q "^ajeno/" <<<"$lista"
tap_check $? "con .agent-kit.json, --list '*test-*.sh' no devuelve los tests propios del proyecto"
(cd "$TMP/r" && python3 scripts/agents/check-docs.py --list >/dev/null 2>&1); codigo=$?
if [ "$codigo" -eq 2 ]; then tap_ok "--list sin glob es un error de uso (no corre el check completo)"; else tap_fail "--list sin glob es un error de uso (no corre el check completo)"; fi
cp "$TMP/r/.agent-kit.json" "$TMP/kit.bak"; echo '{roto' >"$TMP/r/.agent-kit.json"
(cd "$TMP/r" && python3 scripts/agents/check-docs.py --list '*.sh' >/dev/null 2>&1); codigo=$?
if [ "$codigo" -ne 0 ]; then tap_ok "un .agent-kit.json inválido hace fallar --list (no devuelve una lista vacía)"; else tap_fail "un .agent-kit.json inválido hace fallar --list (no devuelve una lista vacía)"; fi
salida=$(check); grep -q "\.agent-kit.json" <<<"$salida" && ! grep -q Traceback <<<"$salida"; tap_check $? "un .agent-kit.json inválido es un error claro del check, sin traceback"
cp "$TMP/kit.bak" "$TMP/r/.agent-kit.json"
printf '# Doc\n\n[roto](no-existe.md)\n' >"$TMP/r/docs/ajeno-en-docs.md"
salida=$(check); grep -q "docs/ajeno-en-docs.md.*broken link" <<<"$salida"; tap_check $? "con .agent-kit.json, un link roto en docs/ sigue fallando"
rm "$TMP/r/docs/ajeno-en-docs.md"
printf '\n[roto](no-existe.md)\n' >>"$TMP/r/README.md"
salida=$(check); grep -q "^- README.md:.*broken link" <<<"$salida"; tap_check $? "con .agent-kit.json, un link roto en un archivo del kit sigue fallando"
rm "$TMP/r/.agent-kit.json"; git -C "$TMP/r" add -A  # sin manifiesto, el kit es lo que git rastrea
salida=$(check); grep -q "ajeno/README.md.*broken link" <<<"$salida"; tap_check $? "sin .agent-kit.json (la plantilla), se revisa todo"
lista=$(listar '*.sh'); grep -qx "ajeno/malo.sh" <<<"$lista"; tap_check $? "sin .agent-kit.json, --list devuelve todos los archivos del repo"

# 6. El modo chico no deja los subagentes (solo en la plantilla: el init borra profiles/).
if [ -f "$RAIZ/profiles/small/DELETE" ]; then
  grep -qx "$AGENTES" "$RAIZ/profiles/small/DELETE"; tap_check $? "el modo chico borra <AGENTES>" "el modo chico borra $AGENTES"
  grep -qx "scripts/agents/test-agents.sh" "$RAIZ/profiles/small/DELETE"; tap_check $? "el modo chico borra test-agents.sh (sin agentes no tiene qué probar)"
fi

# 7. Sin restos en español en lo que no tiene hermano en otro idioma (#143): el `_help` y los `reason` del mapa, el `_help` del
# equipo y los `id:` de los formularios (los hermanos de los formularios usan los mismos ids).
# Solo en el kit (donde está el init): un proyecto instalado en español escribe los reason del mapa y los ids de sus formularios en su idioma.
if [ -f "$RAIZ/scripts/init-template.sh" ]; then
! grep -Eq 'Mapa para agentes|Integrantes del equipo|cambió|cambiaron|Se edita con|qué documento|por ejemplo:|TODO: (comando|tests,|verificar|comparar)' "$RAIZ/docs/agents-map.json" "$RAIZ/.github/team.json" 2>/dev/null; tap_check $? "el _help, los reason y los TODO de docs/agents-map.json y de .github/team.json están en inglés"
ids_viejos='que-pasa|esperado|pasos|contexto|que|porque|criterios|objetivo|alcance|negocio|documento|hallazgo|riesgo|propuesta|herramienta|modo|hasta|trabas|dudas|agente|tiempo|cambiaria'
! grep -rEq "^ *(- )?id: *($ids_viejos) *$" "$RAIZ/.github/ISSUE_TEMPLATE" "$RAIZ/.github/i18n" 2>/dev/null; tap_check $? "los id: de los formularios de issues (y de sus hermanos en español) están en inglés"
fi
# 7. verify.py corre antes del PR cada test-*.sh que corre el CI (#143): si no, el error recién aparece en CI.
# Para cada script, hay una verificación del mapa que lo corre y que se dispara cuando cambia el propio script.
mapa_verify=$(cd "$RAIZ" && python3 - <<'PY'
import json, re, subprocess, sys
sys.path.insert(0, "scripts/agents")
from agents_map import coincide
reglas = json.load(open("docs/agents-map.json", encoding="utf-8"))["verify"]
lista = subprocess.run(["python3", "scripts/agents/check-docs.py", "--list", "*test-*.sh"], capture_output=True, text=True)
tests = lista.stdout.split()
if lista.returncode != 0 or not tests:
    print("check-docs.py --list failed or listed nothing")
for t in tests:
    if not any(re.search(r"(?:^|[;&| ])bash " + re.escape(t) + r"(?: |$)", r["run"]) and coincide(t, r.get("when", [])) for r in reglas):
        print(t)
PY
)
r=1; [ -z "$mapa_verify" ] && r=0
tap_check $r "verify: cada test-*.sh que corre el CI está en el mapa y se dispara al cambiar él mismo" "${mapa_verify:+faltan: $(echo "$mapa_verify" | tr '
' ' ')}"
# Solo en la plantilla: el init borra test-renames.sh y su verificación.
if [ -f "$RAIZ/scripts/test-renames.sh" ]; then
(cd "$RAIZ" && python3 - <<'PY'
import json, sys
sys.path.insert(0, "scripts/agents")
from agents_map import coincide
reglas = {r["name"]: r for r in json.load(open("docs/agents-map.json", encoding="utf-8"))["verify"]}
r = reglas.get("renames", {})
# Los literales viejos recién aparecían en CI: el test de renames corre cuando cambian scripts, tests o docs.
cambios = ["scripts/agents/verify.py", "docs/github-naming-convention.md", ".claude/skills/implement-issue/SKILL.md", "docs/agents-map.json", ".github/workflows/labels.yml"]
sys.exit(0 if all(coincide(c, r.get("when", [])) for c in cambios) else 1)
PY
); tap_check $? "verify: renames corre cuando cambian scripts, docs, skills, el mapa o los workflows"
fi

# 6. check-docs.py valida la sección red del mapa (ADR-002 D2, #152). En un proyecto inicializado check-docs falla
# igual por los TODO del mapa, así que se miran solo sus líneas de la sección red ("docs/agents-map.json: red ...").
# Reemplaza la sección red del mapa de la copia por el JSON que se pasa (o la borra con DEL).
poner_red() {
  RED_JSON="$1" python3 - "$TMP/r/docs/agents-map.json" <<'PY'
import json, os, sys
ruta = sys.argv[1]
m = json.load(open(ruta, encoding="utf-8"))
if os.environ["RED_JSON"] == "DEL":
    m.pop("red", None)
else:
    m["red"] = json.loads(os.environ["RED_JSON"])
open(ruta, "w", encoding="utf-8").write(json.dumps(m, ensure_ascii=False, indent=2) + "\n")
PY
}
errores_red() { check | grep '^- docs/agents-map.json: red' || true; }
OK='{"name":"py","when":["**/test_*.py"],"run":"pytest --junitxml={out}","format":"junit","timeout":600}'
# Una entrada inválida: check-docs informa un error de red con todos los fragmentos. Se usa como:
# rechaza <entrada JSON> <fragmento>...; tap_check $? "id literal"
rechaza() {
  local entrada="$1"; shift
  poner_red "[$entrada]"
  local salida f r=0
  salida=$(errores_red)
  [ -n "$salida" ] || r=1
  for f in "$@"; do grep -q -- "$f" <<<"$salida" || r=1; done
  return $r
}

copia
poner_red "[$OK]"
r=0; [ -z "$(errores_red)" ] || r=1; tap_check $r "check-docs acepta una entrada red válida (pytest, junit, timeout)"
poner_red '[{"name":"b","when":["**/test-*.sh"],"run":"TAP_OUT={out} bash t.sh","format":"tap"}]'
r=0; [ -z "$(errores_red)" ] || r=1; tap_check $r "check-docs acepta una entrada red válida sin timeout (es opcional)"
poner_red DEL
r=0; [ -z "$(errores_red)" ] || r=1; tap_check $r "check-docs acepta un mapa sin sección red (se lee como vacía)"

rechaza '{"name":"sinout","when":["**/*.py"],"run":"pytest","format":"junit"}' "red 'sinout'" '{out}'; tap_check $? "check-docs rechaza una entrada red sin {out} en run"
rechaza '{"name":"fmt","when":["**/*.py"],"run":"pytest --junitxml={out}","format":"xml"}' "red 'fmt'" 'junit' 'tap'; tap_check $? "check-docs rechaza un format que no es junit ni tap"
rechaza '{"name":"nofmt","when":["**/*.py"],"run":"pytest --junitxml={out}"}' "red 'nofmt'" 'format'; tap_check $? "check-docs rechaza una entrada red sin format"
rechaza '{"name":"nowhen","run":"pytest --junitxml={out}","format":"junit"}' "red 'nowhen'" 'when'; tap_check $? "check-docs rechaza una entrada red sin when"
rechaza '{"name":"vacio","when":[],"run":"pytest --junitxml={out}","format":"junit"}' "red 'vacio'" 'when'; tap_check $? "check-docs rechaza un when vacío"
rechaza '{"name":"textos","when":"**/*.py","run":"pytest --junitxml={out}","format":"junit"}' "red 'textos'" 'when'; tap_check $? "check-docs rechaza un when que no es una lista de textos"
rechaza '{"name":"tout","when":["**/*.py"],"run":"pytest --junitxml={out}","format":"junit","timeout":"600"}' "red 'tout'" 'timeout'; tap_check $? "check-docs rechaza un timeout que no es un entero"
rechaza '{"name":"cero","when":["**/*.py"],"run":"pytest --junitxml={out}","format":"junit","timeout":0}' "red 'cero'" 'timeout'; tap_check $? "check-docs rechaza un timeout cero o negativo"
rechaza '{"name":"bool","when":["**/*.py"],"run":"pytest --junitxml={out}","format":"junit","timeout":true}' "red 'bool'" 'timeout'; tap_check $? "check-docs rechaza un timeout booleano (true no es un entero)"
rechaza '{"name":"rep","when":["**/*.py"],"run":"pytest --junitxml={out}","format":"junit","report":"{out}"}' "red 'rep'" 'report'; tap_check $? "check-docs rechaza el campo report, que no existe (el camino va en {out})"
rechaza '{"when":["**/*.py"],"run":"pytest --junitxml={out}","format":"junit"}' "red\[0\]" 'name'; tap_check $? "check-docs rechaza una entrada red sin name"
rechaza '"pytest"' "red\[0\]" 'object'; tap_check $? "check-docs rechaza una entrada red que no es un objeto"

poner_red "[$OK,$OK]"
errores_red | grep -q "more than once"; tap_check $? "check-docs rechaza dos entradas red con el mismo name (red.sh <stack> sería ambiguo)"
poner_red '{"name":"py"}'
errores_red | grep -q "array"; tap_check $? "check-docs rechaza una sección red que no es un arreglo"
poner_red '[{"name":"a","when":["**/*.py"],"run":"x","format":"zzz"}]'
[ "$(errores_red | grep -c "red 'a'")" -ge 2 ]; tap_check $? "check-docs informa todos los problemas de una entrada, no solo el primero"

tap_done
