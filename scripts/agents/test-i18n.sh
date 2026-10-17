#!/usr/bin/env bash
# Tests del par de idiomas X.md / X.es.md (#113): el check de paridad de check-docs.py y el aviso de agents_map.py.
# Corre sobre una copia del repo, así no toca el working tree. Los pares son de ejemplo (el contenido real se traduce en #115).
# Uso: bash scripts/agents/test-i18n.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-i18n-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fallas=0
ok() { echo "ok   - $1"; }
falla() { echo "FAIL - $1"; fallas=$((fallas + 1)); }
afirmar() { if [ "$1" -eq 0 ]; then ok "$2"; else falla "$2"; fi; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
unset BASE

copia() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"
  (cd "$RAIZ" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | tar -xf - -C "$TMP/r"
  (cd "$TMP/r" && git init -q -b main && git add -A && git commit -qm base)
}
check() { (cd "$TMP/r" && python3 scripts/agents/check-docs.py 2>&1); }
# El interruptor "parity" del mapa: la plantilla lo trae prendido; los tests lo fijan en la copia según el caso.
parity() { python3 - "$TMP/r/docs/agents-map.json" "$1" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8")); m["parity"] = sys.argv[2] == "true"
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(m, ensure_ascii=False, indent=2) + "\n")
PY
}
# Un par con 2 encabezados y 1 bloque de código (el "# comentario" dentro del bloque no es un encabezado).
# shellcheck disable=SC2016  # los backticks son Markdown literal
par() { # par <ruta sin extensión> <encabezados extra en .es.md> <bloques extra en .es.md>
  local r="$TMP/r/$1"
  printf '# Title\n\n```bash\n# comment\nls\n```\n\n## Section\n' >"$r.md"
  printf '# Título\n\n```bash\n# comentario\nls\n```\n\n## Sección\n' >"$r.es.md"
  [ "${2:-0}" -gt 0 ] && printf '\n## Extra\n' >>"$r.es.md"
  [ "${3:-0}" -gt 0 ] && printf '\n```\nx\n```\n' >>"$r.es.md"
  return 0
}

grep -q '"parity": true' "$RAIZ/docs/agents-map.json"; afirmar $? "la plantilla trae el interruptor parity prendido en el mapa (el init lo apaga en los proyectos)"
python3 -c "import json,sys; sys.exit(0 if 'CLAUDE.md' in json.load(open('$RAIZ/docs/agents-map.json'))['parity_ignore'] else 1)"; afirmar $? "CLAUDE.md (solo trae @AGENTS.md) está en parity_ignore"
copia; s=$(check)
! grep -q 'sibling\|headings\|code blocks' <<<"$s"; afirmar $? "con parity prendido, la plantilla tal como está no da errores de paridad"
copia; parity false; par docs/sample 1 0
s=$(check)
! grep -q 'sibling\|headings' <<<"$s"; afirmar $? "con parity apagado, un par distinto y todos los demás X.md sin hermano no dan errores"
copia; parity true; par docs/sample
s=$(check)
! grep -q 'sample' <<<"$s" ; afirmar $? "un par con la misma estructura no da errores"
rm "$TMP/r/docs/guides/README.es.md"; s=$(check)
grep -q 'docs/guides/README.md: missing its Spanish sibling docs/guides/README.es.md' <<<"$s"; afirmar $? "con parity prendido, un X.md sin su X.es.md falla con el archivo en el mensaje"
copia; parity true
find "$TMP/r" -name '*.es.md' -not -path '*/.git/*' -delete
s=$(check)
grep -q 'missing its Spanish sibling' <<<"$s"; afirmar $? "con parity prendido, falla aunque no exista ningún .es.md"

copia; parity true; par docs/sample 1 0
s=$(check)
grep -q 'docs/sample.es.md.*3 headings.*docs/sample.md.*2' <<<"$s"; afirmar $? "encabezados distintos: falla con ambos archivos y los conteos"

