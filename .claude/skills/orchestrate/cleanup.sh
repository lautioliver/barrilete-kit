#!/usr/bin/env bash
# Cleans up what an orchestrate run leaves behind, for the already closed issues:
# - the worktrees ../<repo>-wt/<n> (the prepare.sh --worktree ones): the worktree is removed, unless
#   its branch has an open PR;
# - the claude/<n>-… branches (local or remote) whose PR was closed without merging: they are only listed, with
#   the command to delete them (git push origin --delete; gh pr close --delete-branch fails from a
#   detached HEAD). Deleting a branch can lose work, so the person decides. It is decided
#   by the state of the PR on GitHub, not by ancestry (works with squash and rebase).
# Without --delete it only lists; --delete only removes worktrees. It never removes one with uncommitted changes,
# nor any if unsaved retros remain in <common .git>/pending-retros/ (or in retros-pendientes/, the 0.9 name): the run is not
# considered closed until they are saved with retro.sh.
# Usage: cleanup.sh [--delete]
set -euo pipefail
DELETE=""
case "${1:-}" in
  "") ;;
  --delete) DELETE=1 ;;
  *) echo "Usage: $0 [--delete]" >&2; exit 64 ;;
esac
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PENDIENTES="$(git rev-parse --path-format=absolute --git-common-dir)/pending-retros"
PENDIENTES_VIEJO="$(git rev-parse --path-format=absolute --git-common-dir)/retros-pendientes"  # 0.9
errores=0

# Is the issue closed? If it cannot be read, it says so and counts it as an error (and it is not touched).
# The state of each issue is requested only once (bash 3.2: no associative arrays).
ESTADOS=$'\n'
cerrado() {
  local estado
  estado=$(sed -n "s/^$1=//p" <<<"$ESTADOS")
  if [ -z "$estado" ]; then
    if ! estado=$(gh api "repos/$REPO/issues/$1" 2>/dev/null | jq -er .state 2>/dev/null); then
      echo "Could not read the state of issue #$1 ($2): is gh authenticated? Not touching it." >&2
      estado=error; errores=1
    fi
    ESTADOS+="$1=$estado"$'\n'
  fi
  [ "$estado" = closed ]
}

# Does the branch have an open PR? Some projects close the issue when opening the PR: the worktree
# is still needed to fix what the review asks for. If it cannot be read, it is not touched.
pr_abierto() {
  local estados
  [ -n "$1" ] || return 1
  if ! estados=$(gh pr list --head "$1" --state all --json state 2>/dev/null | jq -r '[.[] | select(.state == "OPEN")] | length' 2>/dev/null); then
    echo "Could not read the PRs of $1: not touching it." >&2; errores=1; return 0
  fi
  [ "${estados:-0}" != 0 ]
}

cerrados=(); sucios=()
while read -r ruta; do
  cerrado "${ruta##*/}" "$ruta" || continue
  pr_abierto "$(git -C "$ruta" branch --show-current 2>/dev/null)" && continue
  if [ -n "$(git -C "$ruta" status --porcelain 2>/dev/null)" ]; then sucios+=("$ruta")
  else cerrados+=("$ruta"); fi
done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -E -- '-wt/[0-9]+$' || true)

# Branches of closed issues (local or remote, no fetch: listing changes nothing), by the state of their PR.
ramas=(); avisos=()
while read -r rama; do
  [[ "$rama" =~ ^claude/([0-9]+)- ]] || continue
  cerrado "${BASH_REMATCH[1]}" "$rama" || continue
  if ! estados=$(gh pr list --head "$rama" --state all --json number,state 2>/dev/null | jq -r '[.[].state] | join(",")' 2>/dev/null); then
    echo "Could not read the PRs of $rama." >&2; errores=1; continue
  fi
  case ",$estados," in
    *,MERGED,*|*,OPEN,*) continue ;;   # merged (also squash or rebase) or still open
    ,,) avisos+=("$rama (issue closed without a PR: review it before deleting it)"); continue ;;
  esac
  if git rev-parse -q --verify "refs/heads/$rama" >/dev/null \
    && [ -n "$(git rev-list "$rama" --not --remotes=origin 2>/dev/null)" ]; then
    avisos+=("$rama (PR closed without merging, with unpushed commits)"); continue
  fi
  ramas+=("$rama")
done < <({ git for-each-ref --format='%(refname:short)' refs/heads/claude/
           git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/claude/; } | sort -u)

if [ $((${#cerrados[@]} + ${#sucios[@]} + ${#ramas[@]} + ${#avisos[@]})) -eq 0 ]; then
  [ "$errores" = 0 ] && echo "Nothing to clean up from closed issues."
  exit "$errores"
fi
for r in ${cerrados[@]+"${cerrados[@]}"}; do echo "- worktree $r (issue closed)"; done
for r in ${sucios[@]+"${sucios[@]}"}; do echo "- worktree $r (issue closed, with uncommitted changes: not removed)"; done
# Branches that are still in a worktree: git branch -D fails until it is removed.
EN_WT=$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
for r in ${ramas[@]+"${ramas[@]}"}; do
  if [ -z "$DELETE" ] && grep -qxF "$r" <<<"$EN_WT"; then
    echo "- rama $r (PR closed without merging; it has a worktree: delete it after --delete)"
  else echo "- rama $r (PR closed without merging)"; fi
done
for r in ${avisos[@]+"${avisos[@]}"}; do echo "- rama $r"; done

# The commands to delete the branches, at the end: after removing the worktrees.
comandos_ramas() {
  [ ${#ramas[@]} -gt 0 ] || return 0
  echo; echo "Branches are not deleted automatically. If the person confirms, one by one:"
  local en_wt; en_wt=$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
  # The local one first and with &&: if it cannot be deleted (it is still in a worktree), the remote one is not touched.
  for r in "${ramas[@]}"; do
    if grep -qxF "$r" <<<"$en_wt"; then
      if [ -n "$DELETE" ]; then echo "  $r: still in a worktree (with changes or locked); remove it before deleting the branch"
      else echo "  $r: after --delete"; fi
    elif git rev-parse -q --verify "refs/heads/$r" >/dev/null; then
      echo "  git branch -D $r && git push origin --delete $r"
    else echo "  git push origin --delete $r"; fi
  done
}
if [ -z "$DELETE" ]; then
  comandos_ramas
  echo; echo "To remove the worktrees: $0 --delete"
  exit "$errores"
fi

for dir in "$PENDIENTES" "$PENDIENTES_VIEJO"; do
  if ls "$dir"/*.md >/dev/null 2>&1; then
    echo "Not deleting anything: there are unsaved retros in $dir. Retry each one with" >&2
    echo ".claude/skills/improve-skills/retro.sh <file> and run this again." >&2
    exit 1
  fi
done
for r in ${cerrados[@]+"${cerrados[@]}"}; do
  if git worktree remove "$r" 2>/dev/null; then echo "Removed: $r"
  else echo "cleanup.sh: could not remove $r (locked with git worktree lock?)." >&2; errores=1; fi
done
comandos_ramas
exit "$errores"
