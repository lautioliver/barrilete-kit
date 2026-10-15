#!/usr/bin/env bash
# Gathers what /improve-skills has to consolidate: the new retros since the
# last consolidation (agentes/retros branch, git only) and objective signals
# (CI failures and reverts; the CI ones need gh). Read-only.
# Usage: signals.sh [days]   (default: 30, for the objective signals)
set -euo pipefail
DIAS="${1:-30}"
RAMA=agentes/retros
AQUI=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
. "$AQUI/legacy-names.sh"
cd "$(git rev-parse --show-toplevel)" || exit 1
desde=$(date -u -v-"${DIAS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$DIAS days ago" +%Y-%m-%dT%H:%M:%SZ)

# The remote one if it exists; otherwise the local one (retros saved before having a remote).
ref="refs/heads/$RAMA"
if git remote get-url origin >/dev/null 2>&1; then
  git fetch -q origin "+$ref:refs/remotes/origin/$RAMA" 2>/dev/null || true
  git rev-parse -q --verify "refs/remotes/origin/$RAMA" >/dev/null && ref="refs/remotes/origin/$RAMA"
fi
echo "# Signals to improve the skills"
echo
echo "## New retros"
if ! punta=$(git rev-parse -q --verify "$ref"); then
  echo "_No retros yet (the branch $RAMA does not exist)._"
else
  hasta=$(git show "$punta:consolidado.md" 2>/dev/null | sed -n 's/^consolidado-hasta: *//p' | head -1 || true)
  if [ -n "$hasta" ] && git merge-base --is-ancestor "$hasta" "$punta" 2>/dev/null; then
    nuevas=$(git diff --name-only --diff-filter=A "$hasta" "$punta" -- retros/)
  else
    [ -n "$hasta" ] && echo "_Warning: consolidado.md points to $hasta, which is not in $RAMA; showing all the retros._"
    nuevas=$(git ls-tree -r --name-only "$punta" -- retros/)
  fi
  if [ -z "$nuevas" ]; then
    echo "_None since the last consolidation._"
  else
    while IFS= read -r f; do
      echo "### $f"; git show "$punta:$f" | normalize_legacy_names; echo
    done <<<"$nuevas"
  fi
  echo "To mark this as consolidated, consolidate up to: $punta"
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