copia; parity true; par docs/sample 0 1
s=$(check)
grep -q 'docs/sample.es.md.*2 code blocks.*docs/sample.md.*1' <<<"$s"; afirmar $? "bloques de código distintos: falla con ambos archivos y los conteos"

copia; parity true; par docs/sample; rm "$TMP/r/docs/sample.md"
s=$(check)
grep -q 'docs/sample.es.md.*docs/sample.md' <<<"$s"; afirmar $? "un X.es.md sin su X.md falla"

copia; parity true; par docs/sample
s=$(check)
! grep -q Traceback <<<"$s"; afirmar $? "el check de paridad no deja un Traceback"

# Cercos de código: uno de cuatro backticks que envuelve uno de tres, y uno con ~~~, cuentan como un bloque cada uno.
copia
parity true
# shellcheck disable=SC2016  # los backticks son Markdown literal
printf '# T\n\n````md\n```bash\nls\n```\n````\n\n~~~\n# not a heading\n~~~\n' >"$TMP/r/docs/fences.md"
# shellcheck disable=SC2016
printf '# T\n\n````md\n```bash\nls\n```\n````\n\n~~~\n# no es encabezado\n~~~\n' >"$TMP/r/docs/fences.es.md"
s=$(check)
! grep -q 'fences' <<<"$s"; afirmar $? "cercos de cuatro backticks y de ~~~: el mismo contenido en los dos idiomas no da diferencias"
printf '\n~~~\nx\n~~~\n' >>"$TMP/r/docs/fences.es.md"
s=$(check)
grep -q 'docs/fences.es.md.*3 code blocks.*docs/fences.md.*2' <<<"$s"; afirmar $? "un bloque ~~~ de más en un idioma se cuenta"

# Aviso del PR: agents_map.py dice qué par cambió de un solo lado.
copia; par docs/sample
(cd "$TMP/r" && git add -A && git commit -qm pares && git checkout -qb feat && echo "More." >>docs/sample.md && git commit -qam cambio)
s=$(cd "$TMP/r" && python3 scripts/agents/agents_map.py --base main 2>&1)
grep -q 'UNPAIRED' <<<"$s" && grep -q 'docs/sample.md' <<<"$s" && grep -q 'docs/sample.es.md' <<<"$s"
afirmar $? "agents_map.py avisa si cambia un idioma sin el otro, nombrando los dos archivos"
(cd "$TMP/r" && echo "Más." >>docs/sample.es.md && git commit -qam hermano)
s=$(cd "$TMP/r" && python3 scripts/agents/agents_map.py --base main 2>&1)
! grep -q 'UNPAIRED' <<<"$s"; afirmar $? "agents_map.py no avisa si cambiaron los dos"
grep -q 'UNPAIRED' "$RAIZ/.github/workflows/docs.yml"; afirmar $? "docs.yml convierte el aviso del mapa en un ::warning::"

# llms.txt no es Markdown pero también se instala en dos idiomas: su hermano es llms.es.txt (#115).
copia; parity true
rm -f "$TMP/r/docs/llms.es.txt"
printf '# T\n\n- [a](a.md)\n' >"$TMP/r/docs/llms.txt"
s=$(check)
grep -q 'docs/llms.txt: missing its Spanish sibling docs/llms.es.txt' <<<"$s"; afirmar $? "llms.txt sin su llms.es.txt falla con parity prendido"
printf '# T\n\n## Extra\n- [a](a.md)\n' >"$TMP/r/docs/llms.es.txt"
s=$(check)
grep -q 'docs/llms.es.txt: 2 headings, but docs/llms.txt has 1' <<<"$s"; afirmar $? "llms.txt: encabezados distintos entre los dos idiomas fallan"
printf '# T\n\n- [a](a.md)\n' >"$TMP/r/docs/llms.es.txt"
s=$(check)
! grep '^- docs/llms' <<<"$s" | grep -Eq 'sibling|headings|code blocks'; afirmar $? "llms.txt: el par con la misma estructura no da errores de paridad"

