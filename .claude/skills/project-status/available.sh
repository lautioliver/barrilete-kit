#!/usr/bin/env bash
# Lists the open issues that can be started now (no open blockers),
# sorted by priority and with the current user's first; apart from them, the ones that
# already have an open PR that closes them (in progress), the
# blocked ones with what blocks them, and the epics (issues with open
# sub-issues), which are worked through their sub-issues.
# Read-only: it changes nothing.
# Usage: available.sh [owner/repo]   (default: the repo of the current directory)
set -euo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
YO=$(gh api user -q .login 2>/dev/null || true)

issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" \
  | jq -s '[.[][] | select(.pull_request | not)]')

# Open PRs and the issues they close: {"<issue number>": [<PR number>, ...]}.
# GitHub only fills closingIssuesReferences when the PR goes to the default branch,
# so "Closes #n" is also read from the body, and the number from the branch (<type>/<n>-…).
# shellcheck disable=SC2016  # jq program
MAPEO='
  [.[] | . as $pr
    | ([.closingIssuesReferences[].number]
       + ([(.body // "") | gsub("`[^`]*`"; "") | scan("(?i)(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):? +#([0-9]+)") | .[0] | tonumber])
       + ([.headRefName | capture("^[a-z]+/(?<n>[0-9]+)-")? | .n | tonumber]))
    | unique[] | {issue: tostring, pr: $pr.number}]
  | group_by(.issue) | map({key: .[0].issue, value: [.[].pr]}) | from_entries'
CAMPOS=number,headRefName,body,closingIssuesReferences,baseRefName
prs=$(gh pr list -R "$REPO" --state open --limit 200 --json "$CAMPOS" | jq "$MAPEO")
# Merged into a branch that is not the main one (e.g. develop): the issue stays open
# until the release, but it is already resolved. It is not offered as available.
PRINCIPAL=$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name)
release=$(gh pr list -R "$REPO" --state merged --limit 200 --json "$CAMPOS" \
  | jq --arg p "$PRINCIPAL" "[.[] | select(.baseRefName != \$p)] | $MAPEO")

# Order: critical, high, medium, low, no priority.
# shellcheck disable=SC2016  # jq program: the $ are jq's, not bash's
ORDEN='def prio: ([.labels[].name | select(startswith("priority:"))][0] // "") as $p
  | {"priority:critical":0,"priority:high":1,"priority:medium":2,"priority:low":3}[$p] // 4;
def epica: (.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0);
def prs: $prs[.number | tostring] // [];
# Assigned = responsible (create-issue sets it according to .github/team.json); in progress = with an open PR.
def enrelease: ($release[.number | tostring] // []) | length > 0;
def tomado: (prs | length) > 0 or enrelease;
def mio: any(.assignees[]; .login == $yo);
def responsable: if (.assignees | length) == 0 then "no owner" else ([.assignees[].login | "@" + .] | join(", ")) end;
def quien: ([.assignees[].login | "@" + .] + [prs[] | "PR #\(.)"]) | join(", ");
def etiqueta: ([.labels[].name | select(startswith("priority:") or startswith("area:"))] | join(", "));'

echo "## Can be started now"
echo
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) == 0 and (epica | not) and (tomado | not))]
  | sort_by((if mio then 0 else 1 end), prio, .number)
  | if length == 0 then "_None._" else .[] | "- #\(.number) \(.title) — \(responsable)" + (etiqueta | if . == "" then "" else " · \(.)" end) end'

echo
echo "## In progress"
echo
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) == 0 and (epica | not) and (prs | length) > 0)] | sort_by(prio, .number)
  | if length == 0 then "_None._" else .[] | "- #\(.number) \(.title) — \(quien)" end'

echo
echo "## Waiting for release"
echo
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select(enrelease and ((prs | length) == 0))] | sort_by(.number)
  | if length == 0 then "_None._" else .[] | ($release[.number | tostring]) as $r | "- #\(.number) \(.title) — merged in \(if ($r | length) > 1 then "PRs" else "PR" end) #\($r | map(tostring) | join(", #")); still has to reach the main branch" end'

echo
echo "## Blocked"
echo
bloqueados=$(echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select((.issue_dependencies_summary.blocked_by // 0) > 0 and (epica | not))] | sort_by(prio, .number) | .[].number')
[ -z "$bloqueados" ] && echo "_None._"
for n in $bloqueados; do
  titulo=$(echo "$issues" | jq -r ".[] | select(.number == $n) | .title")
  por=$(gh api "repos/$REPO/issues/$n/dependencies/blocked_by" \
    | jq -r '[.[] | select(.state == "open") | "#\(.number)"] | join(", ")')
  echo "- #$n $titulo — blocked by $por"
done

echo
echo "## Epics in progress"
echo
echo "$issues" | jq -r --argjson prs "$prs" --argjson release "$release" --arg yo "$YO" "$ORDEN"'
  [.[] | select(epica)] | sort_by(prio, .number)
  | if length == 0 then "_None._" else .[] | "- #\(.number) \(.title) — \(.sub_issues_summary.completed)/\(.sub_issues_summary.total) sub-issues closed" end'
