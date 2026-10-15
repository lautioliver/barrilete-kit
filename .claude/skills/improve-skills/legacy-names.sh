#!/usr/bin/env bash
# What retro.sh and signals.sh share about the retros history. Sourced, not run.
#
# - RETROS_BRANCH / RETROS_LEGACY_BRANCH: since #128 retros go to agents/retros. The 0.9 branch
#   (agentes/retros) is still read, never rewritten or deleted, so the history is not lost.
# - retros_tip <branch>: the commit of a retros branch (the remote one if it exists; otherwise the local one).
# - normalize_legacy_names: the 0.9 (Spanish) keys and values of the retro frontmatter become the new
#   ones, so old and new retros count as the same group when they are read or saved.
#   Usage: normalize_legacy_names < text   (only rewrites the frontmatter, the first block between --- lines)
# shellcheck disable=SC2034  # used by the scripts that source this file
RETROS_BRANCH=agents/retros
# shellcheck disable=SC2034
RETROS_LEGACY_BRANCH=agentes/retros

retros_tip() {
  local b=$1
  if git remote get-url origin >/dev/null 2>&1; then
    git fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" 2>/dev/null || true
    git rev-parse -q --verify "refs/remotes/origin/$b" && return 0
  fi
  git rev-parse -q --verify "refs/heads/$b" || true
}

normalize_legacy_names() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
    BEGIN {
      split("modelo:model rol:role agente_sha:agent_sha rutas:paths fecha:date corrida:run", k, " ")
      for (i in k) { split(k[i], kv, ":"); K[kv[1]] = kv[2] }
      split("skill:orquestar=orchestrate skill:mejorar-skills=improve-skills " \
            "role:implementador-liviano=implementer-light role:implementador=implementer role:revisor=reviewer " \
            "role:orquestador=orchestrator role:sesion=session model:desconocido=unknown agent_sha:desconocido=unknown " \
            "pr:sin_PR=no_PR issue:sin_issue=no_issue area:ninguna=none", v, " ")
      for (i in v) { split(v[i], vv, "="); V[vv[1]] = vv[2] }
    }
    NR == 1 && $0 ~ /^---\r?$/ { fm = 1; print; next }
    fm && $0 ~ /^---\r?$/ { fm = 0; print; next }
    fm && match($0, /^[a-z_]+:/) {
      key = substr($0, 1, RLENGTH - 1); val = trim(substr($0, RLENGTH + 1))
      nk = (key in K) ? K[key] : key
      vk = val; gsub(/ /, "_", vk); vk = nk ":" vk
      nv = val
      if (vk in V) { nv = V[vk]; gsub(/_/, " ", nv) }
      if (nk != key || nv != val) { print nk ":" (nv == "" ? "" : " " nv); next }
    }
    { print }
  '
}