# Los formularios de issue (.yml): GitHub carga todo .yml de ISSUE_TEMPLATE, así que el español vive en .github/i18n/ISSUE_TEMPLATE/ (#115).
copia; parity true
rm "$TMP/r/.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml"
s=$(check)
grep -q '.github/ISSUE_TEMPLATE/1-bug.yml: missing its Spanish sibling .github/i18n/ISSUE_TEMPLATE/1-bug.es.yml' <<<"$s"; afirmar $? "formularios: sin su hermano en .github/i18n/ISSUE_TEMPLATE/ falla con esa ruta"
copia; parity true
sed -i.bak 's/id: esperado/id: otro/' "$TMP/r/.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml"
s=$(check)
grep -q '.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml: .*differ.*.github/ISSUE_TEMPLATE/1-bug.yml' <<<"$s"; afirmar $? "formularios: ids distintos entre los dos idiomas fallan con los dos archivos"
copia; parity true
cp "$TMP/r/.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml" "$TMP/r/.github/ISSUE_TEMPLATE/1-bug.es.yml"
s=$(check)
grep -q '.github/ISSUE_TEMPLATE/1-bug.es.yml.*second' <<<"$s"; afirmar $? "formularios: un .es.yml dentro de ISSUE_TEMPLATE falla (GitHub lo ofrecería como otro formulario)"
copia
(cd "$TMP/r" && git checkout -qb feat && echo "# More" >>.github/ISSUE_TEMPLATE/1-bug.yml && git commit -qam cambio)
s=$(cd "$TMP/r" && python3 scripts/agents/agents_map.py --base main 2>&1)
grep -q 'UNPAIRED' <<<"$s" && grep -q '.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml' <<<"$s"; afirmar $? "agents_map.py avisa si cambia un formulario sin su hermano de .github/i18n/ISSUE_TEMPLATE/"

# labels.yml y labels.es.yml: mismos labels y colores (cambian solo las descripciones); si no, un --lang es instalaría labels que faltan.
copia; parity true
s=$(check)
! grep -q 'labels' <<<"$s"; afirmar $? "labels: el par labels.yml / labels.es.yml tal como está no da errores"
sed -i.bak 's/name: "priority:low"/name: "priority:lowest"/' "$TMP/r/.github/labels.es.yml"
s=$(check)
grep -q '.github/labels.es.yml: .*differ.*.github/labels.yml' <<<"$s"; afirmar $? "labels: un label distinto entre los dos idiomas falla con los dos archivos"
copia; parity true
perl -0pi -e 's/color: "7B61FF"/color: "000000"/' "$TMP/r/.github/labels.es.yml"
s=$(check)
grep -q '.github/labels.es.yml: .*differ.*.github/labels.yml' <<<"$s"; afirmar $? "labels: un color distinto entre los dos idiomas falla"
copia; parity true
rm "$TMP/r/.github/labels.es.yml"
s=$(check)
grep -q '.github/labels.yml: missing its Spanish sibling .github/labels.es.yml' <<<"$s"; afirmar $? "labels: sin labels.es.yml falla"

