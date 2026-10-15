#!/usr/bin/env bash
# Replaces the template placeholders and deletes itself.
# Usage: ./scripts/init-template.sh "Project name" [main|develop] [releases] [--small] [--lang en|es]
#   base branch: main (default) or develop.
#   releases:  only with develop. Adds the develop → release/vX.Y.Z → main flow
#              to publish versions without touching production (app with active users).
#   --small:   for projects of one or two people. Replaces several files with
#              short versions (profiles/small/) and deletes what solves team
#              problems (epics, review between sessions, path map, labeler…).
#   --lang:    prose language, en (default) or es. With es, each X.md is replaced by its
#              sibling X.es.md; in both cases the leftover .es.md files are deleted (ADR-001).
#              It is recorded as "language" in .agent-kit.json.
set -euo pipefail
USO="Usage: $0 \"Project name\" [main|develop] [releases] [--small] [--lang en|es]"
CHICO=""
LANG_KIT="en"
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --small) CHICO=1 ;;
    --lang=*) LANG_KIT="${1#--lang=}" ;;
    --lang)
      [ $# -ge 2 ] || { echo "$USO"; echo "--lang needs a value: en or es."; exit 1; }
      LANG_KIT="$2"; shift ;;
    -*) echo "$USO"; echo "Unknown option: $1"; exit 1 ;;
    *) POS+=("$1") ;;
  esac
  shift
done
case "$LANG_KIT" in
  en|es) ;;
  *) echo "$USO"; echo "--lang must be en or es (got: '$LANG_KIT')."; exit 1 ;;
esac
export LANG_KIT
export P="${POS[0]:?$USO}"
export B="${POS[1]:-main}"
MODO="${POS[2]:-}"
if [ -n "$MODO" ] && { [ "$MODO" != "releases" ] || [ "$B" = "main" ]; }; then
  echo "$USO"; echo "'releases' can only be used with the develop base branch."; exit 1
fi
if [ -n "$CHICO" ] && [ "$MODO" = "releases" ]; then
  echo "$USO"; echo "'--small' cannot be combined with 'releases': if you need releases, use the full mode."; exit 1
