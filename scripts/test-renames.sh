#!/usr/bin/env bash
# Tests of the English renames (ADR-001, issue #114): files, paths, JSON keys, labels and hooks.
# The old names live only in this table, in the CHANGELOG and in ADR-001 (the record of the decision).
# Usage: bash scripts/test-renames.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
# shellcheck source=/dev/null
. "$ROOT/scripts/agents/tap.sh"
tap_begin "$0"
# Usage: <condition>; tap_check $? "description"

# old path|new path
RENAMES='
.claude/agents/implementador-liviano.md|.claude/agents/implementer-light.md
.claude/agents/implementador.md|.claude/agents/implementer.md
.claude/agents/revisor.md|.claude/agents/reviewer.md
.claude/skills/crear-issue/SKILL.md|.claude/skills/create-issue/SKILL.md
.claude/skills/estado/SKILL.md|.claude/skills/project-status/SKILL.md
.claude/skills/estado/disponibles.sh|.claude/skills/project-status/available.sh
.claude/skills/estado/estado.sh|.claude/skills/project-status/status.sh
.claude/skills/implement-issue/preparar.sh|.claude/skills/implement-issue/prepare.sh
.claude/skills/implement-issue/test-preparar.sh|.claude/skills/implement-issue/test-prepare.sh
.claude/skills/implement-issue/rojo.sh|.claude/skills/implement-issue/red.sh
.claude/skills/implement-issue/test-rojo.sh|.claude/skills/implement-issue/test-red.sh
.claude/skills/mejorar-skills/SKILL.md|.claude/skills/improve-skills/SKILL.md
.claude/skills/mejorar-skills/plantilla-retro.md|.claude/skills/improve-skills/retro-template.md
.claude/skills/mejorar-skills/retro.sh|.claude/skills/improve-skills/retro.sh
.claude/skills/mejorar-skills/senales.sh|.claude/skills/improve-skills/signals.sh
.claude/skills/mejorar-skills/test-retros.sh|.claude/skills/improve-skills/test-retros.sh
.claude/skills/orquestar/SKILL.md|.claude/skills/orchestrate/SKILL.md
.claude/skills/orquestar/limpiar.sh|.claude/skills/orchestrate/cleanup.sh
.claude/skills/orquestar/ruteo.py|.claude/skills/orchestrate/routing.py
.claude/skills/orquestar/test-orquestar.sh|.claude/skills/orchestrate/test-orchestrate.sh
.claude/skills/plan-feature/planificar.py|.claude/skills/plan-feature/planner.py
.codex/hooks.json|.codex/hooks.json
.github/ISSUE_TEMPLATE/4-auditoria.yml|.github/ISSUE_TEMPLATE/4-audit.yml
.github/ISSUE_TEMPLATE/5-prueba.yml|.github/ISSUE_TEMPLATE/5-trial.yml
.github/equipo.json|.github/team.json
.github/hooks/barandas.json|.github/hooks/guardrails.json
.github/marca/README.md|.github/brand/README.md
.github/marca/barrilete-oscuro.svg|.github/brand/barrilete-dark.svg
.github/marca/dron-con-correa.svg|.github/brand/drone-on-leash.svg
.github/marca/estados/bloqueado.svg|.github/brand/states/blocked.svg
.github/marca/estados/planificando.svg|.github/brand/states/planning.svg
.github/marca/estados/pr-listo.svg|.github/brand/states/pr-ready.svg
.github/marca/estados/trabajando.svg|.github/brand/states/working.svg
.github/workflows/desbloquear.yml|.github/workflows/unblock.yml
docs/agentes/contrato-subagentes.md|docs/agents/subagent-contract.md
docs/agentes/lecciones.md|docs/agents/lessons.md
docs/convencion-nombres-github.md|docs/github-naming-convention.md
docs/mapa-agentes.json|docs/agents-map.json
docs/probar-la-plantilla.md|docs/try-the-template.md
docs/decisions/ADR-000-plantilla.md|docs/decisions/ADR-000-template.md
docs/decisions/ADR-001-idioma-labels-y-nombres-en-ingles.md|docs/decisions/ADR-001-language-labels-and-names-in-english.md
perfiles/chico/BORRAR|profiles/small/DELETE
perfiles/chico/README.md|profiles/small/README.md
perfiles/chico/AGENTS.md|profiles/small/AGENTS.md
perfiles/chico/docs/convencion-nombres-github.md|profiles/small/docs/github-naming-convention.md
perfiles/chico/.claude/skills/crear-issue/SKILL.md|profiles/small/.claude/skills/create-issue/SKILL.md
scripts/actualizar.py|scripts/update.py
scripts/crecer.py|scripts/grow.py
scripts/init-plantilla.sh|scripts/init-template.sh
scripts/test-actualizar.sh|scripts/test-update.sh
scripts/agentes/barandas.py|scripts/agents/guardrails.py
scripts/agentes/test_barandas.py|scripts/agents/test_guardrails.py
scripts/agentes/equipo.py|scripts/agents/team.py
scripts/agentes/test_equipo.py|scripts/agents/test_team.py
scripts/agentes/mapa.py|scripts/agents/agents_map.py
scripts/agentes/verificar.py|scripts/agents/verify.py
scripts/agentes/check-docs.py|scripts/agents/check-docs.py
scripts/agentes/test-agentes.sh|scripts/agents/test-agents.sh
scripts/agentes/test-base.sh|scripts/agents/test-base.sh
'
while IFS='|' read -r old new; do
  [ -n "$old" ] || continue
  [ "$old" = "$new" ] && continue
  if [ ! -e "$old" ] && [ -e "$new" ]; then tap_ok "<old> -> <new>" "$old -> $new"; else tap_fail "<old> -> <new>" "$old -> $new"; fi
