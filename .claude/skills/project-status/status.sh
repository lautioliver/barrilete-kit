#!/usr/bin/env bash
# Summary of the current state of the project, generated on the spot from the sources
# (git, GitHub, docs). It is not stored: it is always up to date. Read-only.
# Usage: status.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
REPO=$(gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner')
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch -q --tags origin 2>/dev/null || true

echo "# Status of $REPO — $(date +%Y-%m-%d)"
echo
echo "## Version and branches"
echo "- Latest version: $(git describe --tags --abbrev=0 "origin/$DEFAULT" 2>/dev/null || echo 'no tags')"
echo "- Default branch: $DEFAULT"
regla=$(grep -m1 -E '^- \*\*(Rama base|Rama|Base branch):\*\*' AGENTS.md 2>/dev/null | sed -E 's/^- \*\*(Rama base|Rama|Base branch):\*\* //')
[ -n "$regla" ] && echo "- Flow: $regla"
rel=$(git branch -r --list 'origin/release/*' | sed 's#origin/##' | xargs)
[ -n "$rel" ] && echo "- Open releases: $rel"
echo "- Latest commit on $DEFAULT: $(git log -1 --format='%h %s (%cr)' "origin/$DEFAULT" 2>/dev/null)"

echo
echo "## Architecture"
if grep -Eq "TODO: (completar|fill in)" docs/development/architecture.md 2>/dev/null; then
  echo "_docs/development/architecture.md has no content yet._"
else
  echo "See docs/development/architecture.md (updated $(git log -1 --format=%cr -- docs/development/architecture.md))."
fi

echo
echo "## Work"
gh api "repos/$REPO/issues?state=open&per_page=100" --paginate 2>/dev/null | jq -rs '
  [.[][] | select(.pull_request | not)] as $i
  | "- Open issues: \($i | length) · blocked: \([$i[] | select((.issue_dependencies_summary.blocked_by // 0) > 0)] | length) · assigned: \([$i[] | select(.assignees | length > 0)] | length) · untriaged: \([$i[] | select(any(.labels[]; .name == "status:triage"))] | length)",
    ([$i[] | select((.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0))][]
      | "- Epic #\(.number) \(.title): \(.sub_issues_summary.completed)/\(.sub_issues_summary.total)")'
echo "- Open PRs:"
gh pr list --limit 20 --json number,title,headRefName,isDraft -q '.[] | "  - #\(.number) \(.title)\(if .isDraft then " (draft)" else "" end)"' | grep . || echo "  _None._"

echo
echo "## Known debt"
gh issue list --state open --label "type:audit" --limit 100 --json number -q 'length' 2>/dev/null \
  | xargs -I{} echo "- Open audit findings: {}"
gh issue list --state open --label "priority:critical" --limit 20 --json number,title -q '.[] | "- CRITICAL #\(.number) \(.title)"'

echo
echo "## Recent decisions"
recientes=$(git log --since="60 days ago" --diff-filter=AMR --name-only --format= "origin/$DEFAULT" -- 'docs/decisions/ADR-*.md' 'docs/decisions/kit/ADR-*.md' 2>/dev/null | sort -u | grep -v 'ADR-000\|\.es\.md$')
if [ -z "$recientes" ]; then echo "_No new or amended ADR in 60 days._"; else
  for f in $recientes; do [ -f "$f" ] && echo "- $(head -1 "$f" | sed 's/^# //') ($(git log -1 --format=%cr -- "$f"))"; done
fi

echo
echo "## Migrations"
migr=$(python3 -c "import json;print(' '.join(r for s in json.load(open('docs/agents-map.json'))['sensitive'] if s['type']=='schema' for r in s['paths']))" 2>/dev/null)
pend=""
for pr in $(gh pr list --limit 50 --json number -q '.[].number'); do
  files=$(gh pr diff "$pr" --name-only 2>/dev/null)
  for g in $migr; do
    re=$(printf '%s' "$g" | sed 's#\*\*/#(.*/)?#g; s#\*\*#.*#g; s#\*#[^/]*#g')
    echo "$files" | grep -Eq "^$re$" && { pend="$pend #$pr"; break; }
  done
done
if [ -n "$pend" ]; then echo "- Open PRs with schema changes:$pend"; else echo "_No open PR touches migrations._"; fi