# AGENTS.md dice el literal que el check de labels acepta: el inglés vigente (el español sigue valiendo como alias).
grep -q 'ADR unchanged: <reason>' "$RAIZ/AGENTS.md" && ! grep -q 'looks for that exact Spanish text' "$RAIZ/AGENTS.md"; afirmar $? "AGENTS.md nombra 'ADR unchanged: <reason>' como el literal del check, sin decir que busca el texto en español"
grep -q 'ADR sin cambios: <motivo>' "$RAIZ/AGENTS.es.md"; afirmar $? "AGENTS.es.md conserva 'ADR sin cambios: <motivo>'"
# labels: también los aliases (sin ellos, un proyecto de 0.9 perdería los renombres) y sin depender del orden de las claves.
copia; parity true
perl -0pi -e 's/"\x74ipo:feature"/"x:feat"/' "$TMP/r/.github/labels.es.yml"
s=$(check)
grep -q '.github/labels.es.yml: .*differ.*.github/labels.yml' <<<"$s"; afirmar $? "labels: un alias distinto entre los dos idiomas falla"
copia; parity true
perl -0pi -e 's/(- name: "type:feature"\n)(  color: "[0-9A-F]+"\n)/$1  description: "x"\n$2/' "$TMP/r/.github/labels.es.yml"
perl -0pi -e 's/(- name: "type:feature"\n  description: "x"\n)  color: "[0-9A-F]+"\n/$1  color: "000000"\n/' "$TMP/r/.github/labels.es.yml"
s=$(check)
grep -q '.github/labels.es.yml: .*differ' <<<"$s"; afirmar $? "labels: un color distinto se detecta aunque otra clave (description) quede entre name y color"
copia; parity true
python3 - "$TMP/r/.github/labels.es.yml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = re.sub(r'(- name: "type:task"\n)(  color: "[0-9A-F]+"\n)(  description: "[^"\n]*"\n)', r'\1\3\2', s)  # descripción antes que el color
open(p, "w", encoding="utf-8").write(s)
PY
s=$(check)
! grep -q 'labels' <<<"$s"; afirmar $? "labels: otro orden de claves dentro de un label no da diferencias falsas"
# formularios: también required y la cantidad de options.
copia; parity true
perl -0pi -e 's/\n    validations: \{ required: true \}//' "$TMP/r/.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml"
s=$(check)
grep -q '.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml: .*differ.*.github/ISSUE_TEMPLATE/1-bug.yml' <<<"$s"; afirmar $? "formularios: un required que falta en un idioma falla"
copia; parity true
perl -0pi -e 's/Otra\]/Otra, Más]/' "$TMP/r/.github/i18n/ISSUE_TEMPLATE/5-trial.es.yml"
s=$(check)
grep -q '.github/i18n/ISSUE_TEMPLATE/5-trial.es.yml: .*differ' <<<"$s"; afirmar $? "formularios: otra cantidad de options falla"
# agents_map.py: labels.yml y su hermano también avisan.
copia
(cd "$TMP/r" && git checkout -qb feat2 && echo "# More" >>.github/labels.yml && git commit -qam cambio)
s=$(cd "$TMP/r" && python3 scripts/agents/agents_map.py --base main 2>&1)
grep -q 'UNPAIRED' <<<"$s" && grep -q '.github/labels.es.yml' <<<"$s"; afirmar $? "agents_map.py avisa si cambia labels.yml sin labels.es.yml"
# El perfil chico también tiene hermanos (#115, parte 3): la plantilla ya no lo exime de la paridad.
! grep -q 'profiles/small' <(python3 -c "import json; print(json.load(open('$RAIZ/docs/agents-map.json'))['parity_ignore'])"); afirmar $? "profiles/small ya no está en parity_ignore (el perfil chico tiene sus hermanos)"
copia; parity true
rm "$TMP/r/profiles/small/AGENTS.es.md"
s=$(check)
grep -q 'profiles/small/AGENTS.md: missing its Spanish sibling profiles/small/AGENTS.es.md' <<<"$s"; afirmar $? "perfil chico: sin su hermano en español falla con parity prendido"
copia; parity true
rm "$TMP/r/profiles/small/docs/llms.es.txt"
s=$(check)
grep -q 'profiles/small/docs/llms.txt: missing its Spanish sibling profiles/small/docs/llms.es.txt' <<<"$s"; afirmar $? "perfil chico: llms.txt sin su llms.es.txt falla con parity prendido"
copia; parity true
rm "$TMP/r/profiles/small/.github/labels.es.yml"
s=$(check)
grep -q 'profiles/small/.github/labels.yml: missing its Spanish sibling profiles/small/.github/labels.es.yml' <<<"$s"; afirmar $? "perfil chico: labels.yml sin su labels.es.yml falla con parity prendido"

