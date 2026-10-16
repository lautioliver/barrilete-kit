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
# El interruptor "parity" del mapa: la plantilla lo trae apagado; los tests lo prenden en la copia.
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

grep -q '"parity": false' "$RAIZ/docs/agents-map.json"; afirmar $? "la plantilla trae el interruptor parity apagado en el mapa (#115 lo prende)"
copia; par docs/sample 1 0
s=$(check)
! grep -q 'sibling\|headings' <<<"$s"; afirmar $? "con parity apagado, un par distinto y todos los demás X.md sin hermano no dan errores"
copia; parity true; par docs/sample
s=$(check)
! grep -q 'sample' <<<"$s" ; afirmar $? "un par con la misma estructura no da errores"
rm "$TMP/r/docs/guides/README.es.md"; s=$(check)
grep -q 'docs/guides/README.md: missing its Spanish sibling docs/guides/README.es.md' <<<"$s"; afirmar $? "con parity prendido, un X.md sin su X.es.md falla con el archivo en el mensaje"
copia; parity true
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
! grep -q '^- docs/llms' <<<"$s"; afirmar $? "llms.txt: el par con la misma estructura no da errores"

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
