#!/usr/bin/env bash
# Reemplaza los marcadores de la plantilla y se borra solo.
# Uso: ./scripts/init-plantilla.sh "Nombre del proyecto" [main|develop] [releases] [--chico]
#   rama-base: main (default) o develop.
#   releases:  solo con develop. Agrega el flujo develop → release/vX.Y.Z → main
#              para publicar versiones sin tocar producción (app con usuarios activos).
#   --chico:   para proyectos de una o dos personas. Reemplaza varios archivos por
#              versiones cortas (perfiles/chico/) y borra lo que resuelve problemas
#              de equipo (épicas, revisión entre sesiones, mapa de rutas, labeler…).
set -euo pipefail
USO="Uso: $0 \"Nombre del proyecto\" [main|develop] [releases] [--chico]"
CHICO=""
POS=()
for a in "$@"; do
  case "$a" in
    --chico) CHICO=1 ;;
    -*) echo "$USO"; echo "Opción desconocida: $a"; exit 1 ;;
    *) POS+=("$a") ;;
  esac
done
export P="${POS[0]:?$USO}"
export B="${POS[1]:-main}"
MODO="${POS[2]:-}"
if [ -n "$MODO" ] && { [ "$MODO" != "releases" ] || [ "$B" = "main" ]; }; then
  echo "$USO"; echo "'releases' solo se puede usar con la rama base develop."; exit 1
fi
if [ -n "$CHICO" ] && [ "$MODO" = "releases" ]; then
  echo "$USO"; echo "'--chico' no se combina con 'releases': si necesitás releases, usá el modo completo."; exit 1
fi
# AGENT_KIT_FECHA: la fecha original del proyecto, para que actualizar.py reproduzca su init.
F=${AGENT_KIT_FECHA:-$(date +%Y-%m-%d)}
export F
if [ "$B" = "main" ]; then
  # shellcheck disable=SC2016  # backticks de Markdown literales
  export R='Única rama permanente `main`: los PRs de trabajo van directo a `main`.'
elif [ "$MODO" = "releases" ]; then
  export R="Los PRs de trabajo van a \`$B\`. Las versiones se preparan en \`release/vX.Y.Z\` (cortada desde \`$B\`, probada en staging) y recién ahí pasan a \`main\`, que es producción."
else
  export R="Los PRs de trabajo van a \`$B\`. \`main\` es producción y solo recibe PRs de release desde \`$B\`."
fi
cd "$(git rev-parse --show-toplevel)"
if [ -n "$CHICO" ]; then
  # Los archivos cortos pisan a los completos; después se borra lo que no aplica.
  (cd perfiles/chico && find . -type f ! -name BORRAR) | while read -r f; do
    mkdir -p "$(dirname "$f")"
    cp "perfiles/chico/$f" "$f"
  done
  grep -v '^#' perfiles/chico/BORRAR | while read -r r; do [ -n "$r" ] && rm -rf -- "$r"; done
  # Sin label logica-negocio: se edita en el lugar (no se copia) para que no se desactualice.
  perl -pi -e 's/el PR lleva el label `logica-negocio`\./el PR lo dice en "Lógica de negocio afectada"./' docs/decisions/README.md
  perl -pi -e 's/ Si sí: cuál, y agregá el label `logica-negocio`\./ Si sí: cuál, y por qué cambia./' .github/pull_request_template.md
fi
rm -rf perfiles
# Los ADRs del kit (línea "Ámbito: kit", ver docs/decisions/README.md) explican cómo es la plantilla,
# no el proyecto: el proyecto numera los suyos desde ADR-001. Sus líneas de los índices van en bloques plantilla:.
{ grep -lx 'Ámbito: kit' docs/decisions/ADR-*.md 2>/dev/null || true; } | while read -r f; do rm -f -- "$f"; done
# La marca (Barrilete) y la guía de prueba son de la plantilla, no del proyecto nuevo.
rm -rf .github/marca
rm -f docs/probar-la-plantilla.md .github/ISSUE_TEMPLATE/5-prueba.yml
for f in README.md README.en.md docs/README.md docs/llms.txt; do
  [ -f "$f" ] || continue
  # marca: lo de Barrilete. plantilla: lo que solo sirve en el repo de la plantilla (la guía de prueba).
  perl -0pi -e 's/<!-- (marca|plantilla):inicio -->.*?<!-- \1:fin -->\n\n?//gs' "$f"
  perl -ni -e 'print unless m{^\|.*`\.github/marca/`}' "$f"  # fila "Marca" de la tabla