# formularios: required se asocia a su id (dos formularios que exigen campos distintos no son iguales) y una opción entre comillas
# con una coma cuenta como una.
copia; parity true
perl -0pi -e 's/(id: que-pasa\n    attributes: \{[^\n]*\}\n)    validations: \{ required: true \}\n/$1/; s/(id: pasos\n    attributes: \{[^\n]*\}\n)/$1    validations: { required: true }\n/' "$TMP/r/.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml"
s=$(check)
grep -q '.github/i18n/ISSUE_TEMPLATE/1-bug.es.yml: .*differ.*.github/ISSUE_TEMPLATE/1-bug.yml' <<<"$s"; afirmar $? "formularios: el mismo número de required en otros campos (otro id) falla"
copia; parity true
perl -0pi -e 's/options: \[Full, /options: ["Full, with all", /' "$TMP/r/.github/ISSUE_TEMPLATE/5-trial.yml"
perl -0pi -e 's/options: \[Completo, /options: ["Completo", /' "$TMP/r/.github/i18n/ISSUE_TEMPLATE/5-trial.es.yml"
s=$(check)
! grep -q '5-trial' <<<"$s"; afirmar $? "formularios: una opción entre comillas con una coma cuenta como una (sin falso positivo)"
# labels: un formato de YAML que el parser no lee falla en vez de perder labels sin avisar (el mismo en los dos archivos no da diferencia).
copia; parity true
perl -0pi -e 's/^- name: "type:bug"/-   name: "type:bug"/m' "$TMP/r/.github/labels.yml" "$TMP/r/.github/labels.es.yml"
s=$(check)
grep -q '.github/labels.yml: .*items.*blocks' <<<"$s"; afirmar $? "labels: un ítem con formato que el parser no lee (-   name:) falla en vez de perderse"
# labels: cada formato que el parser no lee falla (el mismo cambio en los dos archivos y después una diferencia solo en el .es.yml).
while IFS='|' read -r nombre buscar poner cambio_es; do
  copia; parity true
  perl -0pi -e "s/$buscar/$poner/mg" "$TMP/r/.github/labels.yml" "$TMP/r/.github/labels.es.yml"
  perl -0pi -e "s/$cambio_es/g" "$TMP/r/.github/labels.es.yml"
  s=$(check)
  grep -Eq '.github/labels.yml(:[0-9]+)?: .*format not supported' <<<"$s" && grep -Eq '.github/labels.es.yml(:[0-9]+)?: .*format not supported' <<<"$s"; afirmar $? "labels: $nombre falla en vez de perderse"