done <<<"$RENAMES"

# Old names in the content of any file (except this test, the CHANGELOG, ADR-001 and the tests that
# use old values on purpose: the 0.9 init, the label aliases and the old retro values).
OLD_NAMES='scripts/agentes|docs/agentes|barandas\.py|test_barandas|hooks/barandas|mapa-agentes|mapa\.py|verificar\.py|equipo\.py|equipo\.json|preparar\.sh|rojo\.sh|limpiar\.sh|ruteo\.py|planificar\.py|disponibles\.sh|estado\.sh|senales\.sh|plantilla-retro|actualizar\.py|crecer\.py|init-plantilla|test-actualizar|test-orquestar|test-preparar|test-rojo|test-agentes|desbloquear\.yml|convencion-nombres-github|contrato-subagentes|lecciones\.md|probar-la-plantilla|perfiles/|\.github/marca|revisor\.md|skills/(crear-issue|estado|mejorar-skills|orquestar)|/(orquestar|crear-issue|mejorar-skills|estado)\b|usar estado\b|skills/status/|[ `(]/status([^.[:alnum:]_-]|$)|SIN MODIFICAR|--chico|--listar|--revisar|BORRAR|implementador-liviano|agents/(implementador|revisor)|rol: (implementador|revisor)|name: (implementador|revisor)|AGENT_KIT_(PLANTILLA|FECHA)|<PROYECTO>|<RAMA_BASE>|<FECHA>|<REGLA_RAMAS>|(plantilla|marca):(inicio|fin)|agent-kit/pendientes'
# Anchored to the label syntax: Spanish prose ("el tipo: ...", .es.md files) must not trip it.
LABELS_OLD='tipo:(feature|bug|task|audit|docs)|prioridad:(critica|alta|media|baja)|estado:(a-triar|necesita-info|bloqueado)|logica-negocio'
hits=$(git ls-files -co --exclude-standard | grep -vE '^(CHANGELOG\.md|scripts/test-renames\.sh|docs/decisions/ADR-001-.*|scripts/test-update\.sh|scripts/update\.py|scripts/agents/test_labels\.py|.*/improve-skills/(test-retros|legacy-names)\.sh)$' \
  | while read -r f; do [ -f "$f" ] && grep -IHnE "$OLD_NAMES" "$f"; done | head -5 || true)
if [ -z "$hits" ]; then tap_ok "no file mentions an old file, path or flag name"
else tap_fail "no file mentions an old file, path or flag name" "no file mentions an old file, path or flag name (e.g. $(head -1 <<<"$hits" | cut -c1-100))"; fi
# labels.yml keeps the old names as `aliases` (label-sync renames them without losing the ones set on issues).
hits=$(git ls-files -co --exclude-standard | grep -vE '^(CHANGELOG\.md|scripts/test-renames\.sh|docs/decisions/ADR-001-.*|scripts/test-update\.sh|scripts/update\.py|scripts/agents/test_labels\.py|.*/improve-skills/(test-retros|legacy-names)\.sh|.*\.github/labels(\.es)?\.yml)$' \
  | while read -r f; do [ -f "$f" ] && grep -IHnE "$LABELS_OLD" "$f"; done | head -5 || true)
