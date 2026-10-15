#!/usr/bin/env bash
# Gathers what /improve-skills has to consolidate: the new retros since the
# last consolidation (agents/retros branch and the 0.9 one, agentes/retros, git only) and
# objective signals (CI failures and reverts; the CI ones need gh). Read-only.
# Retros with 0.9 keys and values are shown with the new ones, so both count as the same group.
# Usage: signals.sh [days]   (default: 30, for the objective signals)
set -euo pipefail
DIAS="${1:-30}"
AQUI=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
. "$AQUI/legacy-names.sh"
cd "$(git rev-parse --show-toplevel)" || exit 1
desde=$(date -u -v-"${DIAS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$DIAS days ago" +%Y-%m-%dT%H:%M:%SZ)

# Shows the retros of a branch added after <hasta> (all if empty) and the commit to consolidate up to.
# Sets hay=1 if there was something new (the commit to consolidate is only offered then).
# mostrar <punta> <branch> <hasta> <label to add to each file ("" for the new branch)>
mostrar() {
  local punta=$1 rama=$2 hasta=$3 sufijo=$4 nuevas f
  hay=""
  if [ -n "$hasta" ] && git merge-base --is-ancestor "$hasta" "$punta" 2>/dev/null; then
    nuevas=$(git diff --name-only --diff-filter=A "$hasta" "$punta" -- retros/)
  else
    [ -n "$hasta" ] && echo "_Warning: the consolidation marker points to $hasta, which is not in $rama; showing all its retros._"
    nuevas=$(git ls-tree -r --name-only "$punta" -- retros/)
  fi
  if [ -z "$nuevas" ]; then
    echo "_None in $rama since the last consolidation._"
  else
    hay=1
    while IFS= read -r f; do
      echo "### $f$sufijo"; git show "$punta:$f" | normalize_legacy_names; echo
    done <<<"$nuevas"
  fi
}

punta=$(retros_tip "$RETROS_BRANCH"); punta_vieja=$(retros_tip "$RETROS_LEGACY_BRANCH")
echo "# Signals to improve the skills"
echo
echo "## New retros"
if [ -z "$punta" ] && [ -z "$punta_vieja" ]; then
  echo "_No retros yet (the branch $RETROS_BRANCH does not exist)._"
else
  marcas=""
  [ -z "$punta" ] || marcas=$(git show "$punta:consolidated.md" 2>/dev/null || true)
  if [ -n "$punta" ]; then
    hasta=$(sed -n 's/^consolidated-until: *//p' <<<"$marcas" | head -1 || true)
    mostrar "$punta" "$RETROS_BRANCH" "$hasta" ""
    [ -z "$hay" ] || echo "To mark this as consolidated, consolidate up to: $punta"
  fi
  if [ -n "$punta_vieja" ]; then
    # The marker of the 0.9 branch lives in consolidated.md of the new one; before that, in its own consolidado.md.
    hasta=$(sed -n 's/^legacy-consolidated-until: *//p' <<<"$marcas" | head -1 || true)
    [ -n "$hasta" ] || hasta=$(git show "$punta_vieja:consolidado.md" 2>/dev/null | sed -n 's/^consolidado-hasta: *//p' | head -1 || true)
    echo
    echo "### 0.9 branch ($RETROS_LEGACY_BRANCH)"
    mostrar "$punta_vieja" "$RETROS_LEGACY_BRANCH" "$hasta" " ($RETROS_LEGACY_BRANCH)"
    [ -z "$hay" ] || echo "To mark the 0.9 branch ($RETROS_LEGACY_BRANCH) as consolidated, consolidate up to: $punta_vieja"
  fi
fi

echo
echo "## CI failures on agent branches (last $DIAS days)"
if REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); then
  gh run list -R "$REPO" --status failure --limit 200 --json headBranch,workflowName,displayTitle,createdAt,url \
    | jq -r --arg desde "$desde" '[.[] | select(.headBranch | startswith("claude/")) | select(.createdAt >= $desde)]
      | if length == 0 then "_None._" else
        group_by(.workflowName) | sort_by(-length)[]
        | "- **\(.[0].workflowName)**: \(length) failure(s) on \([.[].headBranch] | unique | length) branch(es). Example: \(.[0].headBranch) — \(.[0].displayTitle) (\(.[0].url))"
      end'
else
  echo "_Not available: an authenticated gh is required._"
fi

echo
echo "## Reverts (last $DIAS days)"
reverts=$(git log --since="$DIAS days ago" -i --grep='^revert' --format='- %h %s (%cr)' 2>/dev/null || true)
echo "${reverts:-_None._}"