done <<'FORMATOS'
aliases en una línea|aliases:\n    - "tipo:bug"|aliases: ["tipo:bug"]|\["tipo:bug"\]/["tipo:otro"]
alias con comentario|- "tipo:bug"|- "tipo:bug"  # old|"tipo:bug"  # old/"tipo:otro"  # old
guion solo en su línea|^- name: "type:bug"|-\n  name: "type:bug"|name: "type:bug"\n  color: "7B61FF"/name: "type:bug"\n  color: "000000"
lista indentada|^- name: "type:bug"|  - name: "type:bug"|"tipo:bug"/"tipo:otro"
FORMATOS
copia
printf '# ADR-002 — Prueba\n\n## Status\n\nAccepted\n\nScope: kit\n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
printf '# ADR-002 — Prueba\n\n## Estado\n\nAceptado\n' >"$TMP/r/docs/decisions/ADR-002-prueba.es.md"
s=$(check)
# shellcheck disable=SC2016  # backticks literales del mensaje
grep -q 'Warning: .*ADR-002-prueba.md.*Scope: kit' <<<"$s" && ! grep -q 'has `Ámbito: kit` but' <<<"$s"; afirmar $? "un ADR con 'Scope: kit' y su hermano sin ámbito: un solo aviso, el del Scope (no dice que tiene 'Ámbito: kit')"
# ADRs: 'Ámbito: kit' en un idioma y no en el otro; con finales de línea CRLF el init tampoco lo borra.
copia
printf '# ADR-002 — Prueba\n\n## Status\n\nAccepted\n\nÁmbito: kit\n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
printf '# ADR-002 — Prueba\n\n## Estado\n\nAceptado\n' >"$TMP/r/docs/decisions/ADR-002-prueba.es.md"
s=$(check)
grep -q 'Warning: .*ADR-002-prueba.md.*Ámbito: kit.*ADR-002-prueba.es.md' <<<"$s"; afirmar $? "un ADR con 'Ámbito: kit' en el .md y no en el .es.md avisa"
printf '# ADR-002 — Prueba\n\n## Status\n\nAccepted\n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
printf '# ADR-002 — Prueba\n\n## Estado\n\nAceptado\n\nÁmbito: kit\n' >"$TMP/r/docs/decisions/ADR-002-prueba.es.md"
s=$(check)
grep -q 'Warning: .*ADR-002-prueba.es.md.*Ámbito: kit.*ADR-002-prueba.md' <<<"$s"; afirmar $? "un ADR con 'Ámbito: kit' en el .es.md y no en el .md avisa"
copia
printf '# ADR-002 — Prueba\r\n\r\n## Status\r\n\r\nAccepted\r\n\r\nÁmbito: kit\r\n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
s=$(check)
grep -q 'Warning: .*ADR-002-prueba.md.*Ámbito: kit.*trailing' <<<"$s"; afirmar $? "un 'Ámbito: kit' con final de línea CRLF avisa que el init no lo borra"

# Los índices de ADRs: los hermanos en español (docs/README.es.md, docs/llms.es.txt) también tienen que listar cada ADR.
copia
grep -v 'ADR-001-language' "$TMP/r/docs/README.es.md" >"$TMP/r/x" && mv "$TMP/r/x" "$TMP/r/docs/README.es.md"
s=$(check)
grep -q 'docs/README.es.md: the ADR ADR-001-language-labels-and-names-in-english.md is missing from the index' <<<"$s"; afirmar $? "índices: un ADR que falta en docs/README.es.md falla"
copia
grep -v 'ADR-001-language' "$TMP/r/docs/llms.es.txt" >"$TMP/r/x" && mv "$TMP/r/x" "$TMP/r/docs/llms.es.txt"
s=$(check)
grep -q 'docs/llms.es.txt: the ADR ADR-001-language-labels-and-names-in-english.md is missing from the index' <<<"$s"; afirmar $? "índices: un ADR que falta en docs/llms.es.txt falla"
copia
s=$(check)
! grep -q 'missing from the index' <<<"$s"; afirmar $? "índices: la plantilla tal como está lista el ADR en los cuatro (README, llms, y sus hermanos)"

# "Scope: kit" no lo borra el init (solo "Ámbito: kit"): check-docs avisa, sin fallar.
copia
printf '# ADR-002 — Prueba\n\n## Status\n\nAccepted\n\nScope: kit\n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
s=$(check)
grep -q 'Warning: .*ADR-002-prueba.md.*Scope: kit.*Ámbito: kit' <<<"$s"; afirmar $? "un ADR con 'Scope: kit' da un aviso que dice que el init solo borra 'Ámbito: kit'"
copia
s=$(check)
! grep -q 'Scope: kit' <<<"$s"; afirmar $? "sin 'Scope: kit' en ningún ADR no hay aviso"
# En un proyecto (sin init-template.sh) un ADR propio con esa línea es suyo: no hay nada que borrar, no hay aviso.
copia
rm "$TMP/r/scripts/init-template.sh"
printf '# ADR-002 — Prueba\n\n## Status\n\nAccepted\n\nScope: kit\n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
s=$(check)
! grep -q 'Scope: kit' <<<"$s"; afirmar $? "sin init-template.sh (un proyecto) un ADR con 'Scope: kit' no da aviso"

