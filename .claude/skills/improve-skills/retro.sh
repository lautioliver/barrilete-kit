#!/usr/bin/env bash
# Saves a retro of the agent flow as a file on the orphan branch
# agentes/retros (retros/YYYY-MM-DD-<skill>-<n>.md; <n> is the issue, the orchestrate
# run or the PR). It does not use GitHub: only git.
# It writes with plumbing (temporary index), so it changes neither the current branch nor the
# index, and retries if someone else wrote first. If it cannot save it, it leaves it in
# <common .git>/retros-pendientes/ to retry with the same command.
# Usage: retro.sh <file.md>                          publishes a retro
#        retro.sh --consolidated <commit> <PR link>  marks what is consolidated (used by /improve-skills)
set -euo pipefail
AQUI=$(cd "$(dirname "$0")" && pwd)
if [ $# -eq 0 ]; then
  echo "Usage: $0 <file.md>. Retro format:"; echo
  cat "$AQUI/retro-template.md"; exit 0
fi
# The retro path is relative to where it was called, not to the root.
if [ "$1" != "--consolidated" ] && [ -f "$1" ]; then
  set -- "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
fi
RAMA=agentes/retros
cd "$(git rev-parse --show-toplevel)"
REMOTO=""
git remote get-url origin >/dev/null 2>&1 && REMOTO=origin
# The common .git (not the worktree one, which is deleted with git worktree remove).
PENDIENTES="$(git rev-parse --path-format=absolute --git-common-dir)/retros-pendientes"
hoy=$(date -u +%Y-%m-%d)
contenido=$(mktemp); idx=$(mktemp -d)
modo=""; guardado=0

# If something fails after preparing the retro (any command, not only the push),
# the retro stays in pending instead of being lost.
# shellcheck disable=SC2317,SC2329  # invoked by the EXIT trap (the code changes depending on the version)
al_salir() {
  if [ "$modo" = retro ] && [ "$guardado" = 0 ]; then
    mkdir -p "$PENDIENTES"; pendiente="$PENDIENTES/${base##*/}-$$.md"
    cp "$contenido" "$pendiente"
    echo "retro.sh: could not save to $RAMA. It stayed in $pendiente; retry with: $0 $pendiente" >&2
  fi
  rm -rf "$contenido" "$idx"
}
trap al_salir EXIT

# The tip of the retros branch: the remote one if it exists; otherwise the local one
# (retros saved before having a remote).
punta() {
  if [ -n "$REMOTO" ]; then
    git fetch -q "$REMOTO" "+refs/heads/$RAMA:refs/remotes/$REMOTO/$RAMA" 2>/dev/null || true
    git rev-parse -q --verify "refs/remotes/$REMOTO/$RAMA" && return
  fi
  git rev-parse -q --verify "refs/heads/$RAMA" || true
}

# Normalized frontmatter: no CRLF and no quotes around the values.
# Fails if there is no closed frontmatter at the start.
frontmatter() {
  tr -d '\r' <"$1" | awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{c=1; exit} NR>1{print} END{exit !c}' \
    | sed -E 's/^([a-z_]+): *"(.*)" *$/\1: \2/; s/^([a-z_]+): *'"'"'(.*)'"'"' *$/\1: \2/'
}
campo() { sed -n "s/^$1: *//p" <<<"$2" | head -1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

if [ "$1" = "--consolidated" ]; then
  # Only a commit of the retros branch: with another one, signals.sh would show everything again.
  p=$(punta)
  if [ $# -ne 3 ] || ! hasta=$(git rev-parse -q --verify "$2^{commit}") || [ -z "$p" ] \
    || ! git merge-base --is-ancestor "$hasta" "$p"; then
    echo "Usage: $0 --consolidated <commit of $RAMA printed by signals.sh> <PR link>" >&2; exit 64
  fi
  printf 'consolidado-hasta: %s\npr: %s\nfecha: %s\n' "$hasta" "$3" "$hoy" >"$contenido"
  base=consolidado; mensaje="improve-skills: consolidated up to $hasta"
else
  ARCHIVO="$1"
  [ -s "$ARCHIVO" ] || { echo "retro.sh: $ARCHIVO does not exist or is empty." >&2; exit 1; }
  if ! fm=$(frontmatter "$ARCHIVO"); then
    echo "retro.sh: the retro must start with a frontmatter between two --- lines. Format:" >&2
    cat "$AQUI/retro-template.md" >&2; exit 1
  fi
  skill=$(campo skill "$fm"); issue=$(campo issue "$fm"); pr=$(campo pr "$fm"); corrida=$(campo corrida "$fm")
  issue="${issue#\#}"; pr="${pr#\#}"
  case "$skill" in implement-issue|review-pr|improve-skills|orchestrate) ;; *)
    echo "retro.sh: 'skill:' (implement-issue, review-pr, improve-skills or orchestrate) is missing in the frontmatter. Format:" >&2
    cat "$AQUI/retro-template.md" >&2; exit 1;;
  esac
  # Identifies the retro by the issue (in orchestrate, the epic); if there is none, by the run
  # (YYYYMMDD-HHMM) or, if there is none either, by the PR (a PR without an issue).
  # The run only identifies an orchestrate run.
  if [[ "$issue" =~ ^[0-9]+$ ]]; then n="$issue"
  elif [ "$skill" = orchestrate ] && [[ "$corrida" =~ ^[0-9]{8}-[0-9]{4}$ ]]; then n="$corrida"
  elif [[ "$pr" =~ ^[0-9]+$ ]]; then n="pr$pr"
  else echo "retro.sh: 'issue: <n>', 'pr: <n>' or (in orchestrate) 'corrida: <YYYYMMDD-HHMM>' is missing in the frontmatter." >&2; exit 1
  fi
  # In a repo without commits git log fails: the retro is saved anyway, with unknown skill_sha.
  sha=$(git log -1 --format=%H -- ".claude/skills/$skill/SKILL.md" 2>/dev/null || true); sha="${sha:-desconocido}"
  # Model and role: if they are missing or empty, the retro is still saved as desconocido / sesion
  # (sessions before #35, or a template copied without filling it in).
  modelo=$(campo modelo "$fm"); modelo="${modelo:-desconocido}"
  rol=$(campo rol "$fm"); rol="${rol:-sesion}"
  # A subagent (role with a file in .claude/agents/) records the version of its definition.
  agente_sha=""
  case "$rol" in implementer|implementer-light|reviewer)
    agente_sha=$(campo agente_sha "$fm")
    if [ -z "$agente_sha" ]; then
      agente_sha=$(git log -1 --format=%H -- ".claude/agents/$rol.md" 2>/dev/null || true); agente_sha="${agente_sha:-desconocido}"
    fi;;
  esac
  # Normalized retro: modelo, rol and agente_sha are written only once, already normalized.
  fm_limpio=$(grep -vE '^(modelo|rol|agente_sha):' <<<"$fm" || true)
  {
    echo ---; echo "$fm_limpio"
    grep -q '^fecha:' <<<"$fm_limpio" || echo "fecha: $hoy"
    grep -q '^skill_sha:' <<<"$fm_limpio" || echo "skill_sha: $sha"
    echo "modelo: $modelo"
    echo "rol: $rol"
    if [ -n "$agente_sha" ]; then echo "agente_sha: $agente_sha"; fi
    echo ---; tr -d '\r' <"$ARCHIVO" | awk 'NR>1 && $0=="---" && !c {c=1; next} c'
  } >"$contenido"
  base="retros/$hoy-$skill-$n"; mensaje="retro: $skill $n"; modo=retro
