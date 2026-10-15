#!/usr/bin/env bash
# Prepares the implementation of an issue: validates it can be taken, assigns it
# and creates the branch. Prints the issue context for the agent.
# Usage: prepare.sh <issue number> [--review] [--worktree]
#   --review:  only validates and prints; does not assign or create the branch.
#   --worktree: creates (or resumes) the branch in its own worktree, ../<repo>-wt/<n>,
#               without touching the current checkout. Prints "Worktree: <path>".
set -euo pipefail
USO="Usage: $0 <issue number> [--review] [--worktree] | --help"
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<AYUDA
$USO

Validates that the issue can be taken (open, not an epic, not blocked, no other person
assigned, no uncommitted changes), assigns it, creates the branch claude/<n>-<description>
from the base branch (or resumes the issue one, claude/<n>-*, local or on origin, even if the title
changed; if there is more than one, it fails and lists them) and prints the issue with its context.

  --review   Only validates and prints: does not assign or create the branch.
  --worktree  The same, but in its own worktree (../<repo>-wt/<n>), without touching the
              current checkout: useful to run several issues in parallel.
              - Prints "Worktree: <path>". Work there with absolute paths or
                git -C <path>: if the current directory is reset between commands,
                you would commit in the main checkout.
              - If the branch is already in another worktree, it fails without assigning.
              - With the PR merged, delete it with: git worktree remove <path>
AYUDA
  exit 0
fi
N="${1:?$USO}"; N="${N#\#}"; shift
REVISAR=""; WORKTREE=""
for opcion in "$@"; do
  case "$opcion" in
    --review) REVISAR=1 ;;
    --worktree) WORKTREE=1 ;;
    *) echo "$USO" >&2; exit 64 ;;
  esac
done
[[ "$N" =~ ^[0-9]+$ ]] || { echo "$USO" >&2; exit 64; }
BASE="${BASE:-<BASE_BRANCH>}"   # the template init replaces <BASE_BRANCH>
# Uninitialized template (the placeholder is still there): the remote default branch, with a warning.
if [[ "$BASE" == "<"*">" ]]; then
  defecto=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true); defecto="${defecto#origin/}"
  [ -n "$defecto" ] || defecto=$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p')
  [ -n "$defecto" ] || { echo "prepare.sh: the base branch is not configured ($BASE). Set BASE=<branch>." >&2; exit 64; }
  echo "Warning: the base branch is not configured ($BASE); using the remote default branch, $defecto. For another one, set BASE." >&2
  BASE="$defecto"
fi
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
YO=$(gh api user -q .login)

issue=$(gh api "repos/$REPO/issues/$N")
error() { echo "CANNOT TAKE #$N: $*" >&2; exit 1; }

[ "$(jq -r '.pull_request // empty' <<<"$issue")" ] && error "it is a PR, not an issue."
[ "$(jq -r .state <<<"$issue")" = "open" ] || error "it is closed."
if [ "$(jq -r '(.sub_issues_summary.total // 0) > (.sub_issues_summary.completed // 0)' <<<"$issue")" = "true" ]; then
  ver=""
  [ -f .claude/skills/project-status/available.sh ] && ver=" (see .claude/skills/project-status/available.sh)"
  error "it is an epic with open sub-issues. Implement its sub-issues$ver."
fi
# Issue dependencies are a new GitHub feature: if the repo does not have it (404), it continues without blockers.
bloq=""
if deps=$(gh api "repos/$REPO/issues/$N/dependencies/blocked_by" 2>/dev/null); then
  bloq=$(jq -r '[.[] | select(.state == "open") | "#\(.number) \(.title)"] | join("; ")' <<<"$deps")
fi
[ -n "$bloq" ] && error "it is blocked by: $bloq"
otros=$(jq -r --arg yo "$YO" '[.assignees[].login | select(. != $yo)] | join(", ")' <<<"$issue")
# Assigned = responsible (create-issue assigns it according to .github/team.json): it belongs to that person.
[ -n "$otros" ] && error "it belongs to $otros (responsible). Ask them for it or reassign it: gh issue edit $N --remove-assignee <login> --add-assignee @me"