if [ -z "$hits" ]; then tap_ok "no file mentions an old label"
else tap_fail "no file mentions an old label" "no file mentions an old label (e.g. $(head -1 <<<"$hits" | cut -c1-100))"; fi

# The marker agents_map.py prints is the one the skills tell agents to look for.
for f in .claude/skills/review-pr/SKILL.md .claude/skills/update-docs/SKILL.md; do
  grep -q 'NOT MODIFIED' "$f"; tap_check $? "<f> quotes the NOT MODIFIED marker of agents_map.py" "$f quotes the NOT MODIFIED marker of agents_map.py"
done

# JSON keys of agents-map.json and team.json.
python3 - >&2 <<'PY'
import json, sys
old = {"cuando", "revisar", "motivo", "sensibles", "rutas", "verificar", "nombre", "siempre", "correr",
       "obligatorios", "ignorar_check", "_ayuda", "tipo", "integrantes", "activo"}
new_map = {"when", "review", "reason", "sensitive", "paths", "verify", "name", "always", "run",
           "required", "ignore_check"}
def keys(o):
    if isinstance(o, dict):
        for k, v in o.items():
            yield k
            yield from keys(v)
    elif isinstance(o, list):
        for v in o:
            yield from keys(v)
bad = 0
for ruta in ("docs/agents-map.json", ".github/team.json"):
    try:
        usadas = set(keys(json.load(open(ruta, encoding="utf-8"))))
    except OSError:
        print(f"FAIL - {ruta} does not exist"); bad += 1; continue
    viejas = usadas & old
    print(("ok   - " if not viejas else "FAIL - ") + f"{ruta} has no Spanish keys" + (f" ({sorted(viejas)})" if viejas else ""))
    bad += bool(viejas)
try:
    usadas = set(keys(json.load(open("docs/agents-map.json", encoding="utf-8"))))
except OSError:
    usadas = set()
falta = new_map - usadas
print(("ok   - " if not falta else "FAIL - ") + "agents-map.json uses the English keys" + (f" (missing {sorted(falta)})" if falta else ""))
sys.exit(1 if bad or falta else 0)
PY
tap_check $? "JSON keys are in English"

# Labels: type:, priority:, status:, business-logic, with aliases so label-sync keeps the old ones.
for f in .github/labels.yml profiles/small/.github/labels.yml; do
  grep -q 'name: "type:feature"' "$f" && grep -q 'name: "priority:high"' "$f"; tap_check $? "<f> uses type: and priority:" "$f uses type: and priority:"
done
l=.github/labels.yml
for n in priority:critical priority:high priority:medium priority:low status:triage status:needs-info status:blocked business-logic breaking-change; do
  grep -q "name: \"$n\"" "$l"; tap_check $? "labels.yml defines <n>" "labels.yml defines $n"
done
for a in prioridad:critica prioridad:alta prioridad:media prioridad:baja estado:a-triar estado:necesita-info estado:bloqueado logica-negocio tipo:feature tipo:bug tipo:task tipo:audit tipo:docs; do
  grep -qE "^ +- \"?$a\"?\$" "$l"; tap_check $? "labels.yml keeps <a> as an alias" "labels.yml keeps $a as an alias"
done
grep -q '^  aliases:' "$l"; tap_check $? "labels.yml declares aliases"

# Hooks: the four registrations must point to a script that exists (the hook exits 0 if it does not find it).
for h in .claude/settings.json .codex/hooks.json .cursor/hooks.json .github/hooks/guardrails.json; do
  [ -f "$h" ] || { tap_fail "<h> does not exist" "$h does not exist"; continue; }
  p=$(grep -o 'scripts/[a-z]*/[a-z_]*\.py' "$h" | sort -u)
  [ "$p" = "scripts/agents/guardrails.py" ] && [ -f "$p" ]; tap_check $? "<h> points to scripts/agents/guardrails.py" "$h points to scripts/agents/guardrails.py (found: ${p:-nothing})"
done

echo
tap_done