fi
# AGENT_KIT_DATE: the original date of the project, so update.py reproduces its init.
F=${AGENT_KIT_DATE:-$(date +%Y-%m-%d)}
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
# Language (ADR-001): X.md and X.es.md are siblings. With es, the Spanish one replaces the English one;
# in both cases no .es.md is left. It goes before the edits and deletions that follow, so they apply to
# the file that stays (the DELETE list of --small already took the siblings of its own entries).
apply_language() {
  # The Spanish agents live in .claude/i18n/agents/<name>.es.md (Claude Code loads every .md of .claude/agents/
  # as an agent, so a sibling there would be a second agent with the same name). With es they replace
  # .claude/agents/<name>.md (if the mode kept the agents); in both cases .claude/i18n goes away.
  if [ "$LANG_KIT" = es ] && [ -d .claude/agents ] && [ -d .claude/i18n/agents ]; then
    for f in .claude/i18n/agents/*.es.md; do
      [ -e "$f" ] || continue
      # Only the sibling of an agent that exists: an orphan would be created as a new agent.
      [ -e ".claude/agents/$(basename "${f%.es.md}").md" ] || continue
      mv -f -- "$f" ".claude/agents/$(basename "${f%.es.md}").md"
    done
  fi
  rm -rf .claude/i18n
  { find . -name '*.es.md' -not -path './.git/*' -not -path './profiles/*' || true; } | while read -r f; do
    if [ "$LANG_KIT" = es ]; then mv -f -- "$f" "${f%.es.md}.md"; else rm -f -- "$f"; fi
  done
}
if [ -n "$CHICO" ]; then
  # The short files overwrite the full ones; then what does not apply is deleted.
  (cd profiles/small && find . -type f ! -name DELETE) | while read -r f; do
    mkdir -p "$(dirname "$f")"
    cp "profiles/small/$f" "$f"
    # The profile file wins in both languages: if it has no sibling of its own, the full file's sibling goes
    # (or --lang es would put the full Spanish file over the short one).
    case "$f" in
      *.es.md) ;;
      *.md) [ -e "profiles/small/${f%.md}.es.md" ] || rm -f -- "${f%.md}.es.md" ;;
    esac
  done
  # A .md entry also takes its Spanish sibling (ADR-001), or --lang es would bring the file back as X.md.
  grep -v '^#' profiles/small/DELETE | while read -r r; do
    [ -n "$r" ] || continue
    rm -rf -- "$r"
    case "$r" in *.md) rm -f -- "${r%.md}.es.md" ;; esac
  done
  apply_language
  # Without the business-logic label: it is edited in place (not copied) so it does not get outdated.
  perl -pi -e 's/el PR lleva el label `business-logic`\./el PR lo dice en "Lógica de negocio afectada"./' docs/decisions/README.md
  perl -pi -e 's/ Si sí: cuál, y agregá el label `business-logic`\./ Si sí: cuál, y por qué cambia./' .github/pull_request_template.md
fi
apply_language
rm -rf profiles
# The kit ADRs ("Ámbito: kit" line, see docs/decisions/README.md) explain how the template is,
# not the project: the project numbers its own from ADR-001. Their index lines go in template: blocks.
{ grep -lx 'Ámbito: kit' docs/decisions/ADR-*.md 2>/dev/null || true; } | while read -r f; do rm -f -- "$f"; done
# The brand (Barrilete) and the trial guide belong to the template, not to the new project.
rm -rf .github/brand
rm -f docs/try-the-template.md .github/ISSUE_TEMPLATE/5-trial.yml
for f in README.md README.en.md docs/README.md docs/llms.txt; do
  [ -f "$f" ] || continue
  # brand: what is Barrilete's. template: what is only useful in the template repo (the trial guide).
  perl -0pi -e 's/<!-- (brand|template):start -->.*?<!-- \1:end -->\n\n?//gs' "$f"
  perl -ni -e 'print unless m{^\|.*`\.github/brand/`}' "$f"  # "Brand" row of the table
done
# grow.py is only useful in small projects (to move to the full mode).
[ -z "$CHICO" ] && rm -f scripts/grow.py
# The workflows marked with "# main: for the template itself" (docs.yml, labels.yml) also run on
# main for the template; the project starts from its base branch.
for w in .github/workflows/*.yml; do
  [ -f "$w" ] || continue
  perl -0pi -e 's/ *# main: for the template itself[^\n]*\n( *branches: )\[main, <BASE_BRANCH>\]/$1\[<BASE_BRANCH>\]/' "$w"
  if grep -q 'branches: \[main, <BASE_BRANCH>\]\|for the template itself' "$w"; then
    echo "init: could not adjust the branch filter of $w"; exit 1
  fi
done
# shellcheck disable=SC2016  # $ENV{…} expanded by perl, not bash
grep -rlE '<PROJECT>|<BASE_BRANCH>|<DATE>|<BRANCH_RULE>' --exclude-dir=.git --exclude=init-template.sh . \
  | xargs perl -pi -e 's/<PROJECT>/$ENV{P}/g; s/<BASE_BRANCH>/$ENV{B}/g; s/<DATE>/$ENV{F}/g; s/<BRANCH_RULE>/$ENV{R}/g'
BLOQUES=$(grep -rl 'releases:start' --exclude-dir=.git --exclude=init-template.sh . || true)
if [ "$MODO" = "releases" ]; then
  # The content stays; only the markers are removed.
  for f in $BLOQUES; do perl -ni -e 'print unless /<!-- releases:(start|end) -->/' "$f"; done
  perl -pi -e "s/branches: \[$B\]/branches: [main, $B, 'release\/**']/" .github/workflows/labels.yml .github/workflows/docs.yml
else
  for f in $BLOQUES; do perl -0pi -e 's/\n<!-- releases:start -->.*?<!-- releases:end -->\n//s' "$f"; done
  [ "$B" != "main" ] && perl -pi -e "s/branches: \[$B\]/branches: [main, $B]/" .github/workflows/labels.yml .github/workflows/docs.yml
fi
# install.py is for repos that do not have the kit yet; a project with it uses update.py.
rm -- scripts/init-template.sh scripts/test-init.sh scripts/test-renames.sh scripts/install.py scripts/test-install.sh  # only make sense with the template
rm -f scripts/test-update.sh  # builds template versions: it needs the init
rm -f scripts/agents/test-i18n.sh  # tests the kit's own docs (it assumes the template content)
# The template version stays in .agent-kit.json; VERSION and CHANGELOG.md belong to the template.
V=$(cat VERSION 2>/dev/null || true)
export V
rm -f VERSION CHANGELOG.md
# The "init" check of the map runs that test: without it, it is a dead rule. Same for the kit-only entries.
if [ -f docs/agents-map.json ]; then
  python3 - <<'PY'
import json
ruta = "docs/agents-map.json"
mapa = json.load(open(ruta, encoding="utf-8"))
mapa["verify"] = [v for v in mapa.get("verify", []) if v.get("name") not in ("init", "update", "renames", "i18n", "install")]
# CHANGELOG.md and the kit ADRs are deleted above: their ignore entries would hide the project's own ADR-001.
mapa["ignore_check"] = [g for g in mapa.get("ignore_check", []) if g not in ("CHANGELOG.md", "docs/decisions/ADR-001-*")]
mapa["parity"] = False  # a project has one language: the siblings check is the template's
mapa["parity_ignore"] = [g for g in mapa.get("parity_ignore", []) if g not in ("CHANGELOG.md", "docs/decisions/ADR-001-*")]
open(ruta, "w", encoding="utf-8").write(json.dumps(mapa, ensure_ascii=False, indent=2) + "\n")
PY
fi
# Init registry: with what data the project was created and the hash of each file as it
# was left. grow.py uses it to know which files the project did not touch and can replace.
MODO_KIT=$([ -n "$CHICO" ] && echo small || echo full) RELEASES="$MODO" python3 - <<'PY'
import hashlib, json, os, subprocess
archivos = {}
for base, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d != ".git"]
    for n in files:
        ruta = os.path.relpath(os.path.join(base, n), ".")
        if ruta != ".agent-kit.json":
            archivos[ruta] = hashlib.sha1(open(ruta, "rb").read()).hexdigest()
json.dump({
    "project": os.environ["P"], "base_branch": os.environ["B"], "releases": os.environ["RELEASES"] == "releases",
    "mode": os.environ["MODO_KIT"], "language": os.environ["LANG_KIT"], "date": os.environ["F"], "version": os.environ["V"] or None,
    "files": dict(sorted(archivos.items())),
}, open(".agent-kit.json", "w"), ensure_ascii=False, indent=2)
PY
echo "Done. Pending (TODO:):"
grep -rn "TODO:" --exclude-dir=.git . | cut -c1-120 || true