titulo=$(jq -r .title <<<"$issue")
# Branch: claude/<n>-<description>, lowercase, no accents, only [a-z0-9-], ≤ 50 characters.
slug=$(printf '%s' "$titulo" | perl -CS -MUnicode::Normalize -ne 'print lc NFD($_) =~ s/\pM//gr' \
  | perl -pe 's/[^a-z0-9]+/-/g; s/^-+|-+$//g; s/^(.{1,40})(-.*)?$/$1/ if length > 40')
RAMA="claude/$N-$slug"
# If the issue already has a branch (claude/<n>-*, local or on origin), that one is resumed even if the title
# changed after taking it (#41). With more than one none is chosen: they are listed. The ones of an already merged
# or closed PR do not count: a reopened issue starts again.
del_issue() { grep -E "^claude/$N-[^/]+$" || true; }
locales=$(git for-each-ref --format='%(refname:strip=2)' "refs/heads/claude/" | del_issue)
remotas=$(git ls-remote --heads origin "claude/$N-*") || error "could not query the branches of origin (network or permissions?). Without that I could create a second branch for the issue."
remotas=$(awk '{sub("^refs/heads/", "", $2); print $2}' <<<"$remotas" | del_issue)
existentes=""
for r in $(printf '%s\n%s\n' "$locales" "$remotas" | sort -u); do
  estado=$(gh pr list -R "$REPO" --head "$r" --state all --json state -q '.[0].state' 2>/dev/null || true)
  case "$estado" in MERGED|CLOSED) continue ;; esac
  existentes+="$r"$'\n'
done
existentes=$(sed '/^$/d' <<<"$existentes")
if [ "$(grep -c . <<<"$existentes")" -gt 1 ]; then
  error "it has more than one branch: $(paste -sd ' ' - <<<"$existentes"). Delete the extra ones or resume one by hand."
fi
[ -n "$existentes" ] && RAMA="$existentes"
# Only on origin: the local one is created from there.
SOLO_REMOTA=""; EN_ORIGIN=()
[ -n "$existentes" ] && ! grep -qx "$RAMA" <<<"$locales" && SOLO_REMOTA=1
grep -qx "$RAMA" <<<"$remotas" && EN_ORIGIN=("refs/heads/$RAMA:refs/remotes/origin/$RAMA")
# The worktree goes next to the main checkout (the first in the list), even if this
# is run from another worktree.
if [ -n "$WORKTREE" ]; then
  raiz=$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
  raiz=$(cd "$raiz" && pwd -P)
  WT="$(dirname "$raiz")/$(basename "$raiz")-wt/$N"
fi

echo "# Issue #$N: $titulo"
echo "Labels: $(jq -r '[.labels[].name] | join(", ")' <<<"$issue")"
echo "URL: $(jq -r .html_url <<<"$issue")"
# gh prints the 404 JSON on stdout when there is no epic: the exit code is used.
if padre=$(gh api "repos/$REPO/issues/$N/parent" 2>/dev/null); then
  echo "Epic: $(jq -r '"#\(.number) \(.title)"' <<<"$padre")"
fi
bloquea=""
if deps=$(gh api "repos/$REPO/issues/$N/dependencies/blocking" 2>/dev/null); then
  bloquea=$(jq -r '[.[] | select(.state == "open") | "#\(.number)"] | join(", ")' <<<"$deps")
fi
[ -n "$bloquea" ] && echo "Blocks: $bloquea (when this one is closed, they get unblocked)"
echo
jq -r '.body // "(no body)"' <<<"$issue"
comentarios=$(gh api "repos/$REPO/issues/$N/comments" -q '.[] | "\n--- @\(.user.login):\n\(.body)"')
[ -n "$comentarios" ] && { echo; echo "## Comments"; echo "$comentarios"; }
echo

if [ -n "$REVISAR" ]; then
  echo "(--review: nothing was assigned and no branch was created. Proposed branch: $RAMA${WORKTREE:+, proposed worktree: $WT})"
  exit 0
fi

