#!/usr/bin/env bash
# Tests de los subagentes (.claude/agents/) y de su validación en check-docs.py.
# Corre sobre una copia del repo (git archive), así no toca el working tree.
# Uso: bash scripts/agentes/test-agentes.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-agentes-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
# Uso: <condición>; afirmar $? "descripción"
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
CONTRATO=docs/agentes/contrato-subagentes.md
AGENTES=".claude/agents"

# Copia del repo con lo commiteado y lo que está en el working tree.
copia() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"
  (cd "$RAIZ" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | tar -xf - -C "$TMP/r"
  (cd "$TMP/r" && git init -q && git add -A && git commit -qm base)
}
check() { (cd "$TMP/r" && python3 scripts/agentes/check-docs.py 2>&1); }
# check-docs sin errores de los subagentes. En un proyecto recién inicializado check-docs falla
# igual por los TODO del mapa, así que se mira solo lo de los subagentes.
sin_errores_agentes() { ! check | grep -q "$AGENTES\|contrato-subagentes"; }
frontmatter() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$1"; }

# 1. Los tres roles existen con su modelo y herramientas acotadas.
for par in implementador:sonnet implementador-liviano:haiku revisor:opus; do
  rol=${par%%:*}; modelo=${par##*:}; f="$RAIZ/$AGENTES/$rol.md"
  fm=$(frontmatter "$f" 2>/dev/null)
  grep -qx "name: $rol" <<<"$fm"; afirmar $? "$rol: existe con name: $rol"
  grep -qx "model: $modelo" <<<"$fm"; afirmar $? "$rol: model: $modelo"
  grep -q "^tools: " <<<"$fm"; afirmar $? "$rol: lista sus herramientas (tools:)"
  grep -q "$CONTRATO" "$f" 2>/dev/null; afirmar $? "$rol: remite al contrato de salida común"
done
! grep -q "Edit" <<<"$(frontmatter "$RAIZ/$AGENTES/revisor.md" 2>/dev/null | grep '^tools:')"; afirmar $? "revisor: no puede editar código (Write solo para la revisión y la retro)"

# 2. El contrato de salida está en un solo lugar, con todos los resultados.
for r in pr consulta escalar soltado bloqueantes; do
  grep -q "\`$r\`" "$RAIZ/$CONTRATO" 2>/dev/null; afirmar $? "el contrato define el resultado $r"
done
grep -q "retro.sh" "$RAIZ/$CONTRATO" 2>/dev/null; afirmar $? "el contrato dice que cada subagente guarda su retro con retro.sh"

# 3. El liviano dice exactamente cuándo escalar.
f="$RAIZ/$AGENTES/implementador-liviano.md"
grep -q "mapa.py" "$f" 2>/dev/null && grep -q "rutas sensibles" "$f" && grep -q "logica-negocio" "$f"
afirmar $? "implementador-liviano: escala por rutas sensibles (mapa.py) o lógica de negocio"
f="$RAIZ/$AGENTES/implementador-liviano.md"
grep -q "mapa.py.*error\|error.*mapa.py" "$f" 2>/dev/null; afirmar $? "implementador-liviano: escala si mapa.py no corre o sale con error"
grep -q "prioridad" "$f" 2>/dev/null; afirmar $? "implementador-liviano: dice qué tiene prioridad sobre consulta y soltado del contrato"
grep -q "BASE" "$RAIZ/$CONTRATO" 2>/dev/null; afirmar $? "el contrato dice cómo pasar BASE a los scripts"
f="$RAIZ/$AGENTES/revisor.md"
! grep -q "FETCH_HEAD" "$f" 2>/dev/null && grep -q "headRefOid" "$f" 2>/dev/null; afirmar $? "revisor: trae el PR a una ref propia (no FETCH_HEAD) y comprueba headRefOid"

# 4. check-docs.py valida los subagentes.
copia
sin_errores_agentes; afirmar $? "check-docs no reporta errores en los subagentes del repo"
mkdir -p "$TMP/r/$AGENTES"
printf -- '---\nname: x\ndescription: d\ntools: Read\nmodel: gpt-4\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*model" <<<"$salida"; afirmar $? "check-docs rechaza un model que no es opus, sonnet ni haiku"
printf -- '---\nname: x\ndescription: d\nmodel: haiku\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*tools" <<<"$salida"; afirmar $? "check-docs rechaza un subagente sin tools"
printf -- '---\nname: x\ndescription: d\ntools: Read\nmodel: haiku\n---\nSin contrato.\n' >"$TMP/r/$AGENTES/x.md"
salida=$(check); grep -q "$AGENTES/x.md.*contrato" <<<"$salida"; afirmar $? "check-docs rechaza un subagente que no remite al contrato"
printf -- '---\r\nname: x\r\ndescription: d\r\ntools: Read\r\nmodel: haiku\r\n---\r\nVer %s.\r\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
sin_errores_agentes; afirmar $? "check-docs acepta un subagente con fin de línea CRLF"
printf -- '---\nname: "x"\ndescription: d\ntools: Read\nmodel: "haiku"\n---\nVer %s.\n' "$CONTRATO" >"$TMP/r/$AGENTES/x.md"
sin_errores_agentes; afirmar $? "check-docs acepta valores entre comillas"

# 5. En un repo con .agent-kit.json, check-docs y los listados solo miran los archivos del kit.
copia
python3 - "$TMP/r" <<'PY'
import json, subprocess, sys
r = sys.argv[1]
archivos = subprocess.run(["git", "-C", r, "ls-files"], capture_output=True, text=True).stdout.split()
json.dump({"archivos": {a: "x" for a in archivos}}, open(r + "/.agent-kit.json", "w"))
PY
mkdir -p "$TMP/r/ajeno"
printf '# Ajeno\n\n[roto](no-existe.md)\n' >"$TMP/r/ajeno/README.md"
printf '#!/bin/sh\necho [ -z a ]\n' >"$TMP/r/ajeno/malo.sh"
printf '#!/bin/sh\nexit 1\n' >"$TMP/r/ajeno/test-propio.sh"
listar() { (cd "$TMP/r" && python3 scripts/agentes/check-docs.py --listar "$1" 2>/dev/null); }
# En un proyecto recién inicializado el check falla por los TODO del mapa: se mira solo lo ajeno.
salida=$(check); grep -q "^Documentación\|^Aviso" <<<"$salida" && ! grep -q "ajeno/README.md" <<<"$salida"; afirmar $? "con .agent-kit.json, un .md ajeno con link roto no falla el check"
lista=$(listar '*.sh'); grep -qx "scripts/agentes/test-agentes.sh" <<<"$lista"; afirmar $? "con .agent-kit.json, --listar '*.sh' devuelve los scripts del kit"
! grep -q "^ajeno/" <<<"$lista"; afirmar $? "con .agent-kit.json, --listar '*.sh' no devuelve los .sh ajenos"
lista=$(listar '*test-*.sh'); grep -qx "scripts/agentes/test-agentes.sh" <<<"$lista" && ! grep -q "^ajeno/" <<<"$lista"
afirmar $? "con .agent-kit.json, --listar '*test-*.sh' no devuelve los tests propios del proyecto"
(cd "$TMP/r" && python3 scripts/agentes/check-docs.py --listar >/dev/null 2>&1); codigo=$?
if [ "$codigo" -eq 2 ]; then ok "--listar sin glob es un error de uso (no corre el check completo)"; else falla "--listar sin glob es un error de uso (no corre el check completo)"; fi
cp "$TMP/r/.agent-kit.json" "$TMP/kit.bak"; echo '{roto' >"$TMP/r/.agent-kit.json"
(cd "$TMP/r" && python3 scripts/agentes/check-docs.py --listar '*.sh' >/dev/null 2>&1); codigo=$?
if [ "$codigo" -ne 0 ]; then ok "un .agent-kit.json inválido hace fallar --listar (no devuelve una lista vacía)"; else falla "un .agent-kit.json inválido hace fallar --listar (no devuelve una lista vacía)"; fi
salida=$(check); grep -q "\.agent-kit.json" <<<"$salida" && ! grep -q Traceback <<<"$salida"; afirmar $? "un .agent-kit.json inválido es un error claro del check, sin traceback"
cp "$TMP/kit.bak" "$TMP/r/.agent-kit.json"
printf '# Doc\n\n[roto](no-existe.md)\n' >"$TMP/r/docs/ajeno-en-docs.md"
salida=$(check); grep -q "docs/ajeno-en-docs.md.*link roto" <<<"$salida"; afirmar $? "con .agent-kit.json, un link roto en docs/ sigue fallando"
rm "$TMP/r/docs/ajeno-en-docs.md"
printf '\n[roto](no-existe.md)\n' >>"$TMP/r/README.md"
salida=$(check); grep -q "^- README.md:.*link roto" <<<"$salida"; afirmar $? "con .agent-kit.json, un link roto en un archivo del kit sigue fallando"
rm "$TMP/r/.agent-kit.json"; git -C "$TMP/r" add -A  # sin manifiesto, el kit es lo que git rastrea
salida=$(check); grep -q "ajeno/README.md.*link roto" <<<"$salida"; afirmar $? "sin .agent-kit.json (la plantilla), se revisa todo"
lista=$(listar '*.sh'); grep -qx "ajeno/malo.sh" <<<"$lista"; afirmar $? "sin .agent-kit.json, --listar devuelve todos los archivos del repo"

# 6. El modo chico no deja los subagentes (solo en la plantilla: el init borra perfiles/).
if [ -f "$RAIZ/perfiles/chico/BORRAR" ]; then
  grep -qx "$AGENTES" "$RAIZ/perfiles/chico/BORRAR"; afirmar $? "el modo chico borra $AGENTES"
  grep -qx "scripts/agentes/test-agentes.sh" "$RAIZ/perfiles/chico/BORRAR"; afirmar $? "el modo chico borra test-agentes.sh (sin agentes no tiene qué probar)"
fi

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