# Un ADR con hermano .es.md: el índice pide solo el .md, y 'Scope: kit' se detecta en el .md aunque el .es.md diga 'Ámbito: kit'
# (no puede depender del orden en que el sistema de archivos lista los dos: el test fuerza los dos órdenes).
for orden in 1 2; do
  copia
  printf '# ADR-002 — Prueba\n\n## Status\n\nAccepted\n\nScope: kit\n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
  printf '# ADR-002 — Prueba\n\n## Estado\n\nAceptado\n\nÁmbito: kit\n' >"$TMP/r/docs/decisions/ADR-002-prueba.es.md"
  # touch -t no cambia el orden de os.listdir: se fuerza el orden con un os.listdir propio (ascendente en 1, descendente en 2).
  s=$(cd "$TMP/r" && python3 -c "
import os, runpy, sys
real = os.listdir
os.listdir = lambda p='.': sorted(real(p), reverse=($orden == 2))
sys.argv = ['check-docs.py']
runpy.run_path('scripts/agents/check-docs.py', run_name='__main__')" 2>&1)
  grep -q 'Warning: .*ADR-002-prueba.md .*Scope: kit' <<<"$s" && ! grep -q 'ADR-002-prueba.es.md is missing from the index' <<<"$s" && grep -q 'ADR-002-prueba.md is missing from the index' <<<"$s"
  afirmar $? "ADR con hermano .es.md (prueba $orden): avisa 'Scope: kit' del .md y el índice pide solo el .md"
done
# Un 'Ámbito: kit ' con espacio al final tampoco lo borra el init (grep -x exacto): avisa.
copia
printf '# ADR-002 — Prueba\n\n## Estado\n\nAceptado\n\nÁmbito: kit \n' >"$TMP/r/docs/decisions/ADR-002-prueba.md"
s=$(check)
grep -q 'Warning: .*ADR-002-prueba.md.*Ámbito: kit.*trailing' <<<"$s"; afirmar $? "un 'Ámbito: kit' con espacios al final avisa que el init no lo borra"

# README: sin la nota "Spanish-first"; el README en español muestra --lang es en los comandos de inicio.
! grep -qi 'spanish-first' "$RAIZ/README.md"; afirmar $? "README.md ya no dice que la plantilla es Spanish-first"
grep -q 'init-template.sh "Nombre del proyecto" main --lang es' "$RAIZ/README.es.md"; afirmar $? "README.es.md: el comando de inicio lleva --lang es"
filas=$(grep -c '^| `init-template.sh' "$RAIZ/README.es.md")
[ "$filas" -ge 1 ] && ! grep '^| `init-template.sh' "$RAIZ/README.es.md" | grep -qv -e '--lang es'; afirmar $? "README.es.md: la tabla de modos tiene filas ($filas) y todas llevan --lang es"
# shellcheck disable=SC2016  # backticks de Markdown literales
! grep -q 'después `media`, `baja`' "$RAIZ/profiles/small/.claude/skills/implement-issue/SKILL.es.md" && grep -q 'después `medium`, `low`' "$RAIZ/profiles/small/.claude/skills/implement-issue/SKILL.es.md"; afirmar $? "perfil chico (es): implement-issue nombra los labels que existen (priority:medium y low)"
# shellcheck disable=SC2016
grep -q 'sin `"language": "es"`' "$RAIZ/CHANGELOG.md" || grep -q 'descripción de los commits.*language' "$RAIZ/CHANGELOG.md"; afirmar $? "CHANGELOG: avisa que sin language es también el idioma de las descripciones de commits pasa a inglés"
grep -q 'CHANGELOG.md#tabla-de-renombres' "$RAIZ/README.md" && grep -q 'CHANGELOG.md#tabla-de-renombres' "$RAIZ/README.es.md"; afirmar $? "los README avisan a dónde se mudaron los docs con nombre en español (tabla de renombres del CHANGELOG)"

# Los agentes (ADR-001, R-1): su versión en español vive en .claude/i18n/agents/, no al lado (Claude Code carga todo .md).
copia; parity true
s=$(check)
! grep -q 'Traceback' <<<"$s" && ! grep -v 'profiles/' <<<"$s" | grep -q '\.claude/'; afirmar $? "agentes: el par .claude/agents/X.md + .claude/i18n/agents/X.es.md no da errores (ni Traceback) fuera del perfil chico"
rm "$TMP/r/.claude/i18n/agents/reviewer.es.md"
s=$(check)
grep -q 'reviewer.md: missing its Spanish sibling .claude/i18n/agents/reviewer.es.md' <<<"$s"; afirmar $? "agentes: sin su hermano en .claude/i18n/agents/ falla con esa ruta"
copia
sed -i.bak 's#docs/agents/subagent-contract.md#docs/otro.md#g; s/^model: opus/model: gpt/' "$TMP/r/.claude/i18n/agents/reviewer.es.md"
s=$(check)
grep -q '.claude/i18n/agents/reviewer.es.md: does not point to the common contract' <<<"$s" && grep -q ".claude/i18n/agents/reviewer.es.md: model 'gpt'" <<<"$s" && grep -q "reviewer.es.md: 'model:' is 'gpt' but .claude/agents/reviewer.md has 'opus'" <<<"$s"
afirmar $? "agentes: el hermano en español se valida como agente (contrato, model) y debe coincidir con el inglés"
copia; parity true
printf '\n## Extra\n' >>"$TMP/r/.claude/i18n/agents/reviewer.es.md"
s=$(check)
grep -q '.claude/i18n/agents/reviewer.es.md.*headings.*.claude/agents/reviewer.md' <<<"$s"; afirmar $? "agentes: encabezados distintos entre el agente y su hermano: falla con los dos archivos"
copia
cp "$TMP/r/.claude/i18n/agents/reviewer.es.md" "$TMP/r/.claude/agents/reviewer.es.md"
s=$(check)
grep -q '.claude/agents/reviewer.es.md.*second agent' <<<"$s"; afirmar $? "agentes: un .es.md dentro de .claude/agents/ falla (sería un segundo agente con el mismo name)"
copia; parity true
rm -rf "$TMP/r/.claude/i18n"
s=$(check)
grep -q '.claude/agents/implementer.md: missing its Spanish sibling .claude/i18n/agents/implementer.es.md' <<<"$s"; afirmar $? "agentes: sin .claude/i18n el check de paridad pide los hermanos"
copia
(cd "$TMP/r" && git checkout -qb feat && echo "More." >>.claude/agents/implementer.md && git commit -qam cambio)
s=$(cd "$TMP/r" && python3 scripts/agents/agents_map.py --base main 2>&1)
grep -q 'UNPAIRED' <<<"$s" && grep -q '.claude/i18n/agents/implementer.es.md' <<<"$s"; afirmar $? "agents_map.py avisa si cambia un agente sin su hermano de .claude/i18n/agents/"

# Los tests que dependen del texto de las skills y de los agentes pasan también con --lang es (el init deja el español como X.md
# y esos tests viajan al proyecto): se corren en una copia inicializada en español.
copia
(cd "$TMP/r" && ./scripts/init-template.sh Demo main --lang es >/dev/null 2>&1); afirmar $? "init --lang es sobre la copia termina bien"
for t in scripts/agents/test-agents.sh .claude/skills/orchestrate/test-orchestrate.sh .claude/skills/improve-skills/test-retros.sh; do
  (cd "$TMP/r" && bash "$t" >"$TMP/es-test.log" 2>&1); afirmar $? "con --lang es pasa $t"
done

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