done
# crecer.py solo sirve en proyectos chicos (para pasar al modo completo).
[ -z "$CHICO" ] && rm -f scripts/crecer.py
# Los workflows marcados con "# main: para la plantilla misma" (docs.yml, labels.yml) también corren en
# main para la plantilla; el proyecto parte de su rama base.
for w in .github/workflows/*.yml; do
  [ -f "$w" ] || continue
  perl -0pi -e 's/ *# main: para la plantilla misma[^\n]*\n( *branches: )\[main, <RAMA_BASE>\]/$1\[<RAMA_BASE>\]/' "$w"
  if grep -q 'branches: \[main, <RAMA_BASE>\]\|plantilla misma' "$w"; then
    echo "init: no pude ajustar el filtro de ramas de $w"; exit 1
  fi
done
# shellcheck disable=SC2016  # $ENV{…} lo expande perl, no bash
grep -rlE '<PROYECTO>|<RAMA_BASE>|<FECHA>|<REGLA_RAMAS>' --exclude-dir=.git --exclude=init-plantilla.sh . \
  | xargs perl -pi -e 's/<PROYECTO>/$ENV{P}/g; s/<RAMA_BASE>/$ENV{B}/g; s/<FECHA>/$ENV{F}/g; s/<REGLA_RAMAS>/$ENV{R}/g'
BLOQUES=$(grep -rl 'releases:inicio' --exclude-dir=.git --exclude=init-plantilla.sh . || true)
if [ "$MODO" = "releases" ]; then
  # Se queda el contenido; solo se sacan los marcadores.
  for f in $BLOQUES; do perl -ni -e 'print unless /<!-- releases:(inicio|fin) -->/' "$f"; done
  perl -pi -e "s/branches: \[$B\]/branches: [main, $B, 'release\/**']/" .github/workflows/labels.yml .github/workflows/docs.yml
else
  for f in $BLOQUES; do perl -0pi -e 's/\n<!-- releases:inicio -->.*?<!-- releases:fin -->\n//s' "$f"; done
  [ "$B" != "main" ] && perl -pi -e "s/branches: \[$B\]/branches: [main, $B]/" .github/workflows/labels.yml .github/workflows/docs.yml
fi
rm -- scripts/init-plantilla.sh scripts/test-init.sh  # el test solo sirve con el init
rm -f scripts/test-actualizar.sh  # arma versiones de la plantilla: necesita el init
# La versión de la plantilla queda en .agent-kit.json; VERSION y CHANGELOG.md son de la plantilla.
V=$(cat VERSION 2>/dev/null || true)
export V
rm -f VERSION CHANGELOG.md
# La verificación "init" del mapa corre ese test: sin él, es una regla muerta.
if [ -f docs/mapa-agentes.json ]; then
  python3 - <<'PY'
import json
ruta = "docs/mapa-agentes.json"
mapa = json.load(open(ruta, encoding="utf-8"))
mapa["verificar"] = [v for v in mapa.get("verificar", []) if v.get("nombre") not in ("init", "actualizar")]
open(ruta, "w", encoding="utf-8").write(json.dumps(mapa, ensure_ascii=False, indent=2) + "\n")
PY
fi
# Registro del init: con qué datos se creó el proyecto y la huella de cada archivo tal como
# quedó. crecer.py lo usa para saber qué archivos no tocó el proyecto y puede reemplazar.
MODO_KIT=$([ -n "$CHICO" ] && echo chico || echo completo) RELEASES="$MODO" python3 - <<'PY'
import hashlib, json, os, subprocess
archivos = {}
for base, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d != ".git"]
    for n in files:
        ruta = os.path.relpath(os.path.join(base, n), ".")
        if ruta != ".agent-kit.json":
            archivos[ruta] = hashlib.sha1(open(ruta, "rb").read()).hexdigest()
json.dump({
    "proyecto": os.environ["P"], "rama_base": os.environ["B"], "releases": os.environ["RELEASES"] == "releases",
    "modo": os.environ["MODO_KIT"], "fecha": os.environ["F"], "version": os.environ["V"] or None,
    "archivos": dict(sorted(archivos.items())),
}, open(".agent-kit.json", "w"), ensure_ascii=False, indent=2)
PY
echo "Listo. Pendientes (TODO:):"
grep -rn "TODO:" --exclude-dir=.git . | cut -c1-120 || true