# Several agents in parallel can collide on the .git locks: only that is retried.
# Fetches the base and, if the issue already has a branch on origin, that one too (to resume or compare).
traer() {
  local intento err
  for intento in 1 2 3; do
    err=$(git fetch -q origin "$BASE" ${EN_ORIGIN[@]+"${EN_ORIGIN[@]}"} 2>&1) && return 0
    grep -Eq "\.lock'|cannot lock ref" <<<"$err" || break
    [ "$intento" -lt 3 ] && sleep "$intento"
  done
  echo "$err" >&2; return 1
}
# The local branch is behind the origin one (another clone pushed): a warning is printed, nothing is overwritten.
atrasada() {
  [ ${#EN_ORIGIN[@]} -gt 0 ] && git show-ref -q --verify "refs/heads/$RAMA" \
    && ! git merge-base --is-ancestor "origin/$RAMA" "$RAMA" \
    && echo "Warning: origin/$RAMA has commits that your local branch does not have. Fetch them (git pull --ff-only) before continuing." >&2
  return 0
}

# Where the branch already is (if it is). prune forgets the worktrees whose folder was deleted by hand.
git worktree prune
en_uso=$(git worktree list --porcelain | awk -v r="branch refs/heads/$RAMA" '/^worktree /{w=substr($0, 10)} $0 == r {print w}')
if [ -n "$en_uso" ]; then
  [ -d "$en_uso" ] || error "the branch $RAMA is in a locked worktree whose folder does not exist ($en_uso). If nobody uses it: git worktree unlock \"$en_uso\" && git worktree prune"
  en_uso=$(cd "$en_uso" && pwd -P)
fi

if [ -z "$WORKTREE" ]; then
  [ -n "$(git status --porcelain)" ] && error "there are uncommitted changes in the working tree."
  actual=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
  [ -n "$en_uso" ] && [ "$en_uso" != "$actual" ] && error "the branch $RAMA is already in use in another worktree: $en_uso"
  # First the branch, then the assignment: if something fails, the issue is not left assigned.
  traer
  if git show-ref -q --verify "refs/heads/$RAMA"; then
    git switch -q "$RAMA"; echo "Existing branch: $RAMA (resuming)"; atrasada
  elif [ -n "$SOLO_REMOTA" ]; then
    git switch -q --no-track -c "$RAMA" "origin/$RAMA"; echo "Existing branch: $RAMA (resuming from origin)"
  else
    git switch -q -c "$RAMA" "origin/$BASE"; echo "New branch: $RAMA (from origin/$BASE)"
  fi
  gh issue edit "$N" -R "$REPO" --add-assignee @me >/dev/null
  echo "Assigned to @$YO."
  exit 0
fi

# --worktree: the worktree is validated and created before assigning, so a failure does not leave the issue assigned.
[ -n "$en_uso" ] && [ "$en_uso" != "$WT" ] && error "the branch $RAMA is already in use in another worktree: $en_uso"
if [ -n "$en_uso" ]; then
  [ -n "$(git -C "$WT" status --porcelain)" ] && error "there are uncommitted changes in the worktree $WT."
elif [ -e "$WT" ]; then
  error "$WT already exists and is not the worktree of $RAMA."
fi
traer
if [ -n "$en_uso" ]; then
  echo "Existing branch: $RAMA (resuming)"; atrasada
elif git show-ref -q --verify "refs/heads/$RAMA"; then
  mkdir -p "$(dirname "$WT")"; git worktree add -q "$WT" "$RAMA"
  echo "Existing branch: $RAMA (resuming)"; atrasada
elif [ -n "$SOLO_REMOTA" ]; then
  mkdir -p "$(dirname "$WT")"; git worktree add -q --no-track -b "$RAMA" "$WT" "origin/$RAMA"
  echo "Existing branch: $RAMA (resuming from origin)"
else
  mkdir -p "$(dirname "$WT")"; git worktree add -q --no-track -b "$RAMA" "$WT" "origin/$BASE"
  echo "New branch: $RAMA (from origin/$BASE)"
fi
gh issue edit "$N" -R "$REPO" --add-assignee @me >/dev/null
echo "Worktree: $WT"
echo "Assigned to @$YO."