fi
blob=$(git hash-object -w "$contenido")
nulo=$(printf '%0*d' "${#blob}" 0)   # 40 or 64 characters depending on the repo format

for intento in 1 2 3 4 5; do
  padre=$(punta)
  rm -f "$idx/index"
  [ -n "$padre" ] && GIT_INDEX_FILE="$idx/index" git read-tree "$padre"
  # consolidado.md is replaced; a retro never overwrites another (suffix -2, -3…).
  ruta="$base.md"; i=2
  while [ "$base" != consolidado ] && [ -n "$padre" ] && git cat-file -e "$padre:$ruta" 2>/dev/null; do
    ruta="$base-$i.md"; i=$((i + 1))
  done
  GIT_INDEX_FILE="$idx/index" git update-index --add --cacheinfo "100644,$blob,$ruta"
  arbol=$(GIT_INDEX_FILE="$idx/index" git write-tree)
  commit=$(git commit-tree "$arbol" ${padre:+-p "$padre"} -m "$mensaje")
  if [ -z "$REMOTO" ]; then
    # Compare-and-swap against the parent read: if another session wrote in between, it retries.
    git update-ref "refs/heads/$RAMA" "$commit" "${padre:-$nulo}" 2>/dev/null && guardado=1
  elif err=$(git push -q "$REMOTO" "$commit:refs/heads/$RAMA" 2>&1); then
    git update-ref "refs/remotes/$REMOTO/$RAMA" "$commit"; guardado=1
  elif ! grep -Eq '\[rejected\]|non-fast-forward|fetch first|cannot lock ref' <<<"$err"; then
    # Auth, network, protected branch: retrying is useless.
    echo "retro.sh: the push to $RAMA failed:" >&2; echo "$err" >&2; break
  fi
  if [ "$guardado" = 1 ]; then
    if [ -n "$REMOTO" ]; then echo "Saved in $RAMA:$ruta"; else echo "Saved in $RAMA:$ruta (local only: there is no origin remote)."; fi
    # If it was a pending one, it is no longer needed.
    if [ "$modo" = retro ] && [ "$(cd "$(dirname "$ARCHIVO")" && pwd -P)" = "$(cd "$PENDIENTES" 2>/dev/null && pwd -P)" ]; then
      rm -f "$ARCHIVO"
    fi
    exit 0
  fi
  [ "$intento" -lt 5 ] || break
  echo "Someone else wrote to $RAMA first; retrying ($intento/4)…" >&2
  sleep "$intento"
done
[ "$modo" = retro ] || echo "retro.sh: could not mark what is consolidated; run the same command again." >&2
exit 1
