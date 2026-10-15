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
# Un par con 2 encabezados y 1 bloque de código (el "# comentario" dentro del bloque no es un encabezado).
par() { # par <ruta sin extensión> <encabezados extra en .es.md> <bloques extra en .es.md>
  local r="$TMP/r/$1"
  printf '# Title\n\n```bash\n# comment\nls\n```\n\n## Section\n' >"$r.md"
  printf '# Título\n\n```bash\n# comentario\nls\n```\n\n## Sección\n' >"$r.es.md"
  [ "${2:-0}" -gt 0 ] && printf '\n## Extra\n' >>"$r.es.md"
  [ "${3:-0}" -gt 0 ] && printf '\n```\nx\n```\n' >>"$r.es.md"
  return 0
}

copia
check | grep -q '^Docs OK' ; afirmar $? "el repo sin pares .es.md pasa el check (la paridad se exige desde el primer par)"

copia; par docs/sample
s=$(check)
! grep -q 'sample' <<<"$s" ; afirmar $? "un par con la misma estructura no da errores"
grep -q 'docs/guides/.*\.es\.md.*missing\|missing.*docs/guides/' <<<"$s"; afirmar $? "con un par presente, un X.md sin su X.es.md falla con el archivo en el mensaje"

copia; par docs/sample 1 0
s=$(check)
grep -q 'docs/sample.es.md.*3 headings.*docs/sample.md.*2' <<<"$s"; afirmar $? "encabezados distintos: falla con ambos archivos y los conteos"

copia; par docs/sample 0 1
s=$(check)
grep -q 'docs/sample.es.md.*2 code blocks.*docs/sample.md.*1' <<<"$s"; afirmar $? "bloques de código distintos: falla con ambos archivos y los conteos"

copia; par docs/sample; rm "$TMP/r/docs/sample.md"
s=$(check)
grep -q 'docs/sample.es.md.*docs/sample.md' <<<"$s"; afirmar $? "un X.es.md sin su X.md falla"

copia; par docs/sample
s=$(check)
! grep -q Traceback <<<"$s"; afirmar $? "el check de paridad no deja un Traceback"

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

echo
if [ "$fallas" -ne 0 ]; then echo "$fallas test(s) fallaron."; exit 1; fi
echo "Todos los tests pasan."
